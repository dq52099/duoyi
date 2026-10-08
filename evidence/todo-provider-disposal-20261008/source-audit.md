# TodoProvider disposal boundary audit — 2026-10-08

## Finding

**Confirmed source lifecycle gap:** `TodoProvider` inherits ChangeNotifier disposal without its own dispose override or terminal disposed flag. Disposal therefore does not invalidate its storage or reminder request generations. Pending reminder synchronization and storage loading can continue to apply state and call notifyListeners on the disposed provider.

The appropriate core fix is a terminal disposal fence, not a new scheduling/error decision. Keep account/storage/request semantics, raw diagnostics, structured copy, persistence queue ordering and the existing timeout behavior. Do not use resetLocalState as dispose; it clears visible state and notifies.

This was a bounded read-only audit of `lib/providers/todo_provider.dart` and existing relevant fixtures in the integration source. No production/tests/docs edits, tests, analyzer, build or git calls. Only this private report was written. Line references describe the source read before a lifecycle implementation; no runtime reproduction was executed.

## Proven paths

| Path | Source evidence | Consequence after inherited disposal |
| --- | --- | --- |
| late reminder success/failure | `_syncTodoRemindersNow` at 552; isCurrent at 559 checks account/storage/request only; late callbacks at 631–652 | raw issue/copy, attempt/success timestamp and target mirrors may apply; callbacks then call notifyListeners |
| normal pending reminder completion | apply at 562, `_applyReminderSyncResult` at 680 | raw/copy/timestamps may apply after disposal even before timeout; generation checks remain true |
| preferences hydration | `_loadFromStorage` at 378, initial await at 380; manual account/storage check at 381; final assignment/notify at 461–463 | `_todos`, `_storageLoaded`, revision/stats may change; `_notify` then notifies disposed provider |
| large-data hydration | compute await and shared generation check at 395–398 | inherited disposal does not change the tested identity, so parsed data can still be assigned |
| corrupt rewrite / persistence continuation | guarded rewrite at 447–456; `_writeTodosSnapshot` at 512 | existing checks do not represent disposal; backup/write/callback work may proceed |
| queued write starting after disposal | `_writeToStorage` at 534 queues `_writeTodosSnapshot`; that method captures generation at execution time | incrementing generation in dispose alone is insufficient: a queued callback can capture the new generation and pass an equality-only check |
| notification boundary | `_notify` at 204 increments revision, sorts/recomputes stats, then calls notifyListeners at 219; cloudSyncNotice setter at 156–159 calls it directly | ChangeNotifier's debug disposal contract is violated; merely swallowing the notification would still allow dead-provider state mutation |

Concrete late sequence: save → reminder Future remains pending → confirmation timeout returns null issue/copy with no success timestamp → inherited dispose → pending result completes → isCurrent still true because account/storage/request generations are unchanged → apply mutates state → notifyListeners is called after disposal. In Flutter debug mode this call violates the disposed notifier assertion. The success/late-error callback is attached to an unawaited derived Future, so an assertion thrown from its body can become an unobserved asynchronous error. In release, disposed listeners are cleared; the proven issue is the call and stale provider mutation, not a claim that a cleared listener receives it.

Concrete hydration sequence: loadFromStorage starts → await SharedPreferences or compute → inherited dispose while suspended → existing identity guard passes → assign parsed todos / mark loaded → `_notify` mutates derived state and calls notifyListeners. A guard only at the final notify does not prevent the earlier data assignment.

## Minimal terminal fence

