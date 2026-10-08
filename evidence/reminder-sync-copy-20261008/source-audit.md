# Reminder sync structured copy contract — 2026-10-08

## Decision and scope

Recommend an additive result Future capability on the existing virtual String API, optional immutable entries on `ReminderScheduleSyncException`, and an optional structured issue on `TodoReminderSyncResult`. Do not introduce a provider call to a new scheduling entrypoint that bypasses existing overrides. Do not schedule once for raw output and again for typed output. Capture both outputs in the same serialized invocation.

Production implementation has now been read in five paths; no remaining bounded source blocker found. Final formatted source hashes are recorded at the end. The design section describes the initial proposal; source decisions such as bool includeTitle and the exception's immutable aggregate issueCopy are equivalent additive representations, not mandatory literal type names.

This is a bounded read-only source design audit of the integration source at `/tmp/duoyi-update-deploy-20261005-isvisjkp/source`. Root owns production. Root reported the preceding producer batch committed as `c1b3380`; this agent did not inspect git in this task. Read production and existing tests only; no source/tests/docs edits, tests, analyzer, build, git, network or process intervention. Only this private report was written. Assertions below are proposed verification cases, not executed results.

## Exact existing entrypoints

| Entrypoint | Current contract | Required additive change |
| --- | --- | --- |
| `ReminderScheduleSyncException`, scheduler:381 | const positional `List<String> failures`; toString joins `；` with existing prefix | optional typed failure entries; leave failures/toString unchanged |
| `syncTodos`, scheduler:2045 | virtual `Future<void>`; clears todo failure map inside serialized action; optional batch | same virtual call/control flow; thrown exceptions may carry entries |
| `syncTodosAndGetTodoFailure`, scheduler:2075 | virtual `Future<String?>`; schedules full snapshot once, suppresses aggregate exception, returns only target map value | retain signature; base returns a Future<String?> capability wrapper over one structured result captured inside serialization |
| `_syncTodosLocked`, scheduler:2101 | preflight unresolved list plus later shared rule sync | add parallel typed entries at the existing add sites; preserve throw precedence |
| `_syncRuleObjects`, scheduler:4234 | two rule-failure loops; updates scheduled map before aggregate throw | attach entries in those two existing loops, in identical order |
| `_recordUnresolvedTodoReminderIssue`, scheduler:2146 | target map stores `issue.message`; diagnostic sink stores title/message | message projection for target metadata |
| `_unresolvedTodoReminderFailureSummary`, scheduler:2181 | aggregate stores `title：message` | titleAndMessage projection for aggregate metadata |
| `_recordDispatchIssue`, scheduler:3260 | blocking todo failure assigns `error.toString()` | capture typed native exception only when it has explicit copy; otherwise literal |
| `_recordTodoRuleDispatchFailure`, scheduler:3273 | putIfAbsent bare confirmation string | explicit confirmation-unknown metadata, only if raw fallback is actually inserted |
| `TodoReminderSyncResult`, provider:27 | generation, raw issue, attemptedAt, optional succeededAt | optional structured issue; old constructor calls remain valid |
| `_syncTodoRemindersNow`, provider:540 | one legacy virtual scheduling call, timeout, late handlers, generation guards | transport captured structure through all existing result/application paths |
| `_applyReminderSyncResult`, provider:628 | request generation checks and raw state application | apply optional copy under the identical guard |
| `_createQuickTodoFromAction`, main:4157 | one widget savedReminderIssue path, currently all-todo reporting | capture optional structured result alongside raw detail |
| `WidgetActionMessage.render`, service:118/234 | once-resolved locale; savedReminderIssue currently uses literal detail | optional sync-issue field; render it with that same explicit locale in this branch |

## Proposed data API

New source module: `lib/services/reminder_sync_issue.dart`.

