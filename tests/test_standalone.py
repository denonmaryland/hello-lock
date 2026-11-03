"""Standalone entry-point and profile isolation checks; no desktop required."""
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "bin/hello-lock"


class Standalone(unittest.TestCase):
    def test_bundle_has_no_omarchy_or_authentication_entry(self):
        namespace = runpy.run_path(str(LAUNCHER))
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            plugin = namespace["stage_runtime"](ROOT, stage)
            self.assertFalse((plugin / "Service.qml").exists())
            self.assertFalse((stage / "Commons").exists())
            self.assertFalse((stage / "Ui").exists())
            for file in (ROOT / "LockView.qml", ROOT / "UnlockSplash.qml", ROOT / "Settings.qml",
                         ROOT / "settings/Theme.qml", ROOT / "standalone/shell.qml"):
                text = file.read_text()
                self.assertNotIn("import qs.", text)
                self.assertNotIn("import Quickshell.Hyprland", text)
                self.assertNotIn("WlSessionLock {", text)
                self.assertNotIn("PamContext {", text)

    def test_lock_without_wayland_refuses_and_creates_no_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "unused"
            result = subprocess.run([str(LAUNCHER), "lock", "--config-dir", str(config)], env=dict(os.environ, WAYLAND_DISPLAY=""), capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertTrue(result.stderr)
            self.assertFalse(config.exists())

    def test_launcher_passes_structured_paths_and_private_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / "qs"
            fake.write_text('#!/usr/bin/env python3\nimport os,sys,json\nfrom pathlib import Path\np=Path(sys.argv[-1])\nprint(json.dumps({"action":os.environ["HELLO_LOCK_ACTION"],"config":os.environ["HELLO_LOCK_CONFIG_DIR"],"entry":(p/"shell.qml").is_file(),"auth":(p/"plugin/Service.qml").exists()}))\n')
            fake.chmod(0o700)
            config = root / "profile with spaces; literal"
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"])
            result = subprocess.run([str(LAUNCHER), "preview", "--config-dir", str(config)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), {"action": "preview", "config": str(config), "entry": True, "auth": False})
            self.assertFalse(config.exists())

    def test_config_helper_writes_only_the_requested_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile = root / "standalone"
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / "plugin-config"), HELLO_LOCK_CONFIG_DIR=str(profile))
            result = subprocess.run([str(ROOT / "bin/hello-config"), "save", '{"name":"Standalone"}'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads((profile / "config.json").read_text())["name"], "Standalone")
            self.assertFalse((root / "plugin-config").exists())
            self.assertEqual((profile / "config.json").stat().st_mode & 0o777, 0o600)

    def test_sound_policy_uses_the_same_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sounds-off").touch()
            env = dict(os.environ, HELLO_LOCK_CONFIG_DIR=str(root))
            result = subprocess.run([str(ROOT / "bin/hello-sound"), "--policy"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(json.loads(result.stdout)["enabled"])


if __name__ == "__main__":
    unittest.main()