1. Add private `bool _disposed = false`.
2. Override dispose synchronously: mark terminal first, increment `_storageGeneration` and `_nextReminderSyncGeneration`, then call super.dispose once. Do not change global account generation. Do not clear visible todos/raw/copy state, notify, trigger save, reset shared scheduler, cancel shared/native reminders, or initiate async cleanup.
3. Add `!_disposed` to `_isCurrentStorageGeneration`. The existing reminder isCurrent immediately inherits the disposal condition; its request-generation equality stays intact.
4. Replace the two manually duplicated account/storage-only checks in `_loadFromStorage` and `_writeTodosSnapshot` with the shared helper, so they cannot bypass the disposed flag. Preserve every existing guard position after awaited work and before assignment/write/callback.
5. Add early terminal guards to loadFromStorage, `_loadFromStorage`, `_writeToStorage`, `_writeTodosSnapshot` and `_notifyLocalMutationPersisted`. The queued-write execution guard matters even when enqueue occurred earlier. Keep queue chaining and finally/error observation; no waits or blocking disposal.
6. Add `_disposed` early guard to `_notify` before revision/sort/stat changes. Add a central guarded notifyListeners override or guard every direct notify path as well; `_notify` alone does not cover late callbacks or cloudSyncNotice. Shared generation checks already suppress the current late callbacks, but a central notifier fence provides a narrow safety boundary for direct calls. cloudSyncNotice should return before assigning state when disposed. Guard resetLocalState and dependency-rebinding setters if they can be called after disposal.
7. `_syncTodoRemindersNow` must return before incrementing a request or invoking the scheduler if disposed. Return an ordinary null-issue/null-copy result with no succeededAt (unconfirmed), without applying it. A check only in apply would suppress state but still start new shared scheduler work after disposal.
8. `_applyReminderSyncResult` can explicitly reject disposed state as an additional terminal check while preserving its existing older-request rules. All raw/copy pairs continue clearing/applying together under the original identity guards.

Already-issued native scheduling or a SharedPreferences.setString call cannot be synchronously canceled by provider disposal. Let its Future settle and observe errors; suppress subsequent provider state, notifications, new queued work and external mutation callbacks. Do not alter the shared scheduler's account lifecycle to solve a local provider lifetime problem.

## Hydration continuation boundary

Several existing CRUD methods do `await _ensureStorageLoaded()` followed by mutation without a generation check. If a disposed-aware helper merely returns void, these methods continue after an aborted hydration and can still mutate `_todos`. This is a proven continuation issue inside the same provider, not frontend scope.

The clean additive private contract is `Future<bool> _ensureStorageLoaded()`:

- false immediately when disposed;
- after awaiting an existing load, recheck disposal;
- return true only for a live provider after existing hydration;
- after awaiting loadFromStorage, recheck before returning;
- preserve live errors and existing loading/queue behavior.

Every caller should return its existing neutral API result when false: void returns, false for bool, zero for count, null for optional add result, TodoMutationResult.notSaved for mutation result, or zero-item TodoImportSummary. Alternatively add an explicit disposed check after every hydration await; do not mix incomplete patterns. Keep current account/storage captures and checks in methods that already have them.

Existing unguarded continuation entrypoints read:

- importTodos (748)
- `_updateTodosQuadrantLocked` (1256)
- `_updateTodosPriorityLocked` (1307)
- `_scheduleTodoForTodayLocked` (1474)
- `_reorderLocked` (1563)
- `_reorderVisibleTodosLocked` (1597)
- `_updateListGroupWorkspaceLocked` (1737)
- `_addSubtaskLocked` (1799)
- `_toggleSubtaskLocked` (1829)
- `_deleteSubtaskLocked` (1923)
- `_reorderSubtasksLocked` (1968)
- `_archivePastCompletionsLocked` (2022)
- `_postponeOverdueLocked` (2081)

For continuations after `_saveToStorage`, guard notification/new scheduler/callback work too. Mutations performed while alive need not be undone. Private finally cleanup of in-flight claims may still complete; the intended terminal contract concerns visible provider state, persistence/scheduler starts, callbacks and notifications rather than preventing necessary claim cleanup.

## Existing fixtures read and required assertions

