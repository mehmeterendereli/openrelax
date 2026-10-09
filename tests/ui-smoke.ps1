[CmdletBinding()]
param([string]$Work = (Join-Path $env:TEMP ('openrelax-ui-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-support.ps1')
$workspace = New-TestWorkspace $Work
$reportDir = Join-Path $workspace.Path 'ui'
$result = Start-FixtureApp $workspace.Path ('-UiAcceptanceReportDir "' + $reportDir + '"')
if ($result.ExitCode -ne 0 -or $result.Stderr) { throw ('UI fixture failed: ' + $result.Stderr) }
$report = Get-Content -LiteralPath (Join-Path $reportDir 'ui-report.json') -Raw | ConvertFrom-Json
if (-not $report.passed -or @($report.errors).Count -or @($report.checks).Count -ne 6) { throw ('UI acceptance failed: ' + ($report.errors -join '; ')) }
foreach ($check in 'settings-focus-order','dialog-key-routing','hidden-view-tab-skip','runtime-dpi-context','accessible-names-and-checkbox-action','small-viewport-reachability') {
    if ($check -notin $report.checks) { throw ('Missing acceptance check: ' + $check) }
}
if (-not $report.dpi -or $report.dpi.WindowDpi -le 0 -or $report.dpi.WindowMode -eq 'Invalid') { throw 'DPI evidence missing.' }
Write-Host "UI smoke OK: native Tab/Shift+Tab routing, hidden-view skip, accessible semantics/persistence, constrained viewport and actual DPI context. Evidence: $reportDir"
Write-Host ("Effective DPI: {0}; window DPI {1}; setter success {2}; Win32 error {3}" -f $report.dpi.WindowMode,$report.dpi.WindowDpi,$report.dpi.Initialization.Success,$report.dpi.Initialization.Win32Error)
