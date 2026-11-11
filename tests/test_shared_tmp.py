"""Nothing is written to a fixed name in a folder other users can write to.

Regression tests for the second marketplace review finding on 0.6.7: the
typing harness (a development tool) made /tmp/hl without checking who owned
it, then opened its lock and its log there with truncating redirects. Another
user could create /tmp/hl first and point those names at a file of yours.

The harness runs here with stand-ins for the recorder, Quickshell and ffmpeg,
and with $TMPDIR and $XDG_RUNTIME_DIR in a disposable folder. The last class
is a tripwire for the rest of the code.
"""
import os
from pathlib import Path
import signal
import stat
import subprocess
import tempfile
import time
import unittest

ROOT = Path(os.environ.get("HELLO_LOCK_TEST_ROOT", Path(__file__).resolve().parents[1]))
HARNESS = ROOT / "typing" / "harness" / "run.sh"

RECORDER = r'''#!/usr/bin/env python3
# gpu-screen-recorder stand-in: "records" until a signal stops it. Like the
# real one it sets its own handlers: a background job starts with INT ignored,
# and a plain sh script could never trap it. "stubborn" ignores both signals.
import os, signal, sys, time
state = os.environ["STUB_STATE"]
with open(os.path.join(state, "recorder.pid"), "w") as f:
    f.write(str(os.getpid()))
with open(sys.argv[sys.argv.index("-o") + 1], "w") as f:
    f.write("raw\n")
with open(os.path.join(state, "recorder.fd9"), "w") as f:  # the harness lock's descriptor
    f.write("open" if os.path.exists("/proc/self/fd/9") else "closed")
stubborn = os.path.exists(os.path.join(state, "stubborn"))
def stop(number, _frame):
    if stubborn:
        return
    with open(os.path.join(state, "recorder.stopped"), "w") as f:
        f.write(signal.Signals(number).name)
    sys.exit(0)
signal.signal(signal.SIGINT, stop)
signal.signal(signal.SIGTERM, stop)
while True:
    time.sleep(0.05)
'''
QS = r'''#!/bin/sh
echo "WARN stand-in effect $HL_EFFECT"
if [ -e /proc/$$/fd/9 ]; then echo open; else echo closed; fi > "$STUB_STATE/qs.fd9"
[ -e "$STUB_STATE/hang" ] && { echo started > "$STUB_STATE/qs.started"; sleep 30; }
exit 0
'''
FFMPEG = r'''#!/bin/sh
for last in "$@"; do :; done
echo encoded > "$last"
'''


