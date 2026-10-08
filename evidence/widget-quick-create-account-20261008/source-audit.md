# Typed widget quick-todo account boundary — 2026-10-08

## Conclusion and evidence scope

**The baseline had a confirmed A→B quick-todo mutation path during reminder preflight. The parent's actual coordinator/main patch closes it in source review; no current bounded-contract blocker was found.** The patch also suppresses stale preflight, creation, catch, and deferred frame feedback. Runtime verification remains pending.

Read-only review began at integration HEAD `bba9f366444c08f509dac5ad77d18d9817537dba`; final patch review was against the working tree with HEAD `cd623a223372c9b1e9d7fa05ef521f90265d7438`. No source/test edits, tests, builds, app launches, or network calls were performed. The baseline finding is a source-confirmed reachable ordering, not a claimed device reproduction.

Baseline `lib/main.dart` SHA-256: `8cf43e7cdc9a816512347cc263a96036b7ab9b30215c026d834563e823d7c13e`. Final reviewed `lib/main.dart`: `a81af64124230909739b2da00c30395fc1c7f06e49278edb3c6a4325601882f7`; `lib/services/widget_quick_todo_action.dart`: `87f3cd206a772ea8155151ec606fbf0993239a9596fd60632ce97b189d345500`. TodoProvider was unchanged: `933e150ff316a45a498726f1d2f3596ad9ea99253636c0455757a88e887ef1b1`. Fixture source reviewed: `39f8eb40724fc820b79555dff8178e1b2505ed3bc02527caa2fd1c9e99b4bb74`. Links below point to the current integration file; the ordering section describes the baseline source.

## Baseline concrete ordering

1. A's action is initially accepted. [Typed quick entry](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4006) builds a TodoItem and invokes `_createQuickTodoFromAction`. A bound widget URL has already passed [day/offset/nonce/account-generation validation](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4189); that validation precedes the later reminder await.
2. [Quick creation](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4120) retains that TodoItem while awaiting `_preflightQuickTodoReminder`. A timed phrase such as “明天下午3点开会” produces an enabled push reminder in [SmartTodoDraftBuilder](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/core/smart_todo_draft.dart:65), so this is a normal supported input, not dependent on corrupt reminder metadata.
3. [Preflight](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4373) can wait for notification permission/channel readiness; alarm paths have additional permission awaits. [Notification readiness](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/providers/notification_service.dart:872) has no account-generation check that forces an old request to return false.
4. A→B cleanup [invalidates account writes](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:727), resets the shared TodoProvider's local state, then the authenticated response applies B. This can finish while preflight remains pending: no todo has yet been submitted for persistence.
5. When old preflight returns true, quick creation retrieves `mainShellKey.currentContext ?? context`, checks only `mounted`, retrieves its TodoProvider, and submits A's TodoItem. There is no original generation or `_widgetAccountUnavailable` check before dispatch.
6. [addTodoWithResult](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/providers/todo_provider.dart:653) captures storage/account generations **at this new invocation**, awaits hydration, checks those generations, appends, publishes `todoCreated`, and saves. If B is now stable, it captures B's valid generations and accepts A's retained draft. Its existing guards do not know the action originated in A.

The same provider object is constructed once in main and reset for account changes. Binding the provider before preflight alone therefore does not close the path; an origin-generation guard is essential. Existing provider guards correctly protect a call whose account changes after provider dispatch. The newly identified gap is before that dispatch.

## Baseline sibling comparison and feedback

[Todo completion](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4286) and [habit check-in](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4252) capture the account generation before immediately invoking their captured providers. They do not retrieve a new provider after an unrelated preflight await. Both suppress normal/catch feedback after their mutation await when generation changed. Baseline quick creation had neither that initial captured generation nor the post-create/catch check.

Quick preflight also receives the unguarded shell-feedback function. A failed old permission/channel request can therefore report an old issue on B before the outer function returns false. The fix must guard injected preflight feedback, not just creation success.

The shared [shell feedback helper](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4096) queues a post-frame callback and then reads the latest shell. Checking generation only before queuing is insufficient if switching occurs before that frame. This baseline rendering gap also limited the siblings' existing feedback protection; it does not demonstrate a sibling preflight mutation path. Scoped feedback needs to recheck the original action's validity inside the callback that actually shows the snackbar.

## Minimal contract fix

Use a small production coordinator, invoked by the typed-action branch, that captures `AccountLocalDataCleaner.accountDataGeneration` before its first await. Its `isCurrent` predicate combines that frozen generation with caller context availability and `!_widgetAccountUnavailable(auth)`. Retain local/guest behavior: requiring a logged-in AuthSessionLease would add a different restriction to this local action.

The coordinator should:

- Check currentness before preflight, after preflight immediately before create dispatch, after create returns, and in catch.
- Forward preflight failure messages, provider-unavailable messages, success/reminder issues, and catch feedback only while current.
- Pass its currentness predicate or captured generation into the shell-feedback adapter; recheck at actual frame delivery.
- Bind the original TodoProvider synchronously in main, and retain its existing persistence/reminder guards. No await should intervene between the final pre-dispatch check and invoking create.
- Suppress stale completion entirely; do not announce an old operation as success/failure on a new account. Compute context-dependent success text after the post-create validity check where practical.

