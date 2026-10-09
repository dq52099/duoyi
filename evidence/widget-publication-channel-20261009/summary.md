# Android widget publication channel — 2026-10-09

## Implemented

Engine-scoped `duoyi/widget-publication` registration exposes native read/open/invalidate/advance/publish operations. A bounded serial worker handles parsing, hashing and storage. Detached messengers cannot consume stale callbacks; committed mutations retain their native receipt. The store uses application context and reads never disclose the writer lease.

## Verification

Existing Android `:app:testDebugUnitTest` completed successfully: 79 tests, zero failures/errors. The application Kotlin and Java sources, including MainActivity plugin registration, compiled in that run. Source hashes before/after and current files match. This task did not assemble an APK. The five publication sources also passed standalone Kotlin compilation and the existing 10 document fixtures; a bounded bridge source review found no actionable defect.

The initial attempt could not launch Gradle because the isolated worktree lacked its ignored wrapper; wrapper and SDK configuration were restored from the main checkout before the successful rerun. No signing material was copied.

## Remaining

Flutter publisher/bootstrap/clear barrier, canonical Android renderer and the iOS equivalent remain to be connected. Mutation acknowledgements currently report `refreshRequested: false`; they confirm storage only. Existing unit tests do not establish SQLite runtime durability, process contention, crash recovery, engine detach behavior or launcher display. Device acceptance remains open.
