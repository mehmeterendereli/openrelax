# OpenRelax PC Care v2.1 Preview - PowerShell WinForms system care utility
# Modes: default = GUI | -AutoClean = headless scheduled cleanup | -SelfTest = read-only engine scan
# Test hooks (env): OPENRELAX_SMOKETEST=1|<seconds> auto-close, OPENRELAX_STRESS=<cycles> GUI stress run,
#                   OPENRELAX_TRAP_DIR=<folder> read Fotokapan data from a test folder
param(
    [switch]$AutoClean,
    [switch]$StartMinimized,
    [switch]$SelfTest,
    [switch]$TestMode,
    [string]$FixtureRoot,
    [string]$StateDir,
    [string]$VisualReportDir,
    [string]$UiAcceptanceReportDir,
    [switch]$ExitDuringWorkerTest
)

if ($AutoClean -and $SelfTest) { throw 'AutoClean and SelfTest cannot be combined.' }
if (($VisualReportDir -or $UiAcceptanceReportDir -or $ExitDuringWorkerTest) -and ($AutoClean -or $SelfTest)) { throw 'GUI test reports require GUI mode.' }

$script:AppVersion   = '2.1'
$script:AppEdition   = 'Preview'
$script:ScriptPath   = $PSCommandPath
$script:TestMode = [bool]$TestMode
if ($TestMode) {
    if (-not $FixtureRoot -or -not $StateDir) { throw 'TestMode requires FixtureRoot and StateDir.' }
    $FixtureRoot = [IO.Path]::GetFullPath($FixtureRoot)
    $StateDir = [IO.Path]::GetFullPath($StateDir)
    if (-not $StateDir.StartsWith($FixtureRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Test state must be inside the fixture root.'
    }
    . (Join-Path $PSScriptRoot 'lib\OpenRelax.Core.ps1')
    Assert-TestFixture $FixtureRoot
    Assert-NoReparseAncestors $StateDir
    foreach ($reportDir in @($VisualReportDir,$UiAcceptanceReportDir)) {
        if ($reportDir) {
            if (-not (Test-PathWithin $reportDir $FixtureRoot)) { throw 'GUI test output must be inside the fixture root.' }
            Assert-NoReparseAncestors $reportDir
        }
    }
    $env:OPENRELAX_FIXTURE_ROOT = $FixtureRoot
}
if (-not $TestMode) {
    if ($StateDir) { throw 'StateDir requires TestMode.' }
    foreach ($key in 'OPENRELAX_FIXTURE_ROOT','OPENRELAX_TRAP_DIR','OPENRELAX_STRESS','OPENRELAX_STRESS_REPORT','OPENRELAX_SMOKETEST') { Remove-Item ('Env:\' + $key) -ErrorAction SilentlyContinue }
}
if (($VisualReportDir -or $UiAcceptanceReportDir) -and -not $TestMode) { throw 'GUI reports require TestMode.' }
if ($ExitDuringWorkerTest -and -not $TestMode) { throw 'Exit worker tests require TestMode.' }
$script:SettingsDir = if ($StateDir) { [IO.Path]::GetFullPath($StateDir) } else { Join-Path $env:APPDATA 'OpenRelax' }
$script:SettingsFile = Join-Path $script:SettingsDir 'settings.json'
$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

#region 1. Settings and shared core
. (Join-Path $PSScriptRoot 'lib\OpenRelax.Core.ps1')
$settingsDocument = Read-SettingsDocument $script:SettingsFile
$script:Settings = $settingsDocument.Settings
$script:SettingsValid = $settingsDocument.Valid
$script:SettingsError = $settingsDocument.Error
if ($TestMode) { $script:Settings.autoBoost = $false }
#endregion

#region 2. Localization (TR / EN string table)
$script:Strings = @{
    tr = @{
        accessibleClose = 'Pencereyi kapat veya tepsiye küçült'
        accessibleMinimize = 'Pencereyi küçült'
        accessibleLog = 'Bakım işlem günlüğü'
        accessibleThreshold = 'Otomatik RAM işlemi eşiği'
        logExitPending = 'Aktif işlem ve servis geri yüklemesi tamamlanınca çıkılacak.'
        diskIncomplete = 'Analiz tamamlanamadı; erişilemeyen alanlar ve bağlantılar atlandı.'
        diskEmpty = 'Klasör boyutlarını görmek için Analiz Et düğmesini kullanın.'
        trapEmpty = 'Henüz sıçrama kaydı yok. Kurulduğunda eşik üstü CPU olayları burada görünür.'
        scanFailed = 'Tarama başarısız'
        scanIncomplete = 'Tarama eksik'
        nothingSelected = 'Önce bir bakım işlemi seçin.'
        optRam = 'Bakımda RAM çalışma setlerini daralt'
        optDns = 'Bakımda DNS önbelleğini temizle'
        confirmMaintenance = 'Bu işlemler uygulansın mı?'
        warnRecycle = 'Geri Dönüşüm Kutusu kalıcı boşaltılır; dosyalar geri alınamaz.'
        warnShader = 'Shader önbelleği yeniden oluşturulur; ilk açılış yavaşlayabilir.'
        warnWer = 'Hata raporları tanılama için gerekebilir.'
        warnWu = 'Windows Update servisleri geçici olarak durdurulur.'
        logMaintenanceResult = 'Bakım: {0} · {1} dosya ({2}) · {3} atlanan · {4} hata'
        logRamResult = 'Net bellek değişimi: {0} (geçici); {1} süreç başarılı, {2} atlandı/hata.'
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
        headerSub        = 'Seçili işlemleri gözden geçirin. Dosyalar yalnız onayınızdan sonra temizlenir.'
        btnOneClick      = 'Bakımı Gözden Geçir'
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
        trayTrap         = 'Fotokapan'
        navTrap          = 'Fotokapan'
        trapTitle        = 'FOTOKAPAN · CPU SIÇRAMA KAYDEDİCİ'
        trapStRunning    = 'Çalışıyor'
        trapStStopped    = 'Durmuş'
        trapStMissing    = 'Kurulu değil'
        trapStUpdate     = 'Güncelleme var'
        trapDetail       = 'Son kontrol {0} · eşik %{1} · bu açılışta {2} sıçrama'
        trapDetailNone   = 'Kurulunca CPU %85 üstünde kaldığında sorumluları kaydeder; arayüz kapalıyken de çalışır.'
        btnTrapInstall   = 'Kur / Güncelle'
        btnTrapRemove    = 'Kaldır'
        btnTrapLog       = 'Log''u aç'
        trapTopTitle     = 'EN SIK SORUMLULAR · SON 7 GÜN'
        trapRecentTitle  = 'SON SIÇRAMALAR'
        colProcess       = 'Süreç'
        colSpikes        = 'Sıçrama'
        colAvg           = 'Ort. pay'
        colLast          = 'Son'
        colTime          = 'Zaman'
        colDur           = 'Süre'
        colPeak          = 'Tepe'
        colCulprit       = 'Sorumlu'
        colNote          = 'Not'
        trapDrivers      = 'CPU payı atanamadı'
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
        diskProgress     = 'Taranıyor {0}/{1}: {2}'
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
        logRamNone       = 'Ölçülen net kullanılabilir bellek değişimi yok.'
        logRecycleDone   = 'Geri Dönüşüm Kutusu boşaltıldı.'
        logDnsDone       = 'DNS önbelleği temizlendi.'
        logAllDone       = 'Tüm bakım işlemleri tamamlandı!'
        logAutoBoost     = 'RAM %{0} eşiğini aştı - otomatik boşaltma yapılıyor.'
        logWuStopped     = 'Windows Update servisi geçici olarak durduruldu.'
        logWuStarted     = 'Windows Update servisi yeniden başlatıldı.'
        logMaintStart    = 'Tek Tık Bakım başlatıldı...'
        logError         = 'Hata: {0}'
        logBusy          = 'Devam eden bir işlem var, lütfen bekleyin.'
        logTaskTimeout   = 'İlerleme durdu. İşçinin iptal edilmesi bekleniyor.'
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
        accessibleClose = 'Close window or minimize to tray'
        accessibleMinimize = 'Minimize window'
        accessibleLog = 'Maintenance activity log'
        accessibleThreshold = 'Automatic RAM threshold'
        logExitPending = 'Exiting after the active operation and service restoration finish.'
        diskIncomplete = 'Analysis incomplete; inaccessible entries and links were skipped.'
        diskEmpty = 'Use Analyze to measure folder sizes.'
        trapEmpty = 'No spikes recorded yet. After installation, sustained CPU spikes appear here.'
        scanFailed = 'Scan failed'
        scanIncomplete = 'Scan incomplete'
        nothingSelected = 'Select a maintenance operation first.'
        optRam = 'Trim RAM working sets during maintenance'
        optDns = 'Clear DNS cache during maintenance'
        confirmMaintenance = 'Apply these operations?'
        warnRecycle = 'The Recycle Bin will be emptied permanently; files cannot be restored.'
        warnShader = 'Shader caches rebuild; the next launch may be slower.'
        warnWer = 'Error reports may be needed for diagnostics.'
        warnWu = 'Windows Update services will be stopped temporarily.'
        logMaintenanceResult = 'Maintenance: {0} · {1} files ({2}) · {3} skipped · {4} errors'
        logRamResult = 'Net memory change: {0} (temporary); {1} processes succeeded, {2} skipped/failed.'
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
        headerSub        = 'Review selected operations. Files are cleaned only after your confirmation.'
        btnOneClick      = 'Review Maintenance'
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
        trayTrap         = 'Spike Trap'
        navTrap          = 'Spike Trap'
        trapTitle        = 'SPIKE TRAP · CPU SPIKE RECORDER'
        trapStRunning    = 'Running'
        trapStStopped    = 'Stopped'
        trapStMissing    = 'Not installed'
        trapStUpdate     = 'Update available'
        trapDetail       = 'Last check {0} · threshold {1}% · {2} spikes since boot'
        trapDetailNone   = 'Once installed it records the culprits whenever CPU stays above 85%, even with this window closed.'
        btnTrapInstall   = 'Install / Update'
        btnTrapRemove    = 'Remove'
        btnTrapLog       = 'Open log'
        trapTopTitle     = 'TOP CULPRITS · LAST 7 DAYS'
        trapRecentTitle  = 'RECENT SPIKES'
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
        diskProgress     = 'Scanning {0}/{1}: {2}'
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
        logRamNone       = 'No net change in measured available memory.'
        logRecycleDone   = 'Recycle Bin emptied.'
        logDnsDone       = 'DNS cache flushed.'
        logAllDone       = 'All maintenance tasks finished!'
        logAutoBoost     = 'RAM exceeded the {0}% threshold - auto boosting.'
        logWuStopped     = 'Windows Update service temporarily stopped.'
        logWuStarted     = 'Windows Update service restarted.'
        logMaintStart    = 'One-click maintenance started...'
        logError         = 'Error: {0}'
        logBusy          = 'A task is already running, please wait.'
        logTaskTimeout   = 'Progress stopped. Waiting for worker cancellation to finish.'
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

# BudgetSec > 0 caps the walk: a %TEMP% filled by dev/AI tooling can hold
# hundreds of thousands of folders and take minutes to enumerate. A capped scan
# returns a lower bound (Partial) instead of stalling. Inside a worker, $Sync
# (the task's param, visible through dynamic scope) gets a progress beat for
# the watchdog; in the headless modes it is simply $null.
function Measure-JunkPaths {
    param($Paths, [bool]$IsAdmin, [int]$BudgetSec = 0)
    $size = [long]0; $count = [long]0; $lockedSize = [long]0
    $state = @{ Partial = $false; Skipped = 0; ErrorCount = 0; Errors = @() }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    foreach ($target in $Paths) {
        if (-not (Test-Path -LiteralPath $target.Path)) { continue }
        try { Assert-CleanupPath $target.Path $target.ApprovedRoot }
        catch { $state.ErrorCount++; $state.Errors += $_.Exception.Message; continue }
        $cutoff = [datetime]::MaxValue
        if ($target.ContainsKey('MinAgeHours') -and $target.MinAgeHours) { $cutoff = (Get-Date).AddHours(-$target.MinAgeHours) }
        $remaining = if ($BudgetSec -gt 0) { [Math]::Max(1, $BudgetSec - [int]$clock.Elapsed.TotalSeconds) } else { 0 }
        Get-SafeTreeEntries -Path $target.Path -State $state -BudgetSec $remaining | ForEach-Object {
            if (-not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoff) {
                if ($IsAdmin -or -not $target.Admin) { $size += $_.Length; $count++ }
                else { $lockedSize += $_.Length }
            }
        }
        if ($state.Partial -or ($BudgetSec -gt 0 -and $clock.Elapsed.TotalSeconds -ge $BudgetSec)) { $state.Partial = $true; break }
    }
    return @{ Size = $size; Count = $count; LockedSize = $lockedSize; Partial = $state.Partial; Errors = @($state.Errors) }
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
        if ($target.ContainsKey('MinAgeHours') -and $target.MinAgeHours) { $cutoff = (Get-Date).AddHours(-$target.MinAgeHours) }
        $directories = [Collections.Generic.List[string]]::new()
        Get-SafeTreeEntries -Path $target.Path -State $state | ForEach-Object {
            if ($_.PSIsContainer) { if (-not $target.ContainsKey('MinAgeHours') -or -not $target.MinAgeHours) { $directories.Add($_.FullName) }; return }
            if ($_.LastWriteTime -ge $cutoff) { return }
            try {
                Assert-NoReparseAncestors $_.FullName
                $current = Get-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $current.LastWriteTime -ge $cutoff) { return }
                $length = $current.Length
                Remove-Item -LiteralPath $current.FullName -Force -ErrorAction Stop
                $bytes += $length; $count++
            } catch { $state.Skipped++ }
        }
        # Temp directories may belong to active installers. Their small size does not justify removing them.
        foreach ($directory in ($directories | Sort-Object Length -Descending)) {
            try { Assert-NoReparseAncestors $directory; [IO.Directory]::Delete($directory) } catch {}
        }
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

# Serialized engine source, injected into every background runspace so the
# worker and the UI share a single implementation.
$script:EngineCode = ''
foreach ($fnName in 'Format-Bytes', 'Get-JunkCategories', 'Test-PathWithin', 'Assert-NoReparseAncestors', 'Assert-CleanupPath', 'Get-SafeTreeEntries', 'Measure-JunkPaths', 'Get-RecycleBinInfo', 'Remove-JunkPaths', 'Wait-ServiceState', 'Invoke-WindowsUpdateCacheCleanup', 'Invoke-RamTrim', 'Invoke-Maintenance') {
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
    $totalSize = [long]0; $totalCount = [long]0; $lockedSize = [long]0; $partial = $false; $errors = @()
    foreach ($cat in $cats) {
        $Sync.Step = $cat.Key
        if ($cat.ContainsKey('Warnings')) { $errors += @($cat.Warnings) }
        if ($cat.Key -eq 'recycle') {
            $info = Get-RecycleBinInfo
            $results[$cat.Key] = @{ Size = $info.Size; Count = $info.Count }
            $totalSize += $info.Size; $totalCount += $info.Count
        } else {
            $m = Measure-JunkPaths -Paths $cat.Paths -IsAdmin:$Opt.IsAdmin -BudgetSec 6
            $results[$cat.Key] = @{ Size = $m.Size; Count = $m.Count }
            $totalSize += $m.Size; $totalCount += $m.Count; $lockedSize += $m.LockedSize
            if ($m.Partial) { $partial = $true }
            $errors += @($m.Errors)
        }
    }
    $Sync.ScanResult = @{ Categories = $results; TotalSize = $totalSize; FileCount = $totalCount; LockedSize = $lockedSize; Partial = $partial; Status = $(if ($errors.Count -or $partial) { 'Partial' } else { 'Success' }); Errors = @($errors) }
} catch {
    $Sync.Log.Enqueue(@{ Text = "Scan error: $($_.Exception.Message)"; Type = 'error' })
    $Sync.ScanResult = @{ Categories = @{}; TotalSize = 0; FileCount = 0; LockedSize = 0; Status = 'Failed'; Errors = @($_.Exception.Message) }
}
'@

$script:CleanTaskCode = @'
param($Sync, $Opt)
try { $Sync.CleanResult = Invoke-Maintenance $Opt }
catch { $Sync.CleanResult = @{ Bytes = 0; Count = 0; Skipped = 0; Errors = @($_.Exception.Message); Status = 'Failed'; Ram = $null } }
'@

$script:RamTaskCode = @'
param($Sync, $Opt)
try {
    $ram = Invoke-RamTrim
    $Sync.RamResult = $ram
} catch {
    $Sync.Log.Enqueue(@{ Text = "RAM task error: $($_.Exception.Message)"; Type = 'error' })
    $Sync.RamResult = @{ Saved = 0; Success = 0; Fail = 1 }
}
'@

$script:DiskTaskCode = @'
param($Sync, $Opt)
try {
    Assert-NoReparseAncestors $Opt.Target
    $rows = @(); $issues = @(); $partial = $false; $skipped = 0; $n = 0
    $budget = [Diagnostics.Stopwatch]::StartNew()
    $dirs = @(Get-ChildItem -LiteralPath $Opt.Target -Directory -Force -ErrorAction Stop)
    foreach ($d in $dirs) {
        if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $skipped++; $partial = $true; continue }
        if ($budget.Elapsed.TotalSeconds -ge 30) { $partial = $true; break }
        $n++; $Sync.DiskProgress = @($n,$dirs.Count,$d.Name)
        $state = @{ Partial = $false; Skipped = 0; ErrorCount = 0; Errors = @() }
        $sz = [long]0
        Get-SafeTreeEntries -Path $d.FullName -State $state -BudgetSec ([Math]::Max(1,[int](30 - $budget.Elapsed.TotalSeconds))) | ForEach-Object { if (-not $_.PSIsContainer) { $sz += $_.Length } }
        $rowPartial = ($state.Partial -or $state.Skipped -or $state.ErrorCount)
        if ($rowPartial) { $partial = $true }
        $issues += @($state.Errors); $skipped += $state.Skipped
        $rows += @{ Name = $d.Name; Size = $sz; Partial = [bool]$rowPartial }
    }
    $top = $rows | Sort-Object -Property @{ Expression = { $_.Size } } -Descending | Select-Object -First 10
    $Sync.DiskResult = @{ Rows = @($top); Count = $n; Status = $(if ($partial) { 'Partial' } else { 'Success' }); Errors = @($issues); Skipped = $skipped }
} catch {
    $Sync.DiskResult = @{ Rows = @(); Count = 0; Status = 'Failed'; Errors = @($_.Exception.Message); Skipped = 0 }
}
'@
#endregion

#region 5. Windows integration helpers (startup entry, weekly scheduled task)
$script:PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Set-StartupEntry {
    param([bool]$Enable)
    if ($script:TestMode) { return @{ Ok = $false; Error = 'System integration is disabled in TestMode.' } }
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    try {
        if ($Enable) {
            $cmd = "`"$script:PsExe`" -STA -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$script:ScriptPath`" -StartMinimized"
            Set-ItemProperty -Path $runKey -Name 'OpenRelax' -Value $cmd -ErrorAction Stop
            return @{ Ok = $true; Key = 'logStartupOn' }
        } else {
            if ((Test-Path -LiteralPath $runKey) -and (Get-ItemProperty -LiteralPath $runKey -ErrorAction Stop).PSObject.Properties['OpenRelax']) { Remove-ItemProperty -LiteralPath $runKey -Name 'OpenRelax' -ErrorAction Stop }
            return @{ Ok = $true; Key = 'logStartupOff' }
        }
    } catch {
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}

function Set-WeeklyTask {
    param([bool]$Enable)
    if ($script:TestMode) { return @{ Ok = $false; Error = 'System integration is disabled in TestMode.' } }
    $taskName = 'OpenRelax Weekly Clean'
    try {
        if ($Enable) {
            $action = New-ScheduledTaskAction -Execute $script:PsExe -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$script:ScriptPath`" -AutoClean"
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '12:00'
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Force -ErrorAction Stop | Out-Null
            return @{ Ok = $true; Key = 'logTaskCreated' }
        } else {
            if (@(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object { $_.TaskName -eq $taskName }).Count) { Unregister-ScheduledTask -TaskName $taskName -TaskPath '\' -Confirm:$false -ErrorAction Stop }
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
$script:TrapRoot     = Join-Path $env:ProgramData 'OpenRelax\Fotokapan'
$script:TrapDir      = Join-Path $script:TrapRoot 'logs'
$script:TrapInstalledScript = Join-Path $script:TrapRoot 'bin\fotokapan.ps1'
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

function Get-TrapState {
    param([string]$Dir = $script:TrapDir)
    $st = @{ Installed = $false; Running = $false; Outdated = $false; Beat = $null; Threshold = 85; Spikes = 0 }
    if ($script:TestMode) { return $st }
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
    if (-not $script:TestMode -and -not (Test-Path -LiteralPath $beatFile)) { $beatFile = Join-Path $script:TrapRoot 'durum.json' }
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
    $installed = $script:TrapInstalledScript
    if ($st.Installed -and -not (Test-Path -LiteralPath $installed)) { $st.Outdated = $true }
    if ($st.Installed -and (Test-Path -LiteralPath $installed) -and (Test-Path -LiteralPath $script:TrapScript)) {
        try {
            $st.Outdated = (Get-FileHash -LiteralPath $installed).Hash -ne (Get-FileHash -LiteralPath $script:TrapScript).Hash
            $coreInstalled = Join-Path (Split-Path -Parent $installed) 'lib\OpenRelax.Core.ps1'
            $coreSource = Join-Path $PSScriptRoot 'lib\OpenRelax.Core.ps1'
            if (-not (Test-Path -LiteralPath $coreInstalled) -or (Get-FileHash -LiteralPath $coreInstalled).Hash -ne (Get-FileHash -LiteralPath $coreSource).Hash) { $st.Outdated = $true }
        } catch {}
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
# process accounts for (exited/unreadable processes or interrupts/DPCs) outweighs it.
function Get-TrapCulprit($Start) {
    $top = @($Start.top | Where-Object { $_ })
    $unattributed = [double]$Start.total - [double]$Start.attributed
    if ($top.Count -eq 0 -or $unattributed -gt [double]$top[0].pct) {
        return @{ Name = '*unattributed*'; Pct = [Math]::Max(0, $unattributed) }
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
#endregion

#region 6. Headless modes (-AutoClean / -SelfTest) - no GUI is loaded
if ($AutoClean) {
    if (-not $script:SettingsValid) { Write-Error ('AutoClean stopped: ' + $script:SettingsError); exit 1 }
    $keys = @($script:Settings.categories.Keys | Where-Object { $script:Settings.categories[$_] })
    $result = Invoke-Maintenance @{ Keys = $keys; IsAdmin = $script:IsAdmin; Headless = $true; Confirmed = $false; TrimRam = $false; ClearDns = $false }
    try {
        if ($result.Status -ne 'Failed') { Update-MaintenanceStats $result.Bytes }
        $line = '{0} AutoClean: status={1}; files={2}; bytes={3}; skipped={4}; errors={5}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $result.Status, $result.Count, $result.Bytes, $result.Skipped, ($result.Errors -join '; ')
        Add-Content -LiteralPath (Join-Path $script:SettingsDir 'autoclean.log') -Value $line -Encoding UTF8 -ErrorAction Stop
        Write-Output $line
    } catch { Write-Error ('AutoClean state could not be saved: ' + $_.Exception.Message); exit 1 }
    if ($result.Status -eq 'Failed') { exit 1 }
    if ($result.Status -eq 'Partial') { exit 2 }
    exit 0
}

if ($SelfTest) {
    Write-Host "OpenRelax v$script:AppVersion $script:AppEdition self-test (read-only scan)"
    Write-Host "Admin: $script:IsAdmin | Settings: $script:SettingsFile"
    $scanIssues = @(); $scanPartial = $false
    $grandSize = [long]0; $grandCount = [long]0; $grandLocked = [long]0
    foreach ($cat in (Get-JunkCategories)) {
        if ($cat.ContainsKey('Warnings')) { $scanIssues += @($cat.Warnings) }
        if ($cat.Key -eq 'recycle') {
            $info = Get-RecycleBinInfo
            Write-Host ("  {0,-10} {1,10}  ({2} items)" -f $cat.Key, (Format-Bytes $info.Size), $info.Count)
            $grandSize += $info.Size; $grandCount += $info.Count
        } else {
            $m = Measure-JunkPaths -Paths $cat.Paths -IsAdmin:$script:IsAdmin -BudgetSec 6
            $note = ''
            $scanIssues += @($m.Errors)
            if ($m.Partial) { $scanPartial = $true; $note = ' [partial: 6s budget hit, size is a lower bound]' }
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
    if ($scanIssues.Count -or $scanPartial) {
        foreach ($issue in $scanIssues) { Write-Warning $issue }
        Write-Warning 'Self-test incomplete: rejected/unreadable targets or scan budget reached.'
        exit 2
    }
    Write-Host "Self-test OK"
    exit 0
}
#endregion

#region 7. GUI bootstrap
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$script:GuiMutex = Get-SettingsMutex $script:SettingsFile -Scope 'GUI'
$script:OwnGuiMutex = $false
try { $script:OwnGuiMutex = $script:GuiMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $script:OwnGuiMutex = $true }
if (-not $script:OwnGuiMutex) {
    [void][Windows.Forms.MessageBox]::Show('OpenRelax is already open. Use its window or system tray icon.', 'OpenRelax')
    $script:GuiMutex.Dispose()
    exit 2
}

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

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetClientRect(IntPtr window, out RECT rect);
        public static int GetClientWidth(IntPtr window) {
            RECT rect;
            return GetClientRect(window, out rect) ? rect.Right - rect.Left : 0;
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
$script:ExitRequested = $false
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
    $previousRegion = $control.Region
    $control.Region = New-Object System.Drawing.Region($path)
    $path.Dispose()
    if ($previousRegion) { $previousRegion.Dispose() }
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
$form.Size = New-Object System.Drawing.Size(680, 590)
$form.AutoScroll = $true
$form.AutoScrollMinSize = New-Object Drawing.Size(680,590)
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
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Tag = $navTags[$i]
    $navPanel.Controls.Add($b)
    Set-RoundedRegion $b 8
    $navX += 110
}

$contentHost = New-Object System.Windows.Forms.Panel
$contentHost.Size = New-Object System.Drawing.Size(644, 482)
$contentHost.Location = New-Object System.Drawing.Point(18, 86)
$contentHost.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$form.Controls.Add($contentHost)

$viewDash = New-Object System.Windows.Forms.Panel
$viewDash.Size = New-Object System.Drawing.Size(644, 482)
$viewDash.Location = New-Object System.Drawing.Point(0, 0)
$viewDash.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$contentHost.Controls.Add($viewDash)

$viewSettings = New-Object System.Windows.Forms.Panel
$viewSettings.Size = New-Object System.Drawing.Size(644, 482)
$viewSettings.Location = New-Object System.Drawing.Point(0, 0)
$viewSettings.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$viewSettings.Visible = $false
$contentHost.Controls.Add($viewSettings)

$viewDisk = New-Object System.Windows.Forms.Panel
$viewDisk.Size = New-Object System.Drawing.Size(644, 482)
$viewDisk.Location = New-Object System.Drawing.Point(0, 0)
$viewDisk.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$viewDisk.Visible = $false
$contentHost.Controls.Add($viewDisk)

$viewTrap = New-Object System.Windows.Forms.Panel
$viewTrap.Size = New-Object System.Drawing.Size(644, 482)
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
            $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
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
$leftContainer.Size = New-Object System.Drawing.Size(260, 470)
$leftContainer.Location = New-Object System.Drawing.Point(0, 4)
$leftContainer.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$viewDash.Controls.Add($leftContainer)

# -- CARD 1: RAM (Donut Chart) --
$ramCard = Create-Card $leftContainer (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(260, 105))

$ramTitle = New-Object System.Windows.Forms.Label
$ramTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$ramTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$ramTitle.Location = New-Object System.Drawing.Point(12, 10)
$ramTitle.AutoSize = $true
$ramCard.Controls.Add($ramTitle)

$ramDescLabel = New-Object System.Windows.Forms.Label
$ramDescLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Regular)
$ramDescLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$ramDescLabel.Location = New-Object System.Drawing.Point(12, 30)
$ramDescLabel.Size = New-Object System.Drawing.Size(145, 30)
$ramCard.Controls.Add($ramDescLabel)

$ramDetailsLabel = New-Object System.Windows.Forms.Label
$ramDetailsLabel.Text = "0.0 GB / 0.0 GB"
$ramDetailsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
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
$cpuTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
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
$cpuDetailsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$cpuDetailsLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
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
$sysTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$sysTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$sysTitle.Location = New-Object System.Drawing.Point(12, 10)
$sysTitle.AutoSize = $true
$sysCard.Controls.Add($sysTitle)

$lblUptimeName = New-Object System.Windows.Forms.Label
$lblUptimeName.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblUptimeName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblUptimeName.Location = New-Object System.Drawing.Point(12, 35)
$lblUptimeName.AutoSize = $true
$sysCard.Controls.Add($lblUptimeName)

$lblUptimeVal = New-Object System.Windows.Forms.Label
$lblUptimeVal.Text = "-"
$lblUptimeVal.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblUptimeVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblUptimeVal.Location = New-Object System.Drawing.Point(120, 35)
$lblUptimeVal.Size = New-Object System.Drawing.Size(128, 20)
$lblUptimeVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$sysCard.Controls.Add($lblUptimeVal)

$lblProcName = New-Object System.Windows.Forms.Label
$lblProcName.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblProcName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblProcName.Location = New-Object System.Drawing.Point(12, 65)
$lblProcName.AutoSize = $true
$sysCard.Controls.Add($lblProcName)

$lblProcVal = New-Object System.Windows.Forms.Label
$lblProcVal.Text = "-"
$lblProcVal.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblProcVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblProcVal.Location = New-Object System.Drawing.Point(120, 65)
$lblProcVal.Size = New-Object System.Drawing.Size(128, 20)
$lblProcVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$sysCard.Controls.Add($lblProcVal)

$lblJunkName = New-Object System.Windows.Forms.Label
$lblJunkName.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblJunkName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblJunkName.Location = New-Object System.Drawing.Point(12, 95)
$lblJunkName.AutoSize = $true
$sysCard.Controls.Add($lblJunkName)

$lblJunkVal = New-Object System.Windows.Forms.Label
$lblJunkVal.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblJunkVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblJunkVal.Location = New-Object System.Drawing.Point(120, 95)
$lblJunkVal.Size = New-Object System.Drawing.Size(128, 20)
$lblJunkVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$sysCard.Controls.Add($lblJunkVal)

Register-CardHover $sysCard
#endregion

#region 12. Dashboard view - right column (header, action button, log, footer)
$rightContainer = New-Object System.Windows.Forms.Panel
$rightContainer.Size = New-Object System.Drawing.Size(368, 470)
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
$headerSub.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$headerSub.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
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
$btnOneClick.add_GotFocus({ $btnOneClick.Invalidate() })
$btnOneClick.add_LostFocus({ $btnOneClick.Invalidate() })

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
    if ($sender.Focused) {
        [Windows.Forms.ControlPaint]::DrawFocusRectangle($g,[Drawing.Rectangle]::new(6,6,$sender.Width - 12,$sender.Height - 12),[Drawing.Color]::White,$color1)
    }

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
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblStatus.Location = New-Object System.Drawing.Point(0, 362)
$lblStatus.Size = New-Object System.Drawing.Size(368, 24)
$rightContainer.Controls.Add($lblStatus)

$lblAuto = New-Object System.Windows.Forms.Label
$lblAuto.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblAuto.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblAuto.Location = New-Object System.Drawing.Point(0, 397)
$lblAuto.Size = New-Object System.Drawing.Size(208, 24)
$lblAuto.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$rightContainer.Controls.Add($lblAuto)

$switchPanel = New-Object System.Windows.Forms.CheckBox
$switchPanel.Size = New-Object System.Drawing.Size(22, 24)
$switchPanel.Location = New-Object System.Drawing.Point(214, 393)
$switchPanel.BackColor = [Drawing.Color]::Transparent
$switchPanel.ForeColor = [Drawing.Color]::White
$switchPanel.TabStop = $true
$switchPanel.AccessibleName = 'Automatic RAM working set trimming'
$switchPanel.Checked = [bool]$script:Settings.autoBoost
$rightContainer.Controls.Add($switchPanel)
$switchPanel.add_CheckedChanged({
    if ($script:UILoading) { return }
    $old = [bool]$script:Settings.autoBoost
    $script:Settings.autoBoost = $switchPanel.Checked
    if (-not (Save-Settings)) { $script:Settings.autoBoost = $old; $script:UILoading = $true; try { $switchPanel.Checked = $old } finally { $script:UILoading = $false } }
    $cmbLimit.Enabled = $switchPanel.Checked
})

$lblLimit = New-Object System.Windows.Forms.Label
$lblLimit.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblLimit.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblLimit.Location = New-Object System.Drawing.Point(256, 397)
$lblLimit.Size = New-Object System.Drawing.Size(46, 20)
$lblLimit.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$rightContainer.Controls.Add($lblLimit)

$cmbLimit = New-Object System.Windows.Forms.ComboBox
$cmbLimit.Location = New-Object System.Drawing.Point(306, 393)
$cmbLimit.Size = New-Object System.Drawing.Size(60, 22)
$cmbLimit.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#161F30')
$cmbLimit.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$cmbLimit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbLimit.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbLimit.Font = New-Object System.Drawing.Font("Segoe UI", 9)
foreach ($v in 70, 75, 80, 85, 90) { [void]$cmbLimit.Items.Add("%$v") }
$limitIdx = [Array]::IndexOf(@(70, 75, 80, 85, 90), [int]$script:Settings.autoBoostLimit)
if ($limitIdx -lt 0) { $limitIdx = 3 }
$cmbLimit.SelectedIndex = $limitIdx
$rightContainer.Controls.Add($cmbLimit)
$cmbLimit.Enabled = $switchPanel.Checked

$cmbLimit.add_SelectedIndexChanged({
    if ($script:UILoading) { return }
    $old = [int]$script:Settings.autoBoostLimit
    $script:Settings.autoBoostLimit = [int]($cmbLimit.SelectedItem -replace '%', '')
    if (-not (Save-Settings)) { $script:Settings.autoBoostLimit = $old; $script:UILoading = $true; try { $cmbLimit.SelectedIndex = [Array]::IndexOf(@(70,75,80,85,90),$old) } finally { $script:UILoading = $false } }
})
#endregion

#region 13. Settings view
$catCard = Create-Card $viewSettings (New-Object System.Drawing.Point(0, 4)) (New-Object System.Drawing.Size(316, 470))

$catTitle = New-Object System.Windows.Forms.Label
$catTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$catTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$catTitle.Location = New-Object System.Drawing.Point(12, 10)
$catTitle.AutoSize = $true
$catCard.Controls.Add($catTitle)

# Category checkboxes: created in a top-level loop, wired through a single
# shared handler; per-checkbox data travels via .Tag (safe in PS event scope).
$script:CategoryChangedHandler = {
    param($sender, $e)
    if ($script:UILoading) { return }
    $old = [bool]$script:Settings.categories[$sender.Tag]
    $script:Settings.categories[$sender.Tag] = $sender.Checked
    if (-not (Save-Settings)) { $script:Settings.categories[$sender.Tag] = $old; $script:UILoading = $true; try { $sender.Checked = $old } finally { $script:UILoading = $false } }
}

$catKeys = @('temp', 'browser', 'discord', 'shader', 'wer', 'wu', 'gpusetup', 'recycle')
$catY = 38
foreach ($catKey in $catKeys) {
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Location = New-Object System.Drawing.Point(14, $catY)
    $chk.Size = New-Object System.Drawing.Size(288, 30)
    $chk.Font = New-Object System.Drawing.Font("Segoe UI", 9)
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

$genCard = Create-Card $viewSettings (New-Object System.Drawing.Point(332, 4)) (New-Object System.Drawing.Size(312, 300))

$genTitle = New-Object System.Windows.Forms.Label
$genTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$genTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$genTitle.Location = New-Object System.Drawing.Point(12, 10)
$genTitle.AutoSize = $true
$genCard.Controls.Add($genTitle)

$script:OptionChangedHandler = {
    param($sender, $e)
    if ($script:UILoading) { return }
    $mapping = @{ tray = 'closeToTray'; startup = 'runAtStartup'; weekly = 'weeklyClean'; ram = 'trimRam'; dns = 'clearDns' }
    $key = $mapping[$sender.Tag]
    $old = [bool]$script:Settings[$key]
    $operation = @{ Ok = $true }; $systemChanged = $false
    if ($sender.Tag -eq 'startup') { $operation = Set-StartupEntry $sender.Checked }
    if ($sender.Tag -eq 'weekly') { $operation = Set-WeeklyTask $sender.Checked }
    if ($operation.Ok) {
        $systemChanged = ($sender.Tag -in @('startup','weekly'))
        $script:Settings[$key] = $sender.Checked
        $operation.Ok = Save-Settings
        if (-not $operation.Ok) { $operation.Error = $script:SettingsError }
    }
    if (-not $operation.Ok) {
        $script:Settings[$key] = $old
        if ($systemChanged -and $sender.Tag -eq 'startup') { $rollback = Set-StartupEntry $old }
        if ($systemChanged -and $sender.Tag -eq 'weekly') { $rollback = Set-WeeklyTask $old }
        if ($systemChanged -and -not $rollback.Ok) { Write-Log ('Preference rollback failed: ' + $rollback.Error) 'error' }
        $script:UILoading = $true
        try { $sender.Checked = $old } finally { $script:UILoading = $false }
        Write-Log ([string]::Format((T 'logError'), $operation.Error)) 'error'
    } elseif ($operation.Key) { Write-Log (T $operation.Key) 'success' }
}

$chkTray = New-Object System.Windows.Forms.CheckBox
$chkTray.Location = New-Object System.Drawing.Point(14, 38)
$chkTray.Size = New-Object System.Drawing.Size(284, 22)
$chkTray.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$chkTray.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#CBD5E1')
$chkTray.BackColor = [System.Drawing.Color]::Transparent
$chkTray.Tag = 'tray'
$chkTray.Checked = [bool]$script:Settings.closeToTray
$chkTray.add_CheckedChanged($script:OptionChangedHandler)
$genCard.Controls.Add($chkTray)

$chkStartup = New-Object System.Windows.Forms.CheckBox
$chkStartup.Location = New-Object System.Drawing.Point(14, 68)
$chkStartup.Size = New-Object System.Drawing.Size(284, 22)
$chkStartup.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$chkStartup.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#CBD5E1')
$chkStartup.BackColor = [System.Drawing.Color]::Transparent
$chkStartup.Tag = 'startup'
$chkStartup.Checked = [bool]$script:Settings.runAtStartup
$chkStartup.add_CheckedChanged($script:OptionChangedHandler)
$genCard.Controls.Add($chkStartup)

$chkWeekly = New-Object System.Windows.Forms.CheckBox
$chkWeekly.Location = New-Object System.Drawing.Point(14, 98)
$chkWeekly.Size = New-Object System.Drawing.Size(284, 22)
$chkWeekly.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$chkWeekly.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#CBD5E1')
$chkWeekly.BackColor = [System.Drawing.Color]::Transparent
$chkWeekly.Tag = 'weekly'
$chkWeekly.Checked = [bool]$script:Settings.weeklyClean
$chkWeekly.add_CheckedChanged($script:OptionChangedHandler)
$genCard.Controls.Add($chkWeekly)

$lblLang = New-Object System.Windows.Forms.Label
$lblLang.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblLang.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblLang.Location = New-Object System.Drawing.Point(14, 198)
$lblLang.Size = New-Object System.Drawing.Size(90, 20)
$genCard.Controls.Add($lblLang)

$cmbLang = New-Object System.Windows.Forms.ComboBox
$cmbLang.Location = New-Object System.Drawing.Point(110, 195)
$cmbLang.Size = New-Object System.Drawing.Size(120, 22)
$cmbLang.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#161F30')
$cmbLang.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$cmbLang.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbLang.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbLang.Font = New-Object System.Drawing.Font("Segoe UI", 9)
[void]$cmbLang.Items.Add('Türkçe')
[void]$cmbLang.Items.Add('English')
if ($script:Settings.language -eq 'en') { $cmbLang.SelectedIndex = 1 } else { $cmbLang.SelectedIndex = 0 }
$genCard.Controls.Add($cmbLang)

$cmbLang.add_SelectedIndexChanged({
    if ($script:UILoading) { return }
    $old = $script:Settings.language
    if ($cmbLang.SelectedIndex -eq 1) { $script:Settings.language = 'en' } else { $script:Settings.language = 'tr' }
    if (-not (Save-Settings)) { $script:Settings.language = $old }
    Apply-Language
})

$btnElevate = New-Object System.Windows.Forms.Button
$btnElevate.Size = New-Object System.Drawing.Size(284, 34)
$btnElevate.Location = New-Object System.Drawing.Point(14, 240)
$btnElevate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnElevate.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')
$btnElevate.FlatAppearance.BorderSize = 1
$btnElevate.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnElevate.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')
$btnElevate.BackColor = [System.Drawing.Color]::Transparent
$btnElevate.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnElevate.Visible = (-not $script:IsAdmin)
$genCard.Controls.Add($btnElevate)

$btnElevate.Enabled = (-not $script:TestMode)
$btnElevate.add_Click({
    if ($script:TestMode) { return }
    try {
        # Hidden like launch.bat: closing a stray console window would kill the app
        Start-Process -FilePath $script:PsExe -ArgumentList @('-STA', '-WindowStyle', 'Hidden', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:ScriptPath`"") -Verb RunAs
        $script:ReallyExit = $true
        $form.Close()
    } catch {
        Write-Log (T 'logElevateFail') 'warn'
    }
})

$chkRam = New-Object System.Windows.Forms.CheckBox
$chkDns = New-Object System.Windows.Forms.CheckBox
foreach ($settingControl in @($chkRam,$chkDns)) {
    $settingControl.Size = New-Object Drawing.Size(284, 28)
    $settingControl.Font = New-Object Drawing.Font('Segoe UI', 9)
    $settingControl.ForeColor = [Drawing.ColorTranslator]::FromHtml('#CBD5E1')
    $settingControl.BackColor = [Drawing.Color]::Transparent
    $settingControl.add_CheckedChanged($script:OptionChangedHandler)
    $genCard.Controls.Add($settingControl)
}
$chkRam.Tag = 'ram'; $chkRam.Location = New-Object Drawing.Point(14,128); $chkRam.Checked = $script:Settings.trimRam
$chkDns.Tag = 'dns'; $chkDns.Location = New-Object Drawing.Point(14,160); $chkDns.Checked = $script:Settings.clearDns
Register-CardHover $genCard

$statCard = Create-Card $viewSettings (New-Object System.Drawing.Point(332, 316)) (New-Object System.Drawing.Size(312, 154))

$statTitle = New-Object System.Windows.Forms.Label
$statTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$statTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$statTitle.Location = New-Object System.Drawing.Point(12, 10)
$statTitle.AutoSize = $true
$statCard.Controls.Add($statTitle)

$lblStatTotalName = New-Object System.Windows.Forms.Label
$lblStatTotalName.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblStatTotalName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblStatTotalName.Location = New-Object System.Drawing.Point(12, 40)
$lblStatTotalName.AutoSize = $true
$statCard.Controls.Add($lblStatTotalName)

$lblStatTotalVal = New-Object System.Windows.Forms.Label
$lblStatTotalVal.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblStatTotalVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#10B981')
$lblStatTotalVal.Location = New-Object System.Drawing.Point(160, 40)
$lblStatTotalVal.Size = New-Object System.Drawing.Size(140, 20)
$lblStatTotalVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$statCard.Controls.Add($lblStatTotalVal)

$lblStatRunsName = New-Object System.Windows.Forms.Label
$lblStatRunsName.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblStatRunsName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblStatRunsName.Location = New-Object System.Drawing.Point(12, 70)
$lblStatRunsName.AutoSize = $true
$statCard.Controls.Add($lblStatRunsName)

$lblStatRunsVal = New-Object System.Windows.Forms.Label
$lblStatRunsVal.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblStatRunsVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblStatRunsVal.Location = New-Object System.Drawing.Point(160, 70)
$lblStatRunsVal.Size = New-Object System.Drawing.Size(140, 20)
$lblStatRunsVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$statCard.Controls.Add($lblStatRunsVal)

$lblStatLastName = New-Object System.Windows.Forms.Label
$lblStatLastName.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblStatLastName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblStatLastName.Location = New-Object System.Drawing.Point(12, 100)
$lblStatLastName.AutoSize = $true
$statCard.Controls.Add($lblStatLastName)

$lblStatLastVal = New-Object System.Windows.Forms.Label
$lblStatLastVal.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblStatLastVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblStatLastVal.Location = New-Object System.Drawing.Point(160, 100)
$lblStatLastVal.Size = New-Object System.Drawing.Size(140, 20)
$lblStatLastVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$statCard.Controls.Add($lblStatLastVal)

Register-CardHover $statCard
#endregion

function Fit-ListColumns($List) {
    if (-not $List.Columns.Count) { return }
    $width = $List.ClientSize.Width
    if ($List.IsHandleCreated) { $nativeWidth = [Win32Helper]::GetClientWidth($List.Handle); if ($nativeWidth -gt 0) { $width = $nativeWidth } }
    $used = 0
    for ($i = 0; $i -lt ($List.Columns.Count - 1); $i++) { $used += $List.Columns[$i].Width }
    $last = $List.Columns[$List.Columns.Count - 1]
    $newWidth = [Math]::Max(60,$width - $used)
    if ($last.Width -ne $newWidth) { $last.Width = $newWidth }
}
function Set-ListTheme($List) {
    $List.OwnerDraw = $true
    $List.add_ClientSizeChanged({ param($sender,$e) Fit-ListColumns $sender })
    Fit-ListColumns $List
    $List.add_DrawColumnHeader({ param($sender,$e)
        $brush = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#161F30'))
        try { $e.Graphics.FillRectangle($brush,$e.Bounds); [Windows.Forms.TextRenderer]::DrawText($e.Graphics,$e.Header.Text,$sender.Font,$e.Bounds,[Drawing.ColorTranslator]::FromHtml('#E2E8F0'),[Windows.Forms.TextFormatFlags]'Left,VerticalCenter,EndEllipsis') } finally { $brush.Dispose() }
    })
    $List.add_DrawItem({ param($sender,$e) $e.DrawDefault = $true })
    $List.add_DrawSubItem({ param($sender,$e) $e.DrawDefault = $true })
}
function New-EmptyState($Parent,$Y,$Height) {
    $label = [Windows.Forms.Label]::new()
    $label.Location = [Drawing.Point]::new(24,$Y)
    $label.Size = [Drawing.Size]::new(596,$Height)
    $label.Font = [Drawing.Font]::new('Segoe UI',9)
    $label.ForeColor = [Drawing.ColorTranslator]::FromHtml('#94A3B8')
    $label.BackColor = [Drawing.ColorTranslator]::FromHtml('#0B0F19')
    $label.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
    $Parent.Controls.Add($label)
    $label.BringToFront()
    return $label
}

#region 14. Disk analysis view
$diskCard = Create-Card $viewDisk (New-Object System.Drawing.Point(0, 4)) (New-Object System.Drawing.Size(644, 400))

$diskTitle = New-Object System.Windows.Forms.Label
$diskTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$diskTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$diskTitle.Location = New-Object System.Drawing.Point(12, 10)
$diskTitle.AutoSize = $true
$diskCard.Controls.Add($diskTitle)

$diskDesc = New-Object System.Windows.Forms.Label
$diskDesc.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$diskDesc.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$diskDesc.Location = New-Object System.Drawing.Point(12, 30)
$diskDesc.Size = New-Object System.Drawing.Size(470, 30)
$diskCard.Controls.Add($diskDesc)

$btnAnalyze = New-Object System.Windows.Forms.Button
$btnAnalyze.Size = New-Object System.Drawing.Size(130, 32)
$btnAnalyze.Location = New-Object System.Drawing.Point(500, 14)
$btnAnalyze.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAnalyze.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')
$btnAnalyze.FlatAppearance.BorderSize = 1
$btnAnalyze.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
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
Set-ListTheme $lvDisk
$lblDiskEmpty = New-EmptyState $diskCard 116 100

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
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
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
    Set-ListTheme $lv
    return $lv
}

$trapCard = Create-Card $viewTrap (New-Object System.Drawing.Point(0, 4)) (New-Object System.Drawing.Size(644, 96))
$trapTitle = New-TrapLabel $trapCard 12 10 9 $true '#94A3B8'
$lblTrapState = New-TrapLabel $trapCard 12 26 13 $true '#94A3B8'
$lblTrapDetail = New-TrapLabel $trapCard 12 56 9 $false '#94A3B8'
$lblTrapDetail.AutoSize = $false
$lblTrapDetail.Size = New-Object System.Drawing.Size(284, 36)
$btnTrapInstall = New-TrapButton $trapCard 304 56 '#3B82F6'
$btnTrapRemove = New-TrapButton $trapCard 416 56 '#F87171'
$btnTrapLog = New-TrapButton $trapCard 528 56 '#94A3B8'
Register-CardHover $trapCard

$trapTopCard = Create-Card $viewTrap (New-Object System.Drawing.Point(0, 106)) (New-Object System.Drawing.Size(644, 124))
$trapTopTitle = New-TrapLabel $trapTopCard 12 8 9 $true '#94A3B8'
# Column widths leave room for the vertical scrollbar (no horizontal one)
$lvTrapTop = New-TrapList $trapTopCard 12 28 620 88 @(290, 80, 90, 120)
$lblTrapTopEmpty = New-EmptyState $trapTopCard 60 48
Register-CardHover $trapTopCard

$trapRecentCard = Create-Card $viewTrap (New-Object System.Drawing.Point(0, 238)) (New-Object System.Drawing.Size(644, 166))
$trapRecentTitle = New-TrapLabel $trapRecentCard 12 8 9 $true '#94A3B8'
$lvTrapRecent = New-TrapList $trapRecentCard 12 28 620 130 @(110, 80, 56, 230, 110)
$lblTrapRecentEmpty = New-EmptyState $trapRecentCard 68 60
Register-CardHover $trapRecentCard

$script:TrapProc = $null
$script:TrapLastState = $null
$script:TrapSig = $null

function Get-TrapCulpritText([string]$Name) {
    if ($Name -in @('*drivers*','*unattributed*')) { return (T 'trapDrivers') }
    return $Name
}

function Set-TrapStateLabel($St) {
    if (-not $St.Installed)  { $key = 'trapStMissing'; $color = '#94A3B8' }
    elseif ($St.Outdated)    { $key = 'trapStUpdate';  $color = '#3B82F6' }
    elseif ($St.Running)     { $key = 'trapStRunning'; $color = '#10B981' }
    else                     { $key = 'trapStStopped'; $color = '#F59E0B' }
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

function Update-TrapLists($Episodes, $St) {
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
    Fit-ListColumns $lvTrapTop
    $lblTrapTopEmpty.Visible = ($lvTrapTop.Items.Count -eq 0)

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
        $note = ''
        if ($ep.Defender -eq 'scan') { $note = (T 'trapNoteScan') }
        elseif ($ep.Defender -eq 'realtime') { $note = (T 'trapNoteRealtime') }
        $item = New-Object System.Windows.Forms.ListViewItem((ConvertFrom-TrapTime $ep.Start.t).ToString('dd.MM HH:mm:ss'))
        [void]$item.SubItems.Add($dur)
        [void]$item.SubItems.Add($peak)
        [void]$item.SubItems.Add(('{0}  {1:N0}%' -f (Get-TrapCulpritText $c.Name), $c.Pct))
        [void]$item.SubItems.Add($note)
        [void]$lvTrapRecent.Items.Add($item)
    }
    $lvTrapRecent.EndUpdate()
    Fit-ListColumns $lvTrapRecent
    $lblTrapRecentEmpty.Visible = ($lvTrapRecent.Items.Count -eq 0)
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
            Update-TrapLists (Get-TrapEpisodes $records) $st
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
    if ($script:TestMode) { return }
    if ($script:TrapProc) { Write-Log (T 'logBusy') 'warn'; return }
    if (-not (Test-Path -LiteralPath $script:TrapScript)) { Write-Log (T 'logTrapNoScript') 'error'; return }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f $script:TrapScript), ('-' + $Mode))
    if ($Mode -eq 'Install') { $argList += @('-ReaderSid',[Security.Principal.WindowsIdentity]::GetCurrent().User.Value) }
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
        $logBox.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
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
    $script:Sync.Busy = $true
    $script:Sync.Beat = [DateTime]::UtcNow
    [void]$script:Tasks.Add(@{ PS = $ps; RS = $rs; Handle = $handle; TimedOut = $false })
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
    $script:LastScanResult = $r
    foreach ($k in $r.Categories.Keys) { $script:CatSizes[$k] = $r.Categories[$k].Size }
    if ($r.TotalSize -gt 0) {
        $lblJunkVal.Text = Format-Bytes ([long]$r.TotalSize)
        # Time-capped scan: the real total is at least this much
        if ($r.Partial) { $lblJunkVal.Text = '≥ ' + $lblJunkVal.Text }
    }
    elseif ($r.Status -eq 'Failed') { $lblJunkVal.Text = (T 'scanFailed') }
    elseif ($r.Status -eq 'Partial') { $lblJunkVal.Text = (T 'scanIncomplete') }
    else { $lblJunkVal.Text = (T 'cleanState') }
    foreach ($scanError in $r.Errors) { Write-Log $scanError 'warn' }
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
    $level = if ($r.Status -eq 'Success') { 'success' } elseif ($r.Status -eq 'Partial') { 'warn' } else { 'error' }
    try {
        if ($r.Status -ne 'Failed') { Update-MaintenanceStats ([long]$r.Bytes); Update-StatsUI }
    } catch { Write-Log ('Settings could not be saved: ' + $_.Exception.Message) 'error'; $level = 'error' }
    Write-Log ([string]::Format((T 'logMaintenanceResult'), $r.Status, $r.Count, (Format-Bytes ([long]$r.Bytes)), $r.Skipped, $r.Errors.Count)) $level
    foreach ($maintenanceError in $r.Errors) { Write-Log $maintenanceError 'error' }
    if ($r.Ram) { Write-Log ([string]::Format((T 'logRamResult'), (Format-Bytes ([long]$r.Ram.Saved)), $r.Ram.Success, $r.Ram.Fail)) 'info' }
    if (-not $script:ExitRequested) {
        Start-EngineTask $script:ScanTaskCode @{ IsAdmin = $script:IsAdmin }
        $lblJunkVal.Text = (T 'calculating')
    }
}

function Complete-Ram {
    param($r)
    Write-Log ([string]::Format((T 'logRamResult'), (Format-Bytes ([long]$r.Saved)), $r.Success, $r.Fail)) 'info'
    $script:Sync.Busy = $false
    Update-Status
}

function Complete-Disk {
    param($r)
    $script:Sync.DiskProgress = $null
    $diskDesc.Text = (T 'diskDesc')
    $lvDisk.Items.Clear()
    foreach ($row in $r.Rows) {
        $item = New-Object System.Windows.Forms.ListViewItem($row.Name)
        $sizeText = Format-Bytes ([long]$row.Size)
        if ($row.Partial) { $sizeText = '≥ ' + $sizeText }
        [void]$item.SubItems.Add($sizeText)
        [void]$lvDisk.Items.Add($item)
    }
    Fit-ListColumns $lvDisk
    $lblDiskEmpty.Visible = ($lvDisk.Items.Count -eq 0)
    if ($r.Status -eq 'Success') { Write-Log ([string]::Format((T 'logDiskDone'), $r.Count)) 'success' }
    else { $diskDesc.Text = T 'diskIncomplete'; $lblDiskEmpty.Text = T 'diskIncomplete'; Write-Log (T 'diskIncomplete') 'warn' }
    foreach ($issue in $r.Errors) { Write-Log $issue 'error' }
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
                    # The Fotokapan view is up: snapshot it once per language
                    if ($cycle -lt 2) { Save-StressSnapshot ('stress-trap-{0}.png' -f $script:Settings.language) }
                    if ($script:Settings.language -eq 'en') { $script:Settings.language = 'tr' } else { $script:Settings.language = 'en' }
                    Apply-Language
                    if (-not $script:Sync.Busy -and ($cycle % 3) -eq 0) { Start-ScanTask; $script:StressScans++ }
                    Add-StressSample $cycle
                }
            } elseif (-not $script:Sync.Busy -or $script:StressClock.Elapsed.TotalMinutes -gt 10) {
                $script:StressTimer.Stop()
                $script:Settings.language = $script:StressLanguage
                Apply-Language
                Add-StressSample $script:StressCycles
                $report = [ordered]@{
                    version = "$script:AppVersion $script:AppEdition"; cycles = $script:StressCycles; scans = $script:StressScans
                    seconds = [Math]::Round($script:StressClock.Elapsed.TotalSeconds, 1); busyAtEnd = [bool]$script:Sync.Busy
                    logErrors = [int]$script:LogErrors; lastError = [string]$script:LastErrorText; tickError = [bool]$script:TickErrorShown
                    lastScanStatus = $(if ($script:LastScanResult) { $script:LastScanResult.Status } else { '' })
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
                if ($t.TimedOut) {
                    $script:Sync.Busy = $false
                    $script:Sync.ScanResult = $null; $script:Sync.CleanResult = $null; $script:Sync.RamResult = $null; $script:Sync.DiskResult = $null
                    $btnOneClick.Enabled = $true; $btnOneClick.Text = (T 'btnOneClick')
                    $btnAnalyze.Enabled = $true; $btnAnalyze.Text = (T 'btnAnalyze')
                    Update-Status
                }
            } elseif (-not $t.TimedOut -and ([DateTime]::UtcNow - [DateTime]$script:Sync.Beat).TotalSeconds -gt 60) {
                # Watchdog: workers post a progress beat to $Sync.Beat every
                # 500 files. Long runs are legitimate (cleaning a %TEMP% with
                # hundreds of thousands of folders takes minutes), so only a
                # worker that made no progress for 60s - blocked in native
                # I/O, where even the debugger cannot break in - is abandoned
                # and the UI remains busy until cancellation actually completes. BeginStop is async on
                # purpose: Stop()/Dispose() could block just as badly if the
                # thread is genuinely stuck.
                # Name where it stalled: the category or the last folder with progress
                Write-Log ('{0} [{1}]' -f (T 'logTaskTimeout'), $script:Sync.Step) 'error'
                try { [void]$t.PS.BeginStop($null, $null) } catch {}
                $t.TimedOut = $true
                $btnOneClick.Enabled = $false
                $btnAnalyze.Enabled = $false
            }
        }

        $dp = $script:Sync.DiskProgress
        if ($dp) {
            $txt = [string]::Format((T 'diskProgress'), $dp[0], $dp[1], $dp[2])
            if ($diskDesc.Text -ne $txt) { $diskDesc.Text = $txt }
        }
        if ($script:TrapProc) { Complete-TrapAction }

        $cancelling = @($script:Tasks | Where-Object { $_.TimedOut }).Count -gt 0
        if (-not $cancelling) {
        if ($script:Sync.ScanResult)  { $r = $script:Sync.ScanResult;  $script:Sync.ScanResult = $null;  Complete-Scan $r }
        if ($script:Sync.CleanResult) { $r = $script:Sync.CleanResult; $script:Sync.CleanResult = $null; Complete-Clean $r }
        if ($script:Sync.RamResult)   { $r = $script:Sync.RamResult;   $script:Sync.RamResult = $null;   Complete-Ram $r }
        if ($script:Sync.DiskResult)  { $r = $script:Sync.DiskResult;  $script:Sync.DiskResult = $null;  Complete-Disk $r }
        }
        if ($script:ExitRequested -and $script:Tasks.Count -eq 0) { $form.Close() }
    } catch { Write-Log ([string]::Format((T 'logError'), $_.Exception.Message)) 'error' }
})
#endregion

