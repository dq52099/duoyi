# Focus ranking locale acceptance — 2026-10-11

## Implemented contract

Social ranking headings now expose explicit-locale methods and live getters.
App-generated ranking explanations carry an immutable runtime reason mask;
they render in Chinese or English from the same cached entry. Both local
room/social builders propagate this provenance through final rank assignment.
The reason order and Chinese output remain compatible with the previous
implementation.

Remote explanations retain the existing trimmed server string, even when it
equals a Chinese app-generated phrase. Only a flagged remote entry with an
empty summary receives the localized server-correction fallback. Unflagged
empty summaries remain null. Scores, caps, sorting, rank, session counts,
room/seed JSON, and authored member names are unchanged.

## Verification

All Flutter commands used `/home/ubuntu/flutter/bin/flutter`, `--no-pub`, and
`TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011`.

| Batch | Result | Log under task temp |
| --- | --- | --- |
| Model/provider locale regression, two files | 12 passed, exit 0 | `focus-ranking-locale-regression.log` |
| Four-file source/test analysis | No issues, exit 0, 8.9 seconds | `focus-ranking-locale-analysis.log` |
| Existing focus API/DTO/realtime compatibility | 5 passed, exit 0 | `focus-ranking-api-compatible-regression.log` |

There are **17 passing checks in three distinct test files**. The provider
test uses a mock transport with synthetic users and verifies that an existing
cached global ranking changes generated reasons without another request.
It preserves a server literal matching the fallback phrase. Sol reviewed the
actual model/provider diff and found no blocking defect in that bounded scope.

## Remaining frontend work

Pomodoro ranking selectors still need an explicit locale input or a listenable
repaint boundary. Their comparison can otherwise read the new language from
both cached view models and suppress repaint. AGY owns that page follow-up;
this acceptance covers data/presentation contracts and does not claim the
ranking UI changes live. No device, APK, push, release, or deployment was
performed.
