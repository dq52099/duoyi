# Widget store repair review

2026-10-09. Focused source review of the two revised patches only. Document/Envelope were unchanged and were not reread. No broader audit, source edits, tests, SDK commands, Git operations, or network requests.

Both previously reported defects are resolved at source level:

- `DuoyiWidgetPublicationTransition.kt:207–209` now rejects `supersededPresentation` when a publish reuses the current applied presentation revision but changes any retained presentation value. Comparing `clearedValuesFrom` for both complete validated documents preserves all 22 presentation fields while neutralizing the 67 business fields, so legitimate business updates can retain the presentation version.
- `DuoyiWidgetPublicationStore.kt:123–128` now includes `SQLiteDatabase.NO_LOCALIZED_COLLATORS` for both read-only and writable opens. This suppresses the unnecessary Android locale metadata/reindex path before application store validation. The explicit non-destructive corruption handler remains supplied, and PERSIST/FULL enforcement remains limited to writable connections.

No unresolved finding remains from the prior two-defect review. This conclusion covers the inspected source repairs; store/transition are still not bridged/rendered and have no runtime durability, multiprocess, or device proof from this review.

Inspected paths:

- `/home/ubuntu/duoyi-worktrees/widget-store-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPublicationTransition.kt`, lines 199–221.
- `/home/ubuntu/duoyi-worktrees/widget-store-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPublicationStore.kt`, lines 120–145.
