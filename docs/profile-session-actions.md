# Profile Session Actions

## Capture the original action

`AuthProvider.captureSessionLease()` returns an opaque `AuthSessionLease` for
the current signed-in session. Capture it before opening a file picker, dialog,
or starting a profile draft. Keep that same lease for the action's lifetime.

`isSessionLeaseCurrent(lease)` checks without throwing;
`requireCurrentSessionLease(lease)` throws the existing account-changed
`ApiException`. Capture fails during account transitions, blocked hydration,
signed-out state, or after provider disposal. Leases cannot be constructed by
callers and expose no credentials.

## Local awaits and requests

The following is an integration example, not an implemented screen flow:

```dart
final lease = auth.captureSessionLease();
final file = await openFile();
if (!mounted || !auth.isSessionLeaseCurrent(lease) || file == null) return;
final bytes = await file.readAsBytes();
if (!mounted || !auth.isSessionLeaseCurrent(lease)) return;
await auth.uploadAvatarBytes(
  filename: file.name,
  bytes: bytes,
  sessionLease: lease,
);
if (!mounted || !auth.isSessionLeaseCurrent(lease)) return;
// Apply feedback only to this still-current view and session.
```

`updateProfile`, `uploadAvatarBytes`, `bindEmail`, `sendBindEmailCode`, and
`changePassword` accept the optional `sessionLease` argument. Passing a stale
lease rejects the operation before dispatch. Omitting it preserves existing
call syntax; it does not bind an earlier picker, dialog, or draft.

Existing HTTP guards still protect route fallback and response application.
Profile, avatar, email binding, and email-code success check the lease again.
Password change checks before its own logout; that successful logout naturally
invalidates the lease and still completes normally.

## Lifecycle rules

Same-account refreshes and profile updates retain leases. A legacy session with
an unknown user ID can acquire its ID on refresh. Hydration, successful
reauthentication, account cleanup, and provider disposal invalidate old leases.
Reauthentication invalidates them even when user ID and token are reused.
An attempted cleanup that has taken ownership invalidates the old lease even
if cleanup fails and the previous token remains valid.

Logout preflight retains its original client and session epoch. Its late return
cannot log out a newly authenticated session that reused the same token.

## Required UI integration

This provider contract does not close the profile acceptance requirement:

- Capture dialog leases in the caller before `showDialog`, and pass them into
  password/email dialogs. Reuse them for every send/submit; invalidate old
  cooldowns and sensitive inputs after a session change.
- Bind profile drafts to a session. Reset on session change even when dirty or
  busy; preserve edits across ordinary same-account refresh and locale rebuild.
- Check both view lifetime and lease after each local await and before feedback,
  navigation, controller edits, or local profile writes.
- Add actual picker, dialog, and account-switch UI evidence after integration.
  Provider tests alone prove only the provider boundary.
