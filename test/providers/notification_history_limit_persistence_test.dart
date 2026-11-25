import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _historyKey = 'duoyi_notif_history';
const _historyPreferenceKey = 'pref_notification_history_limit';
const _platformHistoryKey = 'flutter.$_historyKey';
const _platformHistoryPreferenceKey = 'flutter.$_historyPreferenceKey';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Fixture fixture;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    fixture = _Fixture();
    SharedPreferencesStorePlatform.instance = fixture.store;
  });

  tearDown(() async {
    fixture.store.releaseHeldWrite();
    await AccountPreferenceWrites.drain();
    fixture.service.dispose();
    fixture.preferences.dispose();
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });

  for (final throws in [false, true]) {
    test(
      'preference limit save rejects a $throws write without publishing and permits retry',
      () async {
        await fixture.load();
        final changedKeys = <String>{};
        final publishedLimits = <int>[];
        fixture.preferences
          ..onChangedKeys = changedKeys.addAll
          ..addListener(
            () => publishedLimits.add(
              fixture.preferences.notificationHistoryLimit,
            ),
          );
        fixture.store.failNextPreferenceWrite(throws: throws);

        await expectLater(
          fixture.preferences.saveNotificationHistoryLimit(100),
          throwsA(isA<StateError>()),
        );

        expect(fixture.preferences.notificationHistoryLimit, 500);
        expect(fixture.preferences.storageGeneration, 0);
        expect(changedKeys, isEmpty);
        // Failure reloads durable settings and may notify their restored state.
        // It must never publish the rejected target limit.
        expect(publishedLimits, everyElement(500));
        expect(await fixture.diskHistoryLimit(), 500);

        expect(
          await fixture.preferences.saveNotificationHistoryLimit(100),
          isTrue,
        );
        expect(fixture.preferences.notificationHistoryLimit, 100);
        expect(changedKeys, contains(_historyPreferenceKey));
        expect(await fixture.diskHistoryLimit(), 100);
      },
    );
  }

  test(
    'canceled preference save returns false and keeps the legacy void API',
    () async {
      await fixture.load();

      expect(
        await fixture.preferences.saveNotificationHistoryLimit(
          100,
          canWrite: () => false,
        ),
        isFalse,
      );
      expect(fixture.preferences.notificationHistoryLimit, 500);
      expect(await fixture.diskHistoryLimit(), 500);

      final Future<void> legacyWrite = fixture.preferences
          .setNotificationHistoryLimit(100);
      await legacyWrite;
      expect(fixture.preferences.notificationHistoryLimit, 100);
      expect(await fixture.diskHistoryLimit(), 100);
    },
  );

  for (final throws in [false, true]) {
    test(
      'history trim rejects a $throws write without changing memory and retries the same limit',
      () async {
        await fixture.load();
        var notifications = 0;
        fixture.service.addListener(() => notifications++);
        fixture.store.failNextHistoryWrite(throws: throws);

        await expectLater(
          fixture.service.applyHistoryLimit(100),
          throwsA(isA<StateError>()),
        );

        expect(fixture.service.historyLimit, 500);
        expect(fixture.service.storageGeneration, 0);
        expect(fixture.service.history, hasLength(200));
        expect(notifications, 0);
        expect(await fixture.diskHistoryIds(), _initialIds.toSet());

        final writesBeforeRetry = fixture.store.historyWriteCount;
        expect(await fixture.service.applyHistoryLimit(100), isTrue);

        expect(fixture.store.historyWriteCount, greaterThan(writesBeforeRetry));
        expect(fixture.service.historyLimit, 100);
        expect(fixture.service.history, hasLength(100));
        expect(
          fixture.service.history.map((item) => item.id),
          _initialIds.take(100),
        );
        expect(await fixture.diskHistoryIds(), _initialIds.take(100).toSet());
        expect(notifications, 1);
      },
    );
  }

  test(
    'canceled history trim returns false without publishing the limit',
    () async {
      await fixture.load();

      expect(
        await fixture.service.applyHistoryLimit(100, canWrite: () => false),
        isFalse,
      );
      expect(fixture.service.historyLimit, 500);
      expect(fixture.service.history, hasLength(200));
      expect(await fixture.diskHistoryIds(), _initialIds.toSet());

      final Future<void> legacyWrite = fixture.service.setHistoryLimit(100);
      await legacyWrite;
      expect(fixture.service.historyLimit, 100);
      expect(fixture.service.history, hasLength(100));
      expect(await fixture.diskHistoryIds(), _initialIds.take(100).toSet());
    },
  );

  test(
    'a notification added during an acknowledged trim is retained in memory and on disk',
    () async {
      await fixture.load();
      fixture.store.holdNextWrite(_platformHistoryKey);
      final pending = fixture.service.applyHistoryLimit(100);
      await fixture.store.writeStarted.future;

      final newest = _item('live-newest');
      fixture.service.addHistoryForTest(newest);
      expect(fixture.service.history.first.id, newest.id);
      expect(fixture.service.history, hasLength(201));

      fixture.store.releaseHeldWrite();
      expect(await pending, isTrue);
      await AccountPreferenceWrites.drain();

      expect(fixture.service.history, hasLength(100));
      expect(fixture.service.history.first.id, newest.id);
      expect(
        fixture.service.history.skip(1).map((item) => item.id),
        _initialIds.take(99),
      );
      expect(await fixture.diskHistoryIds(), {
        'live-newest',
        ..._initialIds.take(99),
      });
    },
  );

  test(
    'account cleanup drains a held trim and cannot restore its old payload',
    () async {
      await fixture.load();
      fixture.store.holdNextWrite(_platformHistoryKey);
      final pending = fixture.service.applyHistoryLimit(100);
      await fixture.store.writeStarted.future;

      fixture.service.resetLocalState();
      fixture.preferences.resetLocalState();
      var cleanupFinished = false;
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then((
        _,
      ) {
        cleanupFinished = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(cleanupFinished, isFalse);

      fixture.store.releaseHeldWrite();
      expect(await pending, isFalse);
      await cleanup;
      await fixture.prefs.reload();

      expect(cleanupFinished, isTrue);
      expect(fixture.service.history, isEmpty);
      expect(fixture.service.historyLimit, 500);
      expect(fixture.preferences.notificationHistoryLimit, 500);
      expect(fixture.prefs.containsKey(_historyKey), isFalse);
      expect(fixture.prefs.containsKey(_historyPreferenceKey), isFalse);
      expect(
        await fixture.store.getAll(),
        isNot(contains(_platformHistoryKey)),
      );
    },
  );

  test('first trim loads durable history before saving its snapshot', () async {
    await fixture.loadPreferencesOnly();

    expect(await fixture.service.applyHistoryLimit(100), isTrue);
    await fixture.service.loadHistoryForTest();

    expect(fixture.service.historyLimit, 100);
    expect(
      fixture.service.history.map((item) => item.id),
      _initialIds.take(100),
    );
    expect(await fixture.diskHistoryIds(), _initialIds.take(100).toSet());
  });

  test(
    'a notification before deferred load preserves the durable records',
    () async {
      await fixture.loadPreferencesOnly();
      fixture.service.addHistoryForTest(_item('preload-newest'));
      await fixture.service.loadHistoryForTest();
      await AccountPreferenceWrites.drain();

      expect(fixture.service.history, hasLength(201));
      expect(fixture.service.history.first.id, 'preload-newest');
      expect(await fixture.diskHistoryIds(), {
        'preload-newest',
        ..._initialIds,
      });
    },
  );

  test(
    'preload notification batches use the durable cap rather than 500',
    () async {
      fixture.store = _HistoryStore(_seededStorage(limit: 5000));
      SharedPreferencesStorePlatform.instance = fixture.store;
      await fixture.loadPreferencesOnly();

      await fixture.service.runNotificationBatch(() async {
        for (var i = 0; i < 600; i++) {
          fixture.service.addHistoryForTest(_item('preload-$i'));
        }
      });
      await fixture.service.loadHistoryForTest();

      expect(fixture.service.historyLimit, 5000);
      expect(fixture.service.history, hasLength(800));
      expect(await fixture.diskHistoryIds(), {
        ..._initialIds,
        for (var i = 0; i < 600; i++) 'preload-$i',
      });
    },
  );

  for (final throws in [false, true]) {
    test('load waits for a held trim that fails with throws=$throws', () async {
      await fixture.load();
      fixture.store.holdNextWrite(_platformHistoryKey);
      fixture.store.failNextHistoryWrite(throws: throws);
      final trim = fixture.service.applyHistoryLimit(100);
      final failure = expectLater(trim, throwsA(isA<StateError>()));
      await fixture.store.writeStarted.future;
      var loaded = false;
      final load = fixture.service.loadHistoryForTest().then(
        (_) => loaded = true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(loaded, isFalse);
      expect(fixture.service.history, hasLength(200));
      fixture.store.releaseHeldWrite();
      await failure;
      await load;

      expect(fixture.service.history, hasLength(200));
      expect(await fixture.diskHistoryIds(), _initialIds.toSet());
      expect(await fixture.service.applyHistoryLimit(100), isTrue);
      expect(fixture.service.history, hasLength(100));
      expect(await fixture.diskHistoryIds(), _initialIds.take(100).toSet());
    });
  }

  test(
    'clear before deferred load keeps history empty and its durable cap',
    () async {
      fixture.store = _HistoryStore(_seededStorage(limit: 1000));
      SharedPreferencesStorePlatform.instance = fixture.store;
      await fixture.loadPreferencesOnly();
      await fixture.service.clearHistory();
      await fixture.service.loadHistoryForTest();

      expect(fixture.service.history, isEmpty);
      expect(await fixture.diskHistoryIds(), isEmpty);
      expect(fixture.service.historyLimit, 1000);
      fixture.service.addHistoryForTest(_item('after-clear'));
      await AccountPreferenceWrites.drain();
      expect(await fixture.diskHistoryIds(), {'after-clear'});
    },
  );

  for (final throws in [false, true]) {
    test(
      'clear before deferred load rejects throws=$throws without deleting records',
      () async {
        await fixture.loadPreferencesOnly();
        fixture.store.failNextHistoryWrite(throws: throws);
        await expectLater(
          fixture.service.clearHistory(),
          throwsA(isA<StateError>()),
        );

        expect(fixture.service.history, hasLength(200));
        expect(await fixture.diskHistoryIds(), _initialIds.toSet());
        await fixture.service.clearHistory();
        expect(fixture.service.history, isEmpty);
        expect(await fixture.diskHistoryIds(), isEmpty);
      },
    );
  }

  test(
    'cold loading preserves distinct history records with the same native ID',
    () async {
      final old = _item('shared-id');
      final other = NotificationItem(
        id: old.id,
        title: old.title,
        body: old.body,
        scheduledTime: old.scheduledTime.add(const Duration(days: 1)),
        type: old.type,
      );
      fixture.store = _HistoryStore({
        _platformHistoryPreferenceKey: 500,
        _platformHistoryKey: [
          jsonEncode(old.toJson()),
          jsonEncode(other.toJson()),
        ],
      });
      SharedPreferencesStorePlatform.instance = fixture.store;
      await fixture.load();

      expect(fixture.service.history, hasLength(2));
      expect(fixture.service.history.map((item) => item.scheduledTime), [
        old.scheduledTime,
        other.scheduledTime,
      ]);
      expect(await fixture.service.applyHistoryLimit(100), isTrue);
      await fixture.prefs.reload();
      expect(fixture.prefs.getStringList(_historyKey), hasLength(2));
    },
  );

  test('clear preserves a new occurrence sharing an old native ID', () async {
    await fixture.load();
    fixture.store.holdNextWrite(_platformHistoryKey);
    final clear = fixture.service.clearHistory();
    await fixture.store.writeStarted.future;
    final old = _item(_initialIds.first);
    final fresh = NotificationItem(
      id: old.id,
      title: old.title,
      body: old.body,
      scheduledTime: old.scheduledTime.add(const Duration(days: 1)),
      type: old.type,
    );
    fixture.service.addHistoryForTest(fresh);
    fixture.store.releaseHeldWrite();
    await clear;
    await AccountPreferenceWrites.drain();

    expect(fixture.service.history, hasLength(1));
    expect(fixture.service.history.single.scheduledTime, fresh.scheduledTime);
    await fixture.prefs.reload();
    final disk = fixture.prefs.getStringList(_historyKey)!;
    expect(disk, hasLength(1));
    expect(
      (jsonDecode(disk.single) as Map<String, dynamic>)['scheduledTime'],
      fresh.scheduledTime.toIso8601String(),
    );
  });

  test(
    'marking records read during clear does not resurrect old occurrences',
    () async {
      await fixture.load();
      fixture.store.holdNextWrite(_platformHistoryKey);
      final clear = fixture.service.clearHistory();
      await fixture.store.writeStarted.future;
      fixture.service.markHistorySeen();
      fixture.store.releaseHeldWrite();
      await clear;
      await AccountPreferenceWrites.drain();

      expect(fixture.service.history, isEmpty);
      expect(await fixture.diskHistoryIds(), isEmpty);
    },
  );

  for (final throws in [false, true]) {
    test(
      'cold history load keeps all 200 records when cap trim write throws=$throws',
      () async {
        fixture.store = _HistoryStore(_seededStorage(limit: 100));
        SharedPreferencesStorePlatform.instance = fixture.store;
        fixture.store.failNextHistoryWrite(throws: throws);
        await fixture.loadPreferencesOnly();

        await fixture.service.loadHistoryForTest().catchError((Object _) {});

        expect(fixture.service.historyLimit, 500);
        expect(fixture.service.history, hasLength(200));
        expect(fixture.service.history.map((item) => item.id), _initialIds);
        expect(await fixture.diskHistoryIds(), _initialIds.toSet());
      },
    );
  }
}

final List<String> _initialIds = List<String>.generate(
  200,
  (index) => 'history-${200 - index}',
  growable: false,
);

class _Fixture {
  _HistoryStore store = _HistoryStore(_seededStorage(limit: 500));
  final preferences = PreferencesProvider();
  final service = NotificationService();
  late SharedPreferences prefs;

  Future<void> load() async {
    await loadPreferencesOnly();
    await service.loadHistoryForTest();
  }

  Future<void> loadPreferencesOnly() async {
    prefs = await SharedPreferences.getInstance();
    await preferences.loadFromStorage();
  }

  Future<int?> diskHistoryLimit() async {
    await prefs.reload();
    return prefs.getInt(_historyPreferenceKey);
  }

  Future<Set<String>> diskHistoryIds() async {
    await prefs.reload();
    return (prefs.getStringList(_historyKey) ?? const <String>[])
        .map(
          (raw) => (jsonDecode(raw) as Map<String, dynamic>)['id']! as String,
        )
        .toSet();
  }
}

class _HistoryStore extends InMemorySharedPreferencesStore {
  _HistoryStore(super.data) : super.withData();

  static const _historyKey = _platformHistoryKey;
  static const _limitKey = _platformHistoryPreferenceKey;

  String? _failKey;
  bool _throwOnFailure = false;
  String? _heldKey;
  Completer<void>? _writeStarted;
  Completer<void>? _release;
  int historyWriteCount = 0;
  int limitWriteCount = 0;

  Completer<void> get writeStarted => _writeStarted!;

  void failNextHistoryWrite({required bool throws}) {
    _failKey = _historyKey;
    _throwOnFailure = throws;
  }

  void failNextPreferenceWrite({required bool throws}) {
    _failKey = _limitKey;
    _throwOnFailure = throws;
  }

  void holdNextWrite(String key) {
    _heldKey = key;
    _writeStarted = Completer<void>();
    _release = Completer<void>();
  }

  void releaseHeldWrite() {
    final release = _release;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == _historyKey) historyWriteCount++;
    if (key == _limitKey) limitWriteCount++;
    if (key == _heldKey) {
      _heldKey = null;
      _writeStarted!.complete();
      await _release!.future;
    }

    // Simulate stores that commit their value and then return a negative ACK
    // (or throw), so the provider has to restore the previous disk snapshot.
    final saved = await super.setValue(valueType, key, value);
    if (key == _failKey) {
      _failKey = null;
      if (_throwOnFailure) {
        throw StateError('injected notification history write failure');
      }
      return false;
    }
    return saved;
  }
}

Map<String, Object> _seededStorage({required int limit}) => <String, Object>{
  _platformHistoryPreferenceKey: limit,
  _platformHistoryKey: _initialIds
      .map((id) => jsonEncode(_item(id).toJson()))
      .toList(growable: false),
};

NotificationItem _item(String id) {
  final sequence = int.tryParse(id.split('-').last) ?? 1000;
  return NotificationItem(
    id: id,
    title: id,
    body: 'Synthetic notification $id',
    scheduledTime: DateTime.utc(2026, 10, 1).add(Duration(minutes: sequence)),
    type: NotificationType.general,
  );
}