Read `todo_recurrence_reminder_test.dart` timeout/stale-background cases and `todo_storage_safety_test.dart` corrupt recovery, initial hydration, force reload, duplicate collapse, forced rewrite without deadlock and large-data decode cases. Those read fixtures do not dispose the provider during the relevant pending await; their existing reset/request coverage is not disposal coverage. Did not inspect unfinished sync-copy fixtures and did not run any test.

Recommended core assertions (not executed):

1. Pending normal sync, timeout-late success and timeout-late error: dispose before completion; raw/copy/timestamps/revision remain at the disposal snapshot, no notify and no unobserved callback error.
2. Preserve timeout null raw/null copy/no succeededAt before disposal; do not relabel it as registration failure.
3. Disposal with newer request/account/storage reset still suppresses the same old raw and copy results; live generation behavior remains unchanged.
4. Pending small preferences load and large compute load: dispose before awaited result; no parsed todo assignment, loaded-state activation, revision/stats mutation or notify.
5. Pending forced reload/corrupt rewrite: stop post-disposal assignment, backup/rewrite/callback starts while preserving live no-deadlock behavior.
6. A write queued before dispose but starting later does not pass by capturing the new storage generation. A write already issued before dispose may settle, but it must not invoke onLocalMutationPersisted afterwards.
7. A legacy unguarded CRUD path waiting for hydration (e.g. import or subtask update): dispose during load; returning from hydration must not mutate todos, publish a domain event, schedule, write or notify.
8. Public load/mutation/reset/cloud notice/dependency setters called on a disposed provider produce their documented neutral/terminal behavior without framework assertion or new async work.
9. Disposing does not clear already-present todos, raw/copy diagnostics or persisted data, and does not reset/cancel the shared scheduler's registrations.
10. Error observers/finally cleanup remain attached to pending jobs; disposal does not create unhandled underlying Future errors.

## Conclusion

There is one demonstrated lifecycle root cause: provider disposal is absent from the identity/continuation contract. A disposed flag plus local generation invalidation and shared helper closes the reminder/storage guards. Entry guards and a hydration completion signal are necessary to keep queued work and older CRUD continuations from starting or mutating after that terminal state. No frontend change is required for this bounded correction.

## Follow-up review of the proposed complete fence

Root proposed a bool-returning hydration helper and neutral exits for all 22 call sites, with terminal entry guards and local generation invalidation as described above. Additional source reads covered all post-save/sync/TimeAudit/tombstone continuations. No further visible-data mutation after those awaits was found that escapes the proposed hydration/helper/_notify/sync-entry fence. Existing completion/reopen/update/kanban/recompute/deletion external-call loops already test the shared generation helper before and after each awaited TimeAudit or tombstone operation.

Two entry details remain part of a complete neutral terminal contract:

1. `set scheduler` at 140 can clear the missing-scheduler raw/copy diagnostics even after dispose; guard it before dependency assignment/diagnostic clearing. Guard timeAudit rebinding likewise. Healthy setter semantics stay unchanged.
2. Public wrappers can claim keys before they reach `_ensureStorageLoaded`. Have `_claimInFlightKeys` return an empty set immediately when disposed, so existing empty-claim branches return their existing neutral values. `addSubtask` directly checks/adds its key before the shared claim helper and can throw its duplicate-key StateError if an earlier pending operation still holds that key after disposal; add an entry disposed return there. The direct toggle/deleteSubtask key paths can also return before claiming. Preserve finally cleanup for claims acquired while alive.

Current direct notify call sites are exhaustively accounted for: cloudSyncNotice setter, `_notify`, and the two late reminder handlers. The proposed cloud setter/_notify guards plus the existing late isCurrent predicate using the disposed-aware helper cover all four. A guarded notifyListeners override is a defensive option, not mandatory to close a currently unguarded call site.

Do not broaden `_ensureStorageLoaded`'s bool contract into a new account-generation policy for older methods in this batch; it should retain original live loading behavior and signal terminal disposal. Existing methods that already capture/check account/storage generations continue those checks unchanged. The implementation itself remains owned by root and pending a separate lifecycle source handoff; this report records the proven source issue and concrete correction contract, not a claim that production disposal has already been fixed.

