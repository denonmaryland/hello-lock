"""The VM lab's downloads are bounded in size and total time (0.6.9).

From the marketplace review of 0.6.8 (omacom/omarchy-plugin-marketplace#14051,
Low): tests/vm/tools.py wrote 1 MiB chunks to the cache with no total cap or
deadline, and lab.py read the Arch mirror listing and the key README whole.
A server could fill the disk or memory before any checksum or signature was
checked, or keep a transfer open by sending slowly. Now every download has a
byte ceiling (the exact size where pacman knows it), one total deadline,
an HTTPS-only final URL and a free-space reserve.

No network: urlopen, the clock and the disk-usage call are stand-ins.
"""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests/vm"))
spec = importlib.util.spec_from_file_location("lab_tools", ROOT / "tests/vm/tools.py")
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)

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
        patch = mock.patch.object(tools.urllib.request, "urlopen", return_value=response)
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
        self.assertEqual(self.opened.call_args.kwargs["timeout"], 10)
        self.serve(Response([b"ok"], self.clock))
        self.fetch((1024, 600), name="other")
        self.assertEqual(self.opened.call_args.kwargs["timeout"], tools.READ_TIMEOUT)

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

    def test_urlopen_is_used_only_by_the_bounded_readers(self):
        for path in self.FILES:
            text = path.read_text()
            with self.subTest(file=path.name):
                if path.name == "tools.py":
                    self.assertEqual(text.count("urlopen("), 1)  # in _stream
                elif path.name == "guest-cachyos.py":
                    self.assertEqual(text.count("urlopen("), 1)  # in bounded_download
                    self.assertIn("def bounded_download(", text)
                else:
                    self.assertNotIn("urlopen(", text)
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


if __name__ == "__main__":
    unittest.main()
