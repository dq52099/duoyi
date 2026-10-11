# Parallel integration checkpoint

Accepted standalone metadata commit: `2b12c26`
(`fix(calendar): localize generated metadata and preserve authored text`).
Only the aggregator, metadata model, display-text helper, and their tests were
committed; pending page changes and unrelated dirty files were preserved.

## Scheduling

Six independent streams were used: root integration, Sol backup/account review,
Luna Todo detail regression, ringtone regression, calendar regression, and Luna
evidence preparation. Native agent capacity is four including root; separate
AGY jobs and verification processes supplement native agents when useful.

## Recovered AGY results

Three completed implementations were collected after identity-checked recovery
of each worker's hung `ps` child: Todo detail, calendar correction, and ringtone
settings. The worker and AGY process IDs are now stopped. No plugin settings or
shared AGY service were modified. A successful invocation is not acceptance.

The Today predecessor was canceled and retains partial unaccepted edits. The
BackupScreen job failed with explicit Gemini quota exhaustion; its partial
implementation was reviewed after termination. Sonnet high was previously
rejected by the CLI. A request to transfer the remaining frontend fixes to root
is pending under `task-model-routing`; this checkpoint makes no ownership transfer.

## Verification

- Calendar baseline: **24 passed, 1 failed**. The failure confirms that an old
  sheet can acquire a new account generation between route opening and build.
  Log: `.dart_tool/task-temp-20261011/calendar-ui-final-tests.log`.
- Real `America/New_York` DST checks: **4 passed**, including new and edited
  all-day events across March and November 2026 offset changes.
  Log: `.dart_tool/task-temp-20261011/calendar-dst-final-tests.log`.
- Backup and integrations dialog baseline: **5 passed**. These tests cover
  stale import/config confirmations and locale-preserving fields, not every
  import flow. Log: `.dart_tool/task-temp-20261011/backup-ui-baseline-tests.log`.
- Ringtone baseline: **45 passed, 1 failed**. The failing static assertion
  expected inline Chinese text now held in `NotificationUiCopy`. Assertions
  were updated and bilingual feedback checks added. The final combined
  metadata/ringtone/settings boundary batch passed **33 tests**.
  Log: `.dart_tool/task-temp-20261011/ringtone-ui-final-tests.log`.
  Final log: `.dart_tool/task-temp-20261011/calendar-ringtone-copy-final-tests.log`.
- Analysis of six calendar/ringtone files reports three async-context lint
  findings in `_applyRingtoneChange`, not a clean acceptance.
  Log: `.dart_tool/task-temp-20261011/calendar-ringtone-final-analysis.log`.
- Added typed metadata coverage for Todo due dates, TimeEntry category/duration,
  Pomodoro duration, and preservation of authored text. These checks passed in
  the final 33-test batch.
- Existing Todo detail checks: **29 passed** (Markdown, save/return, shared
  locale state), and two-file analysis is clean. Logs:
  `.dart_tool/task-temp-20261011/todo-detail-final-tests.log` and
  `.dart_tool/task-temp-20261011/todo-detail-final-analysis.log`.
- The new Todo account-origin regression **fails as expected against unfixed
  source**: the new-account title becomes the old-account draft. This is a real
  data-boundary blocker despite the existing 29 passing checks. Log:
  `.dart_tool/task-temp-20261011/todo-detail-account-origin-baseline.log`.

## Remaining blockers

- Today: `_TodayTodoSwipeTile` lacks `super.key`; large-font habit cards overflow.
- Calendar: capture origin account generation before pushing the sheet route.
- Backup: catch stale configuration-load cancellation; keep Copy out of write
  action sequencing and disable it while busy; check origin after each provider
  import before beginning another import.
- Todo detail: bind the route/comment drafts to an immutable opening account;
  retire stale drafts and saving/subtask states on account invalidation. A new
  same-ID account regression reproduces the contamination and must pass after
  the fix.

