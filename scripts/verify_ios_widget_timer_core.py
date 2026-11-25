#!/usr/bin/env python3
"""Run source-extracted iOS widget timer core cases with the Swift toolchain."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


BEGIN_MARKER = "// BEGIN DUOYI_WIDGET_TIMER_CORE"
END_MARKER = "// END DUOYI_WIDGET_TIMER_CORE"
SWIFT_TIMEOUT_SECONDS = 180
BASE_FIXTURE_SHA256 = "75f74feb6680238f770f133e76fbd88dc3ad3ee790d83af8186b3a2eaf872a61"
EXTRA_FIXTURE_SHA256 = "0afbea032c00a6315cb462bcf2c45dc5b9112c1c1ee229524e49d49f528f8b5b"
BASE_CASE_NAMES = (
    "timer display uses running countdown and count-up anchors",
    "paused timers show saved seconds with complete hour formatting",
    "future count-up and capped count-up show fixed boundary values",
    "idle and unavailable use plan copy while ended countdown stays at zero",
    "clock rollback keeps the displayed countdown within the saved total",
    "count-up derives elapsed seconds from its start anchor",
    "countdown rounds remaining milliseconds up to seconds",
    "countdown is ended at the exact end anchor",
    "countdown seconds are clamped to the configured total",
    "paused timer anchors may both be zero",
    "countdown idle requires the complete saved duration",
    "unpublished session does not restore saved timer state",
    "focus action intent depends on a fresh timer phase",
    "future count-up start stays running and exposes its start and cap",
    "count-up remains running when its 24-hour cap is reached",
    "count-up reaches its cap from a nonzero millisecond start anchor",
    "missing, malformed, negative, and unrepresentable inputs are unavailable",
    "seconds and total stay safe for accessory plus-59 formatting",
    "timeline sorts and deduplicates midnight with an equal timer end",
    "timeline retains the exact seconds of midnight and timer-end refreshes",
    "running countdown updates across UTC midnight and ends at its anchor",
    "paused countdown keeps its saved seconds across UTC midnight",
    "timeline uses real 23-hour and 25-hour daylight-saving days",
    "timeline includes only deadlines at or before the 48-hour horizon",
)
EXTRA_CASE_NAMES = (
    "clock-sample62 paused countdown preserves 100-plus and million-hour literals",
    "clock-sample62 paused count-up caps oversized saved hours at the exact 24-hour literal",
    "clock-sample62 running countdown uses actual remaining hour digits instead of the configured total",
    "clock-sample62 fractional countdown remainder rounds across the 100-hour digit boundary",
    "clock-sample62 countdown rollback returns the bounded frozen literal and newly resolved clamp",
    "clock-sample62 retained countdown returns zero at expiry and resolved ended state stays zero",
    "clock-sample62 idle zero and unpublished states provide no clock sample",
    "clock-sample62 running count-up reserves the 24-hour sample before the cap",
    "clock-sample62 millisecond count-up cap switches to the fixed 24-hour literal",
    "clock-sample62 future count-up start samples zero until a new start-time resolution",
    "clock-sample62 malformed inputs and nonfinite entry timestamps yield no sample",
    "clock-sample62 valid extreme epoch and distant-future anchors preserve complete samples",
    "clock-sample62 maximum valid saved countdown measures every clamped 64-bit hour digit",
)
LEGACY_SUMMARY = "all production-extracted timer core cases"


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
    parser.add_argument(
        "--extra-fixture",
        type=Path,
        help="append the released clock-sample62 fixture (13 cases) after the existing 24 cases",
    )
    return parser


def _resolve_executable(value: str) -> str | None:
    # Swift selects its driver mode from argv[0]; keep the `swift` symlink
    # name instead of resolving it to the underlying `swift-driver` binary.
    candidate = shutil.which(value)
    if candidate:
        return str(Path(candidate).absolute())
    path = Path(value).expanduser()
    if path.is_file() and os.access(path, os.X_OK):
        return str(path.absolute())
    return None


def _extract_core(source: str) -> str:
    return _extract_marked_core(source, BEGIN_MARKER, END_MARKER)


def _extract_marked_core(
    source: str,
    begin_marker: str,
    end_marker: str,
    *,
    required_imports: tuple[str, ...] = ("import Foundation", "import CoreFoundation"),
) -> str:
    start = source.find(begin_marker)
    end = source.find(end_marker)
    if start < 0 or end < 0 or end <= start:
        raise ValueError(
            f"missing or misordered production markers: {begin_marker!r}, "
            f"{end_marker!r}"
        )
    if source.find(begin_marker, start + len(begin_marker)) >= 0:
        raise ValueError(f"multiple {begin_marker!r} markers")
    if source.find(end_marker, end + len(end_marker)) >= 0:
        raise ValueError(f"multiple {end_marker!r} markers")
    core = source[start + len(begin_marker) : end].strip()
    production_imports = source[:start]
    for required_import in required_imports:
        if required_import not in production_imports:
            raise ValueError(
                f"production file is missing {required_import!r} before the core marker"
            )
    return core


def _private_run_directory(base: Path, prefix: str = "ios-widget-timer-core-") -> Path:
    base.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix=prefix, dir=base))
    run_dir.chmod(stat.S_IRWXU)
    return run_dir


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _input_hashes(paths: list[Path]) -> dict[str, str]:
    return {str(path): _sha256(path) for path in paths}


def _case_names(source: str) -> tuple[str, ...]:
    names = tuple(re.findall(r'^runCase\("([^"\\]+)"\)\s*\{', source, re.MULTILINE))
    calls = re.findall(r"^[ \t]*runCase\s*\(", source, re.MULTILINE)
    if len(calls) != len(names) or len(set(names)) != len(names):
        raise ValueError("Unsupported or duplicate runCase identity in fixture")
    return names


def _private_json(path: Path, record: dict) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix="outcome-", suffix=".tmp", dir=path.parent)
    temporary_path = Path(temporary)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(json.dumps(record, indent=2) + "\n")
            output.flush()
            os.fsync(output.fileno())
        temporary_path.replace(path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


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
    extra_path = args.extra_fixture.expanduser().resolve() if args.extra_fixture else None
    if not production_path.is_file():
        print(f"FAIL: production Swift file not found: {production_path}", file=sys.stderr)
        return 2
    if not cases_path.is_file():
        print(f"FAIL: Swift case fixture not found: {cases_path}", file=sys.stderr)
        return 2

    try:
        bound = [Path(__file__).resolve(), production_path, cases_path, Path(swift)]
        if extra_path is not None:
            bound.append(extra_path)
        before = _input_hashes(bound)
        production = production_path.read_text(encoding="utf-8")
        core = _extract_core(production)
        cases = cases_path.read_text(encoding="utf-8")
        if _case_names(cases) != BASE_CASE_NAMES:
            raise ValueError("Existing timer fixture must retain all 24 distinct case identities in order")
        expected_names = BASE_CASE_NAMES
        extra = ""
        if extra_path is not None:
            if before[str(cases_path)] != BASE_FIXTURE_SHA256:
                raise ValueError("Existing timer fixture does not match the released 24-case hash")
            if before[str(extra_path)] != EXTRA_FIXTURE_SHA256:
                raise ValueError("Extra fixture does not match the released clock-sample62 hash")
            extra = extra_path.read_text(encoding="utf-8")
            if _case_names(extra) != EXTRA_CASE_NAMES:
                raise ValueError("Extra fixture must retain all 13 distinct clock-sample62 case identities in order")
            expected_names += EXTRA_CASE_NAMES
        if _input_hashes(bound) != before:
            raise ValueError("Bound inputs changed during source preparation")
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
            + cases
            + ("\n\n" + extra if extra_path is not None else ""),
            encoding="utf-8",
        )
        merged_path.chmod(stat.S_IRUSR | stat.S_IWUSR)
        merged_sha = _sha256(merged_path)
    except OSError as error:
        print(f"FAIL: could not create private output directory: {error}", file=sys.stderr)
        return 2

    bound.append(merged_path)
    before[str(merged_path)] = merged_sha
    command = [swift, str(merged_path)]
    log_path = run_dir / "swift.log"
    record = dict(
        accepted=False, state="prepared", exitCode=None, swiftExitCode=None,
        before=before, after={}, inputsUnchanged=False,
        extraFixture=str(extra_path) if extra_path is not None else None,
        extraFixtureSha256=before[str(extra_path)] if extra_path is not None else None,
        expectedCases=list(expected_names), expectedCaseCount=len(expected_names),
        observedCases=[], observedCaseCount=None, caseIdentitiesAccepted=False,
        legacySummaryUsedForAcceptance=False, legacySummaryCount=None,
        command=command, timeoutSeconds=SWIFT_TIMEOUT_SECONDS, log=str(log_path),
        guardRunId=os.environ.get("DUOYI_RESOURCE_GUARD_RUN_ID"),
        requiresParentGuardAcceptance=True, terminationReason=None,
        scope="Source-extracted Foundation timer/display and optional clock-sample strings",
        typographyWidthAcceptance=False, logsMergeStdoutAndStderr=True,
        swiftUiWidgetKitTargetCompiled=False, nativeDeviceAcceptance=False,
    )
    code = 2
    try:
        _private_json(run_dir / "inputs.json", record)
        _private_json(run_dir / "outcome.json", record)
        print(f"Swift: {swift}", flush=True)
        print(f"Private output: {run_dir}", flush=True)
        print(f"Executing source extracted from: {production_path}", flush=True)
        print(f"Expected distinct case identities: {len(expected_names)}", flush=True)
        if _input_hashes(bound) != before:
            raise ValueError("Bound inputs changed before Swift execution")
        record["state"] = "running"
        _private_json(run_dir / "outcome.json", record)
        with log_path.open("xb") as output:
            log_path.chmod(stat.S_IRUSR | stat.S_IWUSR)
            result = subprocess.run(
                command, cwd=run_dir, stdout=output, stderr=subprocess.STDOUT,
                check=False, timeout=SWIFT_TIMEOUT_SECONDS,
            )
        record["swiftExitCode"] = result.returncode
        log = log_path.read_text(encoding="utf-8", errors="replace")
        print(log, end="" if not log or log.endswith("\n") else "\n", flush=True)
        passes = re.findall(r"^PASS: (.+)$", log, re.MULTILINE)
        record["legacySummaryCount"] = passes.count(LEGACY_SUMMARY)
        observed = [name for name in passes if name != LEGACY_SUMMARY]
        record.update(observedCases=observed, observedCaseCount=len(observed),
                      caseIdentitiesAccepted=tuple(observed) == expected_names)
        if result.returncode != 0:
            code = result.returncode if result.returncode > 0 else 128 - result.returncode
            raise ValueError(f"Swift exited with status {result.returncode}")
        if not record["caseIdentitiesAccepted"]:
            raise ValueError("Swift PASS identities are missing, duplicated, unexpected, or out of order")
        code = 0
    except subprocess.TimeoutExpired:
        code = 124
        record["terminationReason"] = "Swift execution exceeded its 180-second limit"
    except KeyboardInterrupt:
        code = 130
        record["terminationReason"] = "Interrupted during Swift execution or collection"
    except (OSError, UnicodeError, ValueError) as error:
        record["terminationReason"] = str(error)
    finally:
        try:
            after = _input_hashes(bound)
            changed = sorted(path for path in before if before[path] != after.get(path))
            record.update(after=after, changedInputs=changed, inputsUnchanged=not changed)
            if changed:
                code = 2
                record["terminationReason"] = "Bound inputs changed after Swift execution"
        except OSError as error:
            code = 2
            record.update(inputsUnchanged=False, terminationReason=f"Final input hashing failed: {error}")
        except KeyboardInterrupt:
            code = 130
            record.update(inputsUnchanged=False, terminationReason="Interrupted during final input hashing")
        record.update(accepted=code == 0 and record["inputsUnchanged"] and record["caseIdentitiesAccepted"],
                      state="finished" if code == 0 else "rejected", exitCode=code)
        _private_json(run_dir / "outcome.json", record)
    if not record["accepted"]:
        print(f"FAIL: {record['terminationReason']}", file=sys.stderr, flush=True)
        return code
    print(f"PASS: production Swift timer core satisfied all {len(expected_names)} distinct fixture cases")
    print("Not covered: locale/font width bounds, SwiftUI/WidgetKit target compilation, or rendered device UI behavior.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
