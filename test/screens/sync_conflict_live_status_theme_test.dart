import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/sync_conflict_log_screen.dart';
import 'package:duoyi/services/cloud_sync_notice.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

const _titles = <String, (String, String)>{
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

class _SyncFacts extends CloudSyncProvider {
  _SyncFacts(this.scene);
  String scene;
  @override
  bool get isCloudSyncV2Enabled => scene != 'feature-off';
  @override
  bool get isSyncSuspended => scene == 'paused';
  @override
  bool get hasAuthenticatedClient => scene != 'signed-out';
  @override
  bool get isBackupDisabledByServer => scene == 'backup-off';
  @override
  bool get hasPendingChanges => scene.startsWith('pending');
  @override
  bool get isSyncing => scene == 'syncing';
  @override
  SyncConfig get config =>
      SyncConfig(lastSync: DateTime(2026), autoSync: !scene.endsWith('-off'));
  @override
  String? get lastError => scene.contains('error')
      ? const CloudSyncNotice(CloudSyncNoticeKind.failure).render()
      : null;
  @override
  String? get syncUnavailableStatus => switch (scene) {
    'feature-off' => const CloudSyncNotice(
      CloudSyncNoticeKind.featureDisabled,
    ).render(),
    'paused' => const CloudSyncNotice(
      CloudSyncNoticeKind.accountTransition,
    ).render(),
    'signed-out' => const CloudSyncNotice(
      CloudSyncNoticeKind.signedOut,
    ).render(),
    'backup-off' => const CloudSyncNotice(
      CloudSyncNoticeKind.serverDisabled,
    ).render(),
    _ => null,
  };
  @override
  String? get queuedRemotePullStatus => scene == 'queued'
      ? const CloudSyncNotice(CloudSyncNoticeKind.queuedRemotePull).render()
      : null;
  @override
  String? get syncRetryStatus => scene == 'retry'
      ? const CloudSyncNotice(CloudSyncNoticeKind.retryIncomplete).render()
      : null;
  @override
  String? get lastRealtimeWarning => scene == 'realtime'
      ? const CloudSyncNotice(
          CloudSyncNoticeKind.realtimePollingFallback,
        ).render()
      : null;

  void finish() {
    scene = 'idle';
    notifyListeners();
  }
}

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final scene in _titles.keys) {
      for (final layout in [
        (name: 'large', size: const Size(320, 844)),
        (name: 'landscape', size: const Size(568, 320)),
      ]) {
        final name = 'conflict-live-$brand-$scene-${layout.name}';
        testWidgets(name, (tester) async {
          SharedPreferences.setMockInitialValues({
            'active_brand': brand,
            'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          });
          I18n.setLocale(AppLocale.zh);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final theme = ThemeProvider();
          final sync = _SyncFacts(scene);
          await tester.runAsync(() async {
            await theme.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            theme.dispose();
            sync.dispose();
          });
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<CloudSyncProvider>.value(value: sync),
              ],
              child: Consumer<ThemeProvider>(
                builder: (context, selected, _) =>
                    ValueListenableBuilder<AppLocale>(
                      valueListenable: I18n.localeListenable,
                      builder: (context, locale, _) => MaterialApp(
                        theme: selected.brand.theme,
                        themeAnimationDuration: Duration.zero,
                        locale: Locale(locale.storageValue),
                        supportedLocales: const [Locale('zh'), Locale('en')],
                        localizationsDelegates:
                            GlobalMaterialLocalizations.delegates,
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(
                            context,
                          ).copyWith(textScaler: const TextScaler.linear(2)),
                          child: RepaintBoundary(key: boundary, child: child!),
                        ),
                        home: const BrandRouteSurface(
                          remountOnLocaleChange: false,
                          child: SyncConflictLogScreen(),
                        ),
                      ),
                    ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final retained = tester.state(find.byType(SyncConflictLogScreen));
          final scrollable = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          final probe = RouteRenderProbe(tester, boundary, name);
          Future<void> inspect(String stage) async {
            final card = find.byType(AppSurfaceCard).first;
            final widgets = tester
                .widgetList<Text>(
                  find.descendant(of: card, matching: find.byType(Text)),
                )
                .toList();
            final labels = widgets.map((w) => w.data!).toList();
            final titles = _titles[sync.scene]!;
            expect(
              labels.first,
              I18n.current == AppLocale.en ? titles.$2 : titles.$1,
            );
            expect(labels.length, 6);
            final en = I18n.current == AppLocale.en;
            String pick(String zh, String enText) => en ? enText : zh;
            expect(
              labels[2],
              '${pick('自动同步', 'Auto sync')}: ${sync.config.autoSync ? pick('开启', 'On') : pick('关闭', 'Off')}',
            );
            expect(
              labels[3],
              '${pick('本机改动', 'Local changes')}: ${sync.hasPendingChanges ? pick('待上传', 'Pending upload') : pick('无待上传', 'No pending uploads')}',
            );
            expect(
              labels[4],
              '${pick('同步任务', 'Sync task')}: ${sync.isSyncing ? pick('同步中', 'Syncing') : pick('空闲', 'Idle')}',
            );
            expect(
              labels[5],
              '${pick('远端拉取', 'Remote pull')}: ${sync.queuedRemotePullStatus != null ? pick('已排队', 'Queued') : pick('无排队', 'None queued')}',
            );
            for (final label in labels) {
              final text = find.descendant(
                of: card,
                matching: find.text(label),
              );
              await probe.text(
                text,
                role: '$stage $scene',
                minimumGeometricScale: .999,
              );
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: text, matching: find.byType(RichText)),
              );
              for (final word in RegExp(r'[A-Za-z]+').allMatches(label)) {
                final boxes = paragraph.getBoxesForSelection(
                  TextSelection(baseOffset: word.start, extentOffset: word.end),
                );
                if (boxes.map((box) => (box.top * 10).round()).toSet().length >
                    1) {
                  probe.errors.add('$stage splits ${word.group(0)}');
                }
              }
            }
            await probe.capture('$stage-bottom');
            scrollable.position.jumpTo(0);
            await tester.pumpAndSettle();
            await probe.capture('$stage-top');
            expect(
              tester.state(find.byType(SyncConflictLogScreen)),
              same(retained),
            );
            expect(
              tester.state<ScrollableState>(find.byType(Scrollable).first),
              same(scrollable),
            );
          }

          await inspect('initial');
          I18n.setLocale(AppLocale.en);
          expect(
            await tester.runAsync(
              () => theme.setBrand(
                brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand',
              ),
            ),
            isTrue,
          );
          await tester.pumpAndSettle();
          await inspect('theme-language');
          sync.finish();
          await tester.pumpAndSettle();
          await inspect('idle-transition');
          expect(
            find.descendant(
              of: find.byType(AppSurfaceCard).first,
              matching: find.byType(ButtonStyleButton),
            ),
            findsNothing,
          );
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getStringList('sync_merge_decisions'), isNull);
          await probe.finish();
        });
      }
    }
  }
}
