import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/lock_screen_ui_copy.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/lock_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _submitKey = ValueKey<String>('lock_screen_submit');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocale previousLocale;

  setUp(() {
    previousLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    I18n.setLocale(previousLocale);
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final pin in <String>['01234', '0012345']) {
    testWidgets(
      'LockScreen explicitly verifies a ${pin.length}-digit PIN preserving leading zeroes',
      (tester) async {
        final fixture = await _pumpLockedScreen(tester, correctPin: pin);

        await _enterPin(tester, fixture, pin);
        expect(fixture.lock.verifyAttempts, isEmpty);
        expect(fixture.lock.isLocked, isTrue);

        await _submitPin(tester);

        expect(fixture.lock.verifyAttempts, isNotEmpty);
        expect(
          fixture.lock.verifyAttempts.every((attempt) => attempt == pin),
          isTrue,
        );
        expect(fixture.lock.isLocked, isFalse);
        expect(
          await _readLockStorage(fixture.preferences),
          fixture.storageBefore,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'LockScreen does not verify below four digits or accept a ninth digit',
    (tester) async {
      const pin = '24681357';
      final fixture = await _pumpLockedScreen(tester, correctPin: pin);

      for (final digit in pin.substring(0, 3).split('')) {
        await _tapDigit(tester, digit);
        expect(fixture.lock.verifyAttempts, isEmpty);
      }
      expect(fixture.lock.isLocked, isTrue);

      final submitBeforeMinimum = find.byKey(_submitKey);
      if (submitBeforeMinimum.evaluate().isNotEmpty) {
        await tester.tap(submitBeforeMinimum);
        await tester.pumpAndSettle();
      }
      expect(fixture.lock.verifyAttempts, isEmpty);
      expect(fixture.lock.isLocked, isTrue);

      for (final digit in pin.substring(3).split('')) {
        await _tapDigit(tester, digit);
        expect(fixture.lock.verifyAttempts, isEmpty);
      }
      expect(_visiblePinDotCount(tester), 8);

      await _tapDigit(tester, '9');
      expect(fixture.lock.verifyAttempts, isEmpty);
      expect(_visiblePinDotCount(tester), 8);

      await _submitPin(tester);
      expect(
        fixture.lock.verifyAttempts.every((attempt) => attempt == pin),
        isTrue,
      );
      expect(fixture.lock.isLocked, isFalse);
      expect(
        await _readLockStorage(fixture.preferences),
        fixture.storageBefore,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'busy verification ignores repeated submit and keypad edits until it completes',
    (tester) async {
      const pin = '58139';
      final fixture = await _pumpLockedScreen(tester, correctPin: pin);
      final verification = Completer<bool>();
      fixture.lock.holdNextVerify(verification);

      await _enterPin(tester, fixture, pin);
      expect(fixture.lock.verifyAttempts, isEmpty);
      await tester.tap(find.byKey(_submitKey));
      await tester.pump();
      expect(fixture.lock.verifyAttempts, [pin]);
      expect(fixture.lock.isLocked, isTrue);
      expect(_visiblePinDotCount(tester), pin.length);

      await tester.tap(find.byKey(_submitKey));
      await tester.pump();
      await tester.tap(find.text('9'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      expect(fixture.lock.verifyAttempts, [pin]);
      expect(_visiblePinDotCount(tester), pin.length);
      expect(fixture.lock.isLocked, isTrue);

      verification.complete(true);
      await tester.pumpAndSettle();
      expect(fixture.lock.isLocked, isFalse);
      expect(fixture.lock.verifyAttempts, [pin]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'held verification completing after LockScreen unmount does not unlock',
    (tester) async {
      const pin = '246813';
      final fixture = await _pumpLockedScreen(tester, correctPin: pin);
      final verification = Completer<bool>();
      fixture.lock.holdNextVerify(verification);

      await _enterPin(tester, fixture, pin);
      await tester.tap(find.byKey(_submitKey));
      await tester.pump();
      expect(fixture.lock.verifyAttempts, [pin]);
      expect(fixture.lock.isLocked, isTrue);
      expect(find.byType(LockScreen), findsOneWidget);

      await tester.pumpWidget(_appWith(fixture, const SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);

      verification.complete(true);
      await tester.pumpAndSettle();
      expect(fixture.lock.verifyAttempts, [pin]);
      expect(fixture.lock.isLocked, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'verify exception shows a failure and resets busy state for retry',
    (tester) async {
      const pin = '013579';
      final fixture = await _pumpLockedScreen(tester, correctPin: pin);
      fixture.lock.failNextVerify(StateError('controlled verify diagnostic'));

      await _enterPin(tester, fixture, pin);
      final textBeforeFailure = _visibleTextValues(tester);
      await _submitPin(tester);

      expect(fixture.lock.verifyAttempts, [pin]);
      expect(fixture.lock.isLocked, isTrue);
      expect(
        _visibleTextValues(tester).difference(textBeforeFailure),
        isNotEmpty,
        reason: 'the failed verify should show a user-visible generic error',
      );
      expect(tester.takeException(), isNull);

      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byIcon(Icons.backspace_outlined));
        await tester.pumpAndSettle();
      }
      expect(fixture.lock.verifyAttempts, [pin]);

      await _enterPin(tester, fixture, pin);
      expect(fixture.lock.verifyAttempts, [pin]);
      await _submitPin(tester);

      expect(fixture.lock.verifyAttempts.length, greaterThan(1));
      expect(
        fixture.lock.verifyAttempts.every((attempt) => attempt == pin),
        isTrue,
      );
      expect(fixture.lock.isLocked, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final enabled in [true, false]) {
    for (final outcome in ['success', 'wrong PIN', 'exception']) {
      testWidgets('LockScreen haptic=$enabled preserves $outcome result', (
        tester,
      ) async {
        const pin = '2468';
        final fixture = await _pumpLockedScreen(
          tester,
          correctPin: pin,
          hapticEnabled: enabled,
        );
        final calls = _recordHaptics();
        if (outcome == 'exception') {
          fixture.lock.failNextVerify(StateError('controlled verification'));
        }
        await _enterPin(tester, fixture, outcome == 'wrong PIN' ? '1234' : pin);
        await _submitPin(tester);
        expect(fixture.lock.isLocked, outcome != 'success');
        expect(
          calls,
          enabled
              ? [
                  outcome == 'success'
                      ? 'HapticFeedbackType.lightImpact'
                      : 'HapticFeedbackType.heavyImpact',
                ]
              : isEmpty,
        );
        if (outcome != 'success') {
          expect(
            find.text(
              LockScreenUiCopy.errorMessage(
                outcome == 'wrong PIN'
                    ? LockScreenError.wrongPin
                    : LockScreenError.verificationFailed,
              ),
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final boundary in ['relock', 'account', 'preferences', 'unmount']) {
    testWidgets('Held LockScreen result stays silent after $boundary', (
      tester,
    ) async {
      const pin = '2468';
      final fixture = await _pumpLockedScreen(
        tester,
        correctPin: pin,
        hapticEnabled: true,
      );
      final calls = _recordHaptics();
      final held = Completer<bool>();
      fixture.lock.holdNextVerify(held);
      await _enterPin(tester, fixture, pin);
      await tester.tap(find.byKey(_submitKey));
      await tester.pump();
      expect(fixture.lock.verifyAttempts, [pin]);
      switch (boundary) {
        case 'relock':
          fixture.lock.lock();
        case 'account':
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        case 'preferences':
          fixture.appPreferences!.resetLocalState();
        case 'unmount':
          await tester.pumpWidget(_appWith(fixture, const SizedBox.shrink()));
      }
      await tester.pump();
      held.complete(true);
      await tester.pumpAndSettle();
      expect(fixture.lock.isLocked, isTrue);
      expect(calls, isEmpty);
      expect(
        find.text(LockScreenUiCopy.errorMessage(LockScreenError.wrongPin)),
        findsNothing,
      );
      expect(find.text(LockScreenUiCopy.failedRetry), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Held LockScreen reads haptic preference after verification', (
    tester,
  ) async {
    const pin = '2468';
    final fixture = await _pumpLockedScreen(
      tester,
      correctPin: pin,
      hapticEnabled: true,
    );
    final calls = _recordHaptics();
    final held = Completer<bool>();
    fixture.lock.holdNextVerify(held);
    await _enterPin(tester, fixture, pin);
    await tester.tap(find.byKey(_submitKey));
    await tester.pump();
    await tester.runAsync(() => fixture.appPreferences!.setHaptic(false));
    held.complete(true);
    await tester.pumpAndSettle();
    expect(fixture.lock.isLocked, isFalse);
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Late LockScreen verification exception after unmount is silent',
    (tester) async {
      const pin = '2468';
      final fixture = await _pumpLockedScreen(tester, correctPin: pin);
      final calls = _recordHaptics();
      final held = Completer<bool>();
      fixture.lock.holdNextVerify(held);
      await _enterPin(tester, fixture, pin);
      await tester.tap(find.byKey(_submitKey));
      await tester.pump();
      await tester.pumpWidget(_appWith(fixture, const SizedBox.shrink()));
      held.completeError(StateError('late verification'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(fixture.lock.isLocked, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in <double>[1.6, 2.0]) {
    testWidgets(
      'LockScreen keypad and submit remain usable in short landscape at ${scale}x text with insets',
      (tester) async {
        const pin = '2468';
        final fixture = await _pumpLockedScreen(
          tester,
          correctPin: pin,
          surfaceSize: const Size(640, 320),
          textScale: scale,
          withInsets: true,
        );

        expect(tester.takeException(), isNull);
        for (final digit in '0123456789'.split('')) {
          expect(find.text(digit), findsOneWidget);
        }
        expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);

        await _enterPin(tester, fixture, pin);
        expect(fixture.lock.verifyAttempts, isEmpty);
        expect(find.byKey(_submitKey), findsOneWidget);
        await _submitPin(tester);

        expect(fixture.lock.isLocked, isFalse);
        expect(
          fixture.lock.verifyAttempts.every((attempt) => attempt == pin),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<_LockFixture> _pumpLockedScreen(
  WidgetTester tester, {
  required String correctPin,
  Size surfaceSize = const Size(320, 844),
  double? textScale,
  bool withInsets = false,
  bool? hapticEnabled,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  if (withInsets) {
    tester.view.viewPadding = const FakeViewPadding(
      left: 16,
      top: 12,
      right: 16,
      bottom: 18,
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 44);
  }
  addTearDown(tester.view.reset);

  final lock = _ControlledAppLockProvider();
  await lock.setAutoLockMinutes(17);
  await lock.onAppLifecycleInactive();
  expect(await lock.setPin(correctPin), isTrue);
  await lock.loadFromStorage();
  lock.lock();
  expect(lock.enabled, isTrue);
  expect(lock.isLocked, isTrue);

  final preferences = await SharedPreferences.getInstance();
  final storageBefore = await _readLockStorage(preferences);
  expect(
    preferences.getKeys().where((key) => key.startsWith('app_lock_')).toSet(),
    {
      'app_lock_pin_hash',
      'app_lock_enabled',
      'app_lock_auto_minutes',
      'app_lock_last_active',
    },
    reason: 'the lock store has no PIN-length metadata',
  );
  expect(storageBefore['app_lock_pin_hash'], isNot(correctPin));
  expect(storageBefore['app_lock_enabled'], isTrue);
  expect(storageBefore['app_lock_auto_minutes'], 17);

  final theme = ThemeProvider();
  await theme.loadFromStorage();
  final appPreferences = hapticEnabled == null ? null : PreferencesProvider();
  if (appPreferences != null) {
    await appPreferences.loadFromStorage();
    await appPreferences.setHaptic(hapticEnabled!);
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    lock.dispose();
    theme.dispose();
    appPreferences?.dispose();
  });

  final fixture = _LockFixture(
    lock: lock,
    theme: theme,
    preferences: preferences,
    storageBefore: storageBefore,
    appPreferences: appPreferences,
  );
  await tester.pumpWidget(_appWith(fixture, _screenWithScale(textScale)));
  await tester.pumpAndSettle();
  expect(find.byType(LockScreen), findsOneWidget);
  expect(lock.isLocked, isTrue);
  expect(lock.verifyAttempts, isEmpty);
  expect(tester.takeException(), isNull);

  return fixture;
}

Widget _screenWithScale(double? textScale) {
  final child = const LockScreen();
  if (textScale == null) return child;
  return Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child,
    ),
  );
}

Widget _appWith(_LockFixture fixture, Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AppLockProvider>.value(value: fixture.lock),
    ChangeNotifierProvider<ThemeProvider>.value(value: fixture.theme),
    if (fixture.appPreferences != null)
      ChangeNotifierProvider<PreferencesProvider>.value(
        value: fixture.appPreferences!,
      ),
  ],
  child: MaterialApp(home: child),
);

Future<void> _enterPin(
  WidgetTester tester,
  _LockFixture fixture,
  String pin,
) async {
  final attemptsBeforeTyping = List<String>.of(fixture.lock.verifyAttempts);
  for (final digit in pin.split('')) {
    await _tapDigit(tester, digit);
    expect(
      fixture.lock.verifyAttempts,
      attemptsBeforeTyping,
      reason: 'typing digits must not invoke verify',
    );
  }
}

Future<void> _tapDigit(WidgetTester tester, String digit) async {
  final key = find.text(digit);
  expect(key, findsOneWidget);
  await tester.ensureVisible(key);
  await tester.pumpAndSettle();
  await tester.tap(key);
  await tester.pumpAndSettle();
}

Future<void> _submitPin(WidgetTester tester) async {
  final submit = find.byKey(_submitKey);
  expect(submit, findsOneWidget);
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

int _visiblePinDotCount(WidgetTester tester) {
  return find
      .byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'lock_screen_pin_dot_',
            ),
        description: 'visible PIN entry indicators',
      )
      .evaluate()
      .length;
}

Set<String> _visibleTextValues(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((widget) => widget.data)
    .whereType<String>()
    .toSet();

Future<Map<String, Object?>> _readLockStorage(
  SharedPreferences preferences,
) async => {
  'app_lock_pin_hash': preferences.getString('app_lock_pin_hash'),
  'app_lock_enabled': preferences.getBool('app_lock_enabled'),
  'app_lock_auto_minutes': preferences.getInt('app_lock_auto_minutes'),
  'app_lock_last_active': preferences.getString('app_lock_last_active'),
};

class _ControlledAppLockProvider extends AppLockProvider {
  final List<String> verifyAttempts = [];
  final List<Future<bool> Function(String pin)> _queuedVerifications = [];

  int get verifyCalls => verifyAttempts.length;

  void holdNextVerify(Completer<bool> result) {
    _queuedVerifications.add((_) => result.future);
  }

  void failNextVerify(Object error) {
    _queuedVerifications.add((_) => Future<bool>.error(error));
  }

  @override
  Future<bool> verify(String pin) {
    verifyAttempts.add(pin);
    if (_queuedVerifications.isNotEmpty) {
      return _queuedVerifications.removeAt(0)(pin);
    }
    return super.verify(pin);
  }
}

class _LockFixture {
  const _LockFixture({
    required this.lock,
    required this.theme,
    required this.preferences,
    required this.storageBefore,
    this.appPreferences,
  });

  final _ControlledAppLockProvider lock;
  final ThemeProvider theme;
  final SharedPreferences preferences;
  final Map<String, Object?> storageBefore;
  final PreferencesProvider? appPreferences;
}

List<String> _recordHaptics() {
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      calls.add(call.arguments as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}
