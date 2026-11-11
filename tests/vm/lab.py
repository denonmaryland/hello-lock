#!/usr/bin/env python3
"""Private headless VM lab. No host passwords, desktop input, or host root required."""
import argparse
import fcntl
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import tarfile
import threading
import time
import traceback

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tools import IMAGE, SIGNATURE, environment, fetch, prepare, private_directory, read_url
from profiles import PROFILES, get as guest_profile, verify_identity
from images import ImageUnavailable

ROOT = Path(__file__).resolve().parents[2]
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "hello-lock-vm"
MIRROR = "https://fastly.mirror.pkgbuild.com/images/latest/"
ARCH_BOXES_KEY = "1B9A16984A4E8CB448712D2AE0B78BF4326C6F8F"


class DependencyBlocked(RuntimeError):
    def __init__(self, message, diagnostic=None):
        self.diagnostic = diagnostic or {}
        super().__init__(message)


class InstallerFailed(RuntimeError):
    def __init__(self, diagnostic):
        self.diagnostic = diagnostic
        super().__init__('CachyOS unattended installation failed')


class ResourceAbort(RuntimeError):
    pass


def memory_pressure():
    data = Path("/proc/pressure/memory").read_text()
    match = re.search(r"full avg10=([0-9.]+)", data)
    return float(match[1]) if match else 0.0


def available_memory():
    for line in Path("/proc/meminfo").read_text().splitlines():
        if line.startswith("MemAvailable:"):
            return int(line.split()[1]) // 1024
    return 0


def preflight(cache, memory=3072, reserve=1536):
    return {"kvm_access": os.access("/dev/kvm", os.R_OK | os.W_OK), "memory_pressure_full_avg10": memory_pressure(),
            "available_memory_mib": available_memory(), "guest_memory_mib": memory,
            "host_reserve_mib": reserve, "disk_free_gib": shutil.disk_usage(cache if cache.exists() else cache.parent).free // (1024 ** 3),
            "tools_ready": (cache / "tools/usr/bin/qemu-system-x86_64").is_file()}


def ready(report):
    return report.get("memory_pressure_full_avg10", 0) < 2 and report["kvm_access"] and report["tools_ready"] and report["disk_free_gib"] >= 20 and report["available_memory_mib"] >= report["guest_memory_mib"] + report["host_reserve_mib"]


class QMP:
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(10)
        self.socket.connect(str(path))
        self.stream = self.socket.makefile("rwb")
        json.loads(self.stream.readline())
        self.command("qmp_capabilities")

    def command(self, name, arguments=None):
        self.stream.write((json.dumps({"execute": name, "arguments": arguments or {}}) + "\n").encode())
        self.stream.flush()
        while True:
            line = self.stream.readline()
            if not line:
                raise RuntimeError("QMP disconnected")
            response = json.loads(line)
            if "error" in response:
                if name == 'screendump':
                    # This command has only a controlled output path, never keyboard data.
                    raise RuntimeError('QMP screendump: ' + response['error'].get('desc', 'unavailable'))
                raise RuntimeError("QMP command failed: " + name)
            if "return" in response:
                return response["return"]

    def text(self, value):
        # For the VM's controlled US keyboard only. Never logs input or uses host input APIs.
        if any(char not in "abcdefghijklmnopqrstuvwxyz0123456789" for char in value):
            raise ValueError("Guest test input must be lowercase letters/digits")
        for char in value:
            self.command("send-key", {"keys": [{"type": "qcode", "data": char}], "hold-time": 30})
            time.sleep(0.04)

    def close(self):
        try:
            self.stream.close()
        except OSError:
            pass
        finally:
            self.socket.close()


def image(cache, distro="arch"):
    if distro == "cachyos":
        return image(cache, "arch")
    if distro != "arch":
        from images import prepare_image
        return prepare_image(cache, distro)
    images = cache / "images"
    private_directory(images)
    listing = read_url(MIRROR).decode()
    names = sorted(set(re.findall(r'Arch-Linux-x86_64-cloudimg-[0-9.]+\.qcow2', listing)))
    if not names:
        raise RuntimeError("No dated official Arch cloud image found")
    name = names[-1]
    destination = images / name
    signature = images / (name + ".sig")
    home = cache / "image-verification"
    private_directory(home)
    key = home / "arch-boxes.asc"
    if not key.exists():
        url = "https://raw.githubusercontent.com/archlinux/arch-boxes/master/README.md"
        readme = read_url(url).decode()
        block = re.search(r"-----BEGIN PGP PUBLIC KEY BLOCK-----.*?-----END PGP PUBLIC KEY BLOCK-----", readme, re.S)
        if not block:
            raise RuntimeError("Official image signing key not found")
        key.write_text(block.group(0) + "\n")
    result = subprocess.run(["gpg", "--homedir", str(home), "--batch", "--with-colons", "--show-keys", str(key)], capture_output=True, text=True, check=True)
    fingerprints = [line.split(":")[9] for line in result.stdout.splitlines() if line.startswith("fpr:")]
    if not fingerprints or fingerprints[0] != ARCH_BOXES_KEY:
        raise RuntimeError("Arch image signing key fingerprint mismatch")
    subprocess.run(["gpg", "--homedir", str(home), "--batch", "--import", str(key)], check=True, capture_output=True)
    if not destination.exists():
        print("Downloading official Arch cloud image", flush=True)
        fetch(MIRROR + name, destination, IMAGE)
    if not signature.exists():
        fetch(MIRROR + name + ".sig", signature, SIGNATURE)
    subprocess.run(["gpg", "--homedir", str(home), "--batch", "--verify", str(signature), str(destination)], check=True, capture_output=True)
    probe = subprocess.run([str(cache / "tools/usr/bin/qemu-img"), "info", "--output=json", str(destination)],
                           env=environment(cache / "tools"), capture_output=True, text=True, check=True)
    info = json.loads(probe.stdout)
    if info.get("format") != "qcow2" or info.get("backing-filename") or info.get("data-file"):
        raise RuntimeError("Official image must be a standalone qcow2 image")
    print("Official Arch image signature verified", flush=True)
    return destination


