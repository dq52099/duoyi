// Regression for the two priority themes; captures are opt-in.
// Measures actual Birthday/Memorial entry content, rather than a shared file's
// incidental theme identifiers. Synthetic data; no network or accepted writes.
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final type in [AnniversaryType.birthday, AnniversaryType.memorial]) {
        for (final layout in priorityLayouts) {
          final name =
              'fixed-date-$brand-${locale.name}-${type.name}-${layout.name}';
          testWidgets(name, (tester) async {
            final item = Anniversary(
              id: 'fixed-date-synthetic',
              title:
                  'A complete authored celebration title 原始标题 that stays readable',
              description:
                  'Authored details 原始说明 remain available at enlarged text without losing the final words.',
              originDate: DateTime(2023, 3, 22),
              type: type,
            );
            final provider = AnniversaryProvider();
            final auth = AuthProvider();
            addTearDown(provider.dispose);
            final boundary = await _mountFixedDateFixture(
              tester,
              auth: auth,
              anniversaries: provider,
              brand: brand,
              locale: locale,
              size: layout.size,
              scale: layout.scale,
              home: BrandRouteSurface(
                child: type == AnniversaryType.birthday
                    ? const BirthdayScreen()
                    : const MemorialAnniversaryScreen(),
              ),
            );
            final stored = [jsonEncode(item.toJson())];
            SharedPreferences.setMockInitialValues({
              'active_brand': brand,
              'duoyi_anniversaries_v2': stored,
            });
            await tester.runAsync(provider.loadFromStorage);
            await tester.pumpAndSettle();
            final page = tester.element(find.byType(AnniversaryScreen));
            final list = find.byKey(ValueKey('anniversary_fixed_${type.name}'));
            expect(list, findsOneWidget);
            expect(find.byType(TabBar), findsNothing);
            final probe = RouteRenderProbe(tester, boundary, name);

            Future<void> inspect(String stage) async {
              final scrollable = find
                  .descendant(of: list, matching: find.byType(Scrollable))
                  .first;
              await tester.scrollUntilVisible(
                find.byKey(const ValueKey('anniversary_summary_total')),
                -200,
                scrollable: scrollable,
              );
              for (final key in [
                'anniversary_summary_total',
                'anniversary_summary_within_30_days',
              ]) {
                final stat = find.byKey(ValueKey(key));
                final labels = find.descendant(
                  of: stat,
                  matching: find.byType(Text),
                );
                for (var i = 0; i < labels.evaluate().length; i++) {
                  await probe.text(
                    labels.at(i),
                    role: '$stage $key',
                    minimumGeometricScale: .999,
                  );
                }
              }
              await probe.text(
                find.textContaining(item.title).first,
                role: '$stage nearest title',
                minimumGeometricScale: .999,
              );
              await probe.capture('$stage-summary');
              final card = find.byKey(ValueKey('anniversary_card_${item.id}'));
              await tester.scrollUntilVisible(
                card,
                200,
                scrollable: scrollable,
              );
              for (final value in [item.title, item.description!]) {
                expect(
                  find.descendant(of: card, matching: find.text(value)),
                  findsOneWidget,
                );
              }
              final cardTexts = find.descendant(
                of: card,
                matching: find.byType(Text),
              );
              final count = cardTexts.evaluate().length;
              for (var i = 0; i < count; i++) {
                await probe.text(
                  cardTexts.at(i),
                  role: '$stage complete card text',
                  minimumGeometricScale: .999,
                );
              }
              await probe.capture('$stage-card');
            }

            await inspect('initial');
            final position = tester
                .state<ScrollableState>(
                  find
                      .descendant(of: list, matching: find.byType(Scrollable))
                      .first,
                )
                .position;
            final pixels = position.pixels;
            I18n.setLocale(
              locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
            );
            await tester.pumpAndSettle();
            expect(tester.element(find.byType(AnniversaryScreen)), same(page));
            expect(
              position.pixels,
              closeTo(
                pixels.clamp(
                  position.minScrollExtent,
                  position.maxScrollExtent,
                ),
                .1,
              ),
            );
            expect(provider.items.single.title, item.title);
            expect(provider.items.single.description, item.description);
            await inspect('locale-switched');

            final card = find.byKey(ValueKey('anniversary_card_${item.id}'));
            final title = find.descendant(
              of: card,
              matching: find.text(item.title),
            );
            await probe.reveal(title);
            await tester.tap(title);
            await tester.pumpAndSettle();
            expect(find.byType(TextField), findsWidgets);
            final cancel = find.text(I18n.tr('action.cancel'));
            final modalScroll = find
                .descendant(
                  of: find.byType(AppModalSheet),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Scrollable &&
                        widget.axisDirection == AxisDirection.down,
                  ),
                )
                .first;
            // The center may be a multiline TextField that consumes drags.
            // Drag the list padding so the sheet itself receives the gesture.
            for (
              var attempt = 0;
              attempt < 40 && cancel.hitTestable().evaluate().isEmpty;
              attempt++
            ) {
              final rect = tester.getRect(modalScroll);
              await tester.dragFrom(
                Offset(rect.left + 4, rect.center.dy),
                Offset(0, -(rect.height * .5).clamp(40, 160).toDouble()),
              );
              await tester.pumpAndSettle();
            }
            expect(cancel.hitTestable(), findsOneWidget);
            await tester.tap(cancel);
            await tester.pumpAndSettle();
            expect(find.byType(TextField), findsNothing);
            expect(tester.element(find.byType(AnniversaryScreen)), same(page));
            expect(
              (await SharedPreferences.getInstance()).getStringList(
                'duoyi_anniversaries_v2',
              ),
              stored,
            );
            expect(tester.takeException(), isNull);
            await probe.finish();
          });
        }
      }
    }
  }
}

Future<GlobalKey> _mountFixedDateFixture(
  WidgetTester tester, {
  required AuthProvider auth,
  required AnniversaryProvider anniversaries,
  required String brand,
  required AppLocale locale,
  required Size size,
  required double scale,
  required Widget home,
}) async {
  SharedPreferences.setMockInitialValues({'active_brand': brand});
  I18n.setLocale(locale);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = ThemeProvider();
  await tester.runAsync(() async {
    await theme.loadFromStorage();
    await loadWeeklyReviewScreenshotFonts();
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    auth.dispose();
    theme.dispose();
  });
  final boundary = GlobalKey();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AnniversaryProvider>.value(value: anniversaries),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
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
              textScaler: scale < 0
                  ? const RouteProbeNonlinearScaler()
                  : TextScaler.linear(scale),
            ),
            child: RepaintBoundary(key: boundary, child: child!),
          ),
          home: home,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return boundary;
}
