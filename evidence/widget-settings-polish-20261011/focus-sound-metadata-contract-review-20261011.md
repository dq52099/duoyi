# Focus sound metadata contract review — 2026-10-11

## Scope and decision

Read-only review of the current `FocusSoundCatalog` working-tree diff and confirmation of the existing domain-enum display labels, against checkout `HEAD 7617104`. This audit writes only this report. It does not run Flutter, Gradle, builds, browser checks, or AGY, and makes no production/test edits or Git delivery.

**Accepted within this scope:** the sound-catalog change localizes presentation metadata while preserving sound selection, playback and storage contracts. No blocker was found in the reviewed metadata diff. **Withdraw the earlier implementation suggestion for the four domain enums:** their display getters are already localized; no new `labelFor` API or model edit is needed for this requirement.

## Existing enum localization requires no change

| Actual enum | Existing display implementation | Bilingual dictionary evidence |
| --- | --- | --- |
| `TodoPriority` (5 cases) | `.label` uses `I18n.tr('todo.priority.*')` ([todo.dart](../../lib/models/todo.dart:19)). | Chinese keys at [i18n.dart](../../lib/core/i18n.dart:906), English keys at [i18n.dart](../../lib/core/i18n.dart:2101). |
| `CalendarEventType` (10 cases) | `.label` uses `I18n.tr('calendar_event.*')`; the actual enum is `CalendarEventType` ([calendar_event.dart](../../lib/models/calendar_event.dart:7)). | Chinese keys at [i18n.dart](../../lib/core/i18n.dart:122), English keys at [i18n.dart](../../lib/core/i18n.dart:1246). |
| `TimeEntrySource` (5 cases) | `.label` uses `I18n.tr('time_entry.source.*')` ([time_entry.dart](../../lib/models/time_entry.dart:12)). | Chinese keys at [i18n.dart](../../lib/core/i18n.dart:144), English keys at [i18n.dart](../../lib/core/i18n.dart:1270). |
| `TimeEntryCategory` (8 cases) | `.label` uses `I18n.tr('time_entry.category.*')` ([time_entry.dart](../../lib/models/time_entry.dart:22)). | Chinese keys at [i18n.dart](../../lib/core/i18n.dart:149), English keys at [i18n.dart](../../lib/core/i18n.dart:1275). |

All cases have Chinese and English entries. `I18n.tr` chooses the dictionary from the current locale on every read ([i18n.dart](../../lib/core/i18n.dart:2397)); none of these getters stores a Chinese result. The three model files have no working-tree diff at review time.

Their stored contracts remain independent of display labels: Todo priority uses its enum index ([todo.dart](../../lib/models/todo.dart:233)), calendar event type uses `.name` ([calendar_event.dart](../../lib/models/calendar_event.dart:134)), and TimeEntry category/source use indices, with index/name readers ([time_entry.dart](../../lib/models/time_entry.dart:105)). This narrowed review does not reopen the earlier full AI/import/export/widget-consumer audit.

## Sound metadata diff

- `FocusSoundTrack` and `FocusSoundOption` retain the required named `label` constructor argument and `const` constructors. They store the authored value privately, add an optional English value, and expose the same readable `.label` API through a getter ([focus_sound_catalog.dart](../../lib/core/focus_sound_catalog.dart:3), [focus_sound_catalog.dart](../../lib/core/focus_sound_catalog.dart:25)). Existing constructors without `englishLabel` preserve their authored text in either locale; there is no translation inferred from the ID.
- `.label` follows `I18n.current`. `displayLabel(locale:)` and `FocusSoundCatalog.labelFor(sound, locale:)` allow an explicit locale without changing the global locale ([focus_sound_catalog.dart](../../lib/core/focus_sound_catalog.dart:19), [focus_sound_catalog.dart](../../lib/core/focus_sound_catalog.dart:438)). Retained metadata objects therefore return the new display label on the next read, without replacing the const lists or changing selected IDs.
- The published lists remain **28 tracks and 29 options**: `none` plus one option for each track. All published entries have an English label; corresponding track and option labels agree ([focus_sound_catalog.dart](../../lib/core/focus_sound_catalog.dart:55), [focus_sound_catalog.dart](../../lib/core/focus_sound_catalog.dart:226)). The diff adds translations and formatting while retaining Chinese labels, track/option order, IDs, asset paths and `trackIds`.
- `optionFor` fallback copies `track._label` and `track._englishLabel`, rather than capturing `track.label` in whichever language was active during construction ([focus_sound_catalog.dart](../../lib/core/focus_sound_catalog.dart:452)). A retained fallback such as `optionFor(' rain ')` can therefore follow zh → en → zh correctly.
- Unknown, rejected legacy, or unsupported mix IDs still produce an absence display label; the fallback now uses the localized `none` option. The diff does not change `normalizeForPlayback`, `trackFor`, `trackIdsFor`, `assetsFor`, or `assetMap` ([focus_sound_catalog.dart](../../lib/core/focus_sound_catalog.dart:407), [focus_sound_catalog.dart](../../lib/core/focus_sound_catalog.dart:442)). Playback still resolves IDs to asset/file paths rather than consuming labels ([focus_sound_service.dart](../../lib/services/focus_sound_service.dart:130)).
- Persisted selections remain raw sound IDs in Pomodoro config/session `whiteNoiseSound` and goal/todo `FocusLink.whiteNoise` ([pomodoro.dart](../../lib/models/pomodoro.dart:61), [pomodoro.dart](../../lib/models/pomodoro.dart:322), [goal.dart](../../lib/models/goal.dart:486)). Catalog display labels are not added to these records. The catalog diff changes no screen, provider, model serialization or playback service.

