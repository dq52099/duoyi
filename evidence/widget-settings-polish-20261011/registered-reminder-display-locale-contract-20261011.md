# Registered reminder display locale contract — 2026-10-11

## Scope and conclusion

Read-only audit of scheduler diagnostic display records, registry persistence, retained snapshots, and their title/subtitle consumers. The inspected checkpoint is `HEAD f873d65`; scheduler source hash is `519f3ad4cb34ded9ac1ee7eae161fd179712d4f6b8fa03913e8bbe84c2d3db30`. Only this report is written. No production/test edit, test/build/browser/AGY/deploy command or worktree creation is performed.

**The data-layer gap is real.** App-owned diagnostic text is rendered once into Chinese strings and retained in memory/preferences. A fresh snapshot or UI rebuild cannot translate those strings. Root can fix this independently with an optional typed display descriptor and lazy snapshot rendering. No implementation blocker was found in the reviewed data flow. Page and open-sheet locale subscriptions remain AGY-owned; this report does not accept mounted UI behavior or global bilingual coverage.

The registry's actual source name is `SharedPreferencesReminderScheduleRegistry` ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:470)).

## Current source evidence

- Both `ReminderScheduleDisplayInfo` and `ReminderScheduleSnapshotEntry` contain final rendered `title`/`subtitle` strings and no semantic display metadata ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:79)).
- `_snapshotDisplayFor` prioritizes the scheduler's `_registeredReminderDisplay` cache, then persisted display, then scheduled-rule display, then a generic app-owned fallback. `_registeredRemindersSnapshotLocked` copies the chosen strings into the retained entry ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1491), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1528)).
- Todo/goal rule displays choose the first nonempty trimmed `rule.body` as the title. That body comes from the user-authored todo/goal title; the rule resolvers preserve it independently of notification-title rendering ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1564), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1649), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:5231), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:5448)). Their subtitles assemble Chinese object type, cadence, kind labels and rule count.
- `_rememberReminderDisplay` caches normalized strings. Habit captures primary kind, weekdays and time into a Chinese subtitle; anniversary/countdown capture kind and reminder date/time into Chinese subtitles ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1587), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1862)). These facts are available at creation, so text parsing is unnecessary.
- Preferences keep separate ID and display keys: `reminder_scheduler_registry_v1` and `reminder_scheduler_display_registry_v1`. Display decode currently validates strings, trims them, and decodes `kinds`/`accepted_id_sets`; display write stores those strings and typed sets ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:472), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:671), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:783)). ID decode/write is a separate path ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:635), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:718)).
- Both the row and detail sheet call the same display helpers. These read `entry.title.trim()` and `entry.subtitle.trim()` and return any nonempty value immediately ([notification_history_screen.dart](../../lib/screens/notification_history_screen.dart:2152), [notification_history_screen.dart](../../lib/screens/notification_history_screen.dart:2438), [notification_history_screen.dart](../../lib/screens/notification_history_screen.dart:4469)). The page retains the entry list after loading ([notification_history_screen.dart](../../lib/screens/notification_history_screen.dart:2800), [notification_history_screen.dart](../../lib/screens/notification_history_screen.dart:2967)). Rendering only at snapshot-fetch time would therefore still leave retained entries stale after a locale change.

## Minimal data-layer API

Recommended separation, with names illustrative:

1. **Storage/cache record:** retain `ReminderScheduleDisplayInfo.title` and `.subtitle` as canonical strings. Add optional immutable `ReminderScheduleDisplayCopy? displayCopy`. Keep existing constructor arguments, `kinds`, `acceptedIdSets` and registry methods compatible. The preferences writer can continue reading the canonical fields; it must never persist localized snapshot getters.
2. **Snapshot:** keep the existing `ReminderScheduleSnapshotEntry(title:, subtitle:, ...)` constructor interface, store those inputs privately as raw strings, and add the optional descriptor. Expose the existing `.title`/`.subtitle` names as lazy getters that render valid metadata with `I18n.current`, otherwise return the original strings. Existing UI consumers then obtain localized text on their next read without a layout change or a second scheduler load.
3. **Renderer:** optionally expose an explicit `displayFor(AppLocale)` returning a title/subtitle pair. Resolve the locale once per pair; do not change `I18n.current`, notify providers, touch preferences, query pending queues or invoke scheduling. User content comes from the canonical title, never from a translation dictionary.

