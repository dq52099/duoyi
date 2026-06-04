import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'startup keeps heavy reload sync notification and widget work staggered',
    () {
      final main = File('lib/main.dart').readAsStringSync();

      expect(main, contains('Future<void> _runStartupIdleQueue('));
      expect(main, contains('Future<void> _runStartupStaggeredTask('));
      expect(main, contains('Future<void> _runSyncReloadTasksInBatches('));
      expect(main, contains('Future<void> ensureNotificationLaunchStartup()'));
      expect(main, contains('Future<void> ensureHomeWidgetLaunchStartup()'));
      expect(main, contains('await _yieldForNextFrame();'));
      expect(main, contains("'deferred local storage'"));
      expect(main, contains("'deferred platform services'"));
      expect(main, contains("'startup notification launch payloads'"));
      expect(main, contains("'startup deep links'"));
      expect(main, contains("'home widget initial launch'"));
      expect(main, contains("'server config refresh'"));
      expect(main, contains("'auth profile refresh'"));
      expect(main, contains("'notification quick add'"));
      expect(main, contains("'initial home widget push'"));
      expect(main, contains('initialDelay: const Duration(seconds: 8)'));
      expect(main, contains('gap: const Duration(seconds: 3)'));
      expect(
        main,
        contains('const Duration(milliseconds: 3200)'),
        reason: '首帧后的延迟本地加载不能和首屏渲染立即抢资源。',
      );
      expect(main, contains('delay: const Duration(milliseconds: 900)'));
      expect(main, contains('delay: const Duration(milliseconds: 1100)'));
      expect(main, contains('delay: const Duration(milliseconds: 1400)'));
      expect(main, contains('delay: const Duration(seconds: 6)'));
      expect(main, contains('delay: const Duration(seconds: 14)'));
      expect(main, contains('delay: const Duration(seconds: 9)'));
      expect(main, contains('Timer(const Duration(milliseconds: 2200)'));
      expect(main, contains('var homeWidgetPushInFlight = false'));
      expect(main, contains('homeWidgetPushQueued = true'));

      final background = File(
        'lib/widgets/brand_background.dart',
      ).readAsStringSync();
      expect(background, contains('LayoutBuilder('));
      expect(background, contains('MediaQuery.devicePixelRatioOf(context)'));
      expect(background, contains('cacheWidth: cacheWidth'));
      expect(background, contains('cacheHeight: cacheHeight'));

      final notificationSettings = File(
        'lib/screens/notification_history_screen.dart',
      ).readAsStringSync();
      expect(
        notificationSettings,
        contains("key: const ValueKey('notification_settings_scroll_view')"),
      );
      expect(notificationSettings, contains('CustomScrollView('));
      expect(notificationSettings, contains('SliverSafeArea('));
      expect(notificationSettings, contains('通知状态读取失败，请稍后重试或打开系统通知设置检查。'));
      expect(
        main,
        isNot(contains('_builtTabs.contains(tab) && tab == safeIndex')),
        reason: '已访问底部 tab 必须保留挂载，避免返回日历/习惯/专注时整页重建。',
      );
    },
  );
}
