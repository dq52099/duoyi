# In-app-only popup lifetime — 2026-10-08

## Implemented

- Capture one per-id generation before cleanup, then check it before installing a timer. Later cancel/replacement invalidates the old request while its asynchronous cleanup is still pending.
- Route in-app-only delivery through the existing generation-aware dialog pipeline. An old timer cannot remove a newer timer's tracking or display old content under its identity.
- Use the injected clock for the deadline. Extract cancellation cleanup without changing its two attempts, first error/original stack, serialization or current-only visible-state cleanup.
- Keep in-app-only delivery free of fallback registration/refresh. Delivery errors have an in-app-specific log, avoiding a false fallback registration failure.

## Verification

- Before the correction, the 23-case popup suite passed 19 and failed four: obsolete dialogs after cancel, overlapping in-app requests, injected-clock usage and a regular popup replacing pending in-app cleanup. Baseline logs include the actual unwanted text widgets.
- The identical fixture hash passed after the correction as part of 502 regressions across 32 files. Targeted analysis passed for 40 paths; all 44 frozen source/test hashes remained unchanged during final checks.
- Five new cases cover those four failures plus preservation of cancellation error identity and suppression of a replacement timer after cleanup failure. The first analysis exposed one existing unused private helper; after confirming it had no references, it was removed while retaining the active generation-aware refresh path, then both checks were rerun. Gate completers and fake-time pumps reproduce pending cleanup; the fixed-year clock is isolated from race cases.
- The original 18 popup cases remain, including fallback registration/delivery, repeating rearm, background behavior, duplicate suppression and dialog cancellation. Independent source review, commands, hashes and logs are in source-audit.md, verification.json, baseline.txt, regression.txt and analyze.txt.

## Remaining

This proves Flutter test behavior for one popup lifetime boundary. Native alarm/popup localization, other domain aggregates, mounted page language/draft behavior, Mine/settings flows, iOS visual review and real Android/iOS performance acceptance remain open. No new build or deployment is claimed for this batch.
