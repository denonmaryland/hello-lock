"""Best-effort entry captures, parallel to locking and never an auth dependency."""
import json
import os
from pathlib import Path
import runpy
import subprocess
import threading
import time


class Captures:
    def __init__(self, source, config, directory, generation, write):
        self.source, self.directory, self.generation, self.write = source, directory, generation, write
        self.manifest = directory / ('capture-' + generation + '.json')
        self.ack = directory / ('capture-finished-' + generation + '.json')
        self.stop = threading.Event()
        self.guard = threading.Lock()
        self.capture = None
        self.ready_at = None
        self.config = config
        self.write(self.manifest, {'generation': generation, 'files': {}})
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        # Even a broken/unreadable profile must not delay the session lock.
        try:
            descriptor = os.open(self.config / 'config.json', os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
            with os.fdopen(descriptor) as stream:
                import stat
                info = os.fstat(stream.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_size > 4 * 1024 * 1024: return
                settings = json.loads(stream.read(4 * 1024 * 1024))
                if not isinstance(settings, dict) or settings.get('powerDown') is False: return
        except FileNotFoundError: pass
        except (OSError, ValueError): return
        helper = runpy.run_path(str(self.source / 'bin/hello-snapshot'))
        result = None
        try:
            command = ['hyprctl', '-j', 'monitors'] if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') else ['swaymsg', '-r', '-t', 'get_outputs']
            query = subprocess.run(command, capture_output=True, text=True, timeout=.5, check=True)
            outputs = json.loads(query.stdout)
            names = [item['name'] for item in outputs if isinstance(item, dict) and isinstance(item.get('name'), str) and item.get('active', True)]
            if not names or len(names) > 8 or self.stop.is_set(): return
            runtime = helper['runtime_dir']()
            result = helper['capture'](names, runtime)
            with self.guard:
                if not self.stop.is_set():
                    self.capture = result
                    self.ready_at = time.monotonic()
                    self.write(self.manifest, dict(result, generation=self.generation))
                    result = None
        except (OSError, ValueError, subprocess.SubprocessError, KeyError, TypeError): pass
        finally:
            if result:
                try: helper['clean'](result['directory'], helper['runtime_dir']())
                except (OSError, ValueError): pass

    def poll(self, released=False):
        with self.guard:
            if not self.capture: return
            finished = []
            try:
                if self.ack.stat().st_size <= 8192 and not self.ack.is_symlink():
                    value = json.loads(self.ack.read_text())
                    if value.get('generation') == self.generation and isinstance(value.get('finished'), list):
                        finished = value['finished']
            except (OSError, ValueError, AttributeError): pass
            done = all(name in finished for name in self.capture['files'])
            expired = time.monotonic() - self.ready_at >= 3
        if done or expired or released: self.close()

    def close(self):
        self.stop.set()
        if self.thread and self.thread is not threading.current_thread(): self.thread.join(timeout=5)
        with self.guard:
            self.write(self.manifest, {'generation': self.generation, 'files': {}})
            if self.capture:
                helper = runpy.run_path(str(self.source / 'bin/hello-snapshot'))
                try: helper['clean'](self.capture['directory'], helper['runtime_dir']())
                except (OSError, ValueError): pass
                self.capture = None
            self.manifest.unlink(missing_ok=True)
            self.ack.unlink(missing_ok=True)
