// In-memory auth outcomes only; no real login, mail or registration.
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

class _FeedbackAuth extends AuthProvider {
  String maintenance = '';
  int codeRequests = 0;
  int loginRequests = 0;
  Map<String, dynamic> codeResult = {};
  @override
  bool get maintenanceMode => true;
  @override
  String get maintenanceMessage => maintenance;
  @override
  Future<void> login({
    required String username,
    required String password,
  }) async {
    loginRequests++;
    throw const ApiException('Invalid credentials');
  }

  @override
  Future<Map<String, dynamic>> sendEmailCode({
    required String email,
    String purpose = 'login',
  }) async {
    codeRequests++;
    return codeResult;
  }

  void setMaintenance(String value) {
    maintenance = value;
    notifyListeners();
  }
}

void _feedbackPresent(RouteRenderProbe probe, String key) {
  if (find.text(I18n.tr(key)).evaluate().isEmpty) {
    probe.errors.add('$key remains in previous locale');
  }
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'login-feedback-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final auth = _FeedbackAuth();
          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: const LoginScreen(),
          );
          final probe = RouteRenderProbe(tester, boundary, name);
          final state = tester.state(find.byType(LoginScreen));
          await probe.text(
            find.text(I18n.tr('auth.maintenance')),
            role: 'maintenance notice',
          );
          await probe.capture('maintenance');
          auth.setMaintenance('Synthetic server notice 原文');
          await tester.pumpAndSettle();
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          await probe.text(
            find.text('Synthetic server notice 原文'),
            role: 'server maintenance notice',
          );
          auth.setMaintenance('');
          await tester.pumpAndSettle();
          await probe.text(
            find.text(I18n.tr('auth.maintenance')),
            role: 'live maintenance notice',
          );
          Future<void> press(Finder button) async {
            await probe.reveal(button);
            await tester.tap(button);
            await tester.pumpAndSettle();
          }

          final submit = find.widgetWithText(
            FilledButton,
            I18n.tr('auth.login'),
          );
          await press(submit);
          await probe.text(
            find.text(I18n.tr('auth.error.account_required')),
            role: 'local account error',
          );
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          _feedbackPresent(probe, 'auth.error.account_required');
          final fields = find.byType(TextField);
          final account = tester.widget<TextField>(fields.first).controller!;
          final password = tester.widget<TextField>(fields.last).controller!;
          account.text = 'synthetic-user';
          account.selection = const TextSelection(
            baseOffset: 1,
            extentOffset: 4,
          );
          final accountValue = account.value;
          password.text = 'synthetic-password';
          await press(find.widgetWithText(FilledButton, I18n.tr('auth.login')));
          expect(auth.loginRequests, 1);
          expect(password.text, isEmpty);
          expect(account.value, accountValue);
          await probe.text(
            find.text(I18n.tr('auth.error.invalid_credentials')),
            role: 'invalid credentials',
          );
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          _feedbackPresent(probe, 'auth.error.invalid_credentials');
          await press(find.text(I18n.tr('auth.email_code_login')));
          account.text = 'synthetic@example.test';
          await tester.pump();
          await press(find.widgetWithText(FilledButton, I18n.tr('auth.send')));
          expect(auth.codeRequests, 1);
          await probe.text(
            find.text(I18n.tr('auth.email_code.sent')),
            role: 'default code success',
          );
          await probe.capture('code-success');
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          _feedbackPresent(probe, 'auth.email_code.sent');
          expect(auth.codeRequests, 1);
          await tester.pump(const Duration(seconds: 61));
          await tester.pumpAndSettle();
          auth.codeResult = {
            'message': 'Synthetic published text 原文',
            'dev_code': '009812',
          };
          await press(find.widgetWithText(FilledButton, I18n.tr('auth.send')));
          expect(
            find.text(
              'Synthetic published text 原文 ${I18n.tr('auth.email_code.code_prefix')}009812',
            ),
            findsOneWidget,
          );
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          if (find
              .text(
                'Synthetic published text 原文 ${I18n.tr('auth.email_code.code_prefix')}009812',
              )
              .evaluate()
              .isEmpty) {
            probe.errors.add(
              'developer code prefix remains in previous locale',
            );
          }
          expect(account.text, 'synthetic@example.test');
          expect(tester.state(find.byType(LoginScreen)), same(state));
          expect(auth.codeRequests, 2);
          expect(auth.loginRequests, 1);
          await probe.capture('retained-live');
          await probe.finish();
        });
      }
    }
  }
}
