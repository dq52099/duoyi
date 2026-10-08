// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'language changes notify immediately and persist in choice order',
    () async {
      final store = _install({})..blockFirstWrite = true;
      final provider = LocaleProvider();
      addTearDown(provider.dispose);
      final seen = <AppLocale>[];
      provider.addListener(() => seen.add(provider.locale));

      final english = provider.setLocale(AppLocale.en);
      expect(seen, [AppLocale.en]);
      expect(I18n.current, AppLocale.en);
      await store.writeEntered.future;
      final chinese = provider.setLocale(AppLocale.zh);
      expect(seen, [AppLocale.en, AppLocale.zh]);
      expect(I18n.current, AppLocale.zh);
      expect(store.writes, ['en']);
      store.releaseWrite.complete();
      await Future.wait([english, chinese]);

      expect(store.writes, ['en', 'zh']);
      expect((await store.getAll())['flutter.duoyi_locale_v1'], 'zh');
    },
  );

  test(
    'an explicit default choice wins over an in-flight initial load',
    () async {
      final store = _install({'duoyi_locale_v1': 'en'})..blockFirstRead = true;
      final provider = LocaleProvider();
      addTearDown(provider.dispose);
      final load = provider.loadFromStorage();
      await store.readEntered.future;
      final choice = provider.setLocale(AppLocale.zh);
      store.releaseRead.complete();
      await Future.wait([load, choice]);

      expect(provider.locale, AppLocale.zh);
      expect(I18n.current, AppLocale.zh);
      expect((await store.getAll())['flutter.duoyi_locale_v1'], 'zh');
    },
  );

  test('regional preference migration cannot undo a newer choice', () async {
    final store = _install({'duoyi_locale_v1': 'zh_CN'})
      ..blockFirstWrite = true;
    final provider = LocaleProvider();
    addTearDown(provider.dispose);
    final load = provider.loadFromStorage();
    await store.writeEntered.future;
    final choice = provider.setLocale(AppLocale.en);
    store.releaseWrite.complete();
    await Future.wait([load, choice]);

    expect(provider.locale, AppLocale.en);
    expect(I18n.current, AppLocale.en);
    expect(store.writes, ['zh', 'en']);
    expect((await store.getAll())['flutter.duoyi_locale_v1'], 'en');
  });

  test('a failed save does not poison subsequent language saves', () async {
    final store = _install({})..failFirstWrite = true;
    final provider = LocaleProvider();
    addTearDown(provider.dispose);
    await expectLater(provider.setLocale(AppLocale.en), throwsStateError);
    await provider.setLocale(AppLocale.zh);
    expect((await store.getAll())['flutter.duoyi_locale_v1'], 'zh');
  });

  test('a rejected save is reported and the next choice can save', () async {
    final store = _install({})..rejectFirstWrite = true;
    final provider = LocaleProvider();
    addTearDown(provider.dispose);
    await expectLater(provider.setLocale(AppLocale.en), throwsStateError);
    expect(I18n.current, AppLocale.en);
    await provider.setLocale(AppLocale.zh);
    expect((await store.getAll())['flutter.duoyi_locale_v1'], 'zh');
  });
}

_DelayedStore _install(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues(values);
  final store = _DelayedStore({
    for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
  });
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

class _DelayedStore extends InMemorySharedPreferencesStore {
  _DelayedStore(super.data) : super.withData();

  bool blockFirstRead = false;
  bool blockFirstWrite = false;
  bool failFirstWrite = false;
  bool rejectFirstWrite = false;
  final readEntered = Completer<void>();
  final writeEntered = Completer<void>();
  final releaseRead = Completer<void>();
  final releaseWrite = Completer<void>();
  final writes = <String>[];

  @override
  Future<Map<String, Object>> getAll() async {
    if (blockFirstRead) {
      blockFirstRead = false;
      readEntered.complete();
      await releaseRead.future;
    }
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.duoyi_locale_v1') {
      writes.add(value.toString());
      if (blockFirstWrite) {
        blockFirstWrite = false;
        writeEntered.complete();
        await releaseWrite.future;
      }
      if (failFirstWrite) {
        failFirstWrite = false;
        throw StateError('synthetic persistence failure');
      }
      if (rejectFirstWrite) {
        rejectFirstWrite = false;
        return false;
      }
    }
    return super.setValue(valueType, key, value);
  }
}
