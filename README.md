# OpenRelax PC Care

[![Windows verification](https://github.com/mehmeterendereli/openrelax/actions/workflows/verify.yml/badge.svg)](https://github.com/mehmeterendereli/openrelax/actions/workflows/verify.yml)

Portable, MIT-licensed Windows maintenance software written in PowerShell and
Windows Forms. The source version is declared once, as `$script:AppVersion` in
`openrelax.ps1`; the latest
[GitHub source release](https://github.com/mehmeterendereli/openrelax/releases/latest)
is listed on the releases page ([changelog](CHANGELOG.md)). Releases contain
source only: no signed binary, stable binary distribution or published LTS
support period is provided.

## Install

```powershell
irm https://raw.githubusercontent.com/mehmeterendereli/openrelax/main/install.ps1 | iex
```

The installer reads the latest release, checks the zip against its published
SHA256 **before** extracting, installs to `%LOCALAPPDATA%\Programs\OpenRelax`
for the current user (no administrator rights) and adds a Start menu shortcut.
Settings and records stay in `%APPDATA%\OpenRelax`. Prefer to look first?
[Read install.ps1](install.ps1), download the release zip and `SHA256SUMS`
yourself, or use Scoop:
`scoop bucket add openrelax https://github.com/mehmeterendereli/openrelax` and
then `scoop install openrelax/openrelax`.

## Measured footprint

OpenRelax sits in the tray with the Fotokapan recorder on. `tests/footprint.ps1`
measures the app process itself:

| 10 minutes in the tray, Fotokapan on (Windows 11, 12 logical CPUs) | Value |
| --- | ---: |
| Average CPU, as a share of one core | 0.07 % |
| Highest 10-second CPU | 0.47 % |
| Private memory | 149 MB |
| Memory growth over the run | none (−53 MB once the startup scan was released) |
| Handles / GDI objects | 937 / 35 |

Run it yourself: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\footprint.ps1`
(it uses an owned test folder, cleans nothing and fails above 1 % CPU or 20 MB growth).

The base cost is Windows PowerShell plus WinForms memory. The claim is
near-zero background CPU, not the smallest RAM.

## Interface preview

| English | Türkçe |
| --- | --- |
| ![OpenRelax English dashboard showing maintenance status and review controls](docs/screenshots/en-dashboard.png) | ![OpenRelax Türkçe panel; bakım durumu ve gözden geçirme denetimleri](docs/screenshots/tr-dashboard.png) |

These are real 680×590 WinForms captures made by `tests/visual-smoke.ps1`, not
mock-ups; every CI run publishes fresh ones as evidence.
[Browse all eight TR/EN interface captures](docs/screenshots/README.md).

## Run from source

Keep `openrelax.ps1`, `fotokapan.ps1`, `lib/` and `launch.bat` together. Use
Windows PowerShell 5.1 (`powershell.exe`) on Windows with Windows Forms.
PowerShell 7 and other operating systems are not validated targets.

```bat
launch.bat
```

To create a desktop shortcut with the OpenRelax icon, run
`powershell -NoProfile -ExecutionPolicy Bypass -File .\install-shortcut.ps1`.
The shortcut points to this checkout; keep the folder in place. Administrator
rights are not needed and a different existing shortcut is preserved. Keep
`install-shortcut.ps1` and `docs/openrelax.ico` with the source for this command.

The GUI opens without elevation. Administrator rights are only needed for
marked system targets and for removing the old Fotokapan task of 2.3 and earlier. Review the selected
operations and confirmation dialog before maintenance.

```powershell
# Read-only scan; no saved state is written
powershell -NoProfile -ExecutionPolicy Bypass -File .\openrelax.ps1 -SelfTest

# Open in the tray
powershell -NoProfile -ExecutionPolicy Bypass -File .\openrelax.ps1 -StartMinimized

# Scheduled maintenance using valid saved settings
powershell -NoProfile -ExecutionPolicy Bypass -File .\openrelax.ps1 -AutoClean
```

## Behaviour and safety boundaries

- Defaults select temp, browser cache and Discord cache. Recycle Bin, shader
  cache, error reports, update cache, GPU installer leftovers and developer
  package caches (npm, pip, NuGet, Yarn; files untouched for 24 hours) are opt-in.
- Cleaning shows the files and bytes deleted so far on the maintenance button.
- Interactive maintenance requires confirmation, including warnings for
  permanent Recycle Bin deletion and diagnostic/cache consequences.
- RAM working-set trimming and DNS flushing are separate opt-in settings.
  Automatic RAM trimming is also disabled by default. Critical processes, the
  foreground app (a game, a call), processes busy during a 500 ms CPU sample and
  processes under 30 MB are never trimmed. Trimming can cause pages
  to be loaded again; measured available-memory change is temporary and also
  affected by other programs. It is not proof of a performance improvement.
- Only the canonical user temp and Windows temp paths are accepted. Custom
  `TEMP` values are skipped with a warning. Temp files younger than 24 hours
  and temporary staging directories are kept.
- Protected roots, relative/UNC paths and reparse ancestors are refused for
  deletion. Junctions and symlinks are left in place; locked files are skipped.
  Browser history/bookmarks, Prefetch, Windows Logs and Panther are excluded.
- Windows Update cleanup is interactive, admin-only and restores previously
  running services. Stop/restart failures are errors.
- `-AutoClean` rejects missing/invalid settings. It skips Recycle Bin, shader,
  WER, Windows Update, installer and developer-cache categories and does not
  trim RAM/flush DNS.
  Exit codes: **0** complete, **1** failed, **2** partial/skipped. `-SelfTest`
  also exits nonzero when its scan cannot complete reliably. Combining
  `-SelfTest` and `-AutoClean` is refused before any maintenance or state write.
- Settings use validated types, atomic replacement and a state mutex.
  Global, access-controlled mutexes coordinate the same settings path across Windows
  sessions; one GUI instance prevents stale preference overwrites.
  Statistics preserve the most recent saved preferences.
- Scan sizes may be lower bounds. Disk analysis walks the profile once with
  per-folder totals (files directly in the profile get their own row), skips
  links and unreadable entries, stops after 90 seconds and labels incomplete
  results. A stalled
  worker keeps the GUI busy until cancellation actually completes. Exit waits
  for active operations and service restoration instead of terminating their worker.

Settings and aggregate statistics: `%APPDATA%\OpenRelax\settings.json`.
Scheduled results: `%APPDATA%\OpenRelax\autoclean.log`.
Existing valid 2.1/2.2 settings retain their categories and statistics; new
RAM/DNS, developer-cache and command-line options default off. An invalid file is not silently replaced by AutoClean; review and save
preferences in the GUI to recover it.

## Fotokapan CPU spike recorder

Fotokapan runs **inside OpenRelax** while it is open, in the tray included. It
needs no administrator rights and no scheduled task. Turn it on or off with one
switch on the Fotokapan tab; it is on by default.

**How it records:**
- Every 2 seconds it reads three counters: total CPU, interrupt time and DPC time.
- When CPU stays at or above 85 % for 4 seconds, it reads every process's CPU in a single performance-counter call. That call takes about 16 ms of CPU and includes protected processes such as Defender.
- It records the burst itself:
  - process names, IDs and CPU shares;
  - parent names;
  - whether Task Scheduler started the process;
  - the measured interrupt and DPC share.

**Culprits:**
- Interrupt/DPC load of at least 10 % that outweighs the top process is reported as driver load.
- Other CPU that no process accounts for is labelled unattributed rather than blamed on a driver.
- Defender scan versus real-time classification is a heuristic based on the Defender event log.

**Records:**
- They go to `%APPDATA%\OpenRelax\Fotokapan\` (`spikes-YYYY-MM.jsonl`, `durum.json`); **Open folder** shows them.
- Nothing is recorded while OpenRelax is closed.

**Command lines:** they are not recorded by default (`cmd` and `parentCmd` stay empty). With **Record command lines (masked)** on, masked command lines show which script a `python.exe` or `node.exe` spike ran; the change applies immediately. Masking removes common token, password and key forms, but it cannot guarantee that every secret is removed.

**The tab:**
- **Summary** turns the last 7 days into findings per culprit category with advice, the culprit table and spikes per hour of day.
- **Records** lists every spike.
- **Save report** writes the diagnosis as Markdown to `Documents\OpenRelax\`.
- A tray balloon announces a new spike (at most one per 15 minutes; switch it off on the tab).

**Upgrading from 2.3 or earlier.** The old recorder was a SYSTEM scheduled task (`fotokapan.ps1`).
- While it still runs, the built-in recorder waits so no spike is logged twice, and the tab shows **Remove old task** (one administrator prompt).
- Its records in `%ProgramData%\OpenRelax\Fotokapan\` stay readable and keep appearing in the tab.
- `fotokapan.ps1` remains in 2.4 only for this removal and for its CI acceptance test.
- Older records can still contain command arguments; review them before sharing.

Records reveal process names and timestamps. Omitting arguments does not make
every recorded diagnostic detail anonymous.

## Verification and contribution

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify.ps1
# Interactive desktop: capture all four real pages in TR and EN
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\visual-smoke.ps1
# Native focus, accessible controls and small-viewport reachability
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ui-smoke.ps1
# Release gate: every suite in order with a summary
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-all.ps1
```

`verify.ps1` also runs `tests\unit.ps1`: the engine walker, categories, RAM-trim
selection, Fotokapan recorder helpers and legacy-log migration, diagnosis,
report and notification rules.

CI parses every PowerShell source/test and all five worker scripts, runs
deterministic safety contracts and starts real isolated SelfTest/AutoClean
processes over small synthetic fixtures. It verifies refusal on corrupt
settings, unchanged state during SelfTest and actual deletion/count/statistics.
Test workspaces must be new and marked as owned; existing directories are
refused. `-TestMode` isolates targets/state and disables system integration.
Test hooks are ignored during normal operation.

GUI/resource stress and CPU-burst tests are optional local checks. Do not run
CPU-burst tests on a busy production machine. On a disposable GitHub-hosted
Windows Server 2025 runner, CI also performs a real Fotokapan install, starts the
SYSTEM task, checks protected ACLs through a separate standard-user logon (read
allowed; write/delete denied), upgrades the same reviewed source and uninstalls
while retaining logs. See the [passing evidence run](https://github.com/mehmeterendereli/openrelax/actions/runs/39055301873).
This is not validation of real Windows Update restoration, reboot persistence,
RDP, physical keyboard use, Narrator, monitor-DPI transitions, signing, a stable
release or LTS support. `tests\exit-smoke.ps1` also verifies that closing the
real test GUI waits for its owned worker instead of interrupting it.

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md),
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), [CHANGELOG.md](CHANGELOG.md) and the
ordered [end-to-end plan](PLAN.md). For a reproducible product problem, [open an
issue](https://github.com/mehmeterendereli/openrelax/issues/new) with the Windows
version, exact command or page, expected result, actual result and any reviewed,
non-sensitive log excerpt.

## Source map

| Source | Responsibility |
| --- | --- |
| `openrelax.ps1` | WinForms UI, target descriptors, Windows integration and worker entrypoints |
| `lib/OpenRelax.Core.ps1` | Typed settings, atomic persistence, path guards, traversal and shared maintenance orchestration |
| `lib/OpenRelax.Engine.ps1` | Cleanup categories, the guarded single-pass walker, Windows Update cleanup and RAM trimming |
| `lib/OpenRelax.Trap.ps1` | Fotokapan record reading, episodes, culprits, diagnosis, report and notification rules |
| `lib/OpenRelax.Sampler.ps1` | Embedded Fotokapan: PDH sampling, spike tracker, records and heartbeat |
| `fotokapan.ps1` | Former SYSTEM recorder (2.3 and earlier); kept in 2.4 for removal and its CI acceptance test |
| `install.ps1`, `bucket/`, `.github/workflows/release.yml` | Verified one-line installer, Scoop manifest and release assets |
| `tests/verify.ps1`, `tests/safety-contracts.ps1`, `tests/unit.ps1` | Lightweight CI, pure-function and real synthetic end-to-end checks |
| `tests/run-all.ps1`, `tests/footprint.ps1`, `tests/install-contract.ps1` | Release gate, own-footprint measurement and installer contract |
| `tests/test-support.ps1` | Owned fixtures and bounded child-process isolation |
| `tests/visual-smoke.ps1`, `tests/*-stress.ps1` | Visual and optional resource/load checks |

The UI and target discovery remain in a large script. Further module extraction
should preserve existing contracts, rather than adding features during a safety
fix. Path checks reduce link/race exposure but do not guarantee atomic protection
against a hostile process changing filesystem objects concurrently.

## Türkçe özet

OpenRelax kaynak üzerinden çalışan açık kaynak Windows bakım aracıdır. Bakım
öncesinde seçilen işlemleri gözden geçirin. Sepet, sistem önbellekleri, RAM ve
DNS işlemleri varsayılan olarak kapalıdır. Bozuk ayarla otomatik temizlik durur.
Testler yalnız kendilerinin oluşturduğu sentetik dosyaları kullanır.

2.3 yenilikleri: **Fotokapan** sekmesinde son 7 günün teşhisi (Defender, oyun,
geliştirici/AI araçları, tarayıcı, Windows, zamanlanmış görev ve süreçlere
atanamayan CPU payları, ne yapılacağıyla), saate göre dağılım, tüm sıçramaların
listesi, Markdown raporu (`Belgeler\OpenRelax\`) ve yeni sıçrama bildirimi.
**Komut satırlarını kaydet (maskeli)** seçeneği varsayılan olarak kapalıdır;
açılıp Kur / Güncelle yapıldığında `python.exe` gibi bir sorumlunun hangi betiği
çalıştırdığı görünür. Maskeleme her gizli bilgiyi yakalayamaz. Ayrıca isteğe
bağlı geliştirici önbellekleri (npm, pip, NuGet, Yarn), temizlik sırasında canlı
dosya/bayt sayacı, tek geçişte ve en fazla 90 saniyede biten disk analizi ve ön
plandaki ya da o an çalışan uygulamalara dokunmayan RAM boşaltma geldi. 2.2.x ile
kurulmuş Fotokapan kayıtları, Kur / Güncelle ile yeni `logs\` klasörüne taşınır.
Geliştirme sırası, kabul ölçütleri ve kalan sürüm doğrulamaları [PLAN.md](PLAN.md)
içindedir. Lisans [MIT](LICENSE).

2.4 yenilikleri: **Fotokapan artık OpenRelax'ın içinde çalışıyor.** Yönetici
yetkisi ve zamanlanmış görev gerektirmiyor; Fotokapan sekmesindeki tek düğmeyle
açılıp kapanıyor (varsayılan açık). Tüm süreçlerin CPU payı tek bir performans
sayacı çağrısıyla (~16 ms) okunuyor; Defender dahil. Ölçülmüş kesme/DPC yükü
artık "sürücü" bulgusu olarak ayrı gösteriliyor. Kayıtlar
`%APPDATA%\OpenRelax\Fotokapan\` altında; OpenRelax kapalıyken kayıt alınmaz.
Eski SYSTEM görevi algılanır, çalışırken yerleşik kaydedici çift kayıt olmasın
diye bekler ve **Eski görevi kaldır** düğmesi onu kaldırır; eski kayıtlar
okunmaya devam eder. Tek satırlık kurulum:
`irm https://raw.githubusercontent.com/mehmeterendereli/openrelax/main/install.ps1 | iex`
(zip'in SHA256'sı açmadan önce doğrulanır). Klasör taşınırsa başlangıç kaydı ve
haftalık görev kendiliğinden yeni konuma yönlendirilir.