def ssh_command(run, port):
    return ["ssh", "-F", "/dev/null", "-i", str(run / "ssh-key"), "-p", str(port),
            "-o", "BatchMode=yes", "-o", "ConnectTimeout=3", "-o", "IdentitiesOnly=yes",
            "-o", "IdentityAgent=none", "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes",
            "-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=" + str(run / "known-hosts"),
            "hellotest@127.0.0.1"]


def private_file(path, text):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        stream.write(text)


def seed(run, tools, distro="arch"):
    profile = guest_profile("arch" if distro == "cachyos" else distro)
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(run / "ssh-key")], check=True)
    password = "".join(secrets.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(24))
    private_file(run / "guest-password", password)
    data = {"hostname": "hello-lock-test", "ssh_pwauth": False,
            "users": [{"name": "hellotest", "groups": [profile["admin_group"], "video", "render"], "shell": "/bin/bash",
                       "lock_passwd": False, "sudo": "ALL=(ALL) NOPASSWD:ALL",
                       "ssh_authorized_keys": [(run / "ssh-key.pub").read_text().strip()]}],
            "chpasswd": {"expire": False, "users": [{"name": "hellotest", "password": password, "type": "text"}]},
            "write_files": [{"path": "/etc/hello-lock-vm", "content": "disposable-autonomous-test-guest\n", "permissions": "0644"}, {"path": "/etc/hello-lock-vm-profile", "content": distro + "\n", "permissions": "0644"}],
            "swap": {"filename": "/swapfile", "size": 2147483648, "maxsize": 2147483648},
            "package_update": True, "package_upgrade": False,
            "packages": ["openssh", "python"] if distro == "cachyos" else profile["packages"],
            "runcmd": [["systemctl", "enable", "--now", profile["ssh_service"]]]}
    private_file(run / "user-data", "#cloud-config\n" + json.dumps(data))
    private_file(run / "meta-data", json.dumps({"instance-id": "hello-lock-" + secrets.token_hex(8), "local-hostname": "hello-lock-test"}))
    subprocess.run([str(tools / "usr/bin/xorriso"), "-as", "mkisofs", "-quiet", "-output", str(run / "seed.iso"),
                    "-volid", "cidata", "-joliet", "-rock", str(run / "user-data"), str(run / "meta-data")],
                   env=environment(tools), check=True, capture_output=True)


def save_result(cache, distro, result):
    result = dict(result, distro=distro, recorded_at=datetime.now(timezone.utc).isoformat())
    text = json.dumps(result, indent=2)
    names = ["last-result.json", "result-" + distro + ".json"]
    if result.get("suite") in ("visual", "standalone", "lock-loss"):
        names.append("result-" + distro + "-" + result["suite"] + ".json")
    for name in names:
        descriptor, path = tempfile.mkstemp(prefix=name + '.', suffix='.partial', dir=cache)
        temporary = Path(path)
        try:
            with os.fdopen(descriptor, 'w') as stream: stream.write(text)
            temporary.replace(cache / name)
        finally:
            temporary.unlink(missing_ok=True)
    return result


