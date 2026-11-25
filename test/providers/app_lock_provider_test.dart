import 'dart:async';
import 'dart:io';

import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('拒绝非 4-8 位数字 PIN 且不写入存储', () async {
    final provider = AppLockProvider();

    for (final pin in <String>['abcd', '12a4', '123', '123456789', '12 34']) {
      expect(await provider.setPin(pin), isFalse, reason: pin);
    }

    final prefs = await SharedPreferences.getInstance();
    expect(provider.enabled, isFalse);
    expect(prefs.getString('app_lock_pin_hash'), isNull);
    expect(prefs.getBool('app_lock_enabled'), isNull);
  });

  test('有效 PIN 只保存哈希并按数字 PIN 校验', () async {
    final provider = AppLockProvider();

    expect(await provider.setPin('1234'), isTrue);
    expect(provider.enabled, isTrue);
    expect(provider.isLocked, isFalse);

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('app_lock_pin_hash');
    expect(stored, isNotNull);
    expect(stored, isNot('1234'));
    expect(stored, hasLength(64));
    expect(prefs.getBool('app_lock_enabled'), isTrue);

    expect(await provider.verify('1234'), isTrue);
    expect(await provider.verify('abcd'), isFalse);
    expect(await provider.verify('12a4'), isFalse);
    expect(await provider.verify('9999'), isFalse);
  });

  test('设置页 PIN 输入框限制为数字', () {
    final source = File(
      'lib/screens/lock_settings_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import 'package:flutter/services.dart';"));
    expect(source, contains('FilteringTextInputFormatter.digitsOnly'));
    expect(source, contains(r"RegExp(r'^\d{4,8}$')"));
    expect(source, contains("I18n.tr('app_lock.pin_invalid')"));
    expect(source, contains('try {'));
    final dialogState = source.substring(
      source.indexOf('class _PinInputDialogState'),
    );
    expect(dialogState, contains('void dispose()'));
    expect(dialogState, contains('_controller.dispose();'));
    expect(dialogState, contains('I18n.localeListenable.removeListener'));

    final i18n = File('lib/core/i18n.dart').readAsStringSync();
    expect(i18n, contains("'app_lock.pin_invalid': '需要 4-8 位数字'"));
  });

  for (final transition in ['relock', 'change PIN', 'reload', 'dispose']) {
    test('pending verification cannot unlock after $transition', () async {
      final provider = _HeldVerificationLock();
      await provider.setPin('246813');
      provider.lock();
      final pending = provider.unlockWith('246813');
      expect(provider.verifyCalls, 1);

      switch (transition) {
        case 'relock':
          provider.lock();
        case 'change PIN':
          await provider.setPin('135790');
          provider.lock();
        case 'reload':
          await provider.loadFromStorage();
        case 'dispose':
          provider.dispose();
      }
      provider.verification.complete(true);
      await pending;
      expect(provider.isLocked, isTrue);
      if (transition != 'dispose') provider.dispose();
    });
  }

  test(
    'pending verification requires its initiating screen to remain current',
    () async {
      final provider = _HeldVerificationLock();
      addTearDown(provider.dispose);
      await provider.setPin('246813');
      provider.lock();
      var current = true;
      final pending = provider.unlockWith('246813', isCurrent: () => current);
      current = false;
      provider.verification.complete(true);
      await pending;
      expect(provider.isLocked, isTrue);
      expect(provider.verifyCalls, 1);
    },
  );
}

class _HeldVerificationLock extends AppLockProvider {
  final verification = Completer<bool>();
  int verifyCalls = 0;

  @override
  Future<bool> verify(String pin) {
    verifyCalls++;
    return verification.future;
  }
}