A small public service coordinator can take injected availability, `preflight(guardedFeedback)`, create, result-message, feedback, and error-log callbacks. This executes the same production orchestration in tests without exposing the private main handler or mounting the full shell. Main remains responsible for Flutter context, original provider binding, and frame delivery. The coordinator should own the actual generation capture; fixtures must not supply a substitute implementation of the checks.

## Actual implementation source review

The parent implemented [runWidgetQuickTodoAction](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/widget_quick_todo_action.dart:9) and wired [the real main action](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4120) through it. Generation capture occurs synchronously at coordinator entry, before its first await. Main's original AuthProvider/TodoProvider lookups also occur synchronously before coordinator entry. The predicate combines the frozen generation with the original context's `mounted` status and current transition/blocked flags on the bound AuthProvider. No logged-in or lease requirement was added, preserving guest/local behavior.

The coordinator checks availability before preflight and again after preflight before `create()`, with no intervening await. All injected preflight messages, normal creation result messages, and catch messages use `guardedFeedback`, which checks the same predicate after any asynchronous work. The null-provider branch feeds that guarded callback and returns false, so the create closure's `todos!` is not reached. Retaining the original provider plus the generation predicate handles the real shared-provider reset/reuse during B's login.

Both [the context feedback helper](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4076) and [the shell adapter](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4096) now capture generation when scheduling and recheck it inside `addPostFrameCallback`. This closes the switch-after-scheduling gap for callers such as completion/check-in that already check their operation's generation before scheduling. The shell adapter additionally accepts `isCurrentAction` and checks it inside that same callback, before retrieving/showing on the latest shell; quick-create passes the coordinator's original predicate. This covers its earlier awaits, lifetime and transition/blocked flags. These additions do not establish that every unscoped caller checks its origin across its own awaits; broader refresh/dialog integration was not reviewed as closed.

The create closure materializes `_quickTodoCreatedMessage` before the coordinator's post-create predicate check; that can read a changed shell's sync status, but does not dispatch a mutation or UI, and the completed message is dropped when stale. It is not a remaining bounded-contract blocker. Logging old errors is similarly separate from guarded user feedback. No confirmed current blocker was found in the reviewed coordinator/main source.

The new [fixture](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/test/services/widget_quick_todo_action_test.dart:1) was also read without execution. Its eleven coordinator cases call the production function and cover current success/warnings, failed preflight, initial unavailability, generation/predicate changes during preflight, stale preflight messages/errors, stale create success/error, current preflight/create errors, and a delayed adapter invoking the passed predicate. The additional wiring case inspects the main source. No incorrect expectation was identified; the requested direct stale-create-error case was added and source-reviewed. The delayed recording adapter verifies the predicate contract, not the real Flutter frame helper. No persistence/Flutter frame/runtime result is claimed.

## Deterministic runtime verification approach

Existing quick-action tests mostly inspect main source strings (`android_widget_resources_test.dart`, `notification_quick_add_static_test.dart`). They cannot demonstrate this ordering. Existing gated reminder tests and [theme account-boundary fixtures](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/test/screens/theme_picker_account_boundary_test.dart:18) provide useful patterns: `Completer` gates, real `invalidateInFlightAccountWrites()`, resettable provider memory, and feedback assertions.

Run fixtures against the production coordinator with separately gated preflight/create and a recording feedback adapter. Cover:

| Ordering | Required result |
| --- | --- |
| Stable account, preflight true | One create, original draft/parameters retained, one current feedback |
| Stable preflight false or throws | Zero create; only intended current failure feedback |
| A→B while preflight pending, then true | Zero create, zero stale feedback; B's memory/preferences remain unchanged |
| Transition or local-data-blocked becomes true while preflight pending, without generation change | Zero create and feedback |
| Preflight emits issue after A→B | Zero feedback even before preflight completes |
| A→B while create/reminder sync is pending, then success/issue/error | No old success, reminder issue, or catch feedback on B |
| Caller unmounts during either await | No later create/feedback as applicable |
| Switch after feedback queued, before frame delivery | Recorded queued delivery rechecks validity and shows nothing |
| Guest/local stable action and no-reminder draft | Existing local creation behavior remains available |

For persistence evidence, use the real TodoProvider with mocked SharedPreferences and a recording/gated reminder scheduler, retaining the same provider across invalidation/reset. Assert item IDs in both provider memory and stored `todos`; callback counts alone cannot establish that B's storage stayed unchanged. For the preflight race, arrange B's loaded sentinel data before releasing old preflight. Also keep a provider-level late-invalidation case to show the existing dispatch-time guards still work.

A small Flutter feedback-adapter fixture should pump a queued frame after generation invalidation and assert no SnackBar. A coordinator-only test of immediate feedback does not verify the existing post-frame renderer. Runtime verification remains to be implemented/executed by the parent; none was run in this audit.
