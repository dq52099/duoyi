# Picker locale source audit — 2026-10-09

## Result and scope

No evidenced introduced **MUST-FIX** bug was found in the completed picker locale implementation within this bounded source review. The source supports live picker-owned copy refresh without reinitializing selected date/time, picker mode, ignore-year state, focused month, or existing wheel controllers. The reviewed fixtures use raw locale events while the sheet stays open; they do not conceal locale refresh behind a parent repump.

Inspected only these files in `/home/ubuntu/duoyi-worktrees/picker-locale-20261009`:

- `lib/widgets/app_date_picker.dart`
- `lib/widgets/app_time_picker.dart`
- `lib/core/i18n.dart`
- `lib/core/i18n_date_format.dart`
- `test/widgets/app_picker_locale_state_test.dart`
- `test/widgets/app_date_picker_test.dart`

Also read the existing private focused status JSON and log. No production or fixture files were edited. No Git, formatter, compiler, analysis, test, network, or new verification commands were run. No live Mine or route production was inspected. This report is the only write.

## Live locale and state ownership

[I18n.setLocale](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/core/i18n.dart:2347) updates `I18n.current` before notifying the static `ValueNotifier`. Both sheets attach one listener in initState and remove the same instance-method tear-off in dispose:

| Picker | Attach / callback / removal | State retained during the callback |
| --- | --- | --- |
| Date | [initState](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:178), [callback](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:188), [dispose](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:193) | `_selectedDay`, `_focusedDay`, `_mode`, `_lunar`, `_ignoreYear` |
| Time | [initState](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_time_picker.dart:73), [callback](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_time_picker.dart:87), [dispose](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_time_picker.dart:92) | `_hour`, `_minute`, `_minutes`, `_hourController`, `_minuteController` |

The callbacks perform only mounted-guarded `setState`. They do not reapply initial values, call date conversion setters, round a time again, change mode, recreate controllers, reload storage, or close/reopen the sheet. Both sheet builders return the same kinds of widgets at stable positions without locale-bearing keys.

The lunar wheel [owns its FixedExtentScrollController in initState](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:776) and [disposes it](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:798). On a widget update, [it jumps only if value/min/max changed](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:786). A locale event changes the label builder's output but leaves these numeric values unchanged, so the existing controller and selected item remain. Switching solar/lunar mode intentionally adds/removes the lunar wheels; that separate mode change is not controller retention across locale events.

Time-wheel controllers are created once before the listener is attached and passed into rebuilt [_Wheel instances](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_time_picker.dart:260). Initial 09:13 with a 5-minute step rounds to 09:15; locale refresh does not rerun the rounding operation. The selected value stays in 24-hour numeric storage while English presentation uses AM/PM through [I18nDateFormat.timeOfDay](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/core/i18n_date_format.dart:43). The wheels still show 00–23; this presentation choice does not reinterpret the returned TimeOfDay.

## Semantic keys and literal compatibility

The optional `titleKey`/`subtitleKey` parameters are threaded through Date `show` and `pickSolar`, and Time `show`. [Date resolution](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:230) and [Time resolution](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_time_picker.dart:141) occur in build, so a semantic key is translated anew after each event.

The precedence is explicit and consistent:

1. If a semantic key is supplied, translate it, even when a literal is also supplied.
2. Otherwise preserve the supplied literal byte-for-byte as the caller's content.
3. Otherwise use the localized default picker title. An absent subtitle remains null.

Existing literal callers retain their labels; passing a previously translated literal does not make it live. The new API lets later caller/editor work pass a key instead. An unknown or empty key follows [the existing I18n fallback](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/core/i18n.dart:2354), potentially returning Chinese or the key itself; the picker does not validate key names or fall back to a simultaneously supplied literal. This is the explicit API policy, not a newly demonstrated state-loss defect. There is no implementation documentation or fixture for simultaneous key-and-literal precedence; documenting that policy would make later migration less ambiguous.

The fixture header assertions are scoped to `AppSectionHeader`, so semantic-title copy cannot accidentally pass by finding the identical solar/lunar segment label elsewhere. Separate literal-title cases prove date and time literal compatibility during zh → en → zh.

## Lunar presentation and actual values

[Romanized GanZhi](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:16) uses the standard ten stems and twelve branches indexed from lunarYear − 4, with a positive modulus. The English year label is numeric lunar year plus Romanized GanZhi; the 2026 fixture expects `Bing-Wu`.

The formatter's branches preserve Chinese presentation:

