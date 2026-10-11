import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
  });

  tearDown(() async {
    await AccountPreferenceWrites.drain();
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });

  test('untracked reads wait until nested account cleanup settles', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final boundary = AccountPreferenceWrites.boundary<void>(() async {
      await AccountPreferenceWrites.boundary<void>(() async {});
      started.complete();
      await release.future;
    });
    await started.future;
    var settled = false;
    final read = AccountPreferenceWrites.waitForBoundary().then((_) {
      settled = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    release.complete();
    await Future.wait([read, boundary]);
    expect(settled, isTrue);
    await AccountPreferenceWrites.waitForBoundary();
  });

  test('rejected boolean save restores provider and legacy cache', () async {
    final store = _ControlledStore()..rejectKeyOnce = 'flutter.pref_show_lunar';
    SharedPreferencesStorePlatform.instance = store;
    final changed = <String>{};
    final provider = PreferencesProvider()..onChangedKeys = changed.addAll;
    await provider.loadFromStorage();

    await expectLater(provider.setShowLunar(false), throwsStateError);

    expect(provider.showLunar, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool('pref_show_lunar'),
      isNull,
    );
    expect(changed, isEmpty);
  });

  test('partial reminder save restores every changed key', () async {
    final store = _ControlledStore()
      ..rejectKeyOnce = 'flutter.pref_daily_reminder_hour';
    SharedPreferencesStorePlatform.instance = store;
    final changed = <String>{};
    final provider = PreferencesProvider()..onChangedKeys = changed.addAll;
    await provider.loadFromStorage();

    await expectLater(
      provider.setDailyReminderSlot(
        0,
        const DailyReminderSlot(enabled: true, hour: 8),
      ),
      throwsStateError,
    );

    expect(provider.dailyReminderEnabled, isFalse);
    expect(provider.dailyReminderHour, 20);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getKeys().where(
        (key) => key.startsWith('pref_daily_reminder'),
      ),
      isEmpty,
    );
    expect(changed, isEmpty);
  });

  test('rapid selections persist in submission order', () async {
    final store = _ControlledStore()..holdKey = 'flutter.pref_show_lunar';
    SharedPreferencesStorePlatform.instance = store;
    final provider = PreferencesProvider();
    await provider.loadFromStorage();
    final first = provider.setShowLunar(false);
    await store.started.future;
    final second = provider.setShowLunar(true);
    expect(store.values, [false]);
    store.release.complete();
    await Future.wait([first, second]);

    expect(store.values, [false, true]);
    expect(provider.showLunar, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool('pref_show_lunar'),
      isTrue,
    );
  });

  test(
    'cleanup waits for issued write and discards queued old writes',
    () async {
      final store = _ControlledStore()..holdKey = 'flutter.pref_show_lunar';
      SharedPreferencesStorePlatform.instance = store;
      final changed = <String>{};
      final provider = PreferencesProvider()..onChangedKeys = changed.addAll;
      await provider.loadFromStorage();
      final first = provider.setShowLunar(false);
      await store.started.future;
      final queued = provider.setHaptic(false);
      provider.resetLocalState();
      var cleaned = false;
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then((
        _,
      ) {
        cleaned = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isFalse);
      store.release.complete();
      await Future.wait([first, queued, cleanup]);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey('pref_show_lunar'), isFalse);
      expect(preferences.containsKey('pref_haptic_feedback'), isFalse);
      expect(
        store.events.indexOf('set:flutter.pref_show_lunar'),
        lessThan(store.events.indexOf('remove:flutter.pref_show_lunar')),
      );
      expect(changed, isEmpty);
      expect(provider.showLunar, isTrue);
      expect(provider.haptic, isTrue);
      await provider.setShowLunar(false);
      expect(provider.showLunar, isFalse);
    },
  );

  test(
    'aborted account preflight restores partial reminder write and memory',
    () async {
      final store = _ControlledStore()
        ..holdKey = 'flutter.pref_daily_reminder_enabled';
      SharedPreferencesStorePlatform.instance = store;
      final provider = PreferencesProvider();
      await provider.loadFromStorage();
      final write = provider.setDailyReminderSlot(
        0,
        const DailyReminderSlot(enabled: true, hour: 8),
      );
      await store.started.future;
      final boundary = AccountLocalDataCleaner.runPreferenceBoundary<void>(
        () async {
          throw StateError('Account preflight failed');
        },
      );
      final expectedFailure = expectLater(boundary, throwsStateError);
      store.release.complete();
      await Future.wait([write, expectedFailure]);
      expect(provider.dailyReminderEnabled, isFalse);
      expect(provider.dailyReminderHour, 20);
      expect(
        (await SharedPreferences.getInstance()).getKeys().where(
          (key) => key.startsWith('pref_daily_reminder'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'aborted account preflight restores the timezone pair and process zone',
    () async {
      final store = _ControlledStore();
      SharedPreferencesStorePlatform.instance = store;
      final provider = PreferencesProvider();
      await provider.loadFromStorage();
      store.holdKey = 'flutter.pref_app_timezone_mode';
      final write = provider.setAppTimeZone('Asia/Tokyo');
      await store.started.future;
      final boundary = AccountLocalDataCleaner.runPreferenceBoundary<void>(
        () async {
          throw StateError('Account preflight failed');
        },
      );
      final expectedFailure = expectLater(boundary, throwsStateError);
      store.release.complete();
      await Future.wait([write, expectedFailure]);
      expect(provider.followSystemTimeZone, isTrue);
      expect(provider.appTimeZone, 'Asia/Shanghai');
      expect(tz.local.name, 'Asia/Shanghai');
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(LocalTimezoneResolver.modePreferenceKey),
        isNull,
      );
      expect(
        preferences.getString(LocalTimezoneResolver.preferenceKey),
        isNull,
      );
    },
  );

  test(
    'user writes during a boundary do not cross into the next account',
    () async {
      final provider = PreferencesProvider();
      await AccountLocalDataCleaner.runPreferenceBoundary(() async {
        await provider.setShowLunar(false);
        await AccountLocalDataCleaner.clearSharedPreferences();
      });
      expect(provider.showLunar, isTrue);
      expect(
        (await SharedPreferences.getInstance()).containsKey('pref_show_lunar'),
        isFalse,
      );
      await provider.setShowLunar(false);
      expect(provider.showLunar, isFalse);
    },
  );

  test(
    'rapid timezone selections end with matching storage and process zone',
    () async {
      final store = _ControlledStore()
        ..holdKey = 'flutter.pref_app_timezone_mode';
      SharedPreferencesStorePlatform.instance = store;
      var resyncs = 0;
      final provider = PreferencesProvider()
        ..onAppTimeZoneChanged = () async {
          resyncs++;
        };
      await provider.loadFromStorage();
      final first = provider.setAppTimeZone('Asia/Tokyo');
      await store.started.future;
      final second = provider.setAppTimeZone('America/Mexico_City');
      store.release.complete();
      await Future.wait([first, second]);
      expect(provider.appTimeZone, 'America/Mexico_City');
      expect(tz.local.name, 'America/Mexico_City');
      expect(
        (await SharedPreferences.getInstance()).getString(
          LocalTimezoneResolver.preferenceKey,
        ),
        'America/Mexico_City',
      );
      expect(resyncs, 2);
    },
  );

  test('follow-system save waits for a concurrent lifecycle refresh', () async {
    final provider = PreferencesProvider();
    await provider.setAppTimeZone('Asia/Tokyo');
    final first = Completer<String?>();
    final second = Completer<String?>();
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    var calls = 0;
    LocalTimezoneResolver.debugSystemTimeZoneReader = () {
      if (++calls == 1) {
        firstStarted.complete();
        return first.future;
      }
      secondStarted.complete();
      return second.future;
    };
    var callbacks = 0;
    provider.onAppTimeZoneChanged = () async {
      callbacks++;
    };
    final save = provider.setAppTimeZone('system');
    await firstStarted.future;
    final refresh = LocalTimezoneResolver.refresh();
    await secondStarted.future;
    first.complete('Asia/Shanghai');
    await Future<void>.delayed(Duration.zero);
    expect(callbacks, 0);
    second.complete('America/Mexico_City');
    await Future.wait([save, refresh]);
    expect(provider.appTimeZone, 'America/Mexico_City');
    expect(tz.local.name, 'America/Mexico_City');
    expect(callbacks, 1);
  });

  test('reminder callback failure keeps the committed timezone', () async {
    final changed = <String>{};
    final provider = PreferencesProvider()..onChangedKeys = changed.addAll;
    await provider.loadFromStorage();
    provider.onAppTimeZoneChanged = () async {
      throw StateError('Resync failed');
    };
    await expectLater(provider.setAppTimeZone('Asia/Tokyo'), throwsStateError);
    expect(provider.appTimeZone, 'Asia/Tokyo');
    expect(tz.local.name, 'Asia/Tokyo');
    expect(
      (await SharedPreferences.getInstance()).getString(
        LocalTimezoneResolver.preferenceKey,
      ),
      'Asia/Tokyo',
    );
    expect(changed, contains(LocalTimezoneResolver.preferenceKey));
  });

  test('old timezone reload cannot overwrite a new account location', () async {
    final oldSystemZone = Completer<String?>();
    final started = Completer<void>();
    LocalTimezoneResolver.debugSystemTimeZoneReader = () {
      started.complete();
      return oldSystemZone.future;
    };
    final provider = PreferencesProvider();
    final oldLoad = provider.loadFromStorage();
    await started.future;
    provider.resetLocalState();
    await AccountLocalDataCleaner.clearSharedPreferences();
    await provider.setAppTimeZone('Asia/Tokyo');
    oldSystemZone.complete('America/Mexico_City');
    await oldLoad;
    expect(provider.appTimeZone, 'Asia/Tokyo');
    expect(tz.local.name, 'Asia/Tokyo');
  });
}

class _ControlledStore extends InMemorySharedPreferencesStore {
  _ControlledStore() : super.withData({});
  String? rejectKeyOnce;
  String? holdKey;
  final started = Completer<void>();
  final release = Completer<void>();
  final values = <Object>[];
  final events = <String>[];

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
    final saved = await super.setValue(valueType, key, value);
    events.add('set:$key');
    return saved;
  }

  @override
  Future<bool> remove(String key) async {
    final removed = await super.remove(key);
    events.add('remove:$key');
    return removed;
  }
}
