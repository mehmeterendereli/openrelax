# OpenRelax PC Care v2.1 LTS - PowerShell WinForms system care utility
# Modes: default = GUI | -AutoClean = headless scheduled cleanup | -SelfTest = read-only engine scan
# Test hooks (env): OPENRELAX_SMOKETEST=1|<seconds> auto-close, OPENRELAX_STRESS=<cycles> GUI stress run,
#                   OPENRELAX_TRAP_DIR=<folder> read Fotokapan data from a test folder,
#                   OPENRELAX_STRESS_DISK=1 end a stress run with one disk analysis
param(
    [switch]$AutoClean,
    [switch]$StartMinimized,
    [switch]$SelfTest
)

$script:AppVersion   = '2.1.1'
$script:AppEdition   = 'LTS'
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
            devcache = $false   # opt-in: a cleared cache costs a re-download
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
        btnCleaningProgress = 'Temizleniyor · {0} dosya · {1}'
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
        cat_devcache     = 'Geliştirici Önbellekleri (npm, pip, NuGet, Yarn)'
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
        trayTrap         = 'Fotokapan'
        navTrap          = 'Fotokapan'
        trapTitle        = 'FOTOKAPAN · CPU SIÇRAMA KAYDEDİCİ'
        trapStRunning    = 'Çalışıyor'
        trapStStopped    = 'Durmuş'
        trapStMissing    = 'Kurulu değil'
        trapStUpdate     = 'Güncelleme var'
        trapStInsecure   = 'Güvenlik güncellemesi gerekli'
        trapDetail       = 'Son kontrol {0} · eşik %{1} · bu açılışta {2} sıçrama'
        trapDetailNone   = 'Kurulunca CPU %85 üstünde kaldığında sorumluları kaydeder; arayüz kapalıyken de çalışır.'
        btnTrapInstall   = 'Kur / Güncelle'
        btnTrapRemove    = 'Kaldır'
        btnTrapLog       = 'Log''u aç'
        trapTopTitle     = 'EN SIK SORUMLULAR · SON 7 GÜN'
        trapRecentTitle  = 'SON SIÇRAMALAR'
        trapPageSummary  = 'Özet'
        trapPageRecords  = 'Kayıtlar'
        trapDiagTitle    = 'TEŞHİS · SON 7 GÜN'
        trapHoursTitle   = 'SAATE GÖRE DAĞILIM'
        trapNoteScheduled = 'zamanlanmış görev'
        colProcess       = 'Süreç'
        colSpikes        = 'Sıçrama'
        colAvg           = 'Ort. pay'
        colLast          = 'Son'
        colTime          = 'Zaman'
        colDur           = 'Süre'
        colPeak          = 'Tepe'
        colCulprit       = 'Sorumlu'
        colNote          = 'Not'
        trapDrivers      = 'Sürücüler (kesme/DPC)'
        diag_defender_scan = 'Sıçramaların %{0} kadarı Defender taramasından. Zamanlanmış ve elle başlatılan taramaları bilgisayarı kullanmadığınız saatlere alın.'
        diag_defender_rt = 'Sıçramaların %{0} kadarı Defender''ın gerçek zamanlı taramasından; en çok taranan klasör: {2}. Güvendiğiniz bir çalışma klasörüyse yalnızca o klasör için dar bir istisna düşünün.'
        diag_drivers     = 'Sıçramaların %{0} kadarında yük hiçbir sürece ait değil (kesme/DPC): sürücü kaynaklı. Ekran kartı, ağ ve ses sürücülerini güncelleyin; LatencyMon ile doğrulayın.'
        diag_game        = 'Sıçramaların %{0} kadarı oyunlardan ({1}); oyun sırasında beklenen bir yük.'
        diag_devtools    = 'Sıçramaların %{0} kadarı geliştirici/AI araçlarından ({1}). Ağır derleme ve ajan görevlerini zamanlayın veya paralel iş sayısını sınırlayın.'
        diag_browser     = 'Sıçramaların %{0} kadarı tarayıcıdan ({1}). Ağır sekme ve uzantıları tarayıcının görev yöneticisinde (Shift+Esc) bulun.'
        diag_windows     = 'Sıçramaların %{0} kadarı Windows hizmetlerinden ({1}); güncelleme, dizinleme veya bakım görevleri olabilir.'
        diag_other       = 'Sıçramaların %{0} kadarı {1} kaynaklı.'
        diag_scheduled   = '{3} sıçrama zamanlanmış bir görevle başladı (en sık: {1}). Görev Zamanlayıcı''da çalışma saatlerini kontrol edin.'
        diag_none        = 'Son 7 günde kayıtlı sıçrama yok.'
        diagUnknownFolder = 'henüz bilinmiyor'
        trapNoteScan     = 'Defender taraması'
        trapNoteRealtime = 'Defender gerçek zamanlı'
        trapCut          = 'kesildi'
        trapOngoing      = 'sürüyor'
        trapSec          = '{0} sn'
        trapConfirmRemove = 'Fotokapan kaldırılsın mı? Kayıtlar silinmez.'
        trapNoLog        = 'Henüz fotokapan logu yok.'
        logTrapInstallStart = 'Fotokapan kuruluyor...'
        logTrapRemoveStart  = 'Fotokapan kaldırılıyor...'
        logTrapInstalled = 'Fotokapan kuruldu ve çalışıyor.'
        logTrapRemoved   = 'Fotokapan kaldırıldı (kayıtlar duruyor).'
        logTrapFailed    = 'Fotokapan işlemi başarısız (çıkış kodu {0}).'
        logTrapCancelled = 'Yönetici izni verilmedi, işlem iptal edildi.'
        logTrapNoScript  = 'fotokapan.ps1 OpenRelax klasöründe bulunamadı.'
        diskProgress     = 'Taranıyor: {0} klasör · {1}'
        diskRootFiles    = '(profil kökündeki dosyalar)'
        logDiskPartial   = 'Analiz 90 sn sınırında durdu; boyutlar alt sınırdır.'
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
        logRamSkipped    = '{0} süreç atlandı (ön plandaki, o an çalışan veya küçük).'
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
        logTaskTimeout   = 'İşlem 60 saniyedir ilerlemiyor, iptal edildi. Tekrar deneyebilirsiniz.'
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
        btnCleaningProgress = 'Cleaning · {0} files · {1}'
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
        cat_devcache     = 'Developer Caches (npm, pip, NuGet, Yarn)'
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
        trayTrap         = 'Spike Trap'
        navTrap          = 'Spike Trap'
        trapTitle        = 'SPIKE TRAP · CPU SPIKE RECORDER'
        trapStRunning    = 'Running'
        trapStStopped    = 'Stopped'
        trapStMissing    = 'Not installed'
        trapStUpdate     = 'Update available'
        trapStInsecure   = 'Security update required'
        trapDetail       = 'Last check {0} · threshold {1}% · {2} spikes since boot'
        trapDetailNone   = 'Once installed it records the culprits whenever CPU stays above 85%, even with this window closed.'
        btnTrapInstall   = 'Install / Update'
        btnTrapRemove    = 'Remove'
        btnTrapLog       = 'Open log'
        trapTopTitle     = 'TOP CULPRITS · LAST 7 DAYS'
        trapRecentTitle  = 'RECENT SPIKES'
        trapPageSummary  = 'Summary'
        trapPageRecords  = 'Records'
        trapDiagTitle    = 'DIAGNOSIS · LAST 7 DAYS'
        trapHoursTitle   = 'BY HOUR OF DAY'
        trapNoteScheduled = 'scheduled task'
        colProcess       = 'Process'
        colSpikes        = 'Spikes'
        colAvg           = 'Avg share'
        colLast          = 'Last'
        colTime          = 'Time'
        colDur           = 'Duration'
        colPeak          = 'Peak'
        colCulprit       = 'Culprit'
        colNote          = 'Note'
        trapDrivers      = 'Drivers (interrupt/DPC)'
        diag_defender_scan = 'Defender scans cause about {0}% of the spikes. Move scheduled and manual scans to hours when the PC is idle.'
        diag_defender_rt = 'About {0}% come from Defender''s real-time scanning; most-scanned folder: {2}. If you trust that working folder, consider a narrow exclusion for it alone.'
        diag_drivers     = 'In about {0}% the load belongs to no process (interrupts/DPC): a driver. Update graphics, network and audio drivers; confirm with LatencyMon.'
        diag_game        = 'About {0}% come from games ({1}) - expected while playing.'
        diag_devtools    = 'About {0}% come from developer/AI tools ({1}). Schedule heavy builds and agent jobs or limit their parallelism.'
        diag_browser     = 'About {0}% come from the browser ({1}). Find heavy tabs and extensions in its task manager (Shift+Esc).'
        diag_windows     = 'About {0}% come from Windows services ({1}): updates, indexing or maintenance.'
        diag_other       = 'About {0}% come from {1}.'
        diag_scheduled   = '{3} spikes started from a scheduled task (most often {1}). Check its times in Task Scheduler.'
        diag_none        = 'No spikes recorded in the last 7 days.'
        diagUnknownFolder = 'not known yet'
        trapNoteScan     = 'Defender scan'
        trapNoteRealtime = 'Defender real-time'
        trapCut          = 'cut off'
        trapOngoing      = 'ongoing'
        trapSec          = '{0} s'
        trapConfirmRemove = 'Remove the Spike Trap? Recorded logs are kept.'
        trapNoLog        = 'No Spike Trap log yet.'
        logTrapInstallStart = 'Installing Spike Trap...'
        logTrapRemoveStart  = 'Removing Spike Trap...'
        logTrapInstalled = 'Spike Trap installed and running.'
        logTrapRemoved   = 'Spike Trap removed (logs kept).'
        logTrapFailed    = 'Spike Trap action failed (exit code {0}).'
        logTrapCancelled = 'Administrator permission was not granted; cancelled.'
        logTrapNoScript  = 'fotokapan.ps1 was not found next to OpenRelax.'
        diskProgress     = 'Scanning: {0} folders · {1}'
        diskRootFiles    = '(files in the profile root)'
        logDiskPartial   = 'Analysis stopped at the 90 s limit; sizes are lower bounds.'
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
        logRamSkipped    = '{0} processes skipped (foreground, busy or small).'
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
        logTaskTimeout   = 'Task made no progress for 60s and was cancelled. You can try again.'
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
    # MinAgeHours: running apps (installers, dev/AI tools) keep working files
    # in temp; only files untouched for a day are considered junk.
    if (Test-Path $env:TEMP) { $p += @{ Path = $env:TEMP; Admin = $false; MinAgeHours = 24 } }
    $sysTemp = Join-Path $env:windir 'Temp'
    if (Test-Path $sysTemp) { $p += @{ Path = $sysTemp; Admin = $true; MinAgeHours = 24 } }
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

    # Developer package caches (opt-in): npm, pip, NuGet and Yarn re-download on demand
    $p = @()
    foreach ($c in @(
        (Join-Path $env:LOCALAPPDATA 'npm-cache\_cacache'),
        (Join-Path $env:LOCALAPPDATA 'pip\Cache'),
        (Join-Path $env:LOCALAPPDATA 'NuGet\v3-cache'),
        (Join-Path $env:LOCALAPPDATA 'Yarn\Cache')
    )) {
        if (Test-Path $c) { $p += @{ Path = $c; Admin = $false; MinAgeHours = 24 } }
    }
    $cats += @{ Key = 'devcache'; Paths = $p }

    # Recycle Bin (handled specially via Shell COM / Clear-RecycleBin)
    $cats += @{ Key = 'recycle'; Paths = @() }

    return , $cats
}

