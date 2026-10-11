"""Choose Windows test suites without executing application code (stdlib only)."""
import json
import os
import subprocess
from pathlib import Path

ORDINARY_TESTS = {
    'tests/verify.ps1', 'tests/safety-contracts.ps1', 'tests/test-support.ps1',
    'tests/engine-stress.ps1', 'tests/gui-stress.ps1', 'tests/ui-smoke.ps1',
    'tests/exit-smoke.ps1', 'tests/visual-smoke.ps1', 'tests/fotokapan-stress.ps1',
}


def classify(paths):
    """Unknown paths run both suites; only explicit documentation is exempt."""
    ordinary = elevated = False
    for path in paths:
        if path == 'tests/elevated-fotokapan.ps1':
            elevated = True
        elif path in ORDINARY_TESTS:
            ordinary = True
            # Shared fixture helpers could change integration assumptions.
            if path == 'tests/test-support.ps1':
                elevated = True
        elif (('/' not in path and path.endswith('.md')) or
              (path.startswith('docs/') and Path(path).suffix.lower() in
               {'.md', '.png', '.jpg', '.jpeg', '.svg', '.webp'})):
            continue
        else:
            ordinary = elevated = True
    return {'standard': ordinary, 'elevated': elevated}


def git_paths(base, head, root):
    # --no-renames includes BOTH old and new paths, so moving code into docs
    # cannot evade the code test. NUL separation also preserves unusual names.
    result = subprocess.run(
        ['git', '-C', str(root), 'diff', '--name-only', '--no-renames', '-z', base, head, '--'],
        check=True, capture_output=True, timeout=20,
    )
    return [p.decode('utf-8', errors='strict') for p in result.stdout.split(b'\0') if p]


def plan(event_name, event, root):
    if event_name not in {'push', 'pull_request'}:
        return {'standard': True, 'elevated': True}, 'explicit/full validation'
    try:
        if event_name == 'pull_request':
            base = event['pull_request']['base']['sha']
            head = event['pull_request']['head']['sha']
            # Match GitHub PR change scope, not an unrelated movement on main.
            base = subprocess.run(
                ['git', '-C', str(root), 'merge-base', base, head],
                check=True, capture_output=True, text=True, timeout=20,
            ).stdout.strip()
        else:
            base, head = event['before'], event['after']
        if not base or set(base) == {'0'}:
            raise ValueError('No trustworthy diff base')
        paths = git_paths(base, head, root)
        return classify(paths), f'{len(paths)} changed path(s); unknown paths run all suites'
    except (KeyError, TypeError, ValueError, UnicodeError, OSError, subprocess.SubprocessError):
        # Never skip safety checks because history, an event or decoding failed.
        return {'standard': True, 'elevated': True}, 'diff unavailable; full validation required'


def main():
    root = Path(__file__).resolve().parents[2]
    event_path = os.environ.get('GITHUB_EVENT_PATH')
    try:
        event = json.loads(Path(event_path).read_text(encoding='utf-8')) if event_path else {}
    except (OSError, ValueError):
        event = {}
    flags, reason = plan(os.environ.get('GITHUB_EVENT_NAME', ''), event, root)
    lines = ''.join(f'{key}={str(value).lower()}\n' for key, value in flags.items())
    print(lines + reason)
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as handle:
            handle.write(lines)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as handle:
            handle.write('## Windows test selection\n' + lines.replace('\n', '  \n') +
                         '\n' + reason + '\nSkipped suites are not reported as tested.\n')


if __name__ == '__main__':
    main()
