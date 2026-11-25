// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _localeKey = 'flutter.duoyi_locale_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesStorePlatform previousStore;
  late AppLocale previousLocale;

  setUp(() {
    previousStore = SharedPreferencesStorePlatform.instance;
    previousLocale = I18n.current;
    SharedPreferences.resetStatic();
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previousStore;
    I18n.setLocale(previousLocale);
  });

  test('disposed delayed load cannot publish or migrate', () async {
    final fixture = _install('en_US', holdInitialRead: true);
    final notifications = <AppLocale>[];
    final globalNotifications = <AppLocale>[];
    fixture.provider.addListener(
      () => notifications.add(fixture.provider.locale),
    );
    void recordGlobalLocale() => globalNotifications.add(I18n.current);
    I18n.localeListenable.addListener(recordGlobalLocale);
    addTearDown(() => I18n.localeListenable.removeListener(recordGlobalLocale));

    final load = fixture.provider.loadFromStorage();
    final completion = expectLater(load, completes);
    await fixture.store.readEntered.future;
    fixture.disposeProvider();
    fixture.store.releaseRead();
    await completion;

    expect(fixture.provider.locale, AppLocale.zh);
    expect(I18n.current, AppLocale.zh);
    expect(notifications, isEmpty);
    expect(globalNotifications, isEmpty);
    expect(fixture.store.localeWrites, isEmpty);
    expect((await fixture.store.snapshot())[_localeKey], 'en_US');
  });

  test('disposal cancels locale saves before queued work starts', () async {
    final fixture = _install('zh');
    final notifications = <AppLocale>[];
    fixture.provider.addListener(
      () => notifications.add(fixture.provider.locale),
    );

    final english = fixture.provider.setLocale(AppLocale.en);
    expect(I18n.current, AppLocale.en);
    expect(notifications, [AppLocale.en]);
    final chinese = fixture.provider.setLocale(AppLocale.zh);
    expect(I18n.current, AppLocale.zh);
    fixture.disposeProvider();
    await expectLater(Future.wait([english, chinese]), completes);

    expect(fixture.store.localeWrites, isEmpty);
    expect((await fixture.store.snapshot())[_localeKey], 'zh');
    expect(notifications, [AppLocale.en, AppLocale.zh]);
  });

  test('disposal while acquiring preferences cancels saving', () async {
    final fixture = _install('zh', holdInitialRead: true);
    final notifications = <AppLocale>[];
    fixture.provider.addListener(
      () => notifications.add(fixture.provider.locale),
    );

    final save = fixture.provider.setLocale(AppLocale.en);
    final completion = expectLater(save, completes);
    await fixture.store.readEntered.future;
    expect(fixture.store.localeWrites, isEmpty);
    fixture.disposeProvider();
    // A surviving owner may select another locale while this read is pending.
    I18n.setLocale(AppLocale.zh);
    fixture.store.releaseRead();
    await completion;

    expect(I18n.current, AppLocale.zh);
    expect(notifications, [AppLocale.en]);
    expect(fixture.store.localeWrites, isEmpty);
    expect((await fixture.store.snapshot())[_localeKey], 'zh');
  });

  test('load and explicit choice after disposal have no effects', () async {
    final fixture = _install('en_US');
    fixture.disposeProvider();

    await expectLater(fixture.provider.loadFromStorage(), completes);
    await expectLater(
      Future<void>.sync(() => fixture.provider.setLocale(AppLocale.en)),
      completes,
    );

    expect(fixture.provider.locale, AppLocale.zh);
    expect(I18n.current, AppLocale.zh);
    expect(fixture.store.localeWrites, isEmpty);
    expect((await fixture.store.snapshot())[_localeKey], 'en_US');
  });

  test('live delayed load publishes and migrates its preference', () async {
    final fixture = _install('en_US', holdInitialRead: true);
    final notifications = <AppLocale>[];
    fixture.provider.addListener(
      () => notifications.add(fixture.provider.locale),
    );

    final load = fixture.provider.loadFromStorage();
    await fixture.store.readEntered.future;
    expect(I18n.current, AppLocale.zh);
    expect(notifications, isEmpty);
    fixture.store.releaseRead();
    await load;

    expect(fixture.provider.locale, AppLocale.en);
    expect(I18n.current, AppLocale.en);
    expect(notifications, [AppLocale.en]);
    expect(fixture.store.localeWrites, ['en']);
    expect((await fixture.store.snapshot())[_localeKey], 'en');
  });

  test('live choice publishes before delayed acquisition saves', () async {
    final fixture = _install('zh', holdInitialRead: true);
    final notifications = <AppLocale>[];
    fixture.provider.addListener(
      () => notifications.add(fixture.provider.locale),
    );

    final save = fixture.provider.setLocale(AppLocale.en);
    expect(fixture.provider.locale, AppLocale.en);
    expect(I18n.current, AppLocale.en);
    expect(notifications, [AppLocale.en]);
    await fixture.store.readEntered.future;
    expect(fixture.store.localeWrites, isEmpty);
    expect((await fixture.store.snapshot())[_localeKey], 'zh');
    fixture.store.releaseRead();
    await save;

    expect(fixture.store.localeWrites, ['en']);
    expect((await fixture.store.snapshot())[_localeKey], 'en');
    expect(notifications, [AppLocale.en]);
  });

  test('explicit default choice wins over a delayed regional load', () async {
    final fixture = _install('en_US', holdInitialRead: true);
    final notifications = <AppLocale>[];
    fixture.provider.addListener(
      () => notifications.add(fixture.provider.locale),
    );

    final load = fixture.provider.loadFromStorage();
    await fixture.store.readEntered.future;
    final choice = fixture.provider.setLocale(AppLocale.zh);
    expect(I18n.current, AppLocale.zh);
    fixture.store.releaseRead();
    await Future.wait([load, choice]);

    expect(fixture.provider.locale, AppLocale.zh);
    expect(I18n.current, AppLocale.zh);
    expect(notifications, isEmpty);
    expect(fixture.store.localeWrites, ['zh']);
    expect((await fixture.store.snapshot())[_localeKey], 'zh');
  });
}