# Walks a folder tree for the cleaning engine. Never enters reparse points
# (junctions, symlinks), so nothing outside the tree can be counted or
# deleted, and an unreadable folder is skipped instead of ending the walk.
# Counts files last written before -Cutoff; with -Remove it deletes them
# (read-only ones too; locked ones are skipped) and then removes the folders
# left empty, deepest first. The time budget and the progress beat are
# checked by elapsed time - per folder and every 2048 entries - not by file
# count, so folders without files can neither overrun the budget nor starve
# the watchdog. Inside a worker, $Sync is the task's shared hashtable
# (visible through dynamic scope); in the headless modes it is $null.
function Invoke-JunkWalk {
    param(
        [string]$Root,
        [datetime]$Cutoff = [datetime]::MaxValue,
        [switch]$Remove,
        [int]$BudgetMs = 0,
        [switch]$ByTopFolder
    )
    $r = @{ Size = [long]0; Count = [long]0; Dirs = [long]0; Partial = $false; Folders = @{} }
    if (-not $Root -or -not [System.IO.Directory]::Exists($Root)) { return $r }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $nextBeat = [long]0; $sentCount = [long]0; $sentSize = [long]0; $n = 0
    $stack = New-Object 'System.Collections.Generic.Stack[object]'
    $stack.Push(@($Root, ''))
    $folders = New-Object 'System.Collections.Generic.List[string]'
    while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        $dir = [string]$item[0]; $top = [string]$item[1]
        $r.Dirs++
        $ms = $sw.ElapsedMilliseconds
        if ($BudgetMs -gt 0 -and $ms -gt $BudgetMs) { $r.Partial = $true; break }
        if ($ms -ge $nextBeat -and $Sync) {
            $nextBeat = $ms + 250
            $Sync.Beat = [DateTime]::UtcNow; $Sync.Step = $dir; $Sync.WalkInfo = @($r.Dirs, $top)
            if ($Remove) {
                $Sync.CleanDone = [long]$Sync.CleanDone + ($r.Count - $sentCount)
                $Sync.CleanBytes = [long]$Sync.CleanBytes + ($r.Size - $sentSize)
                $sentCount = $r.Count; $sentSize = $r.Size
            }
        }
        try { $entries = (New-Object System.IO.DirectoryInfo $dir).GetFileSystemInfos() } catch { continue }
        foreach ($e in $entries) {
            if ((++$n % 2048) -eq 0 -and $BudgetMs -gt 0 -and $sw.ElapsedMilliseconds -gt $BudgetMs) { $r.Partial = $true; break }
            if ($e.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            $t = $top
            if ($e -is [System.IO.DirectoryInfo]) {
                if (-not $t) { $t = $e.Name }
                $stack.Push(@($e.FullName, $t))
                if ($Remove) { $folders.Add($e.FullName) }
                continue
            }
            if ($e.LastWriteTime -ge $Cutoff) { continue }
            $len = $e.Length
            if ($Remove) {
                try {
                    if ($e.IsReadOnly) { $e.IsReadOnly = $false }
                    $e.Delete()
                } catch { continue }   # locked or in use
            }
            $r.Size += $len; $r.Count++
            if ($ByTopFolder) { $r.Folders[$t] = [long]$r.Folders[$t] + $len }
        }
        if ($r.Partial) { break }
    }
    if ($Remove) {
        # Longer paths are deeper: children go before their parents; only empty ones go
        foreach ($d in ($folders | Sort-Object -Property Length -Descending)) {
            try { [System.IO.Directory]::Delete($d) } catch {}
        }
        if ($Sync) {
            $Sync.CleanDone = [long]$Sync.CleanDone + ($r.Count - $sentCount)
            $Sync.CleanBytes = [long]$Sync.CleanBytes + ($r.Size - $sentSize)
        }
    }
    return $r
}

# BudgetSec > 0 caps the scan: a %TEMP% filled by dev/AI tooling can hold
# hundreds of thousands of folders and take minutes to walk. A capped scan
# returns a lower bound (Partial) instead of stalling.
function Measure-JunkPaths {
    param($Paths, [bool]$IsAdmin, [int]$BudgetSec = 0)
    $size = [long]0; $count = [long]0; $lockedSize = [long]0; $partial = $false
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($p in $Paths) {
        $left = 0
        if ($BudgetSec -gt 0) {
            $left = [int]($BudgetSec * 1000 - $sw.ElapsedMilliseconds)
            if ($left -le 0) { $partial = $true; break }
        }
        $cutoff = [datetime]::MaxValue
        if ($p.MinAgeHours) { $cutoff = (Get-Date).AddHours(-$p.MinAgeHours) }
        $w = Invoke-JunkWalk -Root $p.Path -Cutoff $cutoff -BudgetMs $left
        if ($IsAdmin -or -not $p.Admin) { $size += $w.Size; $count += $w.Count } else { $lockedSize += $w.Size }
        if ($w.Partial) { $partial = $true; break }
    }
    return @{ Size = $size; Count = $count; LockedSize = $lockedSize; Partial = $partial }
}

