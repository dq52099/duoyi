"""Budget/ownership regressions using synthetic procfs and disposable children only."""
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import resource_guard as guard


GOOD_MEMORY = dict(availableMiB=4096, combinedUsedRatio=.4)


class ResourceGuardTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='duoyi-resource-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def runner(self, **options):
        defaults = dict(root=self.root, report=self.root / 'guard.json', interval=.05,
                        timeout=5, disk_sample=lambda: 30,
                        mem_sample=lambda: GOOD_MEMORY)
        defaults.update(options)
        return guard.ResourceGuard(**defaults)

    def test_success_records_terminal_and_actual_exit_code(self):
        runner = self.runner()
        self.assertEqual(runner.run([sys.executable, '-c', 'pass']), 0)
        result = json.loads(runner.report.read_text())
        self.assertTrue(result['accepted'])
        self.assertFalse(result['active'])
        self.assertEqual(result['exitCode'], 0)

    def test_child_failure_is_not_accepted(self):
        runner = self.runner()
        self.assertEqual(runner.run([sys.executable, '-c', 'raise SystemExit(7)']), 7)
        self.assertFalse(runner.state['accepted'])

    def test_disk_preflight_does_not_launch(self):
        runner = self.runner(disk_sample=lambda: 11)
        with self.assertRaisesRegex(RuntimeError, 'disk budget'):
            runner.run([sys.executable, '-c', 'pass'])
        self.assertIsNone(runner.process)
        self.assertFalse(runner.report.exists())

    def test_memory_preflight_does_not_launch(self):
        for memory in [dict(availableMiB=1024, combinedUsedRatio=.4),
                       dict(availableMiB=4096, combinedUsedRatio=.8)]:
            with self.subTest(memory=memory):
                runner = self.runner(mem_sample=lambda: memory)
                with self.assertRaisesRegex(RuntimeError, 'memory'):
                    runner.run([sys.executable, '-c', 'pass'])
                self.assertIsNone(runner.process)

    def test_signal_during_admission_never_launches_a_command(self):
        import signal

        def admission_sample():
            os.kill(os.getpid(), signal.SIGTERM)
            return 30

        runner = self.runner(disk_sample=admission_sample)
        self.assertEqual(runner.run([sys.executable, '-c', 'raise AssertionError()']), 143)
        self.assertIsNone(runner.process)
        self.assertFalse(runner.state['accepted'])
        self.assertFalse(runner.state['active'])

    def test_live_budget_stops_own_tree_preserves_other_process(self):
        ready = self.root / 'child.pid'
        runner = self.runner(disk_sample=lambda: 11 if ready.exists() else 30)
        sentinel = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
        self.addCleanup(lambda: sentinel.poll() is None and sentinel.kill())
        self.addCleanup(lambda: sentinel.poll())
        command = ('import subprocess,sys,time; from pathlib import Path; '
                   'child=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"]); '
                   'Path(sys.argv[1]).write_text(str(child.pid)); time.sleep(60)')
        self.assertEqual(runner.run([sys.executable, '-c', command, str(ready)]), 125)
        self.assertIn('disk budget', runner.state['terminationReason'])
        self.assertTrue(runner.state['signalsSent'])
        self.assertTrue(all(not guard.same_process(row) for row in runner.owned.values()))
        self.assertIn(int(ready.read_text()), runner.owned)
        self.assertIsNone(sentinel.poll())
        sentinel.terminate()
        sentinel.wait(timeout=3)

    def test_timeout_is_not_reported_as_a_test_failure(self):
        runner = self.runner(timeout=.1)
        self.assertEqual(runner.run([sys.executable, '-c', 'import time; time.sleep(60)']), 124)
        self.assertEqual(runner.state['terminationReason'], 'command timed out')
        self.assertFalse(runner.state['accepted'])

    def test_live_memory_reserve_stops_own_command(self):
        samples = iter([GOOD_MEMORY, dict(availableMiB=512, combinedUsedRatio=.4)])
        runner = self.runner(mem_sample=lambda: next(samples))
        self.assertEqual(runner.run([sys.executable, '-c', 'import time; time.sleep(60)']), 125)
        self.assertIn('memory', runner.state['terminationReason'])
        self.assertTrue(all(not guard.same_process(row) for row in runner.owned.values()))

    def test_ignored_term_escalates_only_for_owned_child(self):
        ready = self.root / 'ready'
        runner = self.runner(disk_sample=lambda: 11 if ready.exists() else 30)
        command = ('import signal,sys,time; from pathlib import Path; '
                   'signal.signal(signal.SIGTERM, signal.SIG_IGN); '
                   'Path(sys.argv[1]).touch(); time.sleep(60)')
        self.assertEqual(runner.run([sys.executable, '-c', command, str(ready)]), 125)
        self.assertTrue(any(row['signal'] == 9 for row in runner.state['signalsSent']))
        self.assertTrue(all(not guard.same_process(row) for row in runner.owned.values()))

    def test_report_write_failure_does_not_interrupt_owned_cleanup(self):
        ready = self.root / 'report-failure-ready'
        runner = self.runner(disk_sample=lambda: 11 if ready.exists() else 30)
        command = ('import signal,sys,time; from pathlib import Path; '
                   'signal.signal(signal.SIGTERM, signal.SIG_IGN); '
                   'Path(sys.argv[1]).touch(); time.sleep(60)')
        actual_save = runner.save

        def failed_cleanup_report():
            if runner.state['signalsSent']:
                raise OSError('synthetic report write failure')
            actual_save()

        try:
            with patch.object(runner, 'save', side_effect=failed_cleanup_report):
                self.assertEqual(runner.run([sys.executable, '-c', command, str(ready)]), 125)
            self.assertTrue(any(row['signal'] == 9 for row in runner.state['signalsSent']))
            self.assertTrue(all(not guard.same_process(row) for row in runner.owned.values()))
            self.assertFalse(runner.state['accepted'])
            self.assertIn('synthetic report write failure', runner.state['cleanupReportError'])
        finally:
            for row in runner.owned.values():
                if guard.same_process(row):
                    os.kill(row['pid'], 9)
            if runner.process is not None:
                runner.process.wait(timeout=3)

    def test_orphan_is_stopped_after_successful_parent_exit(self):
        ready = self.root / 'child.pid'
        runner = self.runner()
        command = ('import subprocess,sys; from pathlib import Path; '
                   'child=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"]); '
                   'Path(sys.argv[1]).write_text(str(child.pid))')
        self.assertEqual(runner.run([sys.executable, '-c', command, str(ready)]), 0)
        self.assertIn(int(ready.read_text()), runner.owned)
        self.assertTrue(all(not guard.same_process(row) for row in runner.owned.values()))

    def test_foreign_or_reused_process_group_does_not_grant_ownership(self):
        proc = self.root / 'proc'
        (proc / '456').mkdir(parents=True)
        (proc / '456/environ').write_bytes(b'KEEP=foreign\0')
        runner = self.runner()
        runner.process = type('FakeProcess', (), dict(pid=123))()
        actual_path = Path

        def mapped_path(value):
            value = str(value)
            return proc / value[6:] if value.startswith('/proc/') else proc if value == '/proc' else actual_path(value)

        row = dict(pid=456, parent=1, group=123, start='999', state='S')
        with patch.object(guard, 'Path', mapped_path), patch.object(guard, 'identity', return_value=row):
            runner.track()
        self.assertEqual(runner.owned, {})

    def test_detached_marker_worker_is_stopped_after_launcher_exits(self):
        ready = self.root / 'detached.pid'
        runner = self.runner()
        command = ('import subprocess,sys; from pathlib import Path; '
                   'child=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"], '
                   'start_new_session=True); '
                   'Path(sys.argv[1]).write_text(str(child.pid))')
        self.assertEqual(runner.run([sys.executable, '-c', command, str(ready)]), 0)
        child = int(ready.read_text())
        self.assertIn(child, runner.owned)
        self.assertEqual(runner.owned[child]['group'], child)
        self.assertTrue(all(not guard.same_process(row) for row in runner.owned.values()))

    def test_return_after_deadline_is_rejected(self):
        # A delayed transport can return after its requested wait expired.
        # Recheck the monotonic deadline even when wait reports exit zero.
        runner = self.runner(timeout=1)
        row = dict(pid=123, parent=1, group=123, start='original', state='S')
        child = type('FakeProcess', (), dict(pid=123, wait=lambda *a, **k: 0))()
        with patch.object(runner, 'prepare'), patch.object(runner, 'track'), \
                patch.object(runner, 'stop_owned', return_value=True), \
                patch.object(guard, 'identity', return_value=row), \
                patch.object(guard.subprocess, 'Popen', return_value=child), \
                patch.object(guard.time, 'monotonic', side_effect=[0, .2, .3, 1.1, 1.2]):
            self.assertEqual(runner.run(['synthetic']), 124)
        self.assertFalse(runner.state['accepted'])

    def test_detached_marker_admission_requires_uid_and_unchanged_birth(self):
        proc = self.root / 'proc'
        (proc / '456').mkdir(parents=True)
        actual_path = Path
        own_uid = os.geteuid()

        def mapped_path(value):
            value = str(value)
            return proc / value[6:] if value.startswith('/proc/') else proc if value == '/proc' else actual_path(value)

        for same_uid, same_birth in ((True, True), (False, True), (True, False)):
            with self.subTest(same_uid=same_uid, same_birth=same_birth):
                runner = self.runner()
                runner.process = type('FakeProcess', (), dict(pid=123))()
                (proc / '456/environ').write_bytes((guard.RUN_KEY + '=' + runner.nonce).encode() + b'\0')
                row = dict(pid=456, parent=1, group=456, start='original', state='S')
                identities = [row, row if same_birth else {**row, 'start': 'replacement'}]
                with patch.object(guard, 'Path', mapped_path), \
                        patch.object(guard, 'identity', side_effect=identities), \
                        patch.object(guard.os, 'geteuid', return_value=own_uid if same_uid else own_uid + 1):
                    runner.track()
                self.assertEqual(456 in runner.owned, same_uid and same_birth)

    def test_birth_mismatch_is_never_live(self):
        row = dict(pid=123, parent=1, group=123, start='original', state='S')
        with patch.object(guard, 'identity', return_value={**row, 'start': 'replacement'}):
            self.assertFalse(guard.same_process(row))

    def test_daemon_requires_home_and_nonce_even_before_its_log_exists(self):
        home = self.root / 'gradle'
        proc = self.root / 'proc'
        (home / 'daemon/9').mkdir(parents=True)
        (proc / '456').mkdir(parents=True)
        (proc / '456/cmdline').write_bytes(b'java\0' + guard.DAEMON_CLASS + b'\0')
        runner = self.runner(build=True)
        runner.home = home
        actual_path = Path

        def mapped_path(value):
            return proc if str(value) == '/proc' else actual_path(value)

        row = dict(pid=456, parent=1, group=456, start='999', state='S')
        env_path = proc / '456/environ'
        for nonce, log, expected in [(False, False, False), (True, False, True),
                                     (False, True, False), (True, True, True)]:
            env_path.write_bytes(('GRADLE_USER_HOME=' + str(home) + '\0' +
                (guard.RUN_KEY + '=' + runner.nonce if nonce else '')).encode())
            logfile = home / 'daemon/9/daemon-456.out.log'
            if log:
                logfile.touch()
            elif logfile.exists():
                logfile.unlink()
            with patch.object(guard, 'Path', mapped_path), patch.object(guard, 'identity', return_value=row):
                found = runner.daemons()
            self.assertEqual(found[0]['ownedDaemon'], expected)
            self.assertEqual(found[0]['daemonLogObserved'], log)

    def test_detached_synthetic_daemon_stopped_after_parent_exit(self):
        home = self.root / 'gradle'
        ready = self.root / 'daemon.pid'
        runner = self.runner(build=True, minimum=25,
                             environment={'GRADLE_USER_HOME': str(home)})
        daemon_code = 'import time; time.sleep(60)'
        command = ('import subprocess,sys; from pathlib import Path; '
                   'child=subprocess.Popen(["java","-c",sys.argv[2],sys.argv[3]], '
                   'executable=sys.executable,start_new_session=True); '
                   'Path(sys.argv[1]).write_text(str(child.pid))')
        self.assertEqual(runner.run([sys.executable, '-c', command, str(ready),
                                   daemon_code, guard.DAEMON_CLASS.decode()]), 0)
        self.assertIn(int(ready.read_text()), runner.owned)
        self.assertTrue(all(not guard.same_process(row) for row in runner.owned.values()))

    def test_daemon_environment_cannot_admit_a_replacement_birth(self):
        home = self.root / 'gradle'
        proc = self.root / 'proc'
        (proc / '456').mkdir(parents=True)
        (proc / '456/cmdline').write_bytes(b'java\0' + guard.DAEMON_CLASS + b'\0')
        runner = self.runner(build=True)
        runner.home = home
        (proc / '456/environ').write_bytes(
            ('GRADLE_USER_HOME=' + str(home) + '\0' + guard.RUN_KEY + '=' + runner.nonce).encode())
        actual_path = Path
        def mapped_path(value):
            return proc if str(value) == '/proc' else actual_path(value)
        row = dict(pid=456, parent=1, group=456, start='original', state='S')
        with patch.object(guard, 'Path', mapped_path), \
                patch.object(guard, 'identity', side_effect=[row, {**row, 'start': 'replacement'}]):
            self.assertEqual(runner.daemons(), [])

    def test_pidfd_rechecks_birth_and_closes_rejected_handle(self):
        row = dict(pid=123, parent=1, group=123, start='original', state='S')
        with patch.object(guard, 'identity', side_effect=[row, {**row, 'start': 'replacement'}]), \
                patch.object(guard.os, 'pidfd_open', return_value=77) as opened, \
                patch.object(guard.signal, 'pidfd_send_signal') as sent, \
                patch.object(guard.os, 'close') as closed:
            self.assertFalse(guard.signal_owned_process(row, 15))
        opened.assert_called_once_with(123)
        sent.assert_not_called()
        closed.assert_called_once_with(77)

    def test_pidfd_signals_only_validated_handle(self):
        row = dict(pid=123, parent=1, group=123, start='original', state='S')
        with patch.object(guard, 'identity', return_value=row), \
                patch.object(guard.os, 'pidfd_open', return_value=77), \
                patch.object(guard.signal, 'pidfd_send_signal') as sent, \
                patch.object(guard.os, 'kill') as numeric, \
                patch.object(guard.os, 'close') as closed:
            self.assertTrue(guard.signal_owned_process(row, 15))
        sent.assert_called_once_with(77, 15)
        numeric.assert_not_called()
        closed.assert_called_once_with(77)

    def test_lineage_does_not_admit_replacement_parents_child(self):
        proc = self.root / 'proc'
        (proc / '123').mkdir(parents=True)
        (proc / '456').mkdir(parents=True)
        actual_path = Path
        def mapped_path(value):
            return proc if str(value) == '/proc' else actual_path(value)
        parent = dict(pid=123, parent=1, group=123, start='original', state='S')
        child = dict(pid=456, parent=123, group=123, start='child', state='S')
        runner = self.runner()
        runner.owned[123] = parent
        parent_reads = 0
        def read_identity(pid):
            nonlocal parent_reads
            if pid == 456:
                return child
            parent_reads += 1
            return parent if parent_reads == 1 else {**parent, 'start': 'replacement'}
        with patch.object(guard, 'Path', mapped_path), \
                patch.object(guard, 'identity', side_effect=read_identity):
            runner.track()
        self.assertNotIn(456, runner.owned)

    def test_external_signal_records_interrupt_and_cleans_child(self):
        report = self.root / 'external.json'
        scripts = self.root / 'scripts'
        scripts.mkdir()
        script = scripts / 'resource_guard.py'
        shutil.copyfile(guard.__file__, script)
        # Exercise a disposable project's lock, preserving the host runner's lock.
        command = [sys.executable, str(script), '--interval', '.05',
                   '--report', str(report), '--', sys.executable, '-c',
                   'import time; time.sleep(60)']
        process = subprocess.Popen(command)
        self.addCleanup(lambda: process.poll() is None and process.kill())
        import time
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if report.exists() and json.loads(report.read_text()).get('childPid'):
                break
            if process.poll() is not None:
                self.fail('Guard exited before signal test admission')
            time.sleep(.05)
        else:
            self.fail('Guard did not launch the disposable child')
        process.terminate()
        self.assertEqual(process.wait(timeout=10), 143)
        result = json.loads(report.read_text())
        self.assertEqual(result['exitCode'], 143)
        self.assertFalse(result['accepted'])
        self.assertTrue(all(not guard.same_process(row) for row in result['trackedIdentities']))

    def test_shared_gradle_home_is_refused(self):
        runner = self.runner(build=True, minimum=25,
                             environment={'GRADLE_USER_HOME': str(Path.home() / '.gradle')})
        with self.assertRaisesRegex(RuntimeError, 'Shared'):
            runner.prepare()

    def test_build_floor_cannot_be_lowered(self):
        with self.assertRaisesRegex(RuntimeError, 'Invalid resource'):
            self.runner(build=True, minimum=12).prepare()

    def test_missing_gradle_home_created_only_after_budget_admission(self):
        home = self.root / 'dedicated-gradle'
        denied = self.runner(build=True, minimum=25, disk_sample=lambda: 24,
                             environment={'GRADLE_USER_HOME': str(home)})
        with self.assertRaisesRegex(RuntimeError, 'disk budget'):
            denied.prepare()
        self.assertFalse(home.exists())
        admitted = self.runner(build=True, minimum=25,
                               environment={'GRADLE_USER_HOME': str(home)})
        admitted.prepare()
        self.assertTrue(home.is_dir())

    def test_known_root_does_not_require_reading_its_environment(self):
        proc = self.root / 'proc'
        (proc / '123').mkdir(parents=True)
        runner = self.runner()
        runner.process = type('FakeProcess', (), dict(pid=123))()
        row = dict(pid=123, parent=1, group=123, start='original', state='S')
        runner.owned[123] = row
        actual_path = Path

        def mapped_path(value):
            if str(value) == '/proc':
                return proc
            if str(value).endswith('/environ'):
                raise PermissionError('Restricted process environment')
            return actual_path(value)

        with patch.object(guard, 'Path', mapped_path), patch.object(guard, 'identity', return_value=row):
            runner.track()
        self.assertEqual(runner.owned[123]['start'], 'original')

    def test_report_is_never_overwritten(self):
        path = self.root / 'guard.json'
        path.write_text('retained evidence')
        with self.assertRaisesRegex(RuntimeError, 'Preserve existing'):
            self.runner().prepare()
        self.assertEqual(path.read_text(), 'retained evidence')

    def test_lock_excludes_second_owner_and_accepts_inherited_descriptor(self):
        with guard.acquire_lock(self.root) as first:
            with self.assertRaises(BlockingIOError):
                guard.acquire_lock(self.root)
            with guard.acquire_lock(self.root, first.fileno()):
                pass
            with (self.root / 'other').open('w') as wrong:
                with self.assertRaisesRegex(RuntimeError, 'not the project'):
                    guard.acquire_lock(self.root, wrong.fileno())

    def test_lock_symlink_is_refused_without_creating_its_target(self):
        lock = self.root / guard.LOCK
        lock.parent.mkdir(parents=True)
        target = self.root / 'must-not-be-created'
        lock.symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, 'symlink'):
            guard.acquire_lock(self.root)
        self.assertFalse(target.exists())

    def test_lock_ancestor_symlink_is_refused_without_writes(self):
        target = self.root / 'external-evidence'
        target.mkdir()
        (self.root / 'evidence').symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, 'symlink'):
            guard.acquire_lock(self.root)
        self.assertEqual(list(target.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
