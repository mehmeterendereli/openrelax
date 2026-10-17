# Cleaning engine: pure functions shared by the GUI, the headless modes and the
# worker runspaces (serialized into $script:EngineCode). Windows PowerShell 5.1.
function Format-Bytes {
    param([long]$Bytes)
    if ([Math]::Abs([double]$Bytes) -ge 1GB) {
        return "$([Math]::Round($Bytes / 1GB, 2)) GB"
    } elseif ([Math]::Abs([double]$Bytes) -ge 1MB) {
        return "$([Math]::Round($Bytes / 1MB, 1)) MB"
    } elseif ([Math]::Abs([double]$Bytes) -ge 1KB) {
        return "$([Math]::Round($Bytes / 1KB, 0)) KB"
    } else {
        return "$Bytes B"
    }
}

# Categories of cleanable locations. Each path carries an Admin flag; admin-only
# paths are skipped entirely when not elevated. Deliberately NOT cleaned:
# Windows\Prefetch (speeds up app launches), Windows\Logs and Panther (needed
# for diagnostics and upgrade rollback).
function Get-JunkCategories {
    if ($env:OPENRELAX_FIXTURE_ROOT) {
        $cats = @()
        foreach ($key in 'temp','browser','discord','shader','wer','wu','gpusetup') {
            $cats += @{ Key = $key; Paths = @(@{ Path = (Join-Path $env:OPENRELAX_FIXTURE_ROOT $key); Admin = ($key -in @('wer','wu','gpusetup')); MinAgeHours = 24 }) }
        }
        $cats += @{ Key = 'recycle'; Paths = @() }
        foreach ($cat in $cats) { foreach ($target in $cat.Paths) { $target.ApprovedRoot = $env:OPENRELAX_FIXTURE_ROOT } }
        return , $cats
    }
    $cats = @()

    # Temp files (user temp, system temp, crash dumps)
    $p = @()
    # MinAgeHours: running apps (installers, dev/AI tools) keep working files
    # in temp; only files untouched for a day are considered junk.
    $tempWarnings = @()
    $knownTemp = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Temp'
    if (Test-Path -LiteralPath $knownTemp) { $p += @{ Path = $knownTemp; Admin = $false; MinAgeHours = 24 } }
    if ($env:TEMP -and -not ([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\').Equals($knownTemp.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase))) {
        $tempWarnings += 'Custom TEMP was skipped; only the known user Temp folder is approved.'
    }
    $sysTemp = Join-Path $env:windir 'Temp'
    if (Test-Path $sysTemp) { $p += @{ Path = $sysTemp; Admin = $true; MinAgeHours = 24 } }
    $crashDumps = Join-Path $env:LOCALAPPDATA 'CrashDumps'
    if (Test-Path $crashDumps) { $p += @{ Path = $crashDumps; Admin = $false } }
    $cats += @{ Key = 'temp'; Paths = $p; Warnings = $tempWarnings }

    # Browser caches - all Chromium profiles (Default + Profile N) and all cache types
    $p = @()
    $chromiumRoots = @(
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'),
        (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data')
    )
    foreach ($root in $chromiumRoots) {
        if (-not (Test-Path $root)) { continue }
        $profiles = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }
        foreach ($prof in $profiles) {
            foreach ($sub in 'Cache', 'Code Cache', 'GPUCache') {
                $c = Join-Path $prof.FullName $sub
                if (Test-Path $c) { $p += @{ Path = $c; Admin = $false } }
            }
        }
    }
    # Opera keeps the profile at the root of its folder
    $operaRoots = @(
        (Join-Path $env:LOCALAPPDATA 'Opera Software\Opera Stable'),
        (Join-Path $env:LOCALAPPDATA 'Opera Software\Opera GX Stable')
    )
    foreach ($root in $operaRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($sub in 'Cache', 'Code Cache', 'GPUCache') {
            $c = Join-Path $root $sub
            if (Test-Path $c) { $p += @{ Path = $c; Admin = $false } }
        }
    }
    # Firefox cache2 lives under LOCALAPPDATA (Roaming holds bookmarks/history - never touch)
    $ffRoot = Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'
    if (Test-Path $ffRoot) {
        foreach ($prof in (Get-ChildItem -LiteralPath $ffRoot -Directory -ErrorAction SilentlyContinue)) {
            $c = Join-Path $prof.FullName 'cache2'
            if (Test-Path $c) { $p += @{ Path = $c; Admin = $false } }
        }
    }
    $cats += @{ Key = 'browser'; Paths = $p }

    # Discord caches
    $p = @()
    $dRoot = Join-Path $env:APPDATA 'discord'
    if (Test-Path $dRoot) {
        foreach ($sub in 'Cache', 'Code Cache', 'GPUCache') {
            $c = Join-Path $dRoot $sub
            if (Test-Path $c) { $p += @{ Path = $c; Admin = $false } }
        }
    }
    $cats += @{ Key = 'discord'; Paths = $p }

    # GPU shader caches (regenerated automatically)
    $p = @()
    foreach ($c in @(
        (Join-Path $env:LOCALAPPDATA 'D3DSCache'),
        (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'),
        (Join-Path $env:LOCALAPPDATA 'AMD\DxCache')
    )) {
        if (Test-Path $c) { $p += @{ Path = $c; Admin = $false } }
    }
    $cats += @{ Key = 'shader'; Paths = $p }

    # Windows Error Reporting archives
    $p = @()
    foreach ($c in @(
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue')
    )) {
        if (Test-Path $c) { $p += @{ Path = $c; Admin = $true } }
    }
    $cats += @{ Key = 'wer'; Paths = $p }

    # Windows Update download cache (cleaned only while wuauserv/bits are stopped)
    $p = @()
    $wu = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
    if (Test-Path $wu) { $p += @{ Path = $wu; Admin = $true } }
    $cats += @{ Key = 'wu'; Paths = $p }

    # GPU installer leftovers
    $p = @()
    foreach ($c in @('C:\NVIDIA', 'C:\AMD', (Join-Path $env:ProgramData 'NVIDIA Corporation\NetService'))) {
        if (Test-Path $c) { $p += @{ Path = $c; Admin = $true } }
    }
    $cats += @{ Key = 'gpusetup'; Paths = $p }

    # Recycle Bin (handled specially via Shell COM / Clear-RecycleBin)
    $cats += @{ Key = 'recycle'; Paths = @() }

    foreach ($cat in $cats) { foreach ($target in $cat.Paths) { $target.ApprovedRoot = $target.Path } }
    return , $cats
}

# Walks a folder tree once for scanning, cleaning and disk analysis. It never
# enters or deletes reparse points (junctions, symlinks), so nothing outside
# the tree can be counted or removed; an unreadable folder is reported and
# skipped instead of ending the walk. It counts files last written before
# -Cutoff; with -Remove it deletes them (read-only ones too; locked ones are
# skipped) and then removes the folders left empty, deepest first, unless
# -KeepDirectories. A removing walk is approved once by Assert-CleanupPath;
# before a folder's files are deleted the folder chain up to the root is
# re-checked for a reparse point swapped in during the walk, and every file is
# re-read before it is deleted. The time budget and the progress beat are
# checked by elapsed time - per folder and every 2048 entries - so trees of
# empty folders can neither overrun the budget nor starve the watchdog. Inside
# a worker, $Sync is the task's shared hashtable (found through dynamic scope).
function Invoke-JunkWalk {
    param(
        [string]$Root,
        [string]$ApprovedRoot,
        [datetime]$Cutoff = [datetime]::MaxValue,
        [switch]$Remove,
        [switch]$KeepDirectories,
        [int]$BudgetMs = 0,
        [switch]$ByTopFolder
    )
    $r = @{ Size = [long]0; Count = [long]0; Dirs = [long]0; Partial = $false; Folders = @{}; Skipped = 0; ErrorCount = 0; Errors = @() }
    $reparse = [IO.FileAttributes]::ReparsePoint
    if ($Remove) {
        if (-not $ApprovedRoot) { throw 'Removal requires an approved root.' }
        Assert-CleanupPath $Root $ApprovedRoot
    }
    if (-not $Root -or -not [IO.Directory]::Exists($Root)) { return $r }
    if (-not $Remove) { Assert-NoReparseAncestors $Root }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $rootPrefix = $rootFull + '\'
    $sync = Get-Variable -Name Sync -ValueOnly -ErrorAction SilentlyContinue
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $nextBeat = [long]0; $sentCount = [long]0; $sentSize = [long]0; $n = 0
    $stack = New-Object 'System.Collections.Generic.Stack[object]'
    $stack.Push(@($rootFull, ''))
    $folders = New-Object 'System.Collections.Generic.List[string]'
    while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        $dir = [string]$item[0]; $top = [string]$item[1]
        $r.Dirs++
        $ms = $clock.ElapsedMilliseconds
        if ($BudgetMs -gt 0 -and $ms -gt $BudgetMs) { $r.Partial = $true; break }
        if ($sync -and $ms -ge $nextBeat) {
            $nextBeat = $ms + 250
            $sync.Beat = [DateTime]::UtcNow; $sync.Step = $dir; $sync.WalkInfo = @($r.Dirs, $top)
            if ($Remove) {
                $sync.CleanDone = [long]$sync.CleanDone + ($r.Count - $sentCount)
                $sync.CleanBytes = [long]$sync.CleanBytes + ($r.Size - $sentSize)
                $sentCount = $r.Count; $sentSize = $r.Size
            }
        }
        if ($Remove) {
            # A folder replaced by a junction after it was queued must not be entered.
            $swapped = $false
            $current = $dir
            try {
                while ($current.Length -ge $rootFull.Length) {
                    if ([IO.File]::GetAttributes($current) -band $reparse) { $swapped = $true; break }
                    if ($current.Length -eq $rootFull.Length) { break }
                    $current = [IO.Path]::GetDirectoryName($current)
                }
            } catch { $swapped = $true }
            if ($swapped) { $r.Skipped++; continue }
        }
        try { $entries = (New-Object System.IO.DirectoryInfo $dir).GetFileSystemInfos() }
        catch {
            $r.ErrorCount++
            if ($r.Errors.Count -lt 10) { $r.Errors += $_.Exception.Message }
            continue
        }
        foreach ($e in $entries) {
            if ((++$n % 2048) -eq 0 -and $BudgetMs -gt 0 -and $clock.ElapsedMilliseconds -gt $BudgetMs) { $r.Partial = $true; break }
            if (-not $e.FullName.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                $r.ErrorCount++; $r.Errors += 'Entry escaped its cleanup root.'; $r.Partial = $true; break
            }
            if ($e.Attributes -band $reparse) { $r.Skipped++; continue }
            $t = $top
            if ($e -is [IO.DirectoryInfo]) {
                if (-not $t) { $t = $e.Name }
                $stack.Push(@($e.FullName, $t))
                if ($Remove -and -not $KeepDirectories) { $folders.Add($e.FullName) }
                continue
            }
            if ($e.LastWriteTime -ge $Cutoff) { continue }
            if ($Remove) {
                try {
                    $e.Refresh()
                    if (-not $e.Exists -or ($e.Attributes -band $reparse) -or $e.LastWriteTime -ge $Cutoff) { continue }
                    if ($e.IsReadOnly) { $e.IsReadOnly = $false }
                    $len = $e.Length
                    $e.Delete()
                } catch { $r.Skipped++; continue }   # locked or in use
            } else { $len = $e.Length }
            $r.Size += $len; $r.Count++
            if ($ByTopFolder) { $r.Folders[$t] = [long]$r.Folders[$t] + $len }
        }
        if ($r.Partial) { break }
    }
    if ($Remove) {
        # Longer paths are deeper: children go before their parents; only empty ones go.
        foreach ($d in ($folders | Sort-Object -Property Length -Descending)) {
            try { if (-not ([IO.File]::GetAttributes($d) -band $reparse)) { [IO.Directory]::Delete($d) } } catch {}
        }
        if ($sync) {
            $sync.CleanDone = [long]$sync.CleanDone + ($r.Count - $sentCount)
            $sync.CleanBytes = [long]$sync.CleanBytes + ($r.Size - $sentSize)
        }
    }
    return $r
}

# BudgetSec > 0 caps the walk: a %TEMP% filled by dev/AI tooling can hold
# hundreds of thousands of folders and take minutes to enumerate. A capped scan
# returns a lower bound (Partial) instead of stalling.
function Measure-JunkPaths {
    param($Paths, [bool]$IsAdmin, [int]$BudgetSec = 0)
    $size = [long]0; $count = [long]0; $lockedSize = [long]0; $partial = $false; $errors = @()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    foreach ($target in $Paths) {
        if (-not (Test-Path -LiteralPath $target.Path)) { continue }
        try { Assert-CleanupPath $target.Path $target.ApprovedRoot }
        catch { $errors += $_.Exception.Message; continue }
        $cutoff = [datetime]::MaxValue
        if ($target.ContainsKey('MinAgeHours') -and $target.MinAgeHours) { $cutoff = (Get-Date).AddHours(-$target.MinAgeHours) }
        $left = 0
        if ($BudgetSec -gt 0) {
            $left = [int]($BudgetSec * 1000 - $clock.ElapsedMilliseconds)
            if ($left -le 0) { $partial = $true; break }
        }
        try { $w = Invoke-JunkWalk -Root $target.Path -Cutoff $cutoff -BudgetMs $left }
        catch { $errors += $_.Exception.Message; continue }
        if ($IsAdmin -or -not $target.Admin) { $size += $w.Size; $count += $w.Count } else { $lockedSize += $w.Size }
        $errors += @($w.Errors)
        if ($w.Partial) { $partial = $true; break }
    }
    return @{ Size = $size; Count = $count; LockedSize = $lockedSize; Partial = $partial; Errors = @($errors) }
}

# Reads $Recycle.Bin directly instead of Shell.Application COM automation:
# the COM object is created on a background STA runspace with no message
# pump, and its cross-apartment calls can block indefinitely waiting for an
# LPC reply that only a pumping thread would service.
function Get-RecycleBinInfo {
    if ($env:OPENRELAX_FIXTURE_ROOT) { return @{ Size = 0; Count = 0 } }
    $size = [long]0; $count = [long]0
    try {
        $sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
        $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }
        foreach ($drive in $drives) {
            $binPath = Join-Path (Join-Path $drive.RootDirectory.FullName '$Recycle.Bin') $sid
            if (Test-Path -LiteralPath $binPath) {
                Get-ChildItem -LiteralPath $binPath -File -Force -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notlike '$I*' } |
                    ForEach-Object { $size += $_.Length; $count++ }
            }
        }
    } catch {}
    return @{ Size = $size; Count = $count }
}

