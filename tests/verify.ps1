[CmdletBinding()]
param([string]$Work = (Join-Path $env:TEMP ('openrelax-verify-' + [guid]::NewGuid().ToString('N'))),[switch]$KeepArtifacts)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-support.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$workspace = New-TestWorkspace $Work
$Work = $workspace.Path
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
try {
    $sources = @(Get-ChildItem -LiteralPath $repo -Filter '*.ps1' -Recurse -File)
    foreach ($source in $sources) {
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($source.FullName,[ref]$tokens,[ref]$errors)
        Assert ($errors.Count -eq 0) ("Parser errors in " + $source.Name + ': ' + ($errors -join '; '))
        if ($source.Name -eq 'openrelax.ps1') { $appAst = $ast }
    }
    $workers = @{}
    foreach ($name in 'ScanTaskCode','CleanTaskCode','RamTaskCode','DiskTaskCode') {
        $assignment = $appAst.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq ('$script:' + $name)},$true)
        $literal = $assignment.Right.Find({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]},$true)
        Assert ($null -ne $literal) "Worker source missing: $name"
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($literal.Value,[ref]$tokens,[ref]$errors)
        Assert ($errors.Count -eq 0) "Worker parser errors: $name"
        $workers[$name] = $literal.Value
    }
    Write-Host "Parser OK: $($sources.Count) source/test files and 4 workers."
    # A bounded child runs pure contracts and small owned synthetic file fixtures.
    $contractInfo = [Diagnostics.ProcessStartInfo]::new()
    $contractInfo.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $contractInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'safety-contracts.ps1') + '" -Work "' + (Join-Path $Work 'contracts') + '" -KeepArtifacts'
    $contractInfo.UseShellExecute = $false; $contractInfo.CreateNoWindow = $true; $contractInfo.RedirectStandardOutput = $true; $contractInfo.RedirectStandardError = $true
    foreach ($key in @($contractInfo.EnvironmentVariables.Keys)) { if ($key -like 'OPENRELAX_*') { $contractInfo.EnvironmentVariables.Remove($key) } }
    $childTemp = Join-Path $Work 'contract-temp'; [void][IO.Directory]::CreateDirectory($childTemp)
    $contractInfo.EnvironmentVariables['TEMP'] = $childTemp; $contractInfo.EnvironmentVariables['TMP'] = $childTemp
    $contractInfo.EnvironmentVariables['PSModuleAnalysisCachePath'] = Join-Path $Work 'contract-module-cache'
    $child = [Diagnostics.Process]::new(); $child.StartInfo = $contractInfo
    [void]$child.Start(); $out = $child.StandardOutput.ReadToEndAsync(); $err = $child.StandardError.ReadToEndAsync()
    if (-not $child.WaitForExit(60000)) { $child.Kill(); $child.WaitForExit(); throw 'Owned contract child timed out.' }
    $code = $child.ExitCode; $text = $out.Result; $errorText = $err.Result; $child.Dispose()
    Write-Host $text.TrimEnd()
    Assert ($code -eq 0 -and -not $errorText -and $text -match '0 failed') ('Safety contracts failed: ' + $errorText)
    $fixture = New-TestWorkspace (Join-Path $Work 'app')
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture.Path 'state'))
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture.Path 'temp'))
    $settingsFile = Join-Path $fixture.Path 'state\settings.json'
    $logFile = Join-Path $fixture.Path 'state\autoclean.log'
    $settings = Get-DefaultSettings
    foreach ($key in @($settings.categories.Keys)) { $settings.categories[$key] = ($key -eq 'temp') }
    Write-SettingsAtomic $settings $settingsFile
    [IO.File]::WriteAllText($logFile,'unchanged')
    $old = Join-Path $fixture.Path 'temp\old.tmp'; [IO.File]::WriteAllBytes($old,(New-Object byte[] 4096)); [IO.File]::SetLastWriteTime($old,(Get-Date).AddDays(-3))
    $fresh = Join-Path $fixture.Path 'temp\fresh.tmp'; [IO.File]::WriteAllText($fresh,'keep')
    $settingsHash = (Get-FileHash -LiteralPath $settingsFile).Hash; $logHash = (Get-FileHash -LiteralPath $logFile).Hash
    $self = Start-FixtureApp $fixture.Path '-SelfTest'
    $version = [regex]::Match([IO.File]::ReadAllText((Join-Path $repo 'openrelax.ps1')), "\`$script:AppVersion\s*=\s*'([^']+)'").Groups[1].Value
    Assert ($self.ExitCode -eq 0 -and -not $self.Stderr -and $self.Stdout -match ('OpenRelax v' + [regex]::Escape($version)) -and $self.Stdout -match 'Self-test OK') ('Real SelfTest failed: ' + $self.Stderr)
    Assert ((Get-FileHash -LiteralPath $settingsFile).Hash -eq $settingsHash -and (Get-FileHash -LiteralPath $logFile).Hash -eq $logHash) 'SelfTest changed persistent state.'
    Assert ((Test-Path -LiteralPath $old) -and [IO.File]::ReadAllText($fresh) -eq 'keep') 'SelfTest modified fixture data.'
    Write-Host 'Real SelfTest OK: fixture files, settings and log unchanged.'
    $conflicting = Start-FixtureApp $fixture.Path '-SelfTest -AutoClean'
    Assert ($conflicting.ExitCode -ne 0 -and $conflicting.Stderr -match 'cannot be combined') 'Conflicting modes were accepted.'
    Assert ((Get-FileHash -LiteralPath $settingsFile).Hash -eq $settingsHash -and (Get-FileHash -LiteralPath $logFile).Hash -eq $logHash -and (Get-Item -LiteralPath $old).Length -eq 4096 -and [IO.File]::ReadAllText($fresh) -eq 'keep') 'Conflicting modes changed state or target files.'
    Write-Host 'Conflicting SelfTest/AutoClean refused before mutation.'
    [IO.File]::WriteAllText($settingsFile,'{"language":')
    $badHash = (Get-FileHash -LiteralPath $settingsFile).Hash
    $bad = Start-FixtureApp $fixture.Path '-AutoClean'
    Assert ($bad.ExitCode -eq 1 -and $bad.Stderr -match 'AutoClean stopped') 'Invalid settings did not stop AutoClean.'
    Assert ((Test-Path -LiteralPath $old) -and (Get-FileHash -LiteralPath $settingsFile).Hash -eq $badHash -and (Get-FileHash -LiteralPath $logFile).Hash -eq $logHash) 'Invalid settings caused a mutation.'
    Write-SettingsAtomic $settings $settingsFile
    $clean = Start-FixtureApp $fixture.Path '-AutoClean'
    Assert ($clean.ExitCode -eq 0 -and -not $clean.Stderr -and $clean.Stdout -match 'status=Success; files=1; bytes=4096') ('AutoClean result incorrect: ' + $clean.Stdout + $clean.Stderr)
    Assert (-not (Test-Path -LiteralPath $old) -and [IO.File]::ReadAllText($fresh) -eq 'keep') 'AutoClean deleted the wrong fixture file.'
    $after = Read-SettingsDocument $settingsFile
    Assert ($after.Valid -and $after.Settings.stats.totalRuns -eq 1 -and $after.Settings.stats.totalCleanedBytes -eq 4096) 'AutoClean statistics were not persisted correctly.'
    $after.Settings.categories.recycle = $true; Write-SettingsAtomic $after.Settings $settingsFile
    $partial = Start-FixtureApp $fixture.Path '-AutoClean'
    Assert ($partial.ExitCode -eq 2 -and $partial.Stdout -match 'status=Partial' -and $partial.Stdout -match 'skipped=1') 'Headless restricted work was reported as complete.'
    Write-Host 'Real AutoClean OK: invalid settings fail closed, correct file/count/statistics, restricted work exits 2.'
    $scanFixture = New-TestWorkspace (Join-Path $Work 'scan')
    $scanTemp = Join-Path $scanFixture.Path 'temp'; [void][IO.Directory]::CreateDirectory($scanTemp)
    $scanFile = Join-Path $scanTemp 'old.tmp'; [IO.File]::WriteAllBytes($scanFile,(New-Object byte[] 88)); [IO.File]::SetLastWriteTime($scanFile,(Get-Date).AddDays(-3))
    $priorFixture = $env:OPENRELAX_FIXTURE_ROOT
    $scanSync = [hashtable]::Synchronized(@{ Beat = [DateTime]::UtcNow; ScanResult = $null; Log = [Collections.Queue]::new() })
    $scanWorker = [powershell]::Create()
    try {
        $env:OPENRELAX_FIXTURE_ROOT = $scanFixture.Path
        $source = Get-TestFunctionSource @('Test-PathWithin','Assert-NoReparseAncestors','Assert-CleanupPath','Get-SafeTreeEntries','Get-JunkCategories','Get-RecycleBinInfo','Measure-JunkPaths')
        [void]$scanWorker.AddScript('Set-StrictMode -Version 2' + "`n" + $source)
        [void]$scanWorker.AddStatement().AddScript($workers.ScanTaskCode).AddArgument($scanSync).AddArgument(@{ IsAdmin = $false })
        $handle = $scanWorker.BeginInvoke()
        if (-not $handle.AsyncWaitHandle.WaitOne(15000)) { [void]$scanWorker.BeginStop($null,$null); throw 'Scan worker timed out.' }
        [void]$scanWorker.EndInvoke($handle)
        Assert (-not $scanWorker.HadErrors -and $scanSync.ScanResult.Status -eq 'Success' -and $scanSync.ScanResult.TotalSize -eq 88 -and $scanSync.ScanResult.FileCount -eq 1 -and $scanSync.ScanResult.Errors.Count -eq 0) 'Real scan worker failed or returned incorrect totals.'
        Assert ((Get-Item -LiteralPath $scanFile).Length -eq 88) 'Scan worker changed the target file.'
    } finally { $scanWorker.Dispose(); $env:OPENRELAX_FIXTURE_ROOT = $priorFixture }
    Write-Host 'Real scan worker OK: successful status and physical byte/count totals.'
    # Run the real analysis worker, including a link to an outside sentinel.
    $disk = New-TestWorkspace (Join-Path $Work 'disk')
    $good = Join-Path $disk.Path 'good'; [void][IO.Directory]::CreateDirectory($good)
    [IO.File]::WriteAllBytes((Join-Path $good 'data.bin'),(New-Object byte[] 123))
    $outside = Join-Path $Work 'disk-outside'; [void][IO.Directory]::CreateDirectory($outside)
    $sentinel = Join-Path $outside 'keep.bin'; [IO.File]::WriteAllBytes($sentinel,(New-Object byte[] 9000))
    $link = Join-Path $disk.Path 'escape'; New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
    $sync = [hashtable]::Synchronized(@{ Beat = [DateTime]::UtcNow; DiskResult = $null; DiskProgress = $null })
    $ps = [powershell]::Create()
    try {
        $engine = Get-TestFunctionSource @('Test-PathWithin','Assert-NoReparseAncestors','Get-SafeTreeEntries')
        [void]$ps.AddScript('Set-StrictMode -Version 2' + "`n" + $engine)
        [void]$ps.AddStatement().AddScript($workers.DiskTaskCode).AddArgument($sync).AddArgument(@{ Target = $disk.Path })
        $handle = $ps.BeginInvoke()
        if (-not $handle.AsyncWaitHandle.WaitOne(15000)) { [void]$ps.BeginStop($null,$null); throw 'Disk worker timed out.' }
        [void]$ps.EndInvoke($handle)
        Assert (-not $ps.HadErrors) ('Disk worker errors: ' + ($ps.Streams.Error -join '; '))
        $result = $sync.DiskResult
        Assert ($result.Status -eq 'Partial' -and $result.Count -eq 1 -and $result.Rows.Count -eq 1 -and $result.Rows[0].Name -eq 'good' -and $result.Rows[0].Size -eq 123 -and $result.Skipped -eq 1) 'Disk worker followed a junction or misreported its result.'
        Assert ((Get-Item -LiteralPath $sentinel).Length -eq 9000) 'Disk analysis changed the outside sentinel.'
    } finally { $ps.Dispose(); [IO.Directory]::Delete($link) }
    # Explicit fixture state redirection must reject an ancestor junction.
    $stateFixture = New-TestWorkspace (Join-Path $Work 'state-guard')
    $stateLink = Join-Path $stateFixture.Path 'state'; New-Item -ItemType Junction -Path $stateLink -Target $outside | Out-Null
    try {
        $refused = Start-FixtureApp $stateFixture.Path '-SelfTest'
        Assert ($refused.ExitCode -ne 0 -and $refused.Stdout -notmatch 'Self-test OK') 'Junction state override was accepted.'
        Assert (-not (Test-Path -LiteralPath (Join-Path $outside 'settings.json'))) 'State override wrote outside its fixture.'
    } finally { [IO.Directory]::Delete($stateLink) }
    Write-Host 'Real disk worker and state-path guards OK: outside sentinel untouched.'
    Write-Host 'Verification OK.'
} finally {
    if ($KeepArtifacts) { Write-Host "Artifacts: $Work" } else { Remove-TestWorkspace $workspace }
}
