$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'CodexStatusWidget.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Widget parse failed' }
$function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-LogCompletionMap' }, $true)
. ([scriptblock]::Create($function.Extent.Text))
Add-Type @'
using System.Threading.Tasks;
public class StalledWidgetReader {
    public Task<string> ReadLineAsync() { return new TaskCompletionSource<string>().Task; }
}
'@
function Start-LogStateProbe { return $true }
function Stop-LogStateProbe { $script:stopped = $true }
$script:stopped = $false
$script:logProbe = [pscustomobject]@{
    StandardInput = [IO.StringWriter]::new()
    StandardOutput = [StalledWidgetReader]::new()
}
$clock = [Diagnostics.Stopwatch]::StartNew()
$result = Get-LogCompletionMap @(@{ Status='running'; ThreadId='thread'; TurnId='turn' })
$clock.Stop()
if (!$script:stopped -or $result.Count -ne 0 -or $clock.Elapsed.TotalSeconds -gt 3) {
    throw 'Stalled log probe did not stop within the timeout budget'
}
Write-Host 'PASS stalled helper returns without blocking the widget'
