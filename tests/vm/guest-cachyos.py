#!/usr/bin/env python3
"""Install CachyOS on the lab's second virtual disk; never run on the host."""
import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess
import sys
import tempfile
import time
import urllib.request

SERIAL = 'HELLO_CACHYOS_TARGET'
KEY = '882DCFE48E2051D48E2562ABF3B607488DB35A47'
REPO = 'https://cdn77.cachyos.org/repo/x86_64/cachyos'
STAGE = 'guard'
MIRRORS = ('https://mirror.lesviallon.fr/cachy/repo', 'https://mirrors.lansing2600.org/cachyos/repo', 'https://cdn77.cachyos.org/repo')


def pinned_repositories(loader_help, cpu_info):
    """Use known reachable official mirrors while preserving CPU-compatible repositories."""
    levels = []
    if 'x86-64-v4 (supported, searched)' in loader_help:
        if 'AuthenticAMD' in cpu_info: levels.append(('znver4', 'x86_64_v4'))
        levels.append(('v4', 'x86_64_v4'))
    if 'x86-64-v3 (supported, searched)' in loader_help:
        levels.append(('v3', 'x86_64_v3'))
    if not levels: raise RuntimeError('CachyOS guest requires x86-64-v3 support')
    text = ''
    for level, architecture in levels:
        for name in ('cachyos-' + level, 'cachyos-core-' + level, 'cachyos-extra-' + level):
            text += '[' + name + ']\nSigLevel = Required DatabaseOptional\n'
            for mirror in MIRRORS:
                text += 'Server = ' + mirror + '/' + architecture + '/$repo\n'
            text += '\n'
    return text


def progress(**fields):
    Path('/home/hellotest/cachyos-install-status.json').write_text(json.dumps(dict(stage=STAGE, **fields)))


def require_target():
    if os.geteuid() != 0 or socket.gethostname() != 'hello-lock-test' or not Path('/etc/hello-lock-vm').is_file():
        raise RuntimeError('Restricted to the disposable lab guest')
    progress(status='running', command='target-guard')
    serial = Path('/sys/class/block/vdb/serial')
    if not serial.exists(): serial = Path('/sys/class/block/vdb/device/serial')
    if serial.read_text().strip() != SERIAL:
        progress(status='failed', command='target-guard', reason='serial-mismatch')
        raise RuntimeError('Refusing any disk without the lab target serial')
    probe = subprocess.run(['lsblk', '-J', '-o', 'NAME,MOUNTPOINT,FSTYPE', '/dev/vdb'], check=True, capture_output=True, text=True)
    disk = json.loads(probe.stdout)['blockdevices'][0]
    if disk.get('mountpoint') or disk.get('fstype') or disk.get('children'):
        progress(status='failed', command='target-guard', reason='nonempty-target')
        raise RuntimeError('Installer target must be a fresh empty virtual disk')


def run(*args, **kwargs):
    progress(status='running', command=args[0])
    try:
        return subprocess.run(list(args), check=True, **kwargs)
    except subprocess.CalledProcessError as error:
        progress(status='failed', command=args[0], exit=error.returncode)
        raise


def bounded_download(url, limit, deadline):
    """A small HTTPS response: refused past `limit` bytes or `deadline` seconds
    in total (a socket timeout alone only bounds each read)."""
    ends = time.monotonic() + deadline
    data = b''
    with urllib.request.urlopen(url, timeout=30) as response:
        if not response.geturl().startswith('https://'):
            raise RuntimeError('Download was redirected away from HTTPS')
        while True:
            if time.monotonic() > ends:
                raise RuntimeError('Download took longer than allowed')
            chunk = response.read(min(65536, limit + 1 - len(data)))
            if not chunk:
                return data
            data += chunk
            if len(data) > limit:
                raise RuntimeError('Download is larger than allowed')


