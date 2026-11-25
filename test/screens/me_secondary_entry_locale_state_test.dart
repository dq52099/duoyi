import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/screens/more_apps_screen.dart';
import 'package:duoyi/screens/sync_conflict_log_screen.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'More apps updates its retained fallback route and entry labels',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final theme = await _screenshotTheme(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 1000),
              textScaler: TextScaler.linear(1.6),
            ),
            child: RepaintBoundary(
              key: key,
              child: const MoreApplicationsScreen(
                visibleBottomNavTabs: [0, 1, 2, 6],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final route = tester.element(find.byType(MoreApplicationsScreen));
      expect(find.text('更多应用'), findsOneWidget);
      expect(find.text('日历'), findsOneWidget);
      expect(find.text('小组件'), findsOneWidget);
      for (final locale in [AppLocale.en, AppLocale.zh, AppLocale.en]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(
          tester.element(find.byType(MoreApplicationsScreen)),
          same(route),
        );
        expect(find.text(I18n.tr('mine.tile.more_apps')), findsOneWidget);
        expect(find.text(I18n.tr('nav.calendar')), findsOneWidget);
        expect(find.text(I18n.tr('nav.widget')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(find.bySemanticsLabel(RegExp('Open Calendar')), findsOneWidget);
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        1,
      );
      await _capture(tester, key, 'more-apps-en-320-scale-1.6.png');
    },
  );

  testWidgets('More apps empty state updates with locale', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MoreApplicationsScreen(visibleBottomNavTabs: [0, 1, 2, 3, 5, 6]),
      ),
    );
    await tester.pumpAndSettle();
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text('No hidden navigation features'), findsOneWidget);
    expect(
      find.text('All features are shown in the bottom navigation'),
      findsOneWidget,
    );
    expect(find.byType(MoreApplicationButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sync fallback follows locale without reloading saved conflicts',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList('sync_merge_decisions', [
        jsonEncode({
          'winner': 'remote',
          'reason': 'literal reason 原始内容',
          'itemId': 'literal-id',
          'itemType': 'todo',
          'changedFields': ['literal_field_名称'],
          'decidedAt': '2026-10-13T10:00:00Z',
        }),
      ]);
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final theme = await _screenshotTheme(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 1000),
              textScaler: TextScaler.linear(1.6),
            ),
            child: RepaintBoundary(
              key: key,
              child: ChangeNotifierProvider(
                create: (_) => ThemeProvider(),
                child: const BrandRouteSurface(child: SyncConflictLogScreen()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(SyncConflictLogScreen));
      expect(find.text('同步状态未接入'), findsOneWidget);
      await preferences.remove('sync_merge_decisions');
      for (final locale in [AppLocale.en, AppLocale.zh, AppLocale.en]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(SyncConflictLogScreen)), same(state));
        expect(find.text(I18n.tr('sync_conflict.title')), findsOneWidget);
        expect(find.text('literal reason 原始内容'), findsOneWidget);
        expect(
          find.text(
            '${locale == AppLocale.en ? 'Field' : '字段'}: literal_field_名称',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Sync status unavailable'), findsOneWidget);
      expect(find.text('Auto sync: Unknown'), findsOneWidget);
      await _capture(tester, key, 'sync-status-en-320-scale-1.6.png');
    },
  );

  final states = <String, (String, String)>{
    'idle': ('云同步正常', 'Cloud sync up to date'),
    'feature-off': ('云同步暂不可用', 'Cloud sync unavailable'),
    'paused': ('云同步已暂停', 'Cloud sync paused'),
    'signed-out': ('未登录云同步账号', 'Sign in to cloud sync'),
    'backup-off': ('云端备份已关闭', 'Cloud backup disabled'),
    'error': ('云同步上次未完成', 'Last cloud sync incomplete'),
    'pending-error': ('本机改动同步未完成', 'Local changes not synced'),
    'queued': ('远端更新已排队', 'Remote updates queued'),
    'syncing': ('正在同步', 'Syncing'),
    'pending-off': ('本机改动未自动上传', 'Automatic upload is off'),
    'pending': ('本机改动待上传', 'Local changes pending upload'),
    'retry': ('云同步等待重试', 'Cloud sync awaiting retry'),
    'realtime': ('实时同步使用轮询兜底', 'Live sync using polling'),
    'auto-off': ('自动同步已关闭', 'Automatic sync is off'),
  };
  for (final entry in states.entries) {
    testWidgets('Sync status ${entry.key} follows live locale', (tester) async {
      final sync = _SyncFixture(entry.key);
      addTearDown(sync.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<CloudSyncProvider>.value(
          value: sync,
          child: MaterialApp(
            home: ChangeNotifierProvider(
              create: (_) => ThemeProvider(),
              child: const BrandRouteSurface(child: SyncConflictLogScreen()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(SyncConflictLogScreen));
      expect(find.text(entry.value.$1), findsWidgets);
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(SyncConflictLogScreen)), same(state));
        expect(
          find.text(locale == AppLocale.en ? entry.value.$2 : entry.value.$1),
          findsWidgets,
        );
        if (entry.key.contains('error')) {
          expect(find.textContaining('literal diagnostic 原样'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _SyncFixture extends CloudSyncProvider {
  _SyncFixture(this.status);
  final String status;
  @override
  bool get isCloudSyncV2Enabled => status != 'feature-off';
  @override
  bool get isSyncSuspended => status == 'paused';
  @override
  bool get hasAuthenticatedClient => status != 'signed-out';
  @override
  bool get isBackupDisabledByServer => status == 'backup-off';
  @override
  bool get hasPendingChanges => status.startsWith('pending');
  @override
  bool get isSyncing => status == 'syncing';
  @override
  SyncConfig get config =>
      SyncConfig(lastSync: DateTime(2026), autoSync: !status.endsWith('-off'));
  @override
  String? get lastError =>
      status.contains('error') ? 'literal diagnostic 原样' : null;
  @override
  String? get syncUnavailableStatus =>
      ['feature-off', 'paused', 'signed-out', 'backup-off'].contains(status)
      ? 'literal unavailable 原样'
      : null;
  @override
  String? get queuedRemotePullStatus =>
      status == 'queued' ? 'literal queued 原样' : null;
  @override
  String? get syncRetryStatus => status == 'retry' ? 'literal retry 原样' : null;
  @override
  String? get lastRealtimeWarning =>
      status == 'realtime' ? 'literal realtime 原样' : null;
}

Future<ThemeData> _screenshotTheme(WidgetTester tester) async {
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final provider = ThemeProvider();
  final theme = provider.brand.theme;
  provider.dispose();
  return theme.copyWith(
    scaffoldBackgroundColor: DesignTokens.defaultPageBackground,
    textTheme: theme.textTheme.apply(
      fontFamily: 'DuoyiScreenshotLatin',
      fontFamilyFallback: const ['DuoyiScreenshot'],
    ),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'DuoyiScreenshotLatin',
        fontFamilyFallback: const ['DuoyiScreenshot'],
      ),
    ),
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['DUOYI_ME_ENTRY_SCREENSHOT_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$directory/$name');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
