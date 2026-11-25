import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/providers/sync_status_presenter.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/cloud_sync_notice.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/sync_status_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

class _Status extends SyncStatusController {
  _Status(this.scene);
  String scene;
  int stateChanges = 0;
  @override
  DateTime get lastSync => DateTime(2026, 10, 24, 12, 30);
  @override
  bool get isSyncing => scene == 'syncing';
  @override
  String? get lastError => scene == 'failed'
      ? const CloudSyncNotice(CloudSyncNoticeKind.failure).render()
      : null;
  @override
  bool get hasEverSynced => scene == 'synced' || scene == 'pending';
  @override
  bool get hasPendingChanges => scene == 'pending' || scene == 'failed';
  void change(String next) {
    scene = next;
    stateChanges++;
    notifyListeners();
  }
}

const _layouts = [
  (name: 'ordinary', size: Size(390, 844), scaler: TextScaler.linear(1)),
  (name: 'large', size: Size(320, 844), scaler: TextScaler.linear(2)),
  (name: 'landscape', size: Size(568, 320), scaler: TextScaler.linear(2)),
  (
    name: 'nonlinear',
    size: Size(332, 844),
    scaler: RouteProbeNonlinearScaler(),
  ),
];

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final scene in ['never', 'syncing', 'synced', 'pending', 'failed']) {
      for (final layout in _layouts) {
        final name = 'sync-status-$brand-$scene-${layout.name}';
        testWidgets(name, (tester) async {
          SharedPreferences.setMockInitialValues({
            'active_brand': brand,
            'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          });
          I18n.setLocale(AppLocale.zh);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          late ThemeProvider theme;
          await tester.runAsync(() async {
            theme = ThemeProvider();
            await theme.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });
          final controller = _Status(scene);
          var providerNotifications = 0;
          controller.addListener(() => providerNotifications++);
          final boundary = GlobalKey();
          final cardKey = GlobalKey();
          final card = SyncStatusCard(key: cardKey);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            theme.dispose();
            controller.dispose();
          });
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<SyncStatusController>.value(
                  value: controller,
                ),
              ],
              child: TickerMode(
                enabled: false,
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
                            ).copyWith(textScaler: layout.scaler),
                            child: RepaintBoundary(
                              key: boundary,
                              child: child!,
                            ),
                          ),
                          home: BrandRouteSurface(
                            remountOnLocaleChange: false,
                            child: Scaffold(
                              backgroundColor: Colors.transparent,
                              body: SafeArea(
                                child: SingleChildScrollView(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: card,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final element = cardKey.currentContext;
          final scroll = find.byType(SingleChildScrollView);
          final scrollable = find.descendant(
            of: scroll,
            matching: find.byType(Scrollable),
          );
          final scrollState = tester.state<ScrollableState>(scrollable);
          final probe = RouteRenderProbe(tester, boundary, name);
          Future<void> inspect(String stage) async {
            final stateKey = controller.scene == 'pending'
                ? 'synced'
                : controller.scene;
            final labels = <(String, double)>[
              (I18n.tr('sync.status.title'), 13),
              (I18n.tr('sync.state.$stateKey'), 12),
              if (controller.scene == 'never')
                (I18n.tr('sync.state.never_hint'), 11),
              if (controller.hasEverSynced)
                (
                  '${I18n.tr('sync.last_sync_prefix')}${I18nDateFormat.shortDateTime(controller.lastSync)}',
                  11,
                ),
              if (controller.scene == 'pending')
                (I18n.tr('sync.pending_badge'), 11),
              if (controller.scene == 'failed') ...[
                (controller.lastError!, 11),
                (I18n.tr('sync.state.auto_retry_hint'), 11),
              ],
            ];
            final cardFinder = find.byType(SyncStatusCard);
            final actual = tester
                .widgetList<Text>(
                  find.descendant(of: cardFinder, matching: find.byType(Text)),
                )
                .map((w) => w.data)
                .toList();
            probe.rows.add({
              'role': '$stage copy',
              'locale': I18n.current.storageValue,
              'brand': theme.brand.id,
              'texts': actual,
              'scene': controller.scene,
            });
            for (final (label, size) in labels) {
              final finder = find.descendant(
                of: cardFinder,
                matching: find.text(label),
              );
              if (finder.evaluate().length != 1) {
                probe.errors.add('$stage: stale or missing $label');
                continue;
              }
              await probe.text(
                finder,
                role: '$stage $size',
                minimumGeometricScale: .999,
              );
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: finder, matching: find.byType(RichText)),
              );
              expect(paragraph.text.style!.fontSize, size);
              expect(paragraph.text.style!.fontWeight, FontWeight.normal);
              expect(
                paragraph.textScaler.scale(size),
                layout.scaler.scale(size),
              );
              for (final word in RegExp(r'[A-Za-z]+').allMatches(label)) {
                final boxes = paragraph.getBoxesForSelection(
                  TextSelection(baseOffset: word.start, extentOffset: word.end),
                );
                if (boxes.map((b) => (b.top * 10).round()).toSet().length > 1) {
                  probe.errors.add('$stage splits ${word.group(0)}');
                }
              }
            }
            expect(
              find.byKey(const ValueKey('sync_status_card_spinner')),
              controller.isSyncing ? findsOneWidget : findsNothing,
            );
            expect(
              find.byKey(const ValueKey('sync_status_card_pending_badge')),
              controller.scene == 'pending' ? findsOneWidget : findsNothing,
            );
            expect(
              find.descendant(
                of: cardFinder,
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
              ),
              findsNothing,
            );
            await Scrollable.ensureVisible(
              tester.element(cardFinder),
              alignment: 0,
            );
            await tester.pumpAndSettle();
            final rect = tester.getRect(cardFinder);
            probe.rows.add({
              'role': '$stage card',
              'left': rect.left,
              'top': rect.top,
              'right': rect.right,
              'bottom': rect.bottom,
            });
            await probe.capture(stage);
            expect(cardKey.currentContext, same(element));
            expect(
              tester.state<ScrollableState>(scrollable),
              same(scrollState),
            );
          }

          await inspect('initial');
          I18n.setLocale(AppLocale.en);
          await tester.pumpAndSettle();
          await inspect('language');
          expect(
            await tester.runAsync(
              () => theme.setBrand(
                brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand',
              ),
            ),
            isTrue,
          );
          await tester.pumpAndSettle();
          await inspect('theme');
          expect(await tester.runAsync(() => theme.setBrand(brand)), isTrue);
          I18n.setLocale(AppLocale.zh);
          await tester.pumpAndSettle();
          await inspect('restored');
          expect(providerNotifications, 0);
          expect(controller.stateChanges, 0);
          controller.change(scene == 'failed' ? 'pending' : 'failed');
          await tester.pumpAndSettle();
          expect(providerNotifications, 1);
          expect(controller.stateChanges, 1);
          await inspect('transition');
          await probe.finish();
        });
      }
    }
  }
}
