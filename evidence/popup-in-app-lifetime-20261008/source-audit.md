# Foreground in-app-only popup lifetime audit — 2026-10-08

## Scope and result

Read-only source audit of `ForegroundReminderPopupSink.scheduleInAppOnlyOnce`, its cancellation/generation/queue/dialog helpers, the popup sink interface, and NotificationService's diagnostic caller. No production/test/docs edits, tests, analyzer, build, git, network or runtime verification. Only this private report is written.

Audited source: `/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/foreground_reminder_popup_sink.dart`

SHA-256 of the existing, not-yet-corrected source: `84f0ca729e119423ad26301b8097fd59f35dc9b5bfc3c3ebba0fa9bbbd63c37a`

**Confirmed source blocker:** in-app-only scheduling awaits public `cancel(id)` and then installs a Timer without retaining the generation invalidated by that cancellation. A cancel/replacement during the await can be followed by obsolete Timer installation. The Timer callback removes tracking unconditionally, has no generation check, and calls `_show`, which reads the current generation rather than the old request's captured identity. A stale request can therefore show under a newer identity and remove another Timer's tracking.

**Confirmed clock inconsistency:** this method uses DateTime.now at 95 although the sink accepts nowGetter at 18/35–37 and the ordinary once/repeating methods use it. An injected clock can therefore make a logically future in-app reminder appear past, or produce a delay unrelated to the caller's clock.

Root owns the implementation and has proposed a concrete correction. This report establishes the current defect and correction contract; it does not claim that corrected source or fixtures have already passed.

## Source evidence

| Boundary | Existing source | Relevant behavior |
| --- | --- | --- |
| in-app-only registration | 87–107; await cancel at 94 | no captured generation or post-await current test; delay uses DateTime.now; Timer assigned to _timers[id] |
| in-app-only Timer callback | 99–105 | unconditionally removes _timers[id], checks foreground/context, directly calls _show with no original generation |
| public cancellation | 493–517 | _invalidate occurs before awaited dialog/fallback cleanup; no second timer invalidation after those awaits |
| invalidation | 520–524 | increments per-id generation and cancels only the Timer currently reachable through the map |
| fallback queue | 370–384 | per-id operations serialize and prior errors are observed; cancellation checks captured generation inside its operation |
| dialog queue | 541–556 | per-id operations serialize and check supplied generation before running |
| existing delivery pipeline | 386–462 | generation test before removing Timer tracking, serialized dialog show with generation, post-await checks; fallback cancellation controlled by cancelFallbackAfterDialog |
| _show identity | 630–681; generation read at 644 | reads _generations[id] at show time, so an obsolete callback can reserve a dialog using the newer cancel/replacement identity |
| diagnostic caller | notification_service.dart:1941–2011 | in-app-only chooses scheduleInAppOnlyOnce when supported; registration errors use inAppPopupFailed and explicitly say no ordinary notification fallback |

The ordinary once/repeating paths already capture generation synchronously and use the fenced delivery pipeline. The bounded correction should give in-app-only the same lifetime ownership while preserving its delivery channel and cancellation semantics.

## Concrete source sequences

These are source-derived sequences, not executed reproductions. Assume a future requested time and a mounted foreground context for popup observation.

### A second cancel can be followed by stale Timer installation

```dart
final oldRequest = sink.scheduleInAppOnlyOnce(
  id: id,
  title: oldTitle,
  body: oldBody,
  when: futureTime,
);
await sink.cancel(id);
await oldRequest;
```

1. Old scheduling calls cancel, which invalidates id to generation 1 and begins awaiting serialized cleanup.
2. The second cancel synchronously invalidates id to generation 2 while old scheduling is suspended. No old Timer exists yet, so it cannot cancel it.
3. Cleanup for the first cancel settles. Old scheduling resumes without checking generation 1 against generation 2, computes delay and installs its Timer.
4. The second cancel settles its own cleanup. Its invalidation occurred before Timer installation and it does not cancel _timers again at completion.
5. The surviving obsolete Timer fires. Its callback removes the id and `_show` reads generation 2, allowing old contents to reserve/show under the cancellation identity.

