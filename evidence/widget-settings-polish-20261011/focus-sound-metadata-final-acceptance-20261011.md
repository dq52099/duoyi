# Focus sound metadata acceptance — 2026-10-11

## Implemented scope

The shared catalog now supplies English names for all **28 built-in recordings and 29 selection options**, including the disabled option. Retained track/option objects read the current locale when their display name is requested; callers can explicitly select a display locale without changing the global locale.

The original Chinese metadata is retained. IDs, option order, audio assets, playback normalization, unsupported mixes, and configuration serialization are unchanged. An entry without explicit translated metadata retains its supplied literal name. The one-track fallback also retains both language variants instead of capturing the current translated name at construction.

This is shared metadata work. No Pomodoro, Goal editor, custom sound provider, layout, modal, or action implementation was edited.

## Completed verification

One serial Flutter command ran six suites with `--no-pub --concurrency=1 --reporter expanded`:

| Suite | Passed |
| --- | ---: |
| Focus sound catalog | 13 |
| Focus sound service | 7 |
| Pomodoro focus-room source checks | 3 |
| Goal editor existing checks | 10 |
| Pomodoro configuration | 9 |
| Custom sound source contract | 1 |

**43 tests passed, exit 0.** The earlier 33-test observation is included in this rerun and is not additional coverage. The six new catalog cases cover retained zh → en → zh labels, explicit locale rendering, fallback objects, invalid/mix IDs, literal metadata, and unchanged normalization/assets.

The subsequent six-item scoped analyzer completed with **no issues, exit 0**. All six recorded source/test hashes matched before and after both commands. Exact commands, exits, outputs, and hashes are retained in `focus-sound-metadata-final-acceptance-logs/`.

Catalog SHA-256: `2c2f7a8f3b7ad83243a112820c5883d75dd2075531ca3bf83db9609b8ed1028e`.
Catalog test SHA-256: `6f8304a4853a81dc5618508905dffa45c56c753103c98d582f56925ab9bc0a34`.

## Consumer and acceptance limits

`focus-sound-metadata-consumer-inventory-20261011.md` confirms storage/backup/cloud model records carry sound IDs, while custom sound names remain separate authored metadata. Playback consumes IDs/assets rather than catalog display names.

The Pomodoro main page already listens for locale changes. Goal editing and open Pomodoro picker/session-editor modals lack their own explicit locale invalidation; this data fix makes names correct when read, but does not establish their live route repaint. Those consumers remain frontend follow-up. Custom audio files are not transferred by preference-only backups/cloud sync; this pre-existing completeness gap is not repaired here.

No native audio/device acceptance, build, push, new APK/version, or deployment was performed. Full Focus and global bilingual acceptance remain open.
