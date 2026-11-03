"""Autonomous lab guards and QMP protocol behavior. No VM boots in unit tests."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
import tarfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("vm_lab", ROOT / "tests/vm/lab.py")
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


class VirtualLab(unittest.TestCase):
    def test_resources_require_host_memory_reserve(self):
        report = {"kvm_access": True, "tools_ready": True, "disk_free_gib": 100,
                  "available_memory_mib": 4000, "guest_memory_mib": 3072, "host_reserve_mib": 1536}
        self.assertFalse(lab.ready(report))
        report["available_memory_mib"] = 5000
        self.assertTrue(lab.ready(report))
        report["memory_pressure_full_avg10"] = 8.0
        self.assertFalse(lab.ready(report))
        report["memory_pressure_full_avg10"] = 0.0
        report["kvm_access"] = False
        self.assertFalse(lab.ready(report))

    def test_deferred_run_does_not_create_credentials_or_start_qemu(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(lab, "preflight", return_value={"kvm_access": False, "tools_ready": False,
                    "disk_free_gib": 100, "available_memory_mib": 0, "guest_memory_mib": 3072, "host_reserve_mib": 1536}), \
                    patch.object(lab.subprocess, "Popen") as process, patch("builtins.print"):
                self.assertEqual(lab.run_vm(Path(directory), 3072, 0), 75)
                process.assert_not_called()
            self.assertEqual({p.name for p in Path(directory).iterdir()}, {"lab.lock", "last-result.json", "result-arch.json"})
            self.assertEqual(json.loads((Path(directory) / 'result-arch.json').read_text())['status'], 'deferred')

    def test_boot_failure_removes_disposable_credentials_and_overlay(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            report = {"kvm_access": True, "tools_ready": True, "disk_free_gib": 100,
                      "available_memory_mib": 6000, "guest_memory_mib": 3072, "host_reserve_mib": 1536}
            def fail(cache, tools, base, run, memory, distro="arch"):
                lab.private_file(run / "guest-password", "synthetic test fixture")
                lab.private_file(run / "disk.qcow2", "synthetic overlay")
                raise RuntimeError("fixture failure")
            with patch.object(lab, "preflight", return_value=report), patch.object(lab, "image", return_value=cache / "base.qcow2"), patch.object(lab, "boot_vm", side_effect=fail):
                with self.assertRaises(RuntimeError): lab.run_vm(cache, 3072, 0)
            self.assertFalse(list(cache.glob("run-*")))
            self.assertEqual(json.loads((cache / "last-result.json").read_text())["status"], "failed")


    def test_interrupted_guest_records_abort_and_removes_run_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            report = {'kvm_access': True, 'tools_ready': True, 'disk_free_gib': 100,
                      'available_memory_mib': 6000, 'guest_memory_mib': 3072, 'host_reserve_mib': 1536}
            def interrupt(cache, tools, base, run, memory, distro='arch'):
                lab.private_file(run / 'guest-password', 'synthetic fixture')
                raise KeyboardInterrupt
            with patch.object(lab, 'preflight', return_value=report), patch.object(lab, 'image', return_value=cache / 'base.qcow2'), patch.object(lab, 'boot_vm', side_effect=interrupt):
                with self.assertRaises(KeyboardInterrupt): lab.run_vm(cache, 3072, 0)
            self.assertFalse(list(cache.glob('run-*')))
            result = json.loads((cache / 'result-arch.json').read_text())
            self.assertEqual((result['status'], result['stage']), ('aborted', 'cancelled'))

    def test_private_files_do_not_follow_or_overwrite_existing_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "private"
            lab.private_file(path, "synthetic test fixture")
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError): lab.private_file(path, "replacement")
            link = Path(directory) / "link"
            link.symlink_to(path)
            with self.assertRaises(FileExistsError): lab.private_file(link, "replacement")
            self.assertEqual(path.read_text(), "synthetic test fixture")

    def test_qmp_skips_events_and_returns_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "qmp.sock"
            server = socket.socket(socket.AF_UNIX)
            server.bind(str(path)); server.listen()
            commands = []
            def serve():
                connection, _ = server.accept()
                with connection, connection.makefile("rwb") as stream:
                    stream.write(b'{"QMP":{}}\n'); stream.flush()
                    for _ in range(2):
                        request = json.loads(stream.readline()); commands.append(request["execute"])
                        stream.write(b'{"event":"TEST_EVENT"}\n')
                        stream.write((json.dumps({"return": {"status": "running"}}) + "\n").encode()); stream.flush()
            worker = threading.Thread(target=serve);worker.start()
            client = lab.QMP(path)
            self.assertEqual(client.command("query-status")["status"], "running")
            client.close();worker.join(timeout=3);server.close()
            self.assertEqual(commands, ["qmp_capabilities", "query-status"])

    def test_source_bundle_excludes_host_integration_and_private_guides(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / "source.tar.gz"
            lab.source_bundle(bundle)
            with tarfile.open(bundle) as archive:
                names = archive.getnames()
                self.assertIn("standalone/shell.qml", names)
                self.assertIn("tests/vm/guest-test.py", names)
                self.assertNotIn("Service.qml", names)
                self.assertFalse(any("AGENTS.md" in name or "/.git" in name or name.startswith(".git") for name in names))
                self.assertFalse(any(member.issym() for member in archive.getmembers()))
                for name in names:
                    if name.endswith('.py'):
                        compile(archive.extractfile(name).read(), name, 'exec')

    def test_guest_desktop_setup_refuses_the_host(self):
        spec = importlib.util.spec_from_file_location("guest_session", ROOT / "tests/vm/guest-session.py")
        session = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(session)
        with patch.object(session.getpass, "getuser", return_value="host-user"), patch.object(session.subprocess, "run") as run:
            with self.assertRaises(RuntimeError): session.configure()
            run.assert_not_called()

    def test_security_guest_refuses_host_before_writes_or_subprocesses(self):
        spec = importlib.util.spec_from_file_location("guest_security", ROOT / "tests/vm/guest-security.py")
        security = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(security)
        with patch('getpass.getuser', return_value='host-user'), patch.object(security.subprocess, 'run') as run, patch.object(security.Path, 'write_text') as write:
            with self.assertRaises(RuntimeError): security.main()
            run.assert_not_called()
            write.assert_not_called()

    def test_security_bundle_is_explicit_and_records_actual_sources(self):
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / 'security.tar.gz'
            runtime = Path(directory) / 'runtime'
            for name in ('Commons', 'Ui'):
                module = runtime / name
                module.mkdir(parents=True)
                (module / 'qmldir').write_text('module qs.' + name + '\n')
                (module / 'Example.qml').write_text('import QtQuick\nQtObject {}\n')
            lab.source_bundle(bundle, suite='lock-loss', runtime_root=runtime)
            with tarfile.open(bundle) as archive:
                names = archive.getnames()
                for name in ('Service.qml', 'tests/vm/security.qml', 'tests/vm/pam-password', 'omarchy/shell/Commons/qmldir'):
                    self.assertIn(name, names)
                manifest = json.load(archive.extractfile('omarchy/source-manifest.json'))
                self.assertEqual(manifest['service_sha256'], hashlib.sha256((ROOT / 'Service.qml').read_bytes()).hexdigest())
                for name, digest in manifest['files'].items():
                    self.assertEqual(hashlib.sha256(archive.extractfile(name).read()).hexdigest(), digest)
                self.assertFalse(any('AGENTS.md' in name or 'guest-password' in name or name.startswith('.git') for name in names))
                self.assertFalse(any(member.issym() for member in archive.getmembers()))

    def test_guest_keyboard_never_places_credential_in_ssh_arguments(self):
        from unittest.mock import MagicMock
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            lab.private_file(run / 'guest-password', 'synthetic123')
            qmp = MagicMock()
            with patch.object(lab.subprocess, 'run') as ssh:
                self.assertEqual(lab.guest_keyboard(run, 2222, qmp, {'sequence': 1, 'action': 'password'}, 0), 1)
                qmp.text.assert_called_once_with('synthetic123')
                self.assertNotIn('synthetic123', repr(ssh.call_args))
                self.assertEqual(lab.guest_keyboard(run, 2222, qmp, {'sequence': 1, 'action': 'password'}, 1), 1)
                qmp.text.assert_called_once()
                for request in ({'sequence': 3, 'action': 'password'}, {'sequence': True, 'action': 'password'},
                                {'sequence': 2, 'action': 'shell'}, {'sequence': 99, 'action': 'password'}):
                    with self.assertRaises(ValueError): lab.guest_keyboard(run, 2222, qmp, request, 1)
                qmp.text.assert_called_once()

    def test_memory_guard_stops_only_its_guest_after_sustained_pressure(self):
        from unittest.mock import MagicMock
        process = MagicMock()
        process.poll.return_value = None
        guard = lab.HostGuard(process)
        guard.event = MagicMock()
        guard.event.wait.side_effect = [False] * 5
        with patch.object(lab, "available_memory", return_value=300):
            guard.watch()
        self.assertTrue(guard.tripped)
        process.terminate.assert_called_once_with()

    def test_memory_guard_ignores_short_memory_dips(self):
        from unittest.mock import MagicMock
        process = MagicMock()
        guard = lab.HostGuard(process)
        guard.event = MagicMock()
        guard.event.wait.side_effect = [False, False, False, True]
        with patch.object(lab, "available_memory", side_effect=[300, 300, 900]):
            guard.watch()
        self.assertFalse(guard.tripped)
        process.terminate.assert_not_called()


    def test_qmp_close_after_guest_termination_still_closes_socket(self):
        from unittest.mock import MagicMock
        client = object.__new__(lab.QMP)
        client.stream = MagicMock()
        client.stream.close.side_effect = BrokenPipeError()
        client.socket = MagicMock()
        client.close()
        client.socket.close.assert_called_once_with()


    def test_virtual_keyboard_rejects_unsupported_input_before_sending(self):
        client = object.__new__(lab.QMP)
        with patch.object(client, "command") as command:
            with self.assertRaises(ValueError): client.text("valid!")
            command.assert_not_called()


class DistributionMatrix(unittest.TestCase):
    def test_cachyos_disk_discovery_accepts_lsblk_tree_and_flat_json(self):
        spec = importlib.util.spec_from_file_location('cachyos_installer', ROOT / 'tests/vm/guest-cachyos.py')
        installer = importlib.util.module_from_spec(spec); spec.loader.exec_module(installer)
        part = {'path': '/dev/vdb1', 'fstype': 'btrfs'}
        self.assertEqual(installer.target_partitions({'blockdevices': [{'path': '/dev/vdb', 'children': [part]}]}), [part])
        self.assertEqual(installer.target_partitions({'blockdevices': [{'path': '/dev/vdb'}, part]}), [part])
        self.assertEqual(installer.target_partitions({'blockdevices': [{'path': '/dev/vda1', 'fstype': 'ext4'}]}), [])

    def test_cachyos_root_mount_supports_official_btrfs_layout_only_on_target(self):
        spec = importlib.util.spec_from_file_location('cachyos_installer', ROOT / 'tests/vm/guest-cachyos.py')
        installer = importlib.util.module_from_spec(spec); spec.loader.exec_module(installer)
        self.assertEqual(installer.root_mount_args({'path': '/dev/vdb2', 'fstype': 'btrfs'}, '/fixture'),
                         ['mount', '-o', 'subvol=@', '/dev/vdb2', '/fixture'])
        self.assertEqual(installer.root_mount_args({'path': '/dev/vdb1', 'fstype': 'ext4'}, '/fixture'),
                         ['mount', '/dev/vdb1', '/fixture'])
        self.assertIsNone(installer.root_mount_args({'path': '/dev/vdb1', 'fstype': 'vfat'}, '/fixture'))
        with self.assertRaises(RuntimeError): installer.root_mount_args({'path': '/dev/vda2', 'fstype': 'btrfs'}, '/fixture')

    def test_installer_uses_system_umask_with_private_log_and_settings(self):
        spec = importlib.util.spec_from_file_location('cachyos_installer', ROOT / 'tests/vm/guest-cachyos.py')
        installer = importlib.util.module_from_spec(spec); spec.loader.exec_module(installer)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); config = root / 'settings.json'; log = root / 'installer.log'
            lab.private_file(config, 'synthetic fixture')
            with patch.object(installer, 'run') as run:
                installer.install_system(config, log)
                run.assert_called_once_with('cachyos-installer', '--config', str(config), umask=0o022)
            self.assertEqual(log.stat().st_mode & 0o777, 0o600)
            self.assertEqual(config.stat().st_mode & 0o777, 0o600)
            log.unlink(); log.symlink_to(config)
            with patch.object(installer, 'run') as run:
                with self.assertRaises(OSError): installer.install_system(config, log)
                run.assert_not_called()

    def test_installer_diagnostics_export_only_approved_public_names(self):
        spec = importlib.util.spec_from_file_location('installer_diagnostics', ROOT / 'tests/vm/installer-diagnostics.py')
        diagnostic = importlib.util.module_from_spec(spec); spec.loader.exec_module(diagnostic)
        log = "password=private-fixture\\nbase install failed\\nerror: failed retrieving file 'gcc.pkg.tar.zst' from cdn77.cachyos.org : error: 404\\nfailed retrieving file 'private-fixture' from private-host"
        result = diagnostic.summarize(log, {'gcc.pkg.tar.zst'})
        self.assertEqual(result['failed_artifacts'], ['gcc.pkg.tar.zst'])
        self.assertEqual(result['http_codes'], ['404'])
        self.assertNotIn('private-fixture', json.dumps(result))
        self.assertNotIn('private-host', json.dumps(result))

    def test_installed_guest_screenshot_survives_nested_run_cleanup(self):
        from types import SimpleNamespace
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory); run = cache / 'run' / 'installed'; run.mkdir(parents=True)
            png = b'\x89PNG\r\n\x1a\nfixture'
            replies = [SimpleNamespace(returncode=0), SimpleNamespace(returncode=0),
                       SimpleNamespace(returncode=0, stdout=json.dumps({'status': 'passed', 'screenshot': True})),
                       SimpleNamespace(returncode=0, stdout=png)]
            with patch.object(lab, 'source_bundle', side_effect=lambda path: path.write_bytes(b'fixture')), patch.object(lab.subprocess, 'run', side_effect=replies), patch.object(lab, 'available_memory', return_value=2000):
                result = lab.guest_tests(run, 2222, cache=cache, distro='cachyos')
            shutil.rmtree(cache / 'run')
            self.assertEqual(result['screenshot_artifact'], 'settings-cachyos.png')
            self.assertEqual((cache / result['screenshot_artifact']).read_bytes(), png)

    def test_parallel_result_writers_leave_complete_private_json(self):
        from concurrent.futures import ThreadPoolExecutor
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            def write(name):
                for _ in range(5): lab.save_result(cache, name, {'status': 'fixture'})
            with ThreadPoolExecutor(max_workers=5) as pool:
                list(pool.map(write, lab.PROFILES))
            for name in lab.PROFILES:
                path = cache / ('result-' + name + '.json')
                self.assertEqual(json.loads(path.read_text())['distro'], name)
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads((cache / 'last-result.json').read_text())['status'], 'fixture')
            self.assertFalse(list(cache.glob('*.partial')))

    def test_matrix_continues_after_blocker_and_includes_cachyos(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            visited = []
            def child(command):
                name = command[command.index('--distro') + 1]
                visited.append(name)
                lab.save_result(cache, name, {'status': 'blocked' if name == 'debian' else 'passed'})
                return 2 if name == 'debian' else 0
            with patch.object(lab, 'matrix_child', side_effect=child):
                self.assertEqual(lab.run_matrix(cache, 1024, 0, True), 1)
            self.assertEqual(set(visited), {'arch', 'fedora', 'ubuntu', 'debian', 'cachyos'})
            self.assertEqual(json.loads((cache / 'matrix-result.json').read_text())['debian']['status'], 'blocked')

    def test_matrix_cannot_reuse_stale_pass_after_child_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            for name in lab.PROFILES: lab.save_result(cache, name, {'status': 'passed'})
            with patch.object(lab, 'matrix_child', return_value=1):
                self.assertEqual(lab.run_matrix(cache, 1024, 0), 1)
            self.assertTrue(all(r['status'] == 'failed' for r in json.loads((cache / 'matrix-result.json').read_text()).values()))

    def test_authentication_matrix_propagates_suite_and_rejects_visual_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            def child(command):
                self.assertEqual(command[command.index('--suite') + 1], 'standalone')
                name = command[command.index('--distro') + 1]
                lab.save_result(cache, name, {'status': 'passed', 'suite': 'visual'})
                return 0
            with patch.object(lab, 'matrix_child', side_effect=child):
                self.assertEqual(lab.run_matrix(cache, 1024, 0, True, 'standalone'), 1)
            self.assertTrue(all(r['status'] == 'failed' for r in json.loads((cache / 'matrix-result.json').read_text()).values()))

    def test_matrix_cancellation_terminates_child_gracefully(self):
        from unittest.mock import MagicMock
        process = MagicMock(); process.wait.side_effect = [KeyboardInterrupt, 0]
        with patch.object(lab.subprocess, 'Popen', return_value=process):
            with self.assertRaises(KeyboardInterrupt): lab.matrix_child(['fixture'])
        process.terminate.assert_called_once()
        process.wait.assert_called_with(timeout=30)

    def test_fedora_setup_uses_sway_without_probing_hyprland(self):
        from unittest.mock import MagicMock
        spec = importlib.util.spec_from_file_location('guest_session', ROOT / 'tests/vm/guest-session.py')
        session = importlib.util.module_from_spec(spec); spec.loader.exec_module(session)
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            profile = MagicMock(); profile.read_text.return_value = 'fedora'
            with patch.object(session, 'require_guest'), patch.object(session, 'Path') as path, patch.object(session.subprocess, 'run') as run:
                path.home.return_value = home
                path.side_effect = lambda value: profile if value == '/etc/hello-lock-vm-profile' else Path(value)
                session.configure()
            self.assertIn('exec dbus-run-session sway -c', (home / '.bash_profile').read_text())
            self.assertIn('exec python3', (home / '.config/sway/config').read_text())
            self.assertFalse(any(call.args[0][0] == 'Hyprland' for call in run.call_args_list))

    def test_busy_lab_defers_without_starting_another_guest(self):
        import fcntl
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            with (cache / 'lab.lock').open('w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                with patch.object(lab, 'image') as image, patch.object(lab, 'boot_vm') as boot, patch('builtins.print'):
                    self.assertEqual(lab.run_vm(cache, 1024, 0, distro='ubuntu'), 75)
                    image.assert_not_called(); boot.assert_not_called()
            self.assertEqual(json.loads((cache / 'result-ubuntu.json').read_text())['status'], 'deferred')

    def test_known_image_blocker_never_starts_guest_or_checks_memory(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(lab, 'preflight') as preflight, patch.object(lab, 'boot_vm') as boot, patch('builtins.print'):
                self.assertEqual(lab.run_vm(Path(directory), 1024, 0, distro='debian'), 2)
                preflight.assert_not_called(); boot.assert_not_called()
            self.assertEqual(json.loads((Path(directory) / 'result-debian.json').read_text())['status'], 'blocked')

    def test_signed_checksums_match_exact_selected_filename_and_algorithm(self):
        from images import checksum_for
        digest = 'ab' * 32
        self.assertEqual(checksum_for(digest + '  image.qcow2', 'image.qcow2', 'sha256'), digest)
        self.assertEqual(checksum_for('SHA256 (image.qcow2) = ' + digest, 'image.qcow2', 'sha256'), digest)
        for text in (digest + '  other.qcow2', 'SHA512 (image.qcow2) = ' + digest,
                     (digest + '  image.qcow2\n') * 2):
            with self.assertRaises(ValueError): checksum_for(text, 'image.qcow2', 'sha256')

    def test_cachyos_cannot_pass_as_arch_or_with_an_arch_kernel(self):
        from profiles import verify_identity
        with self.assertRaises(ValueError): verify_identity('cachyos', {'ID': 'arch'}, '6.18-cachyos')
        with self.assertRaises(ValueError): verify_identity('cachyos', {'ID': 'cachyos'}, '6.18-arch1')
        verify_identity('cachyos', {'ID': 'cachyos'}, '6.18.1-1-cachyos')
        with self.assertRaises(ValueError): verify_identity('fedora', {'ID': 'fedora', 'VERSION_ID': '43'}, '6.18')

    def test_cachyos_installer_refuses_host_before_running_commands(self):
        spec = importlib.util.spec_from_file_location('cachyos_installer', ROOT / 'tests/vm/guest-cachyos.py')
        installer = importlib.util.module_from_spec(spec); spec.loader.exec_module(installer)
        with patch.object(installer.os, 'geteuid', return_value=1000), patch.object(installer.subprocess, 'run') as run:
            with self.assertRaises(RuntimeError): installer.require_target()
            run.assert_not_called()

    def test_cachyos_pinned_repos_preserve_cpu_compatibility(self):
        spec = importlib.util.spec_from_file_location('cachyos_installer', ROOT / 'tests/vm/guest-cachyos.py')
        installer = importlib.util.module_from_spec(spec); spec.loader.exec_module(installer)
        v3 = 'x86-64-v3 (supported, searched)'
        v4 = v3 + '\nx86-64-v4 (supported, searched)'
        amd = installer.pinned_repositories(v4, 'vendor_id : AuthenticAMD')
        self.assertIn('[cachyos-znver4]', amd)
        self.assertIn('https://cdn77.cachyos.org/repo/x86_64_v4/$repo', amd)
        intel = installer.pinned_repositories(v3, 'vendor_id : GenuineIntel')
        self.assertIn('[cachyos-v3]', intel)
        self.assertNotIn('v4', intel)
        self.assertNotIn('znver4', intel)
        with self.assertRaises(RuntimeError): installer.pinned_repositories('x86-64-v2 (supported, searched)', '')

    def test_cachyos_installer_rejects_wrong_serial_and_used_disks(self):
        from unittest.mock import MagicMock
        spec = importlib.util.spec_from_file_location('cachyos_installer', ROOT / 'tests/vm/guest-cachyos.py')
        installer = importlib.util.module_from_spec(spec); spec.loader.exec_module(installer)
        with patch.object(installer.os, 'geteuid', return_value=0), patch.object(installer.socket, 'gethostname', return_value='hello-lock-test'), patch.object(installer, 'Path') as path, patch.object(installer.subprocess, 'run') as run:
            path.return_value.is_file.return_value = True
            path.return_value.exists.return_value = True
            path.return_value.read_text.return_value = 'OTHER_DISK'
            with self.assertRaises(RuntimeError): installer.require_target()
            run.assert_not_called()
            path.return_value.read_text.return_value = installer.SERIAL
            run.return_value.stdout = json.dumps({'blockdevices': [{'mountpoint': None, 'fstype': None, 'children': [{'fstype': 'ext4'}]}]})
            with self.assertRaises(RuntimeError): installer.require_target()
            run.assert_called_once()
            self.assertLessEqual(len(installer.SERIAL.encode()), 20)  # virtio-blk serial field limit
            run.return_value.stdout = json.dumps({'blockdevices': [{'mountpoint': None, 'fstype': None}]})
            installer.require_target()

    def test_all_planned_distributions_have_explicit_profiles(self):
        from profiles import PROFILES
        self.assertEqual(set(PROFILES), {'arch', 'fedora', 'ubuntu', 'debian', 'cachyos'})
        self.assertEqual(PROFILES['cachyos']['bootstrap'], 'arch')

    def test_unsigned_debian_source_is_blocked_before_download(self):
        import images
        with patch.object(images, 'fetch') as fetch:
            with self.assertRaises(images.ImageUnavailable): images.prepare_image(Path('/unused'), 'debian')
            fetch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
