# Widget schedule projection acceptance — 2026-10-11

## Actual behavior repaired

The shared Flutter payload for Schedule rows and the Calendar today summary previously sorted events by `event.date` and raw title. A timed Todo can have a date-only anchor and a separate `event.time`. Four real aggregated Todos titled A/B/C/Z at 15:00/16:00/17:00/09:00 therefore selected A/B/C and omitted the earlier Z item.

`homeWidgetScheduleEvents` now sorts by the effective start used by Calendar aggregation: combine the event date with its explicit time, or retain the date clock when time is absent. Equal starts use raw title, then event ID, for deterministic order. The existing completed-Todo and missing-source-ID filters remain. The projection copies the list and retains the original event objects.

`homeWidgetScheduleEventLabel` reads `CalendarEventDisplayText` metadata so generated Focus/Diary titles follow the app locale. Identically worded authored or legacy titles remain literal. `_homeWidgetEventsForToday` and the existing label wrapper delegate to these helpers; selected events continue to drive both labels and the unchanged deep-link builder.

## Final serial verification

Completed **09:57:07 UTC**; runner exit 0. All eight suites passed, **112 tests** total:

| Suite | Passed |
| --- | ---: |
| Widget schedule projection | 6 |
| Calendar aggregation/conflicts | 8 |
| Calendar display metadata | 16 |
| Home-widget snapshots | 16 |
| Widget publication | 14 |
| Android widget resources/wiring | 39 |
| iOS widget resources/wiring | 12 |
| Startup staggering contract | 1 |

The six new cases cover real aggregated timed-Todo top-three ordering, mixed date/time/all-day values, filtering, retained input values/objects, deterministic ties, retained zh→en→zh metadata labels with literal lookalikes, and the actual main-wrapper consumption chain. The main-wrapper check is static; it is not a mounted launcher/action test.

Each suite ran with `flutter test --no-pub --concurrency=1 --reporter=expanded <suite>`. A scoped `flutter analyze --no-pub` over main, the helper, and all eight suites completed with **no issues**, exit 0. **14 source/test/dependency hashes** matched before and after verification.

## Evidence and limits

[Final summary](widget-schedule-projection-final-acceptance-20261011/summary.json), individual test logs, analyzer log, and before/after hashes are retained in the adjacent directory. The initial [run](widget-schedule-projection-acceptance-20261011/summary.json) also passed 112 tests, but analysis found the now-unused `CalendarEventTypeX` shown import. That import was removed and the entire batch rerun; original evidence remains.

The current [Android platform compile](android-widget-platform-compile-acceptance-20261011.md) separately proves native provider/adapter compilation. This batch does not certify all app routes, live native rendering, frame performance, or device actions. Existing historical suites overlap these regressions; counts must not be summed as unique project coverage. No version bump, signed APK, push, or deployment was performed for this acceptance. Widget preview accuracy, unpublished-state wording, global UI localization, and real Android/iOS acceptance remain open.
