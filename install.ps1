# OpenRelax one-line installer (current user, no administrator rights):
#
#   irm https://raw.githubusercontent.com/mehmeterendereli/openrelax/main/install.ps1 | iex
#
# Downloads the latest GitHub release zip and its SHA256SUMS, verifies the hash
# BEFORE extracting anything, checks that the application files are present,
# installs to %LOCALAPPDATA%\Programs\OpenRelax and adds a Start menu
# shortcut. Settings and records stay in %APPDATA%\OpenRelax and are never
# touched. A folder that is not an OpenRelax install is never replaced.
# Every step is printed. It never elevates and never uses 'exit' (that would
# close the caller's window under iex).
[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'Programs\OpenRelax'),
    [string]$ZipPath,
    [string]$ShaPath,
    [string]$Repository = 'mehmeterendereli/openrelax',
    [switch]$NoShortcut,
    [switch]$NoStartup
)
$ErrorActionPreference = 'Stop'
$required = @('openrelax.ps1', 'launch.bat', 'lib\OpenRelax.Core.ps1', 'lib\OpenRelax.Engine.ps1', 'lib\OpenRelax.Trap.ps1', 'lib\OpenRelax.Sampler.ps1', 'docs\openrelax.ico')
$marker = '.openrelax-install'
function Write-Step([string]$Text) { Write-Host ('[OpenRelax] ' + $Text) }
# Deletes an earlier install's entry. A junction or symlink is removed as a
# link, never entered: Remove-Item -Recurse on Windows PowerShell 5.1 could
# delete the files a junction points to.
function Remove-InstallEntry([IO.FileSystemInfo]$Entry) {
    if ($Entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        if ($Entry -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($Entry.FullName) } else { [IO.File]::Delete($Entry.FullName) }
        return
    }
    if ($Entry -is [IO.DirectoryInfo]) {
        foreach ($child in $Entry.GetFileSystemInfos()) { Remove-InstallEntry $child }
        [IO.Directory]::Delete($Entry.FullName)
    } else {
        if ($Entry.IsReadOnly) { $Entry.IsReadOnly = $false }
        $Entry.Delete()
    }
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('openrelax-install-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
    # 1. The release zip and its checksum list.
    if (-not $ZipPath) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-Step "Reading the latest release of $Repository"
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -Headers @{ 'User-Agent' = 'OpenRelax-installer' }
        $zipAsset = @($release.assets | Where-Object { $_.name -match '^OpenRelax-[0-9][0-9A-Za-z.\-]*\.zip$' }) | Select-Object -First 1
        $sumAsset = @($release.assets | Where-Object { $_.name -eq 'SHA256SUMS' }) | Select-Object -First 1
        if (-not $zipAsset -or -not $sumAsset) { throw "Release $($release.tag_name) has no OpenRelax zip with SHA256SUMS." }
        $ZipPath = Join-Path $temp $zipAsset.name
        $ShaPath = Join-Path $temp 'SHA256SUMS'
        Write-Step "Downloading $($zipAsset.name) ($($release.tag_name))"
        Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $ZipPath -UseBasicParsing
        Invoke-WebRequest -Uri $sumAsset.browser_download_url -OutFile $ShaPath -UseBasicParsing
    }
    if (-not $ShaPath) { throw 'A local -ZipPath needs its -ShaPath (SHA256SUMS).' }

    # 2. Verify before anything is extracted.
    $zipName = Split-Path -Leaf $ZipPath
    $expected = @(Get-Content -LiteralPath $ShaPath | ForEach-Object { $_.Trim() } | Where-Object { $_ -match ('^[0-9a-fA-F]{64}\s+\*?' + [regex]::Escape($zipName) + '$') } | ForEach-Object { ($_ -split '\s+')[0].ToLowerInvariant() }) | Select-Object -First 1
    if (-not $expected) { throw "SHA256SUMS has no line for $zipName; nothing was installed." }
    $actual = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "SHA256 mismatch for $zipName (expected $expected, got $actual); nothing was installed." }
    Write-Step "SHA256 verified: $actual"

    # 3. Extract to staging and check the application files.
    $staging = Join-Path $temp 'staging'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $staging)
    $roots = @(Get-ChildItem -LiteralPath $staging -Directory)
    $source = $staging
    if ($roots.Count -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $staging 'openrelax.ps1'))) { $source = $roots[0].FullName }
    foreach ($file in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $file) -PathType Leaf)) { throw "The release zip lacks $file; nothing was installed." }
    }

    # 4. Destination: new, empty, or an earlier OpenRelax install (marker).
    if ($Destination -notmatch '^[A-Za-z]:\\') { throw 'Destination must be an absolute local path.' }
    $Destination = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
    if ($Destination.Length -le 3) { throw 'A drive root cannot be the destination.' }
    if (Test-Path -LiteralPath $Destination) {
        $existing = @(Get-ChildItem -LiteralPath $Destination -Force)
        if ($existing.Count -and -not (Test-Path -LiteralPath (Join-Path $Destination $marker))) {
            throw "$Destination exists and is not an OpenRelax install; nothing was changed. Choose another -Destination."
        }
        if ((Get-Item -LiteralPath $Destination -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "$Destination is a link; nothing was changed." }
        Write-Step "Replacing the earlier install in $Destination"
        foreach ($item in $existing) { Remove-InstallEntry $item }
    } else {
        [void][IO.Directory]::CreateDirectory($Destination)
    }
    Copy-Item -Path (Join-Path $source '*') -Destination $Destination -Recurse -Force
    [IO.File]::WriteAllText((Join-Path $Destination $marker), ('installed ' + (Get-Date).ToString('s') + ' from ' + $zipName))
    Write-Step "Installed to $Destination"

    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $app = Join-Path $Destination 'openrelax.ps1'
    # 5. Start menu shortcut.
    if (-not $NoShortcut) {
        $programs = [Environment]::GetFolderPath('Programs')
        $link = Join-Path $programs 'OpenRelax.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($link)
        $shortcut.TargetPath = $exe
        $shortcut.Arguments = '-STA -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "' + $app + '"'
        $shortcut.WorkingDirectory = $Destination
        $shortcut.IconLocation = (Join-Path $Destination 'docs\openrelax.ico') + ',0'
        $shortcut.Description = 'OpenRelax PC Care'
        $shortcut.WindowStyle = 7
        $shortcut.Save()
        Write-Step "Start menu shortcut: $link"
    }
    # 6. An existing start-with-Windows entry follows the new install.
    if (-not $NoStartup) {
        $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $entry = Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
        if ($entry -and $entry.PSObject.Properties['OpenRelax']) {
            Set-ItemProperty -LiteralPath $runKey -Name 'OpenRelax' -Value ('"' + $exe + '" -STA -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "' + $app + '" -StartMinimized')
            Write-Step 'Start-with-Windows now starts this install.'
        }
    }
    Write-Step 'Done. Open OpenRelax from the Start menu, or run:'
    Write-Host ('  powershell -STA -NoProfile -ExecutionPolicy Bypass -File "' + $app + '"')
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
