import 'dart:io';

import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('clears every declared account-scoped key', () async {
    SharedPreferences.setMockInitialValues({
      for (final key in AccountLocalDataCleaner.accountScopedKeys) key: 'stale',
    });

    await AccountLocalDataCleaner.clearSharedPreferences();

    final prefs = await SharedPreferences.getInstance();
    for (final key in AccountLocalDataCleaner.accountScopedKeys) {
      expect(prefs.containsKey(key), isFalse, reason: key);
    }
  });

  test('clears dynamic account-scoped prefixes', () async {
    SharedPreferences.setMockInitialValues({
      for (final prefix in AccountLocalDataCleaner.accountScopedPrefixes)
        '${prefix}legacy': 'stale',
      'sync_future_metadata': 'stale',
      'pref_daily_reminder_slot9_enabled': true,
      'pref_reminder_ringtone_fallback_channel_sound_duoyi_general_alerts_v18':
          'duoyi_soft',
      'pref_reminder_ringtone_fallback_channel_sound_schema_duoyi_general_alerts_v18':
          2,
      'duoyi_ics_events_work': '[{"summary":"admin calendar"}]',
      'duoyi_oauth_calendar_events_google': '[{"summary":"admin oauth"}]',
      'todos_corrupt_backup_20260607': '[{"title":"old backup"}]',
      'widget_display_mode_123': 'detailed',
    });

    await AccountLocalDataCleaner.clearSharedPreferences();

    final prefs = await SharedPreferences.getInstance();
    for (final prefix in AccountLocalDataCleaner.accountScopedPrefixes) {
      expect(prefs.containsKey('${prefix}legacy'), isFalse, reason: prefix);
    }
    expect(prefs.containsKey('sync_future_metadata'), isFalse);
    expect(prefs.containsKey('pref_daily_reminder_slot9_enabled'), isFalse);
    expect(
      prefs.containsKey(
        'pref_reminder_ringtone_fallback_channel_sound_duoyi_general_alerts_v18',
      ),
      isFalse,
    );
    expect(
      prefs.containsKey(
        'pref_reminder_ringtone_fallback_channel_sound_schema_duoyi_general_alerts_v18',
      ),
      isFalse,
    );
    expect(prefs.containsKey('duoyi_ics_events_work'), isFalse);
    expect(prefs.containsKey('duoyi_oauth_calendar_events_google'), isFalse);
    expect(prefs.containsKey('todos_corrupt_backup_20260607'), isFalse);
    expect(prefs.containsKey('widget_display_mode_123'), isFalse);
  });

  test('keeps device settings and current auth state', () async {
    SharedPreferences.setMockInitialValues({
      'todos': '[{"title":"admin task"}]',
      'habits': '[{"title":"admin habit"}]',
      'user_profile': '{"coin_balance":999}',
      'active_brand': 'admin-theme',
      'theme_unlocked_brands': <String>['admin-brand'],
      'duoyi_notif_history': '[{"title":"admin notification"}]',
      'ai_review_history': '[{"summary":"admin review"}]',
      'sync_pending_local_changes': true,
      'reminder_scheduler_registry_v1': '{"1":{"title":"admin alarm"}}',
      'duoyi_locale_v1': 'zh_CN',
      'app_lock_enabled': true,
      'app_lock_pin_hash': 'device-pin',
      'app_lock_auto_minutes': 10,
      'app_lock_last_active': '2026-06-07T00:00:00.000',
      'duoyi_widget_display_mode': 'compact',
      'widget_display_mode': 'compact',
      'widget_display_mode_123': 'detailed',
      'notification_status_bar_startup_build': 7,
      'webdav_backup_base_url': 'https://example.com/webdav',
      'webdav_backup_username': 'device-user',
      'webdav_backup_password': 'device-password',
      'webdav_backup_remote_path': '/duoyi-backups',
      'webdav_backup_filename': 'duoyi-latest.json',
      'auth_state': '{"user_id":"test","token":"test-token"}',
    });

    await AccountLocalDataCleaner.clearSharedPreferences();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('todos'), isNull);
    expect(prefs.getString('habits'), isNull);
    expect(prefs.getString('user_profile'), isNull);
    expect(prefs.getString('active_brand'), isNull);
    expect(prefs.getStringList('theme_unlocked_brands'), isNull);
    expect(prefs.getString('duoyi_notif_history'), isNull);
    expect(prefs.getString('ai_review_history'), isNull);
    expect(prefs.getBool('sync_pending_local_changes'), isNull);
    expect(prefs.getString('reminder_scheduler_registry_v1'), isNull);

    expect(prefs.getString('duoyi_locale_v1'), 'zh_CN');
    expect(prefs.getBool('app_lock_enabled'), isTrue);
    expect(prefs.getString('app_lock_pin_hash'), 'device-pin');
    expect(prefs.getInt('app_lock_auto_minutes'), 10);
    expect(prefs.getString('app_lock_last_active'), '2026-06-07T00:00:00.000');
    expect(prefs.getString('duoyi_widget_display_mode'), isNull);
    expect(prefs.getString('widget_display_mode'), isNull);
    expect(prefs.getString('widget_display_mode_123'), isNull);
    expect(prefs.getInt('notification_status_bar_startup_build'), 7);
    expect(prefs.getString('webdav_backup_base_url'), isNull);
    expect(prefs.getString('webdav_backup_username'), isNull);
    expect(prefs.getString('webdav_backup_password'), isNull);
    expect(prefs.getString('webdav_backup_remote_path'), isNull);
    expect(prefs.getString('webdav_backup_filename'), isNull);
    expect(
      prefs.getString('auth_state'),
      '{"user_id":"test","token":"test-token"}',
    );
  });

  test('clears account-scoped local document directories only', () async {
    final root = await Directory.systemTemp.createTemp(
      'duoyi-account-cleaner-',
    );
    try {
      for (final name
          in AccountLocalDataCleaner.accountScopedDocumentDirectories) {
        final dir = Directory('${root.path}${Platform.pathSeparator}$name');
        await dir.create(recursive: true);
        await File(
          '${dir.path}${Platform.pathSeparator}stale.txt',
        ).writeAsString('admin cache');
      }
      final deviceDir = Directory(
        '${root.path}${Platform.pathSeparator}device_exports',
      );
      await deviceDir.create(recursive: true);
      await File(
        '${deviceDir.path}${Platform.pathSeparator}keep.txt',
      ).writeAsString('device cache');

      await AccountLocalDataCleaner.clearDocumentDirectoriesForTest(root);

      for (final name
          in AccountLocalDataCleaner.accountScopedDocumentDirectories) {
        final dir = Directory('${root.path}${Platform.pathSeparator}$name');
        expect(await dir.exists(), isFalse, reason: name);
      }
      expect(await deviceDir.exists(), isTrue);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test(
    'declares notification, alarm, geofence, AI and calendar cache keys',
    () {
      expect(
        AccountLocalDataCleaner.accountScopedKeys,
        containsAll(<String>[
          'duoyi_notif_history',
          'duoyi_notif_history_seen_at',
          'ai_review_history',
          'reminder_scheduler_registry_v1',
          'duoyi_location_reminders_v1',
          'duoyi_ics_subscriptions_v1',
          'duoyi_oauth_calendar_accounts_v1',
          'duoyi_oauth_calendar_pending_authorization_v1',
          'duoyi_caldav_write_target_v1',
          'duoyi_caldav_pushed_uids_v1',
          'duoyi_caldav_pushed_etags_v1',
          'pref_daily_reminder_kind',
          'pref_daily_reminder_repeat_days',
        ]),
      );
      expect(
        AccountLocalDataCleaner.accountScopedPrefixes,
        containsAll(<String>[
          'duoyi_ics_',
          'duoyi_ics_events_',
          'duoyi_oauth_calendar_',
          'duoyi_oauth_calendar_events_',
          'duoyi_caldav_',
          'widget_display_mode_',
        ]),
      );
      expect(
        AccountLocalDataCleaner.accountScopedDocumentDirectories,
        containsAll(<String>[
          'custom_focus_sounds',
          'profile_avatars',
          'avatar_cache',
        ]),
      );
    },
  );

  test(
    'account cleanup entrypoint clears native schedulers and service caches',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final block = _sourceBlock(
        source,
        'Future<void> clearAccountLocalData({required String reason}) async {',
        'String firstNonEmptyProfileText',
      );

      expect(block, contains('cloudSyncProvider.resetForAccountChange()'));
      expect(block, contains('notificationService.cancelAll'));
      expect(block, contains('AlarmService.instance.cancelAll'));
      expect(block, contains('LocationGeofenceService.clearReminders'));
      expect(
        block,
        contains('AccountLocalDataCleaner.clearSharedPreferences()'),
      );
      expect(block, contains('AccountLocalDataCleaner.clearLocalFiles'));
      expect(block, contains('calendarSyncProvider.resetLocalState()'));
      expect(block, contains('aiService.resetLocalState()'));
      expect(block, contains('notificationService.resetLocalState()'));
      expect(block, contains('AccountLocalDataCleaner.clearLocalFiles'));
      expect(block, contains('HomeWidgetService.resetAccountCache()'));
      expect(block, contains('await _pushHomeWidget('));
      expect(
        block.indexOf('HomeWidgetService.resetAccountCache()'),
        lessThan(block.indexOf('await _pushHomeWidget(')),
      );
    },
  );

  test('home widget reset clears every native account payload key', () {
    final source = File(
      'lib/services/home_widget_service.dart',
    ).readAsStringSync();
    final defaultBlock = _sourceBlock(
      source,
      'accountPayloadDefaults = <String, Object>{',
      '  };',
    );
    final savedKeys = RegExp(
      r"HomeWidget\.saveWidgetData<[^>]+>\(\s*'([^']+)'",
      multiLine: true,
    ).allMatches(source).map((match) => match.group(1)!).toSet();
    final defaultKeys = RegExp(
      r"'([^']+)'\s*:",
    ).allMatches(defaultBlock).map((match) => match.group(1)!).toSet();

    expect(
      defaultKeys,
      containsAll(savedKeys.difference({'widget_display_mode'})),
    );
    expect(defaultKeys, isNot(contains('widget_display_mode')));
    expect(defaultKeys, contains('todo_top3_1_id'));
    expect(defaultKeys, contains('calendar_month_summary'));
    expect(defaultKeys, contains('habit_quick_check_id'));
    expect(defaultKeys, contains('widget_theme_background_asset_key'));
    expect(source, contains('static Future<bool> clearAccountWidgetData()'));
    expect(source, contains('HomeWidget.saveWidgetData<bool>'));
    expect(source, contains('HomeWidget.saveWidgetData<int>'));
    expect(source, contains('HomeWidget.saveWidgetData<String>'));
    expect(
      source,
      contains('AndroidWidgetManager.clearDisplayModeOverrides()'),
    );

    final resetBlock = _sourceBlock(
      source,
      'static void resetAccountCache() {',
      'static Future<bool> clearAccountWidgetData()',
    );
    expect(resetBlock, contains('_lastThemeSignature = \'\';'));
    expect(resetBlock, contains('_lastPushSignature = \'\';'));
    expect(resetBlock, contains('clearAccountWidgetData()'));

    final pushBlock = _sourceBlock(
      source,
      'static Future<bool> push({',
      'final signature = _pushSignature(',
    );
    expect(pushBlock, contains('await _drainPendingAccountClear();'));
  });

  test('native widget display mode overrides are cleared on account reset', () {
    final displayMode = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetDisplayMode.kt',
    ).readAsStringSync();
    expect(displayMode, contains('PER_WIDGET_KEY_PREFIX'));
    expect(displayMode, contains('fun clearAll('));
    expect(displayMode, contains('prefs.all.keys'));

    final registry = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetVariantProviders.kt',
    ).readAsStringSync();
    expect(registry, contains('fun clearDisplayModeOverrides('));
    expect(registry, contains('DuoyiWidgetDisplayMode.clearAll(prefs)'));
    expect(registry, contains('standard.toOptions()'));

    final activity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    expect(activity, contains('"clearWidgetDisplayModes"'));

    final manager = File(
      'lib/services/android_widget_manager.dart',
    ).readAsStringSync();
    expect(manager, contains('clearDisplayModeOverrides'));
    expect(manager, contains('clearWidgetDisplayModes'));
  });

  test('service reset methods drop in-memory account state', () {
    final notification = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final notificationReset = _sourceBlock(
      notification,
      'void resetLocalState() {',
      'void clearScheduleIssue()',
    );
    expect(notificationReset, contains('_pomodoroNotificationTimer?.cancel()'));
    expect(notificationReset, contains('_pendingNotifications = 0'));
    expect(notificationReset, contains('_history.clear()'));
    expect(notificationReset, contains('_historyLastSeenAt = null'));
    expect(notificationReset, contains('_clearScheduleIssueState()'));

    final ai = File('lib/services/ai_service.dart').readAsStringSync();
    final aiReset = _sourceBlock(
      ai,
      'void resetLocalState() {',
      'Future<void> _saveHistory()',
    );
    expect(aiReset, contains('_reviewHistory = []'));

    final calendar = File(
      'lib/services/calendar_sync_service.dart',
    ).readAsStringSync();
    final calendarReset = _sourceBlock(
      calendar,
      'void resetLocalState() {',
      'Future<void> addSubscription',
    );
    expect(calendarReset, contains('_subscriptions.clear()'));
    expect(calendarReset, contains('_oauthAccounts.clear()'));
    expect(calendarReset, contains('_eventsBySubscription.clear()'));
    expect(calendarReset, contains('_eventsByOAuthAccount.clear()'));
    expect(calendarReset, contains('_writeTarget = null'));
    expect(calendarReset, contains('_lastCalDavConflicts.clear()'));
  });
}

String _sourceBlock(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, isNonNegative, reason: startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, isNonNegative, reason: endMarker);
  return source.substring(start, end);
}
