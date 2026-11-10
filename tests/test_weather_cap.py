"""The weather reply is remote data: hello-status must bound it before reading it.

Regression tests for the marketplace review finding on 0.6.6: the helper
captured the whole wttr.in reply and only then looked at it, in the unlock
greeting and in the detached refresh alike, so a huge reply cost that much
memory. Everything here uses a disposable home and either a fake `curl` or a
loopback server. Nothing reaches wttr.in and no live configuration is read.
"""
import http.server
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(os.environ.get("HELLO_LOCK_TEST_ROOT", Path(__file__).resolve().parents[1]))
STATUS = ROOT / "bin" / "hello-status"

REPLY = "72°F|Sunny".encode()
MIB = 1024 * 1024
HUGE = 8 * MIB
# What an honest reader may let a writer get rid of before it is stopped: the
# few bytes it reads plus one pipe buffer (64 KiB by default, 1 MiB at most
# without privileges). The old helper accepted all of HUGE.
ACCEPTED_MAX = MIB

# A stand-in for curl that ignores every limit it is given: it writes a valid
# reply padded with spaces to FAKE_CURL_BYTES, and records its arguments and
# how many bytes the reader has let it write so far.
FAKE_CURL = r'''#!%s -I
import json, os, sys
log = os.environ["FAKE_CURL_LOG"]
with open(os.path.join(log, "%%d.argv" %% os.getpid()), "w") as f:
    json.dump(sys.argv[1:], f)
fd = os.open(os.path.join(log, "%%d.accepted" %% os.getpid()), os.O_WRONLY | os.O_CREAT, 0o600)
total = int(os.environ["FAKE_CURL_BYTES"])
head = "72°F|Sunny".encode()
sent = os.write(1, head[:total])
os.pwrite(fd, b"%%020d" %% sent, 0)
block = b" " * 4096
while sent < total:
    sent += os.write(1, block[:total - sent])
    os.pwrite(fd, b"%%020d" %% sent, 0)
'''


