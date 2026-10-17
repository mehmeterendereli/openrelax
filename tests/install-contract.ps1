# Contract of the one-line installer (install.ps1) and the Scoop manifest:
# a verified zip installs; a tampered or incomplete zip, or a destination
# that is not an OpenRelax install, is refused before anything is written.
# Uses only owned fixtures; no shortcut, no registry change.
[CmdletBinding()]
param([string]$Work = (Join-Path $env:TEMP ('openrelax-install-' + [guid]::NewGuid().ToString('N'))),[switch]$KeepArtifacts)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-support.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$workspace = New-TestWorkspace $Work
$Work = $workspace.Path
$script:Cases = [Collections.Generic.List[object]]::new()
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Case([string]$Name,[scriptblock]$Action) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try { & $Action; $script:Cases.Add(@{ name = $Name; passed = $true }); Write-Host ('PASS {0} ({1:N1} s)' -f $Name, $clock.Elapsed.TotalSeconds) }
    catch { $script:Cases.Add(@{ name = $Name; passed = $false; error = $_.Exception.Message }); Write-Host ('FAIL {0} ({1:N1} s): {2}' -f $Name, $clock.Elapsed.TotalSeconds, $_.Exception.Message) }
}
function New-Sums([string]$Zip) {
    $sums = Join-Path (Split-Path -Parent $Zip) 'SHA256SUMS'
    $line = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + (Split-Path -Leaf $Zip)
    [IO.File]::WriteAllText($sums, $line + "`n")
    return $sums
}
function Invoke-Installer([string]$Zip, [string]$Sums, [string]$Destination) {
    $arguments = '-File "' + (Join-Path $repo 'install.ps1') + '" -ZipPath "' + $Zip + '" -ShaPath "' + $Sums + '" -Destination "' + $Destination + '" -NoShortcut -NoStartup'
    $p = Start-OwnedTestProcess $Work $arguments
    if (-not $p.WaitForExit(90000)) {
        $p.Kill(); [void]$p.WaitForExit(10000)
        throw ('Installer timed out after 90 s. Output so far: ' + $p.TestStdout.Result + ' ' + $p.TestStderr.Result)
    }
    $result = @{ ExitCode = $p.ExitCode; Stdout = $p.TestStdout.Result; Stderr = $p.TestStderr.Result }
    $p.Dispose()
    return $result
}

$good = Join-Path $Work 'release\OpenRelax-9.9.9.zip'
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $good))
& git -C $repo archive --format=zip --prefix=OpenRelax-9.9.9/ -o $good HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive failed.' }
$goodSums = New-Sums $good

