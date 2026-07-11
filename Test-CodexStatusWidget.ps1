$ErrorActionPreference = 'Stop'
$widget = Join-Path $PSScriptRoot 'CodexStatusWidget.ps1'
$root = Join-Path $env:TEMP ('codex-widget-tests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$now = [datetime]::UtcNow
function Ts([int]$seconds) { return $now.AddSeconds($seconds).ToString('o') }

function Write-EventFile([string]$name, [object[]]$events) {
    $path = Join-Path $root ($name + '.jsonl')
    $events | ForEach-Object { $_ | ConvertTo-Json -Depth 12 -Compress } | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Event([string]$time, [string]$outer, [hashtable]$payload) {
    return [ordered]@{ timestamp=$time; type=$outer; payload=$payload }
}

function SessionMeta([string]$source, [string]$parent, [string]$time) {
    return Event $time 'session_meta' ([ordered]@{
        id=[guid]::NewGuid().ToString(); thread_source=$source; parent_thread_id=$parent
        source=$(if ($source -eq 'subagent') {[ordered]@{subagent=[ordered]@{other='guardian'}}} else {'user'})
    })
}

function Message([string]$turn, [string]$role, [string]$phase, [string]$text, [string]$time) {
    return Event $time 'response_item' ([ordered]@{
        type='message'; role=$role; phase=$phase
        content=@([ordered]@{type='output_text';text=$text})
        internal_chat_message_metadata_passthrough=[ordered]@{turn_id=$turn}
    })
}

function Probe-State {
    $json = powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $widget -Probe -SessionsRoot $root
    return ($json | ConvertFrom-Json)
}

function Assert-State([string]$expected, [string]$label) {
    $actual = (Probe-State).State
    if ($actual -ne $expected) { throw "$label expected=$expected actual=$actual" }
    Write-Host "PASS $label -> $actual"
}

function Assert-Lamps([string[]]$expected, [string]$label) {
    $actual = @((Probe-State).Lamps)
    if (($actual -join ',') -ne ($expected -join ',')) { throw "$label expected=$($expected -join ',') actual=$($actual -join ',')" }
    Write-Host "PASS $label -> $($actual -join ',')"
}

try {
    $t1='turn-normal'
    Write-EventFile '01-normal' @(
        (Event (Ts 0) 'turn_context' ([ordered]@{turn_id=$t1})),
        (Event (Ts 1) 'event_msg' ([ordered]@{type='task_started';turn_id=$t1})),
        (Message $t1 'assistant' 'final_answer' 'Completed.' (Ts 2)),
        (Event (Ts 3) 'event_msg' ([ordered]@{type='task_complete';turn_id=$t1}))
    ) | Out-Null
    Assert-State 'idle' 'normal completion'

    Remove-Item (Join-Path $root '*.jsonl')
    $t2='turn-plan'
    Write-EventFile '02-plan' @(
        (Event (Ts 10) 'turn_context' ([ordered]@{turn_id=$t2})),
        (Message $t2 'assistant' 'final_answer' '<proposed_plan>Plan</proposed_plan>' (Ts 11)),
        (Event (Ts 12) 'event_msg' ([ordered]@{type='task_complete';turn_id=$t2}))
    ) | Out-Null
    Assert-State 'action' 'plan review'

    Remove-Item (Join-Path $root '*.jsonl')
    $t2tag='turn-tag-explanation'
    Write-EventFile '02-tag-explanation' @(
        (Event (Ts 12) 'turn_context' ([ordered]@{turn_id=$t2tag})),
        (Message $t2tag 'assistant' 'final_answer' 'The literal <proposed_plan> tag is used for review requests.' (Ts 13)),
        (Event (Ts 14) 'event_msg' ([ordered]@{type='task_complete';turn_id=$t2tag}))
    ) | Out-Null
    Assert-State 'idle' 'literal proposal tag mention does not request review'

    Remove-Item (Join-Path $root '*.jsonl')
    $t2b='turn-plan-question'
    Write-EventFile '02b-plan-question' @(
        (Event (Ts 13) 'turn_context' ([ordered]@{turn_id=$t2b;collaboration_mode=[ordered]@{mode='plan'}})),
        (Message $t2b 'assistant' 'final_answer' 'Please choose how I should modify it.' (Ts 14)),
        (Event (Ts 15) 'event_msg' ([ordered]@{type='task_complete';turn_id=$t2b}))
    ) | Out-Null
    Assert-State 'action' 'plan mode final waits for user'

    Remove-Item (Join-Path $root '*.jsonl')
    $t2d='turn-plan-ordinary'
    Write-EventFile '02d-plan-ordinary' @(
        (Event (Ts 16) 'turn_context' ([ordered]@{turn_id=$t2d;collaboration_mode=[ordered]@{mode='plan'}})),
        (Message $t2d 'assistant' 'final_answer' 'I inspected the repo and found no blocking issue.' (Ts 17)),
        (Event (Ts 18) 'event_msg' ([ordered]@{type='task_complete';turn_id=$t2d}))
    ) | Out-Null
    Assert-State 'idle' 'plan mode ordinary final does not request review'

    Remove-Item (Join-Path $root '*.jsonl')
    $t2e='turn-plan-mentions-plan'
    Write-EventFile '02e-plan-mentions-plan' @(
        (Event (Ts 19) 'turn_context' ([ordered]@{turn_id=$t2e;collaboration_mode=[ordered]@{mode='plan'}})),
        (Message $t2e 'assistant' 'final_answer' 'The plan explains the implementation and its tradeoffs.' (Ts 20)),
        (Event (Ts 21) 'event_msg' ([ordered]@{type='task_complete';turn_id=$t2e}))
    ) | Out-Null
    Assert-State 'idle' 'plan mode mentioning plan does not request review'

    Remove-Item (Join-Path $root '*.jsonl')
    $t2c='turn-plan-input'
    Write-EventFile '02c-plan-input' @(
        (Event (Ts 16) 'turn_context' ([ordered]@{turn_id=$t2c;collaboration_mode=[ordered]@{mode='plan'}})),
        (Event (Ts 17) 'response_item' ([ordered]@{
            type='function_call';name='request_user_input';call_id='input-1';arguments='{}'
            internal_chat_message_metadata_passthrough=[ordered]@{turn_id=$t2c}
        }))
    ) | Out-Null
    Assert-State 'action' 'plan mode function input request'

    Remove-Item (Join-Path $root '*.jsonl')
    $t3='turn-running'
    Write-EventFile '03-running' @(
        (Event (Ts 20) 'turn_context' ([ordered]@{turn_id=$t3})),
        (Event (Ts 21) 'event_msg' ([ordered]@{type='task_started';turn_id=$t3}))
    ) | Out-Null
    Assert-State 'running' 'active turn'

    Remove-Item (Join-Path $root '*.jsonl')
    $t4='turn-approval'
    Write-EventFile '04-approval' @(
        (Event (Ts 30) 'turn_context' ([ordered]@{turn_id=$t4})),
        (Event (Ts 31) 'response_item' ([ordered]@{
            type='custom_tool_call';name='exec';call_id='approval-1';input='{"sandbox_permissions":"require_escalated"}'
            internal_chat_message_metadata_passthrough=[ordered]@{turn_id=$t4}
        }))
    ) | Out-Null
    Assert-State 'action' 'approval request'

    Remove-Item (Join-Path $root '*.jsonl')
    $t5='turn-question'
    Write-EventFile '05-question' @(
        (Event (Ts 40) 'turn_context' ([ordered]@{turn_id=$t5})),
        (Message $t5 'assistant' 'final_answer' 'Which option do you prefer?' (Ts 41)),
        (Event (Ts 42) 'event_msg' ([ordered]@{type='task_complete';turn_id=$t5}))
    ) | Out-Null
    Assert-State 'action' 'explicit question'

    Remove-Item (Join-Path $root '*.jsonl')
    $old='turn-old-plan'; $new='turn-user-reply'
    Write-EventFile '06-user-clears-review' @(
        (Event (Ts 50) 'turn_context' ([ordered]@{turn_id=$old})),
        (Message $old 'assistant' 'final_answer' '<proposed_plan>Plan</proposed_plan>' (Ts 51)),
        (Event (Ts 52) 'event_msg' ([ordered]@{type='task_complete';turn_id=$old})),
        (Event (Ts 53) 'turn_context' ([ordered]@{turn_id=$new})),
        (Message $new 'user' $null 'Implement it.' (Ts 54)),
        (Event (Ts 55) 'event_msg' ([ordered]@{type='task_started';turn_id=$new}))
    ) | Out-Null
    Assert-State 'running' 'user reply clears review'

    Remove-Item (Join-Path $root '*.jsonl')
    Write-EventFile '07-review' @(
        (Event (Ts 60) 'turn_context' ([ordered]@{turn_id='turn-review'})),
        (Message 'turn-review' 'assistant' 'final_answer' '<proposed_plan>Plan</proposed_plan>' (Ts 61)),
        (Event (Ts 62) 'event_msg' ([ordered]@{type='task_complete';turn_id='turn-review'}))
    ) | Out-Null
    Write-EventFile '08-running' @(
        (Event (Ts 63) 'turn_context' ([ordered]@{turn_id='turn-parallel'})),
        (Event (Ts 64) 'event_msg' ([ordered]@{type='task_started';turn_id='turn-parallel'}))
    ) | Out-Null
    Assert-State 'action' 'parallel review and running conversations'
    Assert-Lamps @('action','running') 'parallel review and running lamps'

    Remove-Item (Join-Path $root '*.jsonl')
    $staleTime=$now.AddMinutes(-10).ToString('o')
    Write-EventFile '09-stale-start' @(
        (Event $staleTime 'turn_context' ([ordered]@{turn_id='turn-stale'})),
        (Event $staleTime 'event_msg' ([ordered]@{type='task_started';turn_id='turn-stale'}))
    ) | Out-Null
    Assert-State 'idle' 'stale dangling turn expires'

    Remove-Item (Join-Path $root '*.jsonl')
    Write-EventFile '10-long-tool' @(
        (Event $staleTime 'turn_context' ([ordered]@{turn_id='turn-long-tool'})),
        (Event $staleTime 'response_item' ([ordered]@{
            type='custom_tool_call';name='exec';call_id='long-tool-1';input='{}'
            internal_chat_message_metadata_passthrough=[ordered]@{turn_id='turn-long-tool'}
        }))
    ) | Out-Null
    Assert-State 'running' 'long unresolved tool remains active'

    Remove-Item (Join-Path $root '*.jsonl')
    Write-EventFile '10b-ordinary-patch' @(
        (Event ([datetime]::UtcNow.ToString('o')) 'turn_context' ([ordered]@{turn_id='ordinary-patch'})),
        (Event ([datetime]::UtcNow.ToString('o')) 'response_item' ([ordered]@{
            type='custom_tool_call';name='apply_patch';call_id='patch-1';input='*** Begin Patch'
            internal_chat_message_metadata_passthrough=[ordered]@{turn_id='ordinary-patch'}
        }))
    ) | Out-Null
    Assert-State 'running' 'ordinary patch does not request review'

    Remove-Item (Join-Path $root '*.jsonl')
    Write-EventFile '10c-user-running' @(
        (SessionMeta 'user' $null ([datetime]::UtcNow.ToString('o'))),
        (Event ([datetime]::UtcNow.ToString('o')) 'turn_context' ([ordered]@{turn_id='user-running'})),
        (Event ([datetime]::UtcNow.ToString('o')) 'event_msg' ([ordered]@{type='task_started';turn_id='user-running'}))
    ) | Out-Null
    Write-EventFile '10d-guardian-complete' @(
        (SessionMeta 'subagent' 'user-running' ([datetime]::UtcNow.ToString('o'))),
        (Event ([datetime]::UtcNow.ToString('o')) 'turn_context' ([ordered]@{turn_id='guardian-turn'})),
        (Event ([datetime]::UtcNow.ToString('o')) 'event_msg' ([ordered]@{type='task_complete';turn_id='guardian-turn'}))
    ) | Out-Null
    Assert-Lamps @('running') 'guardian completion does not add a white lamp'

    Remove-Item (Join-Path $root '*.jsonl')
    Write-EventFile '11-parallel-running' @(
        (Event ([datetime]::UtcNow.ToString('o')) 'turn_context' ([ordered]@{turn_id='parallel-running'})),
        (Event ([datetime]::UtcNow.ToString('o')) 'event_msg' ([ordered]@{type='task_started';turn_id='parallel-running'}))
    ) | Out-Null
    Write-EventFile '12-just-completed' @(
        (Event ([datetime]::UtcNow.ToString('o')) 'turn_context' ([ordered]@{turn_id='just-completed'})),
        (Event ([datetime]::UtcNow.ToString('o')) 'event_msg' ([ordered]@{type='task_complete';turn_id='just-completed'}))
    ) | Out-Null
    Assert-Lamps @('running','idle') 'parallel conversation lamps'

    Remove-Item (Join-Path $root '*.jsonl')
    $expired=$now.AddSeconds(-8).ToString('o')
    Write-EventFile '13-expired-completion' @(
        (Event $expired 'turn_context' ([ordered]@{turn_id='expired-completion'})),
        (Event $expired 'event_msg' ([ordered]@{type='task_complete';turn_id='expired-completion'}))
    ) | Out-Null
    Assert-Lamps @('idle') 'completed lamp disappears after five seconds'

    Remove-Item (Join-Path $root '*.jsonl')
    $pastReset=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToUnixTimeSeconds()
    Write-EventFile '14-expired-rate-window' @(
        (Event ([datetime]::UtcNow.ToString('o')) 'event_msg' ([ordered]@{
            type='token_count'; rate_limits=[ordered]@{
                primary=[ordered]@{used_percent=100;window_minutes=300;resets_at=$pastReset}
                secondary=[ordered]@{used_percent=50;window_minutes=10080;resets_at=[DateTimeOffset]::UtcNow.AddDays(3).ToUnixTimeSeconds()}
            }
        }))
    ) | Out-Null
    $expiredRate = Probe-State
    if ($expiredRate.Five -ne 100 -or $null -ne $expiredRate.FiveReset) { throw 'expired quota window must show 100% with no stale reset time' }
    Write-Host 'PASS expired quota window clears stale reset time'

    Remove-Item (Join-Path $root '*.jsonl')
    $newReset=[DateTimeOffset]::UtcNow.AddHours(5).ToUnixTimeSeconds()
    Write-EventFile '15-new-rate-window' @(
        (Event ([datetime]::UtcNow.ToString('o')) 'event_msg' ([ordered]@{
            type='token_count'; rate_limits=[ordered]@{
                primary=[ordered]@{used_percent=0;window_minutes=300;resets_at=$newReset}
                secondary=[ordered]@{used_percent=50;window_minutes=10080;resets_at=[DateTimeOffset]::UtcNow.AddDays(3).ToUnixTimeSeconds()}
            }
        }))
    ) | Out-Null
    $newRate = Probe-State
    if ($newRate.Five -ne 100 -or $null -eq $newRate.FiveReset) { throw 'new quota window must retain its new reset time' }
    Write-Host 'PASS new 100% quota window uses new reset time'

    Write-Host 'All state-machine tests passed.'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