function Remove-JunkPaths {
    param($Paths, [bool]$IsAdmin)
    $bytes = [long]0; $count = [long]0
    $state = @{ Partial = $false; Skipped = 0; ErrorCount = 0; Errors = @() }
    foreach ($target in $Paths) {
        if ($target.Admin -and -not $IsAdmin) { $state.Skipped++; continue }
        try {
            if (-not (Test-Path -LiteralPath $target.Path -ErrorAction Stop)) { continue }
            Assert-CleanupPath $target.Path $target.ApprovedRoot
        } catch { $state.ErrorCount++; $state.Errors += $_.Exception.Message; continue }
        $cutoff = [datetime]::MaxValue
        $aged = $target.ContainsKey('MinAgeHours') -and $target.MinAgeHours
        if ($aged) { $cutoff = (Get-Date).AddHours(-$target.MinAgeHours) }
        try {
            # Temp directories may belong to active installers. Their small size does not justify removing them.
            $w = Invoke-JunkWalk -Root $target.Path -ApprovedRoot $target.ApprovedRoot -Cutoff $cutoff -Remove -KeepDirectories:$aged
        } catch { $state.ErrorCount++; $state.Errors += $_.Exception.Message; continue }
        $bytes += $w.Size; $count += $w.Count
        $state.Skipped += $w.Skipped
        $state.Errors += @($w.Errors)
    }
    return @{ Bytes = $bytes; Count = $count; Skipped = $state.Skipped; Errors = @($state.Errors) }
}

