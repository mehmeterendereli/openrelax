# Pure settings, path guards and shared maintenance orchestration. Windows PowerShell 5.1.
function Get-DefaultSettings {
    return @{
        schemaVersion = 2; language = 'tr'; autoBoost = $false; autoBoostLimit = 85
        closeToTray = $true; runAtStartup = $false; weeklyClean = $false
        trimRam = $false; clearDns = $false
        categories = @{ temp = $true; browser = $true; discord = $true; shader = $false; wer = $false; wu = $false; gpusetup = $false; recycle = $false }
        stats = @{ totalCleanedBytes = [long]0; totalRuns = 0; lastClean = '' }
    }
}

function Read-SettingsDocument {
    param([string]$Path)
    $result = @{ Valid = $false; Exists = $false; Settings = (Get-DefaultSettings); Error = '' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $result.Error = 'Settings file is missing.'; return $result }
    $result.Exists = $true
    try {
        $document = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $document -or $document -is [array] -or $document -is [string]) { throw 'Settings must be an object.' }
        foreach ($key in 'autoBoost','closeToTray','runAtStartup','weeklyClean') {
            if ($document.$key -isnot [bool]) { throw "Invalid boolean: $key" }
            $result.Settings[$key] = $document.$key
        }
        if ($document.language -isnot [string] -or $document.language -notin @('tr','en')) { throw 'Invalid language.' }
        if ($document.autoBoostLimit -isnot [int] -and $document.autoBoostLimit -isnot [long]) { throw 'Invalid RAM threshold type.' }
        if ($document.autoBoostLimit -notin @(70,75,80,85,90)) { throw 'Invalid RAM threshold.' }
        $result.Settings.language = $document.language
        $result.Settings.autoBoostLimit = [int]$document.autoBoostLimit
        foreach ($key in @($result.Settings.categories.Keys)) {
            if ($document.categories.$key -isnot [bool]) { throw "Invalid category: $key" }
            $result.Settings.categories[$key] = $document.categories.$key
        }
        foreach ($key in 'trimRam','clearDns') {
            if ($document.PSObject.Properties[$key]) {
                if ($document.$key -isnot [bool]) { throw "Invalid boolean: $key" }
                $result.Settings[$key] = $document.$key
            }
        }
        if ($document.PSObject.Properties['schemaVersion']) {
            if (($document.schemaVersion -isnot [int] -and $document.schemaVersion -isnot [long]) -or $document.schemaVersion -notin @(1,2)) { throw 'Unsupported settings schema.' }
        }
        foreach ($key in 'totalCleanedBytes','totalRuns') {
            $value = $document.stats.$key
            if (($value -isnot [int] -and $value -isnot [long]) -or $value -lt 0) { throw "Invalid statistic: $key" }
            if ($key -eq 'totalRuns' -and $value -gt [int]::MaxValue) { throw 'Run count is too large.' }
            $result.Settings.stats[$key] = $value
        }
        if ($document.stats.lastClean -isnot [string]) { throw 'Invalid last maintenance time.' }
        $result.Settings.stats.lastClean = $document.stats.lastClean
        $result.Valid = $true
    } catch {
        $result.Settings = Get-DefaultSettings
        $result.Error = $_.Exception.Message
    }
    return $result
}

function Write-SettingsAtomic {
    param([hashtable]$Settings, [string]$Path)
    $directory = Split-Path -Parent $Path
    [void][IO.Directory]::CreateDirectory($directory)
    $temporary = Join-Path $directory ('settings-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Settings | ConvertTo-Json -Depth 6))
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    # Failure leaves the previous valid file intact. Never fall back to truncating it.
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
    else { [IO.File]::Move($temporary, $Path) }
}

function Get-SettingsMutex {
    param([string]$Path, [ValidateSet('State','GUI')][string]$Scope = 'State')
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $key = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Path).ToUpperInvariant()))).Replace('-','') }
    finally { $sha.Dispose() }
    # Global namespace coordinates the same settings path across Windows sessions.
    # Grant only the current user and trusted system/admin principals access.
    $security = [Security.AccessControl.MutexSecurity]::new()
    $security.SetAccessRuleProtection($true,$false)
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $security.SetOwner($userSid)
    foreach ($sid in @($userSid.Value,'S-1-5-18','S-1-5-32-544') | Select-Object -Unique) {
        $security.AddAccessRule([Security.AccessControl.MutexAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),[Security.AccessControl.MutexRights]::FullControl,[Security.AccessControl.AccessControlType]::Allow))
    }
    $created = $false
    return [Threading.Mutex]::new($false, ('Global\OpenRelax-' + $Scope + '-' + $key),[ref]$created,$security)
}

