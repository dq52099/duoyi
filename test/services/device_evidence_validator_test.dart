import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('duoyi-device-evidence-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Android evidence validator passes complete proof set', () async {
    final androidDir = Directory('${tempDir.path}/android')..createSync();
    _writeAndroidEvidence(androidDir);

    final result = await _runValidator(
      'android',
      environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
    );

    expect(result.exitCode, 0, reason: _combinedOutput(result));
    expect(result.stdout, contains('Device evidence validation passed.'));
  });

  test('Android evidence validator fails when key proof is missing', () async {
    final androidDir = Directory('${tempDir.path}/android')..createSync();
    _writeAndroidEvidence(androidDir);
    File('${androidDir.path}/default_soft_ringtone.txt').deleteSync();

    final result = await _runValidator(
      'android',
      environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
    );

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains('missing file: ${androidDir.path}/default_soft_ringtone.txt'),
    );
  });

  test(
    'Android evidence validator fails when a captured deep link proof is missing',
    () async {
      final androidDir = Directory('${tempDir.path}/android')..createSync();
      _writeAndroidEvidence(androidDir);
      File(
        '${androidDir.path}/deeplink_duoyi___action_quick_todo.txt',
      ).deleteSync();

      final result = await _runValidator(
        'android',
        environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains(
          'missing file: '
          '${androidDir.path}/deeplink_duoyi___action_quick_todo.txt',
        ),
      );
    },
  );

  test(
    'Android evidence validator fails when a captured deep link did not succeed',
    () async {
      final androidDir = Directory('${tempDir.path}/android')..createSync();
      _writeAndroidEvidence(androidDir);
      File(
        '${androidDir.path}/deeplink_duoyi___calendar.txt',
      ).writeAsStringSync('Status: error');

      final result = await _runValidator(
        'android',
        environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains('Calendar deep link success not found'),
      );
    },
  );

  test(
    'Android evidence validator fails when a base launcher widget provider is missing',
    () async {
      final androidDir = Directory('${tempDir.path}/android')..createSync();
      _writeAndroidEvidence(androidDir);
      File('${androidDir.path}/widget_providers.txt').writeAsStringSync(
        _androidWidgetProviders()
            .split('\n')
            .where((provider) => provider != 'DuoyiDiaryWidgetProvider')
            .join('\n'),
      );

      final result = await _runValidator(
        'android',
        environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains(
          'Android launcher widget provider DuoyiDiaryWidgetProvider not found',
        ),
      );
    },
  );

  test(
    'Android evidence validator fails when soft ringtone proof is empty',
    () async {
      final androidDir = Directory('${tempDir.path}/android')..createSync();
      _writeAndroidEvidence(androidDir);
      File(
        '${androidDir.path}/default_soft_ringtone.txt',
      ).writeAsStringSync('');

      final result = await _runValidator(
        'android',
        environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains('empty file: ${androidDir.path}/default_soft_ringtone.txt'),
      );
    },
  );

  test(
    'Android evidence validator fails when soft ringtone proof is not the default soft sound',
    () async {
      final androidDir = Directory('${tempDir.path}/android')..createSync();
      _writeAndroidEvidence(androidDir);
      File(
        '${androidDir.path}/default_soft_ringtone.txt',
      ).writeAsStringSync('pref_reminder_ringtone_sound=alarm');

      final result = await _runValidator(
        'android',
        environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains('default soft ringtone evidence not found'),
      );
    },
  );

  test(
    'Android evidence validator does not duplicate derived failures when proof files are absent',
    () async {
      final androidDir = Directory('${tempDir.path}/android')..createSync();

      final result = await _runValidator(
        'android',
        environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
      );

      final output = _combinedOutput(result);
      expect(result.exitCode, isNot(0));
      expect(
        _occurrences(output, '${androidDir.path}/manual_evidence_manifest.md'),
        1,
      );
      expect(
        output,
        isNot(
          contains(
            'Android notification shade progress manual proof is not marked passed',
          ),
        ),
      );
      expect(output, isNot(contains('APK install success not found')));
    },
  );

  test('Android evidence validator fails when manual proof is pending', () async {
    final androidDir = Directory('${tempDir.path}/android')..createSync();
    _writeAndroidEvidence(androidDir, manualStatus: 'pending');

    final result = await _runValidator(
      'android',
      environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
    );

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains(
        'Android notification shade progress manual proof is not marked passed',
      ),
    );
  });

  test(
    'Android evidence validator fails when duplicate delivery count is non-zero',
    () async {
      final androidDir = Directory('${tempDir.path}/android')..createSync();
      _writeAndroidEvidence(androidDir);
      File('${androidDir.path}/single_delivery_no_duplicate.txt')
          .writeAsStringSync('''
reminder_id=device-regression-single-delivery
flutter_pending_count=1
native_pending_count=1
delivered_count=2
duplicate_delivery_count=1
''');

      final result = await _runValidator(
        'android',
        environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains('single delivery delivered count not found'),
      );
      expect(
        _combinedOutput(result),
        contains('single delivery duplicate count not found'),
      );
    },
  );

  test(
    'Android evidence validator fails when status bar progress is counted as reminder delivery',
    () async {
      final androidDir = Directory('${tempDir.path}/android')..createSync();
      _writeAndroidEvidence(androidDir);
      File('${androidDir.path}/single_delivery_no_duplicate.txt')
          .writeAsStringSync('''
reminder_id=device-regression-single-delivery
flutter_pending_count=0
native_pending_count=1
status_bar_excluded=false
delivered_count=1
duplicate_delivery_count=0
''');

      final result = await _runValidator(
        'android',
        environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains('single delivery status bar exclusion not found'),
      );
    },
  );

  test(
    'Android evidence validator fails when notification progress capture is empty',
    () async {
      final androidDir = Directory('${tempDir.path}/android')..createSync();
      _writeAndroidEvidence(androidDir);
      File('${androidDir.path}/notification_today_progress.txt')
          .writeAsStringSync('');

      final result = await _runValidator(
        'android',
        environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains(
          'empty file: ${androidDir.path}/notification_today_progress.txt',
        ),
      );
    },
  );

  test(
    'Android evidence validator fails when duplicate delivery count is pending',
    () async {
      final androidDir = Directory('${tempDir.path}/android')..createSync();
      _writeAndroidEvidence(androidDir);
      File('${androidDir.path}/single_delivery_no_duplicate.txt')
          .writeAsStringSync('''
reminder_id=device-regression-single-delivery
flutter_pending_count=manual
native_pending_count=manual
status_bar_excluded=pending
delivered_count=manual
duplicate_delivery_count=pending
''');

      final result = await _runValidator(
        'android',
        environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains('single delivery Flutter pending count not found'),
      );
      expect(
        _combinedOutput(result),
        contains('single delivery duplicate count not found'),
      );
    },
  );

  test(
    'Android evidence validator fails when duplicate delivery proof is missing',
    () async {
      final androidDir = Directory('${tempDir.path}/android')..createSync();
      _writeAndroidEvidence(androidDir);
      File('${androidDir.path}/single_delivery_no_duplicate.txt').deleteSync();

      final result = await _runValidator(
        'android',
        environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains(
          'missing file: ${androidDir.path}/single_delivery_no_duplicate.txt',
        ),
      );
    },
  );

  test('Android evidence validator fails when manual media is missing', () async {
    final androidDir = Directory('${tempDir.path}/android')..createSync();
    _writeAndroidEvidence(androidDir, writeManualMedia: false);

    final result = await _runValidator(
      'android',
      environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
    );

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains(
        'missing file: ${androidDir.path}/evidence/manual/android_notification_progress.png',
      ),
    );
  });

  test(
    'Android evidence validator rejects non-media manual proof files',
    () async {
      final androidDir = Directory('${tempDir.path}/android')..createSync();
      _writeAndroidEvidence(
        androidDir,
        manualPathOverrides: {
          'notification_shade_progress': 'evidence/manual/not_a_screenshot.txt',
        },
      );

      final result = await _runValidator(
        'android',
        environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains(
          'Android notification shade progress manual proof must reference a screenshot or recording',
        ),
      );
    },
  );

  test('Android evidence validator rejects escaped manual proof paths', () async {
    final androidDir = Directory('${tempDir.path}/android')..createSync();
    _writeAndroidEvidence(
      androidDir,
      manualPathOverrides: {'notification_shade_progress': '../outside.mp4'},
    );

    final result = await _runValidator(
      'android',
      environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
    );

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains(
        'Android notification shade progress manual proof path must stay under the evidence directory',
      ),
    );
  });

  test('Android evidence validator rejects text renamed as media', () async {
    final androidDir = Directory('${tempDir.path}/android')..createSync();
    _writeAndroidEvidence(androidDir);
    File(
      '${androidDir.path}/evidence/manual/android_notification_progress.png',
    ).writeAsStringSync('not a png');

    final result = await _runValidator(
      'android',
      environment: {'ANDROID_EVIDENCE_DIR': androidDir.path},
    );

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains(
        'Android notification shade progress manual proof has invalid media signature',
      ),
    );
  });

  test('iOS evidence validator passes complete proof set', () async {
    final iosDir = Directory('${tempDir.path}/ios')..createSync();
    _writeIosEvidence(iosDir);

    final result = await _runValidator(
      'ios',
      environment: {'IOS_EVIDENCE_DIR': iosDir.path},
    );

    expect(result.exitCode, 0, reason: _combinedOutput(result));
    expect(result.stdout, contains('Device evidence validation passed.'));
  });

  test(
    'iOS evidence validator fails when signing build proof is weak',
    () async {
      final iosDir = Directory('${tempDir.path}/ios')..createSync();
      _writeIosEvidence(iosDir);
      File(
        '${iosDir.path}/xcodebuild_device.log',
      ).writeAsStringSync('BUILD FAILED');

      final result = await _runValidator(
        'ios',
        environment: {'IOS_EVIDENCE_DIR': iosDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains('device signing build success not found'),
      );
    },
  );

  test(
    'iOS evidence validator fails when WidgetKit countdown log proof is missing',
    () async {
      final iosDir = Directory('${tempDir.path}/ios')..createSync();
      _writeIosEvidence(iosDir);
      File(
        '${iosDir.path}/widgetkit_calendar_countdown_deeplink.log',
      ).deleteSync();

      final result = await _runValidator(
        'ios',
        environment: {'IOS_EVIDENCE_DIR': iosDir.path},
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains(
          'missing file: '
          '${iosDir.path}/widgetkit_calendar_countdown_deeplink.log',
        ),
      );
    },
  );

  test(
    'iOS evidence validator does not duplicate derived failures when proof files are absent',
    () async {
      final iosDir = Directory('${tempDir.path}/ios')..createSync();

      final result = await _runValidator(
        'ios',
        environment: {'IOS_EVIDENCE_DIR': iosDir.path},
      );

      final output = _combinedOutput(result);
      expect(result.exitCode, isNot(0));
      expect(
        _occurrences(output, '${iosDir.path}/manual_evidence_manifest.md'),
        1,
      );
      expect(
        output,
        isNot(
          contains('iOS WidgetKit gallery manual proof is not marked passed'),
        ),
      );
      expect(output, isNot(contains('visible iOS device not found')));
    },
  );

  test('iOS evidence validator fails when manual proof is pending', () async {
    final iosDir = Directory('${tempDir.path}/ios')..createSync();
    _writeIosEvidence(iosDir, manualStatus: 'pending');

    final result = await _runValidator(
      'ios',
      environment: {'IOS_EVIDENCE_DIR': iosDir.path},
    );

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains('iOS WidgetKit gallery manual proof is not marked passed'),
    );
  });

  test('iOS evidence validator fails when manual media is missing', () async {
    final iosDir = Directory('${tempDir.path}/ios')..createSync();
    _writeIosEvidence(iosDir, writeManualMedia: false);

    final result = await _runValidator(
      'ios',
      environment: {'IOS_EVIDENCE_DIR': iosDir.path},
    );

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains(
        'missing file: ${iosDir.path}/evidence/manual/ios_widget_gallery.png',
      ),
    );
  });

  test('iOS evidence validator rejects non-media manual proof files', () async {
    final iosDir = Directory('${tempDir.path}/ios')..createSync();
    _writeIosEvidence(
      iosDir,
      manualPathOverrides: {
        'widget_gallery_10_widgets': 'evidence/manual/not_a_screenshot.txt',
      },
    );

    final result = await _runValidator(
      'ios',
      environment: {'IOS_EVIDENCE_DIR': iosDir.path},
    );

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains(
        'iOS WidgetKit gallery manual proof must reference a screenshot or recording',
      ),
    );
  });

  test('iOS evidence validator rejects text renamed as media', () async {
    final iosDir = Directory('${tempDir.path}/ios')..createSync();
    _writeIosEvidence(iosDir);
    File(
      '${iosDir.path}/evidence/manual/ios_widget_gallery.png',
    ).writeAsStringSync('not a png');

    final result = await _runValidator(
      'ios',
      environment: {'IOS_EVIDENCE_DIR': iosDir.path},
    );

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains('iOS WidgetKit gallery manual proof has invalid media signature'),
    );
  });
}

