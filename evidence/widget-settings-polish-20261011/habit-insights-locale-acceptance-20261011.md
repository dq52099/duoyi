# Habit insight locale acceptance — 2026-10-11

## Accepted scope

`HabitInsight` retains its const named constructor and accepts optional typed
generated-text provenance. Existing literal constructors remain literal.
The engine attaches immutable overview, change, streak and attention facts
for all five insight kinds; retained results resolve title/message in the
selected locale without recalculating scores or changing membership.
Explicit `titleFor`/`messageFor` calls do not mutate the selected locale.

Authored habit names are copied unchanged when insights are generated. A
later source-name edit does not rewrite a retained insight. Thresholds,
ordering, IDs, limits, score expressions and original Chinese copy remain
unchanged. Window enums and their original data labels are unchanged.

## Verification

- **15 checks passed, exit 0** across the new locale test and existing insight
  and trend tests. Covers all five engine branches, 80/50/49 overview
  thresholds, four windows, same-object Chinese/English/Chinese rendering,
  literal fallback-looking text, authored-name snapshots, JSON stability,
  scoring/order/IDs/limits and existing trend/date calculations.
- Four-file focused analysis: **no issues, exit 0**, 72.1 seconds.
- Sol reviewed the production diff without running tests and found no
  blocking compatibility issue in this scope.

Commands used `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011`
and `/home/ubuntu/flutter/bin/flutter`:

```sh
flutter test --no-pub --concurrency=1 --reporter expanded test/core/habit_insights_locale_test.dart test/core/habit_insights_test.dart test/core/habit_trend_test.dart
flutter analyze --no-pub lib/core/habit_insights.dart test/core/habit_insights_locale_test.dart test/core/habit_insights_test.dart test/core/habit_trend_test.dart
```

Logs: `.dart_tool/task-temp-20261011/habit-insights-locale-regression-20261011.log`
and `habit-insights-locale-analysis-20261011.log`.

## Remaining page work

The Habit screen already listens for locale changes and reads insight
getters, but its section heading, forms, badges and feedback still need the
AGY-owned page-copy pass. This acceptance is domain and regression coverage;
it does not establish complete page localization, screenshots or device
performance.
