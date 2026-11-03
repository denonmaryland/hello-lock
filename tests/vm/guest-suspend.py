#!/usr/bin/env python3
"""Real kernel freeze, restricted to the marked disposable guest and root."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import pwd
import time


def main():
    if os.geteuid() != 0 or socket.gethostname() != 'hello-lock-test' or not Path('/etc/hello-lock-vm').is_file():
        raise RuntimeError('Restricted to the disposable lab guest')
    counter = Path('/sys/power/suspend_stats/success')
    before = int(counter.read_text())
    targets = list(Path('/sys/bus/serio/devices').glob('*/power/wakeup'))
    targets += [Path('/sys/devices/platform/i8042/power/wakeup'), Path('/sys/class/rtc/rtc0/device/power/wakeup')]
    for path in targets:
        if path.exists(): path.write_text('enabled\n')
    pre_sleep_secure = None
    if '--logind' in sys.argv:
        uid = pwd.getpwnam('hellotest').pw_uid
        evidence = Path('/run/hello-lock-vm-pre-sleep.json')
        config = Path('/etc/systemd/sleep.conf.d/hello-lock-vm.conf')
        hook = Path('/usr/lib/systemd/system-sleep/hello-lock-vm-check')
        if config.exists() or hook.exists() or evidence.exists(): raise RuntimeError('VM sleep fixture already exists')
        config.parent.mkdir(parents=True, exist_ok=True)
        hook.parent.mkdir(parents=True, exist_ok=True)
        # The system-sleep pre hook runs after logind's delay inhibitor. Record
        # only compositor-confirmed state, never field data or PAM messages.
        script = '''#!/usr/bin/python3
import glob,json,sys
if sys.argv[1] == 'pre':
    records=[]
    for path in glob.glob('/run/user/''' + str(uid) + '''/hello-lock-*/state.json'):
        try:
            with open(path) as stream: records.append(json.load(stream))
        except (OSError,ValueError): pass
    with open('/run/hello-lock-vm-pre-sleep.json','x') as stream:
        json.dump({'secure': any(s.get('secure') is True and not s.get('released') and s.get('phase') == 'locked' and not s.get('authenticating') for s in records)},stream)
'''
        try:
            with config.open('x') as stream: stream.write('[Sleep]\nSuspendState=freeze\n')
            with hook.open('x') as stream: stream.write(script)
            hook.chmod(0o700)
            subprocess.run(['rtcwake', '-u', '-m', 'no', '-s', '4'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(['systemctl', 'suspend'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 20
            while int(counter.read_text()) <= before and time.monotonic() < deadline: time.sleep(.1)
            pre_sleep_secure = json.loads(evidence.read_text()).get('secure')
        finally:
            config.unlink(missing_ok=True); hook.unlink(missing_ok=True); evidence.unlink(missing_ok=True)
    else:
        subprocess.run(['rtcwake', '-u', '-m', 'freeze', '-s', '4'], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    after = int(counter.read_text())
    if after <= before: raise RuntimeError('Kernel suspend counter did not increase')
    print(json.dumps({'mode': 's2idle', 'before': before, 'after': after, 'pre_sleep_secure': pre_sleep_secure}))


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({'error': type(error).__name__, 'fixture': 'logind' if '--logind' in sys.argv else 'rtcwake'}))
        sys.exit(2)
