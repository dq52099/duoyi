# Widget Action Account and Frame Boundaries

## Typed actions

`duoyi://action/quick_todo?text=...` may wait for reminder permissions before
saving a parsed draft. A valid widget URL at dispatch time does not bind that
later save to the same account.

The typed action now uses `runWidgetQuickTodoAction`. The coordinator constructs a shared `WidgetActionScope` before any await.
The scope freezes `AccountLocalDataCleaner.accountDataGeneration`. Its caller
binds the original auth and todo providers synchronously and supplies a predicate
for the originating context's lifetime and account availability. Guest/offline
use remains supported; no signed-in session lease is required.

## Await and feedback rules

- Reject unavailable callers before reminder preflight.
- Check the original generation and caller again after preflight, before create.
- Keep the original todo provider; its storage-generation guards still apply.
- Suppress old success, reminder warning and error feedback after invalidation.
- Pass guarded feedback into preflight so late permission failures cannot reach
  another account.
- Deferred feedback must recheck the supplied predicate at actual delivery.
  Both main widget feedback helpers delegate to `WidgetActionScope.afterFrame`,
  which checks the frozen generation and optional caller predicate at delivery.

The coordinator does not cancel an already dispatched native permission request
or undo a save already started. Provider storage guards and account cleanup retain
their existing responsibilities.

## Hydration, validation and refresh

Each asynchronous hydration, bound-URL validation and refresh operation captures
its scope before waiting. Error, stale-content and refresh-result feedback retain
that origin scope, including when the helper is invoked after an account switch.
Hydration/validation keep same-account recovery messages available; refresh also
requires the original context to remain mounted and its auth state available.

`afterFrame` calls `ensureVisualUpdate`: idle feedback requests a frame, while
registration during a frame uses its post-frame phase. Registration during
post-frame processing requests the following frame. Requests coalesce, callbacks
run once, and account invalidation makes queued callbacks no-ops. Rendering still
follows Flutter lifecycle rules; this does not force background rendering.

## Acceptance scope

Runtime coordinator fixtures exercise gated preflight/create and account
invalidation. Persistence fixtures use the real TodoProvider with mocked
SharedPreferences, including reuse of that same provider after an account
reset. A separate source-wiring assertion checks main's adapter. Shared-scope widget fixtures exercise actual Flutter frame scheduling and
ScaffoldMessenger delivery, including stale-account suppression. The
source-wiring assertion connects main to that tested helper; it does not execute
main’s complete hydration/deep-link/refresh flows. These fixtures do not
establish Android permission UI, native disk persistence, WidgetKit delivery or
real-device frame timing. Empty quick-entry dialogs are a separate flow and are
not covered by this typed-action contract.
