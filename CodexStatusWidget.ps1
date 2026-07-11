param([switch]$Probe, [string]$SessionsRoot)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CodexWidgetMemory {
    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr process);
}
'@

# Keep exactly one widget instance. This also prevents an old shortcut launch
# from leaving several differently-colored widgets stacked on the desktop.
$instanceMutex = $null
if (!$Probe) {
    $createdNew = $false
    $instanceMutex = [Threading.Mutex]::new($true, 'Local\CodexStatusWidget_9C9A89F2', [ref]$createdNew)
    if (!$createdNew) { exit 0 }
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Codex Status" Width="321" Height="50" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" ResizeMode="NoResize">
  <Border CornerRadius="14" Background="#F2191C23" BorderBrush="#4D667080" BorderThickness="1" Padding="7,6">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="25"/><ColumnDefinition Width="6"/><ColumnDefinition Width="88"/><ColumnDefinition Width="6"/><ColumnDefinition Width="88"/><ColumnDefinition Width="6"/><ColumnDefinition Width="88"/>
      </Grid.ColumnDefinitions>

      <StackPanel x:Name="LampsPanel" Grid.Column="0" Orientation="Horizontal"
                  HorizontalAlignment="Center" VerticalAlignment="Center"/>

      <Border Grid.Column="2" CornerRadius="8" Background="#CC232730" BorderBrush="#303E4653" BorderThickness="1" Padding="6,3">
        <Grid HorizontalAlignment="Center">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock Text="5h" Foreground="#B9C0CB" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
          <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="12,0,0,0">
            <TextBlock x:Name="FiveText" Text="--%" Foreground="#F4F6F8" FontSize="11" FontWeight="SemiBold" TextAlignment="Right"/>
            <TextBlock x:Name="FiveResetText" Text="--:--" Foreground="#AEB6C2" FontSize="10" TextAlignment="Right" Margin="0,-1,0,0"/>
          </StackPanel>
        </Grid>
      </Border>

      <Border Grid.Column="4" CornerRadius="8" Background="#CC232730" BorderBrush="#303E4653" BorderThickness="1" Padding="6,3">
        <Grid HorizontalAlignment="Center">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock Text="&#21608;" Foreground="#B9C0CB" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
          <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="12,0,0,0">
            <TextBlock x:Name="WeekText" Text="--%" Foreground="#F4F6F8" FontSize="11" FontWeight="SemiBold" TextAlignment="Right"/>
            <TextBlock x:Name="WeekResetText" Text="--" Foreground="#AEB6C2" FontSize="10" TextAlignment="Right" Margin="0,-1,0,0"/>
          </StackPanel>
        </Grid>
      </Border>

      <Border Grid.Column="6" CornerRadius="8" Background="#CC232730" BorderBrush="#303E4653" BorderThickness="1" Padding="6,3">
        <Grid VerticalAlignment="Center" HorizontalAlignment="Center">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock x:Name="ResetCountText" Grid.Column="0" Text="--" Foreground="#F4F6F8" FontSize="14" FontWeight="SemiBold"
                     TextAlignment="Center" VerticalAlignment="Center"/>
          <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="12,0,0,0">
            <TextBlock x:Name="ResetExpiryText1" Text="--" Foreground="#F4F6F8" FontSize="11" FontWeight="SemiBold" TextAlignment="Right"/>
            <TextBlock x:Name="ResetExpiryText2" Text="" Foreground="#AEB6C2" FontSize="10" TextAlignment="Right" Margin="0,-1,0,0"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>
  </Border>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$lampsPanel = $window.FindName('LampsPanel')
$fiveText = $window.FindName('FiveText'); $weekText = $window.FindName('WeekText')
$fiveResetText = $window.FindName('FiveResetText'); $weekResetText = $window.FindName('WeekResetText')
$resetCountText = $window.FindName('ResetCountText')
$resetExpiryText1 = $window.FindName('ResetExpiryText1'); $resetExpiryText2 = $window.FindName('ResetExpiryText2')

function New-Brush([string]$color) {
    return [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString($color))
}

function Format-ResetExpiry([object]$value) {
    if (!$value) { return '--' }
    try {
        $date = [datetime]$value
        return $date.Month.ToString() + '/' + $date.Day.ToString()
    } catch {
        return '--'
    }
}

function Set-Lamps([object[]]$states) {
    $colors = @{ idle='#FFF4D6'; running='#F05252'; action='#4BA3FF'; offline='#77808D' }
    if (!$states -or $states.Count -eq 0) { $states = @('idle') }
    $signature = @($states | ForEach-Object { [string]$_ }) -join '|'
    if ($signature -eq $script:lastLampSignature) { return }
    $script:lastLampSignature = $signature
    $lampsPanel.Children.Clear()
    $dotSize = [Math]::Min(12.0, [Math]::Max(3.0, (24.0 / [Math]::Max(1, $states.Count)) - 1.0))
    foreach ($state in $states) {
        $color = if ($colors.ContainsKey([string]$state)) { $colors[[string]$state] } else { $colors.offline }
        $holder = [Windows.Controls.Grid]::new()
        $holder.Width = $dotSize + 1; $holder.Height = $dotSize + 1
        $holder.Margin = [Windows.Thickness]::new(0,0,0,0)
        $glow = [Windows.Shapes.Ellipse]::new()
        $glow.Width = $dotSize + 1; $glow.Height = $dotSize + 1
        $glow.HorizontalAlignment = 'Center'; $glow.VerticalAlignment = 'Center'
        $glow.Fill = New-Brush $color; $glow.Opacity = if ($state -eq 'offline') { 0.15 } else { 0.25 }
        $lamp = [Windows.Shapes.Ellipse]::new()
        $lamp.Width = $dotSize; $lamp.Height = $dotSize
        $lamp.HorizontalAlignment = 'Center'; $lamp.VerticalAlignment = 'Center'
        $lamp.Fill = New-Brush $color; $lamp.Stroke = New-Brush '#BFFFFFFF'; $lamp.StrokeThickness = 0.8
        [void]$holder.Children.Add($glow); [void]$holder.Children.Add($lamp)
        [void]$lampsPanel.Children.Add($holder)
    }
}

function Get-RecentSessionFiles {
    $root = if ($SessionsRoot) { $SessionsRoot } else { Join-Path $env:USERPROFILE '.codex\sessions' }
    if (!(Test-Path $root)) { return @() }
    return @(Get-ChildItem $root -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 12)
}

function Get-ReviewReason([string]$text, [bool]$isPlanMode = $false) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    # Match an actual proposal block, not an explanatory sentence that merely
    # mentions the literal tag name.
    if ($text -match '(?s)<proposed_plan>.+?</proposed_plan>') { return 'plan_review' }
    $tail = $text.Trim()
    if ($tail.Length -gt 320) { $tail = $tail.Substring($tail.Length - 320) }
    if ($tail -match '[?\uFF1F]\s*$') { return 'explicit_question' }
    # A word such as “方案”, “选择”, or “计划” in an ordinary answer is not a
    # request for the user to act.  Only recognise an imperative, a direct
    # yes/no prompt, or an explicit wait-for-confirmation phrase.
    if ($tail -match '\u8BF7\s*(\u9009\u62E9|\u786E\u8BA4|\u544A\u8BC9\u6211|\u56DE\u590D)|\u662F\u5426\s*(\u540C\u610F|\u5141\u8BB8|\u7EE7\u7EED|\u786E\u8BA4)|\u7B49\u5F85.*\u786E\u8BA4|\u5F85.*\u786E\u8BA4|\u9700\u8981\u60A8.*\u786E\u8BA4|\u8BF7\u6307\u793A|\u8BF7\u51B3\u5B9A|\u8BF7\u9009\u5B9A|\b(please\s+)?(choose|confirm|approve|proceed)\b|\bwhich\s+(option|approach)\b') { return 'explicit_choice' }
    if ($isPlanMode -and $tail -match '(\u5982\u4F55|\u600E\u4E48).{0,12}\u4FEE\u6539|\u4FEE\u6539.{0,12}(\u5982\u4F55|\u600E\u4E48)|\u65B9\u6848.{0,16}(\u8BF7\u786E\u8BA4|\u5F85\u786E\u8BA4|\u7B49\u5F85|\u662F\u5426)|\u8BA1\u5212.{0,16}(\u8BF7\u786E\u8BA4|\u5F85\u786E\u8BA4|\u7B49\u5F85|\u662F\u5426)|how\s+.*modify|choose\s+how|plan\s+.*(confirm|wait)') { return 'plan_mode_waiting' }
    return $null
}

