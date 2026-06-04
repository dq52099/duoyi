import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory reportDir;
  late Directory androidDir;
  late Directory iosDir;
  late Directory goalReportDir;
  late Directory statusDir;
  late File matrixFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('duoyi-goal-closure-');
    reportDir = Directory('${tempDir.path}/report')..createSync();
    androidDir = Directory('${tempDir.path}/android')..createSync();
    iosDir = Directory('${tempDir.path}/ios')..createSync();
    goalReportDir = Directory('${tempDir.path}/goal-report');
    statusDir = Directory('${tempDir.path}/status-report');
    matrixFile = File('${tempDir.path}/goal-requirement-matrix.md')
      ..writeAsStringSync(
        File('docs/goal-requirement-matrix.md').readAsStringSync(),
      );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'goal closure validator passes only when all gates and device evidence pass',
    () async {
      _writeReport(reportDir, eighthStatus: 'passed');
      _writeAndroidEvidence(androidDir);
      _writeIosEvidence(iosDir);

      final result = await _runValidator(
        reportDir,
        androidDir,
        iosDir,
        goalReportDir,
        statusDir,
        matrixFile,
      );

      expect(result.exitCode, 0, reason: _combinedOutput(result));
      expect(result.stdout, contains('Goal closure validation passed.'));
      expect(File('${goalReportDir.path}/summary.tsv').existsSync(), isTrue);
      expect(
        File('${goalReportDir.path}/alignment_report.log').existsSync(),
        isTrue,
      );
      expect(
        File('${goalReportDir.path}/goal_requirement_matrix.log').existsSync(),
        isTrue,
      );
      expect(
        File('${goalReportDir.path}/android_device_evidence.log').existsSync(),
        isTrue,
      );
      expect(
        File('${goalReportDir.path}/ios_device_evidence.log').existsSync(),
        isTrue,
      );
      expect(File('${statusDir.path}/status.tsv').existsSync(), isTrue);
      expect(
        File(
          '${goalReportDir.path}/goal_requirement_status.log',
        ).readAsStringSync(),
        contains('Goal requirement status written to ${statusDir.path}'),
      );
      expect(
        File(
          '${goalReportDir.path}/goal_requirement_status_validation.log',
        ).readAsStringSync(),
        contains('Goal requirement status validation passed.'),
      );
      expect(
        File('${statusDir.path}/status.tsv').readAsStringSync(),
        contains('REQ-DEVICE\tclosed\tall mapped gates passed'),
      );
    },
  );

  test(
    'goal closure validator fails when requirement matrix is missing',
    () async {
      _writeReport(reportDir, eighthStatus: 'passed');
      _writeAndroidEvidence(androidDir);
      _writeIosEvidence(iosDir);
      matrixFile.deleteSync();

      final result = await _runValidator(
        reportDir,
        androidDir,
        iosDir,
        goalReportDir,
        statusDir,
        matrixFile,
      );

      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('goal_requirement_matrix: failed(1)'));
      expect(
        _combinedOutput(result),
        contains('goal requirement matrix is incomplete or malformed'),
      );
      expect(
        File(
          '${goalReportDir.path}/goal_requirement_matrix.log',
        ).readAsStringSync(),
        contains('missing file:'),
      );
    },
  );

  test(
    'goal closure validator fails while device-only group is failed',
    () async {
      _writeReport(reportDir, eighthStatus: 'failed(2)');
      _writeAndroidEvidence(androidDir);
      _writeIosEvidence(iosDir);

      final result = await _runValidator(
        reportDir,
        androidDir,
        iosDir,
        goalReportDir,
        statusDir,
        matrixFile,
      );

      expect(result.exitCode, isNot(0));
      expect(
        _combinedOutput(result),
        contains(
          '8/8 device-only notification alarm widget regression is not closed: failed(2)',
        ),
      );
      expect(result.stdout, contains('alignment_report: passed'));
      expect(result.stdout, contains('android_device_evidence: passed'));
      expect(result.stdout, contains('ios_device_evidence: passed'));
      expect(
        result.stderr,
        contains('Report written to ${goalReportDir.path}'),
      );
    },
  );

  test('goal closure validator rejects stale alignment report', () async {
    _writeReport(reportDir, eighthStatus: 'passed');
    _writeAndroidEvidence(androidDir);
    _writeIosEvidence(iosDir);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final sourceFile = File('${tempDir.path}/src/lib/changed.dart');
    sourceFile.parent.createSync(recursive: true);
    sourceFile.writeAsStringSync('// changed after alignment report\n');

    final result = await _runValidator(
      reportDir,
      androidDir,
      iosDir,
      goalReportDir,
      statusDir,
      matrixFile,
      sourceRoot: sourceFile.parent.parent.path,
    );

    expect(result.exitCode, isNot(0));
    expect(result.stdout, contains('alignment_report_freshness: failed(1)'));
    expect(
      File(
        '${goalReportDir.path}/alignment_report_freshness.log',
      ).readAsStringSync(),
      contains('alignment regression report is stale'),
    );
  });
}

Future<ProcessResult> _runValidator(
  Directory reportDir,
  Directory androidDir,
  Directory iosDir,
  Directory goalReportDir,
  Directory statusDir,
  File matrixFile, {
  String? sourceRoot,
}) {
  return Process.run(
    'bash',
    ['scripts/validate_goal_closure.sh'],
    workingDirectory: Directory.current.path,
    environment: {
      'ROOT_DIR_OVERRIDE': sourceRoot ?? _emptySourceRoot(reportDir).path,
      'REPORT_DIR': reportDir.path,
      'GOAL_REPORT_DIR': goalReportDir.path,
      'ANDROID_EVIDENCE_DIR': androidDir.path,
      'IOS_EVIDENCE_DIR': iosDir.path,
      'STATUS_DIR': statusDir.path,
      'MATRIX_FILE': matrixFile.path,
    },
    includeParentEnvironment: true,
  );
}

