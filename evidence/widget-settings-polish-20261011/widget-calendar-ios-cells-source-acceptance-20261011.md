# iOS calendar date cells — scoped source acceptance

Date: 2026-10-11. This accepts the reviewed source change and portable regressions; full native delivery remains open.

## Integrated change

Calendar now builds each real visible day through `calendarDayCell`. Fresh dates use their existing `cell.target`, passed through the snapshot's binding-aware `actionURL`, in a plain-styled `Link`. Missing or stale targets retain the date label. Blank cells have no own date link and are hidden from accessibility; the enclosing calendar section navigation remains available.

The date label fills its column and row hit area. Today's circular primary-color marker, contrast text, selection trait, row budget, custom background, border and section URL remain. The SwiftUI frame uses two valid calls rather than the nonexistent combined overload. No small-family restriction was introduced: the retained official Apple linking reference explicitly lists `systemSmall` among families supporting multiple Links. Accessory families retain their separate summary UI.

## Root verification

All seven serial checks completed successfully:

- 15 resource/source-contract tests, zero failures or skips.
- Scoped analysis of the resource fixture: no issues.
- Swift frontend syntax parsing of the actual complete widget source.
- Four Python verifier/tool-selection tests.
- 29 snapshot/binding, 19 timer and 30 display cases compiled and executed with portable Swift 6.2.3.

All 13 recorded input hashes matched before and after execution and were rechecked before this report. Swift SHA-256: `e4d8cbe7e61164fb0941a26015d2dc1f99e4bd84a6d2ae13c43cec599af6a7d7`.

Authoritative logs and exact hashes: `widget-calendar-ios-cells-20261011/summary.json` and the seven adjacent logs. Source/family review: `.dart_tool/task-temp-20261011/ios-calendar-link-family-policy-review-20261011.md`.

## Remaining native acceptance

Syntax parsing and portable Foundation cases do not type-check SwiftUI or WidgetKit. Xcode extension builds and device checks remain required for exact date delivery, small/medium/large/extra-large hit areas, locale, large text, VoiceOver, account/stale fallback and custom backgrounds. No Apple SDK or connected device is available here. This scoped acceptance does not prove the full widget, internationalization or settings goal complete.
