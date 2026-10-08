# Initial delivery copy foundation — source audit

Date: 2026-10-08. Repository: `/tmp/duoyi-update-deploy-20261005-isvisjkp/source`.

Scope: new ReminderDeliveryCopy and its actual initial-registration integration in ReminderScheduler/NotificationService. This is not acceptance of pending-reminder locale refresh. No repository/test edits, tests, analyzer, builds, Git, network calls or process intervention were performed. Only this private report was created; runtime fixtures remain root/widget-agent owned.

## Actual source binding

The source changed during the first read (semanticFingerprint was added and a scheduler local became const). Reread the complete new copy object and relevant actual producer/cancellation paths, then confirmed these initial audited hashes, superseded by the correction binding below:

- `lib/services/reminder_delivery_copy.dart`: `e1abbee5930443e6b0bfea9d382e2b78a28508b30984e6240035903012655a2f`
- `lib/services/reminder_scheduler.dart`: `f8cda7324f93288cc614391a5b522ad0786f0f1c03ef5e02a5ae685653252c33`
- `lib/providers/notification_service.dart`: `d9472fb43d83e4cf6ba37e792fc2b5f2c4e4fdbc9ef635507308f76e210ea311`

Earlier read hashes `674e2415…` / `2969bdde…` are not the final binding. No passing runtime result is attached to any hash by this auditor.

## Concrete regression: translated local goal titles introduce backend email DELETE during ordinary resync

**Medium; cancellation-side side effect.** Goal email title itself is correctly fixed to canonical Chinese, but this does not isolate the email sink from ordinary reconciliation of local goals.

Actual source path:

1. `_titleFor('goal', type, localKind)` :5704–5717 now renders in I18n.current, so an otherwise unchanged push/popup/alarm goal registered in Chinese has a different English title after a locale change. Before this batch the local goal title was always the same Chinese string.
2. `_ResolvedRule.fingerprint` :1215 includes rendered title. `_sameScheduledRule` :4554–4558 therefore becomes false even with identical rule ID, schedule, payload and user body.
3. `_syncRuleObjects` :4387–4401 enters needsCancel and calls `_cancelRule` for that **local** goal rule.
4. `_cancelRule` :4221–4257 unconditionally invokes `_cancelEmail` :4244–4249 as part of its cross-channel cleanup.
5. Actual BackendReminderEmailSink.cancel :57–61 performs `client.delete('/api/reminders/email/$id')` when a client token is present.

A settled authenticated user who switches zh -> en and later has an ordinary `syncGoals`/full reconciliation will therefore cause a new backend DELETE for the local goal rule ID. The email rule's canonical title prevents its own re-registration/POST, but does not prevent these requests. This finding does **not** assert duplicate email scheduling or deletion of an unrelated differently keyed email rule. It establishes the newly introduced email cancellation call, and means that the broad claim "ordinary locale resync adds no email side effect" is not yet true.

Minimal root-owned correction: classify a local rule change whose logical intent/schedule/user facts are unchanged as a presentation-only replacement and use only local cancellation/replacement for that case. An explicit skipEmail option is acceptable if it is enabled only by that proved local presentation case; structural changes, email->local channel transitions, rule deletion and account cleanup must retain their existing email ownership cleanup. Do not disable email.cancel globally, remove local goal translation, or replace the email sink with a no-op.

The classification needs a captured neutral intent/structural fingerprint (or the retained resolved registration), not parsing the current pipe-joined fingerprint or consulting I18n.current on an old record. The new copy object's JSON semanticFingerprint is a useful collision-safe fact signature, but the scheduler has not yet retained/used it for this classification.

Required runtime fixture: register a non-empty local goal in zh with its ID still pending, use an email fake that records/throws on any schedule/cancel, change to en, perform ordinary syncGoals with identical goal data. Assert English local replacement with unchanged ID/time/payload and **zero email calls**. Add a mixed local+email goal case and assert its actual email rule is kept without a POST. Control cases must show that genuine email->local transitions and deleted email rules still cancel the old email owner. These source assertions are not a test result.

## Source properties confirmed in this bounded batch