## Actual implementation review — first formatted source

Read the formatted implementation handed off by root on October 8. This source implements the terminal flag, local generation invalidation in dispose, disposal-aware shared identity helper, guarded scheduler/timeAudit/cloud notice setters, guarded reset/load/notify/write/snapshot/local callback/sync entry, neutral disposed claims, and direct add/toggle/delete subtask entry guards. It preserves visible todos and diagnostics on dispose, the existing write queue, raw/copy pairs, request ordering, timeout null/no-success result, virtual scheduler compatibility, and error observation/finally cleanup.

The queued-write concern is closed in the actual source: `_writeToStorage` checks disposal before enqueue; `_writeTodosSnapshot` checks disposal **before** capturing its generation at execution; its shared identity check after compute/preferences prevents a write from starting after disposal; its check after an already-issued setString prevents the mutation callback. A queued callback therefore cannot become current by capturing the newly incremented disposal generation. Forced reload checks the captured identity before calling the loader. The nonforced loader is reached synchronously through guarded load entry; post-preferences/compute identity checks protect parsed assignment, and corrupt backup/rewrite continuations retain their checks. No independent unguarded late reminder notify path remains: both late handlers use disposal-aware isCurrent before apply/notify. Normal reminder apply is reached only through the same guarded closure.

Two continuation findings prevent a clean verdict for this first source:

1. **Stale hydration true result.** All 22 callers currently use only `if (!await _ensureStorageLoaded())`. Even with already-loaded storage, a caller's await yields: the helper can compute true while alive, dispose can run before the outer continuation, and older CRUD methods without a subsequent shared generation test mutate dead provider state. Source-only sequence: `await provider.loadFromStorage(); final pending = provider.importTodos([newTodo]); provider.dispose(); await pending;`. Import adds the todo and publishes a domain event after disposal despite suppressed storage/notify/scheduler downstream. This also affects the older quadrant/priority/schedule/reorder/subtask/archive/postpone paths. Correct every caller to `if (!await _ensureStorageLoaded() || _disposed)` with the existing neutral return; the right side checks the provider after await resumes. This corrects an incompleteness in the earlier bool-helper design recommendation. Root confirmed the finding and will correct all 22 after its already-running frozen regression settles.
2. **Synchronous domain-event continuation.** `DomainEventBus` uses `StreamController<DomainEvent>.broadcast(sync: true)` (core/domain_event_bus.dart:37). Event listeners execute inside publish and can synchronously dispose this provider. Source-only sequence: subscribe to todoCreated, dispose on the first imported item event, then import two items; import currently continues adding/publishing the second item after disposal. Completion/toggle/kanban also append recurrence or continue their loop after publishing a completion event. Add an immediate terminal/identity check after publish in import, completeTodos, toggleTodo and kanban; keep dispose-before-event mutations as they are. Add/update have only guarded save and further guarded work after their event and do not expose another visible mutation at that position. Reported to root for the terminal contract correction; no runtime reproduction performed by this auditor.

Read-only scope remains unchanged. Production fixes and fixtures are owned by root. No final implementation hash or clean conclusion is recorded until the corrected formatted handoff is reread.

## Final corrected implementation audit

Root handed off the stable formatted provider after correcting both findings above. Reread the actual file, every hydration call condition and neutral return, all six domain-event publish positions, the four reentrant continuation fences, guarded setters/notify/reset/load/queue/snapshot/callback/sync entries, existing late reminder closures, and final dispose/shared identity helper. No tests, analyzer, build, git, network or production edits were performed by this auditor. Fixtures remain root-owned and are not used here as evidence of runtime behavior.

Audited source: `/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/providers/todo_provider.dart`

SHA-256: `4a6b26410a12f6d6571445b821739ee89aa78c53eb2b68c5f7dc0289b3526d97`

