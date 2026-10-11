# Registered reminder display — final source contract review (2026-10-11)

## Decision and scope

**No substantive source blocker found.** The reviewed data-layer implementation satisfies the [display-locale contract](registered-reminder-display-locale-contract-20261011.md): new owned diagnostic facts render lazily, canonical strings remain stored, legacy/malformed descriptors retain literal display and registry identity, and metadata reaches retained snapshots through cache/batch/copy paths.

This is a read-only review of the current owned production diff at `HEAD f873d65`, plus the three authors' test sources. Only this report is written. No production/test edits, Flutter/Dart/test/build/deploy execution, Git delivery or agent spawning is performed.

The first serial six-suite/nine-item gate finished with a test-fixture failure and one fixture analysis info. Root corrected the two test issues and completed a **full rerun** (handle `52436`): **189 tests passed**, nine-item analysis reported **No issues found**, both exit codes were zero, and all nine before/after source hashes were unchanged. The final logs and summary were read directly for this report; the five reviewed hashes match them. Page/detail-sheet locale subscriptions and mounted UI repaint remain a separate AGY acceptance scope.

## Parsing failure preserves the record

- `tryFromJson` requires schema version 1, exact keys, recognized shape/subject/title mode, and matching outer object type. Rules require an actual bool and a positive safe integer count. Habit/dated shapes require an active recognized primary kind; weekdays are unique integer values 1–7, optional time is either fully unset or a valid pair, and dated facts have exact integer components with a real calendar date ([reminder_schedule_display_copy.dart](../../lib/services/reminder_schedule_display_copy.dart:140), [reminder_schedule_display_copy.dart](../../lib/services/reminder_schedule_display_copy.dart:334)).
- The parser rejects unsupported/incomplete descriptors with `null`. In the preferences JSON path, casts/factory calls follow validation, so malformed descriptor fields do not throw into the whole display-registry catch. Date validation checks bounded components and rejects constructor rollover ([reminder_schedule_display_copy.dart](../../lib/services/reminder_schedule_display_copy.dart:350)).
- `_readDisplayAll` always builds the valid base `ReminderScheduleDisplayInfo` from the original string values, separately decoded kinds and accepted groups, and the optional parser result. A null descriptor does not skip that record ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:713)). Existing base-record validation remains: non-string or entirely blank base display fields are invalid independently of metadata.
- Notification IDs remain under the separate ID-registry key and reader. Neither optional parsing nor rendering modifies that reader, ID normalization, kinds decoder or accepted-ID decoder. Legacy absence and malformed metadata therefore preserve the same valid base record and ID ownership.
- `ReminderScheduleSnapshotEntry.displayFor` also rejects a typed descriptor whose subject does not match `objectType`, returning the raw title/subtitle. This protects the retained in-memory display boundary as well as the preferences parser ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:107)).

No Chinese text matching or reconstruction of facts from rendered titles/subtitles was added.

## Raw storage and retained display are separated

- `ReminderScheduleDisplayInfo.title`/`.subtitle` remain canonical final strings. Preferences decode uses trimming only to validate emptiness, then retains the original values; write persists those raw fields plus locale-neutral descriptor JSON ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:717), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:825)).
- Both rule-display builders and `_rememberReminderDisplay` preserve a nonblank authored title without trimming away its original text. They retain the existing Chinese canonical fallback/subtitle and record title ownership explicitly from whether the source title is blank ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1597), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1627), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1694)). This does not alter rule bodies or domain objects.
- Snapshot construction carries the raw fields and descriptor together. Existing `.title`/`.subtitle` reads now render using the current locale; a retained entry does not need to be refetched. `displayFor(AppLocale)` allows a single explicit-locale pair without changing global locale ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:80), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1535)).
- Rendering uses only captured facts, supplied kinds, strings and the locale argument. It invokes no scheduler/sink, preference API, notifier, pending-queue query or current-time/next-occurrence computation ([reminder_schedule_display_copy.dart](../../lib/services/reminder_schedule_display_copy.dart:261)). Literal title mode returns the supplied authored title exactly; legacy/malformed snapshots return both raw fields exactly.
- Descriptor JSON has no locale field or rendered wording. Habit weekdays are copied into an unmodifiable list. Dated display retains captured local components and formats them without timezone conversion.

