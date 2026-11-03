#!/usr/bin/env python3
"""Run the shared visual suite inside the disposable guest's compositor."""
import json
import os
from pathlib import Path
import subprocess
import sys
import platform
import time
import importlib.util
import re


def main(authentication=False):
    spec = importlib.util.spec_from_file_location('guest_session', Path(__file__).with_name('guest-session.py'))
    session = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(session)
    session.require_guest()
    os.umask(0o077)
    home = Path.home()
    root = Path(__file__).resolve().parents[2]
    profile_name = Path('/etc/hello-lock-vm-profile').read_text().strip()
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from profiles import verify_identity, get
    identity = platform.freedesktop_os_release()
    result = {'profile': profile_name, 'os_id': identity.get('ID'), 'os_version': identity.get('VERSION_ID'), 'kernel': platform.release(), 'status': 'failed', 'stage': 'visual-tests', 'authentication_tested': False}
    try:
        verify_identity(profile_name, identity, platform.release())
        version = subprocess.run(['qs','--version'],capture_output=True,text=True,timeout=5)
        match = re.search(r'[0-9]+\.[0-9]+\.[0-9]+',version.stdout + version.stderr)
        result['quickshell_version'] = match.group(0) if match else 'unknown'
        if Path('/usr/share/omarchy').exists():
            raise RuntimeError('Guest unexpectedly contains Omarchy')
        compositor = get(profile_name).get('compositor', 'Hyprland')
        output_command = ['swaymsg', '-r', '-t', 'get_outputs'] if compositor == 'Sway' else ['hyprctl', '-j', 'monitors']
        for _ in range(60):
            monitors = subprocess.run(output_command, capture_output=True, text=True, timeout=5)
            if monitors.returncode == 0 and json.loads(monitors.stdout): break
            time.sleep(.5)
        else:
            raise RuntimeError('No guest output became ready')
        env = dict(os.environ, HELLO_LOCK_QA_EXPECT_CALM='1', HELLO_LOCK_QA_IMAGE=str(home / 'settings-preview.png'),
                   HELLO_LOCK_QA_WEATHER_IMAGE=str(home / 'settings-weather-preview.png'))
        with (home / 'visual-tests.log').open('w') as log:
            test = subprocess.run([sys.executable, str(root / 'tests/run-standalone.py')], env=env,
                                  stdout=log, stderr=subprocess.STDOUT, timeout=120)
        result.update(status='passed' if test.returncode == 0 else 'failed', visual_suite_exit=test.returncode,
                      screenshot=(home / 'settings-preview.png').is_file(),
                      weather_screenshot=(home / 'settings-weather-preview.png').is_file(),
                      compositor=compositor, compositor_renderer=os.environ.get('WLR_RENDERER', 'automatic'), omarchy_present=False)
        if test.returncode:
            text = (home / 'visual-tests.log').read_text(errors='replace')
            result['visual_diagnostics'] = [label for label in ('IndentationError', 'SyntaxError', 'AssertionError', 'RuntimeError', 'ReferenceError', 'TypeError') if label in text]
            result['visual_failure_locations'] = sorted(set(re.findall(r'([A-Za-z0-9_-]+\.qml:[0-9]+)', text)))
            result['visual_python_lines'] = re.findall(r'File "[^"\n]*run-standalone\.py", line ([0-9]+)', text)
        if test.returncode == 0 and authentication:
            result['stage'] = 'standalone-authentication'
            auth_spec = importlib.util.spec_from_file_location('guest_auth', Path(__file__).with_name('guest-auth.py'))
            auth = importlib.util.module_from_spec(auth_spec); auth_spec.loader.exec_module(auth)
            result.update(auth.run_tests(root))
            if result.get('authentication_status') != 'passed': result['status'] = 'failed'

    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        result['status'] = 'failed'
        result['error_type'] = type(error).__name__
    finally:
        temporary = home / 'vm-result.partial'
        temporary.write_text(json.dumps(result))
        temporary.replace(home / 'vm-result.json')


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--authentication', action='store_true')
    main(parser.parse_args().authentication)
