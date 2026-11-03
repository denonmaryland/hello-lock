"""Opt-in idle integration. Never edits compositor config or manages another locker."""
import fcntl
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess


def command(source, config, seconds):
    if type(seconds) is not int or not 1 <= seconds <= 86400:
        raise ValueError('Idle timeout must be 1–86400 seconds')
    # swayidle executes event commands through /bin/sh. Quote each literal arg.
    lock = shlex.join([str(source / 'bin/hello-lock'), 'lock', '--background', '--config-dir', str(config)])
    return ['swayidle', '-w', '-C', '/dev/null', 'timeout', str(seconds), lock,
            'before-sleep', lock, 'lock', lock]


def other_idle():
    for path in Path('/proc').iterdir():
        if not path.name.isdigit(): continue
        try:
            if path.stat().st_uid == os.getuid() and (path / 'comm').read_text().strip() in ('swayidle', 'hypridle'):
                return True
        except (OSError, UnicodeError): pass
    return False


def run(source, config, seconds, runtime):
    if not shutil.which('swayidle'): raise ValueError('swayidle is required for idle integration')
    if not (os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') or os.environ.get('SWAYSOCK')):
        raise ValueError('Start idle integration inside Hyprland or Sway')
    directory = runtime.runtime_dir()
    descriptor = runtime.lock_fd_for(directory / 'idle.lock')
    child = None
    previous = {}
    try:
        try: fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: raise ValueError('Hello Lock idle integration is already running')
        if other_idle(): raise ValueError('Another swayidle/hypridle daemon is running; configure one idle owner')
        runtime.runpy.run_path(str(source / 'bin/hello-lock-pam'))['check']()
        child = subprocess.Popen(command(source, config, seconds), start_new_session=True)
        def stop(signum, frame):
            if child.poll() is None: child.terminate()
        previous = {sig: signal.signal(sig, stop) for sig in (signal.SIGINT, signal.SIGTERM)}
        return child.wait()
    finally:
        if child and child.poll() is None:
            child.terminate()
            try: child.wait(timeout=5)
            except subprocess.TimeoutExpired: child.kill(); child.wait()
        for sig, handler in previous.items(): signal.signal(sig, handler)
        os.close(descriptor)


def suspend(source, config, runtime):
    # Unlike a bounded logind delay hook, this explicit path aborts on failure.
    runtime.background(source, config)
    value = runtime.status()
    if not value.get('active') or not value.get('secure') or value.get('released') or value.get('phase') != 'locked':
        raise ValueError('Suspend aborted: compositor lock is not confirmed')
    return subprocess.run(['systemctl', 'suspend'], check=False).returncode
