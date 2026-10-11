# Calendar latest copy acceptance — 2026-10-11

Focused verification of the finalized Calendar copy source and dependent widget/model contracts. Commands ran serially from `/home/ubuntu/duoyi` with the assigned Flutter binary and temporary directory. No `pub get`, install, Git, build, or source/test edits were performed.

Command form:

```sh
env TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
  /home/ubuntu/flutter/bin/flutter test --no-pub --reporter expanded <test-file>
```

## Results

| Test file | Result | Log |
| --- | --- | --- |
| `test/core/calendar_agenda_ui_copy_test.dart` | Exit 0; 6 passed | [01-calendar_agenda_ui_copy.log](calendar-latest-copy-acceptance-logs/01-calendar_agenda_ui_copy.log) |
| `test/widgets/calendar_cached_display_locale_test.dart` | Exit 1; compile failed before tests loaded (0 executed) | [02-calendar_cached_display_locale.log](calendar-latest-copy-acceptance-logs/02-calendar_cached_display_locale.log) |
| `test/widgets/calendar_day_timeline_static_test.dart` | Exit 0; 4 passed | [03-calendar_day_timeline_static.log](calendar-latest-copy-acceptance-logs/03-calendar_day_timeline_static.log) |
| `test/widgets/calendar_month_grid_static_test.dart` | Exit 0; 3 passed | [04-calendar_month_grid_static.log](calendar-latest-copy-acceptance-logs/04-calendar_month_grid_static.log) |
| `test/widgets/calendar_drag_adjust_static_test.dart` | Exit 0; 1 passed | [05-calendar_drag_adjust_static.log](calendar-latest-copy-acceptance-logs/05-calendar_drag_adjust_static.log) |
| `test/core/calendar_event_display_text_test.dart` | Exit 0; 16 passed | [06-calendar_event_display_text.log](calendar-latest-copy-acceptance-logs/06-calendar_event_display_text.log) |
| `test/providers/calendar_provider_test.dart` | Exit 0; 9 passed | [07-calendar_provider_model.log](calendar-latest-copy-acceptance-logs/07-calendar_provider_model.log) |
| `test/providers/calendar_multiday_static_test.dart` | Exit 0; 3 passed | [08-calendar_multiday_static.log](calendar-latest-copy-acceptance-logs/08-calendar_multiday_static.log) |

The seven suites that loaded completed **42 tests successfully**. The retained mounted day/week locale test could not compile because `lib/core/todo_board_ui_copy.dart` references undefined `TodoDueFilter` and `TodoCompletionFilter` types at lines 189 and 199–203. This is outside the Calendar source scope and matches the separately reported incomplete Todo copy helper. No Calendar test body ran in that command. Rerun the mounted test after the authorized Todo source repair, or on an isolated clean Calendar candidate if the shared tree remains blocked.

## Source hashes

The first four hashes were captured before tests; the post-run values matched exactly. The Todo helper hash was captured after the compile failure for blocker provenance.

| Source | SHA-256 |
| --- | --- |
| `lib/core/calendar_agenda_ui_copy.dart` | `e31e3b82fe9a3bded90733c8cc5be360ca6d52866f345eb59ffe9da3cf09508e` |
| `lib/widgets/calendar_month_grid.dart` | `a37e7ce7c00d6262403a27a539232d482a19b4817e12f2b825aa9768eec04317` |
| `lib/widgets/calendar_day_agenda.dart` | `fe146ff5e14175dae65424637e2b45e3937f85536b2e8a26215d74d233ffb3cd` |
| `lib/widgets/calendar_week_strip.dart` | `7b33ef2c090bbfce6976d7f48089b162e16e264967045c2674c4dff19578fe23` |
| `lib/core/todo_board_ui_copy.dart` (compile blocker) | `260f50f4591d0c3d15f73aafa95defc8943424c03690fd224da3082a9cb40dc9` |

The Flutter window was released to the root agent after the serial test commands completed.

## Isolated finalized-candidate rerun — 2026-10-11