The async dialog/fallback queues provide the suspension even when no fallback or visible dialog exists; a gated fallback cancellation is another clear way for the overlapping interval to arise.

### A replacement leaves an old Timer orphaned and allows stale removal of current tracking

Start in-app-only request A; while its cancellation is suspended, start request B for the same id.

1. A invalidates to generation 1; B invalidates to generation 2 while A has not yet installed a Timer.
2. A resumes and installs T_A despite being stale.
3. With the normal queue order B later installs T_B at the same map key. The map no longer holds T_A and nothing canceled it, so T_A is orphaned.
4. If T_A fires while T_B is still pending, its unconditional `_timers.remove(id)` deletes T_B's tracking. It then calls `_show` with old contents and the current generation 2.
5. A later cancel cannot reach T_B through the map. If B is also in-app-only, its callback has no generation guard either and can deliver after that later cancellation. If B uses the normal scheduling path, its generation-aware callback suppresses its own stale delivery, but the old in-app-only request still delivered incorrectly and disrupted tracking.

This establishes stale resurrection, orphaning, and deletion of newer Timer tracking. It does **not** rely on a claim that A's installation necessarily occurs after B's installation and overwrites an already-installed newer Timer; the normal serialized cleanup order commonly installs A first. The lack of ownership checks is the defect, and the stale callback's tracking removal is concrete.

### Inconsistent logical clock

With nowGetter fixed at an earlier date and when set five seconds after that clock, ordinary scheduleOnce treats it as future while in-app-only compares against the real system date and throws the past-time StateError. With a later logical date it computes an excessive real-clock delay instead. Using nowGetter after cleanup makes registration decisions consistent with the sink's existing injected clock contract.

## Correction contract

1. **Capture lifetime before any awaited cleanup.** In scheduleInAppOnlyOnce synchronously call `final generation = _invalidate(id)`. Do not await public cancel and then read `_generations[id]`; that would adopt a newer request's identity. Do not invalidate twice through both the entry and public cancel.
2. **Factor existing cancellation cleanup into `_cancelGeneration(id, generation)`.** Public cancel captures `_invalidate(id)` and awaits that helper. In-app-only captures its own generation and awaits the same helper. The helper keeps dialog and fallback serialization, generation checks inside queued operations, current-only final visible-state cleanup, and original exception behavior.
3. **Preserve cleanup error handling exactly.** Existing cancel attempts dialog close and fallback cancel separately, retaining the first error/stack and still attempting the second cleanup. Throw with the original stack after both attempts. If an external cancellation was already issued while current and fails after supersession, retain its error; do not mask it merely because the generation later became stale. Prior queue error recovery and finally map cleanup stay attached.
4. **Check ownership after cleanup and before registration.** Immediately after awaiting the helper, return if `_isCurrent(id, generation)` is false. Stale schedules return silently like existing normal once/repeating generations. Compute `when.difference(nowGetter())` and retain the exact existing past-time StateError for a live invalid time. Only a current generation may install its Timer.
5. **Capture that same generation in Timer delivery.** Use `_prepareForegroundDelivery` with id, generation, title/body/payload and `cancelFallbackAfterDialog: false`. It checks identity before removing tracking, enters the serialized dialog queue using the same generation, and rechecks after waits. Do not call `_show` directly from this Timer. This also prevents a fired-but-waiting delivery from showing after cancel/replacement.
6. **Keep delivery in-app-only.** No `_scheduleFallbackOnce`, `_replaceFallback`, fallback schedule result call, repeating refresh or rearm. Prior fallback cancellation during cleanup remains intentional: switching to in-app-only must remove an old system fallback. Timer delivery with false must not cancel a newly owned fallback or register any fallback when background/context unavailable/show fails. No repeating callbacks should be supplied.
7. **Observe async UI delivery errors without inventing fallback failure.** An unawaited fenced delivery Future needs an error observer. For in-app-only, use an in-app-specific debugPrint catch or a genuinely popup-only reporter. `_reportFallbackIssue` is unsuitable for that catch: it writes a ReminderScheduleIssue to notificationFallback with the claim that the system notification fallback failed to update, although this path intentionally did not use one. The old direct Timer callback did not invoke that reporter. Preserve cleanup failure propagation to NotificationService's existing inAppPopupFailed handler.

