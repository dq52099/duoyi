# Native reminder locale foundation — 2026-10-09

## Implemented

- Android reminder chrome uses the selected Chinese/English app language for status, stop, snooze, detail, content labels and dates. Nonblank user title/body text remains literal.
- Dart registration snapshots locale before asynchronous initialization and carries it through all native calls/retries. Native show/once/daily registrations reject explicitly unsupported locale values; omitted legacy values retain Chinese behavior.
- Locale travels through saved JSON, receiver delivery, daily successor, reboot restore, fullscreen reuse, fallback notification, snooze and automatic repeat. Timing, IDs, action/channel identity and reminder options retain existing behavior.

## Verified scope

- 725 regressions across 49 files passed; analysis of 62 Dart paths reported no issues. Source hashes remained unchanged through each run.
- Six production-helper JVM cases passed, covering native strings, exact language-code fallback, literal user text, blank/matching body handling and date formatting independent of JVM default locale.
- Dart MethodChannel tests execute the real show/once/daily bridge and assert explicit/default locale plus original registration arguments. Receiver/restore/snooze propagation is source-contract coverage, not real Android delivery.
- Android debug APK compiled. SHA-256: `66b15372f18c0fb8f74731a6a5d880d6fb29093218278e3cb7e8fbb932e57cd0`. The artifact remains private; no new deployed APK is claimed. Commands, logs, suite names and frozen hashes are in `verification.json`.

The first JVM-test launch failed before Gradle started because this new checkout lacked ignored `android/gradlew`; the subsequent Flutter build generated it, and the recorded rerun above passed.

## Still open

Changing language does not yet update already-pending physical registrations or active follow-up copy. Exact registration identity, account ownership fencing, copy-only refresh, plugin fallback ownership and restart/legacy bootstrap remain required. Channel/settings diagnostics and auxiliary delivery text still need complete localization. No real Android/iOS delivery, WidgetKit build, widget UI or mobile frame/startup acceptance was performed. The full requirements remain open.
