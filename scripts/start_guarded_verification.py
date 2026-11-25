#!/usr/bin/env python3
"""Start a persistent worker with durable identity and terminal evidence.

The worker owns the shared lock. Do not nest it inside a lock-owning runner.
Read outcome.json and validate launch/worker identities before reporting a wait.
"""
import argparse
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import uuid

from resource_guard import ROOT, ResourceGuard, acquire_lock, identity, same_process


def publish_json(path, value, before_commit=None):
    """Publish a complete new record without replacing evidence or following links."""
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    old_mask = None
    try:
        with os.fdopen(descriptor, 'w') as output:
            if before_commit is not None:
                old_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
                before_commit(False)
            payload = json.dumps(value, indent=2) + '\n'
            output.write(payload)
            output.flush()
            os.fsync(output.fileno())
            if before_commit is not None:
                before_commit(True)
                updated = json.dumps(value, indent=2) + '\n'
                if updated != payload:
                    output.seek(0)
                    output.truncate()
                    output.write(updated)
                    output.flush()
                    os.fsync(output.fileno())
        os.link(temporary, path)
    finally:
        if old_mask is not None:
            signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
        os.unlink(temporary)


def run_worker(folder, reservation, timeout, command):
    result = dict(accepted=False, exitCode=125, state='not admitted')
    canceled = None
    guard = None
    claimed = False
    committed = False

    def on_signal(number, frame):
        nonlocal canceled
        if committed:
            return
        canceled = number
        if guard is not None:
            guard.interrupted = number

    old_handlers = {number: signal.signal(number, on_signal)
                    for number in (signal.SIGTERM, signal.SIGINT)}
    try:
        intent = json.loads((folder / 'intent.json').read_text())
        if (intent['reservation'] != reservation or intent['command'] != command or
                intent['timeout'] != timeout):
            raise RuntimeError('Worker does not match the reserved launch intent.')
        if any((folder / name).exists() or (folder / name).is_symlink()
               for name in ('worker.json', 'outcome.json', 'guard.json')):
            raise RuntimeError('Preserve existing worker and verification evidence.')
        publish_json(folder / 'worker.claim', dict(reservation=reservation))
        claimed = True
        row = identity(os.getpid())
        if row is None:
            raise RuntimeError('Worker process identity could not be recorded.')
        publish_json(folder / 'worker.json', dict(identity=row, state='registered; admission pending'))
        if canceled is not None:
            raise RuntimeError('Worker canceled before admission.')
        with acquire_lock(ROOT):
            guard = ResourceGuard(ROOT, folder / 'guard.json', timeout=timeout)
            guard.interrupted = canceled
            code = guard.run(command)
            result.update(exitCode=code, accepted=bool(guard.state.get('accepted')),
                          state='finished', terminationReason=guard.state.get('terminationReason'))
    except (RuntimeError, OSError, KeyboardInterrupt) as error:
        if not claimed:
            raise
        result.update(terminationReason=str(error), state='admission failed')
    finally:
        def finalize(complete):
            nonlocal committed
            pending = signal.sigpending()
            number = (canceled or (guard.interrupted if guard is not None else None) or
                      (signal.SIGTERM if signal.SIGTERM in pending else
                       signal.SIGINT if signal.SIGINT in pending else None))
            if number is not None:
                result.update(accepted=False, exitCode=128 + number, state='canceled',
                              terminationReason='interrupted by signal ' + str(number))
            # The command and owned cleanup already ended. This is the final
            # cancellation boundary; later signals cannot change completed work.
            committed = complete
        try:
            if claimed:
                publish_json(folder / 'outcome.json', result, before_commit=finalize)
        finally:
            for number, handler in old_handlers.items():
                signal.signal(number, handler)
    return result['exitCode']


class LaunchCanceled(RuntimeError):
    def __init__(self, number):
        self.number = number
        super().__init__('Launch canceled by signal ' + str(number))


