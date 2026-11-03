#!/usr/bin/env python3
"""Exercise standalone visuals on Wayland with disposable settings and no PAM.

The staged Settings copy does not take keyboard focus. No Commons/Ui modules,
Omarchy adapter, or authentication service are placed in its launch tree.
"""
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import time

SOURCE = Path(__file__).resolve().parents[1]
QA = '''
  IpcHandler {
    target: "qa"
    function state(): string {
      return JSON.stringify({away: settings.item.away, logo: root.logo, calm: splash.calm, automaticCalm: desktopMotion.calm, studioCalm: settings.item.calm,
        unlockAnimation: settings.item.unlockAnimation, unlockDuration: settings.item.unlockDuration,
        customDuration: settings.item.customUnlockDuration,
        weather: settings.item.weather, weatherAvailable: settings.item.weatherAvailable,
        weatherLocation: settings.item.weatherLocation, weatherUnit: settings.item.weatherUnit,
        typingAudio: Qt.createComponent("plugin/TypingSound.qml").status,
        loadedDuration: root.config.unlockDuration, playDuration: splash.playDuration,
        color: String(Platform.Color.background), menu: settings.item.menuState,
        omarchy: settings.item.omarchyIntegration, status: settings.item.status, image: settings.item.imagePath, picker: Qt.createComponent("plugin/platform/FilePicker.qml").status})
    }
    function wordmark(): string {
      settings.item.chooseLogo("wordmark"); settings.item.wordmarkText = "NOVA";
      settings.item.wordmarkStyle = "led"; settings.item.renderWordmark(true); return "ok"
    }
    function preview(): string { settings.item.lockPreviewRequested("liquid"); return "ok" }
    function unlock(): string { settings.item.unlockPreviewRequested("radar", "flip"); return "ok" }
    function calm(): string { settings.item.save({motion: "reduced"}); return "ok" }
    function automatic(): string { settings.item.save({motion: null}); return "ok" }
    function full(): string { settings.item.save({motion: "full"}); return "ok" }
    function timing(milliseconds: int, animated: bool): string {
      settings.item.unlockAnimation = animated
      settings.item.unlockDuration = milliseconds
      settings.item.save({unlockAnimation: animated, unlockDuration: milliseconds}); return "ok"
    }
    function image(): string { settings.item.importImage(root.sourceDir + "/symbols/nova.svg"); return "ok" }
    function weather(on: bool): string {
      settings.item.weather = on; settings.item.weatherLocation = "Fixture Town"; settings.item.weatherUnit = "metric"
      settings.item.save({weather: on, weatherLocation: "Fixture Town", weatherUnit: "metric"}); return "ok"
    }
    function snapshot(path: string): string {
      settings.item.captureItem().grabToImage(function(result) { result.saveToFile(path) }); return "ok"
    }
  }
'''


