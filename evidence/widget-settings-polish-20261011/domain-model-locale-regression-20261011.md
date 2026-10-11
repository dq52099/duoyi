# Domain model locale regression acceptance — 2026-10-11

## Result

The four focused regression files passed: **18 tests, exit code 0**. Log: `.dart_tool/task-temp-20261011/domain-model-locale-regression.log`.

Command:

```sh
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 /home/ubuntu/flutter/bin/flutter test --no-pub --reporter expanded test/models/enum_label_i18n_test.dart test/models/note_json_compat_test.dart test/core/diary_deep_review_test.dart test/services/module_exporter_csv_static_test.dart
```

## Covered contracts

- Every Mood and Weather label follows the selected locale; emoji and enum indices remain stable. Explicit `labelFor` calls do not change the global locale.
- Empty diary and note titles localize lazily. Authored first lines that exactly match the Chinese fallback remain literal, and locale changes leave both models' JSON unchanged. Explicit `titleFor` calls do not change the global locale.
- The diary deep-review prompt is byte-for-byte equivalent across Chinese and English app locales.
- CSV output remains byte-identical across locales with a whitespace-only note and an empty diary; historical Chinese note and mood/weather labels remain in the export.

Calendar and search regression coverage is being handled in the root's separate batch.
