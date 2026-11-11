#!/usr/bin/env python3
"""Live clipboard check for Settings and the setup screen (0.6.9).

Requires a running Wayland session and wl-clipboard. Meant for the disposable
VM lab (tests/vm/guest-test.py runs it after the visual suite), not your own
desktop: each phase opens a window that takes the keyboard.

`wl-copy --foreground --paste-once` serves one read of the clipboard and
then exits. A Wayland client only gets the clipboard offer while it has
keyboard focus. So each phase starts Quickshell with one window that takes
the keyboard, puts a one-time offer on the clipboard, waits, and looks at
whether wl-copy is still waiting, which means nobody read it.

- control: a plain writable TextInput. Qt must read the offer, which proves
  this check can see a read at all.
- settings, onboarding: Hello Lock's Settings and setup screen. Nothing may
  read the offer, focused or not.
- paste: a SafeTyping field with Ctrl+V sent to it. bin/hello-paste reads a
  normal offer into the field, and an offer over 4096 bytes is refused.

Never loads Service.qml, LockView.qml as a lock, PAM, or a real lock path.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

SOURCE = Path(os.environ.get("HELLO_LOCK_TEST_ROOT", Path(__file__).resolve().parents[1]))
MARKER = "hello-lock-clipboard-marker"

SHELL = r'''import QtQuick
import Quickshell
import "plugin/platform"
import "plugin/settings"
import "plugin/platform/SafeTyping.js" as SafeTyping

// Only the current phase's items exist: a hidden writable field still reads
// the clipboard, so a probe left in another phase would spoil it.
ShellRoot {
  id: root
  readonly property string phase: Quickshell.env("HL_CLIP_PHASE")
  readonly property string source: Quickshell.env("HELLO_LOCK_SOURCE")
  readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") + "/hello-lock"
  readonly property var probes: ({ control: plainProbe, empty: emptyProbe, readonly: readonlyProbe,
                                   inputfield: fieldProbe, paste: pasteProbe })

  Loader {
    active: root.probes[root.phase] !== undefined
    sourceComponent: FloatingWindow {
      visible: true
      implicitWidth: 420; implicitHeight: 120
      color: "#202020"
      Loader {
        anchors.fill: parent
        sourceComponent: root.probes[root.phase]
        onLoaded: { item.forceActiveFocus(); console.log("READY:" + root.phase) }
      }
    }
  }

  // A writable field: Qt must read the offer, or this check can't see reads.
  Component { id: plainProbe
    TextInput { color: "white"; font.pixelSize: 20 } }
  // Negative controls.
  Component { id: emptyProbe
    Item { focus: true } }
  Component { id: readonlyProbe
    TextInput { color: "white"; font.pixelSize: 20; readOnly: true } }
  Component { id: fieldProbe
    InputField { width: 300; maximumLength: 40 } }
  // A SafeTyping field, Ctrl+V, then what it holds.
  Component { id: pasteProbe
    TextInput {
      id: safe
      color: "white"; font.pixelSize: 20
      readOnly: true; cursorVisible: activeFocus; maximumLength: 40
      Keys.onPressed: (event) => SafeTyping.key(safe, event, paste)
      SafePaste { id: paste }
      Timer {
        running: true; interval: 2500
        onTriggered: {
          SafeTyping.key(safe, { key: Qt.Key_V, text: "\u0016", modifiers: Qt.ControlModifier, accepted: false }, paste)
          report.start()
        }
      }
      Timer { id: report; interval: 2500; onTriggered: console.log("FIELD:" + JSON.stringify(safe.text)) }
    }
  }

  Loader {
    active: root.phase === "settings"
    source: "plugin/Settings.qml"
    onLoaded: {
      item.pluginDir = root.source; item.configDir = root.configDir
      item.currentConfig = ({ name: "Ada" }); item.start()
      console.log("READY:settings")
    }
    onStatusChanged: if (status === Loader.Error) console.log("READY:error")
  }
  Loader {
    active: root.phase === "onboarding"
    source: "plugin/Onboarding.qml"
    onLoaded: {
      item.pluginDir = root.source; item.configDir = root.configDir
      item.suggestedName = "Ada"; item.currentConfig = ({}); item.start()
      console.log("READY:onboarding")
    }
    onStatusChanged: if (status === Loader.Error) console.log("READY:error")
  }
}
'''


class Shell:
    def __init__(self, root, phase):
        self.log = open(root / ("qs-" + phase + ".log"), "w+")
        env = dict(os.environ, HL_CLIP_PHASE=phase, HELLO_LOCK_SOURCE=str(SOURCE),
                   XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"),
                   XDG_CACHE_HOME=str(root / "cache"))
        self.proc = subprocess.Popen(["qs", "-p", str(root)], env=env,
                                     stdout=self.log, stderr=subprocess.STDOUT)

    def text(self):
        self.log.flush()
        self.log.seek(0)
        return self.log.read()

    def wait_for(self, pattern, seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            match = re.search(pattern, self.text())
            if match:
                return match
            if self.proc.poll() is not None:
                break
            time.sleep(0.1)
        raise RuntimeError("no %r from the shell:\n%s" % (pattern, self.text()[-4000:]))

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        self.log.close()


def offer(data, once=True):
    """Put `data` on the clipboard with wl-copy kept in the foreground."""
    argv = ["wl-copy", "--foreground", "--type", "text/plain;charset=utf-8"]
    if once:
        argv.insert(2, "--paste-once")
    proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    proc.stdin.write(data)
    proc.stdin.close()
    return proc


def stop(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def read_once(root, phase, settle=2.0, watch=4.0):
    """Whether the window of `phase` read a one-time offer within `watch` s."""
    shell = Shell(root, phase)
    copy = None
    try:
        ready = shell.wait_for(r"READY:(\w+)", 30).group(1)
        if ready != phase:
            raise RuntimeError("%s did not load:\n%s" % (phase, shell.text()[-4000:]))
        time.sleep(settle)          # mapped and holding the keyboard
        copy = offer(MARKER.encode())
        deadline = time.monotonic() + watch
        while time.monotonic() < deadline and copy.poll() is None:
            time.sleep(0.1)
        return copy.poll() is not None
    finally:
        if copy is not None:
            stop(copy)
        shell.close()


def pasted(root, data):
    copy = offer(data, once=False)
    shell = Shell(root, "paste")
    try:
        shell.wait_for(r"READY:paste", 30)
        return json.loads(shell.wait_for(r"FIELD:(.*)", 30).group(1))
    finally:
        shell.close()
        stop(copy)


def main():
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise SystemExit("run-clipboard: needs a running Wayland session")
    for tool in ("qs", "wl-copy", "wl-paste"):
        if not shutil.which(tool):
            raise SystemExit("run-clipboard: %s is required" % tool)
    results = {}
    with tempfile.TemporaryDirectory(prefix="hello-lock-clipboard-") as directory:
        root = Path(directory)
        (root / "plugin").symlink_to(SOURCE, target_is_directory=True)
        (root / "config/hello-lock").mkdir(parents=True)
        (root / "shell.qml").write_text(SHELL)
        results["control_read"] = read_once(root, "control")
        results["empty_read"] = read_once(root, "empty")
        results["readonly_read"] = read_once(root, "readonly")
        results["inputfield_read"] = read_once(root, "inputfield")
        results["settings_read"] = read_once(root, "settings")
        results["onboarding_read"] = read_once(root, "onboarding")
        results["paste_small"] = pasted(root, b"Bob\nSmith")
        results["paste_big"] = pasted(root, b"x" * 65536)
    print("CLIPBOARD:" + json.dumps(results, sort_keys=True))
    failures = []
    if results["control_read"] is not True:
        failures.append("the control field never read the offer, so this check can't see reads")
    if results["empty_read"]:
        failures.append("a window with no text field read the offer: something below Hello Lock "
                        "reads it, so this check can't tell Hello Lock's fields apart")
    if results["readonly_read"]:
        failures.append("a plain read-only TextInput read the clipboard")
    if results["inputfield_read"]:
        failures.append("Hello Lock's InputField read the clipboard")
    if results["settings_read"]:
        failures.append("Settings read the clipboard")
    if results["onboarding_read"]:
        failures.append("the setup screen read the clipboard")
    if results["paste_small"] != "Bob Smith":
        failures.append("paste gave %r, not 'Bob Smith'" % results["paste_small"])
    if results["paste_big"] != "":
        failures.append("an offer over 4096 bytes was pasted")
    for failure in failures:
        print("FAIL: " + failure)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
