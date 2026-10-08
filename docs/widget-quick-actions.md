# Widget Quick Todo Account Boundary

## Typed actions

`duoyi://action/quick_todo?text=...` may wait for reminder permissions before
saving a parsed draft. A valid widget URL at dispatch time does not bind that
later save to the same account.

The typed action now uses `runWidgetQuickTodoAction`. The coordinator captures
`AccountLocalDataCleaner.accountDataGeneration` before any await. Its caller
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
  Both main widget feedback helpers also freeze/check their scheduling generation
  inside the post-frame callback.

The coordinator does not cancel an already dispatched native permission request
or undo a save already started. Provider storage guards and account cleanup retain
their existing responsibilities.

## Acceptance scope

Runtime coordinator fixtures exercise gated preflight/create and account
invalidation. Persistence fixtures use the real TodoProvider with mocked
SharedPreferences, including reuse of that same provider after an account
reset. A separate source-wiring assertion checks main's adapter. These do not
establish Android permission UI, native disk persistence, WidgetKit delivery or
Flutter frame behavior. Empty quick-entry dialogs are a separate flow and are
not covered by this typed-action contract.
