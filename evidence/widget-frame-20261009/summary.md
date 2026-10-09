# Android widget immutable rendering frames — 2026-10-09

## Implemented

All eleven actual widget renderers build from one per-instance immutable raw/display map, captured dimensions/density, locale, wall/elapsed clock and zone. Scalar types remain intact; StringSets and exposed map/set views cannot mutate the snapshot. Generic editing is rejected. Stale content masks business IDs/counters while preserving theme IDs; untrusted sessions hide every timer read and use safe placeholders.

The shared main-looper helper initializes existing styles before capture, compares complete raw values (including same-tuple payload changes), options, zone/day/offset, system locale, clock progression and countdown expiry immediately before its only UI commit. A rejected frame gets at most one full recapture/build; two rejections or a failed build/Binder call commit no old frame or effect.

Todo/Habit/Focus/legacy mutation URIs use captured day/offset/account metadata and require a fresh trusted session. Focus date, countdown/count-up display and chronometer bases use one captured clock and exact millisecond deltas. Its existing 14101 timer alarm updates only after an accepted UI commit, and invalidated sessions preserve the existing alarm. Calendar month-title formatters use the same frozen zone as the grid; the final audit's reproduced default-zone mismatch is fixed.

## Executed verification

- 29 production-source JVM fixtures passed: 19 frame/attempt cases plus ten adapter/projection/month-zone cases. Earlier fixture generic-type compile failure is retained.
- Android Gradle unit tests passed: 69 cases in five suites, including the prior display/day-boundary/native reminder coverage.
- 931 integrated Flutter regressions across 75 files passed, including route and picker state retention and renderer wiring checks. Targeted Dart analysis passed.
- Android arm64 debug APK compiled; SHA-256 `d2c5c022bfdab6278d2776368b0263f0f0e35d69c8745309a632dcda21706376`. It remains private for later integrated delivery.
- Exact commands, frozen source/fixture hashes, logs, native XML reports and [source-audit.md](source-audit.md) are retained.
- Three legacy static assertions initially failed after helper extraction: two whitespace-dependent localized text checks and the old direct style-init/action branches. They now assert whitespace-independent view/copy wiring, the stronger fresh-session guard and style initialization before shared frame capture. The initial failure log is retained and current-source checks were rerun.

## Evidence boundary and remaining acceptance

This ensures one accepted RemoteViews uses one frozen native map and rejects changes already visible at the native commit check. It does not make queued Dart reset requests, sequential publication writes, launcher repaint and alarm scheduling one transaction, nor revoke UI already submitted before a later clear. Device pin/resize/action/alarm behavior and real smoothness require Android evidence; iOS WidgetKit compilation/layout requires its own platform evidence.

Shared editor copy, Mine/Profile feedback and comprehensive iOS visuals remain open. This local integration publishes no artifact and does not close the full goal.