After the main-tree run above, the finalized Calendar/Habit/Search candidate at `.dart_tool/task-temp-20261011/calendar-habit-search-candidate-4ce3d77` was accepted as a detached copy based on `4ce3d77`. Its adjacent manifest identifies the 12 copied Calendar/Habit/Search files. This rerun addresses the Calendar checks on that isolated candidate only; it does not repair or change the shared main tree.

Before running Flutter, all 12 candidate file hashes matched `calendar-habit-search-candidate-4ce3d77-manifest.json`. Cached dependencies resolved offline successfully (exit `0`):

```sh
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
  /home/ubuntu/flutter/bin/flutter pub get --offline
```

The eight Calendar suites then ran in one serial invocation (exit `0`; **44 tests passed**):

```sh
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
  /home/ubuntu/flutter/bin/flutter test --no-pub --concurrency=1 --reporter expanded \
  test/widgets/calendar_cached_display_locale_test.dart \
  test/core/calendar_agenda_ui_copy_test.dart \
  test/widgets/calendar_day_timeline_static_test.dart \
  test/widgets/calendar_month_grid_static_test.dart \
  test/widgets/calendar_drag_adjust_static_test.dart \
  test/core/calendar_event_display_text_test.dart \
  test/providers/calendar_provider_test.dart \
  test/providers/calendar_multiday_static_test.dart
```

| Candidate test file | Result |
| --- | --- |
| `test/widgets/calendar_cached_display_locale_test.dart` | Exit 0; 2 passed |
| `test/core/calendar_agenda_ui_copy_test.dart` | Exit 0; 6 passed |
| `test/widgets/calendar_day_timeline_static_test.dart` | Exit 0; 4 passed |
| `test/widgets/calendar_month_grid_static_test.dart` | Exit 0; 3 passed |
| `test/widgets/calendar_drag_adjust_static_test.dart` | Exit 0; 1 passed |
| `test/core/calendar_event_display_text_test.dart` | Exit 0; 16 passed |
| `test/providers/calendar_provider_test.dart` | Exit 0; 9 passed |
| `test/providers/calendar_multiday_static_test.dart` | Exit 0; 3 passed |

The overlay-focused analysis of the four Calendar sources and the five new or updated Calendar tests exited `0` with **no issues found**:

```sh
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
  /home/ubuntu/flutter/bin/flutter analyze --no-pub \
  lib/core/calendar_agenda_ui_copy.dart \
  lib/widgets/calendar_month_grid.dart \
  lib/widgets/calendar_day_agenda.dart \
  lib/widgets/calendar_week_strip.dart \
  test/core/calendar_agenda_ui_copy_test.dart \
  test/widgets/calendar_cached_display_locale_test.dart \
  test/widgets/calendar_day_timeline_static_test.dart \
  test/widgets/calendar_drag_adjust_static_test.dart \
  test/widgets/calendar_month_grid_static_test.dart
```

For extra Calendar-only coverage, analysis of all eight test files from the serial suite together with the four sources also exited `0` with no issues found (12 items; log `02-calendar-focused-analyze.log`). No Habit or Search targets were included in either analysis or the test run. The candidate manifest hashes were checked again afterward; all 12 matched both the initial values and manifest. No candidate source or test file was edited.

Logs and the pre/post hash records are in [the isolated candidate acceptance logs](calendar-habit-search-candidate-4ce3d77-acceptance-logs/): offline `pub get`, serial test output, both focused analysis runs (`03-calendar-overlay-focused-analyze.log` is the overlay-only analysis), and source-hash JSON. The manifest SHA-256 is `f563cc9a4d8e1bd01c9ba69a8e9119f74bd59890610ab565b18c2729e8631894`.

The earlier main-tree mounted Calendar test remains blocked: `lib/core/todo_board_ui_copy.dart` in the shared main tree still has undefined `TodoDueFilter` and `TodoCompletionFilter` references. Passing on this detached candidate does not imply that the main-tree helper was fixed. Flutter verification was handed back to the root agent after this isolated rerun.
