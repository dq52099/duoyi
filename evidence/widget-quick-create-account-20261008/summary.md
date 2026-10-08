# Typed widget quick-todo account boundary — 2026-10-08

## Change

Source review confirmed a normal typed reminder draft could wait for permission under account A, then be submitted into account B after switching. URL validation occurred before that later await; TodoProvider could only validate the account at its own invocation.

The production coordinator now freezes the original account generation, keeps the original provider, and checks caller availability before preflight and immediately before create. Preflight messages and create success/failure feedback retain that same predicate. Both main feedback helpers check their scheduling generation at actual post-frame delivery; typed quick-create also supplies its origin/lifetime predicate. Guest/local use and reminder warning semantics are retained.

## Executed verification

- **127 Flutter cases passed** across coordinator, widget snapshot/resources, notification, todo storage and main-shell smoke fixtures.
- **2 additional persistence cases passed** through the real TodoProvider and mocked SharedPreferences: guest creation persists the original draft; A→B during gated preflight reuses/reset-loads the same provider, makes zero create calls and preserves B's exact stored sentinel records.
- **129 distinct Flutter cases total** in the final two runs. Of the new cases, 11 execute the coordinator, two exercise provider storage and one checks main's source wiring.
- Main/coordinator/action fixture analysis: **no issues found**, terminal exit 0. Analysis took 717.7 seconds under observed host resource pressure; the existing run completed without restart.
- Final hashes and exact commands are recorded in `verification.json`. The source audit predates runtime execution; its pending-runtime statement is superseded by these records.

## Acceptance limits

Mocked preferences exercise production serialization and provider reuse; they do not prove native disk persistence. The delayed callback fixture exercises the validity predicate, while main's actual post-frame adapter is source-reviewed. Real Android permission UI, Flutter frame delivery, WidgetKit acceptance, empty quick-entry dialogs, wider bilingual/visual flows and device performance remain open.

No new build, deployment, push or release was performed. The complete user objective remains active.
