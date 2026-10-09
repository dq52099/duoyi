# Android widget day-boundary refresh — 2026-10-09

## Implemented

One global, content-free inexact alarm refreshes actual installed native widgets at the next local Gregorian day start or earlier UTC-offset transition. The existing registry supplies all 31 known components; no pending pin flag substitutes for an installed instance. Enable/update/resize/restore/delete/disabled, resume, publication and time/zone broadcasts reconcile the same alarm. The final widget removal cancels it. Delayed delivery calculates the next future boundary from actual delivery time.

The receiver is private, accepts one explicit action, ignores payload, catches dispatch failures and rearms in finally. It starts no Flutter engine, service or network request and writes no publication metadata. It uses no exact-alarm authorization; focus token 14101 is separate from refresh token 14102.

## Executed verification

- 735 Flutter regressions across 50 files passed.
- Focused Dart analysis passed with no issues.
- 13 production-source JVM policy/controller cases passed, including DST, half-hour offset changes, midnight gap/overlap, Apia skipped date, calendar boundaries, delayed delivery, idempotence, deletion and failure retry.
- Android Gradle unit tests passed: the same 13 widget cases and six native reminder copy cases.
- Android arm64 debug APK compiled. SHA-256: `fd2fe9d24178d74bed83ee989731cced82a9426c0dbd7c612f5f781621d49812`.
- Frozen production and fixture hashes stayed unchanged through each acceptance command. See [verification.json](verification.json), check logs and [source-audit.md](source-audit.md).

## Remaining acceptance

Inexact delivery may be delayed by Android/Doze/OEM policies; no midnight punctuality claim is made. Real pin/resize/delete/boot/resume/time-zone behavior, focus coexistence and device timing remain open. Native snapshot live reads and UI commit atomicity are a separately documented existing gap. iOS, global localization, default iOS visual acceptance and device performance requirements remain open.

No public artifact was replaced by this batch. The APK remains private until integrated release delivery.
