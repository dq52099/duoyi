# Device Regression Evidence

The full alignment gate is `scripts/alignment_regression_gate.sh`. The first seven groups verify code, route contracts, layout, notifications, widgets, backend permissions, analyzer, and APK build. The eighth group is device-only and must not be treated as complete until both Android and iOS device evidence have passed.

Before collecting device evidence, run `scripts/generate_device_readiness_report.sh` and `scripts/validate_device_readiness_report.sh`. They write `build/device-readiness/latest` and record host architecture, whether Flutter detects Android/iOS runtimes, whether adb sees a device, whether Android Emulator/AVD/system images/KVM are available and launchable on this host, and whether the host can collect iOS evidence. This readiness report explains missing external prerequisites; it does not replace Android or iOS evidence.

## Android Evidence

Run `scripts/device_regression_check.sh` with an attached Android phone or emulator. When Android is detected, it calls `scripts/android_device_evidence.sh` and writes evidence to `build/device-regression/android`.
After collection, `scripts/validate_device_evidence.sh android` must pass.

Expected files:

- `device_manufacturer.txt`, `device_model.txt`, `android_version.txt`, `android_sdk.txt`
- `install.txt`, `launch.txt`
- `deeplink_duoyi___tab_today.txt`, `deeplink_duoyi___calendar.txt`, `deeplink_duoyi___countdown_device_regression_missing.txt`, `deeplink_duoyi___action_quick_todo.txt`, `deeplink_duoyi___action_complete_todo_id_device_regression_missing.txt`, `deeplink_duoyi___action_checkin_habit_id_device_regression_missing.txt`
- `package.txt`, `appops.txt`, `notification_assistant.txt`
- `shared_prefs_files.txt`, `reminder_preferences.txt`, `notification_channels.txt`
- `dumpsys_notification.txt`, `dumpsys_alarm.txt`, `dumpsys_appwidget.txt`
- `notification_today_progress.txt`, `reminder_alarm_queue.txt`, `default_soft_ringtone.txt`, `single_delivery_no_duplicate.txt`
- `widget_providers.txt`, `logcat_duoyi.txt`, `manual_required.md`, `manual_evidence_manifest.md`

`widget_providers.txt` must list all 10 base Android launcher widget providers: `DuoyiTodoWidgetProvider`, `DuoyiHabitWidgetProvider`, `DuoyiCalendarWidgetProvider`, `DuoyiScheduleWidgetProvider`, `DuoyiGoalWidgetProvider`, `DuoyiCourseWidgetProvider`, `DuoyiNoteWidgetProvider`, `DuoyiAnniversaryWidgetProvider`, `DuoyiDiaryWidgetProvider`, and `DuoyiFocusHabitWidgetProvider`. `notification_today_progress.txt` must be non-empty and show the notification shade progress row or `pref_notification_today_progress` setting state. `default_soft_ringtone.txt` must be non-empty and contain a soft/default marker such as `duoyi_soft`, `柔和晨铃`, or `pref_reminder_ringtone_sound=soft`; countdown deep-link files must show `Status: ok`. `single_delivery_no_duplicate.txt` must record the tested reminder id and observed queue/delivery counts with `status_bar_excluded=true` and `duplicate_delivery_count=0`; the ongoing today-progress notification is not counted as a reminder delivery.

Manual evidence that must be attached to the release issue:

- Screenshot or recording of notification shade showing today's task progress, then the same notification removed after the setting is disabled.
- Recording of a reminder firing as notification, popup, and alarm/full-screen mode, including vibration and selected built-in ringtone.
- Recording of the same reminder after repeat-save/cold-start resync proving only one notification/dialog/alarm fires, with no duplicate reminder row and no double ringtone. The ongoing notification shade progress row must stay excluded from this count.
- Screenshot of the ringtone picker showing default `柔和晨铃`.
- Recording or screenshots proving all 10 visible Android launcher widgets can be added from the launcher.
- Recording of compact, standard, and detailed Android widget display modes or launcher sizes where supported.
- Recording of widget data changing before/after app data refresh.
- Recordings of Android widget actions: completing a todo, quick-adding a todo, and checking in a habit.
- Recording of a countdown opening from the Today schedule/calendar aggregate deep link path. Countdown deep links are only evidence for the Today schedule/calendar aggregate; do not introduce or require a standalone countdown WidgetKit or launcher entry.