class Harness(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(self.kill_leftover_recorder)  # runs before the folder goes
        self.base = Path(self.tmp.name)
        self.shared = self.base / "shared-tmp"      # stands in for /tmp
        self.runtime = self.base / "runtime"
        self.state = self.base / "state"
        stubs = self.base / "stubs"
        for folder in (self.shared, self.state, stubs):
            folder.mkdir()
        self.runtime.mkdir(mode=0o700)
        for name, text in (("gpu-screen-recorder", RECORDER), ("qs", QS), ("ffmpeg", FFMPEG)):
            (stubs / name).write_text(text)
            (stubs / name).chmod(0o700)
        self.env = {"PATH": "%s:/usr/bin:/bin" % stubs, "HOME": str(self.base / "home"),
                    "TMPDIR": str(self.shared), "XDG_RUNTIME_DIR": str(self.runtime),
                    "STUB_STATE": str(self.state)}
        # What another user could have left behind: the old fixed folder, with
        # the lock, the log and the recording pointing at files of ours.
        self.victims = {}
        planted = self.shared / "hl"
        planted.mkdir()
        planted.chmod(0o777)
        for name in ("fx-harness.lock", "fx-cells.log", "fx-cells.mp4", "fx-cells-sheet.png"):
            victim = self.base / ("victim-" + name)
            victim.write_text("precious " + name)
            (planted / name).symlink_to(victim)
            self.victims[victim] = "precious " + name
        self.planted = planted

    def kill_leftover_recorder(self):
        # A failing run must not leave a stand-in recorder looping forever.
        try:
            os.kill(int((self.state / "recorder.pid").read_text()), signal.SIGKILL)
        except (OSError, ValueError):
            pass

    def source(self):
        return HARNESS.read_text()

    def run_harness(self, *args, env=None):
        # The old script ignored $TMPDIR and wrote to the machine's real /tmp/hl.
        # Refuse to run that here; the test fails on it all the same.
        self.assertNotIn("/tmp/", self.source(), "the harness names a fixed path in /tmp")
        return subprocess.run(["bash", str(HARNESS), *args], env=env or self.env, cwd=self.base,
                              capture_output=True, text=True, timeout=60)

    def result_folders(self):
        return sorted(p for p in self.shared.iterdir() if p != self.planted)

    def assert_victims_untouched(self):
        for victim, text in self.victims.items():
            self.assertEqual(victim.read_text(), text)
        self.assertEqual(sorted(p.name for p in self.planted.iterdir()),
                         ["fx-cells-sheet.png", "fx-cells.log", "fx-cells.mp4", "fx-harness.lock"])

    def test_planted_folder_and_symlinks_are_never_written_through(self):
        result = self.run_harness("cells", "/logo.svg")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_victims_untouched()
        (folder,) = self.result_folders()
        self.assertTrue(folder.name.startswith("hello-lock-fx."))
        self.assertEqual(stat.S_IMODE(folder.lstat().st_mode), 0o700)
        self.assertEqual(sorted(p.name for p in folder.iterdir()),
                         ["fx-cells-crop.mp4", "fx-cells-sheet.png", "fx-cells.log", "fx-cells.mp4"])
        self.assertIn("video: %s/fx-cells-crop.mp4" % folder, result.stdout)
        self.assertIn("log: %s/fx-cells.log" % folder, result.stdout)
        self.assertIn("WARN stand-in effect", result.stdout)
        # INT, so the real recorder finishes the video before it is cropped.
        self.assertEqual((self.state / "recorder.stopped").read_text(), "SIGINT")
        self.assert_gone(int((self.state / "recorder.pid").read_text()))
        self.assertEqual([p.name for p in self.runtime.iterdir()], ["hello-lock-fx-harness.lock"])

    def assert_gone(self, pid):
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_the_recorder_and_the_window_never_hold_the_lock(self):
        # Otherwise a recorder orphaned by a killed script keeps the lock and
        # every later run waits forever.
        self.assertEqual(self.run_harness("cells").returncode, 0)
        self.assertEqual((self.state / "recorder.fd9").read_text(), "closed")
        self.assertEqual((self.state / "qs.fd9").read_text().strip(), "closed")

    def test_an_orphaned_recorder_does_not_block_the_next_run(self):
        (self.state / "stubborn").write_text("")
        process = subprocess.Popen(["bash", str(HARNESS), "cells"], env=self.env, cwd=self.base,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 20
        while not (self.state / "recorder.pid").exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        orphan = int((self.state / "recorder.pid").read_text())
        process.kill()  # SIGKILL: no trap runs, the recorder is left behind
        process.wait()
        os.kill(orphan, 0)  # still running
        (self.state / "stubborn").unlink()
        (self.state / "recorder.pid").unlink()
        self.addCleanup(lambda: os.kill(orphan, signal.SIGKILL))
        result = self.run_harness("cells")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_victims_untouched()

    def test_a_recorder_that_ignores_signals_is_killed_not_waited_on(self):
        (self.state / "stubborn").write_text("")
        started = time.monotonic()
        result = self.run_harness("cells")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(time.monotonic() - started, 30)
        self.assertFalse((self.state / "recorder.stopped").exists())
        self.assert_gone(int((self.state / "recorder.pid").read_text()))
        (folder,) = self.result_folders()
        self.assertTrue((folder / "fx-cells-crop.mp4").exists())
        self.assert_victims_untouched()

    def test_each_run_gets_its_own_folder_and_the_lock_is_reused(self):
        first = self.run_harness("cells")
        second = self.run_harness("cells", "--reduced")
        self.assertEqual((first.returncode, second.returncode), (0, 0), first.stderr + second.stderr)
        folders = self.result_folders()
        self.assertEqual(len(folders), 2)
        self.assertEqual(sorted(len(list(f.glob("fx-cells-reduced*"))) for f in folders), [0, 4])
        self.assert_victims_untouched()

    def test_lock_already_holding_data_is_not_truncated(self):
        lock = self.runtime / "hello-lock-fx-harness.lock"
        lock.write_text("kept")
        self.assertEqual(self.run_harness("cells").returncode, 0)
        self.assertEqual(lock.read_text(), "kept")

    def test_refuses_a_runtime_folder_others_could_use(self):
        open_folder = self.base / "open-runtime"
        open_folder.mkdir()
        open_folder.chmod(0o777)
        link = self.base / "runtime-link"
        link.symlink_to(self.runtime, target_is_directory=True)
        for value in (None, "", "relative", str(self.base / "missing"), str(open_folder), str(link)):
            with self.subTest(runtime=value):
                env = dict(self.env)
                env.pop("XDG_RUNTIME_DIR")
                if value is not None:
                    env["XDG_RUNTIME_DIR"] = value
                result = self.run_harness("cells", env=env)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn("XDG_RUNTIME_DIR", result.stderr)
                self.assertEqual(self.result_folders(), [])
                self.assertFalse((self.state / "recorder.pid").exists())
                self.assertEqual(list(open_folder.iterdir()), [])
        self.assert_victims_untouched()

    def test_effect_name_cannot_leave_the_folder(self):
        for name in ("../cells", "a/b", "", "Cells", "x y", "-o", "--reduced", "-"):
            with self.subTest(name=name):
                result = self.run_harness(name)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(self.result_folders(), [])
        self.assertEqual(self.run_harness().returncode, 2)

    def test_interrupted_run_stops_the_recorder_and_keeps_nothing(self):
        self.assertNotIn("/tmp/", self.source())
        (self.state / "hang").write_text("")
        process = subprocess.Popen(["bash", str(HARNESS), "cells"], env=self.env, cwd=self.base,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   start_new_session=True)
        try:
            deadline = time.monotonic() + 20
            while not (self.state / "qs.started").exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue((self.state / "qs.started").exists())
            recorder = int((self.state / "recorder.pid").read_text())
            os.killpg(process.pid, signal.SIGINT)  # Ctrl+C reaches the whole group
            self.assertEqual(process.wait(timeout=20), 130)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        self.assert_gone(recorder)
        self.assertEqual(self.result_folders(), [])
        self.assert_victims_untouched()


class FixedSharedPaths(unittest.TestCase):
    """A tripwire: every file that names a path in a folder other users can
    write to has to be listed here, with the reason it is safe. Scripts, QML,
    tests and docs are all scanned (a README command gets pasted and run)."""

    SHARED = ("/tmp", "/var/tmp", "/dev/shm")
    TEXT = (".py", ".sh", ".qml", ".js", ".json", ".jsonc", ".service", ".md", ".txt", ".conf")

    REVIEWED = {
        "bin/hello-lock-doctor":
            "reads only: lists your own leftover captures (owned, regular, known names)",
        "bin/hello-status":
            "reads the bar's update database only if the folder is your own and private",
        "tests/vm/guest-cachyos.py":
            "root in a disposable installer guest; O_NOFOLLOW and an owner check",
        "tests/test_hostile_names.py":
            "test data: redirects the old /tmp patterns into a disposable folder",
        "tests/test_shared_tmp.py":
            "this tripwire and its planted stand-in for /tmp",
        "CHANGELOG.md": "describes the fixes",
        "README.md": "says captures never use shared /tmp",
        "docs/standalone.md": "says state never uses shared /tmp",
        "docs/code-review-2026-10-25.md": "history: the fixed screenshot fallback",
    }

    @staticmethod
    def project_files():
        """The project's files: tracked or new, never ones git ignores (a
        private local guide, build output). Without git (an archive of the
        tree), every file."""
        try:
            listed = subprocess.run(
                ["git", "-C", str(ROOT), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                capture_output=True, check=True, timeout=30).stdout
        except (OSError, subprocess.SubprocessError):
            return list(ROOT.rglob("*"))
        return [ROOT / os.fsdecode(name) for name in listed.split(b"\0") if name]

    def test_every_file_naming_a_shared_folder_is_reviewed(self):
        named = set()
        for path in self.project_files():
            relative = path.relative_to(ROOT)
            if not path.is_file() or path.is_symlink() or relative.parts[0].startswith("."):
                continue
            if "__pycache__" in relative.parts:
                continue
            if path.suffix not in self.TEXT and relative.parts[0] != "bin":
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            if any(word in text for word in self.SHARED):
                named.add(str(relative))
        self.assertEqual(named, set(self.REVIEWED))

    def test_scripts_that_take_a_private_folder_never_name_shared_ones(self):
        for script in ("typing/harness/run.sh", "bin/hello-snapshot", "standalone/runtime.py",
                       "bin/hello-lock-install", "bin/hello-lock-pam", "sounds/README.md"):
            with self.subTest(script=script):
                text = (ROOT / script).read_text()
                self.assertFalse([w for w in self.SHARED if w in text])


if __name__ == "__main__":
    unittest.main()
