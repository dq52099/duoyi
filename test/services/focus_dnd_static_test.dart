import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'Android focus DND channel declares permission and restores prior state',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      final service = File(
        'lib/services/focus_dnd_service.dart',
      ).readAsStringSync();
      final provider = File(
        'lib/providers/pomodoro_provider.dart',
      ).readAsStringSync();
      final model = File('lib/models/pomodoro.dart').readAsStringSync();
      final screen = File(
        'lib/screens/pomodoro_screen.dart',
      ).readAsStringSync();

      expect(
        manifest,
        contains('android.permission.ACCESS_NOTIFICATION_POLICY'),
      );
      expect(service, contains("MethodChannel('duoyi/focus_dnd')"));
      expect(service, contains('openPolicyAccessSettings'));
      expect(service, contains('enableDnd'));
      expect(service, contains('restoreDnd'));
      expect(
        service,
        contains('defaultTargetPlatform == TargetPlatform.android'),
      );

      expect(
        mainActivity,
        contains('private val focusDndChannel = "duoyi/focus_dnd"'),
      );
      expect(
        mainActivity,
        contains('Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS'),
      );
      expect(mainActivity, contains('isNotificationPolicyAccessGranted'));
      expect(mainActivity, contains('currentInterruptionFilter'));
      expect(mainActivity, contains('manager.setInterruptionFilter(filter)'));
      expect(
        mainActivity,
        contains('notificationManager().setInterruptionFilter(previousFilter)'),
      );
      expect(
        mainActivity,
        contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.M'),
      );

      expect(model, contains('bool autoEnableDnd'));
      expect(model, contains("'autoEnableDnd': autoEnableDnd"));
      expect(provider, contains('FocusDndService.instance'));
      expect(
        provider,
        contains('_dndPreviousFilter ??= result.previousFilter'),
      );
      expect(provider, contains('_restoreFocusDndIfNeeded'));
      expect(provider, contains('_state.isRunning'));
      expect(provider, contains('_state.type == PomodoroType.focus'));
      expect(provider, contains('openFocusDndSettings'));

      expect(screen, contains('专注勿扰'));
      expect(screen, contains('专注时自动开启勿扰'));
      expect(screen, contains('去授权'));
      expect(screen, contains('_FocusDndTile'));
    },
  );
}
