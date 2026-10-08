# Profile Session Contract — 2026-10-08

## Core changes

- Add an opaque provider-owned `AuthSessionLease` captured before a local asynchronous action or form begins.
- Validate owner, client, session epoch, token, known account identity and active session status. Reject capture during transition, blocked hydration, signed-out state or after disposal.
- Keep leases across ordinary profile/refresh mutations and legacy user-ID completion. Invalidate them on hydration, reauthentication, cleanup and disposal, including same-ID/same-token reauthentication and failed cleanup after takeover.
- Accept optional original-session leases for profile, avatar, email-code, email-binding and password operations. Reject stale leases before dispatch; preserve existing HTTP/fallback guards. Validate profile/email/avatar completion without invalidating a successful password change's own logout.
- Bind logout preflight to client and epoch so its late return cannot log out a same-token newly authenticated session.
- Guard retired-provider continuation, notification and subsequent account-storage/callback dispatch. Previously dispatched HTTP/storage/callback work is not withdrawn.

## Verification

**66 Flutter cases passed against the final recorded source:** 51 existing profile/provider regressions and 15 new session-contract cases. The mock factory also intercepts rebuilt clients after login; zero-request assertions compare complete dispatch snapshots and the exact account-changed exception. Expected negative cleanup/disposal cases produce diagnostic stack traces and pass.

Read-only implementation review found no unresolved confirmed core blocker. The review and runtime source hashes match. Changed-file analysis is recorded separately in `verification.json`; earlier partial runs are not counted as extra cases.

Reproduce: `flutter test --no-pub --concurrency=1 test/providers/auth_provider_profile_test.dart test/providers/auth_session_lease_test.dart`.

## Incomplete UI and delivery

`docs/profile-session-actions.md` specifies the required UI integration. Existing screen calls still omit leases. This batch does **not** close the avatar picker, old password/email dialog or dirty-draft account-switch findings. Those flows require origin capture, lease arguments and mounted/session checks around local awaits and feedback.

No web/APK rebuild or deployment was performed for this source batch. WidgetKit presentation, full-route localization, default iOS style, settings workflows and real-device performance acceptance remain open. The overall goal remains active.
