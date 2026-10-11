# Best Practices and Security Alignment Update — Widget Launch Intent and Deep-Link Dispatch

**Review state:** 2026-10-11, canonical repository `/home/ubuntu/duoyi`, HEAD `2704add` plus the owned uncommitted widget changes. This is a read-only security review of app code; only this report was written. The unified diff below is a snapshot of the 19 owned app source and service files at review time. It includes four untracked new files that plain `git diff` would omit. It excludes unrelated dirty work, tests, harness scripts, and unchanged manifest/build files.

## Security alignment area, impact, and priority

| Area | Priority and impact | Alignment action and conclusion |
| --- | --- | --- |
| Exported Activity intake and Intent routing | **High:** a local app can explicitly launch exported `MainActivity` with a forged widget action or URI. | Exact widget action, hierarchical `duoyi` scheme, host allowlist, and length cap gate native capture. Widget delivery is separated from ordinary deep links. **Aligned for the stated account-bound, non-auth provenance model; caller identity is not authenticated.** |
| Secure widget PendingIntents | **High:** mutable or implicit launch tokens could be changed or intercepted. | `home_widget` 0.7.0+1 creates an explicit `MainActivity` Intent with `FLAG_IMMUTABLE` on API 23+. The pin callback's mutable token targets a named non-exported receiver. No widget-tap PendingIntent flag changed in this diff. |
| Bound entity and action dispatch | **High:** a stale widget from another account/day could open a colliding ID or mutate current account data. | Fresh snapshot mutation/entity URLs carry day, UTC offset, and account nonce; Dart hydrates and validates before item lookup or bound action dispatch. Invalid entity links fall back to their section; invalid bound actions stop. **Aligned for newly sourced mutation/entity URLs.** |
| Buffered cold and warm delivery | **Medium:** `singleTop` reuse, plugin stream timing, or repeated identical URLs can collapse or replay taps. | Android assigns a fresh ID per accepted widget Intent; iOS does so for accepted `source=widget` URLs. Each queue retains up to 256 entries and ACKs terminal handoff. **Aligned within process lifetime and queue capacity for those paths.** |
| Diagnostic privacy | **Medium:** URLs can contain quick-todo text and account binding data. | Dart's four launch diagnostics now emit fixed status text rather than raw URI, host, path, query, nonce, or authored text. **Aligned in the reviewed launch path.** |
| Adjacent public deep-link actions | **High:** an external app can send an unmarked `duoyi://action/...` URI to exported `MainActivity`. | Existing `ACTION_VIEW` routing preserves unbound action behavior. This is **outside the source-marked widget transport guarantee** and remains an open authorization boundary for account-data actions. |

## Scope and implementation

- **Android component boundary.** `MainActivity` remains `android:exported="true"` and `launchMode="singleTop"` for launcher and public deep links (`android/app/src/main/AndroidManifest.xml:34–59`). On a new Activity instance, `onCreate` captures the launch Intent before `super.onCreate`; it skips capture when `savedInstanceState != null` to avoid replaying a recreated Activity's current Intent. When the Activity is already on top, `onNewIntent` first calls `setIntent(newIntent)`, then captures that *new* Intent, then calls `super.onNewIntent`, so Flutter/plugin observers see the same stamped data (`MainActivity.kt:59–67,81–98`). If the Activity is not at the top, `singleTop` may create a new instance and the `onCreate` path applies. The ordinary deep-link bridge excludes the widget action (`MainActivity.kt:593–599`).
- **Native widget parser and queue.** `DuoyiWidgetLaunchBridge.capture` accepts only `HOME_WIDGET_LAUNCH_ACTION`, a hierarchical `duoyi` URI, one of its 15 listed hosts, and at most 8192 Android string characters. It replaces all incoming `source` and `widget_delivery` values, appends one new UUID delivery ID, and never fills missing day/account bindings (`DuoyiWidgetLaunchBridge.kt:16–45`). The main-thread process queue holds at most 256 unacknowledged entries; `subscribe` snapshots them in receipt order, hot callbacks can overlap that snapshot, and ACK removes only the matching ID (`DuoyiWidgetLaunchQueue.kt:9–27`, `DuoyiWidgetLaunchBridge.kt:48–83`). Engine attachment uses an expected-channel guard so an old plugin detachment cannot remove a newer channel. No nested Intent extra is forwarded or launched, so `IntentSanitizer` is not needed for this path despite the project's existing AndroidX Core 1.13.1 dependency.
- **PendingIntent boundary.** Widget rows use `HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)`. The dependency constructs an explicit Intent and adds `FLAG_IMMUTABLE` on API 23+ (`/home/ubuntu/.pub-cache/hosted/pub.dev/home_widget-0.7.0+1/android/src/main/kotlin/es/antonborri/home_widget/HomeWidgetIntent.kt:13–42`). The separate widget-pin callback uses `FLAG_MUTABLE` on Android 12+ only because the launcher supplies the widget ID; its base Intent explicitly targets `DuoyiWidgetPinResultReceiver`, which is `exported="false"` (`MainActivity.kt:681–695`, `AndroidManifest.xml:141–143`). These facts do not authenticate a caller that sends its own explicit Intent to exported `MainActivity`.
- **Binding and dispatch.** `DuoyiWidgetSnapshot.actionUri` strips duplicate binding/delivery query keys and adds `source=widget`, published day, UTC offset, and account nonce only for a fresh render frame. `entityUri` sends stale/invalid item targets to a section fallback (`DuoyiWidgetSnapshot.kt:99–122`); Todo, Calendar, Anniversary, Course, Diary, Goal, Note, and Schedule item targets use it. iOS binds fresh entity and mutating action links the same way (`ios/DuoyiWidgets/DuoyiWidgets.swift:337–370`). The native bridge stamps provenance but does not forge account binding on an old URL. After hydration, `WidgetLinkDispatch` requires validation for sourced entity IDs and bound actions, then checks account generation and availability again before resolving IDs. Android validation checks the current native published snapshot state/day/offset/owner epoch (`lib/main.dart:688–706`); iOS validates the current account nonce/day/offset (`home_widget_service.dart:215–236`). A failed entity check opens only its section; a failed bound action is dropped (`widget_link_dispatch.dart:21–65`, `lib/main.dart:4406–4449`). `refresh_widgets` and an empty quick-todo that opens a draft are deliberate unbound exceptions for sourced widget URLs; source-marked quick-todo text that writes data stays bound. Plain external action URLs without a source marker bypass this binding decision, as noted below.
- **iOS receipt path.** `SceneDelegate` forwards every cold and warm URL context. With the scene manifest present, `AppDelegate` does not also capture `launchOptions` for the same cold open. The iOS buffer requires `source=widget`, validates scheme/host/size, allocates a new UUID even for identical URLs, and retains up to 256 entries until ACK. Both widget and ordinary deep-link channels reattach when Flutter messenger identity changes (`ios/Runner/AppDelegate.swift:12–159,162–195`, `ios/Runner/SceneDelegate.swift:5–27`, `ios/Runner/Info.plist:40–57`). Whole-widget targets and footer links are current plain section URLs; `actionURL` also leaves refresh and empty quick-todo unmarked. Concrete Todo detail, generic entity rows, and data-mutating action URLs are bound and sourced (`ios/DuoyiWidgets/DuoyiWidgets.swift:337–370,1188–1203,1585–1619,1825–1833,1951–1979,2201–2212`). The calendar summary resolves to a section or a supported entity host that generic row rendering binds (`ios/DuoyiWidgets/DuoyiWidgets.swift:652–708`). `urlContexts` is an unordered set, so multiple contexts within one callback have no guaranteed order.

## Limitations and residual risk

