#!/usr/bin/env python3
"""Prepare private, signature-checked QEMU tools without modifying host packages."""
import base64
import hashlib
import http.client
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tarfile
import threading
import time
import urllib.request

PACKAGES = ("qemu-system-x86", "qemu-img", "qemu-hw-display-virtio-gpu",
            "qemu-hw-display-virtio-vga", "qemu-hw-display-virtio-vga-gl", "qemu-ui-egl-headless",
            "qemu-hw-display-virtio-gpu-gl", "qemu-hw-display-qxl", "libisoburn")


# Every download has a byte ceiling and one total deadline, checked while it
# is read: a socket timeout alone only bounds each read, so a server that
# keeps sending slowly could hold a transfer open forever, and one that keeps
# sending could fill the disk before any checksum or signature is checked.
# A ceiling is the exact size when a trusted one is known (pacman's CSIZE).
MiB = 1024 * 1024
IMAGE = (2048 * MiB, 30 * 60)       # official cloud images are 0.5-0.9 GiB
SIGNATURE = (64 * 1024, 60)
METADATA = (1 * MiB, 60)            # keys, checksum lists, mirror listings
PACKAGE_DEADLINE = 10 * 60
PACKAGE_MAX = 512 * MiB          # QEMU's largest piece is about 7 MiB
# Free space a download must leave on the cache's filesystem.
RESERVE = 2048 * MiB
READ_TIMEOUT = 30                   # per receive; Deadline bounds the whole
CHUNK = 64 * 1024


class DownloadError(RuntimeError):
    """A download went over its size or time limit, or wasn't HTTPS."""


class Deadline:
    """One wall-clock limit for a whole download: name lookup, connecting,
    TLS handshake, headers and body.

    A socket timeout restarts on every byte, and a buffered read waits for all
    the bytes it asked for, so a server sending a byte at a time could keep a
    download going long past any check made between reads. So when the limit
    passes, a timer shuts down every connection the download opened (through
    a duplicate of its socket): a receive that is blocked or trickling ends at
    once, in the TLS handshake, the headers or the body."""

    def __init__(self, seconds):
        self.ends = time.monotonic() + seconds
        self.expired = False
        self._lock = threading.Lock()
        self._sockets = []
        self._timer = threading.Timer(max(0.0, seconds), self._expire)
        self._timer.daemon = True
        self._timer.start()

    def track(self, sock):
        copy = sock.dup()   # survives the TLS wrapper detaching the original
        with self._lock:
            self._sockets.append(copy)
            if self.expired:
                _shut(copy)

    def _expire(self):
        with self._lock:
            self.expired = True
            for sock in self._sockets:
                _shut(sock)

    def remaining(self):
        return self.ends - time.monotonic()

    def check(self):
        if self.expired or self.remaining() <= 0:
            raise DownloadError("Download took longer than allowed")

    def close(self):
        self._timer.cancel()
        with self._lock:
            for sock in self._sockets:
                sock.close()
            self._sockets.clear()


def _shut(sock):
    try:
        sock.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass


class _HTTPSOnlyRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.startswith("https://"):
            raise DownloadError("Download was redirected away from HTTPS")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def resolve(host, port, deadline):
    """getaddrinfo, given up on when the deadline passes. The system resolver
    can't be interrupted, so it runs in a thread that is left to finish on
    its own (it ends at the resolver's own timeout)."""
    found = {}

    def lookup():
        try:
            found["addresses"] = socket.getaddrinfo(host, port, 0, socket.SOCK_STREAM)
        except OSError as error:
            found["error"] = error
    thread = threading.Thread(target=lookup, daemon=True)
    thread.start()
    thread.join(max(0.0, deadline.remaining()))
    if thread.is_alive():
        raise DownloadError("Download took longer than allowed")
    if "error" in found:
        raise found["error"]
    return found["addresses"]


def connect(address, timeout, source_address, deadline):
    """socket.create_connection within the deadline: the lookup, and each
    address tried in turn, get only the time that is left, and every socket
    is handed to the deadline before it connects."""
    host, port = address
    error = None
    for family, kind, proto, _name, target in resolve(host, port, deadline):
        deadline.check()
        sock = socket.socket(family, kind, proto)
        try:
            deadline.track(sock)
            sock.settimeout(max(0.001, min(timeout, deadline.remaining())))
            if source_address:
                sock.bind(source_address)
            sock.connect(target)
            sock.settimeout(timeout)
            return sock
        except OSError as failure:
            sock.close()
            error = failure
    deadline.check()
    raise error if error is not None else OSError("no address to connect to")


def _open(url, timeout, deadline):
    """urlopen, except every connection it makes (redirects too) is made by
    connect(), within the deadline, and redirects must stay on HTTPS."""
    class Connection(http.client.HTTPSConnection):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self._create_connection = (lambda address, timeout=READ_TIMEOUT, source_address=None:
                                       connect(address, timeout, source_address, deadline))

    class Handler(urllib.request.HTTPSHandler):
        def https_open(self, req):
            return self.do_open(Connection, req, context=self._context)

    return urllib.request.build_opener(Handler(), _HTTPSOnlyRedirects()).open(url, timeout=timeout)


