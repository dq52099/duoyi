// Synthetic route rendering and local mode switching; no authentication calls.
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

String _compact(String text) => text.replaceAll(RegExp(r'\s+'), '');

Future<Finder> _footer(
  WidgetTester tester,
  RouteRenderProbe probe, {
  required bool registration,
}) async {
  final button = find.byType(TextButton).last;
  await probe.reveal(button);
  final expected = I18n.tr(
    registration ? 'auth.switch_to_login' : 'auth.switch_to_register',
  );
  final paragraphs = find.descendant(
    of: button,
    matching: find.byType(RichText),
  );
  final rendered = paragraphs.evaluate().map(
    (element) => element.renderObject! as RenderParagraph,
  );
  final label = rendered.map((p) => p.text.toPlainText()).join(' ');
  expect(_compact(label), _compact(expected));
  final action = I18n.current == AppLocale.zh
      ? (registration ? '登录' : '注册')
      : (registration ? 'Sign in' : 'Register');
  final containing = rendered.where(
    (paragraph) => paragraph.text.toPlainText().contains(action),
  );
  expect(
    containing,
    hasLength(1),
    reason: 'Keep the action readable as one unit',
  );
  final paragraph = containing.single;
  final plain = paragraph.text.toPlainText();
  final start = plain.indexOf(action);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + action.length),
  );
  final lineCount = boxes.map((box) => box.top.round()).toSet().length;
  probe.rows.add({
    'role': 'footer action lines',
    'registration': registration,
    'locale': I18n.current.name,
    'label': label,
    'action': action,
    'lineCount': lineCount,
  });
  if (lineCount != 1) {
    probe.errors.add('footer action $action spans $lineCount lines');
  }
  final boundary =
      probe.boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  for (final paragraph in rendered) {
    if (paragraph.didExceedMaxLines ||
        paragraph.textSize.width > paragraph.size.width + 0.1 ||
        paragraph.textSize.height > paragraph.size.height + 0.1) {
      probe.errors.add('footer label is clipped');
    }
    final nominal = paragraph.text.style!.fontSize!;
    final rect = MatrixUtils.transformRect(
      paragraph.getTransformTo(boundary),
      Offset.zero & paragraph.size,
    );
    final expectedSize = MediaQuery.textScalerOf(
      tester.element(button),
    ).scale(nominal);
    final painted =
        paragraph.textScaler.scale(nominal) *
        rect.height /
        paragraph.size.height;
    probe.rows.add({
      'role': 'footer natural size',
      'nominalFontSize': nominal,
      'expectedFontSize': expectedSize,
      'paintedFontSize': painted,
    });
    if ((painted - expectedSize).abs() > 0.1) {
      probe.errors.add('footer text shrinks from $expectedSize to $painted');
    }
  }
  final data = tester.getSemantics(button).getSemanticsData();
  expect(_compact(data.label), _compact(expected));
  expect(tester.widget<TextButton>(button).onPressed, isNotNull);
  final rect = tester.getRect(button);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width + 1));
  return button;
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
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
        final name = 'footer-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            SharedPreferences.setMockInitialValues({'active_brand': brand});
            I18n.setLocale(locale);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final auth = AuthProvider();
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
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ],
                child: ValueListenableBuilder<AppLocale>(
                  valueListenable: I18n.localeListenable,
                  builder: (context, selected, _) => MaterialApp(
                    locale: Locale(selected == AppLocale.en ? 'en' : 'zh'),
                    supportedLocales: const [Locale('en'), Locale('zh')],
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    theme: theme.brand.theme,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: layout.scale < 0
                            ? const RouteProbeNonlinearScaler()
                            : TextScaler.linear(layout.scale),
                      ),
                      child: RepaintBoundary(key: boundary, child: child!),
                    ),
                    home: const LoginScreen(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final probe = RouteRenderProbe(tester, boundary, name);
            final state = tester.state(find.byType(LoginScreen));
            final username = tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!;
            username.text = 'synthetic-user';
            final toRegister = await _footer(
              tester,
              probe,
              registration: false,
            );
            await probe.capture('login');
            await tester.tap(toRegister);
            await tester.pumpAndSettle();
            expect(find.text(I18n.tr('auth.confirm_password')), findsOneWidget);
            await _footer(tester, probe, registration: true);
            await probe.capture('register');
            I18n.setLocale(
              locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
            );
            await tester.pumpAndSettle();
            final toLogin = await _footer(tester, probe, registration: true);
            await probe.capture('register-live-locale');
            expect(tester.state(find.byType(LoginScreen)), same(state));
            await tester.tap(toLogin);
            await tester.pumpAndSettle();
            expect(find.text(I18n.tr('auth.confirm_password')), findsNothing);
            await _footer(tester, probe, registration: false);
            await probe.capture('login-live-locale');
            final retained = tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!;
            expect(retained, same(username));
            expect(retained.text, 'synthetic-user');
            await probe.finish();
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}