def wait_for_registration(process, folder, launched_identity, cancellation=lambda: None):
    """Return a receipt only after the worker can record an early cancellation."""
    if launched_identity is None:
        raise RuntimeError('Worker identity unavailable before registration.')
    deadline = time.monotonic() + 10
    while True:
        number = cancellation()
        if number is not None:
            raise LaunchCanceled(number)
        record = folder / 'worker.json'
        if record.is_file() and not record.is_symlink():
            registered = json.loads(record.read_text())['identity']
            if any(registered[key] != launched_identity[key] for key in ('pid', 'start')):
                raise RuntimeError('Worker registration does not match the launched identity.')
            return
        code = process.poll()
        if code is not None:
            raise RuntimeError(f'Worker exited before registration (exit {code}).')
        if time.monotonic() >= deadline:
            raise RuntimeError('Worker registration timed out.')
        time.sleep(.01)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=3600)
    parser.add_argument('--worker', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--reservation', help=argparse.SUPPRESS)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('A verification command is required after --.')
    raw = args.output_dir.absolute()
    if (any(path.is_symlink() for path in (raw, *raw.parents)) or
            not raw.resolve().is_relative_to(ROOT / 'evidence') or
            (raw.exists() and not args.worker)):
        parser.error('Choose a new nonsymlinked output directory under repository evidence/.')
    if not math.isfinite(args.timeout) or args.timeout <= 0 or args.timeout > 3600:
        parser.error('Verification timeout must be between 0 and 3600 seconds.')
    if args.worker:
        if not raw.is_dir() or not args.reservation:
            parser.error('Worker requires an existing reserved output directory.')
        try:
            return run_worker(raw, args.reservation, args.timeout, command)
        except (RuntimeError, OSError, ValueError) as error:
            print('Verification worker refused: ' + str(error), file=sys.stderr)
            return 125
    subprocess.run([sys.executable, str(ROOT / 'scripts/disk_budget.py'), 'check'], check=True)
    raw.mkdir(parents=True)
    reservation = uuid.uuid4().hex
    publish_json(raw / 'intent.json', dict(reservation=reservation, command=command,
                                         timeout=args.timeout, accepted=False))
    guard_command = [sys.executable, str(Path(__file__).resolve()), '--worker',
                     '--output-dir', str(raw), '--timeout', str(args.timeout),
                     '--reservation', reservation, '--', *command]
    process = None
    row = None
    canceled = None
    committed = False

    def on_signal(number, frame):
        nonlocal canceled
        if not committed:
            canceled = number

    def receipt_boundary(complete):
        nonlocal committed
        pending = signal.sigpending()
        number = canceled or (signal.SIGTERM if signal.SIGTERM in pending else
                              signal.SIGINT if signal.SIGINT in pending else None)
        if number is not None:
            raise LaunchCanceled(number)
        committed = complete

    old_handlers = {number: signal.signal(number, on_signal)
                    for number in (signal.SIGTERM, signal.SIGINT)}
    try:
        with (raw / 'command.log').open('x') as log:
            if canceled is not None:
                raise LaunchCanceled(canceled)
            process = subprocess.Popen(guard_command, cwd=ROOT, stdin=subprocess.DEVNULL,
                                       stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        row = identity(process.pid)
        receipt = dict(pid=process.pid, identity=row, command=command,
                       intent=str(raw / 'intent.json'), workerRecord=str(raw / 'worker.json'),
                       guardReport=str(raw / 'guard.json'), log=str(raw / 'command.log'),
                       accepted=False, state='started; admission and result not yet collected')
        wait_for_registration(process, raw, row, cancellation=lambda: canceled)
        publish_json(raw / 'launch.json', receipt, before_commit=receipt_boundary)
    except (OSError, RuntimeError, KeyboardInterrupt) as error:
        # A child owned by Popen cannot have its PID reused before it is reaped.
        # Recorded identities prove termination when registration has begun.
        if process is not None:
            if (row is not None and same_process(row)) or (row is None and process.poll() is None):
                number = (error.number if isinstance(error, LaunchCanceled) else
                          signal.SIGINT if isinstance(error, KeyboardInterrupt) else signal.SIGTERM)
                process.send_signal(number)
            process.wait(timeout=20)
        code = (128 + error.number if isinstance(error, LaunchCanceled) else
                130 if isinstance(error, KeyboardInterrupt) else
                143 if isinstance(error, OSError) else 125)
        if not (raw / 'outcome.json').exists() and not (raw / 'outcome.json').is_symlink():
            publish_json(raw / 'outcome.json', dict(accepted=False, exitCode=code,
                         state='canceled' if isinstance(error, (LaunchCanceled, KeyboardInterrupt))
                         else 'launch failed', terminationReason=str(error) + '; worker stopped.'))
        if isinstance(error, (RuntimeError, KeyboardInterrupt)):
            print('Verification launch refused: ' + str(error), file=sys.stderr)
            return code
        raise
    finally:
        for number, handler in old_handlers.items():
            signal.signal(number, handler)
    print(json.dumps(receipt, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