function Wait-ServiceState {
    param([string]$Name,[string]$State)
    $service = Get-Service -Name $Name -ErrorAction Stop
    if ([string]$service.Status -ne $State) {
        $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]$State,[TimeSpan]::FromSeconds(15))
        $service.Refresh()
    }
    if ([string]$service.Status -ne $State) { throw "$Name did not reach $State." }
}

function Invoke-WindowsUpdateCacheCleanup {
    param($Paths, [bool]$IsAdmin)
    if ($env:OPENRELAX_FIXTURE_ROOT) { return (Remove-JunkPaths $Paths $IsAdmin) }
    if (-not $IsAdmin) { throw 'Windows Update cache cleanup requires administrator privileges.' }
    $original = @{}
    # Validate all states before changing either service.
    foreach ($name in 'wuauserv','bits') {
        $state = [string](Get-Service -Name $name -ErrorAction Stop).Status
        if ($state -notin @('Running','Stopped')) { throw "$name is $state; Windows Update cleanup was refused." }
        $original[$name] = $state
    }
    $restartServices = @(); $restartErrors = @(); $removed = $null
    try {
        foreach ($name in 'wuauserv','bits') {
            if ($original[$name] -eq 'Running') {
                # Remember before attempting a stop that may throw after taking effect.
                $restartServices += $name
                # Refuse if running dependent services prevent a normal stop;
                # Force could stop extra services that this operation cannot restore.
                Stop-Service -Name $name -ErrorAction Stop
            }
            Wait-ServiceState $name 'Stopped'
        }
        $removed = Remove-JunkPaths -Paths $Paths -IsAdmin:$IsAdmin
        return $removed
    } finally {
        foreach ($name in $restartServices) {
            try {
                if ([string](Get-Service -Name $name -ErrorAction Stop).Status -ne 'Running') { Start-Service -Name $name -ErrorAction Stop }
                Wait-ServiceState $name 'Running'
            } catch { $restartErrors += "$name`: $($_.Exception.Message)" }
        }
        if ($restartErrors.Count) {
            $failure = [InvalidOperationException]::new("Windows Update service state could not be restored: $($restartErrors -join '; ')")
            if ($removed) { $failure.Data['MaintenanceResult'] = $removed }
            throw $failure
        }
    }
}