Case 'a verified release zip installs the application files' {
    $dest = Join-Path $Work 'dest-good'
    $r = Invoke-Installer $good $goodSums $dest
    Assert-True ($r.ExitCode -eq 0) ('Installer failed: ' + $r.Stderr + $r.Stdout)
    foreach ($file in 'openrelax.ps1','launch.bat','lib\OpenRelax.Core.ps1','lib\OpenRelax.Engine.ps1','lib\OpenRelax.Trap.ps1','lib\OpenRelax.Sampler.ps1','docs\openrelax.ico') {
        Assert-True (Test-Path -LiteralPath (Join-Path $dest $file)) "Missing after install: $file"
    }
    Assert-True (Test-Path -LiteralPath (Join-Path $dest '.openrelax-install')) 'The install marker is missing.'
    $again = Invoke-Installer $good $goodSums $dest
    Assert-True ($again.ExitCode -eq 0) ('Reinstalling over an OpenRelax install failed: ' + $again.Stderr)
}
Case 'replacing an install removes a junction inside it without entering it' {
    $dest = Join-Path $Work 'dest-junction'
    $first = Invoke-Installer $good $goodSums $dest
    Assert-True ($first.ExitCode -eq 0) ('First install failed: ' + $first.Stderr)
    $outside = Join-Path $Work 'outside-sentinel'; [void][IO.Directory]::CreateDirectory($outside)
    [IO.File]::WriteAllText((Join-Path $outside 'keep.txt'),'keep')
    $escape = Join-Path $dest 'escape'
    New-Item -ItemType Junction -Path $escape -Target $outside | Out-Null
    try {
        $r = Invoke-Installer $good $goodSums $dest
        Assert-True ($r.ExitCode -eq 0) ('Reinstall failed: ' + $r.Stderr)
        Assert-True ([IO.File]::ReadAllText((Join-Path $outside 'keep.txt')) -eq 'keep') 'The junction target was deleted.'
        Assert-True (-not (Test-Path -LiteralPath $escape)) 'The junction was left in the new install.'
    } finally {
        # A failed case must not leave a link that blocks workspace cleanup.
        if ([IO.Directory]::Exists($escape)) { [IO.Directory]::Delete($escape) }
    }
}
Case 'a destination that is a link is refused without touching its target' {
    $target = Join-Path $Work 'link-target'; [void][IO.Directory]::CreateDirectory($target)
    [IO.File]::WriteAllText((Join-Path $target '.openrelax-install'),'pretend'); [IO.File]::WriteAllText((Join-Path $target 'keep.txt'),'keep')
    $dest = Join-Path $Work 'dest-link'
    New-Item -ItemType Junction -Path $dest -Target $target | Out-Null
    try {
        $r = Invoke-Installer $good $goodSums $dest
        Assert-True ($r.ExitCode -ne 0) 'A junction destination was accepted.'
        Assert-True ([IO.File]::ReadAllText((Join-Path $target 'keep.txt')) -eq 'keep' -and -not (Test-Path -LiteralPath (Join-Path $target 'openrelax.ps1'))) 'The junction target was changed.'
    } finally {
        if ([IO.Directory]::Exists($dest)) { [IO.Directory]::Delete($dest) }
    }
}
Case 'a tampered zip is refused before anything is extracted' {
    $bad = Join-Path $Work 'tampered\OpenRelax-9.9.9.zip'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $bad))
    Copy-Item -LiteralPath $good -Destination $bad
    Copy-Item -LiteralPath $goodSums -Destination (Join-Path (Split-Path -Parent $bad) 'SHA256SUMS')
    $bytes = [IO.File]::ReadAllBytes($bad); $bytes[[int]($bytes.Length / 2)] = $bytes[[int]($bytes.Length / 2)] -bxor 0xFF; [IO.File]::WriteAllBytes($bad, $bytes)
    $dest = Join-Path $Work 'dest-tampered'
    $r = Invoke-Installer $bad (Join-Path (Split-Path -Parent $bad) 'SHA256SUMS') $dest
    Assert-True ($r.ExitCode -ne 0 -and (($r.Stderr + $r.Stdout) -replace '\s+','') -match 'SHA256') ('A tampered zip was accepted: ' + $r.Stdout)
    Assert-True (-not (Test-Path -LiteralPath $dest)) 'Files were written for a tampered zip.'
}
Case 'a zip without the application is refused' {
    $src = Join-Path $Work 'partial-src\OpenRelax-9.9.9'
    [void][IO.Directory]::CreateDirectory((Join-Path $src 'lib'))
    [IO.File]::WriteAllText((Join-Path $src 'launch.bat'),'rem')
    $partial = Join-Path $Work 'partial\OpenRelax-9.9.9.zip'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $partial))
    # .NET directly: Compress-Archive autoloads a module, and with the empty module
    # analysis cache verify gives this child that can scan every installed module.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($src, $partial, [IO.Compression.CompressionLevel]::Optimal, $true)
    $dest = Join-Path $Work 'dest-partial'
    $r = Invoke-Installer $partial (New-Sums $partial) $dest
    Assert-True ($r.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $dest)) 'An incomplete zip was installed.'
}
Case 'a folder that is not an OpenRelax install is never replaced' {
    $dest = Join-Path $Work 'dest-foreign'
    [void][IO.Directory]::CreateDirectory($dest)
    [IO.File]::WriteAllText((Join-Path $dest 'notes.txt'),'keep me')
    $r = Invoke-Installer $good $goodSums $dest
    Assert-True ($r.ExitCode -ne 0) 'A foreign folder was accepted as the destination.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $dest 'notes.txt')) -eq 'keep me' -and -not (Test-Path -LiteralPath (Join-Path $dest 'openrelax.ps1'))) 'A foreign folder was changed.'
}
Case 'the installer runs under irm | iex' {
    $text = [IO.File]::ReadAllText((Join-Path $repo 'install.ps1'))
    # -cmatch: a case-insensitive class also matches ASCII 'k' (Kelvin sign folding).
    Assert-True ($text[0] -ne [char]0xFEFF -and -not ($text -cmatch '[^\x00-\x7F]')) 'install.ps1 must be plain ASCII without a BOM.'
    [void][scriptblock]::Create($text)
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    Assert-True ($errors.Count -eq 0) 'install.ps1 does not parse.'
    $exits = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.ExitStatementAst] }, $true))
    Assert-True ($exits.Count -eq 0) "install.ps1 uses 'exit', which would close the caller's window under iex."
}
Case 'the Scoop manifest points at the verified release asset' {
    $manifest = Get-Content -LiteralPath (Join-Path $repo 'bucket\openrelax.json') -Raw | ConvertFrom-Json
    foreach ($field in 'version','url','hash','extract_dir','shortcuts','checkver','autoupdate','license','homepage','description') {
        Assert-True ([bool]$manifest.PSObject.Properties[$field]) "Manifest field missing: $field"
    }
    Assert-True ($manifest.url -eq ('https://github.com/mehmeterendereli/openrelax/releases/download/v{0}/OpenRelax-{0}.zip' -f $manifest.version)) "Unexpected url: $($manifest.url)"
    Assert-True ($manifest.extract_dir -eq ('OpenRelax-' + $manifest.version) -and $manifest.hash -match '^[0-9a-f]{64}$') 'extract_dir or hash do not match the release layout.'
    Assert-True ($manifest.autoupdate.url -eq 'https://github.com/mehmeterendereli/openrelax/releases/download/v$version/OpenRelax-$version.zip' -and $manifest.autoupdate.hash.url -match 'SHA256SUMS$') 'autoupdate does not follow the release assets.'
}

$failed = @($script:Cases | Where-Object { -not $_.passed }).Count
Write-Host ("Install contracts: {0} cases, {1} failed." -f $script:Cases.Count, $failed)
if (-not $KeepArtifacts) { Remove-TestWorkspace $workspace }
if ($failed) { exit 1 }
exit 0
