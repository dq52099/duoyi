import 'dart:async';
import 'dart:io';

import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/notification_history_screen.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/alarm_service.dart';
import 'package:duoyi/services/native_reminder_ringtone.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('每日提醒闹钟保存先检查精准闹钟和全屏权限', () {
    final source = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final saveStart = source.indexOf('Future<void> _save(');
    final saveEnd = source.indexOf('Future<bool> _ensureReminderSlotReady');
    final saveBody = source.substring(saveStart, saveEnd);
    expect(saveBody, contains('_ensureReminderSlotReady(context, next)'));
    expect(saveBody, contains('_syncReminderSlotAfterSave(context)'));

    final helperStart = source.indexOf('Future<bool> _ensureReminderSlotReady');
    final helperEnd = source.indexOf('void _showSlotSaveError', helperStart);
    final helper = source.substring(helperStart, helperEnd);
    expect(helper, contains('kind == ReminderKind.alarm'));
    expect(helper, contains('AlarmService.instance.init()'));
    expect(helper, contains('hasExactAlarmPermission()'));
    expect(helper, contains('requestExactAlarmPermission()'));
    expect(helper, contains('hasFullScreenIntentPermission()'));
    expect(helper, contains('requestFullScreenIntentPermission()'));
    expect(
      helper.indexOf('kind == ReminderKind.alarm'),
      lessThan(helper.indexOf('ensureReadyForReminder(')),
    );
  });

  test('每日提醒保存后等待真实系统注册结果', () {
    final screen = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(
      screen,
      contains("import '../services/daily_digest_reminder_sync.dart';"),
    );
    final syncStart = screen.indexOf('Future<void> _syncReminderSlotAfterSave');
    final syncEnd = screen.indexOf('Future<bool> _ensureReminderSlotReady');
    expect(syncStart, greaterThanOrEqualTo(0));
    expect(syncEnd, greaterThan(syncStart));
    final syncBody = screen.substring(syncStart, syncEnd);
    expect(syncBody, contains('context.read<DailyDigestReminderSync?>()'));
    expect(syncBody, contains('notif?.clearScheduleIssue()'));
    expect(syncBody, contains('result = await sync.registerImmediately()'));
    expect(syncBody, contains('result.issueForSlot(index)'));
    expect(syncBody, isNot(contains('notif?.lastScheduleIssue')));
    expect(syncBody, isNot(contains('_isDailyReminderIssue(issue)')));
    expect(
      syncBody,
      contains('NotificationUiCopy.dailyRegistrationIssue(issue)'),
    );
    expect(syncBody, contains('NotificationUiCopy.dailyRegistrationFailed'));

    expect(
      main,
      contains("import 'services/daily_digest_reminder_sync.dart';"),
    );
    expect(main, contains('Provider<DailyDigestReminderSync>.value'));
    expect(main, contains('registerImmediately: ()'));
    expect(main, contains('dailyDigestSyncDebounce?.cancel();'));
    expect(main, contains('return syncDailyDigestReminder();'));
    expect(
      main,
      contains('Future<DailyDigestReminderResult> _syncDailyDigestReminder('),
    );
  });

  test('提醒注册状态入口摘要使用明确状态口径', () {
    final screen = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final summaryStart = screen.indexOf('String _registeredReminderSummary()');
    final stateStart = screen.indexOf(
      '_RegisteredReminderQueueState _settingsQueueStateFor',
    );
    final stateEnd = screen.indexOf(
      'Future<void> _showRegisteredReminderDetails',
      stateStart,
    );
    expect(summaryStart, greaterThanOrEqualTo(0));
    expect(stateStart, greaterThan(summaryStart));
    expect(stateEnd, greaterThan(stateStart));
    final summary = screen.substring(summaryStart, stateEnd);

    expect(summary, contains('NotificationUiCopy.registeredSummary('));
    expect(summary, contains('queued: queued'));
    expect(summary, contains('partial: partial'));
    expect(summary, contains('unconfirmed: unconfirmed'));
    expect(summary, contains('missing: missing'));
    expect(summary, contains('_registeredReminderQueueProbe'));
    expect(summary, contains('_RegisteredReminderQueueProbe.resolved'));
    expect(summary, contains('_entryAcceptedBySystemQueue'));
    expect(summary, contains('_entryHasAnySystemQueueHit'));
    expect(summary, isNot(contains('生效')));
    expect(summary, isNot(contains('未生效')));
  });

  test('通知记录详情使用滚动容器避免长内容小屏溢出', () {
    final source = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final detailStart = source.indexOf('class _NotificationRecordDetailSheet');
    final detailEnd = source.indexOf(
      'class _NotificationRecordDetailLine',
      detailStart,
    );
    expect(detailStart, greaterThanOrEqualTo(0));
    expect(detailEnd, greaterThan(detailStart));
    final detail = source.substring(detailStart, detailEnd);

    expect(detail, contains('SingleChildScrollView('));
    expect(detail, contains("ValueKey('notification_record_detail_scroll')"));
    expect(source, contains('isScrollControlled: true'));
    expect(detail, contains('detailSheetContentLabel'));
  });

  test('1 分钟弹出测试使用全局 popup sink 而不是临时 sink', () {
    final source = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final methodStart = source.indexOf('Future<void> _sendScheduledDiagnostic');
    final methodEnd = source.indexOf(
      'void _showScheduleIssueSnack',
      methodStart,
    );
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);

    expect(
      method,
      contains('final scheduler = _readReminderScheduler(context);'),
    );
    expect(method, contains('popup: scheduler?.popup'));
    expect(method, isNot(contains('ForegroundReminderPopupSink(')));
    expect(method, isNot(contains('ReminderInAppOnlyPopupSink(')));
    expect(method, isNot(contains('notificationFallback: service')));
  });

  test('AI 待办创建等待提醒同步结果而不是读取旧状态', () {
    final source = File(
      'lib/screens/ai_schedule_screen.dart',
    ).readAsStringSync();
    final todoStart = source.indexOf('final todo = draft.toTodo()');
    final syncStatusStart = source.indexOf(
      'final syncStatus = _syncStatus()',
      todoStart,
    );
    expect(todoStart, greaterThanOrEqualTo(0));
    expect(syncStatusStart, greaterThan(todoStart));
    final todoBranch = source.substring(todoStart, syncStatusStart);
    final addTodoIndex = todoBranch.indexOf(
      'final reminderSyncResult = await todoProvider.addTodoWithResult(',
    );
    expect(addTodoIndex, greaterThanOrEqualTo(0));
    final afterAddTodo = todoBranch.substring(addTodoIndex);

    expect(
      todoBranch,
      contains(
        'final reminderSyncResult = await todoProvider.addTodoWithResult(',
      ),
    );
    expect(todoBranch, contains('waitForReminderSync: true'));
    expect(todoBranch, contains('reminderSyncResult.hasIssue'));
    expect(todoBranch, contains('AiScheduleUiCopy.renderReminderIssue'));
    expect(
      afterAddTodo,
      isNot(contains('final issue = notificationService.lastScheduleIssue')),
    );
  });

  test('已注册提醒页回写分页 clamp 并用 generation 丢弃旧队列结果', () {
    final source = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final stateStart = source.indexOf('class _RegisteredRemindersScreenState');
    final stateEnd = source.indexOf('class _RegisteredReminderProbeBanner');
    expect(stateStart, greaterThanOrEqualTo(0));
    expect(stateEnd, greaterThan(stateStart));
    final state = source.substring(stateStart, stateEnd);

    expect(state, contains('int _loadGeneration = 0;'));
    expect(state, contains('final generation = ++_loadGeneration;'));
    expect(state, contains('loadGeneration == _loadGeneration'));
    expect(state, contains('_isCurrentAccount(accountGeneration, key)'));
    expect(
      state,
      contains('_isCurrentLoad(generation, accountGeneration, accountKey)'),
    );
    expect(
      state,
      contains(
        '_resolveSystemQueue(generation, accountGeneration, accountKey)',
      ),
    );
    expect(state, contains('if (currentPage != _page)'));
    expect(state, contains('setState(() => _page = currentPage)'));
    expect(state, contains('_refreshOpenDetailSnapshot();'));
  });

  testWidgets('通知记录 320px 下批量已读和筛选区不挤压', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    service.addHistoryForTest(
      NotificationItem(
        id: 'unread-long-title',
        title: '待办提醒：一条很长的通知标题用于验证窄屏布局',
        body: '这里是一段较长的通知内容，用来覆盖 320px 下通知记录卡片和筛选区域的换行表现。',
        scheduledTime: DateTime(2026, 6, 9, 8),
        type: NotificationType.todo,
        isRead: false,
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<NotificationService>.value(
        value: service,
        child: const MaterialApp(home: NotificationHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('通知记录'), findsOneWidget);
    expect(find.text('全部'), findsAtLeastNWidgets(1));
    expect(find.text('未读'), findsAtLeastNWidgets(1));
    expect(find.text('已读'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const ValueKey('notification_history_mark_all_read_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('notification_history_mark_all_read_button')),
    );
    await tester.pumpAndSettle();

    expect(service.unreadCount, 0);
    expect(
      find.byKey(const ValueKey('notification_history_mark_all_read_button')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('通知设置 320px 下操作对齐且宽操作自适应换行', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    service.addHistoryForTest(
      NotificationItem(
        id: 'unread-entry',
        title: '待办提醒',
        body: '通知设置入口布局验证',
        scheduledTime: DateTime(2026, 6, 9, 9),
        type: NotificationType.todo,
        isRead: false,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NotificationService>.value(value: service),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ],
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await tester.pump();
    final permissionTile = find.byKey(
      const ValueKey('notification_permission_tile'),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(of: permissionTile, matching: find.text('通知权限')),
      subtitle: find.descendant(
        of: permissionTile,
        matching: find.text('开启后才能收到普通通知和提醒'),
      ),
      icon: find.descendant(
        of: permissionTile,
        matching: find.byIcon(Icons.notifications_off_outlined),
      ),
      action: find.descendant(of: permissionTile, matching: find.text('开启')),
    );
    final normalChannelTile = find.ancestor(
      of: find.text('普通提醒渠道'),
      matching: find.byType(AppSettingsTile),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: normalChannelTile,
        matching: find.text('普通提醒渠道'),
      ),
      subtitle: find.descendant(
        of: normalChannelTile,
        matching: find.textContaining('检查普通通知的声音、横幅和锁屏权限'),
      ),
      icon: find.descendant(
        of: normalChannelTile,
        matching: find.byIcon(Icons.settings_outlined),
      ),
      action: find.byKey(
        const ValueKey(
          'notification_channel_status_${NotificationService.channelId}',
        ),
      ),
    );
    final alarmChannelTile = find.ancestor(
      of: find.text('强提醒渠道'),
      matching: find.byType(AppSettingsTile),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: alarmChannelTile,
        matching: find.text('强提醒渠道'),
      ),
      subtitle: find.descendant(
        of: alarmChannelTile,
        matching: find.textContaining('检查闹钟提醒的声音、横幅和全屏展示权限'),
      ),
      icon: find.descendant(
        of: alarmChannelTile,
        matching: find.byIcon(Icons.alarm_on_outlined),
      ),
      action: find.byKey(
        const ValueKey('notification_channel_status_${AlarmService.channelId}'),
      ),
    );
    final fallbackChannelTile = find.ancestor(
      of: find.text('闹钟降级兜底'),
      matching: find.byType(AppSettingsTile),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: fallbackChannelTile,
        matching: find.text('闹钟降级兜底'),
      ),
      subtitle: find.descendant(
        of: fallbackChannelTile,
        matching: find.textContaining('强提醒或内置铃声注册失败时会改用普通提醒'),
      ),
      icon: find.descendant(
        of: fallbackChannelTile,
        matching: find.byIcon(Icons.alt_route_outlined),
      ),
      action: find.byKey(
        const ValueKey(
          'notification_channel_status_${NativeReminderRingtone.fallbackChannelId}',
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('已调度闹钟提醒'),
      900,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    final pendingPushTile = find.byKey(
      const ValueKey('notification_pending_push_tile'),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: pendingPushTile,
        matching: find.text('已调度普通提醒'),
      ),
      subtitle: find.descendant(
        of: pendingPushTile,
        matching: find.textContaining('待触发'),
      ),
      icon: find.descendant(
        of: pendingPushTile,
        matching: find.byIcon(Icons.schedule),
      ),
      action: find.byKey(
        const ValueKey('notification_pending_push_refresh_button'),
      ),
    );
    final pendingAlarmTile = find.byKey(
      const ValueKey('notification_pending_alarm_tile'),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: pendingAlarmTile,
        matching: find.text('已调度闹钟提醒'),
      ),
      subtitle: find.descendant(
        of: pendingAlarmTile,
        matching: find.textContaining('强提醒队列'),
      ),
      icon: find.descendant(
        of: pendingAlarmTile,
        matching: find.byIcon(Icons.alarm_on_outlined),
      ),
      action: find.byKey(
        const ValueKey('notification_pending_alarm_exact_button'),
      ),
    );
    final registeredTile = find.byKey(
      const ValueKey('notification_registered_reminders_tile'),
    );
    final registeredSubtitle = _firstExisting(tester, [
      find.descendant(
        of: registeredTile,
        matching: find.textContaining('提醒注册表'),
      ),
      find.descendant(
        of: registeredTile,
        matching: find.textContaining('提醒调度器'),
      ),
      find.descendant(
        of: registeredTile,
        matching: find.textContaining('提醒对象'),
      ),
    ]);
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(of: registeredTile, matching: find.text('提醒注册状态')),
      subtitle: registeredSubtitle,
      icon: find.descendant(
        of: registeredTile,
        matching: find.byIcon(Icons.fact_check_outlined),
      ),
      action: find.byKey(
        const ValueKey('notification_registered_reminders_refresh_button'),
      ),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(of: registeredTile, matching: find.text('提醒注册状态')),
      subtitle: registeredSubtitle,
      icon: find.descendant(
        of: registeredTile,
        matching: find.byIcon(Icons.fact_check_outlined),
      ),
      action: find.byKey(
        const ValueKey('notification_registered_reminders_view_button'),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notification_history_entry_tile')),
      1200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();

    final titleRect = tester.getRect(
      find.byKey(const ValueKey('notification_history_entry_title')),
    );
    final historyTileRect = tester.getRect(
      find.byKey(const ValueKey('notification_history_entry_tile')),
    );
    final historyIconRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('notification_history_entry_tile')),
        matching: find.byIcon(Icons.history_outlined),
      ),
    );
    final subtitleRect = tester.getRect(find.text('共 1 条，未读 1 条'));
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('notification_history_entry_view_button')),
    );
    final historyTextCenterDy = _textBlockCenterDy(titleRect, subtitleRect);

    expect(historyTileRect.height, greaterThan(historyIconRect.height));
    expect(
      (historyIconRect.center.dy - historyTextCenterDy).abs(),
      lessThan(5),
    );
    expect((buttonRect.center.dy - historyTextCenterDy).abs(), lessThan(5));
    expect(subtitleRect.top, greaterThan(titleRect.bottom));
    expect(buttonRect.left, greaterThan(titleRect.right));
    expect(find.text('共 1 条，未读 1 条'), findsOneWidget);
    final historyLimitTile = find.byKey(
      const ValueKey('notification_history_limit_tile'),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: historyLimitTile,
        matching: find.text('通知记录保留'),
      ),
      subtitle: find.descendant(
        of: historyLimitTile,
        matching: find.textContaining('最多保留'),
      ),
      icon: find.descendant(
        of: historyLimitTile,
        matching: find.byIcon(Icons.inventory_2_outlined),
      ),
      action: find.byKey(const ValueKey('notification_history_limit_dropdown')),
      stacked: true,
    );

    if (find
        .byKey(const ValueKey('notification_quick_add_switch'))
        .evaluate()
        .isNotEmpty) {
      final quickAddTile = find.byKey(
        const ValueKey('notification_quick_add_tile'),
      );
      _expectTileIconAndActionCenteredWithReadableText(
        tester,
        title: find.descendant(of: quickAddTile, matching: find.text('通知快捷记录')),
        subtitle: find.descendant(
          of: quickAddTile,
          matching: find.textContaining('通知栏'),
        ),
        icon: find.descendant(
          of: quickAddTile,
          matching: find.byIcon(Icons.add_alert_outlined),
        ),
        action: find.byKey(const ValueKey('notification_quick_add_switch')),
      );
      final todayProgressTile = find.byKey(
        const ValueKey('notification_today_progress_tile'),
      );
      _expectTileIconAndActionCenteredWithReadableText(
        tester,
        title: find.descendant(
          of: todayProgressTile,
          matching: find.text('今日任务进展'),
        ),
        subtitle: find.descendant(
          of: todayProgressTile,
          matching: find.textContaining('今日'),
        ),
        icon: find.descendant(
          of: todayProgressTile,
          matching: find.byIcon(Icons.today_outlined),
        ),
        action: find.byKey(
          const ValueKey('notification_today_progress_switch'),
        ),
      );
    }

    await tester.scrollUntilVisible(
      find.text('每日效率复盘'),
      1200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('每日效率复盘'));
    await tester.pumpAndSettle();
    final dailyReportTimeTile = find.ancestor(
      of: find.text('推送时间'),
      matching: find.byType(AppSettingsTile),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: dailyReportTimeTile,
        matching: find.text('推送时间'),
      ),
      subtitle: find.descendant(
        of: dailyReportTimeTile,
        matching: find.text('到点推送今天报告动态摘要'),
      ),
      icon: find.descendant(
        of: dailyReportTimeTile,
        matching: find.byIcon(Icons.schedule),
      ),
      action: find.byKey(const ValueKey('report_reminder_time_button_daily')),
      stacked: true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('每日提醒 320px 默认字号下四种提醒方式保持一行', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => NotificationService()),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ],
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('daily_reminder_kind_selector_row')),
      1200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();

    final buttons = [
      find.byKey(const ValueKey('daily_reminder_kind_push')),
      find.byKey(const ValueKey('daily_reminder_kind_popup')),
      find.byKey(const ValueKey('daily_reminder_kind_alarm')),
      find.byKey(const ValueKey('daily_reminder_kind_off')),
    ];
    for (final button in buttons) {
      expect(button, findsOneWidget);
    }

    final rects = buttons.map(tester.getRect).toList(growable: false);
    final centers = rects.map((rect) => rect.center.dy).toList(growable: false);
    final minCenter = centers.reduce((a, b) => a < b ? a : b);
    final maxCenter = centers.reduce((a, b) => a > b ? a : b);
    expect(maxCenter - minCenter, lessThan(6));
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left, greaterThan(rects[i - 1].left));
    }
    expect(rects.last.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('通知设置 320px 下展开头部图标和开关垂直居中', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => NotificationService()),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ],
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await tester.pump();

    final firstReminderHeader = find.byKey(
      const ValueKey('daily_reminder_slot_0_header'),
    );
    await tester.scrollUntilVisible(
      firstReminderHeader,
      1200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    _expectExpansionHeaderAligned(
      tester,
      header: firstReminderHeader,
      icon: find.byKey(const ValueKey('daily_reminder_slot_0_header_icon')),
      title: find.byKey(const ValueKey('daily_reminder_slot_0_header_title')),
      subtitle: find.byKey(
        const ValueKey('daily_reminder_slot_0_header_subtitle'),
      ),
      action: find.byKey(
        const ValueKey('daily_reminder_slot_0_enabled_switch'),
      ),
    );

    final dailyReportHeader = find.byKey(
      const ValueKey('report_reminder_daily_header'),
    );
    await tester.scrollUntilVisible(
      dailyReportHeader,
      1200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    _expectExpansionHeaderAligned(
      tester,
      header: dailyReportHeader,
      icon: find.byKey(const ValueKey('report_reminder_daily_header_icon')),
      title: find.byKey(const ValueKey('report_reminder_daily_header_title')),
      subtitle: find.byKey(
        const ValueKey('report_reminder_daily_header_subtitle'),
      ),
      action: find.byKey(
        const ValueKey('report_reminder_daily_enabled_switch'),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('提醒注册状态 320px 下可以打开独立页面', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => NotificationService()),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ],
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('notification_registered_reminders_view_button'),
      ),
      1200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        const ValueKey('notification_registered_reminders_view_button'),
      ),
    );
    await tester.pumpAndSettle();
    // 后台系统队列解析驱动到完成，避免遗留计时器影响断言。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    expect(find.byType(RegisteredRemindersScreen), findsOneWidget);
    expect(find.text('提醒注册状态'), findsAtLeastNWidgets(1));
    // 默认聚焦待触发或待确认项；空表说明当前没有可关注的待处理提醒。
    expect(find.text('暂无待触发/待确认的提醒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已注册提醒独立页默认展示待处理项并支持分页和状态过滤', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    addTearDown(service.dispose);
    final registry = InMemoryReminderScheduleRegistry();
    final activeIds = <int>{};
    for (var i = 1; i <= 21; i++) {
      final id = 9100 + i;
      activeIds.add(id);
      final number = i.toString().padLeft(2, '0');
      await registry.replaceObject(
        'todo',
        'todo-$number',
        {id},
        display: ReminderScheduleDisplayInfo(
          title: '客户回访 $number',
          subtitle: '待办 · 一次提醒 · 普通通知 · 明天 09:00',
          kinds: const <ReminderKind>{ReminderKind.push},
        ),
      );
    }
    activeIds.add(9901);
    await registry.replaceObject(
      'todo',
      'todo-partial',
      {9901, 9902},
      display: const ReminderScheduleDisplayInfo(
        title: '复查材料',
        subtitle: '待办 · 两次提醒 · 普通通知 · 明天 10:00、18:00',
        kinds: <ReminderKind>{ReminderKind.push},
      ),
    );
    await registry.replaceObject(
      'habit',
      'drink-water',
      {9801},
      display: const ReminderScheduleDisplayInfo(
        title: '喝水',
        subtitle: '习惯 · 重复提醒 · 闹钟提醒 · 每天 21:00',
        kinds: <ReminderKind>{ReminderKind.alarm},
      ),
    );
    activeIds.add(9701);
    await registry.replaceObject(
      'todo',
      'popup-mixed',
      {9701, 9702},
      display: const ReminderScheduleDisplayInfo(
        title: '前台弹窗确认',
        subtitle: '待办 · 两次提醒 · 自定义通道 · 明天 08:00、20:00',
        kinds: <ReminderKind>{ReminderKind.popup},
      ),
    );
    await registry.replaceObject(
      'todo',
      'email-mixed',
      {9601},
      display: const ReminderScheduleDisplayInfo(
        title: '邮件确认',
        subtitle: '待办 · 一次提醒 · 邮箱发送 · 明天 11:00',
        kinds: <ReminderKind>{ReminderKind.email},
      ),
    );
    final scheduler = ReminderScheduler(service, registry: registry);

    await tester.pumpWidget(
      Provider<ReminderScheduler?>.value(
        value: scheduler,
        child: MaterialApp(
          home: RegisteredRemindersScreen(
            pendingQueueLoader: () async => activeIds,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> revealReminderText(String text) async {
      final target = find.text(text);
      if (target.evaluate().isNotEmpty) return;
      final registeredScrollable = find.byType(Scrollable).last;
      if (registeredScrollable.evaluate().isEmpty) return;
      await tester.scrollUntilVisible(
        target,
        80,
        scrollable: registeredScrollable,
      );
    }

    expect(find.byType(RegisteredRemindersScreen), findsOneWidget);
    expect(find.text('全部 · 25'), findsOneWidget);
    expect(find.text('待触发/待确认 · 24'), findsOneWidget);
    expect(find.text('系统待触发 · 21'), findsOneWidget);
    expect(find.text('部分待触发 · 1'), findsOneWidget);
    expect(find.text('需重新保存 · 1'), findsOneWidget);
    expect(find.text('待确认 · 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('registered_reminders_queue_banner')),
      findsOneWidget,
    );
    expect(find.textContaining('1 条提醒在系统队列中查不到，1 条只确认到一部分'), findsOneWidget);
    await revealReminderText('提醒事项：客户回访 01');
    expect(find.text('提醒事项：客户回访 01'), findsOneWidget);
    expect(find.text('简述：待办 · 一次提醒 · 普通通知 · 明天 09:00'), findsWidgets);
    expect(find.text('已登记 1 条提醒规则 · 点开查看判断和处理建议'), findsWidgets);
    expect(find.text('每页 20 条 · 1-20 / 24 · 第 1/2 页'), findsOneWidget);
    expect(find.textContaining('todo-01'), findsNothing);
    expect(find.textContaining('9101'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('registered_reminders_next')));
    await tester.pumpAndSettle();

    await revealReminderText('提醒事项：客户回访 21');
    expect(find.text('提醒事项：客户回访 21'), findsOneWidget);
    expect(find.text('提醒事项：喝水'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('全部 · 25'),
      -240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部 · 25'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('registered_reminders_next')));
    await tester.pumpAndSettle();

    await revealReminderText('提醒事项：客户回访 21');
    await revealReminderText('提醒事项：喝水');
    expect(find.text('提醒事项：喝水'), findsOneWidget);
    expect(find.text('每页 20 条 · 21-25 / 25 · 第 2/2 页'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('部分待触发 · 1'),
      -240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('部分待触发 · 1'));
    await tester.pumpAndSettle();

    await revealReminderText('提醒事项：复查材料');
    expect(find.text('提醒事项：复查材料'), findsOneWidget);
    expect(find.text('部分待触发'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('需重新保存 · 1'),
      -240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('需重新保存 · 1'));
    await tester.pumpAndSettle();

    await revealReminderText('提醒事项：喝水');
    expect(find.text('提醒事项：喝水'), findsOneWidget);
    expect(find.text('简述：习惯 · 重复提醒 · 闹钟提醒 · 每天 21:00'), findsOneWidget);
    expect(find.text('需重新保存'), findsOneWidget);

    await tester.tap(find.text('提醒事项：喝水'));
    await tester.pumpAndSettle();

    expect(find.text('打开事项并重新保存'), findsOneWidget);
    expect(find.textContaining('调整到未来后重新保存'), findsOneWidget);
    Navigator.of(tester.element(find.text('打开事项并重新保存'))).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('待确认 · 2'),
      -240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('待确认 · 2'));
    await tester.pumpAndSettle();

    await revealReminderText('提醒事项：前台弹窗确认');
    expect(find.text('提醒事项：前台弹窗确认'), findsOneWidget);
    expect(find.text('提醒事项：邮件确认'), findsOneWidget);
    expect(find.text('待确认'), findsWidgets);
    expect(find.text('简述：待办 · 两次提醒 · 自定义通道 · 明天 08:00、20:00'), findsOneWidget);

    await tester.tap(find.text('提醒事项：前台弹窗确认'));
    await tester.pumpAndSettle();

    expect(find.text('简述'), findsOneWidget);
    expect(find.text('待办 · 两次提醒 · 自定义通道 · 明天 08:00、20:00'), findsWidgets);
    expect(find.text('当前判断'), findsOneWidget);
    expect(find.text('处理建议'), findsOneWidget);
    expect(find.text('技术详情'), findsOneWidget);
    expect(find.text('来源对象'), findsNothing);
    expect(find.text('todo:popup-mixed'), findsNothing);
    expect(find.text('登记编号'), findsNothing);
    expect(find.text('系统命中'), findsNothing);
    expect(find.text('未命中编号'), findsNothing);
    expect(find.text('待确认'), findsWidgets);
    expect(find.text('弹出框'), findsOneWidget);

    await tester.tap(find.text('技术详情'));
    await tester.pumpAndSettle();

    expect(find.text('来源对象'), findsOneWidget);
    expect(find.text('todo:popup-mixed'), findsOneWidget);
    expect(find.text('登记编号'), findsOneWidget);
    expect(find.text('系统命中'), findsOneWidget);
    expect(find.text('未命中编号'), findsOneWidget);
    expect(find.text('不适用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已注册提醒系统队列读取失败时显示待确认而不是需重新保存', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    addTearDown(service.dispose);
    final registry = InMemoryReminderScheduleRegistry();
    await registry.replaceObject(
      'todo',
      'pending-read-failed',
      {9301},
      display: const ReminderScheduleDisplayInfo(
        title: '队列读取失败测试',
        subtitle: '待办 · 一次提醒 · 普通通知 · 明天 09:00',
        kinds: <ReminderKind>{ReminderKind.push},
      ),
    );
    final scheduler = ReminderScheduler(service, registry: registry);

    await tester.pumpWidget(
      Provider<ReminderScheduler?>.value(
        value: scheduler,
        child: MaterialApp(
          home: RegisteredRemindersScreen(
            pendingQueueLoader: () async => throw StateError('pending failed'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部 · 1'), findsOneWidget);
    expect(find.text('待触发/待确认 · 1'), findsOneWidget);
    expect(find.text('系统待触发 · 0'), findsOneWidget);
    expect(find.text('需重新保存 · 0'), findsOneWidget);
    expect(find.text('待确认 · 1'), findsOneWidget);
    expect(find.text('提醒事项：队列读取失败测试'), findsOneWidget);
    expect(find.text('需重新保存'), findsNothing);
    expect(
      find.byKey(const ValueKey('registered_reminders_queue_banner')),
      findsOneWidget,
    );
    expect(find.textContaining('系统待触发队列读取失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('提醒事项：队列读取失败测试'));
    await tester.pumpAndSettle();

    expect(find.text('系统待触发列表读取失败'), findsOneWidget);
    expect(find.text('普通通知'), findsOneWidget);
    expect(find.text('待确认'), findsWidgets);
    expect(find.text('不适用'), findsNothing);

    await tester.tap(find.text('技术详情'));
    await tester.pumpAndSettle();

    expect(find.text('不适用'), findsOneWidget);
    expect(find.text('弹出框'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已注册提醒详情在系统队列解析完成后刷新当前判断', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    addTearDown(service.dispose);
    final registry = InMemoryReminderScheduleRegistry();
    await registry.replaceObject(
      'todo',
      'detail-refresh',
      {9301},
      display: const ReminderScheduleDisplayInfo(
        title: '详情刷新测试',
        subtitle: '待办 · 一次提醒 · 普通通知 · 明天 09:00',
        kinds: <ReminderKind>{ReminderKind.push},
      ),
    );
    final scheduler = ReminderScheduler(service, registry: registry);
    final pendingQueue = Completer<Set<int>>();

    await tester.pumpWidget(
      Provider<ReminderScheduler?>.value(
        value: scheduler,
        child: MaterialApp(
          home: RegisteredRemindersScreen(
            pendingQueueLoader: () => pendingQueue.future,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('提醒事项：详情刷新测试'), findsOneWidget);
    expect(find.text('待确认'), findsWidgets);

    await tester.tap(find.text('提醒事项：详情刷新测试'));
    await tester.pumpAndSettle();

    expect(find.text('系统待触发列表'), findsNothing);
    expect(find.text('正在读取系统待触发列表'), findsOneWidget);
    expect(find.text('当前判断'), findsOneWidget);
    expect(find.text('待确认'), findsWidgets);

    pendingQueue.complete(<int>{9301});
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('系统待触发列表已读取'), findsOneWidget);
    expect(find.text('系统待触发'), findsWidgets);

    await tester.tap(find.text('技术详情'));
    await tester.pumpAndSettle();

    expect(find.text('9301'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已注册提醒忽略旧刷新返回的系统队列结果', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    addTearDown(service.dispose);
    final registry = InMemoryReminderScheduleRegistry();
    await registry.replaceObject(
      'todo',
      'queue-race',
      {9401},
      display: const ReminderScheduleDisplayInfo(
        title: '队列乱序测试',
        subtitle: '待办 · 一次提醒 · 普通通知 · 明天 09:00',
        kinds: <ReminderKind>{ReminderKind.push},
      ),
    );
    final scheduler = ReminderScheduler(service, registry: registry);
    final queueLoads = <Completer<Set<int>>>[];

    await tester.pumpWidget(
      Provider<ReminderScheduler?>.value(
        value: scheduler,
        child: MaterialApp(
          home: RegisteredRemindersScreen(
            pendingQueueLoader: () {
              final completer = Completer<Set<int>>();
              queueLoads.add(completer);
              return completer.future;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(queueLoads.length, 1);
    expect(find.text('提醒事项：队列乱序测试'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('registered_reminders_refresh')),
    );
    await tester.pump();
    await tester.pump();

    expect(queueLoads.length, 2);

    queueLoads[1].complete(<int>{9401});
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('系统待触发 · 1'), findsOneWidget);
    expect(find.text('需重新保存 · 0'), findsOneWidget);
    expect(find.text('提醒事项：队列乱序测试'), findsOneWidget);

    queueLoads[0].complete(<int>{});
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('系统待触发 · 1'), findsOneWidget);
    expect(find.text('需重新保存 · 0'), findsOneWidget);
    expect(find.text('提醒事项：队列乱序测试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已注册提醒按有效编号组判定重复闹钟和混合通道状态', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    addTearDown(service.dispose);
    final registry = InMemoryReminderScheduleRegistry();
    await registry.replaceObject(
      'habit',
      'weekly-alarm',
      {9800, 9801, 9802},
      display: const ReminderScheduleDisplayInfo(
        title: '喝水',
        subtitle: '习惯 · 重复提醒 · 闹钟提醒 · 每天 21:00',
        kinds: <ReminderKind>{ReminderKind.alarm},
        acceptedIdSets: <Set<int>>[
          <int>{9800},
          <int>{9801, 9802},
        ],
      ),
    );
    await registry.replaceObject(
      'todo',
      'popup-push-mixed',
      {9700},
      display: const ReminderScheduleDisplayInfo(
        title: '前台加系统兜底',
        subtitle: '待办 · 弹出提醒 + 普通通知 · 明天 09:00',
        kinds: <ReminderKind>{ReminderKind.popup, ReminderKind.push},
        acceptedIdSets: <Set<int>>[
          <int>{9700},
        ],
      ),
    );
    await registry.replaceObject(
      'todo',
      'combined-system-rules',
      {9501, 9502},
      display: const ReminderScheduleDisplayInfo(
        title: '双规则系统提醒',
        subtitle: '待办 · 两条规则 · 普通通知 · 明天 09:00、18:00',
        kinds: <ReminderKind>{ReminderKind.push},
        acceptedIdSets: <Set<int>>[
          <int>{9501, 9502},
        ],
      ),
    );
    final scheduler = ReminderScheduler(service, registry: registry);

    await tester.pumpWidget(
      Provider<ReminderScheduler?>.value(
        value: scheduler,
        child: MaterialApp(
          home: RegisteredRemindersScreen(
            pendingQueueLoader: () async => <int>{9800, 9700, 9501},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部 · 3'), findsOneWidget);
    expect(find.text('待触发/待确认 · 3'), findsOneWidget);
    expect(find.text('系统待触发 · 2'), findsOneWidget);
    expect(find.text('部分待触发 · 1'), findsOneWidget);
    expect(find.text('需重新保存 · 0'), findsOneWidget);
    expect(find.text('待确认 · 0'), findsOneWidget);
    expect(find.text('每页 20 条 · 1-3 / 3 · 第 1/1 页'), findsNothing);

    await tester.tap(find.text('部分待触发 · 1'));
    await tester.pumpAndSettle();

    expect(find.text('提醒事项：双规则系统提醒'), findsOneWidget);
    expect(find.text('部分待触发'), findsOneWidget);

    await tester.tap(find.text('提醒事项：双规则系统提醒'));
    await tester.pumpAndSettle();

    expect(find.text('判定编号'), findsNothing);

    await tester.tap(find.text('技术详情'));
    await tester.pumpAndSettle();

    expect(find.text('判定编号'), findsOneWidget);
    expect(find.text('9501+9502'), findsOneWidget);
    expect(find.text('系统命中'), findsOneWidget);
    expect(find.text('9501'), findsWidgets);
    expect(find.text('未命中编号'), findsOneWidget);
    expect(find.text('9502'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('系统待触发 · 2'));
    await tester.pumpAndSettle();

    expect(find.text('提醒事项：喝水'), findsOneWidget);
    expect(find.text('提醒事项：前台加系统兜底'), findsOneWidget);
    expect(find.text('系统待触发'), findsWidgets);

    await tester.tap(find.text('提醒事项：喝水'));
    await tester.pumpAndSettle();

    expect(find.text('未命中编号'), findsNothing);
    expect(find.text('9801'), findsNothing);

    await tester.tap(find.text('技术详情'));
    await tester.pumpAndSettle();

    expect(find.text('判定编号'), findsOneWidget);
    expect(find.textContaining('9800'), findsWidgets);
    expect(find.textContaining('9801+9802'), findsOneWidget);
    expect(find.text('兼容编号未命中，不影响当前判断：9801、9802'), findsOneWidget);
    expect(find.text('闹钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已注册提醒页在详情弹窗打开时退出不会双重释放 Notifier 且生命周期安全', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    addTearDown(service.dispose);
    final registry = InMemoryReminderScheduleRegistry();
    await registry.replaceObject(
      'todo',
      'lifecycle-test-1',
      {9901},
      display: const ReminderScheduleDisplayInfo(
        title: '生命周期测试',
        subtitle: '待办 · 一次提醒 · 普通通知 · 明天 09:00',
        kinds: <ReminderKind>{ReminderKind.push},
      ),
    );
    final scheduler = ReminderScheduler(service, registry: registry);

    await tester.pumpWidget(
      Provider<ReminderScheduler?>.value(
        value: scheduler,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RegisteredRemindersScreen(
                        pendingQueueLoader: () async => <int>{9901},
                      ),
                    ),
                  );
                },
                child: const Text('进入已注册提醒'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('进入已注册提醒'));
    await tester.pumpAndSettle();

    expect(find.text('提醒事项：生命周期测试'), findsOneWidget);

    await tester.tap(find.text('提醒事项：生命周期测试'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('registered_reminder_detail_close')),
      findsOneWidget,
    );

    final pageContext = tester.element(find.byType(RegisteredRemindersScreen));
    Navigator.of(pageContext).popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();

    expect(find.text('进入已注册提醒'), findsOneWidget);
    expect(find.byType(RegisteredRemindersScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已注册提醒详情弹窗可通过关闭按钮正常关闭', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    addTearDown(service.dispose);
    final registry = InMemoryReminderScheduleRegistry();
    await registry.replaceObject(
      'todo',
      'close-test-1',
      {9902},
      display: const ReminderScheduleDisplayInfo(
        title: '关闭测试',
        subtitle: '待办 · 一次提醒 · 普通通知 · 明天 09:00',
        kinds: <ReminderKind>{ReminderKind.push},
      ),
    );
    final scheduler = ReminderScheduler(service, registry: registry);

    await tester.pumpWidget(
      Provider<ReminderScheduler?>.value(
        value: scheduler,
        child: const MaterialApp(home: RegisteredRemindersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('提醒事项：关闭测试'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('registered_reminder_detail_close')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('registered_reminder_detail_close')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('registered_reminder_detail_close')),
      findsNothing,
    );
    expect(find.text('提醒事项：关闭测试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已注册提醒详情点击打开事项能安全关闭并触发路由跳转且返回刷新', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    addTearDown(service.dispose);
    final registry = InMemoryReminderScheduleRegistry();
    await registry.replaceObject(
      'todo',
      'source-nav-test',
      {9903},
      display: const ReminderScheduleDisplayInfo(
        title: '打开事项测试',
        subtitle: '待办 · 一次提醒 · 普通通知 · 明天 09:00',
        kinds: <ReminderKind>{ReminderKind.push},
      ),
    );
    final scheduler = ReminderScheduler(service, registry: registry);

    var queueLoads = 0;
    final todo = TodoItem(id: 'source-nav-test', title: '打开事项测试待办');
    final todoProvider = TodoProvider();
    await todoProvider.addTodo(todo);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReminderScheduler?>.value(value: scheduler),
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          home: RegisteredRemindersScreen(
            pendingQueueLoader: () async {
              queueLoads++;
              return <int>{9903};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(queueLoads, 1);

    await tester.tap(find.text('提醒事项：打开事项测试'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('registered_reminder_open_object')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('registered_reminder_open_object')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TodoDetailScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(TodoDetailScreen))).pop();
    await tester.pumpAndSettle();

    expect(queueLoads, 2);
    expect(find.text('提醒事项：打开事项测试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已注册提醒详情在条目被移除时展示移除提示并可关闭', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    addTearDown(service.dispose);
    final registry = InMemoryReminderScheduleRegistry();
    await registry.replaceObject(
      'todo',
      'item-remove-test',
      {9904},
      display: const ReminderScheduleDisplayInfo(
        title: '即将删除的提醒',
        subtitle: '待办 · 一次提醒 · 普通通知 · 明天 09:00',
        kinds: <ReminderKind>{ReminderKind.push},
      ),
    );
    final scheduler = ReminderScheduler(service, registry: registry);

    await tester.pumpWidget(
      Provider<ReminderScheduler?>.value(
        value: scheduler,
        child: const MaterialApp(home: RegisteredRemindersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('提醒事项：即将删除的提醒'));
    await tester.pumpAndSettle();

    expect(find.text('当前判断'), findsOneWidget);

    await registry.removeObject('todo', 'item-remove-test');
    await tester.tap(
      find.byKey(const ValueKey('registered_reminder_detail_refresh')),
    );
    await tester.pumpAndSettle();

    expect(find.text('这条提醒已不在当前注册表中，请返回后刷新列表。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('registered_reminder_removed_close')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('registered_reminder_removed_close')),
    );
    await tester.pumpAndSettle();

    expect(find.text('这条提醒已不在当前注册表中，请返回后刷新列表。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认筛选在缺失项剔除后正确更新分页并可在空态一键跳转需重新保存', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    addTearDown(service.dispose);
    final registry = InMemoryReminderScheduleRegistry();
    for (var i = 1; i <= 25; i++) {
      final id = 9910 + i;
      await registry.replaceObject(
        'todo',
        'missing-item-$i',
        {id},
        display: ReminderScheduleDisplayInfo(
          title: '缺席待办 $i',
          subtitle: '待办 · 一次提醒 · 普通通知 · 明天 09:00',
          kinds: const <ReminderKind>{ReminderKind.push},
        ),
      );
    }
    final scheduler = ReminderScheduler(service, registry: registry);
    final queueCompleter = Completer<Set<int>>();

    await tester.pumpWidget(
      Provider<ReminderScheduler?>.value(
        value: scheduler,
        child: MaterialApp(
          home: RegisteredRemindersScreen(
            pendingQueueLoader: () => queueCompleter.future,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('每页 20 条 · 1-20 / 25 · 第 1/2 页'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('registered_reminders_next')));
    await tester.pumpAndSettle();
    expect(find.text('每页 20 条 · 21-25 / 25 · 第 2/2 页'), findsOneWidget);

    queueCompleter.complete(<int>{});
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('当前没有待触发/待确认的提醒；另有 25 条需重新保存'), findsOneWidget);
    expect(find.text('查看需重新保存'), findsOneWidget);

    await tester.tap(find.text('查看需重新保存'));
    await tester.pumpAndSettle();

    expect(find.text('需重新保存 · 25'), findsOneWidget);
    expect(find.text('每页 20 条 · 1-20 / 25 · 第 1/2 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account invalidation clears list and detached detail before cleanup settles',
    (tester) async {
      final service = NotificationService();
      final auth = _ReminderBoundaryAuth();
      final registry = InMemoryReminderScheduleRegistry();
      await _registerBoundaryRow(registry, '账号A提醒');
      final scheduler = _BoundarySnapshotScheduler(service, registry: registry);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ReminderScheduler?>.value(value: scheduler),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: MaterialApp(
            home: RegisteredRemindersScreen(
              pendingQueueLoader: () async => <int>{9950},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('提醒事项：账号A提醒'));
      await tester.pumpAndSettle();
      expect(find.text('账号A提醒'), findsOneWidget);
      final loadsBefore = scheduler.loads;

      auth.beginCleanup();
      await tester.pumpAndSettle();
      expect(find.textContaining('账号A提醒'), findsNothing);
      expect(
        find.byKey(const ValueKey('registered_reminder_removed_close')),
        findsOneWidget,
      );
      expect(scheduler.loads, loadsBefore);

      await _registerBoundaryRow(registry, '账号B提醒');
      auth.settle(const AuthState(userId: 'B', token: 'token-B'));
      await tester.pumpAndSettle();
      expect(find.text('提醒事项：账号B提醒'), findsOneWidget);
      expect(find.text('账号B提醒'), findsNothing, reason: 'A详情不能绑定B的同名对象');
      expect(
        find.byKey(const ValueKey('registered_reminder_removed_close')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('registered_reminder_removed_close')),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      service.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'snapshot failure exposes retry and optional auth fixtures recover',
    (tester) async {
      final service = NotificationService();
      final registry = InMemoryReminderScheduleRegistry();
      await _registerBoundaryRow(registry, '重试提醒');
      final scheduler = _BoundarySnapshotScheduler(service, registry: registry)
        ..failNext = true;
      await tester.pumpWidget(
        Provider<ReminderScheduler?>.value(
          value: scheduler,
          child: MaterialApp(
            home: RegisteredRemindersScreen(
              pendingQueueLoader: () async => <int>{9950},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('读取提醒注册状态失败，请重试。'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('提醒事项：重试提醒'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );

  testWidgets(
    'old snapshot cannot return after same-account cleanup recovery',
    (tester) async {
      final service = NotificationService();
      final auth = _ReminderBoundaryAuth();
      final registry = InMemoryReminderScheduleRegistry();
      await _registerBoundaryRow(registry, '恢复前提醒');
      final oldEntries = await ReminderScheduler(
        service,
        registry: registry,
      ).registeredRemindersSnapshot();
      final firstLoad = Completer<List<ReminderScheduleSnapshotEntry>>();
      final scheduler = _BoundarySnapshotScheduler(service, registry: registry)
        ..firstLoad = firstLoad;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ReminderScheduler?>.value(value: scheduler),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: MaterialApp(
            home: RegisteredRemindersScreen(
              pendingQueueLoader: () async => <int>{9950},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(scheduler.loads, 1);
      auth.beginCleanup();
      await _registerBoundaryRow(registry, '恢复后提醒');
      auth.settle(auth.state);
      await tester.pumpAndSettle();
      expect(find.text('提醒事项：恢复后提醒'), findsOneWidget);
      firstLoad.complete(oldEntries);
      await tester.pumpAndSettle();
      expect(find.textContaining('恢复前提醒'), findsNothing);
      expect(find.text('提醒事项：恢复后提醒'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      service.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same-account transition without cleanup resumes a pending snapshot',
    (tester) async {
      final service = NotificationService();
      final auth = _ReminderBoundaryAuth();
      final registry = InMemoryReminderScheduleRegistry();
      await _registerBoundaryRow(registry, '切换前提醒');
      final oldEntries = await ReminderScheduler(
        service,
        registry: registry,
      ).registeredRemindersSnapshot();
      final firstLoad = Completer<List<ReminderScheduleSnapshotEntry>>();
      final scheduler = _BoundarySnapshotScheduler(service, registry: registry)
        ..firstLoad = firstLoad;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ReminderScheduler?>.value(value: scheduler),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: MaterialApp(
            home: RegisteredRemindersScreen(
              pendingQueueLoader: () async => <int>{9950},
            ),
          ),
        ),
      );
      await tester.pump();
      final generation = AccountLocalDataCleaner.accountDataGeneration;
      auth.beginTransitionWithoutCleanup();
      firstLoad.complete(oldEntries);
      await tester.pumpAndSettle();
      expect(find.textContaining('切换前提醒'), findsNothing);
      await _registerBoundaryRow(registry, '恢复后的提醒');
      auth.settle(auth.state);
      await tester.pumpAndSettle();
      expect(scheduler.loads, 2);
      expect(AccountLocalDataCleaner.accountDataGeneration, generation);
      expect(find.text('提醒事项：恢复后的提醒'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      service.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _firstExisting(WidgetTester tester, List<Finder> candidates) {
  for (final candidate in candidates) {
    if (candidate.evaluate().isNotEmpty) return candidate;
  }
  throw TestFailure('No finder matched any expected widget.');
}

void _expectTileIconAndActionCenteredWithReadableText(
  WidgetTester tester, {
  required Finder title,
  required Finder subtitle,
  required Finder icon,
  required Finder action,
  bool stacked = false,
}) {
  final titleRect = tester.getRect(title);
  final subtitleRect = tester.getRect(subtitle);
  final iconRect = tester.getRect(icon);
  final actionRect = tester.getRect(action);
  final textCenterDy = _textBlockCenterDy(titleRect, subtitleRect);

  expect((iconRect.center.dy - textCenterDy).abs(), lessThan(5));
  expect(subtitleRect.top, greaterThan(titleRect.bottom));
  expect(actionRect.left, greaterThan(titleRect.left));
  if (stacked) {
    final tile = find.ancestor(
      of: title,
      matching: find.byType(AppSettingsTile),
    );
    final tileRect = tester.getRect(tile);
    expect(actionRect.top, greaterThan(subtitleRect.bottom));
    expect(actionRect.right, lessThanOrEqualTo(tileRect.right));
    expect(actionRect.bottom, lessThanOrEqualTo(tileRect.bottom));
    for (final text in [title, subtitle]) {
      final rect = tester.getRect(text);
      expect(tileRect.inflate(0.1).contains(rect.topLeft), isTrue);
      expect(tileRect.inflate(0.1).contains(rect.bottomRight), isTrue);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: text, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.textSize.width, lessThanOrEqualTo(rect.width + 0.1));
      expect(paragraph.textSize.height, lessThanOrEqualTo(rect.height + 0.1));
    }
  } else {
    expect((actionRect.center.dy - textCenterDy).abs(), lessThan(5));
  }
}

void _expectExpansionHeaderAligned(
  WidgetTester tester, {
  required Finder header,
  required Finder icon,
  required Finder title,
  required Finder subtitle,
  required Finder action,
}) {
  final headerRect = tester.getRect(header);
  final iconRect = tester.getRect(icon);
  final titleRect = tester.getRect(title);
  final subtitleRect = tester.getRect(subtitle);
  final actionRect = tester.getRect(action);
  final textCenterDy = _textBlockCenterDy(titleRect, subtitleRect);

  expect(headerRect.height, greaterThan(iconRect.height));
  expect((iconRect.center.dy - textCenterDy).abs(), lessThan(4));
  expect((actionRect.center.dy - textCenterDy).abs(), lessThan(5));
  expect(subtitleRect.top, greaterThan(titleRect.bottom));
  expect(actionRect.left, greaterThan(titleRect.left));
}

double _textBlockCenterDy(Rect titleRect, Rect subtitleRect) {
  final top = titleRect.top < subtitleRect.top
      ? titleRect.top
      : subtitleRect.top;
  final bottom = titleRect.bottom > subtitleRect.bottom
      ? titleRect.bottom
      : subtitleRect.bottom;
  return (top + bottom) / 2;
}

class _ReminderBoundaryAuth extends AuthProvider {
  AuthState _fixtureState = const AuthState(userId: 'A', token: 'token-A');
  bool _transitioning = false;
  @override
  AuthState get state => _fixtureState;
  @override
  bool get isAccountTransitionInProgress => _transitioning;
  void beginCleanup() {
    _transitioning = true;
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
  }

  void beginTransitionWithoutCleanup() {
    _transitioning = true;
    notifyListeners();
  }

  void settle(AuthState state) {
    _fixtureState = state;
    _transitioning = false;
    notifyListeners();
  }
}

class _BoundarySnapshotScheduler extends ReminderScheduler {
  _BoundarySnapshotScheduler(super.notifications, {super.registry});
  int loads = 0;
  bool failNext = false;
  Completer<List<ReminderScheduleSnapshotEntry>>? firstLoad;
  @override
  Future<List<ReminderScheduleSnapshotEntry>> registeredRemindersSnapshot() {
    loads++;
    if (loads == 1 && firstLoad != null) return firstLoad!.future;
    if (failNext) {
      failNext = false;
      return Future.error(StateError('synthetic snapshot failure'));
    }
    return super.registeredRemindersSnapshot();
  }
}

Future<void> _registerBoundaryRow(
  InMemoryReminderScheduleRegistry registry,
  String title,
) => registry.replaceObject(
  'todo',
  'same-object-id',
  <int>{9950},
  display: ReminderScheduleDisplayInfo(
    title: title,
    subtitle: '待办提醒',
    kinds: const <ReminderKind>{ReminderKind.push},
  ),
);