- [Chinese year branch](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:48) still uses `LunarCalendar.ganzhiOf`, `年`, and the parenthesized numeric year. In the result preview, the parenthesized year is the selected solar year; in the year wheel it is the lunar year, as coded.
- [Chinese result branch](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:68) continues using Chinese lunar month/day names and the actual `isLeapMonth` for the displayed month name.
- The English result branch shows `Lunar`, the Romanized year, `Month`/`Leap Month`, and a numeric `Day` using English dictionary keys. [Wheel label helpers](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:695) use the same year/month/day presentation policy.

Romanization and label translation operate only on strings. `AppDatePickerResult.date`, `mode`, and `ignoreYear` remain final numeric/domain values. Locale change itself does not call `_setLunar` or `LunarCalendar.toSolar`. The fixture confirms a noninitial selected `DateTime(2026, 5, 19)` is returned after both locale changes, so translated presentation is not silently changing the selected date. This fixture does not independently validate every GanZhi year, a lunar-year boundary, or a leap-month case.

## Month, weekday, tooltip, and semantics behavior

Solar month headers use [I18nDateFormat.yearMonth](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/core/i18n_date_format.dart:22): Chinese `2026年6月` becomes English `Jun 2026`. The [calendar build](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:414) derives that from retained `_focusedDay`. Previous/next-month tooltip strings, compact weekday labels, and their separate weekday semantics labels are translated at build time. English `weekday.*` dictionary values are abbreviations (`Mon`…`Sun`), although the helper list is named `_weekdayFullKeys`; it does not supply full English weekday names.

Each [solar date cell](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:647) rebuilds a localized full-date Semantics label while retaining locale-independent `solar-day-YYYY-MM-DD` keys. Selected/enabled/button metadata derives from the actual date and bounds, rather than localized text. Lunar wheel [semantics labels](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:819) use the freshly formatted wheel label. Time's [selected-value header semantics](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_time_picker.dart:172) follows the same locale formatter as the visible value.

The two fixture files do not inspect a rendered semantics tree. The time fixture's `_selectedTimeText` predicate checks the Semantics widget's `header` and `label` properties, which demonstrates updated input to semantics but does not prove an assistive technology's final announcement. Weekday, date-cell, lunar-wheel, time-wheel, and selected-time wrappers pair an explicit `Semantics(label: ...)` with an ordinary Text child without `excludeSemantics`. This leaves a source-level risk of combined/repeated child announcements; the review cannot classify a specific rendered announcement regression without semantics-tree evidence or a baseline. It is not reported as an introduced MUST-FIX bug. Month tooltips and date/weekday semantics are live by source construction, but they lack direct post-switch fixture assertions.

## Fixture strength and limits

[The locale/state fixture](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/test/widgets/app_picker_locale_state_test.dart:22) is meaningful for the intended sheet lifecycle:

- It opens the picker once, changes May 17 to May 19, navigates to June, switches to lunar mode, and enables ignore-year before sending raw `I18n.setLocale` events.
- It calls only `pumpAndSettle` after those events; `_pumpHost`/`pumpWidget` is not called again while the active sheet is being asserted. The host has no LocaleProvider listener that rebuilds its parent from the event.
- It asserts changed labels, one still-open sheet, no premature future completion, retained mode/ignore-year/date during both events, retained June after returning to solar mode, and the final independent DateTime/mode/ignoreYear result.
- The English lunar state case rejects Chinese Han text in the visible picker. This covers built/visible wheel labels and preview copy; it does not enumerate every hidden wheel item.

[The time-controller case](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/test/widgets/app_picker_locale_state_test.dart:204) records both controller objects, changes from a rounded 09:15 to 20:00 using a preset, and checks `identical` controller objects plus selected indices across both events. Its final returned `TimeOfDay(20, 0)` is an independent domain assertion. It would catch remounting the time sheet or resetting its controller state. It does not simulate a wheel drag or a locale event during an in-flight wheel animation.

[The disposal case](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/test/widgets/app_picker_locale_state_test.dart:276) cancels each sheet, asserts null results, changes locale after dismissal, and checks for framework exceptions. This supports safe disposal, but **does not by itself prove listener removal**: a leaked callback containing `if (mounted)` could survive without throwing. Balanced add/remove is established by the production source in this audit. The test does not count listeners or assert a weak-reference/lifecycle leak condition.

The date fixture does not record lunar wheel controller or sheet State identities and does not move a lunar wheel before the locale event. Its noninitial date/mode/ignore-year/focus values make sheet-state reinitialization detectable, but direct lunar-controller lifecycle retention remains source-backed rather than separately fixture-proven. The existing [date-picker fixture](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/test/widgets/app_date_picker_test.dart:49) covers Chinese grid/clickable dates and style/current-month color, with no locale event, narrow viewport, enlarged text, or semantics tree assertion.

