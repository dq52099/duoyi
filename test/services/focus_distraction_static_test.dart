import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android strict focus can monitor distracting foreground apps', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final service = File(
      'lib/services/focus_distraction_service.dart',
    ).readAsStringSync();
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final model = File('lib/models/pomodoro.dart').readAsStringSync();
    final screen = File('lib/screens/pomodoro_screen.dart').readAsStringSync();

    expect(manifest, contains('android.permission.PACKAGE_USAGE_STATS'));
    expect(manifest, contains('tools:ignore="ProtectedPermissions"'));
    expect(manifest, contains('android.permission.BIND_ACCESSIBILITY_SERVICE'));
    expect(manifest, contains('DuoyiFocusBlockerAccessibilityService'));
    expect(
      manifest,
      contains('@xml/duoyi_focus_blocker_accessibility_service'),
    );
    expect(service, contains("'duoyi/focus_distraction'"));
    expect(service, contains('openUsageAccessSettings'));
    expect(service, contains('openAccessibilitySettings'));
    expect(service, contains('setFocusBlocker'));
    expect(service, contains('accessibilityGranted'));
    expect(service, contains('blockerConfigured'));
    expect(service, contains('getForegroundApp'));
    expect(mainActivity, contains('private val focusDistractionChannel'));
    expect(mainActivity, contains('UsageStatsManager'));
    expect(mainActivity, contains('AppOpsManager.OPSTR_GET_USAGE_STATS'));
    expect(mainActivity, contains('Settings.ACTION_USAGE_ACCESS_SETTINGS'));
    expect(mainActivity, contains('Settings.ACTION_ACCESSIBILITY_SETTINGS'));
    expect(mainActivity, contains('setFocusBlocker'));
    expect(mainActivity, contains('hasFocusBlockerAccessibilityAccess'));
    expect(mainActivity, contains('FocusBlockerStore.setConfig'));
    expect(mainActivity, contains('queryUsageStats'));
    expect(mainActivity, contains('foregroundPackageName'));
    final blocker = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusBlockerAccessibilityService.kt',
    ).readAsStringSync();
    final blockerXml = File(
      'android/app/src/main/res/xml/duoyi_focus_blocker_accessibility_service.xml',
    ).readAsStringSync();
    expect(blocker, contains('class DuoyiFocusBlockerAccessibilityService'));
    expect(blocker, contains('AccessibilityService'));
    expect(blocker, contains('TYPE_WINDOW_STATE_CHANGED'));
    expect(blocker, contains('FocusBlockerStore.isBlocked'));
    expect(blocker, contains('FocusBlockerStore.recordBlockedPackage'));
    expect(blocker, contains('MainActivity::class.java'));
    expect(blockerXml, contains('typeWindowStateChanged'));

    expect(model, contains('bool monitorDistractingApps'));
    expect(model, contains('List<String> distractingAppPackages'));
    expect(model, contains('distractingApp'));
    expect(model, contains('appPackage'));
    expect(provider, contains('FocusDistractionService.instance'));
    expect(provider, contains('Timer? _distractionTimer'));
    expect(provider, contains('setMonitorDistractingApps'));
    expect(provider, contains('setDistractingAppPackages'));
    expect(provider, contains('openFocusAccessibilitySettings'));
    expect(provider, contains('setFocusBlocker'));
    expect(provider, contains('_checkDistractingForegroundApp'));
    expect(provider, contains('FocusPenaltyReason.distractingApp'));
    expect(screen, contains('监控分心应用'));
    expect(screen, contains('分心应用包名'));
    expect(screen, contains('使用情况权限'));
    expect(screen, contains('辅助功能拦截'));
  });
}