# Reads $Recycle.Bin directly instead of Shell.Application COM automation:
# the COM object is created on a background STA runspace with no message
# pump, and its cross-apartment calls can block indefinitely waiting for an
# LPC reply that only a pumping thread would service.
function Get-RecycleBinInfo {
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
    foreach ($p in $Paths) {
        if ($p.Admin -and -not $IsAdmin) { continue }
        $cutoff = [datetime]::MaxValue
        if ($p.MinAgeHours) { $cutoff = (Get-Date).AddHours(-$p.MinAgeHours) }
        $w = Invoke-JunkWalk -Root $p.Path -Cutoff $cutoff -Remove
        $bytes += $w.Size; $count += $w.Count
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

# Which processes to trim: never critical ones or ourselves, never the
# foreground app (a game, a call), never one busy during the sample (trimming
# it only buys page faults), and only those holding enough memory to matter.
function Select-TrimTargets {
    param($Processes, [int]$ForegroundPid, [hashtable]$CpuBefore, [hashtable]$CpuAfter, [double]$IntervalMs, [int]$CpuCount, [int]$SelfPid)
    $critical = @('csrss', 'wininit', 'winlogon', 'lsass', 'services', 'smss', 'dwm', 'fontdrvhost',
                  'Memory Compression', 'Registry', 'System', 'Idle', 'vmmem', 'audiodg')
    $targets = New-Object 'System.Collections.Generic.List[int]'
    foreach ($p in $Processes) {
        if ($p.Id -eq $SelfPid -or $p.Id -eq $ForegroundPid) { continue }
        if ($critical -contains $p.Name) { continue }
        if ([long]$p.WorkingSet -lt 30MB) { continue }
        if ($IntervalMs -gt 0 -and $CpuBefore.ContainsKey($p.Id) -and $CpuAfter.ContainsKey($p.Id)) {
            $pct = ($CpuAfter[$p.Id] - $CpuBefore[$p.Id]) / $IntervalMs / [Math]::Max(1, $CpuCount) * 100
            if ($pct -ge 1) { continue }
        }
        $targets.Add([int]$p.Id)
    }
    return , $targets
}

# Trims the working sets Select-TrimTargets picks from a 500 ms CPU sample.
# The reclaimed number is transient by nature: pages return as the processes
# touch them again. -DryRun only reports what would be trimmed.
function Invoke-RamTrim {
    param([switch]$DryRun)
    $before = [Win32Helper]::GetMemoryStatus().ullAvailPhys
    $fg = [int][Win32Helper]::GetForegroundProcessId()
    $cpu1 = @{}
    foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
        try { $cpu1[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds } catch {} finally { $p.Dispose() }
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Milliseconds 500
    $cpu2 = @{}
    $procs = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
        try {
            $cpu2[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds
            $procs.Add(@{ Id = $p.Id; Name = $p.ProcessName; WorkingSet = $p.WorkingSet64 })
        } catch {
            # not readable (protected or exited): not a candidate
        } finally { $p.Dispose() }
    }
    $targets = Select-TrimTargets -Processes $procs -ForegroundPid $fg -CpuBefore $cpu1 -CpuAfter $cpu2 `
        -IntervalMs $sw.Elapsed.TotalMilliseconds -CpuCount ([Environment]::ProcessorCount) -SelfPid $PID
    $skipped = $procs.Count - $targets.Count
    if ($DryRun) { return @{ Success = 0; Fail = 0; Saved = [long]0; Skipped = $skipped; Targets = $targets.ToArray() } }
    $ok = 0; $fail = 0
    foreach ($id in $targets) {
        try {
            $proc = [System.Diagnostics.Process]::GetProcessById($id)
            try { if ([Win32Helper]::EmptyWorkingSet($proc.Handle)) { $ok++ } else { $fail++ } } finally { $proc.Dispose() }
        } catch { $fail++ }
    }
    Start-Sleep -Milliseconds 300
    $after = [Win32Helper]::GetMemoryStatus().ullAvailPhys
    $saved = [long]0
    if ($after -gt $before) { $saved = [long]($after - $before) }
    return @{ Success = $ok; Fail = $fail; Saved = $saved; Skipped = $skipped }
}

# Serialized engine source, injected into every background runspace so the
# worker and the UI share a single implementation.
$script:EngineCode = ''
foreach ($fnName in 'Format-Bytes', 'Get-JunkCategories', 'Invoke-JunkWalk', 'Measure-JunkPaths', 'Get-RecycleBinInfo', 'Remove-JunkPaths', 'Invoke-WindowsUpdateCacheCleanup', 'Select-TrimTargets', 'Invoke-RamTrim') {
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
    $totalSize = [long]0; $totalCount = [long]0; $lockedSize = [long]0; $partial = $false
    foreach ($cat in $cats) {
        $Sync.Step = $cat.Key
        if ($cat.Key -eq 'recycle') {
            $info = Get-RecycleBinInfo
            $results[$cat.Key] = @{ Size = $info.Size; Count = $info.Count }
            $totalSize += $info.Size; $totalCount += $info.Count
        } else {
            $m = Measure-JunkPaths -Paths $cat.Paths -IsAdmin:$Opt.IsAdmin -BudgetSec 6
            $results[$cat.Key] = @{ Size = $m.Size; Count = $m.Count }
            $totalSize += $m.Size; $totalCount += $m.Count; $lockedSize += $m.LockedSize
            if ($m.Partial) { $partial = $true }
        }
    }
    $Sync.ScanResult = @{ Categories = $results; TotalSize = $totalSize; FileCount = $totalCount; LockedSize = $lockedSize; Partial = $partial }
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
    if ($ram.Skipped) { $Sync.Log.Enqueue(@{ Key = 'logRamSkipped'; Args = @($ram.Skipped); Type = 'info' }) }

    $Sync.Log.Enqueue(@{ Key = 'logCleanStart'; Type = 'info' })
    # Invoke-JunkWalk adds to these as it deletes; the pump shows them live
    $Sync.CleanDone = [long]0; $Sync.CleanBytes = [long]0; $Sync.Cleaning = $true
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
    # Progress off before the result, so the pump never shows a stale count after it
    $Sync.Cleaning = $false
    $Sync.CleanResult = @{ Bytes = $deletedBytes; Count = $deletedCount }
} catch {
    $Sync.Cleaning = $false
    $Sync.Log.Enqueue(@{ Text = "Clean error: $($_.Exception.Message)"; Type = 'error' })
    $Sync.CleanResult = @{ Bytes = 0; Count = 0 }
}
'@

$script:RamTaskCode = @'
param($Sync, $Opt)
try {
    $ram = Invoke-RamTrim
    $Sync.RamResult = @{ Saved = $ram.Saved; Skipped = $ram.Skipped }
} catch {
    $Sync.Log.Enqueue(@{ Text = "RAM task error: $($_.Exception.Message)"; Type = 'error' })
    $Sync.RamResult = @{ Saved = 0 }
}
'@

$script:DiskTaskCode = @'
param($Sync, $Opt)
try {
    $Sync.DiskRunning = $true
    # One bounded walk with per-folder totals instead of a full walk per folder
    $w = Invoke-JunkWalk -Root $Opt.Target -ByTopFolder -BudgetMs 90000
    $rows = foreach ($k in @($w.Folders.Keys)) { @{ Name = [string]$k; Size = [long]$w.Folders[$k] } }
    $top = @($rows | Sort-Object -Property @{ Expression = { $_.Size } } -Descending | Select-Object -First 10)
    $Sync.DiskRunning = $false
    $Sync.DiskResult = @{ Rows = $top; Count = $w.Folders.Count; Partial = $w.Partial }
} catch {
    $Sync.DiskRunning = $false
    $Sync.Log.Enqueue(@{ Text = "Disk analysis error: $($_.Exception.Message)"; Type = 'error' })
    $Sync.DiskResult = @{ Rows = @(); Count = 0; Partial = $false }
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

#region 5b. Fotokapan (CPU spike trap) integration
# The trap runs as a SYSTEM scheduled task (fotokapan.ps1) so it keeps sampling
# while this GUI is starved, frozen or closed. OpenRelax installs it and reads
# its machine-readable output: durum.json (heartbeat) and spikes-YYYY-MM.jsonl.
$script:TrapTaskName = 'OpenRelax Fotokapan'
$script:TrapDir      = Join-Path $env:ProgramData 'OpenRelax\Fotokapan'
# Test hook: tests\gui-stress.ps1 points the view at a synthetic data set
if ($env:OPENRELAX_TRAP_DIR) { $script:TrapDir = $env:OPENRELAX_TRAP_DIR }
$script:TrapScript   = Join-Path (Split-Path -Parent $script:ScriptPath) 'fotokapan.ps1'
$script:TrapCache    = @{}

# The trap appends to / swaps these files while we read them: share everything.
function Read-SharedText([string]$Path) {
    $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]'ReadWrite, Delete')
    try {
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        return $sr.ReadToEnd()
    } finally {
        $fs.Dispose()
    }
}

# True when an identity other than SYSTEM or Administrators may change the
# path (write, delete or re-permission it): the SYSTEM task would then run
# code that a standard-user process could have swapped in.
function Test-TrapAclWritableByUsers([string]$Path) {
    $trusted = @('S-1-5-18', 'S-1-5-32-544')
    $write = [int]([System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, WriteAttributes, Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership') -bor 0x10000000 -bor 0x40000000   # + GENERIC_ALL, GENERIC_WRITE
    foreach ($ace in (Get-Acl -LiteralPath $Path).Access) {
        if ($ace.AccessControlType -ne 'Allow') { continue }
        if ($ace.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
        $sid = [string]$ace.IdentityReference
        try { $sid = $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch {}
        if ($trusted -contains $sid) { continue }
        if (([int]$ace.FileSystemRights -band $write) -ne 0) { return $true }
    }
    return $false
}

function Get-TrapState {
    param([string]$Dir = $script:TrapDir)
    $st = @{ Installed = $false; Running = $false; Outdated = $false; Insecure = $false; Beat = $null; Threshold = 85; Spikes = 0 }
    $taskKnown = $true; $taskFound = $false; $taskRunning = $false
    try {
        $svc = New-Object -ComObject Schedule.Service
        $svc.Connect()
        $task = $svc.GetFolder('\').GetTask($script:TrapTaskName)
        $taskFound = $true
        $taskRunning = ($task.State -eq 4)   # TASK_STATE_RUNNING
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($task)
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($svc)
    } catch {
        # 0x80070002 = no such task. Anything else (a standard user may not be
        # allowed to read a SYSTEM task) leaves the answer to the heartbeat.
        $hr = $_.Exception.HResult
        if ($_.Exception.InnerException) { $hr = $_.Exception.InnerException.HResult }
        if ($hr -ne -2147024894) { $taskKnown = $false }
    }
    $beatFile = Join-Path $Dir 'durum.json'
    if (Test-Path -LiteralPath $beatFile) {
        try {
            $b = (Read-SharedText $beatFile) | ConvertFrom-Json
            $st.Beat = [datetime]::ParseExact([string]$b.t, 's', [System.Globalization.CultureInfo]::InvariantCulture)
            $st.Threshold = [int]$b.threshold
            $st.Spikes = [int]$b.spikes
        } catch {}
    }
    # The heartbeat is rewritten every minute; a stuck or dead monitor goes stale.
    $fresh = [bool]($st.Beat -and ((Get-Date) - $st.Beat).TotalSeconds -lt 180)
    if ($taskKnown) {
        $st.Installed = $taskFound
        $st.Running = $taskRunning -and $fresh
    } else {
        $st.Installed = $fresh
        $st.Running = $fresh
    }
    $installed = Join-Path $Dir 'fotokapan.ps1'
    if ($st.Installed -and (Test-Path -LiteralPath $installed) -and (Test-Path -LiteralPath $script:TrapScript)) {
        try { $st.Outdated = (Get-FileHash -LiteralPath $installed).Hash -ne (Get-FileHash -LiteralPath $script:TrapScript).Hash } catch {}
    }
    # Installs before 2.1.1 let the installing user change the script SYSTEM runs
    if ($st.Installed -and (Test-Path -LiteralPath $installed)) {
        try { $st.Insecure = (Test-TrapAclWritableByUsers $Dir) -or (Test-TrapAclWritableByUsers $installed) } catch {}
    }
    return $st
}

# Records of the last $Days days, oldest first. Parsed files are cached by
# length, so a refresh with no new spikes costs a stat call per file.
function Read-TrapRecords {
    param([string]$Dir = $script:TrapDir, [int]$Days = 7)
    $cutoff = (Get-Date).AddDays(-$Days).ToString('s')
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($month in @((Get-Date).AddMonths(-1), (Get-Date))) {
        $path = Join-Path $Dir ('spikes-{0:yyyy-MM}.jsonl' -f $month)
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $len = (Get-Item -LiteralPath $path).Length
        $c = $script:TrapCache[$path]
        if (-not $c -or $c.Length -ne $len) {
            $items = New-Object System.Collections.Generic.List[object]
            # Old lines are skipped by their ISO timestamp prefix without being
            # parsed; a line still being appended has no closing brace yet.
            $lines = @((Read-SharedText $path) -split "`n" | Where-Object {
                $_.Length -gt 25 -and $_.StartsWith('{"t":"') -and $_.TrimEnd().EndsWith('}') -and $_.Substring(6, 19) -ge $cutoff })
            if ($lines.Count) {
                try {
                    foreach ($r in ('[' + ($lines -join ',') + ']' | ConvertFrom-Json)) { $items.Add($r) }
                } catch {
                    # A damaged line spoils the batch parse: fall back to line by line.
                    $items.Clear()
                    foreach ($l in $lines) { try { $items.Add(($l | ConvertFrom-Json)) } catch {} }
                }
            }
            $c = @{ Length = $len; Items = $items }
            $script:TrapCache[$path] = $c
        }
        foreach ($r in $c.Items) { if ([string]$r.t -ge $cutoff) { $all.Add($r) } }
    }
    return , $all
}

