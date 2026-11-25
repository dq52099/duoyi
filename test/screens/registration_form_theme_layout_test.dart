// Synthetic registration presentation and retained local controls; no API calls.
import 'dart:math' as math;
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

class _RegistrationAuth extends AuthProvider {
  bool emailRequired = true;
  bool inviteRequired = false;
  bool enabled = true;
  @override
  bool get registrationEmailRequired => emailRequired;
  @override
  bool get inviteCodeRequired => inviteRequired;
  @override
  bool get registrationEnabled => enabled;
  void configure({bool? email, bool? invite, bool? registration}) {
    emailRequired = email ?? emailRequired;
    inviteRequired = invite ?? inviteRequired;
    enabled = registration ?? enabled;
    notifyListeners();
  }
}

Future<void> _text(
  WidgetTester tester,
  RouteRenderProbe probe,
  Finder finder,
  String role,
) async {
  await probe.text(finder, role: role, contrast: false);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
  final boundary =
      probe.boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  final rect = MatrixUtils.transformRect(
    paragraph.getTransformTo(boundary),
    Offset.zero & paragraph.size,
  );
  final nominal = paragraph.text.style!.fontSize!;
  final geometricScale = rect.height / paragraph.size.height;
  final painted = paragraph.textScaler.scale(nominal) * geometricScale;
  // InputDecorator's native floating label transform is 0.75. Additional
  // shrink-to-fit transforms must not conceal the complete-form problem.
  if (geometricScale < 0.749) {
    probe.errors.add('$role shrinks label geometry: $geometricScale');
  }
  final field = find.ancestor(of: finder, matching: find.byType(TextField));
  if (field.evaluate().length == 1) {
    final editable = tester
        .state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .renderEditable;
    if (editable.plainText.isNotEmpty) {
      final labelBoxes = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: paragraph.text.toPlainText().length,
        ),
      );
      final valueBoxes = editable.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: editable.plainText.length),
      );
      // Selection boxes include font strut, so standard one-line floating
      // labels can intersect them without their painted glyphs colliding.
      // This check addresses the additional lines introduced by wrapping.
      final labelLines = labelBoxes.map((box) => box.top).toSet().length;
      final viewport = MatrixUtils.transformRect(
        editable.getTransformTo(boundary),
        Offset.zero & editable.size,
      );
      var overlaps = false;
      for (final label in labelBoxes) {
        final labelRect = MatrixUtils.transformRect(
          paragraph.getTransformTo(boundary),
          label.toRect(),
        );
        for (final value in valueBoxes) {
          final valueRect = MatrixUtils.transformRect(
            editable.getTransformTo(boundary),
            value.toRect(),
          ).intersect(viewport);
          final intersection = labelRect.intersect(valueRect);
          if (intersection.width > 0.5 && intersection.height > 0.5) {
            overlaps = true;
          }
        }
      }
      probe.rows.add({
        'role': '$role label/value separation',
        'selectionBoxesOverlap': overlaps,
        'labelLines': labelLines,
        'enforcedForWrapping': labelLines > 1,
      });
      if (labelLines > 1 && overlaps) {
        probe.errors.add('$role wrapped label overlaps entered text');
      }
    }
  }
  final point = Offset(rect.left - 3, rect.center.dy);
  final background = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final x = point.dx.floor(), y = point.dy.floor();
      expect(x, inInclusiveRange(0, image.width - 1));
      expect(y, inInclusiveRange(0, image.height - 1));
      final offset = (y * image.width + x) * 4;
      return Color.fromARGB(
        255,
        raw.getUint8(offset),
        raw.getUint8(offset + 1),
        raw.getUint8(offset + 2),
      );
    } finally {
      image.dispose();
    }
  });
  final style = paragraph.text.style!;
  final foreground = style.foreground?.color ?? style.color!;
  final a = Color.alphaBlend(foreground, background!).computeLuminance();
  final b = background.computeLuminance();
  final contrast = (math.max(a, b) + .05) / (math.min(a, b) + .05);
  final required = painted >= 24 ? 3.0 : 4.5;
  probe.rows.add({
    'role': '$role actual paint',
    'nominalFontSize': nominal,
    'geometricScale': geometricScale,
    'paintedFontSize': painted,
    'contrast': contrast,
    'required': required,
    'foregroundARGB': foreground.toARGB32(),
    'backgroundARGB': background.toARGB32(),
  });
  if (contrast < required) {
    probe.errors.add('$role contrast $contrast below $required');
  }
}

