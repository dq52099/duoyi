#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_EVIDENCE_DIR="${ANDROID_EVIDENCE_DIR:-$ROOT_DIR/build/device-regression/android}"
IOS_EVIDENCE_DIR="${IOS_EVIDENCE_DIR:-$ROOT_DIR/build/device-regression/ios}"

failures=0

note() {
  printf '%s\n' "$*"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

require_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    fail "missing file: $file"
  fi
}

require_non_empty() {
  local file="$1"
  require_file "$file"
  if [[ -f "$file" && ! -s "$file" ]]; then
    fail "empty file: $file"
  fi
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if [[ ! -f "$file" ]]; then
    return
  fi
  if ! grep -Eiq "$pattern" "$file"; then
    fail "$label not found in $file"
  fi
}

require_count_at_least() {
  local file="$1"
  local pattern="$2"
  local expected_count="$3"
  local label="$4"
  local actual_count=0
  if [[ ! -f "$file" ]]; then
    return
  fi
  actual_count="$(grep -Ei "$pattern" "$file" | wc -l | tr -d '[:space:]')"
  if [[ "$actual_count" -lt "$expected_count" ]]; then
    fail "$label count is $actual_count, expected at least $expected_count in $file"
  fi
}

require_widget_provider() {
  local provider="$1"
  require_pattern "$ANDROID_EVIDENCE_DIR/widget_providers.txt" "$provider" "Android launcher widget provider $provider"
}