The Android `manual_evidence_manifest.md` must mark these keys as `passed - relative/path`, and each referenced screenshot or recording must exist and be non-empty: `notification_shade_progress`, `notification_shade_toggle_off`, `reminder_notification_popup_alarm`, `single_delivery_no_duplicate`, `default_soft_ringtone`, `launcher_widgets_10_added`, `android_widget_style_matrix`, `widget_refresh_before_after`, `widget_todo_complete`, `widget_quick_add`, `widget_habit_checkin`, `calendar_countdown_deeplink`.

Environment notes:

- On Linux `aarch64`, `sdkmanager` may not provide the Android Emulator package. In that case the Android path requires an attached phone, an externally provisioned emulator binary, or a different host with emulator support.
- A present Android SDK and a passing APK build are not enough for this section; the files above must be generated from `adb` against an Android runtime.

## iOS Evidence

Run `scripts/device_regression_check.sh` on macOS with Xcode and a signed trusted iPhone/iPad. When iOS is detected, it calls `scripts/ios_device_evidence.sh` and writes evidence to `build/device-regression/ios`.
After collection, `scripts/validate_device_evidence.sh ios` must pass.

Expected files:

- `macos_version.txt`, `xcode_version.txt`, `xctrace_devices.txt`, `xctrace_physical_ios_devices.txt`
- `app_group_entitlements.txt`, `widget_bundle_id.txt`, `widget_target.txt`
- `xcodebuild_device.log`
- `simctl_devices.txt`, `widgetkit_recent.log`, `widgetkit_calendar_countdown_deeplink.log`, `manual_required.md`, `manual_evidence_manifest.md`

The iOS validator requires `xctrace_physical_ios_devices.txt` to list a physical iPhone or iPad, `app_group_entitlements.txt` to show `group.com.duoyi.duoyi` in both `ios/Runner/Runner.entitlements` and `ios/DuoyiWidgets/DuoyiWidgets.entitlements`, `widget_target.txt` to show the app extension product, Swift source, and Embed App Extensions phase, and `widgetkit_calendar_countdown_deeplink.log` to include both `duoyi://calendar` and a `duoyi://countdown/` aggregate deep link.

Manual evidence that must be attached to the release issue:

- Screenshot of the system widget gallery showing all 10 Duoyi WidgetKit widgets and no overview/combo widget.
- Screenshot or recording matrix covering WidgetKit families/display sizes for the 10 widgets where the OS supports them.
- Recording of WidgetKit data refreshing after app data changes.
- Recordings of WidgetKit actions: todo complete, quick add, habit check-in, focus start, and footer navigation links.
- Recording of a countdown opening from the Today schedule/calendar aggregate deep link path. Countdown deep links are only evidence for the Today schedule/calendar aggregate; do not introduce or require a standalone countdown WidgetKit or launcher entry.
- Screenshot or recording of iOS notification/time-sensitive reminder behavior where applicable.

The iOS `manual_evidence_manifest.md` must mark these keys as `passed - relative/path`, and each referenced screenshot or recording must exist and be non-empty: `widget_gallery_10_widgets`, `widgetkit_family_matrix`, `app_group_refresh`, `widget_todo_complete`, `widget_quick_add`, `widget_habit_checkin`, `widget_focus_start`, `widget_footer_navigation`, `calendar_countdown_deeplink`, `ios_notification_behavior`.

## Completion Rule

The goal is not complete when `scripts/device_regression_check.sh` fails because no Android/iOS device is attached, because only one platform has evidence, because emulator prerequisites are missing, because macOS/Xcode signing is unavailable, or because `scripts/validate_device_evidence.sh` reports missing/empty evidence. `build/device-readiness/latest` may prove why a host cannot run the device gate, but it does not close the gate. Static tests and APK builds are necessary evidence, but they do not prove notification shade, full-screen alarm, ringtone playback, launcher widgets, or WidgetKit behavior.