1. `enum ReminderSyncIssueProjection { message, titleAndMessage }`.
2. Immutable `ReminderSyncIssueEntry`: required raw String; optional explicitly typed copy; explicit projection; literal rawTitle/rawMessage used only as rendering fallbacks. If copy is absent, return raw verbatim. Do not split raw strings, trim them, parse `：`, search error text, or infer ownership by equality. Known native/preflight metadata comes from its producer descriptor. Rule failure metadata is a separate explicit code, not a guess derived from the generic raw summary.
3. Immutable `ReminderSyncIssue`: an unmodifiable ordered list of entries. `raw` is exactly `entries.map((e) => e.raw).join('；')`. Rendering selects locale once and passes it to every entry/copy; use `；` for zh and `; ` for en display. Preserve duplicates and entry order. Mixed typed/literal arrays must retain every unknown literal raw entry.
4. Optional Future capability, e.g. `abstract interface class ReminderTodoFailureResultFuture { Future<ReminderSyncIssue?> get reminderSyncIssueResult; }`.
5. A small concrete wrapper implementing both `Future<String?>` and that capability. Its single underlying structured Future is the scheduling invocation. Legacy Future operations delegate to a **lazy** raw projection of that Future. Implement the standard Future methods (`then`, `catchError`, `whenComplete`, `timeout`, `asStream`) without rerunning scheduling. Do not eagerly create an unused derived raw Future, which can produce an unobserved error when the consumer only awaits the structured Future.

The base `syncTodosAndGetTodoFailure` must be a non-async forwarding method when returning this wrapper; an outer async function would flatten it to an ordinary Future and erase the optional capability. Keep its existing `Future<String?>` signature and named parameters. Private structured work retains all account checks, snapshot creation, serialized action, aggregate catch and target capture. Store an immutable target entry/result in a local **before the serialized action returns**. Both raw and typed completion derive from that local snapshot, never from a later scheduler-map getter.

Provider target routing should be conceptually:

```dart
final legacy = scheduler.syncTodosAndGetTodoFailure(snapshot, reportTodoId);
final pending = legacy is ReminderTodoFailureResultFuture
    ? legacy.reminderSyncIssueResult
    : legacy.then((raw) => raw == null ? null : ReminderSyncIssue.literal(raw));
```

This calls the legacy virtual method exactly once. Existing overrides returning normal Future<String?> still execute and become raw-only results. A custom implementation can opt into the returned Future capability. The provider must inspect the capability **before** `.then`, `.timeout` or other Future transformations erase its runtime identity.

Full-list routing must still call virtual `scheduler.syncTodos(snapshot)` exactly once. Success remains the old `.then((_) => null)` result; failure metadata comes only from optional entries on the thrown aggregate exception. A new typed target method called directly by the provider is not recommended.

## Producer and shape mapping for the first implementation

| Producer | Raw value preserved | Explicit metadata / projection |
| --- | --- | --- |
| unresolved preflight target | `issue.message` | existing `ReminderIssueCopy.preflight(issue.copy)`; message |
| unresolved preflight aggregate | `${issue.title}：${issue.message}` | same existing descriptor; titleAndMessage |
| typed `NotificationScheduleUnavailableException` dispatch | `error.toString()` | captured `error.title`, `error.message`, `error.copy`; titleAndMessage |
| unknown dispatch error | `error.toString()` | literal only; no exception-text classification |
| `_recordTodoRuleDispatchFailure` fallback | `提醒调度器未能确认规则已注册到系统` | separate explicit confirmation-unknown code; message |
| generic rule aggregate | existing `_ruleScheduleFailureSummary(rule)` | separate rule-registration-failed code; titleAndMessage |

Rule title metadata must explicitly map object type: todo → task registration failure, goal → goal registration failure, other → generic registration failure. Raw titles stay `待办提醒注册失败`, `目标提醒注册失败`, `提醒注册失败`. These are actual failed-rule summaries; do not reuse warning/unconfirmed titles for them.

Rule message metadata captures `ReminderKind` and the **literal `rule.body`**, including quotes, Chinese, newlines and diagnostic/date/rule labels already contained in that body. Existing body behavior is `body.trim().isEmpty` to select `该提醒`; nonempty quoted content uses the original untrimmed body. Do not change that to `${body.trim()}`. Capture any additional object/rule/date parameters as immutable literals at production time; do not reread the Todo/rule, recompute preflight, or resolve scheduling time when UI renders.

