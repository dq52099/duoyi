#!/usr/bin/env python3
"""Run source-extracted iOS widget display core cases with Swift."""

from __future__ import annotations

import argparse
import hashlib
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

import verify_ios_widget_timer_core as timer_runner


BEGIN_MARKER = "// BEGIN DUOYI_WIDGET_DISPLAY_CORE"
END_MARKER = "// END DUOYI_WIDGET_DISPLAY_CORE"


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--swift-bin",
        default="swift",
        help="Swift interpreter executable (default: swift)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="base directory for retained private run artifacts (default: system temp)",
    )
    return parser


def main() -> int:
    args = _parser().parse_args()
    swift = timer_runner._resolve_executable(args.swift_bin)
    if swift is None:
        print(
            f"FAIL: Swift executable not found or not executable: {args.swift_bin}",
            file=sys.stderr,
        )
        return 2

    root = Path(__file__).resolve().parents[1]
    production_path = root / "ios" / "DuoyiWidgets" / "DuoyiWidgets.swift"
    cases_path = Path(__file__).with_name("ios_widget_display_core_cases.swift")
    if not production_path.is_file():
        print(f"FAIL: production Swift file not found: {production_path}", file=sys.stderr)
        return 2
    if not cases_path.is_file():
        print(f"FAIL: Swift case fixture not found: {cases_path}", file=sys.stderr)
        return 2

    try:
        production = production_path.read_text(encoding="utf-8")
        core = timer_runner._extract_marked_core(
            production,
            BEGIN_MARKER,
            END_MARKER,
        )
        cases = cases_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError, ValueError) as error:
        print(f"FAIL: could not prepare production Swift cases: {error}", file=sys.stderr)
        return 2

    output_base = (
        args.output_dir.expanduser().resolve()
        if args.output_dir
        else Path(tempfile.gettempdir())
    )
    try:
        run_dir = timer_runner._private_run_directory(
            output_base,
            prefix="ios-widget-display-core-",
        )
        merged_path = run_dir / "ios_widget_display_core_cases.swift"
        merged_path.write_text(
            "import Foundation\nimport CoreFoundation\n\n"
            + core
            + "\n\n"
            + cases,
            encoding="utf-8",
        )
        merged_path.chmod(stat.S_IRUSR | stat.S_IWUSR)
    except OSError as error:
        print(f"FAIL: could not create private output directory: {error}", file=sys.stderr)
        return 2

    case_count = len(re.findall(r"^displayRunCase\(", cases, flags=re.MULTILINE))
    core_sha = hashlib.sha256(core.encode("utf-8")).hexdigest()
    fixture_sha = hashlib.sha256(cases.encode("utf-8")).hexdigest()
    merged_sha = hashlib.sha256(merged_path.read_bytes()).hexdigest()

    print(f"Swift: {swift}")
    print(f"Private output: {run_dir}")
    print(f"Production source: {production_path}")
    print(f"Fixture source: {cases_path}")
    print(f"Merged script: {merged_path}")
    print(f"Case count: {case_count}")
    print(f"Production core SHA-256: {core_sha}")
    print(f"Fixture SHA-256: {fixture_sha}")
    print(f"Merged script SHA-256: {merged_sha}")

    try:
        result = subprocess.run(
            [swift, str(merged_path)],
            cwd=run_dir,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
    except OSError as error:
        print(f"FAIL: could not execute Swift: {error}", file=sys.stderr)
        return 2

    if result.stdout:
        print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
    if result.returncode != 0:
        print(f"FAIL: swift exited with status {result.returncode}", file=sys.stderr)
        return result.returncode or 1

    print("PASS: production Swift display core satisfied all fixture assertions")
    print(
        "Not covered: widget entry/provider and timeline integration, SwiftUI/WidgetKit target "
        "compilation, or rendered device UI behavior."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
