# TodoProvider lifetime — 2026-10-08

## Implemented

- Disposal is terminal: invalidate local storage and reminder generations without clearing visible tasks or saved raw/copy diagnostics.
- Fence hydration, queued writes, persisted callbacks, scheduler/dependency setters, new mutations and late reminder results. All 22 hydration continuations recheck disposal after the await resumes.
- Stop import/completion/toggle/kanban work immediately after synchronous events if the listener disposed the provider, before another item or recurring successor is created. Mutations completed before disposal stay visible.
- Keep existing account/request semantics, virtual scheduling APIs, timeout-unconfirmed behavior, persistence queue ordering, error observers and in-flight claim cleanup. Already-issued native requests and writes can finish.

## Verification

- 479 regressions passed across 31 files, followed sequentially by clean targeted analysis across 38 paths; all 42 frozen source/test hashes stayed unchanged.
- Ten disposal fixtures cover pending normal/late reminder results, hydration interruption, live success, terminal CRUD, already-hydrated await races on independent task IDs, and disposal inside real synchronous import/completion listeners.
- Independent source review closed the stale hydration-return and synchronous event continuation findings. Exact commands, hashes and outputs are in verification.json, regression.txt, analyze.txt and source-audit.md.
- Initial run passed 475 cases and failed one obsolete source-string assertion from the prior metadata change. Updated only that expected representation; behavior assertions remain. Before final checks, fixed the two additional lifecycle findings and expanded fixtures. New fixture paths use separate task IDs to exercise hydration rather than shared in-flight rejection. The first final analyzer run found a missing brace lint in the new kanban guard; braces were added with no behavior change before both checks were rerun.

## Remaining

This evidence covers provider lifetime and synthetic regression behavior. Global bilingual routes, native alarm/popup copy, Mine/settings flows, default iOS visual review and Android/iOS device performance remain open. No new build, deployment or device acceptance is claimed for this batch.
