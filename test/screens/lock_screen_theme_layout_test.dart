// Real lock overlay, production priority themes, synthetic verification only.
import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/lock_screen_ui_copy.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

class _ThemeLockPort extends AppLockProvider {
  final attempts = <String>[];
  Completer<void>? pending;
  bool fail = false;

  @override
  bool get enabled => true;
  @override
  bool get isLocked => true;
  @override
  Future<void> unlockWith(String pin, {bool Function()? isCurrent}) async {
    if (isCurrent?.call() == false) return;
    attempts.add(pin);
    await pending?.future;
    if (isCurrent?.call() == false) return;
    if (fail) throw const FormatException('Synthetic verification unavailable');
  }
}

void main() {
  final original = I18n.current;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() {
    I18n.setLocale(original);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'lock-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final lock = _ThemeLockPort();
          addTearDown(lock.dispose);
          final boundary = await mountPriorityFixture(
            tester,
            auth: AuthProvider(),
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: ChangeNotifierProvider<AppLockProvider>.value(
              value: lock,
              child: const Stack(
                fit: StackFit.expand,
                children: [
                  Scaffold(body: Text('Synthetic covered application')),
                  LockScreen(),
                ],
              ),
            ),
          );
          final state = tester.state(find.byType(LockScreen));
          final probe = RouteRenderProbe(tester, boundary, name);
          Future<void> header(String stage) async {
            final theme = tester
                .element(find.byType(LockScreen))
                .read<ThemeProvider>();
            await probe.text(
              find.text(theme.brand.strings.appTitle),
              role: '$stage app title',
            );
            await probe.text(
              find.text(I18n.tr('app_lock.pin_hint_enter')),
              role: '$stage PIN guidance',
            );
            await probe.capture('$stage-header');
          }

          await header('initial');
          for (final digit in '1234567890'.split('')) {
            final finder = find.text(digit);
            await probe.text(finder, role: 'keypad digit $digit');
            final response = find.ancestor(
              of: finder,
              matching: find.byType(InkResponse),
            );
            final size = tester.getSize(response);
            expect(size.width, greaterThanOrEqualTo(48));
            expect(size.height, greaterThanOrEqualTo(48));
          }
          Future<void> digit(String value) async {
            final finder = find.text(value);
            await tester.ensureVisible(finder);
            await tester.tap(finder);
            await tester.pumpAndSettle();
          }

          for (final d in '1234'.split('')) {
            await digit(d);
          }
          expect(lock.attempts, isEmpty);
          final submit = find.byKey(const ValueKey('lock_screen_submit'));
          await probe.text(
            find.text(LockScreenUiCopy.unlock),
            role: 'enabled unlock action',
          );
          await probe.capture('entered');
          final pending = Completer<void>();
          lock.pending = pending;
          await tester.tap(submit);
          await tester.pump();
          expect(lock.attempts, ['1234']);
          expect(find.text(LockScreenUiCopy.busyMessage), findsOneWidget);
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pump();
          expect(tester.state(find.byType(LockScreen)), same(state));
          expect(find.text(LockScreenUiCopy.busyMessage), findsOneWidget);
          expect(tester.widget<FilledButton>(submit).onPressed, isNull);
          expect(lock.attempts, ['1234']);
          pending.complete();
          await tester.pumpAndSettle();
          await probe.text(
            find.text(I18n.tr('app_lock.pin_wrong')),
            role: 'wrong PIN feedback',
          );
          await probe.capture('wrong');
          await header('live');
          final delete = find.byIcon(Icons.backspace_outlined);
          await tester.ensureVisible(delete);
          await tester.tap(delete);
          await tester.pumpAndSettle();
          expect(find.text(I18n.tr('app_lock.pin_wrong')), findsNothing);
          await digit('4');
          lock.pending = null;
          lock.fail = true;
          await tester.ensureVisible(submit);
          await tester.tap(submit);
          await tester.pumpAndSettle();
          expect(lock.attempts, ['1234', '1234']);
          await probe.text(
            find.text(LockScreenUiCopy.failedRetry),
            role: 'verification failure feedback',
          );
          await probe.capture('failure');
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          await probe.text(
            find.text(LockScreenUiCopy.failedRetry),
            role: 'retained verification failure',
          );
          expect(tester.state(find.byType(LockScreen)), same(state));
          expect(lock.attempts, ['1234', '1234']);
          expect(lock.isLocked, isTrue);
          await probe.finish();
        });
      }
    }
  }
}
