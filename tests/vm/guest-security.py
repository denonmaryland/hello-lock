#!/usr/bin/env python3
"""Real service/Wayland/PAM integration, restricted to the disposable guest."""
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import time


def require_guest():
    spec = importlib.util.spec_from_file_location('guest_session', Path(__file__).with_name('guest-session.py'))
    session = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(session)
    session.require_guest()
    if Path('/etc/hello-lock-vm-profile').read_text().strip() != 'arch':
        raise RuntimeError('Security integration requires the disposable Arch guest')


def main():
    require_guest()  # Before any writes, process launches or lock operations.
    os.umask(0o077)
    home = Path.home()
    source = Path(__file__).resolve().parents[2]
    result = {'status': 'failed', 'stage': 'lock-loss', 'authentication_tested': False,
              'fingerprint_tested': False, 'full_omarchy_shell_tested': False,
              'os_id': platform.freedesktop_os_release().get('ID'), 'kernel': platform.release(),
              'checks': []}
    sequence = 0
    process = None
    try:
        # Guest stack is system-auth, with the production service name. This
        # tests real PAM passwords, not the host's exact PAM policy or hardware.
        subprocess.run(['sudo', '-n', 'install', '-m', '644', str(source / 'tests/vm/pam-password'),
                        '/etc/pam.d/omarchy-lock-password'], check=True, capture_output=True)
        config = home / '.config/hello-lock'
        config.mkdir(parents=True, exist_ok=True)
        (config / 'config.json').write_text(json.dumps({'sounds': False, 'weather': False, 'powerDown': False,
                                                      'motion': 'reduced', 'brand': 'VM security test'}))
        state = home / '.local/state/hello-lock'
        state.mkdir(parents=True, exist_ok=True)
        (state / 'onboarded').write_text('1\n')
        for _ in range(100):
            monitors = subprocess.run(['hyprctl', '-j', 'monitors'], capture_output=True, text=True, timeout=5)
            if monitors.returncode == 0 and json.loads(monitors.stdout): break
            time.sleep(.3)
        else: raise RuntimeError('Guest output unavailable')
        result['versions'] = {name: subprocess.run(command, capture_output=True, text=True, timeout=5).stdout.strip()
                              for name, command in [('hyprland', ['Hyprland', '--version']), ('quickshell', ['qs', '--version'])]}
        result['source_manifest'] = json.loads((source / 'omarchy/source-manifest.json').read_text())
        with tempfile.TemporaryDirectory(prefix='lock-security-') as directory:
            stage = Path(directory)
            (stage / 'plugin').symlink_to(source, target_is_directory=True)
            for module in ('Commons', 'Ui'):
                (stage / module).symlink_to(source / 'omarchy/shell' / module, target_is_directory=True)
            shutil.copyfile(source / 'tests/vm/security.qml', stage / 'shell.qml')
            env = dict(os.environ, HELLO_LOCK_DISPOSABLE_GUEST='1', HELLO_STATUS_WEATHER_CACHE=str(home/'weather.json'))
            with (home / 'security-tests.log').open('w') as log:
                process = subprocess.Popen(['qs', '-p', str(stage), '--no-color'], env=env, stdout=log, stderr=subprocess.STDOUT)

                def ipc(target, action, *arguments):
                    call = subprocess.run(['qs', 'ipc', '-p', str(stage), 'call', target, action, *arguments],
                                          capture_output=True, text=True, timeout=5)
                    if call.returncode: raise RuntimeError('Guest IPC failed: ' + action)
                    return call.stdout.strip()

                def status(): return json.loads(ipc('qa', 'status'))

                def wait(predicate, seconds=10):
                    deadline = time.monotonic() + seconds
                    while time.monotonic() < deadline:
                        if process.poll() is not None: raise RuntimeError('Guest service exited')
                        try:
                            value = status()
                            if predicate(value): return value
                        except (RuntimeError, ValueError): pass
                        time.sleep(.08)
                    raise RuntimeError('Guest state timeout')

                def check(condition, name):
                    if not condition: raise RuntimeError('Failed: ' + name)
                    result['checks'].append(name)

                def compositor_locked():
                    outputs = json.loads(subprocess.run(['hyprctl', '-j', 'monitors'], capture_output=True,
                                                        text=True, check=True, timeout=5).stdout)
                    return bool(outputs) and all('LOCK' in output.get('solitaryBlockedBy', []) for output in outputs)

                def monitor_names():
                    outputs = json.loads(subprocess.run(['hyprctl', '-j', 'monitors'], capture_output=True,
                                                        text=True, check=True, timeout=5).stdout)
                    return {output['name'] for output in outputs}

                def covered_monitors():
                    # The fail-closed cover is an overlay layer; Hyprland lists it per output.
                    layers = json.loads(subprocess.run(['hyprctl', '-j', 'layers'], capture_output=True,
                                                       text=True, check=True, timeout=5).stdout)
                    return {name for name, monitor in layers.items()
                            if any(layer.get('namespace') == 'hello-lock-cover'
                                   for level in (monitor.get('levels') or {}).values() for layer in level)}

                def wait_cover(present, seconds=5):
                    deadline = time.monotonic() + seconds
                    while time.monotonic() < deadline:
                        names = monitor_names()
                        if (covered_monitors() >= names) if present else not covered_monitors(): return True
                        time.sleep(.08)
                    return False

                def keyboard(action):
                    nonlocal sequence
                    sequence += 1
                    temporary = home / 'vm-input.partial'
                    temporary.write_text(json.dumps({'sequence': sequence, 'action': action}))
                    temporary.replace(home / 'vm-input.json')
                    deadline = time.monotonic() + 30
                    while time.monotonic() < deadline:
                        ack = home / 'vm-input-ack'
                        if ack.exists() and ack.read_text() == str(sequence): return
                        time.sleep(.1)
                    raise RuntimeError('QMP input timeout')

                def authenticate():
                    keyboard('password')
                    wait(lambda value: not value['secure'] and not value['requested'], 15)
                    time.sleep(.8)
                    check(not status()['requested'] and not compositor_locked(), 'authenticated unlock remains released')
                    check(wait_cover(False, 3) and not status()['covered'], 'authenticated unlock removes the fail-closed cover')
                    # Dismiss the cosmetic splash through its normal input path
                    # on the next lock; beginLock() also finishes it directly.

                wait(lambda value: value['ready'])
                check(ipc('lock', 'lock') == 'ok', 'lock request accepted')
                wait(lambda value: value['secure'])
                check(compositor_locked(), 'compositor confirms real lock on all outputs')
                check(wait_cover(True) and status()['covered'], 'fail-closed cover is mapped behind the lock on every output')
                check(ipc('lock', 'lock') == 'ok' and status()['secure'], 'repeated lock preserves secure state')
                keyboard('wrong-password')
                wait(lambda value: value['attempts'] == 1 and not value['authenticating'], 15)
                check(status()['secure'] and compositor_locked(), 'wrong password rejected while compositor stays locked')
                authenticate()
                result['authentication_tested'] = True

                for _ in range(3):
                    ipc('lock', 'lock')
                    wait(lambda value: value['secure'])
                    before = status()['lossEvents']
                    check(ipc('qa', 'drop') == 'dropped', 'real lock released by guest-only fault injection')
                    # Taken at once, inside the relock window: the cover, not the desktop.
                    exposed = not compositor_locked()
                    check(covered_monitors() >= monitor_names(), 'lost lock leaves the cover on every output')
                    result.setdefault('cover_during_loss', []).append({'compositor_unlocked': exposed, 'covered': True})
                    recovered = wait(lambda value: value['secure'] and value['lossEvents'] > before)
                    check(recovered['requested'] and compositor_locked(), 'lost lock reacquired without authentication')
                    authenticate()

                ipc('lock', 'lock')
                wait(lambda value: value['secure'])
                modern = 'hl.' in (home / '.config/hypr/hyprland.lua').read_text() if (home / '.config/hypr/hyprland.lua').exists() else False
                for _ in range(3):
                    for state in ('off', 'on'):
                        dispatch = 'hl.dsp.dpms({ state = "' + state + '" })' if modern else 'dpms ' + state
                        subprocess.run(['hyprctl', 'dispatch', dispatch], capture_output=True, check=True, timeout=5)
                        time.sleep(.6)
                    wait(lambda value: value['secure'] and value['requested'])
                    check(compositor_locked(), 'DPMS cycle ends with compositor lock held')
                    check(wait_cover(True), 'DPMS cycle keeps the cover on every output')
                for _ in range(2):
                    subprocess.run(['hyprctl', 'output', 'create', 'headless', 'LOCK-QA'], capture_output=True, check=True, timeout=5)
                    time.sleep(.8)
                    wait(lambda value: value['secure'] and compositor_locked())
                    outputs = json.loads(subprocess.run(['hyprctl', '-j', 'monitors'], capture_output=True,
                                                        text=True, check=True, timeout=5).stdout)
                    check(any(output['name'] == 'LOCK-QA' for output in outputs) and len(outputs) >= 2,
                          'new virtual output is present and compositor-protected')
                    check(wait_cover(True) and 'LOCK-QA' in covered_monitors(), 'new virtual output gets the cover')
                    subprocess.run(['hyprctl', 'output', 'remove', 'LOCK-QA'], capture_output=True, check=True, timeout=5)
                    time.sleep(.8)
                    wait(lambda value: value['secure'] and value['requested'] and compositor_locked())
                    check(True, 'virtual output removal preserves compositor lock')
                    check(wait_cover(True), 'cover follows output changes')
                authenticate()
                wait(lambda value: not value['splashShown'])
                before = status()['animatedTransitions']
                check(ipc('qa', 'saveTiming', 'false') == 'saving', 'instant settings update submitted')
                wait(lambda value: value['watcherDisabled'] and not value['animationEnabled'] and value['savedName'] == 'Guest saved settings')
                check(True, 'real service reloads Settings save without filesystem notifications')
                ipc('lock', 'lock')
                wait(lambda value: value['secure'])
                keyboard('wrong-password')
                wait(lambda value: value['attempts'] == 1 and not value['authenticating'], 15)
                check(status()['secure'] and compositor_locked(), 'instant mode rejects wrong password')
                authenticate()
                check(status()['animatedTransitions'] == before and not status()['splashShown'], 'real PAM instant unlock skips visual gate and splash')
                check(ipc('qa', 'saveTiming', 'true') == 'saving', 'animated settings update submitted')
                wait(lambda value: value['animationEnabled'])
                ipc('lock', 'lock')
                wait(lambda value: value['secure'])
                authenticate()
                check(status()['animatedTransitions'] == before + 1, 'reenabling animations restores the visual gate')
                check(not status()['splashShown'], '600 ms cap ends the real post-unlock overlay')
                result['recovery_ms'] = status()['recoveryMs']
                result['loss_events'] = status()['lossEvents']
                check(len(result['recovery_ms']) >= 3, 'all injected losses produced measured secure recovery')
                result['pam_policy'] = 'Arch guest system-auth under omarchy-lock-password'
                result['status'] = 'passed'
                ipc('qa', 'quit')
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        # Errors contain no keyboard payload or raw service log.
        result['error'] = str(error) if isinstance(error, RuntimeError) else type(error).__name__
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
        temporary = home / 'vm-result.partial'
        temporary.write_text(json.dumps(result))
        temporary.replace(home / 'vm-result.json')


if __name__ == '__main__':
    main()
