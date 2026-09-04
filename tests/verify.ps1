[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$appPath = Join-Path $repoRoot 'openrelax.ps1'

if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) {
    throw "OpenRelax entrypoint was not found: $appPath"
}

function Get-FileFingerprint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            Exists = $false
            Hash   = $null
            Length = [long]0
        }
    }

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    return [pscustomobject]@{
        Exists = $true
        Hash   = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        Length = [long]$file.Length
    }
}

function Assert-FileFingerprintUnchanged {
    param(
        [Parameter(Mandatory = $true)]
        $Before,

        [Parameter(Mandatory = $true)]
        $After,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if ($Before.Exists -ne $After.Exists) {
        throw "$Label existence changed during -SelfTest."
    }

    if ($Before.Exists -and (($Before.Hash -ne $After.Hash) -or ($Before.Length -ne $After.Length))) {
        throw "$Label content changed during -SelfTest."
    }
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

$settingsPath = Join-Path $env:APPDATA 'OpenRelax\settings.json'
$autoCleanLogPath = Join-Path $env:APPDATA 'OpenRelax\autoclean.log'
$settingsBefore = Get-FileFingerprint -Path $settingsPath
$autoCleanLogBefore = Get-FileFingerprint -Path $autoCleanLogPath

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

$settingsAfter = Get-FileFingerprint -Path $settingsPath
$autoCleanLogAfter = Get-FileFingerprint -Path $autoCleanLogPath
Assert-FileFingerprintUnchanged -Before $settingsBefore -After $settingsAfter -Label 'Settings file'
Assert-FileFingerprintUnchanged -Before $autoCleanLogBefore -After $autoCleanLogAfter -Label 'AutoClean log'

Write-Host 'Read-only contract OK: settings and AutoClean log were unchanged.'
Write-Host 'Verification OK: parser clean, self-test completed and persistent state stayed unchanged.'