| Requirement | Actual observation | Verdict |
| --- | --- | --- |
| Pure copy render | all facts are final; render takes explicit AppLocale/BrandStrings; no provider, global locale or clock read in render; semanticFingerprint is jsonEncode of typed facts | Suitable foundation. Global locale mutation is absent from the value object. |
| Raw user content | todo/goal body equals raw title; habit/anniversary/countdown interpolate the unchanged raw userTitle with no trim, substring replacement or translation | No new user-content mutation found. |
| Todo compatibility | `_todoTitle` uses new todo render; its zh `提醒：` and en `Reminder: ` exactly match existing I18n prefix keys; daily/weekly titles remain injected brand strings; bodies remain t.title | Existing locale-prefix behavior, including email's pre-existing locale behavior, is preserved. This does not claim newly frozen Todo email. |
| Goal email copy | `_titleFor` explicitly chooses AppLocale.zh for email; goal render's Chinese type labels and kind emoji match preceding implementation; body remains g.title | Email rule presentation remains canonical; distinct cancellation-side issue above remains. |
| Countdown email copy | `_syncCountdownsLocked` explicitly chooses AppLocale.zh for email; zh title/body match preceding strings; daysRemaining is captured once; ID/when/payload/fullScreen dispatch arguments unchanged | No new email presentation/fingerprint change found in this producer. |
| Primary habit push | actual NotificationService.scheduleHabitReminder renders semanticPush:true using its injected brand strings; default zh body remains `别忘了: <raw name>`; original habit ID, time/weekdays, confirm payload and history type remain | Intended brand/localization improvement; default zh semantic body preserved. |
| Nonprimary/generic habit | scheduler's generic push/popup/alarm paths use semanticPush:false body; `_habitTitle` still uses scheduler branding; independent rule IDs/time/weekdays/options/payload unchanged | Existing generic variant is kept, rather than changed to primary push's `别忘了` wording. |
| Anniversary semantic push | actual NotificationService.scheduleAnniversary renders kind:push, retaining 📅 prefix; still computes DateTime(year/month/day/hour/minute)-daysBefore, uses anni_<id>, and routes to duoyi://tab/calendar | No time/ID/payload change introduced by this batch. Existing scheduler-versus-wrapper time behavior was not rewritten. |
| Anniversary popup/alarm/email | popup 🔔 and alarm ⏰ render typed copy with original IDs/time/payload; actual email branch remains its old explicit zh ✉️ title/body | No new email scheduling copy change found. |

BrandStrings is supplied separately from locale. Caller code must supply the matching locale's strings; this foundation does not magically translate a caller's stale Chinese BrandStrings. Main already reinjects strings on locale changes. This is an API precondition, not a newly introduced runtime regression in the inspected caller paths.

## Public helper discrepancy to resolve before extending its email use

ReminderDeliveryCopy.anniversary(..., ReminderKind.email).render currently returns a 📅 prefix (:99–103), whereas the actual preserved anniversary email producer uses ✉️. The pure fixture explicitly expects 📅 for email, so it would not catch a future consolidation that changed real email copy to that helper. No current production email path calls this rendered result, so this is not a second current runtime regression.

Keep the helper explicitly local-only for anniversary email, or add the email ✉️ variant and update its pure fixture before replacing the preserved email producer. Do not reuse the current helper for actual anniversary email and claim byte-for-byte compatibility.

## Pending refresh goal remains open

This batch renders future initial registrations. It does not update OS notifications, popup timers or native alarm entries that were already pending. The following requirements from `native-reminder-locale-refresh-implementation-decision-oct8.md` remain implementation work:

- Successful physical-local ledger with exact original arguments and actual fallback owners; semantic copy retained for every successful part.
- Captured locale/presentation signature on resolved rules/scopes; no dynamic fingerprint getter.
- Dedicated serialized local copy refresh, cancel/dispatch isolation from email, unchanged IDs/times/payload/channel/actions and history counters.
- Auth transition/blocked guards through internal awaits and latest-locale retry after transition settles.
- Safe owned refresh independent of best-effort provider hydration; explicit unknown/legacy bootstrap and true success evidence where provider facts are needed.
- Native/Flutter action localization and locale persistence/forwarding through restored entries, receiver/service/fullscreen and snooze/auto-repeat; current hardcoded alarm buttons remain.
- Daily/report/holiday auxiliary pending registrations, which still bypass these initial five-family render integrations.

