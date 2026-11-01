"""Static checks for the Settings window's component folder (no QML engine)."""
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT = Path(os.environ.get("HELLO_LOCK_TEST_ROOT", Path(__file__).resolve().parents[1]))
SETTINGS = ROOT / "settings"


class SettingsFolder(unittest.TestCase):
    def test_qmldir_lists_every_component(self):
        # With a qmldir present, Quickshell resolves the folder only through
        # it, so an unlisted file would fail to load as a type.
        entries = {}
        for line in (SETTINGS / "qmldir").read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            singleton = parts[0] == "singleton"
            name, version, file = parts[1:4] if singleton else parts[0:3]
            self.assertEqual(file, name + ".qml")
            self.assertEqual(version, "1.0")
            entries[name] = singleton
        files = {p.stem for p in SETTINGS.glob("*.qml")}
        self.assertEqual(set(entries), files)
        self.assertEqual([n for n, s in entries.items() if s], ["Theme"])

    def test_stages_cover_every_section(self):
        source = (ROOT / "Settings.qml").read_text(encoding="utf-8")
        sections = re.search(r"readonly property var sections: \[(.*?)\n  \]", source, re.S).group(1)
        ids = re.findall(r'\{ id: "([a-z]+)", label:', sections)
        self.assertEqual(ids, ["you", "logo", "unlock", "typing", "lock", "sound", "presets", "privacy"])
        files = re.search(r"stageFiles: \(\{(.*?)\}\)", source, re.S).group(1)
        for ident, name in re.findall(r'(\w+): "(Stage\w+\.qml)"', files):
            self.assertIn(ident, ids)
            self.assertTrue((SETTINGS / name).is_file(), name)

    def test_sound_peaks_are_current(self):
        result = subprocess.run([sys.executable, str(ROOT / "sounds/peaks.py"), "--check"],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_colours_come_from_the_theme(self):
        # Only Theme.qml may name a fixed colour (the splash's gold); stages
        # and controls take theirs from it.
        for path in list(SETTINGS.glob("*.qml")) + [ROOT / "Settings.qml"]:
            if path.name == "Theme.qml":
                continue
            text = path.read_text(encoding="utf-8")
            self.assertNotRegex(text, r'"#[0-9A-Fa-f]{3,8}"', path.name)


if __name__ == "__main__":
    unittest.main()