function New-TurnState([string]$turnId, [datetime]$when) {
    return @{
        TurnId=$turnId; Status='running'; Updated=$when; LastEvent='turn_started'
        NeedsReview=$false; ReviewReason=$null; Pending=@{}; ActiveTools=@{}; FinalText=''; IsPlanMode=$false
    }
}

function Start-LogStateProbe {
    if ($script:logProbe -and !$script:logProbe.HasExited) { return $true }
    $pythonCandidates = @(
        (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'),
        'python.exe'
    )
    $python = $pythonCandidates | Where-Object { $_ -eq 'python.exe' -or (Test-Path $_) } | Select-Object -First 1
    $probeScript = Join-Path $PSScriptRoot 'CodexLogStateProbe.py'
    if (!$python -or !(Test-Path $probeScript)) { return $false }
    try {
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = $python
        $info.Arguments = '"' + $probeScript + '"'
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.StandardOutputEncoding = [Text.Encoding]::UTF8
        $script:logProbe = [Diagnostics.Process]::new()
        $script:logProbe.StartInfo = $info
        return $script:logProbe.Start()
    } catch {
        $script:logProbe = $null
        return $false
    }
}

function Stop-LogStateProbe {
    if (!$script:logProbe) { return }
    try { if (!$script:logProbe.HasExited) { $script:logProbe.Kill() } } catch {}
    try { $script:logProbe.Dispose() } catch {}
    $script:logProbe = $null
}

function Get-LogCompletionMap([object[]]$sessions) {
    $result = @{}
    $turns = @($sessions | Where-Object { ($_.Status -eq 'running' -or $_.IsPlanMode) -and $_.ThreadId -and $_.TurnId } |
        ForEach-Object { @{ threadId=$_.ThreadId; turnId=$_.TurnId } })
    if ($turns.Count -eq 0) {
        Stop-LogStateProbe
        return $result
    }
    if (!(Start-LogStateProbe)) { return $result }
    try {
        $request = @{ turns=$turns } | ConvertTo-Json -Depth 4 -Compress
        $script:logProbe.StandardInput.WriteLine($request)
        $script:logProbe.StandardInput.Flush()
        $line = $script:logProbe.StandardOutput.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) { return $result }
        $response = $line | ConvertFrom-Json -ErrorAction Stop
        foreach ($property in $response.results.PSObject.Properties) {
            $result[$property.Name] = $property.Value
        }
    } catch {
        Stop-LogStateProbe
    }
    return $result
}

