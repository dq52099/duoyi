// Synthetic paired-theme route regression; optional evidence uses DUOYI_SECONDARY_* env vars.
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/ai_history_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../support/secondary_route_render_probe.dart';
import '../support/secondary_route_header_probe.dart';

const _body = 'Literal AI body 原文 remains unchanged across locale switches.';
final _entry = AiReviewEntry(
  id: 'synthetic-theme-review',
  createdAt: DateTime(2026, 10, 14, 9, 35),
  summary: 'this week数据：完成 2 / 3 项待办，专注 45 分钟，习惯连续打卡 4 天。',
  content: _body,
  model: 'Synthetic model',
);

class _History extends AiService {
  @override
  List<AiReviewEntry> get reviewHistory => [_entry];
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in [
        (name: 'common', size: const Size(390, 844), scale: 1.0),
        (name: 'narrow', size: const Size(320, 844), scale: 1.6),
        (name: 'landscape', size: const Size(568, 320), scale: 2.0),
        (name: 'desktop', size: const Size(1000, 720), scale: 1.1),
        (name: 'large', size: const Size(320, 844), scale: 2.0),
        (name: 'nonlinear', size: const Size(332, 844), scale: -1.0),
      ]) {
        final name = 'history-$brand-${locale.name}-${layout.name}';
        testWidgets('history complete generated copy and contrast $name', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          I18n.setLocale(locale);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final theme = ThemeProvider();
          final ai = _History();
          final auth = AuthProvider();
          await tester.runAsync(() async {
            await theme.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            theme.dispose();
            ai.dispose();
            auth.dispose();
          });
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AiService>.value(value: ai),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ],
              child: ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, selected, _) => MaterialApp(
                  locale: Locale(selected == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: layout.scale < 0
                          ? const RouteProbeNonlinearScaler()
                          : TextScaler.linear(layout.scale),
                    ),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: Center(
                        child: TextButton(
                          key: const ValueKey('probe_open_route'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BrandRouteSurface(
                                child: AiHistoryScreen(),
                              ),
                            ),
                          ),
                          child: const Text('Open synthetic route'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('probe_open_route')));
          await tester.pumpAndSettle();
          expect(theme.brand.id, brand);
          final probe = RouteRenderProbe(tester, boundary, name);
          await checkSecondaryRouteHeader(
            probe,
            'ai_history.title',
            stage: 'initial',
          );
          await probe.capture('collapsed');
          await probe.text(
            find.text(I18nDateFormat.fullDateTime(_entry.createdAt)),
            role: 'timestamp',
          );
          await probe.text(find.text(_entry.displaySummary), role: 'summary');
          await probe.text(find.text(_entry.model), role: 'model');
          final toggle = find.byKey(
            const ValueKey('ai_history_toggle_synthetic-theme-review'),
          );
          final menu = find.byKey(
            const ValueKey('ai_history_menu_synthetic-theme-review'),
          );
          for (final control in [toggle, menu]) {
            await probe.reveal(control);
            final rect = tester.getRect(control);
            if (rect.width < 43.99 || rect.height < 43.99) {
              probe.errors.add(
                'history control target ${rect.width} x ${rect.height} below44',
              );
            }
            expect(control.hitTestable(), findsOneWidget);
          }
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(find.text(_body), findsOneWidget);
          await probe.text(find.text(_body), role: 'saved body');
          await probe.capture('expanded');
          final state = tester.state(find.byType(AiHistoryScreen));
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(AiHistoryScreen)), same(state));
          expect(find.text(_body), findsOneWidget);
          expect(ai.reviewHistory.single.content, _body);
          expect(find.text(_entry.displaySummary), findsOneWidget);
          await probe.text(
            find.text(I18nDateFormat.fullDateTime(_entry.createdAt)),
            role: 'live timestamp',
          );
          await probe.text(
            find.text(_entry.displaySummary),
            role: 'live summary',
          );
          await probe.reveal(menu);
          await tester.tap(menu);
          await tester.pumpAndSettle();
          expect(find.text(I18n.tr('ai_history.copy')), findsOneWidget);
          Navigator.of(
            tester.element(find.text(I18n.tr('ai_history.copy'))),
          ).pop();
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(AiHistoryScreen)), same(state));
          await probe.capture('live');
          await checkSecondaryRouteHeader(
            probe,
            'ai_history.title',
            stage: 'live',
          );
          await probe.finish();
          final back = find.byType(BackButton);
          expect(back.hitTestable(), findsOneWidget);
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(find.byType(AiHistoryScreen), findsNothing);
          expect(
            find.byKey(const ValueKey('probe_open_route')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
