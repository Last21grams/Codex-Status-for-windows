$ErrorActionPreference = 'Stop'
$desktop = [Environment]::GetFolderPath('Desktop')
$target = Join-Path $PSScriptRoot 'Start-CodexStatusWidget.vbs'
$shortcutName = 'Codex ' + [char]0x72B6 + [char]0x6001 + [char]0x706F + '.lnk'
$shortcutPath = Join-Path $desktop $shortcutName
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $target
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = 'Codex status and usage widget'
$shortcut.IconLocation = (Join-Path $PSScriptRoot 'assets\codex-status-icon.ico') + ',0'
$shortcut.Save()
Write-Host "Desktop shortcut created: $shortcutPath"