# Trims process working sets via EmptyWorkingSet. Skips critical system
# processes; the reclaimed number is transient by nature (pages return on use).
function Invoke-RamTrim {
    if ($env:OPENRELAX_FIXTURE_ROOT) { return @{ Success = 0; Fail = 0; Saved = 0 } }
    $skip = @('csrss', 'wininit', 'winlogon', 'lsass', 'services', 'smss', 'dwm',
              'fontdrvhost', 'Memory Compression', 'Registry', 'System', 'Idle', 'vmmem')
    $before = [Win32Helper]::GetMemoryStatus().ullAvailPhys
    $ok = 0; $fail = 0
    foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
        if ($proc.Id -eq $PID) { continue }
        if ($skip -contains $proc.ProcessName) { continue }
        try {
            $h = $proc.Handle
            if ($h -ne [IntPtr]::Zero) {
                if ([Win32Helper]::EmptyWorkingSet($h)) { $ok++ } else { $fail++ }
            }
        } catch {
            $fail++
        } finally {
            $proc.Dispose()
        }
    }
    Start-Sleep -Milliseconds 300
    $after = [Win32Helper]::GetMemoryStatus().ullAvailPhys
    $saved = [long]0
    $saved = [long]$after - [long]$before
    return @{ Success = $ok; Fail = $fail; Saved = $saved }
}