_Fixture _install(String storedLocale, {bool holdInitialRead = false}) {
  SharedPreferences.setMockInitialValues({'duoyi_locale_v1': storedLocale});
  final store = _DelayedStore({
    _localeKey: storedLocale,
  }, holdInitialRead: holdInitialRead);
  SharedPreferencesStorePlatform.instance = store;
  final fixture = _Fixture(store);
  addTearDown(() {
    fixture.disposeProvider();
    store.releaseRead();
  });
  return fixture;
}

class _Fixture {
  _Fixture(this.store);

  final _DelayedStore store;
  final LocaleProvider provider = LocaleProvider();
  bool _disposed = false;

  void disposeProvider() {
    if (_disposed) return;
    _disposed = true;
    provider.dispose();
  }
}

class _DelayedStore extends InMemorySharedPreferencesStore {
  _DelayedStore(super.data, {required bool holdInitialRead})
    : _holdInitialRead = holdInitialRead,
      super.withData();

  bool _holdInitialRead;
  final readEntered = Completer<void>();
  final _readRelease = Completer<void>();
  final localeWrites = <String>[];

  void releaseRead() {
    if (!_readRelease.isCompleted) _readRelease.complete();
  }

  Future<Map<String, Object>> snapshot() => super.getAll();

  @override
  Future<Map<String, Object>> getAll() async {
    if (_holdInitialRead) {
      _holdInitialRead = false;
      readEntered.complete();
      await _readRelease.future;
    }
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == _localeKey) localeWrites.add(value as String);
    return super.setValue(valueType, key, value);
  }
}
