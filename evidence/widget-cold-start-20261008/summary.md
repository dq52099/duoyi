# Widget cold-start nonce recovery — 2026-10-08

A cold-start runtime fixture reproduced the old service publishing a whitespace-only stored account nonce (`space/tab/newline/NBSP`). The new native snapshot validation correctly rejects such metadata; reusing it would keep widgets unavailable across restarts.

Initialization now generates a new secure nonce for blank stored values while preserving valid raw values. It still writes only through the existing serialized publication queue. The production fixture checks recovery, publication order, current binding acceptance, old binding rejection and stable cached identity across repeated initialization/push.

- Baseline against the old service: expected failure, exit 1, because the blank nonce was reused.
- Final Flutter widget regression: **62 cases passed**, including the new cold-start case.
- Analysis of the service and fixture: **no issues found**.
- Exact commands and final hashes are in `verification.json`.

No new web/APK publication or native device acceptance is claimed. Real launcher/WidgetKit behavior remains pending.
