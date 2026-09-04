# OpenRelax PC Care v2.0 - PowerShell WinForms system care utility
# Modes: default = GUI | -AutoClean = headless scheduled cleanup | -SelfTest = read-only engine scan
param(
    [switch]$AutoClean,
    [switch]$StartMinimized,
    [switch]$SelfTest
)

$script:AppVersion   = '2.0'
$script:ScriptPath   = $PSCommandPath
$script:SettingsDir  = Join-Path $env:APPDATA 'OpenRelax'
$script:SettingsFile = Join-Path $script:SettingsDir 'settings.json'
$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

#region 1. Settings (persisted to %APPDATA%\OpenRelax\settings.json)
function Get-DefaultSettings {
    return @{
        language       = 'tr'
        autoBoost      = $false
        autoBoostLimit = 85
        closeToTray    = $true
        runAtStartup   = $false
        weeklyClean    = $false
        categories     = @{
            temp     = $true
            browser  = $true
            discord  = $true
            shader   = $true
            wer      = $true
            wu       = $false   # off by default: requires stopping Windows Update service
            gpusetup = $true
            recycle  = $true
        }
        stats          = @{
            totalCleanedBytes = 0
            totalRuns         = 0
            lastClean         = ''
        }
    }
}

function Load-Settings {
    $s = Get-DefaultSettings
    if (Test-Path $script:SettingsFile) {
        try {
            $json = Get-Content $script:SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $json.PSObject.Properties) {
                if (-not $s.ContainsKey($prop.Name)) { continue }
                if ($s[$prop.Name] -is [hashtable]) {
                    foreach ($sub in $prop.Value.PSObject.Properties) {
                        if ($s[$prop.Name].ContainsKey($sub.Name)) { $s[$prop.Name][$sub.Name] = $sub.Value }
                    }
                } else {
                    $s[$prop.Name] = $prop.Value
                }
            }
        } catch {}
    }
    return $s
}

function Save-Settings {
    try {
        if (-not (Test-Path $script:SettingsDir)) { New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null }
        $script:Settings | ConvertTo-Json -Depth 5 | Set-Content -Path $script:SettingsFile -Encoding UTF8
    } catch {}
}

$script:Settings = Load-Settings
#endregion

#region 2. Localization (TR / EN string table)
$script:Strings = @{
    tr = @{
        navDash          = 'Panel'
        navSettings      = 'Ayarlar'
        navDisk          = 'Disk Analizi'
        ramTitle         = 'BELLEK (RAM) DURUMU'
        ramDesc          = 'Sistem bellek doluluğu ve kullanım detayları.'
        cpuTitle         = 'İŞLEMCİ (CPU) DALGASI'
        cpuDesc          = 'İşlemci Anlık Yük'
        sysTitle         = 'SİSTEM DETAYLARI'
        uptime           = 'Çalışma Süresi:'
        uptimeFmt        = '{0}g {1}s {2}d'
        procCount        = 'İşlem Sayısı:'
        junkFiles        = 'Geçici Dosya:'
        scanning         = 'Taranıyor...'
        calculating      = 'Hesaplanıyor...'
        cleanState       = 'Temiz'
        headerTitle      = 'Sistem Bakımı ve Temizlik'
        headerSub        = 'Tek butonla seçili kategorilerdeki önbellekleri ve disk çöplerini temizleyin, RAM bellek alanlarını boşaltın.'
        btnOneClick      = 'Tek Tıkla Sistem Bakımı Yap'
        btnCleaning      = 'Temizleniyor...'
        statusAdmin      = 'Durum: Yönetici Modu'
        statusUser       = 'Durum: Kullanıcı Modu'
        statusBusy       = 'Durum: Çalışıyor...'
        autoBoost        = 'Oto RAM Boşalt:'
        limit            = 'Sınır:'
        cat_temp         = 'Geçici Dosyalar'
        cat_browser      = 'Tarayıcı Önbellekleri'
        cat_discord      = 'Discord Önbelleği'
        cat_shader       = 'GPU Shader Önbelleği'
        cat_wer          = 'Hata Raporları (WER)'
        cat_wu           = 'Windows Update Önbelleği'
        cat_gpusetup     = 'GPU Kurulum Kalıntıları'
        cat_recycle      = 'Geri Dönüşüm Kutusu'
        adminRequired    = '(yönetici gerekli)'
        settingsCats     = 'TEMİZLİK KATEGORİLERİ'
        settingsGeneral  = 'GENEL AYARLAR'
        settingsStats    = 'İSTATİSTİKLER'
        optCloseTray     = 'Kapatınca sistem tepsisine küçült'
        optStartup       = 'Windows ile başlat'
        optWeekly        = 'Haftalık otomatik temizlik (Pazar 12:00)'
        language         = 'Dil:'
        btnElevate       = 'Yönetici Olarak Yeniden Başlat'
        statTotal        = 'Toplam temizlenen:'
        statRuns         = 'Bakım sayısı:'
        statLast         = 'Son bakım:'
        never            = 'Henüz yok'
        diskTitle        = 'EN BÜYÜK KLASÖRLER'
        diskDesc         = 'Kullanıcı profilinizde en çok yer kaplayan klasörler (salt okunur analiz).'
        btnAnalyze       = 'Analiz Et'
        analyzing        = 'Analiz...'
        colFolder        = 'Klasör'
        colSize          = 'Boyut'
        trayShow         = 'Göster'
        trayClean        = 'Bakım Yap'
        trayExit         = 'Çıkış'
        trayBalloon      = 'OpenRelax arka planda çalışmaya devam ediyor. Çıkmak için tepsi simgesine sağ tıklayın.'
        logStart         = 'Sistem taraması başlatıldı...'
        logAdminOn       = 'Yönetici yetkileri aktif (Tam Sistem Temizliği).'
        logAdminOff      = 'Normal yetkiler ile çalışıyor (bazı sistem alanları atlanır).'
        logScanDone      = 'Tarama bitti: {0} dosya ({1}) temizlenebilir.'
        logScanAdminExtra= 'Ek {0} için yönetici yetkisi gerekiyor.'
        logCleanStart    = 'Geçici dosyalar temizleniyor...'
        logCleanDone     = 'Temizlik tamamlandı: {0} dosya silindi ({1}).'
        logRamStart      = 'Bellek (RAM) optimizasyonu başlatıldı...'
        logRamDone       = 'RAM boşaltıldı: {0} geçici olarak geri kazanıldı.'
        logRamNone       = 'Bellek zaten optimum seviyede.'
        logRecycleDone   = 'Geri Dönüşüm Kutusu boşaltıldı.'
        logDnsDone       = 'DNS önbelleği temizlendi.'
        logAllDone       = 'Tüm bakım işlemleri tamamlandı!'
        logAutoBoost     = 'RAM %{0} eşiğini aştı - otomatik boşaltma yapılıyor.'
        logWuStopped     = 'Windows Update servisi geçici olarak durduruldu.'
        logWuStarted     = 'Windows Update servisi yeniden başlatıldı.'
        logMaintStart    = 'Tek Tık Bakım başlatıldı...'
        logError         = 'Hata: {0}'
        logBusy          = 'Devam eden bir işlem var, lütfen bekleyin.'
        logDiskStart     = 'Klasör boyutları hesaplanıyor...'
        logDiskDone      = 'Analiz bitti: {0} klasör tarandı.'
        logTaskCreated   = 'Haftalık temizlik görevi oluşturuldu.'
        logTaskRemoved   = 'Haftalık temizlik görevi kaldırıldı.'
        logTaskError     = 'Zamanlanmış görev işlemi başarısız: {0}'
        logStartupOn     = 'Windows başlangıcına eklendi.'
        logStartupOff    = 'Windows başlangıcından kaldırıldı.'
        logTickError     = 'İzleme hatası: {0}'
        logStats         = 'Bugüne kadar toplam {0} temizlendi ({1} bakım).'
        logCpuFail       = 'CPU sayacı başlatılamadı, CPU grafiği devre dışı.'
        logElevateFail   = 'Yönetici olarak başlatma iptal edildi.'
    }
    en = @{
        navDash          = 'Dashboard'
        navSettings      = 'Settings'
        navDisk          = 'Disk Analysis'
        ramTitle         = 'MEMORY (RAM) STATUS'
        ramDesc          = 'System memory load and usage details.'
        cpuTitle         = 'CPU WAVE'
        cpuDesc          = 'Current CPU Load'
        sysTitle         = 'SYSTEM DETAILS'
        uptime           = 'Uptime:'
        uptimeFmt        = '{0}d {1}h {2}m'
        procCount        = 'Processes:'
        junkFiles        = 'Junk Files:'
        scanning         = 'Scanning...'
        calculating      = 'Calculating...'
        cleanState       = 'Clean'
        headerTitle      = 'System Maintenance & Cleanup'
        headerSub        = 'Clean caches and disk junk in the selected categories and trim RAM working sets with a single click.'
        btnOneClick      = 'Run One-Click Maintenance'
        btnCleaning      = 'Cleaning...'
        statusAdmin      = 'Status: Administrator Mode'
        statusUser       = 'Status: User Mode'
        statusBusy       = 'Status: Working...'
        autoBoost        = 'Auto RAM Boost:'
        limit            = 'Limit:'
        cat_temp         = 'Temp Files'
        cat_browser      = 'Browser Caches'
        cat_discord      = 'Discord Cache'
        cat_shader       = 'GPU Shader Cache'
        cat_wer          = 'Error Reports (WER)'
        cat_wu           = 'Windows Update Cache'
        cat_gpusetup     = 'GPU Installer Leftovers'
        cat_recycle      = 'Recycle Bin'
        adminRequired    = '(admin required)'
        settingsCats     = 'CLEANUP CATEGORIES'
        settingsGeneral  = 'GENERAL SETTINGS'
        settingsStats    = 'STATISTICS'
        optCloseTray     = 'Minimize to tray on close'
        optStartup       = 'Run at Windows startup'
        optWeekly        = 'Weekly automatic cleanup (Sun 12:00)'
        language         = 'Language:'
        btnElevate       = 'Restart as Administrator'
        statTotal        = 'Total cleaned:'
        statRuns         = 'Maintenance runs:'
        statLast         = 'Last cleanup:'
        never            = 'Not yet'
        diskTitle        = 'LARGEST FOLDERS'
        diskDesc         = 'Folders taking the most space in your user profile (read-only analysis).'
        btnAnalyze       = 'Analyze'
        analyzing        = 'Analyzing...'
        colFolder        = 'Folder'
        colSize          = 'Size'
        trayShow         = 'Show'
        trayClean        = 'Run Maintenance'
        trayExit         = 'Exit'
        trayBalloon      = 'OpenRelax keeps running in the background. Right-click the tray icon to exit.'
        logStart         = 'System scan started...'
        logAdminOn       = 'Administrator privileges active (full system cleanup).'
        logAdminOff      = 'Running without admin rights (some system areas are skipped).'
        logScanDone      = 'Scan finished: {0} files ({1}) cleanable.'
        logScanAdminExtra= 'An additional {0} requires administrator rights.'
        logCleanStart    = 'Cleaning junk files...'
        logCleanDone     = 'Cleanup finished: {0} files deleted ({1}).'
        logRamStart      = 'RAM optimization started...'
        logRamDone       = 'RAM trimmed: {0} temporarily reclaimed.'
        logRamNone       = 'Memory already at an optimal level.'
        logRecycleDone   = 'Recycle Bin emptied.'
        logDnsDone       = 'DNS cache flushed.'
        logAllDone       = 'All maintenance tasks finished!'
        logAutoBoost     = 'RAM exceeded the {0}% threshold - auto boosting.'
        logWuStopped     = 'Windows Update service temporarily stopped.'
        logWuStarted     = 'Windows Update service restarted.'
        logMaintStart    = 'One-click maintenance started...'
        logError         = 'Error: {0}'
        logBusy          = 'A task is already running, please wait.'
        logDiskStart     = 'Calculating folder sizes...'
        logDiskDone      = 'Analysis finished: {0} folders scanned.'
        logTaskCreated   = 'Weekly cleanup task registered.'
        logTaskRemoved   = 'Weekly cleanup task removed.'
        logTaskError     = 'Scheduled task operation failed: {0}'
        logStartupOn     = 'Added to Windows startup.'
        logStartupOff    = 'Removed from Windows startup.'
        logTickError     = 'Monitor error: {0}'
        logStats         = '{0} cleaned so far across {1} maintenance runs.'
        logCpuFail       = 'CPU counter could not start, CPU graph disabled.'
        logElevateFail   = 'Elevation was cancelled.'
    }
}

