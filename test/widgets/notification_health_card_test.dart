import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/platform_info.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/services/alarm_service.dart';
import 'package:duoyi/services/permission_health_service.dart';
import 'package:duoyi/widgets/notification_health_card.dart';

void main() {
  testWidgets('通知健康卡片显示摘要、检查项和动作按钮', (tester) async {
    var refreshCount = 0;
    var openSettingsCount = 0;
    var sendTestCount = 0;
    var sendStrongTestCount = 0;
    var clearCount = 0;

    final report = NotificationHealthReport(
      notificationGranted: true,
      exactAlarmGranted: true,
      fullScreenIntentGranted: true,
      channelIds: <String>{
        NotificationService.channelId,
        AlarmService.channelId,
      },
      androidDevice: const AndroidDeviceInfoLite(
        manufacturer: 'Xiaomi',
        brand: 'xiaomi',
        model: '2210132C',
        sdkInt: 34,
      ),
      isAndroid: true,
      isIOS: false,
      checkedAt: DateTime(2026, 5, 10, 10, 20),
      checks: const [
        PermissionHealthCheck(
          id: 'xiaomi_autostart_policy',
          title: 'HyperOS/MIUI 自启动',
          subtitle: '安全中心或应用管理中允许多仪自启动，避免重启后提醒不恢复',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.none,
          manual: true,
        ),
        PermissionHealthCheck(
          id: 'xiaomi_battery_policy',
          title: 'HyperOS/MIUI 后台与电池',
          subtitle: '把多仪设为后台无限制，关闭省电策略对闹钟和白噪音的限制',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.none,
          manual: true,
        ),
        PermissionHealthCheck(
          id: 'xiaomi_lock_screen_policy',
          title: 'HyperOS/MIUI 锁屏与横幅',
          subtitle: '通知管理中允许锁屏通知、横幅通知、悬浮通知、声音和振动',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.none,
          manual: true,
        ),
        PermissionHealthCheck(
          id: 'xiaomi_channel_sound_policy',
          title: 'HyperOS/MIUI 渠道声音',
          subtitle: '分别检查“多仪 · 通知提醒”和“多仪 · 强提醒”渠道，不要设为静音',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.none,
          manual: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotificationHealthCard(
              report: report,
              pendingCount: 3,
              lastTestAt: DateTime(2026, 5, 10, 9, 30),
              onRefresh: () => refreshCount++,
              onOpenSystemSettings: () => openSettingsCount++,
              onOpenNotificationChannelSettings: (_) => openSettingsCount++,
              onSendTest: () => sendTestCount++,
              onSendStrongTest: () => sendStrongTestCount++,
              onClearPending: () => clearCount++,
              onRequestNotificationPermission: () {},
              onRequestExactAlarmPermission: () {},
              onRequestFullScreenIntentPermission: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('通知健康检查'), findsOneWidget);
    expect(find.textContaining('HyperOS/MIUI'), findsWidgets);
    expect(find.text('HyperOS/MIUI 自启动'), findsOneWidget);
    expect(find.text('HyperOS/MIUI 后台与电池'), findsOneWidget);
    expect(find.text('HyperOS/MIUI 锁屏与横幅'), findsOneWidget);
    expect(find.text('HyperOS/MIUI 渠道声音'), findsOneWidget);
    expect(find.text('立即发送测试通知'), findsOneWidget);
    expect(find.text('测试强提醒铃声'), findsOneWidget);
    expect(find.text('30 秒后强提醒'), findsNothing);
    expect(find.text('疑难设置入口'), findsOneWidget);
    expect(find.textContaining('先按上方检查项逐项确认'), findsOneWidget);
    expect(find.text('3 条待触发'), findsOneWidget);
    expect(find.text('去设置'), findsNothing);

    await tester.tap(find.text('刷新'));
    await tester.pump();
    await tester.ensureVisible(find.text('疑难设置入口'));
    await tester.tap(find.text('疑难设置入口'));
    await tester.pump();
    await tester.ensureVisible(find.text('立即发送测试通知'));
    await tester.tap(find.text('立即发送测试通知'));
    await tester.pump();
    await tester.ensureVisible(find.text('测试强提醒铃声'));
    await tester.tap(find.text('测试强提醒铃声'));
    await tester.pump();
    await tester.ensureVisible(find.text('全部取消'));
    await tester.tap(find.text('全部取消'));
    await tester.pump();

    expect(refreshCount, 1);
    expect(openSettingsCount, 1);
    expect(sendTestCount, 1);
    expect(sendStrongTestCount, 1);
    expect(clearCount, 1);
  });

  testWidgets('通知健康正常时隐藏疑难设置入口，减少重复跳转', (tester) async {
    var openSettingsCount = 0;
    final report = NotificationHealthReport(
      notificationGranted: true,
      exactAlarmGranted: true,
      fullScreenIntentGranted: true,
      channelIds: <String>{
        NotificationService.channelId,
        AlarmService.channelId,
      },
      androidDevice: const AndroidDeviceInfoLite(
        manufacturer: 'Google',
        brand: 'google',
        model: 'Pixel 8',
        sdkInt: 34,
      ),
      isAndroid: true,
      isIOS: false,
      checkedAt: DateTime(2026, 5, 10, 10, 20),
      checks: const [
        PermissionHealthCheck(
          id: 'notification_permission',
          title: '系统通知权限',
          subtitle: '已授权，提醒可以进入通知中心',
          status: PermissionHealthStatus.ok,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationHealthCard(
            report: report,
            pendingCount: 0,
            onRefresh: () {},
            onOpenSystemSettings: () => openSettingsCount++,
            onOpenNotificationChannelSettings: (_) => openSettingsCount++,
            onSendTest: () {},
            onSendStrongTest: () {},
            onClearPending: () {},
            onRequestNotificationPermission: () {},
            onRequestExactAlarmPermission: () {},
            onRequestFullScreenIntentPermission: () {},
          ),
        ),
      ),
    );

    expect(find.text('通知健康检查'), findsOneWidget);
    expect(find.text('疑难设置入口'), findsNothing);
    expect(find.text('0 条待触发'), findsOneWidget);
    expect(openSettingsCount, 0);
  });

  testWidgets('多个静音渠道可以逐项打开对应渠道设置', (tester) async {
    final opened = <String>[];
    final report = NotificationHealthReport(
      notificationGranted: true,
      exactAlarmGranted: true,
      fullScreenIntentGranted: true,
      channelIds: const <String>{},
      androidDevice: const AndroidDeviceInfoLite(
        manufacturer: 'Xiaomi',
        brand: 'xiaomi',
        model: '2210132C',
        sdkInt: 34,
      ),
      isAndroid: true,
      isIOS: false,
      checkedAt: DateTime(2026, 5, 10, 10, 20),
      checks: const [
        PermissionHealthCheck(
          id: 'notification_channel_sound',
          title: '渠道声音',
          subtitle: '已静音 duoyi_general_alerts_v18、duoyi_alarm_fullscreen_v18',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.openAppSettings,
          actionLabel: '渠道设置',
          actionChannelIds: [
            'duoyi_general_alerts_v18',
            'duoyi_alarm_fullscreen_v18',
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationHealthCard(
            report: report,
            pendingCount: 0,
            onRefresh: () {},
            onOpenSystemSettings: () {},
            onOpenNotificationChannelSettings: opened.add,
            onSendTest: () {},
            onSendStrongTest: () {},
            onClearPending: () {},
            onRequestNotificationPermission: () {},
            onRequestExactAlarmPermission: () {},
            onRequestFullScreenIntentPermission: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();

    expect(find.text('通知提醒渠道'), findsOneWidget);
    expect(find.text('强提醒渠道'), findsOneWidget);

    await tester.tap(find.text('强提醒渠道'));
    await tester.pumpAndSettle();

    expect(opened, ['duoyi_alarm_fullscreen_v18']);
  });
}
