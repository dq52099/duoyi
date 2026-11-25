#!/usr/bin/env python3
"""Check disk headroom or remove an explicit set of disposable project caches."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
GIB = 1024 ** 3
CURRENT_RUNTIME = Path('.dart_tool/native-busy-acceptance-20261024-v177')
LOCK = 'evidence/priority-content-20261024/flutter-serial.lock'
HISTORICAL = (
    'priority-next-acceptance-20261024', 'shared-controls-review-20261023',
    'settings-live-parallel-20261023', 'widget-live-parallel-20261023',
    'widget-runtime-recheck-20261023', 'widget-completion-theme-temp-20261023',
    'library-route-temp-20261023', 'widget-store-runtime-host-20261023',
    'duoyi-widget-runtime-20261023', 'widget-cross-process-host-20261023',
)


def space(root=ROOT):
    usage = shutil.disk_usage(root)
    return dict(total_bytes=usage.total, free_bytes=usage.free)


def check(root=ROOT, min_free_gib=12):
    free = space(root)['free_bytes'] / GIB
    print(f'Disk: {free:.2f} GiB free; required: {min_free_gib:g} GiB')
    if free < min_free_gib:
        raise RuntimeError('Insufficient disk space; review disk_budget.py cleanup before retrying.')


def safe_path(root, path):
    """Reject symlinks (including descendants), mount points and protected paths."""
    relative = path.relative_to(root)
    if relative == CURRENT_RUNTIME or CURRENT_RUNTIME in relative.parents:
        raise RuntimeError(f'Protected runtime: {path}')
    cursor = root
    device = root.stat().st_dev
    for part in relative.parts:
        cursor /= part
        if cursor.is_symlink():
            raise RuntimeError(f'Symlink refused: {cursor}')
        if cursor.exists() and cursor.stat().st_dev != device:
            raise RuntimeError(f'Different filesystem: {cursor}')
    if path.is_dir():
        for parent, dirs, files in os.walk(path, followlinks=False):
            for name in dirs + files:
                child = Path(parent) / name
                if child.is_symlink() or child.stat().st_dev != device:
                    raise RuntimeError(f'Unsafe cache entry: {child}')


def candidates(root=ROOT, include_failed_emulator=False):
    paths = [root / name for name in (
        'build/app/intermediates', 'build/test_cache', 'build/unit_test_assets',
        '.dart_tool/flutter_build', '.dart_tool/hooks_runner',
    )]
    for name in HISTORICAL:
        base = root / '.dart_tool' / name
        # Only the known disposable build/cache children, never the runtime itself.
        runtimes = [base] + (sorted(base.iterdir()) if base.is_dir() else [])
        for runtime in runtimes:
            for cache in ('build/test_cache', 'build/unit_test_assets',
                          '.dart_tool/hooks_runner', '.dart_tool/flutter_build'):
                paths.append(runtime / cache)
    old = root / '.dart_tool/shared-controls-review-20261023/recovery-baseline/.dart_tool/shared-controls-temp-20261023'
    paths.extend(old.glob('flutter_tools.*'))
    if include_failed_emulator:
        base = root / '.dart_tool/native-widget-runtime-20261023'
        paths.extend(base / name for name in (
            'android-data.img', 'android-x86_64-9.0-r2.iso',
            'android-x86_64-9.0-r2.parallel.iso', 'boot', 'image-parts',
        ))
    result = []
    for path in sorted(set(paths)):
        # Check broken symlinks too, rather than quietly ignoring them.
        if not path.exists() and not path.is_symlink():
            continue
        safe_path(root, path)
        result.append(path)
    return result


def assert_idle(root=ROOT):
    """Fail closed if a compiler/tester/emulator or project process is alive."""
    blockers = []
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            args = (proc / 'cmdline').read_bytes().split(b'\0')
            args = [arg.decode(errors='replace') for arg in args if arg]
            if not args:
                continue
            program = Path(args[0]).name
            compile_process = program in ('dart', 'dartaotruntime', 'flutter_tester', 'flutter', 'emulator')
            compile_process |= program.startswith('qemu-system-')
            compile_process |= any(arg.endswith(('flutter_tools.snapshot', 'frontend_server_aot.dart.snapshot')) for arg in args)
            compile_process |= program == 'java' and any(
                marker in arg for arg in args for marker in (
                    'GradleWrapperMain', 'GradleMain', 'GradleDaemon',
                    'GradleWorkerMain', 'KotlinCompileDaemon',
                ))
            # Other project verification runners must also be stopped first.
            project_runner = False
            if program.startswith('python'):
                for arg in args[1:]:
                    if arg.startswith('-') or not arg.endswith('.py'):
                        continue
                    script = Path(arg)
                    if not script.is_absolute():
                        script = (proc / 'cwd').resolve(strict=True) / script
                    script = script.resolve()
                    if (root.resolve() / 'evidence') in script.parents:
                        project_runner = True
                        break
            if compile_process or project_runner:
                blockers.append(f'{proc.name}:{program}')
        except FileNotFoundError:
            continue
        except PermissionError as error:
            raise RuntimeError(f'Cannot verify idle processes: {proc.name}') from error
    if blockers:
        raise RuntimeError('Active verification/emulator processes: ' + ', '.join(blockers))


def allocated(path):
    if path.is_file():
        return path.stat().st_blocks * 512
    return sum((Path(parent) / name).stat().st_blocks * 512
               for parent, _, files in os.walk(path) for name in files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    guard = sub.add_parser('check')
    guard.add_argument('--min-free-gib', type=float, default=12)
    cleanup = sub.add_parser('cleanup', help='Dry-run unless --apply is supplied')
    cleanup.add_argument('--apply', action='store_true')
    cleanup.add_argument('--include-failed-emulator', action='store_true')
    options = parser.parse_args()
    if options.action == 'check':
        if not 0 < options.min_free_gib < float('inf'):
            parser.error('--min-free-gib must be finite and positive')
        check(min_free_gib=options.min_free_gib)
        return
    lock_path = ROOT / LOCK
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Verification lock is busy; cleanup refused.')
        assert_idle()
        paths = candidates(include_failed_emulator=options.include_failed_emulator)
        report = dict(applied=options.apply, before=space(), candidates=[
            dict(path=str(path.relative_to(ROOT)), allocated_bytes=allocated(path))
            for path in paths])
        # Emit the complete manifest before removing anything.
        print(json.dumps(report), flush=True)
        if options.apply:
            for path in paths:
                safe_path(ROOT, path)
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
        print(json.dumps(dict(after=space(), applied=options.apply)), flush=True)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError) as error:
        print(f'Disk budget: {error}', file=sys.stderr)
        sys.exit(1)
