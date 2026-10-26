#!/usr/bin/env python3
"""Run isolated visual previews; prints the path for `qs ipc -p PATH call review ...`.

Uses installed Omarchy Commons/Ui read-only. Never instantiates Service.qml,
never touches the live plugin or user settings, exits automatically after 2 min.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="hello-lock-review-") as directory:
    root = Path(directory)
    (root / "plugin").symlink_to(source, target_is_directory=True)
    for module in ("Commons", "Ui"):
        (root / module).symlink_to(Path("/usr/share/omarchy/shell") / module, target_is_directory=True)
    shutil.copy2(source / "tests/preview.qml", root / "shell.qml")
    (root / "config/hello-lock").mkdir(parents=True)
    env = dict(os.environ, XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"),
               HELLO_LOCK_SOURCE=str(source))
    print("Preview root: " + str(root), flush=True)
    subprocess.run(["qs", "-p", str(root)], env=env, check=True)
