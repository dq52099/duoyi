# Registered reminder display acceptance — 2026-10-11

## Accepted scope

New scheduler diagnostic records carry optional, immutable display facts for Todo, Goal, Habit, Anniversary and Countdown. Storage keeps canonical title/subtitle strings; retained snapshot getters render application-owned fragments in the current Chinese/English locale. Explicit `displayFor(locale)` reads leave the global locale alone. Authored titles, including surrounding whitespace, stay literal.

The closed descriptor schema records generic registration, rule cadence/count, habit primary channel/weekdays/time, or the already chosen reminder date/time. No text parsing, locale-driven migration, occurrence recalculation, registration or cancellation is added. Metadata follows preferences, memory, accepted-ID copies, snapshots and reconciliation batches.

Absent or invalid metadata falls back to the original strings. Per-record parser failure preserves the separate IDs, channels and accepted alternatives, and does not discard neighboring records. Both existing preferences keys and account-generation gates remain.

## Final serial verification

The final runner completed at **09:30:47 UTC**, with both commands exiting **0** and all **nine recorded source/test hashes unchanged**. See [summary.json](registered-display-final-acceptance-logs/summary.json), [tests.log](registered-display-final-acceptance-logs/tests.log) and [analyze.log](registered-display-final-acceptance-logs/analyze.log).

| Suite | Passed |
| --- | ---: |
| Display descriptor parser/rendering | 11 |
| Preferences registry and batch propagation | 3 |
| Scheduler integration | 150 |
| Scheduled notification diagnostics | 4 |
| Delivery descriptor regression | 16 |
| Scheduler brand-title contracts | 5 |
| **This run** | **189** |

Scoped analysis of the two changed production files, unchanged delivery descriptor and six suites reports **no issues**. Commands use `/home/ubuntu/flutter/bin/flutter`, `TMPDIR=.dart_tool/task-temp-20261011`, `test --no-pub --concurrency=1 --reporter expanded`, followed by `analyze --no-pub`. The full file lists and hashes are in the summary.

The new fixtures exercise real five-type sync into retained snapshots; four channels and every weekday name; blank-title ownership; unchanged schedule/cancel calls, IDs and accepted groups; initially English cold preferences; byte-for-byte storage invariance; eleven malformed descriptor variants beside two legacy records and a valid neighbor; staged overlay and persisted batch flush.

## Initial results and review

Initial logs remain in [registered-display-initial-acceptance-logs](registered-display-initial-acceptance-logs/summary.json). The first six-suite run had **188 passed / 1 failed** because its new negative fixture wrongly rejected the valid boolean `true`. The test now checks both valid booleans and rejects nonbooleans. One analyzer suggestion in a fixture was also corrected. Those corrections changed tests only; the complete rerun above supersedes their initial results. Earlier production brace suggestions were fixed before that six-suite run.

The separate Sol contract review is [registered-reminder-display-final-contract-review-20261011.md](registered-reminder-display-final-contract-review-20261011.md).

## Remaining goal scope

This accepts the diagnostic data contract. The registered-reminder page and retained detail sheet still need their own locale subscriptions and mounted repaint acceptance under the frontend owner. This run provides no new Android/iOS device, Web build, APK, release or deployment evidence. Widget preview accuracy, Habit live-form copy, Backup latest Undo, remaining route/admin localization, and device smoothness remain open in [goal-coverage-20261011.md](goal-coverage-20261011.md).
