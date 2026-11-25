import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _dateFormatKey = 'pref_date_format';
const _platformDateFormatKey = 'flutter.pref_date_format';

PreferencesProvider _providerWithStore(_ControlledStore store) {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  SharedPreferencesStorePlatform.instance = store;
  final provider = PreferencesProvider();
  addTearDown(provider.dispose);
  return provider;
}

Future<SharedPreferences> _preferences() => SharedPreferences.getInstance();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async => null;
  });

  tearDown(() async {
    await AccountPreferenceWrites.drain();
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });

  test(
    'readiness starts false, becomes true after load, and reset clears it',
    () async {
      final provider = _providerWithStore(_ControlledStore());

      expect(provider.isStorageLoaded, isFalse);
      final load = provider.loadFromStorage();
      expect(provider.isStorageLoaded, isFalse);
      await load;

      expect(provider.isStorageLoaded, isTrue);
      provider.resetLocalState();
      expect(provider.isStorageLoaded, isFalse);
    },
  );

  test(
    'reload clears readiness until the held timezone read completes',
    () async {
      final provider = _providerWithStore(_ControlledStore());
      await provider.loadFromStorage();
      expect(provider.isStorageLoaded, isTrue);

      final started = Completer<void>();
      final release = Completer<String?>();
      LocalTimezoneResolver.debugSystemTimeZoneReader = () {
        started.complete();
        return release.future;
      };

      final reload = provider.loadFromStorage();
      expect(provider.isStorageLoaded, isFalse);
      await started.future;
      expect(provider.isStorageLoaded, isFalse);

      release.complete('Asia/Tokyo');
      await reload;

      expect(provider.isStorageLoaded, isTrue);
      expect(provider.appTimeZone, 'Asia/Tokyo');
    },
  );

  test(
    'newer same-generation reload wins over a held earlier reload',
    () async {
      final provider = _providerWithStore(_ControlledStore());
      await provider.loadFromStorage();

      final firstStarted = Completer<void>();
      final firstRelease = Completer<String?>();
      final secondStarted = Completer<void>();
      final secondRelease = Completer<String?>();
      var reads = 0;
      LocalTimezoneResolver.debugSystemTimeZoneReader = () {
        if (reads++ == 0) {
          firstStarted.complete();
          return firstRelease.future;
        }
        secondStarted.complete();
        return secondRelease.future;
      };

      final firstReload = provider.loadFromStorage();
      await firstStarted.future;
      final secondReload = provider.loadFromStorage();
      expect(provider.isStorageLoaded, isFalse);

      firstRelease.complete('Asia/Tokyo');
      await firstReload;
      await secondStarted.future;
      expect(provider.isStorageLoaded, isFalse);

      secondRelease.complete('America/Mexico_City');
      await secondReload;

      expect(provider.isStorageLoaded, isTrue);
      expect(provider.appTimeZone, 'America/Mexico_City');
    },
  );

  test('queued setters and reloads preserve submission order', () async {
    final store = _ControlledStore()..holdKey = _platformDateFormatKey;
    final provider = _providerWithStore(store);
    await provider.loadFromStorage();

    final firstSetter = provider.setDateFormat('MM/dd/yyyy');
    await store.started.future;
    final reloadAfterSetter = provider.loadFromStorage();
    expect(provider.isStorageLoaded, isFalse);
    store.release.complete();
    await Future.wait([firstSetter, reloadAfterSetter]);

    expect(provider.isStorageLoaded, isTrue);
    expect(provider.dateFormat, 'MM/dd/yyyy');
    expect((await _preferences()).getString(_dateFormatKey), 'MM/dd/yyyy');

    final timezoneStarted = Completer<void>();
    final timezoneRelease = Completer<String?>();
    LocalTimezoneResolver.debugSystemTimeZoneReader = () {
      timezoneStarted.complete();
      return timezoneRelease.future;
    };
    final reloadBeforeSetter = provider.loadFromStorage();
    await timezoneStarted.future;
    final lastSetter = provider.setDateFormat('dd/MM/yyyy');
    expect(provider.isStorageLoaded, isFalse);

    timezoneRelease.complete('Asia/Shanghai');
    await Future.wait([reloadBeforeSetter, lastSetter]);

    expect(provider.isStorageLoaded, isTrue);
    expect(provider.dateFormat, 'dd/MM/yyyy');
    expect((await _preferences()).getString(_dateFormatKey), 'dd/MM/yyyy');
  });

  test(
    'rejected write recovers directly and reports rolled-back readiness',
    () async {
      final store = _ControlledStore()..rejectKeyOnce = _platformDateFormatKey;
      final provider = _providerWithStore(store);
      await provider.loadFromStorage();

      final recoveryStarted = Completer<void>();
      final recoveryRelease = Completer<String?>();
      LocalTimezoneResolver.debugSystemTimeZoneReader = () {
        recoveryStarted.complete();
        return recoveryRelease.future;
      };

      final write = provider.setDateFormat('MM/dd/yyyy');
      await recoveryStarted.future;
      expect(provider.isStorageLoaded, isFalse);

      recoveryRelease.complete('Asia/Shanghai');
      await expectLater(write, throwsStateError);

      expect(provider.isStorageLoaded, isTrue);
      expect(provider.dateFormat, I18nDateFormat.defaultPattern);
      expect((await _preferences()).getString(_dateFormatKey), isNull);
    },
  );

  test('reset invalidates a held reload without restoring readiness', () async {
    final provider = _providerWithStore(_ControlledStore());
    await provider.loadFromStorage();

    final started = Completer<void>();
    final release = Completer<String?>();
    LocalTimezoneResolver.debugSystemTimeZoneReader = () {
      started.complete();
      return release.future;
    };
    final reload = provider.loadFromStorage();
    await started.future;

    provider.resetLocalState();
    expect(provider.isStorageLoaded, isFalse);
    release.complete('Asia/Tokyo');
    await reload;

    expect(provider.isStorageLoaded, isFalse);
    expect(provider.dateFormat, I18nDateFormat.defaultPattern);
  });

  test(
    'account generation change invalidates a held reload readiness',
    () async {
      final provider = _providerWithStore(_ControlledStore());
      await provider.loadFromStorage();

      final started = Completer<void>();
      final release = Completer<String?>();
      LocalTimezoneResolver.debugSystemTimeZoneReader = () {
        started.complete();
        return release.future;
      };
      final reload = provider.loadFromStorage();
      await started.future;

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      expect(provider.isStorageLoaded, isFalse);
      release.complete('Asia/Tokyo');
      await reload;

      expect(provider.isStorageLoaded, isFalse);
    },
  );
}

class _ControlledStore extends InMemorySharedPreferencesStore {
  _ControlledStore() : super.withData(<String, Object>{});

  String? rejectKeyOnce;
  String? holdKey;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == holdKey) {
      if (!started.isCompleted) {
        started.complete();
        await release.future;
      }
    }
    if (key == rejectKeyOnce) {
      rejectKeyOnce = null;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}