1. **Non-auth provenance.** The exported Activity can receive a forged explicit Intent. `HOME_WIDGET_LAUNCH_ACTION`, `source=widget`, and `widget_delivery` identify routing, not the sender or authority. Published day, UTC offset, and owner epoch isolate stale or other-account widget actions within the local workspace; they are not cryptographic sender authentication and do not prove that a specific item was rendered. A threat model requiring widget-only caller authentication needs a separate origin mechanism. Ordinary external `ACTION_VIEW` links deliberately retain their existing unbound detail behavior.
2. **Volatile handoff.** Both native queues are in memory. Android may lose a tap after process death if `savedInstanceState != null` suppresses recapture; either platform may lose a tap at capacity, and a crash between Dart's accepted dispatch and ACK can replay or lose a mutation. ACK is not a transaction around asynchronous provider writes. The 256-entry cap and Android 8192-character/iOS 8192-byte URL limits bound pending storage but reject the newest tap without app-visible feedback.
3. **Existing public action URL gap.** `MainActivity.duoyiDeepLinkFrom` accepts a `duoyi` URI from any non-widget action, including `ACTION_VIEW`. In Dart, `WidgetLinkDispatch.requiresBinding` returns false when `source=widget` is absent; the ordinary action router can then start focus, create a quick todo with text, complete a known todo ID, or check in a known habit ID (`MainActivity.kt:593–605`, `widget_link_dispatch.dart:21–40`, `lib/main.dart:4191–4289`). This behavior predates the new bridge. It does not bypass the stamped widget path, but a hostile local app with an item ID can trigger the existing public action surface without publication binding. **High priority** if the release policy expects all external URI mutations to require user confirmation or account-bound authorization.
4. **Current plain navigation and legacy links.** Current iOS whole-widget targets, footer navigation, refresh, and empty quick-todo URLs omit `source=widget`; they use the ordinary deep-link bridge and its single pending initial slot, so two early plain URLs can overwrite. These routes do not perform bound account-data mutation or open a concrete item ID. Cached old iOS widget URLs without `source=widget` also remain indistinguishable from ordinary external links and retain the URI-based action debounce or unbound detail behavior. This report does not audit unrelated receivers, geofences, services, file sharing, or server-side authorization.
5. **Adjacent exported extra (medium priority).** The exported Activity also honors `ReminderRingtoneService.extraStopRingtone` on arbitrary incoming Intents and stops its private ringtone service (`MainActivity.kt:64,85,586–591`). This predates this widget diff and is outside the reviewed widget dispatch, but a local app can invoke it through an explicit Intent. Review separately if stopping alarms must be restricted to app-owned notifications.
6. **Platform acceptance.** The portable Swift Foundation snapshot/launch and timer cores pass. An optional display-core attempt was canceled before Swift execution after the image disappeared from the local cache and the Docker client began pulling it again; no display-core pass is claimed. These runs do not compile Flutter/WidgetKit targets or verify actual scene and launcher behavior on iOS. No physical Android or iOS widget interaction was available for this review.

## Files modified in the reviewed app diff

- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiAnniversaryWidgetProvider.kt`
- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt`
- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCourseWidgetProvider.kt`
- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiDiaryWidgetProvider.kt`
- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiGoalWidgetProvider.kt`
- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiNoteWidgetProvider.kt`
- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiScheduleWidgetProvider.kt`
- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiTodoWidgetProvider.kt`
- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSnapshot.kt`
- `android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt`
- `ios/DuoyiWidgets/DuoyiWidgets.swift`
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/SceneDelegate.swift`
- `lib/main.dart`
- `lib/services/home_widget_service.dart`
- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetLaunchBridge.kt`
- `android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetLaunchQueue.kt`
- `lib/services/widget_launch_service.dart`
- `lib/services/widget_link_dispatch.dart`

Unchanged configuration reviewed: `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`, `ios/Runner/Info.plist`, and the dependency's `HomeWidgetIntent.kt`. Verification tooling outside the app diff: `scripts/ios_widget_snapshot_core_cases.swift`, `scripts/verify_ios_widget_snapshot_core.py`, and `scripts/verify_ios_widget_timer_core.py`.

## Testing and verification evidence

- Root-owned final Flutter widget regression: **103 passed** (`.dart_tool/task-temp-20261011/widget-launch-accepted-tests-final.log`, final `+103: All tests passed!`), after the required-call and safe-logging static assertions were strengthened. A separate final snapshot/publication/quick-todo persistence batch passed **32** (`widget-launch-compatible-services-final.log`).
- Root-owned Android queue JUnit: **5 passed** (reported by integration owner); `:app:testDebugUnitTest` ended `BUILD SUCCESSFUL` in `.dart_tool/task-temp-20261011/widget-launch-native-online-tests.log`. This report did not rerun the tests.
- Focused Dart analysis: `.dart_tool/task-temp-20261011/widget-launch-integration-final-analysis.log` and the later four-file `.dart_tool/task-temp-20261011/widget-launch-accepted-analysis.log` both report `No issues found!`.
- Root-owned portable Swift 6.2 Noble container: **23 snapshot/launch core cases and 19 timer core cases passed**, including the distinct identical cold URL case (`.dart_tool/task-temp-20261011/widget-launch-ios-container-final.log`, `.dart_tool/task-temp-20261011/widget-launch-ios-timer-final.log`). These are source-extracted Foundation cases, not Xcode/WidgetKit compilation or iOS device acceptance.
- Audit method: read-only source, manifest, dependency, and log inspection. No tests, Git mutations, or deployment were run by this auditor.

## Exact unified implementation diff

The following diff is the exact `git diff --no-ext-diff --no-color --unified=3` of the 15 tracked app files above, followed by `git diff --no-index --no-ext-diff --no-color --unified=3 -- /dev/null <path>` for each of the four untracked app files. It is relative to HEAD `2704add`; it is limited to these owned widget source/service files. Diff SHA-256: `08555879c591565ebdf5dd42ab31829cb6819e93225c9ad23e276127b444ca51`.

```diff
diff --git a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiAnniversaryWidgetProvider.kt b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiAnniversaryWidgetProvider.kt
index 5f4ee4c..dea7867 100644
--- a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiAnniversaryWidgetProvider.kt
+++ b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiAnniversaryWidgetProvider.kt
@@ -141,7 +141,8 @@ open class DuoyiAnniversaryWidgetProvider : DuoyiStyledWidgetProvider() {
                     HomeWidgetLaunchIntent.getActivity(
                         context,
                         MainActivity::class.java,
-                        Uri.parse(item1?.target ?: "duoyi://anniversary")
+                        DuoyiWidgetSnapshot.entityUri(frame,
+                            Uri.parse(item1?.target ?: "duoyi://anniversary"), Uri.parse("duoyi://anniversary"))
                     )
                 )
                 views.setOnClickPendingIntent(
@@ -149,7 +150,8 @@ open class DuoyiAnniversaryWidgetProvider : DuoyiStyledWidgetProvider() {
                     HomeWidgetLaunchIntent.getActivity(
                         context,
                         MainActivity::class.java,
-                        Uri.parse(item2?.target ?: "duoyi://anniversary")
+                        DuoyiWidgetSnapshot.entityUri(frame,
+                            Uri.parse(item2?.target ?: "duoyi://anniversary"), Uri.parse("duoyi://anniversary"))
                     )
                 )
                 views.setOnClickPendingIntent(
@@ -157,7 +159,8 @@ open class DuoyiAnniversaryWidgetProvider : DuoyiStyledWidgetProvider() {
                     HomeWidgetLaunchIntent.getActivity(
                         context,
                         MainActivity::class.java,
-                        Uri.parse(item3?.target ?: "duoyi://anniversary")
+                        DuoyiWidgetSnapshot.entityUri(frame,
+                            Uri.parse(item3?.target ?: "duoyi://anniversary"), Uri.parse("duoyi://anniversary"))
                     )
                 )
                 views.setOnClickPendingIntent(R.id.widget_anniversary_nav_todo, openTodo)
diff --git a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt
index a21805c..1877ad2 100644
--- a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt
+++ b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt
@@ -126,7 +126,8 @@ open class DuoyiCalendarWidgetProvider : DuoyiStyledWidgetProvider() {
                     views.setTextViewText(R.id.widget_calendar_event_summary, summaryResult.summary)
                     views.setViewVisibility(R.id.widget_calendar_event_summary, View.VISIBLE)
                     val openEvent = HomeWidgetLaunchIntent.getActivity(
-                        context, MainActivity::class.java, Uri.parse(summaryResult.target)
+                        context, MainActivity::class.java,
+                        DuoyiWidgetSnapshot.entityUri(frame, Uri.parse(summaryResult.target), Uri.parse("duoyi://calendar"))
                     )
                     views.setOnClickPendingIntent(R.id.widget_calendar_event_summary, openEvent)
                 } else {
diff --git a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCourseWidgetProvider.kt b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCourseWidgetProvider.kt
index b0aa3bd..bd35a40 100644
--- a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCourseWidgetProvider.kt
+++ b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCourseWidgetProvider.kt
@@ -127,15 +127,15 @@ open class DuoyiCourseWidgetProvider : DuoyiStyledWidgetProvider() {
                 views.setOnClickPendingIntent(R.id.widget_course_subtitle, openCourse)
                 views.setOnClickPendingIntent(
                     R.id.widget_course_1,
-                    itemIntent(context, prefs, "course_highlight_1_id", "duoyi://course")
+                    itemIntent(context, frame, "course_highlight_1_id", "duoyi://course")
                 )
                 views.setOnClickPendingIntent(
                     R.id.widget_course_2,
-                    itemIntent(context, prefs, "course_highlight_2_id", "duoyi://course")
+                    itemIntent(context, frame, "course_highlight_2_id", "duoyi://course")
                 )
                 views.setOnClickPendingIntent(
                     R.id.widget_course_3,
-                    itemIntent(context, prefs, "course_highlight_3_id", "duoyi://course")
+                    itemIntent(context, frame, "course_highlight_3_id", "duoyi://course")
                 )
                 views.setOnClickPendingIntent(R.id.widget_course_nav_todo, openTodo)
                 views.setOnClickPendingIntent(R.id.widget_course_nav_habit, openHabit)
@@ -148,11 +148,11 @@ open class DuoyiCourseWidgetProvider : DuoyiStyledWidgetProvider() {
     }
 
     companion object {
-        private fun itemIntent(context: Context, prefs: SharedPreferences, key: String, fallback: String) =
+        private fun itemIntent(context: Context, frame: DuoyiWidgetRenderFrame, key: String, fallback: String) =
             HomeWidgetLaunchIntent.getActivity(
                 context,
                 MainActivity::class.java,
-                detailUri(prefs, key, fallback)
+                DuoyiWidgetSnapshot.entityUri(frame, detailUri(frame.prefs, key, fallback), Uri.parse(fallback))
             )
 
         private fun detailUri(prefs: SharedPreferences, key: String, fallback: String): Uri {
diff --git a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiDiaryWidgetProvider.kt b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiDiaryWidgetProvider.kt
index 7023a83..1563073 100644
--- a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiDiaryWidgetProvider.kt
+++ b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiDiaryWidgetProvider.kt
@@ -122,15 +122,15 @@ open class DuoyiDiaryWidgetProvider : DuoyiStyledWidgetProvider() {
                 views.setOnClickPendingIntent(R.id.widget_diary_subtitle, openDiary)
                 views.setOnClickPendingIntent(
                     R.id.widget_diary_1,
-                    itemIntent(context, prefs, "diary_highlight_1_id", "duoyi://diary")
+                    itemIntent(context, frame, "diary_highlight_1_id", "duoyi://diary")
                 )
                 views.setOnClickPendingIntent(
                     R.id.widget_diary_2,
-                    itemIntent(context, prefs, "diary_highlight_2_id", "duoyi://diary")
+                    itemIntent(context, frame, "diary_highlight_2_id", "duoyi://diary")
                 )
                 views.setOnClickPendingIntent(
                     R.id.widget_diary_3,
-                    itemIntent(context, prefs, "diary_highlight_3_id", "duoyi://diary")
+                    itemIntent(context, frame, "diary_highlight_3_id", "duoyi://diary")
                 )
                 views.setOnClickPendingIntent(R.id.widget_diary_nav_todo, openTodo)
                 views.setOnClickPendingIntent(R.id.widget_diary_nav_habit, openHabit)
@@ -143,11 +143,11 @@ open class DuoyiDiaryWidgetProvider : DuoyiStyledWidgetProvider() {
     }
 
     companion object {
-        private fun itemIntent(context: Context, prefs: SharedPreferences, key: String, fallback: String) =
+        private fun itemIntent(context: Context, frame: DuoyiWidgetRenderFrame, key: String, fallback: String) =
             HomeWidgetLaunchIntent.getActivity(
                 context,
                 MainActivity::class.java,
-                detailUri(prefs, key, fallback)
+                DuoyiWidgetSnapshot.entityUri(frame, detailUri(frame.prefs, key, fallback), Uri.parse(fallback))
             )
 
         private fun detailUri(prefs: SharedPreferences, key: String, fallback: String): Uri {
diff --git a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiGoalWidgetProvider.kt b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiGoalWidgetProvider.kt
index ca69018..05d9a55 100644
--- a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiGoalWidgetProvider.kt
+++ b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiGoalWidgetProvider.kt
@@ -126,15 +126,15 @@ open class DuoyiGoalWidgetProvider : DuoyiStyledWidgetProvider() {
                 views.setOnClickPendingIntent(R.id.widget_goal_subtitle, openGoal)
                 views.setOnClickPendingIntent(
                     R.id.widget_goal_1,
-                    itemIntent(context, prefs, "goal_highlight_1_id", "duoyi://goal")
+                    itemIntent(context, frame, "goal_highlight_1_id", "duoyi://goal")
                 )
                 views.setOnClickPendingIntent(
                     R.id.widget_goal_2,
-                    itemIntent(context, prefs, "goal_highlight_2_id", "duoyi://goal")
+                    itemIntent(context, frame, "goal_highlight_2_id", "duoyi://goal")
                 )
                 views.setOnClickPendingIntent(
                     R.id.widget_goal_3,
-                    itemIntent(context, prefs, "goal_highlight_3_id", "duoyi://goal")
+                    itemIntent(context, frame, "goal_highlight_3_id", "duoyi://goal")
                 )
                 views.setOnClickPendingIntent(R.id.widget_goal_nav_todo, openTodo)
                 views.setOnClickPendingIntent(R.id.widget_goal_nav_habit, openHabit)
@@ -147,11 +147,11 @@ open class DuoyiGoalWidgetProvider : DuoyiStyledWidgetProvider() {
     }
 
     companion object {
-        private fun itemIntent(context: Context, prefs: SharedPreferences, key: String, fallback: String) =
+        private fun itemIntent(context: Context, frame: DuoyiWidgetRenderFrame, key: String, fallback: String) =
             HomeWidgetLaunchIntent.getActivity(
                 context,
                 MainActivity::class.java,
-                detailUri(prefs, key, fallback)
+                DuoyiWidgetSnapshot.entityUri(frame, detailUri(frame.prefs, key, fallback), Uri.parse(fallback))
             )
 
         private fun detailUri(prefs: SharedPreferences, key: String, fallback: String): Uri {
diff --git a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiNoteWidgetProvider.kt b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiNoteWidgetProvider.kt
index b6497ed..feb1975 100644
--- a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiNoteWidgetProvider.kt
+++ b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiNoteWidgetProvider.kt
@@ -122,15 +122,15 @@ open class DuoyiNoteWidgetProvider : DuoyiStyledWidgetProvider() {
                 views.setOnClickPendingIntent(R.id.widget_note_subtitle, openNote)
                 views.setOnClickPendingIntent(
                     R.id.widget_note_1,
-                    itemIntent(context, prefs, "note_highlight_1_id", "duoyi://note")
+                    itemIntent(context, frame, "note_highlight_1_id", "duoyi://note")
                 )
                 views.setOnClickPendingIntent(
                     R.id.widget_note_2,
-                    itemIntent(context, prefs, "note_highlight_2_id", "duoyi://note")
+                    itemIntent(context, frame, "note_highlight_2_id", "duoyi://note")
                 )
                 views.setOnClickPendingIntent(
                     R.id.widget_note_3,
-                    itemIntent(context, prefs, "note_highlight_3_id", "duoyi://note")
+                    itemIntent(context, frame, "note_highlight_3_id", "duoyi://note")
                 )
                 views.setOnClickPendingIntent(R.id.widget_note_nav_todo, openTodo)
                 views.setOnClickPendingIntent(R.id.widget_note_nav_habit, openHabit)
@@ -143,11 +143,11 @@ open class DuoyiNoteWidgetProvider : DuoyiStyledWidgetProvider() {
     }
 
     companion object {
-        private fun itemIntent(context: Context, prefs: SharedPreferences, key: String, fallback: String) =
+        private fun itemIntent(context: Context, frame: DuoyiWidgetRenderFrame, key: String, fallback: String) =
             HomeWidgetLaunchIntent.getActivity(
                 context,
                 MainActivity::class.java,
-                detailUri(prefs, key, fallback)
+                DuoyiWidgetSnapshot.entityUri(frame, detailUri(frame.prefs, key, fallback), Uri.parse(fallback))
             )
 
         private fun detailUri(prefs: SharedPreferences, key: String, fallback: String): Uri {
diff --git a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiScheduleWidgetProvider.kt b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiScheduleWidgetProvider.kt
index dcc0352..5ae4f36 100644
--- a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiScheduleWidgetProvider.kt
+++ b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiScheduleWidgetProvider.kt
@@ -137,15 +137,15 @@ open class DuoyiScheduleWidgetProvider : DuoyiStyledWidgetProvider() {
                 views.setOnClickPendingIntent(R.id.widget_schedule_subtitle, openCalendar)
                 views.setOnClickPendingIntent(
                     R.id.widget_schedule_1,
-                    itemIntent(context, prefs, "schedule_highlight_1_id", "duoyi://calendar")
+                    itemIntent(context, frame, "schedule_highlight_1_id", "duoyi://calendar")
                 )
                 views.setOnClickPendingIntent(
                     R.id.widget_schedule_2,
-                    itemIntent(context, prefs, "schedule_highlight_2_id", "duoyi://calendar")
+                    itemIntent(context, frame, "schedule_highlight_2_id", "duoyi://calendar")
                 )
                 views.setOnClickPendingIntent(
                     R.id.widget_schedule_3,
-                    itemIntent(context, prefs, "schedule_highlight_3_id", "duoyi://calendar")
+                    itemIntent(context, frame, "schedule_highlight_3_id", "duoyi://calendar")
                 )
                 views.setOnClickPendingIntent(R.id.widget_schedule_nav_todo, openTodo)
                 views.setOnClickPendingIntent(R.id.widget_schedule_nav_habit, openHabit)
@@ -158,11 +158,11 @@ open class DuoyiScheduleWidgetProvider : DuoyiStyledWidgetProvider() {
     }
 
     companion object {
-        private fun itemIntent(context: Context, prefs: SharedPreferences, key: String, fallback: String) =
+        private fun itemIntent(context: Context, frame: DuoyiWidgetRenderFrame, key: String, fallback: String) =
             HomeWidgetLaunchIntent.getActivity(
                 context,
                 MainActivity::class.java,
-                detailUri(prefs, key, fallback)
+                DuoyiWidgetSnapshot.entityUri(frame, detailUri(frame.prefs, key, fallback), Uri.parse(fallback))
             )
 
         private fun detailUri(prefs: SharedPreferences, key: String, fallback: String): Uri {
diff --git a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiTodoWidgetProvider.kt b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiTodoWidgetProvider.kt
index e319d46..98a6af2 100644
--- a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiTodoWidgetProvider.kt
+++ b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiTodoWidgetProvider.kt
@@ -237,7 +237,9 @@ open class DuoyiTodoWidgetProvider : DuoyiStyledWidgetProvider() {
             HomeWidgetLaunchIntent.getActivity(
                 context,
                 MainActivity::class.java,
-                Uri.parse("duoyi://todo/$encodedTodoId")
+                DuoyiWidgetSnapshot.entityUri(
+                    frame, Uri.parse("duoyi://todo/$encodedTodoId"), Uri.parse("duoyi://todo")
+                )
             )
         )
         views.setOnClickPendingIntent(
diff --git a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSnapshot.kt b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSnapshot.kt
index a24a2f9..52fce59 100644
--- a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSnapshot.kt
+++ b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSnapshot.kt
@@ -98,7 +98,13 @@ object DuoyiWidgetSnapshot {
 
     fun actionUri(frame: DuoyiWidgetRenderFrame, action: Uri): Uri {
         require(frame.fresh) { "Widget action requires a fresh published session" }
-        return action.buildUpon()
+        val bindingKeys = setOf("source", "widget_day", "widget_offset", "widget_account", "widget_delivery")
+        val builder = action.buildUpon().clearQuery()
+        for (name in action.queryParameterNames) {
+            if (name in bindingKeys) continue
+            for (value in action.getQueryParameters(name)) builder.appendQueryParameter(name, value)
+        }
+        return builder
             .appendQueryParameter("source", "widget")
             .appendQueryParameter("widget_day", frame.core.day)
             .appendQueryParameter("widget_offset", frame.core.offset.toString())
@@ -106,6 +112,15 @@ object DuoyiWidgetSnapshot {
             .build()
     }
 
+    fun entityUri(frame: DuoyiWidgetRenderFrame, target: Uri, fallback: Uri): Uri {
+        val hosts = setOf("todo", "habit", "course", "note", "diary", "goal",
+            "anniversary", "countdown", "time-entry", "calendar", "focus", "tab")
+        if (!frame.fresh || target.scheme != "duoyi" || !target.isHierarchical || target.host !in hosts) {
+            return fallback
+        }
+        return runCatching { actionUri(frame, target) }.getOrDefault(fallback)
+    }
+
     private fun finishRender(views: RemoteViews, frame: DuoyiWidgetRenderFrame) {
         val prefs = frame.prefs
         val width = frame.core.options.minWidth
diff --git a/android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt b/android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt
index 5c00828..141df9b 100644
--- a/android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt
+++ b/android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt
@@ -57,6 +57,9 @@ class MainActivity : FlutterActivity() {
     private var lastWidgetRestoreAtMillis = 0L
 
     override fun onCreate(savedInstanceState: Bundle?) {
+        // A recreation reuses the launch Intent. Its queued tap already lives
+        // in the process bridge; only a new Activity launch receives a new ID.
+        if (savedInstanceState == null) DuoyiWidgetLaunchBridge.capture(intent)
         super.onCreate(savedInstanceState)
         stopReminderRingtoneIfRequested(intent)
         pendingInitialDeepLink = duoyiDeepLinkFrom(intent)
@@ -76,8 +79,9 @@ class MainActivity : FlutterActivity() {
     }
 
     override fun onNewIntent(intent: Intent) {
-        super.onNewIntent(intent)
         setIntent(intent)
+        DuoyiWidgetLaunchBridge.capture(intent)
+        super.onNewIntent(intent)
         stopReminderRingtoneIfRequested(intent)
         val deepLink = duoyiDeepLinkFrom(intent)
         val link = oauthDeepLinkFrom(intent)
@@ -118,6 +122,9 @@ class MainActivity : FlutterActivity() {
 
     override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
         super.configureFlutterEngine(flutterEngine)
+        if (!flutterEngine.plugins.has(DuoyiWidgetLaunchPlugin::class.java)) {
+            flutterEngine.plugins.add(DuoyiWidgetLaunchPlugin())
+        }
         if (!flutterEngine.plugins.has(DuoyiWidgetPublicationBridge::class.java)) {
             flutterEngine.plugins.add(DuoyiWidgetPublicationBridge())
         }
@@ -584,7 +591,7 @@ class MainActivity : FlutterActivity() {
     }
 
     private fun duoyiDeepLinkFrom(intent: Intent?): String? {
-        // HomeWidget owns this launch in both cold-start and onNewIntent paths.
+        // The app-owned widget bridge handles cold and warm widget launches.
         if (intent?.action == HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION) return null
         val uri = intent?.data ?: return null
         if (uri.scheme != "duoyi") return null
diff --git a/ios/DuoyiWidgets/DuoyiWidgets.swift b/ios/DuoyiWidgets/DuoyiWidgets.swift
index 4dc6ce3..6a8c7f4 100644
--- a/ios/DuoyiWidgets/DuoyiWidgets.swift
+++ b/ios/DuoyiWidgets/DuoyiWidgets.swift
@@ -336,8 +336,13 @@ private struct DuoyiWidgetSnapshot {
 
     func actionURL(_ components: URLComponents?, at date: Date, calendar: Calendar) -> URL? {
         guard var components = components else { return nil }
-        guard components.scheme?.lowercased() == "duoyi",
-              components.host?.lowercased() == "action" else { return components.url }
+        guard components.scheme?.lowercased() == "duoyi" else { return components.url }
+        let entityHosts = Set(["todo", "habit", "course", "note", "diary", "goal",
+                               "anniversary", "countdown", "time-entry"])
+        let host = components.host?.lowercased() ?? ""
+        let isEntity = entityHosts.contains(host) &&
+            components.percentEncodedPath.split(separator: "/").first != nil
+        guard host == "action" || isEntity else { return components.url }
         // Flutter dispatches the first decoded path segment, including when
         // extra trailing segments are present. Decode after splitting so an
         // encoded slash does not create a different action.
@@ -349,11 +354,11 @@ private struct DuoyiWidgetSnapshot {
             $0.name == "text" && !($0.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
         } ?? false
         // Opening quick entry and requesting refresh are recoverable navigation.
-        let mutates = ["complete_todo", "checkin_habit", "start_pomodoro"].contains(action) ||
+        let mutates = isEntity || ["complete_todo", "checkin_habit", "start_pomodoro"].contains(action) ||
             (action == "quick_todo" && hasQuickText)
         guard mutates else { return components.url }
         guard isFresh(at: date, calendar: calendar), let offset = utcOffsetMinutes else { return nil }
-        let bindingKeys = Set(["source", "widget_day", "widget_offset", "widget_account"])
+        let bindingKeys = Set(["source", "widget_day", "widget_offset", "widget_account", "widget_delivery"])
         var items = (components.queryItems ?? []).filter { !bindingKeys.contains($0.name) }
         items.append(contentsOf: [
             URLQueryItem(name: "source", value: "widget"),
@@ -1185,7 +1190,7 @@ private struct DuoyiTodoRow: Identifiable {
             return nil
         }
         let encodedId = todoId.addingPercentEncoding(withAllowedCharacters: duoyiPathSegmentAllowed) ?? todoId
-        return URL(string: "duoyi://todo/\(encodedId)")
+        return snapshot.actionURL(URLComponents(string: "duoyi://todo/\(encodedId)"))
     }
 
     var completeURL: URL? {
diff --git a/ios/Runner/AppDelegate.swift b/ios/Runner/AppDelegate.swift
index 2bc8e32..b8ad322 100644
--- a/ios/Runner/AppDelegate.swift
+++ b/ios/Runner/AppDelegate.swift
@@ -1,24 +1,121 @@
 import Flutter
+import Foundation
 import UIKit
 
+// BEGIN DUOYI_WIDGET_LAUNCH_CORE
+struct DuoyiWidgetLaunchDelivery {
+  let id: String
+  let uri: String
+  var payload: [String: String] { ["id": id, "uri": uri] }
+}
+
+final class DuoyiWidgetLaunchBuffer {
+  private var deliveries: [DuoyiWidgetLaunchDelivery] = []
+  private let maxPending: Int
+  private let nextID: () -> String
+
+  init(maxPending: Int = 256, nextID: @escaping () -> String = { UUID().uuidString }) {
+    self.maxPending = maxPending
+    self.nextID = nextID
+  }
+
+  func receive(url: URL) -> (handled: Bool, delivery: DuoyiWidgetLaunchDelivery?) {
+    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
+          components.scheme == "duoyi",
+          components.queryItems?.contains(where: { $0.name == "source" && $0.value == "widget" }) == true else {
+      return (false, nil)
+    }
+    let hosts = Set(["tab", "todo", "habit", "calendar", "focus", "widget", "course", "note",
+                     "diary", "goal", "anniversary", "countdown", "time-entry", "report", "action"])
+    guard hosts.contains(components.host ?? ""), url.absoluteString.utf8.count <= 8192 else {
+      return (true, nil)
+    }
+    guard deliveries.count < maxPending else { return (true, nil) }
+    let id = nextID()
+    var items = (components.queryItems ?? []).filter { $0.name != "source" && $0.name != "widget_delivery" }
+    items.append(URLQueryItem(name: "source", value: "widget"))
+    items.append(URLQueryItem(name: "widget_delivery", value: id))
+    components.queryItems = items
+    guard let tagged = components.url else { return (true, nil) }
+    let delivery = DuoyiWidgetLaunchDelivery(id: id, uri: tagged.absoluteString)
+    deliveries.append(delivery)
+    return (true, delivery)
+  }
+
+  func snapshot() -> [DuoyiWidgetLaunchDelivery] { deliveries }
+
+  func acknowledge(_ id: String) { deliveries.removeAll { $0.id == id } }
+}
+// END DUOYI_WIDGET_LAUNCH_CORE
+
+final class DuoyiWidgetLaunchBridge {
+  static let shared = DuoyiWidgetLaunchBridge()
+  private let buffer = DuoyiWidgetLaunchBuffer()
+  private var channel: FlutterMethodChannel?
+  private var messenger: FlutterBinaryMessenger?
+  private var subscribed = false
+
+  private init() {}
+
+  func attach(to messenger: FlutterBinaryMessenger) {
+    if let current = self.messenger, (current as AnyObject) === (messenger as AnyObject) { return }
+    channel?.setMethodCallHandler(nil)
+    self.messenger = messenger
+    subscribed = false
+    let next = FlutterMethodChannel(name: "duoyi/widget_launch", binaryMessenger: messenger)
+    channel = next
+    next.setMethodCallHandler { [weak self, weak next] call, result in
+      guard let self = self, let next = next, self.channel === next else {
+        result(FlutterError(code: "STALE_WIDGET_ENGINE", message: "Widget launch engine changed", details: nil))
+        return
+      }
+      switch call.method {
+      case "subscribe":
+        self.subscribed = true
+        result(self.buffer.snapshot().map { $0.payload })
+      case "unsubscribe":
+        self.subscribed = false
+        result(nil)
+      case "ack":
+        if let id = call.arguments as? String { self.buffer.acknowledge(id) }
+        result(nil)
+      default:
+        result(FlutterMethodNotImplemented)
+      }
+    }
+  }
+
+  func handle(url: URL) -> Bool {
+    let receipt = buffer.receive(url: url)
+    if let delivery = receipt.delivery, subscribed {
+      channel?.invokeMethod("onLaunch", arguments: delivery.payload)
+    }
+    return receipt.handled
+  }
+}
+
 final class DuoyiDeepLinkBridge {
   static let shared = DuoyiDeepLinkBridge()
 
   private let channelName = "duoyi/deep_links"
   private var channel: FlutterMethodChannel?
+  private var messenger: FlutterBinaryMessenger?
   private var pendingInitialLink: String?
   private var pendingInitialOAuthLink: String?
 
   private init() {}
 
   func attach(to messenger: FlutterBinaryMessenger) {
-    if channel != nil { return }
+    DuoyiWidgetLaunchBridge.shared.attach(to: messenger)
+    if let current = self.messenger, (current as AnyObject) === (messenger as AnyObject) { return }
+    channel?.setMethodCallHandler(nil)
+    self.messenger = messenger
     let nextChannel = FlutterMethodChannel(
       name: channelName,
       binaryMessenger: messenger
     )
-    nextChannel.setMethodCallHandler { [weak self] call, result in
-      guard let self = self else {
+    nextChannel.setMethodCallHandler { [weak self, weak nextChannel] call, result in
+      guard let self = self, let nextChannel = nextChannel, self.channel === nextChannel else {
         result(nil)
         return
       }
@@ -48,6 +145,7 @@ final class DuoyiDeepLinkBridge {
     guard let url = url, url.scheme == "duoyi" else {
       return false
     }
+    if DuoyiWidgetLaunchBridge.shared.handle(url: url) { return true }
     let link = url.absoluteString
     if initial || channel == nil {
       pendingInitialLink = link
@@ -71,10 +169,14 @@ final class DuoyiDeepLinkBridge {
     if let controller = window?.rootViewController as? FlutterViewController {
       DuoyiDeepLinkBridge.shared.attach(to: controller.binaryMessenger)
     }
-    DuoyiDeepLinkBridge.shared.handle(
-      url: launchOptions?[.url] as? URL,
-      initial: true
-    )
+    // SceneDelegate owns cold URL contexts when a scene manifest is present.
+    // Processing launchOptions too could count one physical launch twice.
+    if Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") == nil {
+      DuoyiDeepLinkBridge.shared.handle(
+        url: launchOptions?[.url] as? URL,
+        initial: true
+      )
+    }
     return launched
   }
 
diff --git a/ios/Runner/SceneDelegate.swift b/ios/Runner/SceneDelegate.swift
index b27cc0d..12c88ee 100644
--- a/ios/Runner/SceneDelegate.swift
+++ b/ios/Runner/SceneDelegate.swift
@@ -11,8 +11,8 @@ class SceneDelegate: FlutterSceneDelegate {
     if let controller = window?.rootViewController as? FlutterViewController {
       DuoyiDeepLinkBridge.shared.attach(to: controller.binaryMessenger)
     }
-    if let url = connectionOptions.urlContexts.first?.url {
-      DuoyiDeepLinkBridge.shared.handle(url: url, initial: true)
+    for context in connectionOptions.urlContexts {
+      DuoyiDeepLinkBridge.shared.handle(url: context.url, initial: true)
     }
   }
 
diff --git a/lib/main.dart b/lib/main.dart
index 0a595f8..8f7a481 100644
--- a/lib/main.dart
+++ b/lib/main.dart
@@ -62,6 +62,7 @@ import 'services/widget_publication_client.dart';
 import 'services/widget_publication_controller.dart';
 import 'services/widget_quick_todo_action.dart';
 import 'services/widget_action_scope.dart';
+import 'services/widget_link_dispatch.dart';
 import 'services/widget_action_message.dart';
 import 'services/reminder_issue_copy.dart';
 import 'services/ai_service.dart';
@@ -106,6 +107,7 @@ import 'widgets/surface_components.dart';
 final GlobalKey<MainShellState> mainShellKey = GlobalKey<MainShellState>();
 final List<Uri> _pendingWidgetUris = <Uri>[];
 final Map<String, DateTime> _recentWidgetActionUris = <String, DateTime>{};
+final Set<String> _handledWidgetDeliveries = <String>{};
 typedef _ReminderResyncQueue =
     Future<void> Function({Duration delay, String reason});
 
@@ -1055,6 +1057,7 @@ void main() async {
     WidgetsBinding.instance.addPostFrameCallback((_) {
       _handleWidgetUri(uri, pomodoroProvider);
     });
+    WidgetsBinding.instance.ensureVisualUpdate();
   }
 
   void handleSharedText(String text) {
@@ -3938,11 +3941,16 @@ void _queuePendingWidgetUri(Uri uri, String reason) {
   )) {
     return;
   }
-  if (_pendingWidgetUris.length >= 20) {
-    _pendingWidgetUris.removeAt(0);
+  if (_pendingWidgetUris.length >= 20 &&
+      !HomeWidgetService.isReceivedLaunch(uri)) {
+    final disposable = _pendingWidgetUris.indexWhere(
+      (pending) => !HomeWidgetService.isReceivedLaunch(pending),
+    );
+    if (disposable < 0) return;
+    _pendingWidgetUris.removeAt(disposable);
   }
   _pendingWidgetUris.add(uri);
-  debugPrint('[DeepLink] queued $uri: $reason');
+  debugPrint('[DeepLink] queued launch: $reason');
 }
 
 void _drainPendingWidgetUris(PomodoroProvider pomodoro) {
@@ -3955,6 +3963,9 @@ void _drainPendingWidgetUris(PomodoroProvider pomodoro) {
 }
 
 bool _reserveWidgetActionUri(Uri uri) {
+  // The native bridge deduplicates deliveries. Separate user taps can share
+  // the same action URL and must each increment a count-based habit.
+  if (HomeWidgetService.isReceivedLaunch(uri)) return true;
   final now = DateTime.now();
   _recentWidgetActionUris.removeWhere(
     (_, at) => now.difference(at) > const Duration(seconds: 5),
@@ -3962,7 +3973,7 @@ bool _reserveWidgetActionUri(Uri uri) {
   final key = uri.toString();
   final last = _recentWidgetActionUris[key];
   if (last != null && now.difference(last) <= const Duration(seconds: 5)) {
-    debugPrint('[DeepLink] duplicate widget action skipped: $uri');
+    debugPrint('[DeepLink] duplicate widget action skipped');
     return false;
   }
   _recentWidgetActionUris[key] = now;
@@ -3978,25 +3989,11 @@ void _handleWidgetUri(
 }) {
   if (uri == null) return;
   if (uri.scheme != 'duoyi') return;
-  if (!dataReady &&
-      const {
-        'todo',
-        'habit',
-        'course',
-        'note',
-        'diary',
-        'goal',
-        'anniversary',
-        'calendar',
-        'action',
-      }.contains(uri.host)) {
-    unawaited(_dispatchWidgetUriAfterHydration(uri, pomodoro));
-    return;
-  }
 
   final state = mainShellKey.currentState;
   final ctx = mainShellKey.currentContext;
   if (ctx != null && _widgetAccountUnavailable(ctx.read<AuthProvider>())) {
+    unawaited(HomeWidgetService.acknowledgeLaunch(uri));
     return;
   }
   if (state == null && retry < 8) {
@@ -4009,11 +4006,43 @@ void _handleWidgetUri(
     if (allowQueue) {
       _queuePendingWidgetUri(uri, 'main shell not ready after $retry frames');
     } else {
-      debugPrint('[DeepLink] dropped $uri: main shell not ready');
+      debugPrint('[DeepLink] dropped launch: main shell not ready');
     }
     return;
   }
 
+  if (!dataReady && WidgetLinkDispatch.requiresHydration(uri)) {
+    unawaited(_dispatchWidgetUriAfterHydration(uri, pomodoro));
+    return;
+  }
+
+  final receivedLaunch = HomeWidgetService.isReceivedLaunch(uri);
+  final delivery = receivedLaunch
+      ? uri.queryParameters['widget_delivery']
+      : null;
+  if (receivedLaunch &&
+      delivery != null &&
+      !_handledWidgetDeliveries.add(delivery)) {
+    unawaited(HomeWidgetService.acknowledgeLaunch(uri));
+    return;
+  }
+  if (_handledWidgetDeliveries.length > 4096) {
+    _handledWidgetDeliveries.remove(_handledWidgetDeliveries.first);
+  }
+
+  try {
+    _routeHydratedWidgetUri(uri, pomodoro, state, ctx);
+  } finally {
+    unawaited(HomeWidgetService.acknowledgeLaunch(uri));
+  }
+}
+
+void _routeHydratedWidgetUri(
+  Uri uri,
+  PomodoroProvider pomodoro,
+  MainShellState state,
+  BuildContext? ctx,
+) {
   if (uri.host == 'tab') {
     final tab = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
     final idx = switch (tab) {
@@ -4161,10 +4190,6 @@ void _handleWidgetUri(
     ns.handleSnoozeDeepLink(uri);
   } else if (uri.host == 'action') {
     final action = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
-    if (uri.queryParameters['source'] == 'widget') {
-      unawaited(_handleBoundWidgetAction(uri));
-      return;
-    }
     if (!_reserveWidgetActionUri(uri)) return;
     if (action == 'start_pomodoro') {
       state.navigateTo(4, allowHidden: true);
@@ -4264,7 +4289,7 @@ void _handleWidgetUri(
       unawaited(_checkInHabitFromWidgetAction(habits, target));
     }
   } else {
-    debugPrint('[DeepLink] unknown duoyi host: ${uri.host} uri=$uri');
+    debugPrint('[DeepLink] unsupported entry');
     state.navigateTo(6, allowHidden: true);
     if (ctx != null) {
       _showWidgetActionFeedback(
@@ -4385,57 +4410,42 @@ Future<void> _dispatchWidgetUriAfterHydration(
   final generation = AccountLocalDataCleaner.accountDataGeneration;
   final scope = WidgetActionScope();
   try {
-    await _ensureHomeWidgetDataReady?.call();
-    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
-      return;
-    }
-    final context = mainShellKey.currentContext;
-    if (context != null &&
-        context.mounted &&
-        _widgetAccountUnavailable(context.read<AuthProvider>())) {
-      return;
-    }
-    _handleWidgetUri(uri, pomodoro, dataReady: true);
-  } catch (e, st) {
-    debugPrint('[WidgetAction] data preparation failed: $e\n$st');
-    _showWidgetActionFeedbackFromShell(
-      const WidgetActionMessage(WidgetActionNotice.hydrationFailed),
-      isCurrentAction: () => scope.isCurrent,
+    final result = await WidgetLinkDispatch.resolve(
+      uri,
+      hydrate: () async => await _ensureHomeWidgetDataReady?.call(),
+      validate: HomeWidgetService.isCurrentWidgetAction,
+      isCurrent: () {
+        if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
+          generation,
+        )) {
+          return false;
+        }
+        final context = mainShellKey.currentContext;
+        return context != null &&
+            context.mounted &&
+            !_widgetAccountUnavailable(context.read<AuthProvider>());
+      },
     );
-  }
-}
-
-Future<void> _handleBoundWidgetAction(Uri uri) async {
-  final generation = AccountLocalDataCleaner.accountDataGeneration;
-  final scope = WidgetActionScope();
-  try {
-    await _ensureHomeWidgetDataReady?.call();
-    final current = await HomeWidgetService.isCurrentWidgetAction(uri);
-    final context = mainShellKey.currentContext;
-    if (!current ||
-        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) ||
-        context == null ||
-        !context.mounted ||
-        _widgetAccountUnavailable(context.read<AuthProvider>())) {
+    if (result.stale) {
       _showWidgetActionFeedbackFromShell(
         const WidgetActionMessage(WidgetActionNotice.staleContent),
         isCurrentAction: () => scope.isCurrent,
       );
-      return;
     }
-    final parameters = Map<String, String>.from(uri.queryParameters)
-      ..remove('source');
-    _handleWidgetUri(
-      uri.replace(queryParameters: parameters),
-      context.read<PomodoroProvider>(),
-      dataReady: true,
-    );
+    if (result.uri != null) {
+      _handleWidgetUri(result.uri, pomodoro, dataReady: true);
+    }
+    // A rejected or section-only fallback consumes the original delivery too.
+    if (result.uri == null || result.stale) {
+      await HomeWidgetService.acknowledgeLaunch(uri);
+    }
   } catch (e, st) {
-    debugPrint('[WidgetAction] validation failed: $e\n$st');
+    debugPrint('[WidgetAction] data preparation failed: $e\n$st');
     _showWidgetActionFeedbackFromShell(
-      const WidgetActionMessage(WidgetActionNotice.validationFailed),
+      const WidgetActionMessage(WidgetActionNotice.hydrationFailed),
       isCurrentAction: () => scope.isCurrent,
     );
+    await HomeWidgetService.acknowledgeLaunch(uri);
   }
 }
 
diff --git a/lib/services/home_widget_service.dart b/lib/services/home_widget_service.dart
index 3917761..28cc411 100644
--- a/lib/services/home_widget_service.dart
+++ b/lib/services/home_widget_service.dart
@@ -11,6 +11,7 @@ import '../core/i18n.dart';
 import '../core/platform_info.dart';
 import '../providers/theme_provider.dart';
 import 'android_widget_manager.dart';
+import 'widget_launch_service.dart';
 
 /// Pushes today's stats and brand strings out to Android/iOS home widgets.
 /// 在 web / 其他平台下为空实现。
@@ -828,14 +829,30 @@ class HomeWidgetService {
 
   static Stream<Uri?> get widgetClickedStream {
     if (!_supported) return const Stream.empty();
+    if (PlatformInfo.isAndroid || PlatformInfo.isIOS) {
+      return WidgetLaunchService.instance.links;
+    }
     return HomeWidget.widgetClicked;
   }
 
   static Future<Uri?> initialLaunchUri() async {
     if (!_supported) return null;
+    // Native cold and hot launches drain from one queue. Reading a plugin's
+    // initial launch later can replay the latest tap or collapse early taps.
+    if (PlatformInfo.isAndroid || PlatformInfo.isIOS) return null;
     return HomeWidget.initiallyLaunchedFromHomeWidget();
   }
 
+  static Future<void> acknowledgeLaunch(Uri uri) async {
+    if (PlatformInfo.isAndroid || PlatformInfo.isIOS) {
+      await WidgetLaunchService.instance.acknowledge(uri);
+    }
+  }
+
+  static bool isReceivedLaunch(Uri uri) =>
+      (PlatformInfo.isAndroid || PlatformInfo.isIOS) &&
+      WidgetLaunchService.instance.ownsDelivery(uri);
+
   static String _pushSignature({
     required int todoCount,
     required int habitPercent,
diff --git a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetLaunchBridge.kt b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetLaunchBridge.kt
new file mode 100644
index 0000000..051fb07
--- /dev/null
+++ b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetLaunchBridge.kt
@@ -0,0 +1,98 @@
+package com.duoyi.duoyi
+
+import android.content.Intent
+import android.net.Uri
+import android.util.Log
+import es.antonborri.home_widget.HomeWidgetLaunchIntent
+import io.flutter.embedding.engine.plugins.FlutterPlugin
+import io.flutter.plugin.common.BinaryMessenger
+import io.flutter.plugin.common.MethodChannel
+
+/** App-owned widget transport. All methods run on Android's main thread. */
+object DuoyiWidgetLaunchBridge {
+    private val queue = DuoyiWidgetLaunchQueue()
+    private var channel: MethodChannel? = null
+    private var subscribed = false
+    private val supportedHosts = setOf(
+        "tab", "todo", "habit", "calendar", "focus", "widget", "course", "note",
+        "diary", "goal", "anniversary", "countdown", "time-entry", "report", "action",
+    )
+
+    fun capture(intent: Intent?) {
+        if (intent?.action != HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION) return
+        val uri = intent.data ?: return
+        if (uri.scheme != "duoyi" || !uri.isHierarchical ||
+            uri.host !in supportedHosts || uri.toString().length > 8192) return
+        val delivery = runCatching { queue.receive { id ->
+            // Transport origin is not account authorization. Keep the original
+            // snapshot binding, including its absence on legacy widget links.
+            val builder = uri.buildUpon().clearQuery()
+            for (name in uri.queryParameterNames) {
+                if (name == "source" || name == "widget_delivery") continue
+                for (value in uri.getQueryParameters(name)) builder.appendQueryParameter(name, value)
+            }
+            builder.appendQueryParameter("source", "widget")
+                .appendQueryParameter("widget_delivery", id)
+                .build().toString()
+        } }.getOrElse {
+            Log.w("DuoyiWidgetLaunch", "Ignoring malformed widget launch URI")
+            return
+        } ?: run {
+            Log.w("DuoyiWidgetLaunch", "Widget launch backlog full; ignoring new launch")
+            return
+        }
+        intent.data = Uri.parse(delivery.uri)
+        if (subscribed) channel?.invokeMethod("onLaunch", delivery.payload())
+    }
+
+    fun attach(messenger: BinaryMessenger): MethodChannel {
+        channel?.setMethodCallHandler(null)
+        subscribed = false
+        val next = MethodChannel(messenger, "duoyi/widget_launch")
+        channel = next
+        next.setMethodCallHandler { call, result ->
+            if (channel !== next) {
+                result.error("STALE_WIDGET_ENGINE", "Widget launch engine changed", null)
+                return@setMethodCallHandler
+            }
+            when (call.method) {
+                "subscribe" -> {
+                    subscribed = true
+                    result.success(queue.snapshot().map { it.payload() })
+                }
+                "unsubscribe" -> {
+                    subscribed = false
+                    result.success(null)
+                }
+                "ack" -> {
+                    val id = call.arguments as? String
+                    if (id != null) queue.acknowledge(id)
+                    result.success(null)
+                }
+                else -> result.notImplemented()
+            }
+        }
+        return next
+    }
+
+    fun detach(expectedChannel: MethodChannel?) {
+        if (channel !== expectedChannel) return
+        subscribed = false
+        channel?.setMethodCallHandler(null)
+        channel = null
+    }
+}
+
+/** Keeps a retained Flutter engine subscribed across Activity recreation. */
+class DuoyiWidgetLaunchPlugin : FlutterPlugin {
+    private var channel: MethodChannel? = null
+
+    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
+        channel = DuoyiWidgetLaunchBridge.attach(binding.binaryMessenger)
+    }
+
+    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
+        DuoyiWidgetLaunchBridge.detach(channel)
+        channel = null
+    }
+}
diff --git a/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetLaunchQueue.kt b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetLaunchQueue.kt
new file mode 100644
index 0000000..8e998e2
--- /dev/null
+++ b/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetLaunchQueue.kt
@@ -0,0 +1,28 @@
+package com.duoyi.duoyi
+
+import java.util.UUID
+
+data class DuoyiWidgetLaunchDelivery(val id: String, val uri: String) {
+    fun payload(): Map<String, String> = mapOf("id" to id, "uri" to uri)
+}
+
+/** Retains each received tap until the Dart launch stream acknowledges it. */
+class DuoyiWidgetLaunchQueue(
+    private val maxPending: Int = 256,
+    private val newId: () -> String = { UUID.randomUUID().toString() },
+) {
+    private val pending = linkedMapOf<String, DuoyiWidgetLaunchDelivery>()
+
+    fun receive(buildUri: (String) -> String): DuoyiWidgetLaunchDelivery? {
+        // Reject the newest overflow, retaining every already accepted tap.
+        if (pending.size >= maxPending) return null
+        val id = newId()
+        return DuoyiWidgetLaunchDelivery(id, buildUri(id)).also { pending[id] = it }
+    }
+
+    fun snapshot(): List<DuoyiWidgetLaunchDelivery> = pending.values.toList()
+
+    fun acknowledge(id: String) {
+        pending.remove(id)
+    }
+}
diff --git a/lib/services/widget_launch_service.dart b/lib/services/widget_launch_service.dart
new file mode 100644
index 0000000..72dac78
--- /dev/null
+++ b/lib/services/widget_launch_service.dart
@@ -0,0 +1,164 @@
+import 'dart:async';
+import 'dart:collection';
+
+import 'package:flutter/foundation.dart';
+import 'package:flutter/services.dart';
+
+/// Buffered native widget launches, distinct from ordinary external links.
+/// A delivery ID identifies a received tap, not its URI or account binding.
+class WidgetLaunchService {
+  WidgetLaunchService({
+    MethodChannel channel = const MethodChannel('duoyi/widget_launch'),
+  }) : _channel = channel {
+    _controller = StreamController<Uri>.broadcast(
+      onListen: _subscribe,
+      onCancel: _unsubscribe,
+    );
+  }
+
+  static final instance = WidgetLaunchService();
+
+  final MethodChannel _channel;
+  late final StreamController<Uri> _controller;
+  final Set<String> _receivedIds = {};
+  final Set<String> _terminalIds = {};
+  final Set<String> _acknowledgedIds = {};
+  final Queue<String> _acknowledgedOrder = Queue<String>();
+  int _generation = 0;
+  Timer? _retryTimer;
+  int _retryAttempt = 0;
+
+  Stream<Uri> get links => _controller.stream;
+
+  bool ownsDelivery(Uri uri) {
+    try {
+      return _receivedIds.contains(uri.queryParameters['widget_delivery']);
+    } on FormatException {
+      return false;
+    }
+  }
+
+  void _subscribe() {
+    final generation = ++_generation;
+    // Install the handler before asking native code to drain the backlog.
+    // An overlapping hot delivery is harmless because both carry the same ID.
+    _channel.setMethodCallHandler((call) async {
+      if (call.method == 'onLaunch') {
+        await _receive(call.arguments, generation);
+      }
+      return null;
+    });
+    unawaited(_drain(generation));
+  }
+
+  Future<void> _drain(int generation) async {
+    if (generation != _generation || !_controller.hasListener) return;
+    try {
+      final pending = await _channel.invokeListMethod<Object?>('subscribe');
+      if (generation != _generation) return;
+      _retryAttempt = 0;
+      for (final delivery in pending ?? const <Object?>[]) {
+        await _receive(delivery, generation);
+      }
+    } catch (error, stack) {
+      debugPrint('[WidgetLaunch] subscription failed: $error\n$stack');
+      _scheduleRetry(generation);
+    }
+  }
+
+  void _scheduleRetry(int generation) {
+    if (generation != _generation ||
+        !_controller.hasListener ||
+        _retryTimer?.isActive == true) {
+      return;
+    }
+    const delays = [1, 2, 4, 8, 16];
+    final seconds = delays[_retryAttempt < 4 ? _retryAttempt++ : 4];
+    _retryTimer = Timer(Duration(seconds: seconds), () {
+      _retryTimer = null;
+      unawaited(_drain(generation));
+    });
+  }
+
+  Future<void> _receive(Object? raw, int generation) async {
+    if (generation != _generation || !_controller.hasListener) return;
+    if (raw is! Map) return;
+    final id = raw['id'];
+    final link = raw['uri'];
+    if (id is! String || id.trim().isEmpty) return;
+    final uri = _uriFromEnvelope(link, id);
+    if (uri == null) {
+      // Reject corrupt native envelopes terminally instead of retaining them
+      // forever. No URI from this branch is emitted to the application.
+      _receivedIds.add(id);
+      await _acknowledgeId(id);
+      return;
+    }
+    if (_receivedIds.add(id)) {
+      _controller.add(uri);
+    } else if (_terminalIds.contains(id)) {
+      await acknowledge(uri);
+    }
+  }
+
+  static Uri? _uriFromEnvelope(Object? link, String id) {
+    if (link is! String) return null;
+    try {
+      final uri = Uri.tryParse(link);
+      if (uri != null &&
+          uri.scheme == 'duoyi' &&
+          uri.hasAuthority &&
+          uri.queryParameters['source'] == 'widget' &&
+          uri.queryParameters['widget_delivery'] == id) {
+        return uri;
+      }
+    } on FormatException {
+      return null;
+    }
+    return null;
+  }
+
+  Future<void> acknowledge(Uri uri) async {
+    final id = uri.queryParameters['widget_delivery'];
+    if (id == null || !_receivedIds.contains(id)) return;
+    await _acknowledgeId(id);
+  }
+
+  Future<void> _acknowledgeId(String id) async {
+    _terminalIds.add(id);
+    try {
+      // The caller has accepted or rejected dispatch. ACK is not a claim that
+      // a provider's asynchronous data mutation has finished successfully.
+      await _channel.invokeMethod<void>('ack', id);
+      if (_acknowledgedIds.add(id)) _acknowledgedOrder.add(id);
+      // Native cannot replay an ACKed entry. Retain a generous overlap window
+      // for already returned drain snapshots; unacknowledged IDs stay tracked.
+      while (_acknowledgedOrder.length > 4096) {
+        final expired = _acknowledgedOrder.removeFirst();
+        _acknowledgedIds.remove(expired);
+        _receivedIds.remove(expired);
+        _terminalIds.remove(expired);
+      }
+    } catch (error, stack) {
+      // Native retains it for reconnect. A repeated delivery is ACKed again
+      // without being added to the Dart stream for a second time.
+      debugPrint('[WidgetLaunch] acknowledgement failed: $error\n$stack');
+      _scheduleRetry(_generation);
+    }
+  }
+
+  void _unsubscribe() {
+    ++_generation;
+    _retryTimer?.cancel();
+    _retryTimer = null;
+    _retryAttempt = 0;
+    _receivedIds.removeWhere((id) => !_terminalIds.contains(id));
+    unawaited(() async {
+      try {
+        await _channel.invokeMethod<void>('unsubscribe');
+      } catch (error, stack) {
+        debugPrint('[WidgetLaunch] unsubscribe failed: $error\n$stack');
+      }
+    }());
+  }
+}
diff --git a/lib/services/widget_link_dispatch.dart b/lib/services/widget_link_dispatch.dart
new file mode 100644
index 0000000..e2695ad
--- /dev/null
+++ b/lib/services/widget_link_dispatch.dart
@@ -0,0 +1,67 @@
+/// Resolves widget links after data hydration and account binding validation.
+/// Plain reminder/external deep links retain their existing behavior.
+class WidgetLinkDispatch {
+  const WidgetLinkDispatch(this.uri, {this.stale = false});
+
+  final Uri? uri;
+  final bool stale;
+
+  static const entityHosts = {
+    'todo',
+    'habit',
+    'course',
+    'note',
+    'diary',
+    'goal',
+    'anniversary',
+    'countdown',
+    'time-entry',
+  };
+
+  static bool requiresHydration(Uri uri) =>
+      entityHosts.contains(uri.host) ||
+      uri.host == 'calendar' ||
+      uri.host == 'action';
+
+  static bool requiresBinding(Uri uri) {
+    if (uri.queryParameters['source'] != 'widget') return false;
+    if (uri.host == 'action') {
+      final action = uri.pathSegments.firstOrNull;
+      // These recover a stale widget or open a new draft for the active
+      // account. A quick todo carrying text writes data and stays bound.
+      if (action == 'refresh_widgets') return false;
+      if (action == 'quick_todo' &&
+          (uri.queryParameters['text']?.trim().isEmpty ?? true)) {
+        return false;
+      }
+      return true;
+    }
+    return entityHosts.contains(uri.host) && uri.pathSegments.isNotEmpty;
+  }
+
+  static Future<WidgetLinkDispatch> resolve(
+    Uri uri, {
+    required Future<void> Function() hydrate,
+    required Future<bool> Function(Uri) validate,
+    required bool Function() isCurrent,
+  }) async {
+    await hydrate();
+    if (!isCurrent()) return const WidgetLinkDispatch(null);
+    if (!requiresBinding(uri)) return WidgetLinkDispatch(uri);
+    final valid = await validate(uri);
+    if (!isCurrent()) return const WidgetLinkDispatch(null);
+    if (!valid) {
+      return WidgetLinkDispatch(
+        entityHosts.contains(uri.host)
+            ? Uri(scheme: 'duoyi', host: uri.host)
+            : null,
+        stale: true,
+      );
+    }
+    // Only validated dispatch loses its origin marker. Preserve the received
+    // delivery ID so deliberately repeated count-habit taps stay distinct.
+    final parameters = Map<String, String>.from(uri.queryParameters)
+      ..remove('source');
+    return WidgetLinkDispatch(uri.replace(queryParameters: parameters));
+  }
+}
```