def run_vm(cache, memory, wait_seconds, reserve=1536, distro="arch", suite="visual"):
    if suite == "lock-loss" and distro != "arch":
        raise ValueError("Lock-loss integration currently requires the Arch guest")
    private_directory(cache)
    if guest_profile(distro).get('image_blocked_reason'):
        result = save_result(cache, distro, {'status': 'blocked', 'stage': 'image-verification',
                                            'reason': guest_profile(distro)['image_blocked_reason'], 'authentication_tested': False})
        print(json.dumps(result))
        return 2
    with (cache / "lab.lock").open("w") as lock:
        deadline = time.monotonic() + wait_seconds
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    print(json.dumps(save_result(cache, distro, {"status": "deferred", "reason": "another lab guest is running"})))
                    return 75
                time.sleep(min(2, max(0, deadline - time.monotonic())))
        while True:
            report = preflight(cache, memory, reserve)
            if ready(report):
                break
            if time.monotonic() >= deadline:
                print(json.dumps(save_result(cache, distro, {"status": "deferred", "reason": "resource preflight", **report})))
                return 75
            time.sleep(min(15, max(0, deadline - time.monotonic())))
        tools = cache / "tools"
        try:
            base = image(cache) if distro == "arch" else image(cache, distro)
        except Exception as error:
            save_result(cache, distro, {"status": "blocked" if isinstance(error, ImageUnavailable) else "failed", "stage": "image-verification", "error_type": type(error).__name__, "authentication_tested": False})
            raise
        with tempfile.TemporaryDirectory(prefix="run-", dir=cache) as directory:
            try:
                return boot_vm(cache, tools, base, Path(directory), memory, distro, **({"suite": suite} if suite != "visual" else {}))
            except BaseException as error:
                cancelled = isinstance(error, (KeyboardInterrupt, SystemExit))
                save_result(cache, distro, {"status": "aborted" if cancelled or isinstance(error, ResourceAbort) else "blocked" if isinstance(error, DependencyBlocked) else "failed", "stage": "cancelled" if cancelled else "resource-guard" if isinstance(error, ResourceAbort) else "dependencies" if isinstance(error, DependencyBlocked) else "vm-run", "error_type": type(error).__name__, "error_code": {
                                               'Guest desktop pixels exposed while locked': 'desktop-pixel-exposure',
                                               'Guest compositor or visual tests timed out': 'guest-tests-timeout',
                                               'Guest desktop setup failed': 'guest-desktop-setup',
                                               'Virtual framebuffer did not provide a complete frame': 'virtual-display-frame-unverified',
                                               'Virtual display is inactive or changed size; lock frame unverified': 'virtual-display-frame-unverified',
                                               'Guest kernel suspend fixture failed': 'suspend-fixture-failed',
                                               'Unknown guest input action': 'unknown-input-action'}.get(str(error), str(error) if str(error).startswith(('QMP screendump:', 'QMP command failed:', 'QMP disconnected')) else 'other'), "authentication_tested": False,
                                           "failure_locations": [Path(frame.filename).name + ':' + str(frame.lineno) for frame in traceback.extract_tb(error.__traceback__)],
                                           "suite": suite,
                                           "installer": error.diagnostic if isinstance(error, InstallerFailed) else None,
                                           "dependencies": error.diagnostic if isinstance(error, DependencyBlocked) else None})
                raise



def source_bundle(destination, suite="visual", runtime_root=Path("/usr/share/omarchy/shell")):
    import runpy
    files = runpy.run_path(str(ROOT / "bin/hello-lock"))["VISUAL_FILES"]
    selected = list(files) + ["standalone", "LICENSE", "THIRD_PARTY_NOTICES.md", "docs/standalone.md", "docs/packaging.md", "docs/release-review.md", "tests/run-standalone.py", "tests/run-clipboard.py", "Onboarding.qml",
                             "tests/vm/guest-session.py", "tests/vm/guest-test.py", "tests/vm/guest-auth.py", "tests/vm/guest-suspend.py", "tests/vm/sentinel.qml", "tests/vm/profiles.py"]
    if suite == "lock-loss":
        selected += ["Service.qml", "adapters", "tests/vm/guest-security.py",
                     "tests/vm/security.qml", "tests/vm/pam-password"]
    def header(member):
        member.uid = member.gid = 0
        member.uname = member.gname = ""
        return member
    with tarfile.open(destination, "w:gz") as archive:
        for name in selected:
            path = ROOT / name
            members = [path] + sorted(path.rglob("*")) if path.is_dir() else [path]
            for item in members:
                if "__pycache__" in item.parts or any(part.startswith(".") for part in item.relative_to(ROOT).parts) or item.name in ("AGENTS.md", "CLAUDE.md"):
                    continue
                if item.is_symlink():
                    raise ValueError("Source bundle refuses symlinks")
                archive.add(item, arcname=str(item.relative_to(ROOT)), recursive=False, filter=header)
        if suite == "lock-loss":
            # Public installed runtime source only, never user config or runtime state.
            import hashlib
            import io
            sources = {}
            for module in ("Commons", "Ui"):
                directory = runtime_root / module
                if not (directory / "qmldir").is_file():
                    raise ValueError("Omarchy runtime module is missing")
                for item in sorted(directory.rglob("*")):
                    if not item.is_file(): continue
                    if item.is_symlink() or not (item.suffix in (".qml", ".js") or item.name == "qmldir"):
                        raise ValueError("Unexpected Omarchy runtime source")
                    name = "omarchy/shell/" + str(item.relative_to(directory.parent))
                    data = item.read_bytes()
                    sources[name] = hashlib.sha256(data).hexdigest()
                    member = tarfile.TarInfo(name); member.mode = 0o644; member.size = len(data)
                    archive.addfile(member, io.BytesIO(data))
            data = json.dumps({"files": sources, "service_sha256": hashlib.sha256((ROOT / "Service.qml").read_bytes()).hexdigest()}).encode()
            member = tarfile.TarInfo("omarchy/source-manifest.json"); member.mode = 0o644; member.size = len(data)
            archive.addfile(member, io.BytesIO(data))