No version bump, push, signed APK, or deployment was performed at this checkpoint.
Android/iOS physical-device acceptance remains pending because no device is available.

## Buffered widget launch integration follow-up

The next accepted service checkpoint is `2704add`
(`fix(admin): localize response errors and validate list members`): 54 admin/API
service checks passed and the five-file analysis was clean. This does not close
the pending page work above.

This round used root plus three native agents; the runtime permits four native
agents including root. Two independent Swift verifier processes ran alongside
them, yielding six active work streams when all were running. Completed or
queued work is not counted as active.

Android and source-marked iOS widget launches now use an app-owned pending
delivery queue with a distinct UUID for every received tap, a snapshot/hot
delivery protocol, terminal ACK and retries. Android receives both cold and
warm widget Intents before plugin callbacks. A retained engine preserves its
subscription across Activity recreation. Distinct repeated count-habit taps
are separate deliveries; repeated snapshots of one delivery do not dispatch it
again. Pending capacity is 256 and rejects the newest overflow. Terminal ID
retention is capped at 4096. This is a process-memory handoff, not durable
exactly-once mutation.

New concrete widget entity URLs carry the rendered account/day/offset binding.
After data hydration, Dart checks the opening account generation and current
publication before resolving an entity ID. Stale source-marked entity links
fall back to their section; stale write actions are rejected. Native transport
does not fill missing bindings from the active account. Four routing diagnostics
no longer print URI contents, user draft text or account nonce.

Portable Swift verification now ran with the official `swift:6.2-noble` image,
network disabled and the repository mounted read-only: 23 snapshot/launch
cases and 19 timer cases passed, each process exiting 0. This does not compile
the SwiftUI/WidgetKit target or MethodChannel adapters and does not replace
device evidence. Existing iOS plain navigation and old unmarked cached URLs
still follow the ordinary deep-link path with one early pending slot.

The final widget regression, focused analysis, native report and security audit
are recorded in `widget-launch-platform-regression-20261011.md` and
`widget-launch-security-alignment-20261011.md`. Frontend re-analysis confirms
the Today constructor errors and remaining async-context findings; see
`frontend-current-blockers-20261011.md`. The page ownership decision remains
pending under `task-model-routing`; no ownership is inferred from elapsed time
or from the user's concurrency request.

No new version, signed APK, push or deployment is claimed by this follow-up.

## Service internationalization checkpoint

This follow-up organized six useful streams: root service integration, Sol typed-contract review, Luna exporter implementation/acceptance, Luna updater-copy inventory/extraction, and two independent root regression processes for cloud-sync and widget/API feedback. Native capacity remains four including root; this is not a claim that six native subagents ran simultaneously. Finished streams were reused for compatibility regression, focused analysis, and evidence recording.

Accepted commits are `ec27048` (sync/widget feedback), `100f9bc` (exports), and `729f2ea` (update notices and target-version asset selection). The distinct focused regression groups contain **190 passing checks**, with clean focused analyses and a source review of the changed contracts. Full commands and limits are recorded in the three service acceptance reports.

Pending frontend source and its original regression fixtures remain outside these commits. Today compile errors, calendar opening-account capture, Todo draft account binding, and Backup async/cancellation/import sequencing still prevent whole-task acceptance. Under `task-model-routing`, AGY owns those frontend changes; Gemini quota was reported unavailable until roughly 06:00 UTC and Sonnet high invocation was rejected. The earlier takeover request remains unanswered. Neither the concurrency request nor elapsed time changes that ownership.

No push, new signed APK, version bump, or deployment occurred in this follow-up. Physical Android/iOS acceptance and Xcode/WidgetKit compilation remain outstanding.


The subsequent existing data-settings error suite passed **11** checks with clean two-file analysis. Only its test file changed; it confirms bilingual safe error framing and WebDAV classification, not the pending Backup page/account flows. See `data-settings-error-locale-acceptance-20261011.md`. The four independent focused groups now contain **201 distinct passing checks**.
