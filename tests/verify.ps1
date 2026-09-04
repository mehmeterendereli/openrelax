[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$appPath = Join-Path $repoRoot 'openrelax.ps1'

if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) {
    throw "OpenRelax entrypoint was not found: $appPath"
}

Write-Host '== PowerShell parser check =='
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $appPath,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null

if ($parseErrors.Count -gt 0) {
    foreach ($parseError in $parseErrors) {
        Write-Error ("{0}:{1}:{2} {3}" -f $appPath, $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message)
    }
    throw "PowerShell parser reported $($parseErrors.Count) error(s)."
}

Write-Host "Parser OK: $($tokens.Count) tokens"
Write-Host '== Read-only application self-test =='

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    $windowsPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
}

$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $windowsPowerShell
$startInfo.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$appPath`" -SelfTest"
$startInfo.WorkingDirectory = $repoRoot
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo

if (-not $process.Start()) {
    throw 'Could not start the OpenRelax self-test process.'
}

$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()
$exitCode = $process.ExitCode
$process.Dispose()

if ($stdout) {
    Write-Host $stdout.TrimEnd()
}
if ($stderr) {
    Write-Host $stderr.TrimEnd()
}

if ($exitCode -ne 0) {
    throw "OpenRelax -SelfTest exited with code $exitCode."
}
if ($stdout -notmatch 'OpenRelax v2\.0 self-test') {
    throw 'The self-test banner was not found in the application output.'
}
if ($stdout -notmatch 'Self-test OK') {
    throw 'The application did not emit its Self-test OK completion marker.'
}

Write-Host 'Verification OK: parser clean and read-only self-test completed.'
