# Todo reminder preflight copy — 2026-10-08

## Implemented scope

All seven app-owned preflight issue producers carry one of five immutable
`TodoReminderPreflightNotice` codes. The coded factory retains the exact legacy
Chinese title/message, default blocking flag and scheduled time. Existing raw
constructors remain supported without assigning a reason code.

Main captures the code alongside the canonical title/message. The widget
renderer selects its outer text, preflight title and preflight reason using one
explicit delivery locale inside the existing guarded frame. The shared immediate
String preflight wrapper uses the same renderer. Unknown raw issues remain literal.

## Verification

Expanded regression: **364 cases passed**, terminal exit 0, including the five
new service cases and two appended frame/messenger cases. Targeted analysis of
15 paths: **No issues found**, terminal exit 0 (68.0 seconds). Both runs retained
all 21 frozen source/test hashes. Exact commands, times, log hashes and file
hashes are recorded in `verification.json`. The independent production audit
found no blocker in this four-file scope; all seven canonical diagnostic pairs
matched the original text and scheduler control flow remained equivalent.
The no-deliverable-rule fallback is retained; the present exhaustive rule switch
makes it unreachable for current rule types. Descriptor coverage is separate from
runtime producer coverage.

## Remaining work

Notification permission/channel diagnostics, alarm/popup reasons, scheduler
String failure aggregates and screens that read canonical preflight strings
remain separate migrations. This batch does not change reminder severity,
permission requests, scheduling, persistence or account invalidation.

Native widget rendering/actions, mounted route/dialog language changes, mine/profile
session leases, the complete default iOS visual review and real-device behavior
and frame timing remain open. No build, deployment, push or release is included.
The full objective remains active.