# Pairs start/end records into episodes. A 'monitor' record (trap restarted)
# or a new start closes an episode whose end was never written.
function Get-TrapEpisodes {
    param($Records)
    $episodes = New-Object System.Collections.Generic.List[object]
    $open = $null
    foreach ($r in $Records) {
        switch ([string]$r.kind) {
            'start' {
                if ($open) { $open.Cut = $true }
                $open = @{ Start = $r; Duration = $null; Peak = $null; Cut = $false; Defender = $r.defender }
                $episodes.Add($open)
            }
            'ongoing' { if ($open -and -not $open.Defender) { $open.Defender = $r.defender } }
            'end'     { if ($open) { $open.Duration = $r.durationSec; $open.Peak = $r.peak; $open = $null } }
            'monitor' { if ($open) { $open.Cut = $true; $open = $null } }
        }
    }
    return , $episodes
}

# The main culprit of an episode: its top process, unless CPU time that no
# process accounts for (interrupts/DPCs, i.e. drivers) outweighs it.
function Get-TrapCulprit($Start) {
    $top = @($Start.top | Where-Object { $_ })
    $unattributed = [double]$Start.total - [double]$Start.attributed
    if ($top.Count -eq 0 -or $unattributed -gt [double]$top[0].pct) {
        return @{ Name = '*drivers*'; Pct = [Math]::Max(0, $unattributed) }
    }
    return @{ Name = [string]$top[0].name; Pct = [double]$top[0].pct }
}

function Get-TrapCulprits {
    param($Episodes)
    $by = @{}
    foreach ($ep in $Episodes) {
        $c = Get-TrapCulprit $ep.Start
        $e = $by[$c.Name]
        if (-not $e) { $e = @{ Name = $c.Name; Count = 0; Sum = 0.0; Last = '' }; $by[$c.Name] = $e }
        $e.Count++
        $e.Sum += $c.Pct
        if ([string]$ep.Start.t -gt $e.Last) { $e.Last = [string]$ep.Start.t }
    }
    return @($by.Values | Sort-Object -Property @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { $_.Sum }; Descending = $true })
}