def install_system(config, log_file):
    # System creation needs a normal umask. Protect the credential-bearing log
    # explicitly instead of imposing private modes on the target's /etc tree.
    descriptor = os.open(log_file, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(descriptor)
        if info.st_uid != os.geteuid() or not stat.S_ISREG(info.st_mode):
            raise RuntimeError('Installer log must be an owned regular file')
        os.fchmod(descriptor, 0o600)
    finally:
        os.close(descriptor)
    run('cachyos-installer', '--config', str(config), umask=0o022)


def root_mount_args(part, target):
    if part.get('fstype') not in ('ext4', 'btrfs'): return None
    if not re.fullmatch(r'/dev/vdb[0-9]+', part.get('path', '')):
        raise RuntimeError('Root candidate must belong to the guarded target disk')
    options = ['-o', 'subvol=@'] if part['fstype'] == 'btrfs' else []
    return ['mount', *options, part['path'], str(target)]


def target_partitions(layout):
    parts = []
    for block in layout.get('blockdevices', []):
        if block.get('path') == '/dev/vdb':
            parts.extend(block.get('children', []))
        elif re.fullmatch(r'/dev/vdb[0-9]+', block.get('path', '')):
            parts.append(block)
    return parts


def main():
    global STAGE
    require_target()
    os.umask(0o077)
    data = json.load(sys.stdin)
    if not data['public_key'].startswith('ssh-ed25519 ') or not data['password'].isalnum():
        raise ValueError('Invalid lab credentials')
    with tempfile.TemporaryDirectory(prefix='hello-cachyos-') as directory:
        work = Path(directory)
        # QEMU's default user network provides DNS at this address. A regular file
        # also works inside the installer's chroots, without a cloud-image stub resolver.
        STAGE = 'guest-dns'
        resolver = Path('/etc/resolv.conf')
        if resolver.is_symlink(): resolver.unlink()
        resolver.write_text('nameserver 10.0.2.3\noptions timeout:3 attempts:2\n')
        resolver.chmod(0o644)
        # Trust the full official fingerprint, then retain pacman's package signatures.
        STAGE = 'signing-key'
        key_file = work / 'cachyos-public-key.asc'
        progress(status='running', command='public-key-download')
        key_file.write_bytes(bounded_download('https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x' + KEY,
                                              1024 * 1024, 120))
        run('pacman-key', '--add', str(key_file))
        info = run('gpg', '--homedir', '/etc/pacman.d/gnupg', '--with-colons', '--fingerprint', KEY, capture_output=True, text=True)
        if KEY not in [s.split(':')[9] for s in info.stdout.splitlines() if s.startswith('fpr:')]:
            raise RuntimeError('CachyOS signing key mismatch')
        run('pacman-key', '--lsign-key', KEY)
        config = Path('/etc/pacman.conf')
        text = config.read_text()
        # Enforce downloaded-package signatures even if a future bootstrap changes its default.
        text = re.sub(r'^\s*#?\s*RemoteFileSigLevel\s*=.*$', 'RemoteFileSigLevel = Required', text, flags=re.M)
        if 'RemoteFileSigLevel = Required' not in text:
            text = text.replace('[options]', '[options]\nRemoteFileSigLevel = Required', 1)
        config.write_text(text)
        STAGE = 'signed-repository-packages'
        run('pacman', '--noconfirm', '-U', REPO + '/cachyos-keyring-20240331-1-any.pkg.tar.zst',
            *[REPO + '/' + name + '-27-1-any.pkg.tar.zst' for name in ('cachyos-mirrorlist', 'cachyos-v3-mirrorlist', 'cachyos-v4-mirrorlist')])
        for name in ('cachyos-mirrorlist', 'cachyos-v3-mirrorlist', 'cachyos-v4-mirrorlist'):
            architecture = 'x86_64_v3' if '-v3-' in name else 'x86_64_v4' if '-v4-' in name else 'x86_64'
            Path('/etc/pacman.d', name).write_text(''.join('Server = ' + mirror + '/' + architecture + '/$repo\n' for mirror in MIRRORS))
        text = config.read_text()
        base_servers = '\n'.join('Server = ' + mirror + '/x86_64/cachyos' for mirror in MIRRORS)
        config.write_text(text.replace('[core]', '[cachyos]\nSigLevel = Required DatabaseOptional\n' + base_servers + '\n\n[core]', 1))
        STAGE = 'installer-dependencies'
        # Use independent official mirrors; package signatures remain required.
        mirrors = 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch\nServer = https://fastly.mirror.pkgbuild.com/$repo/os/$arch\n'
        Path('/etc/pacman.d/mirrorlist').write_text(mirrors)
        Path('/etc/pacman.d/mirrorlist').chmod(0o644)
        # CachyOS's mirror tooling uses pacman architecture variables absent from stock Arch.
        # Force the signed CachyOS build even when its version equals the bootstrap build.
        run('pacman', '-Sy', '--noconfirm', 'cachyos/pacman')
        run('pacman', '-Syu', '--noconfirm', '--needed', 'cachyos-cli-installer-new', 'arch-install-scripts')
        loader = run('/lib/ld-linux-x86-64.so.2', '--help', capture_output=True, text=True).stdout
        pinned = pinned_repositories(loader, Path('/proc/cpuinfo').read_text())
        text = config.read_text()
        text = re.sub(r'^Include\s*=\s*/etc/pacman.d/mirrorlist\s*$',
                      mirrors.rstrip(), text, flags=re.M)
        config.write_text(text.replace('[cachyos]', pinned + '[cachyos]', 1))
        # Rolling mirrors can replace a package between bootstrap and install.
        # Refresh all databases from the same preferred mirror immediately before
        # pacstrap; retain required package signatures and independent fallbacks.
        run('pacman', '-Syy', '--noconfirm')
        # The installer may rank mirrors again; these explicit Server entries remain stable.
        settings = {'install_type': 'simple', 'headless_mode': True, 'device': '/dev/vdb',
                    'fs_name': 'btrfs', 'allow_auto_partition': True, 'partitions': [],
                    'hostname': 'hello-lock-test', 'locale': 'en_US.UTF-8', 'xkbmap': 'us', 'timezone': 'UTC',
                    'user_name': 'hellotest', 'user_pass': data['password'], 'root_pass': data['password'],
                    'user_shell': '/bin/bash', 'kernel': 'linux-cachyos', 'bootloader': 'grub',
                    'server_profile': 'minimal', 'ssh_authorized_keys': [data['public_key']],
                    'server_extra_packages': ['hyprland', 'quickshell', 'qt6-svg', 'qt6-multimedia', 'mesa', 'python', 'ttf-dejavu', 'sudo', 'swayidle', 'grim']}
        path = work / 'settings.json'
        path.write_text(json.dumps(settings))
        STAGE = 'official-installer'
        install_system(path, '/tmp/cachyos-install.log')
        STAGE = 'installed-system-setup'
        # The installer unmounts its target. Locate its genuine root, never fabricate os-release.
        layout = json.loads(run('lsblk', '-J', '--tree', '-o', 'PATH,FSTYPE', '/dev/vdb', capture_output=True, text=True).stdout)
        parts = target_partitions(layout)
        progress(status='running', command='root-discovery', partitions=len(parts),
                 filesystems=[p.get('fstype') if p.get('fstype') in ('btrfs', 'ext4', 'vfat', 'swap') else 'other' for p in parts])
        target = work / 'target'; target.mkdir()
        for part in parts:
            arguments = root_mount_args(part, target)
            if arguments is None: continue
            run(*arguments)
            identity = target / 'etc/os-release'
            if identity.exists() and any(line in ('ID=cachyos', 'ID="cachyos"') for line in identity.read_text().splitlines()): break
            run('umount', str(target))
        else: raise RuntimeError('Installer did not create a CachyOS root filesystem')
        try:
            (target / 'etc/hello-lock-vm').write_text('disposable-autonomous-test-guest\n')
            (target / 'etc/hello-lock-vm-profile').write_text('cachyos\n')
            for name in ('hello-lock-vm', 'hello-lock-vm-profile'):
                (target / 'etc' / name).chmod(0o644)
            sudo = target / 'etc/sudoers.d/hello-lock-test'
            sudo.write_text('hellotest ALL=(ALL) NOPASSWD:ALL\n'); sudo.chmod(0o440)
            network = target / 'etc/systemd/network'; network.mkdir(parents=True, exist_ok=True)
            network.chmod(0o755)
            network_file = network / '20-lab.network'
            network_file.write_text('[Match]\nName=en* eth*\n[Network]\nDHCP=yes\n')
            network_file.chmod(0o644)
            resolver = target / 'etc/resolv.conf'
            if resolver.is_symlink(): resolver.unlink()
            resolver.write_text('nameserver 10.0.2.3\n')
            resolver.chmod(0o644)
            run('systemctl', '--root', str(target), 'enable', 'sshd', 'systemd-networkd', 'systemd-resolved')
        finally:
            run('umount', str(target))


if __name__ == '__main__':
    main()
