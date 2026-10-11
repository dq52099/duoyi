# Today Candidate Regression — 2026-10-11

## Candidate snapshot

- Detached worktree: `/home/ubuntu/duoyi/.dart_tool/task-temp-20261011/today-candidate-e80678b`
- Base commit: `e80678bd11e7ca8241213f5e7d8aeca03a4a7165`
- `flutter pub get --offline --enforce-lockfile` succeeded with Flutter 3.41.9. `pubspec.yaml` and `pubspec.lock` stayed unchanged.
- The candidate production snapshot was not edited during verification. Root copied the corrected Today/Mine fixture test into the candidate immediately before the final 34-test run. That hash identifies this run's snapshot; it does not include the retained Today suggestion callback same-ID test added later to the main worktree.

### Five-file fingerprints

Initial full-suite inputs (SHA-256):

| File | SHA-256 |
| --- | --- |
| `lib/screens/today_screen.dart` | `5cd564139b2309a8f03605d9d3f5eecb0f1023b5cc80adc9b652e9106bda0705` |
| `lib/core/today_ui_copy.dart` | `6b1677851e3036c80613a04b09514908c8dd0c5a0d8b0ea77cdca7931d5fdc56` |
| `lib/core/almanac_locale_format.dart` | `c2c85ada3c3b60134a3a7b8225b4a54d6984bc7e313c0a06058eedc4f677025a` |
| `test/screens/desktop_web_shell_widescreen_test.dart` | `4fb45e6ad5456827b7034dba9b5d5b173dd3209f52782723acfd5c74173081df` |
| `test/screens/today_mine_smoke_test.dart` (initial) | `f65e329f1439724ebf80383297688a3c5dbba0e0429f23d0dc826c4ca5c95667` |

The intermediate attempt used root's first locator fix for `today_mine_smoke_test.dart` (`7d54030b8d1b1ec33d336cbfea1d268584dbc4feb99417b319193ef28a7e830c`). The three production files and the desktop shell test fingerprints remained identical.

## First full test run

Ran serially with `flutter test --no-pub --concurrency=1 --reporter expanded` on:

- `test/screens/desktop_web_shell_widescreen_test.dart`
- `test/screens/today_mine_smoke_test.dart`

Screenshot capture was enabled for this run. Result: **34 tests total, 32 passed, 2 failed**.

1. `Today open delete confirmation stays bound to its original account` initially failed at line 184 because `find.textContaining('原账号任务')` matched both the row and the confirmation dialog copy. Root fixed this overly broad locator. This first failure alone did not reach the deletion assertion and was not evidence of a UI account-isolation bug.
2. `今日和我的概览/入口样式保持独立且不过度放大` failed at line 539 because the test looked for the exact source string `return _MineRecordReviewGroup();`, which was absent. Candidate `mine_screen.dart` actually returns `capped(_MineRecordReviewGroup(columns: tileColumns))`. The `5996` value was a Dart source-string index compared with `-1`, not a scroll offset or visual measurement. Root fixed this static source locator.

Full output: `.dart_tool/task-temp-20261011/today-candidate-regression-20261011.log`.

## Focused analysis

Analyzed the three Today source files and both target tests with `flutter analyze --no-pub`. The command exited 1 with three **info** diagnostics and no warning/error diagnostics:

- `lib/screens/today_screen.dart:2540` — `use_build_context_synchronously`: `_confirmDelete` awaits the dialog, checks State `mounted`, then uses its `BuildContext` parameter.
- `lib/screens/today_screen.dart:3419` and `:3420` — `deprecated_member_use`: the candidate adds `ExpansionTileController`, deprecated in the installed Flutter SDK in favor of `ExpansibleController`.

Both sites are in the candidate's changed code. Full output: `.dart_tool/task-temp-20261011/today-candidate-analysis-20261011.log`.

## Intermediate retest after locator fixes

