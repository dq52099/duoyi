// Preserve every registration validation branch during retained-copy refactor.
import 'dart:async';

import 'package:duoyi/core/account_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/priority_theme_fixture.dart';

class _ValidationAuth extends AuthProvider {
  final registrations = <Map<String, String?>>[];
  final failure = const ApiException('429: too many requests');
  @override
  bool get registrationEmailRequired => true;
  @override
  bool get inviteCodeRequired => true;
  @override
  Future<void> register({
    required String username,
    required String password,
    String? email,
    String? emailCode,
    String? displayName,
    String? inviteCode,
  }) async {
    registrations.add({
      'username': username,
      'password': password,
      'email': email,
      'code': emailCode,
      'display': displayName,
      'invite': inviteCode,
    });
    throw failure;
  }
}

class _PendingFeedbackAuth extends AuthProvider {
  late Future<Map<String, dynamic>> nextCode;
  int requests = 0;
  @override
  Future<Map<String, dynamic>> sendEmailCode({
    required String email,
    String purpose = 'login',
  }) {
    expect(email, 'synthetic@example.test');
    expect(purpose, 'login');
    requests++;
    return nextCode;
  }
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    testWidgets(
      'login $brand pending feedback locale and disposed completion',
      (tester) async {
        final pending = Completer<Map<String, dynamic>>();
        final auth = _PendingFeedbackAuth()..nextCode = pending.future;
        await mountPriorityFixture(
          tester,
          auth: auth,
          brand: brand,
          locale: AppLocale.zh,
          size: const Size(390, 844),
          scale: 1,
          home: const LoginScreen(),
        );
        await tester.tap(find.text(I18n.tr('auth.email_code_login')));
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(LoginScreen));
        final account = tester
            .widget<TextField>(find.byType(TextField).first)
            .controller!;
        account.text = 'synthetic@example.test';
        account.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
        final value = account.value;
        await tester.pump();
        Future<void> send() async {
          final button = find.widgetWithText(
            FilledButton,
            I18n.tr('auth.send'),
          );
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pump();
        }

        await send();
        I18n.setLocale(AppLocale.en);
        await tester.pump();
        expect(auth.requests, 1);
        expect(tester.state(find.byType(LoginScreen)), same(state));
        expect(account.value, value);
        final failure = const ApiException('too many requests for email code');
        pending.completeError(failure);
        await tester.pumpAndSettle();
        expect(find.text(AccountUiCopy.formatError(failure)), findsOneWidget);
        I18n.setLocale(AppLocale.zh);
        await tester.pump();
        expect(find.text(AccountUiCopy.formatError(failure)), findsOneWidget);
        expect(auth.requests, 1);
        final late = Completer<Map<String, dynamic>>();
        auth.nextCode = late.future;
        await send();
        await tester.pumpWidget(
          const MaterialApp(home: Text('Synthetic destination')),
        );
        late.complete({'message': 'Obsolete synthetic code response'});
        await tester.pumpAndSettle();
        expect(find.text('Synthetic destination'), findsOneWidget);
        expect(find.text('Obsolete synthetic code response'), findsNothing);
        expect(auth.requests, 2);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'registration $brand validation keys retain drafts and submit contract',
      (tester) async {
        final auth = _ValidationAuth();
        await mountPriorityFixture(
          tester,
          auth: auth,
          brand: brand,
          locale: AppLocale.zh,
          size: const Size(390, 844),
          scale: 1,
          home: const LoginScreen(),
        );
        final toRegister = find.byType(TextButton).last;
        await tester.ensureVisible(toRegister);
        await tester.tap(toRegister);
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(LoginScreen));
        final fields = find.byType(TextField);
        expect(fields, findsNWidgets(7));
        final controllers = [
          for (final f in tester.widgetList<TextField>(fields)) f.controller!,
        ];
        Future<void> submit() async {
          final button = find.widgetWithText(
            FilledButton,
            I18n.tr('auth.register'),
          );
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
        }

        Future<void> check(String key) async {
          controllers[0].selection = TextSelection(
            baseOffset: 0,
            extentOffset: controllers[0].text.length,
          );
          final values = controllers.map((c) => c.value).toList();
          await submit();
          expect(find.text(I18n.tr(key)), findsOneWidget);
          I18n.setLocale(
            I18n.current == AppLocale.zh ? AppLocale.en : AppLocale.zh,
          );
          await tester.pump();
          expect(find.text(I18n.tr(key)), findsOneWidget);
          expect(tester.state(find.byType(LoginScreen)), same(state));
          for (var i = 0; i < controllers.length; i++) {
            expect(
              tester.widgetList<TextField>(fields).elementAt(i).controller,
              same(controllers[i]),
            );
            expect(controllers[i].value, values[i]);
          }
          expect(auth.registrations, isEmpty);
        }

        await check('auth.error.username_required');
        controllers[0].text = 'ab';
        await check('auth.error.username_length');
        controllers[0].text = 'user name';
        await check('auth.error.username_no_space');
        controllers[0].text = ' synthetic-user ';
        await check('auth.error.email_required');
        controllers[1].text = 'invalid-email';
        await check('auth.error.email_invalid');
        controllers[1].text = ' synthetic@example.test ';
        await check('auth.error.email_code_required');
        controllers[2].text = ' 123456 ';
        controllers[4].text = '123';
        await check('auth.error.password_short');
        controllers[4].text = 'synthetic-password';
        controllers[5].text = 'different-password';
        await check('auth.error.password_mismatch');
        controllers[5].text = 'synthetic-password';
        await check('auth.error.invite_required');
        controllers[3].text = ' Synthetic nickname ';
        controllers[6].text = ' invite-only-synthetic ';
        await submit();
        expect(auth.registrations, [
          {
            'username': 'synthetic-user',
            'password': 'synthetic-password',
            'email': 'synthetic@example.test',
            'code': '123456',
            'display': 'Synthetic nickname',
            'invite': 'invite-only-synthetic',
          },
        ]);
        expect(
          find.text(AccountUiCopy.formatError(auth.failure)),
          findsOneWidget,
        );
        I18n.setLocale(
          I18n.current == AppLocale.zh ? AppLocale.en : AppLocale.zh,
        );
        await tester.pump();
        expect(
          find.text(AccountUiCopy.formatError(auth.failure)),
          findsOneWidget,
        );
        expect(auth.registrations.length, 1);
        expect(controllers[4].text, 'synthetic-password');
        expect(controllers[5].text, 'synthetic-password');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
