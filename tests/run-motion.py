#!/usr/bin/env python3
"""Exercise the real Motion.qml offscreen with synthetic compositor replies."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def main():
    if not shutil.which('qs'): raise RuntimeError('Quickshell is required')
    source = Path(__file__).resolve().parents[1] / 'platform/Motion.qml'
    cases = [({'bool':True},False), ({'bool':False},True), ({'int':1},False),
             ({'int':0},True), ({'unknown':True},True), (None,True)]
    for reply, expected in cases:
        with tempfile.TemporaryDirectory(prefix='hello-motion-') as directory:
            root = Path(directory); (root/'bin').mkdir()
            fake = root/'bin/hyprctl'
            body = 'print(' + repr(json.dumps(reply)) + ')' if reply is not None else 'raise SystemExit(1)'
            fake.write_text('#!/usr/bin/python3\n' + body + '\n'); fake.chmod(0o700)
            (root/'Motion.qml').write_text(source.read_text())
            (root/'shell.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
  Motion { id: motion }
  Timer { running: true; interval: 1500; onTriggered: { console.log("RESULT:" + JSON.stringify(motion.calm)); Qt.quit() } }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', HYPRLAND_INSTANCE_SIGNATURE='fixture',
                       WAYLAND_DISPLAY='', PATH=str(root/'bin')+':'+os.environ['PATH'],
                       XDG_RUNTIME_DIR=str(root), XDG_CONFIG_HOME=str(root/'config'), XDG_CACHE_HOME=str(root/'cache'))
            result = subprocess.run(['qs','-n','-p',str(root)], env=env, capture_output=True, text=True, timeout=8)
            match = re.search(r'RESULT:(true|false)', result.stdout+result.stderr)
            if result.returncode or not match or (match.group(1)=='true') is not expected:
                raise RuntimeError('Motion reply handling failed for synthetic case ' + str(reply))
    print('6 real QML motion scenarios passed offscreen; no desktop, PAM or input used.')


if __name__ == '__main__': main()
