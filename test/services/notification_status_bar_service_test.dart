import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/notification_status_bar_service.dart';
import 'package:duoyi/services/notification_status_bar_sync_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('NotificationStatusBarPlan', () {
    setUp(() => I18n.setLocale(AppLocale.zh));

    test('关闭快捷添加和今日进展时取消常驻通知', () {
      final plan = buildNotificationStatusBarPlan(
        notificationQuickAdd: false,
        notificationTodayProgress: false,
        todayProgressBody: '今日还要完成 0 项',
      );

      expect(plan.shouldShow, isFalse);
      expect(plan.enableQuickActions, isFalse);
      expect(plan.title, isEmpty);
      expect(plan.body, isEmpty);
    });

    test('仅开启今日进展时展示摘要但不暴露快捷操作', () {
      final plan = buildNotificationStatusBarPlan(
        notificationQuickAdd: false,
        notificationTodayProgress: true,
        todayProgressBody: '今日还要完成 2 项\n日常 1 / 待办 2 / 目标 1',
      );

      expect(plan.shouldShow, isTrue);
      expect(plan.title, '今日任务进展');
      expect(plan.body, '今日还要完成 2 项\n日常 1 / 待办 2 / 目标 1');
      expect(plan.enableQuickActions, isFalse);
    });

    test('今日进展和快捷添加同时开启时追加快捷提示', () {
      final plan = buildNotificationStatusBarPlan(
        notificationQuickAdd: true,
        notificationTodayProgress: true,
        todayProgressBody: '今日还要完成 1 项\n日常 1 / 待办 1 / 目标 0',
      );

      expect(plan.shouldShow, isTrue);
      expect(plan.title, '今日任务进展');
      expect(plan.body, '今日还要完成 1 项\n日常 1 / 待办 1 / 目标 0\n下拉可快速添加待办');
      expect(plan.enableQuickActions, isTrue);
    });

    test('仅开启快捷添加时降级为快捷记录常驻通知', () {
      final plan = buildNotificationStatusBarPlan(
        notificationQuickAdd: true,
        notificationTodayProgress: false,
        todayProgressBody: '今日还要完成 9 项',
      );

      expect(plan.shouldShow, isTrue);
      expect(plan.title, '多仪快捷记录');
      expect(plan.body, '下拉通知栏添加待办，或一键开始专注');
      expect(plan.enableQuickActions, isTrue);
    });

    test('关闭今日进展不会把旧进展摘要留在通知栏', () {
      final previousProgress = buildNotificationStatusBarPlan(
        notificationQuickAdd: true,
        notificationTodayProgress: true,
        todayProgressBody: '今日还要完成 5 项\n日常 2 / 待办 5 / 目标 2',
      );
      final disabledProgress = buildNotificationStatusBarPlan(
        notificationQuickAdd: true,
        notificationTodayProgress: false,
        todayProgressBody: previousProgress.body,
      );

      expect(previousProgress.title, '今日任务进展');
      expect(disabledProgress.shouldShow, isTrue);
      expect(disabledProgress.title, '多仪快捷记录');
      expect(disabledProgress.body, '下拉通知栏添加待办，或一键开始专注');
      expect(disabledProgress.body, isNot(contains('今日还要完成')));
    });

    test('通知栏计划和进展摘要跟随英文语言', () {
      I18n.setLocale(AppLocale.en);
      final body = formatNotificationTodayProgressBody(
        remaining: 3,
        dailyCount: 1,
        todoCount: 3,
        goalCount: 4,
      );
      final plan = buildNotificationStatusBarPlan(
        notificationQuickAdd: true,
        notificationTodayProgress: true,
        todayProgressBody: body,
      );

      expect(body, '3 tasks left today\nDaily 1 / Tasks 3 / Goals 4');
      expect(plan.title, 'Today progress');
      expect(plan.body, '$body\nPull down to quickly add a task');
      expect(plan.enableQuickActions, isTrue);
    });

    test('通知设置页保留今日任务进展独立开关并同步常驻通知', () {
      final screen = File(
        'lib/screens/notification_history_screen.dart',
      ).readAsStringSync();
      final bridge = File(
        'lib/services/notification_status_bar_sync_bridge.dart',
      ).readAsStringSync();

      expect(screen, contains('preferences.notification_today_progress.title'));
      expect(screen, contains('PlatformInfo.isAndroid'));
      expect(
        screen,
        contains('preferences.notification_status_bar.unsupported'),
      );
      expect(screen, contains('value: prefs.notificationTodayProgress'));
      expect(screen, contains('quickAdd: false'));
      expect(screen, contains('setNotificationTodayProgress(value)'));
      expect(
        screen,
        contains('NotificationStatusBarSyncBridge.sync('),
        reason: '设置页保存后必须复用 main 层签名去重入口，避免自己 show 一次、监听器再 show 一次。',
      );
      expect(screen, contains('force: true'));
      expect(screen, contains('requestIfNeeded: requestIfNeeded'));
      expect(screen, contains('requestIfNeeded: value'));
      expect(
        bridge,
        contains('typedef NotificationStatusBarSync ='),
        reason: '桥接层必须传回底层同步结果，失败时设置页才能恢复旧开关。',
      );
      expect(bridge, contains('Future<bool> Function'));
      expect(bridge, contains('bool requestIfNeeded'));
      expect(
        bridge,
        contains(
          'return current(force: force, requestIfNeeded: requestIfNeeded);',
        ),
      );
      expect(
        bridge,
        isNot(contains('await current(force: force);\n    return true;')),
      );
    });

    test('状态栏同步桥透传 force 和底层成功状态', () async {
      final calls = <({bool force, bool requestIfNeeded})>[];
      addTearDown(() => NotificationStatusBarSyncBridge.attach(null));
      NotificationStatusBarSyncBridge.attach(({
        bool force = false,
        bool requestIfNeeded = false,
      }) async {
        calls.add((force: force, requestIfNeeded: requestIfNeeded));
        return force && requestIfNeeded;
      });

      expect(await NotificationStatusBarSyncBridge.sync(), isFalse);
      expect(await NotificationStatusBarSyncBridge.sync(force: true), isFalse);
      expect(
        await NotificationStatusBarSyncBridge.sync(
          force: true,
          requestIfNeeded: true,
        ),
        isTrue,
      );
      expect(calls, <({bool force, bool requestIfNeeded})>[
        (force: false, requestIfNeeded: false),
        (force: true, requestIfNeeded: false),
        (force: true, requestIfNeeded: true),
      ]);

      NotificationStatusBarSyncBridge.attach(null);
      expect(await NotificationStatusBarSyncBridge.sync(force: true), isFalse);
    });
  });
}
