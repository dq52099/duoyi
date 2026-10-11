# Main-tree Calendar, Search, Focus, and Todo integration acceptance — 2026-10-11

## Scope and integration

The test-only account-opening assertions from the accepted Calendar/Habit/Search candidate were copied into `test/screens/search_screen_static_test.dart`. The main file now matches the accepted candidate exactly. No production source was edited during this acceptance. The main-tree Todo copy dependency fix was already present before the pre-run hashes were captured.

The expected-failing Habit regression and unrepaired Backup regression were excluded. No additional Flutter suites were run.

## Serial test results

Each suite ran in its own serial command from `/home/ubuntu/duoyi` using `flutter test --no-pub --concurrency=1 --reporter expanded <test-file>`. All 16 suites exited 0; **80 tests passed**.

| Test file | Passed | Exit |
| --- | ---: | ---: |
| `test/core/calendar_agenda_ui_copy_test.dart` | 6 | 0 |
| `test/widgets/calendar_cached_display_locale_test.dart` | 2 | 0 |
| `test/widgets/calendar_day_timeline_static_test.dart` | 4 | 0 |
| `test/widgets/calendar_month_grid_static_test.dart` | 3 | 0 |
| `test/widgets/calendar_drag_adjust_static_test.dart` | 1 | 0 |
| `test/core/calendar_event_display_text_test.dart` | 16 | 0 |
| `test/providers/calendar_provider_test.dart` | 9 | 0 |
| `test/providers/calendar_multiday_static_test.dart` | 3 | 0 |
| `test/screens/focus_cached_ranking_locale_test.dart` | 1 | 0 |
| `test/screens/search_retained_locale_test.dart` | 1 | 0 |
| `test/screens/search_screen_static_test.dart` | 1 | 0 |
| `test/core/todo_filters_test.dart` | 5 | 0 |
| `test/core/todo_kanban_test.dart` | 8 | 0 |
| `test/screens/todo_filters_static_test.dart` | 6 | 0 |
| `test/screens/todo_kanban_view_test.dart` | 8 | 0 |
| `test/services/android_widget_frame_static_test.dart` | 6 | 0 |

The eight Calendar suites passed 44 tests, including the mounted cached-display test that had previously failed to compile in main because the Todo filter types were unresolved. The seven Focus, Search, and Todo suites passed 30 tests. The Android widget frame static suite passed 6 checks after the root agent updated its Snapshot wiring assertion.

## Scoped analysis

`flutter analyze --no-pub` analyzed 24 items: the four Calendar sources and eight Calendar tests; Search source and two Search tests; Focus Room copy, Pomodoro screen, and cached-ranking test; Todo board copy, Todo screen, and four Todo tests. It reported **no issues found** and exited 0. A separate scoped analysis of `test/services/android_widget_frame_static_test.dart` also reported no issues and exited 0. The outputs are in `main-calendar-search-focus-integration-logs/scoped-analyze.log` and `android-widget-frame-scoped-analyze.log`.

## Source hashes

All pre-run and post-run hashes match. Full hash records are in `main-calendar-search-focus-integration-logs/source-hashes-pre.sha256` and `source-hashes-post.sha256`.

| Source | SHA-256 |
| --- | --- |
| `lib/core/calendar_agenda_ui_copy.dart` | `e31e3b82fe9a3bded90733c8cc5be360ca6d52866f345eb59ffe9da3cf09508e` |
| `lib/widgets/calendar_month_grid.dart` | `a37e7ce7c00d6262403a27a539232d482a19b4817e12f2b825aa9768eec04317` |
| `lib/widgets/calendar_day_agenda.dart` | `fe146ff5e14175dae65424637e2b45e3937f85536b2e8a26215d74d233ffb3cd` |
| `lib/widgets/calendar_week_strip.dart` | `7b33ef2c090bbfce6976d7f48089b162e16e264967045c2674c4dff19578fe23` |
| `lib/screens/search_screen.dart` | `2e75864a367ed8cb8f8fbe037c008513729fe7d44bbd73ee0be35d3ee0486c77` |
| `lib/screens/pomodoro_screen.dart` | `86c5ec8502c2d3ff7c89a0250c5c7a804ce0b71d5b7f676e356ee8e61907a718` |
| `lib/core/focus_room_ui_copy.dart` | `92f4a198899c9d0cca59067a91c7940aed8e40f51413daa0966891b2eb9d3a82` |
| `lib/core/todo_board_ui_copy.dart` | `68f97bad9ef01cdf3b63cc1a3e0262804cf4142f54cb7c23fb40f4134cd9136a` |
| `lib/screens/todo_screen.dart` | `22508abd9c1cf00a8c1af0a6529294296b7f90fce07e881ca7ebe69ac208495d` |

The accepted Search source/test hashes match in main: Search source `2e75864a…0486c77`, retained-locale test `47ca5c12…1fadaa9`, and static account-boundary test `bef2d989…00d3f2b`.

## Logs and blocker boundary

Per-suite logs, including `16-android_widget_frame_static_test.log`, and `suite-status.tsv` are in `main-calendar-search-focus-integration-logs/`. The analyzer and source hash records are in the same directory. Habit remains an expected failing locale regression pending frontend repair; Backup remains excluded pending its Snackbar repair.
