# Contributing to OpenRelax

Use Windows PowerShell 5.1 and Git. GUI checks require an interactive Windows
desktop. No package installation, model download or external SDK is needed.
Keep contributions focused on a concrete behaviour and acceptance criterion.

## Required checks

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify.ps1
```

This parses all source/tests and four worker texts, runs strict synthetic
contracts and the real isolated SelfTest/AutoClean paths. The test creates a
new owned workspace and refuses existing `-Work` directories. Use
`-Work C:\your-test-root\new-directory -KeepArtifacts` to retain evidence.
Do not point tests at a personal profile or production data.

For visible changes run `tests\visual-smoke.ps1` and inspect all eight TR/EN
images. `tests\gui-stress.ps1 -Cycles 30 -Launches 2` checks real handlers,
background scans and bounded resource growth. These are local desktop checks.
Run `tests\exit-smoke.ps1` for lifecycle changes; the real GUI must defer exit
until its owned worker finishes.
Run `tests\ui-smoke.ps1` for native Tab/Shift+Tab dialog routing, hidden-view
skipping, accessible control semantics, preference persistence and reachability
in a constrained 540×450 viewport. The report measures the effective window/
thread DPI context, window DPI and process-context setter result. A host that
already selected its context may reject the setter; its measured mode is retained.
This verifies control APIs; physical keyboard, Narrator speech and monitor DPI
transitions require separate interactive acceptance. The workflow also runs
these bounded fixture checks; it never installs SYSTEM tasks or alters services.

For traversal changes, `tests\engine-stress.ps1 -Dirs 8 -FilesPerDir 3` is a
small worker fixture; the default 30,000-file load is optional. The CPU-burst
`tests\fotokapan-stress.ps1` is optional and consumes substantial CPU/time.
It identifies burners by PID and asserts argument omission. It must not alter
an installed task; choose an isolated test machine if other recorders are active.
Children route TEMP/TMP/module caches to the owned workspace and are stopped
in `finally`. Use `-KeepArtifacts` to retain its summary and private recordings;
review process metadata before sharing. Parallel burners can legitimately rank
as unassigned CPU when the unknown aggregate exceeds any individual process.

Never report unrun tests as passing. State the Windows build, exact command,
result and any remaining elevated/native validation in the PR.

## Safety contracts

- SelfTest leaves settings, maintenance logs and target files unchanged.
- Corrupt/missing settings stop AutoClean; it skips interactive-only categories.
- Interactive deletion requires confirmation. RAM and DNS are opt-in.
- Protected roots, relative paths, reparse ancestors and out-of-bound targets
  are refused. Locked/recent temp files and staging folders survive cleanup.
- Windows Update deletion requires successful service stops and restoration of
  prior states. Failures remain observable.
- Typed settings are replaced atomically. State updates cannot lose statistics
  or reset the latest saved preferences. One GUI per settings path is allowed.
- SYSTEM source files/parents have protected administrative ownership and ACLs;
  the reader cannot modify them. Reparse/hardlinked files fail before ACL writes.
- No process arguments are retained. Keep diagnostic traces explicitly opt-in.
- Scans/cleanup/analysis stay outside the GUI thread; cancellation must finish
  before another maintenance task starts.
- Test mode routes state/targets into owned fixtures and blocks system mutations.

## Source and encoding

Keep source distribution complete: entrypoints plus `lib/`. Pure core helpers
must have no startup side effects. Use UTF-8 with BOM for PowerShell files
containing non-ASCII text, so Windows PowerShell 5.1 decodes Turkish correctly.
Do not commit generated binaries, traces, logs, local settings or test artifacts.
The MIT license remains the contribution license.

## Issues and review

Use the issue forms for version/build, mode, reproduction and expected/actual
behaviour. Review excerpts and screenshots before posting. Logs may disclose
process names/timestamps and historical logs may include command arguments.
Follow [SECURITY.md](SECURITY.md) for vulnerabilities and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for participation.

`.github/CODEOWNERS` routes reviews to the maintainer. It does not itself require
approval; required reviews and branch rules are separate repository settings.
See [GitHub's code-owner documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners).

## Source release checklist

Before a maintainer tags/releases a version:

1. Pass CI on the reviewed final commit and record exact local checks.
2. Validate the supported Windows builds and interactive TR/EN, keyboard, high-DPI
   and screen-reader flows. Record unsupported/unvalidated configurations.
3. On a disposable Windows machine validate Fotokapan install, upgrade and
   uninstall, SYSTEM task action and effective owner/ACL of code/parents/logs.
   Exercise real Windows Update restoration only there.
4. Resolve security reports and decide whether GitHub private vulnerability
   reporting/required reviews are enabled; publish an actual contact if needed.
5. Update version/changelog and support policy; inspect the source archive for
   the `lib/` dependency and absence of private data. Record its SHA-256.
6. Create the tag/release only with maintainer authorization. If binaries are
   introduced later, add reproducible build/provenance and signing validation.

These repository-setting and release actions are not performed by local tests.
