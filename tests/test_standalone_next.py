"""Idle readiness, capture lifecycle and package boundaries, using disposable files."""
import importlib.util
import io
import json
import os
from pathlib import Path
import runpy
import shlex
import tarfile
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location('hello_' + name, ROOT/'standalone'/ (name + '.py'))
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result)
    return result


class Idle(unittest.TestCase):
    def test_event_commands_are_quoted_and_do_not_load_an_existing_config(self):
        idle = module('idle')
        profile = Path('/test/space $(literal); quote\' profile')
        command = idle.command(ROOT, profile, 300)
        self.assertEqual(command[:5], ['swayidle', '-w', '-C', '/dev/null', 'timeout'])
        for index in (6, 8, 10):
            self.assertEqual(shlex.split(command[index]), [str(ROOT/'bin/hello-lock'), 'lock', '--background', '--config-dir', str(profile)])
        with self.assertRaises(ValueError): idle.command(ROOT, profile, 0)

    def test_suspend_aborts_without_confirmed_lock_and_propagates_lock_failure(self):
        idle = module('idle'); runtime = Mock()
        with patch.object(idle.subprocess, 'run') as process:
            runtime.background.side_effect = ValueError('unconfirmed')
            with self.assertRaises(ValueError): idle.suspend(ROOT, Path('/fixture'), runtime)
            runtime.background.side_effect = None
            for state in ({}, {'active':True,'secure':True,'released':True}, {'active':False,'secure':True},
                          {'active':True,'secure':True,'released':False,'phase':'lock-lost'}):
                runtime.status.return_value = state
                with self.assertRaises(ValueError): idle.suspend(ROOT, Path('/fixture'), runtime)
            process.assert_not_called()
            runtime.status.return_value = {'active':True,'secure':True,'released':False,'phase':'locked'}
            process.return_value.returncode = 0
            self.assertEqual(idle.suspend(ROOT, Path('/fixture'), runtime), 0)
            process.assert_called_once_with(['systemctl','suspend'], check=False)

    def test_managed_unit_preserves_foreign_edits_and_escapes_specifiers(self):
        tool = runpy.run_path(str(ROOT/'bin/hello-lock-idle-install'))
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory); executable = base/'hello % literal'; executable.touch(); executable.chmod(0o700)
            unitdir = base/'units'
            tool['change']('install', unitdir, executable, 300)
            path = unitdir/'hello-lock-idle.service'
            self.assertIn('hello %% literal', path.read_text())
            path.write_text('foreign fixture')
            for action in ('install','remove'):
                with self.assertRaises(ValueError): tool['change'](action, unitdir, executable, 300)
            self.assertEqual(path.read_text(),'foreign fixture')


class Ownership(unittest.TestCase):
    def test_relock_waits_for_released_owner_and_never_replaces_a_secure_owner(self):
        import fcntl,time
        runtime=module('runtime')
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ,XDG_RUNTIME_DIR=directory,WAYLAND_DISPLAY='fixture'):
            base=runtime.runtime_dir(); owner=runtime.lock_fd(base); contender=runtime.lock_fd(base)
            try:
                fcntl.flock(owner,fcntl.LOCK_EX)
                runtime.write_json(base/'instance.json',{'generation':'fixture'})
                runtime.write_json(base/'state.json',{'generation':'fixture','secure':True,'released':False,'phase':'locked'})
                self.assertFalse(runtime.claim(base,contender,timeout=.3))
                runtime.write_json(base/'state.json',{'generation':'fixture','secure':False,'released':True})
                def finish():
                    time.sleep(.08); fcntl.flock(owner,fcntl.LOCK_UN)
                worker=threading.Thread(target=finish); worker.start()
                self.assertTrue(runtime.claim(base,contender,timeout=.5)); worker.join(1)
            finally:
                os.close(owner); os.close(contender)