require_manual_evidence() {
  local file="$1"
  local base_dir="$2"
  local key="$3"
  local label="$4"
  local line=""
  local path=""
  local evidence_file=""

  if [[ ! -f "$file" ]]; then
    return
  fi

  line="$(grep -Ei "^- +$key: +passed +-[[:space:]]+[^[:space:]]+" "$file" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    fail "$label manual proof is not marked passed in $file"
    return
  fi

  path="$(printf '%s' "$line" | sed -E "s/^- +$key: +passed +- +([^[:space:]]+).*/\1/I")"
  if [[ -z "$path" || "$path" == "$line" ]]; then
    fail "$label manual proof path is missing in $file"
    return
  fi

  if [[ "$path" = /* || "$path" == *..* ]]; then
    fail "$label manual proof path must stay under the evidence directory in $file"
    return
  fi
  if ! printf '%s' "$path" | grep -Eiq '\.(png|jpe?g|mp4|mov|webm)$'; then
    fail "$label manual proof must reference a screenshot or recording in $file"
    return
  fi

  evidence_file="$base_dir/$path"

  require_non_empty "$evidence_file"
  require_media_signature "$evidence_file" "$label"
}

require_media_signature() {
  local file="$1"
  local label="$2"
  local ext="${file##*.}"
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

  case "$ext" in
    png|jpg|jpeg|mp4|mov|webm)
      ;;
    *)
      return
      ;;
  esac

  if ! python3 - "$file" "$ext" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
ext = sys.argv[2]
data = path.read_bytes()[:32]
ok = False
if ext == "png":
    ok = data.startswith(b"\x89PNG\r\n\x1a\n")
elif ext in {"jpg", "jpeg"}:
    ok = data.startswith(b"\xff\xd8\xff")
elif ext in {"mp4", "mov"}:
    ok = len(data) >= 12 and data[4:8] == b"ftyp"
elif ext == "webm":
    ok = data.startswith(b"\x1a\x45\xdf\xa3")
sys.exit(0 if ok else 1)
PY
  then
    fail "$label manual proof has invalid media signature in $file"
  fi
}

validate_android() {
  note "== Validate Android evidence =="
  if [[ ! -d "$ANDROID_EVIDENCE_DIR" ]]; then
    fail "Android evidence directory missing: $ANDROID_EVIDENCE_DIR"
    return
  fi

  local required_non_empty=(
    device_manufacturer.txt
    device_model.txt
    android_version.txt
    android_sdk.txt
    install.txt
    launch.txt
    deeplink_duoyi___tab_today.txt
    deeplink_duoyi___calendar.txt
    deeplink_duoyi___countdown_device_regression_missing.txt
    deeplink_duoyi___action_quick_todo.txt
    deeplink_duoyi___action_complete_todo_id_device_regression_missing.txt
    deeplink_duoyi___action_checkin_habit_id_device_regression_missing.txt
    package.txt
    appops.txt
    dumpsys_notification.txt
    dumpsys_alarm.txt
    dumpsys_appwidget.txt
    notification_today_progress.txt
    widget_providers.txt
    logcat_duoyi.txt
    manual_required.md
    manual_evidence_manifest.md
  )
  for name in "${required_non_empty[@]}"; do
    require_non_empty "$ANDROID_EVIDENCE_DIR/$name"
  done

  local required_present=(
    shared_prefs_files.txt
    reminder_preferences.txt
    notification_channels.txt
    notification_assistant.txt
    reminder_alarm_queue.txt
    single_delivery_no_duplicate.txt
  )
  for name in "${required_present[@]}"; do
    require_file "$ANDROID_EVIDENCE_DIR/$name"
  done
  require_non_empty "$ANDROID_EVIDENCE_DIR/default_soft_ringtone.txt"
  require_pattern "$ANDROID_EVIDENCE_DIR/default_soft_ringtone.txt" 'duoyi_soft|柔和晨铃|pref_reminder_ringtone_sound[^[:space:]]*soft|sound[[:space:]_:-]*=[[:space:]]*soft|id[[:space:]_:-]*=[[:space:]]*soft' 'default soft ringtone evidence'

  require_pattern "$ANDROID_EVIDENCE_DIR/install.txt" 'Success' 'APK install success'
  require_pattern "$ANDROID_EVIDENCE_DIR/launch.txt" 'Events injected|monkey' 'launcher smoke result'
  require_pattern "$ANDROID_EVIDENCE_DIR/deeplink_duoyi___tab_today.txt" 'Status:[[:space:]]+ok' 'Today deep link success'
  require_pattern "$ANDROID_EVIDENCE_DIR/deeplink_duoyi___calendar.txt" 'Status:[[:space:]]+ok' 'Calendar deep link success'
  require_pattern "$ANDROID_EVIDENCE_DIR/deeplink_duoyi___countdown_device_regression_missing.txt" 'Status:[[:space:]]+ok' 'Countdown aggregate deep link success'
  require_pattern "$ANDROID_EVIDENCE_DIR/deeplink_duoyi___action_quick_todo.txt" 'Status:[[:space:]]+ok' 'Quick todo deep link success'
  require_pattern "$ANDROID_EVIDENCE_DIR/deeplink_duoyi___action_complete_todo_id_device_regression_missing.txt" 'Status:[[:space:]]+ok' 'Complete todo deep link success'
  require_pattern "$ANDROID_EVIDENCE_DIR/deeplink_duoyi___action_checkin_habit_id_device_regression_missing.txt" 'Status:[[:space:]]+ok' 'Habit check-in deep link success'
  require_pattern "$ANDROID_EVIDENCE_DIR/notification_today_progress.txt" 'today progress|今日任务进展|NotificationStatusBar|pref_notification_today_progress' 'notification shade today progress evidence'
  require_widget_provider 'DuoyiTodoWidgetProvider'
  require_widget_provider 'DuoyiHabitWidgetProvider'
  require_widget_provider 'DuoyiCalendarWidgetProvider'
  require_widget_provider 'DuoyiScheduleWidgetProvider'
  require_widget_provider 'DuoyiGoalWidgetProvider'
  require_widget_provider 'DuoyiCourseWidgetProvider'
  require_widget_provider 'DuoyiNoteWidgetProvider'
  require_widget_provider 'DuoyiAnniversaryWidgetProvider'
  require_widget_provider 'DuoyiDiaryWidgetProvider'
  require_widget_provider 'DuoyiFocusHabitWidgetProvider'
  require_pattern "$ANDROID_EVIDENCE_DIR/widget_providers.txt" 'Duoyi(Todo|Habit|Calendar|Schedule|Goal|Course|Note|Anniversary|Diary|FocusHabit)WidgetProvider' 'widget provider registration'
  require_pattern "$ANDROID_EVIDENCE_DIR/manual_required.md" 'Notification shade|Reminder methods|Default ringtone|Launcher widgets' 'manual proof checklist'
  require_pattern "$ANDROID_EVIDENCE_DIR/single_delivery_no_duplicate.txt" 'reminder_id[[:space:]_:-]*=' 'single delivery reminder id'
  require_pattern "$ANDROID_EVIDENCE_DIR/single_delivery_no_duplicate.txt" 'flutter_pending_count[[:space:]_:-]*=[[:space:]]*[0-9]+' 'single delivery Flutter pending count'
  require_pattern "$ANDROID_EVIDENCE_DIR/single_delivery_no_duplicate.txt" 'native_pending_count[[:space:]_:-]*=[[:space:]]*[0-9]+' 'single delivery native pending count'
  require_pattern "$ANDROID_EVIDENCE_DIR/single_delivery_no_duplicate.txt" 'status_bar_excluded[[:space:]_:-]*=[[:space:]]*true' 'single delivery status bar exclusion'
  require_pattern "$ANDROID_EVIDENCE_DIR/single_delivery_no_duplicate.txt" 'delivered_count[[:space:]_:-]*=[[:space:]]*1' 'single delivery delivered count'
  require_pattern "$ANDROID_EVIDENCE_DIR/single_delivery_no_duplicate.txt" 'duplicate_delivery_count[[:space:]_:-]*=[[:space:]]*0' 'single delivery duplicate count'
  require_manual_evidence "$ANDROID_EVIDENCE_DIR/manual_evidence_manifest.md" "$ANDROID_EVIDENCE_DIR" 'notification_shade_progress' 'Android notification shade progress'
  require_manual_evidence "$ANDROID_EVIDENCE_DIR/manual_evidence_manifest.md" "$ANDROID_EVIDENCE_DIR" 'notification_shade_toggle_off' 'Android notification shade toggle off'
  require_manual_evidence "$ANDROID_EVIDENCE_DIR/manual_evidence_manifest.md" "$ANDROID_EVIDENCE_DIR" 'reminder_notification_popup_alarm' 'Android reminder methods'
  require_manual_evidence "$ANDROID_EVIDENCE_DIR/manual_evidence_manifest.md" "$ANDROID_EVIDENCE_DIR" 'single_delivery_no_duplicate' 'Android single reminder delivery'
  require_manual_evidence "$ANDROID_EVIDENCE_DIR/manual_evidence_manifest.md" "$ANDROID_EVIDENCE_DIR" 'default_soft_ringtone' 'Android default soft ringtone'
  require_manual_evidence "$ANDROID_EVIDENCE_DIR/manual_evidence_manifest.md" "$ANDROID_EVIDENCE_DIR" 'launcher_widgets_10_added' 'Android 10 launcher widgets added'
  require_manual_evidence "$ANDROID_EVIDENCE_DIR/manual_evidence_manifest.md" "$ANDROID_EVIDENCE_DIR" 'android_widget_style_matrix' 'Android launcher widget style matrix'
  require_manual_evidence "$ANDROID_EVIDENCE_DIR/manual_evidence_manifest.md" "$ANDROID_EVIDENCE_DIR" 'widget_refresh_before_after' 'Android launcher widget refresh before and after'
  require_manual_evidence "$ANDROID_EVIDENCE_DIR/manual_evidence_manifest.md" "$ANDROID_EVIDENCE_DIR" 'widget_todo_complete' 'Android launcher widget todo complete'
  require_manual_evidence "$ANDROID_EVIDENCE_DIR/manual_evidence_manifest.md" "$ANDROID_EVIDENCE_DIR" 'widget_quick_add' 'Android launcher widget quick add'
  require_manual_evidence "$ANDROID_EVIDENCE_DIR/manual_evidence_manifest.md" "$ANDROID_EVIDENCE_DIR" 'widget_habit_checkin' 'Android launcher widget habit check-in'
  require_manual_evidence "$ANDROID_EVIDENCE_DIR/manual_evidence_manifest.md" "$ANDROID_EVIDENCE_DIR" 'calendar_countdown_deeplink' 'Android calendar countdown deep link'
}

validate_ios() {
  note "== Validate iOS evidence =="
  if [[ ! -d "$IOS_EVIDENCE_DIR" ]]; then
    fail "iOS evidence directory missing: $IOS_EVIDENCE_DIR"
    return
  fi

  local required_non_empty=(
    macos_version.txt
    xcode_version.txt
    xctrace_devices.txt
    xctrace_physical_ios_devices.txt
    app_group_entitlements.txt
    widget_bundle_id.txt
    widget_target.txt
    xcodebuild_device.log
    simctl_devices.txt
    widgetkit_recent.log
    widgetkit_calendar_countdown_deeplink.log
    manual_required.md
    manual_evidence_manifest.md
  )
  for name in "${required_non_empty[@]}"; do
    require_non_empty "$IOS_EVIDENCE_DIR/$name"
  done

  require_pattern "$IOS_EVIDENCE_DIR/xctrace_devices.txt" 'iPhone|iPad' 'visible iOS device'
  require_pattern "$IOS_EVIDENCE_DIR/xctrace_physical_ios_devices.txt" 'iPhone|iPad' 'visible physical iOS device'
  require_pattern "$IOS_EVIDENCE_DIR/app_group_entitlements.txt" 'group\.com\.duoyi\.duoyi' 'App Group entitlement'
  require_pattern "$IOS_EVIDENCE_DIR/app_group_entitlements.txt" 'Runner/Runner\.entitlements:.*group\.com\.duoyi\.duoyi' 'Runner App Group entitlement'
  require_pattern "$IOS_EVIDENCE_DIR/app_group_entitlements.txt" 'DuoyiWidgets/DuoyiWidgets\.entitlements:.*group\.com\.duoyi\.duoyi' 'WidgetKit App Group entitlement'
  require_count_at_least "$IOS_EVIDENCE_DIR/app_group_entitlements.txt" 'group\.com\.duoyi\.duoyi' 2 'App Group entitlement'
  require_pattern "$IOS_EVIDENCE_DIR/widget_bundle_id.txt" 'com\.duoyi\.duoyi\.DuoyiWidgets' 'Widget bundle id'
  require_pattern "$IOS_EVIDENCE_DIR/widget_target.txt" 'DuoyiWidgets\.appex' 'WidgetKit app extension product'
  require_pattern "$IOS_EVIDENCE_DIR/widget_target.txt" 'DuoyiWidgets\.swift in Sources' 'WidgetKit Swift source wiring'
  require_pattern "$IOS_EVIDENCE_DIR/widget_target.txt" 'Embed App Extensions' 'WidgetKit embed phase'
  require_pattern "$IOS_EVIDENCE_DIR/xcodebuild_device.log" 'BUILD SUCCEEDED' 'device signing build success'
  require_pattern "$IOS_EVIDENCE_DIR/widgetkit_calendar_countdown_deeplink.log" 'duoyi://calendar' 'WidgetKit calendar aggregate deep link'
  require_pattern "$IOS_EVIDENCE_DIR/widgetkit_calendar_countdown_deeplink.log" 'duoyi://countdown/' 'WidgetKit countdown aggregate deep link'
  require_pattern "$IOS_EVIDENCE_DIR/manual_required.md" '10 Duoyi WidgetKit widgets' 'iOS WidgetKit gallery checklist'
  require_pattern "$IOS_EVIDENCE_DIR/manual_required.md" 'App Group' 'iOS App Group checklist'
  require_pattern "$IOS_EVIDENCE_DIR/manual_required.md" 'quick actions' 'iOS WidgetKit quick actions checklist'
  require_pattern "$IOS_EVIDENCE_DIR/manual_required.md" 'countdown' 'iOS countdown deep link checklist'
  require_pattern "$IOS_EVIDENCE_DIR/manual_required.md" 'notification' 'iOS notification checklist'
  require_manual_evidence "$IOS_EVIDENCE_DIR/manual_evidence_manifest.md" "$IOS_EVIDENCE_DIR" 'widget_gallery_10_widgets' 'iOS WidgetKit gallery'
  require_manual_evidence "$IOS_EVIDENCE_DIR/manual_evidence_manifest.md" "$IOS_EVIDENCE_DIR" 'widgetkit_family_matrix' 'iOS WidgetKit family matrix'
  require_manual_evidence "$IOS_EVIDENCE_DIR/manual_evidence_manifest.md" "$IOS_EVIDENCE_DIR" 'app_group_refresh' 'iOS App Group refresh'
  require_manual_evidence "$IOS_EVIDENCE_DIR/manual_evidence_manifest.md" "$IOS_EVIDENCE_DIR" 'widget_todo_complete' 'iOS WidgetKit todo complete'
  require_manual_evidence "$IOS_EVIDENCE_DIR/manual_evidence_manifest.md" "$IOS_EVIDENCE_DIR" 'widget_quick_add' 'iOS WidgetKit quick add'
  require_manual_evidence "$IOS_EVIDENCE_DIR/manual_evidence_manifest.md" "$IOS_EVIDENCE_DIR" 'widget_habit_checkin' 'iOS WidgetKit habit check-in'
  require_manual_evidence "$IOS_EVIDENCE_DIR/manual_evidence_manifest.md" "$IOS_EVIDENCE_DIR" 'widget_focus_start' 'iOS WidgetKit focus start'
  require_manual_evidence "$IOS_EVIDENCE_DIR/manual_evidence_manifest.md" "$IOS_EVIDENCE_DIR" 'widget_footer_navigation' 'iOS WidgetKit footer navigation'
  require_manual_evidence "$IOS_EVIDENCE_DIR/manual_evidence_manifest.md" "$IOS_EVIDENCE_DIR" 'calendar_countdown_deeplink' 'iOS calendar countdown deep link'
  require_manual_evidence "$IOS_EVIDENCE_DIR/manual_evidence_manifest.md" "$IOS_EVIDENCE_DIR" 'ios_notification_behavior' 'iOS notification behavior'
}

case "${1:-all}" in
  android)
    validate_android
    ;;
  ios)
    validate_ios
    ;;
  all)
    validate_android
    validate_ios
    ;;
  *)
    echo "Usage: $0 [android|ios|all]" >&2
    exit 2
    ;;
esac

if [[ "$failures" -gt 0 ]]; then
  echo "Device evidence validation failed with $failures issue(s)." >&2
  exit 1
fi

echo "Device evidence validation passed."
