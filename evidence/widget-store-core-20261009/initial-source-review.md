# Widget store implementation review

2026-10-09. Bounded source review of the frozen Android Document, Envelope, Transition, and Store. No source edits, tests, SDK commands, Git operations, or network requests. The two findings below refer to the frozen implementation supplied for this review; root has acknowledged both and plans fixes.

## Actionable defects

### P1: publish can replace presentation values without advancing their version

Source: `DuoyiWidgetPublicationTransition.kt:201–208`.

Publish verifies owner, publication sequence, desired revision, and locale, but does not check the 22 presentation values when reusing the current document's applied presentation revision. With desired=applied revision R, a caller can submit publication N+1 with changed theme/brand at the same R, then submit an older complete theme as N+2 at R. Both are accepted; the complete-presentation fence cannot detect the obsolete theme.

Fix: when incoming document.presentationRevision equals current document.presentationRevision, require equality of the complete sanitized presentation snapshots, using `clearedValuesFrom` on both sets of values. Continue allowing changed business data and state at that revision. Existing open/invalidate already perform the analogous check in `acceptsPresentation`.

### P2: writable open can modify Android locale metadata before store validation

Source: `DuoyiWidgetPublicationStore.kt:122–134`.

The flags omit `SQLiteDatabase.NO_LOCALIZED_COLLATORS`. Android's writable SQLite connection initialization can create/update `android_metadata` and perform localized reindexing during `openDatabase`, before this code validates the existing schema/envelope or confirms PERSIST/FULL. An unsupported existing store can therefore receive an implicit metadata transaction even though the mutation is subsequently rejected.

Fix: include `NO_LOCALIZED_COLLATORS` in all open flags. This raw JSON store uses no localized indexes and does not need Android locale metadata. Keep the custom non-destructive corruption handler.

## Other reviewed boundaries

No additional actionable defect was found in the bounded read:

- Strict parsed request shapes, normalized exact Int/Long values, and immutable owned maps support the native tagged SHA-256 digest. Sorted map keys and UTF-16 code units preserve literal strings and make numeric channel representations equivalent without granting caller authority.
- Receipt replay precedes CAS/time checks and native token issuance. Replays preserve original metadata and do not create a replacement. Changed content under the same operation ID is rejected.
- Existing-store CAS checks exact epoch/revision; absent initialization alone permits null expectations. Initialize/resume/invalidate perform the required epoch/lease/binding changes, and revisions cannot wrap. Fresh identical desired advances are rejected as the chosen policy.
- Publish uses the declared acceptance policy: current same civil day and current zone offset at both capture and acceptance, with no future capture. Historical document decode remains independent of that policy.
- The fixed lock is never replaced/deleted by this code. Initialization reconfirms absence after exclusive acquisition. Existing DB plus missing lock fails closed. The process gate precedes file lock/SQLite, and callback reentry cannot take the gate again.
- Writers explicitly confirm PERSIST and FULL. Read-only connections are correctly not required to report PERSIST, since journal mode can differ across new connections. The custom corruption handler avoids Android's default delete behavior, and the DB/journal/lock live together under noBackupFilesDir.
- The full replacement and receipt share the transaction. `endTransaction` completes before acknowledgement; a fresh connection reads back the exact canonical envelope under the retained exclusive operation lock. Commit/readback uncertainty quarantines current-process writes. Corrupt/unsupported/unavailable stores are not reinitialized or replaced with defaults.
- Final snapshot acceptance tries the gate and shared file lock without waiting, uses SQLite busy timeout 0, compares fresh complete canonical facts, and holds gate/file lock through the synchronous callback. Callback failure rejects acceptance. This supports the approved final acceptance boundary when its caller supplies the remaining frame checks.

## Remaining integration, outside these source defects

Bridge registration and background dispatch, Dart generation/auth bootstrap and cleanup barrier, caller reconciliation of the presentation floor, Android frame capture/final main-thread checks and accepted effects, alarms/reconcile, iOS storage/readers, and platform evidence remain unwired. Their absence is not counted as a defect in this isolated store implementation. `acceptSnapshot` callers must execute synchronous UI submission on the main looper and check clock/offset/options/system locale/style/expiry before accepting; the callback must not defer the actual submission until after it returns.

The source audit is not a SQLite crash/durability, multiprocess, device, or end-to-end execution result. Root separately reported successful native compilation and ten existing Document tests; those do not establish store/transition runtime behavior.

## Sources

- `/home/ubuntu/duoyi-worktrees/widget-store-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPublicationTransition.kt`.
- `/home/ubuntu/duoyi-worktrees/widget-store-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPublicationStore.kt`.
- Same directory: `DuoyiWidgetPublicationDocument.kt`, `DuoyiWidgetPublicationEnvelope.kt`.
- Approved contract documents: `/home/ubuntu/duoyi/evidence/widget-publication-descriptor-20261009/native-store-implementation-plan.md`, `/home/ubuntu/duoyi/evidence/widget-publication-descriptor-20261009/wire-schema-audit.md`.