Final source evidence:

| Boundary | Corrected source | Closure |
| --- | --- | --- |
| terminal lifetime | flag at 94; dispose at 2222; shared helper at 2229 | flag set before local storage/request generations increment and super.dispose; shared identity includes !disposed; visible data and diagnostics are retained |
| stale hydration bool | helper at 497; all 22 call sites use `if (!await _ensureStorageLoaded() || _disposed)` | caller checks disposal after its own await resumes; existing null/false/zero/notSaved/empty-summary/void returns retained; existing identity captures/checks remain |
| synchronous import event | publish at 789; disposed check at 792 | no second imported item or subsequent storage/scheduler work after an event listener disposes provider; first mutation made while alive is retained |
| synchronous completion/recurrence event | completion check at 991; toggle check at 1145; kanban check at 1431 | shared identity checked after publish and before recurrence append or next batch iteration; add/update have only guarded save and further guarded work after publish |
| queued or suspended persistence | enqueue at 539; snapshot entry at 519; shared post-await check at 530; callback check at 534/548 | queued snapshot cannot capture a fresh valid generation after dispose; no new setString or external mutation callback starts after terminal state; previously issued writes may settle |
| storage hydration/reload/recovery | entry at 325; forced queue predicate at 352; loader checks at 388/400/451/456/460/465 | preferences/compute continuation cannot assign parsed state after dispose; forced queued load and corrupt backup/rewrite continuation are fenced; live ordering/no-self-queue design retained |
| reminder continuation | sync terminal entry at 562; isCurrent at 573; late handlers at 645/651 | no new scheduler call after disposal, normal/late raw-copy application is suppressed by shared storage/account/request identity, and both late direct notifications remain behind isCurrent |
| notification and rebinding | setters at 141/151/159; _notify at 208; reset at 368; shared claims at 2163; direct subtask entries at 1801/1837/1932 | no assignment, revision/sort/stats mutation, notifications or new claims at those terminal entries; finally/error observation stays attached |

The earlier raw/structured sync metadata contract remains intact in the audited file: paired raw/copy clearing and application, explicit unconfirmed timeout with no succeededAt, late failure semantics, legacy virtual target scheduler call exactly once, account/storage/request ordering, and literal unknown error diagnostics. Disposal does not invoke resetLocalState, cancel shared/native reminders, alter global account generation, start cleanup writes or clear visible state.

**Final bounded source verdict: no remaining concrete disposal blocker found.** The stale hydration result and synchronous domain-event continuation findings are closed in this actual hash. This is a source inspection conclusion, not a test or deployment claim. Already-started external/native/storage operations cannot be canceled synchronously; the provider suppresses subsequent application, notifications, callbacks and new work while allowing necessary private claim/future cleanup.

## Final formatting follow-up

Root reported its first frozen regression run passed 479 checks and its analyzer identified only `curly_braces_in_flow_control_structures` on the new multiline kanban post-event identity check. Both processes stopped before root added braces and formatted the provider. These are parent-reported verification results; this auditor did not run or independently verify them, and they are not attributed to the subsequently formatted hash.

Reread the actual kanban post-event condition at 1431: it now has braces around the same `return 0`, still immediately after publish and before recurrence generation or loop continuation. Recounted all 22 post-await `|| _disposed` hydration conditions and reread import/completion/toggle post-event fences, queued snapshot entry/post-await guards, late sync notification guards, and dispose/shared identity helper. No new source issue found; the bounded source verdict above remains unchanged.

**Latest audited provider SHA-256:** `92486d46f55aa854ce5f75a593d1468e9d5ffecf89b9a1dbc63781d959dfb0cf`

This hash supersedes the earlier `4a6b2641…` for final delivery. Root owns the fresh frozen regression/analyzer rerun. This auditor only read source and updated this private report; popup lifetime findings remain in the separate `popup-in-app-lifetime-contract-oct8.md` for the next batch.
