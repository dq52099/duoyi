#!/usr/bin/env python3
"""Run source-extracted iOS widget timer core cases with the Swift toolchain."""

from __future__ import annotations

import argparse
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


BEGIN_MARKER = "// BEGIN DUOYI_WIDGET_TIMER_CORE"
END_MARKER = "// END DUOYI_WIDGET_TIMER_CORE"


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


def _resolve_executable(value: str) -> str | None:
    candidate = shutil.which(value)
    if candidate:
        return candidate
    path = Path(value).expanduser()
    if path.is_file() and os.access(path, os.X_OK):
        return str(path.resolve())
    return None


def _extract_core(source: str) -> str:
    start = source.find(BEGIN_MARKER)
    end = source.find(END_MARKER)
    if start < 0 or end < 0 or end <= start:
        raise ValueError(
            f"missing or misordered production markers: {BEGIN_MARKER!r}, "
            f"{END_MARKER!r}"
        )
    if source.find(BEGIN_MARKER, start + len(BEGIN_MARKER)) >= 0:
        raise ValueError(f"multiple {BEGIN_MARKER!r} markers")
    if source.find(END_MARKER, end + len(END_MARKER)) >= 0:
        raise ValueError(f"multiple {END_MARKER!r} markers")
    core = source[start + len(BEGIN_MARKER) : end].strip()
    production_imports = source[:start]
    for required_import in ("import Foundation", "import CoreFoundation"):
        if required_import not in production_imports:
            raise ValueError(
                f"production file is missing {required_import!r} before the core marker"
            )
    return core


def _private_run_directory(base: Path) -> Path:
    base.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix="ios-widget-timer-core-", dir=base))
    run_dir.chmod(stat.S_IRWXU)
    return run_dir


def main() -> int:
    args = _parser().parse_args()
    swift = _resolve_executable(args.swift_bin)
    if swift is None:
        print(
            f"FAIL: Swift executable not found or not executable: {args.swift_bin}",
            file=sys.stderr,
        )
        return 2

    root = Path(__file__).resolve().parents[1]
    production_path = root / "ios" / "DuoyiWidgets" / "DuoyiWidgets.swift"
    cases_path = Path(__file__).with_name("ios_widget_timer_core_cases.swift")
    if not production_path.is_file():
        print(f"FAIL: production Swift file not found: {production_path}", file=sys.stderr)
        return 2
    if not cases_path.is_file():
        print(f"FAIL: Swift case fixture not found: {cases_path}", file=sys.stderr)
        return 2

    try:
        production = production_path.read_text(encoding="utf-8")
        core = _extract_core(production)
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
        run_dir = _private_run_directory(output_base)
        merged_path = run_dir / "ios_widget_timer_core_cases.swift"
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

    print(f"Swift: {swift}")
    print(f"Private output: {run_dir}")
    print(f"Executing source extracted from: {production_path}")
    result = subprocess.run(
        [swift, str(merged_path)],
        cwd=run_dir,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.stdout:
        print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
    if result.returncode != 0:
        print(f"FAIL: swift exited with status {result.returncode}", file=sys.stderr)
        return result.returncode or 1
    print("PASS: production Swift timer core satisfied all fixture assertions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
