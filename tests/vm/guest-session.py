#!/usr/bin/env python3
"""Configure only the disposable guest's graphical login; refuses the host."""
import getpass
import json
import os
import re
from pathlib import Path
import socket
import subprocess


def require_guest():
    marker = Path('/etc/hello-lock-vm')
    if getpass.getuser() != 'hellotest' or socket.gethostname() != 'hello-lock-test' or not marker.is_file():
        raise RuntimeError('This command is restricted to the disposable Hello Lock guest')


def configure(suite="visual", software_gpu=False, suspend_mode="s2idle"):
    require_guest()
    home = Path.home()
    from profiles import get
    compositor = get(Path('/etc/hello-lock-vm-profile').read_text().strip()).get('compositor', 'Hyprland')
    config = home / ('.config/sway' if compositor == 'Sway' else '.config/hypr')
    config.mkdir(parents=True, exist_ok=True)
    if suite not in ("visual", "lock-loss", "standalone"): raise ValueError("Unknown guest suite")
    if suspend_mode not in ('s2idle', 's3'): raise ValueError('Unknown suspend mode')
    runner = home / ('hello-lock/tests/vm/guest-security.py' if suite == "lock-loss" else 'hello-lock/tests/vm/guest-test.py')
    command = 'python3 ' + str(runner) + (' --authentication' if suite == 'standalone' else '')
    if suite == 'standalone': command = 'env HELLO_LOCK_VM_SUSPEND=' + suspend_mode + ' ' + command
    lua = '''hl.monitor({output = "", mode = "1280x800@60", position = "auto", scale = 1})
hl.config({animations = {enabled = false}, general = {gaps_in = 0, gaps_out = 0},
  decoration = {blur = {enabled = false}, shadow = {enabled = false}},
  misc = {disable_hyprland_logo = true, disable_splash_rendering = true}})
hl.on("hyprland.start", function() hl.exec_cmd(''' + json.dumps(command) + ''') end)
'''
    version = subprocess.run(['Hyprland', '--version'], capture_output=True, text=True, check=True) if compositor == 'Hyprland' else None
    match = re.search(r'(\d+)\.(\d+)', version.stdout + version.stderr) if version else None
    modern = match and tuple(map(int, match.groups())) >= (0, 55)
    filename = 'hyprland.lua' if modern else 'hyprland.conf'
    legacy = '''monitor=,1280x800@60,auto,1
animations {
  enabled=false
}
decoration {
  blur {
    enabled=false
  }
}
misc {
  disable_hyprland_logo=true
  disable_splash_rendering=true
}
exec-once=''' + command + '\n'
    if compositor == 'Sway':
        filename = 'config'
        (config / filename).write_text('output * mode 1280x800 scale 1\nxwayland disable\nexec ' + command + '\n')
    else:
        if suite == 'standalone':
            lua = lua.replace('disable_hyprland_logo = true,', 'allow_session_lock_restore = true, disable_hyprland_logo = true,')
            legacy = legacy.replace('  disable_hyprland_logo=true', '  allow_session_lock_restore=true\n  disable_hyprland_logo=true')
        (config / filename).write_text(lua if modern else legacy)
    (home / '.bash_profile').write_text('''if [ "$(tty)" = /dev/tty1 ]; then
  export XDG_SESSION_TYPE=wayland
  export XDG_CURRENT_DESKTOP=''' + ('sway' if compositor == 'Sway' else 'Hyprland') + '''
  export QT_QPA_PLATFORM=wayland
''' + ('  export LIBGL_ALWAYS_SOFTWARE=1\n  export WLR_RENDERER_ALLOW_SOFTWARE=1\n' if software_gpu else '') + ('  export WLR_RENDERER=pixman\n' if software_gpu and compositor == 'Sway' else '') + '''
  exec dbus-run-session ''' + ('sway' if compositor == 'Sway' else 'Hyprland') + ''' -c "''' + str(config / filename) + '''"
fi
''')
    directory = '/etc/systemd/system/getty@tty1.service.d'
    subprocess.run(['sudo', '-n', 'mkdir', '-p', directory], check=True)
    override = '[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin hellotest --noclear %I $TERM\n'
    subprocess.run(['sudo', '-n', 'tee', directory + '/autologin.conf'], input=override, text=True, check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['sudo', '-n', 'systemctl', 'daemon-reload'], check=True)
    subprocess.run(['sudo', '-n', 'systemctl', 'restart', 'getty@tty1'], check=True)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=("visual", "lock-loss", "standalone"), default="visual")
    parser.add_argument("--software-gpu", action="store_true")
    parser.add_argument("--suspend-mode", choices=('s2idle', 's3'), default='s2idle')
    args = parser.parse_args()
    configure(args.suite, args.software_gpu, args.suspend_mode)