Future<void> _requiredFields(
  WidgetTester tester,
  RouteRenderProbe probe,
  String stage,
) async {
  await _text(
    tester,
    probe,
    find.text(I18n.tr('auth.email.required_helper')),
    'required email guidance $stage',
  );
  await probe.capture('$stage-guidance');
  for (final key in [
    'auth.username',
    'auth.email',
    'auth.email_code',
    'auth.display_name.optional',
    'auth.password',
    'auth.confirm_password',
  ]) {
    await _text(
      tester,
      probe,
      find.text(I18n.tr(key)).last,
      'field $key $stage',
    );
  }
  await probe.capture('$stage-fields');
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
        final name = 'registration-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            SharedPreferences.setMockInitialValues({'active_brand': brand});
            I18n.setLocale(locale);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final auth = _RegistrationAuth();
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
            final toRegister = find.byType(TextButton).last;
            await probe.reveal(toRegister);
            await tester.tap(toRegister);
            await tester.pumpAndSettle();
            final state = tester.state(find.byType(LoginScreen));
            await _requiredFields(tester, probe, 'required');
            final fields = find.byType(TextField);
            expect(fields, findsNWidgets(6));
            final controllers = [
              for (final widget in tester.widgetList<TextField>(fields))
                widget.controller!,
            ];
            for (final entry in <int, String>{
              0: 'synthetic-user',
              1: 'synthetic@example.test',
              2: '123456',
              3: 'Synthetic nickname',
              4: 'synthetic-password',
              5: 'synthetic-password',
            }.entries) {
              controllers[entry.key].text = entry.value;
            }
            final selected = controllers[0];
            selected.selection = const TextSelection(
              baseOffset: 1,
              extentOffset: 4,
            );
            final value = selected.value;
            I18n.setLocale(
              locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
            );
            await tester.pumpAndSettle();
            await _requiredFields(tester, probe, 'live');
            expect(tester.state(find.byType(LoginScreen)), same(state));
            expect(selected.value, value);
            for (var i = 0; i < controllers.length; i++) {
              expect(
                tester.widgetList<TextField>(fields).elementAt(i).controller,
                same(controllers[i]),
              );
            }
            auth.configure(email: false);
            await tester.pumpAndSettle();
            await _text(
              tester,
              probe,
              find.text(I18n.tr('profile.email.binding')),
              'optional binding title',
            );
            await _text(
              tester,
              probe,
              find.text(I18n.tr('auth.email.optional')).first,
              'optional binding guidance',
            );
            await _text(
              tester,
              probe,
              find.text(I18n.tr('auth.email.optional')).last,
              'optional email label',
            );
            await _text(
              tester,
              probe,
              find.text(I18n.tr('auth.email_code.optional')).last,
              'optional code label',
            );
            await probe.capture('optional');
            auth.configure(invite: true, registration: false);
            await tester.pumpAndSettle();
            await _text(
              tester,
              probe,
              find.text(I18n.tr('auth.invite_code')),
              'invite label',
            );
            await _text(
              tester,
              probe,
              find.text(I18n.tr('auth.registration_closed')),
              'registration closed guidance',
            );
            await probe.capture('closed');
            expect(
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, I18n.tr('auth.register')),
                  )
                  .onPressed,
              isNull,
            );
            final toggle = find.byType(Switch);
            await probe.reveal(toggle);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(
              find.text(I18n.tr('auth.email_code.optional')),
              findsNothing,
            );
            expect(controllers[1].text, isEmpty);
            expect(controllers[2].text, isEmpty);
            expect(selected.value, value);
            expect(controllers[3].text, 'Synthetic nickname');
            expect(controllers[4].text, 'synthetic-password');
            expect(controllers[5].text, 'synthetic-password');
            await probe.finish();
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}
