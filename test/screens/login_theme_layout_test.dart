// Synthetic form rendering only; code delivery uses an in-memory override.
import 'dart:ui' as ui;

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

class _SyntheticCodeAuth extends AuthProvider {
  int requests = 0;
  @override
  Future<Map<String, dynamic>> sendEmailCode({
    required String email,
    String purpose = 'login',
  }) async {
    requests++;
    return {'message': 'Synthetic code request'};
  }
}

Future<void> _naturalLabel(
  WidgetTester tester,
  RouteRenderProbe probe,
  Finder label,
  String role,
) async {
  await probe.reveal(label);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: label, matching: find.byType(RichText)),
  );
  final render =
      probe.boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  final rect = MatrixUtils.transformRect(
    paragraph.getTransformTo(render),
    Offset.zero & paragraph.size,
  );
  final geometricScale = rect.height / paragraph.size.height;
  final nominal = paragraph.text.style!.fontSize!;
  final expected = MediaQuery.textScalerOf(
    tester.element(label),
  ).scale(nominal);
  final painted = paragraph.textScaler.scale(nominal) * geometricScale;
  probe.rows.add({
    'role': role,
    'nominalFontSize': nominal,
    'expectedFontSize': expected,
    'paintedFontSize': painted,
    'geometricScale': geometricScale,
  });
  if ((painted - expected).abs() > 0.1) {
    probe.errors.add('$role painted $painted expected $expected');
  }
}

