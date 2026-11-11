"""The VM lab's downloads are bounded in size and total time (0.6.9).

From the marketplace review of 0.6.8 (omacom/omarchy-plugin-marketplace#14051,
Low): tests/vm/tools.py wrote 1 MiB chunks to the cache with no total cap or
deadline, and lab.py read the Arch mirror listing and the key README whole.
A server could fill the disk or memory before any checksum or signature was
checked, or keep a transfer open by sending slowly. Now every download has a
byte ceiling (the exact size where pacman knows it), one total deadline,
an HTTPS-only final URL and a free-space reserve.

Two kinds of test. Bounded: the connection, the clock and the disk-usage call
are stand-ins. RealSockets: real sockets on this machine and the real clock,
because a stand-in response returns after every chunk while a real buffered
response waits for all it asked for (Codex T146: a byte every 0.03 s kept a
0.15 s download going for 1.18 s). No network either way.
"""
import http.client
import importlib.util
import re
from pathlib import Path
import socket
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests/vm"))
spec = importlib.util.spec_from_file_location("lab_tools", ROOT / "tests/vm/tools.py")
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)
spec = importlib.util.spec_from_file_location("guest_cachyos", ROOT / "tests/vm/guest-cachyos.py")
guest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guest)

GiB = 1024 ** 3


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


class Response:
    """An HTTP response stand-in: `chunks` bytes objects, read one per call.
    Each read moves `clock` on by `per_read` seconds."""

    def __init__(self, chunks, clock, per_read=0.0, length=None, url="https://example.test/x"):
        # Read lazily: `chunks` may be endless. (An earlier list() here ran
        # the machine out of memory.)
        self.source = iter(chunks)
        self.pending = b""
        self.clock = clock
        self.per_read = per_read
        self.headers = {} if length is None else {"Content-Length": str(length)}
        self.url = url
        self.reads = 0
        self.asked = []

    def geturl(self):
        return self.url

    def read(self, size):
        self.reads += 1
        self.asked.append(size)
        self.clock.now += self.per_read
        if self.reads > 100000:  # a runaway reader fails, it never eats memory
            raise AssertionError("the reader never stopped")
        if not self.pending:
            self.pending = next(self.source, b"")
        chunk, self.pending = self.pending[:size], self.pending[size:]
        return chunk

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def endless(size=64 * 1024):
    while True:
        yield b"x" * size


