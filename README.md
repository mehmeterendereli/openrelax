# OpenRelax PC Care

[![Windows verification](https://github.com/mehmeterendereli/openrelax/actions/workflows/verify.yml/badge.svg)](https://github.com/mehmeterendereli/openrelax/actions/workflows/verify.yml)

Portable, MIT-licensed Windows maintenance software written in PowerShell and
Windows Forms. Source version **2.1 Preview**; the current safety changes are
unreleased. No signed binary or published LTS support period is provided.

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
marked system targets and Fotokapan installation/removal. Review the selected
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
  cache, error reports, update cache and GPU installer leftovers are opt-in.
- Interactive maintenance requires confirmation, including warnings for
  permanent Recycle Bin deletion and diagnostic/cache consequences.
- RAM working-set trimming and DNS flushing are separate opt-in settings.
  Automatic RAM trimming is also disabled by default. Trimming can cause pages
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
  WER, Windows Update and installer categories and does not trim RAM/flush DNS.
  Exit codes: **0** complete, **1** failed, **2** partial/skipped. `-SelfTest`
  also exits nonzero when its scan cannot complete reliably. Combining
  `-SelfTest` and `-AutoClean` is refused before any maintenance or state write.
- Settings use validated types, atomic replacement and a state mutex.
  Global, access-controlled mutexes coordinate the same settings path across Windows
  sessions; one GUI instance prevents stale preference overwrites.
  Statistics preserve the most recent saved preferences.
- Scan sizes may be lower bounds. Disk analysis skips links and unreadable
  entries, has a 30-second budget and labels incomplete results. A stalled
  worker keeps the GUI busy until cancellation actually completes. Exit waits
  for active operations and service restoration instead of terminating their worker.

Settings and aggregate statistics: `%APPDATA%\OpenRelax\settings.json`.
Scheduled results: `%APPDATA%\OpenRelax\autoclean.log`.
Existing valid 2.1 settings retain their categories; new RAM/DNS options default
off. An invalid file is not silently replaced by AutoClean; review and save
preferences in the GUI to recover it.

## Fotokapan CPU spike recorder

Fotokapan runs independently as a SYSTEM scheduled task. Sustained CPU spikes
record process names, IDs, parent names, CPU shares and timestamps. **Command
arguments are omitted** (`cmd` is empty). CPU that cannot be assigned to a
process is labelled unassigned, rather than diagnosed as a faulty driver.
Defender scan/realtime classification is heuristic; extra Defender performance
tracing is off unless standalone `-DefenderTrace` is explicitly supplied.
Such traces may contain file paths; do not publish them without review.

```powershell
# From an elevated PowerShell, or use the GUI's Fotokapan tab
.\fotokapan.ps1 -Install
.\fotokapan.ps1 -Uninstall
```

Installed source is in `%ProgramData%\OpenRelax\Fotokapan\bin\`, including
its `lib/` dependency. Logs/heartbeat are in the separate `logs/` directory.
SYSTEM and Administrators have full control; the requesting GUI user has read
and execute access even when a different administrator completes elevation.
Standalone installation defaults to its current user; use `-ReaderSid <user-SID>`
when explicitly installing for another Windows account. Source files retain
administrative ownership and protected ACLs. Reparse and
hardlinked existing task files/logs are rejected before ACL changes. Uninstall
retains recordings. Old logs in the previous root are retained on upgrade. They can still contain
command arguments recorded by earlier versions; review them before sharing.
Failed upgrades leave the old task disabled, including across reboot.
Monthly logs older than 180 days are pruned by the recorder.

Logs still reveal process names and timestamps. Argument omission is not a
guarantee that all recorded diagnostic information is anonymous.

## Verification and contribution

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify.ps1
# Interactive desktop: capture all four real pages in TR and EN
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\visual-smoke.ps1
# Native focus, accessible controls and small-viewport reachability
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ui-smoke.ps1
```

CI parses every PowerShell source/test and all four worker scripts, runs
deterministic safety contracts and starts real isolated SelfTest/AutoClean
processes over small synthetic fixtures. It verifies refusal on corrupt
settings, unchanged state during SelfTest and actual deletion/count/statistics.
Test workspaces must be new and marked as owned; existing directories are
refused. `-TestMode` isolates targets/state and disables system integration.
Test hooks are ignored during normal operation.

GUI/resource stress and CPU-burst tests are optional local checks. Do not run
CPU-burst tests on a busy production machine. Real SYSTEM installation, Windows
Update integration, other Windows builds, high DPI and screen-reader behaviour
need additional release validation; synthetic checks do not establish those.
`tests\exit-smoke.ps1` also verifies that closing the real test GUI waits for
its owned worker instead of interrupting it.

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md),
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), [CHANGELOG.md](CHANGELOG.md) and the
ordered [end-to-end plan](PLAN.md).

## Source map

| Source | Responsibility |
| --- | --- |
| `openrelax.ps1` | WinForms UI, target descriptors, Windows integration and worker entrypoints |
| `lib/OpenRelax.Core.ps1` | Typed settings, atomic persistence, path guards, traversal and shared maintenance orchestration |
| `fotokapan.ps1` | Recorder and protected SYSTEM installation |
| `tests/verify.ps1`, `tests/safety-contracts.ps1` | Lightweight CI and real synthetic end-to-end checks |
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
Geliştirme sırası, kabul ölçütleri ve kalan sürüm doğrulamaları [PLAN.md](PLAN.md)
içindedir. Lisans [MIT](LICENSE).
