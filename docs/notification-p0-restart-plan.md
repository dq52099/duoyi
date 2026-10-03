# Notification P0 Restart Plan

## Decision

Treat notification reliability as the current release gate. Keep the existing
channel IDs and native alarm architecture; fix deterministic Dart state and
diagnostic errors before changing Kotlin or OEM-specific behavior.

The current workflow uses six native lanes: one Sol decision lane and five
Luna execution/review lanes. AGY owns visual direction; the Calendar shell and
standalone-route background split is the approved low-risk UI change.

## Completed code scope

- Cold-start alarm actions share the warm-response mapper for todo completion,
  habit check-in, and snooze.
- Launch actions wait for reminder-provider hydration before dispatch.
- User-muted/blocked notification channels are no longer repaired from system
  status alone.
- Null channel and permission probes report unknown/denied instead of healthy.
- Calendar shell and standalone routes have separate background ownership.

## Device acceptance matrix

On a Pixel/AOSP device and a Xiaomi/HyperOS device, verify the same release
candidate for:

1. Push, popup, and native alarm delivery in foreground, background, and
   locked states.
2. Audible ringtone, vibration, notification shade visibility, full-screen
   presentation, Stop/Snooze, and task/habit actions.
3. Cold-start action completion exactly once after killing the app process.
4. Exact-alarm/full-screen permission denial and channel mute/block states.
5. Repeat-save, reboot, timezone change, and resync without duplicate delivery.

Capture `dumpsys alarm`, notification channels, app-ops, logcat, screenshots,
and recordings under `evidence/notification-p0-20260912/`.

## Current blockers

- No Android device or emulator is attached to this host.
- `flutter analyze --suggestions` reports Java/Gradle/KGP/AGP compatibility.
  The missing Gradle transform outputs were isolated into the recoverable
  quarantine directory `~/.gradle/caches/8.14/transforms.quarantine-20260912`;
  `flutter build apk --debug` now passes and produces the debug APK.
- An API 35 x86_64 AVD was present but cannot start because `/dev/kvm` is
  unavailable; an ARM64 API 35 image was installed but the emulator host is
  x86_64, so that image is unsupported here. A physical Android device or a
  KVM-enabled host is required for runtime acceptance.

No release, tag, or deployment is allowed until this matrix passes and the
user approves the candidate.
