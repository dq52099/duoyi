import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/sync_status_presenter.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/sync_status_card.dart';

Widget _wrap(SyncStatusController? controller) {
  final child = const MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: SyncStatusCard())),
  );
  if (controller == null) return child;
  return ChangeNotifierProvider<SyncStatusController>.value(
    value: controller,
    child: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('SyncStatusController 转发底层 provider 的状态通知', () async {
    final cloud = CloudSyncProvider();
    var notifications = 0;
    final controller = SyncStatusController(source: cloud)
      ..addListener(() => notifications++);

    expect(controller.lastError, isNull);
    expect(controller.hasEverSynced, isFalse);

    // provider 状态变化（无 apiClientGetter → 置"请先登录"错误）应转发到 controller。
    await cloud.syncNow();
    await Future<void>.delayed(Duration.zero);
    expect(notifications, greaterThan(0));
    expect(controller.lastError, '请先登录');

    controller.dispose();
    cloud.dispose();
  });

  testWidgets('controller 未注入时整卡兜底为空', (tester) async {
    await tester.pumpWidget(_wrap(null));
    await tester.pump();
    expect(find.byKey(const ValueKey('sync_status_card')), findsNothing);
  });

  testWidgets('从未同步：渲染引导文案，无任何手动触发按钮', (tester) async {
    final cloud = CloudSyncProvider();
    final controller = SyncStatusController(source: cloud);
    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(controller.hasEverSynced, isFalse);
    expect(find.text(I18n.tr('sync.status.title')), findsOneWidget);
    expect(find.text(I18n.tr('sync.state.never')), findsOneWidget);
    expect(find.text(I18n.tr('sync.state.never_hint')), findsOneWidget);
    // 架构守卫要求：UI 不允许出现手动同步入口。
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('已同步：显示上次同步时间，无待同步角标', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sync_last_time': '2026-06-07T12:00:00.000Z',
    });
    final cloud = CloudSyncProvider();
    await cloud.loadFromStorage();
    final controller = SyncStatusController(source: cloud);
    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(controller.hasEverSynced, isTrue);
    expect(find.text(I18n.tr('sync.state.synced')), findsOneWidget);
    expect(
      find.textContaining(I18n.tr('sync.last_sync_prefix')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sync_status_card_pending_badge')),
      findsNothing,
    );
  });

  testWidgets('有本地改动未同步：已同步态追加待同步角标', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sync_last_time': '2026-06-07T12:00:00.000Z',
      'sync_pending_local_changes': true,
    });
    final cloud = CloudSyncProvider();
    await cloud.loadFromStorage();
    final controller = SyncStatusController(source: cloud);
    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(controller.hasPendingChanges, isTrue);
    expect(find.text(I18n.tr('sync.state.synced')), findsOneWidget);
    expect(find.text(I18n.tr('sync.pending_badge')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sync_status_card_pending_badge')),
      findsOneWidget,
    );
  });

  testWidgets('同步中：渲染转圈与正在同步文案', (tester) async {
    final cloud = CloudSyncProvider();
    // 注意：Completer 不能跨 tester.runAsync 的 zone 边界传递（监听者
    // 留在 fake-async zone 不会被唤醒），这里用轮询布尔标志等待请求到达。
    var mockHit = false;
    final release = Completer<http.Response>();
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'test-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sync') mockHit = true;
        return release.future;
      }),
    );
    cloud.apiClientGetter = () => client;
    cloud.serverConfigGetter = () => <String, dynamic>{'backup_enabled': true};
    final controller = SyncStatusController(source: cloud);

    await tester.pumpWidget(_wrap(controller));
    await tester.pump();
    // 卡片初始为"尚未同步"态。
    expect(find.text(I18n.tr('sync.state.never')), findsOneWidget);

    await tester.runAsync(() async {
      unawaited(cloud.syncNow());
      for (var i = 0; i < 50 && !mockHit; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();

    expect(mockHit, isTrue, reason: '同步请求应已到达 mock 客户端并保持阻塞');
    expect(controller.isSyncing, isTrue);
    expect(find.text(I18n.tr('sync.state.syncing')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sync_status_card_spinner')),
      findsOneWidget,
    );
  });

  testWidgets('失败：显示失败原因与自动重试提示，不提供手动触发按钮', (tester) async {
    final cloud = CloudSyncProvider();
    // 服务端关闭 backup_enabled → 同步失败态（提前返回，不触网）。
    cloud.apiClientGetter = () => ApiClient(token: 'test-token');
    cloud.serverConfigGetter = () => <String, dynamic>{'backup_enabled': false};
    await cloud.syncNow();
    expect(cloud.lastError, '管理员已关闭云端备份');

    final controller = SyncStatusController(source: cloud);
    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(find.text(I18n.tr('sync.state.failed')), findsOneWidget);
    expect(find.text('管理员已关闭云端备份'), findsOneWidget);
    expect(find.text(I18n.tr('sync.state.auto_retry_hint')), findsOneWidget);
    // 架构守卫要求：失败态同样不出现手动重试/立即同步入口。
    expect(find.byType(TextButton), findsNothing);
    expect(find.byKey(const ValueKey('sync_status_card_retry')), findsNothing);
  });

  test('sync.* 词条 zh/en 双语存在且不回退', () {
    addTearDown(() => I18n.setLocale(AppLocale.zh));
    const keys = <String>[
      'sync.status.title',
      'sync.state.never',
      'sync.state.never_hint',
      'sync.state.syncing',
      'sync.state.synced',
      'sync.state.failed',
      'sync.state.auto_retry_hint',
      'sync.last_sync_prefix',
      'sync.pending_badge',
    ];
    I18n.setLocale(AppLocale.zh);
    for (final key in keys) {
      expect(I18n.tr(key), isNot(key), reason: '$key 缺少 zh 词条');
    }
    // en 缺失时 tr 会静默回退 zh，因此对 en 断言具体英文值。
    I18n.setLocale(AppLocale.en);
    const expectedEn = <String, String>{
      'sync.status.title': 'Cloud sync',
      'sync.state.never': 'Not synced yet',
      'sync.state.never_hint':
          'Sign in and enable cloud sync to back up your data automatically',
      'sync.state.syncing': 'Syncing…',
      'sync.state.synced': 'Synced',
      'sync.state.failed': 'Sync failed',
      'sync.state.auto_retry_hint':
          'Will retry automatically in the background',
      'sync.last_sync_prefix': 'Last synced ',
      'sync.pending_badge': 'Pending',
    };
    for (final key in keys) {
      expect(I18n.tr(key), expectedEn[key], reason: '$key 的 en 词条不符');
    }
  });
}
