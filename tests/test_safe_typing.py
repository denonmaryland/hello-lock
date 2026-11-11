"""Text fields that never let Qt read the clipboard (0.6.9).

The marketplace review of 0.6.7 (omacom/omarchy-plugin-marketplace#14051,
Medium) found that Settings' and Onboarding's text fields let Qt read the
whole clipboard in the shell on every clipboard change, with no size limit:
QQuickTextInput::q_canPasteChanged() calls mimeData->text() whenever the
field is not readOnly, focused or not, and Qt's Wayland reader has no total
cap. Those fields are now readOnly for good, and platform/SafeTyping.js does
the typing. Paste goes through bin/hello-paste, which reads at most 4096
bytes within a second outside the shell.

Three parts:
- the helper, with stand-ins for wl-paste (sizes, slow and endless sources,
  cleaning);
- the real fields in Quickshell offscreen, fed key events (typing, limits,
  validators, selection, Backspace/Delete, cut, paste);
- a tripwire: every text field in Settings and Onboarding is literally
  readOnly: true and goes through SafeTyping.
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
import unittest

ROOT = Path(os.environ.get("HELLO_LOCK_TEST_ROOT", Path(__file__).resolve().parents[1]))
HELPER = ROOT / "bin" / "hello-paste"

# A wl-paste stand-in driven by files in $STUB_STATE.
WL_PASTE = r'''#!/usr/bin/env python3
import os, sys, time
state = os.environ["STUB_STATE"]
with open(os.path.join(state, "argv"), "w") as f:
    f.write(" ".join(sys.argv[1:]))
with open(os.path.join(state, "pid"), "w") as f:
    f.write(str(os.getpid()))
mode = open(os.path.join(state, "mode")).read().strip()
out = sys.stdout.buffer
if mode == "fail":
    sys.exit(1)
if mode == "endless":
    while True:
        out.write(b"x" * 1024); out.flush()
if mode == "slow":
    for _ in range(100):
        out.write(b"a"); out.flush(); time.sleep(0.05)
    sys.exit(0)
if mode == "silent":
    time.sleep(30)
out.write(open(os.path.join(state, "data"), "rb").read())
'''


class Stub:
    def __init__(self, add_cleanup):
        tmp = tempfile.TemporaryDirectory()
        add_cleanup(tmp.cleanup)
        self.base = Path(tmp.name)
        self.state = self.base / "state"
        self.bin = self.base / "bin"
        self.state.mkdir()
        self.bin.mkdir()
        (self.bin / "wl-paste").write_text(WL_PASTE)
        (self.bin / "wl-paste").chmod(0o700)
        self.env = dict(os.environ, PATH="%s:%s" % (self.bin, os.environ.get("PATH", "/usr/bin:/bin")),
                        STUB_STATE=str(self.state))
        add_cleanup(self.kill)  # runs before the folder goes

    def set(self, mode, data=b""):
        (self.state / "mode").write_text(mode)
        (self.state / "data").write_bytes(data)

    def kill(self):
        try:
            os.kill(int((self.state / "pid").read_text()), 9)
        except (OSError, ValueError):
            pass

    def gone(self):
        try:
            os.kill(int((self.state / "pid").read_text()), 0)
        except ProcessLookupError:
            return True
        return False


class Helper(unittest.TestCase):
    def setUp(self):
        self.stub = Stub(self.addCleanup)

    def paste(self, mode, data=b""):
        self.stub.set(mode, data)
        started = time.monotonic()
        result = subprocess.run([str(HELPER)], env=self.stub.env, capture_output=True, timeout=10)
        return result.returncode, result.stdout.decode(), time.monotonic() - started

    def test_asks_for_text_without_a_trailing_newline(self):
        self.assertEqual(self.paste("data", b"Ada")[:2], (0, "Ada"))
        self.assertEqual((self.stub.state / "argv").read_text(), "--no-newline --type text")

    def test_at_the_limit_is_kept_and_one_byte_over_is_refused(self):
        self.assertEqual(self.paste("data", b"a" * 4096)[:2], (0, "a" * 4096))
        self.assertEqual(self.paste("data", b"a" * 4097)[:2], (3, ""))
        self.assertEqual(self.paste("data", "\xe9".encode() * 2049)[:2], (3, ""))

    def test_an_endless_source_is_cut_off_and_killed(self):
        code, out, took = self.paste("endless")
        self.assertEqual((code, out), (3, ""))
        self.assertLess(took, 3)
        self.assertTrue(self.stub.gone())

    def test_a_slow_or_silent_source_is_stopped_at_one_second(self):
        for mode in ("slow", "silent"):
            with self.subTest(mode=mode):
                code, out, took = self.paste(mode)
                self.assertEqual((code, out), (3, ""))
                self.assertLess(took, 3)
                self.assertTrue(self.stub.gone())

    def test_one_clean_line(self):
        raw = "  Ada\r\nLovelace\t1815\x1b[2J\u202eevil\u200b\x00 ".encode()
        self.assertEqual(self.paste("data", raw)[:2], (0, "  Ada Lovelace 1815[2Jevil "))
        self.assertEqual(self.paste("data", b"caf\xc3\xa9 \xff\xfe ok")[:2], (0, "caf\xe9  ok"))
        self.assertEqual(self.paste("data", "\u65e5\u672c \U0001f600".encode())[:2], (0, "\u65e5\u672c \U0001f600"))

    def test_no_text_or_no_wl_paste_prints_nothing(self):
        self.assertEqual(self.paste("fail")[:2], (1, ""))
        bare = self.stub.base / "python-only"   # Python, but no wl-paste
        bare.mkdir()
        (bare / "python3").symlink_to(sys.executable)
        env = dict(self.stub.env, PATH=str(bare))
        result = subprocess.run([str(HELPER)], env=env, capture_output=True, timeout=10)
        self.assertEqual((result.returncode, result.stdout), (1, b""))

    def test_takes_no_arguments(self):
        result = subprocess.run([str(HELPER), "--type", "image"], env=self.stub.env,
                                capture_output=True, timeout=10)
        self.assertEqual((result.returncode, result.stdout), (2, b""))


# Each step: a key event (key, text, modifiers) or a call, then the field's
# text, cursor and how many textEdited signals it sent.
SHELL = r'''import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import "platform"
import "platform/SafeTyping.js" as SafeTyping

ShellRoot {
  id: shell
  property var log: []
  property int edits: 0
  FloatingWindow {
    implicitWidth: 400; implicitHeight: 200; visible: true
    Column {
      QQC.TextField {
        id: control; width: 300; readOnly: true; cursorVisible: activeFocus; maximumLength: 8
        onTextEdited: shell.edits++
        Keys.onPressed: (event) => SafeTyping.key(control, event, paste)
      }
      TextInput {
        id: digits; width: 300; readOnly: true; cursorVisible: activeFocus; maximumLength: 2
        validator: RegularExpressionValidator { regularExpression: /\d{0,2}/ }
        onTextEdited: shell.edits++
        Keys.onPressed: (event) => SafeTyping.key(digits, event, paste)
      }
      TextInput {
        id: hour; width: 300; readOnly: true; maximumLength: 2
        validator: IntValidator { bottom: 0; top: 23 }
        Keys.onPressed: (event) => SafeTyping.key(hour, event, null)
      }
      TextInput {
        id: scale; width: 300; readOnly: true
        validator: DoubleValidator { bottom: 0.5; top: 8; decimals: 1; locale: "C"; notation: DoubleValidator.StandardNotation }
        Keys.onPressed: (event) => SafeTyping.key(scale, event, null)
      }
    }
  }
  SafePaste { id: paste }

  function press(field, key, text, mods) {
    var e = { key: key, text: text || "", modifiers: mods || 0, accepted: false }
    SafeTyping.key(field, e, field === hour ? null : paste)
    return e.accepted
  }
  function snap(name, field, accepted) {
    log.push({ step: name, text: field.text, cursor: field.cursorPosition, edits: edits,
               accepted: accepted, canPaste: field.canPaste, readOnly: field.readOnly,
               cursorVisible: field.cursorVisible })
  }
  function type(field, s) { for (var i = 0; i < s.length; i++) press(field, 0, s[i]) }

  Timer {
    running: true; interval: 300
    onTriggered: {
      control.forceActiveFocus()
      type(control, "Ada"); snap("type", control, true)
      type(control, " Lovelace"); snap("limit", control, true)
      control.cursorPosition = 1; type(control, "x"); snap("insert-full", control, true)
      control.select(0, 3); type(control, "Z"); snap("replace", control, true)
      snap("backspace", control, press(control, Qt.Key_Backspace))
      control.cursorPosition = 0
      snap("delete", control, press(control, Qt.Key_Delete))
      control.text = "one two"; control.cursorPosition = 7
      snap("word-back", control, press(control, Qt.Key_Backspace, "", Qt.ControlModifier))
      control.select(0, 3)
      snap("cut", control, press(control, Qt.Key_X, "\u0018", Qt.ControlModifier))
      snap("left", control, press(control, Qt.Key_Left))
      snap("ctrl-a", control, press(control, Qt.Key_A, "\u0001", Qt.ControlModifier))
      snap("enter", control, press(control, Qt.Key_Return, "\r"))
      snap("control-char", control, press(control, 0, "\u001b"))
      control.text = "\ud83d\ude00"; control.cursorPosition = 2
      snap("emoji-back", control, press(control, Qt.Key_Backspace))
      digits.forceActiveFocus()
      type(digits, "1a2"); snap("validator", digits, true)
      type(digits, "3"); snap("digits-full", digits, true)
      hour.forceActiveFocus()
      type(hour, "2"); type(hour, "9"); snap("int-validator", hour, true)
      snap("no-paste", hour, press(hour, Qt.Key_V, "\u0016", Qt.ControlModifier))
      scale.forceActiveFocus()
      type(scale, "0"); snap("double-below", scale, true)
      type(scale, ".5"); snap("double-in", scale, true)
      type(scale, "5"); snap("double-places", scale, true)
      scale.text = ""; type(scale, "9"); snap("double-over", scale, true)
      type(scale, "7.25"); snap("double-typed", scale, true)
      control.text = ""; control.forceActiveFocus()
      snap("paste", control, press(control, Qt.Key_V, "\u0016", Qt.ControlModifier))
      pasteWait.start()
    }
  }
  Timer {
    id: pasteWait; interval: 2500
    onTriggered: {
      snap("pasted", control, true)
      console.log("RESULT:" + JSON.stringify(log))
      Qt.quit()
    }
  }
}
'''


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class Fields(unittest.TestCase):
    """The real QML, in Quickshell offscreen: no desktop, clipboard or PAM."""

    @classmethod
    def setUpClass(cls):
        stub = Stub(cls.addClassCleanup)
        root = stub.base / "shell"
        (root / "bin").mkdir(parents=True)
        shutil.copytree(ROOT / "platform", root / "platform")
        shutil.copy2(HELPER, root / "bin" / "hello-paste")
        (root / "shell.qml").write_text(SHELL)
        stub.set("data", "Bob\nSmith with a long tail".encode())
        env = dict(stub.env, QT_QPA_PLATFORM="offscreen", WAYLAND_DISPLAY="",
                   HYPRLAND_INSTANCE_SIGNATURE="fixture", XDG_RUNTIME_DIR=str(stub.base),
                   XDG_CONFIG_HOME=str(stub.base / "config"), XDG_CACHE_HOME=str(stub.base / "cache"))
        result = subprocess.run(["qs", "-n", "-p", str(root)], env=env, capture_output=True,
                                text=True, timeout=30)
        match = re.search(r"RESULT:(\[.*\])", result.stdout + result.stderr)
        if not match:
            raise AssertionError("no result from the shell:\n" + result.stdout + result.stderr)
        cls.steps = {s["step"]: s for s in json.loads(match.group(1))}

    def check(self, step, text, cursor=None, edits=None, accepted=None):
        s = self.steps[step]
        self.assertEqual(s["text"], text, step)
        if cursor is not None:
            self.assertEqual(s["cursor"], cursor, step)
        if edits is not None:
            self.assertEqual(s["edits"], edits, step)
        if accepted is not None:
            self.assertEqual(s["accepted"], accepted, step)

    def test_fields_stay_read_only_so_qt_never_reads_the_clipboard(self):
        for s in self.steps.values():
            self.assertTrue(s["readOnly"], s["step"])
            self.assertFalse(s["canPaste"], s["step"])

    def test_typing_follows_the_field_limit(self):
        self.check("type", "Ada", 3, 3)
        self.check("limit", "Ada Love", 8, 8)        # maximumLength 8
        self.check("insert-full", "Ada Love", 1, 8)  # full: nothing goes in, no edit
        # A replaced selection is Qt's remove() then insert(): two textEdited
        # signals. The fields' handlers only set a value or redraw.
        self.check("replace", "Z Love", 1, 10)
        self.assertTrue(self.steps["type"]["cursorVisible"])

    def test_erasing(self):
        self.check("backspace", " Love", 0, 11, True)
        self.check("delete", "Love", 0, 12, True)
        self.check("word-back", "one ", 4, 13, True)
        self.check("cut", " ", 0, 14, True)
        self.check("emoji-back", "", 0, None, True)  # both halves of the pair

    def test_navigation_shortcuts_and_enter_are_left_to_the_field(self):
        self.check("left", " ", None, 14, False)
        self.check("ctrl-a", " ", None, 14, False)
        self.check("enter", " ", None, 14, False)
        self.check("control-char", " ", None, 14, False)

    def test_validators_still_apply(self):
        self.check("validator", "12", 2)
        self.check("digits-full", "12", 2)
        self.check("int-validator", "2", 1)  # 29 is not an hour

    def test_decimal_fields_allow_in_between_states_only(self):
        self.check("double-below", "0")      # below 0.5, but "0.5" is on the way
        self.check("double-in", "0.5")
        self.check("double-places", "0.5")   # one decimal place
        self.check("double-over", "")        # 9 is over 8
        self.check("double-typed", "7.2")

    def test_paste_is_bounded_cleaned_and_kept_to_the_limit(self):
        self.check("no-paste", "2", accepted=True)
        self.check("paste", "", accepted=True)
        self.check("pasted", "Bob Smit", 8)


class Tripwire(unittest.TestCase):
    """Every text field in Settings and Onboarding is read-only to Qt."""

    FILES = ["Settings.qml", "Onboarding.qml"] + sorted(
        str(p.relative_to(ROOT)) for p in (ROOT / "settings").glob("*.qml"))

    FIELD = re.compile(r"(?<![\w.])(?:QQC\.)?(?:TextInput|TextEdit|TextField|TextArea)\s*\{")

    def fields(self, text):
        """(own lines, whole body) of each text-field element in `text`."""
        for match in self.FIELD.finditer(text):
            depth, i = 0, match.end() - 1
            while True:
                depth += {"{": 1, "}": -1}.get(text[i], 0)
                i += 1
                if depth == 0:
                    break
            body = own = text[match.end():i - 1]
            # Its own lines: drop nested blocks (children, handlers), innermost first.
            while True:
                stripped = re.sub(r"\{[^{}]*\}", "", own)
                if stripped == own:
                    break
                own = stripped
            yield own, body

    def test_every_text_field_is_read_only_and_uses_safe_typing(self):
        found = 0
        for name in self.FILES:
            for own, body in self.fields((ROOT / name).read_text()):
                found += 1
                with self.subTest(file=name, field=own.strip().splitlines()[0]):
                    self.assertRegex(own, r"(?m)^\s*readOnly:\s*true\s*$")
                    self.assertRegex(own, r"(?m)^\s*Keys\.onPressed:")
                    self.assertIn("SafeTyping.key(", body)
        self.assertEqual(found, 5)  # InputField and the four Onboarding fields

    def test_nothing_calls_qt_paste_or_makes_a_field_writable(self):
        for name in self.FILES + ["platform/SafeTyping.js", "platform/SafePaste.qml"]:
            text = (ROOT / name).read_text()
            with self.subTest(file=name):
                self.assertNotRegex(text, r"\.paste\(\)")
                self.assertNotRegex(text, r"readOnly\s*[:=](?!\s*true\b)")

    def test_settings_uses_only_input_field(self):
        self.assertNotRegex((ROOT / "Settings.qml").read_text(),
                            r"\b(TextInput|TextEdit|TextField|TextArea)\s*\{")


if __name__ == "__main__":
    unittest.main()