| Kind | Existing raw channel label | Existing raw hint to preserve |
| --- | --- | --- |
| push | 普通通知 | 请检查系统通知权限和通知渠道。 |
| popup | 弹出提醒 | 请保持应用前台运行，或开启系统通知权限以便后台兜底。 |
| alarm | 闹钟提醒 | 请检查通知权限、精准闹钟权限、全屏提醒权限和强提醒渠道。 |
| email | 邮件提醒 | 请检查邮件提醒服务配置。 |
| off | 关闭 | 请重新启用提醒方式。 |

First scope should cover preflight/native entries, todo/goal shared rule summaries and the bare target confirmation fallback. Existing habit/anniversary/countdown aggregate producers may continue throwing the legacy constructor with no metadata. The synthetic false-result StateErrors currently created by push once/daily result helpers are explicit owned producers if root chooses to type them later; do not infer their type by matching their raw string or reread NotificationService.lastScheduleIssue to recover a precise cause.

The private todo failure store may become `Map<String, ReminderSyncIssueEntry>` with `.raw` projected by the legacy API, or keep a rigorously synchronized parallel metadata map. The structured map has fewer opportunities for mismatched raw/copy. In either choice, preserve exactly the same assignments, clear/remove sites and putIfAbsent precedence. An unknown overwrite must clear/replace earlier typed metadata, and the confirmation fallback must not replace an existing precise dispatch failure.

## Aggregate ordering and target isolation

The current collectors are **not one combined list**. `_syncTodosLocked` adds unresolved preflight summaries first, then awaits `_syncRuleObjects`. If `_syncRuleObjects` throws, the earlier unresolved list is never emitted by the outer throw. Thus a snapshot with both unresolved and failed resolved rules currently exposes the rule aggregate exception only. Preserve this behavior; do not combine, reorder, deduplicate or sort the collectors during the copy migration.

Within `_syncRuleObjects`, failures from the prior-scheduled-object loop precede failures from the new-wanted-object loop, each in the existing map/rule traversal order. Raw failures and metadata entries must be one-to-one in that same order. Preserve the location of the final scheduled-map replacement and throw.

Target-only API suppresses aggregate failures belonging to other objects and returns only the selected todo's map value. It may return null despite other failures. It must not receive the full exception entries as its target metadata. Full-list API continues reporting the aggregate exception. `_createQuickTodoFromAction` currently does **not** set `reportReminderScheduleFailure:true`; preserve its all-list behavior in this wiring slice.

## TodoProvider timing and generation requirements

Add optional `ReminderSyncIssue? issueCopy` to `TodoReminderSyncResult`, default null, leaving `generation`, `issue`, `attemptedAt`, `succeededAt`, `hasIssue` and all existing String getters intact. Add raw/copy mirror fields/getters only where needed to retain late state. Clear them at the exact places the corresponding raw fields clear: scheduler-missing setter branch, resetLocalState, and guarded pre-request schedule-issue reset. Apply them beside the existing raw assignments under the existing checks.

`resultFor` gains an optional copy argument; its existing `succeededAt: confirmed && issue == null ? DateTime.now() : null` rule stays. Do not decide failure/confirmation from the presence of copy. Do not treat a metadata-only result as an issue if legacy raw is null.

Preserve all branches:

- Normal success: raw null, copy null, confirmed success timestamp.
- Normal known failure: same raw value plus captured copy.
- Scheduler missing: raw sentinel `reminder_scheduler_missing` unchanged. It can receive a separate explicit owned copy at this producer; never replace the raw sentinel with translated text.
- Confirmation timeout: raw null, copy null, `confirmed:false`, succeededAt null; scheduling continues. No new registration-failed or timeout-failed copy/message.
- Late success/failure: reuse the **same pending structured Future**, not another scheduling call. Apply copy and raw together only after `isCurrent()`.
- Normal aggregate exception with empty failures: preserve the existing raw fallback `提醒未注册成功，请检查通知权限、提醒方式和提醒时间。`.
- Late aggregate exception with empty failures: preserve the current empty String from `error.failures.join('；')`; do not normalize this to null or the normal fallback. The old `hasIssue` remains `issue != null`, so empty late issue is still an issue.
- Unknown normal/late exception: raw `error.toString()` unchanged and literal-only metadata unless the producer supplied an explicit descriptor.