function Save-Settings {
    $mutex = $null
    $acquired = $false
    try {
        $mutex = Get-SettingsMutex $script:SettingsFile
        try { $acquired = $mutex.WaitOne(5000) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Settings are in use by another instance.' }
        $latest = Read-SettingsDocument $script:SettingsFile
        if ($latest.Valid) { $script:Settings.stats = $latest.Settings.stats }
        Write-SettingsAtomic $script:Settings $script:SettingsFile
        $script:SettingsValid = $true
        return $true
    } catch {
        $script:SettingsError = $_.Exception.Message
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log ('Settings could not be saved: ' + $script:SettingsError) 'error' }
        else { Write-Warning ('Settings could not be saved: ' + $script:SettingsError) }
        return $false
    } finally { if ($acquired) { $mutex.ReleaseMutex() }; if ($mutex) { $mutex.Dispose() } }
}

function Update-MaintenanceStats {
    param([long]$Bytes)
    $mutex = Get-SettingsMutex $script:SettingsFile
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(5000) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Settings are in use by another instance.' }
        $latest = Read-SettingsDocument $script:SettingsFile
        if ($latest.Exists -and -not $latest.Valid) { throw 'Maintenance statistics cannot overwrite invalid settings.' }
        $settings = if ($latest.Valid) { $latest.Settings } else { $script:Settings }
        if ($Bytes -lt 0 -or $settings.stats.totalCleanedBytes -gt ([long]::MaxValue - $Bytes)) { throw 'Invalid maintenance byte count.' }
        $settings.stats.totalCleanedBytes = [long]$settings.stats.totalCleanedBytes + $Bytes
        if ($settings.stats.totalRuns -ge [int]::MaxValue) { throw 'Maintenance run count would overflow.' }
        $settings.stats.totalRuns = [int]$settings.stats.totalRuns + 1
        $settings.stats.lastClean = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        Write-SettingsAtomic $settings $script:SettingsFile
        $script:Settings.stats = $settings.stats
        $script:SettingsValid = $true
    } finally { if ($acquired) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}

