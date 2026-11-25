import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pinWrongZh = 'PIN 错误';
const _pinWrongEn = 'Incorrect PIN';
const _submitKey = ValueKey<String>('lock_screen_submit');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocale previousLocale;

  setUp(() {
    previousLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    I18n.setLocale(previousLocale);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final pin in <String>['2468', '246813', '24681357']) {
    testWidgets(
      'LockScreen submits a ${pin.length}-digit PIN only after explicit confirmation',
      (tester) async {
        final fixture = await _pumpLockedScreen(tester, correctPin: pin);

        await _enterPrefixWithoutVerification(tester, fixture, pin);
        expect(fixture.lock.isLocked, isTrue);
        expect(fixture.lock.verifyAttempts, isEmpty);
        expect(find.text(_pinWrongZh), findsNothing);

        await _submitPin(tester);

        expect(fixture.lock.verifyAttempts, isNotEmpty);
        expect(
          fixture.lock.verifyAttempts.every((attempt) => attempt == pin),
          isTrue,
          reason: 'only the complete PIN should reach verify',
        );
        expect(fixture.lock.isLocked, isFalse);
        expect(fixture.lock.enabled, isTrue);
        expect(
          await _readLockStorage(fixture.preferences),
          fixture.storageBefore,
        );

        final verifyCallsAfterUnlock = fixture.lock.verifyCalls;
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expect(fixture.lock.verifyCalls, verifyCallsAfterUnlock);
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
    'wrong submitted PIN remains locked and its error follows zh-en-zh without retries or storage writes',
    (tester) async {
      const correctPin = '246813';
      const wrongPin = '135790';
      final fixture = await _pumpLockedScreen(tester, correctPin: correctPin);

      await _enterPrefixWithoutVerification(tester, fixture, wrongPin);
      expect(fixture.lock.verifyCalls, 0);
      expect(fixture.lock.isLocked, isTrue);
      expect(find.text(_pinWrongZh), findsNothing);

      await _submitPin(tester);
      expect(fixture.lock.verifyAttempts, [wrongPin]);
      expect(fixture.lock.verifyCalls, 1);
      expect(fixture.lock.isLocked, isTrue);
      expect(find.text(_pinWrongZh), findsOneWidget);
      expect(
        await _readLockStorage(fixture.preferences),
        fixture.storageBefore,
      );

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text(_pinWrongEn), findsOneWidget);
      expect(find.text(_pinWrongZh), findsNothing);
      expect(fixture.lock.verifyAttempts, [wrongPin]);
      expect(fixture.lock.isLocked, isTrue);
      expect(
        await _readLockStorage(fixture.preferences),
        fixture.storageBefore,
      );

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(find.text(_pinWrongZh), findsOneWidget);
      expect(find.text(_pinWrongEn), findsNothing);
      expect(fixture.lock.verifyAttempts, [wrongPin]);
      expect(fixture.lock.isLocked, isTrue);
      expect(
        await _readLockStorage(fixture.preferences),
        fixture.storageBefore,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_LockFixture> _pumpLockedScreen(
  WidgetTester tester, {
  required String correctPin,
}) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final lock = _RecordingAppLockProvider();
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
  expect(storageBefore['app_lock_last_active'], isA<String>());

  final theme = ThemeProvider();
  await theme.loadFromStorage();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    lock.dispose();
    theme.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppLockProvider>.value(value: lock),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ],
      child: const MaterialApp(home: LockScreen()),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(LockScreen), findsOneWidget);
  expect(lock.isLocked, isTrue);
  expect(lock.verifyAttempts, isEmpty);
  expect(tester.takeException(), isNull);

  return _LockFixture(
    lock: lock,
    preferences: preferences,
    storageBefore: storageBefore,
  );
}

Future<void> _enterPrefixWithoutVerification(
  WidgetTester tester,
  _LockFixture fixture,
  String pin,
) async {
  final firstFour = pin.substring(0, 4);
  final firstFourDigits = firstFour.split('');
  for (var index = 0; index < firstFourDigits.length; index++) {
    final digit = firstFourDigits[index];
    await _tapDigit(tester, digit);
    if (index < 3) {
      expect(fixture.lock.verifyCalls, 0);
      expect(fixture.lock.isLocked, isTrue);
    }
  }

  expect(
    find.byKey(_submitKey),
    findsOneWidget,
    reason: 'a valid 4–8 digit entry needs an explicit submit action',
  );
  expect(
    fixture.lock.verifyCalls,
    0,
    reason: 'entering the fourth digit must not invoke verify',
  );

  await tester.tap(find.byIcon(Icons.backspace_outlined));
  await tester.pumpAndSettle();
  expect(
    fixture.lock.verifyCalls,
    0,
    reason: 'deleting a digit must not invoke verify',
  );
  expect(fixture.lock.isLocked, isTrue);

  await _tapDigit(tester, firstFour.substring(3));
  expect(fixture.lock.verifyCalls, 0);
  expect(find.byKey(_submitKey), findsOneWidget);
  expect(fixture.lock.isLocked, isTrue);

  for (final digit in pin.substring(4).split('')) {
    await _tapDigit(tester, digit);
    expect(
      fixture.lock.verifyCalls,
      0,
      reason: 'PIN entry prefixes must not invoke verify',
    );
    expect(fixture.lock.isLocked, isTrue);
  }
}

Future<void> _tapDigit(WidgetTester tester, String digit) async {
  final key = find.text(digit);
  expect(key, findsOneWidget);
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

Future<Map<String, Object?>> _readLockStorage(
  SharedPreferences preferences,
) async => {
  'app_lock_pin_hash': preferences.getString('app_lock_pin_hash'),
  'app_lock_enabled': preferences.getBool('app_lock_enabled'),
  'app_lock_auto_minutes': preferences.getInt('app_lock_auto_minutes'),
  'app_lock_last_active': preferences.getString('app_lock_last_active'),
};

class _RecordingAppLockProvider extends AppLockProvider {
  final List<String> verifyAttempts = [];

  int get verifyCalls => verifyAttempts.length;

  @override
  Future<bool> verify(String pin) async {
    verifyAttempts.add(pin);
    return super.verify(pin);
  }
}

class _LockFixture {
  const _LockFixture({
    required this.lock,
    required this.preferences,
    required this.storageBefore,
  });

  final _RecordingAppLockProvider lock;
  final SharedPreferences preferences;
  final Map<String, Object?> storageBefore;
}
