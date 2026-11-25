#!/usr/bin/env python3
"""Collect one AGY source job under the existing live resource/deadline guard.

Invoke with start_guarded_verification.py, which owns the serial lock and tracks
inherited-marker workers even after their launcher exits. This bridge acquires
no lock, changes no plugin configuration, and never restarts an execution.
The caller remains responsible for skill-required timeout recovery approval.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

from resource_guard import ROOT, RUN_KEY, identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--companion', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--prompt-file', type=Path, required=True)
    parser.add_argument('--model', required=True)
    parser.add_argument('--job', help='A stopped conversation explicitly authorized for continuation.')
    parser.add_argument('--budget-seconds', type=int, default=900)
    args = parser.parse_args()
    if not os.environ.get(RUN_KEY):
        parser.error('Run through start_guarded_verification.py; a live guard is required.')
    if not 60 <= args.budget_seconds <= 3600:
        parser.error('Budget must be between 60 and 3600 seconds.')
    output = args.output_dir.absolute()
    prompt = args.prompt_file.absolute()
    for path in (output, prompt, args.companion.absolute()):
        if any(part.is_symlink() for part in (path, *path.parents)):
            parser.error('Symlink paths are refused.')
    if not output.is_dir() or not output.is_relative_to(ROOT / 'evidence'):
        parser.error('Use the existing reserved guard output directory under evidence/.')
    if not prompt.is_file() or not args.companion.is_file():
        parser.error('Prompt and companion must be existing files.')
    mode = ['continue', '--job', args.job] if args.job else ['implement']
    command = ['node', str(args.companion), *mode, '--model', args.model,
               '--timeout', str(args.budget_seconds) + 's', '--prompt-file', str(prompt)]
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    (output / 'agy-launch.log').write_text(result.stdout)
    print(result.stdout, end='', flush=True)
    if result.returncode != 0:
        return result.returncode
    found = re.search(r'job id:\s*([a-zA-Z0-9-]+)\s*\(pid\s+(\d+)\)', result.stdout)
    if not found:
        raise RuntimeError('No job identity in launch response; guard will stop its owned descendants.')
    job, pid_text = found.groups()
    row = identity(int(pid_text))
    (output / 'agy-job.json').write_text(json.dumps({
        'job': job, 'workerIdentityAtLaunch': row, 'model': args.model,
        'budgetSeconds': args.budget_seconds, 'callerConversation': args.job,
        'sourceAccepted': False,
    }, indent=2) + '\n')
    if row is None:
        raise RuntimeError('Worker identity is unavailable; collect diagnostics before any new execution.')
    index = 0
    while True:
        # A soft wait expiry only collects the SAME execution again.
        waiting = subprocess.run(['node', str(args.companion), 'wait', job, '--timeout', '2m'],
                                 cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT)
        (output / f'agy-wait-{index}.log').write_text(waiting.stdout)
        print(waiting.stdout, end='', flush=True)
        index += 1
        if waiting.returncode != 2:
            return waiting.returncode


if __name__ == '__main__':
    raise SystemExit(main())
