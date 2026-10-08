# Notification issue copy — 2026-10-08

## Implemented

- Attach immutable copy metadata to 26 owned NotificationService producers (25 reasons, 17 title codes), preserving raw title/message, blocking, related IDs, history and deduplication behavior.
- Capture native exception detail once and retain it literally in both diagnostics and presentation. Custom, empty and whitespace titles remain literal; ownership uses explicit codes.
- Render six channel-warning/permission-unconfirmed states with neutral owned titles, including scheduled notification tests. Concrete failures retain failure titles.
- Carry the same metadata into guarded widget preflight feedback; select one locale at frame delivery. Account/frame guards remain in place.
- Offer a typed sink capability for unresolved preflight issues without changing legacy sink interfaces or recording twice. Typed unavailable exceptions preserve their original toString.

## Verification

- 386 regression cases passed across 19 test files, including new bilingual copy/service/formatter/delivery fixtures and existing scheduler, notification, storage, native-resource and API regressions.
- Targeted Flutter analysis passed for 23 paths. All 28 frozen source/test hashes stayed unchanged during each final run.
- Independent source audit found no remaining blocker in this scope; see source-audit.md. Commands, hashes and logs are in verification.json, regression.txt and analyze.txt.
- First run exposed one obsolete one-line source assertion; the replacement requires the same channel probe plus its explicit title ownership code. Other behavior assertions remain intact.

## Remaining

Page consumers still read raw fields; adding a formatter does not migrate them. Scheduler aggregates, native alarm/popup reasons, mounted route/dialog localization, Mine/settings acceptance, default iOS visual review and device performance remain open. No build or deployment was performed for this batch. Android/iOS real-device evidence is still unavailable; this evidence does not close the full goal.
