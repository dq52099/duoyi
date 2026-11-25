"""Lifecycle checks with disposable commands and temporary project locks only."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import resource_guard as guard
import start_guarded_verification as launcher


class GuardedVerificationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='duoyi-launcher-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.addCleanup(patch.stopall)
        patch.object(launcher, 'ROOT', self.root).start()
        self.next = 0

    def reserve(self, command=None, timeout=30):
        self.next += 1
        folder = self.root / 'evidence' / str(self.next)
        folder.mkdir(parents=True)
        command = command or [sys.executable, '-c', 'pass']
        launcher.publish_json(folder / 'intent.json', dict(reservation='test-reservation',
                              command=command, timeout=timeout))
        return folder, command, timeout

    def execute(self, reservation):
        folder, command, timeout = reservation
        return launcher.run_worker(folder, 'test-reservation', timeout, command)

    def test_success_and_nonzero_exit_are_truthful(self):
        for code in (0, 7):
            with self.subTest(code=code):
                job = self.reserve([sys.executable, '-c', f'raise SystemExit({code})'])
                self.assertEqual(self.execute(job), code)
                result = json.loads((job[0] / 'outcome.json').read_text())
                self.assertEqual(result['accepted'], code == 0)
                self.assertEqual(result['exitCode'], code)
                self.assertTrue((job[0] / 'worker.json').exists())
                with guard.acquire_lock(self.root):
                    pass

    def test_timeout_stops_the_owned_command(self):
        job = self.reserve([sys.executable, '-c', 'import time; time.sleep(60)'], .05)
        self.assertEqual(self.execute(job), 124)
        result = json.loads((job[0] / 'guard.json').read_text())
        self.assertFalse(result['accepted'])
        self.assertTrue(all(not guard.same_process(row) for row in result['trackedIdentities']))

    def test_admission_signals_record_interrupt_without_launching(self):
        for number in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=number):
                job = self.reserve([sys.executable, '-c', 'raise AssertionError()'])
                actual_sample = guard.memory_sample

                def canceled_sample():
                    os.kill(os.getpid(), number)
                    return actual_sample()

                with patch.object(guard, 'memory_sample', side_effect=canceled_sample):
                    self.assertEqual(self.execute(job), 128 + number)
                outcome = json.loads((job[0] / 'outcome.json').read_text())
                report = json.loads((job[0] / 'guard.json').read_text())
                self.assertFalse(outcome['accepted'])
                self.assertEqual(outcome['state'], 'canceled')
                self.assertNotIn('childPid', report)

    def test_memory_and_disk_rejection_publish_terminal_outcomes(self):
        for reason in ('memory', 'disk'):
            with self.subTest(reason=reason):
                job = self.reserve()
                replacement = (patch.object(guard, 'memory_sample', return_value={
                    'availableMiB': 512, 'combinedUsedRatio': .4}) if reason == 'memory' else
                    patch.object(guard.shutil, 'disk_usage', return_value=type('Usage', (), {'free': 11 * 2**30})()))
                with replacement:
                    self.assertEqual(self.execute(job), 125)
                outcome = json.loads((job[0] / 'outcome.json').read_text())
                self.assertFalse(outcome['accepted'])
                self.assertIn(reason, outcome['terminationReason'])
                self.assertFalse((job[0] / 'guard.json').exists())

    def test_lock_contention_never_launches_work(self):
        job = self.reserve()
        with guard.acquire_lock(self.root):
            self.assertEqual(self.execute(job), 125)
        self.assertFalse((job[0] / 'guard.json').exists())
        self.assertFalse(json.loads((job[0] / 'outcome.json').read_text())['accepted'])

    def test_repeated_worker_cannot_overwrite_evidence(self):
        job = self.reserve()
        self.assertEqual(self.execute(job), 0)
        before = {p.name: p.read_bytes() for p in job[0].iterdir()}
        with self.assertRaisesRegex(RuntimeError, 'Preserve existing'):
            self.execute(job)
        self.assertEqual(before, {p.name: p.read_bytes() for p in job[0].iterdir()})

    def test_incorrect_reservation_never_claims_or_launches(self):
        folder, command, timeout = self.reserve()
        with self.assertRaisesRegex(RuntimeError, 'reserved launch intent'):
            launcher.run_worker(folder, 'wrong', timeout, command)
        self.assertEqual([p.name for p in folder.iterdir()], ['intent.json'])

    def test_outcome_symlink_preserves_external_data(self):
        job = self.reserve()
        target = self.root / 'retained-result'
        target.write_text('retained')
        (job[0] / 'outcome.json').symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, 'Preserve existing'):
            self.execute(job)
        self.assertEqual(target.read_text(), 'retained')
        self.assertFalse((job[0] / 'worker.claim').exists())

    def test_atomic_publication_refuses_existing_and_symlink_records(self):
        target = self.root / 'retained'
        target.write_text('keep')
        link = self.root / 'link'
        link.symlink_to(target)
        for path in (target, link):
            with self.assertRaises(FileExistsError):
                launcher.publish_json(path, {'accepted': True})
        self.assertEqual(target.read_text(), 'keep')
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ['link', 'retained'])

    def test_registration_failure_publishes_rejection_without_launching(self):
        job = self.reserve()
        actual_publish = launcher.publish_json

        def failed_registration(path, value, **options):
            if path.name == 'worker.json':
                raise OSError('synthetic registration failure')
            actual_publish(path, value, **options)

        with patch.object(launcher, 'publish_json', side_effect=failed_registration):
            self.assertEqual(self.execute(job), 125)
        outcome = json.loads((job[0] / 'outcome.json').read_text())
        self.assertIn('registration failure', outcome['terminationReason'])
        self.assertFalse((job[0] / 'guard.json').exists())

    def test_receipt_failure_stops_the_actual_detached_worker(self):
        scripts = self.root / 'scripts'
        scripts.mkdir()
        source = Path(guard.__file__).parent
        for name in ('resource_guard.py', 'disk_budget.py', 'start_guarded_verification.py'):
            shutil.copyfile(source / name, scripts / name)
        folder = self.root / 'evidence' / 'receipt-failure'
        actual_publish = launcher.publish_json

        def failed_receipt(path, value, **options):
            if path.name == 'launch.json':
                raise OSError('synthetic receipt failure')
            actual_publish(path, value, **options)

        args = ['launcher', '--output-dir', str(folder), '--timeout', '30', '--',
                sys.executable, '-c', 'import time; time.sleep(60)']
        with patch.object(launcher, '__file__', str(scripts / 'start_guarded_verification.py')), \
                patch.object(sys, 'argv', args), \
                patch.object(launcher, 'publish_json', side_effect=failed_receipt):
            with self.assertRaisesRegex(OSError, 'receipt failure'):
                launcher.main()
        self.assertTrue((folder / 'intent.json').exists())
        outcome = json.loads((folder / 'outcome.json').read_text())
        self.assertFalse(outcome['accepted'])
        self.assertEqual(outcome['exitCode'], 143)
        if (folder / 'worker.json').exists():
            row = json.loads((folder / 'worker.json').read_text())['identity']
            self.assertFalse(guard.same_process(row))
        if (folder / 'guard.json').exists():
            report = json.loads((folder / 'guard.json').read_text())
            self.assertTrue(all(not guard.same_process(row) for row in report['trackedIdentities']))
        with guard.acquire_lock(self.root):
            pass

    def test_cancel_at_outcome_publication_never_publishes_success(self):
        job = self.reserve()
        actual_publish = launcher.publish_json

        def cancel_publication(path, value, **options):
            if path.name == 'outcome.json':
                os.kill(os.getpid(), signal.SIGTERM)
            actual_publish(path, value, **options)

        with patch.object(launcher, 'publish_json', side_effect=cancel_publication):
            self.assertEqual(self.execute(job), 143)
        result = json.loads((job[0] / 'outcome.json').read_text())
        self.assertFalse(result['accepted'])
        self.assertEqual(result['exitCode'], 143)

    def host_scripts(self, worker_prelude):
        scripts = self.root / 'scripts'
        scripts.mkdir()
        source = Path(guard.__file__).parent
        for name in ('resource_guard.py', 'disk_budget.py'):
            shutil.copyfile(source / name, scripts / name)
        entry = scripts / 'start_guarded_verification.py'
        entry.write_text(worker_prelude + (source / entry.name).read_text())
        return entry

    def test_successful_receipt_waits_for_worker_registration(self):
        entry = self.host_scripts(
            "import sys, time\nif '--worker' in sys.argv: time.sleep(.5)\n")
        folder = self.root / 'evidence' / 'delayed-worker'
        args = ['launcher', '--output-dir', str(folder), '--timeout', '30', '--',
                sys.executable, '-c', 'import time; time.sleep(60)']
        row = None
        try:
            with patch.object(launcher, '__file__', str(entry)), \
                    patch.object(sys, 'argv', args):
                self.assertEqual(launcher.main(), 0)
            row = json.loads((folder / 'launch.json').read_text())['identity']
            self.assertTrue((folder / 'worker.json').exists(),
                            'A successful launch must return a cancellable registered worker.')
            registered = json.loads((folder / 'worker.json').read_text())['identity']
            self.assertEqual((registered['pid'], registered['start']),
                             (row['pid'], row['start']))
        finally:
            if row is None and (folder / 'launch.json').exists():
                row = json.loads((folder / 'launch.json').read_text())['identity']
            if row is not None and guard.same_process(row):
                os.kill(row['pid'], signal.SIGTERM)
            deadline = time.monotonic() + 15
            while row is not None and guard.same_process(row) and time.monotonic() < deadline:
                time.sleep(.02)
        self.assertFalse(guard.same_process(row))
        outcome = json.loads((folder / 'outcome.json').read_text())
        self.assertFalse(outcome['accepted'])
        self.assertEqual(outcome['exitCode'], 143)
        if (folder / 'guard.json').exists():
            report = json.loads((folder / 'guard.json').read_text())
            self.assertTrue(all(not guard.same_process(r) for r in report['trackedIdentities']))

    def test_exit_before_registration_publishes_terminal_rejection(self):
        entry = self.host_scripts("import sys\nif '--worker' in sys.argv: sys.exit(19)\n")
        folder = self.root / 'evidence' / 'early-exit'
        args = ['launcher', '--output-dir', str(folder), '--timeout', '30', '--',
                sys.executable, '-c', 'raise AssertionError("must not launch")']
        with patch.object(launcher, '__file__', str(entry)), \
                patch.object(sys, 'argv', args):
            self.assertEqual(launcher.main(), 125)
        outcome = json.loads((folder / 'outcome.json').read_text())
        self.assertFalse(outcome['accepted'])
        self.assertIn('registration', outcome['terminationReason'])
        self.assertFalse((folder / 'worker.json').exists())
        self.assertFalse((folder / 'guard.json').exists())
        self.assertFalse((folder / 'launch.json').exists())

    def check_parent_startup_cancellation(self, number):
        entry = self.host_scripts(
            "import sys, time, json, os\n"
            "from pathlib import Path\n"
            "if '--worker' in sys.argv:\n"
            "    import resource_guard as bootstrap_guard\n"
            "    folder = Path(sys.argv[sys.argv.index('--output-dir') + 1])\n"
            "    (folder / 'bootstrap.tmp').write_text(json.dumps(bootstrap_guard.identity(os.getpid())))\n"
            "    (folder / 'bootstrap.tmp').rename(folder / 'bootstrap.json')\n"
            "    time.sleep(2)\n")
        folder = self.root / 'evidence' / 'parent-cancellation'
        marker = self.root / 'workload-started'
        command = [sys.executable, str(entry), '--output-dir', str(folder),
                   '--timeout', '30', '--', sys.executable, '-c',
                   f'from pathlib import Path; Path({str(marker)!r}).write_text("unexpected")']
        parent = subprocess.Popen(command, cwd=self.root, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True, start_new_session=True)
        worker = None
        try:
            deadline = time.monotonic() + 10
            while not (folder / 'bootstrap.json').exists() and time.monotonic() < deadline:
                if parent.poll() is not None:
                    break
                time.sleep(.02)
            self.assertTrue((folder / 'bootstrap.json').exists(), 'Delayed worker never started.')
            worker = json.loads((folder / 'bootstrap.json').read_text())
            parent.send_signal(number)
            output, errors = parent.communicate(timeout=20)
            self.assertEqual(parent.returncode, 128 + number, output + errors)
            outcome = json.loads((folder / 'outcome.json').read_text())
            self.assertFalse(outcome['accepted'])
            self.assertEqual(outcome['exitCode'], 128 + number)
            self.assertFalse((folder / 'launch.json').exists())
            self.assertFalse(guard.same_process(worker))
            self.assertFalse(marker.exists())
        finally:
            if parent.poll() is None:
                parent.terminate()
                parent.wait(timeout=20)
            if worker is not None and guard.same_process(worker):
                os.kill(worker['pid'], signal.SIGTERM)
                deadline = time.monotonic() + 10
                while guard.same_process(worker) and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertFalse(guard.same_process(worker))
            parent.stdout.close()
            parent.stderr.close()

    def test_sigint_during_parent_startup_stops_worker(self):
        self.check_parent_startup_cancellation(signal.SIGINT)

    def test_sigterm_during_parent_startup_stops_worker(self):
        self.check_parent_startup_cancellation(signal.SIGTERM)

    def test_sigint_after_registration_preserves_terminal_exit(self):
        entry = self.host_scripts('')
        folder = self.root / 'evidence' / 'registered-cancellation'
        args = ['launcher', '--output-dir', str(folder), '--timeout', '30', '--',
                sys.executable, '-c', 'import time; time.sleep(60)']
        actual_wait = launcher.wait_for_registration

        def cancel_registered(*arguments, **options):
            actual_wait(*arguments, **options)
            os.kill(os.getpid(), signal.SIGINT)

        with patch.object(launcher, '__file__', str(entry)), \
                patch.object(sys, 'argv', args), \
                patch.object(launcher, 'wait_for_registration', side_effect=cancel_registered):
            self.assertEqual(launcher.main(), 130)
        outcome = json.loads((folder / 'outcome.json').read_text())
        self.assertFalse(outcome['accepted'])
        self.assertEqual(outcome['exitCode'], 130)
        row = json.loads((folder / 'worker.json').read_text())['identity']
        self.assertFalse(guard.same_process(row))
        if (folder / 'guard.json').exists():
            report = json.loads((folder / 'guard.json').read_text())
            self.assertTrue(all(not guard.same_process(r) for r in report['trackedIdentities']))

    def test_early_claim_cancellation_records_a_terminal_rejection(self):
        job = self.reserve()
        actual_publish = launcher.publish_json

        def cancel_claim(path, value, **options):
            if path.name == 'worker.claim':
                os.kill(os.getpid(), signal.SIGTERM)
            actual_publish(path, value, **options)

        with patch.object(launcher, 'publish_json', side_effect=cancel_claim):
            self.assertEqual(self.execute(job), 143)
        result = json.loads((job[0] / 'outcome.json').read_text())
        self.assertFalse(result['accepted'])
        self.assertFalse((job[0] / 'guard.json').exists())

    def test_invalid_output_traversal_and_nonfinite_timeout_never_launch(self):
        for output, timeout in [(self.root / 'evidence/../lib/escaped', '30'),
                                (self.root / 'evidence/nan', 'nan')]:
            args = ['launcher', '--output-dir', str(output), '--timeout', timeout,
                    '--', sys.executable, '-c', 'pass']
            with patch.object(sys, 'argv', args):
                with self.assertRaises(SystemExit) as error:
                    launcher.main()
            self.assertEqual(error.exception.code, 2)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