class Bounded(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)
        self.clock = Clock()
        self.free = [100 * GiB]
        patches = [mock.patch.object(tools.time, "monotonic", self.clock),
                   mock.patch.object(tools, "free_bytes", lambda _path: self.free[0])]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def serve(self, response):
        patch = mock.patch.object(tools, "_open", side_effect=lambda url, timeout, deadline: response)
        self.opened = patch.start()
        self.addCleanup(patch.stop)
        return response

    def fetch(self, limits, exact=None, name="file"):
        destination = self.dir / name
        tools.fetch("https://example.test/" + name, destination, limits, exact=exact)
        return destination

    def assertNothingLeft(self):
        self.assertEqual(sorted(p.name for p in self.dir.iterdir()), [])

    def test_a_normal_download_is_kept(self):
        self.serve(Response([b"a" * 1000, b"b" * 24], self.clock))
        destination = self.fetch((1024, 60))
        self.assertEqual(destination.read_bytes(), b"a" * 1000 + b"b" * 24)
        self.assertEqual(sorted(p.name for p in self.dir.iterdir()), ["file"])

    def test_one_byte_over_the_ceiling_is_refused_and_removed(self):
        self.serve(Response([b"a" * 1025], self.clock))
        with self.assertRaises(tools.DownloadError):
            self.fetch((1024, 60))
        self.assertNothingLeft()

    def test_an_endless_response_stops_at_the_ceiling(self):
        response = self.serve(Response(endless(), self.clock))
        with self.assertRaises(tools.DownloadError):
            self.fetch((tools.MiB, 60))
        self.assertNothingLeft()
        # Each read asks only for what's left up to one byte past the
        # ceiling, so it stops right after the ceiling.
        self.assertEqual(response.asked[-1], 1)
        self.assertEqual(response.reads, tools.MiB // (64 * 1024) + 1)

    def test_a_declared_length_over_the_ceiling_is_refused_before_reading(self):
        response = self.serve(Response([b"a"], self.clock, length=2048))
        with self.assertRaises(tools.DownloadError):
            self.fetch((1024, 60))
        self.assertEqual(response.reads, 0)
        self.assertNothingLeft()

    def test_slow_progress_is_stopped_at_the_total_deadline(self):
        # A byte every 20 s: each read is within the socket timeout, the
        # transfer as a whole is not.
        response = self.serve(Response(iter([b"x"] * 1000), self.clock, per_read=20))
        with self.assertRaises(tools.DownloadError):
            self.fetch((tools.MiB, 60))
        self.assertLessEqual(response.reads, 4)
        self.assertNothingLeft()

    def test_the_socket_timeout_never_exceeds_the_deadline(self):
        self.serve(Response([b"ok"], self.clock))
        self.fetch((1024, 10))
        self.assertEqual(self.opened.call_args.args[1], 10)
        self.serve(Response([b"ok"], self.clock))
        self.fetch((1024, 600), name="other")
        self.assertEqual(self.opened.call_args.args[1], tools.READ_TIMEOUT)

    def test_an_exact_size_is_required(self):
        for chunks, exact in (([b"a" * 99], 100), ([b"a" * 101], 100)):
            with self.subTest(got=len(chunks[0])):
                self.serve(Response(chunks, self.clock))
                with self.assertRaises(tools.DownloadError):
                    self.fetch((tools.MiB, 60), exact=exact)
                self.assertNothingLeft()
        self.serve(Response([b"a" * 100], self.clock, length=200))
        with self.assertRaises(tools.DownloadError):
            self.fetch((tools.MiB, 60), exact=100)
        self.serve(Response([b"a" * 100], self.clock, length=100))
        self.assertEqual(self.fetch((tools.MiB, 60), exact=100).stat().st_size, 100)

    def test_an_exact_size_cannot_raise_the_ceiling(self):
        with self.assertRaises(tools.DownloadError):
            self.fetch((1024, 60), exact=4096)
        with self.assertRaises(tools.DownloadError):
            self.fetch((1024, 60), exact=0)

    def test_free_space_is_kept(self):
        self.free[0] = tools.RESERVE + 1000
        with self.assertRaises(tools.DownloadError):  # not enough to start
            self.fetch((tools.MiB, 60))
        # Enough to start, then the disk fills from elsewhere mid-download.
        self.free[0] = tools.RESERVE + 2 * tools.MiB
        response = Response(endless(256 * 1024), self.clock)
        original = response.read

        def read(size):
            self.free[0] -= 512 * 1024
            return original(size)
        response.read = read
        self.serve(response)
        with self.assertRaises(tools.DownloadError):
            self.fetch((100 * tools.MiB, 60))
        self.assertNothingLeft()

    def test_https_only_including_redirects(self):
        with self.assertRaises(ValueError):
            tools.fetch("http://example.test/x", self.dir / "x", (1024, 60))
        self.serve(Response([b"a"], self.clock, url="http://elsewhere.test/x"))
        with self.assertRaises(tools.DownloadError):
            self.fetch((1024, 60))
        self.assertNothingLeft()

    def test_read_url_is_bounded_too(self):
        self.serve(Response([b"<html>", b"listing"], self.clock))
        self.assertEqual(tools.read_url("https://example.test/"), b"<html>listing")
        self.serve(Response(endless(), self.clock))
        with self.assertRaises(tools.DownloadError):
            tools.read_url("https://example.test/")
        self.serve(Response(iter([b"x"] * 1000), self.clock, per_read=20))
        with self.assertRaises(tools.DownloadError):
            tools.read_url("https://example.test/")

    def test_limits_fit_the_real_files(self):
        self.assertGreaterEqual(tools.IMAGE[0], 1 * GiB)      # Ubuntu's is 0.86 GiB
        self.assertLessEqual(tools.IMAGE[0], 4 * GiB)
        self.assertLessEqual(tools.SIGNATURE[0], 1024 * 1024)
        self.assertLessEqual(tools.METADATA[0], 16 * 1024 * 1024)
        for _, seconds in (tools.IMAGE, tools.SIGNATURE, tools.METADATA):
            self.assertLessEqual(seconds, 3600)


class EveryCaller(unittest.TestCase):
    """No download in the lab goes around the bounded reader."""

    FILES = sorted((ROOT / "tests/vm").glob("*.py"))

    def test_every_connection_goes_through_a_deadline(self):
        for path in self.FILES:
            text = path.read_text()
            with self.subTest(file=path.name):
                # No urlopen anywhere: the openers that hand each socket to a
                # deadline are the only way out.
                self.assertNotIn("urlopen(", text)
                if path.name == "tools.py":
                    self.assertEqual(text.count("build_opener("), 1)
                    calls = re.findall(r"(?<!def )\b_open\(", text)
                    self.assertEqual(len(calls), 1)   # only in _stream
                elif path.name == "guest-cachyos.py":
                    self.assertEqual(text.count("build_opener("), 1)
                    self.assertIn("def bounded_download(", text)
                else:
                    self.assertNotIn("build_opener(", text)
                # No whole read of a network response (local tar entries are fine).
                self.assertNotRegex(text, r"response\.read\(\)")

    def test_every_fetch_names_its_limits(self):
        import re
        for path in self.FILES:
            for call in re.findall(r"(?<!def )\bfetch\(([^)]*)\)", path.read_text()):
                with self.subTest(file=path.name, call=call):
                    self.assertGreaterEqual(call.count(",") + 1, 3, call)

    def test_packages_use_pacmans_exact_size(self):
        self.assertIn('exact=int(meta["CSIZE"])', (ROOT / "tests/vm/tools.py").read_text())


class Server:
    """The far end of a real connection, sending on a script in a thread."""

    def __init__(self, sock, script):
        self.sock = sock
        self.thread = threading.Thread(target=self.run, args=(script,), daemon=True)
        self.thread.start()

    def run(self, script):
        try:
            for data, pause in script:
                if data:
                    self.sock.sendall(data)
                time.sleep(pause)
        except OSError:
            pass                # the reader shut the connection: expected

    def stop(self):
        self.thread.join(timeout=10)
        self.sock.close()


HEAD = b"HTTP/1.1 200 OK\r\nContent-Length: 40\r\n\r\n"
TRICKLE_BODY = [(HEAD, 0)] + [(b"x", 0.03)] * 40           # Codex's case: 1.2 s
TRICKLE_HEADERS = [(b"HTTP/1.1 200 OK\r\n", 0)] + [(b"X", 0.03)] * 100
SILENT = [(b"", 5)]
WHOLE = [(HEAD + b"x" * 40, 0)]
DEADLINE = 0.15
# Generous: the point is "about the deadline", not 1.2 s or 5 s.
SLACK = 0.6


class RealSockets(unittest.TestCase):
    """Both readers, over real sockets, end at their deadline."""

    def readers(self):
        return {"tools": lambda: tools.read_url("https://example.test/x", (1024, DEADLINE)),
                "guest": lambda: guest.bounded_download("https://example.test/x", 1024, DEADLINE)}

    def pair(self, script):
        client, far = socket.socketpair()
        # A long per-receive timeout: only the deadline can end things early.
        client.settimeout(10)
        server = Server(far, script)
        self.addCleanup(server.stop)
        self.addCleanup(client.close)
        return client

    def response_over(self, client, track):
        # What _open does, minus TLS: hand the socket to the deadline first,
        # then read the status line and headers (so a trickle there counts).
        track(client)
        response = http.client.HTTPResponse(client, url="https://example.test/x")
        response.begin()
        response.url = "https://example.test/x"
        return response

    def patched(self, name, script):
        client = self.pair(script)
        if name == "tools":
            return mock.patch.object(tools, "_open", lambda url, timeout, deadline:
                                     self.response_over(client, deadline.track))
        return mock.patch.object(guest, "_open_tracked", lambda url, timeout, track, remaining:
                                 self.response_over(client, track))

    def timed(self, name, script):
        with self.patched(name, script):
            started = time.monotonic()
            try:
                result = self.readers()[name]()
            except (tools.DownloadError, RuntimeError) as error:
                result = error
            return result, time.monotonic() - started

    def test_a_trickling_body_ends_at_the_deadline(self):
        for name in ("tools", "guest"):
            with self.subTest(reader=name):
                result, took = self.timed(name, TRICKLE_BODY)
                self.assertIsInstance(result, RuntimeError)
                self.assertIn("longer", str(result))
                self.assertLess(took, DEADLINE + SLACK)

    def test_trickling_headers_end_at_the_deadline(self):
        for name in ("tools", "guest"):
            with self.subTest(reader=name):
                result, took = self.timed(name, TRICKLE_HEADERS)
                self.assertIsInstance(result, (RuntimeError, OSError, http.client.HTTPException))
                self.assertLess(took, DEADLINE + SLACK)

    def test_a_silent_server_ends_at_the_deadline_not_the_socket_timeout(self):
        for name in ("tools", "guest"):
            with self.subTest(reader=name):
                result, took = self.timed(name, [(HEAD, 0)] + SILENT)
                self.assertIsInstance(result, RuntimeError)
                self.assertLess(took, DEADLINE + SLACK)

    def test_a_prompt_answer_is_read_whole(self):
        for name in ("tools", "guest"):
            with self.subTest(reader=name):
                result, _ = self.timed(name, WHOLE)
                self.assertEqual(result, b"x" * 40)

    def listener(self, hold=5):
        """A loopback server that accepts and then says nothing."""
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(4)
        self.addCleanup(server.close)
        accepted = []

        def accept():
            try:
                conn, _ = server.accept()
                accepted.append(conn)
                time.sleep(hold)
                conn.close()
            except OSError:
                pass
        threading.Thread(target=accept, daemon=True).start()
        return server.getsockname()[1], accepted

    def through_real_opener(self, name, addresses, socket_class=None):
        """Run a reader through the real opener and connect(), with getaddrinfo
        (and optionally socket.socket) replaced. Returns (error, seconds)."""
        patches = [mock.patch("socket.getaddrinfo", addresses if callable(addresses)
                              else (lambda *a, **k: addresses))]
        if socket_class is not None:
            patches.append(mock.patch("socket.socket", socket_class))
        started = time.monotonic()
        error = None
        for patch in patches:
            patch.start()
        try:
            self.readers()[name]()
        except Exception as caught:   # noqa: BLE001 - the type is checked below
            error = caught
        finally:
            for patch in reversed(patches):
                patch.stop()
        return error, time.monotonic() - started

    def test_the_real_opener_cuts_a_stuck_tls_handshake(self):
        """Through the real opener and TLS: the server accepts and says
        nothing. Only the deadline can end it (the socket timeout is 30 s)."""
        for name in ("tools", "guest"):
            with self.subTest(reader=name):
                port, accepted = self.listener()
                local = [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", ("127.0.0.1", port))]
                error, took = self.through_real_opener(name, local)
                self.assertIsInstance(error, (RuntimeError, OSError))
                self.assertLess(took, DEADLINE + SLACK)
                self.assertEqual(len(accepted), 1)   # it really connected

    def test_a_slow_name_lookup_ends_at_the_deadline(self):
        # Codex T150: getaddrinfo ran before the deadline was watched.
        def slow(*_args, **_kwargs):
            time.sleep(0.9)
            raise socket.gaierror("synthetic slow resolver")
        for name in ("tools", "guest"):
            with self.subTest(reader=name):
                error, took = self.through_real_opener(name, slow)
                self.assertIsInstance(error, RuntimeError)
                self.assertIn("longer", str(error))
                self.assertLess(took, DEADLINE + SLACK)

    def test_many_slow_addresses_share_one_deadline(self):
        # Codex T150: each address used to get the full per-try timeout.
        attempts = []

        class Stuck(socket.socket):
            def connect(self, address):
                attempts.append(self.gettimeout())
                time.sleep(self.gettimeout())
                raise TimeoutError("synthetic connect timeout")
        eight = [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", ("127.0.0.1", 1))] * 8
        for name in ("tools", "guest"):
            with self.subTest(reader=name):
                attempts.clear()
                error, took = self.through_real_opener(name, eight, Stuck)
                self.assertIsInstance(error, RuntimeError)
                self.assertIn("longer", str(error))
                self.assertLess(took, DEADLINE + SLACK)
                self.assertLessEqual(len(attempts), 2)
                self.assertTrue(all(timeout <= DEADLINE for timeout in attempts))

    def test_a_failed_address_falls_through_to_the_next(self):
        """Normal fallback still works: a refused address, then a live one."""
        for name in ("tools", "guest"):
            with self.subTest(reader=name):
                port, accepted = self.listener(hold=1)
                closed = socket.socket()
                closed.bind(("127.0.0.1", 0))
                dead = closed.getsockname()[1]
                closed.close()   # nothing listens there: refused
                pair = [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", ("127.0.0.1", dead)),
                        (socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", ("127.0.0.1", port))]
                self.through_real_opener(name, pair)
                self.assertEqual(len(accepted), 1)   # reached the second address

    def test_the_deadline_shuts_a_socket_tracked_after_it_passed(self):
        clock = tools.Deadline(0)
        time.sleep(0.05)
        a, b = socket.socketpair()
        self.addCleanup(a.close)
        self.addCleanup(b.close)
        a.settimeout(5)
        clock.track(a)
        started = time.monotonic()
        self.assertEqual(a.recv(10), b"")   # shut, not waiting 5 s
        self.assertLess(time.monotonic() - started, 1)
        clock.close()


if __name__ == "__main__":
    unittest.main()