The existing UI row/detail helpers still read `entry.title` and `entry.subtitle` on build, so the preserved getter interface supplies fresh text when those consumers rebuild ([notification_history_screen.dart](../../lib/screens/notification_history_screen.dart:2152), [notification_history_screen.dart](../../lib/screens/notification_history_screen.dart:2438)). Their own trimming, empty-field fallback/chrome text, and rebuild triggers were not changed by this data diff.

## Metadata propagation inventory

| Path | Review result |
| --- | --- |
| Preferences read/write | Reads/writes `display_copy` alongside the unchanged canonical fields, kinds and accepted groups. |
| `_snapshotDisplayFor` / `_registryDisplayFor` | Preserve existing memory → persisted → scheduled/resolved rules precedence; newly created generic records carry `registered` metadata. Legacy preferred records are not inferred or upgraded from another record. |
| Scheduled/resolved rule display builders | Capture explicit title mode, repeating flag and nonempty rule-list count, while preserving the existing typed kinds and accepted-group normalization. |
| `_rememberReminderDisplay` and habit/anniversary/countdown creators | Carry the descriptor into `_registeredReminderDisplay`; source facts supply metadata directly. |
| `_withAcceptedIdSets` | Copies `displayCopy` together with raw title/subtitle and kinds; the unchanged empty-normalized-groups branch returns the original complete object ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1724)). |
| Snapshot projection | Copies `displayCopy` without rendering at projection time ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1543)). |
| In-memory registry replace/applyBatch | Store the whole display object, retaining the descriptor ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:923), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:957)). |
| Batch wrapper, mutation, overlay, flush | Pass/store the whole display object; `overlayDisplays` and `stageReplace` retain it directly. No string-only reconstruction strips metadata ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:992), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1130)). |

All production `ReminderScheduleDisplayInfo` construction sites were checked. No missing descriptor copy was found.

## Generators preserve scheduling and account boundaries

- Rule metadata constructors require todo/goal subjects and nonzero counts. The scheduler's rule-display calls receive nonempty lists, and todo/goal reconciliation call sites supply those known subjects. The new `byName`/factory validations do not add a throwing path for those existing supported inputs ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1576), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1668), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:2255), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:3320)).
- Habit metadata is created after the existing enabled/non-off primary-rule gate. `_habitWeekdays` supplies normalized valid weekdays, and invalid/unset clock inputs are represented as two null facts before the strict factory is called ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1915), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:2577), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:5768)). This affects display facts only.
- Anniversary/countdown creators omit metadata for off kinds or years outside 1–9999 while preserving their canonical display and kind fields. Their reminder time is already a `DateTime`; ordinary validated dates/time therefore meet the metadata factory's constraints ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1940), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1967)). No reminder time is changed to make metadata valid.
- The owned scheduler diff changes display types/builders and optional display persistence only. `_ResolvedRule`/`_ScheduledRule`, scope and intent/delivery/fingerprint comparison, dispatch/touch payload, ID derivation, registration/cancellation/retry logic, and account guards remain outside the diff ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1248), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1465), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:5706)). Locale display reads cannot become a reconciliation trigger through the new code.
- Existing preference generation guards and interrupted-batch ID-only ownership behavior are preserved. `_persistInterruptedBatchOwnership` still avoids committing old-account displays ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1486)).

## Test-source coverage and remaining acceptance

The earlier fixture omissions have been filled in the current test source:

- **Copy tests:** all four shapes, exact bilingual output, literal title preservation, explicit locale without global mutation, frozen weekdays, JSON round trips, invalid versions/keys/types, kind/weekday/time validation, safe counts, impossible dates, and subject mismatches ([reminder_schedule_display_copy_test.dart](../../test/services/reminder_schedule_display_copy_test.dart:92), [reminder_schedule_display_copy_test.dart](../../test/services/reminder_schedule_display_copy_test.dart:452)).
- **Registry tests:** replace/applyBatch round trip, first snapshot read under English with exact English getter assertions, retained zh → en → zh reads, raw strings/descriptors/kinds/accepted groups and both preference strings unchanged, and batch overlay/flush propagation ([reminder_schedule_display_registry_test.dart](../../test/services/reminder_schedule_display_registry_test.dart:21), [reminder_schedule_display_registry_test.dart](../../test/services/reminder_schedule_display_registry_test.dart:533)).
- **Whole preferences fallback matrix:** 11 malformed descriptors, two legacy literal records, and a valid neighboring record are seeded into real mock preference JSON. The test checks the entire registry decoder and cold retained snapshot, preserving each object's IDs, raw strings, kinds and accepted groups while the neighbor still localizes. Initial English reads and subsequent getter switches are asserted; both preference strings stay unchanged ([reminder_schedule_display_registry_test.dart](../../test/services/reminder_schedule_display_registry_test.dart:178)). Unexpected schedule/cancel sinks fail the read-only path if called.
- **Scheduler integration additions:** production generators for todo/goal/habit/anniversary/countdown; empty authored title; all four active rule kinds; seven weekdays/every-day representation; captured dates/time; nonempty accepted groups; retained snapshot reads with unchanged raw registry contents, identities and sink schedules/cancellations; plus IDs-only generic fallback and template-looking legacy literal records ([reminder_scheduler_integration_test.dart](../../test/services/reminder_scheduler_integration_test.dart:6309)).

These assertions were inspected, not executed by this audit. Root's final serial test/analyzer gate is complete and tied to the reviewed source hashes by the existing logs and summary below. No substantive fixture gap remains from the earlier review. Mounted page/open-sheet repaint and draft/UI state behavior still require separate frontend acceptance; this source review cannot establish them.

### First gate and corrected fixture checkpoint

The preserved [initial summary](registered-display-initial-acceptance-logs/summary.json) records test exit 1, analysis exit 1, and all nine before/after source hashes unchanged. Root reports **188 passing tests and one failed test**, plus one analysis info. The failing parser assertion had incorrectly classified `repeating: true` as invalid; both boolean values are valid facts in the production parser. The analysis info concerned the fixture's conditional map element.

Read-only inspection confirms the repairs: the copy test now explicitly accepts both `false` and `true`, and rejects non-boolean repeating values ([reminder_schedule_display_copy_test.dart](../../test/services/reminder_schedule_display_copy_test.dart:538)); the registry fixture uses `'display_copy': ?descriptor`, preserving the legacy absence behavior ([reminder_schedule_display_registry_test.dart](../../test/services/reminder_schedule_display_registry_test.dart:347)). Both corrections affect tests only. Production hashes still match the reviewed implementation and initial gate. The initial failed gate is not treated as a pass or added to the final test total.

### Completed full rerun evidence

The existing [final tests log](registered-display-final-acceptance-logs/tests.log) ends with `00:10 +189: All tests passed!`. The existing [final analysis log](registered-display-final-acceptance-logs/analyze.log) reports `Analyzing 9 items...` and `No issues found! (ran in 61.6s)`.

The [final summary](registered-display-final-acceptance-logs/summary.json) records the six test files, start `2026-10-11T09:29:27Z`, finish `2026-10-11T09:30:47Z`, `tests_exit_code: 0`, `analysis_exit_code: 0`, and `source_hashes_unchanged: true`. Its nine before/after hash pairs match; the five source/test files reviewed here match the fingerprint table below. This records root's complete rerun of the corrected fixtures, without executing another verification command or combining overlapping test totals.

## Reviewed source fingerprint

| File | SHA-256 |
| --- | --- |
| `lib/services/reminder_schedule_display_copy.dart` | `62ad4ce827ecccd18d0d8ef16090009d5256431b509431aee8fa27d33fb6cf60` |
| `lib/services/reminder_scheduler.dart` | `e0a443c48c825005a09455a61b6d128446d154e7a75a617012f19f402dd704bc` |
| `test/services/reminder_schedule_display_copy_test.dart` | `565cacc3b4b72775929e276ba34930756b5d6df43addd111a30c9f24e4458bd1` |
| `test/services/reminder_schedule_display_registry_test.dart` | `75016577fbe751b9e35d81fb48ee9e6c1c9b6bf7057e67a46dcf4893129a8ea4` |
| `test/services/reminder_scheduler_integration_test.dart` | `893edec8e93e03d8f4e0fd3f0510614d65bafe1f6e138f2af7cf19678e727898` |

The two production hashes were unchanged across repeated reads during this audit. All five hashes above match both the before and after values in root's completed final acceptance summary. The first failed checkpoint remains preserved separately; the completed runtime gate applies to the corrected fixture hashes shown here.