The descriptor should own only the application-generated display fragments. A retained literal title remains the literal title; an explicitly tagged app-generated default title can render as a localized `<subject> reminder`. Record that distinction at creation from the source facts, including whether the selected user body/name is empty. Never decide ownership by comparing a title/subtitle with Chinese phrases.

The existing decoder's trimming is a separate normalization behavior. To preserve original stored strings, validate emptiness using `.trim()` but retain the original string values in the storage record; rendering or a locale switch must not rewrite them. The current UI helpers may still trim their rendered output. This is a preservation requirement for the data layer, not a request to edit those helpers.

## Typed descriptor facts and JSON contract

Add a single optional nested field such as `display_copy` under the existing display record. Keep both registry keys, outer object maps, original `title`/`subtitle`, `kinds`, and `accepted_id_sets`. There is no locale field and no migration triggered by reading or changing locale.

Use a closed set of descriptor shapes rather than a general template/expression language:

| Shape | Allowed subject | Required facts | Rendering ownership |
| --- | --- | --- | --- |
| `registered` | todo, goal, habit, anniversary, countdown | Subject; app-default title mode. | Generic title and “registered with the system reminder queue” subtitle. |
| `rules` | todo, goal | Subject; literal/default title mode; `repeating: bool`; positive `ruleCount: int`. | Subject, one-shot/repeating wording, rule count and localized kind names. The actual typed outer `kinds` set supplies kinds, avoiding a duplicate channel-state field. Empty kinds retain the current “system reminder” display fallback. |
| `habit` | habit | Literal/default title mode; primary kind; weekdays; valid local time or explicit unset time. | Habit subject, primary kind, weekday names/every-day wording and time-not-set wording. The primary kind is separate from the outer set because a multi-rule habit currently displays its primary rule while retaining all enabled kinds. |
| `dated` | anniversary, countdown | Subject; literal/default title mode; kind; captured local date/time. | Subject and kind labels around the existing date/time facts. No date is recomputed at display time. |

For example, a new todo display can retain its current Chinese subtitle and attach:

```json
{
  "schemaVersion": 1,
  "shape": "rules",
  "subject": "todo",
  "titleMode": "literal",
  "repeating": false,
  "ruleCount": 2
}
```

The descriptor does not need a second copy of user text, object IDs, accepted ID groups, pending status, rule fingerprints or touch payload. It renders against the storage record's canonical title and typed outer kinds. Fact lists must be immutable after creation/decode.

### Strict optional parser

The parser must return either a fully validated typed descriptor or `null`, without throwing into the whole-registry decoder:

- Require a map with exactly the allowed keys for that shape. Reject unknown schema versions, shape/subject/title-mode strings, missing keys, non-string keys, unsupported extra keys and invalid shape/subject combinations. Match the descriptor subject to its outer registry object type.
- Require exact JSON types: integer version/count/date/time values and actual booleans. Do not coerce strings, floating-point numbers or booleans into integers. Bound counts to positive exact JSON integers; enum names must be explicitly recognized.
- For habit/dated primary kinds, accept active kind names (`push`, `popup`, `alarm`, `email`); reject unknown/off values. Parsing failure must not modify the separately decoded outer `kinds` set.
- Weekdays are a list of unique integers 1–7, with at most seven elements; empty or the valid full week renders every day, matching the existing display convention. Reject invalid elements rather than silently filtering them.
- Local time is a complete valid hour/minute pair (0–23, 0–59), or an explicit unset representation. A creator with invalid/unset source time can emit the unset variant; a malformed stored pair cannot be normalized into a different time.
- Capture date/time as validated local components (year/month/day/hour/minute), with a real calendar date and valid clock time. Reject impossible dates rather than relying on `DateTime` constructor/parse rollover. Rendering must not convert timezone, recalculate the next occurrence, or consult `DateTime.now()`.
- Invalid/absent metadata returns literal title/subtitle for that one valid base display record. It must not cause the inner record to be skipped or the outer `_readDisplayAll` catch to return an empty map. Other records, IDs, kinds and accepted groups remain readable.