The legacy NotificationService todo body decoration also remains Chinese, and actions are still constructed later by concrete/native sinks. These are existing full-range delivery requirements rather than new foundation regressions. Reading the pure fixture confirms its intended assertions only; its execution and the expanded production-path integration fixture result remain with root.

**Initial bounded source verdict:** one concrete newly introduced cancellation-side email regression was outstanding at the initial audited hash. Other inspected initial-copy/time/identity/semantic paths met the requested foundation compatibility. The correction disposition follows; no pending-refresh completion or runtime-pass claim is made.

## Cancellation correction — final bounded source disposition

Root added the narrow presentation-only cancellation option. Reread the actual intent snapshot, local predicate, sole conditional call site, default cancellation paths and legacy Todo/Goal cleanup. This closes the specific regression above at:

**ReminderScheduler SHA-256:** `519f3ad4cb34ded9ac1ee7eae161fd179712d4f6b8fa03913e8bbe84c2d3db30`

Companion hashes remain:

- ReminderDeliveryCopy: `e1abbee5930443e6b0bfea9d382e2b78a28508b30984e6240035903012655a2f`
- NotificationService: `d9472fb43d83e4cf6ba37e792fc2b5f2c4e4fdbc9ef635507308f76e210ea311`

| Correction property | Actual source | Conclusion |
| --- | --- | --- |
| Captured logical intent | `_ResolvedRule.intentFingerprint` :1219–1238 JSON-encodes object type/id/rule ID, kind/mode/rule type/scope, raw body, payload, fullScreen/vibrate/snooze/repeat, when/hour/minute/weekdays; `_scheduledFromResolved` :5127–5136 stores its resulting String in `_ScheduledRule.intentFingerprint` | The prior signature is immutable and locale-neutral. JSON avoids delimiter collisions in user strings. Time, content, options and channel changes cannot qualify merely because their rendered title resembles the prior one. |
| Safe title exclusion for these families | Todo/Goal resolved bodies remain the verbatim user title | Excluding generated title preserves raw user-content identity; title-only locale/brand changes can be distinguished without losing a real title edit. This rule is bounded to these current Todo/Goal resolution families. |
| Local-only eligibility | `_isLocalPresentationChange` :4589–4594 rejects email/off, requires equal prior/next kind and captured intent Strings | Email->local, local->email, local channel changes and genuine schedule/content changes cannot suppress email ownership cleanup. |
| Unique skip-email call site | needsCancel :4417–4427 passes `includeEmail: !_isLocalPresentationChange(prior, nextRule)`; rg confirms no other includeEmail caller | A proved presentation-only change cancels local peers and dispatches the local replacement without the newly introduced backend DELETE. This is not a broad email disable. |
| Defaults remain intact | `_cancelRule` :4245 has includeEmail=true and guards only its email section :4268–4275; new registration, missing-queue, rule deletion, structural change and account cleanup paths retain their existing calls/defaults | Actual prior email ownership still participates in real reconciliation and reset. |
| Legacy cleanup has no hidden email path | `_cancelTodo` / `_cancelGoal` :3987–4026 only call notification and alarm cleanup; aliases :4028–4032 delegate directly | cancelLegacyOnce in the presentation branch does not bypass the new isolation via another backend DELETE. |

The independent copy semanticFingerprint addition does not alter any render branch. The final foundation source verdict is therefore **no remaining concrete blocker found in this bounded initial-delivery/cancellation correction batch**. The public anniversary-email helper discrepancy above remains a future-use compatibility constraint, not a current production email-path regression.

Root reports that the widget fixture owner is adding locale/zero-email-call and structural-change controls to the existing integration fixture. This auditor neither ran those fixtures nor treats their requested assertions as passing evidence. Required controls remain: stable known local goal -> locale replacement with zero email calls; changed raw body/time/options/type/kind -> ordinary email cleanup retained; actual email->local transition/deletion -> old email canceled. Final runtime acceptance remains root-owned against matching frozen hashes.

The complete pending-reminder locale refresh requirements in the preceding section and implementation decision report remain open. This correction fixes an initial-registration ordinary-resync side effect; it does not introduce an owned registration ledger, debounce, native copy update, account/hydration coordination or auxiliary pending refresh. Only this private report was edited in the follow-up.
