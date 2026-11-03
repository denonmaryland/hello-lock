#!/usr/bin/env python3
"""Real guest password tests. Inputs originate at QEMU's virtual keyboard."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import hashlib
import runpy
import re


def wait(predicate, timeout=15):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        value = predicate()
        if value: return value
        time.sleep(.1)
    raise RuntimeError('Guest authentication test timed out')


def run_tests(root):
    spec = importlib.util.spec_from_file_location('guest_session', Path(__file__).with_name('guest-session.py'))
    session = importlib.util.module_from_spec(spec); spec.loader.exec_module(session)
    session.require_guest()
    os.umask(0o077)
    home = Path.home()
    fixture = home / 'hello-feature-fixture'
    fixture.mkdir(mode=0o700, exist_ok=True)
    fakebin = fixture / 'bin'; fakebin.mkdir(mode=0o700, exist_ok=True)
    requests = fixture / 'weather-requests.jsonl'
    cues = fixture / 'sound-cues.jsonl'
    muted = fixture / 'muted'
    # Only external forecast/audio transports are fixtures. PAM remains native.
    scripts = {
        'curl': "import json,sys\nwith open(" + repr(str(requests)) + ", 'a') as f: f.write(json.dumps(sys.argv[-1]) + '\\n')\nprint('21°C|Clear')\n",
        'pw-play': "import pathlib,sys\nwith open(" + repr(str(cues)) + ", 'a') as f: f.write(pathlib.Path(sys.argv[-1]).name + '\\n')\n",
        'wpctl': "import pathlib\nprint('Volume: 0.50' + (' [MUTED]' if pathlib.Path(" + repr(str(muted)) + ").exists() else ''))\n"
    }
    for name, body in scripts.items():
        target = fakebin / name; target.write_text('#!/usr/bin/python3\n' + body); target.chmod(0o700)
    os.environ['PATH'] = str(fakebin) + ':' + os.environ['PATH']
    os.environ['XDG_STATE_HOME'] = str(fixture / 'state')
    os.environ['XDG_CACHE_HOME'] = str(fixture / 'cache')
    os.environ['HELLO_STATUS_WEATHER_URL'] = 'https://forecast.fixture.invalid'
    executable = root / 'bin/hello-lock'
    compositor = 'sway' if os.environ.get('SWAYSOCK') else 'hyprland'
    checks = []
    sequence = 0
    def command(*args): return subprocess.run(list(map(str, args)), capture_output=True, text=True, timeout=10)
    def rpc(action):
        nonlocal sequence
        sequence += 1
        temporary = home / 'vm-input.partial'
        temporary.write_text(json.dumps({'sequence': sequence, 'action': action, 'checks': list(checks), 'stage': stage}))
        temporary.replace(home / 'vm-input.json')
        def acknowledged():
            try:
                value = json.loads((home / 'vm-input-ack.json').read_text())
                if value.get('sequence') == sequence and value.get('failed'): raise RuntimeError('Host rejected virtual frame')
                return value.get('sequence') == sequence
            except (OSError, ValueError): return False
        wait(acknowledged, 40 if action in ('suspend_resume', 'suspend_s2idle', 'suspend_s2idle_logind', 'locked_frame', 'desktop_frame') else 15)
    def state():
        try:
            response = command(executable, 'status')
            return json.loads(response.stdout) if response.returncode == 0 else {}
        except (subprocess.TimeoutExpired, ValueError): return {}
    def compositor_locked():
        if compositor == 'hyprland':
            response = command('hyprctl', '-j', 'monitors')
            monitors = json.loads(response.stdout)
            return bool(monitors) and all('LOCK' in m.get('solitaryBlockedBy', []) for m in monitors)
        # Input and pixels are independent witnesses on Sway, which has no lock-state IPC.
        return state().get('secure') is True
    witness = subprocess.Popen(['qs', '-n', '-p', str(root / 'tests/vm/sentinel.qml')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    def witness_call(method):
        response = command('qs', 'ipc', '-p', root / 'tests/vm/sentinel.qml', 'call', 'witness', method)
        return json.loads(response.stdout) if method == 'status' and response.returncode == 0 else response.returncode == 0
    locker = None
    stage = 'desktop-witness'
    wake_diagnostics = None
    suspend_evidence = None
    logind_evidence = None
    package_diagnostic = {}
    try:
        wait(lambda: witness_call('status'))
        time.sleep(.5)
        rpc('desktop_key'); wait(lambda: witness_call('status').get('inputSeen'))
        witness_call('reset')
        checks.append('desktop-input-witness')
        rpc('desktop_frame')
        checks.append('desktop-pixel-witness')
        stage = 'native-package-install'
        login_digest = hashlib.sha256(Path('/etc/pam.d/login').read_bytes()).hexdigest()
        packager = runpy.run_path(str(root/'bin/hello-lock-package'))
        expected_payload = packager['payload'](root)
        package_code_hash = packager['code_hash'](expected_payload)
        packages = home / 'built-packages'; packages.mkdir(mode=0o700, exist_ok=True)
        package_kind = 'rpm' if compositor == 'sway' else 'arch'
        built = subprocess.run([str(root/'bin/hello-lock-package'), '--format', package_kind, '--version', '0.5.3', '--output-dir', str(packages)], capture_output=True, text=True, timeout=120)
        package_diagnostic = {'phase':'build', 'exit':built.returncode, 'labels':[label for label in ('error:', 'Bad exit status', 'Failed dependencies', 'Unpackaged file', 'not found', 'Permission denied') if label in built.stderr]}
        if built.returncode: raise RuntimeError('Native package build failed')
        package = next(packages.glob('*.rpm' if package_kind == 'rpm' else '*.pkg.tar.zst'))
        install_command = ['dnf','-y','install',str(package)] if package_kind == 'rpm' else ['pacman','--noconfirm','-U',str(package)]
        installed = subprocess.run(['sudo','-n',*install_command], capture_output=True, text=True, timeout=120)
        package_diagnostic = {'phase':'install', 'exit':installed.returncode, 'labels':[label for label in ('Error:', 'conflicting', 'nothing provides', 'Permission denied') if label in installed.stderr]}
        if installed.returncode: raise RuntimeError('Native package install failed')
        if hashlib.sha256(Path('/etc/pam.d/login').read_bytes()).hexdigest() != login_digest:
            raise RuntimeError('Package changed the login policy')
        for name, (data, mode) in expected_payload.items():
            installed_file = Path('/') / name
            if installed_file.read_bytes() != data or installed_file.stat().st_mode & 0o777 != mode:
                package_diagnostic = {'phase':'payload-check', 'file':name, 'bytes_differ':installed_file.read_bytes()!=data, 'mode':installed_file.stat().st_mode & 0o777, 'expected_mode':mode}
                raise RuntimeError('Installed package differs from reviewed payload')
        checks.append('native-package-install-preserves-login-policy')
        executable = Path('/usr/bin/hello-lock')
        profile = home / '.config/hello-lock-auth-test'; profile.mkdir(mode=0o700, exist_ok=True)
        settings = {'sounds': False, 'weather': False, 'motion': 'reduced', 'name': 'Guest', 'legendary': False,
                    'presetMode': 'cycle', 'selectedPreset': 'a', 'typingEffect': 'shuffle', 'typingSound': 'shuffle',
                    'brandingPresets': [
                        {'id':'a','name':'Fixture A','branding': {'logo':str(root/'symbols/prompt.svg'), 'symbolParts':[str(root/'symbols/prompt.svg'),str(root/'symbols/nova.svg')]}},
                        {'id':'b','name':'Fixture B','branding': {'logo':str(root/'symbols/nova.svg'), 'symbol':'@shuffle'}}]}
        def save_settings(): (profile / 'config.json').write_text(json.dumps(settings))
        save_settings()
        state_file = fixture / 'state/hello-lock-standalone' / (hashlib.sha256(str(profile.absolute()).encode()).hexdigest() + '.json')
        def selection():
            try: return json.loads(state_file.read_text())
            except (OSError, ValueError): return {}
        def chosen(preset): return state().get('extrasReady') and state().get('preset') == preset
        def lines(path): return path.read_text().splitlines() if path.exists() else []
        log = (home / 'auth-tests.log').open('w')
        def start(plain=False):
            return subprocess.Popen([str(executable), 'lock', '--config-dir', str(profile)] + (['--plain'] if plain else []), stdout=log, stderr=subprocess.STDOUT)
        def confirmed():
            value = state()
            return value.get('active') and value.get('secure') and not value.get('released') and compositor_locked()
        stage = 'first-lock'
        locker = start()
        wait(confirmed)
        checks.append('compositor-confirmed-lock')
        limits = Path('/proc') / str(state()['backend_pid']) / 'limits'
        if not re.search(r'Max core file size\s+0\s+0\s+bytes', limits.read_text()): raise RuntimeError('Locker core dumps are not disabled')
        checks.append('backend-core-dumps-disabled')
        wait(lambda: chosen('b'))
        first_session = selection()['session']
        checks.append('confirmed-lock-branding-selection')
        stage = 'locked-frame'
        rpc('locked_frame')
        rpc('desktop_key')
        if witness_call('status').get('inputSeen'): raise RuntimeError('Locked desktop received input')
        # Clear the test key from the lock field with an actual virtual keyboard Ctrl+U.
        rpc('clear_input')
        duplicate = command(executable, 'lock', '--config-dir', profile)
        if duplicate.returncode or not confirmed(): raise RuntimeError('Repeated lock request failed')
        checks.append('repeated-lock')
        if selection().get('session') != first_session or not chosen('b'): raise RuntimeError('Repeated request advanced branding')
        stage = 'wrong-password'
        rpc('wrong_password')
        wait(lambda: state().get('attempts', 0) >= 1)
        if not confirmed() or witness_call('status').get('inputSeen'): raise RuntimeError('Wrong password exposed the desktop')
        checks.append('wrong-password-stays-locked')
        stage = 'correct-password'
        rpc('correct_password')
        wait(lambda: state().get('released'))
        locker.wait(timeout=12)
        if locker.returncode: raise RuntimeError('Authenticated locker exit failed')
        rpc('desktop_key'); wait(lambda: witness_call('status').get('inputSeen'))
        checks.append('real-password-unlock')
        checks.append('installed-package-real-pam-unlock')
        stage = 'native-package-removal'
        before_profile = (profile/'config.json').read_bytes()
        remove_command = ['dnf','-y','remove','hello-lock-standalone'] if package_kind == 'rpm' else ['pacman','--noconfirm','-R','hello-lock-standalone']
        removed = subprocess.run(['sudo','-n',*remove_command], capture_output=True, text=True, timeout=120)
        if removed.returncode or Path('/usr/bin/hello-lock').exists(): raise RuntimeError('Native package removal failed')
        if (profile/'config.json').read_bytes() != before_profile or hashlib.sha256(Path('/etc/pam.d/login').read_bytes()).hexdigest() != login_digest:
            raise RuntimeError('Package removal changed user preferences or login policy')
        checks.append('native-package-removal-preserves-preferences')
        executable = root/'bin/hello-lock'
        installed = command('sudo','-n',root/'bin/hello-lock-pam','install')
        if installed.returncode: raise RuntimeError('Source PAM policy setup failed')
        witness_call('reset')
        # The independent fallback UI must authenticate with the same actual PAM stack.
        stage = 'crash-recovery'
        locker = start(True)
        wait(confirmed)
        stage = 'recovery-branding-selection'
        wait(lambda: chosen('a'))
        crash_session = selection()['session']
        before = state()['backend_pid']
        os.kill(before, signal.SIGKILL)
        stage = 'recovery-backend-replacement'
        wait(lambda: state().get('backend_pid') not in (None, before) and confirmed())
        if witness_call('status').get('inputSeen'): raise RuntimeError('Crash exposed the desktop')
        checks.append('backend-crash-recovery')
        wait(lambda: chosen('a'))
        if selection().get('session') != crash_session: raise RuntimeError('Recovery advanced branding')
        checks.append('rotation-once-across-requests-and-crashes')
        rpc('correct_password')
        wait(lambda: state().get('released'))
        locker.wait(timeout=12)
        if locker.returncode: raise RuntimeError('Recovered locker exit failed')
        rpc('desktop_key'); wait(lambda: witness_call('status').get('inputSeen'))
        checks.append('fallback-pam-unlock')
        witness_call('reset')
        stage = 'background-readiness'
        background = command(executable, 'lock', '--background', '--plain', '--config-dir', profile)
        if background.returncode or not confirmed(): raise RuntimeError('Background readiness was not secure')
        checks.append('background-confirmation-barrier')
        stage = 'background-password-input'
        rpc('wrong_password')
        wait(lambda: state().get('attempts', 0) >= 1)
        if not confirmed(): raise RuntimeError('Background wrong password released the lock')
        checks.append('background-password-input')
        stage = 'suspend-resume'
        suspend_mode = os.environ.get('HELLO_LOCK_VM_SUSPEND', 's2idle')
        if suspend_mode == 's3':
            rpc('suspend_resume')
        else:
            rpc('suspend_s2idle')
            suspend_evidence = json.loads((home / 'vm-suspend-evidence.json').read_text())
        # This lab has no idle daemon. Wake outputs explicitly, as a desktop's
        # on-resume policy would; a powered-off QEMU placeholder is not evidence.
        if compositor == 'hyprland':
            modern = (home / '.config/hypr/hyprland.lua').exists()
            off = command('hyprctl', 'dispatch', 'hl.dsp.dpms({state="off"})' if modern else 'dpms off')
            time.sleep(.3)
            wake = command('hyprctl', 'dispatch', 'hl.dsp.dpms({state="on"})' if modern else 'dpms on')
        else:
            off = command('swaymsg', 'output', '*', 'power', 'off')
            time.sleep(.3)
            wake = command('swaymsg', 'output', '*', 'power', 'on')
        if off.returncode or wake.returncode:
            stage = 'output-wake-failed'
            text = (wake.stdout + wake.stderr).lower()
            wake_diagnostics = {'exit': wake.returncode,
                                'labels': [label for label in ('unknown command', 'invalid command', 'failed to connect', 'unable to connect', 'failed to commit', 'unable to retrieve') if label in text]}
            raise RuntimeError('Guest output wake failed')
        time.sleep(1)
        wait(confirmed)
        rpc('desktop_key')
        if witness_call('status').get('inputSeen'): raise RuntimeError('Resume exposed desktop input')
        rpc('clear_input'); rpc('locked_frame')
        checks.append('guest-suspend-resume-' + suspend_mode)
        if compositor == 'hyprland':
            stage = 'virtual-outputs'
            for _ in range(2):
                if command('hyprctl', 'output', 'create', 'headless', 'HELLO-QA').returncode:
                    raise RuntimeError('Virtual output creation failed')
                wait(lambda: state().get('outputs', 0) >= 2 and confirmed())
                # Exercise a different scale on the added virtual output only.
                modern = (home / '.config/hypr/hyprland.lua').exists()
                scale = command('hyprctl', 'eval', 'hl.monitor({output="HELLO-QA",mode="1280x800@60",position="auto",scale=1.25})') if modern else command('hyprctl', 'keyword', 'monitor', 'HELLO-QA,1280x800@60,auto,1.25')
                if scale.returncode:
                    raise RuntimeError('Mixed scale configuration failed')
                wait(confirmed)
                wait(lambda: any(m['name'] == 'HELLO-QA' and abs(m.get('scale', 0) - 1.25) < .01
                                 for m in json.loads(command('hyprctl', '-j', 'monitors').stdout)))
                if command('hyprctl', 'output', 'remove', 'HELLO-QA').returncode:
                    raise RuntimeError('Virtual output removal failed')
                wait(lambda: state().get('outputs') == 1 and confirmed())
            checks.append('virtual-output-add-remove-mixed-scale')
        stage = 'post-resume-password'
        rpc('correct_password')
        wait(lambda: state().get('released'))
        wait(lambda: not state().get('active'))
        rpc('desktop_key'); wait(lambda: witness_call('status').get('inputSeen'))
        checks.append('post-resume-pam-unlock')
        witness_call('reset')
        stage = 'missing-visuals'
        graphics = [root / 'LockView.qml', root / 'UnlockSplash.qml']
        try:
            for graphic in graphics: graphic.rename(graphic.with_suffix('.disabled'))
            locker = start()
            wait(confirmed)
            rpc('locked_frame')
            rpc('correct_password')
            wait(lambda: state().get('released'))
            locker.wait(timeout=12)
            if locker.returncode: raise RuntimeError('Missing-visual fallback exit failed')
            rpc('desktop_key'); wait(lambda: witness_call('status').get('inputSeen'))
            checks.append('missing-visuals-real-pam-fallback')
        finally:
            for graphic in graphics:
                disabled = graphic.with_suffix('.disabled')
                if disabled.exists(): disabled.rename(graphic)
        if lines(requests) or lines(cues): raise RuntimeError('Disabled extras performed network/audio work')
        checks.append('weather-and-sounds-off-remain-silent')
        witness_call('reset')
        stage = 'weather-and-cues'
        settings.update(weather=True, weatherLocation='Fixture Town', weatherUnit='metric', sounds=True,
                        unlockAnimation=False, typingSound='off')
        save_settings()
        (profile / 'sound.conf').write_text('QUIET_START=\nQUIET_END=\nVOLUME=0.4\n')
        launcher = runpy.run_path(str(executable))
        weather_cache = launcher['weather_cache'](profile)
        locker = start(True); wait(confirmed)
        wait(lambda: state().get('statusReady') and weather_cache.exists())
        cached = json.loads(weather_cache.read_text())
        if cached.get('temp') != '21°C' or cached.get('unit') != 'metric': raise RuntimeError('Standalone weather did not populate its cache')
        wait(lambda: 'lock.wav' in lines(cues))
        rpc('wrong_password'); wait(lambda: state().get('attempts', 0) >= 1)
        wait(lambda: 'error.wav' in lines(cues))
        rpc('correct_password'); wait(lambda: state().get('released'))
        locker.wait(timeout=12)
        wait(lambda: 'unlock-short.wav' in lines(cues))
        if len(lines(requests)) != 1: raise RuntimeError('Unexpected forecast request count')
        env = dict(os.environ, HELLO_LOCK_CONFIG_DIR=str(profile), HELLO_STATUS_WEATHER_CACHE=str(weather_cache))
        status = subprocess.run([str(root/'bin/hello-status'),'--standalone','--location','Fixture Town','--unit','metric'], env=env, capture_output=True, text=True, timeout=5)
        if status.returncode or json.loads(status.stdout).get('temp') != '21°C' or len(lines(requests)) != 1:
            raise RuntimeError('Fresh forecast cache was not reused')
        settings['weather'] = False; save_settings()
        status = subprocess.run([str(root/'bin/hello-status'),'--standalone'], env=env, capture_output=True, text=True, timeout=5)
        if status.returncode or json.loads(status.stdout).get('temp') is not None or len(lines(requests)) != 1:
            raise RuntimeError('Disabling weather did not stop requests')
        checks += ['forecast-opt-in-cache-and-opt-out', 'lock-error-unlock-cue-dispatch']
        stage = 'muted-cues'
        muted.touch(); before_cues = lines(cues)
        locker = start(True); wait(confirmed); wait(lambda: state().get('extrasReady'))
        rpc('correct_password'); wait(lambda: state().get('released')); locker.wait(timeout=12)
        if lines(cues) != before_cues: raise RuntimeError('Muted output played a cue')
        checks.append('cue-mute-policy')
        muted.unlink()
        stage = 'missing-optional-features'
        settings['motion'] = 'auto'; save_settings()
        optional = [root/'TypingSound.qml', root/'standalone/Extras.qml', root/'platform/Motion.qml']
        try:
            for component in optional: component.rename(component.with_suffix('.disabled'))
            locker = start(True); wait(confirmed)
            rpc('correct_password'); wait(lambda: state().get('released')); locker.wait(timeout=12)
            if locker.returncode: raise RuntimeError('Missing optional features blocked authentication')
            checks.append('missing-audio-status-component-pam-fallback')
        finally:
            for component in optional:
                disabled = component.with_suffix('.disabled')
                if disabled.exists(): disabled.rename(component)
        stage = 'relock-during-decoration'
        settings.update(sounds=False, weather=False, unlockAnimation=True, unlockDuration=8000, motion='full')
        save_settings()
        locker = start(); wait(confirmed)
        rpc('correct_password'); wait(lambda: state().get('released'))
        old_locker = locker
        locker = start(True)
        wait(confirmed, 12)
        old_locker.wait(timeout=5)
        rpc('correct_password'); wait(lambda: state().get('released')); locker.wait(timeout=12)
        checks.append('relock-during-post-unlock-decoration')
        stage = 'motion-crt-and-rapid-relocks'
        settings.update(sounds=False, weather=False, powerDown=True, unlockAnimation=False)
        for motion in ('auto','full','reduced'):
            settings['motion'] = motion; save_settings()
            locker = start(); wait(confirmed)
            wait(lambda: state().get('captureObserved') and state().get('captureFinished', 0) >= 1)
            expected_calm = motion != 'full'  # Both guest compositor profiles disable animation.
            if state().get('calm') is not expected_calm: raise RuntimeError('Automatic/explicit motion policy mismatch')
            rpc('correct_password'); wait(lambda: state().get('released')); locker.wait(timeout=12)
            if locker.returncode: raise RuntimeError('Rapid relock failed')
            wait(lambda: not list(Path(os.environ['XDG_RUNTIME_DIR']).glob('hello-lock-snapshot-*')))
        checks += ['automatic-and-explicit-motion', 'real-crt-capture-and-private-cleanup', 'rapid-relocks-fresh-pam']
        if compositor == 'hyprland':
            stage = 'automatic-motion-enabled'
            modern = (home/'.config/hypr/hyprland.lua').exists()
            toggle = command('hyprctl','eval','hl.config({animations={enabled=true}})') if modern else command('hyprctl','keyword','animations:enabled','1')
            if toggle.returncode or toggle.stdout.strip() != 'ok': raise RuntimeError('Guest animation toggle failed')
            value = json.loads(command('hyprctl','-j','getoption','animations:enabled').stdout)
            if value.get('bool', value.get('int')) not in (True,1): raise RuntimeError('Guest animation precondition did not apply')
            try:
                settings['motion'] = 'auto'; save_settings()
                locker = start(True); wait(confirmed)
                wait(lambda: state().get('calm') is False)
                rpc('correct_password'); wait(lambda: state().get('released')); locker.wait(timeout=12)
                checks.append('automatic-motion-follows-enabled-animations')
            finally:
                if modern: command('hyprctl','eval','hl.config({animations={enabled=false}})')
                else: command('hyprctl','keyword','animations:enabled','0')

        stage = 'idle-timeout'
        daemon = subprocess.Popen([str(executable),'idle','--idle-seconds','2','--config-dir',str(profile)], stdout=log, stderr=subprocess.STDOUT)
        try:
            wait(confirmed, 20)
            rpc('correct_password'); wait(lambda: state().get('released'))
            wait(lambda: not state().get('active'))
            checks.append('real-idle-timeout-pam-unlock')
        finally:
            daemon.terminate(); daemon.wait(timeout=8)
        stage = 'logind-idle-hooks'
        daemon = subprocess.Popen([str(executable),'idle','--idle-seconds','86400','--config-dir',str(profile)], stdout=log, stderr=subprocess.STDOUT)
        try:
            time.sleep(1)
            if daemon.poll() is not None: raise RuntimeError('Idle daemon did not start')
            if command('loginctl','lock-session',os.environ['XDG_SESSION_ID']).returncode: raise RuntimeError('Logind lock request failed')
            wait(confirmed, 20)
            rpc('correct_password'); wait(lambda: state().get('released')); wait(lambda: not state().get('active'))
            checks.append('logind-lock-event-pam-unlock')
            rpc('suspend_s2idle_logind')
            evidence = json.loads((home/'vm-suspend-evidence.json').read_text())
            logind_evidence = evidence
            if evidence.get('pre_sleep_secure') is not True: raise RuntimeError('Before-sleep hook did not secure the session')
            wait(confirmed)
            rpc('locked_frame'); rpc('correct_password'); wait(lambda: state().get('released')); wait(lambda: not state().get('active'))
            checks.append('logind-before-sleep-confirmed-lock-and-pam-resume')
        finally:
            daemon.terminate(); daemon.wait(timeout=8)
        stage = 'idle-user-unit-lifetime'
        manager_env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS='unix:path='+str(Path(os.environ['XDG_RUNTIME_DIR'])/'bus'))
        def manager(*args):
            return subprocess.run(['systemctl','--user',*args],env=manager_env,capture_output=True,text=True,timeout=25)
        imported = manager('import-environment','WAYLAND_DISPLAY','XDG_RUNTIME_DIR','QT_QPA_PLATFORM',
                           'HYPRLAND_INSTANCE_SIGNATURE' if compositor == 'hyprland' else 'SWAYSOCK')
        if imported.returncode: raise RuntimeError('Guest user manager unavailable')
        unit_dir = home/'hello-unit-fixture'; unit_dir.mkdir(mode=0o700,exist_ok=True)
        unit_name = 'hello-lock-idle-fixture.service'
        unit = unit_dir/unit_name
        text = (root/'standalone/hello-lock-idle.service').read_text()
        # Paths below are fixed by require_guest(), never external input.
        text = text.replace('ExecStart=/usr/bin/hello-lock idle',
            'ExecStart='+str(executable)+' idle --idle-seconds 86400 --config-dir '+str(profile))
        unit.write_text(text)
        try:
            if manager('link','--runtime',str(unit)).returncode or manager('daemon-reload').returncode:
                raise RuntimeError('Guest user-unit setup failed')
            if manager('start',unit_name).returncode: raise RuntimeError('Guest user-unit start failed')
            time.sleep(1)
            if command('loginctl','lock-session',os.environ['XDG_SESSION_ID']).returncode: raise RuntimeError('User-unit lock event failed')
            wait(confirmed,20)
            if manager('stop',unit_name).returncode: raise RuntimeError('Guest user-unit stop failed')
            if not confirmed(): raise RuntimeError('Stopping idle unit stopped its active locker')
            rpc('desktop_key')
            if witness_call('status').get('inputSeen'): raise RuntimeError('Idle-unit stop exposed desktop input')
            rpc('clear_input'); rpc('correct_password')
            wait(lambda: state().get('released')); wait(lambda: not state().get('active'))
            checks.append('idle-unit-stop-preserves-locker-and-real-pam')
        finally:
            manager('stop',unit_name); manager('disable',unit_name); manager('daemon-reload')
            unit.unlink(missing_ok=True)
        return {'authentication_tested': True, 'authentication_checks': checks, 'authentication_status': 'passed', 'suspend_evidence': suspend_evidence, 'logind_suspend_evidence': logind_evidence, 'package_file': package.name, 'package_code_sha256': package_code_hash}
    except BaseException as error:
        diagnostic_text = (home / 'auth-tests.log').read_text(errors='replace') if (home / 'auth-tests.log').exists() else ''
        return {'authentication_tested': True, 'authentication_checks': checks, 'authentication_status': 'failed', 'authentication_error': type(error).__name__, 'authentication_stage': stage,
                'authentication_error_code': 'test-timeout' if str(error) == 'Guest authentication test timed out' else 'output-wake-failed' if str(error) == 'Guest output wake failed' else 'other',
                'package_diagnostic': package_diagnostic,
                'package_file': package.name if 'package' in locals() else None,
                'locker_exit': locker.poll() if locker else None,
                'locker_trace_locations': re.findall(r'File "[^"\n]*/([A-Za-z0-9_.-]+)", line ([0-9]+)', diagnostic_text),
                'locker_diagnostics': [label for label in ('A locker is starting or finishing', 'Unsafe', 'already locked', 'SyntaxError', 'ReferenceError', 'TypeError', 'ModuleNotFoundError', 'FileNotFoundError', 'PermissionError', 'NameError', 'KeyError', 'SubprocessError', 'RuntimeError') if label in diagnostic_text],
                'output_wake_diagnostics': wake_diagnostics,
                'suspend_evidence': suspend_evidence, 'logind_suspend_evidence': logind_evidence,
                'authentication_state': {k:v for k,v in state().items() if k in ('phase','active','secure','released','attempts','authenticating','outputs','extrasReady','preset','statusReady','calm','captureObserved','captureFinished','diagnostics','locations')}}
    finally:
        if locker and locker.poll() is None:
            locker.terminate()
            try: locker.wait(timeout=8)
            except subprocess.TimeoutExpired: locker.kill(); locker.wait()
        witness.terminate()
        try: witness.wait(timeout=8)
        except subprocess.TimeoutExpired: witness.kill(); witness.wait()