Account/storage/request suppression remains `_isCurrentStorageGeneration(storageGeneration, accountGeneration)` AND `generation == _nextReminderSyncGeneration`; `_applyReminderSyncResult` retains its own older-generation check. No typed field may update before/outside these guards. Reset must still increment storage and request generations before clearing state. Late handlers keep current notify/debug timing. An older result must not overwrite newer raw **or** copy state; account reset must suppress both.

## Widget delivery

Add an optional `ReminderSyncIssue? syncIssue` (or consistently named syncIssueCopy) to `WidgetActionMessage`, distinct from its existing single native/preflight issueCopy. In main's savedReminderIssue construction capture `reminderSyncResult?.issueCopy` and keep `detail: reminderSyncIssue` as the exact legacy raw fallback. Do not render at save time or reread provider diagnostics at display time.

In render, compute saved reminder detail as `syncIssue?.render(locale: effectiveLocale) ?? detail`, and use it only for savedReminderIssue. The outer neutral saved wrapper remains `Task saved on this device. Check reminder status: ...` / its existing zh counterpart. Existing raw constructors remain literal, including empty/custom reasons. Use the same already-resolved effectiveLocale for every entry and nested descriptor.

Do not change `_showWidgetActionFeedbackFromShell`, WidgetActionScope, mounted checks, original-provider binding or runWidgetQuickTodoAction lifetime guards. Timeout still returns the existing ordinary saved notice; a late provider diagnostic update must not replay a stale widget toast. The separate dialog/smart-capture String snackbars at main:4770 and main:4898 are outside this bounded widget delivery slice.

## Existing source/runtime assertions to retain and extend

Existing evidence read:

- `test/providers/todo_recurrence_reminder_test.dart:87`: missing scheduler raw sentinel, raw errors, successful sync and persisted todo preservation.
- Same file:124/167: awaited sync and stale background result suppression.
- Same file:210–232: timeout is not failure; late target result updates diagnostics.
- Same file:254–276: `_GatedTodoScheduler` overrides both legacy APIs. The new provider path must still call those overrides exactly once.
- `test/test_support/recording_reminder_scheduler.dart:21`: virtual full-list sync override records invocations/errors.
- `test/services/reminder_scheduler_integration_test.dart:1784`: target false-result raw includes `系统通知服务返回未注册`.
- Same file:1275: unresolved aggregate raw Chinese and diagnostic values remain canonical.
- `test/services/widget_action_message_test.dart:54–88`: raw service/custom reasons retained in both locales; neutral saved wrapper.
- `test/services/widget_quick_todo_action_test.dart:450–505`: original provider binding, caller availability, scoped afterFrame delivery and saved raw detail.
- `test/providers/todo_batch_operations_test.dart:227–289`: precise source-shape assertions currently mention Future<String?> pending and old resultFor expressions. If intentionally updated for additive metadata, retain behavioral assertions rather than forcing a new scheduling call to satisfy a substring.

Proposed additional assertions (not executed):

1. One legacy virtual invocation for plain override Future and for base capability Future; no duplicate native scheduling/queue work.
2. Base target capability raw await equals the old String exactly; typed await is the same result snapshot. Standard Future operations retain success/errors.
3. A typed-only consumer does not create an unobserved raw derived Future error.
4. Two queued target invocations for the same ID each retain their own captured entry after a later invocation rewrites the map.
5. Target success with another object's failure stays null/no copy; full-list failure keeps full original aggregate and order.
6. Preflight message-only target and titleAndMessage aggregate render their intended shapes; mixed typed/unknown entries preserve literal suffixes and duplicate order.
7. Combined unresolved and rule failure preserves existing throw precedence; each emitted metadata item corresponds to the emitted raw item, not a suppressed collector.
8. Structured map/parallel metadata clears follow raw clears; unknown overwrite removes stale copy; putIfAbsent preserves precise native entry.
9. Timeout returns raw null/copy null/succeededAt null; late genuine failure applies both fields once; late success stamps success without new scheduling.
10. Request-generation supersession, account reset and storage reset suppress old raw and copy in normal and late branches; saved todo remains persisted.
11. Normal/late empty aggregate raw asymmetry and missing scheduler sentinel stay exact.
12. Captured widget sync metadata renders after locale change using explicit delivery locale, without changing I18n.current or rereading native/provider state; account change before queued frame suppresses display.
13. Legacy raw widget constructor still contains exact literal reason in zh/en. Typed aggregate preserves user names, quotes, newlines, dates, rule labels and unknown reasons; no heuristic translation.

