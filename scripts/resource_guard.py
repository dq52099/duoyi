#!/usr/bin/env python3
"""Run one serial verification command with live budgets and owned-process cleanup."""

import argparse
import datetime
import fcntl
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
LOCK = 'evidence/priority-content-20261024/flutter-serial.lock'
RUN_KEY = 'DUOYI_RESOURCE_GUARD_RUN_ID'
DAEMON_CLASS = b'org.gradle.launcher.daemon.bootstrap.GradleDaemon'


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def identity(pid):
    try:
        fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
        return dict(pid=pid, parent=int(fields[1]), group=int(fields[2]),
                    start=fields[19], state=fields[0])
    except (FileNotFoundError, ProcessLookupError):
        return None


def same_process(row):
    current = identity(row['pid'])
    return current is not None and current['start'] == row['start'] and current['state'] != 'Z'


def signal_owned_process(row, number):
    """Pin the observed process before signaling; never fall back to a PID."""
    if not same_process(row):
        return False
    descriptor = os.pidfd_open(row['pid'])
    try:
        # The PID may have been reused before pidfd_open. The second birth
        # check rejects that handle; reuse after this check cannot retarget it.
        if not same_process(row):
            return False
        signal.pidfd_send_signal(descriptor, number)
        return True
    finally:
        os.close(descriptor)


def memory_sample():
    values = {line.split(':', 1)[0]: int(line.split()[1])
              for line in Path('/proc/meminfo').read_text().splitlines()}
    return dict(availableMiB=values['MemAvailable'] / 1024,
                combinedUsedRatio=1 - (values['MemAvailable'] + values['SwapFree']) /
                (values['MemTotal'] + values['SwapTotal']))


def acquire_lock(root, inherited_fd=None):
    path = root / LOCK
    if any(candidate.is_symlink() for candidate in (path, *path.parents)):
        raise RuntimeError('Verification lock or its ancestry must not be a symlink.')
    path.parent.mkdir(parents=True, exist_ok=True)
    if inherited_fd is None:
        descriptor = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        handle = os.fdopen(descriptor, 'a')
    else:
        actual = os.fstat(inherited_fd)
        expected = path.stat()
        if (actual.st_dev, actual.st_ino) != (expected.st_dev, expected.st_ino):
            raise RuntimeError('Inherited descriptor is not the project verification lock.')
        handle = os.fdopen(os.dup(inherited_fd), 'a')
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BaseException:
        handle.close()
        raise
    return handle