Future<ProcessResult> _runValidator(
  String platform, {
  required Map<String, String> environment,
}) {
  return Process.run(
    'bash',
    ['scripts/validate_device_evidence.sh', platform],
    workingDirectory: Directory.current.path,
    environment: environment,
    includeParentEnvironment: true,
  );
}

void _writeAndroidEvidence(
  Directory dir, {
  String manualStatus = 'passed',
  bool writeManualMedia = true,
  Map<String, String> manualPathOverrides = const {},
}) {
  final manualFiles = <String, String>{
    'notification_shade_progress':
        'evidence/manual/android_notification_progress.png',
    'notification_shade_toggle_off':
        'evidence/manual/android_notification_toggle_off.png',
    'reminder_notification_popup_alarm':
        'evidence/manual/android_reminder_modes.mp4',
    'single_delivery_no_duplicate':
        'evidence/manual/android_single_delivery_no_duplicate.mp4',
    'default_soft_ringtone':
        'evidence/manual/android_default_soft_ringtone.mp4',
    'launcher_widgets_10_added':
        'evidence/manual/android_launcher_widgets_10_added.mp4',
    'android_widget_style_matrix':
        'evidence/manual/android_widget_style_matrix.mp4',
    'widget_refresh_before_after':
        'evidence/manual/android_widget_refresh_before_after.mp4',
    'widget_todo_complete':
        'evidence/manual/android_widget_todo_complete.mp4',
    'widget_quick_add': 'evidence/manual/android_widget_quick_add.mp4',
    'widget_habit_checkin': 'evidence/manual/android_widget_habit_checkin.mp4',
    'calendar_countdown_deeplink':
        'evidence/manual/android_calendar_countdown_deeplink.mp4',
  };
  manualPathOverrides.forEach((key, value) {
    manualFiles[key] = value;
  });
  final files = <String, String>{
    'device_manufacturer.txt': 'Google',
    'device_model.txt': 'Pixel test device',
    'android_version.txt': '15',
    'android_sdk.txt': '35',
    'install.txt': 'Success',
    'launch.txt': 'Events injected: 1',
    'package.txt': 'package com.duoyi.duoyi',
    'appops.txt': 'POST_NOTIFICATION: allow',
    'dumpsys_notification.txt': 'Duoyi today progress notification',
    'dumpsys_alarm.txt': 'ReminderRingtone RTC_WAKEUP duoyi_soft',
    'dumpsys_appwidget.txt': 'Duoyi appwidget hosts',
    'widget_providers.txt': _androidWidgetProviders(),
    'logcat_duoyi.txt': 'ReminderRingtone NotificationStatusBar AppWidget',
    'notification_assistant.txt': 'allowed_assistant=none',
    'manual_required.md': [
      'Notification shade',
      'Reminder methods',
      'Default ringtone',
      'Launcher widgets',
      'Widget style matrix',
      'Countdown deep link',
    ].join('\n'),
    'manual_evidence_manifest.md': manualFiles.entries
        .map((entry) => '- ${entry.key}: $manualStatus - ${entry.value}')
        .join('\n'),
    'shared_prefs_files.txt': 'FlutterSharedPreferences.xml',
    'reminder_preferences.txt': 'pref_reminder_ringtone_sound=soft',
    'notification_channels.txt': 'duoyi_soft',
    'notification_today_progress.txt': 'today progress Duoyi',
    'reminder_alarm_queue.txt': 'ReminderRingtone RTC_WAKEUP',
    'default_soft_ringtone.txt': 'duoyi_soft 柔和晨铃',
    'single_delivery_no_duplicate.txt': '''
reminder_id=device-regression-single-delivery
flutter_pending_count=0
native_pending_count=1
status_bar_excluded=true
delivered_count=1
duplicate_delivery_count=0
''',
    'deeplink_duoyi___tab_today.txt': 'Status: ok',
    'deeplink_duoyi___calendar.txt': 'Status: ok',
    'deeplink_duoyi___countdown_device_regression_missing.txt': 'Status: ok',
    'deeplink_duoyi___action_quick_todo.txt': 'Status: ok',
    'deeplink_duoyi___action_complete_todo_id_device_regression_missing.txt':
        'Status: ok',
    'deeplink_duoyi___action_checkin_habit_id_device_regression_missing.txt':
        'Status: ok',
  };
  for (final entry in files.entries) {
    File('${dir.path}/${entry.key}').writeAsStringSync(entry.value);
  }
  if (writeManualMedia) {
    for (final path in manualFiles.values) {
      final file = File('${dir.path}/$path');
      file.parent.createSync(recursive: true);
      _writeFakeMedia(file);
    }
  }
}

