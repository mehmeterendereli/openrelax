# CI selection and cost controls

`Windows verification` is the single automatic workflow. Its Ubuntu preflight
checks change-selection regressions and parses PowerShell files/embedded workers
without running the application. PowerShell 7 syntax checks do not replace the
Windows PowerShell 5.1 runtime checks.

- Documentation-only changes allocate no Windows runner.
- Changes only to `tests/elevated-fotokapan.ps1` run the integration suite, not the
  unrelated GUI/cleanup suite. Shared runtime/CI or unknown paths run both.
- Failed diff/history retrieval selects both suites; code-to-documentation renames
  retain the old code path and cannot evade testing.
- Draft PRs run preflight only; `ready_for_review` starts applicable Windows tests.
- The short elevated suite runs before the long GUI/cleanup suite when requested.
  Its failure blocks ordinary Windows acceptance instead of wasting a full run.
  A deliberately unrequested suite may be skipped, never represented as tested.
- Fork PRs do not receive the elevated integration job. No secrets or write token
  are added. The two existing Windows job names and all test assertions remain.
- Superseded runs are cancelled within the original concurrency group; cancelled
  runs do not spend time uploading artifacts. Limits: 3/8/4 minutes for
  preflight/ordinary/elevated jobs. Manual dispatch and merge queues run all suites.
- Main validation is retained: a merge is a separately reviewed source tree.

Before pushing, batch related changes and run `python3 .github/ci/test_scope.py`.
With PowerShell installed, run `.github/ci/parse-powershell.ps1`. Do not rerun an
unchanged deterministic failure, hide it with `continue-on-error`, weaken a test,
or remove branch protections to obtain green CI. This directory changes execution
scope, not release criteria or the product's support claims.
