import os
from pathlib import Path
import runpy
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
tool = runpy.run_path(str(ROOT / 'bin/hello-lock-install'))


class StandaloneInstallation(unittest.TestCase):
    def test_roundtrip_preserves_custom_files_and_preferences(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); target = root / 'share'; bindir = root / 'bin'
            preferences = root / 'preferences'; preferences.mkdir(); (preferences / 'config.json').write_text('private fixture')
            tool['install'](ROOT, target, bindir)
            self.assertTrue((target / 'standalone/lock.qml').exists())
            self.assertFalse((target / 'AGENTS.md').exists())
            self.assertTrue((bindir / 'hello-lock').stat().st_mode & 0o100)
            (target / 'custom.txt').write_text('keep')
            tool['remove'](target, bindir)
            self.assertEqual((target / 'custom.txt').read_text(), 'keep')
            self.assertEqual((preferences / 'config.json').read_text(), 'private fixture')
            self.assertFalse((bindir / 'hello-lock').exists())

    def test_modified_managed_file_is_not_overwritten_or_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); target = root / 'share'; bindir = root / 'bin'
            tool['install'](ROOT, target, bindir)
            modified = target / 'standalone/lock.qml'; modified.write_text('custom code fixture')
            with self.assertRaises(ValueError): tool['install'](ROOT, target, bindir)
            tool['remove'](target, bindir)
            self.assertEqual(modified.read_text(), 'custom code fixture')

    def test_refuses_foreign_command_and_symlink_redirects(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); target = root / 'share'; bindir = root / 'bin'; bindir.mkdir()
            (bindir / 'hello-lock').write_text('unrelated fixture')
            with self.assertRaises(ValueError): tool['install'](ROOT, target, bindir)
            self.assertFalse(target.exists())
            (bindir / 'hello-lock').unlink()
            tool['install'](ROOT, target, bindir)
            import shutil
            outside = root / 'outside'; outside.mkdir(); (outside / 'keep').write_text('keep')
            shutil.rmtree(target / 'platform'); (target / 'platform').symlink_to(outside, target_is_directory=True)
            with self.assertRaises(ValueError): tool['remove'](target, bindir)
            self.assertEqual((outside / 'keep').read_text(), 'keep')
