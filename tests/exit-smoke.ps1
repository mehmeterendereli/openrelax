[CmdletBinding()]
param([string]$Work = (Join-Path $env:TEMP ('openrelax-exit-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-support.ps1')
$workspace = New-TestWorkspace $Work
$result = Start-FixtureApp $workspace.Path '-ExitDuringWorkerTest'
if ($result.ExitCode -ne 0 -or $result.Stderr) { throw ('Exit fixture failed: ' + $result.Stderr) }
$proof = [IO.File]::ReadAllText((Join-Path $workspace.Path 'exit-worker.txt'))
if ($proof -ne 'begin;end') { throw 'Closing the window terminated the active worker before it completed.' }
Write-Host 'Exit smoke OK: real GUI close waited for the owned worker to complete.'
