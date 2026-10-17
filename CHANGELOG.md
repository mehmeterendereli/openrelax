# Changelog

## 2.4.0 — 2026-10-18

Fotokapan now runs inside OpenRelax. Design: `docs/superpowers/specs/2026-10-17-openrelax-ai-growth-design.md`; plan: `docs/superpowers/plans/2026-10-17-openrelax-2.4.md`.

### Changed
- **Embedded Fotokapan.** The spike recorder runs in a background runspace while OpenRelax is open.
  - No administrator rights, no SYSTEM task, one switch on the Fotokapan tab (on by default).
  - Per-process CPU comes from one PDH read of all processes (~16 ms of CPU, Defender included), not from process handles (~300 ms, protected processes unreadable).
  - Records keep the 2.3 format and go to `%APPDATA%\OpenRelax\Fotokapan\`.
  - It records only while OpenRelax runs.
- **The old SYSTEM task.** It is detected. While it still records, the built-in recorder waits so spikes are not logged twice, and **Remove old task** uninstalls it (one administrator prompt). Its records under `ProgramData` are still read.
- **Command-line recording** (opt-in, masked) now applies immediately.
- **Open folder** opens the records folder; the embedded recorder writes no text log.

### Added
- **Measured driver load.** Records carry the interrupt and DPC share of the CPU. When that share is at least 10 % and larger than the top process, the culprit is reported as driver load backed by the measurement. Residual CPU without it stays "unattributed".
- **Path repair.** When start-with-Windows or weekly cleaning is on but the registered command starts a script that no longer exists (the folder was moved), OpenRelax registers itself again. A working registration of another copy is left alone.
- **One-line install:**

  ```powershell
  irm https://raw.githubusercontent.com/mehmeterendereli/openrelax/main/install.ps1 | iex
  ```

  - Downloads the latest release zip and checks its SHA256 before extracting.
  - Installs to `%LOCALAPPDATA%\Programs\OpenRelax` and adds a Start menu shortcut.
  - Never replaces a folder that is not an OpenRelax install.
- **Release assets.** `OpenRelax-<version>.zip` and `SHA256SUMS` are attached to every release by `.github/workflows/release.yml`. A Scoop manifest is in `bucket/`.
- **Tests:**
  - `tests/footprint.ps1` measures the app's own CPU, memory, handles and GDI in the tray (see README).
  - `tests/install-contract.ps1` covers the installer.
  - The sampler, tracker, record, driver-load and path-repair cases are in `tests/unit.ps1`.

### Fixed
- `tests/verify.ps1` no longer fails when a longer checkout path makes PowerShell wrap an error message across lines.

## 2.3.0 — 2026-10-17

This release joins the two lines of development. The 2.2 features were built
locally on top of 2.1.1 and never published (they are kept on branch
`archive/local-2.2.1`); `main` meanwhile received the hardening below. 2.3.0 is
`main` plus the 2.2 features, ported onto its safety model. Design and plan:
`docs/superpowers/specs/2026-10-17-openrelax-roadmap-design.md`,
`docs/superpowers/plans/2026-10-17-openrelax-2.3.md`.

### Added
- **Fotokapan diagnosis.** The tab's Summary page turns the last 7 days of spikes into findings per culprit category: Defender (on-demand scans vs. real-time scanning, with the folder it scanned most when a `-DefenderTrace` recording exists), games, developer/AI tools, browser, Windows, scheduled tasks and unattributed CPU. Each finding gives its share and what to do. The page also shows the culprit table and spikes per hour of day.
- **Records page and report.** Every spike with duration, peak, culprit and notes (Defender scan/real-time, scheduled task); **Save report** writes the diagnosis as Markdown to `Documents\OpenRelax\`.
- **Spike notifications.** A tray balloon when a new spike is recorded (at most one per 15 minutes; a click opens the records; switch on the Fotokapan tab).
- **Opt-in command-line recording.** Off by default. When switched on (Fotokapan tab, then Install / Update), the trap keeps masked command lines of the top processes and their parents, so a `python.exe` or `node.exe` spike shows which script ran. Masking is best effort and the setting says so.
- **Scheduled-task detection without storing arguments.** The recorder decides from the parent's command line whether Task Scheduler started a process, then discards it.
- **Developer caches** category (npm, pip, NuGet, Yarn): opt-in, files untouched for 24 h only, never cleaned by headless AutoClean.
- **Live cleaning progress**: files and bytes deleted so far on the button.
- `tests/unit.ps1` (part of `verify.ps1`) and `tests/run-all.ps1` (release gate).

### Changed
- **Engine walker.** Scan, clean and disk analysis share `Invoke-JunkWalk` (`lib/OpenRelax.Engine.ps1`): one directory walk that never enters reparse points, re-checks the folder chain and each file before deleting, and reports progress by elapsed time. Removing 30 000 files: about 6.6 s.
- **Disk analysis** walks the profile once (at most 90 s) with per-folder totals; files directly in the profile get their own row.
- **RAM trimming** leaves the foreground app, processes busy during a 500 ms CPU sample and processes under 30 MB alone, and logs how many it skipped.
- Fotokapan record reading, diagnosis and report logic moved to `lib/OpenRelax.Trap.ps1`; settings schema 3 (`devcache`, `trapNotify`, `trapRecordCommandLines`; older files load unchanged).

### Fixed
- **Upgrading a 2.2.x trap lost the visible history.** 2.2.x wrote its records to the trap root; 2.3 reads `logs\`. The GUI now also reads the old root until the trap is reinstalled, and installing moves the files into `logs\` (a month present in both keeps the older lines first).
- Defender recordings no longer lose their summary on report rows without a path or on archive members (from 2.2.1).

### Hardening carried over from `main` (previously "Unreleased")

- Add a current-user desktop shortcut installer and a multi-resolution icon matching the application branding.
- Split typed settings, atomic persistence, path guards and maintenance orchestration into `lib/OpenRelax.Core.ps1`.
- Fail closed on invalid AutoClean settings; default destructive/system categories off; require interactive confirmation and opt-in RAM/DNS.
- Restrict custom TEMP, reparse traversal and SYSTEM task ownership/ACLs; deploy protected source atomically and reject hardlinked task/log files.
- Omit command arguments and make extra Defender traces opt-in; label unassigned CPU honestly.
- Report partial/failure outcomes, signed temporary memory change and cancellation completion; preserve preferences/statistics and prevent multiple GUI snapshots.
- Wait for active work before GUI exit; preserve deletion counts after service restoration fails and avoid forced stops of dependent services.
- Improve keyboard order, accessible control names, constrained-screen scrolling, contrast, status layout, TR/EN localization, table headers and empty states.
- Verify native Tab/Shift+Tab routing and hidden-view skipping; record the actual window/thread DPI context and context-setter result.
- Refuse conflicting read-only/cleanup modes; preserve the requesting GUI user as the Fotokapan reader across different-account elevation.
- Add owned fixture isolation, strict safety contracts, real SelfTest/AutoClean checks and visual smoke; migrate stress tests.
- Add security/conduct policies, issue/PR forms, review ownership and a source release checklist. Remove an undefined current LTS claim.

## 2.1 LTS — 2026-10-04

Long-term-support release: stabilization of 2.0 plus the Fotokapan CPU spike trap. Verified with the stress tests in `tests/`.

### Fixed
- **Background tasks never ran.** Worker runspaces used `ThreadOptions = ReuseThread`, under which the pipeline never started: every scan, one-click clean, disk analysis and RAM boost hung until the watchdog gave up ("did not respond"). Workers now use the default thread option.
- **Junk scan of a large `%TEMP%` took minutes** (hundreds of thousands of folders left by dev/AI tools). Scans are time-budgeted (6 s per category) and show a lower bound (`≥ X GB`) when the budget is hit.
- **Cleaning buffered and sorted every entry before deleting anything.** Deletion is streamed; emptied folders are removed afterwards, junctions are never entered or removed.
- **The fixed 35 s watchdog cancelled legitimate long runs.** Workers post progress beats; a task is abandoned only after 60 s without progress, and the log names where it stalled.
- Recycle Bin size was read through Shell COM, which can block a worker; it is now read from `$Recycle.Bin` directly.
- Windows Update cleanup stops only the update services that were running, aborts if one cannot be stopped, and restores their prior state (#5).
- "Restart as Administrator" left a console window behind whose closing killed the app; the elevated instance now starts hidden like `launch.bat`.
- CI's self-test check reads the expected version from the script instead of a hard-coded `v2.0`.

### Added
- **Fotokapan** (`fotokapan.ps1`): SYSTEM scheduled task that records the culprits of CPU spikes (burst-window per-process CPU, parents, command lines with secrets masked, new processes, interrupt/DPC share, Defender scan state or a 30 s Defender performance report). Writes a human-readable log, a JSONL record stream and a heartbeat.
- **Fotokapan tab** and tray entry: status, install/update/remove (UAC when needed), top culprits of the last 7 days, recent spikes, open log.
- Temp files changed within the last 24 hours are left alone, so running apps keep their working files.
- Disk analysis shows which folder it is on.
- `-SelfTest` prints a Fotokapan summary.
- Stress tests (`tests/`) and test hooks: `OPENRELAX_STRESS`, `OPENRELAX_SMOKETEST=<seconds>`, `OPENRELAX_TRAP_DIR`.