#region 18. Action handlers
$btnOneClick.add_Click({
    if ($script:Sync.Busy) {
        Write-Log (T 'logBusy') 'warn'
        return
    }
    $selected = @($script:Settings.categories.Keys | Where-Object { $script:Settings.categories[$_] })
    if (-not $selected.Count -and -not $script:Settings.trimRam -and -not $script:Settings.clearDns) { Write-Log (T 'nothingSelected') 'warn'; return }
    $names = @($selected | ForEach-Object { T ('cat_' + $_) })
    if ($script:Settings.trimRam) { $names += T 'optRam' }
    if ($script:Settings.clearDns) { $names += T 'optDns' }
    $message = (T 'confirmMaintenance') + "`r`n`r`n" + ($names -join "`r`n")
    if ($selected -contains 'recycle') { $message += "`r`n`r`n" + (T 'warnRecycle') }
    if ($selected -contains 'shader') { $message += "`r`n" + (T 'warnShader') }
    if ($selected -contains 'wer') { $message += "`r`n" + (T 'warnWer') }
    if ($selected -contains 'wu') { $message += "`r`n" + (T 'warnWu') }
    $answer = [Windows.Forms.MessageBox]::Show($form, $message, 'OpenRelax', [Windows.Forms.MessageBoxButtons]::OKCancel, [Windows.Forms.MessageBoxIcon]::Warning, [Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($answer -ne [Windows.Forms.DialogResult]::OK) { return }
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
    Start-EngineTask $script:CleanTaskCode @{ IsAdmin = $script:IsAdmin; Keys = $keys; Confirmed = $true; Headless = $false; TrimRam = $script:Settings.trimRam; ClearDns = $script:Settings.clearDns }
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
    $diskTarget = if ($script:TestMode) { $FixtureRoot } else { $env:USERPROFILE }
    Start-EngineTask $script:DiskTaskCode @{ Target = $diskTarget }
})
#endregion

#region 19. Localization apply
function Apply-Language {
    $lblDiskEmpty.Text = T 'diskEmpty'
    $lblTrapTopEmpty.Text = T 'trapEmpty'
    $lblTrapRecentEmpty.Text = T 'trapEmpty'
    if ($script:LastScanResult -and $script:LastScanResult.TotalSize -eq 0) {
        $lblJunkVal.Text = if ($script:LastScanResult.Status -eq 'Failed') { T 'scanFailed' } elseif ($script:LastScanResult.Status -eq 'Partial') { T 'scanIncomplete' } else { T 'cleanState' }
    }
    $chkRam.Text = T 'optRam'; $chkDns.Text = T 'optDns'
    $switchPanel.AccessibleName = T 'autoBoost'
    $btnClose.AccessibleName = T 'accessibleClose'
    $btnMin.AccessibleName = T 'accessibleMinimize'
    $logBox.AccessibleName = T 'accessibleLog'
    $cmbLimit.AccessibleName = T 'accessibleThreshold'
    $cmbLang.AccessibleName = T 'language'
    $lvDisk.AccessibleName = T 'diskTitle'
    $lvTrapTop.AccessibleName = T 'trapTopTitle'
    $lvTrapRecent.AccessibleName = T 'trapRecentTitle'
    $script:UILoading = $true
    try { $cmbLang.SelectedIndex = if ($script:Settings.language -eq 'en') { 1 } else { 0 } } finally { $script:UILoading = $false }

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
        if ($script:Settings.autoBoost -and -not $script:ExitRequested) {
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
    if ($script:Tasks.Count -gt 0) {
        $e.Cancel = $true
        if (-not $script:ExitRequested) { Write-Log (T 'logExitPending') 'warn' }
        $script:ExitRequested = $true
        $script:ReallyExit = $true
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
    if (-not $script:SettingsValid -and $settingsDocument.Exists) { Write-Log ('Settings were rejected; safe defaults are active: ' + $script:SettingsError) 'error' }
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
    $workingArea = [Windows.Forms.Screen]::FromControl($form).WorkingArea
    $form.Size = New-Object Drawing.Size([Math]::Min(680,$workingArea.Width),[Math]::Min(590,$workingArea.Height))
    $form.Location = New-Object Drawing.Point(($workingArea.Left + [Math]::Max(0,[int](($workingArea.Width-$form.Width)/2))),($workingArea.Top + [Math]::Max(0,[int](($workingArea.Height-$form.Height)/2))))
    if ($StartMinimized) {
        $script:BalloonShown = $true
        Hide-ToTray
    }
})

# Match keyboard traversal to the visual order, including controls added later.
function Set-VisualTabOrder([Windows.Forms.Control]$Parent) {
    $index = 0
    foreach ($control in @($Parent.Controls | Sort-Object Top,Left)) {
        $control.TabIndex = $index++
        if ($control.HasChildren) { Set-VisualTabOrder $control }
    }
}
Set-VisualTabOrder $form

Show-View 'dash'
Apply-Language
$script:UILoading = $false

# Visual fixture mode exercises the real renderer without external input.
if ($ExitDuringWorkerTest) {
    $script:ExitTestTimer = [Windows.Forms.Timer]::new()
    $script:ExitTestTimer.Interval = 200
    $script:ExitTestTimer.add_Tick({
        if ($script:Sync.Busy -or $script:Tasks.Count) { return }
        $script:ExitTestTimer.Stop()
        $probe = @'
param($Sync,$Opt)
[IO.File]::WriteAllText($Opt.Path,'begin')
Start-Sleep -Seconds 3
[IO.File]::AppendAllText($Opt.Path,';end')
$Sync.RamResult = @{ Saved = 0; Success = 0; Fail = 0 }
'@
        Start-EngineTask $probe @{ Path = (Join-Path $FixtureRoot 'exit-worker.txt') }
        $script:ReallyExit = $true
        $form.Close()
    })
    $form.add_Shown({ $script:ExitTestTimer.Start() })
}
if ($VisualReportDir) {
    [void][IO.Directory]::CreateDirectory($VisualReportDir)
    Add-Type -Namespace OpenRelax -Name VisualApi -MemberDefinition '[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);'
    $script:VisualStep = 0
    $script:VisualErrors = @()
    $script:VisualTimer = New-Object System.Windows.Forms.Timer
    $script:VisualTimer.Interval = 500
    $script:VisualTimer.add_Tick({
        try {
            $index = [int][Math]::Floor($script:VisualStep / 2)
            if ($index -ge 8) {
                $script:VisualTimer.Stop()
                @{ screenshots = 8; errors = @($script:VisualErrors) } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $VisualReportDir 'visual-report.json') -Encoding UTF8
                $script:ReallyExit = $true
                $form.Close()
                return
            }
            $language = if ($index -lt 4) { 'tr' } else { 'en' }
            $view = @('dash','settings','disk','trap')[$index % 4]
            if (($script:VisualStep % 2) -eq 0) {
                $script:Settings.language = $language
                Apply-Language
                Show-View $view
            } else {
                $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height)
                $graphics = [Drawing.Graphics]::FromImage($bmp)
                $hdc = $graphics.GetHdc()
                try { $captured = [OpenRelax.VisualApi]::PrintWindow($form.Handle, $hdc, 0) }
                finally { $graphics.ReleaseHdc($hdc); $graphics.Dispose() }
                try {
                    if (-not $captured) { throw 'PrintWindow failed.' }
                    $bmp.Save((Join-Path $VisualReportDir ($language + '-' + $view + '.png')), [Drawing.Imaging.ImageFormat]::Png)
                } finally { $bmp.Dispose() }
            }
            $script:VisualStep++
        } catch {
            $script:VisualErrors += $_.Exception.Message
            $script:VisualStep++
        }
    })
    $form.add_Shown({ $script:VisualTimer.Start() })
}
if ($UiAcceptanceReportDir) {
    [void][IO.Directory]::CreateDirectory($UiAcceptanceReportDir)
    $script:UiProbeTimer = [Windows.Forms.Timer]::new()
    $script:UiProbeTimer.Interval = 250
    $script:UiProbeTimer.add_Tick({
        if ($script:Sync.Busy -or $script:Tasks.Count) { return }
        $script:UiProbeTimer.Stop()
        $errors = @(); $checks = @()
        $originalSize = $form.Size; $originalLanguage = $script:Settings.language
        try {
            Show-View 'settings'
            $form.Activate()
            $expected = @($chkTray,$chkStartup,$chkWeekly,$chkRam,$chkDns,$cmbLang)
            if ($btnElevate.Enabled -and $btnElevate.Visible) { $expected += $btnElevate }
            $current = $null
            foreach ($control in $expected) {
                $moved = $genCard.SelectNextControl($current,$true,$true,$false,$false)
                if (-not $moved -or -not $control.Focused) { throw ('Settings focus order failed at: ' + $control.Text) }
                $current = $control
            }
            if ($genCard.SelectNextControl($current,$true,$true,$false,$false)) { throw 'Unexpected additional settings tab stop.' }
            $checks += 'settings-focus-order'
            foreach ($language in 'tr','en') {
                $script:Settings.language = $language; Apply-Language
                foreach ($control in @($btnClose,$btnMin,$cmbLimit,$cmbLang,$logBox,$lvDisk,$lvTrapTop,$lvTrapRecent)) {
                    $name = [string]$control.AccessibilityObject.Name
                    if ([string]::IsNullOrWhiteSpace($name) -or $name -ne $control.AccessibleName) { throw 'Accessible name missing or inconsistent.' }
                }
            }
            if ($chkDns.AccessibilityObject.Role.ToString() -ne 'CheckButton') { throw 'DNS option lacks native checkbox accessibility role.' }
            $priorDns = $chkDns.Checked
            try {
                $chkDns.AccessibilityObject.DoDefaultAction()
                if ($chkDns.Checked -eq $priorDns) { throw 'Native checkbox default action failed.' }
                $saved = Read-SettingsDocument $script:SettingsFile
                if (-not $saved.Valid -or $saved.Settings.clearDns -ne $chkDns.Checked) { throw 'Checkbox preference did not persist.' }
            } finally {
                if ($chkDns.Checked -ne $priorDns) { $chkDns.AccessibilityObject.DoDefaultAction() }
            }
            $checks += 'accessible-names-and-checkbox-action'
            Show-View 'dash'
            $form.AutoScrollPosition = [Drawing.Point]::Empty
            $form.Size = [Drawing.Size]::new(540,450)
            $form.PerformLayout()
            $form.ScrollControlIntoView($switchPanel)
            $form.PerformLayout()
            $bounds = $switchPanel.RectangleToScreen($switchPanel.ClientRectangle)
            $visible = $bounds; $parent = $switchPanel.Parent
            while ($parent) {
                $visible = [Drawing.Rectangle]::Intersect($visible,$parent.RectangleToScreen($parent.ClientRectangle))
                $parent = $parent.Parent
            }
            if (-not $visible.Equals($bounds)) { throw 'Small viewport cannot reveal the dashboard option.' }
            if (-not $form.HorizontalScroll.Visible -or -not $form.VerticalScroll.Visible) { throw 'Small viewport did not exercise both scrollbars.' }
            $checks += 'small-viewport-reachability'
        } catch { $errors += $_.Exception.Message }
        finally {
            $script:Settings.language = $originalLanguage; Apply-Language
            $form.Size = $originalSize; $form.AutoScrollPosition = [Drawing.Point]::Empty
            @{ passed = ($errors.Count -eq 0 -and $checks.Count -eq 3); checks = @($checks); errors = @($errors); boundary = 'Native control API; no physical keyboard, Narrator speech or monitor DPI transition.' } |
                ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $UiAcceptanceReportDir 'ui-report.json') -Encoding UTF8
            $script:ReallyExit = $true; $form.Close()
        }
    })
    $form.add_Shown({ $script:UiProbeTimer.Start() })
}

try { [System.Windows.Forms.Application]::Run($form) }
finally { if ($script:OwnGuiMutex) { $script:GuiMutex.ReleaseMutex() }; $script:GuiMutex.Dispose() }

# Guarantee process termination even if a worker runspace thread is still alive
[Environment]::Exit(0)
#endregion
