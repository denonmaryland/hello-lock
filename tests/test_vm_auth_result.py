"""A driver exception after passing previews must never become an authentication pass."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('guest_runner', Path(__file__).parent / 'vm/guest-test.py')
guest = importlib.util.module_from_spec(spec); spec.loader.exec_module(guest)


class GuestAuthenticationResult(unittest.TestCase):
    def test_suspend_fixture_refuses_owner_machine_before_writes(self):
        spec = importlib.util.spec_from_file_location('guest_suspend', Path(__file__).parent / 'vm/guest-suspend.py')
        fixture = importlib.util.module_from_spec(spec); spec.loader.exec_module(fixture)
        with patch.object(fixture.os, 'geteuid', return_value=0), \
             patch.object(fixture.socket, 'gethostname', return_value='owner-desktop'), \
             patch.object(Path, 'write_text') as write, patch.object(Path, 'read_text') as read, \
             patch.object(fixture.subprocess, 'run') as run:
            with self.assertRaises(RuntimeError): fixture.main()
        write.assert_not_called(); read.assert_not_called(); run.assert_not_called()

    def test_authentication_driver_timeout_overrides_visual_success(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            original_read, original_exists = Path.read_text, Path.exists
            def read(path, *args, **kwargs):
                if str(path) == '/etc/hello-lock-vm-profile': return 'arch'
                return original_read(path, *args, **kwargs)
            def exists(path):
                return False if str(path) == '/usr/share/omarchy' else original_exists(path)
            authentication = Mock(side_effect=subprocess.TimeoutExpired('guest-only-fixture', 1))
            modules = [SimpleNamespace(require_guest=lambda: None), SimpleNamespace(run_tests=authentication)]
            loader = SimpleNamespace(exec_module=lambda module: None)
            response = SimpleNamespace(returncode=0, stdout='[{"name":"virtual"}]', stderr='')
            with patch.object(guest.importlib.util, 'spec_from_file_location', return_value=SimpleNamespace(loader=loader)), \
                 patch.object(guest.importlib.util, 'module_from_spec', side_effect=modules), \
                 patch.object(Path, 'home', return_value=home), patch.object(Path, 'read_text', read), \
                 patch.object(Path, 'exists', exists), \
                 patch.object(guest.os, 'umask'), \
                 patch.object(guest.platform, 'freedesktop_os_release', return_value={'ID': 'arch'}), \
                 patch.object(guest.subprocess, 'run', return_value=response):
                guest.main(authentication=True)
            result = json.loads((home / 'vm-result.json').read_text())
            self.assertEqual(result['visual_suite_exit'], 0)
            self.assertEqual(result['status'], 'failed')
            self.assertFalse(result['authentication_tested'])
            self.assertEqual(result['error_type'], 'TimeoutExpired')
            authentication.assert_called_once()
