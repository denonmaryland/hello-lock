"""Locker boundary tests. No real display, PAM authentication or host policy writes."""
import importlib.util
import json
import os
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('locker_runtime', ROOT / 'standalone/runtime.py')
runtime = importlib.util.module_from_spec(spec); spec.loader.exec_module(runtime)
pam = runpy.run_path(str(ROOT / 'bin/hello-lock-pam'))


class LockerBoundary(unittest.TestCase):
    def test_runtime_allows_execute_only_acl_without_changing_parent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); root.chmod(0o710)
            with patch.dict(os.environ, XDG_RUNTIME_DIR=directory, WAYLAND_DISPLAY='wayland-test'):
                result = runtime.runtime_dir()
                self.assertEqual(result.parent, root)
                self.assertEqual(result.stat().st_mode & 0o777, 0o700)
            self.assertEqual(root.stat().st_mode & 0o777, 0o710)

    def test_runtime_rejects_shared_directory_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); root.chmod(0o750)
            with patch.dict(os.environ, XDG_RUNTIME_DIR=directory, WAYLAND_DISPLAY='wayland-test'):
                with self.assertRaises(ValueError): runtime.runtime_dir()
            root.chmod(0o700); link = root / 'link'; link.symlink_to(root, target_is_directory=True)
            with patch.dict(os.environ, XDG_RUNTIME_DIR=str(link), WAYLAND_DISPLAY='wayland-test'):
                with self.assertRaises(ValueError): runtime.runtime_dir()

    def test_state_writer_is_private_and_read_rejects_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'state.json'
            runtime.write_json(path, {'phase': 'fixture'})
            self.assertEqual(runtime.read_json(path), {'phase': 'fixture'})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            link = path.with_name('link'); link.symlink_to(path)
            with self.assertRaises(ValueError): runtime.read_json(link)

    def test_installer_refuses_nonroot_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(os, 'geteuid', return_value=1000):
                with self.assertRaises(PermissionError): pam['install'](Path(directory))
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_policy_install_and_remove_preserve_unrelated_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory); (path / 'login').write_text('original login fixture')
            namespace = pam['install'].__globals__
            with patch.object(os, 'geteuid', return_value=0), patch.dict(namespace, trusted=lambda *args: None):
                pam['install'](path)
                self.assertEqual((path / 'hello-lock').read_bytes(), pam['POLICY'])
                self.assertEqual((path / 'hello-lock').stat().st_mode & 0o777, 0o644)
                (path / 'hello-lock').write_text('custom admin fixture')
                with self.assertRaises(ValueError): pam['remove'](path)
                (path / 'hello-lock').write_bytes(pam['POLICY'])
                pam['remove'](path)
            self.assertEqual((path / 'login').read_text(), 'original login fixture')
            self.assertFalse(list(path.glob('.hello-lock-*')))

    def test_core_has_no_unlock_or_password_submission_ipc(self):
        source = (ROOT / 'standalone/lock.qml').read_text()
        self.assertNotIn('IpcHandler', source)
        self.assertEqual(source.count('session.locked = false'), 1)
        self.assertIn('interval: 360', source)

    def test_background_never_reports_readiness_for_unconfirmed_or_failed_state(self):
        child = Mock()
        child.poll.return_value = None
        with patch.object(runtime.runpy, 'run_path', return_value={'check': lambda: None}), \
             patch.object(runtime.subprocess, 'Popen', return_value=child), \
             patch.object(runtime, 'status', side_effect=ValueError('invalid private state')):
            with self.assertRaises(ValueError): runtime.background(ROOT, Path('/unused'))
        child.terminate.assert_called_once()
        child.wait.assert_called_once()

    def test_background_waits_through_reported_loss_until_owner_reconfirms(self):
        child = Mock(); child.poll.return_value = 2
        states = [{'active':True,'secure':True,'released':False,'phase':'lock-lost'},
                  {'active':True,'secure':True,'released':False,'phase':'locked'}]
        with patch.object(runtime.runpy,'run_path',return_value={'check':lambda:None}), \
             patch.object(runtime.subprocess,'Popen',return_value=child), \
             patch.object(runtime,'status',side_effect=states) as observed, patch.object(runtime.time,'sleep'):
            self.assertEqual(runtime.background(ROOT,Path('/unused')),0)
            self.assertEqual(observed.call_count,2)
        child.terminate.assert_not_called()

    def test_background_leaves_confirmed_locker_running(self):
        child = Mock()
        with patch.object(runtime.runpy, 'run_path', return_value={'check': lambda: None}), \
             patch.object(runtime.subprocess, 'Popen', return_value=child), \
             patch.object(runtime, 'status', return_value={'active': True, 'secure': True, 'released': False, 'phase': 'locked'}):
            self.assertEqual(runtime.background(ROOT, Path('/unused')), 0)
        child.terminate.assert_not_called()


if __name__ == '__main__': unittest.main()
