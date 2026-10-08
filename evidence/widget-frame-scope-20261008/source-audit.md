# Widget action frame scope audit — 2026-10-08

## Result and reviewed source

**No confirmed blocker in the bounded source patch.** The shared scope retains the original account generation through awaits and frame delivery. It preserves quick-create's caller/auth guards, adds an explicit frame request for idle or late-post-frame feedback, and closes the committed hydration/bound-action/refresh stale-feedback paths described below.

Repository: `/tmp/duoyi-update-deploy-20261005-isvisjkp/source`, base HEAD `976f6dacf1dc625de6a4e93cb83019906d2852c6`. Read-only audit: no project edits, tests, builds, analysis commands, or process interventions. Only this private report was written. Runtime verification of this new patch is pending; earlier quick-create results do not establish execution of this revision.

| Source | Reviewed SHA-256 |
| --- | --- |
| Working-tree `lib/main.dart` | `9a69ae16cd6103ab98ecd5d9a867f58f01bf853cccdfa0de1ecbaefe93351673` |
| `lib/services/widget_action_scope.dart` | `caaf1b0f6d4d2c3e0a369b38cddced1c29bf2fa78d53f657a6abbb2d4d446ead` |
| `lib/services/widget_quick_todo_action.dart` | `23655f11ea4aa89d791a29a1ea3adf00cc33a8c67a364657e650add07471f5b9` |
| Committed HEAD `lib/main.dart` | `a81af64124230909739b2da00c30395fc1c7f06e49278edb3c6a4325601882f7` |
| Committed HEAD quick-create coordinator | `87f3cd206a772ea8155151ec606fbf0993239a9596fd60632ce97b189d345500` |

## Verified baseline defects

Read committed HEAD via `git show HEAD:...`, rather than attributing the following defects to the already patched working tree:

- Hydration dispatch captured generation and guarded successful dispatch, but its catch called shell feedback without passing that pre-await generation. A late A hydration error could schedule feedback using B's newly current generation.
- Bound actions captured generation and guarded actual dispatch, but both the invalid branch and catch omitted origin identity when showing feedback. A generation mismatch itself could therefore cause A's old validation result to be shown on B.
- Refresh guarded day/account availability after hydration, before `_pushHomeWidget`, but success/failure feedback after that awaited push and catch omitted origin identity. A later account switch could display A's refresh result on B.
- Both feedback helpers guarded the generation captured when scheduling. This already prevented switching between scheduling and delivery, but could not recover identity lost before the helper call. They also used `addPostFrameCallback` without requesting a frame. Flutter explicitly documents that this API does not request a frame, so an idle async failure could remain queued until another event scheduled one.

These are confirmed source orderings, not device reproductions. Existing mutation dispatch checks were present; this patch's new integration concerns feedback origin and frame delivery.

## Scope and wiring review

[WidgetActionScope](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/widget_action_scope.dart:7) captures account generation synchronously in its constructor. `isCurrent` first checks the frozen generation, then its optional availability predicate; an invalid generation short-circuits the predicate. The scope does not rebase itself to a newer account, mutate preferences, or own any provider. Multiple `afterFrame` calls are independently queued one-time deliveries, not a recurring callback loop.

The [quick-create coordinator](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/widget_quick_todo_action.dart:17) creates this scope at the same point its old inline generation capture occurred. Original AuthProvider/TodoProvider binding in main remains synchronous before coordinator entry. The checks before/after preflight and guarded preflight/result/catch feedback still use the original generation plus the original context's mounted status and bound auth transition/blocked flags. No signed-in requirement or AuthSessionLease was introduced, so local/guest behavior is retained.

Both [feedback helpers](/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/main.dart:4077) now delegate actual delivery to `afterFrame`. The shell helper combines its newly captured scheduling generation with the supplied origin predicate. Consequently, an A operation that calls the helper after B becomes current is rejected by the origin scope, while a switch after scheduling is rejected by the helper's own scope. The callback retrieves the current shell only after these checks, then checks mounted before showing feedback.

