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
final _sampleDate = DateTime(2026, 5, 15);
const _expectedByPattern = <String, String>{
  'yyyy-MM-dd': '2026-05-15',
  'MM/dd/yyyy': '05/15/2026',
  'dd/MM/yyyy': '15/05/2026',
  'yyyy年M月d日': '2026年5月15日',
};

Future<PreferencesProvider> _providerWithStore(_ControlledStore store) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  SharedPreferencesStorePlatform.instance = store;
  final provider = PreferencesProvider();
  addTearDown(provider.dispose);
  await provider.loadFromStorage();
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
    'all four supported date formats persist and format the same civil day',
    () async {
      for (final entry in _expectedByPattern.entries) {
        final store = _ControlledStore();
        final provider = await _providerWithStore(store);

        await provider.setDateFormat(entry.key);

        expect(provider.dateFormat, entry.key);
        expect(provider.formatDate(_sampleDate), entry.value);
        expect((await _preferences()).getString(_dateFormatKey), entry.key);
      }
    },
  );

  test(
    'unsupported and malformed stored values load the default format',
    () async {
      final invalidStoredValues = <Object>['yyyy/MM/dd', '', 42, true];
      for (final value in invalidStoredValues) {
        final store = _ControlledStore(
          initialData: <String, Object>{_platformDateFormatKey: value},
        );
        final provider = await _providerWithStore(store);

        expect(
          provider.dateFormat,
          I18nDateFormat.defaultPattern,
          reason: '$value',
        );
        expect(
          provider.formatDate(_sampleDate),
          '2026-05-15',
          reason: '$value',
        );
      }
    },
  );

  test(
    'invalid setter inputs persist the normalized default pattern',
    () async {
      for (final input in ['yyyy/MM/dd', '']) {
        final store = _ControlledStore();
        final provider = await _providerWithStore(store);

        await provider.setDateFormat(input);

        expect(provider.dateFormat, I18nDateFormat.defaultPattern);
        expect(provider.formatDate(_sampleDate), '2026-05-15');
        expect(
          (await _preferences()).getString(_dateFormatKey),
          I18nDateFormat.defaultPattern,
        );
      }
    },
  );

  test(
    'rapid A-B-A date format writes end with matching state and storage',
    () async {
      final store = _ControlledStore()..holdKey = _platformDateFormatKey;
      final provider = await _providerWithStore(store);
      final first = provider.setDateFormat('MM/dd/yyyy');
      await store.started.future;
      final second = provider.setDateFormat('dd/MM/yyyy');
      final third = provider.setDateFormat('MM/dd/yyyy');
      expect(store.values, ['MM/dd/yyyy']);

      store.release.complete();
      await Future.wait([first, second, third]);

      expect(store.values, ['MM/dd/yyyy', 'dd/MM/yyyy', 'MM/dd/yyyy']);
      expect(provider.dateFormat, 'MM/dd/yyyy');
      expect(provider.formatDate(_sampleDate), '05/15/2026');
      expect((await _preferences()).getString(_dateFormatKey), 'MM/dd/yyyy');
    },
  );

  test(
    'a rejected date format write restores provider state and storage',
    () async {
      final store = _ControlledStore()..rejectKeyOnce = _platformDateFormatKey;
      final provider = await _providerWithStore(store);
      final changedKeys = <String>{};
      provider.onChangedKeys = changedKeys.addAll;

      await expectLater(provider.setDateFormat('MM/dd/yyyy'), throwsStateError);

      expect(provider.dateFormat, I18nDateFormat.defaultPattern);
      expect(provider.formatDate(_sampleDate), '2026-05-15');
      expect((await _preferences()).getString(_dateFormatKey), isNull);
      expect(changedKeys, isEmpty);
    },
  );

  test(
    'queued old account format writes cannot overwrite the next account',
    () async {
      final store = _ControlledStore()..holdKey = _platformDateFormatKey;
      final provider = await _providerWithStore(store);
      final oldIssued = provider.setDateFormat('MM/dd/yyyy');
      await store.started.future;
      final oldQueued = provider.setDateFormat('dd/MM/yyyy');

      // Account cleanup resets this provider before draining writes. The first
      // issued write is allowed to finish its platform call, while its queued
      // sibling must be discarded by the generation boundary.
      provider.resetLocalState();
      final boundary = AccountLocalDataCleaner.runPreferenceBoundary<void>(
        AccountLocalDataCleaner.clearSharedPreferences,
      );
      store.release.complete();
      await Future.wait([oldIssued, oldQueued, boundary]);

      expect(provider.dateFormat, I18nDateFormat.defaultPattern);
      final newAccountWrite = provider.setDateFormat('yyyy年M月d日');
      await newAccountWrite;

      expect(store.values, ['MM/dd/yyyy', 'yyyy年M月d日']);
      expect(provider.dateFormat, 'yyyy年M月d日');
      expect(provider.formatDate(_sampleDate), '2026年5月15日');
      expect((await _preferences()).getString(_dateFormatKey), 'yyyy年M月d日');
    },
  );
}

class _ControlledStore extends InMemorySharedPreferencesStore {
  _ControlledStore({Map<String, Object> initialData = const <String, Object>{}})
    : super.withData(initialData);

  String? rejectKeyOnce;
  String? holdKey;
  final started = Completer<void>();
  final release = Completer<void>();
  final values = <Object>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == holdKey) {
      values.add(value);
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
