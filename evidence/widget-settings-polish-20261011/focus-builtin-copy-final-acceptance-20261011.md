# Built-in Focus room copy acceptance — 2026-10-11

Root implemented explicit display provenance for the three app-generated rooms, with pure `nameFor(AppLocale)` / `descriptionFor(AppLocale)` methods. Original room and member JSON, raw names/descriptions, room IDs, ranking data, and API parameters retain their previous values.

## Persistent behavior

The local `duoyi_focus_rooms` envelope gains optional `builtinRoomCopy` V1 metadata on existing business saves. Valid markers require the exact version/type, catalog code/ID, and unchanged canonical raw title/description. Missing or invalid markers remain literal. User-authored rooms and remote invite rooms cannot gain provenance from matching IDs or text. Remote replacements clear it; subsequent saves omit invalid entries. Empty metadata is omitted.

Fresh app-generated defaults retain bilingual display across save and provider recreation. Older stored rooms without explicit provenance remain literal to preserve their meaning; no inferred migration or locale-driven writes are performed.

## Root execution

- Four serial Flutter suites: **39 passed** (22 new provenance tests; 17 existing model/provider/API checks).
- Scoped analysis of the two production files and new test: **exit 0**, no issues.
- Accepted input hashes remained unchanged during execution and matched current files afterward.
- Public `joinRoom` / storage load, `acceptInviteCode` / HTTP DTO, and actual invite request bodies were exercised with synthetic fixtures.
- Source review passed. Its model/provider hashes match final production inputs; the test subsequently changed only three equivalent null-aware map entries to satisfy the analyzer.

Fresh evidence is in `focus-builtin-copy-v2-acceptance-20261011/`. The initial run is retained separately and excluded from acceptance: all 39 tests passed, but three test-only style findings caused analysis exit 1.

## Limits and next work

Provider recreation proves the storage decode path; no process-kill device evidence is claimed. AGY still owns screen consumers and mounted modal/controller verification. This accepted model/provider change does not establish full Focus UI internationalization, release readiness, launcher behavior, native iOS acceptance, or deployment.

This batch also includes a one-line trailing-empty-line correction to the previously accepted `javap-c-p.txt`; bytecode text is unchanged.
