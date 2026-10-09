. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\OpenRelax.Core.ps1')

function New-TestWorkspace {
    param([string]$Path)
    if ($Path -notmatch '^[A-Za-z]:\\') { throw 'Test workspace must be an absolute local path.' }
    $full = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $full) { throw 'Test workspace already exists; no existing data may be overwritten.' }
    Assert-CleanupPath $full $full
    [void][IO.Directory]::CreateDirectory($full)
    $workspace = @{ Path = $full; Owner = [guid]::NewGuid().ToString('N') }
    $marker = @{ kind = 'OpenRelaxTestWorkspace'; owner = $workspace.Owner; path = $full } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $full '.openrelax-test-workspace'),$marker,[Text.UTF8Encoding]::new($false))
    return $workspace
}

function Remove-TestWorkspace {
    param([hashtable]$Workspace)
    Assert-TestFixture $Workspace.Path
    $marker = Get-Content -LiteralPath (Join-Path $Workspace.Path '.openrelax-test-workspace') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($marker.owner -ne $Workspace.Owner) { throw 'Workspace ownership changed; cleanup refused.' }
    # Junctions created by a fixture must be explicitly removed before workspace cleanup.
    $state = @{ Partial = $false; Skipped = 0; ErrorCount = 0; Errors = @() }
    [void]@(Get-SafeTreeEntries -Path $Workspace.Path -State $state)
    if ($state.Skipped -or $state.ErrorCount) { throw 'Workspace has a link/unreadable entry; cleanup refused.' }
    [IO.Directory]::Delete($Workspace.Path,$true)
}

function Get-TestFunctionSource {
    param([string[]]$Names)
    $repo = Split-Path -Parent $PSScriptRoot
    $functions = @{}
    foreach ($path in @((Join-Path $repo 'openrelax.ps1'),(Join-Path $repo 'fotokapan.ps1'),(Join-Path $repo 'lib\OpenRelax.Core.ps1'))) {
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        if ($errors.Count) { throw "Invalid PowerShell source: $path" }
        foreach ($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)) { $functions[$node.Name] = $node.Extent.Text }
    }
    return (($Names | ForEach-Object { if (-not $functions.ContainsKey($_)) { throw "Missing function: $_" }; $functions[$_] }) -join "`n")
}

function Start-FixtureApp {
    param([string]$Root,[string]$Arguments,[int]$TimeoutSeconds = 45,[hashtable]$Hooks = @{},[switch]$VisibleUi)
    Assert-TestFixture $Root
    foreach ($directory in 'state','temp','local','profile','trap','temp-data','browser','discord','shader','wer','wu','gpusetup') { [void][IO.Directory]::CreateDirectory((Join-Path $Root $directory)) }
    $app = Join-Path (Split-Path -Parent $PSScriptRoot) 'openrelax.ps1'
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $info.Arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "' + $app + '" -TestMode -FixtureRoot "' + $Root + '" -StateDir "' + (Join-Path $Root 'state') + '" ' + $Arguments
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true; $info.WindowStyle = 'Hidden'
    if ($VisibleUi) { $info.WindowStyle = 'Normal' }
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    foreach ($key in @($info.EnvironmentVariables.Keys)) { if ($key -like 'OPENRELAX_*') { $info.EnvironmentVariables.Remove($key) } }
    # Explicit TestMode routes app state/targets to fixtures. Keep known-folder
    # identities accurate so protected-path checks remain meaningful.
    foreach ($pair in @(@('TEMP','temp'),@('TMP','temp'),@('OPENRELAX_TRAP_DIR','trap'),@('PSModuleAnalysisCachePath','module-cache'))) { $info.EnvironmentVariables[$pair[0]] = Join-Path $Root $pair[1] }
    foreach ($key in $Hooks.Keys) {
        if ($key -notin @('OPENRELAX_STRESS','OPENRELAX_STRESS_REPORT','OPENRELAX_SMOKETEST')) { throw 'Unsupported fixture hook.' }
        if ($key -eq 'OPENRELAX_STRESS_REPORT') { Assert-CleanupPath $Hooks[$key] $Root }
        $info.EnvironmentVariables[$key] = [string]$Hooks[$key]
    }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        # This PID was created and is owned by this exact test invocation.
        $process.Kill(); $process.WaitForExit(); $process.Dispose()
        throw 'Owned fixture application timed out.'
    }
    $result = @{ ExitCode = $process.ExitCode; Stdout = $stdout.Result; Stderr = $stderr.Result }
    $process.Dispose()
    return $result
}


function Start-OwnedTestProcess {
    param([string]$Root,[string]$Arguments)
    Assert-TestFixture $Root
    $temp = Join-Path $Root 'temp'; [void][IO.Directory]::CreateDirectory($temp)
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $info.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass ' + $Arguments
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true; $info.WindowStyle = 'Hidden'
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    foreach ($key in @($info.EnvironmentVariables.Keys)) { if ($key -like 'OPENRELAX_*') { $info.EnvironmentVariables.Remove($key) } }
    $info.EnvironmentVariables['TEMP'] = $temp; $info.EnvironmentVariables['TMP'] = $temp
    $info.EnvironmentVariables['PSModuleAnalysisCachePath'] = Join-Path $Root 'module-cache'
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    [void]$process.Start()
    Add-Member -InputObject $process -MemberType NoteProperty -Name TestStdout -Value ($process.StandardOutput.ReadToEndAsync())
    Add-Member -InputObject $process -MemberType NoteProperty -Name TestStderr -Value ($process.StandardError.ReadToEndAsync())
    return $process
}