function T {
    param([string]$Key)
    $lang = $script:Settings.language
    $tbl = $script:Strings[$lang]
    if (-not $tbl) { $tbl = $script:Strings['tr'] }
    $v = $tbl[$Key]
    if (-not $v) { $v = $script:Strings['tr'][$Key] }
    if (-not $v) { $v = $Key }
    return $v
}
#endregion

#region 3. Cleaning engine (pure functions - also injected into background runspaces)
function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) {
        return "$([Math]::Round($Bytes / 1GB, 2)) GB"
    } elseif ($Bytes -ge 1MB) {
        return "$([Math]::Round($Bytes / 1MB, 1)) MB"
    } elseif ($Bytes -ge 1KB) {
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
    $cats = @()

    # Temp files (user temp, system temp, crash dumps)
    $p = @()
    if (Test-Path $env:TEMP) { $p += @{ Path = $env:TEMP; Admin = $false } }
    $sysTemp = Join-Path $env:windir 'Temp'
    if (Test-Path $sysTemp) { $p += @{ Path = $sysTemp; Admin = $true } }
    $crashDumps = Join-Path $env:LOCALAPPDATA 'CrashDumps'
    if (Test-Path $crashDumps) { $p += @{ Path = $crashDumps; Admin = $false } }
    $cats += @{ Key = 'temp'; Paths = $p }

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

    return , $cats
}

function Measure-JunkPaths {
    param($Paths, [bool]$IsAdmin)
    $size = [long]0; $count = [long]0; $lockedSize = [long]0
    foreach ($p in $Paths) {
        $accessible = $IsAdmin -or (-not $p.Admin)
        try {
            Get-ChildItem -LiteralPath $p.Path -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if ($accessible) { $size += $_.Length; $count++ } else { $lockedSize += $_.Length }
            }
        } catch {}
    }
    return @{ Size = $size; Count = $count; LockedSize = $lockedSize }
}

function Get-RecycleBinInfo {
    $size = [long]0; $count = [long]0
    try {
        $sh = New-Object -ComObject Shell.Application
        $bin = $sh.NameSpace(0x0A)
        if ($bin) {
            foreach ($item in @($bin.Items())) {
                $size += [long]$item.Size
                $count++
            }
        }
    } catch {}
    return @{ Size = $size; Count = $count }
}

