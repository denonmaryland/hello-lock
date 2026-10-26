"""Regression tests using disposable homes; never use the live configuration."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import xml.etree.ElementTree as ET

ROOT = Path(os.environ.get("HELLO_LOCK_TEST_ROOT", Path(__file__).resolve().parents[1]))


def load_helper(name):
    loader = importlib.machinery.SourceFileLoader(name, str(ROOT / "bin" / name))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class Helpers(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / "config"),
                        XDG_STATE_HOME=str(self.home / "state"))
        self.cfg = self.home / "config/hello-lock/config.json"
        self.cfg.parent.mkdir(parents=True)

    def run_helper(self, name, *args):
        return subprocess.run([str(ROOT / "bin" / name), *args], env=self.env, cwd=self.home,
                              capture_output=True, text=True, timeout=5)

    def preset(self, action, value=""):
        result = self.run_helper("hello-config", "preset", action, value)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_presets_preserve_assets_and_unrelated_preferences(self):
        logo = self.home / "company.svg"
        logo.write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
        self.cfg.write_text(json.dumps({"brand": "Company", "logo": str(logo),
            "symbolParts": [str(logo), str(logo)], "name": "Person", "weather": False}))
        first = self.preset("create", "Company / Primary")
        ident = first["selectedPreset"]
        logo.unlink()
        self.assertTrue((self.cfg.parent / first["brandingPresets"][0]["branding"]["logo"]).is_file())
        self.run_helper("hello-config", "save", '{"brand":"Other","logo":null,"symbolParts":null,"symbol":"@radar"}')
        second = self.preset("create", "Company / Alternate")
        other = second["selectedPreset"]
        restored = self.preset("apply", ident)
        self.assertEqual(restored["brand"], "Company")
        self.assertEqual(len(restored["symbolParts"]), 2)
        self.assertNotIn("symbol", restored)
        self.assertEqual(restored["name"], "Person")
        self.assertFalse(restored["weather"])
        self.assertEqual(self.preset("next")["selectedPreset"], other)
        self.assertNotIn("symbolParts", json.loads(self.cfg.read_text()))
        self.assertEqual(self.preset("mode", "shuffle")["presetMode"], "shuffle")
        updated = self.preset("update", "Renamed")
        self.assertEqual(updated["brandingPresets"][1]["name"], "Renamed")
        deleted = self.preset("delete", other)
        self.assertEqual(len(deleted["brandingPresets"]), 1)
        self.assertNotIn("selectedPreset", deleted)
        self.assertEqual(deleted["symbol"], "@radar")

    def test_wordmark_preset_restores_text_and_style(self):
        self.run_helper("hello-config", "save", '{"wordmarkText":"ACME","wordmarkStyle":"outline","tintLogo":false}')
        first = self.preset("create", "Wordmark")
        self.run_helper("hello-config", "save", '{"wordmarkText":null,"logo":null,"wordmarkStyle":null,"tintLogo":true}')
        restored = self.preset("apply", first["selectedPreset"])
        self.assertEqual(restored["wordmarkText"], "ACME")
        self.assertEqual(restored["wordmarkStyle"], "outline")
        self.assertFalse(restored["tintLogo"])
        self.assertTrue((self.cfg.parent / restored["logo"]).is_file())

    def test_missing_preset_asset_does_not_change_config(self):
        self.cfg.write_text('{"logo":"missing.svg","brand":"Keep"}')
        before = self.cfg.read_bytes()
        self.assertNotEqual(self.run_helper("hello-config", "preset", "create", "Missing").returncode, 0)
        self.assertEqual(self.cfg.read_bytes(), before)

    def test_invalid_preset_schema_is_rejected_without_writes(self):
        for bad in ([None], [{"id":"a", "name":7, "branding":{}}],
                    [{"id":"a", "name":"A", "branding":{"symbolParts":[False]}}],
                    [{"id":"a", "name":"A", "branding":{}}] * 2):
            self.cfg.write_text('{"name":"Keep"}')
            before = self.cfg.read_bytes()
            result = self.run_helper("hello-config", "save", json.dumps({"brandingPresets":bad}))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.cfg.read_bytes(), before)
            self.cfg.write_text(json.dumps({"name":"Keep", "brandingPresets":bad}))
            before = self.cfg.read_bytes()
            result = self.run_helper("hello-config", "preset", "create", "New")
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("Traceback", result.stderr)
            self.assertEqual(self.cfg.read_bytes(), before)

    def test_bad_preset_operations_preserve_config(self):
        self.cfg.write_text('{"brand":"Before"}')
        self.preset("create", "One")
        before = self.cfg.read_bytes()
        for action, value in [("create", "one"), ("create", " "), ("apply", "missing"),
                              ("delete", "missing"), ("mode", "invalid")]:
            result = self.run_helper("hello-config", "preset", action, value)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.cfg.read_bytes(), before)
        self.cfg.write_text('{broken')
        self.assertNotEqual(self.run_helper("hello-config", "preset", "create", "Two").returncode, 0)
        self.assertEqual(self.cfg.read_text(), '{broken')

    def test_save_merges_preserves_unknown_keys_and_backs_up(self):
        before = '{"weather":false,"custom":{"x":1},"name":"Before"}\n'
        self.cfg.write_text(before)
        result = self.run_helper("hello-config", "save", '{"name":"After","birthday":null}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.cfg.read_text()), {"weather": False, "custom": {"x": 1}, "name": "After"})
        self.assertEqual(next(self.cfg.parent.glob("config.json.bak.*")).read_text(), before)
        self.assertEqual(self.cfg.stat().st_mode & 0o777, 0o600)

    def test_handoff_setting_is_saved(self):
        self.cfg.write_text('{"name":"A"}\n')
        self.assertEqual(self.run_helper("hello-config", "save", '{"handoff":"glitch"}').returncode, 0)
        self.assertEqual(json.loads(self.cfg.read_text()), {"name": "A", "handoff": "glitch"})
        self.assertEqual(self.run_helper("hello-config", "save", '{"handoff":null}').returncode, 0)
        self.assertEqual(json.loads(self.cfg.read_text()), {"name": "A"})

    def test_settings_saves_without_backup_and_prunes_old_backups(self):
        self.cfg.write_text('{"name":"A"}\n')
        for i in range(13):
            self.assertEqual(self.run_helper("hello-config", "save", '{"name":"N%d"}' % i).returncode, 0)
        backups = sorted(self.cfg.parent.glob("config.json.bak.*"))
        self.assertEqual(len(backups), 10)
        result = self.run_helper("hello-config", "save", "--no-backup", '{"weather":false}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(self.cfg.parent.glob("config.json.bak.*")), backups)
        self.assertEqual(json.loads(self.cfg.read_text()), {"name": "N12", "weather": False})

    def test_sound_settings_round_trip_and_validate(self):
        conf = self.cfg.parent / "sound.conf"
        get = lambda: json.loads(self.run_helper("hello-config", "sound-get").stdout)
        self.assertEqual(get(), {"volume": 0.5, "quietStart": 23, "quietEnd": 7})
        self.assertEqual(self.run_helper("hello-config", "sound-save", '{"volume":0.8,"quietStart":22}').returncode, 0)
        self.assertEqual(get(), {"volume": 0.8, "quietStart": 22, "quietEnd": 7})
        self.assertIn("QUIET_START=22", conf.read_text())
        self.assertEqual(self.run_helper("hello-config", "sound-save", '{"quietStart":null}').returncode, 0)
        self.assertEqual(get(), {"volume": 0.8, "quietStart": None, "quietEnd": None})
        before = conf.read_text()
        for bad in ('{"quietStart":24}', '{"volume":"loud"}', '{"quietEnd":true}', '[1]'):
            self.assertNotEqual(self.run_helper("hello-config", "sound-save", bad).returncode, 0, bad)
        self.assertEqual(conf.read_text(), before)
        # hello-sound reads the same file: an empty quiet hour turns quiet hours off.
        self.assertRegex(before, r"QUIET_START=\nQUIET_END=\n")

    def test_malformed_config_is_never_replaced(self):
        for before in ('{"weather":false,', '[1,2]', '"settings"'):
            with self.subTest(before=before):
                self.cfg.write_text(before)
                result = self.run_helper("hello-config", "save", '{"name":"After"}')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.cfg.read_text(), before)

    def test_wordmark_preview_writes_no_files(self):
        saved = self.cfg.parent / "wordmark.svg"
        saved.write_text("original")
        before = set(self.cfg.parent.iterdir())
        result = self.run_helper("hello-wordmark", "ADA 42", "-", "--style", "blocks")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(ET.fromstring(result.stdout).tag, "{http://www.w3.org/2000/svg}svg")
        self.assertEqual(saved.read_text(), "original")
        self.assertEqual(set(self.cfg.parent.iterdir()), before)

    def test_save_wordmark_keeps_previous_asset(self):
        saved = self.cfg.parent / "wordmark.svg"
        saved.write_text("original")
        self.cfg.write_text('{"logo":"wordmark.svg","weather":false}')
        result = self.run_helper("hello-config", "save", '{"wordmarkText":"ADA","wordmarkStyle":"led","logo":"wordmark.svg"}')
        self.assertEqual(result.returncode, 0, result.stderr)
        cfg = json.loads(self.cfg.read_text())
        self.assertNotEqual(cfg["logo"], "wordmark.svg")
        self.assertEqual(saved.read_text(), "original")
        self.assertFalse(cfg["weather"])
        ET.parse(self.cfg.parent / cfg["logo"])

    def test_invalid_wordmark_does_not_change_config(self):
        before = '{"logo":"wordmark.svg","weather":false}'
        self.cfg.write_text(before)
        result = self.run_helper("hello-config", "save", '{"wordmarkText":"123","wordmarkStyle":"omarchy"}')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.cfg.read_text(), before)

    def test_failed_config_replace_preserves_saved_logo_and_cleans_temp(self):
        with mock.patch.dict(os.environ, self.env):
            helper = load_helper("hello-config")
        before = '{"logo":"wordmark.svg"}'
        self.cfg.write_text(before)
        with mock.patch.object(helper.os, "replace", side_effect=OSError("disk failure")):
            with self.assertRaises(OSError):
                helper.save('{"name":"After"}')
        self.assertEqual(self.cfg.read_text(), before)
        self.assertEqual(list(self.cfg.parent.glob('.tmp-*')), [])

    def test_import_keeps_previous_logos_and_config(self):
        before = '{"logo":"logo.svg"}'
        self.cfg.write_text(before)
        old = self.cfg.parent / "logo.svg"
        old.write_text("original")
        for ext in ("svg", "png"):
            with self.subTest(ext=ext):
                src = self.home / ("picked." + ext)
                src.write_bytes(b"new image")
                result = self.run_helper("hello-config", "import-logo", str(src))
                self.assertEqual(result.returncode, 0, result.stderr)
                imported = Path(result.stdout.strip())
                self.assertNotEqual(imported, old)
                self.assertEqual(imported.read_bytes(), b"new image")
                self.assertEqual(old.read_text(), "original")
                self.assertEqual(self.cfg.read_text(), before)

    def test_every_wordmark_style_renders_valid_svg(self):
        styles = self.run_helper("hello-wordmark", "--styles").stdout.splitlines()
        self.assertEqual(len(styles), 11)
        for style in styles:
            with self.subTest(style=style):
                out = self.home / (style + ".svg")
                result = self.run_helper("hello-wordmark", "ADA", str(out), "--style", style)
                self.assertEqual(result.returncode, 0, result.stderr)
                svg = ET.parse(out).getroot()
                self.assertGreater(float(svg.attrib["width"]), 0)
                self.assertTrue(svg[0].attrib["d"])


class Snapshots(unittest.TestCase):
    def setUp(self):
        self.helper = load_helper("hello-snapshot")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.runtime = Path(self.temp.name).resolve()
        self.env = mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.runtime)})
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_missing_runtime_does_not_fall_back_to_tmp(self):
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": ""}):
            with self.assertRaises(ValueError):
                self.helper.runtime_dir()

    def test_shared_runtime_is_rejected(self):
        self.runtime.chmod(0o755)
        with self.assertRaises(ValueError):
            self.helper.runtime_dir()

    def test_symlink_runtime_is_rejected(self):
        link = self.runtime / "link"
        link.symlink_to(self.runtime, target_is_directory=True)
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(link)}):
            with self.assertRaises(ValueError):
                self.helper.runtime_dir()

    def test_capture_uses_private_unique_paths_not_output_names(self):
        with mock.patch.object(self.helper.subprocess, "run") as grim:
            a = self.helper.capture(["eDP-1", "../other screen"], self.runtime)
            b = self.helper.capture(["eDP-1"], self.runtime)
        self.assertNotEqual(a["directory"], b["directory"])
        self.assertEqual(Path(a["directory"]).stat().st_mode & 0o777, 0o700)
        for path in a["files"].values():
            self.assertEqual(Path(path).parent, Path(a["directory"]))
            self.assertEqual(Path(path).stat().st_mode & 0o777, 0o600)
        self.assertEqual(grim.call_args_list[1].args[0][-2], "../other screen")
        self.helper.clean(a["directory"], self.runtime)
        self.assertTrue(Path(b["directory"]).exists())

    def test_partial_failure_and_timeout_leave_no_images(self):
        for error in (subprocess.CalledProcessError(1, "grim"), subprocess.TimeoutExpired("grim", .4)):
            with self.subTest(error=error):
                with mock.patch.object(self.helper.subprocess, "run", side_effect=[None, error]):
                    with self.assertRaises(subprocess.SubprocessError):
                        self.helper.capture(["eDP-1", "HDMI-A-1"], self.runtime)
                self.assertEqual(list(self.runtime.iterdir()), [])

    def test_clean_refuses_other_directories_and_symlink_targets(self):
        other = self.runtime / "unrelated"
        other.mkdir()
        protected = other / "keep.jpg"
        protected.write_bytes(b"keep")
        link = self.runtime / (self.helper.PREFIX + "link")
        link.symlink_to(other, target_is_directory=True)
        for path in (other, link):
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.helper.clean(path, self.runtime)
        self.assertEqual(protected.read_bytes(), b"keep")

    def test_stale_crash_capture_is_removed_without_removing_recent_one(self):
        with mock.patch.object(self.helper.subprocess, "run"):
            stale = self.helper.capture(["eDP-1"], self.runtime)
            os.utime(stale["directory"], (1, 1))
            recent = self.helper.capture(["eDP-1"], self.runtime)
            self.helper.capture(["HDMI-A-1"], self.runtime)
        self.assertFalse(Path(stale["directory"]).exists())
        self.assertTrue(Path(recent["directory"]).exists())


class Menu(unittest.TestCase):
    """bin/hello-menu edits only its own line of the user's Omarchy menu."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        home = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / "config"))
        self.menu = home / "config/omarchy/extensions/omarchy-menu.jsonc"

    def run_menu(self, action):
        return subprocess.run([str(ROOT / "bin" / "hello-menu"), action], env=self.env,
                              capture_output=True, text=True, timeout=5)

    def parsed(self):
        return load_helper("hello-menu").parse(self.menu.read_text())

    def test_creates_the_file_and_removes_cleanly(self):
        self.assertEqual(self.run_menu("status").stdout.strip(), "off")
        self.assertEqual(self.run_menu("add").stdout.strip(), "on")
        entry = self.parsed()["style.lockscreen"]
        self.assertEqual(entry["action"], "omarchy-shell lock settings")
        self.assertIn("plugins/hello-lock", entry["when"])
        self.assertEqual(self.run_menu("remove").stdout.strip(), "off")
        self.assertEqual(self.parsed(), {})

    def test_keeps_comments_and_other_entries(self):
        self.menu.parent.mkdir(parents=True)
        original = '{\n  // mine\n  "trigger.x": {"label": "X", "action": "echo x"} /* note */\n}\n'
        self.menu.write_text(original)
        self.assertEqual(self.run_menu("add").returncode, 0)
        self.assertIn("// mine", self.menu.read_text())
        self.assertEqual(set(self.parsed()), {"trigger.x", "style.lockscreen"})
        self.assertEqual(self.run_menu("add").stdout.strip(), "on")  # idempotent
        self.assertEqual(self.menu.read_text().count("style.lockscreen"), 1)
        self.run_menu("remove")
        self.assertEqual(self.parsed(), {"trigger.x": {"label": "X", "action": "echo x"}})
        backups = list(self.menu.parent.glob("omarchy-menu.jsonc.bak.hello-lock.*"))
        self.assertTrue(backups)
        self.assertIn(original, [b.read_text() for b in backups])

    def test_leaves_someone_elses_entry_alone(self):
        self.menu.parent.mkdir(parents=True)
        mine = '{ "style.lockscreen": {"label": "Mine", "action": "hyprlock"} }\n'
        self.menu.write_text(mine)
        for action in ("add", "remove"):
            result = self.run_menu(action)
            self.assertEqual((result.returncode, result.stdout.strip()), (3, "other"))
        self.assertEqual(self.menu.read_text(), mine)

    def test_never_writes_a_broken_file(self):
        self.menu.parent.mkdir(parents=True)
        self.menu.write_text('{ "a": ')
        result = self.run_menu("add")
        self.assertEqual((result.returncode, result.stdout.strip()), (4, "unreadable"))
        self.assertEqual(self.menu.read_text(), '{ "a": ')


