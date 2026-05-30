#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_WORKSPACE="${IOS_WORKSPACE:-$ROOT_DIR/ios/Runner.xcworkspace}"
IOS_SCHEME="${IOS_SCHEME:-Runner}"
IOS_DESTINATION="${IOS_DESTINATION:-generic/platform=iOS}"
BUNDLE_ID="${BUNDLE_ID:-com.duoyi.duoyi}"
WIDGET_BUNDLE_ID="${WIDGET_BUNDLE_ID:-com.duoyi.duoyi.DuoyiWidgets}"
APP_GROUP_ID="${APP_GROUP_ID:-group.com.duoyi.duoyi}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT_DIR/build/device-regression/ios}"

cd "$ROOT_DIR"
mkdir -p "$EVIDENCE_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS device evidence requires macOS with Xcode and a signed iPhone device." >&2
  exit 2
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found. Install Xcode command line tools." >&2
  exit 2
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install Xcode." >&2
  exit 2
fi

echo "== iOS device evidence =="
sw_vers | tee "$EVIDENCE_DIR/macos_version.txt"
xcodebuild -version | tee "$EVIDENCE_DIR/xcode_version.txt"
xcrun xctrace list devices | tee "$EVIDENCE_DIR/xctrace_devices.txt"
awk '
  /^== Devices ==/ { in_devices = 1; next }
  /^== / { in_devices = 0 }
  in_devices && /iPhone|iPad/ { print }
' "$EVIDENCE_DIR/xctrace_devices.txt" > "$EVIDENCE_DIR/xctrace_physical_ios_devices.txt"

if [[ ! -s "$EVIDENCE_DIR/xctrace_physical_ios_devices.txt" ]]; then
  echo "No physical iPhone or iPad is visible to xctrace. No iPhone or iPad is visible to xctrace under the physical Devices section. Connect and trust a signed iOS device first." >&2
  exit 2
fi

echo
echo "== Entitlements and WidgetKit target evidence =="
grep -H "$APP_GROUP_ID" ios/Runner/Runner.entitlements ios/DuoyiWidgets/DuoyiWidgets.entitlements \
  | tee "$EVIDENCE_DIR/app_group_entitlements.txt"
grep -R "$WIDGET_BUNDLE_ID" ios/Runner.xcodeproj/project.pbxproj \
  | tee "$EVIDENCE_DIR/widget_bundle_id.txt"
grep -R 'DuoyiWidgets.appex\|DuoyiWidgets.swift in Sources\|Embed App Extensions' ios/Runner.xcodeproj/project.pbxproj \
  | tee "$EVIDENCE_DIR/widget_target.txt"

echo
echo "== Xcode build for device signing evidence =="
xcodebuild \
  -workspace "$IOS_WORKSPACE" \
  -scheme "$IOS_SCHEME" \
  -destination "$IOS_DESTINATION" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=YES \
  build \
  | tee "$EVIDENCE_DIR/xcodebuild_device.log"

echo
echo "== WidgetKit and deep-link log evidence =="
xcrun simctl list devices > "$EVIDENCE_DIR/simctl_devices.txt" || true
log show --last 20m --style compact \
  --predicate 'process CONTAINS "Duoyi" OR subsystem CONTAINS "WidgetKit" OR eventMessage CONTAINS "duoyi://"' \
  > "$EVIDENCE_DIR/widgetkit_recent.log" || true
grep -E 'duoyi://(calendar|countdown/)' "$EVIDENCE_DIR/widgetkit_recent.log" \
  > "$EVIDENCE_DIR/widgetkit_calendar_countdown_deeplink.log" || true

cat > "$EVIDENCE_DIR/manual_required.md" <<MSG
# iOS Manual Verification Required

- Add all 10 Duoyi WidgetKit widgets from the system widget gallery and confirm no overview/combo widget appears.
- Capture the WidgetKit family/display-size matrix for the 10 widgets where the OS supports those families.
- Confirm Runner and DuoyiWidgets both use $APP_GROUP_ID in the generated app_group_entitlements.txt evidence.
- Change app data in Runner and record the WidgetKit widgets refreshing from the shared App Group data.
- Tap WidgetKit quick actions and footer links, including todo complete, quick add, habit check-in, focus start, and navigation links.
- Confirm countdown opens from Today schedule/calendar aggregate deep links only; no standalone countdown widget is required or expected.
- Confirm iOS notification/time-sensitive reminder behavior where applicable.
MSG

cat > "$EVIDENCE_DIR/manual_evidence_manifest.md" <<'MSG'
# iOS Manual Evidence Manifest

Set each item to `passed - relative/path` only after the screenshot or recording exists in the release evidence bundle.

- widget_gallery_10_widgets: pending - evidence/manual/ios_widget_gallery.png
- widgetkit_family_matrix: pending - evidence/manual/ios_widget_family_matrix.mp4
- app_group_refresh: pending - evidence/manual/ios_app_group_refresh.mp4
- widget_todo_complete: pending - evidence/manual/ios_widget_todo_complete.mp4
- widget_quick_add: pending - evidence/manual/ios_widget_quick_add.mp4
- widget_habit_checkin: pending - evidence/manual/ios_widget_habit_checkin.mp4
- widget_focus_start: pending - evidence/manual/ios_widget_focus_start.mp4
- widget_footer_navigation: pending - evidence/manual/ios_widget_footer_navigation.mp4
- calendar_countdown_deeplink: pending - evidence/manual/ios_calendar_countdown_deeplink.mp4
- ios_notification_behavior: pending - evidence/manual/ios_notification_behavior.mp4
MSG

cat <<MSG

iOS device evidence written to:
$EVIDENCE_DIR

Manual verification still required on the same signed iOS device:
- Add all 10 Duoyi WidgetKit widgets from the system widget gallery and confirm no overview/combo widget appears.
- Capture the WidgetKit family/display-size matrix for the 10 widgets where the OS supports those families.
- Confirm Runner and DuoyiWidgets both use $APP_GROUP_ID and widget data refreshes after app changes.
- Tap widget quick actions and footer links, including todo complete, quick add, habit check-in, focus start, and navigation links.
- Confirm countdown opens from Today schedule/calendar aggregate deep links only; no standalone countdown widget is required or expected.
- Confirm iOS notification/time-sensitive reminder behavior where applicable.
MSG
