"""Single-owner locker supervisor. Runtime records contain state, never input."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import resource
import re
import runpy
import secrets
import shutil
import signal
import stat
import subprocess
import tempfile
import time


def private(path, directory=False):
    info = path.lstat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('Locker runtime must be owned and private')
    if not (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)):
        raise ValueError('Unexpected locker runtime file type')


def runtime_dir(create=True):
    value = os.environ.get('XDG_RUNTIME_DIR', '')
    base = Path(value)
    if not value or not base.is_absolute(): raise ValueError('An absolute XDG_RUNTIME_DIR is required')
    info = base.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o066:
        raise ValueError('XDG_RUNTIME_DIR must be owned and exclude group/other read and write')
    display = os.environ.get('WAYLAND_DISPLAY', '')
    if not display: raise ValueError('A Wayland session is required')
    socket = Path(display) if Path(display).is_absolute() else base / display
    identity = hashlib.sha256(str(socket.absolute()).encode()).hexdigest()[:16]
    path = base / ('hello-lock-' + identity)
    if create: path.mkdir(mode=0o700, exist_ok=True)
    if path.exists(): private(path, True)
    return path


def read_json(path):
    try:
        private(path)
        if path.stat().st_size > 8192: raise ValueError('Oversized locker state')
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except FileNotFoundError:
        return {}


def write_json(path, value):
    descriptor, name = tempfile.mkstemp(dir=path.parent, prefix='.state-')
    try:
        with os.fdopen(descriptor, 'w') as stream: json.dump(value, stream)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def lock_fd(directory):
    return lock_fd_for(directory / 'owner.lock')


def lock_fd_for(path):
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    info = os.fstat(descriptor)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        os.close(descriptor); raise ValueError('Unsafe locker ownership file')
    return descriptor


def status():
    directory = runtime_dir(False)
    if not directory.exists(): return {'active': False, 'secure': None, 'phase': 'inactive'}
    descriptor = lock_fd(directory)
    try:
        try: fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB); active = False
        except BlockingIOError: active = True
        meta = read_json(directory / 'instance.json')
        state = read_json(directory / 'state.json')
        if state.get('generation') != meta.get('generation'): state = {}
        return dict(state, active=active, backend_pid=meta.get('pid'), recoveries=meta.get('recoveries', 0),
                    secure=state.get('secure') if active else None,
                    phase=state.get('phase', 'starting') if active else 'inactive')
    finally:
        os.close(descriptor)


def hyprland_state():
    """Conservative live-lock check used before asking Hyprland to lock/restore."""
    if not os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'): return None
    result = subprocess.run(['hyprctl', '-j', 'monitors'], capture_output=True, text=True, timeout=3)
    if result.returncode: raise ValueError('Could not establish compositor lock state')
    monitors = json.loads(result.stdout)
    if not isinstance(monitors, list) or not monitors: raise ValueError('No compositor output is available')
    if any(not isinstance(monitor, dict) or not isinstance(monitor.get('solitaryBlockedBy'), list) or
           any(not isinstance(item, str) for item in monitor['solitaryBlockedBy']) for monitor in monitors):
        raise ValueError('Compositor lock state is not yet readable')
    if any('LOCK' in monitor.get('solitaryBlockedBy', []) for monitor in monitors): return True
    if any('WORKSPACE' not in monitor.get('solitaryBlockedBy', ['WORKSPACE']) for monitor in monitors): return False
    raise ValueError('Compositor lock state is not yet readable')


def child_setup():
    # Passwords remain in process memory only; disable core dumps in the entire child tree.
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def claim(directory, descriptor, timeout=4):
    """Wait only for an authenticated owner to finish; never replace its lock."""
    deadline = time.monotonic() + timeout
    requested = set()
    while True:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except BlockingIOError:
            existing = status()
            finishing = existing.get('released') or existing.get('phase') in ('authenticated', 'authenticating')
            if existing.get('secure') and not finishing and existing.get('phase') == 'locked': return False
            generation = existing.get('generation')
            if finishing and isinstance(generation, str) and re.fullmatch('[a-f0-9]{32}', generation) and generation not in requested:
                write_json(directory / ('finish-' + generation + '.json'), {'generation':generation,'finish':True})
                requested.add(generation)
            if not finishing or time.monotonic() >= deadline:
                raise ValueError('A locker is starting or finishing; no second locker was created')
            time.sleep(.02)


def background(source, config, plain=False):
    # A before-sleep caller must not report readiness until the compositor confirms.
    runpy.run_path(str(source / 'bin/hello-lock-pam'))['check']()
    child = subprocess.Popen([str(source / 'bin/hello-lock'), 'lock', '--config-dir', str(config)] +
                             (['--plain'] if plain else []), start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ready = False
    try:
        end = time.monotonic() + 12
        while time.monotonic() < end:
            value = status()
            if value.get('active') and value.get('secure') and not value.get('released') and value.get('phase') == 'locked':
                ready = True
                return 0
            if child.poll() is not None and not (value.get('active') and not value.get('released') and value.get('phase') in ('starting','locked','lock-lost','authenticating','authenticated','unconfirmed')):
                raise ValueError('Locker did not confirm a secure session; inspect hello-lock status')
            time.sleep(.1)
        raise ValueError('Timed out waiting for compositor lock confirmation')
    finally:
        if not ready and child.poll() is None:
            child.terminate()
            try: child.wait(timeout=8)
            except subprocess.TimeoutExpired: child.kill(); child.wait()


def run(source, config, plain=False):
    # Set this before any capture thread or subprocess. Avoid preexec_fn in a
    # multithreaded supervisor; every child inherits the disabled core limit.
    child_setup()
    if os.getuid() == 0: raise ValueError('Run the locker as the desktop user, not root')
    runpy.run_path(str(source / 'bin/hello-lock-pam'))['check']()
    directory = runtime_dir()
    descriptor = lock_fd(directory)
    try:
        if not claim(directory, descriptor): return 0
        if not (os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') or os.environ.get('SWAYSOCK')):
            raise ValueError('This milestone supports Hyprland and Sway sessions')
        if hyprland_state() is True:
            raise ValueError('The compositor is already locked; refusing to take over another locker')
        with tempfile.TemporaryDirectory(prefix='stage-', dir=directory) as temporary:
            stage = Path(temporary)
            plugin = stage / 'plugin'; plugin.mkdir(mode=0o700)
            launcher = runpy.run_path(str(source / 'bin/hello-lock'))
            visual_files = launcher['VISUAL_FILES']
            for name in visual_files:
                item = source / name
                if name in ('LockView.qml', 'UnlockSplash.qml', 'TypingSound.qml') and not item.exists(): continue
                if item.is_dir(): shutil.copytree(item, plugin / name)
                else: shutil.copy2(item, plugin / name)
            shutil.copy2(source / 'standalone/lock.qml', stage / 'shell.qml')
            if (source / 'standalone/Extras.qml').exists():
                shutil.copy2(source / 'standalone/Extras.qml', stage / 'Extras.qml')
            session_id = secrets.token_hex(16)
            started_at = str(int(time.time() * 1000))
            stopping = False
            def stop(signum, frame):
                nonlocal stopping
                stopping = True
            previous = {sig: signal.signal(sig, stop) for sig in (signal.SIGTERM, signal.SIGINT)}
            child = None
            captures = None
            try:
                for restart in range(4):
                    generation = secrets.token_hex(16)
                    if restart == 0 and not plain:
                        try:
                            from capture import Captures
                            captures = Captures(plugin, config, directory, generation, write_json)
                        except (OSError, ValueError, ImportError, RuntimeError): captures = None
                    env = dict(os.environ, HELLO_LOCK_SOURCE=str(plugin), HELLO_LOCK_CONFIG_DIR=str(config),
                               HELLO_LOCK_STATE=str(directory / 'state.json'), HELLO_LOCK_GENERATION=generation,
                               HELLO_LOCK_SESSION=session_id, HELLO_LOCK_STARTED=started_at, HELLO_LOCK_RECOVERY=str(restart),
                               HELLO_LOCK_CAPTURE=str(directory / ('capture-' + generation + '.json')),
                               HELLO_LOCK_CAPTURE_ACK=str(directory / ('capture-finished-' + generation + '.json')),
                               HELLO_LOCK_FINISH=str(directory / ('finish-' + generation + '.json')),
                               HELLO_STATUS_WEATHER_CACHE=os.environ.get('HELLO_STATUS_WEATHER_CACHE') or str(launcher['weather_cache'](config)),
                               HELLO_LOCK_PLAIN='1' if plain else '0', WAYLAND_DEBUG='',
                               QT_LOGGING_RULES='quickshell.service.pam.debug=false')
                    for key in ('QML_DEBUG_ARGS', 'QS_CONFIG_PATH', 'QS_CONFIG_NAME', 'QS_MANIFEST'):
                        env.pop(key, None)
                    with (stage / 'backend.log').open('ab') as log:
                        child = subprocess.Popen(['qs', '-n', '-p', str(stage)], env=env, stdout=log,
                                                 stderr=subprocess.STDOUT, pass_fds=(descriptor,),
                                                 start_new_session=True)
                        write_json(directory / 'instance.json', {'generation': generation, 'pid': child.pid, 'recoveries': restart})
                        confirmed = False
                        released = False
                        while child.poll() is None and not stopping:
                            state = read_json(directory / 'state.json')
                            if state.get('generation') == generation:
                                confirmed = confirmed or bool(state.get('secure') or state.get('everSecure'))
                                released = released or bool(state.get('released'))
                            if captures:
                                try: captures.poll(released)
                                except (OSError, ValueError): pass
                            time.sleep(0.1)
                        state = read_json(directory / 'state.json')
                        if state.get('generation') == generation:
                            confirmed = confirmed or bool(state.get('secure') or state.get('everSecure'))
                            released = released or bool(state.get('released'))
                        if stopping: return 130
                        if released:
                            # The compositor is already released and the backend
                            # has exited. Optional capture cleanup must not keep
                            # another genuine lock request waiting on ownership.
                            fcntl.flock(descriptor, fcntl.LOCK_UN)
                            return 0
                        if not confirmed or released:
                            text = (stage / 'backend.log').read_text(errors='replace')
                            import re
                            errors = [label for label in ('SyntaxError', 'ReferenceError', 'TypeError', 'Cannot assign', 'is not installed', 'is not a type', 'Unexpected token') if label in text]
                            locations = sorted(set(re.findall(r'([A-Za-z0-9_-]+\.qml:[0-9]+)', text)))
                            write_json(directory / 'state.json', dict(state, generation=generation, phase='failed', diagnostics=errors, locations=locations))
                            return 3
                    if captures:
                        try: captures.close()
                        except (OSError, ValueError): pass
                        captures = None
                    # A dead owner cannot release ext-session-lock. Recreate its UI,
                    # requiring a fresh PAM success; no cached grant survives a restart.
                    time.sleep(0.25)
                return 3
            finally:
                if child and child.poll() is None:
                    child.terminate()
                    try: child.wait(timeout=5)
                    except subprocess.TimeoutExpired: child.kill(); child.wait()
                if captures:
                    try: captures.close()
                    except (OSError, ValueError): pass
                try: (directory / ('finish-' + generation + '.json')).unlink(missing_ok=True)
                except OSError: pass
                for sig, handler in previous.items(): signal.signal(sig, handler)
    finally:
        os.close(descriptor)
