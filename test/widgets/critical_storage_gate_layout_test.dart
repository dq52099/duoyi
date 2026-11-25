// Synthetic presentation only; root admission is verified separately.
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/critical_storage_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in [
        (name: 'common', size: const Size(390, 844), scale: 1.0),
        (name: 'narrow', size: const Size(320, 844), scale: 1.6),
        (name: 'large', size: const Size(320, 844), scale: 2.0),
        (name: 'landscape', size: const Size(568, 320), scale: 2.0),
        (name: 'desktop', size: const Size(1000, 720), scale: 1.1),
        (name: 'nonlinear', size: const Size(332, 844), scale: -1.0),
      ]) {
        final name = 'critical-gate-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          I18n.setLocale(locale);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final theme = ThemeProvider();
          await tester.runAsync(() async {
            await theme.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });
          addTearDown(theme.dispose);
          var busy = false;
          var retries = 0;
          final boundary = GlobalKey();
          await tester.pumpWidget(
            StatefulBuilder(
              builder: (context, setState) => ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, selected, _) => MaterialApp(
                  locale: Locale(selected == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      disableAnimations: true,
                      textScaler: layout.scale < 0
                          ? const RouteProbeNonlinearScaler()
                          : TextScaler.linear(layout.scale),
                    ),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: CriticalStorageGate(
                    busy: busy,
                    failed: !busy,
                    onRetry: () => setState(() {
                      retries++;
                      busy = true;
                    }),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final state = tester.element(find.byType(CriticalStorageGate));
          final probe = RouteRenderProbe(tester, boundary, name);
          Future<void> verifyError(String stage) async {
            final english = I18n.current == AppLocale.en;
            await probe.text(
              find.text(english ? 'Unable to load local data' : '无法加载本地数据'),
              role: '$stage title',
            );
            await probe.text(
              find.text(english ? 'Please retry to continue.' : '请重试以继续。'),
              role: '$stage description',
            );
            await probe.text(
              find.text(I18n.tr('action.retry')),
              role: '$stage retry',
              contrast: false,
            );
            final button = find.byKey(const ValueKey('critical_storage_retry'));
            await probe.reveal(button);
            final rect = tester.getRect(button);
            expect(rect.width, greaterThanOrEqualTo(44));
            expect(rect.height, greaterThanOrEqualTo(44));
            await probe.capture(stage);
          }

          await verifyError('failed');
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          expect(tester.element(find.byType(CriticalStorageGate)), same(state));
          await verifyError('failed-live-locale');
          await tester.tap(
            find.byKey(const ValueKey('critical_storage_retry')),
          );
          await tester.pumpAndSettle();
          expect(retries, 1);
          expect(
            find.byKey(const ValueKey('critical_storage_retry')),
            findsNothing,
          );
          expect(
            find.byType(CircularProgressIndicator),
            findsNothing,
            reason: 'reduced motion uses a static waiting indicator',
          );
          await probe.text(
            find.text(
              I18n.current == AppLocale.en ? 'Loading local data' : '正在加载本地数据',
            ),
            role: 'busy',
          );
          await probe.capture('busy');
          await probe.finish();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        });
      }
    }
  }
}