function ConvertFrom-TrapTime([string]$Iso) {
    return [datetime]::ParseExact($Iso, 's', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-TrapCulpritText([string]$Name) {
    if ($Name -eq '*drivers*') { return (T 'trapDrivers') }
    return $Name
}

# Coarse category of a culprit process, matched by name (wildcards allowed).
# The lists stay short on purpose: unknown names are simply 'other'.
function Get-TrapCategory([string]$Name) {
    $map = [ordered]@{
        defender = 'MsMpEng.exe', 'MpDefenderCoreService.exe', 'NisSrv.exe', 'MsSense.exe', 'MpCmdRun.exe', 'SecurityHealthService.exe'
        game     = '*Shipping.exe', 'League of Legends.exe', 'LeagueClient*.exe', 'TFTClient*.exe', 'Riot*.exe', 'vgc.exe', 'VALORANT*.exe',
                   'steam.exe', 'steamwebhelper.exe', 'EpicGamesLauncher.exe', 'cs2.exe', 'dota2.exe', 'HD-Player.exe', 'Bluestacks*.exe'
        devtools = 'node.exe', 'python*.exe', 'py.exe', 'java.exe', 'javaw.exe', 'gradle*.exe', 'dotnet.exe', 'MSBuild.exe', 'VBCSCompiler.exe',
                   'cl.exe', 'link.exe', 'rustc.exe', 'cargo.exe', 'go.exe', 'git.exe', 'pwsh.exe', 'powershell.exe', 'codex*.exe', 'claude.exe',
                   'ChatGPT.exe', 'Code.exe', 'devenv.exe', 'idea64.exe', 'studio64.exe', 'Docker*.exe', 'com.docker*.exe', 'vmmem*', 'wsl*.exe',
                   'bun.exe', 'deno.exe', 'esbuild.exe', 'tsc.exe'
        browser  = 'chrome.exe', 'msedge.exe', 'msedgewebview2.exe', 'firefox.exe', 'brave.exe', 'opera.exe', 'vivaldi.exe'
        windows  = 'System', 'Registry', 'MemCompression', 'svchost.exe', 'TiWorker.exe', 'TrustedInstaller.exe', 'MoUsoCoreWorker.exe',
                   'wuauclt.exe', 'SearchIndexer.exe', 'SearchProtocolHost.exe', 'SearchFilterHost.exe', 'CompatTelRunner.exe', 'WmiPrvSE.exe',
                   'dwm.exe', 'explorer.exe', 'sihost.exe', 'RuntimeBroker.exe', 'audiodg.exe', 'lsass.exe', 'csrss.exe', 'services.exe',
                   'dllhost.exe', 'taskhostw.exe', 'msiexec.exe'
    }
    foreach ($cat in $map.Keys) {
        foreach ($pattern in $map[$cat]) { if ($Name -like $pattern) { return $cat } }
    }
    return 'other'
}

# Started by Task Scheduler: COM-handler tasks run under taskhostw.exe,
# program tasks are children of the svchost instance hosting "Schedule".
function Test-TrapScheduled($Top) {
    if (-not $Top) { return $false }
    if ([string]$Top.parent -eq 'taskhostw.exe') { return $true }
    return ([string]$Top.parent -eq 'svchost.exe' -and [string]$Top.parentCmd -match '\s-s\s+Schedule\b')
}

# Turns episodes into findings: one per culprit category (count, share of all
# spikes, most frequent process) plus one for spikes started by scheduled
# tasks. A Defender finding says whether on-demand scans or real-time
# scanning dominate and names the folder Defender scanned most.
function Get-TrapDiagnosis {
    param($Episodes)
    $findings = New-Object System.Collections.Generic.List[object]
    # .Count, not @($Episodes).Count: PS 5.1 throws "Argument types do not
    # match" for @() around a List[object] variable
    $total = 0
    if ($Episodes) { $total = $Episodes.Count }
    if ($total -eq 0) { return }   # findings go to the pipeline: callers collect with @()
    $groups = @{}; $scheduled = @{}; $scheduledCount = 0; $defScan = 0; $defFolder = ''
    foreach ($ep in $Episodes) {
        $c = Get-TrapCulprit $ep.Start
        if ($c.Name -eq '*drivers*') { $cat = 'drivers' } else { $cat = Get-TrapCategory $c.Name }
        if (-not $groups.ContainsKey($cat)) { $groups[$cat] = @{ Count = 0; Names = @{} } }
        $groups[$cat].Count++
        $groups[$cat].Names[$c.Name] = 1 + [int]$groups[$cat].Names[$c.Name]
        $top0 = @($ep.Start.top | Where-Object { $_ }) | Select-Object -First 1
        if (Test-TrapScheduled $top0) {
            $scheduledCount++
            $scheduled[[string]$top0.name] = 1 + [int]$scheduled[[string]$top0.name]
        }
        if ($cat -eq 'defender') {
            if ($ep.Defender -eq 'scan') { $defScan++ }
            $dt = $ep.Start.defenderTop
            if ($dt -and @($dt.folders).Count) { $defFolder = [string]@($dt.folders)[0].path }
        }
    }
    foreach ($cat in $groups.Keys) {
        $g = $groups[$cat]
        $key = 'diag_' + $cat; $detail = ''
        if ($cat -eq 'defender') {
            if ($defScan * 2 -ge $g.Count) { $key = 'diag_defender_scan' } else { $key = 'diag_defender_rt'; $detail = $defFolder }
        }
        $findings.Add(@{ Category = $cat; Key = $key; Count = $g.Count; Share = [int][Math]::Round(100.0 * $g.Count / $total)
            Top = ($g.Names.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1).Key; Detail = $detail })
    }
    if ($scheduledCount -gt 0) {
        $findings.Add(@{ Category = 'scheduled'; Key = 'diag_scheduled'; Count = $scheduledCount; Share = [int][Math]::Round(100.0 * $scheduledCount / $total)
            Top = ($scheduled.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1).Key; Detail = '' })
    }
    return $findings | Sort-Object -Property @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { $_.Category } }
}

function Format-TrapFinding($Finding) {
    $detail = [string]$Finding.Detail
    if (-not $detail) { $detail = (T 'diagUnknownFolder') }
    return [string]::Format((T $Finding.Key), $Finding.Share, (Get-TrapCulpritText $Finding.Top), $detail, $Finding.Count)
}

# Spike starts per hour of the day (local time) - periodic jobs stand out.
function Get-TrapHourHistogram {
    param($Episodes)
    $h = New-Object int[] 24
    foreach ($ep in $Episodes) { $h[(ConvertFrom-TrapTime ([string]$ep.Start.t)).Hour]++ }
    return , $h
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
    Write-Host "OpenRelax v$script:AppVersion $script:AppEdition self-test (read-only scan)"
    Write-Host "Admin: $script:IsAdmin | Settings: $script:SettingsFile"
    $grandSize = [long]0; $grandCount = [long]0; $grandLocked = [long]0
    foreach ($cat in (Get-JunkCategories)) {
        if ($cat.Key -eq 'recycle') {
            $info = Get-RecycleBinInfo
            Write-Host ("  {0,-10} {1,10}  ({2} items)" -f $cat.Key, (Format-Bytes $info.Size), $info.Count)
            $grandSize += $info.Size; $grandCount += $info.Count
        } else {
            $m = Measure-JunkPaths -Paths $cat.Paths -IsAdmin:$script:IsAdmin -BudgetSec 6
            $note = ''
            if ($m.Partial) { $note = ' [partial: 6s budget hit, size is a lower bound]' }
            Write-Host ("  {0,-10} {1,10}  ({2} files, {3} paths, locked {4}){5}" -f $cat.Key, (Format-Bytes $m.Size), $m.Count, @($cat.Paths).Count, (Format-Bytes $m.LockedSize), $note)
            $grandSize += $m.Size; $grandCount += $m.Count; $grandLocked += $m.LockedSize
        }
    }
    Write-Host "Total cleanable: $(Format-Bytes $grandSize) in $grandCount files (admin-locked: $(Format-Bytes $grandLocked))"
    $ts = Get-TrapState
    $beat = 'none'
    if ($ts.Beat) { $beat = $ts.Beat.ToString('yyyy-MM-dd HH:mm:ss') }
    Write-Host ("Fotokapan: installed={0} running={1} outdated={2} heartbeat={3} threshold={4}" -f $ts.Installed, $ts.Running, $ts.Outdated, $beat, $ts.Threshold)
    $episodes = Get-TrapEpisodes (Read-TrapRecords)
    Write-Host ("  spikes in the last 7 days: {0}" -f $episodes.Count)
    foreach ($c in (Get-TrapCulprits $episodes | Select-Object -First 3)) {
        Write-Host ("  culprit {0,-28} x{1,-4} avg {2:N0}%" -f $c.Name, $c.Count, ($c.Sum / $c.Count))
    }
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

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        // 0 when no window has the focus (e.g. a locked or headless session)
        public static uint GetForegroundProcessId() {
            uint pid;
            GetWindowThreadProcessId(GetForegroundWindow(), out pid);
            return pid;
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
$script:Sync.Beat = [DateTime]::UtcNow
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
$titleLabel.Text = "OpenRelax PC Care v$script:AppVersion $script:AppEdition"
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
$btnNavTrap = New-Object System.Windows.Forms.Button
$navButtons = @($btnNavDash, $btnNavSettings, $btnNavDisk, $btnNavTrap)
$navTags = @('dash', 'settings', 'disk', 'trap')
$navX = 18
for ($i = 0; $i -lt $navButtons.Count; $i++) {
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

$viewTrap = New-Object System.Windows.Forms.Panel
$viewTrap.Size = New-Object System.Drawing.Size(644, 412)
$viewTrap.Location = New-Object System.Drawing.Point(0, 0)
$viewTrap.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$viewTrap.Visible = $false
$contentHost.Controls.Add($viewTrap)

function Show-View {
    param([string]$Name)
    $script:ActiveView = $Name
    $viewDash.Visible = ($Name -eq 'dash')
    $viewSettings.Visible = ($Name -eq 'settings')
    $viewDisk.Visible = ($Name -eq 'disk')
    $viewTrap.Visible = ($Name -eq 'trap')
    if ($Name -eq 'trap') { Update-TrapView }
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
$btnNavTrap.add_Click($script:NavClickHandler)
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

$catKeys = @('temp', 'browser', 'discord', 'shader', 'wer', 'wu', 'gpusetup', 'devcache', 'recycle')
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
    $catY += 38   # nine rows fit the 400 px card
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
        # Hidden like launch.bat: closing a stray console window would kill the app
        Start-Process -FilePath $script:PsExe -ArgumentList @('-STA', '-WindowStyle', 'Hidden', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:ScriptPath`"") -Verb RunAs
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

#region 14b. Fotokapan (spike trap) view
function New-TrapLabel($Parent, $X, $Y, $Size, $Bold, $Color) {
    $l = New-Object System.Windows.Forms.Label
    $style = [System.Drawing.FontStyle]::Regular
    if ($Bold) { $style = [System.Drawing.FontStyle]::Bold }
    $l.Font = New-Object System.Drawing.Font("Segoe UI", $Size, $style)
    $l.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($Color)
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.AutoSize = $true
    $Parent.Controls.Add($l)
    return $l
}

function New-TrapButton($Parent, $X, $Y, $Color) {
    $b = New-Object System.Windows.Forms.Button
    $b.Size = New-Object System.Drawing.Size(104, 30)
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml($Color)
    $b.FlatAppearance.BorderSize = 1
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($Color)
    $b.BackColor = [System.Drawing.Color]::Transparent
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Parent.Controls.Add($b)
    return $b
}

function New-TrapList($Parent, $X, $Y, $W, $H, [int[]]$Widths) {
    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point($X, $Y)
    $lv.Size = New-Object System.Drawing.Size($W, $H)
    $lv.View = [System.Windows.Forms.View]::Details
    $lv.FullRowSelect = $true
    $lv.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
    $lv.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#E2E8F0')
    $lv.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $lv.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lv.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
    foreach ($w in $Widths) { [void]$lv.Columns.Add('', $w) }
    $Parent.Controls.Add($lv)
    return $lv
}

$trapCard = Create-Card $viewTrap (New-Object System.Drawing.Point(0, 4)) (New-Object System.Drawing.Size(644, 96))
$trapTitle = New-TrapLabel $trapCard 12 10 7.5 $true '#94A3B8'
$lblTrapState = New-TrapLabel $trapCard 12 26 13 $true '#64748B'
$lblTrapDetail = New-TrapLabel $trapCard 12 56 8 $false '#64748B'
$lblTrapDetail.AutoSize = $false
$lblTrapDetail.Size = New-Object System.Drawing.Size(284, 36)
$btnTrapInstall = New-TrapButton $trapCard 304 56 '#3B82F6'
$btnTrapRemove = New-TrapButton $trapCard 416 56 '#F87171'
$btnTrapLog = New-TrapButton $trapCard 528 56 '#94A3B8'

# Page switch inside the status card: summary (diagnosis) / records (every spike)
function New-TrapPageButton($X, [string]$Page) {
    $b = New-Object System.Windows.Forms.Button
    $b.Size = New-Object System.Drawing.Size(80, 24)
    $b.Location = New-Object System.Drawing.Point($X, 8)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 0
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Tag = $Page
    $trapCard.Controls.Add($b)
    Set-RoundedRegion $b 8
    return $b
}
$btnTrapPageSummary = New-TrapPageButton 468 'summary'
$btnTrapPageRecords = New-TrapPageButton 552 'records'
Register-CardHover $trapCard

function New-TrapPage {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point(0, 106)
    $p.Size = New-Object System.Drawing.Size(644, 306)
    $p.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
    $viewTrap.Controls.Add($p)
    return $p
}
$trapPageSummary = New-TrapPage
$trapPageRecords = New-TrapPage
$trapPageRecords.Visible = $false

# Summary page: full-width diagnosis (advice texts can run to ~200 characters),
# then the culprit table with the hour-of-day distribution beside it
$trapDiagCard = Create-Card $trapPageSummary (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(644, 168))
$trapDiagTitle = New-TrapLabel $trapDiagCard 12 8 7.5 $true '#94A3B8'
$lblTrapDiag = @()
foreach ($i in 0..2) {
    $l = New-TrapLabel $trapDiagCard 12 (28 + $i * 44) 8 $false '#CBD5E1'
    $l.AutoSize = $false
    $l.Size = New-Object System.Drawing.Size(620, 42)
    $lblTrapDiag += $l
}
Register-CardHover $trapDiagCard

$trapTopCard = Create-Card $trapPageSummary (New-Object System.Drawing.Point(0, 174)) (New-Object System.Drawing.Size(644, 132))
$trapTopTitle = New-TrapLabel $trapTopCard 12 8 7.5 $true '#94A3B8'
# Column widths leave room for the vertical scrollbar (no horizontal one)
$lvTrapTop = New-TrapList $trapTopCard 12 28 392 96 @(170, 55, 70, 75)
$trapHoursTitle = New-TrapLabel $trapTopCard 416 8 7.5 $true '#94A3B8'
$pnlTrapHours = New-Object System.Windows.Forms.Panel
$pnlTrapHours.Location = New-Object System.Drawing.Point(416, 28)
$pnlTrapHours.Size = New-Object System.Drawing.Size(216, 96)
$pnlTrapHours.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#161F30')
$trapTopCard.Controls.Add($pnlTrapHours)
$script:TrapHours = New-Object int[] 24
# 24 bars, the busiest hour in amber; every GDI object is disposed per paint
$pnlTrapHours.add_Paint({
    param($sender, $e)
    $h = $script:TrapHours
    $max = ($h | Measure-Object -Maximum).Maximum
    $chartH = $sender.Height - 16
    $barW = [Math]::Floor($sender.Width / 24)
    $bar = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#3B82F6'))
    $peak = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#F59E0B'))
    $axis = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#64748B'))
    $font = New-Object System.Drawing.Font('Segoe UI', 7)
    try {
        for ($i = 0; $i -lt 24; $i++) {
            $x = $i * $barW
            if ($max -gt 0 -and $h[$i] -gt 0) {
                $bh = [Math]::Max(2, [int]($chartH * $h[$i] / $max))
                $brush = $bar
                if ($h[$i] -eq $max) { $brush = $peak }
                $e.Graphics.FillRectangle($brush, $x + 1, $chartH - $bh, $barW - 2, $bh)
            }
            if (($i % 6) -eq 0) { $e.Graphics.DrawString(('{0:D2}' -f $i), $font, $axis, [single]$x, [single]($chartH + 2)) }
        }
    } finally {
        $bar.Dispose(); $peak.Dispose(); $axis.Dispose(); $font.Dispose()
    }
})
Register-CardHover $trapTopCard

# Records page: every spike of the last 7 days
$trapRecentCard = Create-Card $trapPageRecords (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(644, 306))
$trapRecentTitle = New-TrapLabel $trapRecentCard 12 8 7.5 $true '#94A3B8'
$lvTrapRecent = New-TrapList $trapRecentCard 12 36 620 262 @(110, 64, 56, 246, 110)
Register-CardHover $trapRecentCard

function Show-TrapPage([string]$Page) {
    $script:TrapPage = $Page
    $trapPageSummary.Visible = ($Page -eq 'summary')
    $trapPageRecords.Visible = ($Page -eq 'records')
    foreach ($b in $btnTrapPageSummary, $btnTrapPageRecords) {
        if ($b.Tag -eq $Page) {
            $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
            $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#1E293B')
        } else {
            $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
            $b.BackColor = [System.Drawing.Color]::Transparent
        }
    }
}
$script:TrapPageClick = {
    param($sender, $e)
    Show-TrapPage $sender.Tag
}
$btnTrapPageSummary.add_Click($script:TrapPageClick)
$btnTrapPageRecords.add_Click($script:TrapPageClick)
Show-TrapPage 'summary'

$script:TrapDiagColors = @{
    defender = '#F59E0B'; drivers = '#F87171'; game = '#A78BFA'; devtools = '#38BDF8'
    browser = '#34D399'; windows = '#94A3B8'; scheduled = '#FBBF24'; other = '#CBD5E1'
}

$script:TrapProc = $null
$script:TrapLastState = $null
$script:TrapSig = $null


function Set-TrapStateLabel($St) {
    if (-not $St.Installed)  { $key = 'trapStMissing';  $color = '#64748B' }
    elseif ($St.Insecure)    { $key = 'trapStInsecure'; $color = '#F87171' }
    elseif ($St.Outdated)    { $key = 'trapStUpdate';   $color = '#3B82F6' }
    elseif ($St.Running)     { $key = 'trapStRunning';  $color = '#10B981' }
    else                     { $key = 'trapStStopped';  $color = '#F59E0B' }
    $lblTrapState.Text = (T $key)
    $lblTrapState.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($color)
    if ($St.Installed -and $St.Beat) {
        $lblTrapDetail.Text = [string]::Format((T 'trapDetail'), $St.Beat.ToString('HH:mm:ss'), $St.Threshold, $St.Spikes)
    } else {
        $lblTrapDetail.Text = (T 'trapDetailNone')
    }
}

function Update-TrapButtons {
    $idle = -not $script:TrapProc
    $btnTrapInstall.Enabled = $idle
    $btnTrapRemove.Enabled = $idle -and $script:TrapLastState -and $script:TrapLastState.Installed
}

function Update-TrapContent($Episodes, $St) {
    # Diagnosis: the three largest findings, coloured by category
    $findings = @(Get-TrapDiagnosis $Episodes)
    for ($i = 0; $i -lt 3; $i++) {
        $l = $lblTrapDiag[$i]
        if ($i -lt $findings.Count) {
            $l.Text = [char]0x2022 + ' ' + (Format-TrapFinding $findings[$i])
            $l.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($script:TrapDiagColors[[string]$findings[$i].Category])
        } elseif ($i -eq 0) {
            $l.Text = (T 'diag_none')
            $l.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
        } else {
            $l.Text = ''
        }
    }
    $script:TrapHours = Get-TrapHourHistogram $Episodes
    $pnlTrapHours.Invalidate()

    $lvTrapTop.BeginUpdate()
    $lvTrapTop.Items.Clear()
    foreach ($c in (Get-TrapCulprits $Episodes | Select-Object -First 8)) {
        $item = New-Object System.Windows.Forms.ListViewItem((Get-TrapCulpritText $c.Name))
        [void]$item.SubItems.Add([string]$c.Count)
        [void]$item.SubItems.Add(('{0:N0}%' -f ($c.Sum / $c.Count)))
        [void]$item.SubItems.Add((ConvertFrom-TrapTime $c.Last).ToString('dd.MM HH:mm'))
        [void]$lvTrapTop.Items.Add($item)
    }
    $lvTrapTop.EndUpdate()

    $lvTrapRecent.BeginUpdate()
    $lvTrapRecent.Items.Clear()
    for ($i = $Episodes.Count - 1; $i -ge [Math]::Max(0, $Episodes.Count - 30); $i--) {
        $ep = $Episodes[$i]
        $c = Get-TrapCulprit $ep.Start
        if ($null -ne $ep.Duration) { $dur = [string]::Format((T 'trapSec'), $ep.Duration) }
        elseif ($ep.Cut -or -not $St.Running) { $dur = (T 'trapCut') }
        else { $dur = (T 'trapOngoing') }
        $peak = ''
        if ($null -ne $ep.Peak) { $peak = '{0}%' -f $ep.Peak }
        $notes = @()
        if ($ep.Defender -eq 'scan') { $notes += (T 'trapNoteScan') }
        elseif ($ep.Defender -eq 'realtime') { $notes += (T 'trapNoteRealtime') }
        $top0 = @($ep.Start.top | Where-Object { $_ }) | Select-Object -First 1
        if (Test-TrapScheduled $top0) { $notes += (T 'trapNoteScheduled') }
        $note = $notes -join ', '
        $item = New-Object System.Windows.Forms.ListViewItem((ConvertFrom-TrapTime $ep.Start.t).ToString('dd.MM HH:mm:ss'))
        [void]$item.SubItems.Add($dur)
        [void]$item.SubItems.Add($peak)
        [void]$item.SubItems.Add(('{0}  {1:N0}%' -f (Get-TrapCulpritText $c.Name), $c.Pct))
        [void]$item.SubItems.Add($note)
        [void]$lvTrapRecent.Items.Add($item)
    }
    $lvTrapRecent.EndUpdate()
}

function Update-TrapView {
    try {
        $st = Get-TrapState
        $script:TrapLastState = $st
        Set-TrapStateLabel $st
        $records = Read-TrapRecords
        # Rebuild the lists only when the data, the language or the state changed.
        $last = ''
        if ($records.Count) { $last = [string]$records[$records.Count - 1].t }
        $sig = '{0}|{1}|{2}|{3}' -f $records.Count, $last, $script:Settings.language, $st.Running
        if ($sig -ne $script:TrapSig) {
            $script:TrapSig = $sig
            Update-TrapContent (Get-TrapEpisodes $records) $st
        }
        Update-TrapButtons
    } catch {
        if (-not $script:TrapErrorShown) {
            $script:TrapErrorShown = $true
            Write-Log ([string]::Format((T 'logError'), $_.Exception.Message)) 'error'
        }
    }
}

function Start-TrapAction([string]$Mode) {
    if ($script:TrapProc) { Write-Log (T 'logBusy') 'warn'; return }
    if (-not (Test-Path -LiteralPath $script:TrapScript)) { Write-Log (T 'logTrapNoScript') 'error'; return }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f $script:TrapScript), ('-' + $Mode))
    $sp = @{ FilePath = $script:PsExe; ArgumentList = $argList; PassThru = $true; WindowStyle = 'Hidden' }
    # Registering a SYSTEM task needs elevation: ask through UAC when not admin.
    if (-not $script:IsAdmin) { $sp.Verb = 'RunAs' }
    try {
        $script:TrapProc = Start-Process @sp
        $script:TrapMode = $Mode
        $script:TrapStarted = Get-Date
        if ($Mode -eq 'Install') { Write-Log (T 'logTrapInstallStart') 'info' } else { Write-Log (T 'logTrapRemoveStart') 'info' }
    } catch {
        $script:TrapProc = $null
        if ($_.Exception.Message -match 'cancel|iptal') { Write-Log (T 'logTrapCancelled') 'warn' }
        else { Write-Log ([string]::Format((T 'logError'), $_.Exception.Message)) 'error' }
    }
    Update-TrapButtons
}

# Polled by the pump timer: reports how the install/uninstall run ended.
function Complete-TrapAction {
    $done = $false; $code = $null
    try {
        if ($script:TrapProc.HasExited) { $done = $true; $code = $script:TrapProc.ExitCode }
    } catch {
        # No access to the elevated process: give it time, then just refresh.
        $done = ((Get-Date) - $script:TrapStarted).TotalSeconds -gt 20
    }
    if (-not $done) { return }
    if ($code -eq 0) {
        if ($script:TrapMode -eq 'Install') { Write-Log (T 'logTrapInstalled') 'success' } else { Write-Log (T 'logTrapRemoved') 'success' }
    } elseif ($null -ne $code) {
        Write-Log ([string]::Format((T 'logTrapFailed'), $code)) 'error'
    }
    try { $script:TrapProc.Dispose() } catch {}
    $script:TrapProc = $null
    $script:TrapSig = $null
    Update-TrapView
}

$btnTrapInstall.add_Click({ Start-TrapAction 'Install' })
$btnTrapRemove.add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show((T 'trapConfirmRemove'), 'OpenRelax',
        [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) { Start-TrapAction 'Uninstall' }
})
$btnTrapLog.add_Click({
    $log = Get-ChildItem -LiteralPath $script:TrapDir -Filter 'fotokapan-*.log' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($log) { Start-Process notepad.exe -ArgumentList ('"{0}"' -f $log.FullName) }
    else { Write-Log (T 'trapNoLog') 'warn' }
})
#endregion

#region 15. System tray icon
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = $script:AppIcon
$notifyIcon.Text = "OpenRelax PC Care"
$notifyIcon.Visible = $true

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miShow = $trayMenu.Items.Add("Show")
$miTrap = $trayMenu.Items.Add("Spike Trap")
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
$miTrap.add_Click({ Show-MainWindow; Show-View 'trap' })
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
    if ($Type -eq 'error') { $script:LogErrors++; $script:LastErrorText = $Message }
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
    # MTA: this worker never touches WinForms controls or COM, so it doesn't
    # need an STA message queue. ThreadOptions stays at its default (a fresh
    # thread per invocation): with ReuseThread the pipeline never started on
    # this machine - every scan/clean/disk/RAM task hung until the watchdog
    # gave up (reproduced 3/3; Default 2/2 fine), and each runspace runs a
    # single pipeline anyway.
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($script:EngineCode)
    [void]$ps.AddStatement().AddScript($TaskCode).AddArgument($script:Sync).AddArgument($Opt)
    $handle = $ps.BeginInvoke()
    $script:Sync.Beat = [DateTime]::UtcNow
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
    if ($r.TotalSize -gt 0) {
        $lblJunkVal.Text = Format-Bytes ([long]$r.TotalSize)
        # Time-capped scan: the real total is at least this much
        if ($r.Partial) { $lblJunkVal.Text = '≥ ' + $lblJunkVal.Text }
    }
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
    if ($r.Skipped) { Write-Log ([string]::Format((T 'logRamSkipped'), $r.Skipped)) 'info' }
    $script:Sync.Busy = $false
    Update-Status
}

function Complete-Disk {
    param($r)
    $script:Sync.DiskRunning = $false
    $script:Sync.WalkInfo = $null
    $diskDesc.Text = (T 'diskDesc')
    $lvDisk.Items.Clear()
    foreach ($row in $r.Rows) {
        $name = [string]$row.Name
        if (-not $name) { $name = (T 'diskRootFiles') }
        $size = Format-Bytes ([long]$row.Size)
        # The 90 s budget ran out: sizes are lower bounds
        if ($r.Partial) { $size = '≥ ' + $size }
        $item = New-Object System.Windows.Forms.ListViewItem($name)
        [void]$item.SubItems.Add($size)
        [void]$lvDisk.Items.Add($item)
    }
    Write-Log ([string]::Format((T 'logDiskDone'), $r.Count)) 'success'
    if ($r.Partial) { Write-Log (T 'logDiskPartial') 'warn' }
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
$smokeSec = 0
if ([int]::TryParse([string]$env:OPENRELAX_SMOKETEST, [ref]$smokeSec) -and $smokeSec -gt 4) {
    $script:SmokeTimer.Interval = $smokeSec * 1000
}
$script:SmokeTimer.add_Tick({
    $script:SmokeTimer.Stop()
    $script:ReallyExit = $true
    $form.Close()
})

# GUI stress support (tests\gui-stress.ps1). OPENRELAX_STRESS=<cycles> drives
# the real handlers through the live message loop - nav clicks over every
# view, language re-apply (in memory only), junk scans in the worker,
# Fotokapan refreshes - and samples memory and handle/GDI/USER object counts
# once per cycle. Nothing is cleaned and no setting is saved. The JSON report
# goes to OPENRELAX_STRESS_REPORT, Fotokapan view snapshots next to it.
$script:StressCycles = 0
[void][int]::TryParse([string]$env:OPENRELAX_STRESS, [ref]$script:StressCycles)
if ($script:StressCycles -gt 0) {
    Add-Type -Namespace OpenRelax -Name StressApi -MemberDefinition @'
[DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
'@
    $script:StressReport = [string]$env:OPENRELAX_STRESS_REPORT
    $script:StressSamples = New-Object System.Collections.ArrayList
    $script:StressErrors = New-Object System.Collections.ArrayList
    $script:StressStep = 0
    $script:StressScans = 0
    $script:StressLanguage = $script:Settings.language
    $script:StressClock = [System.Diagnostics.Stopwatch]::StartNew()
    # Never trim other apps' working sets during a test run (in memory only).
    $script:Settings.autoBoost = $false

    function Save-StressSnapshot([string]$Name) {
        if (-not $script:StressReport) { return }
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $hdc = $g.GetHdc()
        try { [void][OpenRelax.StressApi]::PrintWindow($form.Handle, $hdc, 2) }
        finally { $g.ReleaseHdc($hdc); $g.Dispose() }
        $bmp.Save((Join-Path (Split-Path -Parent $script:StressReport) $Name), [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }

    function Add-StressSample([int]$Cycle) {
        $me = [System.Diagnostics.Process]::GetCurrentProcess()
        [void]$script:StressSamples.Add([ordered]@{
            cycle = $Cycle; sec = [Math]::Round($script:StressClock.Elapsed.TotalSeconds, 1)
            privateMB = [Math]::Round($me.PrivateMemorySize64 / 1MB, 1); handles = $me.HandleCount
            gdi = [int][OpenRelax.StressApi]::GetGuiResources($me.Handle, 0)
            user = [int][OpenRelax.StressApi]::GetGuiResources($me.Handle, 1)
            tasks = $script:Tasks.Count; step = [string]$script:Sync.Step
            beatAgeSec = [Math]::Round(([DateTime]::UtcNow - [DateTime]$script:Sync.Beat).TotalSeconds, 1)
        })
        $me.Dispose()
    }

    $script:StressTimer = New-Object System.Windows.Forms.Timer
    $script:StressTimer.Interval = 250
    $script:StressTimer.add_Tick({
        try {
            $s = $script:StressStep++
            $cycle = [int][Math]::Floor($s / 4)
            if ($cycle -lt $script:StressCycles) {
                $navButtons[$s % 4].PerformClick()
                if (($s % 4) -eq 3) {
                    # The Fotokapan view is up: switch its page (summary twice, then
                    # records twice - the language alternates per cycle) and snapshot
                    # each page in both languages once
                    $page = @('summary', 'summary', 'records', 'records')[$cycle % 4]
                    Show-TrapPage $page
                    if ($cycle -lt 4) { Save-StressSnapshot ('stress-trap-{0}-{1}.png' -f $page, $script:Settings.language) }
                    if ($script:Settings.language -eq 'en') { $script:Settings.language = 'tr' } else { $script:Settings.language = 'en' }
                    Apply-Language
                    if (-not $script:Sync.Busy -and ($cycle % 3) -eq 0) { Start-ScanTask; $script:StressScans++ }
                    Add-StressSample $cycle
                }
            } elseif ($env:OPENRELAX_STRESS_DISK -and -not $script:StressDiskStarted -and -not $script:Sync.Busy) {
                # Optional last step: one real disk analysis (read-only, at most 90 s)
                $script:StressDiskStarted = $true
                Show-View 'disk'
                $btnAnalyze.PerformClick()
            } elseif (-not $script:Sync.Busy -or $script:StressClock.Elapsed.TotalMinutes -gt 10) {
                $script:StressTimer.Stop()
                $script:Settings.language = $script:StressLanguage
                Apply-Language
                Add-StressSample $script:StressCycles
                $report = [ordered]@{
                    version = "$script:AppVersion $script:AppEdition"; cycles = $script:StressCycles; scans = $script:StressScans
                    seconds = [Math]::Round($script:StressClock.Elapsed.TotalSeconds, 1); busyAtEnd = [bool]$script:Sync.Busy
                    logErrors = [int]$script:LogErrors; lastError = [string]$script:LastErrorText; tickError = [bool]$script:TickErrorShown
                    diskRan = [bool]$script:StressDiskStarted; diskItems = $lvDisk.Items.Count
                    errors = $script:StressErrors.ToArray(); samples = $script:StressSamples.ToArray()
                }
                if ($script:StressReport) { ConvertTo-Json -InputObject $report -Depth 5 | Set-Content -LiteralPath $script:StressReport -Encoding UTF8 }
                $script:ReallyExit = $true
                $form.Close()
            }
        } catch {
            [void]$script:StressErrors.Add($_.Exception.Message)
        }
    })
}

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
            } elseif (([DateTime]::UtcNow - [DateTime]$script:Sync.Beat).TotalSeconds -gt 60) {
                # Watchdog: workers post a progress beat to $Sync.Beat every
                # 500 files. Long runs are legitimate (cleaning a %TEMP% with
                # hundreds of thousands of folders takes minutes), so only a
                # worker that made no progress for 60s - blocked in native
                # I/O, where even the debugger cannot break in - is abandoned
                # and the UI reset so the user can retry. BeginStop is async on
                # purpose: Stop()/Dispose() could block just as badly if the
                # thread is genuinely stuck.
                # Name where it stalled: the category or the last folder with progress
                Write-Log ('{0} [{1}]' -f (T 'logTaskTimeout'), $script:Sync.Step) 'error'
                try { [void]$t.PS.BeginStop({}, $null) } catch {}
                $script:Tasks.RemoveAt($i)
                $script:Sync.Busy = $false
                $script:Sync.ScanResult = $null
                $btnOneClick.Enabled = $true
                $btnOneClick.Text = (T 'btnOneClick')
                $btnOneClick.Invalidate()
                $btnAnalyze.Enabled = $true
                $btnAnalyze.Text = (T 'btnAnalyze')
                $script:Sync.DiskRunning = $false
                $script:Sync.WalkInfo = $null
                $script:Sync.Cleaning = $false
                $diskDesc.Text = (T 'diskDesc')
                $lblJunkVal.Text = '—'
                Update-Status
            }
        }

        if ($script:Sync.DiskRunning -and $script:Sync.WalkInfo) {
            $wi = $script:Sync.WalkInfo
            $where = [string]$wi[1]
            if (-not $where) { $where = '...' }
            $txt = [string]::Format((T 'diskProgress'), ([long]$wi[0]).ToString('N0'), $where)
            if ($diskDesc.Text -ne $txt) { $diskDesc.Text = $txt }
        }
        if ($script:TrapProc) { Complete-TrapAction }
        if ($script:Sync.Cleaning) {
            $txt = [string]::Format((T 'btnCleaningProgress'), ([long]$script:Sync.CleanDone).ToString('N0'), (Format-Bytes ([long]$script:Sync.CleanBytes)))
            if ($btnOneClick.Text -ne $txt) { $btnOneClick.Text = $txt; $btnOneClick.Invalidate() }
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
    $script:Sync.WalkInfo = $null
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
    $miTrap.Text = (T 'trayTrap')
    $miClean.Text = (T 'trayClean')
    $miExit.Text = (T 'trayExit')
    $btnNavTrap.Text = (T 'navTrap')
    $trapTitle.Text = (T 'trapTitle')
    $trapTopTitle.Text = (T 'trapTopTitle')
    $trapRecentTitle.Text = (T 'trapRecentTitle')
    $trapDiagTitle.Text = (T 'trapDiagTitle')
    $trapHoursTitle.Text = (T 'trapHoursTitle')
    $btnTrapPageSummary.Text = (T 'trapPageSummary')
    $btnTrapPageRecords.Text = (T 'trapPageRecords')
    $btnTrapInstall.Text = (T 'btnTrapInstall')
    $btnTrapRemove.Text = (T 'btnTrapRemove')
    $btnTrapLog.Text = (T 'btnTrapLog')
    $i = 0
    foreach ($k in 'colProcess', 'colSpikes', 'colAvg', 'colLast') { $lvTrapTop.Columns[$i++].Text = (T $k) }
    $i = 0
    foreach ($k in 'colTime', 'colDur', 'colPeak', 'colCulprit', 'colNote') { $lvTrapRecent.Columns[$i++].Text = (T $k) }
    if ($script:TrapLastState) { Set-TrapStateLabel $script:TrapLastState }
    $script:TrapSig = $null
    if ($script:ActiveView -eq 'trap') { Update-TrapView }
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
        if ($script:ActiveView -eq 'trap' -and $form.Visible -and ($script:TickCount % 10) -eq 0) {
            Update-TrapView
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
    if ($script:StressCycles -gt 0) {
        $script:StressTimer.Start()
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