The nearby `ReminderDeliveryCopy.tryFromJson` demonstrates the existing exact-key/version/type validation style ([reminder_delivery_copy.dart](../../lib/services/reminder_delivery_copy.dart:81)); its delivery facts and renderer should remain a separate contract. Diagnostic metadata cannot alter delivery semantics.

Legacy records without metadata remain literal in every locale, including Chinese strings that exactly resemble current application templates. Unknown or malformed descriptors use the same literal fallback. An ordinary later save/reconciliation with trusted domain objects may create new metadata through the normal display builders; locale switching must not migrate, infer, re-register or repair legacy records.

## Required propagation points

| Source point | Required change or preservation |
| --- | --- |
| Snapshot/display types ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:79)) | Add optional descriptor; retain raw storage strings and lazy snapshot reads. Preserve the const constructor interface and all identity/channel fields. |
| `_readDisplayAll` ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:671)) | Parse the optional descriptor independently per record, retain valid base strings/kinds/accepted groups on descriptor failure, preserve raw string values. |
| `_writeDisplayAll` ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:783)) | Persist canonical strings plus descriptor facts; avoid rendering. Keep all existing outer fields and account-generation checks. |
| `_registeredRemindersSnapshotLocked` ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1506)) | Copy raw strings **and** descriptor from the selected display into the snapshot. Do not resolve the locale while constructing the snapshot. |
| `_snapshotDisplayFor` and `_registryDisplayFor` ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1528), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1614)) | Preserve existing cache/persisted/rules precedence. Attach typed `registered` facts only to newly generated generic fallback records. A legacy preferred cache record must not borrow metadata from a different persisted display. |
| `_displayFromScheduledRules` / `_displayFromResolvedRules` ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1564), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1649)) | Capture title ownership, repeating flag and list count at the same point that currently produces the canonical strings. Carry the existing kinds and normalized accepted groups unchanged. |
| `_rememberReminderDisplay` ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1587)) | Accept/carry optional typed metadata into `_registeredReminderDisplay`; keep title/subtitle canonical and retain existing kind filtering. |
| Three `_remember*ReminderDisplay` methods ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1862)) | Supply habit/dated facts directly from the domain object, primary rule and already chosen reminder time. Mark empty user titles as app-default explicitly. |
| `_withAcceptedIdSets` ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1672)) | Copy the descriptor while preserving raw strings/kinds and current accepted-group normalization. Otherwise the normal nonempty accepted-ID path would strip metadata. |
| Registry replace/batch/cache chain ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:500), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:547), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:893), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1101)) | These paths already pass/store the whole `ReminderScheduleDisplayInfo`. Verify they retain the new field through replace, staged mutation, overlay and flush. No ID algorithm change is needed. |

Account cleanup, removal, and interrupted-batch cancellation ownership remain as they are. In particular, `_persistInterruptedBatchOwnership` intentionally commits IDs without old displays ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1457)); adding metadata must not change that policy.

## Invariants

- Reading display getters or changing locale performs no registration, cancellation, retry, preference write, pending-queue probe or scheduling side effect.
- Original title/subtitle strings and descriptor JSON are locale-independent. Across zh → en → zh reads, both preference values remain byte-for-byte unchanged after their initial legitimate save.
- Object types/IDs/order, notification IDs, accepted alternatives, kinds and account-generation boundaries stay unchanged. Queue-health classification consumes those fields ([notification_history_screen.dart](../../lib/screens/notification_history_screen.dart:2312)); metadata must never replace them.
- `_ScheduledRule`, `_ResolvedRule`, fingerprint/intent/delivery comparison, scope and dispatch payload stay separate from diagnostic rendering ([reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:363), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:1217), [reminder_scheduler.dart](../../lib/services/reminder_scheduler.dart:5624)). Do not insert locale, rendered diagnostic strings or display metadata into those comparisons.
- Scheduled times, local weekday/time facts and object-opening payloads (`duoyi://...`) remain unchanged. Display metadata uses captured facts and cannot recalculate scheduling.

