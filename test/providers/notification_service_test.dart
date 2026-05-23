import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('clearHistory only clears notification history and refreshes UI', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> clearHistory()');
    final end = source.indexOf('@override', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('_history.clear();'));
    expect(method, isNot(contains('_pendingNotifications = 0;')));
    expect(method, contains('await _saveHistory();'));
    expect(method, contains('notifyListeners();'));
    expect(
      method.indexOf('_history.clear();'),
      lessThan(method.indexOf('await _saveHistory();')),
    );
    expect(
      method.indexOf('await _saveHistory();'),
      lessThan(method.indexOf('notifyListeners();')),
    );
  });

  test('cancel decrements pending notification count and refreshes UI', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> cancel(int id)');
    final end = source.indexOf('/// 取消全部已调度通知', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('LocalNotifications.instance.cancel(id)'));
    expect(method, contains('if (_pendingNotifications > 0)'));
    expect(method, contains('_pendingNotifications--;'));
    expect(method, contains('notifyListeners();'));
  });

  test('Mine notification history entry hides zero history count', () {
    final source = File('lib/screens/mine_screen.dart').readAsStringSync();
    final start = source.indexOf("label: '通知记录'");
    final end = source.indexOf(
      'if (auth.state.isLoggedIn && auth.state.isAdmin)',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final entry = source.substring(start, end);

    expect(entry, contains('notifService.historyCount == 0'));
    expect(entry, contains('? null'));
    expect(entry, contains(r"'${notifService.historyCount} 条'"));
  });

  test(
    'Mine notification history and reminder preferences are separate entries',
    () {
      final source = File('lib/screens/mine_screen.dart').readAsStringSync();
      final groupStart = source.indexOf("title: '通知支持'");
      final groupEnd = source.indexOf("label: '公告'", groupStart);
      expect(groupStart, greaterThanOrEqualTo(0));
      expect(groupEnd, greaterThan(groupStart));
      final group = source.substring(groupStart, groupEnd);

      expect(group, contains("label: '通知记录'"));
      expect(group, contains('onTap: () => _openNotificationHistory(context)'));
      expect(group, contains("label: s.mineNotificationsLabel"));
      expect(group, contains("subtitle: '管理提醒时间、通知权限和铃声'"));
      expect(
        group,
        contains('onTap: () => _openNotificationSettings(context)'),
      );
      expect(
        group.indexOf("label: '通知记录'"),
        lessThan(group.indexOf("label: s.mineNotificationsLabel")),
      );
      expect(group, isNot(contains("label: '通知设置'")));
    },
  );

  test('Mine notification settings opens preferences notification section', () {
    final source = File('lib/screens/mine_screen.dart').readAsStringSync();

    expect(
      source,
      contains('void _openNotificationSettings(BuildContext context)'),
    );
    expect(
      source,
      contains('initialSection: PreferencesInitialSection.notifications'),
    );
    expect(
      source,
      contains('void _openNotificationHistory(BuildContext context)'),
    );
    expect(source, contains('const _NotificationHistoryScreen()'));
    expect(source, isNot(contains('void _notifDialog')));
    expect(source, isNot(contains('onTap: () => _notifDialog')));
  });

  test('notification history is a dedicated scrollable page', () {
    final source = File('lib/screens/mine_screen.dart').readAsStringSync();
    final start = source.indexOf('class _NotificationHistoryScreen');
    final end = source.indexOf('class _ChangePasswordDialog', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final screen = source.substring(start, end);

    expect(screen, contains('class _NotificationHistoryScreenState'));
    expect(screen, contains("title: const Text('通知记录')"));
    expect(screen, contains('TextField('));
    expect(screen, contains("hintText: '搜索标题、内容或关联 ID'"));
    expect(screen, contains('NotificationType? _typeFilter'));
    expect(screen, contains('List<NotificationItem> _filteredHistory'));
    expect(screen, contains('ChoiceChip('));
    expect(screen, contains('for (final type in NotificationType.values)'));
    expect(screen, contains('_notificationTypeLabel(type)'));
    expect(screen, contains('static const _pageSize = 50;'));
    expect(screen, contains('final visibleHistory = filteredHistory.sublist'));
    expect(screen, contains('itemCount: visibleHistory.length'));
    expect(screen, contains("tooltip: '上一页'"));
    expect(screen, contains("tooltip: '下一页'"));
    expect(screen, contains('setState(_resetPaging)'));
    expect(screen, contains('ListView.separated'));
    expect(screen, contains('clearHistory()'));
    expect(screen, contains('Future<void> _confirmClearHistory(int count)'));
    expect(screen, contains("title: const Text('清空通知记录？')"));
    expect(screen, contains('已调度的提醒不会被取消'));
    expect(screen, contains("const Center(child: Text('暂无通知记录'))"));
    expect(screen, contains("message: '没有匹配的通知记录'"));
    expect(screen, contains('支持搜索、筛选和分页浏览'));
    expect(screen, isNot(contains('take(10)')));
  });

  test('notification history keeps enough records for the dedicated list', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final policy = File(
      'lib/core/notification_history_policy.dart',
    ).readAsStringSync();
    final preferences = File(
      'lib/providers/preferences_provider.dart',
    ).readAsStringSync();
    final preferencesScreen = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();

    expect(
      policy,
      contains("preferenceKey = 'pref_notification_history_limit'"),
    );
    expect(policy, contains('defaultLimit = 500'));
    expect(policy, contains('maxLimit = 5000'));
    expect(policy, contains('options = <int>[100, 500, 1000, 2000, 5000]'));
    expect(
      source,
      contains('int _historyLimit = NotificationHistoryPolicy.defaultLimit'),
    );
    expect(source, contains('int get historyLimit => _historyLimit'));
    expect(
      source,
      contains('p.getInt(NotificationHistoryPolicy.preferenceKey)'),
    );
    expect(source, contains('Future<void> setHistoryLimit(int value)'));
    expect(
      source,
      contains('_history.removeRange(_historyLimit, _history.length)'),
    );
    expect(source, contains('_history'));
    expect(source, contains('.take(_historyLimit)'));
    expect(source, isNot(contains('_history.take(50)')));
    expect(source, isNot(contains('_history.length > 50')));
    expect(source, isNot(contains('static const _maxHistoryItems = 500;')));
    expect(preferences, contains('int get notificationHistoryLimit'));
    expect(preferences, contains('setNotificationHistoryLimit'));
    expect(preferencesScreen, contains("title: '通知记录保留'"));
    expect(preferencesScreen, contains('p.notificationHistoryLimit'));
    expect(preferencesScreen, contains('notif.setHistoryLimit'));
  });

  test('all normal notification paths are recorded in history', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();

    void expectMethodRecordsHistory(String startNeedle, String endNeedle) {
      final start = source.indexOf(startNeedle);
      final end = source.indexOf(endNeedle, start);
      expect(start, greaterThanOrEqualTo(0), reason: startNeedle);
      expect(end, greaterThan(start), reason: endNeedle);
      final method = source.substring(start, end);
      expect(method, contains('_addToHistory('), reason: startNeedle);
      expect(method, contains('NotificationItem('), reason: startNeedle);
    }

    expectMethodRecordsHistory(
      'Future<void> show({',
      '/// 稍后提醒（Snooze, Task T-12）。',
    );
    expectMethodRecordsHistory(
      'Future<void> snooze({',
      '/// 通过 deep-link `duoyi://snooze/{id}?delay={minutes}` 触发的快捷路径。',
    );
    expectMethodRecordsHistory(
      'Future<void> scheduleOnce({',
      '/// 每日固定时间的 push 通知',
    );
    expectMethodRecordsHistory(
      'Future<void> scheduleDaily({',
      '/// 取消某个已调度的通知。',
    );
    expectMethodRecordsHistory(
      'Future<void> scheduleTodoReminder({',
      '@override\n  Future<void> cancelTodoReminder',
    );
    expectMethodRecordsHistory(
      'Future<void> scheduleHabitReminder({',
      '@override\n  Future<void> cancelHabitReminder',
    );
    expectMethodRecordsHistory(
      'Future<void> scheduleAnniversary({',
      '@override\n  Future<void> cancelAnniversary',
    );

    expect(source, contains('NotificationType.todo'));
    expect(source, contains('NotificationType.habit'));
    expect(source, contains('NotificationType.anniversary'));
  });

  test('preferences screen can scroll directly to notification settings', () {
    final source = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('enum PreferencesInitialSection { bottomNav, notifications }'),
    );
    expect(
      source,
      contains('final PreferencesInitialSection? initialSection;'),
    );
    expect(source, contains("title: '提醒偏好 / 通知设置'"));
    expect(source, contains("subtitle: '管理每日提醒、通知权限、通知记录保留和提醒铃声'"));
    expect(source, contains('GlobalKey _notificationSectionKey'));
    expect(source, contains('int _initialSectionScrollAttempts = 0;'));
    expect(source, contains('if (!mounted) return;'));
    expect(source, contains('if (_initialSectionScrollAttempts >= 2) return;'));
    expect(source, contains('Scrollable.ensureVisible'));
    expect(source, contains('key: _notificationSectionKey'));
    final notificationSectionStart = source.indexOf(
      'key: _notificationSectionKey',
    );
    final notificationSectionEnd = source.indexOf(
      'const _ReportReminderSection()',
      notificationSectionStart,
    );
    expect(notificationSectionStart, greaterThanOrEqualTo(0));
    expect(notificationSectionEnd, greaterThan(notificationSectionStart));
    final notificationSection = source.substring(
      notificationSectionStart,
      notificationSectionEnd,
    );
    expect(notificationSection, contains("title: '通知记录保留'"));
    expect(notificationSection, contains('_notificationHistoryLimitOptions'));
    expect(notificationSection, contains('setNotificationHistoryLimit'));
    expect(notificationSection, contains('setHistoryLimit'));
    expect(notificationSection, contains('p.dailyReminderSlots.length'));
    expect(notificationSection, contains('_DailyReminderSlotTile('));
  });

  test('scheduled diagnostic test uses ordinary notification path', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> sendScheduledTest');
    final end = source.indexOf('void notifyAchievementUnlocked', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('LocalNotifications.instance.scheduleOnce'));
    expect(method, contains('定时通知调度正常'));
    expect(method, isNot(contains('AlarmService.instance.scheduleFullScreen')));
  });

  test('immediate diagnostic test uses ordinary notification path', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> sendTest');
    final end = source.indexOf('Future<void> sendScheduledTest', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('LocalNotifications.instance.show'));
    expect(method, contains('多仪 · 通知测试'));
    expect(method, isNot(contains('AlarmService.instance.showFullScreenTest')));
    expect(method, isNot(contains('HapticFeedback.vibrate')));
    expect(method, isNot(contains('LocalNotifications.instance.scheduleOnce')));
  });

  test('location reminders use local notification, history and deep link', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('void notifyLocationReminderHit');
    final end = source.indexOf('/// 调度一次性待办到期提醒', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('_showImmediate'));
    expect(method, contains('NotificationType.location'));
    expect(method, contains('relatedId: reminder.id'));
    expect(method, contains("return 'duoyi://location/"));
    expect(method, contains("return 'duoyi://todo/"));
    expect(method, contains("return 'duoyi://goal/"));
  });

  test('location notification deep link opens integrations center', () {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf("uri.host == 'location'");
    final end = source.indexOf("uri.host == 'snooze'", start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final branch = source.substring(start, end);

    expect(branch, contains('state?.navigateTo(6)'));
    expect(branch, contains('const IntegrationsScreen()'));
  });

  test('todo completion deep link reuses the optional time record flow', () {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf("action == 'complete_todo'");
    final end = source.indexOf("action == 'checkin_habit'", start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final branch = source.substring(start, end);

    expect(branch, contains('completeTodoWithOptionalTimeRecord(ctx, target)'));
    expect(branch, isNot(contains('todos.toggleTodo(id);')));
  });

  test(
    'snooze deep link and todo action path reuse the same reminder payload',
    () {
      final notificationService = File(
        'lib/providers/notification_service.dart',
      ).readAsStringSync();
      final localNotifications = File(
        'lib/services/local_notifications_io.dart',
      ).readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();

      final snoozeStart = notificationService.indexOf('Future<void> snooze({');
      final snoozeEnd = notificationService.indexOf(
        '/// 通过 deep-link `duoyi://snooze/{id}?delay={minutes}` 触发的快捷路径。',
        snoozeStart,
      );
      expect(snoozeStart, greaterThanOrEqualTo(0));
      expect(snoozeEnd, greaterThan(snoozeStart));
      final snoozeMethod = notificationService.substring(
        snoozeStart,
        snoozeEnd,
      );
      expect(snoozeMethod, contains('LocalNotifications.instance.cancel(id);'));
      expect(snoozeMethod, contains('DateTime.now().add(delay)'));
      expect(
        snoozeMethod,
        contains('LocalNotifications.instance.scheduleOnce'),
      );
      expect(snoozeMethod, contains('payload: payload,'));
      expect(snoozeMethod, contains('channelId: channelId,'));

      final handleStart = notificationService.indexOf(
        'Future<void> handleSnoozeDeepLink(Uri uri)',
      );
      final handleEnd = notificationService.indexOf(
        '/// 上层（通知中心、深链处理或通知 action）调用此通用方法重新调度提醒。',
        handleStart,
      );
      expect(handleStart, greaterThan(snoozeEnd));
      expect(handleEnd, greaterThan(handleStart));
      final handleMethod = notificationService.substring(
        handleStart,
        handleEnd,
      );
      expect(handleMethod, contains("if (uri.host != 'snooze') return;"));
      expect(
        handleMethod,
        contains(
          "final minutes = int.tryParse(uri.queryParameters['delay'] ?? '5') ?? 5;",
        ),
      );
      expect(
        handleMethod,
        contains("final payload = uri.queryParameters['payload'];"),
      );
      expect(handleMethod, contains('await snooze('));
      expect(handleMethod, contains('Duration(minutes: minutes)'));

      expect(
        localNotifications,
        contains("if (actionId.startsWith('todo_snooze_'))"),
      );
      expect(localNotifications, contains(r"duoyi://snooze/${resp.id ?? 0}"));
      expect(
        localNotifications,
        contains(r'?delay=5&payload=duoyi://todo/$id'),
      );
      expect(localNotifications, contains(r'todo_snooze_$id'));
      expect(localNotifications, contains('5 分钟后'));

      final snoozeBranchStart = main.indexOf("uri.host == 'snooze'");
      final snoozeBranchEnd = main.indexOf(
        "uri.host == 'action'",
        snoozeBranchStart,
      );
      expect(snoozeBranchStart, greaterThanOrEqualTo(0));
      expect(snoozeBranchEnd, greaterThan(snoozeBranchStart));
      final snoozeBranch = main.substring(snoozeBranchStart, snoozeBranchEnd);
      expect(
        snoozeBranch,
        contains('Provider.of<NotificationService>(ctx, listen: false)'),
      );
      expect(snoozeBranch, contains('ns.handleSnoozeDeepLink(uri)'));
    },
  );
}
