# Widget pin receipt retention — final scoped acceptance

Date: 2026-10-11 UTC. This implementation extends the request isolation in `8af23c7` and is accepted for the source, JVM, Flutter and Android compilation scopes below.

## Implemented lifecycle

- Before launcher submission, native code reserves the request for 120 seconds using a monotonic uptime clock. Accepted requests renew that handoff; unsuccessful submission releases it. Idle expiry runs the same cleanup.
- Real waits register an engine-owned token on `duoyi/widget_pin_results`. Multiple tokens for one ID remain independently protected. Tokens do not expire according to the Dart wait timeout: an issued poll RPC and its acknowledgement may still be in flight. Exact owner/ID/token release, engine detach, destruction, or restart ends protection. Activity recreation retains the engine owner.
- Dart measures registration and polling from entry with `clock.stopwatch()`. Failed/null registration returns unavailable rather than polling without protection. A matching successful receipt follows awaited read → clear acknowledgement → token release → return, including a poll that finishes after the deadline. Both confirmed and confirmed_unverified remain successful. Timeout alone does not acknowledge or cancel the launcher request.
- Shared native storage limits unattended namespaced receipts to 64, incoming included and retained. Active protection, the legacy slot, and unknown data are outside this budget. Eviction removes only six recognized fields of a canonical length-delimited request namespace. Unknown fields, unrelated data and legacy compatibility remain intact.
- The application facade coalesces expiry tasks under the shared store/state lock. Process reconstruction seeds arrival ordering from persisted confirmation time and ID; confirmation timestamps are ordering input rather than TTL.

## Controlled evidence

| Scope | Actual result | Evidence directory |
| --- | --- | --- |
| Kotlin/JVM | 67 passed, including 20 actual-store cases; compiler and JUnit exit 0; all 15 before/after source hashes match | `widget-pin-retention-jvm-final-acceptance-logs/` |
| Flutter | Nine suites, 104 passed; 10-item analysis has no issues; current inputs match both manifests | `widget-pin-retention-flutter-final-acceptance-20261011/` |
| Android | `:app:compileDebugKotlin --offline -x :app:compileFlutterBuildDebug --max-workers=1 --no-daemon -Dorg.gradle.jvmargs=-Xmx2G --console=plain`, exit 0 at 11:16:30 UTC; all 280 input hashes match; all 49 inspected classes and 36 manifest widget components exist | `widget-pin-retention-platform-compile-20261011/` |

These are overlapping scoped regressions, not a cumulative full-project test count. The root session ran the controlled final checks; an independently started duplicate JVM run is excluded. Initial Flutter failures were an obsolete platform-literal assertion and gated Completers constructed outside fakeAsync. Fixtures were corrected, timing/acknowledgement assertions retained, and the full Flutter batch rerun successfully. Initial and duplicate logs remain historical.

## Limits and pending acceptance

The 120 seconds is a native handoff reservation, not an RPC hard deadline or a cap on protected records. Failed clear/end RPCs report errors; failed end can leave protection until engine cleanup. Total persisted data is therefore not promised to fit 64 records.

Real launcher callback/pinning, SharedPreferences durability, idle Handler behavior, Activity and engine lifecycle, process death, widget resizing and device performance still require platform evidence. The Android gate excludes Flutter compilation and produces no packaged APK. There was no version bump, push, release, deployment or Android/iOS device acceptance in this batch. The full widget/style/global-localization/Mine/settings/smoothness goal remains active.