## Conclusion

The returned-Future capability is the minimal path that simultaneously preserves the existing virtual String API, single scheduling invocation, target isolation and race-free metadata capture. Optional exception entries handle full-list failure without changing syncTodos or its overrides. Optional result/widget fields carry that same captured metadata through timeout and late completion while keeping all legacy raw values and guards authoritative.

## Actual five-path production source audit

Read the implementation in `reminder_sync_issue.dart`, `reminder_scheduler.dart`, `todo_provider.dart`, `widget_action_message.dart`, and `main.dart` after root's source-ready handoff. No production edits or verification commands were performed by this agent. No remaining source blocker found in this bounded scope. Final formatting snapshot hashes were collected after root's formatting-complete handoff; this conclusion is not compile/runtime/frozen verification evidence.

### Types, projection and explicit codes

Actual `ReminderSyncIssueEntry` is final with const constructor and final fields. `includeTitle` is the explicit message versus titleAndMessage projection for existing ReminderIssueCopy. Native/preflight title/message fallbacks are captured literal fields. Copy takes priority over notice; production constructors use the appropriate single metadata source. No-copy/no-notice entries return raw unchanged.

Actual `ReminderSyncIssue` owns an unmodifiable list. Its raw property exactly maps entry.raw and joins `；`; display uses the selected locale's separator and explicitly forwards the same locale to all entries. No sorting, dedup, raw-text parsing or provider/native lookup is introduced.

Explicit owned notice codes include schedulerMissing, registrationUnconfirmed, pushNotRegistered, repeatingPushNotRegistered, ruleNotRegistered and genericFailure. Rule copy snapshots object type, ReminderKind and original rule.body. task/goal/generic titles, all five channel labels and every existing hint have explicit zh/en branches. The zh rule summary retains the original nonempty untrimmed body and original punctuation, including the space before `的`.

The two synthetic false-result StateErrors receive notice codes directly at their once/daily creation sites. Their raw entry still uses exactly error.toString(), including its legacy StateError prefix. Typed display deliberately presents the owned reason without that diagnostic prefix; the canonical raw value is not rewritten. Scheduler-missing likewise retains its sentinel raw value and has friendly explicitly owned display copy. Unknown errors remain literal rather than being classified by matching those known strings.

### Future and source compatibility

`ReminderTodoFailureFuture` implements `Future<String?>` and `ReminderTodoFailureResultFuture`; `issueResult` is the one underlying structured operation. Its raw projection is a `late final Future<String?> _legacy`, so it is not constructed unless a legacy Future method is observed. All five standard Future instance methods delegate to that projection. A provider observing only issueResult creates no derived raw Future; both representations derive from the same operation, not two schedules.

The existing public `syncTodosAndGetTodoFailure` signature is unchanged and now returns the wrapper from a non-async forwarding method. Private `_syncTodosAndGetTodoIssue` contains the previous snapshot/account/serialization/aggregate-catch logic and captures the immutable target issue **inside** the serialized action before it completes. No mutable map read occurs after serialization to populate metadata.

TodoProvider calls the old virtual target method once and detects capability on the returned Future before transformations. Plain Future overrides become literal ReminderSyncIssue results; they are not bypassed by a call to the base private method. Full-list still calls the old virtual syncTodos exactly once and maps success to null. Existing legacy const exception calls and String result callers stay valid at source level; compilation/runtime override behavior was not executed.

### Scheduler raw and state contract