void _writeIosEvidence(
  Directory dir, {
  String manualStatus = 'passed',
  bool writeManualMedia = true,
  Map<String, String> manualPathOverrides = const {},
}) {
  final manualFiles = <String, String>{
    'widget_gallery_10_widgets': 'evidence/manual/ios_widget_gallery.png',
    'widgetkit_family_matrix': 'evidence/manual/ios_widget_family_matrix.mp4',
    'app_group_refresh': 'evidence/manual/ios_app_group_refresh.mp4',
    'widget_todo_complete': 'evidence/manual/ios_widget_todo_complete.mp4',
    'widget_quick_add': 'evidence/manual/ios_widget_quick_add.mp4',
    'widget_habit_checkin': 'evidence/manual/ios_widget_habit_checkin.mp4',
    'widget_focus_start': 'evidence/manual/ios_widget_focus_start.mp4',
    'widget_footer_navigation':
        'evidence/manual/ios_widget_footer_navigation.mp4',
    'calendar_countdown_deeplink':
        'evidence/manual/ios_calendar_countdown_deeplink.mp4',
    'ios_notification_behavior':
        'evidence/manual/ios_notification_behavior.mp4',
  };
  manualPathOverrides.forEach((key, value) {
    manualFiles[key] = value;
  });
  final files = <String, String>{
    'macos_version.txt': 'ProductVersion: 15.0',
    'xcode_version.txt': 'Xcode 16.0',
    'xctrace_devices.txt': 'Test iPhone (0000) (iPhone)',
    'xctrace_physical_ios_devices.txt': 'Test iPhone (0000) (iPhone)',
    'app_group_entitlements.txt': [
      'ios/Runner/Runner.entitlements: group.com.duoyi.duoyi',
      'ios/DuoyiWidgets/DuoyiWidgets.entitlements: group.com.duoyi.duoyi',
    ].join('\n'),
    'widget_bundle_id.txt': 'com.duoyi.duoyi.DuoyiWidgets',
    'widget_target.txt':
        'DuoyiWidgets.appex DuoyiWidgets.swift in Sources Embed App Extensions',
    'xcodebuild_device.log': 'BUILD SUCCEEDED',
    'simctl_devices.txt': 'iPhone 16',
    'widgetkit_recent.log':
        'WidgetKit duoyi://tab/today duoyi://calendar duoyi://countdown/test',
    'widgetkit_calendar_countdown_deeplink.log':
        'duoyi://calendar duoyi://countdown/test',
    'manual_required.md': [
      'Add all 10 Duoyi WidgetKit widgets',
      'App Group',
      'quick actions',
      'countdown',
      'notification',
    ].join('\n'),
    'manual_evidence_manifest.md': manualFiles.entries
        .map((entry) => '- ${entry.key}: $manualStatus - ${entry.value}')
        .join('\n'),
  };
  for (final entry in files.entries) {
    File('${dir.path}/${entry.key}').writeAsStringSync(entry.value);
  }
  if (writeManualMedia) {
    for (final path in manualFiles.values) {
      final file = File('${dir.path}/$path');
      file.parent.createSync(recursive: true);
      _writeFakeMedia(file);
    }
  }
}

