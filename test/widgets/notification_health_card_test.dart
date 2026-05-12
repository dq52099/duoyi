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
    var sendScheduledTestCount = 0;
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
          id: 'xiaomi_background',
          title: '后台限制',
          subtitle: '将多仪加入后台无限制或允许后台运行',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.openAppSettings,
          actionLabel: '去设置',
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
              onSendTest: () => sendTestCount++,
              onSendScheduledTest: () => sendScheduledTestCount++,
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
    expect(find.textContaining('小米/MIUI'), findsOneWidget);
    expect(find.textContaining('自启动、后台、锁屏和电池优化'), findsWidgets);
    expect(find.text('发送测试通知'), findsOneWidget);
    expect(find.text('1 分钟后测试提醒'), findsOneWidget);
    expect(find.text('系统应用设置'), findsOneWidget);
    expect(find.text('3 条待触发'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);

    await tester.tap(find.text('刷新'));
    await tester.pump();
    await tester.ensureVisible(find.text('去设置'));
    await tester.tap(find.text('去设置'));
    await tester.pump();
    await tester.ensureVisible(find.text('发送测试通知'));
    await tester.tap(find.text('发送测试通知'));
    await tester.pump();
    await tester.ensureVisible(find.text('1 分钟后测试提醒'));
    await tester.tap(find.text('1 分钟后测试提醒'));
    await tester.pump();
    await tester.ensureVisible(find.text('全部取消'));
    await tester.tap(find.text('全部取消'));
    await tester.pump();

    expect(refreshCount, 1);
    expect(openSettingsCount, 1);
    expect(sendTestCount, 1);
    expect(sendScheduledTestCount, 1);
    expect(clearCount, 1);
  });
}