class Capture(unittest.TestCase):
    def test_capture_is_parallel_generation_checked_and_acknowledged_per_output(self):
        capture = module('capture'); runtime = module('runtime')
        started = threading.Event(); finish = threading.Event(); cleaned = []
        def shot(names, base):
            started.set(); finish.wait(2)
            return {'directory':str(base/'shots'), 'files':{'A':str(base/'shots/0.jpg'),'B':str(base/'shots/1.jpg')}}
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory); profile = base/'profile'; profile.mkdir()
            helper = {'runtime_dir':lambda:base,'capture':shot,'clean':lambda *args:cleaned.append(args)}
            with patch.object(capture.runpy,'run_path',return_value=helper), patch.object(capture.subprocess,'run',return_value=Mock(stdout='[{"name":"A"},{"name":"B"}]')):
                instance = capture.Captures(ROOT,profile,base,'epoch',runtime.write_json)
                self.assertTrue(started.wait(1)); self.assertIsNone(instance.ready_at)
                finish.set(); instance.thread.join(2)
                self.assertEqual(json.loads(instance.manifest.read_text())['generation'],'epoch')
                for epoch, names in [('old',['A','B']),('epoch',['A'])]:
                    runtime.write_json(instance.ack, {'generation':epoch,'finished':names})
                    instance.poll(); self.assertFalse(cleaned)
                runtime.write_json(instance.ack, {'generation':'epoch','finished':['A','B']})
                instance.poll(); self.assertEqual(len(cleaned),1)
                self.assertFalse(instance.manifest.exists())

    def test_fifo_profile_cannot_block_optional_capture_setup(self):
        capture=module('capture'); runtime=module('runtime')
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory); os.mkfifo(base/'config.json')
            instance=capture.Captures(ROOT,base,base,'epoch',runtime.write_json)
            instance.thread.join(1)
            self.assertFalse(instance.thread.is_alive())
            self.assertIsNone(instance.ready_at)
            instance.close()

    def test_disabled_capture_does_not_start_and_expiry_cleans_without_ack(self):
        capture = module('capture'); runtime = module('runtime')
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory); (base/'config.json').write_text('{"powerDown":false}')
            instance=capture.Captures(ROOT,base,base,'epoch',runtime.write_json)
            instance.thread.join(2)
            self.assertIsNone(instance.ready_at)
            instance.capture={'directory':str(base/'shots'),'files':{'A':'unused'}}; instance.ready_at=-10
            helper={'runtime_dir':lambda:base,'clean':Mock()}
            with patch.object(capture.runpy,'run_path',return_value=helper): instance.poll()
            helper['clean'].assert_called_once()


class Packages(unittest.TestCase):
    def test_payload_excludes_private_guides_and_preserves_policy_and_licenses(self):
        tool=runpy.run_path(str(ROOT/'bin/hello-lock-package'))
        files=tool['payload'](ROOT)
        self.assertFalse(any('AGENTS.md' in name or '/.git/' in name or '__pycache__' in name for name in files))
        self.assertFalse(any('/harness/' in name for name in files))
        self.assertTrue(files['usr/share/hello-lock/bin/hello-sound'][0].startswith(b'#!/usr/bin/bash\n'))
        self.assertIn('etc/pam.d/hello-lock',files)
        self.assertEqual(files['etc/pam.d/hello-lock'][1],0o644)
        self.assertIn('usr/share/hello-lock/THIRD_PARTY_NOTICES.md',files)
        record=json.loads(files['usr/share/doc/hello-lock-standalone/BUILD-MANIFEST.json'][0])
        self.assertIn('usr/bin/hello-lock',record)

    def test_archive_directory_permissions_survive_a_restrictive_umask(self):
        tool=runpy.run_path(str(ROOT/'bin/hello-lock-package'))
        data=tool['archive']({'usr/share/hello-lock/bin/hello-lock':(b'fixture',0o755)},0)
        with tempfile.TemporaryDirectory() as directory:
            old=os.umask(0o077)
            try:
                with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as stream:
                    self.assertEqual(stream.getmember('usr/share/hello-lock').mode,0o755)
                    stream.extractall(directory,filter='tar')
            finally: os.umask(old)
            self.assertEqual((Path(directory)/'usr/share/hello-lock').stat().st_mode & 0o777,0o755)

    def test_symlink_source_roots_are_refused_and_font_provenance_matches(self):
        import hashlib
        tool=runpy.run_path(str(ROOT/'bin/hello-lock-package'))
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory); (base/'bin').mkdir()
            (base/'bin/hello-lock').write_text('VISUAL_FILES=("platform",)')
            (base/'platform').symlink_to(ROOT/'platform',target_is_directory=True)
            with self.assertRaises(ValueError): tool['payload'](base)
        source=json.loads((ROOT/'wordmark/SOURCES.json').read_text())
        self.assertEqual(hashlib.sha256((ROOT/'wordmark/delta-corps-priest-1.flf').read_bytes()).hexdigest(),source['sha256'])
        self.assertEqual(hashlib.sha256((ROOT/'wordmark/LICENSE-figlet.txt').read_bytes()).hexdigest(),source['license_sha256'])

    def test_reproducible_archives_and_debian_conffile_metadata(self):
        tool=runpy.run_path(str(ROOT/'bin/hello-lock-package'))
        fixture={'etc/pam.d/hello-lock':(b'fixture',0o644)}
        self.assertEqual(tool['archive'](fixture,0),tool['archive'](fixture,0))
        with tempfile.TemporaryDirectory() as directory, patch.dict(tool['build'].__globals__,payload=lambda source:fixture):
            package=tool['build'](ROOT,Path(directory),'deb','1.2.3','0.preview1')
            data=package.read_bytes(); self.assertTrue(data.startswith(b'!<arch>\n'))
            size=int(data[8+60+4+48:8+60+4+58])
            control_start=8+60+4+60
            with tarfile.open(fileobj=io.BytesIO(data[control_start:control_start+size]),mode='r:gz') as stream:
                self.assertEqual(stream.extractfile('conffiles').read(),b'/etc/pam.d/hello-lock\n')
            with self.assertRaises(FileExistsError): tool['build'](ROOT,Path(directory),'deb','1.2.3','0.preview1')


if __name__ == '__main__': unittest.main()