void _writeFakeMedia(File file) {
  final path = file.path.toLowerCase();
  if (path.endsWith('.png')) {
    file.writeAsBytesSync([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  } else if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
    file.writeAsBytesSync([0xff, 0xd8, 0xff, 0xe0]);
  } else if (path.endsWith('.mp4') || path.endsWith('.mov')) {
    file.writeAsBytesSync([
      0x00,
      0x00,
      0x00,
      0x18,
      0x66,
      0x74,
      0x79,
      0x70,
      0x69,
      0x73,
      0x6f,
      0x6d,
    ]);
  } else if (path.endsWith('.webm')) {
    file.writeAsBytesSync([0x1a, 0x45, 0xdf, 0xa3]);
  } else {
    file.writeAsStringSync('manual evidence bytes');
  }
}

String _androidWidgetProviders() {
  return [
    'DuoyiTodoWidgetProvider',
    'DuoyiHabitWidgetProvider',
    'DuoyiCalendarWidgetProvider',
    'DuoyiScheduleWidgetProvider',
    'DuoyiGoalWidgetProvider',
    'DuoyiCourseWidgetProvider',
    'DuoyiNoteWidgetProvider',
    'DuoyiAnniversaryWidgetProvider',
    'DuoyiDiaryWidgetProvider',
    'DuoyiFocusHabitWidgetProvider',
  ].join('\n');
}

String _combinedOutput(ProcessResult result) {
  return '${result.stdout}\n${result.stderr}';
}

int _occurrences(String value, String needle) {
  var count = 0;
  var index = 0;
  while (true) {
    index = value.indexOf(needle, index);
    if (index == -1) {
      return count;
    }
    count += 1;
    index += needle.length;
  }
}
