#!/usr/bin/env python3
"""Prepare private, signature-checked QEMU tools without modifying host packages."""
import base64
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tarfile
import urllib.request

PACKAGES = ("qemu-system-x86", "qemu-img", "qemu-hw-display-virtio-gpu",
            "qemu-hw-display-virtio-vga", "qemu-hw-display-virtio-vga-gl", "qemu-ui-egl-headless",
            "qemu-hw-display-virtio-gpu-gl", "qemu-hw-display-qxl", "libisoburn")


def fetch(url, destination):
    if not url.startswith("https://"):
        raise ValueError("Downloads require HTTPS")
    temporary = destination.with_suffix(destination.suffix + ".partial")
    try:
        with urllib.request.urlopen(url, timeout=45) as response, temporary.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


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
            fetch(url, package)
        with package.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != meta["SHA256SUM"]:
                raise ValueError("Package checksum mismatch: " + name)
        signature = downloads / (package.name + ".sig")
        if meta.get("PGPSIG"):
            signature.write_bytes(base64.b64decode(meta["PGPSIG"]))
        elif not signature.exists():
            fetch(url + ".sig", signature)
        subprocess.run(["gpgv", "--homedir", str(home), "--keyring", "/etc/pacman.d/gnupg/pubring.gpg",
                        str(signature), str(package)], check=True, capture_output=True)
        subprocess.run(["bsdtar", "--no-same-owner", "-xf", str(package), "-C", str(tools)], check=True)
    print("Verified and extracted " + str(len(packages)) + " packages into the private lab cache.", flush=True)
    return tools


def environment(tools):
    return dict(os.environ, LD_LIBRARY_PATH=str(tools / "usr/lib"),
                QEMU_MODULE_DIR=str(tools / "usr/lib/qemu"))
