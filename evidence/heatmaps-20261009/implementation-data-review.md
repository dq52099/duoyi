# Heatmap implementation — bounded data source review, 2026-10-09

## Scope and verdict

Reviewed the frozen root-owned implementation in `/home/ubuntu/duoyi-worktrees/heatmaps-20261009`, root-provided HEAD `98d46d8`. Read the scoped actual diff against the prior audited `1f00a46`, the new `heatmap_calendar.dart` and `activity_heatmap_card.dart`, the habit model/provider/callers, statistics activity production, and the shared renderer's date eligibility plus metric-copy dependency. HEAD was not independently checked. The independently authored tests were not read. No production/fixture edits, SDK/checks/builds/tests or commits occurred; only this private report was written.

**One narrow source revision remains: use the shared canonical date-key formatter for single-habit and activity output keys.** The window/summary correction, direct flex DST correction, actual-instant timezone attribution and preserved metrics otherwise pass this bounded source review. Current dates with four-digit years do not exhibit the remaining mismatch, but the helper/parser expressly accepts years 1..9999.

## Required repair: two producers emit keys the shared renderer cannot read

`HeatmapCalendarWindow.dateKey` pads the year to four digits (`lib/core/heatmap_calendar.dart:24–27`), and `tryParseDateKey` accepts exact four-digit dates with years 1..9999 (`39–46`). The shared renderer and summary look up values with that formatter (`lib/widgets/habit_heatmap.dart:44–45`; `HeatmapCalendarWindow.summarize:65–68`).

Two output paths still use the prior unpadded year:

- `Habit.heatmapData` writes `final key = dateKey(date)` and also uses that key for the persisted completion lookup (`lib/models/habit.dart:638–639`); the existing `Habit.dateKey` at `493` does not pad the year.
- Statistics `_dateKey` at `lib/screens/statistics_screen.dart:670–671` also does not pad the year; this private method is used only by activity accumulation (`642`).

Source-derived example, not an executed fixture: a reference date in year 999 produces `999-01-02` in these maps while the chart/summary asks for `0999-01-02`. A canonical habit activity input key `0999-01-02` can pass the new parser, then be accumulated under the unpadded output key and disappear from the chart/summary. Combined habit output already uses the correct shared formatter (`habit_provider.dart` diff).

**Minimum repair:** use `HeatmapCalendarWindow.dateKey(date)` for heatmap presentation output keys in both sites. In the single-habit producer, keep legacy completion lookup through `countForDate(date)` or the existing unpadded completion key; do not globally change `Habit.dateKey` or rewrite persisted completion maps just to align output. The statistics private output formatter can delegate directly to the shared formatter. This repair is confined to the two reviewed production files.

## Source acceptance findings

### Shared window and summary align

- The factory rejects weeks <1, captures/normalizes one supplied or current today, and computes the oldest Monday as the current Monday minus N−1 weeks (`heatmap_calendar.dart:8–22`).
- `dayDistance` compares UTC representations of the civil year/month/day labels, avoiding local offset changes in day counts (`29–32`). `visibleDays` is start..today inclusive, and `contains` uses the same indices (`49–59`). This gives `7 × (N−1) + today.weekday` eligible dates.
- `CalendarHeatmap` generates N×7 Monday–Sunday positions with `window.dayAt(column*7+row)` (`198–201`). `_cell` rejects ineligible future slots before invoking describeDay/colorForDay (`273–278`); selection also rejects out-of-window dates (`58–60`). Today/selection comparisons use date keys rather than instant equality (`275–276`).
- `HeatmapCalendarWindow.summarize` iterates only visibleDays, counts positive normalized levels and calculates the maximum (`62–70`). Off-grid older/future keys cannot affect the summary.
- `ActivityHeatmapCard` creates one window for the summary and passes its exact normalized today to HabitHeatmap (`22–23`, `43`). The child's reconstructed window therefore has the same 52-week range. The statistics producer is an all-record date map with no independent today filtering, so it does not need a second window/capture to determine eligibility.
- Habit overview and detail each capture one heatmapToday, pass it to their producer and chart, and retain 12/20 weeks. The production call-site diff explicitly establishes that pairing. Other detail metrics' separate DateTime.now calls are outside this chart's summary contract.

### Calendar arithmetic and strict key parsing pass

`shiftDay` uses a local date constructor with day overflow (`21–22`), not elapsed Duration arithmetic. Both habit producers iterate the shared visibleDays. The weekly `Habit.periodBoundsForDate` start/end now use shiftDay, and direct `completionCountInRange` normalizes its start, advances by civil day and compares dayDistance. This corrects the direct flex heatmap path without changing target/count definitions.

The strict parser checks exact ASCII yyyy-MM-dd form, year 1..9999 and constructor round-trip equality. Month/day overflow, year0000, noncanonical strings and impossible Gregorian dates are rejected rather than normalized into ghost activity. Parsing is presentation-only; no completion map is rewritten. Standard leap-day validity is source-consistent, but timezone/DST cases were not executed.