class ResourceGuard:
    def __init__(self, root, report, minimum=12, build=False, interval=5,
                 timeout=3600, environment=None, disk_sample=None, mem_sample=None):
        self.root = Path(root).resolve()
        self.report = Path(report)
        self.minimum = minimum
        self.build = build
        self.interval = interval
        self.timeout = timeout
        self.env = dict(os.environ if environment is None else environment)
        self.nonce = uuid.uuid4().hex
        self.env[RUN_KEY] = self.nonce
        self.disk_sample = disk_sample or (lambda: shutil.disk_usage(self.root).free / 2**30)
        self.mem_sample = mem_sample or memory_sample
        self.owned = {}
        self.process = None
        self.home = None
        self.interrupted = None
        self.state = dict(at=now(), active=True, pid=os.getpid(), runMarker=self.nonce,
                          minimumFreeGiB=minimum, intervalSeconds=interval,
                          build=build, samples=0, signalsSent=[], trackedIdentities=[])

    def save(self):
        self.state['trackedIdentities'] = list(self.owned.values())
        temporary = self.report.with_suffix(self.report.suffix + '.tmp')
        temporary.write_text(json.dumps(self.state, indent=2) + '\n')
        temporary.replace(self.report)

    def sample(self, before=False):
        free, memory = self.disk_sample(), self.mem_sample()
        self.state.update(lastChecked=now(), freeGiB=free, memory=memory,
                          samples=self.state['samples'] + 1,
                          minimumObservedFreeGiB=min(free, self.state.get('minimumObservedFreeGiB', free)))
        if free < self.minimum:
            return 'disk budget below required floor'
        if memory['availableMiB'] < (2048 if before else 1024):
            return 'available memory below required reserve'
        if memory['combinedUsedRatio'] >= (.75 if before else .85):
            return 'combined memory budget exceeded'
        return None

    def daemons(self):
        if self.home is None:
            return []
        found = []
        for proc in Path('/proc').iterdir():
            if not proc.name.isdigit():
                continue
            try:
                row = identity(int(proc.name))
                if row is None or row['state'] == 'Z':
                    continue
                if proc.stat().st_uid != os.getuid():
                    continue
                args = (proc / 'cmdline').read_bytes().split(b'\0')
                if not args or Path(os.fsdecode(args[0])).name != 'java' or DAEMON_CLASS not in args:
                    continue
                environ = (proc / 'environ').read_bytes().split(b'\0')
                home_matches = ('GRADLE_USER_HOME=' + str(self.home)).encode() in environ
                log_matches = bool(list((self.home / 'daemon').glob('*/daemon-' + proc.name + '.out.log')))
                if not (home_matches or log_matches):
                    continue
                if same_process(row):
                    # The inherited unique nonce proves this invocation. The
                    # log can appear after daemon startup, so retain it as
                    # corroborating evidence rather than racing its creation.
                    row['daemonLogObserved'] = log_matches
                    row['ownedDaemon'] = (home_matches and
                        (RUN_KEY + '=' + self.nonce).encode() in environ)
                    found.append(row)
            except (FileNotFoundError, ProcessLookupError):
                continue
        return found

    def prepare(self):
        if not (hasattr(os, 'pidfd_open') and hasattr(signal, 'pidfd_send_signal')):
            raise RuntimeError('Identity-safe cleanup requires Linux pidfd support.')
        if (not math.isfinite(self.minimum) or self.minimum < (25 if self.build else 12) or
                not math.isfinite(self.interval) or not 0 < self.interval <= 20 or
                not math.isfinite(self.timeout) or self.timeout <= 0):
            raise RuntimeError('Invalid resource floor, sampling interval or timeout.')
        reason = self.sample(before=True)
        if reason:
            raise RuntimeError(reason)
        if self.build:
            configured = self.env.get('GRADLE_USER_HOME')
            if not configured or not Path(configured).is_absolute():
                raise RuntimeError('Builds require an explicit dedicated absolute GRADLE_USER_HOME.')
            home = Path(configured)
            if home.is_symlink() or home.resolve() == (Path.home() / '.gradle').resolve():
                raise RuntimeError('Shared or symlinked Gradle homes are refused.')
            # Create only after budgets and shared/symlink checks have passed.
            home.mkdir(parents=True, exist_ok=True)
            self.home = home.resolve(strict=True)
            if not self.home.is_dir():
                raise RuntimeError('Dedicated Gradle home must be an existing directory.')
            self.env['GRADLE_USER_HOME'] = str(self.home)
            if self.daemons():
                raise RuntimeError('Pre-existing dedicated Gradle daemon: refuse reuse or signaling.')
            self.state['dedicatedGradleHome'] = str(self.home)
        if self.report.exists() or self.report.is_symlink():
            raise RuntimeError('Preserve existing guard report; choose a new path.')
        self.report.parent.mkdir(parents=True, exist_ok=True)

    def track(self):
        rows = {}
        for proc in Path('/proc').iterdir():
            if proc.name.isdigit():
                row = identity(int(proc.name))
                if row and row['state'] != 'Z':
                    rows[row['pid']] = row
        if self.process is not None:
            # Detached AGY workers can become PID 1 children in a new session
            # before the launcher is scanned. Require our exact nonce and UID,
            # then recheck birth identity; the numeric PGID grants no authority.
            for row in rows.values():
                known = self.owned.get(row['pid'])
                if known and known['start'] == row['start']:
                    continue
                try:
                    proc = Path(f"/proc/{row['pid']}")
                    if proc.stat().st_uid != os.geteuid():
                        continue
                    environ = (proc / 'environ').read_bytes().split(b'\0')
                    if ((RUN_KEY + '=' + self.nonce).encode() in environ and
                            same_process(row)):
                        self.owned[row['pid']] = row
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    # The lineage pass can still prove an identity-matched
                    # parent's children when their environment is unreadable.
                    continue
        for row in self.daemons():
            if not row.pop('ownedDaemon'):
                raise RuntimeError('Unowned daemon appeared in the dedicated Gradle home.')
            self.owned[row['pid']] = row
        changed = True
        while changed:
            changed = False
            for row in rows.values():
                parent = self.owned.get(row['parent'])
                current_parent = rows.get(row['parent'])
                if (row['pid'] not in self.owned and parent and current_parent and
                        parent['start'] == current_parent['start']):
                    child = identity(row['pid'])
                    if (child and child['start'] == row['start'] and
                            child['parent'] == parent['pid'] and
                            same_process(parent) and same_process(child)):
                        self.owned[row['pid']] = child
                        changed = True

    def stop_owned(self):
        for sig, seconds in ((signal.SIGTERM, 5), (signal.SIGKILL, 3)):
            deadline = time.monotonic() + seconds
            sent = set()
            while True:
                try:
                    self.track()
                except (RuntimeError, OSError) as error:
                    self.state['cleanupInspectionError'] = str(error)
                live = [row for row in self.owned.values() if same_process(row)]
                if not live:
                    return True
                for row in reversed(live):
                    key = (row['pid'], row['start'])
                    if key in sent or not same_process(row):
                        continue
                    try:
                        if signal_owned_process(row, sig):
                            sent.add(key)
                            self.state['signalsSent'].append(dict(pid=row['pid'], start=row['start'], signal=int(sig)))
                    except ProcessLookupError:
                        pass
                if self.process is not None:
                    self.process.poll()
                try:
                    self.save()
                except OSError as error:
                    # Reporting must never prevent escalation for owned writers.
                    self.state['cleanupReportError'] = str(error)
                if time.monotonic() >= deadline:
                    break
                time.sleep(.1)
        return not any(same_process(row) for row in self.owned.values())

    def run(self, command):
        old_handlers = {}
        for sig in (signal.SIGTERM, signal.SIGINT):
            old_handlers[sig] = signal.signal(sig, lambda number, frame: setattr(self, 'interrupted', number))
        try:
            self.prepare()
        except BaseException:
            for sig, handler in old_handlers.items():
                signal.signal(sig, handler)
            raise
        code, reason = 125, None
        started = time.monotonic()
        try:
            self.save()
            if self.interrupted is not None:
                raise RuntimeError('Verification canceled before command launch.')
            self.process = subprocess.Popen(command, cwd=self.root, env=self.env, start_new_session=True)
            row = identity(self.process.pid)
            if row:
                self.owned[row['pid']] = row
            self.state.update(commandExecutable=Path(command[0]).name, argumentCount=len(command) - 1,
                              childPid=self.process.pid, childStart=row['start'] if row else None)
            while True:
                self.track()
                reason = self.sample()
                if self.interrupted is not None:
                    reason = 'interrupted by signal ' + str(self.interrupted)
                elif time.monotonic() - started >= self.timeout:
                    reason = 'command timed out'
                self.save()
                if reason:
                    code = 128 + self.interrupted if self.interrupted else 124 if reason == 'command timed out' else 125
                    break
                try:
                    remaining = self.timeout - (time.monotonic() - started)
                    if remaining <= 0:
                        reason, code = 'command timed out', 124
                        break
                    code = self.process.wait(timeout=min(self.interval, remaining))
                    if self.interrupted is not None:
                        reason = 'interrupted by signal ' + str(self.interrupted)
                        code = 128 + self.interrupted
                    elif time.monotonic() - started >= self.timeout:
                        reason, code = 'command timed out', 124
                    break
                except subprocess.TimeoutExpired:
                    pass
        except (RuntimeError, OSError) as error:
            reason = str(error)
        finally:
            self.state['terminationReason'] = reason
            try:
                cleaned = self.stop_owned()
                if self.process is not None:
                    self.process.wait(timeout=2)
                if (not cleaned or self.state.get('cleanupInspectionError') or
                        self.state.get('cleanupReportError')):
                    code = 125
                    self.state['terminationReason'] = (
                        self.state.get('cleanupReportError') or reason or
                        'Owned cleanup could not be verified.')
            except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
                code = 125
                self.state['terminationReason'] = 'Cleanup failed: ' + str(error)
            finally:
                if self.interrupted is not None:
                    code = 128 + self.interrupted
                    self.state['terminationReason'] = 'interrupted by signal ' + str(self.interrupted)
                if code < 0:
                    code = 128 - code
                self.state.update(active=False, finishedAt=now(), exitCode=code,
                                  durationSeconds=time.monotonic() - started,
                                  accepted=code == 0 and self.state['terminationReason'] is None)
                try:
                    self.save()
                except OSError as error:
                    code = 128 + self.interrupted if self.interrupted else 125
                    self.state.update(accepted=False, exitCode=code,
                                      cleanupReportError=str(error))
                    print('Resource guard report failed: ' + str(error), file=sys.stderr)
                finally:
                    for sig, handler in old_handlers.items():
                        signal.signal(sig, handler)
        return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--lock-fd', type=int)
    parser.add_argument('--min-free-gib', type=float)
    parser.add_argument('--interval', type=float, default=5)
    parser.add_argument('--timeout', type=float, default=3600)
    parser.add_argument('--report', type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    options = parser.parse_args()
    command = options.command
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        parser.error('A command is required after --.')
    report = options.report or ROOT / 'evidence/resource-guard' / (uuid.uuid4().hex + '.json')
    try:
        with acquire_lock(ROOT, options.lock_fd):
            guard = ResourceGuard(ROOT, report, minimum=options.min_free_gib if options.min_free_gib is not None else 25 if options.build else 12,
                                  build=options.build, interval=options.interval, timeout=options.timeout)
            return guard.run(command)
    except (RuntimeError, OSError) as error:
        print('Resource guard: ' + str(error), file=sys.stderr)
        return 125


if __name__ == '__main__':
    sys.exit(main())
