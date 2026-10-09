[CmdletBinding()]
param([string]$Work = (Join-Path $env:TEMP ('openrelax-ui-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-support.ps1')
$workspace = New-TestWorkspace $Work
$reportDir = Join-Path $workspace.Path 'ui'
$result = Start-FixtureApp $workspace.Path ('-UiAcceptanceReportDir "' + $reportDir + '"')
if ($result.ExitCode -ne 0 -or $result.Stderr) { throw ('UI fixture failed: ' + $result.Stderr) }
$report = Get-Content -LiteralPath (Join-Path $reportDir 'ui-report.json') -Raw | ConvertFrom-Json
if (-not $report.passed -or @($report.errors).Count -or @($report.checks).Count -ne 3) { throw ('UI acceptance failed: ' + ($report.errors -join '; ')) }
foreach ($check in 'settings-focus-order','accessible-names-and-checkbox-action','small-viewport-reachability') {
    if ($check -notin $report.checks) { throw ('Missing acceptance check: ' + $check) }
}
Write-Host "UI smoke OK: native focus order, accessible semantics/persistence and constrained viewport. Evidence: $reportDir"