Directory _emptySourceRoot(Directory reportDir) {
  final root = Directory('${reportDir.parent.path}/source-root');
  for (final name in [
    'android',
    'backend',
    'docs',
    'ios',
    'lib',
    'scripts',
    'test',
  ]) {
    Directory('${root.path}/$name').createSync(recursive: true);
  }
  final files = [
    File('${root.path}/pubspec.yaml')..writeAsStringSync('name: duoyi_test\n'),
    File('${root.path}/pubspec.lock')..writeAsStringSync('# lock\n'),
  ];
  final summary = File('${reportDir.path}/summary.tsv');
  if (summary.existsSync()) {
    final staleTime = summary.lastModifiedSync().subtract(
      const Duration(seconds: 1),
    );
    for (final file in files) {
      file.setLastModifiedSync(staleTime);
    }
  }
  return root;
}

void _writeReport(Directory dir, {required String eighthStatus}) {
  final groups = <String>[
    '1/8 404 and route contracts',
    '2/8 style layout and readable selection',
    '3/8 notification ringtone and status progress',
    '4/8 widgets Android and iOS static contracts',
    '5/8 admin groups default coins and permissions',
    '6/8 Flutter analyzer',
    '7/8 debug APK build',
    '8/8 device-only notification alarm widget regression',
  ];
  final summary = StringBuffer('group\tstatus\tduration_seconds\tlog\n');
  final markdown = StringBuffer('''# Alignment Regression Gate

| Group | Status | Duration | Log |
| --- | --- | ---: | --- |
''');
  for (final group in groups) {
    final log = File('${dir.path}/${group.hashCode}.log');
    log.writeAsStringSync('log for $group');
    final status = group.startsWith('8/8') ? eighthStatus : 'passed';
    summary.writeln('$group\t$status\t1\t${log.path}');
    markdown.writeln('| $group | $status | 1s | `${log.path}` |');
  }
  File('${dir.path}/summary.tsv').writeAsStringSync(summary.toString());
  File('${dir.path}/summary.md').writeAsStringSync(markdown.toString());
}

void _writeAndroidEvidence(Directory dir) {
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
    'widget_todo_complete': 'evidence/manual/android_widget_todo_complete.mp4',
    'widget_quick_add': 'evidence/manual/android_widget_quick_add.mp4',
    'widget_habit_checkin': 'evidence/manual/android_widget_habit_checkin.mp4',
    'calendar_countdown_deeplink':
        'evidence/manual/android_calendar_countdown_deeplink.mp4',
  };
  final files = <String, String>{
    'device_manufacturer.txt': 'Google',
    'device_model.txt': 'Pixel test device',
    'android_version.txt': '15',
    'android_sdk.txt': '35',
    'install.txt': 'Success',
    'launch.txt': 'Events injected: 1',
    'deeplink_duoyi___tab_today.txt': 'Status: ok',
    'deeplink_duoyi___calendar.txt': 'Status: ok',
    'deeplink_duoyi___countdown_device_regression_missing.txt': 'Status: ok',
    'deeplink_duoyi___action_quick_todo.txt': 'Status: ok',
    'deeplink_duoyi___action_complete_todo_id_device_regression_missing.txt':
        'Status: ok',
    'deeplink_duoyi___action_checkin_habit_id_device_regression_missing.txt':
        'Status: ok',
    'package.txt': 'package com.duoyi.duoyi',
    'appops.txt': 'POST_NOTIFICATION: allow',
    'notification_assistant.txt': 'allowed_assistant=none',
    'dumpsys_notification.txt': 'Duoyi today progress notification',
    'dumpsys_alarm.txt': 'ReminderRingtone RTC_WAKEUP duoyi_soft',
    'dumpsys_appwidget.txt': 'Duoyi appwidget hosts',
    'widget_providers.txt': _androidWidgetProviders(),
    'logcat_duoyi.txt': 'ReminderRingtone NotificationStatusBar AppWidget',
    'manual_required.md':
        'Notification shade\nReminder methods\nDefault ringtone\nLauncher widgets\nWidget style matrix\nCountdown deep link',
    'manual_evidence_manifest.md': manualFiles.entries
        .map((entry) => '- ${entry.key}: passed - ${entry.value}')
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
  };
  _writeFiles(dir, files);
  _writeManualMedia(dir, manualFiles.values);
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

void _writeIosEvidence(Directory dir) {
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
        .map((entry) => '- ${entry.key}: passed - ${entry.value}')
        .join('\n'),
  };
  _writeFiles(dir, files);
  _writeManualMedia(dir, manualFiles.values);
}

void _writeFiles(Directory dir, Map<String, String> files) {
  for (final entry in files.entries) {
    File('${dir.path}/${entry.key}').writeAsStringSync(entry.value);
  }
}

void _writeManualMedia(Directory dir, Iterable<String> paths) {
  for (final path in paths) {
    final file = File('${dir.path}/$path');
    file.parent.createSync(recursive: true);
    _writeFakeMedia(file);
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

String _combinedOutput(ProcessResult result) {
  return '${result.stdout}\n${result.stderr}';
}
