# Calendar sheet candidate acceptance

- Base revision: `e80678bd11e7ca8241213f5e7d8aeca03a4a7165` (detached worktree)
- Worktree: `.dart_tool/task-temp-20261011/calendar-candidate-e80678b`

## Initial isolated run: incomplete overlay

The first run overlaid the six requested sheet and test files from main but omitted `lib/core/i18n.dart`. At that point, offline locked dependency resolution exited `0`; the selected five test files (20 tests) and six-file focused analysis also exited `0`. Those results are retained, but they did not validate the complete candidate: the main sheet references nine `calendar.picker.*` keys that were missing from the base revision's i18n dictionaries, and the existing locale test's broad `findsWidgets` assertion did not by itself prove the picker heading was translated. The omission was found in review, so the first pass is not treated as final acceptance.

## Supplemental run with the missing copy

After the Today candidate's serialized Flutter/Dart window ended, copied only main's `lib/core/i18n.dart` into the detached candidate. No other source or tests were copied. The file SHA-256 in main and candidate is `46e21e9087b77f74990b96cc7526dfefc676fd4847a39b35b026dd86ce92c6dc`.

Read-only key verification found all nine `titleKey`/`subtitleKey` values referenced by the candidate sheet in both `_zh` and `_en` dictionaries. The date picker heading locale-switch test and the same-ID account route-opening test both passed in the supplemental run.

The seven-file candidate overlay manifest SHA-256 is `6b17e9caa409b2e81eb7cac5a512a1219b2c48ae2049771b7a592fadc29b3f34`. Its individual file hashes are recorded in `.dart_tool/task-temp-20261011/calendar-candidate-with-picker-copy-manifest.txt`. Dependency manifests were not changed: `pubspec.yaml` SHA-256 `9af01291ef169f6957d5e601df5f3c94468db34a8f19986c5e553199568fa39e`; `pubspec.lock` SHA-256 `73b80135ea9e434f83d7ae0e4eb77664a69c8f810e3f0cb346298d4b070e2786`. The prior offline locked `pub get` remains applicable because this supplemental copy changes no dependencies.

### Re-run tests

```sh
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
  /home/ubuntu/flutter/bin/flutter test --no-pub --concurrency=1 \
  test/widgets/calendar_event_sheet_locale_test.dart \
  test/widgets/calendar_all_day_dst_test.dart \
  test/widgets/calendar_event_sheet_static_test.dart \
  test/widgets/calendar_local_event_static_test.dart \
  test/widgets/calendar_event_sheet_test.dart
```

Exit code: `0`; all 20 tests passed. In particular, `nested date picker heading switches language with selection intact` and `sheet opening keeps the generation from before its route builds` passed.

For additional coverage of semantic picker headings updating live, also ran the existing base-revision test file (no source or test changes):

```sh
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
  /home/ubuntu/flutter/bin/flutter test --no-pub --concurrency=1 \
  test/widgets/app_picker_locale_state_test.dart
```

Exit code: `0`; all 5 tests passed, including the date and time picker semantic title/subtitle locale-switch cases. Across the requested and supplemental test selections, 25 tests passed.

### Re-run focused analysis

```sh
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 \
  /home/ubuntu/flutter/bin/flutter analyze --no-pub \
  lib/widgets/calendar_event_sheet.dart \
  lib/core/calendar_event_sheet_ui_copy.dart \
  lib/core/i18n.dart \
  test/widgets/calendar_event_sheet_locale_test.dart \
  test/widgets/calendar_all_day_dst_test.dart \
  test/widgets/calendar_event_sheet_static_test.dart \
  test/widgets/calendar_local_event_static_test.dart
```

Exit code: `0`; no issues found in the seven candidate files.

Full logs and the key/overlay manifests are retained under `.dart_tool/task-temp-20261011/`:

- Initial pass: `calendar-candidate-e80678b-pub-get.log`, `calendar-candidate-e80678b-tests.log`, `calendar-candidate-e80678b-analysis.log`
- Supplemental pass: `calendar-candidate-with-picker-copy-tests.log`, `calendar-candidate-with-picker-copy-picker-locale-tests.log`, `calendar-candidate-with-picker-copy-analysis.log`, `calendar-candidate-with-picker-copy-keys.log`, `calendar-candidate-with-picker-copy-manifest.txt`

No Flutter build, device check, commit, push, or deployment was run.