function Get-CodexAuthHeaders {
    $authPath = Join-Path $env:USERPROFILE '.codex\auth.json'
    if (!(Test-Path $authPath)) { return $null }
    try {
        $auth = Get-Content -LiteralPath $authPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (!$auth.tokens.access_token -or !$auth.tokens.account_id) { return $null }
        return @{
            Authorization = 'Bearer ' + [string]$auth.tokens.access_token
            'ChatGPT-Account-ID' = [string]$auth.tokens.account_id
            'OAI-Language' = 'zh-CN'
            originator = 'Codex Desktop'
        }
    } catch {
        return $null
    }
}

function ConvertTo-UnixResetTime([object]$value) {
    if ($null -eq $value) { return $null }
    try { return [long]$value } catch {}
    try { return [DateTimeOffset]::Parse([string]$value).ToUnixTimeSeconds() } catch { return $null }
}

function Get-CodexUsageRateLimits {
    $headers = Get-CodexAuthHeaders
    if ($null -eq $headers) { return $null }
    try {
        $response = Invoke-RestMethod -Uri 'https://chatgpt.com/backend-api/wham/usage' `
            -Headers $headers -Method Get -TimeoutSec 8 -ErrorAction Stop
        if ($null -eq $response.rate_limit) { return $null }

        $result = @{}
        if ($null -ne $response.rate_limit.primary_window) {
            $window = $response.rate_limit.primary_window
            $result.primary = @{
                used_percent = [double]$window.used_percent
                resets_at = ConvertTo-UnixResetTime $window.reset_at
            }
        }
        if ($null -ne $response.rate_limit.secondary_window) {
            $window = $response.rate_limit.secondary_window
            $result.secondary = @{
                used_percent = [double]$window.used_percent
                resets_at = ConvertTo-UnixResetTime $window.reset_at
            }
        }
        if ($result.Count -eq 0) { return $null }
        return $result
    } catch {
        return $null
    }
}

function Get-RateLimitResetCredits {
    $headers = Get-CodexAuthHeaders
    if ($null -eq $headers) { return $null }
    try {
        $response = Invoke-RestMethod -Uri 'https://chatgpt.com/backend-api/wham/rate-limit-reset-credits' `
            -Headers $headers -Method Get -TimeoutSec 8 -ErrorAction Stop
        if ($null -eq $response.available_count) { return $null }
        $availableExpiries = [System.Collections.Generic.List[datetime]]::new()
        foreach ($credit in @($response.credits)) {
            if ($credit.status -ne 'available' -or [string]::IsNullOrWhiteSpace([string]$credit.expires_at)) { continue }
            try {
                $availableExpiries.Add([DateTimeOffset]::Parse([string]$credit.expires_at).LocalDateTime)
            } catch {}
        }
        $expiresAtList = @($availableExpiries.ToArray())
        [array]::Sort($expiresAtList)
        if ($expiresAtList.Count -gt 2) {
            $expiresAtList = @($expiresAtList[0..1])
        }
        return [pscustomobject]@{
            Count = [int]$response.available_count
            ExpiresAtList = $expiresAtList
        }
    } catch {
        return $null
    }
}

