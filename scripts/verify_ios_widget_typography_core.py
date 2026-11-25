#!/usr/bin/env python3
"""Run the retained typography fixtures against the production DISPLAY core.

The caller owns resource admission and the verification lock. This checks
supplied geometry only, not UIKit metrics or Apple rendering.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

import verify_ios_widget_timer_core as helper


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swift-bin', default='swift')
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--fixture', type=Path, action='append', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = root / 'ios/DuoyiWidgets/DuoyiWidgets.swift'
    swift = helper._resolve_executable(args.swift_bin)
    if swift is None:
        parser.error('Swift executable is unavailable.')
    paths = [source, Path(__file__).absolute(), Path(helper.__file__).absolute(),
             Path(swift), *[path.absolute() for path in args.fixture]]
    output = args.output_dir.absolute()
    if (any(path.is_symlink() for path in (output, *output.parents)) or
            not output.resolve().is_relative_to(root / 'evidence')):
        parser.error('Use a nonsymlinked output directory under evidence/.')
    inputs = [{'path': str(path), 'sha256': digest(path)} for path in paths]
    fixtures = [path.read_text() for path in args.fixture]
    expected = [name for fixture in fixtures for name in re.findall(
        r'^dt(?:22|35)Case\("([^"\\]+)"\)', fixture, re.MULTILINE)]
    if not expected or len(set(expected)) != len(expected):
        parser.error('Fixtures require distinct explicit case identities.')
    core = helper._extract_marked_core(
        source.read_text(), '// BEGIN DUOYI_WIDGET_DISPLAY_CORE',
        '// END DUOYI_WIDGET_DISPLAY_CORE')
    if 'enum DuoyiWidgetTypographyLayoutCore' not in core:
        parser.error('Production typography planner is not implemented.')
    run_dir = helper._private_run_directory(output, 'ios-widget-typography-')
    merged = run_dir / 'typography_cases.swift'
    merged.write_text('import Foundation\nimport CoreFoundation\n\n' + core +
                      '\n\n' + '\n\n'.join(fixtures))
    merged.chmod(0o600)
    manifest = dict(inputs=inputs, coreSha256=hashlib.sha256(core.encode()).hexdigest(),
                    mergedScript=str(merged), mergedSha256=digest(merged),
                    command=[swift, str(merged)], accepted=False,
                    expectedCases=expected,
                    scope='Production-extracted numeric typography geometry only')
    (run_dir / 'inputs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Retained artifacts: ' + str(run_dir), flush=True)
    result = subprocess.run(manifest['command'], cwd=run_dir, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (run_dir / 'swift.log').write_text(result.stdout)
    print(result.stdout, end='', flush=True)
    stable = all(digest(Path(row['path'])) == row['sha256'] for row in inputs)
    messages = [line.removeprefix('PASS: ') for line in result.stdout.splitlines()
                if line.startswith('PASS: ')]
    passed = [name for name in messages if name in expected]
    cases_complete = passed == expected
    manifest.update(exitCode=result.returncode, inputsUnchanged=stable,
                    passedCases=passed, caseIdentitySequenceMatches=cases_complete,
                    summaryMessages=[name for name in messages if name not in expected],
                    accepted=result.returncode == 0 and stable and cases_complete)
    (run_dir / 'outcome.json').write_text(json.dumps(manifest, indent=2) + '\n')
    if not stable:
        print('FAIL: Verification inputs changed during execution.', file=sys.stderr)
    if not cases_complete:
        print('FAIL: Missing, duplicate or reordered case output.', file=sys.stderr)
    return result.returncode if result.returncode else (0 if manifest['accepted'] else 125)


if __name__ == '__main__':
    raise SystemExit(main())
