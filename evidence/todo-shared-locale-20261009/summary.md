# Shared Todo locale and asynchronous lifetime — 2026-10-09

## Implemented

All five Kanban grouping labels and shared matrix empty/completed/overdue/overflow copy use the current locale. Matrix locale refresh retains permission and drag/drop logic. Stored keys, enum order, default/custom column titles and literal user titles remain unchanged.

Completion confirmation and duration prompts refresh Chinese/English copy while mounted. The private duration dialog State owns its controller and focus node until actual removal, retaining input/selection/focus across locale changes and reverse dismissal. Completion feedback updates its existing Snackbar content without replay or extending its lifetime.

The flow captures origin account generation before provider lookup, excludes duplicate `(generation, todo ID)` actions, revalidates caller/account after every awaited stage and before each new mutation, and checks the captured messenger before feedback. A stale flow cannot begin a new account's same-ID completion or suppress its independent flow.

TimeAuditProvider disposal invalidates storage/save generations and callbacks. Its load/save/entry paths and post-await notifications reject disposed, reset or stale-account continuations; storage schema, dedupe and account-level tombstone semantics are retained.

## Executed verification

- 64 focused checks passed across the scoped shared Todo, Kanban and TimeAudit files.
- 987 integrated Flutter regressions across 83 files passed with unchanged source/fixture hashes; targeted analysis passed.
- The dedicated locale fixture exercises raw language changes, literal user strings, dialog state/resources, original feedback timeout, duplicate/account generation and controlled-await origin invalidation. Provider fixtures use controlled prefs load/write/tombstone barriers.
- One legacy static assertion initially required fixed Chinese completed/overdue labels. It now checks the same visual-state branch wired to dynamic TodoUiCopy; actual bilingual widget fixtures remain intact. The initial failure is retained and current-source gates were rerun.
- Initial analysis exposed one asynchronous context lint and fixture-only protected listener access/unused parameter findings. AGY added an explicit mounted check while retaining the origin guard. A documented fixture accessor retains all listener assertions, and a fifteenth locale case holds automatic recording through account invalidation, checking no additional recording or stale feedback and listener cleanup. The initial analysis failure and AGY repair result are retained; all current-source gates were rerun.
- Exact commands, logs, frozen hashes and separate frontend/provider source reviews are retained. This batch extends the verified main-route/native-frame baseline.

## Remaining acceptance

Already-started provider/platform writes cannot be rolled back by continuation guards. The inherited reload ordering and delegated tombstone lifetime scope need separate contracts; this batch does not establish atomic persistence during account cleanup. Counting widget fakes establish flow call boundaries, while provider fixtures cover the actual TimeAuditProvider within their explicit barriers.

Main Todo editor literals/default-column display, broader Mine/settings/Calendar content and real iOS/Android device visual/performance/delivery evidence remain open. No artifact is published and the full goal remains incomplete.
