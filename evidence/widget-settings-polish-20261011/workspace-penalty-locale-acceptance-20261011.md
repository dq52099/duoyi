# Workspace and focus penalty locale acceptance — 2026-10-11

Workspace roles and six known activity actions now expose explicit-locale
methods and live-locale getters. Unknown action codes, member names, activity
details, permissions, and serialized role keys remain unchanged.

Focus penalty reasons now render in Chinese or English without changing enum
order or reason keys. `PomodoroFocusPenalty.toJson()` explicitly retains the
historical Chinese `reasonLabel` field in both locales; stored history is not
rewritten.

## Accepted verification

Commands used `/home/ubuntu/flutter/bin/flutter`, `--no-pub`, and
`TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011`.

| Batch | Result | Log under task temp |
| --- | --- | --- |
| Two model regression files | 18 passed, exit 0 | `workspace-penalty-locale-regression.log` |
| Two model and two test file analysis | Clean, exit 0, 46.5 seconds | `workspace-penalty-locale-analysis.log` |
| Pomodoro provider/snapshot/strict-focus compatibility, three files | 35 passed, exit 0 | `pomodoro-locale-compatible-accepted.log` |
| Sharing/role reset/account-load compatibility, two files | 5 passed, exit 0 | `workspace-locale-compatible-accepted.log` |

There are **58 passing checks in seven distinct test files**. Two initial
compatibility invocations included nonexistent paths and exited 1; the
verified-path runs above supersede those attempts. No production defect was
reported by the failed invocations.

This acceptance covers model presentation and storage/service compatibility.
It does not claim complete frontend localization or physical-device behavior.
No release, APK, push, or deployment was performed.
