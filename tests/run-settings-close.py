#!/usr/bin/env python3
"""Settings-only QML persistence checks. Requires a running Wayland desktop.

Uses disposable settings and IPC method calls, not mouse input. Never loads
Service.qml, LockView.qml, PAM, or a real lock path.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

SOURCE = Path(os.environ.get("HELLO_LOCK_TEST_ROOT", Path(__file__).resolve().parents[1]))
QML = r'''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 id: root
 property string lastExit: ""
 Loader {
  id: settings
  active: false
  source: "plugin/Settings.qml"
  property var config: ({})
  onLoaded: {
   item.pluginDir = Quickshell.env("HELLO_LOCK_SOURCE")
   item.configDir = Quickshell.env("XDG_CONFIG_HOME") + "/hello-lock"
   item.currentConfig = config
   item.start()
  }
 }
 Connections {
  target: settings.item
  function onClosed() { root.lastExit = "close"; settings.active = false }
  function onSetupRequested() { root.lastExit = "setup"; settings.active = false }
 }
 Timer { interval: 60000; running: true; onTriggered: Qt.quit() }
 IpcHandler {
  target: "qa"
  function open(config: string): string {
   settings.active = false; root.lastExit = "";
   settings.config = JSON.parse(config); settings.active = true; return "ok"
  }
  function edit(kind: string): string {
   var i = settings.item
   if (kind === "name") { i.save({name: "After close"}, 600); i.requestExit("close") }
   else if (kind === "burst") {
    i.save({brand: "FIRST"}); i.flush(); i.save({clock: false}, 600); i.requestExit("close")
   } else if (kind === "sound") { i.saveSound({volume: 0.85, quietStart: 22}); i.requestExit("close") }
   else if (kind === "wordmark") {
    i.logoChoice = "wordmark"; i.wordmarkText = "QA"; i.renderWordmark(true); i.requestExit("setup")
   } else if (kind === "custom") { i.chooseSymbol("radar"); i.chooseSymbol("custom"); i.requestExit("close") }
   else if (kind === "preset-close") {
    i.save({brand: "Queued brand"}, 300)
    i.runPreset("create", "Queued preset"); i.requestExit("close")
   }
   else if (kind === "failed-preset-close") {
    i.runPreset("create", "Existing"); i.requestExit("close")
   }
   else if (kind === "menu-on-close") { i.setMenu(true); i.requestExit("close") }
   else if (kind === "menu-off-close") { i.setMenu(false); i.requestExit("close") }
   else if (kind === "close") i.requestExit("close")
   else if (kind === "birthday") {
    i.birthMonth = "1"; i.birthDay = "14"; i.saveBirthday()
    i.birthMonth = "13"; i.saveBirthday(); i.requestExit("close")
   }
   return "ok"
  }
  function section(id: string): string {
   settings.item.sectionIndex = settings.item.sections.findIndex(function(s) { return s.id === id }); return "ok"
  }
  function preset(action: string, value: string): string {
   settings.item.sectionIndex = settings.item.sections.findIndex(function(s) { return s.id === "presets" })
   settings.item.runPreset(action, value); return "ok"
  }
  function status(): string {
   return JSON.stringify({active: settings.active, lastExit: root.lastExit,
    name: settings.item ? settings.item.name : "",
    presetBusy: settings.item ? settings.item.presetBusy : false,
    selectedPreset: settings.item ? settings.item.selectedPreset : "",
    presets: settings.item ? settings.item.brandingPresets : [],
    menuState: settings.item ? settings.item.menuState : "",
    status: settings.item ? settings.item.status : "closed"})
  }
  function quit(): string { Qt.quit(); return "ok" }
 }
}
'''

class SettingsClose(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="hello-lock-settings-test-")
        cls.root = Path(cls.temp.name)
        cls.config_dir = cls.root / "config/hello-lock"
        cls.config_dir.mkdir(parents=True)
        for name in ("one.svg", "two.svg"):
            (cls.config_dir / name).write_text('<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>')
        cls.config = cls.config_dir / "config.json"
        (cls.root / "plugin").symlink_to(SOURCE, target_is_directory=True)
        for module in ("Commons", "Ui"):
            (cls.root / module).symlink_to(Path("/usr/share/omarchy/shell") / module, target_is_directory=True)
        (cls.root / "shell.qml").write_text(QML)
        cls.env = dict(os.environ, XDG_CONFIG_HOME=str(cls.root / "config"),
                       XDG_STATE_HOME=str(cls.root / "state"), XDG_CACHE_HOME=str(cls.root / "cache"),
                       HELLO_LOCK_SOURCE=str(SOURCE))
        cls.log = (cls.root / "qml.log").open("w+")
        cls.proc = subprocess.Popen(["qs", "-p", str(cls.root)], env=cls.env,
                                    stdout=cls.log, stderr=subprocess.STDOUT)
        try:
            cls.wait_for(lambda: cls.call("status"), allow_failure=True)
        except Exception:
            cls.proc.terminate(); cls.proc.wait(timeout=5)
            cls.log.seek(0)
            raise RuntimeError(cls.log.read())

    @classmethod
    def tearDownClass(cls):
        try:
            cls.call("quit")
        finally:
            if cls.proc.poll() is None:
                cls.proc.terminate()
            cls.proc.wait(timeout=5)
            cls.log.seek(0)
            log = cls.log.read()
            cls.log.close()
            cls.temp.cleanup()
            print(log)

    @classmethod
    def call(cls, *args):
        result = subprocess.run(["qs", "ipc", "-p", str(cls.root), "call", "qa", *args],
                                env=cls.env, capture_output=True, text=True, timeout=5)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        return result.stdout.strip()

    @classmethod
    def wait_for(cls, check, allow_failure=False):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            try:
                if check():
                    return
            except RuntimeError:
                if not allow_failure:
                    raise
            time.sleep(0.05)
        raise AssertionError("Settings operation did not complete")

    def open(self, config=None):
        config = config or {"name": "Before", "weather": False, "customKey": {"keep": True}}
        self.config.write_text(json.dumps(config))
        self.call("open", json.dumps(config))
        self.wait_for(lambda: json.loads(self.call("status"))["active"])

    def edit_close(self, kind, exit_action="close"):
        self.call("edit", kind)
        self.wait_for(lambda: not json.loads(self.call("status"))["active"])
        self.assertEqual(json.loads(self.call("status"))["lastExit"], exit_action)
        return json.loads(self.config.read_text())

    def test_failed_preset_blocks_first_close_but_allows_retry(self):
        self.open({"name": "Before", "brandingPresets": [{"id": "a", "name": "Existing", "branding": {}}]})
        self.call("edit", "failed-preset-close")
        self.wait_for(lambda: "already exists" in json.loads(self.call("status"))["status"])
        time.sleep(0.15)
        self.assertTrue(json.loads(self.call("status"))["active"])
        self.call("edit", "close")
        self.wait_for(lambda: not json.loads(self.call("status"))["active"])

    def test_menu_toggle_finishes_before_close(self):
        menu = self.root / "config/omarchy/extensions/omarchy-menu.jsonc"
        self.open()
        self.wait_for(lambda: json.loads(self.call("status"))["menuState"] == "off")
        self.edit_close("menu-on-close")
        self.assertIn('"action":"omarchy-shell lock settings"', menu.read_text())
        self.open()
        self.wait_for(lambda: json.loads(self.call("status"))["menuState"] == "on")
        self.edit_close("menu-off-close")
        self.assertNotIn("style.lockscreen", menu.read_text())

    def test_invalid_presets_do_not_interrupt_personal_settings(self):
        for bad in ([None], [{"id": "a", "name": 7, "branding": {}}], "not a list"):
            self.open({"name": "Existing name", "brand": "Existing brand", "brandingPresets": bad})
            state = json.loads(self.call("status"))
            self.assertEqual(state["name"], "Existing name")
            self.assertEqual(state["presets"], [])
            self.assertIn("invalid", state["status"])
            self.edit_close("name")
            self.assertEqual(json.loads(self.config.read_text())["brandingPresets"], bad)

    def test_preset_waits_for_autosave_and_close(self):
        self.open()
        saved = self.edit_close("preset-close")
        self.assertEqual(saved["brandingPresets"][0]["branding"]["brand"], "Queued brand")
        self.assertEqual(saved["name"], "Before")

    def test_preset_ui_create_apply_delete_and_retry(self):
        self.open({"brand": "Brand", "symbolParts": ["one.svg", "two.svg"]})
        def run(action, value=""):
            self.call("preset", action, value)
            self.wait_for(lambda: not json.loads(self.call("status"))["presetBusy"])
            return json.loads(self.call("status"))
        first = run("create", "First")
        ident = first["selectedPreset"]
        self.assertEqual(len(first["presets"]), 1)
        failed = run("create", "First")
        self.assertIn("already exists", failed["status"])
        second = run("create", "Second")
        self.assertEqual(len(second["presets"]), 2)
        self.assertEqual(run("apply", ident)["selectedPreset"], ident)
        run("mode", "cycle")
        self.assertEqual(json.loads(self.config.read_text())["presetMode"], "cycle")
        self.assertEqual(len(run("delete", ident)["presets"]), 1)

    def test_name_persists_on_immediate_close_and_reopen(self):
        self.open()
        saved = self.edit_close("name")
        self.assertEqual(saved["name"], "After close")
        self.assertEqual(saved["customKey"], {"keep": True})
        self.call("open", json.dumps(saved))
        self.assertEqual(json.loads(self.call("status"))["name"], "After close")

    def test_inflight_and_pending_updates_both_persist(self):
        self.open()
        saved = self.edit_close("burst")
        self.assertEqual(saved["brand"], "FIRST")
        self.assertIs(saved["clock"], False)

    def test_sound_persists_on_immediate_close(self):
        self.open()
        self.edit_close("sound")
        text = (self.config_dir / "sound.conf").read_text()
        self.assertIn("VOLUME=0.85", text)
        self.assertIn("QUIET_START=22", text)

    def test_wordmark_finishes_before_setup_exit(self):
        self.open()
        saved = self.edit_close("wordmark", "setup")
        self.assertEqual(saved["wordmarkText"], "QA")
        self.assertTrue((self.config_dir / saved["logo"]).is_file())

    def test_custom_symbol_can_be_restored_before_exit(self):
        self.open({"symbolParts": ["one.svg", "two.svg"], "weather": False})
        saved = self.edit_close("custom")
        self.assertEqual(saved["symbolParts"], ["one.svg", "two.svg"])
        self.assertNotIn("symbol", saved)

    def test_failed_sound_write_keeps_settings_open(self):
        self.open()
        sound = self.config_dir / "sound.conf"
        if sound.exists():
            sound.unlink()
        sound.mkdir()
        try:
            self.call("edit", "sound")
            self.wait_for(lambda: "directory" in json.loads(self.call("status"))["status"].lower())
            time.sleep(0.1)
            self.assertTrue(json.loads(self.call("status"))["active"])
        finally:
            sound.rmdir()

    def test_failed_write_keeps_settings_open(self):
        self.open()
        self.config.write_text("{broken")
        self.call("edit", "name")
        self.wait_for(lambda: "refusing to replace" in json.loads(self.call("status"))["status"])
        time.sleep(0.1)
        self.assertTrue(json.loads(self.call("status"))["active"])
        self.assertEqual(self.config.read_text(), "{broken")

    def test_second_close_after_failed_write_closes(self):
        self.open()
        self.config.write_text("{broken")
        self.call("edit", "name")
        self.wait_for(lambda: "refusing to replace" in json.loads(self.call("status"))["status"])
        self.call("edit", "close")
        self.wait_for(lambda: not json.loads(self.call("status"))["active"])
        self.assertEqual(self.config.read_text(), "{broken")

    def test_half_typed_invalid_birthday_is_not_saved(self):
        self.open({"name": "Before", "birthday": "07-04", "weather": False})
        saved = self.edit_close("birthday")
        self.assertEqual(saved["birthday"], "07-04")

if __name__ == "__main__":
    unittest.main(verbosity=2)