function Get-CodexSnapshot {
    $files = @(Get-RecentSessionFiles)
    $noSessionFiles = $files.Count -eq 0

    $latestRate = $script:liveRate
    $diagnostics = @()
    $sessionStates = @()

    foreach ($file in $files) {
        $turns = @{}
        $currentTurnId = $null
        $threadId = $null
        $isTopLevelConversation = $true
        $isPlanMode = $false
        try {
            $meta = Get-Content -LiteralPath $file.FullName -TotalCount 1 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $threadId = [string]$(if ($meta.payload.id) { $meta.payload.id } else { $meta.payload.session_id })
            $hasParentThread = ![string]::IsNullOrWhiteSpace([string]$meta.payload.parent_thread_id)
            $hasSubagentSource = $meta.payload.source -is [pscustomobject] -and $null -ne $meta.payload.source.subagent
            if ($meta.type -eq 'session_meta' -and
                ($meta.payload.thread_source -eq 'subagent' -or $hasParentThread -or $hasSubagentSource)) {
                $isTopLevelConversation = $false
            }
        } catch {}
        try {
            foreach ($headLine in @(Get-Content -LiteralPath $file.FullName -TotalCount 80 -ErrorAction Stop)) {
                try { $headItem = $headLine | ConvertFrom-Json -ErrorAction Stop } catch { continue }
                if ($headItem.type -eq 'event_msg' -and $headItem.payload.type -eq 'thread_settings_applied' -and $headItem.payload.thread_settings.collaboration_mode.mode) {
                    $isPlanMode = ([string]$headItem.payload.thread_settings.collaboration_mode.mode -eq 'plan')
                }
                if ($headItem.type -eq 'turn_context' -and $headItem.payload.collaboration_mode.mode) {
                    $isPlanMode = ([string]$headItem.payload.collaboration_mode.mode -eq 'plan')
                }
            }
        } catch {}
        # Recent structured events are sufficient to reconstruct the latest
        # turn. Keeping a smaller tail substantially reduces transient string
        # allocations when several long conversations exist.
        $lines = @(Get-Content -LiteralPath $file.FullName -Tail 600 -ErrorAction SilentlyContinue)

        foreach ($line in $lines) {
            try { $item = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            try { $when = [datetime]::Parse($item.timestamp).ToLocalTime() } catch { $when = $file.LastWriteTime }

            if ($item.type -eq 'event_msg' -and $item.payload.type -eq 'thread_settings_applied' -and $item.payload.thread_settings.collaboration_mode.mode) {
                $isPlanMode = ([string]$item.payload.thread_settings.collaboration_mode.mode -eq 'plan')
            }
            if ($item.type -eq 'turn_context' -and $item.payload.collaboration_mode.mode) {
                $isPlanMode = ([string]$item.payload.collaboration_mode.mode -eq 'plan')
            }

            if ($item.type -eq 'event_msg' -and $item.payload.type -eq 'token_count' -and $item.payload.rate_limits) {
                if (!$latestRate -or $when -gt $latestRate.When) { $latestRate = @{ When=$when; Data=$item.payload.rate_limits } }
            }

            $eventTurnId = $null
            if ($item.type -eq 'turn_context') { $eventTurnId = [string]$item.payload.turn_id }
            elseif ($item.payload.turn_id) { $eventTurnId = [string]$item.payload.turn_id }
            elseif ($item.payload.internal_chat_message_metadata_passthrough.turn_id) {
                $eventTurnId = [string]$item.payload.internal_chat_message_metadata_passthrough.turn_id
            }
            if (!$eventTurnId) { $eventTurnId = $currentTurnId }

            if ($item.type -eq 'turn_context' -or ($item.type -eq 'event_msg' -and $item.payload.type -eq 'task_started')) {
                if (!$eventTurnId) { continue }
                $currentTurnId = $eventTurnId
                foreach ($old in $turns.Values) { $old.NeedsReview=$false; $old.ReviewReason=$null }
                if (!$turns.ContainsKey($eventTurnId)) { $turns[$eventTurnId] = New-TurnState $eventTurnId $when }
                $turns[$eventTurnId].Status='running'; $turns[$eventTurnId].Updated=$when; $turns[$eventTurnId].LastEvent='task_started'
                $turns[$eventTurnId].IsPlanMode=$isPlanMode
                continue
            }

            if (!$eventTurnId) { continue }
            if (!$turns.ContainsKey($eventTurnId)) { $turns[$eventTurnId] = New-TurnState $eventTurnId $when }
            $turn = $turns[$eventTurnId]
            $turn.IsPlanMode = $isPlanMode

            if ($item.type -eq 'response_item' -and $item.payload.type -eq 'message' -and $item.payload.role -eq 'user') {
                foreach ($old in $turns.Values) { $old.NeedsReview=$false; $old.ReviewReason=$null }
                $turn.Status='running'; $turn.LastEvent='user_message'; $turn.Updated=$when
                continue
            }

            if ($item.type -eq 'response_item' -and $item.payload.type -eq 'message' -and
                $item.payload.role -eq 'assistant' -and $item.payload.phase -in @('final','final_answer')) {
                $text = (($item.payload.content | ForEach-Object { [string]$_.text }) -join '')
                $turn.FinalText = $text
                $reason = Get-ReviewReason $text ([bool]$turn.IsPlanMode)
                if ($reason) { $turn.NeedsReview=$true; $turn.ReviewReason=$reason }
                $turn.LastEvent='final_answer'; $turn.Updated=$when
                continue
            }

            if ($item.type -eq 'response_item' -and $item.payload.type -in @('custom_tool_call','function_call')) {
                $callId = [string]$item.payload.call_id
                $raw = [string]$item.payload.input
                $actualEscalation = $raw -match 'sandbox_permissions\\?["'']?\s*:\s*\\?["'']require_escalated'
                $isInputRequest = [string]$item.payload.name -eq 'request_user_input'
                if ($callId -and ($actualEscalation -or $isInputRequest)) {
                    $reason = if ($isInputRequest) { 'user_input' } else { 'approval' }
                    $turn.Pending[$callId] = $reason
                    $turn.NeedsReview=$true; $turn.ReviewReason=$reason
                }
                if ($callId) { $turn.ActiveTools[$callId] = $when }
                $turn.LastEvent='tool_call'; $turn.Updated=$when
                continue
            }

            if ($item.type -eq 'response_item' -and $item.payload.type -in @('custom_tool_call_output','function_call_output')) {
                $callId = [string]$item.payload.call_id
                if ($callId -and $turn.Pending.ContainsKey($callId)) { $turn.Pending.Remove($callId) }
                if ($callId -and $turn.ActiveTools.ContainsKey($callId)) { $turn.ActiveTools.Remove($callId) }
                if ($turn.Pending.Count -eq 0 -and $turn.ReviewReason -in @('user_input','file_change','approval')) {
                    $turn.NeedsReview=$false; $turn.ReviewReason=$null
                }
                $turn.LastEvent='tool_output'; $turn.Updated=$when
                continue
            }

            if ($item.type -eq 'event_msg' -and $item.payload.type -eq 'task_complete') {
                $turn.Status='completed'; $turn.Pending.Clear(); $turn.ActiveTools.Clear(); $turn.LastEvent='task_complete'; $turn.Updated=$when
                if ($turn.ReviewReason -in @('user_input','file_change','approval')) {
                    $turn.NeedsReview=$false; $turn.ReviewReason=$null
                }
                continue
            }

            if (($item.type -eq 'event_msg' -and $item.payload.type -in @('turn_aborted','task_aborted','error')) -or
                ($item.type -eq 'response_item' -and $item.payload.type -eq 'error')) {
                $turn.Status='stopped'; $turn.Pending.Clear(); $turn.NeedsReview=$false; $turn.ReviewReason=$null
                $turn.ActiveTools.Clear()
                $turn.LastEvent=[string]$item.payload.type; $turn.Updated=$when
                continue
            }

            # Reasoning, token, and other structured events are activity heartbeats.
            $turn.Updated=$when
            $turn.LastEvent=if ($item.payload.type) { [string]$item.payload.type } else { [string]$item.type }
        }

        $latestTurn = @($turns.Values | Sort-Object { $_.Updated } -Descending | Select-Object -First 1)
        if ($isTopLevelConversation -and $latestTurn.Count -gt 0) {
            $t = $latestTurn[0]
            $sessionStates += [pscustomobject]@{
                Path=$file.FullName; TurnId=$t.TurnId; Status=$t.Status; Updated=$t.Updated
                ThreadId=$threadId
                LastEvent=$t.LastEvent; NeedsReview=[bool]$t.NeedsReview; ReviewReason=$t.ReviewReason
                IsPlanMode=[bool]$t.IsPlanMode
                PendingIds=@($t.Pending.Keys); ActiveToolIds=@($t.ActiveTools.Keys)
            }
        }
    }

    # Codex Desktop 26.623 may omit final_answer/task_complete from rollout
    # JSONL even though the completed FinalAnswer is recorded in logs_2.sqlite.
    # Merge that structured completion before building the lamp group.
    $logCompletions = Get-LogCompletionMap $sessionStates
    foreach ($session in $sessionStates) {
        if ($logCompletions.ContainsKey([string]$session.TurnId)) {
            $completion = $logCompletions[[string]$session.TurnId]
            $session.Status = 'completed'
            $session.LastEvent = 'log_final_answer'
            $session.Updated = [DateTimeOffset]::FromUnixTimeSeconds([long]$completion.timestamp).LocalDateTime
            $reason = Get-ReviewReason ([string]$completion.finalText) ([bool]$session.IsPlanMode)
            $session.NeedsReview = [bool]$reason
            $session.ReviewReason = $reason
            $session.ActiveToolIds = @()
            $session.PendingIds = @()
        }
    }

    # Each live top-level conversation owns one lamp. A completed conversation
    # turns milk-white for five seconds, then leaves the group. With no live
    # conversations, the group falls back to one milk-white idle lamp.
    $now = Get-Date
    $completionCutoff = $now.AddSeconds(-5)
    $lampEntries = @()
    # A rollout path is stable for the lifetime of a conversation, so ordering
    # by path prevents lamps from swapping places whenever one emits an event.
    foreach ($current in @($sessionStates | Sort-Object Path)) {
        if ($current.NeedsReview) {
            $lampEntries += [pscustomobject]@{ State='action'; Updated=$current.Updated; Expires=$null }
        } elseif ($current.Status -eq 'running') {
            $activeKey = $current.Path + '|' + $current.TurnId
            $wasObservedActive = $script:observedActiveTurns.ContainsKey($activeKey)
            $startedRecently = $current.Updated -ge $script:widgetStartedAt.AddMinutes(-5)
            if ($wasObservedActive -or $startedRecently -or $current.ActiveToolIds.Count -gt 0) {
                $script:observedActiveTurns[$activeKey] = $true
                $lampEntries += [pscustomobject]@{ State='running'; Updated=$current.Updated; Expires=$null }
            }
        } elseif ($current.Status -in @('completed','stopped') -and $current.Updated -ge $completionCutoff) {
            $activeKey = $current.Path + '|' + $current.TurnId
            if ($script:observedActiveTurns.ContainsKey($activeKey)) { $script:observedActiveTurns.Remove($activeKey) }
            $lampEntries += [pscustomobject]@{ State='idle'; Updated=$current.Updated; Expires=$current.Updated.AddSeconds(5) }
        }
    }
    $lamps = @($lampEntries | ForEach-Object { $_.State })
    if ($noSessionFiles) { $lamps = @('offline') }
    elseif ($lamps.Count -eq 0) { $lamps = @('idle') }
    $nextLampExpiry = @($lampEntries | Where-Object { $_.Expires } | Sort-Object Expires | Select-Object -First 1)
    $state = if ($lamps -contains 'offline') { 'offline' } elseif ($lamps -contains 'action') { 'action' } elseif ($lamps -contains 'running') { 'running' } else { 'idle' }
    $detail = if ($state -eq 'offline') { 'No local sessions found' } elseif ($state -eq 'action') { 'Action needed' } elseif ($state -eq 'running') { 'Working' } else { 'Idle' }

    $five = $null; $week = $null; $fiveReset = $null; $weekReset = $null
    if ($latestRate) {
        if ($latestRate.Data.primary) {
            $five = [math]::Max(0, 100 - [double]$latestRate.Data.primary.used_percent)
            if ($latestRate.Data.primary.resets_at) {
                $fiveReset = [DateTimeOffset]::FromUnixTimeSeconds([long]$latestRate.Data.primary.resets_at).LocalDateTime
                if ($now -ge $fiveReset) { $five = 100; $fiveReset = $null }
            }
        }
        if ($latestRate.Data.secondary) {
            $week = [math]::Max(0, 100 - [double]$latestRate.Data.secondary.used_percent)
            if ($latestRate.Data.secondary.resets_at) {
                $weekReset = [DateTimeOffset]::FromUnixTimeSeconds([long]$latestRate.Data.secondary.resets_at).LocalDateTime
                if ($now -ge $weekReset) { $week = 100; $weekReset = $null }
            }
        }
    }
    foreach ($s in $sessionStates) {
        $diagnostics += [pscustomobject]@{ Path=$s.Path; TurnId=$s.TurnId; LastEvent=$s.LastEvent; Status=$s.Status; NeedsReview=$s.NeedsReview; ReviewReason=$s.ReviewReason; IsPlanMode=$s.IsPlanMode; PendingIds=$s.PendingIds; ActiveToolIds=$s.ActiveToolIds; Updated=$s.Updated }
    }
    return @{ State=$state; Lamps=$lamps; Detail=$detail; Five=$five; Week=$week; FiveReset=$fiveReset; WeekReset=$weekReset; ResetCount=$script:resetCount; ResetExpires=$script:resetExpires; ResetExpiresList=$script:resetExpiresList; RateUpdated=$(if ($latestRate) {$latestRate.When} else {$null}); NextLampExpiry=$(if ($nextLampExpiry.Count) {$nextLampExpiry[0].Expires} else {$null}); Diagnostics=$diagnostics }
}

$script:lastUsageUpdate = [datetime]::MinValue
$script:lastFullScan = [datetime]::MinValue
$script:cachedSnapshot = $null
$script:statusDirty = $true
$script:lastSessionSignature = ''
$script:lastDisplayedRateUpdate = [datetime]::MinValue
$script:lastAccountUsageRefresh = [datetime]::MinValue
$script:lastResetRefresh = [datetime]::MinValue
$script:liveRate = $null
$script:resetCount = $null
$script:resetExpires = $null
$script:resetExpiresList = @()
$script:widgetStartedAt = Get-Date
$script:observedActiveTurns = @{}
$script:logProbe = $null
$script:lastLampSignature = $null
$script:timer = $null
$script:idleSince = $null
$script:lastMemoryCleanup = [datetime]::MinValue
$script:errorLog = Join-Path $PSScriptRoot 'CodexStatusWidget-errors.log'

function Get-SessionSignature {
    $files = @(Get-RecentSessionFiles)
    return (($files | ForEach-Object { $_.FullName + ':' + $_.Length + ':' + $_.LastWriteTimeUtc.Ticks }) -join '|')
}

function Invoke-IdleMemoryCleanup([string]$state, [datetime]$now) {
    if ($state -in @('running','action')) {
        $script:idleSince = $null
        return
    }
    if ($null -eq $script:idleSince) {
        $script:idleSince = $now
        return
    }
    if (($now - $script:idleSince).TotalSeconds -lt 30 -or
        ($now - $script:lastMemoryCleanup).TotalMinutes -lt 10) { return }

    # PowerShell and WPF retain transient scan allocations in the process
    # working set. Reclaim them only during sustained idle periods so active
    # status updates never pay the collection/page-in cost.
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    [GC]::Collect()
    try {
        $process = [Diagnostics.Process]::GetCurrentProcess()
        [void][CodexWidgetMemory]::EmptyWorkingSet($process.Handle)
        $process.Dispose()
    } catch {}
    $script:lastMemoryCleanup = $now
}

function Update-Widget {
    $now = Get-Date
    # Session logs only receive fresh quota events while Codex is active. Poll
    # the account endpoint every five minutes as a quiet-time source so the
    # displayed usage and reset times also advance while all chats are idle.
    if (($now - $script:lastAccountUsageRefresh).TotalSeconds -ge 300) {
        $accountRate = Get-CodexUsageRateLimits
        $script:lastAccountUsageRefresh = $now
        if ($null -ne $accountRate) {
            $script:liveRate = @{ When=$now; Data=$accountRate }
            $script:statusDirty = $true
        }
    }
    $lampExpiryDue = $script:cachedSnapshot -and $script:cachedSnapshot.NextLampExpiry -and $now -ge $script:cachedSnapshot.NextLampExpiry
    if ($script:statusDirty -or !$script:cachedSnapshot -or $lampExpiryDue -or ($now - $script:lastFullScan).TotalSeconds -ge 10) {
        $script:cachedSnapshot = Get-CodexSnapshot
        $script:lastFullScan = $now
        $script:statusDirty = $false
    }
    $s = $script:cachedSnapshot
    Set-Lamps @($s.Lamps)
    $resetRefreshSeconds = if ($s.State -in @('running','action')) { 60 } else { 300 }
    if (($now - $script:lastResetRefresh).TotalSeconds -ge $resetRefreshSeconds) {
        $resetCredits = Get-RateLimitResetCredits
        if ($null -ne $resetCredits) {
            $script:resetCount = $resetCredits.Count
            $script:resetExpiresList = @($resetCredits.ExpiresAtList)
            $script:resetExpires = if ($script:resetExpiresList.Count -gt 0) { $script:resetExpiresList[0] } else { $null }
            $resetCountText.Text = [string]$resetCredits.Count
            if ($script:resetExpiresList.Count -gt 0) {
                $resetExpiryText1.Text = Format-ResetExpiry $script:resetExpiresList[0]
                $resetExpiryText2.Text = if ($script:resetExpiresList.Count -gt 1) { Format-ResetExpiry $script:resetExpiresList[1] } else { '' }
            } else {
                $resetExpiryText1.Text = '--'
                $resetExpiryText2.Text = ''
            }
        }
        $script:lastResetRefresh = $now
    }
    $usageSeconds = if ($s.State -in @('running','action')) { 10 } else { 300 }
    $newRateEvent = $s.RateUpdated -and $s.RateUpdated -gt $script:lastDisplayedRateUpdate
    $refreshUsage = ($now - $script:lastUsageUpdate).TotalSeconds -ge $usageSeconds -or $fiveText.Text -eq '--%' -or $newRateEvent
    if ($refreshUsage -and $null -ne $s.Five) {
        $fiveText.Text=('{0:0}%' -f $s.Five)
        $fiveResetText.Text = if ($s.FiveReset) { $s.FiveReset.ToString('HH:mm') } else { '--:--' }
    }
    if ($refreshUsage -and $null -ne $s.Week) {
        $weekText.Text=('{0:0}%' -f $s.Week)
        if ($s.WeekReset) {
            $weekResetText.Text = $s.WeekReset.Month.ToString() + [char]0x6708 + $s.WeekReset.Day.ToString() + [char]0x65E5
        } else { $weekResetText.Text = '--' }
    }
    if ($refreshUsage) {
        $script:lastUsageUpdate = $now
        if ($s.RateUpdated) { $script:lastDisplayedRateUpdate = $s.RateUpdated }
    }
    if ($script:timer) {
        $pollSeconds = if ($s.State -in @('running','action')) { 2 } else { 5 }
        if ($script:timer.Interval.TotalSeconds -ne $pollSeconds) {
            $script:timer.Interval = [TimeSpan]::FromSeconds($pollSeconds)
        }
    }
    Invoke-IdleMemoryCleanup $s.State $now
}

function Invoke-SafeWidgetUpdate {
    try {
        $signature = Get-SessionSignature
        if ($signature -ne $script:lastSessionSignature) {
            $script:lastSessionSignature = $signature
            $script:statusDirty = $true
        }
        Update-Widget
    } catch {
        $message = (Get-Date).ToString('s') + ' ' + $_.Exception.ToString()
        try { Add-Content -LiteralPath $script:errorLog -Value $message -Encoding UTF8 } catch {}
    }
}

if ($Probe) {
    if (!$SessionsRoot) {
        $accountRate = Get-CodexUsageRateLimits
        if ($null -ne $accountRate) {
            $script:liveRate = @{ When=(Get-Date); Data=$accountRate }
        }
        $resetCredits = Get-RateLimitResetCredits
        if ($null -ne $resetCredits) {
            $script:resetCount = $resetCredits.Count
            $script:resetExpiresList = @($resetCredits.ExpiresAtList)
            $script:resetExpires = if ($script:resetExpiresList.Count -gt 0) { $script:resetExpiresList[0] } else { $null }
        }
    }
    Get-CodexSnapshot | ConvertTo-Json -Depth 8
    exit 0
}

$window.Add_MouseLeftButtonDown({
    if ($args[1].ClickCount -ge 2) { $window.Close(); return }
    try { $window.DragMove() } catch {}
})
$window.Add_MouseRightButtonUp({ $window.Topmost = !$window.Topmost })

$workArea = [System.Windows.SystemParameters]::WorkArea
$window.Left = $workArea.Right - $window.Width - 18
$window.Top = $workArea.Bottom - $window.Height - 18

$script:timer = [Windows.Threading.DispatcherTimer]::new()
$script:timer.Interval = [TimeSpan]::FromSeconds(2)
$script:timer.Add_Tick({ Invoke-SafeWidgetUpdate })
$window.Add_Loaded({ Invoke-SafeWidgetUpdate; $script:timer.Start() })
$window.Add_Closed({
    $script:timer.Stop()
    Stop-LogStateProbe
    if ($instanceMutex) {
        try { $instanceMutex.ReleaseMutex() } catch {}
        $instanceMutex.Dispose()
    }
})

[void]$window.ShowDialog()