Hydration and bound-action scopes are constructed before their first awaits; their new catch/invalid feedback closures retain those scopes. Refresh additionally retains its original context's mounted/auth availability predicate. Its currentness is reevaluated at delivery, including after push success/failure or catch. `showFeedback: false` remains silent.

There is no origin identity borrowing path in these reviewed closures. Generation-only hydration/bound scopes intentionally allow current-account recovery diagnostics even if that account is blocked or in transition. They do not claim to suppress every same-generation auth-transition message. Actual dispatch still checks auth availability. Refresh and quick-create have the stricter optional availability predicates. This distinction avoids turning initial hydration failure into silent recovery failure; it is not a new cross-account mutation path.

## Frame scheduling and disposal

The installed [Flutter scheduler](/home/ubuntu/flutter/packages/flutter/lib/src/scheduler/binding.dart:906) was read, not executed. Its phase behavior matches the new implementation:

| Call phase | Source behavior |
| --- | --- |
| Idle | Callback is queued; `ensureVisualUpdate()` requests the next frame |
| Transient callbacks / mid-frame microtasks / persistent callbacks | Callback is eligible for the current frame's later post-frame phase; no extra frame request is needed |
| Already executing post-frame callbacks | Flutter has copied/cleared the current callback list; the new callback remains for the next frame, which `ensureVisualUpdate()` requests |

`scheduleFrame` coalesces an already scheduled frame and respects `framesEnabled`. The helper does not force rendering while the app is hidden/inactive, so delivery can remain deferred until rendering resumes. Currentness is checked at that eventual delivery. Do not interpret the helper as an immediate-delivery guarantee for a background app.

Flutter cannot unregister a post-frame callback. This implementation correctly makes invalidated callbacks no-ops at delivery. Caller lifetime is the responsibility of the supplied predicate or callback: refresh/quick-create test `mounted` before provider reads; generic shell callbacks use the mounted current shell. An originating shell being disposed while another shell for the same account exists is not itself account invalidation. The global diagnostic paths may still deliver to that same-account shell; the stricter context-bound operations suppress their own disposed callers.

Predicates/callbacks are assumed to behave as ordinary synchronous callbacks. If one throws, Flutter's scheduler reports the callback exception; `afterFrame` is not a new exception-swallowing layer. None of the reviewed production predicates introduced a demonstrated disposed-context read because mounted/generation checks short-circuit first.

## Required fixture evidence and limits

Fixture ownership remains with the separate agent. The initially read existing quick-create wiring assertion still searched for inline generation and `addPostFrameCallback` inside main, so it must be updated to follow the new shared production helper; no failing test run was performed by this audit.

Useful deterministic cases should execute the real `WidgetActionScope.afterFrame`, not reproduce its checks in a recording fake:

- Idle scheduling: assert a frame is requested before manually pumping, then confirm one delivery. Pumping unconditionally without inspecting scheduling can hide the old no-frame bug.
- A callback added during post-frame execution: confirm it schedules/runs on the next frame exactly once; also cover registration before the current post-frame phase.
- Generation changes before delivery, caller predicate becomes false without a generation change, and disposed caller: callback is suppressed. Verify stale generation prevents touching its predicate.
- Old A scope handed to a B-created scheduling helper: no delivery; same-account invalid bound URL/hydration failure still yields its intended recovery message.
- A→B during hydration/validation/push, including invalid and catch branches: old feedback is suppressed. Stable refresh and stable guest/local quick-create retain expected output.
- Actual Flutter messenger/frame delivery: ensure no stale SnackBar appears after account invalidation, rather than only proving a predicate was passed to a fake adapter.

Source review establishes these guard/scheduling relationships, not execution, device timing or all deep-link/dialog integration. Earlier successful analyzer/persistence results are evidence for their recorded hashes only. No broader UI boundary closure is claimed here.
