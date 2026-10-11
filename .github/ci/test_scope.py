"""Offline regression coverage for test selection; never runs Windows operations."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('ci_scope', Path(__file__).with_name('scope.py'))
SCOPE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SCOPE)


class ScopeTests(unittest.TestCase):
    def test_documentation_only(self):
        self.assertEqual(SCOPE.classify(['README.md', 'docs/guide.md', 'docs/example.png']),
                         {'standard': False, 'elevated': False})

    def test_elevated_test_only(self):
        self.assertEqual(SCOPE.classify(['tests/elevated-fotokapan.ps1', 'README.md']),
                         {'standard': False, 'elevated': True})

    def test_regular_test_only(self):
        self.assertEqual(SCOPE.classify(['tests/visual-smoke.ps1']),
                         {'standard': True, 'elevated': False})

    def test_all_runtime_and_ci_surfaces(self):
        for path in ['openrelax.ps1', 'fotokapan.ps1', 'lib/OpenRelax.Core.ps1',
                     'launch.bat', 'install-shortcut.ps1', 'docs/openrelax.ico',
                     '.github/workflows/verify.yml', '.github/ci/scope.py',
                     '.github/ci/test_scope.py', 'tests/test-support.ps1',
                     'new-unknown-file', 'docs/new-script.ps1']:
            with self.subTest(path=path):
                self.assertEqual(SCOPE.classify([path]), {'standard': True, 'elevated': True})

    def test_manual_and_merge_queue_are_full(self):
        for event in ['workflow_dispatch', 'merge_group', 'unknown']:
            self.assertEqual(SCOPE.plan(event, {}, '.')[0], {'standard': True, 'elevated': True})

    def test_bad_events_do_not_skip(self):
        for event in [{}, {'before': '0' * 40, 'after': '1' * 40}, None]:
            self.assertEqual(SCOPE.plan('push', event, '.')[0],
                             {'standard': True, 'elevated': True})

    def test_diff_failure_does_not_skip(self):
        with patch.object(SCOPE, 'git_paths', side_effect=OSError('unavailable')):
            self.assertEqual(SCOPE.plan('push', {'before': 'a'*40, 'after': 'b'*40}, '.')[0],
                             {'standard': True, 'elevated': True})

    def test_actual_git_diff_and_code_rename(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            def git(*args):
                return subprocess.run(['git', '-C', tmp, *args], check=True,
                                      capture_output=True, text=True).stdout.strip()
            git('init', '-q')
            git('config', 'user.name', 'CI scope fixture')
            git('config', 'user.email', 'fixture@example.invalid')
            (root/'openrelax.ps1').write_text('fixture only', encoding='utf-8')
            git('add', '.'); git('commit', '-qm', 'base')
            base = git('rev-parse', 'HEAD')
            (root/'README.md').write_text('documentation', encoding='utf-8')
            git('add', '.'); git('commit', '-qm', 'docs')
            docs = git('rev-parse', 'HEAD')
            self.assertEqual(SCOPE.plan('push', {'before': base, 'after': docs}, root)[0],
                             {'standard': False, 'elevated': False})
            self.assertEqual(SCOPE.plan('pull_request', {'pull_request': {
                'base': {'sha': base}, 'head': {'sha': docs}}}, root)[0],
                             {'standard': False, 'elevated': False})
            (root/'docs').mkdir()
            git('mv', 'openrelax.ps1', 'docs/moved.md')
            git('commit', '-qm', 'move code')
            self.assertEqual(SCOPE.plan('push', {'before': docs, 'after': git('rev-parse', 'HEAD')}, root)[0],
                             {'standard': True, 'elevated': True})


if __name__ == '__main__':
    unittest.main()