Future<void> _header(
  WidgetTester tester,
  RouteRenderProbe probe,
  ThemeProvider theme, {
  required bool email,
}) async {
  await probe.text(
    find.text(theme.brand.strings.appTitle),
    role: 'brand title',
  );
  await probe.text(
    find.text(
      I18n.tr(
        email
            ? 'auth.login.subtitle.email_code'
            : 'auth.login.subtitle.password',
      ),
    ),
    role: 'mode explanation',
  );
  final selector = find.byType(SegmentedButton<bool>);
  for (final key in ['auth.password_login', 'auth.email_code_login']) {
    final label = find.byElementPredicate(
      (element) =>
          element.widget is Text &&
          (element.widget as Text).data == I18n.tr(key) &&
          element.findAncestorWidgetOfExactType<TextField>() == null,
    );
    await probe.text(label, role: 'mode $key');
    await _naturalLabel(tester, probe, label, 'mode $key natural size');
    final merged = find.ancestor(
      of: label,
      matching: find.byType(MergeSemantics),
    );
    final semantics = tester
        .getSemantics(merged.evaluate().isEmpty ? label : merged.first)
        .getSemanticsData();
    final expectedSelected = key == 'auth.email_code_login' ? email : !email;
    final selected = semantics.flagsCollection.isSelected.toBoolOrNull();
    final exclusive = semantics.flagsCollection.isInMutuallyExclusiveGroup;
    final canTap = semantics.hasAction(ui.SemanticsAction.tap);
    probe.rows.add({
      'role': 'mode semantics',
      'text': I18n.tr(key),
      'selected': selected,
      'expectedSelected': expectedSelected,
      'mutuallyExclusive': exclusive,
      'canTap': canTap,
    });
    if (selected != expectedSelected || !exclusive || !canTap) {
      probe.errors.add(
        'mode $key semantics selected=$selected expected=$expectedSelected '
        'exclusive=$exclusive tap=$canTap',
      );
    }
    final button = find.ancestor(of: label, matching: find.byType(TextButton));
    final selectorRect = tester.getRect(selector);
    final buttonRect = tester.getRect(button);
    final vertical =
        tester.widget<SegmentedButton<bool>>(selector).direction ==
        Axis.vertical;
    if (vertical) {
      final widthGap = selectorRect.width - buttonRect.width;
      // Native SegmentedButton clips children to its outline. Compare visible
      // coverage; an internally wider child does not leave a dead region.
      final uncoveredWidth =
          selectorRect.width - buttonRect.intersect(selectorRect).width;
      probe.rows.add({
        'role': 'vertical mode row width',
        'text': I18n.tr(key),
        'selectorWidth': selectorRect.width,
        'buttonWidth': buttonRect.width,
        'widthGap': widthGap,
        'uncoveredWidth': uncoveredWidth,
      });
      if (uncoveredWidth > 1) {
        probe.errors.add(
          'mode $key leaves $uncoveredWidth visible pixels outside its button',
        );
      }
      if (expectedSelected) {
        final render =
            probe.boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final left = render.globalToLocal(
          Offset(selectorRect.left + 8, buttonRect.center.dy),
        );
        final right = render.globalToLocal(
          Offset(selectorRect.right - 8, buttonRect.center.dy),
        );
        final delta = await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1);
          try {
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final a = (left.dy.floor() * image.width + left.dx.floor()) * 4;
            final b = (right.dy.floor() * image.width + right.dx.floor()) * 4;
            return List.generate(
              3,
              (c) => (data.getUint8(a + c) - data.getUint8(b + c)).abs(),
            ).reduce((a, b) => a > b ? a : b);
          } finally {
            image.dispose();
          }
        });
        probe.rows.add({'role': 'vertical selected fill', 'rgbDelta': delta});
        if (delta! > 6) {
          probe.errors.add('selected mode fill differs across row: $delta');
        }
      }
    }
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: label, matching: find.byType(RichText)),
    );
    final text = paragraph.text.toPlainText();
    for (final match in RegExp(r'[A-Za-z]+').allMatches(text)) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: match.start, extentOffset: match.end),
      );
      final tops = boxes.map((box) => box.top.round()).toSet();
      if (tops.length > 1) {
        probe.errors.add('mode $key splits word ${match.group(0)}');
      }
      probe.rows.add({
        'role': 'mode word line count',
        'text': match.group(0),
        'lines': tops.length,
      });
    }
  }
  // Exercise both visible edges, restoring the original selection each time.
  for (final side in ['left', 'right']) {
    for (final target in [!email, email]) {
      final key = target ? 'auth.email_code_login' : 'auth.password_login';
      final label = find.text(I18n.tr(key));
      await probe.reveal(label);
      final rect = tester.getRect(selector);
      final vertical =
          tester.widget<SegmentedButton<bool>>(selector).direction ==
          Axis.vertical;
      final button = find.ancestor(
        of: label,
        matching: find.byType(TextButton),
      );
      final row = tester.getRect(button);
      final point = Offset(
        side == 'left'
            ? (vertical ? rect.left + 8 : row.left + 8)
            : (vertical ? rect.right - 8 : row.right - 8),
        row.center.dy,
      );
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      final actual = tester
          .widget<SegmentedButton<bool>>(selector)
          .selected
          .single;
      probe.rows.add({
        'role': 'mode outer edge tap',
        'side': side,
        'target': target,
        'actual': actual,
        'vertical': vertical,
      });
      if (actual != target) {
        probe.errors.add('mode $key outer edge tap did not select the row');
        await tester.tap(label);
        await tester.pumpAndSettle();
      }
    }
  }
  await probe.capture(
    'header-${email ? 'email' : 'password'}-${I18n.current.name}',
  );
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
        final name = 'login-$brand-${locale.name}-${layout.name}';
        testWidgets('login send label retains natural scaling $name', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          try {
            SharedPreferences.setMockInitialValues({'active_brand': brand});
            I18n.setLocale(locale);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final auth = _SyntheticCodeAuth();
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
            await _header(tester, probe, theme, email: false);
            await probe.capture('password');
            final submit = find.widgetWithText(
              FilledButton,
              I18n.tr('auth.login'),
            );
            await probe.reveal(submit);
            await tester.tap(submit);
            await tester.pumpAndSettle();
            await probe.text(
              find.text(I18n.tr('auth.error.account_required')),
              role: 'local validation error',
            );
            await probe.capture('validation-error');
            expect(auth.requests, 0);
            final mode = find.text(I18n.tr('auth.email_code_login'));
            await probe.reveal(mode);
            await tester.tap(mode);
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byType(TextField).first,
              'synthetic@example.test',
            );
            await tester.pumpAndSettle();
            final state = tester.state(find.byType(LoginScreen));
            final controller = tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!;
            controller.selection = const TextSelection(
              baseOffset: 1,
              extentOffset: 4,
            );
            final value = controller.value;
            for (final stage in ['email', 'live']) {
              if (stage == 'live') {
                I18n.setLocale(
                  locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
                );
                await tester.pumpAndSettle();
              }
              await _header(tester, probe, theme, email: true);
              final label = find.text(I18n.tr('auth.send'));
              await probe.text(label, role: '$stage send');
              await _naturalLabel(
                tester,
                probe,
                label,
                '$stage send painted scaling',
              );
              await probe.capture(stage);
              expect(tester.state(find.byType(LoginScreen)), same(state));
              expect(controller.value, value);
              expect(auth.state.isLoggedIn, isFalse);
              expect(auth.requests, 0);
            }
            await tester.tap(
              find.widgetWithText(FilledButton, I18n.tr('auth.send')),
            );
            await tester.pumpAndSettle();
            expect(auth.requests, 1);
            await probe.text(
              find.text('Synthetic code request'),
              role: 'code request feedback',
            );
            await probe.capture('request-feedback');
            for (final stage in ['cooldown', 'cooldown-live']) {
              if (stage == 'cooldown-live') {
                I18n.setLocale(locale);
                await tester.pumpAndSettle();
              }
              final label = find.byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    (widget.data?.startsWith('Retry in ') == true ||
                        widget.data?.endsWith('s 后') == true),
              );
              await probe.text(label, role: stage, contrast: false);
              await _naturalLabel(
                tester,
                probe,
                label,
                '$stage painted scaling',
              );
              final button = tester.widget<FilledButton>(
                find
                    .ancestor(of: label, matching: find.byType(FilledButton))
                    .first,
              );
              expect(button.onPressed, isNull);
              expect(auth.requests, 1);
              expect(controller.value, value);
              expect(tester.state(find.byType(LoginScreen)), same(state));
              await probe.capture(stage);
            }
            await probe.finish();
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}