Previous-period, completionDatesInRange, report and streak traversal remain unchanged. They are inherited boundaries outside the direct heatmap path, as root specified; this review does not claim a repository-wide calendar migration.

### Habit progress and domain semantics pass

- Both progress producers use the same `progressLevel` (`heatmap_calendar.dart:36–37`), preserving ceil bands: 0; (0,.2]; (.2,.4]; (.4,.6]; (.6,.8]; (.8,1]. No new exact-percentage or level5-means-completed claim appears in the reviewed copy.
- Combined habits retain the activeForDate filter, empty-active-set level0, and arithmetic mean of active progressForDate values. An inactive habit does not enter the denominator.
- Single positive habit retains count/safeTarget and clipping, inactive days retain0, and negative zero-record success retains5 versus positive setback count0. Flex retains the existing whole-period ratio; it is not converted to a daily count or as-of-cell history.
- The actual model/provider diff changes only the helper import, heatmap producer iteration/optional today, and the direct civil-day helpers. Stored completion maps, IDs, constructors, serializers, habit scheduling/targets and flex count meaning are unchanged.
- HabitHeatmap has an explicit progress/activity metric mode, uses normalized 0–5 levels, and describes levels rather than event counts (`habit_heatmap.dart:9–20`, `40–45`). Copy says that flex habits use period progress; it does not infer ratio as level×20.

### Activity weights, date affiliation and null mood pass

The scoped statistics producer diff preserves the existing weights and conditions:

| Source | Preserved contribution |
| --- | --- |
| Completed todo with completedAt | +2 on completedAt's local calendar date |
| Active-date habit completion entry | recorded positive amount |
| Focus session | +2 on endTime's local calendar date |
| Time entry | +2 at >=60 minutes, otherwise +1 on startAt's local calendar date |
| Diary | +1 on its declared calendar date, including null-mood diary |

Only actual instant sources receive toLocal (`statistics_screen.dart:648`, `657`, `661`). Habit keys use the strict calendar parser; diary.date is passed without timezone shifting (`652–654`, `663–664`). The raw scores still clip to0..5 (`667`). No unique-event count, new duration filtering, source deduplication, record splitting or substitution of habit progress was introduced.

ActivityHeatmapCard explicitly selects HeatmapMetric.activity. Its summary labels active days and peak level, and the chart/legend describe activity levels. A negative-habit setback can still raise activity while reducing habit progress; zero-duration time records and focus/time-log overlap retain their existing behavior. Those are preserved metric boundaries, not newly verified business-policy guarantees.

## Acceptance limits and later evidence

This is source acceptance apart from the one canonical output-key repair; no diagnostic, widget, timezone or runtime evidence was run. The test author is independent. This assignment did not reread the new mood renderer or diary editor/navigation changes, so it does not sign off their categorical UI/actions; it confirms only preserved null-mood diary contribution in the activity producer.

After the formatter repair, later focused evidence should cover canonical years0001/0999/1000 and leap boundaries; Monday/Friday/Sunday eligible counts; old/future values excluded from summary; DST spring/fall with unique consecutive keys; single/combined positive, negative and flex levels; timestamp-local versus diary-calendar attribution; score clipping; and chart/summary agreement through the same today/window. Stored legacy habit lookup must remain intact when canonical presentation output keys change.

## Fingerprints and final freeze

| Reviewed path | SHA-256 |
| --- | --- |
| `lib/core/heatmap_calendar.dart` | `53ec395fa0292b6dcc5939d7faf764bb0d3e4af57b65b65e1dc1f4a41cd08641` |
| `lib/widgets/activity_heatmap_card.dart` | `5180ca6c180de9f1d73cf3148f689181e133865b93c0b636699cf2bf0684b313` |
| `lib/widgets/habit_heatmap.dart` | `577c674015017bf0b1e9e20283c425e918df9da83a5d30a20af1c6ab53b447c6` |
| `lib/widgets/calendar_heatmap.dart` | `16f20135406d4a9217d9435f6241b43339752b986fa3c4333adfb08c3be3acf7` |
| `lib/models/habit.dart` | `c487c72e39b2b3a8340c05ce95a847c618883a35eb1c2078dd1597bc99c9db8d` |
| `lib/providers/habit_provider.dart` | `8a39378492ca2ce1c4aaf2050933ac344ab33c8dc0ece1961933b78d8f0f18e8` |
| `lib/screens/habit_screen.dart` | `788989f5ef7c1c89be148949aec77a3b547eb98c887f42facfdca62d432d7d4c` |
| `lib/screens/habit_detail_screen.dart` | `dcb4bae627483b6079a93527fbb343a0b9e2643feaa7c7b4526995f11bc3acb2` |
| `lib/screens/statistics_screen.dart` | `5411e1a097919203ed8f6f560eabf7141b57e12271ed23711f587eb9f286a601` |
| `lib/core/heatmap_ui_copy.dart` | `9e414096712d6123623d0d5ba67f78bd39514cccf8dc6bb71ebacd36a0fa1eb9` |

**Production reads are frozen/stopped at report completion.** Only this private report was changed. Root retains implementation ownership.