def guest_keyboard(run, port, qmp, value, previous):
    sequence = value.get("sequence")
    # Fixed chords only: the guest picks one by name, never sends key data.
    chords = {"bind-marker": ["meta_l", "m"], "bind-intruder": ["meta_l", "o"], "type-a": ["a"],
              "vt2": ["ctrl", "alt", "f2"], "vt1": ["ctrl", "alt", "f1"]}
    if type(sequence) is not int or sequence < 1 or sequence > 60 or value.get("action") not in ("wrong-password", "password", "burst", *chords):
        raise ValueError("Unexpected guest input request")
    if sequence == previous: return previous
    if sequence != previous + 1: raise ValueError("Out-of-order guest input request")
    if qmp is None: raise RuntimeError("QMP is required for guest authentication")
    if value["action"] == "burst":
        # About six seconds of alternating exec chords and plain keys, announced
        # first so the guest can map an overlay in the middle of it.
        subprocess.run(ssh_command(run, port) + ["printf '%s' '" + str(sequence) + "' > vm-input-burst"], check=True, capture_output=True, timeout=10)
        for index in range(90):
            keys = chords["bind-marker"] if index % 2 == 0 else chords["type-a"]
            qmp.command("send-key", {"keys": [{"type": "qcode", "data": key} for key in keys], "hold-time": 25})
            time.sleep(.04)
        subprocess.run(ssh_command(run, port) + ["printf '%s' '" + str(sequence) + "' > vm-input-ack"], check=True, capture_output=True, timeout=10)
        return sequence
    if value["action"] in chords:
        qmp.command("send-key", {"keys": [{"type": "qcode", "data": key} for key in chords[value["action"]]], "hold-time": 60})
        subprocess.run(ssh_command(run, port) + ["printf '%s' '" + str(sequence) + "' > vm-input-ack"], check=True, capture_output=True, timeout=10)
        return sequence
    # The generated credential goes only to the guest virtual keyboard, never
    # a command argument, log, source bundle or result artifact.
    qmp.text("incorrect123" if value["action"] == "wrong-password" else (run / "guest-password").read_text())
    qmp.command("send-key", {"keys": [{"type": "qcode", "data": "ret"}], "hold-time": 30})
    subprocess.run(ssh_command(run, port) + ["printf '%s' '" + str(sequence) + "' > vm-input-ack"], check=True, capture_output=True, timeout=10)
    return sequence


