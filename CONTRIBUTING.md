# Contributing to OpenRelax

OpenRelax is a Windows maintenance utility. Small changes can affect files,
services, scheduled tasks or diagnostic logs, so contributions should keep the
safety boundary explicit and easy to review.

## Development environment

- A Windows host; an interactive desktop is needed for GUI stress tests
- Windows PowerShell 5.1 (`powershell.exe`), which is also what the launcher and
  GitHub Actions use
- Git

Clone the repository and run the read-only verification path before editing:

```powershell
git clone https://github.com/mehmeterendereli/openrelax.git
cd openrelax
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify.ps1
```

`tests\verify.ps1` parses the complete application, exercises the isolated
Windows Update service-state contract, runs the real `-SelfTest` entrypoint and
checks that settings and the AutoClean log remain unchanged. It must pass for
every pull request.

## Choose the smallest relevant test

Run the common verification command above, then add the test that matches the
behaviour you changed:

| Changed area | Additional command | What it exercises |
|---|---|---|
| Cleanup engine or path guards | `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\engine-stress.ps1` | Synthetic files, junctions, locked/recent files, long paths and worker progress |
| Fotokapan recorder or reader | `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\fotokapan-stress.ps1` | Private synthetic CPU bursts, JSONL records, damaged lines and monitor overhead |
| WinForms UI or runspaces | `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\gui-stress.ps1` | Interactive handlers, repeated launches and resource growth |
| Documentation only | Common verification command | Referenced commands and paths must also be checked manually |

The stress tests can use substantial CPU, disk space and time. They create
their own temporary data and must not be redirected to a real user or system
folder. The GUI test needs an interactive Windows desktop. Before the
Fotokapan stress test, pause an installed `OpenRelax Fotokapan` scheduled task
so synthetic bursts do not enter real statistics.

If a test cannot be run, state exactly which one and why in the pull request.
Do not report an unrun test as passing.

## Safety rules for changes

Changes must preserve these contracts unless a pull request explicitly
replaces them with an equally testable boundary:

- `-SelfTest` stays read-only and does not create or change saved settings or
  `autoclean.log`.
- Junctions are not followed or removed.
- Locked files and temporary files changed within the last 24 hours are kept.
- Browser history, bookmarks, profile data, Prefetch and Windows diagnostic
  folders are not cleanup targets.
- Administrator-only work is skipped without elevation.
- Windows Update cleanup stops only services that were running, aborts if a
  required stop fails and restores the original service states.
- Cleanup, scans and disk analysis stay off the WinForms UI thread.
- Secrets in recorded command lines remain masked.

Do not test destructive cleanup against a personal profile or production
machine for a pull request. Use the synthetic fixtures in `tests/`.

## Source and encoding

Keep deployment source-first: do not commit generated executables, installers,
logs, stress-test artifacts or local settings. PowerShell files containing
non-ASCII text must remain UTF-8 with BOM so Windows PowerShell 5.1 reads the
Turkish strings correctly.

## Bug reports

Include:

1. Windows edition/build and OpenRelax version or commit.
2. The mode used (`GUI`, `-SelfTest`, `-AutoClean` or Fotokapan).
3. Minimal reproduction steps, expected result and actual result.
4. The smallest relevant log excerpt and the exact test command run.

Review logs before attaching them. Fotokapan records process names, parent
processes and masked command lines; file paths or arguments can still reveal
personal information. Never publish an entire
`C:\ProgramData\OpenRelax\Fotokapan\` directory without inspecting and
redacting it first.

## Pull requests

Keep each pull request focused on one behaviour. In the description, explain:

- the user-visible problem;
- the safety boundary that could be affected;
- the commands actually run and their results;
- any validation that still requires a real Windows configuration.

Screenshots are useful for visible UI changes, but they do not replace the
parser, self-test or relevant stress test.
