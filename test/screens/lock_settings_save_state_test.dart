import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/lock_settings_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _failureEn = 'Could not save settings. Please try again.';
const _failureZh = '无法保存设置，请重试';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'failed PIN save reports failure, follows locale and permits retry',
    (tester) async {
      final lock = _ControlledLock()..rejectPin = true;
      await _mount(tester, lock);
      await _toggle(tester);
      await _enter(tester, '2468');
      await _enter(tester, '2468');
      expect(lock.enabled, isFalse);
      expect(find.text(_failureZh), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text(_failureEn), findsOneWidget);
      expect(find.text(_failureZh), findsNothing);
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(find.text(_failureZh), findsOneWidget);
      lock.rejectPin = false;
      await _toggle(tester);
      await _enter(tester, '2468');
      await _enter(tester, '2468');
      expect(lock.enabled, isTrue);
      expect(lock.pinSaves, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'disable distinguishes wrong PIN and failed persistence and verifies through one operation',
    (tester) async {
      final lock = _ControlledLock();
      await lock.setPin('2468');
      await _mount(tester, lock);
      await _toggle(tester);
      await _enter(tester, '1111');
      expect(lock.disableCalls, 1);
      expect(
        lock.uiVerifyCalls,
        0,
        reason: 'disable owns the sole PIN verification',
      );
      expect(find.text(I18n.tr('app_lock.pin_wrong')), findsOneWidget);
      lock.rejectDisable = true;
      await _toggle(tester);
      await _enter(tester, '2468');
      expect(lock.enabled, isTrue);
      expect(find.text(_failureZh), findsOneWidget);
      lock.rejectDisable = false;
      await _toggle(tester);
      await _enter(tester, '2468');
      expect(lock.enabled, isFalse);
      expect(lock.disableCalls, 3);
      expect(lock.uiVerifyCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'timeout rejection preserves the old selection and permits retry',
    (tester) async {
      final lock = _ControlledLock();
      await lock.setPin('2468');
      await _mount(tester, lock);
      lock.timeout = Completer<void>();
      await _selectTimeout(tester, '1 小时');
      expect(lock.autoLockMinutes, 5);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      lock.timeout!.completeError(StateError('injected failure'));
      await tester.pumpAndSettle();
      expect(find.text(_failureEn), findsOneWidget);
      expect(lock.autoLockMinutes, 5);
      lock.timeout = null;
      await _selectTimeout(tester, '1 hour');
      expect(lock.autoLockMinutes, 60);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'accepted save completes after route disposal without showing feedback',
    (tester) async {
      final lock = _ControlledLock();
      await _mount(tester, lock);
      await _toggle(tester);
      await _enter(tester, '2468');
      lock.pin = Completer<void>();
      await _enter(tester, '2468');
      final navigator = Navigator.of(
        tester.element(find.byType(LockSettingsScreen)),
      );
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Replacement')),
        ),
      );
      await tester.pumpAndSettle();
      lock.pin!.complete();
      await tester.pumpAndSettle();
      expect(lock.enabled, isTrue);
      expect(find.text('Replacement'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('lock now retains the settings route', (tester) async {
    final lock = _ControlledLock();
    await lock.setPin('2468');
    await _mount(tester, lock);
    final route = ModalRoute.of(
      tester.element(find.byType(LockSettingsScreen)),
    )!;
    final action = find.text(I18n.tr('app_lock.lock_now'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(lock.isLocked, isTrue);
    expect(route.isCurrent, isTrue);
    expect(find.byType(LockSettingsScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _mount(WidgetTester tester, _ControlledLock lock) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(lock.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppLockProvider>.value(value: lock),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(home: const LockSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(Switch).first);
  await tester.tap(find.byType(Switch).first);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String pin) async {
  await tester.enterText(find.byType(TextField).last, pin);
  await tester.tap(
    find.widgetWithText(FilledButton, I18n.tr('action.confirm')),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectTimeout(WidgetTester tester, String label) async {
  final title = find.text(I18n.tr('app_lock.auto_lock'));
  await tester.ensureVisible(title);
  await tester.tap(title);
  await tester.pumpAndSettle();
  final option = find.descendant(
    of: find.byType(AppModalSheet),
    matching: find.text(label),
  );
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

class _ControlledLock extends AppLockProvider {
  bool rejectPin = false;
  bool rejectDisable = false;
  int pinSaves = 0;
  int disableCalls = 0;
  int uiVerifyCalls = 0;
  Completer<void>? pin;
  Completer<void>? timeout;

  @override
  Future<bool> setPin(String value) async {
    pinSaves++;
    await pin?.future;
    if (rejectPin) throw StateError('injected failure');
    return super.setPin(value);
  }

  @override
  Future<bool> disable(String value) async {
    disableCalls++;
    if (rejectDisable) throw StateError('injected failure');
    return super.disable(value);
  }

  @override
  Future<bool> verify(String value) async {
    uiVerifyCalls++;
    return super.verify(value);
  }

  @override
  Future<void> setAutoLockMinutes(int minutes) async {
    await timeout?.future;
    return super.setAutoLockMinutes(minutes);
  }
}