Suggested registration/delivery shape (design only):

```dart
final generation = _invalidate(id);
await _cancelGeneration(id, generation);
if (!_isCurrent(id, generation)) return;
final delay = when.difference(nowGetter());
if (delay <= Duration.zero) {
  throw StateError('提醒时间已过去，popup 提醒未注册');
}
_timers[id] = Timer(delay, () {
  unawaited(
    _prepareForegroundDelivery(
      id: id,
      generation: generation,
      title: title,
      body: body,
      payload: payload,
      cancelFallbackAfterDialog: false,
    ).catchError((Object error, StackTrace stackTrace) {
      // In-app-only delivery observation; no fallback issue record.
      debugPrint('[ForegroundReminderPopupSink] in-app-only popup delivery failed: '
          '$error\n$stackTrace');
    }),
  );
});
```

No need to change the shared sink interfaces, NotificationService's typed diagnostic ownership, ordinary once/repeating fallback registration behavior, or global/account lifecycle to close this per-id hole. The visible-dialog duplicate window currently uses the real clock separately; this report's requested clock correction is the in-app scheduling delay/validation.

## Review assertions for root-owned verification

Not executed by this auditor:

- Overlap in-app-only A with cancel: after both settle, advancing past A cannot show or leave tracking that supersedes cancellation.
- Overlap A with in-app-only B and with normal once/repeating B: A cannot install or fire a stale Timer, remove B's tracking, or show old contents; later cancel still cancels/fences B.
- Cancel/replacement after a Timer fires but while dialog queue cleanup is pending: original generation cannot show or clear newer visible state.
- Injected nowGetter is used after cleanup; live past-time error text and live future scheduling remain intact.
- In-app-only may cancel old fallback during cleanup, but never calls fallback schedule/refresh/delivery-cancel; background or absent context produces no ordinary notification fallback.
- Dialog/fallback cleanup failures retain both-attempt behavior, first error/stack and propagation even for already-issued superseded calls.
- UI delivery exceptions are observed without a fallback registration issue record; NotificationService continues owning typed in-app registration failure copy.

## Conclusion

The existing source has a concrete per-id lifetime hole in in-app-only registration and delivery, plus an inconsistent clock read. Root's `_cancelGeneration` extraction and generation-aware delivery plan closes the proven async boundaries if it preserves the error and channel behavior above. A corrected-source handoff and hash are still required for an implementation-clean verdict.

## Final corrected-source audit

Root reported the baseline had stopped with 23 cases, 19 passing and four failing: obsolete dialogs were observed in cancel/overlap/mixed-replacement cases, and the injected clock was not read. Root then applied its prepared script and formatted the production file. These baseline results are parent-reported context, not independently verified by this auditor. The auditor did not read fixture work as evidence, execute the script, run checks, or intervene in the baseline/regression process.

Read the private `patch-popup-in-app-lifetime-oct8.py` as text only and reread the actual corrected production method, cancellation helper, per-id fallback/dialog queues, delivery pipeline, show identity/cleanup, and NotificationService's diagnostic caller. The script's two replacements and the actual formatted source follow the correction contract above; no further planned-code correction is needed from this bounded source review.

**Final audited source SHA-256:** `5ab49e36fcb09621c9a7278ea5dcdcc55714e91cbe9adbe24c2b9f5387f5ceef`

Source: `/tmp/duoyi-update-deploy-20261005-isvisjkp/source/lib/services/foreground_reminder_popup_sink.dart`

