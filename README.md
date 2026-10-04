# OpenRelax PC Care

[![Windows verification](https://github.com/mehmeterendereli/openrelax/actions/workflows/verify.yml/badge.svg)](https://github.com/mehmeterendereli/openrelax/actions/workflows/verify.yml)

[Open-source portfolio](https://www.mehmeterendereli.com/en/open-source) · [Maintainer profile](https://github.com/mehmeterendereli)

A portable Windows maintenance utility built with **PowerShell and Windows Forms**. It runs from source, requires no installer, and keeps its cleanup targets and safety boundaries visible in one inspectable script.

**Current status:** source version 2.2.1 ([changelog](CHANGELOG.md)) · long-term support: 2.1.1 LTS on branch `lts/2.1` · focused Windows utility · MIT licensed · CI: parser, read-only self-test, unit tests and engine stress · no signed binary release

> OpenRelax is not a registry “optimizer” and it does not promise permanent RAM gains. It cleans regenerable files, trims eligible process working sets, and reports what happened.

## What you can inspect

| Area | Concrete implementation |
|---|---|
| **Cleanup engine** | Explicit path lists for temporary files, browser/application caches, GPU caches, Windows Error Reporting, update cache and installer leftovers |
| **Safety model** | Administrator-only targets are marked and skipped without elevation; locked files are skipped; sensitive profile data and diagnostic folders are excluded |
| **Execution** | Cleanup, scanning and disk analysis run in background PowerShell runspaces so the WinForms UI remains responsive |
| **Operating modes** | Interactive GUI, tray/minimized startup, scheduled headless cleanup and read-only `-SelfTest` |
| **CPU spike trap** | `fotokapan.ps1` runs as a SYSTEM scheduled task and records which processes (or drivers) caused each CPU spike; the **Fotokapan** tab turns the records into a diagnosis with advice, an hour-of-day distribution and an exportable report |
| **Verification** | Windows CI parses the complete script, runs the real `-SelfTest` path (settings and AutoClean log must stay unchanged), the unit tests and an engine stress test; spike-trap, install and GUI stress tests run locally before a release |
| **Persistence** | Settings and aggregate usage statistics are stored in `%APPDATA%\OpenRelax\settings.json` |

## Execution map

```mermaid
flowchart LR
    USER[User or scheduled task] --> MODE{Mode}
    MODE -->|GUI| SELECT[Select categories]
    MODE -->|SelfTest| SCAN[Read-only scan]
    MODE -->|AutoClean| CLEAN[Headless cleanup]
    SELECT --> WORKER[Background runspace]
    SCAN --> ENGINE[Shared cleanup engine]
    CLEAN --> ENGINE
    WORKER --> ENGINE
    ENGINE --> GUARDS[Privilege and path guards]
    GUARDS --> RESULT[Log, result and statistics]
```

The GUI and headless modes use the same serialized engine functions rather than maintaining separate cleanup implementations.

## Quick start

### Open the interface

Clone or download the repository, then run:

```bat
launch.bat
```

The launcher starts `openrelax.ps1` and opens the Windows Forms interface.

### Inspect without deleting anything

Run the read-only engine scan first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\openrelax.ps1 -SelfTest
```

`-SelfTest` reports the selected targets and what is detectable on the current machine. It is a practical smoke check, **not** a complete unit-test suite.

### Other modes

```powershell
# Start hidden in the system tray
powershell -NoProfile -ExecutionPolicy Bypass -File .\openrelax.ps1 -StartMinimized

# Run cleanup headlessly with saved settings
powershell -NoProfile -ExecutionPolicy Bypass -File .\openrelax.ps1 -AutoClean
```

`-AutoClean` can delete files according to the saved category settings. Use `-SelfTest` first when evaluating the tool on a new system.

### Run as administrator

Administrator rights are needed only for the admin-only cleanup targets (system temp, Windows Error Reporting, Windows Update cache) and for installing or removing the CPU spike trap. Either right-click `launch.bat` → **Run as administrator**, or use **Settings → Restart as administrator** inside the app.

## Fotokapan (CPU spike trap)

Intermittent 100 % CPU is hard to diagnose: by the time Task Manager is open, the burst is often over, and a starved UI thread cannot sample during it. `fotokapan.ps1` therefore runs outside the GUI as a SYSTEM scheduled task (above-normal priority, no time limit):

- When total CPU stays at or above 85 % for 4 seconds it measures **the burst itself** (per-process CPU from the first hot sample), plus parent processes, command lines (secrets masked), processes started in the last two minutes and CPU time no process accounts for (interrupts/DPCs — drivers).
- If Microsoft Defender is among the top consumers it records whether an on-demand scan is running, or otherwise attaches a 30-second Defender performance report (at most every 6 hours) including the folders Defender scanned most.
- Output lives in `C:\ProgramData\OpenRelax\Fotokapan\`: `fotokapan-YYYY-MM.log` (human-readable), `spikes-YYYY-MM.jsonl` (one JSON record per line — the contract the GUI reads) and `durum.json` (heartbeat, rewritten every minute). Only SYSTEM and Administrators can change anything there — the task runs that script as SYSTEM — and only the installing user may read it, since command lines can carry tokens.

The **Fotokapan** tab has two pages:

- **Summary** — the diagnosis of the last 7 days: each culprit category (Defender scans or real-time scanning, drivers, games, developer/AI tools, browser, Windows, scheduled tasks) with its share of the spikes and what to do about it; the culprit table; spikes per hour of day, which exposes periodic jobs.
- **Records** — every spike with its duration, peak, culprit and notes, and **Save report**, which writes the diagnosis as Markdown to `Documents\OpenRelax\`.

When a new spike is recorded the tray icon announces it (at most once per 15 minutes; switch off under Settings). A tab state of **Security update required** means the trap was installed by 2.1 or earlier with user-writable files — **Install / Update** fixes it.

Install, update or remove it from the **Fotokapan** tab (asks for elevation when needed) or from an elevated PowerShell:

```powershell
.\fotokapan.ps1 -Install     # copy to ProgramData, register and start the task
.\fotokapan.ps1 -Uninstall   # remove the task; recorded logs are kept
```

## Automated verification

Every push and pull request targeting `main` runs on a GitHub-hosted Windows machine. The verification job:

1. Parses the complete `openrelax.ps1` file with PowerShell's language parser and fails on any syntax error.
2. Starts the real application in a separate Windows PowerShell process with `-SelfTest`.
3. Requires a zero exit code, the versioned self-test banner and the final `Self-test OK` marker.
4. Exercises the Windows Update service-state contract without deleting files: only services that were running may be stopped, cleanup is blocked after a stop failure, and prior states must be restored.
5. Fingerprints `%APPDATA%\OpenRelax\settings.json` and `autoclean.log` before and after execution, failing if the supposedly read-only path creates, removes or modifies either file.
6. Runs `tests\unit.ps1`: the pure functions — engine walker, categories, RAM-trim selection, recorder helpers, Fotokapan episodes, diagnosis, report and notification rules.
7. Runs `tests\engine-stress.ps1` on a small synthetic tree: the real scan/clean engine with junction, locked-file, 24-hour and long-path traps.

Run the same entrypoint locally:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify.ps1
```

This proves that the checked-in script parses, its non-destructive scan path executes successfully on Windows, its Windows Update service-state guard behaves deterministically, and its persistent settings/log state stays unchanged. It does **not** replace comprehensive unit tests for every cleanup function or destructive-mode testing on every Windows configuration.

### All tests (release gate)

`tests\run-all.ps1` runs every test below in order from an elevated PowerShell, pausing an installed trap while synthetic load runs, and prints a summary. The GUI test needs an interactive desktop.

| Script | What it proves |
|---|---|
| `tests\verify.ps1` | The CI contract above. |
| `tests\unit.ps1` | Pure-function behaviour, in seconds (also in CI). |
| `tests\trap-install.ps1` | Installing into a throw-away folder under a test task name — including over the 2.1 layout — leaves nothing writable by users, keeps the logs readable for the installing user, registers the task as SYSTEM / highest / priority 3 / no time limit, and uninstalls cleanly. |
| `tests\engine-stress.ps1` | The real scan/clean engine, in a worker runspace as the GUI uses it, on a 30 000-file synthetic tree with traps — a junction loop, a junction to an outside sentinel, a held-open file, files younger than 24 h, read-only/hidden files, bracket/Turkish names, deep and over-long paths. Nothing outside the tree is touched, progress beats keep coming and memory stays bounded. |
| `tests\fotokapan-stress.ps1` | A private spike-trap instance through a storm of CPU bursts: every burst caught and attributed to the right process, JSONL contract valid, heartbeat refreshed, monitor overhead and handles/memory stable, and the GUI's reader survives damaged lines. Pause an installed trap first (`Stop-ScheduledTask 'OpenRelax Fotokapan'`) to keep the synthetic bursts out of its statistics. |
| `tests\gui-stress.ps1` | Drives the real GUI handlers for N cycles — view switches, language re-apply, background scans, both Fotokapan pages re-rendered over 300 synthetic spikes, a report export — and fails on handler errors or GDI/USER/handle/memory growth; snapshots the Fotokapan and settings views in both languages; with `-WithDisk` it ends with a real disk analysis; then starts and closes the app repeatedly. Nothing is cleaned and no setting is saved. |

The GUI test uses environment hooks that are inert otherwise: `OPENRELAX_STRESS=<cycles>` with `OPENRELAX_STRESS_REPORT=<file.json>`, `OPENRELAX_STRESS_DISK=1`, `OPENRELAX_SMOKETEST=1|<seconds>` and `OPENRELAX_TRAP_DIR=<folder>`.

## Safety contract

OpenRelax deliberately avoids broad “delete everything” behaviour:

- **Windows Prefetch is not cleaned.** Windows manages it, and removing it can make application launches slower.
- **`Windows\Logs` and `Windows\Panther` are not cleaned.** They may be needed for diagnostics and upgrade rollback.
- **Browser bookmarks, history and profile data are not targeted.** Only known regenerable cache directories are included.
- **Windows Update cleanup is disabled by default** and requires administrator rights. When enabled, the related services are stopped before cleanup and restarted afterward.
- **Administrator-only paths are skipped** when OpenRelax is not elevated.
- **Locked or in-use files are skipped** instead of being forced or scheduled for deletion.
- **Recently changed temp files are kept.** Files in the temp folders that changed within the last 24 hours belong to running applications and are neither counted nor deleted.
- **Junctions are never followed or removed**, so cleaning a folder cannot reach data that a junction points to.
- **Scans are time-budgeted.** A huge temp folder is reported as a lower bound (`≥ X GB`) instead of stalling; background work reports progress, and a worker is abandoned only after 60 seconds without any.
- **Working-set trimming leaves active work alone.** Critical Windows processes, the foreground app (a game, a call), processes busy during a 500 ms CPU sample and processes under 30 MB are never trimmed.
- **Developer caches are opt-in.** The npm, pip, NuGet and Yarn download caches are cleaned only when that category is switched on, and only files untouched for 24 hours.
- **RAM reclamation is temporary by nature.** Applications can request those pages again as their workload continues.

The source remains the final authority. Review `Get-JunkCategories`, `Remove-JunkPaths` and `Invoke-RamTrim` in `openrelax.ps1` before deploying it in a managed environment.

## Features

- One-click maintenance for selected categories
- User and system temporary-file scanning
- Chrome, Edge, Brave, Opera/Opera GX and Firefox cache cleanup across detected profiles
- Discord and GPU shader-cache cleanup
- Optional Windows Error Reporting, Windows Update and GPU-installer cleanup
- Recycle Bin cleanup
- Optional developer package-cache cleanup (npm, pip, NuGet, Yarn)
- Live file and byte count while cleaning
- Native Windows API working-set trimming that skips critical, foreground, busy and small processes
- Automatic RAM threshold with five-minute cooldown and hysteresis
- System tray operation and start-with-Windows option
- Weekly scheduled cleanup using saved settings
- Read-only largest-folder analysis for the user profile: one walk, at most 90 seconds, with progress
- Fotokapan CPU spike trap with a GUI tab: diagnosis and advice, hour-of-day distribution, culprit table, every spike, Markdown report, tray notification, install/update/remove
- Aggregate cleaned-space and maintenance-run statistics
- Turkish and English interface strings
- Live CPU, RAM and uptime display

## Repository map

```text
openrelax.ps1                  Application, UI, engine and operating modes
fotokapan.ps1                  CPU spike trap (SYSTEM scheduled task)
launch.bat                     No-install Windows launcher
tests/verify.ps1               Parser + real read-only self-test entrypoint (CI)
tests/unit.ps1                 Pure-function unit tests (CI)
tests/*-stress.ps1             Engine (CI, small), spike-trap and GUI stress tests
tests/trap-install.ps1         Spike-trap install / permission test (elevated)
tests/run-all.ps1              Release gate: every test in order
CHANGELOG.md                   Release notes
docs/superpowers/plans/        Implementation plans
.github/workflows/verify.yml   Windows CI definition
docs/social-preview.png        Repository social-preview upload asset
README.md                      Behaviour, safety contract and usage
PLAN.md                        Original implementation plan and design notes
LICENSE                        MIT license text
```

Keeping the application in one script makes it easy to audit and copy. It also creates a real maintenance limit: the project is not yet split into independently testable modules.

## Current limits

- Windows and Windows Forms only
- Distributed as source; there is currently no signed installer or signed executable release
- Windows CI covers parser correctness, the real read-only self-test, an isolated Windows Update service-state contract, the unit tests and a small engine stress test; the spike-trap, install and GUI tests need elevation or a desktop and run locally (`tests\run-all.ps1`)
- Installing the spike trap requires administrator rights; it records from the moment it is installed
- The application is a single large PowerShell script, which keeps deployment simple but reduces modular testability
- Cleanup results vary by permissions, active applications and machine configuration
- Working-set trimming should not be interpreted as a permanent performance or memory-capacity increase

These limits are stated intentionally so the repository shows what exists now—not what a future release might become.

## Türkçe özet

OpenRelax; geçici dosyaları ve bilinen uygulama önbelleklerini temizleyen, uygun süreçlerin kullanılmayan çalışma setlerini daraltan ve Windows sistem tepsisinde çalışabilen açık kaynak bir bakım aracıdır.

İlk denemede hiçbir dosya silmeden kontrol etmek için:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\openrelax.ps1 -SelfTest
```

Aynı parser ve salt-okunur uygulama kontrolünü yerelde çalıştırmak için:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify.ps1
```

CI, `SelfTest` çalışırken ayar dosyası ile AutoClean günlüğünün oluşturulmadığını, silinmediğini veya değiştirilmediğini de doğrular.

Araç; Prefetch klasörünü, Windows tanılama günlüklerini, tarayıcı geçmişini, yer imlerini ve kullanıcı profil verilerini temizlemez. Windows Update temizliği varsayılan olarak kapalıdır ve yalnızca yönetici yetkisiyle çalışır. Geçici klasörlerde son 24 saatte değişen dosyalara ve junction'ların hedeflerine dokunulmaz.

**Fotokapan (CPU sıçrama kaydedici):** Ara ara %100'e çıkan CPU'nun sorumlusunu bulmak için `fotokapan.ps1` arayüzden bağımsız, SYSTEM görevi olarak çalışır. CPU 4 saniye %85 üstünde kalınca sıçramanın kendisini ölçer; sorumlu süreçleri, ebeveynlerini, komut satırlarını (gizli değerler maskelenir), sürücü (kesme/DPC) payını ve Defender taramalarını kaydeder. Uygulamadaki **Fotokapan** sekmesi kayıtları teşhise çevirir: **Özet** sayfası son 7 günün sorumlu kategorilerini (Defender taraması veya gerçek zamanlı tarama, sürücüler, oyunlar, geliştirici/AI araçları, tarayıcı, Windows, zamanlanmış görevler) payları ve ne yapılacağıyla, en sık sorumluları ve saate göre dağılımı gösterir; **Kayıtlar** sayfası her sıçramayı listeler ve **Raporu kaydet** ile teşhisi Markdown olarak `Belgeler\OpenRelax\` içine yazar. Yeni bir sıçrama kaydedilince tepsi simgesi haber verir (en fazla 15 dakikada bir; Ayarlar'dan kapatılabilir). Kurma, güncelleme ve kaldırma da bu sekmeden yapılır; "Güvenlik güncellemesi gerekli" durumu, 2.1 veya öncesiyle kurulmuş ve dosyaları kullanıcı tarafından değiştirilebilen bir kurulumu gösterir — **Kur / Güncelle** düzeltir.

Diğer 2.2 yenilikleri: isteğe bağlı geliştirici önbellekleri kategorisi (npm, pip, NuGet, Yarn), temizlik sırasında canlı dosya ve bayt sayacı, tek geçişte ve en fazla 90 saniyede biten disk analizi, ön plandaki ve o an çalışan uygulamalara dokunmayan RAM boşaltma.

Yönetici olarak açmak için `launch.bat` dosyasına sağ tıklayıp **Yönetici olarak çalıştır**'ı seçin ya da uygulamada **Ayarlar → Yönetici olarak yeniden başlat**'ı kullanın.

## License

Released under the [MIT License](LICENSE).