def guest_tests(run, port, guard=None, cache=None, distro=None, suite="visual", qmp=None):
    bundle = run / "source.tar.gz"
    source_bundle(bundle, **({"suite": suite} if suite != "visual" else {}))
    with bundle.open("rb") as stream:
        subprocess.run(ssh_command(run, port) + ["mkdir -p hello-lock && tar -xzf - -C hello-lock"],
                       stdin=stream, capture_output=True, check=True, timeout=90)
    setup = subprocess.run(ssh_command(run, port) + ["python3 hello-lock/tests/vm/guest-session.py" + (" --suite " + suite if suite != "visual" else "") + (" --software-gpu" if os.environ.get('HELLO_LOCK_VM_SOFTWARE_GPU') == '1' else '') + (' --suspend-mode s3' if os.environ.get('HELLO_LOCK_VM_SUSPEND') == 's3' else '')],
                           capture_output=True, timeout=30)
    if setup.returncode:
        raise RuntimeError("Guest desktop setup failed")
    deadline = time.monotonic() + (420 if suite in ("standalone", "lock-loss") else 240)
    input_sequence = 0
    last_input = 0
    desktop_size = None
    while time.monotonic() < deadline:
        if guard is not None and guard.tripped:
            raise ResourceAbort("Host memory guard stopped the guest")
        if available_memory() < 512:
            raise ResourceAbort("Host memory reserve exhausted; guest stopped")
        try:
            probe = subprocess.run(ssh_command(run, port) + ["cat vm-result.json"], capture_output=True, text=True, timeout=10)
        except subprocess.TimeoutExpired:
            continue
        if suite == "lock-loss" and probe.returncode != 0:
            request = subprocess.run(ssh_command(run, port) + ["cat vm-input.json"], capture_output=True, text=True, timeout=10)
            if request.returncode == 0:
                input_sequence = guest_keyboard(run, port, qmp, json.loads(request.stdout), input_sequence)
        if probe.returncode == 0:
            result = json.loads(probe.stdout)
            if (result.get("status") == "passed" or result.get("visual_suite_exit") == 0) and result.get("screenshot"):
                screen = subprocess.run(ssh_command(run, port) + ["cat settings-preview.png"], capture_output=True, check=True, timeout=15)
                if not screen.stdout.startswith(b"\x89PNG\r\n\x1a\n") or len(screen.stdout) > 20 * 1024 * 1024:
                    raise RuntimeError("Guest screenshot is invalid")
                destination = cache if cache is not None else run.parent
                (destination / "last-settings-preview.png").write_bytes(screen.stdout)
                if distro:
                    (destination / ('settings-' + distro + '.png')).write_bytes(screen.stdout)
                    result['screenshot_artifact'] = 'settings-' + distro + '.png'
            if (result.get("status") == "passed" or result.get("visual_suite_exit") == 0) and result.get("weather_screenshot"):
                screen = subprocess.run(ssh_command(run, port) + ["cat settings-weather-preview.png"], capture_output=True, check=True, timeout=15)
                if not screen.stdout.startswith(b"\x89PNG\r\n\x1a\n") or len(screen.stdout) > 20 * 1024 * 1024:
                    raise RuntimeError("Guest weather screenshot is invalid")
                destination = cache if cache is not None else run.parent
                name = 'weather-' + distro + '.png' if distro else 'last-weather-preview.png'
                (destination / name).write_bytes(screen.stdout)
                result['weather_screenshot_artifact'] = name
            if isinstance(result.get('package_file'), str):
                filename = result['package_file']
                if not re.fullmatch(r'hello-lock-standalone[-_][A-Za-z0-9._-]+(?:\.rpm|\.pkg\.tar\.zst)', filename):
                    raise RuntimeError('Unexpected guest package filename')
                package = subprocess.run(ssh_command(run, port) + ['cat built-packages/' + filename], capture_output=True, check=True, timeout=30)
                if len(package.stdout) > 64 * 1024 * 1024 or not package.stdout.startswith((b'\xed\xab\xee\xdb', b'\x28\xb5\x2f\xfd')):
                    raise RuntimeError('Invalid guest package artifact')
                destination = cache if cache is not None else run.parent
                artifact = filename if result.get('status') == 'passed' else 'failed-' + filename
                (destination / artifact).write_bytes(package.stdout)
                result['package_artifact'] = artifact
            return result
        if suite == "standalone" and qmp is not None:
            request = subprocess.run(ssh_command(run, port) + ["cat vm-input.json"], capture_output=True, text=True, timeout=10)
            if request.returncode == 0:
                action = json.loads(request.stdout)
                if cache is not None:
                    progress = {'status': 'incomplete', 'stage': action.get('stage') if isinstance(action.get('stage'), str) and re.fullmatch('[a-z0-9-]{1,80}', action['stage']) else 'unknown',
                                'checks': [item for item in action.get('checks', []) if isinstance(item, str) and re.fullmatch('[a-z0-9-]{1,100}', item)][:80]}
                    (cache / ('progress-' + distro + '.json')).write_text(json.dumps(progress))
                if action.get('sequence', 0) > last_input:
                    last_input = action['sequence']
                    if action.get('action') == 'correct_password':
                        qmp.text((run / 'guest-password').read_text().strip())
                        qmp.command('send-key', {'keys': [{'type': 'qcode', 'data': 'ret'}], 'hold-time': 40})
                    elif action.get('action') == 'wrong_password':
                        qmp.text('incorrectpassword')
                        qmp.command('send-key', {'keys': [{'type': 'qcode', 'data': 'ret'}], 'hold-time': 40})
                    elif action.get('action') == 'desktop_key': qmp.text('z')
                    elif action.get('action') == 'clear_input':
                        qmp.command('send-key', {'keys': [{'type': 'qcode', 'data': 'ctrl'}, {'type': 'qcode', 'data': 'u'}], 'hold-time': 40})
                    elif action.get('action') == 'suspend_resume':
                        if not qmp.command('query-current-machine').get('wakeup-suspend-support'):
                            raise RuntimeError('Virtual machine has no suspend wakeup support')
                        suspend = subprocess.Popen(ssh_command(run, port) + ['sudo -n systemctl suspend'],
                                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        try:
                            end = time.monotonic() + 15
                            while qmp.command('query-status').get('status') != 'suspended':
                                if time.monotonic() >= end: raise RuntimeError('Guest did not enter suspend')
                                time.sleep(.1)
                            time.sleep(.5)
                            qmp.command('system_wakeup')
                            suspend.wait(timeout=15)
                            if suspend.returncode: raise RuntimeError('Guest suspend command failed')
                        finally:
                            if suspend.poll() is None:
                                suspend.terminate(); suspend.wait(timeout=5)
                    elif action.get('action') in ('suspend_s2idle', 'suspend_s2idle_logind'):
                        suspend = subprocess.Popen(ssh_command(run, port) + ['sudo -n python3 hello-lock/tests/vm/guest-suspend.py' + (' --logind' if action['action'] == 'suspend_s2idle_logind' else '')],
                                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                        try:
                            end = time.monotonic() + 6
                            while suspend.poll() is None and time.monotonic() < end: time.sleep(.1)
                            if suspend.poll() is None:
                                qmp.command('send-key', {'keys': [{'type': 'qcode', 'data': 'shift'}], 'hold-time': 40})
                            output, _ = suspend.communicate(timeout=15)
                            if suspend.returncode:
                                raise RuntimeError('Guest kernel suspend fixture failed')
                            evidence = json.loads(output)
                            if evidence.get('mode') != 's2idle' or evidence.get('after', 0) <= evidence.get('before', 0):
                                raise RuntimeError('Guest kernel did not confirm s2idle')
                            subprocess.run(ssh_command(run, port) + ['cat > vm-suspend-evidence.json'], input=json.dumps(evidence),
                                           text=True, capture_output=True, check=True, timeout=10)
                        finally:
                            if suspend.poll() is None:
                                suspend.terminate(); suspend.wait(timeout=5)
                    elif action.get('action') in ('locked_frame', 'desktop_frame'):
                        from framebuffer import capture
                        # QEMU can initially send a full-size inactive placeholder.
                        # Keep the same connection until actual guest pixels arrive.
                        color = (0, 255, 17) if action['action'] == 'desktop_frame' else (26, 27, 38)
                        try:
                            with capture(run / 'display.sock', lambda frame: sum(1 for rgb in frame.getdata() if rgb == color) >= 1000,
                                         rejected_path=cache / ('rejected-display-' + distro + '.png') if cache is not None else None) as picture:
                                exposed = sum(1 for rgb in picture.getdata() if rgb == (0, 255, 17))
                                if action['action'] == 'desktop_frame':
                                    if exposed < 1000: raise RuntimeError('Desktop pixel witness was not visible')
                                    desktop_size = (picture.width, picture.height)
                                else:
                                    if desktop_size != (picture.width, picture.height):
                                        raise RuntimeError('Virtual display is inactive or changed size; lock frame unverified')
                                    if cache is not None: picture.save(cache / ('lock-' + distro + '.png'))
                                    if exposed: raise RuntimeError('Guest desktop pixels exposed while locked')
                        except (RuntimeError, OSError):
                            subprocess.run(ssh_command(run, port) + ['cat > vm-input-ack.json'], input=json.dumps({'sequence':last_input,'failed':True}), text=True, capture_output=True, timeout=10)
                            for _ in range(30):
                                detail = subprocess.run(ssh_command(run, port) + ['cat vm-result.json'], capture_output=True, text=True, timeout=5)
                                if detail.returncode == 0:
                                    if cache is not None: (cache / ('failure-context-' + distro + '.json')).write_text(json.dumps(json.loads(detail.stdout)))
                                    break
                                time.sleep(.1)
                            raise
                    else: raise RuntimeError('Unknown guest input action')
                    print('Guest authentication input/check completed: ' + action['action'], flush=True)
                    end = time.monotonic() + 20
                    while True:
                        ack = subprocess.run(ssh_command(run, port) + ['cat > vm-input-ack.json'], input=json.dumps({'sequence': last_input}), text=True, capture_output=True, timeout=10)
                        if ack.returncode == 0: break
                        if time.monotonic() >= end: raise RuntimeError('Guest input acknowledgement failed')
                        time.sleep(.2)
        time.sleep(.2)
    raise RuntimeError("Guest compositor or visual tests timed out")



class HostGuard:
    """Stops only this lab's VM after sustained host memory pressure."""
    def __init__(self, process):
        self.process = process
        self.tripped = False
        self.event = threading.Event()
        self.thread = threading.Thread(target=self.watch, daemon=True)

    def watch(self):
        low = 0
        while not self.event.wait(1):
            pressure = Path("/proc/pressure/memory").read_text()
            full = re.search(r"full avg10=([0-9.]+)", pressure)
            low = low + 1 if available_memory() < 512 or (full and float(full[1]) > 10) else 0
            if low >= 5:
                self.tripped = True
                if self.process.poll() is None: self.process.terminate()
                return

    def start(self): self.thread.start()
    def stop(self): self.event.set(); self.thread.join(timeout=2)


def boot_vm(cache, tools, base, run, memory, distro="arch", installed=False, suite="visual"):
    # The entire run is private, including generated credentials, seed and QMP socket.
    os.umask(0o077)
    if not installed: seed(run, tools, distro)
    env = environment(tools)
    disk = run / "disk.qcow2"
    subprocess.run([str(tools / "usr/bin/qemu-img"), "create", "-q", "-f", "qcow2", "-F", "qcow2",
                    "-b", str(base), str(disk), "24G"], env=env, check=True)
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    command = [str(tools / "usr/bin/qemu-system-x86_64"), "-enable-kvm", "-cpu", "host", "-smp", "2", "-m", str(memory),
               "-L", str(tools / "usr/share/qemu"), "-display", "egl-headless,rendernode=/dev/dri/renderD128", "-device", "virtio-vga-gl",
               "-drive", "file=" + str(disk) + ",format=qcow2,if=none,id=systemdisk",
               "-device", "virtio-blk-pci,drive=systemdisk,bootindex=1",
               "-drive", "file=" + str(run / "seed.iso") + ",format=raw,media=cdrom,readonly=on",
               "-nic", "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:" + str(port) + "-:22",
               "-qmp", "unix:" + str(run / "qmp.sock") + ",server=on,wait=off", "-monitor", "none",
               "-serial", "file:" + str(run / "serial.log")]
    if installed:
        seed_index = command.index("file=" + str(run / "seed.iso") + ",format=raw,media=cdrom,readonly=on")
        del command[seed_index - 1:seed_index + 1]
    elif distro == "cachyos":
        target = run / "cachyos-target.qcow2"
        subprocess.run([str(tools / "usr/bin/qemu-img"), "create", "-q", "-f", "qcow2", str(target), "24G"], env=env, check=True)
        command += ["-drive", "file=" + str(target) + ",format=qcow2,if=none,id=cachytarget",
                    "-device", "virtio-blk-pci,drive=cachytarget,bootindex=2,serial=HELLO_CACHYOS_TARGET"]
    if suite == 'standalone':
        command += ['-vnc', 'unix:' + str(run / 'display.sock')]
    if os.environ.get('HELLO_LOCK_VM_SOFTWARE_GPU') == '1':
        command[command.index('egl-headless,rendernode=/dev/dri/renderD128')] = 'none'
        # Plain virtio also loses its scanout across guest sleep. QXL exercises
        # a different guest driver while Mesa renders in software.
        command[command.index('virtio-vga-gl')] = 'qxl-vga'
        command += ['-spice', 'unix=on,addr=' + str(run / 'spice.sock') + ',disable-ticketing=on']
    qmp = None
    with (run / "qemu.log").open("w") as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True, preexec_fn=lambda: os.nice(10))
        guard = HostGuard(process)
        try:
            guard.start()
            end = time.monotonic() + 900
            print("Guest started; waiting for automatic package setup", flush=True)
            while time.monotonic() < end:
                if process.poll() is not None:
                    if guard.tripped: raise ResourceAbort("Host memory guard stopped the guest")
                    raise RuntimeError("VM exited before boot completed")
                if qmp is None and (run / "qmp.sock").exists():
                    qmp = QMP(run / "qmp.sock")
                if available_memory() < 512:
                    raise ResourceAbort("Host memory reserve exhausted; guest stopped")
                try:
                    compositor_command = 'sway' if guest_profile(distro).get('compositor') == 'Sway' else 'Hyprland'
                    probe_script = "import json,pathlib,shutil,platform; print(json.dumps({'finished':pathlib.Path('/var/lib/cloud/instance/boot-finished').exists(),'compositor':bool(shutil.which(" + repr(compositor_command) + ")),'quickshell':bool(shutil.which('qs')),'identity':platform.freedesktop_os_release(),'kernel':platform.release()}))"
                    import shlex
                    probe = subprocess.run(ssh_command(run, port) + ["sudo -n python3 -c " + shlex.quote(probe_script)], capture_output=True, text=True, timeout=10)
                except subprocess.TimeoutExpired:
                    continue
                if probe.returncode == 0:
                    status = json.loads(probe.stdout)
                    if status["finished"] or installed:
                        if not (distro == 'cachyos' and not installed):
                            verify_identity(distro, status['identity'], status['kernel'])
                        if not (distro == "cachyos" and not installed) and (not status["compositor"] or not status["quickshell"]):
                            raise DependencyBlocked("Guest package setup did not provide its compositor and Quickshell",
                                                    {'os_id': status['identity'].get('ID'), 'os_version': status['identity'].get('VERSION_ID'),
                                                     'missing': [name for name in ('compositor', 'quickshell') if not status[name]]})
                        break
                time.sleep(3)
            else:
                raise RuntimeError("Guest bootstrap timed out")
            if distro == "cachyos" and not installed:
                print("Installing genuine CachyOS on the isolated second virtual disk", flush=True)
                for filename in ('guest-cachyos.py', 'installer-diagnostics.py'):
                    with (ROOT / 'tests/vm' / filename).open('rb') as source:
                        subprocess.run(ssh_command(run, port) + ['cat > ' + filename], stdin=source, capture_output=True, check=True, timeout=30)
                payload = json.dumps({"password": (run / "guest-password").read_text(), "public_key": (run / "ssh-key.pub").read_text().strip()})
                install = subprocess.run(ssh_command(run, port) + ["umask 077; sudo -n python3 guest-cachyos.py > cachyos-install.log 2>&1"],
                                         input=payload, text=True, capture_output=True, timeout=1800)
                if guard.tripped: raise ResourceAbort("Host memory guard stopped the guest")
                if install.returncode:
                    state = {}
                    diagnostic = subprocess.run(ssh_command(run, port) + ["sudo -n cat cachyos-install-status.json"], capture_output=True, text=True, timeout=15)
                    if diagnostic.returncode == 0:
                        state = json.loads(diagnostic.stdout)
                    flags = subprocess.run(ssh_command(run, port) + ['sudo -n python3 installer-diagnostics.py'], capture_output=True, text=True, timeout=30)
                    if flags.returncode == 0: state.update(json.loads(flags.stdout))
                    print(json.dumps({"installer": state}), flush=True)
                    raise InstallerFailed(state)
                qmp.command("quit"); process.wait(timeout=15); guard.stop()
                child = run / "installed"; child.mkdir(mode=0o700)
                for name in ("ssh-key", "ssh-key.pub", "guest-password"): shutil.copyfile(run / name, child / name)
                # This phase boots only the installed target; the Arch bootstrap is absent.
                return boot_vm(cache, tools, target, child, memory, distro, installed=True, suite=suite)
            print("Guest provisioned; starting independent Wayland tests", flush=True)
            result = guest_tests(run, port, guard, cache=cache, distro=distro, **({"suite": suite, "qmp": qmp} if suite != "visual" else {}))
            if suite == 'standalone' and (result.get('authentication_status') != 'passed' or result.get('authentication_tested') is not True):
                result['status'] = 'failed'
            result.update({"guest_status": "provisioned", "guest": guest_profile(distro)["name"] + " without Omarchy", "distro": distro, "memory_mib": memory,
                      "qmp": qmp.command("query-status")["status"], "ssh": "dedicated test account",
                      "locking_tests": "standalone PAM/compositor/QMP" if suite == "standalone" else "real service/PAM/QMP" if suite == "lock-loss" else "not tested", "suite": suite,
                      "virtual_gpu": "qxl-software" if os.environ.get('HELLO_LOCK_VM_SOFTWARE_GPU') == '1' else 'virgl'})
            result = save_result(cache, distro, result)
            print(json.dumps(result))
            return 0 if result["status"] == "passed" else 1
        finally:
            guard.stop()
            if qmp:
                try: qmp.command("quit")
                except (OSError, RuntimeError): pass
                qmp.close()
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
            # The guest overlay can contain cloud-init copies of the test credentials.
            for name in ("guest-password", "ssh-key", "ssh-key.pub", "user-data", "meta-data", "seed.iso", "disk.qcow2"):
                (run / name).unlink(missing_ok=True)




def smoke(cache):
    tools = cache / "tools"
    if available_memory() < 1664:
        print(json.dumps({"status": "deferred", "reason": "memory reserve"}))
        return 75
    with tempfile.TemporaryDirectory(prefix="qmp-smoke-", dir=cache) as directory:
        run = Path(directory)
        command = [str(tools / "usr/bin/qemu-system-x86_64"), "-enable-kvm", "-machine", "pc",
                   "-nodefaults", "-m", "128", "-S", "-display", "none", "-device", "virtio-vga",
                   "-L", str(tools / "usr/share/qemu"), "-qmp", "unix:" + str(run / "qmp.sock") + ",server=on,wait=off",
                   "-monitor", "none", "-serial", "none"]
        with (run / "qemu.log").open("w") as log:
            process = subprocess.Popen(command, env=environment(tools), stdout=log, stderr=subprocess.STDOUT)
            qmp = None
            try:
                for _ in range(100):
                    if process.poll() is not None:
                        raise RuntimeError("QEMU smoke failed: " + (run / "qemu.log").read_text())
                    if (run / "qmp.sock").exists(): break
                    time.sleep(.05)
                qmp = QMP(run / "qmp.sock")
                assert qmp.command("query-kvm")["enabled"]
                assert qmp.command("query-status")["status"] == "prelaunch"
                qmp.text("test123")
                qmp.command("screendump", {"filename": str(run / "screen.ppm")})
                assert (run / "screen.ppm").stat().st_size > 0
                print(json.dumps({"status": "passed", "kvm": True, "qmp": True, "virtual_keyboard": True,
                                  "virtual_screenshot": True, "guest_os_booted": False}))
            finally:
                if qmp:
                    try: qmp.command("quit")
                    except (OSError, RuntimeError): pass
                    qmp.close()
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=5)
    return 0