function Remove-JunkPaths {
    param($Paths, [bool]$IsAdmin)
    $bytes = [long]0; $count = [long]0
    foreach ($p in $Paths) {
        if ($p.Admin -and -not $IsAdmin) { continue }
        $items = Get-ChildItem -LiteralPath $p.Path -Recurse -Force -ErrorAction SilentlyContinue
        $files = $items | Where-Object { -not $_.PSIsContainer }
        $dirs = $items | Where-Object { $_.PSIsContainer } |
            Sort-Object -Property @{ Expression = { $_.FullName.Length } } -Descending
        foreach ($f in $files) {
            try {
                $len = $f.Length
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $bytes += $len; $count++
            } catch {
                # Locked or in-use file - skip silently
            }
        }
        foreach ($d in $dirs) {
            try {
                if (-not (Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)) {
                    Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
    }
    return @{ Bytes = $bytes; Count = $count }
}

function Invoke-WindowsUpdateCacheCleanup {
    param($Paths, [bool]$IsAdmin)

    if (-not $IsAdmin) {
        throw 'Windows Update cache cleanup requires administrator privileges.'
    }

    $restartServices = @()
    $restartErrors = @()
    try {
        foreach ($name in 'wuauserv', 'bits') {
            $service = Get-Service -Name $name -ErrorAction Stop
            if ($service.Status -eq 'Running') {
                Stop-Service -Name $name -Force -ErrorAction Stop
                $restartServices += $name
            }
        }

        return Remove-JunkPaths -Paths $Paths -IsAdmin:$IsAdmin
    } finally {
        foreach ($name in $restartServices) {
            try {
                Start-Service -Name $name -ErrorAction Stop
            } catch {
                $restartErrors += "$name`: $($_.Exception.Message)"
            }
        }

        if ($restartErrors.Count -gt 0) {
            throw "Windows Update service state could not be restored: $($restartErrors -join '; ')"
        }
    }
}

# Trims process working sets via EmptyWorkingSet. Skips critical system
# processes; the reclaimed number is transient by nature (pages return on use).
function Invoke-RamTrim {
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
    if ($after -gt $before) { $saved = [long]($after - $before) }
    return @{ Success = $ok; Fail = $fail; Saved = $saved }
}

# Serialized engine source, injected into every background runspace so the
# worker and the UI share a single implementation.
$script:EngineCode = ''
foreach ($fnName in 'Format-Bytes', 'Get-JunkCategories', 'Measure-JunkPaths', 'Get-RecycleBinInfo', 'Remove-JunkPaths', 'Invoke-WindowsUpdateCacheCleanup', 'Invoke-RamTrim') {
    $script:EngineCode += "function $fnName {`n" + (Get-Command $fnName).Definition + "`n}`n"
}
#endregion

#region 4. Background task scripts (run inside worker runspaces)
# Each receives ($Sync, $Opt). Logs are queued as hashtables and rendered by the
# UI pump timer; results land in $Sync.<X>Result fields.
$script:ScanTaskCode = @'
param($Sync, $Opt)
try {
    $cats = Get-JunkCategories
    $results = @{}
    $totalSize = [long]0; $totalCount = [long]0; $lockedSize = [long]0
    foreach ($cat in $cats) {
        if ($cat.Key -eq 'recycle') {
            $info = Get-RecycleBinInfo
            $results[$cat.Key] = @{ Size = $info.Size; Count = $info.Count }
            $totalSize += $info.Size; $totalCount += $info.Count
        } else {
            $m = Measure-JunkPaths -Paths $cat.Paths -IsAdmin:$Opt.IsAdmin
            $results[$cat.Key] = @{ Size = $m.Size; Count = $m.Count }
            $totalSize += $m.Size; $totalCount += $m.Count; $lockedSize += $m.LockedSize
        }
    }
    $Sync.ScanResult = @{ Categories = $results; TotalSize = $totalSize; FileCount = $totalCount; LockedSize = $lockedSize }
} catch {
    $Sync.Log.Enqueue(@{ Text = "Scan error: $($_.Exception.Message)"; Type = 'error' })
    $Sync.ScanResult = @{ Categories = @{}; TotalSize = 0; FileCount = 0; LockedSize = 0 }
}
'@

$script:CleanTaskCode = @'
param($Sync, $Opt)
try {
    $Sync.Log.Enqueue(@{ Key = 'logRamStart'; Type = 'info' })
    $ram = Invoke-RamTrim
    if ($ram.Saved -gt 0) {
        $Sync.Log.Enqueue(@{ Key = 'logRamDone'; Args = @((Format-Bytes $ram.Saved)); Type = 'success' })
    } else {
        $Sync.Log.Enqueue(@{ Key = 'logRamNone'; Type = 'info' })
    }

    $Sync.Log.Enqueue(@{ Key = 'logCleanStart'; Type = 'info' })
    $cats = Get-JunkCategories
    $deletedBytes = [long]0; $deletedCount = [long]0
    foreach ($cat in $cats) {
        if ($Opt.Keys -notcontains $cat.Key) { continue }
        if ($cat.Key -eq 'recycle') {
            try {
                Clear-RecycleBin -Force -ErrorAction Stop
                $Sync.Log.Enqueue(@{ Key = 'logRecycleDone'; Type = 'success' })
            } catch {}
            continue
        }
        if ($cat.Key -eq 'wu') {
            if (-not $Opt.IsAdmin) { continue }
            try {
                $Sync.Log.Enqueue(@{ Key = 'logWuStopped'; Type = 'info' })
                $r = Invoke-WindowsUpdateCacheCleanup -Paths $cat.Paths -IsAdmin:$Opt.IsAdmin
                $deletedBytes += $r.Bytes; $deletedCount += $r.Count
                $Sync.Log.Enqueue(@{ Key = 'logWuStarted'; Type = 'info' })
            } catch {
                $Sync.Log.Enqueue(@{ Text = "Windows Update cleanup skipped: $($_.Exception.Message)"; Type = 'error' })
            }
            continue
        }
        $r = Remove-JunkPaths -Paths $cat.Paths -IsAdmin:$Opt.IsAdmin
        $deletedBytes += $r.Bytes; $deletedCount += $r.Count
    }
    try {
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        $Sync.Log.Enqueue(@{ Key = 'logDnsDone'; Type = 'success' })
    } catch {}
    $Sync.CleanResult = @{ Bytes = $deletedBytes; Count = $deletedCount }
} catch {
    $Sync.Log.Enqueue(@{ Text = "Clean error: $($_.Exception.Message)"; Type = 'error' })
    $Sync.CleanResult = @{ Bytes = 0; Count = 0 }
}
'@

$script:RamTaskCode = @'
param($Sync, $Opt)
try {
    $ram = Invoke-RamTrim
    $Sync.RamResult = @{ Saved = $ram.Saved }
} catch {
    $Sync.Log.Enqueue(@{ Text = "RAM task error: $($_.Exception.Message)"; Type = 'error' })
    $Sync.RamResult = @{ Saved = 0 }
}
'@

$script:DiskTaskCode = @'
param($Sync, $Opt)
try {
    $rows = @()
    $dirs = Get-ChildItem -LiteralPath $Opt.Target -Directory -Force -ErrorAction SilentlyContinue
    foreach ($d in $dirs) {
        $sz = [long]0
        Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $sz += $_.Length }
        $rows += @{ Name = $d.Name; Size = $sz }
    }
    $top = $rows | Sort-Object -Property @{ Expression = { $_.Size } } -Descending | Select-Object -First 10
    $Sync.DiskResult = @{ Rows = @($top); Count = @($dirs).Count }
} catch {
    $Sync.Log.Enqueue(@{ Text = "Disk analysis error: $($_.Exception.Message)"; Type = 'error' })
    $Sync.DiskResult = @{ Rows = @(); Count = 0 }
}
'@
#endregion

#region 5. Windows integration helpers (startup entry, weekly scheduled task)
$script:PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Set-StartupEntry {
    param([bool]$Enable)
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    try {
        if ($Enable) {
            $cmd = "`"$script:PsExe`" -STA -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$script:ScriptPath`" -StartMinimized"
            Set-ItemProperty -Path $runKey -Name 'OpenRelax' -Value $cmd
            return @{ Ok = $true; Key = 'logStartupOn' }
        } else {
            Remove-ItemProperty -Path $runKey -Name 'OpenRelax' -ErrorAction SilentlyContinue
            return @{ Ok = $true; Key = 'logStartupOff' }
        }
    } catch {
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}

function Set-WeeklyTask {
    param([bool]$Enable)
    $taskName = 'OpenRelax Weekly Clean'
    try {
        if ($Enable) {
            $action = New-ScheduledTaskAction -Execute $script:PsExe -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$script:ScriptPath`" -AutoClean"
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '12:00'
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Force | Out-Null
            return @{ Ok = $true; Key = 'logTaskCreated' }
        } else {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            return @{ Ok = $true; Key = 'logTaskRemoved' }
        }
    } catch {
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}
#endregion

#region 6. Headless modes (-AutoClean / -SelfTest) - no GUI is loaded
if ($AutoClean) {
    $logFile = Join-Path $script:SettingsDir 'autoclean.log'
    if (-not (Test-Path $script:SettingsDir)) { New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null }
    $enabledKeys = @()
    foreach ($k in $script:Settings.categories.Keys) {
        if ($script:Settings.categories[$k]) { $enabledKeys += $k }
    }
    $bytes = [long]0; $count = [long]0
    foreach ($cat in (Get-JunkCategories)) {
        if ($enabledKeys -notcontains $cat.Key) { continue }
        if ($cat.Key -eq 'recycle') {
            try { Clear-RecycleBin -Force -ErrorAction Stop } catch {}
            continue
        }
        if ($cat.Key -eq 'wu') {
            if (-not $script:IsAdmin) { continue }
            try {
                $r = Invoke-WindowsUpdateCacheCleanup -Paths $cat.Paths -IsAdmin:$script:IsAdmin
                $bytes += $r.Bytes; $count += $r.Count
            } catch {}
            continue
        }
        $r = Remove-JunkPaths -Paths $cat.Paths -IsAdmin:$script:IsAdmin
        $bytes += $r.Bytes; $count += $r.Count
    }
    try { Clear-DnsClientCache -ErrorAction SilentlyContinue } catch {}
    $script:Settings.stats.totalCleanedBytes = [long]$script:Settings.stats.totalCleanedBytes + $bytes
    $script:Settings.stats.totalRuns = [int]$script:Settings.stats.totalRuns + 1
    $script:Settings.stats.lastClean = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    Save-Settings
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') AutoClean: $count files deleted ($(Format-Bytes $bytes))"
    exit 0
}

if ($SelfTest) {
    Write-Host "OpenRelax v$script:AppVersion self-test (read-only scan)"
    Write-Host "Admin: $script:IsAdmin | Settings: $script:SettingsFile"
    $grandSize = [long]0; $grandCount = [long]0; $grandLocked = [long]0
    foreach ($cat in (Get-JunkCategories)) {
        if ($cat.Key -eq 'recycle') {
            $info = Get-RecycleBinInfo
            Write-Host ("  {0,-10} {1,10}  ({2} items)" -f $cat.Key, (Format-Bytes $info.Size), $info.Count)
            $grandSize += $info.Size; $grandCount += $info.Count
        } else {
            $m = Measure-JunkPaths -Paths $cat.Paths -IsAdmin:$script:IsAdmin
            Write-Host ("  {0,-10} {1,10}  ({2} files, {3} paths, locked {4})" -f $cat.Key, (Format-Bytes $m.Size), $m.Count, @($cat.Paths).Count, (Format-Bytes $m.LockedSize))
            $grandSize += $m.Size; $grandCount += $m.Count; $grandLocked += $m.LockedSize
        }
    }
    Write-Host "Total cleanable: $(Format-Bytes $grandSize) in $grandCount files (admin-locked: $(Format-Bytes $grandLocked))"
    Write-Host "Self-test OK"
    exit 0
}
#endregion

#region 7. GUI bootstrap
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Crisper text on high-DPI displays without changing the pixel layout
# (DPI_AWARENESS_CONTEXT_UNAWARE_GDISCALED = -5, Windows 10 1809+)
if (-not ([System.Management.Automation.PSTypeName]'OpenRelax.DpiHelper').Type) {
    try {
        Add-Type -Namespace OpenRelax -Name DpiHelper -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);' -ErrorAction Stop
    } catch {}
}
try {
    if (([System.Management.Automation.PSTypeName]'OpenRelax.DpiHelper').Type) {
        [void][OpenRelax.DpiHelper]::SetProcessDpiAwarenessContext((New-Object IntPtr(-5)))
    }
} catch {}

# Native Windows API helpers - a compile failure here is fatal, so surface it
if (-not ([System.Management.Automation.PSTypeName]'Win32Helper').Type) {
    $apiSource = @"
    using System;
    using System.Runtime.InteropServices;

    public class Win32Helper {
        [DllImport("psapi.dll", SetLastError = true)]
        public static extern bool EmptyWorkingSet(IntPtr hProcess);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        public struct MEMORYSTATUSEX {
            public uint dwLength;
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;
            public void Init() {
                this.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

        [DllImport("kernel32.dll")]
        public static extern ulong GetTickCount64();

        public static MEMORYSTATUSEX GetMemoryStatus() {
            MEMORYSTATUSEX memStatus = new MEMORYSTATUSEX();
            memStatus.Init();
            GlobalMemoryStatusEx(ref memStatus);
            return memStatus;
        }

        public static TimeSpan GetSystemUptime() {
            return TimeSpan.FromMilliseconds(GetTickCount64());
        }
    }
"@
    try {
        Add-Type -TypeDefinition $apiSource -ErrorAction Stop
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Native API helper failed to compile:`n$($_.Exception.Message)", "OpenRelax") | Out-Null
        exit 1
    }
}

# Shared state between the UI thread and worker runspaces
$script:Sync = [hashtable]::Synchronized(@{})
$script:Sync.Log = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$script:Sync.Busy = $false
$script:Sync.ScanResult = $null
$script:Sync.CleanResult = $null
$script:Sync.RamResult = $null
$script:Sync.DiskResult = $null
$script:Tasks = New-Object System.Collections.ArrayList

# UI state
$script:cpuHistory = [System.Collections.Generic.List[int]]::new()
for ($i = 0; $i -lt 20; $i++) { $script:cpuHistory.Add(0) }
$script:pulse = $false
$script:ramLoad = 0
$script:TickCount = 0
$script:TickErrorShown = $false
$script:LastBoost = [DateTime]::MinValue
$script:BoostArmed = $true
$script:ReallyExit = $false
$script:BalloonShown = $false
$script:UILoading = $true
$script:CatSizes = @{}
$script:CatChecks = @{}
$script:CatAdminOnly = @{}

# App icon drawn at runtime: gradient donut on the brand colors
$iconBmp = New-Object System.Drawing.Bitmap(32, 32)
$ig = [System.Drawing.Graphics]::FromImage($iconBmp)
$ig.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$iconRect = New-Object System.Drawing.Rectangle(2, 2, 28, 28)
$iconBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($iconRect, [System.Drawing.ColorTranslator]::FromHtml('#3B82F6'), [System.Drawing.ColorTranslator]::FromHtml('#EC4899'), 45.0)
$ig.FillEllipse($iconBrush, $iconRect)
$iconInner = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#0B0F19'))
$ig.FillEllipse($iconInner, 10, 10, 12, 12)
$iconBrush.Dispose(); $iconInner.Dispose(); $ig.Dispose()
$script:AppIcon = [System.Drawing.Icon]::FromHandle($iconBmp.GetHicon())
#endregion

#region 8. UI helper functions
function Set-RoundedRegion {
    param($control, $radius)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $arcRect = New-Object System.Drawing.Rectangle(0, 0, $radius, $radius)
    $path.AddArc($arcRect, 180, 90)
    $arcRect.X = $control.Width - $radius
    $path.AddArc($arcRect, 270, 90)
    $arcRect.Y = $control.Height - $radius
    $path.AddArc($arcRect, 0, 90)
    $arcRect.X = 0
    $path.AddArc($arcRect, 90, 90)
    $path.CloseAllFigures()
    $control.Region = New-Object System.Drawing.Region($path)
}

$global:cardHoverStates = @{}

function Create-Card {
    param($parent, $location, $size)
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = $location
    $card.Size = $size
    $card.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#161F30')
    $parent.Controls.Add($card)
    Set-RoundedRegion $card 16

    $card.add_Paint({
        param($sender, $e)
        $cardName = $sender.GetHashCode().ToString()
        $isHovered = $global:cardHoverStates[$cardName] -eq $true
        $borderColor = if ($isHovered) { '#3B82F6' } else { '#1E293B' }
        $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($borderColor), 1.5)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $radius = 16
        $arcRect = New-Object System.Drawing.Rectangle(0, 0, $radius, $radius)
        $path.AddArc($arcRect, 180, 90)
        $arcRect.X = $sender.Width - $radius - 1
        $path.AddArc($arcRect, 270, 90)
        $arcRect.Y = $sender.Height - $radius - 1
        $path.AddArc($arcRect, 0, 90)
        $arcRect.X = 0
        $path.AddArc($arcRect, 90, 90)
        $path.CloseAllFigures()

        $e.Graphics.DrawPath($pen, $path)
        $pen.Dispose()
        $path.Dispose()
    })
    return $card
}

function Register-CardHover {
    param($card)
    $cardName = $card.GetHashCode().ToString()
    $global:cardHoverStates[$cardName] = $false

    $hoverEnter = {
        $global:cardHoverStates[$cardName] = $true
        $card.Invalidate()
    }.GetNewClosure()

    $hoverLeave = {
        $clientPos = $card.PointToClient([System.Windows.Forms.Cursor]::Position)
        if (-not $card.ClientRectangle.Contains($clientPos)) {
            $global:cardHoverStates[$cardName] = $false
            $card.Invalidate()
        }
    }.GetNewClosure()

    $card.add_MouseEnter($hoverEnter)
    $card.add_MouseLeave($hoverLeave)
    foreach ($ctrl in $card.Controls) {
        $ctrl.add_MouseEnter($hoverEnter)
        $ctrl.add_MouseLeave($hoverLeave)
    }
}
#endregion

#region 9. Main form and title bar
$form = New-Object System.Windows.Forms.Form
$form.Text = "OpenRelax PC Care"
$form.Size = New-Object System.Drawing.Size(680, 520)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Icon = $script:AppIcon
$form.KeyPreview = $true
$form.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic).SetValue($form, $true, $null)

$form.add_Paint({
    param($sender, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#3B82F6'), 1.5)
    $e.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
    $pen.Dispose()
})

$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Size = New-Object System.Drawing.Size(680, 42)
$titleBar.Location = New-Object System.Drawing.Point(0, 0)
$titleBar.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
$form.Controls.Add($titleBar)

$titleBar.add_Paint({
    param($sender, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#1E293B'), 1)
    $e.Graphics.DrawLine($pen, 0, $sender.Height - 1, $sender.Width, $sender.Height - 1)
    $pen.Dispose()
})

$script:drag = $false
$script:mousePos = $null

$titleBar.add_MouseDown({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:drag = $true
        $script:mousePos = [System.Windows.Forms.Cursor]::Position
    }
})
$titleBar.add_MouseMove({
    param($sender, $e)
    if ($script:drag) {
        $diffX = [System.Windows.Forms.Cursor]::Position.X - $script:mousePos.X
        $diffY = [System.Windows.Forms.Cursor]::Position.Y - $script:mousePos.Y
        $form.Left = $form.Left + $diffX
        $form.Top = $form.Top + $diffY
        $script:mousePos = [System.Windows.Forms.Cursor]::Position
    }
})
$titleBar.add_MouseUp({
    $script:drag = $false
})

$logoDot = New-Object System.Windows.Forms.Panel
$logoDot.Size = New-Object System.Drawing.Size(8, 8)
$logoDot.Location = New-Object System.Drawing.Point(15, 17)
$logoDot.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#10B981')
$titleBar.Controls.Add($logoDot)
Set-RoundedRegion $logoDot 8

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "OpenRelax PC Care v$script:AppVersion"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$titleLabel.Location = New-Object System.Drawing.Point(30, 11)
$titleLabel.AutoSize = $true
$titleBar.Controls.Add($titleLabel)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Size = New-Object System.Drawing.Size(42, 42)
$btnClose.Location = New-Object System.Drawing.Point(638, 0)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.Text = "X"
$btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnClose.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClose.add_MouseEnter({ $btnClose.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#EF4444'); $btnClose.ForeColor = [System.Drawing.Color]::White })
$btnClose.add_MouseLeave({ $btnClose.BackColor = [System.Drawing.Color]::Transparent; $btnClose.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8') })
$titleBar.Controls.Add($btnClose)

$btnMin = New-Object System.Windows.Forms.Button
$btnMin.Size = New-Object System.Drawing.Size(42, 42)
$btnMin.Location = New-Object System.Drawing.Point(596, 0)
$btnMin.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnMin.FlatAppearance.BorderSize = 0
$btnMin.Text = "-"
$btnMin.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnMin.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$btnMin.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnMin.add_MouseEnter({ $btnMin.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#334155'); $btnMin.ForeColor = [System.Drawing.Color]::White })
$btnMin.add_MouseLeave({ $btnMin.BackColor = [System.Drawing.Color]::Transparent; $btnMin.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8') })
$btnMin.add_Click({ $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized })
$titleBar.Controls.Add($btnMin)
#endregion

#region 10. Navigation strip and view containers
$navPanel = New-Object System.Windows.Forms.Panel
$navPanel.Size = New-Object System.Drawing.Size(680, 36)
$navPanel.Location = New-Object System.Drawing.Point(0, 42)
$navPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$form.Controls.Add($navPanel)

$navPanel.add_Paint({
    param($sender, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#1E293B'), 1)
    $e.Graphics.DrawLine($pen, 0, $sender.Height - 1, $sender.Width, $sender.Height - 1)
    $pen.Dispose()
})

$btnNavDash = New-Object System.Windows.Forms.Button
$btnNavSettings = New-Object System.Windows.Forms.Button
$btnNavDisk = New-Object System.Windows.Forms.Button
$navButtons = @($btnNavDash, $btnNavSettings, $btnNavDisk)
$navTags = @('dash', 'settings', 'disk')
$navX = 18
for ($i = 0; $i -lt 3; $i++) {
    $b = $navButtons[$i]
    $b.Size = New-Object System.Drawing.Size(104, 30)
    $b.Location = New-Object System.Drawing.Point($navX, 3)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 0
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Tag = $navTags[$i]
    $navPanel.Controls.Add($b)
    Set-RoundedRegion $b 8
    $navX += 110
}

$contentHost = New-Object System.Windows.Forms.Panel
$contentHost.Size = New-Object System.Drawing.Size(644, 412)
$contentHost.Location = New-Object System.Drawing.Point(18, 86)
$contentHost.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$form.Controls.Add($contentHost)

$viewDash = New-Object System.Windows.Forms.Panel
$viewDash.Size = New-Object System.Drawing.Size(644, 412)
$viewDash.Location = New-Object System.Drawing.Point(0, 0)
$viewDash.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$contentHost.Controls.Add($viewDash)

$viewSettings = New-Object System.Windows.Forms.Panel
$viewSettings.Size = New-Object System.Drawing.Size(644, 412)
$viewSettings.Location = New-Object System.Drawing.Point(0, 0)
$viewSettings.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$viewSettings.Visible = $false
$contentHost.Controls.Add($viewSettings)

$viewDisk = New-Object System.Windows.Forms.Panel
$viewDisk.Size = New-Object System.Drawing.Size(644, 412)
$viewDisk.Location = New-Object System.Drawing.Point(0, 0)
$viewDisk.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$viewDisk.Visible = $false
$contentHost.Controls.Add($viewDisk)

function Show-View {
    param([string]$Name)
    $script:ActiveView = $Name
    $viewDash.Visible = ($Name -eq 'dash')
    $viewSettings.Visible = ($Name -eq 'settings')
    $viewDisk.Visible = ($Name -eq 'disk')
    foreach ($b in $navButtons) {
        if ($b.Tag -eq $Name) {
            $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
            $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#161F30')
        } else {
            $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
            $b.BackColor = [System.Drawing.Color]::Transparent
        }
    }
}

$script:NavClickHandler = {
    param($sender, $e)
    Show-View $sender.Tag
}
$btnNavDash.add_Click($script:NavClickHandler)
$btnNavSettings.add_Click($script:NavClickHandler)
$btnNavDisk.add_Click($script:NavClickHandler)
#endregion

#region 11. Dashboard view - left column (RAM, CPU, system cards)
$leftContainer = New-Object System.Windows.Forms.Panel
$leftContainer.Size = New-Object System.Drawing.Size(260, 400)
$leftContainer.Location = New-Object System.Drawing.Point(0, 4)
$leftContainer.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$viewDash.Controls.Add($leftContainer)

# -- CARD 1: RAM (Donut Chart) --
$ramCard = Create-Card $leftContainer (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(260, 105))

$ramTitle = New-Object System.Windows.Forms.Label
$ramTitle.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$ramTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$ramTitle.Location = New-Object System.Drawing.Point(12, 10)
$ramTitle.AutoSize = $true
$ramCard.Controls.Add($ramTitle)

$ramDescLabel = New-Object System.Windows.Forms.Label
$ramDescLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Regular)
$ramDescLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$ramDescLabel.Location = New-Object System.Drawing.Point(12, 30)
$ramDescLabel.Size = New-Object System.Drawing.Size(145, 30)
$ramCard.Controls.Add($ramDescLabel)

$ramDetailsLabel = New-Object System.Windows.Forms.Label
$ramDetailsLabel.Text = "0.0 GB / 0.0 GB"
$ramDetailsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$ramDetailsLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')
$ramDetailsLabel.Location = New-Object System.Drawing.Point(12, 65)
$ramDetailsLabel.Size = New-Object System.Drawing.Size(145, 20)
$ramCard.Controls.Add($ramDetailsLabel)

$ramPercentLabel = New-Object System.Windows.Forms.Label
$ramPercentLabel.Text = "0%"
$ramPercentLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11.5, [System.Drawing.FontStyle]::Bold)
$ramPercentLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$ramPercentLabel.BackColor = [System.Drawing.Color]::Transparent
$ramPercentLabel.Location = New-Object System.Drawing.Point(165, 15)
$ramPercentLabel.Size = New-Object System.Drawing.Size(75, 75)
$ramPercentLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$ramCard.Controls.Add($ramPercentLabel)

$ramCard.add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $rect = New-Object System.Drawing.Rectangle(165, 15, 75, 75)
    $trackPen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#0B0F19'), 7)
    $g.DrawEllipse($trackPen, $rect)

    $sweepAngle = [float](360 * ([Math]::Min([Math]::Max([int]$script:ramLoad, 0), 100) / 100))
    if ($sweepAngle -gt 0) {
        $color1 = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')
        $color2 = [System.Drawing.ColorTranslator]::FromHtml('#EC4899')
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $color1, $color2, 45.0)
        $valuePen = New-Object System.Drawing.Pen($brush, 7)
        $valuePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $valuePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawArc($valuePen, $rect, -90, $sweepAngle)
        $valuePen.Dispose()
        $brush.Dispose()
    }
    $trackPen.Dispose()
})
Register-CardHover $ramCard

# -- CARD 2: CPU (Real-Time Line Graph) --
$cpuCard = Create-Card $leftContainer (New-Object System.Drawing.Point(0, 120)) (New-Object System.Drawing.Size(260, 105))

$cpuTitle = New-Object System.Windows.Forms.Label
$cpuTitle.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$cpuTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$cpuTitle.Location = New-Object System.Drawing.Point(12, 10)
$cpuTitle.AutoSize = $true
$cpuCard.Controls.Add($cpuTitle)

$cpuPercentLabel = New-Object System.Windows.Forms.Label
$cpuPercentLabel.Text = "0%"
$cpuPercentLabel.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$cpuPercentLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#8B5CF6')
$cpuPercentLabel.Location = New-Object System.Drawing.Point(10, 32)
$cpuPercentLabel.AutoSize = $true
$cpuCard.Controls.Add($cpuPercentLabel)

$cpuDetailsLabel = New-Object System.Windows.Forms.Label
$cpuDetailsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Regular)
$cpuDetailsLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$cpuDetailsLabel.Location = New-Object System.Drawing.Point(12, 65)
$cpuDetailsLabel.Size = New-Object System.Drawing.Size(85, 30)
$cpuCard.Controls.Add($cpuDetailsLabel)

$cpuCard.add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $gridPen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#0B0F19'), 1)
    $g.DrawLine($gridPen, 110, 48, 245, 48)
    $g.DrawLine($gridPen, 110, 66, 245, 66)

    if ($script:cpuHistory.Count -gt 1) {
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $stepX = 135 / 19

        $points = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        for ($i = 0; $i -lt $script:cpuHistory.Count; $i++) {
            $px = 110 + ($i * $stepX)
            $py = 85 - ($script:cpuHistory[$i] / 100 * 50)
            $points.Add((New-Object System.Drawing.PointF($px, $py)))
        }

        $firstX = 110
        $lastX = 110 + (($script:cpuHistory.Count - 1) * $stepX)
        $points.Add((New-Object System.Drawing.PointF($lastX, 85)))
        $points.Add((New-Object System.Drawing.PointF($firstX, 85)))

        $path.AddLines($points.ToArray())
        $path.CloseAllFigures()

        $gradRect = New-Object System.Drawing.Rectangle(110, 35, 135, 50)
        $colorTop = [System.Drawing.Color]::FromArgb(80, 139, 92, 246)
        $colorBottom = [System.Drawing.Color]::FromArgb(0, 139, 92, 246)
        $fillBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($gradRect, $colorTop, $colorBottom, 90.0)
        $g.FillPath($fillBrush, $path)

        $graphPen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#8B5CF6'), 2)
        for ($i = 0; $i -lt ($script:cpuHistory.Count - 1); $i++) {
            $x1 = 110 + ($i * $stepX)
            $y1 = 85 - ($script:cpuHistory[$i] / 100 * 50)
            $x2 = 110 + (($i + 1) * $stepX)
            $y2 = 85 - ($script:cpuHistory[$i + 1] / 100 * 50)
            $g.DrawLine($graphPen, $x1, $y1, $x2, $y2)
        }

        $graphPen.Dispose()
        $fillBrush.Dispose()
        $path.Dispose()
    }
    $gridPen.Dispose()
})
Register-CardHover $cpuCard

# -- CARD 3: SYSTEM INFO --
$sysCard = Create-Card $leftContainer (New-Object System.Drawing.Point(0, 240)) (New-Object System.Drawing.Size(260, 135))

$sysTitle = New-Object System.Windows.Forms.Label
$sysTitle.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$sysTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$sysTitle.Location = New-Object System.Drawing.Point(12, 10)
$sysTitle.AutoSize = $true
$sysCard.Controls.Add($sysTitle)

$lblUptimeName = New-Object System.Windows.Forms.Label
$lblUptimeName.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblUptimeName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblUptimeName.Location = New-Object System.Drawing.Point(12, 35)
$lblUptimeName.AutoSize = $true
$sysCard.Controls.Add($lblUptimeName)

$lblUptimeVal = New-Object System.Windows.Forms.Label
$lblUptimeVal.Text = "-"
$lblUptimeVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblUptimeVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblUptimeVal.Location = New-Object System.Drawing.Point(120, 35)
$lblUptimeVal.Size = New-Object System.Drawing.Size(128, 20)
$lblUptimeVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$sysCard.Controls.Add($lblUptimeVal)

$lblProcName = New-Object System.Windows.Forms.Label
$lblProcName.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblProcName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblProcName.Location = New-Object System.Drawing.Point(12, 65)
$lblProcName.AutoSize = $true
$sysCard.Controls.Add($lblProcName)

$lblProcVal = New-Object System.Windows.Forms.Label
$lblProcVal.Text = "-"
$lblProcVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblProcVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblProcVal.Location = New-Object System.Drawing.Point(120, 65)
$lblProcVal.Size = New-Object System.Drawing.Size(128, 20)
$lblProcVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$sysCard.Controls.Add($lblProcVal)

$lblJunkName = New-Object System.Windows.Forms.Label
$lblJunkName.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblJunkName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblJunkName.Location = New-Object System.Drawing.Point(12, 95)
$lblJunkName.AutoSize = $true
$sysCard.Controls.Add($lblJunkName)

$lblJunkVal = New-Object System.Windows.Forms.Label
$lblJunkVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblJunkVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblJunkVal.Location = New-Object System.Drawing.Point(120, 95)
$lblJunkVal.Size = New-Object System.Drawing.Size(128, 20)
$lblJunkVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$sysCard.Controls.Add($lblJunkVal)

Register-CardHover $sysCard
#endregion

#region 12. Dashboard view - right column (header, action button, log, footer)
$rightContainer = New-Object System.Windows.Forms.Panel
$rightContainer.Size = New-Object System.Drawing.Size(368, 400)
$rightContainer.Location = New-Object System.Drawing.Point(276, 4)
$rightContainer.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$viewDash.Controls.Add($rightContainer)

$headerTitle = New-Object System.Windows.Forms.Label
$headerTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$headerTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$headerTitle.Location = New-Object System.Drawing.Point(0, 0)
$headerTitle.AutoSize = $true
$rightContainer.Controls.Add($headerTitle)

$headerSub = New-Object System.Windows.Forms.Label
$headerSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$headerSub.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$headerSub.Location = New-Object System.Drawing.Point(0, 26)
$headerSub.Size = New-Object System.Drawing.Size(368, 36)
$rightContainer.Controls.Add($headerSub)

$btnOneClick = New-Object System.Windows.Forms.Button
$btnOneClick.Size = New-Object System.Drawing.Size(368, 46)
$btnOneClick.Location = New-Object System.Drawing.Point(0, 68)
$btnOneClick.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOneClick.FlatAppearance.BorderSize = 0
$btnOneClick.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
$btnOneClick.Cursor = [System.Windows.Forms.Cursors]::Hand
$rightContainer.Controls.Add($btnOneClick)
Set-RoundedRegion $btnOneClick 8

$btnOneClick.add_MouseEnter({ $btnOneClick.Invalidate() })
$btnOneClick.add_MouseLeave({ $btnOneClick.Invalidate() })
$btnOneClick.add_MouseDown({ $btnOneClick.Invalidate() })
$btnOneClick.add_MouseUp({ $btnOneClick.Invalidate() })

$btnOneClick.add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $color1 = [System.Drawing.ColorTranslator]::FromHtml('#7C3AED')
    $color2 = [System.Drawing.ColorTranslator]::FromHtml('#EC4899')

    if (-not $sender.Enabled) {
        $color1 = [System.Drawing.ColorTranslator]::FromHtml('#3B1D5A')
        $color2 = [System.Drawing.ColorTranslator]::FromHtml('#5B1D45')
    } elseif ($sender.Capture -and $sender.ClientRectangle.Contains($sender.PointToClient([System.Windows.Forms.Cursor]::Position))) {
        $color1 = [System.Drawing.ColorTranslator]::FromHtml('#6D28D9')
        $color2 = [System.Drawing.ColorTranslator]::FromHtml('#DB2777')
    } elseif ($sender.ClientRectangle.Contains($sender.PointToClient([System.Windows.Forms.Cursor]::Position))) {
        $color1 = [System.Drawing.ColorTranslator]::FromHtml('#8B5CF6')
        $color2 = [System.Drawing.ColorTranslator]::FromHtml('#F472B6')
    }

    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($sender.ClientRectangle, $color1, $color2, 0.0)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $radius = 8
    $arcRect = New-Object System.Drawing.Rectangle(0, 0, $radius, $radius)
    $path.AddArc($arcRect, 180, 90)
    $arcRect.X = $sender.Width - $radius - 1
    $path.AddArc($arcRect, 270, 90)
    $arcRect.Y = $sender.Height - $radius - 1
    $path.AddArc($arcRect, 0, 90)
    $arcRect.X = 0
    $path.AddArc($arcRect, 90, 90)
    $path.CloseAllFigures()

    $g.FillPath($brush, $path)

    $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString($sender.Text, $sender.Font, $textBrush, (New-Object System.Drawing.RectangleF(0, 0, $sender.Width, $sender.Height)), $sf)

    $brush.Dispose()
    $path.Dispose()
    $textBrush.Dispose()
    $sf.Dispose()
})

$logPanel = New-Object System.Windows.Forms.Panel
$logPanel.Size = New-Object System.Drawing.Size(368, 220)
$logPanel.Location = New-Object System.Drawing.Point(0, 125)
$logPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#070A13')
$rightContainer.Controls.Add($logPanel)
Set-RoundedRegion $logPanel 10

$logPanel.add_Paint({
    param($sender, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#1E293B'), 1)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $radius = 10
    $arcRect = New-Object System.Drawing.Rectangle(0, 0, $radius, $radius)
    $path.AddArc($arcRect, 180, 90)
    $arcRect.X = $sender.Width - $radius - 1
    $path.AddArc($arcRect, 270, 90)
    $arcRect.Y = $sender.Height - $radius - 1
    $path.AddArc($arcRect, 0, 90)
    $arcRect.X = 0
    $path.AddArc($arcRect, 90, 90)
    $path.CloseAllFigures()
    $e.Graphics.DrawPath($pen, $path)
    $pen.Dispose()
    $path.Dispose()
})

$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Location = New-Object System.Drawing.Point(8, 8)
$logBox.Size = New-Object System.Drawing.Size(352, 204)
$logBox.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#070A13')
$logBox.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#10B981')
$logBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$logBox.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$logBox.ReadOnly = $true
$logPanel.Controls.Add($logBox)

# Footer: status, auto-boost switch, threshold selector
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblStatus.Location = New-Object System.Drawing.Point(0, 362)
$lblStatus.Size = New-Object System.Drawing.Size(112, 20)
$rightContainer.Controls.Add($lblStatus)

$lblAuto = New-Object System.Windows.Forms.Label
$lblAuto.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblAuto.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblAuto.Location = New-Object System.Drawing.Point(112, 362)
$lblAuto.Size = New-Object System.Drawing.Size(98, 20)
$lblAuto.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$rightContainer.Controls.Add($lblAuto)

$switchPanel = New-Object System.Windows.Forms.Panel
$switchPanel.Size = New-Object System.Drawing.Size(36, 20)
$switchPanel.Location = New-Object System.Drawing.Point(214, 361)
$switchPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#334155')
$switchPanel.Cursor = [System.Windows.Forms.Cursors]::Hand
$rightContainer.Controls.Add($switchPanel)
Set-RoundedRegion $switchPanel 10

$switchPanel.add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $bgBrush = if ($script:Settings.autoBoost) {
        New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#10B981'))
    } else {
        New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#334155'))
    }
    $g.FillRectangle($bgBrush, 0, 0, $sender.Width, $sender.Height)
    $bgBrush.Dispose()

    $knobBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $knobX = if ($script:Settings.autoBoost) { 18 } else { 2 }
    $g.FillEllipse($knobBrush, $knobX, 2, 16, 16)
    $knobBrush.Dispose()
})

$switchPanel.add_Click({
    $script:Settings.autoBoost = -not $script:Settings.autoBoost
    Save-Settings
    $switchPanel.Invalidate()
})

$lblLimit = New-Object System.Windows.Forms.Label
$lblLimit.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblLimit.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblLimit.Location = New-Object System.Drawing.Point(256, 362)
$lblLimit.Size = New-Object System.Drawing.Size(46, 20)
$lblLimit.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$rightContainer.Controls.Add($lblLimit)

$cmbLimit = New-Object System.Windows.Forms.ComboBox
$cmbLimit.Location = New-Object System.Drawing.Point(306, 360)
$cmbLimit.Size = New-Object System.Drawing.Size(60, 22)
$cmbLimit.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#161F30')
$cmbLimit.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$cmbLimit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbLimit.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbLimit.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
foreach ($v in 70, 75, 80, 85, 90) { [void]$cmbLimit.Items.Add("%$v") }
$limitIdx = [Array]::IndexOf(@(70, 75, 80, 85, 90), [int]$script:Settings.autoBoostLimit)
if ($limitIdx -lt 0) { $limitIdx = 3 }
$cmbLimit.SelectedIndex = $limitIdx
$rightContainer.Controls.Add($cmbLimit)

$cmbLimit.add_SelectedIndexChanged({
    if ($script:UILoading) { return }
    $script:Settings.autoBoostLimit = [int]($cmbLimit.SelectedItem -replace '%', '')
    Save-Settings
})
#endregion

#region 13. Settings view
$catCard = Create-Card $viewSettings (New-Object System.Drawing.Point(0, 4)) (New-Object System.Drawing.Size(316, 400))

$catTitle = New-Object System.Windows.Forms.Label
$catTitle.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$catTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$catTitle.Location = New-Object System.Drawing.Point(12, 10)
$catTitle.AutoSize = $true
$catCard.Controls.Add($catTitle)

# Category checkboxes: created in a top-level loop, wired through a single
# shared handler; per-checkbox data travels via .Tag (safe in PS event scope).
$script:CategoryChangedHandler = {
    param($sender, $e)
    if ($script:UILoading) { return }
    $script:Settings.categories[$sender.Tag] = $sender.Checked
    Save-Settings
}

$catKeys = @('temp', 'browser', 'discord', 'shader', 'wer', 'wu', 'gpusetup', 'recycle')
$catY = 38
foreach ($catKey in $catKeys) {
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Location = New-Object System.Drawing.Point(14, $catY)
    $chk.Size = New-Object System.Drawing.Size(288, 22)
    $chk.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $chk.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#CBD5E1')
    $chk.BackColor = [System.Drawing.Color]::Transparent
    $chk.Tag = $catKey
    $chk.Checked = [bool]$script:Settings.categories[$catKey]
    $chk.add_CheckedChanged($script:CategoryChangedHandler)
    $catCard.Controls.Add($chk)
    $script:CatChecks[$catKey] = $chk
    $catY += 42
}
Register-CardHover $catCard

# Which categories consist purely of admin-only paths (for UI hints)
foreach ($cat in (Get-JunkCategories)) {
    $allAdmin = $false
    if (@($cat.Paths).Count -gt 0) {
        $allAdmin = $true
        foreach ($p in $cat.Paths) { if (-not $p.Admin) { $allAdmin = $false } }
    }
    $script:CatAdminOnly[$cat.Key] = $allAdmin
}

$genCard = Create-Card $viewSettings (New-Object System.Drawing.Point(332, 4)) (New-Object System.Drawing.Size(312, 230))

$genTitle = New-Object System.Windows.Forms.Label
$genTitle.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$genTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$genTitle.Location = New-Object System.Drawing.Point(12, 10)
$genTitle.AutoSize = $true
$genCard.Controls.Add($genTitle)

$script:OptionChangedHandler = {
    param($sender, $e)
    if ($script:UILoading) { return }
    switch ($sender.Tag) {
        'tray' {
            $script:Settings.closeToTray = $sender.Checked
            Save-Settings
        }
        'startup' {
            $script:Settings.runAtStartup = $sender.Checked
            Save-Settings
            $r = Set-StartupEntry $sender.Checked
            if ($r.Ok) { Write-Log (T $r.Key) 'success' }
            else { Write-Log ([string]::Format((T 'logError'), $r.Error)) 'error' }
        }
        'weekly' {
            $script:Settings.weeklyClean = $sender.Checked
            Save-Settings
            $r = Set-WeeklyTask $sender.Checked
            if ($r.Ok) { Write-Log (T $r.Key) 'success' }
            else { Write-Log ([string]::Format((T 'logTaskError'), $r.Error)) 'error' }
        }
    }
}

$chkTray = New-Object System.Windows.Forms.CheckBox
$chkTray.Location = New-Object System.Drawing.Point(14, 38)
$chkTray.Size = New-Object System.Drawing.Size(284, 22)
$chkTray.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$chkTray.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#CBD5E1')
$chkTray.BackColor = [System.Drawing.Color]::Transparent
$chkTray.Tag = 'tray'
$chkTray.Checked = [bool]$script:Settings.closeToTray
$chkTray.add_CheckedChanged($script:OptionChangedHandler)
$genCard.Controls.Add($chkTray)

$chkStartup = New-Object System.Windows.Forms.CheckBox
$chkStartup.Location = New-Object System.Drawing.Point(14, 68)
$chkStartup.Size = New-Object System.Drawing.Size(284, 22)
$chkStartup.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$chkStartup.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#CBD5E1')
$chkStartup.BackColor = [System.Drawing.Color]::Transparent
$chkStartup.Tag = 'startup'
$chkStartup.Checked = [bool]$script:Settings.runAtStartup
$chkStartup.add_CheckedChanged($script:OptionChangedHandler)
$genCard.Controls.Add($chkStartup)

$chkWeekly = New-Object System.Windows.Forms.CheckBox
$chkWeekly.Location = New-Object System.Drawing.Point(14, 98)
$chkWeekly.Size = New-Object System.Drawing.Size(284, 22)
$chkWeekly.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$chkWeekly.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#CBD5E1')
$chkWeekly.BackColor = [System.Drawing.Color]::Transparent
$chkWeekly.Tag = 'weekly'
$chkWeekly.Checked = [bool]$script:Settings.weeklyClean
$chkWeekly.add_CheckedChanged($script:OptionChangedHandler)
$genCard.Controls.Add($chkWeekly)

$lblLang = New-Object System.Windows.Forms.Label
$lblLang.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblLang.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblLang.Location = New-Object System.Drawing.Point(14, 134)
$lblLang.Size = New-Object System.Drawing.Size(90, 20)
$genCard.Controls.Add($lblLang)

$cmbLang = New-Object System.Windows.Forms.ComboBox
$cmbLang.Location = New-Object System.Drawing.Point(110, 131)
$cmbLang.Size = New-Object System.Drawing.Size(120, 22)
$cmbLang.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#161F30')
$cmbLang.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$cmbLang.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbLang.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbLang.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
[void]$cmbLang.Items.Add('Türkçe')
[void]$cmbLang.Items.Add('English')
if ($script:Settings.language -eq 'en') { $cmbLang.SelectedIndex = 1 } else { $cmbLang.SelectedIndex = 0 }
$genCard.Controls.Add($cmbLang)

$cmbLang.add_SelectedIndexChanged({
    if ($script:UILoading) { return }
    if ($cmbLang.SelectedIndex -eq 1) { $script:Settings.language = 'en' } else { $script:Settings.language = 'tr' }
    Save-Settings
    Apply-Language
})

$btnElevate = New-Object System.Windows.Forms.Button
$btnElevate.Size = New-Object System.Drawing.Size(284, 34)
$btnElevate.Location = New-Object System.Drawing.Point(14, 172)
$btnElevate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnElevate.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')
$btnElevate.FlatAppearance.BorderSize = 1
$btnElevate.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$btnElevate.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')
$btnElevate.BackColor = [System.Drawing.Color]::Transparent
$btnElevate.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnElevate.Visible = (-not $script:IsAdmin)
$genCard.Controls.Add($btnElevate)

$btnElevate.add_Click({
    try {
        Start-Process -FilePath $script:PsExe -ArgumentList @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:ScriptPath`"") -Verb RunAs
        $script:ReallyExit = $true
        $form.Close()
    } catch {
        Write-Log (T 'logElevateFail') 'warn'
    }
})

Register-CardHover $genCard

$statCard = Create-Card $viewSettings (New-Object System.Drawing.Point(332, 250)) (New-Object System.Drawing.Size(312, 154))

$statTitle = New-Object System.Windows.Forms.Label
$statTitle.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$statTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$statTitle.Location = New-Object System.Drawing.Point(12, 10)
$statTitle.AutoSize = $true
$statCard.Controls.Add($statTitle)

$lblStatTotalName = New-Object System.Windows.Forms.Label
$lblStatTotalName.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblStatTotalName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblStatTotalName.Location = New-Object System.Drawing.Point(12, 40)
$lblStatTotalName.AutoSize = $true
$statCard.Controls.Add($lblStatTotalName)

$lblStatTotalVal = New-Object System.Windows.Forms.Label
$lblStatTotalVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblStatTotalVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#10B981')
$lblStatTotalVal.Location = New-Object System.Drawing.Point(160, 40)
$lblStatTotalVal.Size = New-Object System.Drawing.Size(140, 20)
$lblStatTotalVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$statCard.Controls.Add($lblStatTotalVal)

$lblStatRunsName = New-Object System.Windows.Forms.Label
$lblStatRunsName.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblStatRunsName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblStatRunsName.Location = New-Object System.Drawing.Point(12, 70)
$lblStatRunsName.AutoSize = $true
$statCard.Controls.Add($lblStatRunsName)

$lblStatRunsVal = New-Object System.Windows.Forms.Label
$lblStatRunsVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblStatRunsVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblStatRunsVal.Location = New-Object System.Drawing.Point(160, 70)
$lblStatRunsVal.Size = New-Object System.Drawing.Size(140, 20)
$lblStatRunsVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$statCard.Controls.Add($lblStatRunsVal)

$lblStatLastName = New-Object System.Windows.Forms.Label
$lblStatLastName.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblStatLastName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblStatLastName.Location = New-Object System.Drawing.Point(12, 100)
$lblStatLastName.AutoSize = $true
$statCard.Controls.Add($lblStatLastName)

$lblStatLastVal = New-Object System.Windows.Forms.Label
$lblStatLastVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblStatLastVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblStatLastVal.Location = New-Object System.Drawing.Point(160, 100)
$lblStatLastVal.Size = New-Object System.Drawing.Size(140, 20)
$lblStatLastVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$statCard.Controls.Add($lblStatLastVal)

Register-CardHover $statCard
#endregion

#region 14. Disk analysis view
$diskCard = Create-Card $viewDisk (New-Object System.Drawing.Point(0, 4)) (New-Object System.Drawing.Size(644, 400))

$diskTitle = New-Object System.Windows.Forms.Label
$diskTitle.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$diskTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$diskTitle.Location = New-Object System.Drawing.Point(12, 10)
$diskTitle.AutoSize = $true
$diskCard.Controls.Add($diskTitle)

$diskDesc = New-Object System.Windows.Forms.Label
$diskDesc.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$diskDesc.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$diskDesc.Location = New-Object System.Drawing.Point(12, 30)
$diskDesc.Size = New-Object System.Drawing.Size(470, 30)
$diskCard.Controls.Add($diskDesc)

$btnAnalyze = New-Object System.Windows.Forms.Button
$btnAnalyze.Size = New-Object System.Drawing.Size(130, 32)
$btnAnalyze.Location = New-Object System.Drawing.Point(500, 14)
$btnAnalyze.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAnalyze.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')
$btnAnalyze.FlatAppearance.BorderSize = 1
$btnAnalyze.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$btnAnalyze.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')
$btnAnalyze.BackColor = [System.Drawing.Color]::Transparent
$btnAnalyze.Cursor = [System.Windows.Forms.Cursors]::Hand
$diskCard.Controls.Add($btnAnalyze)

$lvDisk = New-Object System.Windows.Forms.ListView
$lvDisk.Location = New-Object System.Drawing.Point(12, 64)
$lvDisk.Size = New-Object System.Drawing.Size(620, 322)
$lvDisk.View = [System.Windows.Forms.View]::Details
$lvDisk.FullRowSelect = $true
$lvDisk.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$lvDisk.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#E2E8F0')
$lvDisk.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$lvDisk.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lvDisk.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
[void]$lvDisk.Columns.Add('Folder', 450)
[void]$lvDisk.Columns.Add('Size', 140)
$diskCard.Controls.Add($lvDisk)

Register-CardHover $diskCard
#endregion

#region 15. System tray icon
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = $script:AppIcon
$notifyIcon.Text = "OpenRelax PC Care"
$notifyIcon.Visible = $true

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miShow = $trayMenu.Items.Add("Show")
$miClean = $trayMenu.Items.Add("Clean")
[void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miExit = $trayMenu.Items.Add("Exit")
$notifyIcon.ContextMenuStrip = $trayMenu

function Show-MainWindow {
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.Activate()
}

function Hide-ToTray {
    $form.Hide()
    if (-not $script:BalloonShown) {
        $script:BalloonShown = $true
        $notifyIcon.BalloonTipTitle = "OpenRelax"
        $notifyIcon.BalloonTipText = (T 'trayBalloon')
        $notifyIcon.ShowBalloonTip(2500)
    }
}

$notifyIcon.add_DoubleClick({ Show-MainWindow })
$miShow.add_Click({ Show-MainWindow })
$miClean.add_Click({ Show-MainWindow; $btnOneClick.PerformClick() })
$miExit.add_Click({
    $script:ReallyExit = $true
    $form.Close()
})

$btnClose.add_Click({
    if ($script:Settings.closeToTray) {
        Hide-ToTray
    } else {
        $script:ReallyExit = $true
        $form.Close()
    }
})

$form.add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        if ($script:Settings.closeToTray) { Hide-ToTray }
        else { $script:ReallyExit = $true; $form.Close() }
    }
})
#endregion

#region 16. Logging
function Write-Log {
    param(
        [string]$Message,
        [string]$Type = "info"
    )
    $timestamp = Get-Date -Format "HH:mm:ss"

    $logAction = {
        # Keep the log bounded so long sessions do not grow memory forever
        if ($logBox.Text.Length -gt 100000) { $logBox.Clear() }

        $logBox.SelectionStart = $logBox.Text.Length
        $logBox.SelectionLength = 0
        $logBox.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml('#475569')
        $logBox.AppendText("[$timestamp] ")

        $prefix = "[i] "
        $prefixColor = '#06B6D4'
        switch ($Type) {
            "success" { $prefix = "[OK] "; $prefixColor = '#10B981' }
            "warn"    { $prefix = "[!] ";  $prefixColor = '#F59E0B' }
            "error"   { $prefix = "[X] ";  $prefixColor = '#EF4444' }
        }
        $logBox.SelectionStart = $logBox.Text.Length
        $logBox.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml($prefixColor)
        $logBox.AppendText($prefix)

        $logBox.SelectionStart = $logBox.Text.Length
        $logBox.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml('#E2E8F0')
        $logBox.AppendText("$Message`n")

        $logBox.SelectionStart = $logBox.Text.Length
        $logBox.ScrollToCaret()
    }

    if ($form.IsHandleCreated -and $form.InvokeRequired) {
        $form.BeginInvoke([Action]($logAction.GetNewClosure())) | Out-Null
    } else {
        & $logAction
    }
}
#endregion

#region 17. Background task runner and completion handlers
function Start-EngineTask {
    param([string]$TaskCode, [hashtable]$Opt)
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::STA
    $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($script:EngineCode)
    [void]$ps.AddStatement().AddScript($TaskCode).AddArgument($script:Sync).AddArgument($Opt)
    $handle = $ps.BeginInvoke()
    [void]$script:Tasks.Add(@{ PS = $ps; RS = $rs; Handle = $handle })
}

function Update-Status {
    if ($script:Sync.Busy) { $lblStatus.Text = (T 'statusBusy') }
    elseif ($script:IsAdmin) { $lblStatus.Text = (T 'statusAdmin') }
    else { $lblStatus.Text = (T 'statusUser') }
}

function Update-StatsUI {
    $lblStatTotalVal.Text = Format-Bytes ([long]$script:Settings.stats.totalCleanedBytes)
    $lblStatRunsVal.Text = ([int]$script:Settings.stats.totalRuns).ToString()
    if ($script:Settings.stats.lastClean) { $lblStatLastVal.Text = $script:Settings.stats.lastClean }
    else { $lblStatLastVal.Text = (T 'never') }
}

function Update-CategoryTexts {
    foreach ($key in @($script:CatChecks.Keys)) {
        $chk = $script:CatChecks[$key]
        $txt = T ("cat_" + $key)
        if ($script:CatAdminOnly[$key] -and -not $script:IsAdmin) {
            $txt = "$txt " + (T 'adminRequired')
        }
        if ($script:CatSizes.ContainsKey($key)) {
            $sz = [long]$script:CatSizes[$key]
            if ($sz -gt 0) { $txt = "$txt  -  $(Format-Bytes $sz)" }
        }
        $chk.Text = $txt
    }
}

function Start-ScanTask {
    $script:Sync.Busy = $true
    $lblJunkVal.Text = (T 'calculating')
    Update-Status
    Start-EngineTask $script:ScanTaskCode @{ IsAdmin = $script:IsAdmin }
}

function Complete-Scan {
    param($r)
    $script:CatSizes = @{}
    foreach ($k in $r.Categories.Keys) { $script:CatSizes[$k] = $r.Categories[$k].Size }
    if ($r.TotalSize -gt 0) { $lblJunkVal.Text = Format-Bytes ([long]$r.TotalSize) }
    else { $lblJunkVal.Text = (T 'cleanState') }
    Write-Log ([string]::Format((T 'logScanDone'), $r.FileCount, (Format-Bytes ([long]$r.TotalSize)))) 'info'
    if ($r.LockedSize -gt 0) {
        Write-Log ([string]::Format((T 'logScanAdminExtra'), (Format-Bytes ([long]$r.LockedSize)))) 'warn'
    }
    Update-CategoryTexts
    $script:Sync.Busy = $false
    $btnOneClick.Enabled = $true
    $btnOneClick.Text = (T 'btnOneClick')
    $btnOneClick.Invalidate()
    Update-Status
}

function Complete-Clean {
    param($r)
    $script:Settings.stats.totalCleanedBytes = [long]$script:Settings.stats.totalCleanedBytes + [long]$r.Bytes
    $script:Settings.stats.totalRuns = [int]$script:Settings.stats.totalRuns + 1
    $script:Settings.stats.lastClean = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    Save-Settings
    Update-StatsUI
    Write-Log ([string]::Format((T 'logCleanDone'), $r.Count, (Format-Bytes ([long]$r.Bytes)))) 'success'
    Write-Log (T 'logAllDone') 'success'
    # Rescan so the junk size reflects the cleanup; button re-enables after it
    Start-EngineTask $script:ScanTaskCode @{ IsAdmin = $script:IsAdmin }
    $lblJunkVal.Text = (T 'calculating')
}

function Complete-Ram {
    param($r)
    if ($r.Saved -gt 0) {
        Write-Log ([string]::Format((T 'logRamDone'), (Format-Bytes ([long]$r.Saved)))) 'success'
    }
    $script:Sync.Busy = $false
    Update-Status
}

function Complete-Disk {
    param($r)
    $lvDisk.Items.Clear()
    foreach ($row in $r.Rows) {
        $item = New-Object System.Windows.Forms.ListViewItem($row.Name)
        [void]$item.SubItems.Add((Format-Bytes ([long]$row.Size)))
        [void]$lvDisk.Items.Add($item)
    }
    Write-Log ([string]::Format((T 'logDiskDone'), $r.Count)) 'success'
    $btnAnalyze.Enabled = $true
    $btnAnalyze.Text = (T 'btnAnalyze')
    $script:Sync.Busy = $false
    Update-Status
}

# Smoke-test support: auto-closes the app shortly after startup. Rooted at
# script scope - a locally-scoped WinForms Timer can be garbage-collected
# mid-run and would then never fire.
$script:SmokeTimer = New-Object System.Windows.Forms.Timer
$script:SmokeTimer.Interval = 4000
$script:SmokeTimer.add_Tick({
    $script:SmokeTimer.Stop()
    $script:ReallyExit = $true
    $form.Close()
})

# Pump timer: drains worker logs, applies results, disposes finished runspaces
$pump = New-Object System.Windows.Forms.Timer
$pump.Interval = 250
$pump.add_Tick({
    try {
        while ($script:Sync.Log.Count -gt 0) {
            $entry = $script:Sync.Log.Dequeue()
            $msg = ''
            if ($entry.ContainsKey('Text')) {
                $msg = $entry.Text
            } else {
                $fmt = T $entry.Key
                if ($entry.ContainsKey('Args')) { $msg = [string]::Format($fmt, [object[]]$entry.Args) }
                else { $msg = $fmt }
            }
            Write-Log $msg $entry.Type
        }

        for ($i = $script:Tasks.Count - 1; $i -ge 0; $i--) {
            $t = $script:Tasks[$i]
            if ($t.Handle.IsCompleted) {
                try { [void]$t.PS.EndInvoke($t.Handle) } catch {
                    Write-Log ([string]::Format((T 'logError'), $_.Exception.Message)) 'error'
                }
                try { $t.PS.Dispose() } catch {}
                try { $t.RS.Dispose() } catch {}
                $script:Tasks.RemoveAt($i)
            }
        }

        if ($script:Sync.ScanResult)  { $r = $script:Sync.ScanResult;  $script:Sync.ScanResult = $null;  Complete-Scan $r }
        if ($script:Sync.CleanResult) { $r = $script:Sync.CleanResult; $script:Sync.CleanResult = $null; Complete-Clean $r }
        if ($script:Sync.RamResult)   { $r = $script:Sync.RamResult;   $script:Sync.RamResult = $null;   Complete-Ram $r }
        if ($script:Sync.DiskResult)  { $r = $script:Sync.DiskResult;  $script:Sync.DiskResult = $null;  Complete-Disk $r }
    } catch {}
})
#endregion

#region 18. Action handlers
$btnOneClick.add_Click({
    if ($script:Sync.Busy) {
        Write-Log (T 'logBusy') 'warn'
        return
    }
    $script:Sync.Busy = $true
    $btnOneClick.Enabled = $false
    $btnOneClick.Text = (T 'btnCleaning')
    $btnOneClick.Invalidate()
    Update-Status
    Write-Log (T 'logMaintStart') 'info'
    $keys = @()
    foreach ($k in $script:Settings.categories.Keys) {
        if ($script:Settings.categories[$k]) { $keys += $k }
    }
    Start-EngineTask $script:CleanTaskCode @{ IsAdmin = $script:IsAdmin; Keys = $keys }
})

$btnAnalyze.add_Click({
    if ($script:Sync.Busy) {
        Write-Log (T 'logBusy') 'warn'
        return
    }
    $script:Sync.Busy = $true
    $btnAnalyze.Enabled = $false
    $btnAnalyze.Text = (T 'analyzing')
    Update-Status
    Write-Log (T 'logDiskStart') 'info'
    Start-EngineTask $script:DiskTaskCode @{ Target = $env:USERPROFILE }
})
#endregion

#region 19. Localization apply
function Apply-Language {
    $btnNavDash.Text = (T 'navDash')
    $btnNavSettings.Text = (T 'navSettings')
    $btnNavDisk.Text = (T 'navDisk')
    $ramTitle.Text = (T 'ramTitle')
    $ramDescLabel.Text = (T 'ramDesc')
    $cpuTitle.Text = (T 'cpuTitle')
    $cpuDetailsLabel.Text = (T 'cpuDesc')
    $sysTitle.Text = (T 'sysTitle')
    $lblUptimeName.Text = (T 'uptime')
    $lblProcName.Text = (T 'procCount')
    $lblJunkName.Text = (T 'junkFiles')
    $headerTitle.Text = (T 'headerTitle')
    $headerSub.Text = (T 'headerSub')
    if (-not $script:Sync.Busy) {
        $btnOneClick.Text = (T 'btnOneClick')
        $btnOneClick.Invalidate()
    }
    $lblAuto.Text = (T 'autoBoost')
    $lblLimit.Text = (T 'limit')
    $catTitle.Text = (T 'settingsCats')
    $genTitle.Text = (T 'settingsGeneral')
    $statTitle.Text = (T 'settingsStats')
    $chkTray.Text = (T 'optCloseTray')
    $chkStartup.Text = (T 'optStartup')
    $chkWeekly.Text = (T 'optWeekly')
    $lblLang.Text = (T 'language')
    $btnElevate.Text = (T 'btnElevate')
    $lblStatTotalName.Text = (T 'statTotal')
    $lblStatRunsName.Text = (T 'statRuns')
    $lblStatLastName.Text = (T 'statLast')
    $diskTitle.Text = (T 'diskTitle')
    $diskDesc.Text = (T 'diskDesc')
    if ($btnAnalyze.Enabled) { $btnAnalyze.Text = (T 'btnAnalyze') }
    $lvDisk.Columns[0].Text = (T 'colFolder')
    $lvDisk.Columns[1].Text = (T 'colSize')
    $miShow.Text = (T 'trayShow')
    $miClean.Text = (T 'trayClean')
    $miExit.Text = (T 'trayExit')
    Update-CategoryTexts
    Update-StatsUI
    Update-Status
}
#endregion

#region 20. Monitoring timer
$script:cpuCounter = $null
try {
    $script:cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total")
    [void]$script:cpuCounter.NextValue()
} catch {
    $script:cpuCounter = $null
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.add_Tick({
    try {
        $memStatus = [Win32Helper]::GetMemoryStatus()
        $totalGB = [Math]::Round($memStatus.ullTotalPhys / 1GB, 1)
        $usedGB = [Math]::Round(($memStatus.ullTotalPhys - $memStatus.ullAvailPhys) / 1GB, 1)
        $script:ramLoad = [int]$memStatus.dwMemoryLoad

        $ramPercentLabel.Text = "$($script:ramLoad)%"
        $ramDetailsLabel.Text = "$usedGB GB / $totalGB GB"
        $ramCard.Invalidate()

        if ($script:cpuCounter) {
            $cpuVal = [Math]::Round($script:cpuCounter.NextValue())
            if ($cpuVal -gt 100) { $cpuVal = 100 }
            if ($cpuVal -lt 0) { $cpuVal = 0 }
            $cpuPercentLabel.Text = "$cpuVal%"
            $script:cpuHistory.Add([int]$cpuVal)
            if ($script:cpuHistory.Count -gt 20) { $script:cpuHistory.RemoveAt(0) }
            $cpuCard.Invalidate()
        }

        $uptime = [Win32Helper]::GetSystemUptime()
        $lblUptimeVal.Text = [string]::Format((T 'uptimeFmt'), $uptime.Days, $uptime.Hours, $uptime.Minutes)

        $script:TickCount++
        if (($script:TickCount % 3) -eq 0) {
            $lblProcVal.Text = ([System.Diagnostics.Process]::GetProcesses().Length).ToString()
        }

        if ($script:pulse) {
            $logoDot.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#059669')
        } else {
            $logoDot.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#10B981')
        }
        $script:pulse = -not $script:pulse

        # Auto-boost with cooldown (5 min) + hysteresis (re-arm 5 points below limit)
        $limitVal = [int]$script:Settings.autoBoostLimit
        if ($script:Settings.autoBoost) {
            if ($script:ramLoad -ge $limitVal) {
                $cooldownOk = ((Get-Date) - $script:LastBoost).TotalSeconds -ge 300
                if ($script:BoostArmed -and $cooldownOk -and -not $script:Sync.Busy) {
                    $script:LastBoost = Get-Date
                    $script:BoostArmed = $false
                    $script:Sync.Busy = $true
                    Write-Log ([string]::Format((T 'logAutoBoost'), $limitVal)) 'warn'
                    Start-EngineTask $script:RamTaskCode @{}
                }
            } elseif ($script:ramLoad -le ($limitVal - 5)) {
                $script:BoostArmed = $true
            }
        }
    } catch {
        if (-not $script:TickErrorShown) {
            $script:TickErrorShown = $true
            Write-Log ([string]::Format((T 'logTickError'), $_.Exception.Message)) 'error'
        }
    }
})
#endregion

#region 21. Form lifecycle
$form.add_FormClosing({
    param($sender, $e)
    if ($script:Settings.closeToTray -and -not $script:ReallyExit) {
        $e.Cancel = $true
        Hide-ToTray
        return
    }
    try { $timer.Stop() } catch {}
    try { $pump.Stop() } catch {}
    # Ask running workers to stop asynchronously - a synchronous Stop() here
    # could block the UI thread mid-close; the process exit below reclaims
    # everything regardless.
    foreach ($t in @($script:Tasks)) {
        try { [void]$t.PS.BeginStop($null, $null) } catch {}
    }
    $script:Tasks.Clear()
    if ($script:cpuCounter) { try { $script:cpuCounter.Dispose() } catch {} }
    try { $notifyIcon.Visible = $false; $notifyIcon.Dispose() } catch {}
})

$form.add_Load({
    Write-Log (T 'logStart') 'info'
    if (-not $script:cpuCounter) { Write-Log (T 'logCpuFail') 'warn' }

    if ($script:IsAdmin) {
        Write-Log (T 'logAdminOn') 'success'
    } else {
        Write-Log (T 'logAdminOff') 'warn'
    }
    if ([long]$script:Settings.stats.totalRuns -gt 0) {
        Write-Log ([string]::Format((T 'logStats'), (Format-Bytes ([long]$script:Settings.stats.totalCleanedBytes)), $script:Settings.stats.totalRuns)) 'info'
    }
    Update-Status

    $timer.Start()
    $pump.Start()
    Start-ScanTask

    if ($env:OPENRELAX_SMOKETEST) {
        $script:SmokeTimer.Start()
    }
})

$form.add_Shown({
    if ($StartMinimized) {
        $script:BalloonShown = $true
        Hide-ToTray
    }
})

Show-View 'dash'
Apply-Language
$script:UILoading = $false

[System.Windows.Forms.Application]::Run($form)

# Guarantee process termination even if a worker runspace thread is still alive
[Environment]::Exit(0)
#endregion
