// Real reset dialog with in-memory request/confirm ports; never sends mail.
import 'dart:async';

import 'package:duoyi/core/account_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

class _ResetAuth extends AuthProvider {
  final requested = <String>[];
  final confirmed = <Map<String, String?>>[];
  Future<Map<String, dynamic>>? nextRequest;

  @override
  Future<Map<String, dynamic>> requestPasswordReset({
    required String account,
  }) async {
    requested.add(account);
    final pending = nextRequest;
    if (pending != null) return await pending;
    return <String, dynamic>{};
  }

  @override
  Future<void> confirmPasswordReset({
    String? token,
    String? account,
    String? email,
    String? code,
    required String newPassword,
  }) async {
    confirmed.add({
      'account': account,
      'email': email,
      'code': code,
      'password': newPassword,
    });
  }
}

Future<void> _mountRetainedReset(
  WidgetTester tester,
  _ResetAuth auth,
  String brand,
) async {
  SharedPreferences.setMockInitialValues({'active_brand': brand});
  I18n.setLocale(AppLocale.zh);
  final theme = ThemeProvider();
  await tester.runAsync(theme.loadFromStorage);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    auth.dispose();
    theme.dispose();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ],
      child: MaterialApp(theme: theme.brand.theme, home: const LoginScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(I18n.tr('auth.forgot_password')));
  await tester.tap(find.text(I18n.tr('auth.forgot_password')));
  await tester.pumpAndSettle();
}

Finder _dialogField(int index) => find
    .descendant(of: find.byType(AlertDialog), matching: find.byType(TextField))
    .at(index);

