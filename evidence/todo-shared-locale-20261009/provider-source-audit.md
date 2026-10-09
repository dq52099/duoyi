# TimeAuditProvider lifetime draft — source audit, 2026-10-09

## Boundary and conclusion

Read only the frozen `/home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009/lib/providers/time_audit_provider.dart`, plus the stable account-generation implementation and CloudSyncProvider tombstone helpers. The four AGY-owned Todo targets and the evolving provider test were not read. No SDK, checks, tests, Git, or network operations were performed. This report is the only write.

**The draft fences TimeAuditProvider's own post-await mutations, notifications, persisted-mutation callback, and new save stages against disposal/reset/account invalidation. No actual introduced regression was identified in this limited source review.** This conclusion has the inherited concurrency/delegated-helper boundaries below; it is not proof that an already-started storage operation can be cancelled or rolled back.

## Reviewed protections

| Path | Assessment |
| --- | --- |
| `dispose` (`33–40`) | Sets `_disposed`, increments storage generation and save revision, clears the external mutation callback, then disposes ChangeNotifier. Outstanding work becomes stale before superclass disposal. |
| Load (`48–71`) | Disposed entry is a no-op. After obtaining prefs, storage/account/lifetime validity is checked before decoding, assigning entries, and notifying. Those remaining operations are synchronous; no unguarded await separates the check from them. |
| Reset (`73–78`) | Disposed entry is a no-op. Storage-generation increment invalidates pending saves and entry continuations, even though reset does not separately increment save revision. |
| Save (`80–97`) | Captures revision, storage/account generation, and a list snapshot. Rechecks after isolate encoding, after obtaining prefs, and after `setStringList`. No stale save starts a new provider-owned prefs write after its guard fails. The last check suppresses the persisted-mutation callback after invalidation. |
| Callback (`99–106`) | A disposed provider cannot invoke it; callback errors retain the existing catch/report behavior. If a callback itself resets/disposes the provider, the caller's post-save generation check prevents the later listener notification. |
| Add/import/upsert/update (`128–187`, `249–259`) | Entry guards prevent mutation after disposal. Every direct notification after `_save` checks captured storage/account/lifetime validity. The upsert fallback delegates directly to guarded `add`; it has no additional continuation effects. |
| Delete methods (`191–232`, `261–279`) | Entry and pre-delegation guards remain; post-tombstone checks prevent starting `_save` after invalidation, and post-save checks prevent notification. Account-level `time_entries` tombstones and `workspaceId: null` are preserved. |
| Convenience record/remove methods (`234–247`, `281–414`) | They synchronously compute arguments and delegate to guarded mutation methods, with no later writes or notifications of their own. Absence of an extra entry guard in these wrappers does not bypass the guarded mutation entry. Read-only queries have no lifetime side effects. |

The current `_isCurrentSave` still requires both latest revision and the storage/account/lifetime predicate (`108–126`). Titles, notes, dedupe keys, import duplicate calculation, serialization payload, isolate threshold, and account/private tombstone selection were not changed by this lifetime draft.

## Boundaries retained from existing behavior

### Accepted writes are not reversible

A prefs write submitted at line 94 while the operation was valid may finish after disposal, reset, a newer save, or account invalidation. The guard at line 95 prevents later callbacks; it cannot undo the submitted write. The same distinction applies to tombstone writes already submitted by CloudSyncProvider. No rollback or stronger serialization guarantee should be claimed from these guards.

### In-progress tombstone helper has its own scope

Stable `CloudSyncProvider.recordDeletedItems` captures account generation and checks it after obtaining prefs and before submitting the tombstone write (`cloud_sync_provider.dart:1108–1170`). It does not capture this provider's disposal/storage generation.

Consequently, a tombstone helper invoked while the provider is live can still begin its actual prefs write after **same-account provider disposal/reset**, if it was waiting for prefs at the time. This differs from a platform write already accepted before invalidation. The target provider correctly suppresses its later `_save`/notify when the helper returns, and account invalidation is fenced by the helper itself. This is an inherited delegated-helper boundary, not a regression introduced by the lifetime guards. Requiring zero additional tombstone writes after same-account disposal would require a separate helper-availability contract; it cannot be proven by the provider's post-await check alone.

### Reload ordering remains inherited

An accepted load increments `_saveRevision` and replaces `_entries` (`67–70`). A load that began before a newer local mutation can accept older prefs data and invalidate that mutation's pending save, because load does not capture/check a mutation-order revision. Root confirmed that the exact increment/placement/comment already exists in the baseline and that this draft did not change reload policy. It is therefore an inherited concurrency gap, separate from lifetime protection. Do not alter reload authority/order as part of this bounded repair without defining its intended ordering and evidence.

An invalidated import also retains its computed summary, while skipping later notification. That result describes work accepted before invalidation; it is not a persistence or current-account UI guarantee.

## Focused evidence needed

No runtime verification was performed. The later isolated fixture should establish:

- Dispose while load, prefs acquisition, isolate encoding, or save completion is held: no later entry replacement, listener notification, or persisted-mutation callback; no new provider-owned write stage after a failed guard.
- Invoke every mutation/reset/load after disposal: no state, persistence, tombstone, or callback effects; disposed import returns its zero summary.
- Reset and account invalidation during each await: suppress subsequent stages and notifications, while allowing already-submitted writes to finish without claiming rollback.
- Overlap saves: preserve existing latest-save revision behavior and payload/key format. Do not silently assert a new reload ordering guarantee.
- Delete while a tombstone await is held: after invalidation, no subsequent provider `_save` or notification. Explicitly distinguish helper writes submitted before invalidation, helper writes that can begin later under same-account disposal, and account-invalidated helpers.
- A persisted-mutation callback that resets/disposes the provider: no later listener notification from that operation.

## Fingerprint and reader freeze

Reviewed source SHA-256: `478a44e42482b3a660b226936b774fe831d7cad5deb5fba1dba2707c8f731c3b`.

**Reads are frozen at report completion.** AGY revision 2 review is a separate assignment after its actual terminal state.