The todo failure map now stores immutable entries. Its clear/remove sites, assignment precedence and putIfAbsent behavior match the previous raw map. An unknown dispatch overwrite replaces an older typed entry completely; the bare confirmation fallback is inserted only when no precise entry exists.

Preflight target still returns message only; aggregate still stores `title：message`; typed NotificationScheduleUnavailableException dispatch still returns its original toString raw value; synthetic false-result and unknown error raw values remain exact. The exception retains final List<String> failures, old const positional constructor compatibility and exact toString prefix/join. Its optional `ReminderSyncIssue? issueCopy` supplies the ordered immutable entries rather than altering failures.

Only `_syncTodosLocked`'s unresolved collector and the shared `_syncRuleObjects` rule collector attach aggregate copy. Existing habit/anniversary/countdown collectors keep legacy raw constructors. The two rule add sites remain in their original loops with the same traversal order. The old shared-rule exception still prevents the outer unresolved list from being emitted. Cancellation, dispatch, prior-rule retention, pending probes, registry replacement and final scheduled-map update/throw locations are unchanged by these source changes.

### Provider timeout, late completion and identity

TodoReminderSyncResult gains optional issueCopy; all original fields/default behavior and hasIssue remain. Raw/copy mirrors clear together in scheduler injection's missing-sentinel branch, resetLocalState and guarded pre-request schedule reset. apply sets target raw/copy together, and `_applyReminderSyncResult` sets global raw/copy together beneath the existing generation checks.

Timeout still returns `resultFor(null, confirmed:false)` with no copy or success timestamp. The same pending Future is reused for late completion. Late success/failure checks isCurrent before raw/copy apply and notification. Request/account/storage guards and reset's generation increments are unchanged. Prior succeededAt is still updated only by a nonnull new success timestamp.

Normal aggregate empty failures still produce the old Chinese generic fallback, now with explicit genericFailure copy. Late empty aggregate still uses empty joined String and optional exception copy without substituting the normal fallback. Unknown normal and late exceptions retain raw toString with no inferred copy. No branch treats copy presence as proof of registration or as a new failure decision.

### Widget delivery

WidgetActionMessage gains independent optional `syncIssueCopy`. The savedReminderIssue branch uses that captured aggregate, with the existing effectiveLocale explicitly forwarded; literal detail remains fallback. Both localized outer strings receive the same explicit locale for interpolation. They are evaluated as immutable presentation only; no global locale change, provider/native lookup or new record is involved.

Main's widget saved path adds only `syncIssueCopy: reminderSyncResult?.issueCopy`, keeps raw `detail: reminderSyncIssue`, and keeps reportReminderScheduleFailure omitted/false. It preserves the original provider/auth binding, coordinator, mounted/account/caller guards and afterFrame rendering. The separate dialog/smart-capture String branches were not migrated. Timeout yields the existing ordinary saved notice; no late toast replay was added.

This batch carries explicit copy through the current todo/goal aggregate and target pipeline. It does not type every AlarmService reason or every domain's legacy aggregate, and does not change the precision of the existing bool-only notification result sink. Those raw paths remain subject to their original contracts.

### Final formatted production snapshot

Root notified final production formatting completed and the scheduler's unused dart:async import was removed. Hash collection followed that handoff. The other four hashes match the earlier source-read snapshot. Runtime fixture/regression work belongs to root and the fixture agents; it is outside this source audit and was not executed or treated as passed here.

| File | SHA-256 |
| --- | --- |
| `lib/services/reminder_sync_issue.dart` | `f3a42d17421cd8ded133af453374540b9b1f9146e41da02499aabf9916ff19d8` |
| `lib/services/reminder_scheduler.dart` | `562551326a06d79738e0e955d09d878bb9467297fed39076e2b1a9c1099fcb7b` |
| `lib/providers/todo_provider.dart` | `2e23f08586874d50fec70ae1133713b44afd4539b2647d161820bf087f77b48c` |
| `lib/services/widget_action_message.dart` | `ce641eeec55e53ce13364f50298ef3c89e64272958d8605b56c1daca66d4cea3` |
| `lib/main.dart` | `acde8067d142e2c97c1d39d50eb008736e37c9dcd3fe8fb7cc42bb9f8388a81b` |