## Compatibility boundaries

1. **Display reads still need a UI rebuild.** The getter change cannot itself repaint an existing `Text`. The Pomodoro screen listens to locale changes ([pomodoro_screen.dart](../../lib/screens/pomodoro_screen.dart:446)); Goal's focus section watches the custom-sound provider, and the open sound picker/session editor have no direct locale subscription ([goal_edit_screen.dart](../../lib/screens/goal_edit_screen.dart:1474), [pomodoro_screen.dart](../../lib/screens/pomodoro_screen.dart:38), [pomodoro_screen.dart](../../lib/screens/pomodoro_screen.dart:1420)). Mounted route refresh and draft preservation remain frontend work; this metadata review does not accept those flows.
2. **Authored custom names remain literal.** `CustomFocusSound.label` is a separately persisted field derived from the imported filename. Missing/blank custom metadata still has the existing Chinese fallback `自定义音频` ([custom_focus_sound_provider.dart](../../lib/providers/custom_focus_sound_provider.dart:24), [custom_focus_sound_provider.dart](../../lib/providers/custom_focus_sound_provider.dart:55), [custom_focus_sound_provider.dart](../../lib/providers/custom_focus_sound_provider.dart:178)). That fallback is outside this catalog diff; custom names must not be translated as built-in labels.
3. **A localized label is presentation text, not a stable key.** Retaining a resolved string freezes its current wording; retaining the metadata object allows a fresh getter read. Existing selection/storage/playback consumers use IDs. Any future operation requiring a single fixed output language should use the explicit locale argument and continue storing IDs.

These boundaries do not require adding APIs to the already localized domain enums, and they do not establish global locale acceptance.

## Existing acceptance evidence

The root's [acceptance summary](focus-sound-metadata-final-acceptance-logs/summary.json) records a serial six-suite run and six-item analysis, both exit 0. The [test log](focus-sound-metadata-final-acceptance-logs/tests.log) ends with **43 tests passed**; the [analysis log](focus-sound-metadata-final-acceptance-logs/analyze.log) says `No issues found!`.

The six suites are the catalog, playback service, Pomodoro focus-room static wiring, goal-editor static wiring, Pomodoro config, and custom-sound static contract suites. New catalog checks cover retained zh → en → zh objects, explicit locale without global mutation, fallback metadata, invalid IDs, literal untranslated metadata, and unchanged normalization/assets ([focus_sound_catalog_test.dart](../../test/core/focus_sound_catalog_test.dart:122)).

Read-only SHA-256 checks during this review match all six recorded before/after values: catalog, its test, Pomodoro model, custom-sound provider, Pomodoro screen and goal editor. In particular, catalog hash is `2c2f7a8f3b7ad83243a112820c5883d75dd2075531ca3bf83db9609b8ed1028e`; test hash is `6f8304a4853a81dc5618508905dffa45c56c753103c98d582f56925ab9bc0a34`. This audit reruns no tests and makes no device, open-route or full-project acceptance claim.

The broader [consumer inventory](focus-sound-metadata-consumer-inventory-20261011.md) remains the reference for persistence, backup and frontend follow-up details.