def load_status():
    loader = importlib.machinery.SourceFileLoader("hello_status", str(STATUS))
    spec = importlib.util.spec_from_loader("hello_status", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class Disposable(unittest.TestCase):
    """A private home and cache; the helper runs as its own process."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.cache = self.base / "cache" / "weather.json"
        (self.base / "home").mkdir()
        self.env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": str(self.base / "home"),
            "LANG": "en_US.UTF-8",
            "HELLO_STATUS_WEATHER_CACHE": str(self.cache),
            "HELLO_STATUS_WEATHER_URL": "http://127.0.0.1:9/unused",
            "CHECKUPDATES_DB": str(self.base / "no-updates-db"),
        }

    def tearDown(self):
        # A failed greeting fetch starts a detached refresh. Let it finish
        # before its cache folder is removed.
        self.wait_for_refresh()
        self.tmp.cleanup()

    def wait_for_refresh(self):
        lock = Path(str(self.cache) + ".refreshing")
        deadline = time.monotonic() + 20
        while lock.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertFalse(lock.exists(), "the detached refresh did not finish")

    def helper(self, *args):
        return subprocess.run([sys.executable, "-I", str(STATUS), *args], env=self.env,
                              capture_output=True, text=True, timeout=30)

    def greeting(self):
        result = self.helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        status = json.loads(result.stdout)
        self.wait_for_refresh()
        return status["temp"], status["condition"]

    def refresh(self):
        result = self.helper("--refresh-weather")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.wait_for_refresh()
        return self.cached()

    def cached(self):
        try:
            saved = json.loads(self.cache.read_text())
        except FileNotFoundError:
            return None
        return saved["temp"], saved["condition"]


class FakeCurl(Disposable):
    """The cap holds even when curl itself does not enforce it."""

    def setUp(self):
        super().setUp()
        self.log = self.base / "curl-log"
        self.log.mkdir()
        fake = self.base / "bin" / "curl"
        fake.parent.mkdir()
        fake.write_text(FAKE_CURL % sys.executable)
        fake.chmod(0o700)
        self.env["PATH"] = str(fake.parent) + os.pathsep + self.env["PATH"]
        self.env["FAKE_CURL_LOG"] = str(self.log)
        self.reply_bytes(len(REPLY))

    def reply_bytes(self, count):
        self.env["FAKE_CURL_BYTES"] = str(count)

    def runs(self):
        """One (arguments, bytes accepted by the reader) pair per curl run."""
        return [(json.loads(path.read_text()), int(path.with_suffix(".accepted").read_text()))
                for path in sorted(self.log.glob("*.argv"))]

    def test_greeting_stops_reading_an_oversized_reply(self):
        self.reply_bytes(HUGE)
        shown = self.greeting()
        runs = self.runs()
        for _, accepted in runs:
            self.assertLessEqual(accepted, ACCEPTED_MAX)
        # The greeting's own fetch, then the detached refresh it falls back to.
        self.assertEqual(len(runs), 2)
        self.assertEqual(shown, (None, None))
        self.assertIsNone(self.cached())

    def test_detached_refresh_stops_reading_an_oversized_reply(self):
        self.reply_bytes(HUGE)
        saved = self.refresh()
        runs = self.runs()
        self.assertEqual(len(runs), 1)
        self.assertLessEqual(runs[0][1], ACCEPTED_MAX)
        self.assertIsNone(saved)

    def test_limit_is_exact_and_padding_cannot_get_past_it(self):
        limit = load_status().WEATHER_MAX_BYTES
        self.reply_bytes(limit)
        self.assertEqual(self.refresh(), ("72°F", "Sunny"))
        self.cache.unlink()
        self.reply_bytes(limit + 1)
        self.assertIsNone(self.refresh())
        self.assertEqual(self.greeting(), (None, None))

    def test_curl_is_given_the_same_limit_on_both_paths(self):
        limit = str(load_status().WEATHER_MAX_BYTES)
        self.assertEqual(self.refresh(), ("72°F", "Sunny"))
        self.cache.unlink()
        self.assertEqual(self.greeting(), ("72°F", "Sunny"))
        runs = self.runs()
        self.assertEqual(len(runs), 2)
        for argv, _ in runs:
            self.assertEqual(argv[argv.index("--max-filesize") + 1], limit)
            self.assertNotIn("-L", argv)
            self.assertNotIn("--compressed", argv)


class Replies(http.server.BaseHTTPRequestHandler):
    """/ok, /declared (honest Content-Length) and /streamed (no length)."""
    padded = REPLY + b" " * (64 * 1024)

    def do_GET(self):
        kind = self.path.split("/")[1].split("?")[0]
        body = REPLY if kind == "ok" else self.padded
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        if kind != "streamed":
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except OSError:
            pass  # The client hung up at its limit.

    def log_message(self, *args):
        pass


@unittest.skipUnless(shutil.which("curl"), "curl is not installed")
class RealCurl(Disposable):
    """The real curl against a loopback server."""

    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Replies)
        cls.server.daemon_threads = True
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def serve(self, kind):
        self.env["HELLO_STATUS_WEATHER_URL"] = "http://127.0.0.1:%d/%s" % (
            self.server.server_address[1], kind)

    def test_ordinary_reply_still_reaches_the_greeting_and_the_cache(self):
        self.serve("ok")
        self.assertEqual(self.refresh(), ("72°F", "Sunny"))
        self.cache.unlink()
        self.assertEqual(self.greeting(), ("72°F", "Sunny"))
        self.assertEqual(self.cached(), ("72°F", "Sunny"))

    def test_oversized_reply_is_no_weather_on_both_paths(self):
        # Trailing spaces used to be read in full and then stripped, so this
        # reply was shown as weather.
        for kind in ("declared", "streamed"):
            with self.subTest(kind=kind):
                self.serve(kind)
                self.assertIsNone(self.refresh())
                self.assertEqual(self.greeting(), (None, None))
                self.assertIsNone(self.cached())


class RunBounded(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.status = load_status()

    def bounded(self, script, limit=16, timeout=5.0):
        return self.status.run_bounded([sys.executable, "-I", "-c", script], limit, timeout)

    def test_output_up_to_the_limit_is_returned_with_the_exit_code(self):
        self.assertEqual(self.bounded("print('x' * 15)"), (0, b"x" * 15 + b"\n"))
        self.assertEqual(self.bounded("import sys; sys.exit(22)"), (22, b""))

    def test_one_byte_over_the_limit_is_refused(self):
        self.assertIsNone(self.bounded("print('x' * 16)"))

    def test_program_that_cannot_start_is_refused(self):
        self.assertIsNone(self.status.run_bounded(["/nonexistent/hello-lock-curl"], 16, 1.0))

    def test_silent_program_is_killed_at_the_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            pidfile = Path(directory) / "pid"
            script = ("import os, time; open(%r, 'w').write(str(os.getpid()));"
                      " time.sleep(60)" % str(pidfile))
            started = time.monotonic()
            self.assertIsNone(self.bounded(script, timeout=1.0))
            self.assertLess(time.monotonic() - started, 5)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pidfile.read_text()), 0)

    def test_endless_writer_is_killed_at_the_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            pidfile = Path(directory) / "pid"
            script = ("import os, sys; open(%r, 'w').write(str(os.getpid()));"
                      " [sys.stdout.buffer.write(b'x' * 4096) for _ in iter(int, 1)]"
                      % str(pidfile))
            started = time.monotonic()
            self.assertIsNone(self.bounded(script, timeout=30.0))
            self.assertLess(time.monotonic() - started, 10)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pidfile.read_text()), 0)


if __name__ == "__main__":
    unittest.main()
