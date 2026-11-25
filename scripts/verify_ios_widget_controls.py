#!/usr/bin/env python3
"""Execute source-extracted widget controls and schedule projection with Swift.

Uses the production timer, snapshot, locale, fallback, row, provider methods
and quick-action properties. Fixture entry/config wrappers replace SwiftUI
types only; this does not compile or render the WidgetKit target.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

import verify_ios_widget_timer_core as support


def member(source: str, marker: str) -> str:
    start = source.find(marker)
    if start < 0 or source.find(marker, start + len(marker)) >= 0:
        raise ValueError(f"Missing or ambiguous source member: {marker}")
    opened = source.find("{", start)
    depth = 0
    quoted = False
    escaped = False
    for end in range(opened, len(source)):
        char = source[end]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[start : end + 1]
    raise ValueError(f"Unterminated source member: {marker}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift-bin", default="swift")
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    swift = support._resolve_executable(args.swift_bin)
    if swift is None:
        parser.error("Swift executable is unavailable")
    root = Path(__file__).resolve().parents[1]
    production = root / "ios/DuoyiWidgets/DuoyiWidgets.swift"
    fixture = Path(__file__).with_name("ios_widget_controls_cases.swift")
    source = production.read_text()
    pieces = ["import Foundation\nimport CoreFoundation"]
    for core in ["TIMER", "SNAPSHOT", "DISPLAY"]:
        pieces.append(support._extract_marked_core(
            source, f"// BEGIN DUOYI_WIDGET_{core}_CORE",
            f"// END DUOYI_WIDGET_{core}_CORE"))
    # member() ends at the closure's brace; retain its production invocation.
    pieces.append(member(source, "private let duoyiPathSegmentAllowed:") + "()")
    pieces.append(member(source, "private struct DuoyiTodoRow:"))
    for marker in [
        "private enum DuoyiWidgetLocale:",
        "private struct DuoyiWidgetRow:",
        "private func localizedFallbackString(",
        "private func localizedNavigationLabel(",
        "private func localizedFocusTimerLabel(",
        "private func isAnniversaryFallback(",
        "private func isScheduleFallback(",
    ]:
        pieces.append(member(source, marker))
    # The wrapper retains production member signatures and field semantics.
    pieces.append("""
private struct DuoyiWidgetConfig {
    let kind: String
    let deepLink: String
    let primaryKey: String
    let fallback: String
    let rowKeys: [String]
    let quickActionTitle: String
    let quickActionLink: String
}
private struct FixtureProvider {
""")
    for name in ["readString", "readPrimary", "readRows", "readTodoCount"]:
        pieces.append(member(source, f"private func {name}(").replace(
            "private func", "func", 1))
    pieces.append("""
}
private struct FixtureEntry {
    let date: Date
    let config: DuoyiWidgetConfig
    let locale: DuoyiWidgetLocale
    let snapshot: DuoyiWidgetSnapshot
    let isDailyFresh: Bool
    let todoRows: [DuoyiTodoRow]
    let todoCount: Int?
    let primaryTarget: String
    let primary: String
    let rows: [DuoyiWidgetRow]
    let displayMode: String
    let habitQuickCheckId: String
    let focusTimer: DuoyiFocusTimerState
    let focusTimerLabel: String
""")
    pieces.append(member(source, "var focusActionIntent:"))
    for name in ["focusTimerRunning", "focusTimerRemainingSeconds"]:
        pieces.append(member(source, f"var {name}:"))
    pieces.append("""
}
private enum FixtureFamily {
    case systemSmall, systemMedium, systemLarge, systemExtraLarge
    case accessoryInline, accessoryCircular, accessoryRectangular
}
private struct FixtureView {
    let entry: FixtureEntry
    var family = FixtureFamily.systemMedium
""")
    for name in ["quickActionTitle", "quickURL", "supportsItemLinks", "focusStatusLabel",
                 "widgetRootURL", "visibleTodoRows", "visibleRows", "isAccessoryFamily",
                 "calendarAccessoryDates", "accessoryPrimaryText", "accessorySecondaryText",
                 "accessoryShortText"]:
        pieces.append(member(source, f"private var {name}:").replace(
            "private var", "var", 1))
    for name in ["cleanRow", "isKnownFallback", "formatMinutes"]:
        pieces.append(member(source, f"private func {name}("))
    pieces.append("}")
    cases = fixture.read_text()
    merged = "\n\n".join(pieces) + "\n\n" + cases
    output = support._private_run_directory(args.output_dir.resolve(),
                                            prefix="ios-widget-controls-")
    script = output / "controls.swift"
    script.write_text(merged)
    script.chmod(0o600)
    metadata = {
        "production_sha256": hashlib.sha256(production.read_bytes()).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
        "merged_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
        "case_count": len(re.findall(r"^controlsCase\(", cases, re.M)),
        "scope": "Extracted production control/provider behavior; fixture wrappers.",
        "limits": "No SwiftUI/WidgetKit target compilation or device rendering.",
    }
    (output / "inputs.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Swift: {swift}\nPrivate output: {output}", flush=True)
    print(json.dumps(metadata, indent=2), flush=True)
    result = subprocess.run([swift, str(script)], cwd=output, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end="")
    print("PASS" if result.returncode == 0 else "FAIL",
          "source-extracted iOS widget controls")
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