| Corrected boundary | Actual source evidence | Verdict |
| --- | --- | --- |
| lifetime capture | scheduleInAppOnlyOnce:94–96 | `_invalidate(id)` captured before the first await; the same generation is passed to cleanup and checked after cleanup; a superseded request returns before validation/Timer installation |
| clock/validation | :97–100 | delay reads nowGetter after cleanup; live past-time StateError text is unchanged |
| Timer callback ownership | :101–118; _prepareForegroundDelivery:398–435 | callback carries the original generation; identity checked at :409 before removing map tracking; it cannot remove or show under a replacement generation |
| queued dialog delivery | _showOrFallback:437–474; _serializeDialogOperation:555–570 | original generation checked before/inside serialized show and after the awaited queue; later cancellation or replacement suppresses queued stale show |
| in-app-only channel | callback sets cancelFallbackAfterDialog false at :109; repeating/default callbacks omitted | no fallback schedule, refresh/rearm or post-dialog fallback cancellation is added; background/missing-context/show-unavailable remain no-fallback paths |
| public/shared cleanup | cancel:503–506; _cancelGeneration:508–532 | public cancel invalidates once and delegates; in-app scheduling delegates using its already-captured generation; helper preserves separately attempted dialog/fallback cleanup |
| cleanup errors/queue policy | helper :513–531; serialized fallback operation :382–396 | retains first error and original stack, still attempts fallback cleanup after dialog failure, throws issued failures even after supersession; queued operations keep current checks, prior-error recovery and finally map cleanup |
| delivery errors | :110–116 | in-app-specific debugPrint observer is attached to the unawaited delivery Future; it does not call _reportFallbackIssue or add a fallback registration issue |
| diagnostic ownership | notification_service.dart:1941–2011 | registration/cleanup exceptions still reach the existing inAppPopupFailed typed diagnostic path; its no-ordinary-notification text remains |

Ordinary once/repeating fallback scheduling and its error reporter remain in their original paths. In-app-only cleanup still cancels any old system fallback, intentionally, but its delivery branch never creates one. Original show duplicate suppression and signature/generation-aware completion cleanup are retained. The independent real-clock visible-dialog duplicate window is unchanged; the requested injected-clock correction is the in-app registration delay.

**Final bounded source verdict: no remaining concrete blocker found in the corrected in-app-only lifetime/clock/error-channel contract.** The stale Timer installation, stale tracking removal/current-generation adoption, and inconsistent delay clock findings are closed in this actual hash. Already-issued cancellation operations may settle and still report their original errors; supersession suppresses subsequent registration/delivery without relabeling failures. This is a source audit conclusion, not a corrected regression, analyzer or deployment claim. Root owns the frozen regression/analyzer run for this source.

## Final unused-helper follow-up

Root reported the first corrected-source regression passed 502 checks and the analyzer then found the preexisting unused private `_rescheduleRepeatingFallbackSafely`. Root stopped both checks and removed that helper before the new frozen rerun. These results are parent-reported and apply to the earlier source; this auditor did not run or independently verify them.

Read the final actual source and searched `lib`/`test` for the removed helper and the active repeating fallback path. The removed private helper no longer appears. Active repeating registration still calls `_scheduleFallbackRepeating` through `_replaceFallback` (:135); foreground repeating delivery still awaits `_refreshRepeatingFallback` (:185), which retains its generation test, serialized replacement and nonblocking fallback-rebuild issue handling (:297–333). Foreground/background Timer rearm paths are retained. No reachable repeating registration, refresh, error reporting or rearm behavior is lost by removal of the unused helper.

Reread in-app-only registration/callback (:87–118), current-before-Timer-removal delivery (:362), dialog generation queue (:519), false post-dialog fallback cancellation branch (:401–438), and shared cancel cleanup/error propagation (:466–496). The prior lifetime/clock/error-channel verdict remains unchanged with no additional concrete source blocker.

**Latest audited popup source SHA-256:** `3c2f4c12822af714e508ddd3aa051b37cdb128396d0fba048e2b44377b4373b3`

This supersedes `5ab49e36…` for final delivery. Root owns fresh frozen regression/analyzer verification for this hash. This auditor only read source/searched text and appended this private report; no tests, analyzer, git or production edits were performed.
