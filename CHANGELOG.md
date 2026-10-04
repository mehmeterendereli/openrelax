# Changelog

## 2.1 LTS — 2026-10-04

Long-term-support release: stabilization of 2.0 plus the Fotokapan CPU spike trap. Verified with the stress tests in `tests/`.

### Fixed
- **Background tasks never ran.** Worker runspaces used `ThreadOptions = ReuseThread`, under which the pipeline never started: every scan, one-click clean, disk analysis and RAM boost hung until the watchdog gave up ("did not respond"). Workers now use the default thread option.
- **Junk scan of a large `%TEMP%` took minutes** (hundreds of thousands of folders left by dev/AI tools). Scans are time-budgeted (6 s per category) and show a lower bound (`≥ X GB`) when the budget is hit.
- **Cleaning buffered and sorted every entry before deleting anything.** Deletion is streamed; emptied folders are removed afterwards, junctions are never entered or removed.
- **The fixed 35 s watchdog cancelled legitimate long runs.** Workers post progress beats; a task is abandoned only after 60 s without progress, and the log names where it stalled.
- Recycle Bin size was read through Shell COM, which can block a worker; it is now read from `$Recycle.Bin` directly.

### Added
- **Fotokapan** (`fotokapan.ps1`): SYSTEM scheduled task that records the culprits of CPU spikes (burst-window per-process CPU, parents, command lines with secrets masked, new processes, interrupt/DPC share, Defender scan state or a 30 s Defender performance report). Writes a human-readable log, a JSONL record stream and a heartbeat.
- **Fotokapan tab** and tray entry: status, install/update/remove (UAC when needed), top culprits of the last 7 days, recent spikes, open log.
- Temp files changed within the last 24 hours are left alone, so running apps keep their working files.
- Disk analysis shows which folder it is on.
- `-SelfTest` prints a Fotokapan summary.
- Stress tests (`tests/`) and test hooks: `OPENRELAX_STRESS`, `OPENRELAX_SMOKETEST=<seconds>`, `OPENRELAX_TRAP_DIR`.
