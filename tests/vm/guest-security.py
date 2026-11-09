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
                    value = None
                    while time.monotonic() < deadline:
                        if process.poll() is not None: raise RuntimeError('Guest service exited')
                        try:
                            value = status()
                            if predicate(value): return value
                        except (RuntimeError, ValueError): pass
                        time.sleep(.08)
                    # Booleans only: names which flags were off, never any input.
                    off = sorted(key for key, flag in (value or {}).items() if flag is False)
                    try:
                        # The service's own event names (lock/secure/barrier states), never input.
                        result['service_events'] = [event for event in json.loads(ipc('qa', 'events')) if not event.startswith(('session-locked=', 'secure=', 'lock-lost', 'lock-pending'))][-60:]
                    except (RuntimeError, ValueError, subprocess.SubprocessError): pass
                    raise RuntimeError('Guest state timeout (false: ' + ', '.join(off) + ')')

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

                def layer_namespaces(output=None):
                    layers = json.loads(subprocess.run(['hyprctl', '-j', 'layers'], capture_output=True,
                                                       text=True, check=True, timeout=5).stdout)
                    return {layer.get('namespace') for name, monitor in layers.items() if output in (None, name)
                            for level in (monitor.get('levels') or {}).values() for layer in level}

                def frame(output=None):
                    # Composited pixels as the compositor would show them (grim, PPM).
                    data = subprocess.run(['grim', '-t', 'ppm'] + (['-o', output] if output else []) + ['-'],
                                          capture_output=True, check=True, timeout=10).stdout
                    fields, offset = [], 0
                    while len(fields) < 4:
                        while data[offset:offset + 1].isspace(): offset += 1
                        end = offset
                        while not data[end:end + 1].isspace(): end += 1
                        fields.append(data[offset:end]); offset = end
                    if fields[0] != b'P6' or fields[3] != b'255': raise RuntimeError('Unexpected grim frame')
                    pixels = data[offset + 1:]
                    count = magenta = black = 0
                    for index in range(0, len(pixels) - 2, 3 * 17):
                        r, g, b = pixels[index], pixels[index + 1], pixels[index + 2]
                        count += 1
                        magenta += r > 24 and b > 24 and g < 16
                        black += r < 12 and g < 12 and b < 12
                    return {'magenta': magenta, 'black': black / max(count, 1)}

                def console():
                    return subprocess.run(['sudo', '-n', 'fgconsole'], capture_output=True, text=True, timeout=5).stdout.strip()

                def until(predicate, seconds=5, step=.03):
                    deadline = time.monotonic() + seconds
                    while time.monotonic() < deadline:
                        if predicate(): return True
                        time.sleep(step)
                    return False

                def await_ack(number):
                    deadline = time.monotonic() + 30
                    while time.monotonic() < deadline:
                        ack = home / 'vm-input-ack'
                        if ack.exists() and ack.read_text() == str(number): return
                        time.sleep(.1)
                    raise RuntimeError('QMP input timeout')

                def keyboard(action, wait=True):
                    nonlocal sequence
                    sequence += 1
                    temporary = home / 'vm-input.partial'
                    temporary.write_text(json.dumps({'sequence': sequence, 'action': action}))
                    temporary.replace(home / 'vm-input.json')
                    if wait: await_ack(sequence)
                    return sequence

                def authenticate():
                    keyboard('password')
                    wait(lambda value: not value['secure'] and not value['requested'], 15)
                    time.sleep(.8)
                    check(not status()['requested'] and not compositor_locked(), 'authenticated unlock remains released')
                    check(wait_cover(False, 3) and not status()['covered'], 'authenticated unlock removes the fail-closed cover')
                    # Dismiss the cosmetic splash through its normal input path
                    # on the next lock; beginLock() also finishes it directly.

                wait(lambda value: value['ready'])
                # Marketplace #14051: no hidden lock view (and so no idle password
                # field for clipboard offers) until the preview is shown.
                def preview_loaded(): return json.loads(ipc('lock', 'status'))['previewLoaded']
                check(preview_loaded() is False, 'no preview lock view exists while the preview is hidden')
                check(ipc('lock', 'preview') == 'ok', 'settings preview opens')
                check(until(lambda: preview_loaded() is True and 'omarchy-lock-preview' in layer_namespaces(), 5),
                      'preview lock view is created when the preview opens')
                check(ipc('lock', 'hidePreview') == 'ok', 'settings preview closes')
                check(until(lambda: preview_loaded() is False and 'omarchy-lock-preview' not in layer_namespaces(), 5),
                      'preview lock view is destroyed when the preview closes')
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

                # Issue #2 reviews (T29, T32): hold recovery open and prove that,
                # with compositor animations on, the desktop stays covered and
                # inert for the whole time: no binding runs and no key reaches
                # any client, including a second exclusive overlay as it maps.
                marker, started = home / 'qa-bind-marker', home / 'qa-intruder-started'
                intruder_log = home / 'qa-intruder.log'
                for path in (marker, started, intruder_log): path.unlink(missing_ok=True)
                intruder_dir = home / 'qa-intruder'
                intruder_dir.mkdir(exist_ok=True)
                (intruder_dir / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Wayland
ShellRoot {
  PanelWindow {
    anchors { top: true; left: true }
    implicitWidth: 320; implicitHeight: 200
    color: "#00ff00"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qa-intruder"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    Item {
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) { console.warn("QA-INTRUDER-KEY " + event.key) }
    }
  }
}
''')

                def submap():
                    return subprocess.run(['hyprctl', 'submap'], capture_output=True, text=True, timeout=5).stdout.strip()

                def start_intruder():
                    log = intruder_log.open('a')
                    return subprocess.Popen(['qs', '-p', str(intruder_dir), '--no-color'], stdout=log, stderr=subprocess.STDOUT)

                def stop(child):
                    child.terminate()
                    try: child.wait(timeout=5)
                    except subprocess.TimeoutExpired: child.kill(); child.wait()

                def barrier_binds():
                    binds = json.loads(subprocess.run(['hyprctl', '-j', 'binds'], capture_output=True, text=True,
                                                      check=True, timeout=5).stdout)
                    return [bind for bind in binds if bind.get('submap') == 'hello-lock-barrier']

                def barrier_live():
                    found = barrier_binds()
                    return submap() == 'hello-lock-barrier' and len(found) == 1 and found[0].get('catch_all') is True

                def intruder_keys():
                    return intruder_log.read_text().count('QA-INTRUDER-KEY') if intruder_log.exists() else 0

                def opaque_new_output(name, label):
                    subprocess.run(['hyprctl', 'output', 'create', 'headless', name], capture_output=True, check=True, timeout=5)
                    try:
                        check(until(lambda: 'hello-lock-cover' in layer_namespaces(name), 5), label + ': new output gets a cover')
                        shot = frame(name)  # Taken as soon as it maps: a fade-in would still show magenta.
                        result.setdefault('new_output_frames', {})[label] = shot
                        check(shot['magenta'] == 0 and shot['black'] >= .99, label + ': new output cover is opaque from its first frame')
                    finally:
                        subprocess.run(['hyprctl', 'output', 'remove', name], capture_output=True, timeout=5)

                ipc('lock', 'lock')
                wait(lambda value: value['secure'])
                check(submap() == 'default', 'no barrier while the real lock holds (locked binds keep working)')
                # A config reload drops Lua rules: the next cover must still map opaque.
                subprocess.run(['hyprctl', 'reload'], capture_output=True, check=True, timeout=10)
                time.sleep(1)
                wait(lambda value: value['secure'] and value['requested'], 10)
                check(ipc('qa', 'hold') == 'holding', 'recovery held open by guest-only fault injection')
                held = wait(lambda value: value['holding'] and value['requested'] and not value['secure']
                            and value['covered'] and value['coverKeyboard'] and value['shortcutsInhibited'] and value['barrier'], 10)
                check(held['holdDrops'] >= 1, 'held recovery keeps the cover, keyboard, inhibitor and barrier')
                check(until(lambda: not compositor_locked(), 3), 'held recovery leaves the compositor unlocked')
                check(until(barrier_live, 3), 'Hyprland is in the barrier submap, one catchall bind, during recovery')
                shot = frame()
                result['held_frame'] = shot
                check(shot['magenta'] == 0 and shot['black'] >= .99, 'held recovery shows the opaque cover, not the desktop')
                opaque_new_output('LOCK-HOLD', 'after reload before loss')
                keyboard('bind-marker')
                time.sleep(1.2)
                check(not marker.exists(), 'exec keybinding stays inert while the lock is missing')
                keyboard('bind-intruder')
                time.sleep(1.5)
                check(not started.exists() and 'qa-intruder' not in layer_namespaces(),
                      'overlay keybinding stays inert while the lock is missing')
                # Chords and plain keys from before a second exclusive overlay maps
                # until well after the cover has taken the keyboard back.
                burst = keyboard('burst', wait=False)
                check(until(lambda: (home / 'vm-input-burst').exists() and (home / 'vm-input-burst').read_text() == str(burst), 15, .02),
                      'input burst started')
                before = status()['reclaims']
                intruder = start_intruder()
                try:
                    check(until(lambda: 'qa-intruder' in layer_namespaces(), 10, .02), 'second exclusive overlay maps during the burst')
                    # The cover gets the keyboard back either by its own reclaim or
                    # when a relock in the held loop hands focus back; either way
                    # the barrier, not focus, is what keeps input out meanwhile.
                    reclaimed = wait(lambda value: value['coverKeyboard'] and value['shortcutsInhibited'] and value['holding'], 5)
                    result['reclaim_events'] = reclaimed['reclaims'] - before
                    check(not reclaimed['secure'], 'cover has the keyboard again after a second exclusive overlay')
                    await_ack(burst)
                    time.sleep(.5)
                    check(not marker.exists(), 'no exec keybinding ran from overlay mapping through reclaim')
                    result['burst_intruder_keys'] = intruder_keys()
                    check(intruder_keys() == 0, 'no key reached the second overlay from mapping through reclaim')
                finally:
                    stop(intruder)
                # A reload during the loss clears the barrier's bind and the rule.
                subprocess.run(['hyprctl', 'reload'], capture_output=True, check=True, timeout=10)
                check(until(barrier_live, 5), 'reload during recovery rebuilds the barrier catchall')
                wait(lambda value: value['barrier'] and value['holding'] and value['covered'], 10)
                opaque_new_output('LOCK-RELOAD', 'reload during loss')
                keyboard('bind-marker')
                time.sleep(1.2)
                check(not marker.exists(), 'exec keybinding stays inert after a reload during recovery')
                keyboard('vt2')
                check(until(lambda: console() == '2', 5, .2), 'TTY switch still works during recovery (escape route)')
                keyboard('vt1')
                check(until(lambda: console() == '1', 5, .2), 'switching back returns to the session')
                wait(lambda value: value['holding'] and value['covered'], 10)
                check(not marker.exists() and not started.exists(), 'no keybinding ran during held recovery')
                check(ipc('qa', 'release') == 'released', 'held recovery released')
                wait(lambda value: value['secure'] and value['requested'], 10)
                check(compositor_locked(), 'released recovery relocks without authentication')
                check(submap() == 'hello-lock-barrier', 'the barrier lingers right after the relock (a flapping lock leaves no gap)')
                wait(lambda value: value['secure'] and not value['barrier'], 12)
                check(until(lambda: submap() == 'default', 3), 'the barrier lifts once the real lock has held')
                check(ipc('qa', 'clearEntry') == 'cleared', 'lock entry cleared before authenticating')
                authenticate()
                check(submap() == 'default', 'no barrier after authenticated unlock')
                # The probes are live: unlocked, the binding runs and keys arrive.
                intruder = start_intruder()
                try:
                    check(until(lambda: 'qa-intruder' in layer_namespaces(), 10), 'control overlay maps on the unlocked desktop')
                    time.sleep(.5)
                    keyboard('type-a')
                    check(until(lambda: intruder_keys() > 0, 3), 'control: keys reach an overlay when unlocked')
                finally:
                    stop(intruder)
                keyboard('bind-marker')
                check(until(marker.exists, 3), 'control: the exec keybinding runs when unlocked')
                marker.unlink(missing_ok=True)

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
                # A shell that dies during a loss must not strand the barrier: the
                # next start of the service resets it.
                ipc('lock', 'lock')
                wait(lambda value: value['secure'])
                check(ipc('qa', 'hold') == 'holding', 'final hold for the crash check')
                wait(lambda value: value['barrier'] and value['holding'], 10)
                check(until(lambda: not compositor_locked(), 3) and until(barrier_live, 3), 'barrier on before the crash')
                process.kill()
                process.wait()
                check(submap() == 'hello-lock-barrier', 'a killed service leaves the barrier behind')
                process = subprocess.Popen(['qs', '-p', str(stage), '--no-color'], env=env, stdout=log, stderr=subprocess.STDOUT)
                wait(lambda value: value['ready'], 20)
                check(until(lambda: submap() == 'default', 5), 'a restarted service resets the barrier')
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
