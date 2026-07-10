$ErrorActionPreference = 'Stop'

$widget = Join-Path $PSScriptRoot 'CodexStatusWidget.ps1'
$sessions = Join-Path $env:TEMP ('codex-lamp-case-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $sessions)

function Write-Events([string]$name, [object[]]$events) {
    $path = Join-Path $sessions ($name + '.jsonl')
    $events | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress } |
        Set-Content -LiteralPath $path -Encoding UTF8
}

function New-Event([string]$type, [string]$turnId, [datetime]$time) {
    [ordered]@{
        timestamp = $time.ToUniversalTime().ToString('o')
        type = 'event_msg'
        payload = [ordered]@{ type = $type; turn_id = $turnId }
    }
}

function Get-Lamps {
    $json = powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $widget -Probe -SessionsRoot $sessions
    return @(($json | ConvertFrom-Json).Lamps)
}

function Assert-Lamps([string]$step, [string[]]$expected) {
    $actual = @(Get-Lamps)
    if (($actual -join ',') -ne ($expected -join ',')) {
        throw "$step failed: expected [$($expected -join ', ')], got [$($actual -join ', ')]"
    }
    Write-Host "PASS $step : $($actual -join ' + ')"
}

try {
    $now = Get-Date
    Write-Events 'conversation-a' @((New-Event 'task_started' 'turn-a' $now))
    Write-Events 'conversation-b' @((New-Event 'task_started' 'turn-b' $now))
    Assert-Lamps 'two conversations running' @('running', 'running')

    Write-Events 'conversation-b' @(
        (New-Event 'task_started' 'turn-b' $now),
        (New-Event 'task_complete' 'turn-b' (Get-Date))
    )
    Assert-Lamps 'one conversation just completed' @('running', 'idle')

    Write-Host 'Waiting 6 seconds for the white completion lamp to disappear...'
    Start-Sleep -Seconds 6
    Assert-Lamps 'completion grace period elapsed' @('running')

    $finishedEarlier = (Get-Date).AddSeconds(-6)
    Write-Events 'conversation-a' @(
        (New-Event 'task_started' 'turn-a' $now),
        (New-Event 'task_complete' 'turn-a' $finishedEarlier)
    )
    Assert-Lamps 'all conversations idle' @('idle')

    Write-Host 'Small multi-conversation lamp test passed.' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $sessions -Recurse -Force -ErrorAction SilentlyContinue
}
