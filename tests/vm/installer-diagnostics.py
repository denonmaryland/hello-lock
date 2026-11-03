#!/usr/bin/env python3
"""Export fixed error labels and public package names, never raw installer logs."""
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tarfile

LABELS = ['partitioning failed', 'base install failed', 'fstab generation failed', 'system settings failed',
          'bootloader installation failed', 'failed retrieving file', 'target not found',
          'invalid or corrupted package', 'no space left', 'could not resolve', 'timed out',
          'failed to regenerate initramfs', 'failed to generate fstab', 'failed to run chwd',
          'temporary failure in name resolution', 'out of memory', 'failed to install base',
          'could not satisfy dependencies', 'failed to prepare transaction', 'failed to commit transaction',
          'conflicting files', 'exists in filesystem', 'unknown trust', 'invalid signature',
          'signature is invalid', 'key could not be looked up', 'failed to lock database',
          'error while loading shared libraries', 'illegal instruction', 'exec format error',
          'permission denied', 'certificate problem', 'corrupted package', 'killed',
          'invalid architecture', 'does not match system', 'incompatible architecture']


def summarize(log, allowed):
    text = log.lower()
    failed = [line for line in text.splitlines() if 'failed retrieving file' in line]
    names = set(re.findall(r"failed retrieving file '([^']+)'", text))
    return {'failure_labels': [label for label in LABELS if label in text],
            'failed_artifacts': sorted(names & {name.lower() for name in allowed}),
            'http_codes': sorted(set(re.findall(r'(?:error|http)\s*:?\s*([45][0-9]{2})\b', '\n'.join(failed)))),
            'mirrors': [host for host in ('cdn77.cachyos.org', 'mirrors.lansing2600.org', 'mirror.lesviallon.fr', 'fastly.mirror.pkgbuild.com') if any(host in line for line in failed)]}


def main():
    if os.geteuid() != 0 or socket.gethostname() != 'hello-lock-test' or not Path('/etc/hello-lock-vm').is_file():
        raise RuntimeError('Restricted to the disposable lab guest')
    allowed = set()
    for root in ('/var/lib/pacman/sync', '/mnt/var/lib/pacman/sync'):
        for database in Path(root).glob('*.db'):
            try:
                with tarfile.open(database) as archive:
                    for member in archive:
                        if member.name.endswith('/desc'):
                            fields = dict(re.findall(r'%([A-Z0-9]+)%\n(.*?)(?=\n\n|\Z)', archive.extractfile(member).read().decode(), re.S))
                            if fields.get('FILENAME'):
                                allowed.update((fields['FILENAME'], fields['FILENAME'] + '.sig'))
            except (OSError, tarfile.TarError):
                continue
    result = summarize(Path('cachyos-install.log').read_text(errors='replace'), allowed)
    kernel = subprocess.run(['dmesg'],capture_output=True,text=True,timeout=5).stdout.lower()
    result['guest_oom'] = 'out of memory' in kernel or 'oom-kill' in kernel
    swap = re.search(r'^SwapTotal:\s+([0-9]+)',Path('/proc/meminfo').read_text(),re.M)
    result['swap_mib'] = int(swap.group(1)) // 1024 if swap else None
    print(json.dumps(result))


if __name__ == '__main__':
    main()
