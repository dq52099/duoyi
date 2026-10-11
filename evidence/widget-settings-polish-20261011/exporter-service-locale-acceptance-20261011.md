# Export service locale acceptance — 2026-10-11

## Scope

Verified `IcsExporter` and `ModuleExporter` locale behavior in the current `/home/ubuntu/duoyi` checkout. The change is limited to `lib/services/ics_exporter.dart`, `lib/core/export_ui_copy.dart`, and `test/services/module_exporter_csv_static_test.dart`.

## Behavior recorded

- Each ICS or Markdown export snapshots `I18n.current` for its call. Omitted ICS calendar names resolve to the active locale; a supplied name, including an empty string, overrides the default and is escaped as ICS text. Commas, semicolons, CRLF, CR, and LF are escaped in text properties.
- Generated Markdown headings, attachment labels, note status labels, diary tag label, anniversary type/calendar labels, and the next-occurrence label are localized. Event and authored todo, note, diary, anniversary, and goal text, user group names, tags, and attachment names remain literal.
- Todo grouping uses a unique object sentinel for unnamed items. A user group named `未分组` or `Ungrouped` stays distinct from the unnamed group, even when both display the same localized heading.
- CSV headers and stable schema fields remain unchanged. To preserve historical output, Todo priority and time-entry category/source labels stay in their existing Chinese forms across locale changes. Diary mood/weather and anniversary type labels remain Chinese; goal status/category and habit kind remain enum names; anniversary calendar values remain `solar`/`lunar`.
- ICS `PRODID`, UID construction, `CATEGORIES`, recurring `RRULE`, and export filenames are unchanged.

## Test

Command:

```sh
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 /home/ubuntu/flutter/bin/flutter test --no-pub --reporter expanded test/services/module_exporter_csv_static_test.dart
```

Result: **5 tests passed**, exit code **0** (`+5: All tests passed!`). The captured log is `/home/ubuntu/duoyi/.dart_tool/task-temp-20261011/exporter-service-locale-tests.log`.

Coverage includes bilingual ICS defaults and Markdown labels, explicit ICS name escaping and empty-name override, protocol identity, preservation of authored content, distinct unnamed/named todo groups, and Chinese-to-English CSV output equality with stable headers and enum values.

## Analysis

Command:

```sh
TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 /home/ubuntu/flutter/bin/flutter analyze --no-pub lib/services/ics_exporter.dart lib/core/export_ui_copy.dart test/services/module_exporter_csv_static_test.dart
```

Result: **No issues found**, exit code **0** (ran in 31.5 seconds).
