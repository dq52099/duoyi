import 'dart:async';

import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late AppLockProvider lock;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    lock = AppLockProvider();
  });
  tearDown(() => lock.dispose());

  for (final failedKey in [
    'flutter.app_lock_pin_hash',
    'flutter.app_lock_enabled',
  ]) {
    for (final throwFailure in [false, true]) {
      test(
        'PIN replacement restores the previous credential after $failedKey / throw $throwFailure',
        () async {
          await lock.setPin('02468');
          lock.lock();
          final prefs = await SharedPreferences.getInstance();
          final originalHash = prefs.getString('app_lock_pin_hash');
          var notices = 0;
          lock.addListener(() => notices++);
          store.failedKey = failedKey;
          store.throwFailure = throwFailure;
          await expectLater(lock.setPin('135790'), throwsStateError);
          expect(prefs.getString('app_lock_pin_hash'), originalHash);
          expect(prefs.getBool('app_lock_enabled'), isTrue);
          expect(await lock.verify('02468'), isTrue);
          expect(await lock.verify('135790'), isFalse);
          expect(lock.enabled, isTrue);
          expect(lock.isLocked, isTrue);
          expect(notices, 0);
          expect(await lock.setPin('135790'), isTrue);
          expect(await lock.verify('135790'), isTrue);
          expect(
            lock.isLocked,
            isTrue,
            reason: 'changing a PIN is not an unlock',
          );
        },
      );
    }
  }

  test('failed initial enable leaves both credential keys absent', () async {
    store.failedKey = 'flutter.app_lock_enabled';
    await expectLater(lock.setPin('2468'), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_lock_pin_hash'), isNull);
    expect(prefs.getBool('app_lock_enabled'), isNull);
    expect(lock.enabled, isFalse);
  });

  test(
    'failed disable restores enabled state and credential; wrong PIN is distinct',
    () async {
      await lock.setPin('2468');
      expect(await lock.disable('1111'), isFalse);
      store.failedKey = 'flutter.app_lock_pin_hash';
      await expectLater(lock.disable('2468'), throwsStateError);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('app_lock_enabled'), isTrue);
      expect(await lock.verify('2468'), isTrue);
      expect(lock.enabled, isTrue);
      expect(await lock.disable('2468'), isTrue);
      expect(lock.enabled, isFalse);
      expect(prefs.getString('app_lock_pin_hash'), isNull);
      expect(prefs.getBool('app_lock_enabled'), isFalse);
    },
  );

  test(
    'timeout only updates after acceptance, rejected save permits retry',
    () async {
      await lock.setAutoLockMinutes(17);
      store.holdKey = 'flutter.app_lock_auto_minutes';
      store.failedKey = store.holdKey;
      final saving = lock.setAutoLockMinutes(60);
      final rejection = expectLater(saving, throwsStateError);
      await store.started.future;
      expect(lock.autoLockMinutes, 17);
      store.release.complete();
      await rejection;
      expect(lock.autoLockMinutes, 17);
      expect(
        (await SharedPreferences.getInstance()).getInt('app_lock_auto_minutes'),
        17,
      );
      await lock.setAutoLockMinutes(60);
      expect(lock.autoLockMinutes, 60);
    },
  );

  test('rapid timeout selections persist in submission order', () async {
    store.holdKey = 'flutter.app_lock_auto_minutes';
    final first = lock.setAutoLockMinutes(60);
    await store.started.future;
    final second = lock.setAutoLockMinutes(5);
    store.release.complete();
    await Future.wait([first, second]);
    expect(store.timeoutWrites, [60, 5]);
    expect(lock.autoLockMinutes, 5);
    expect(
      (await SharedPreferences.getInstance()).getInt('app_lock_auto_minutes'),
      5,
    );
  });

  test(
    'verification waits for an entire credential save; a new lock survives',
    () async {
      await lock.setPin('2468');
      store.holdKey = 'flutter.app_lock_pin_hash';
      final saving = lock.setPin('135790');
      await store.started.future;
      var verificationFinished = false;
      final verifying = lock.verify('135790').then((value) {
        verificationFinished = true;
        return value;
      });
      lock.lock();
      await Future<void>.delayed(Duration.zero);
      expect(verificationFinished, isFalse);
      store.release.complete();
      await saving;
      expect(await verifying, isTrue);
      expect(lock.isLocked, isTrue);
    },
  );

  test(
    'reload cancels a held credential replacement before restoring lock state',
    () async {
      await lock.setPin('2468');
      store.holdKey = 'flutter.app_lock_pin_hash';
      final saving = lock.setPin('135790');
      final canceled = expectLater(saving, throwsException);
      await store.started.future;
      final loading = lock.loadFromStorage();
      store.release.complete();
      await canceled;
      await loading;
      expect(lock.isLocked, isTrue);
      expect(await lock.verify('2468'), isTrue);
      expect(await lock.verify('135790'), isFalse);
    },
  );
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  String? failedKey;
  String? holdKey;
  bool throwFailure = false;
  final started = Completer<void>();
  final release = Completer<void>();
  final timeoutWrites = <Object>[];

  bool _shouldFail(String key) {
    if (key != failedKey) return false;
    failedKey = null;
    if (throwFailure) throw StateError('injected storage failure');
    return true;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.app_lock_auto_minutes') timeoutWrites.add(value);
    if (key == holdKey && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    if (_shouldFail(key)) return false;
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (_shouldFail(key)) return false;
    return super.remove(key);
  }
}
