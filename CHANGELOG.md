# Changelog

## 2.2.1 — 2026-10-04

### Fixed
- **Fotokapan lost its Defender recording on the first live spike.** Defender reports can hold rows with an empty path, and the folder summary passed those to `Split-Path`, which throws. That one exception discarded the whole 30-second recording, and the 6-hour rate limit then blocked a retry. The summary now skips rows without a path and folds archive members (`C:\a.zip->inner\file`) into the archive's folder. If the summary still fails, the text report is logged anyway.

Feature release on top of 2.1.1 LTS; the long-term-support line stays on branch `lts/2.1`. Plan: `docs/superpowers/plans/2026-10-04-openrelax-2.2.md`.

### Security
- Everything in 2.1.1 LTS: only SYSTEM and Administrators can change the installed Fotokapan; the tab flags older user-writable installs as "Security update required".

### Added
- **Fotokapan diagnosis.** The tab's new summary page turns the last 7 days of spikes into findings per culprit category — Defender (on-demand scans vs. real-time scanning, with the folder it scanned most), drivers (interrupts/DPC), games, developer/AI tools, browser, Windows, scheduled tasks — each with its share and what to do; plus the culprit table and spikes per hour of day.
- **Records page and report.** Every spike with duration, peak, culprit and Defender/scheduled-task notes; **Save report** writes the diagnosis as Markdown to `Documents\OpenRelax\`.
- **Spike notifications.** A tray balloon when a new spike is recorded (at most one per 15 minutes; click opens the tab; switch in Settings).
- **Recorder 2.2.** Records the parent's (masked) command line, so Task Scheduler starts are recognisable, and Defender's top scanning processes and most-scanned folders.
- **Developer caches** category (npm, pip, NuGet, Yarn), opt-in, under the 24 h rule.
- **Live cleaning progress**: files and bytes deleted so far on the button.
- Tests: `tests/unit.ps1` (pure functions), `tests/trap-install.ps1` (install permissions), `tests/run-all.ps1` (release gate). CI now also runs the unit tests and a small engine stress test.

### Changed
- **Engine walker.** Scan, clean and disk analysis share one walker that never enters junctions, skips unreadable folders, and checks its time budget and progress beat by elapsed time instead of file count. Removing 30 000 files: 39.9 s → 5.2 s.
- **Disk analysis** walks the profile once with per-folder totals and stops at 90 s (sizes then marked as lower bounds); root files get their own row.
- **RAM trim** leaves the foreground app, processes busy during a 500 ms CPU sample and processes under 30 MB alone, and logs how many it skipped.

## 2.1.1 LTS — 2026-10-04

### Security
- **The installed Fotokapan script was writable by the installing user.** SYSTEM runs it at every boot, so any non-elevated process could have swapped it to gain SYSTEM rights. Only SYSTEM and Administrators can now change the trap; the user keeps read access to the logs. Reinstalling (Fotokapan tab → Install / Update) fixes existing installs, which the tab now flags as "Security update required".

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