## Suggested acceptance for root's implementation

These are proposed checks; none were added or run by this audit.

| Check | Required result |
| --- | --- |
| Retained memory snapshot | Create/sync under zh, retain the same entry/list, switch en then zh without another snapshot fetch. Newly owned title/subtitle fragments follow the locale; user titles remain literal; IDs/groups/kinds stay identical. |
| New generic fallback | Seed only IDs for each supported object type. Snapshot creates typed app-owned generic copy; the same retained entry follows locale changes with no registry write or scheduling call. |
| Todo/goal rule groups | Cover one-shot, repeating and mixed kinds, empty user title and nonempty literal title. Count/cadence/kind copy localizes; blank-title fallback is tagged at creation. Rule fingerprints and pending identity remain unchanged. |
| Habit facts | Cover daily/full-week, selected weekdays, multi-rule primary kind, valid/unset time and primary-vs-all kinds. Weekdays/time/kind facts and outer queue kinds stay stable. |
| Dated facts | Cover anniversary/countdown and all active kinds. The captured local date/time remains identical after locale switches; no next-occurrence recalculation or timezone shift occurs. |
| Cold preferences snapshot | Save new metadata, create a fresh scheduler/registry without warming its in-memory display cache or resyncing objects, read a snapshot and retain it through zh → en → zh. Both initial English read and subsequent retained reads localize. |
| Storage invariance | Capture both registry preference strings, decoded object maps, canonical display strings, kinds and accepted groups. Locale changes and snapshot reads leave them byte-for-byte/structurally identical. A legitimate round trip preserves raw string values and valid descriptor facts. |
| Legacy literal preservation | Seed a title/subtitle with no metadata, including strings exactly matching current Chinese templates, mixed Chinese/English text, emoji/punctuation and surrounding whitespace. Raw strings stay preserved; no inferred descriptor is attached and no locale-driven migration occurs. |
| Malformed optional metadata | For each unknown/missing/extra schema field, wrong JSON type, invalid count/kind/date/time/weekday, and outer subject mismatch, retain the same valid base display, IDs, accepted groups and kinds. Neighboring valid entries still decode/localize. No exceptions escape into whole-registry fallback or trigger retry/re-registration. |
| Copy/batch propagation | Exercise nonempty accepted groups through `_withAcceptedIdSets`, in-memory registry, preferences replace, staged batch overlay and flush. Each resulting snapshot retains the descriptor and raw fields; stale-account/interrupted-batch ownership behavior is unchanged. |
| Side-effect/fingerprint boundary | Record sink scheduling/cancellation calls and storage writes before display reads. Switching locale and reading snapshots produces no new calls; existing registration, cancellation debt, retry decisions, timings and `duoyi://...` payloads remain intact. Existing delivery-copy locale tests remain their own separate coverage. |

Existing scheduler integration tests cover sorted snapshots, user title and kind exposure, immutable ID lists, and accepted/cancellation behavior ([reminder_scheduler_integration_test.dart](../../test/services/reminder_scheduler_integration_test.dart:1011), [reminder_scheduler_integration_test.dart](../../test/services/reminder_scheduler_integration_test.dart:2250)). They do not demonstrate the new lazy-display or cold-preferences contract.

## Delivery boundary

Root can implement the descriptor, parser, storage/cache propagation and lazy snapshot getters within services/data types. The current UI getter interface can be retained. AGY still owns page/detail-sheet locale listeners and UI fallback/chrome copy; those need their own mounted-route acceptance later. This report supplies the data contract and identifies the current missing capability; it does not claim that either implementation or UI acceptance is complete.