Future<void> _resetAction(
  WidgetTester tester,
  String key, {
  bool settle = true,
}) async {
  final button = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(FilledButton, I18n.tr(key)),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _label(
  WidgetTester tester,
  RouteRenderProbe probe,
  String key,
) async {
  final finder = find.text(I18n.tr(key)).last;
  await probe.text(finder, role: key, contrast: false);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
  final nominal = paragraph.text.style!.fontSize!;
  final boundary =
      probe.boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  final rect = MatrixUtils.transformRect(
    paragraph.getTransformTo(boundary),
    Offset.zero & paragraph.size,
  );
  final geometricScale = rect.height / paragraph.size.height;
  probe.rows.add({
    'role': '$key typography',
    'nominalFontSize': nominal,
    'geometricScale': geometricScale,
  });
  if (geometricScale < 0.749) {
    probe.errors.add('$key shrinks beyond normal floating label');
  }
  final field = find.ancestor(of: finder, matching: find.byType(TextField));
  if (field.evaluate().length == 1) {
    final editable = tester
        .state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .renderEditable;
    if (editable.plainText.isNotEmpty) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: paragraph.text.toPlainText().length,
        ),
      );
      final lines = boxes.map((box) => box.top).toSet().length;
      final values = editable.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: editable.plainText.length),
      );
      final viewport = MatrixUtils.transformRect(
        editable.getTransformTo(boundary),
        Offset.zero & editable.size,
      );
      var overlap = false;
      for (final label in boxes) {
        final labelRect = MatrixUtils.transformRect(
          paragraph.getTransformTo(boundary),
          label.toRect(),
        );
        for (final value in values) {
          final valueRect = MatrixUtils.transformRect(
            editable.getTransformTo(boundary),
            value.toRect(),
          ).intersect(viewport);
          final intersection = labelRect.intersect(valueRect);
          overlap |= intersection.width > .5 && intersection.height > .5;
        }
      }
      probe.rows.add({
        'role': '$key separation',
        'lines': lines,
        'enforced': lines > 1,
        'overlap': overlap,
      });
      if (lines > 1 && overlap) {
        probe.errors.add('$key wrapped label overlaps value');
      }
    }
  }
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    testWidgets('reset $brand retained local errors and server text', (
      tester,
    ) async {
      final auth = _ResetAuth();
      await _mountRetainedReset(tester, auth, brand);
      final element = tester.element(find.byType(AlertDialog));
      await _resetAction(tester, 'auth.password_reset.send_email');
      expect(
        find.text(I18n.tr('auth.error.reset_account_required')),
        findsOneWidget,
      );
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(tester.element(find.byType(AlertDialog)), same(element));
      expect(
        find.text(I18n.tr('auth.error.reset_account_required')),
        findsOneWidget,
      );
      final account = tester.widget<TextField>(_dialogField(0)).controller!;
      account.text = 'synthetic-user';
      auth.nextRequest = Future.value({
        'message': 'Server exact 原文',
        'dev_code': '009812',
      });
      await _resetAction(tester, 'auth.password_reset.send_email');
      expect(
        find.text(
          'Server exact 原文 ${I18n.tr('auth.email_code.code_prefix')}009812',
        ),
        findsOneWidget,
      );
      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(
        find.text(
          'Server exact 原文 ${I18n.tr('auth.email_code.code_prefix')}009812',
        ),
        findsOneWidget,
      );
      await _resetAction(tester, 'auth.password_reset.confirm');
      expect(
        find.text(I18n.tr('auth.error.mail_code_required')),
        findsOneWidget,
      );
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(
        find.text(I18n.tr('auth.error.mail_code_required')),
        findsOneWidget,
      );
      tester.widget<TextField>(_dialogField(1)).controller!.text = '123456';
      await _resetAction(tester, 'auth.password_reset.confirm');
      expect(
        find.text(I18n.tr('auth.error.new_password_short')),
        findsOneWidget,
      );
      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(
        find.text(I18n.tr('auth.error.new_password_short')),
        findsOneWidget,
      );
      expect(auth.requested, ['synthetic-user']);
      expect(auth.confirmed, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reset $brand pending request failure and disposed response', (
      tester,
    ) async {
      final auth = _ResetAuth();
      final pending = Completer<Map<String, dynamic>>();
      auth.nextRequest = pending.future;
      await _mountRetainedReset(tester, auth, brand);
      final account = tester.widget<TextField>(_dialogField(0)).controller!;
      account.text = 'synthetic@example.test';
      account.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
      final value = account.value;
      await _resetAction(
        tester,
        'auth.password_reset.send_email',
        settle: false,
      );
      expect(
        tester
            .widget<TextButton>(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed,
        isNull,
      );
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(account.value, value);
      final failure = ApiException('invalid code');
      pending.completeError(failure);
      await tester.pumpAndSettle();
      expect(find.text(AccountUiCopy.formatError(failure)), findsOneWidget);
      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(find.text(AccountUiCopy.formatError(failure)), findsOneWidget);
      final late = Completer<Map<String, dynamic>>();
      auth.nextRequest = late.future;
      await _resetAction(
        tester,
        'auth.password_reset.send_email',
        settle: false,
      );
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(I18n.tr('auth.forgot_password')));
      await tester.tap(find.text(I18n.tr('auth.forgot_password')));
      await tester.pumpAndSettle();
      final fresh = tester.widget<TextField>(_dialogField(0)).controller!;
      late.complete({'message': 'Obsolete synthetic result'});
      await tester.pumpAndSettle();
      expect(find.text('Obsolete synthetic result'), findsNothing);
      expect(fresh.text, isEmpty);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );
      expect(auth.requested.length, 2);
      expect(auth.confirmed, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
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
        final name = 'reset-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          I18n.setLocale(locale);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final auth = _ResetAuth();
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
                  home: const LoginScreen(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final probe = RouteRenderProbe(tester, boundary, name);
          final forgot = find.text(I18n.tr('auth.forgot_password'));
          await probe.reveal(forgot);
          await tester.tap(forgot);
          await tester.pumpAndSettle();
          final dialog = find.byType(AlertDialog);
          expect(dialog, findsOneWidget);
          Finder field(int index) => find
              .descendant(of: dialog, matching: find.byType(TextField))
              .at(index);
          Future<void> press(String key) async {
            final button = find.descendant(
              of: dialog,
              matching: find.widgetWithText(FilledButton, I18n.tr(key)),
            );
            await probe.reveal(button);
            await tester.tap(button);
            await tester.pumpAndSettle();
          }

          await _label(tester, probe, 'auth.reset_account');
          await probe.text(
            find.text(I18n.tr('auth.reset_account.helper')),
            role: 'account guidance',
          );
          await probe.text(
            find.text(I18n.tr('auth.password_reset.send_email')),
            role: 'send action',
          );
          await probe.capture('initial');
          await press('auth.password_reset.send_email');
          await probe.text(
            find.text(I18n.tr('auth.error.reset_account_required')),
            role: 'empty account error',
          );
          expect(auth.requested, isEmpty);
          final account = tester.widget<TextField>(field(0)).controller!;
          account.text = 'synthetic@example.test';
          account.selection = const TextSelection(
            baseOffset: 1,
            extentOffset: 4,
          );
          final accountValue = account.value;
          await press('auth.password_reset.send_email');
          expect(auth.requested, ['synthetic@example.test']);
          expect(tester.widget<TextField>(field(0)).enabled, isFalse);
          await _label(tester, probe, 'auth.email_code');
          await _label(tester, probe, 'auth.new_password');
          await probe.text(
            find.text(I18n.tr('auth.password_reset.email_sent')),
            role: 'request success',
          );
          await probe.capture('requested');
          final code = tester.widget<TextField>(field(1)).controller!;
          final password = tester.widget<TextField>(field(2)).controller!;
          code.text = '123456';
          password.text = 'synthetic-password';
          password.selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 5,
          );
          final passwordValue = password.value;
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          await _label(tester, probe, 'auth.reset_account');
          await _label(tester, probe, 'auth.new_password');
          if (find
              .text(I18n.tr('auth.password_reset.email_sent'))
              .evaluate()
              .isEmpty) {
            probe.errors.add(
              'local reset success message remains in previous locale',
            );
          }
          expect(tester.widget<TextField>(field(0)).controller, same(account));
          expect(account.value, accountValue);
          expect(tester.widget<TextField>(field(1)).controller, same(code));
          expect(tester.widget<TextField>(field(2)).controller, same(password));
          expect(password.value, passwordValue);
          expect(auth.requested.length, 1);
          final visibility = find.descendant(
            of: field(2),
            matching: find.byType(IconButton),
          );
          await probe.reveal(visibility);
          await tester.tap(visibility);
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(field(2)).obscureText, isFalse);
          await probe.capture('retained-live');
          if (layout.size.height > 700 && layout.size.width < 500) {
            tester.view.viewInsets = const FakeViewPadding(bottom: 240);
            await tester.pumpAndSettle();
            await _label(tester, probe, 'auth.new_password');
            await probe.text(
              find.descendant(
                of: find.descendant(
                  of: dialog,
                  matching: find.byType(FilledButton),
                ),
                matching: find.text(I18n.tr('auth.password_reset.confirm')),
              ),
              role: 'confirm with simulated keyboard',
            );
            await probe.capture('keyboard');
            tester.view.viewInsets = const FakeViewPadding();
            await tester.pumpAndSettle();
            expect(password.value, passwordValue);
          }
          await press('auth.password_reset.confirm');
          expect(dialog, findsNothing);
          expect(auth.confirmed, [
            {
              'account': 'synthetic@example.test',
              'email': 'synthetic@example.test',
              'code': '123456',
              'password': 'synthetic-password',
            },
          ]);
          final reopen = find.text(I18n.tr('auth.forgot_password'));
          await probe.reveal(reopen);
          await tester.tap(reopen);
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(field(0)).controller!.text, isEmpty);
          final cancel = find.descendant(
            of: dialog,
            matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
          );
          await probe.reveal(cancel);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(dialog, findsNothing);
          expect(auth.requested.length, 1);
          expect(auth.confirmed.length, 1);
          await probe.finish();
        });
      }
    }
  }
}