function Test-PathWithin {
    param([string]$Path, [string]$Root)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    return $full.Equals($base, [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparseAncestors {
    param([string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current -ErrorAction Stop) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'A cleanup path or ancestor is a reparse point.' }
        }
        $parent = [IO.Directory]::GetParent($current)
        if (-not $parent) { break }
        $current = $parent.FullName
    }
}

function Assert-CleanupPath {
    param([string]$Path, [string]$AllowedRoot)
    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path.StartsWith('\\')) { throw 'Cleanup requires an absolute local filesystem path.' }
    $full = [IO.Path]::GetFullPath($Path)
    $volume = [IO.Path]::GetPathRoot($full)
    if ($full.TrimEnd('\').Equals($volume.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'A volume root cannot be cleaned.' }
    foreach ($folder in 'Windows','ProgramFiles','ProgramFilesX86','CommonApplicationData','UserProfile','Desktop','MyDocuments','MyPictures','ApplicationData','LocalApplicationData') {
        $protected = [Environment]::GetFolderPath($folder)
        if ($protected -and (Test-PathWithin $protected $full)) { throw 'A protected folder or its ancestor cannot be cleaned.' }
    }
    if (-not $AllowedRoot -or -not (Test-PathWithin $full $AllowedRoot)) { throw 'Cleanup target is outside its approved root.' }
    Assert-NoReparseAncestors $full
}

function Get-SafeTreeEntries {
    param([string]$Path, [hashtable]$State, [int]$BudgetSec = 0)
    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push($Path)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($stack.Count) {
        if ($BudgetSec -gt 0 -and $clock.Elapsed.TotalSeconds -ge $BudgetSec) { $State.Partial = $true; return }
        $directory = $stack.Pop()
        $syncState = Get-Variable Sync -ValueOnly -ErrorAction SilentlyContinue
        if ($syncState) { $syncState.Beat = [DateTime]::UtcNow; $syncState.Step = $directory }
        try {
            Assert-NoReparseAncestors $directory
            $current = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
            if ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) { $State.Skipped++; continue }
            foreach ($entry in (Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)) {
                if ($BudgetSec -gt 0 -and $clock.Elapsed.TotalSeconds -ge $BudgetSec) { $State.Partial = $true; return }
                if (-not (Test-PathWithin $entry.FullName $Path)) { throw 'Entry escaped its cleanup root.' }
                if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { $State.Skipped++; continue }
                $entry
                if ($entry.PSIsContainer) { $stack.Push($entry.FullName) }
            }
        } catch {
            $State.ErrorCount++
            if ($State.Errors.Count -lt 10) { $State.Errors += $_.Exception.Message }
        }
    }
}

function Assert-TestFixture {
    param([string]$Path)
    Assert-CleanupPath $Path $Path
    $markerPath = Join-Path $Path '.openrelax-test-workspace'
    $marker = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($marker.kind -ne 'OpenRelaxTestWorkspace' -or $marker.owner -notmatch '^[a-f0-9]{32}$' -or -not ([IO.Path]::GetFullPath($marker.path).Equals([IO.Path]::GetFullPath($Path),[StringComparison]::OrdinalIgnoreCase))) {
        throw 'TestMode requires an owned synthetic workspace.'
    }
}

function Invoke-Maintenance {
    param([hashtable]$Options)
    foreach ($key in 'Headless','Confirmed','TrimRam','ClearDns','IsAdmin') {
        if (-not $Options.ContainsKey($key)) { $Options[$key] = $false }
    }
    if (-not $Options.ContainsKey('Keys')) { $Options.Keys = @() }
    $result = @{ Bytes = [long]0; Count = [long]0; Skipped = 0; Errors = @(); Status = 'Success'; Ram = $null }
    $restricted = @('recycle','wu','wer','gpusetup','shader')
    if (-not $Options.Headless -and -not $Options.Confirmed) { throw 'Interactive maintenance requires confirmation.' }
    foreach ($category in (Get-JunkCategories)) {
        if ($Options.Keys -notcontains $category.Key) { continue }
        if ($category.ContainsKey('Warnings') -and $category.Warnings) { $result.Errors += @($category.Warnings) }
        if ($Options.Headless -and $category.Key -in $restricted) { $result.Skipped++; continue }
        try {
            if ($category.Key -eq 'recycle') {
                if ($env:OPENRELAX_FIXTURE_ROOT) { $result.Skipped++; continue }
                $before = Get-RecycleBinInfo
                Clear-RecycleBin -Force -ErrorAction Stop
                $result.Bytes += $before.Size; $result.Count += $before.Count
                continue
            }
            if ($category.Key -eq 'wu') {
                if (-not $Options.IsAdmin) { $result.Skipped++; continue }
                $removed = Invoke-WindowsUpdateCacheCleanup -Paths $category.Paths -IsAdmin:$Options.IsAdmin
            } else { $removed = Remove-JunkPaths -Paths $category.Paths -IsAdmin:$Options.IsAdmin }
            $result.Bytes += $removed.Bytes; $result.Count += $removed.Count
            $result.Skipped += $removed.Skipped
            $result.Errors += @($removed.Errors)
        } catch {
            $result.Errors += $_.Exception.Message
            # Service restoration can fail after files were removed. Keep that
            # completed work visible instead of claiming that nothing changed.
            $completed = $_.Exception.Data['MaintenanceResult']
            if ($completed) {
                $result.Bytes += $completed.Bytes; $result.Count += $completed.Count
                $result.Skipped += $completed.Skipped; $result.Errors += @($completed.Errors)
            }
        }
    }
    if ($Options.TrimRam -and -not $Options.Headless) {
        try { $result.Ram = Invoke-RamTrim; if ($result.Ram.Fail -gt 0) { $result.Skipped += $result.Ram.Fail } }
        catch { $result.Errors += $_.Exception.Message }
    }
    if ($Options.ClearDns -and -not $Options.Headless -and -not $env:OPENRELAX_FIXTURE_ROOT) {
        try { Clear-DnsClientCache -ErrorAction Stop } catch { $result.Errors += $_.Exception.Message }
    }
    if ($result.Errors.Count -gt 0) { $result.Status = if ($result.Count -gt 0) { 'Partial' } else { 'Failed' } }
    elseif ($result.Skipped -gt 0) { $result.Status = 'Partial' }
    return $result
}
