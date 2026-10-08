# Reminder sync copy — 2026-10-08

## Implemented

- Preserve ordered raw diagnostics while carrying immutable owned copy from todo preflight and todo/goal rule aggregate failures into TodoReminderSyncResult and saved-widget feedback.
- Keep the existing virtual String-returning scheduling API. Its returned Future optionally exposes operation-bound metadata; plain override futures still execute once and remain compatible. Both projections capture the result inside serialization, avoiding later map replacement.
- Preserve target-only versus full-list reporting, original raw join order and aggregate throw precedence. Unknown errors remain literal; owned labels/hints translate while original task text remains untouched.
- Keep timeout unconfirmed, reuse the same pending operation for late delivery, and retain account/storage/request guards. Raw/copy getters clear and apply together. The widget selects one locale at guarded frame delivery.

## Verification

- 438 regression cases passed across 24 files; targeted analysis passed for 31 paths. All 35 frozen source/test hashes remained unchanged during final checks.
- New cases cover explicit projections, collector order, mixed preflight/rule throw precedence, typed versus opaque dispatch errors, override compatibility, Future error/timeout forwarding, immutable lists, all 15 object/channel rendering combinations, account/reset/request invalidation and late-empty aggregate compatibility.
- Independent bounded source audit: no remaining blocker; source-audit.md. Commands, hashes and logs: verification.json, regression.txt and analyze.txt.
- First run found a nonexistent enum name in two new fixtures. Only fixture constructors changed to dailyTime; no production workaround or weakened assertions.

## Remaining

Native alarm/popup reasons and habit/anniversary/countdown aggregates still need explicit ownership metadata. Page consumers remain separate work. A disposed-provider callback gap discovered during this audit is being addressed in a separate lifecycle change. Full bilingual routes, Mine/settings flows, default iOS visual acceptance and real Android/iOS device fluency remain open. No new build or deployment in this batch.
