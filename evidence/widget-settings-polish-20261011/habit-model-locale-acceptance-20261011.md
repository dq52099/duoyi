# Habit model locale acceptance — 2026-10-11

## Accepted behavior

- Generated week/month progress, flex targets and recorded-count framing
  follow Chinese/English. Explicit locale methods leave global locale alone.
- English null-unit counts use `time`/`times`. Every non-null authored unit,
  including Chinese `次` and an empty string, stays literal. Habit names,
  notes, tags, categories, JSON, reminder plans and completion rules stay
  unchanged.
- Calendar aggregation freezes its raw subtitle in the legacy Chinese form,
  and captures immutable typed Habit display facts. The resolver changes
  retained display copy by locale without rewriting event JSON or titles.
  Imported/JSON-round-tripped events keep literal subtitles; copied local
  events are excluded by the event-type guard.
- Calendar signatures include flex rules. Value comparisons include Habit
  display facts, so default-unit → authored `次` edits notify even when raw
  Chinese text is equal; equal facts suppress redundant notifications.

## Verification

**89 checks passed, exit 0** across nine model/core/provider/heatmap test
files. They cover both kinds, week/month rules, pluralization, authored
units, same-object locale switches, out-of-range flex fallback, immutable
calendar facts, JSON/copy/type boundaries, cache invalidation and the existing
Habit/provider/date behavior. See `habit-model-locale-regression-20261011.md`
for the exact targets and logs.

Six production files and the three locale tests listed in that report
passed focused analysis: **no issues, exit 0**, 124.0 seconds. The provider
cache test passed compilation and execution in the regression suite.

The existing export suite additionally passed **5 checks, exit 0**, including
the all-module CSV locale invariant with Habit data. Command:
`flutter test --no-pub --concurrency=1 --reporter expanded test/services/module_exporter_csv_static_test.dart`.
It used the task TMPDIR and `/home/ubuntu/flutter/bin/flutter`; log:
`.dart_tool/task-temp-20261011/habit-locale-csv-compatibility-20261011.log`.

Sol reviewed the final production diff and both cache fixes without running
tests; its bounded review found no remaining blocking issue.

## Remaining UI acceptance

AGY still owns routing calendar day/week rows through the display resolver
and translating Habit badges/forms/feedback around the new model labels.
Widget publication does not call these count formatters; its schema/actions
were unchanged by inspection. This round did not establish device behavior,
widget rendering, final page localization or a new release.
