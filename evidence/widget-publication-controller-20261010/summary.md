# Widget publication controller — 2026-10-10

## Implemented

- The Dart controller starts without writer authority. It accepts a workspace only after a caller supplies validated auth/owner context and the current account generation.
- It serializes native requests, keeps uncertain requests immutable for an exact retry, and uses an ordered healthy native read to drain an unknown response before a new operation. A read never supplies a writer lease.
- Revocation synchronously stops captures. Explicit cleanup, forced same-account reset and foreign-owner handoff keep a barrier latched until a validated sealed/absent read or confirmed native invalidate. A failed/unknown clear cannot reopen the old active lease.
- Locale, brand and theme are captured as one presentation value set. Revisions do not move below a previously observed floor. Business captures bind the original scope, lease, revision, day and offset; a stale capture is rejected before native submission.

## Review and verification

- Bounded independent source review found two barrier gaps (forced reset and foreign owner after failed invalidate) and one lower priority revision-floor gap. All three were repaired before this record. The review did not run code.
- Targeted `flutter analyze --no-pub lib/services/widget_publication_controller.dart` passed with no issues; exact command, source hashes and raw output are in `verification.json` and `analyze.log`.

## Remaining integration

This controller is not called by AuthProvider or HomeWidgetService. Existing Android/iOS widget readers still consume the legacy payload. The Android canonical frame, account transition hook, guest marker, iOS shared store/bridge/WidgetKit reader, launcher refresh and physical-device acceptance remain open. Analyzer success does not establish native durability, display updates or smoothness.
