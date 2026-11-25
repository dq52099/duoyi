#!/usr/bin/env python3
"""Run the four retained production-extracted suites under the caller's guard.

This checks portable logic and selected source members, not Apple rendering.
The caller must stop source writers and hold the shared verification lock.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

import verify_ios_widget_timer_core as helper


SUITES = (
    ('display', 'display_core', 'displayRunCase'),
    ('controls', 'controls', 'controlsCase'),
    ('timer', 'timer_core', 'runCase'),
    ('snapshot', 'snapshot_core', 'snapshotRunCase'),
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swift-bin', required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    if not os.environ.get('DUOYI_RESOURCE_GUARD_RUN_ID'):
        parser.error('Run under the project resource guard and inherited lock.')
    root = Path(__file__).resolve().parents[1]
    output = args.output_dir.absolute()
    if (any(p.is_symlink() for p in (output, *output.parents)) or
            not output.resolve().is_relative_to(root / 'evidence')):
        parser.error('Use a new nonsymlinked directory under evidence/.')
    swift = helper._resolve_executable(args.swift_bin)
    if swift is None:
        parser.error('Cached Swift executable is unavailable.')
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    paths = [root / 'ios/DuoyiWidgets/DuoyiWidgets.swift',
             root / 'ios/Runner/AppDelegate.swift', Path(__file__).absolute(),
             Path(swift), root / 'scripts/resource_guard.py',
             root / 'scripts/start_guarded_verification.py',
             root / 'scripts/disk_budget.py',
             root / 'scripts/with_disk_budget.sh']
    for _, suffix, _ in SUITES:
        paths.extend([root / f'scripts/verify_ios_widget_{suffix}.py',
                      root / f'scripts/ios_widget_{suffix}_cases.swift'])
    paths = list(dict.fromkeys(paths))
    record = dict(accepted=False, scope='Production-extracted portable iOS logic '
                  'and selected provider/control members; no Apple SDK/rendering',
                  inputs={}, inputChecks=[], suites=[], caseCount=0)

    def publish():
        (output / 'outcome.json').write_text(json.dumps(record, indent=2) + '\n')

    def hashes():
        return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}

    def check(stage):
        current = hashes()
        changed = [p for p in record['inputs'] if current[p] != record['inputs'][p]]
        record['inputChecks'].append(dict(stage=stage, changedInputs=changed))
        publish()
        if changed:
            raise RuntimeError('Verification inputs changed: ' + ', '.join(changed))

    code = 125
    try:
        record['inputs'] = hashes()
        publish()
        for name, suffix, case_function in SUITES:
            fixture = root / f'scripts/ios_widget_{suffix}_cases.swift'
            expected = re.findall(r'^' + case_function + r'\("([^"\\\n]+)"\)',
                                  fixture.read_text(), re.MULTILINE)
            if not expected or len(expected) != len(set(expected)):
                raise RuntimeError('Fixture needs distinct explicit case names: ' + name)
            command = [sys.executable, '-u', str(root / f'scripts/verify_ios_widget_{suffix}.py'),
                       '--swift-bin', swift, '--output-dir', str(output / name)]
            row = dict(name=name, command=command, expectedCases=expected,
                       passedCases=[], accepted=False)
            record['suites'].append(row)
            check('before ' + name)
            log_path = output / f'{name}.log'
            print('Running ' + name + '; retained log: ' + str(log_path), flush=True)
            # Open before launch: interruption cannot discard diagnostics held
            # only in the parent's memory. The guard owns descendant cleanup.
            with log_path.open('xb') as log:
                result = subprocess.run(command, cwd=root, stdout=log,
                                        stderr=subprocess.STDOUT)
            diagnostic = log_path.read_text()
            print(diagnostic, end='', flush=True)
            messages = [line.removeprefix('PASS: ') for line in diagnostic.splitlines()
                        if line.startswith('PASS: ')]
            passed = [message for message in messages if message in expected]
            row.update(exitCode=result.returncode, passedCases=passed,
                       summaryMessages=[m for m in messages if m not in expected])
            check('after ' + name)
            row['accepted'] = result.returncode == 0 and passed == expected
            publish()
            if not row['accepted']:
                code = result.returncode or 125
                raise RuntimeError('Suite failed or case identities differ: ' + name)
        check('final')
        record.update(accepted=True,
                      caseCount=sum(len(row['passedCases']) for row in record['suites']))
        code = 0
    except Exception as error:
        record['error'] = str(error)
        print('FAIL: ' + str(error), file=sys.stderr)
    finally:
        record['exitCode'] = code
        publish()
    return code


if __name__ == '__main__':
    raise SystemExit(main())