Root's first corrected test file was copied to the candidate and the same two-file test group was rerun without screenshot capture. The delete-confirmation test then reached its final assertion and got `['old-account-task', 'new-account-task']` where it expected only the new task. This was traced to the fixture: `TodoProvider.resetLocalState()` clears in-memory state but does not clear SharedPreferences; the following `addTodo()` hydrates the old stored list before adding the new task. The fixture only invalidated writes and reset the provider, so it did not model the account cleaner's disk cleanup. Root has corrected the fixture to clear the stored `todos` key and added a same-ID account-switch case while retaining the final assertion.

That intermediate runner disappeared after reporting 18 test completions while the root's serial provider suite was also running. Its log has no final summary and is not treated as a completed result: `.dart_tool/task-temp-20261011/today-candidate-regression-retry-20261011.log`.

## Final fixture-corrected regression

After root fixed the account-switch fixture, copied only the current `test/screens/today_mine_smoke_test.dart` into the candidate. The corrected fixture removes the persisted `todos` key after resetting the old provider state, then adds the replacement account's todo with the **same ID** and a new title. The retained deletion assertion checks that the old dialog does not delete the replacement account's same-ID todo.

Final candidate fingerprints:

| File | SHA-256 |
| --- | --- |
| `lib/screens/today_screen.dart` | `5cd564139b2309a8f03605d9d3f5eecb0f1023b5cc80adc9b652e9106bda0705` |
| `lib/core/today_ui_copy.dart` | `6b1677851e3036c80613a04b09514908c8dd0c5a0d8b0ea77cdca7931d5fdc56` |
| `lib/core/almanac_locale_format.dart` | `c2c85ada3c3b60134a3a7b8225b4a54d6984bc7e313c0a06058eedc4f677025a` |
| `test/screens/desktop_web_shell_widescreen_test.dart` | `4fb45e6ad5456827b7034dba9b5d5b173dd3209f52782723acfd5c74173081df` |
| `test/screens/today_mine_smoke_test.dart` (fixture-corrected snapshot used by the final run; excludes the later suggestion callback same-ID test) | `1b115bcf8091ef064f4996e4e40c144a676260472560fe7a4bdb33beae384c90` |

The same two-file serial test command was rerun without recapturing screenshots. Final result: **34 tests passed, 0 failed**. This includes the same-ID account-switch deletion case and the corrected Mine source locator.

- Full output: `.dart_tool/task-temp-20261011/today-candidate-final-regression-20261011.log`.
- Final focused analysis on the same five paths completed and returned the same three production `info` diagnostics listed above; the corrected test file added no diagnostics. Output: `.dart_tool/task-temp-20261011/today-candidate-final-analysis-20261011.log`.
- The intermediate failure logs are retained for history; final status is based on the fixture-corrected run above.

## Screenshot evidence

The first test run wrote eight screenshots through the test's relative paths under the candidate worktree's `evidence/screenshots/`. Root copied and reviewed them in the main project at:

- `evidence/screenshots/today-candidate-e80678b-20261011/locale/home-en-320-scale-1.6.png`
- `evidence/screenshots/today-candidate-e80678b-20261011/locale/home-en-390-scale-1.6.png`
- `evidence/screenshots/today-candidate-e80678b-20261011/locale/home-en-1120-scale-1.6.png`
- `evidence/screenshots/today-candidate-e80678b-20261011/locale/home-en-1440-scale-1.6.png`
- `evidence/screenshots/today-candidate-e80678b-20261011/calendar/home-320.png`
- `evidence/screenshots/today-candidate-e80678b-20261011/calendar/home-390.png`
- `evidence/screenshots/today-candidate-e80678b-20261011/calendar/home-430.png`
- `evidence/screenshots/today-candidate-e80678b-20261011/calendar/home-1440.png`

Root reports that transparent screenshot backgrounds appear black in the viewer. These captures can document the tested widget layout; they do not establish production-theme rendering or offline font acceptance. No browser run or visual review was performed by this candidate regression task.

No production source was changed, and nothing was committed or deployed.
