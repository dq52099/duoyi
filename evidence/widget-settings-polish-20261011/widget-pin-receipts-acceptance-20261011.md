# Widget pin receipt isolation — 2026-10-11

## Accepted change

At parent HEAD `391eb4f4580182525003403e5097fe4a56265249`, each Flutter catalog button can request a pin independently, while Android previously stored only the most recent receipt. If callbacks A and B arrived before A's next 700 ms poll, B replaced A and A could time out despite placement. This is a source-confirmed interleaving, not a recorded launcher reproduction.

The receiver now writes six fields under a length-delimited namespace containing the complete request ID. `MainActivity` reads and clears through the same `DuoyiWidgetPinResultStore`. Clearing A preserves B and unrelated preferences. The store prefers a complete matching new record, then reads the matching legacy single slot. Missing legacy fields keep their original defaults: empty strings, Android invalid widget ID **0**, and timestamp **0L**. Malformed new records do not throw or affect neighboring requests.

Callback intents now use `Uri.Builder.appendPath(requestId)` to give each full ID a distinct `PendingIntent` data identity, including IDs whose Java hash codes collide. Existing extras and callbacks without data remain supported. Success and `confirmed_unverified`, style initialization, the two-minute wait, 700 ms polling, late callbacks, cancellation, and pending-provider TTL are unchanged.

## Verification inspected

Operations ran serially with no concurrent Flutter/Gradle build.

| Scope | Result | Evidence |
| --- | --- | --- |
| Kotlin/JVM runtime | **58 passed**, including **11 new** store tests; compiler and JUnit exit 0; 14 input hashes matched | `widget-pin-receipts-jvm-acceptance-logs/{01-kotlin-compile.log,02-junit.log,runner-summary.json}` |
| Flutter regressions | **92 passed** across eight suites; nine-item analysis has no issues; 17 input hashes matched; finished 10:22:05 UTC | `widget-pin-receipts-flutter-acceptance-20261011/{summary.json,analyze.log,sources-before.json,sources-after.json}` and individual logs |
| Android platform compilation | Exit 0 at **10:30:16 UTC**; 488.114 seconds; **208 tasks: 203 executed, five up to date**; 277 input hashes matched | `widget-pin-receipts-platform-compile-20261011/{compile.log,summary.json,sources-before.json,sources-after.json}` |

Platform outputs include all **36** manifest-declared widget components and MainActivity, plus the receipt core, record, store, and existing bridge classes: **44 required classes**, all present with hashes. A final union recheck matched **285** accepted inputs against the working tree.

The eleven new tests call the production store with a writable in-memory `SharedPreferences` fake. They cover both receipts before polling, selective clearing, different styles, clear-then-late A, `Aa`/`BB` Java hash collisions, legacy defaults and precedence, every field missing or mistyped, mismatched embedded IDs, healthy neighbors, adapter reconstruction, blank IDs, and unverified confirmations. Reconstruction simulates restoring a snapshot; it does not execute a real process restart or disk write.

The platform command remains `./gradlew :app:compileDebugKotlin --offline -x :app:compileFlutterBuildDebug --max-workers=1 --no-daemon -Dorg.gradle.jvmargs=-Xmx2G --console=plain`, with the existing task-specific Gradle cache. Existing deprecation/copy-visibility warnings remain in the logs.

## Remaining boundaries

No APK, release, version bump, push, deployment, device, or Xcode execution occurred. JVM behavior, static production wiring, and compilation do not establish real launcher callbacks, resizing, visual fidelity, or smoothness.

Receipt retention remains unfinished: a page can close before consuming a result, or a callback can arrive after polling ends. The new namespaces preserve those receipts indefinitely until explicitly cleared; the old slot was naturally limited to one. This is an identified storage lifecycle regression requiring a separate bounded-retention change before delivery. See `widget-pin-receipt-retention-decision-20261011.md`. Android count-up display also lacks the app/iOS 24-hour cap; its source contract is recorded separately.

The full widget/default-iOS/global-localization/Mine/settings/smoothness goal remains active and incomplete.