def _stream(url, limit, deadline, write, exact=None, room=None):
    """Read url into write(chunk): never more than `limit` bytes, never past
    `deadline` seconds from the start of the connection to the last byte."""
    if not url.startswith("https://"):
        raise ValueError("Downloads require HTTPS")
    clock = Deadline(deadline)
    try:
        try:
            response = _open(url, min(READ_TIMEOUT, deadline), clock)
        except DownloadError:
            raise
        except OSError:
            clock.check()   # a connection the deadline cut is a timeout
            raise
        with response:
            if not response.geturl().startswith("https://"):
                raise DownloadError("Download was redirected away from HTTPS")
            declared = response.headers.get("Content-Length")
            if declared is not None and declared.isdigit():
                if int(declared) > limit or (exact is not None and int(declared) != exact):
                    raise DownloadError("Download is larger than allowed")
            # read1 returns what has arrived instead of waiting for all of it.
            read = getattr(response, "read1", response.read)
            total = 0
            while True:
                clock.check()
                try:
                    chunk = read(min(CHUNK, limit + 1 - total))
                except (OSError, http.client.HTTPException):
                    clock.check()
                    raise
                if not chunk:
                    break
                total += len(chunk)
                if total > limit:
                    raise DownloadError("Download is larger than allowed")
                if room is not None:
                    room(len(chunk))
                write(chunk)
            # A connection the deadline shut down also ends with no data.
            clock.check()
            if exact is not None and total != exact:
                raise DownloadError("Download is not the expected size")
            if declared is not None and declared.isdigit() and total != int(declared):
                raise DownloadError("Download ended early")
        return total
    finally:
        clock.close()


def free_bytes(path):
    return shutil.disk_usage(path).free


def fetch(url, destination, limits, exact=None):
    """Download url to destination, within `limits` (bytes, seconds) or the
    `exact` byte count. A partial file is removed on any failure."""
    limit, deadline = limits
    if exact is not None:
        if exact <= 0 or exact > limit:
            raise DownloadError("Expected size is outside the allowed range")
        limit = exact
    folder = destination.parent
    if free_bytes(folder) < limit + RESERVE:
        raise DownloadError("Not enough free space for this download")
    temporary = destination.with_suffix(destination.suffix + ".partial")

    def room(_size):
        if free_bytes(folder) < RESERVE:
            raise DownloadError("Download would leave too little free space")
    try:
        with temporary.open("wb") as output:
            _stream(url, limit, deadline, output.write, exact=exact, room=room)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def read_url(url, limits=METADATA):
    """A small response (a listing, a README) as bytes, within limits."""
    parts = []
    _stream(url, limits[0], limits[1], parts.append)
    return b"".join(parts)


def private_directory(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_symlink() or path.stat().st_uid != os.getuid():
        raise ValueError("Lab directory must be owned and not a symlink")
    path.chmod(0o700)


def checksum(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def prepare(cache):
    private_directory(cache)
    downloads = cache / "packages"
    private_directory(downloads)
    tools = cache / "tools"
    private_directory(tools)
    home = cache / "verification"
    private_directory(home)
    result = subprocess.run(["pacman", "-Sp", "--print-format", "%n %v %l", *PACKAGES],
                            capture_output=True, text=True, check=True)
    packages = [line.split(maxsplit=2) for line in result.stdout.splitlines() if line.strip()]
    wanted = {name for name, _, _ in packages}
    metadata = {}
    for database in Path("/var/lib/pacman/sync").glob("*.db"):
        with tarfile.open(database) as archive:
            for member in archive:
                if not member.name.endswith("/desc"):
                    continue
                data = archive.extractfile(member).read().decode()
                fields = dict(re.findall(r"%([A-Z0-9]+)%\n(.*?)(?=\n\n|\Z)", data, re.S))
                name = fields.get("NAME")
                if name in wanted and name not in metadata:
                    metadata[name] = fields
    for name, version, url in packages:
        meta = metadata[name]
        if meta["VERSION"] != version:
            raise ValueError("Package metadata version mismatch")
        package = downloads / meta["FILENAME"]
        if not package.exists() or checksum(package) != meta["SHA256SUM"]:
            print("Downloading " + name, flush=True)
            # The signed sync database gives each package's exact size.
            fetch(url, package, (PACKAGE_MAX, PACKAGE_DEADLINE), exact=int(meta["CSIZE"]))
        with package.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != meta["SHA256SUM"]:
                raise ValueError("Package checksum mismatch: " + name)
        signature = downloads / (package.name + ".sig")
        if meta.get("PGPSIG"):
            signature.write_bytes(base64.b64decode(meta["PGPSIG"]))
        elif not signature.exists():
            fetch(url + ".sig", signature, SIGNATURE)
        subprocess.run(["gpgv", "--homedir", str(home), "--keyring", "/etc/pacman.d/gnupg/pubring.gpg",
                        str(signature), str(package)], check=True, capture_output=True)
        subprocess.run(["bsdtar", "--no-same-owner", "-xf", str(package), "-C", str(tools)], check=True)
    print("Verified and extracted " + str(len(packages)) + " packages into the private lab cache.", flush=True)
    return tools


def environment(tools):
    return dict(os.environ, LD_LIBRARY_PATH=str(tools / "usr/lib"),
                QEMU_MODULE_DIR=str(tools / "usr/lib/qemu"))