def matrix_child(command):
    process = subprocess.Popen(command)
    try:
        return process.wait()
    except BaseException:
        # Give the child's SIGTERM handler time to clean up its own QEMU and credentials.
        process.terminate()
        try: process.wait(timeout=30)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
        raise


def run_matrix(cache, memory, wait_seconds, compact=False, suite="visual", tiny=False):
    statuses = {}
    for distro in PROFILES:
        started = datetime.now(timezone.utc).isoformat()
        code = matrix_child([sys.executable, str(Path(__file__).resolve()), "run", "--distro", distro,
                               "--cache", str(cache), "--memory", str(memory),
                               "--wait-for-memory", str(wait_seconds)] + (["--tiny"] if tiny else ["--compact"] if compact else []) +
                               (["--suite", suite] if suite != "visual" else []))
        result_path = cache / ("result-" + distro + ".json")
        result = json.loads(result_path.read_text()) if result_path.exists() else {}
        if result.get("recorded_at", "") < started or (code and result.get("status") == "passed") or (suite != 'visual' and result.get('suite') != suite):
            result = {"status": "failed", "stage": "runner", "exit": code}
        statuses[distro] = result
    (cache / "matrix-result.json").write_text(json.dumps(statuses, indent=2))
    return 0 if all(r.get("status") == "passed" for r in statuses.values()) else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("check", "prepare", "smoke", "run", "matrix"))
    parser.add_argument("--distro", choices=list(PROFILES), default="arch")
    parser.add_argument("--suite", choices=("visual", "lock-loss", "standalone"), default="visual")
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--memory", type=int, default=3072)
    parser.add_argument("--compact", action="store_true", help="1 GiB guest plus 768 MiB host reserve; guest swap enabled")
    parser.add_argument("--tiny", action="store_true", help="768 MiB guest plus 1 GiB host reserve; guest swap enabled")
    parser.add_argument("--wait-for-memory", type=int, default=0, help="bounded autonomous wait, seconds")
    args = parser.parse_args()
    if args.memory < 768 or args.memory > 8192 or args.wait_for_memory < 0 or args.wait_for_memory > 3600:
        parser.error("memory must be 768–8192 MiB; wait must be 0–3600 seconds")
    if args.compact and args.tiny: parser.error('Choose either compact or tiny')
    if args.suite == "lock-loss" and (args.distro != "arch" or args.action == "matrix"):
        parser.error("lock-loss currently supports only --distro arch without matrix")
    if args.compact:
        args.memory = 1024
    if args.tiny: args.memory = 768
    reserve = 1024 if args.tiny else 768 if args.compact else 1536
    cache = args.cache.expanduser().absolute()
    os.umask(0o077)
    if args.action == "check":
        report = preflight(cache, args.memory, reserve)
        print(json.dumps({"ready_to_boot": ready(report), **report}, indent=2))
        return 0
    if args.action == "smoke":
        return smoke(cache)
    if args.action == "prepare":
        prepare(cache)
        image(cache, args.distro)
        return 0
    if args.action == "matrix":
        return run_matrix(cache, args.memory, args.wait_for_memory, args.compact, args.suite, args.tiny)
    try:
        return run_vm(cache, args.memory, args.wait_for_memory, reserve, args.distro, suite=args.suite)
    except ImageUnavailable:
        print(json.dumps({"status": "blocked", "stage": "image-verification", "distro": args.distro}))
        return 2
    except DependencyBlocked:
        print(json.dumps({"status": "blocked", "stage": "dependencies", "distro": args.distro}))
        return 2
    except ResourceAbort:
        print(json.dumps({"status": "aborted", "reason": "host-memory-pressure"}))
        return 75
    except KeyboardInterrupt:
        print(json.dumps({"status": "aborted", "reason": "cancelled"}))
        return 130
    except Exception as error:
        print(json.dumps({"status": "failed", "distro": args.distro, "error_type": type(error).__name__}))
        return 1


if __name__ == "__main__":
    def terminate(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, terminate)
    sys.exit(main())