def main():
    namespace = runpy.run_path(str(SOURCE / "bin/hello-lock"))
    with tempfile.TemporaryDirectory(prefix="hello-standalone-qa-") as directory:
        root = Path(directory)
        bundle = root / "bundle"
        bundle.mkdir()
        plugin = namespace["stage_runtime"](SOURCE, bundle)
        (plugin / "Settings.qml").unlink()
        settings = (SOURCE / "Settings.qml").read_text().replace("WlrKeyboardFocus.Exclusive", "WlrKeyboardFocus.None")
        settings = settings.replace("  signal closed()", "  function captureItem() { return card }\n  signal closed()", 1)
        (plugin / "Settings.qml").write_text(settings)
        (plugin / "UnlockSplash.qml").unlink()
        (plugin / "UnlockSplash.qml").write_text((SOURCE / "UnlockSplash.qml").read_text().replace("WlrKeyboardFocus.Exclusive", "WlrKeyboardFocus.None"))
        shell = bundle / "shell.qml"
        # Simulate missed atomic-replacement notifications. Successful Settings
        # saves must explicitly reload the persisted config, without a restart.
        shell.write_text(shell.read_text().replace("  id: root", "  id: root\n" + QA, 1)
                         .replace("onFileChanged: reload()", "onFileChanged: {}"))
        config = root / "config"
        config.mkdir()
        (config / "config.json").write_text(json.dumps({"name": "Ada", "weather": False, "sounds": False}))
        (config / "appearance.json").write_text('{"background":"#18232f","accent":"#92d8c7"}')
        (config / "sounds-off").touch()
        env = dict(os.environ, HELLO_LOCK_SOURCE=str(plugin), HELLO_LOCK_CONFIG_DIR=str(config),
                   HELLO_LOCK_ACTION="settings", XDG_CONFIG_HOME=str(root / "xdg-config"),
                   XDG_STATE_HOME=str(root / "state"), XDG_CACHE_HOME=str(root / "cache"),
                   HELLO_STATUS_WEATHER_CACHE=str(root / "cache/weather.json"))
        with (root / "qml.log").open("w") as log:
            proc = subprocess.Popen(["qs", "-p", str(bundle)], env=env, stdout=log, stderr=subprocess.STDOUT)
            def ipc(target, method, *args):
                result = subprocess.run(["qs", "ipc", "-p", str(bundle), "call", target, method, *map(str, args)], capture_output=True, text=True)
                if result.returncode:
                    raise RuntimeError(result.stdout + result.stderr)
                return result.stdout.strip()
            def wait(predicate):
                for _ in range(80):
                    if proc.poll() is not None:
                        raise RuntimeError((root / "qml.log").read_text())
                    try:
                        if predicate(): return
                    except (ValueError, RuntimeError, FileNotFoundError): pass
                    time.sleep(0.1)
                raise AssertionError("Timed out waiting for standalone preview: " + str(state()) + " saved=" + str(saved()) + " logs=" + (root / "qml.log").read_text())
            def state(): return json.loads(ipc("qa", "state"))
            def saved(): return json.loads((config / "config.json").read_text())
            try:
                wait(lambda: json.loads(ipc("standalone", "status"))["ready"])
                assert state()["omarchy"] is False
                assert state()["menu"] == ""
                assert state()["color"] == "#18232f"
                assert state()["picker"] == 1  # Component.Ready; does not open a dialog.
                assert state()["typingAudio"] == 1  # Compile only; no player or edit events.
                assert state()["weatherAvailable"] and not state()["weather"]
                ipc("qa", "automatic")
                wait(lambda: state()["studioCalm"] == state()["automaticCalm"])
                if os.environ.get("HELLO_LOCK_QA_EXPECT_CALM") == "1":
                    assert state()["automaticCalm"] is True
                for section in range(8):
                    assert ipc("standalone", "section", section) == "ok"
                    time.sleep(0.15)
                for reduced in (False, True):
                    ipc("qa", "timing", 600, "true")
                    wait(lambda: state().get("loadedDuration") == 600)
                    assert state()["customDuration"] == 600
                    if reduced:
                        ipc("qa", "calm")
                        wait(lambda: saved().get("motion") == "reduced")
                    started = time.monotonic()
                    ipc("qa", "unlock")
                    wait(lambda: json.loads(ipc("standalone", "status"))["splash"])
                    assert state()["playDuration"] == 600
                    wait(lambda: not json.loads(ipc("standalone", "status"))["splash"])
                    elapsed = time.monotonic() - started
                    assert 0.35 <= elapsed < 1.6, '600 ms overlay limit did not apply: ' + str(elapsed)
                    wait(lambda: not state()["away"])
                if os.environ.get("HELLO_LOCK_QA_UNLOCK_IMAGE"):
                    ipc("qa", "timing", 1700, "true")
                    wait(lambda: state().get("loadedDuration") == 1700)
                    assert state()["customDuration"] == 1700
                    ipc("standalone", "section", 2)
                    time.sleep(.3)
                    ipc("qa", "snapshot", os.environ["HELLO_LOCK_QA_UNLOCK_IMAGE"])
                    wait(lambda: Path(os.environ["HELLO_LOCK_QA_UNLOCK_IMAGE"]).is_file())
                ipc("qa", "timing", 0, "false")
                wait(lambda: saved().get("unlockAnimation") is False and state().get("loadedDuration") == 0)
                assert state()["unlockAnimation"] is False
                ipc("qa", "timing", 0, "true")
                wait(lambda: saved().get("unlockAnimation") is True)
                # Return to full motion for the pre-existing preview scenarios.
                ipc("qa", "full")
                wait(lambda: saved().get("motion") == "full")
                ipc("qa", "wordmark")
                wait(lambda: saved().get("wordmarkText") == "NOVA")
                wait(lambda: Path(state()["logo"]).is_file())
                ipc("qa", "preview")
                assert json.loads(ipc("standalone", "status"))["preview"]
                assert state()["away"]
                ipc("standalone", "closePreview")
                assert not state()["away"]
                ipc("qa", "unlock")
                wait(lambda: json.loads(ipc("standalone", "status"))["splash"])
                assert not state()["calm"]
                ipc("standalone", "closePreview")
                assert not state()["away"]
                ipc("qa", "calm")
                wait(lambda: saved().get("motion") == "reduced")
                time.sleep(0.2)
                ipc("qa", "unlock")
                wait(lambda: json.loads(ipc("standalone", "status"))["splash"])
                assert state()["calm"]
                ipc("standalone", "closePreview")
                assert not state()["away"]
                ipc("qa", "image")
                wait(lambda: Path(saved().get("logo", "")).name.startswith("logo-"))
                assert not saved().get("wordmarkText")
                ipc("standalone", "section", 1)
                time.sleep(0.3)
                if os.environ.get("HELLO_LOCK_QA_IMAGE"):
                    ipc("qa", "snapshot", os.environ["HELLO_LOCK_QA_IMAGE"])
                    wait(lambda: Path(os.environ["HELLO_LOCK_QA_IMAGE"]).stat().st_size > 0)
                ipc("standalone", "section", 7)
                ipc("qa", "weather", "true")
                wait(lambda: saved().get("weather") is True and saved().get("weatherLocation") == "Fixture Town")
                assert state()["weatherUnit"] == "metric"
                if os.environ.get("HELLO_LOCK_QA_WEATHER_IMAGE"):
                    time.sleep(.3)
                    ipc("qa", "snapshot", os.environ["HELLO_LOCK_QA_WEATHER_IMAGE"])
                    wait(lambda: Path(os.environ["HELLO_LOCK_QA_WEATHER_IMAGE"]).stat().st_size > 0)
                ipc("qa", "weather", "false")
                wait(lambda: saved().get("weather") is False)
                ipc("standalone", "quit")
                proc.wait(timeout=5)
            finally:
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait(timeout=5)
        text = (root / "qml.log").read_text()
        failures = [line for line in text.splitlines() if "ERROR" in line or "ReferenceError" in line or "TypeError" in line]
        assert not failures, "\n".join(failures)
        print("Standalone: 8 sections, timed normal/reduced splashes, explicit config reload without file-watch events, isolated persistence, wordmark, image import, native dialog compilation, theme, lock preview and return passed.")
        for line in text.splitlines():
            if "WARN" in line: print(line)


if __name__ == "__main__":
    main()
