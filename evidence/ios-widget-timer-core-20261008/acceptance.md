# iOS Widget Timer Core — 2026-10-08

## Changes

- Resolve running countdowns from absolute end anchors (ceil remaining seconds), and count-up timers from absolute start anchors (floor elapsed seconds).
- Preserve paused saved values; accept count-up total zero; keep count-up running at its 24-hour display cap.
- Reject malformed, Boolean-as-integer, fractional, nonfinite, negative and overflowing input. Keep accessory minute rounding safe.
- Expose fresh-session Start/Resume/Open intent. This batch exposes the contract; views still need to consume it.
- Capture one preferences map for current and future entries. Preserve its publication/account metadata and evaluate daily freshness per entry.
- Schedule local midnight, daylight-saving transitions and timer end/start/cap events within a 48-hour horizon, with a bounded reload request.

## Verification

- **19 Swift cases passed**, executing the actual source-extracted production core in Swift 6.1.3 on Linux arm64. The executed combined file exactly matches the final production core and fixture.
- **22 Flutter cases passed** in `ios_widget_resources_test.dart` and `home_widget_snapshot_test.dart`; includes negative provider/refresh mocks. Repeated runs are not additional cases.
- Source review found no confirmed timer-core blocker. Cross-midnight running/paused cases were added and executed.
- Final changed-file analyzer and source hashes are recorded in `verification.json`.

Reproduce on a host with Swift: `python3 scripts/verify_ios_widget_timer_core.py`. It extracts the marked production region, combines it with the fixture in a private temporary directory, and executes Swift.

## Scope and remaining acceptance

This is portable Foundation execution and Dart contract evidence. It does **not** establish Xcode/WidgetKit compilation, SwiftUI presentation, native reload timing, launcher behavior or device smoothness. No native device or macOS toolchain is available here.

WidgetKit home/accessory views still need phase-specific bilingual copy, live count-up/clamped countdown display, future-start/cap guards and intent-aware actions. Calendar presentation and full device acceptance remain open.

This Swift-only batch does not change web or Android artifacts. Web stays at **1.1.45+140011**; the public Android update policy stays at **1.1.43 / 140009**. The full user goal remains active.