class MenuBackups(unittest.TestCase):
    """hello-menu backups are owner-only (0600) from creation, whatever the umask."""

    ORIGINAL = '{\n  // private\n  "trigger.x": {"label": "X", "action": "echo secret"}\n}\n'

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / "config"))
        self.menu = self.home / "config/omarchy/extensions/omarchy-menu.jsonc"
        self.menu.parent.mkdir(parents=True)
        self.menu.write_text(self.ORIGINAL)
        self.menu.chmod(0o600)
        self.helper = load_helper("hello-menu")
        self.helper.MENU = str(self.menu)

    def run_menu(self, action, umask=0o022):
        return subprocess.run([str(ROOT / "bin" / "hello-menu"), action], env=self.env,
                              capture_output=True, text=True, timeout=5,
                              preexec_fn=lambda: os.umask(umask))

    def backups(self):
        return sorted(self.menu.parent.glob("omarchy-menu.jsonc.bak.hello-lock.*"))

    def mode(self, path):
        return os.lstat(path).st_mode & 0o777

    def fixed_stamp(self, stamp="20260101-000000-000000"):
        fake = mock.Mock()
        fake.datetime.now.return_value.strftime.return_value = stamp
        return mock.patch.object(self.helper, "datetime", fake)

    def test_private_source_under_umask_022(self):
        result = self.run_menu("add", umask=0o022)
        self.assertEqual(result.returncode, 0, result.stderr)
        [backup] = self.backups()
        self.assertEqual(self.mode(backup), 0o600)
        self.assertEqual(backup.read_text(), self.ORIGINAL)
        self.assertEqual(self.mode(self.menu), 0o600)  # the menu keeps its own mode

    def test_policy_holds_under_permissive_umask_and_open_source(self):
        self.menu.chmod(0o644)
        for umask in (0o000, 0o002):
            for action in ("add", "remove"):
                result = self.run_menu(action, umask=umask)
                self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.backups()), 3)
        for backup in self.backups():
            self.assertEqual(self.mode(backup), 0o600)
        self.assertEqual(self.mode(self.menu), 0o644)

    def test_strict_umask_still_leaves_a_readable_backup(self):
        result = self.run_menu("add", umask=0o277)
        self.assertEqual(result.returncode, 0, result.stderr)
        [backup] = self.backups()
        self.assertEqual(self.mode(backup), 0o600)
        self.assertEqual(backup.read_text(), self.ORIGINAL)

    def test_failed_replacement_keeps_the_original_and_a_private_backup(self):
        old = os.umask(0o022)
        self.addCleanup(os.umask, old)
        with mock.patch.object(self.helper.os, "replace", side_effect=OSError("disk full")):
            with self.assertRaises(self.helper.Unsafe):
                self.helper.add()
        self.assertEqual(self.menu.read_text(), self.ORIGINAL)
        self.assertEqual(self.mode(self.menu), 0o600)
        [backup] = self.backups()
        self.assertEqual(self.mode(backup), 0o600)
        self.assertEqual(backup.read_text(), self.ORIGINAL)
        self.assertEqual(list(self.menu.parent.glob(".omarchy-menu.*")), [])  # no temp file left

    def test_existing_backup_path_is_never_overwritten_or_followed(self):
        victim = self.home / "victim"
        victim.write_text("unrelated")
        victim.chmod(0o644)
        stamp = "20260101-000000-000000"
        planted = Path(str(self.menu) + ".bak.hello-lock." + stamp)
        missing = self.home / "would-be-created"
        for setup in (lambda: planted.write_text("unrelated"),
                      lambda: planted.symlink_to(victim),
                      lambda: planted.symlink_to(missing)):
            setup()
            with self.fixed_stamp(stamp), self.assertRaises(self.helper.Unsafe):
                self.helper.add()
            self.assertEqual(self.menu.read_text(), self.ORIGINAL)
            planted.unlink()
        self.assertEqual(victim.read_text(), "unrelated")
        self.assertEqual(self.mode(victim), 0o644)
        self.assertFalse(missing.exists())

    def test_rotation_ignores_symlinks_and_tightens_old_backups(self):
        victim = self.home / "victim"
        victim.write_text("unrelated")
        victim.chmod(0o644)
        prefix = str(self.menu) + ".bak.hello-lock."
        link = Path(prefix + "00000000-000000-000000")  # oldest name: first to be pruned
        link.symlink_to(victim)
        legacy = Path(prefix + "20250101-000000-000000")  # as written by 0.4.0/0.5.0
        legacy.write_text(self.ORIGINAL)
        legacy.chmod(0o644)
        result = self.run_menu("add")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(link.is_symlink())
        self.assertEqual((victim.read_text(), self.mode(victim)), ("unrelated", 0o644))
        self.assertEqual(self.mode(legacy), 0o600)
        for _ in range(3):
            self.run_menu("remove")
            self.run_menu("add")
        regular = [b for b in self.backups() if not b.is_symlink()]
        self.assertEqual(len(regular), 3)
        self.assertNotIn(legacy, regular)
        self.assertTrue(link.is_symlink())

    def test_add_remove_and_rollback_from_backup(self):
        self.assertEqual(self.run_menu("add").stdout.strip(), "on")
        self.assertEqual(self.run_menu("status").stdout.strip(), "on")
        self.assertEqual(self.run_menu("remove").stdout.strip(), "off")
        self.assertEqual(self.helper.parse(self.menu.read_text()), self.helper.parse(self.ORIGINAL))
        first = self.backups()[0]
        self.assertEqual(first.read_text(), self.ORIGINAL)
        self.run_menu("add")
        self.menu.write_text(first.read_text())  # restoring by hand from the backup
        self.assertEqual(self.run_menu("status").stdout.strip(), "off")
        self.assertEqual(self.helper.parse(self.menu.read_text()),
                         {"trigger.x": {"label": "X", "action": "echo secret"}})


if __name__ == "__main__":
    unittest.main()