## Narrow and enlarged-text risks

The source improves English label fit without changing controller geometry: [weekday labels use FittedBox](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:561), [lunar labels use FittedBox](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:822), [time ±30-minute labels use FittedBox](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_time_picker.dart:205), and time presets are in a Wrap. No fixture in the permitted files varies viewport size or TextScaler.

Remaining source-level risks, not observed failures:

- The lunar year's English `2026 (Bing-Wu)` must fit one of three equal columns at a fixed 42-pixel wheel item extent. FittedBox can avoid horizontal overflow by shrinking text, which limits enlarged-text readability.
- Solar day numbers retain [38-pixel cell height](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:662), with no text fitting. Time wheels retain [44-pixel item extent](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_time_picker.dart:327) and ordinary titleLarge text. At high text scaling, glyphs may exceed the available row height or spacing.
- The date mode segment labels include longer English `Gregorian`; the two segments have no local fitting/wrapping policy. The month heading likewise has an Expanded slot but ordinary Text between arrow buttons.
- The lunar summary has [maxLines: 1 and ellipsis](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:335), so narrow screens truncate the longer English summary. Full values remain in the source Text's data/semantics input but visual access may require a later design change.

The shared modal layout was outside the allowed source scope. This review does not assert overall modal overflow or keyboard behavior; those require the modal's layout and viewport evidence. Existing recorded surface-layout checks cannot be interpreted as proving every picker combination and text scale.

## Existing gaps and scope exclusions

These lunar conversion/clamping issues are the existing gaps identified in the task, visible in the current code; they are not caused by the locale callback or Romanized labels and are not claimed fixed:

- [_setLunar](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:213) uses current `_lunar.isLeapMonth` for `daysInMonth`, then calls `toSolar` without supplying a leap-month flag. A lunar edit can lose leap-month interpretation.
- [The month wheel](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:727) has numeric months 1–12; it does not offer regular and leap occurrences as separate selectable values. Its Leap Month label describes the existing selection.
- [The lunar day-wheel maximum](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:743) calls `daysInMonth` without `isLeap`, so its range is not explicitly aligned to a selected leap month.
- [_clamp](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:198) normalizes the candidate to midnight but compares against raw firstDate/lastDate and may return a raw bound with a time component. [Solar cell bounds](/home/ubuntu/duoyi-worktrees/picker-locale-20261009/lib/widgets/app_date_picker.dart:600) normalize both bounds, producing a date-only inconsistency for time-bearing limits. Lunar wheels also retain fixed 1900–2099 year limits while arbitrary caller bounds are enforced only after conversion/clamping.

No broader caller/editor source was inspected. A caller that passes a Chinese literal or a captured translated literal will continue to display that literal even when the picker-owned controls update. The semantic-key API enables later caller migration; it does not automatically translate user content or arbitrary caller strings. Editor drafts and captured editor titles have their own state/dependency paths and are not proven live by these picker fixtures.

## Existing recorded verification

The private [status JSON](/home/ubuntu/duoyi_deploy_backups/widget-refinement-20261006/picker-locale-focused-oct9-status.json) records a focused run from `2026-10-09T02:34:45.292743+00:00` to `02:35:09.522021+00:00`, exit code 0, `case_count: 36`, `source_unchanged: true`, and `success_marker_present: true`. The private [log](/home/ubuntu/duoyi_deploy_backups/widget-refinement-20261006/picker-locale-focused-oct9.log) ends with `+36: All tests passed!`. Its command covers the two picker fixtures, date formatting, style/layout guards, and widget day-boundary checks. Only five cases in that run belong to the locale/state picker fixture; the total of 36 should not be described as 36 picker lifecycle cases.

Those results belong to the already completed run. This audit read them and performed no new checks, hash calculation, or rerun. The JSON's recorded unchanged-source assertion was not independently re-established here.

## Recommendation

Accept the bounded picker locale implementation on the source evidence and existing recorded focused results, with no additional AGY production revision requested from this audit. Carry forward the explicit limits: broader literal caller/editor migration, existing lunar leap/clamping behavior, and picker-specific semantics/narrow/enlarged-text coverage. If a later verification batch extends fixtures, the most useful additions are a lunar-wheel controller identity plus changed lunar selection across a raw notifier event, English solar month/weekday/tooltip/semantics assertions, real semantics-tree output, and representative narrow/large-text layouts. These are recommendations, not tests added or run by this task.
