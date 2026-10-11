# Widget preview, publication copy and count-up cap acceptance

## Implemented scope

- Android standard previews consume the real 180×110 dp ratio (18/11) and omit the navigation footer; iOS medium previews retain 1.5 and the footer. The platform test seam belongs to each card. Existing compact/detailed behavior and enlarged-text accommodation remain.
- Cleared, blocked, absent and invalid publication states display “Open Duoyi to update this widget” / “打开多仪以更新小组件”, blank secondary content, zero daily counters and no entity/timer data. Published stale and ordinary fresh/empty states remain distinct. Calendar and Anniversary providers pass actual publication state to their content helpers, including generic targets; refresh accessibility and Focus timer summary consume the same state.
- Android count-up formatting clamps at 86,400 seconds; paused values clamp without writing sessions. Invalid/future/overflow anchors cannot start a live Chronometer. At a rendered cap, the static timer reads 24:00:00 and the Chronometer is stopped/hidden. Canonical state, nonce and timer fields fence PendingIntent creation and cap scheduling/cancellation through the actual store acceptance boundary. A final-clock crossing requests a revalidated update; already-capped capture does not loop. Positive cap deadlines still schedule after a crossing; callback refreshes the current canonical state. Countdown/cap intents remain separate (14101/14103).

## Serial root verification

| Evidence | Actual result | Scope |
| --- | --- | --- |
| `widget-preview-cap-jvm-final-acceptance-logs/` | **117 JVM tests**, compiler/test exit 0; 19 input hashes unchanged | Publication, frame/projection, real content helpers, display values, receipt retention and cap core; no Android provider runtime |
| `widget-preview-cap-flutter-final-v2-acceptance-20261011/` | **138 passed**, **1 skipped**, 12 suites; clean 14-item analysis; 34 hashes unchanged | Ten preview kinds in both locales/platform seams, narrow enlarged text, sample interactions and named resource/pin/launch/publication regressions |
| `widget-preview-cap-platform-final-compile-20261011/` | Kotlin compile exit 0; platform evidence finished at **2026-10-11T12:10:21.040172+00:00**; 350 unchanged inputs; **63 classes**, **36 declared components**; all 18 bytecode symbol checks true | Offline debug Kotlin/resource dependencies; compiled state-aware signatures and cap consumers. Flutter build excluded |
| `widget-preview-cap-final-input-recheck-20261011.json` | **363 combined accepted inputs** still match current source | Independent final source/evidence correspondence |

The one skipped interaction case follows its existing Sunday rule because no later weekday exists in that week's fixture. It was not executed. Counts overlap earlier batches and must not be added to a distinct full-project total.

## Initial findings and integration

Root copied ten terminal geometry files and five previously frozen cap files only after main matched each candidate baseline. Two existing stale-timer typed getter assertions were restored. Obsolete static assertions for the old aspect-ratio consumer and old Anniversary helper signature were updated to the actual consumers, including publication state.

The first Flutter run had an obsolete Anniversary signature failure; its runner also failed to parse the passing interaction line containing a skip count. Original evidence is preserved. The fresh v2 run records both passes and skips and supersedes those findings. Root verified the actual final logs and current hashes. AGY source-review conclusions and successful formatting were not counted as runtime evidence.

## Remaining acceptance

No Android/iOS device or Xcode is available. Pinning, resize, all ten live-data/actions, launcher replacement, Binder delivery, lifecycle and real alarm timing remain pending. Doze/inexact alarms can leave a host Chronometer growing briefly beyond 24 hours until a successful redraw; this change does not guarantee an instantaneous cap or redraw on every screen wake. Flutter preview fixtures do not prove native iOS rendering or device smoothness. There is no new APK, version bump, push or deployment in this batch. The full widget/style/global-locale/Mine/settings goal remains active.
