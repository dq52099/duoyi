// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _subscriptionsKey = 'duoyi_ics_subscriptions_v1';
const _wait = Duration(seconds: 2);
const _oldTitle = 'Confirmed 用户事件';
const _newTitle = 'Fetched 用户事件';
const _freshCalendar = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:fetched@test
SUMMARY:Fetched 用户事件
DTSTART:20261109T110000
DTEND:20261109T120000
END:VEVENT
END:VCALENDAR
''';

// Contract tests use the existing public API. They intentionally expose its
// current acknowledgement and stale-response gaps without replacing methods.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _IcsStore store;
  late SharedPreferences prefs;
  late CalendarSyncProvider provider;
  late _Feed feed;
  late SharedPreferencesStorePlatform previousStore;
  final pending = <Future<Object?>>[];
  final additionalProviders = <CalendarSyncProvider>[];
  var disposed = false;

  setUp(() async {
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    previousStore = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _IcsStore();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    provider = CalendarSyncProvider();
    feed = _Feed();
    pending.clear();
    additionalProviders.clear();
    disposed = false;
  });

  tearDown(() async {
    store.releaseAll();
    feed.releaseAll();
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
    } finally {
      if (!disposed) provider.dispose();
      for (final extra in additionalProviders) {
        extra.dispose();
      }
      SharedPreferencesStorePlatform.instance = previousStore;
    }
  });

  Future<Object?> capture<T>(Future<T> future) {
    final outcome = future.then<Object?>(
      (_) => null,
      onError: (Object error) => error,
    );
    pending.add(outcome);
    return outcome;
  }

  Future<void> withFeed(Future<void> Function() body) =>
      http.runWithClient(body, () => MockClient(feed.respond));

  Future<Map<String, String?>> seed({bool load = true}) async {
    final subscription = _subscription(
      'old',
      synced: DateTime.utc(2026, 11, 1),
    );
    final raws = <String, String?>{
      _subscriptionsKey: '[\n  ${jsonEncode(subscription.toJson())}\n]\n',
      _cacheKey('old'): '[\n  ${jsonEncode(_cachedEvent())}\n]\n',
    };
    for (final entry in raws.entries) {
      await prefs.setString(entry.key, entry.value!);
    }
    if (load) await provider.loadFromStorage();
    store.writes.clear();
    return raws;
  }

  Future<void> expectStorage(Map<String, String?> raws) async {
    for (final entry in raws.entries) {
      expect(
        prefs.getString(entry.key),
        entry.value,
        reason: 'cached ${entry.key}',
      );
      expect(
        await store.diskRaw(entry.key),
        entry.value,
        reason: 'backing storage ${entry.key}',
      );
    }
    await prefs.reload();
    for (final entry in raws.entries) {
      expect(
        prefs.getString(entry.key),
        entry.value,
        reason: 'reloaded ${entry.key}',
      );
    }
  }

  test(
    'cold add stages its row and preserves existing durable subscriptions',
    () => withFeed(() async {
      final raws = await seed(load: false);
      final effects = _Effects(provider);
      final gate = store.holdNext(_subscriptionsKey);
      final adding = capture(provider.addSubscription(_subscription('new')));
      await gate.entered.future.timeout(_wait);

      expect(
        provider.subscriptions.map((sub) => sub.id),
        isNot(contains('new')),
      );
      expect(await store.diskRaw(_subscriptionsKey), raws[_subscriptionsKey]);
      expect(
        effects.subscriptionIds.expand((ids) => ids),
        isNot(contains('new')),
      );
      expect(feed.requests, isEmpty);

      gate.release.complete();
      expect(await adding, isNull);

      expect(provider.subscriptions.map((sub) => sub.id), ['old', 'new']);
      expect(_storedSubscriptions(prefs).map((sub) => sub.id), ['old', 'new']);
      expect(prefs.getString(_cacheKey('old')), raws[_cacheKey('old')]);
      expect(
        feed.requests,
        isEmpty,
        reason: 'saving configuration does not fetch',
      );
    }),
  );

  for (final operation in ['add', 'update', 'delete cache', 'delete list']) {
    for (final throws in [false, true]) {
      test(
        '$operation write-then-${throws ? 'throw' : 'false'} restores raw state and permits retry',
        () => withFeed(() async {
          final raws = await seed();
          final originalSubscriptions = _subscriptionSnapshot(provider);
          final originalEvents = _eventTitles(provider);
          final effects = _Effects(provider);
          final rejectedKey = operation == 'delete cache'
              ? _cacheKey('old')
              : _subscriptionsKey;
          store.rejectNext(rejectedKey, throws: throws);

          Future<void> mutate() {
            if (operation == 'add') {
              return provider.addSubscription(_subscription('retry'));
            }
            if (operation == 'update') {
              return provider.updateSubscription(
                provider.subscriptions.single.copyWith(name: 'Edited 用户订阅'),
              );
            }
            return provider.removeSubscription('old');
          }

          expect(
            await capture(mutate()),
            isNotNull,
            reason: 'a rejected persistence ACK must reject the mutation',
          );

          await expectStorage(raws);
          expect(_subscriptionSnapshot(provider), originalSubscriptions);
          expect(_eventTitles(provider), originalEvents);
          expect(
            effects.subscriptionIds,
            everyElement(
              originalSubscriptions.map((sub) => sub['id']).toList(),
            ),
          );
          expect(effects.eventTitles, everyElement(originalEvents));
          expect(
            effects.subscriptionSnapshots,
            everyElement(originalSubscriptions),
          );

          expect(await capture(mutate()), isNull);
          if (operation == 'add') {
            expect(_storedSubscriptions(prefs).map((sub) => sub.id), [
              'old',
              'retry',
            ]);
            expect(
              provider.subscriptions.where((sub) => sub.id == 'retry'),
              hasLength(1),
            );
          } else if (operation == 'update') {
            expect(provider.subscriptions.single.name, 'Edited 用户订阅');
            expect(_storedSubscriptions(prefs).single.name, 'Edited 用户订阅');
          } else {
            expect(provider.subscriptions, isEmpty);
            expect(provider.allEvents(), isEmpty);
            expect(_storedSubscriptions(prefs), isEmpty);
            expect(prefs.getString(_cacheKey('old')), isNull);
          }
        }),
      );
    }
  }

  test(
    'same draft retry after refresh does not duplicate or undo sync metadata',
    () async {
      await withFeed(() async {
        final draft = _subscription('stable');
        expect(await capture(provider.addSubscription(draft)), isNull);
        expect(await capture(provider.syncAll()), isNull);
        expect(provider.subscriptions.single.lastSyncedAt, isNotNull);
        final acknowledged = prefs.getString(_subscriptionsKey);
        store.writes.clear();
        final effects = _Effects(provider);

        expect(await capture(provider.addSubscription(draft)), isNull);

        expect(provider.subscriptions.map((sub) => sub.id), ['stable']);
        expect(prefs.getString(_subscriptionsKey), acknowledged);
        expect(_storedSubscriptions(prefs).single.lastSyncedAt, isNotNull);
        expect(store.writes, isEmpty);
        expect(effects.subscriptionIds, everyElement(['stable']));
        expect(feed.requests, hasLength(1));
      });
    },
  );

  test(
    'two loaded providers retain both adds through a held shared-key write',
    () => withFeed(() async {
      await seed();
      final replacement = CalendarSyncProvider();
      additionalProviders.add(replacement);
      await replacement.loadFromStorage();
      final gate = store.holdNext(_subscriptionsKey);
      final first = capture(provider.addSubscription(_subscription('first')));
      await gate.entered.future.timeout(_wait);
      final second = capture(
        replacement.addSubscription(_subscription('second')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, [_subscriptionsKey]);

      gate.release.complete();
      expect(await first, isNull);
      expect(await second, isNull);

      expect(_storedSubscriptions(prefs).map((sub) => sub.id), [
        'old',
        'first',
        'second',
      ]);
      expect(replacement.subscriptions.map((sub) => sub.id), [
        'old',
        'first',
        'second',
      ]);
    }),
  );

  test(
    'pause hides confirmed cached events and resume restores them',
    () => withFeed(() async {
      final raws = await seed();
      final original = provider.subscriptions.single;
      expect(_eventTitles(provider), [_oldTitle]);

      expect(
        await capture(
          provider.updateSubscription(original.copyWith(enabled: false)),
        ),
        isNull,
      );

      expect(provider.allEvents(), isEmpty);
      expect(_storedSubscriptions(prefs).single.enabled, isFalse);
      expect(prefs.getString(_cacheKey('old')), raws[_cacheKey('old')]);

      expect(await capture(provider.updateSubscription(original)), isNull);
      expect(_eventTitles(provider), [_oldTitle]);
      expect(_storedSubscriptions(prefs).single.enabled, isTrue);
      expect(feed.requests, isEmpty);
    }),
  );

  test(
    'reload after both account keys disappear cannot revive old subscriptions',
    () => withFeed(() async {
      await seed();
      await prefs.remove(_subscriptionsKey);
      await prefs.remove(_cacheKey('old'));
      await provider.loadFromStorage();

      expect(provider.subscriptions, isEmpty);
      expect(provider.allEvents(), isEmpty);

      expect(
        await capture(provider.addSubscription(_subscription('new'))),
        isNull,
      );
      expect(_storedSubscriptions(prefs).map((sub) => sub.id), ['new']);
      expect(prefs.getString(_cacheKey('old')), isNull);
    }),
  );

  test(
    'refresh publishes cache and timestamp together after durable ACK',
    () async {
      await withFeed(() async {
        final raws = await seed();
        final originalSubscriptions = _subscriptionSnapshot(provider);
        final effects = _Effects(provider);
        final gate = store.holdNext(_cacheKey('old'));
        final metadataGate = store.holdNext(_subscriptionsKey);
        final syncing = capture(provider.syncAll());
        final first = await Future.any<_WriteGate>([
          gate.entered.future.then((_) => gate),
          metadataGate.entered.future.then((_) => metadataGate),
        ]).timeout(_wait);
        final second = identical(first, gate) ? metadataGate : gate;
        final remainingKey = identical(second, gate)
            ? _cacheKey('old')
            : _subscriptionsKey;

        expect(_eventTitles(provider), [_oldTitle]);
        expect(_subscriptionSnapshot(provider), originalSubscriptions);
        expect(await store.diskRaw(_cacheKey('old')), raws[_cacheKey('old')]);
        expect(await store.diskRaw(_subscriptionsKey), raws[_subscriptionsKey]);
        expect(
          effects.eventTitles.expand((titles) => titles),
          isNot(contains(_newTitle)),
        );

        first.release.complete();
        await second.entered.future.timeout(_wait);

        expect(_eventTitles(provider), [_oldTitle]);
        expect(_subscriptionSnapshot(provider), originalSubscriptions);
        expect(await store.diskRaw(remainingKey), raws[remainingKey]);
        expect(effects.eventTitles, everyElement([_oldTitle]));
        expect(
          effects.subscriptionSnapshots,
          everyElement(originalSubscriptions),
        );

        second.release.complete();
        expect(await syncing, isNull);

        expect(_eventTitles(provider), [_newTitle]);
        expect(_storedEventTitles(prefs, 'old'), [_newTitle]);
        expect(
          provider.subscriptions.single.lastSyncedAt,
          isNot(DateTime.utc(2026, 11, 1)),
        );
        expect(
          _storedSubscriptions(prefs).single.lastSyncedAt,
          provider.subscriptions.single.lastSyncedAt,
        );
      });
    },
  );

  for (final rejectedKey in [_cacheKey('old'), _subscriptionsKey]) {
    test(
      'refresh rejection of $rejectedKey preserves cache and timestamp for retry',
      () async {
        await withFeed(() async {
          final raws = await seed();
          final originalSubscriptions = _subscriptionSnapshot(provider);
          final effects = _Effects(provider);
          store.rejectNext(rejectedKey);

          final failure = await capture(provider.syncAll());

          expect(
            failure != null || provider.lastError != null,
            isTrue,
            reason: 'refresh rejection must expose a failure outcome',
          );
          await expectStorage(raws);
          expect(_subscriptionSnapshot(provider), originalSubscriptions);
          expect(_eventTitles(provider), [_oldTitle]);
          expect(
            effects.eventTitles.expand((titles) => titles),
            isNot(contains(_newTitle)),
          );
          expect(
            effects.subscriptionSnapshots,
            everyElement(originalSubscriptions),
          );

          expect(await capture(provider.syncAll()), isNull);
          expect(_eventTitles(provider), [_newTitle]);
          expect(_storedEventTitles(prefs, 'old'), [_newTitle]);
          expect(
            _storedSubscriptions(prefs).single.lastSyncedAt,
            isNot(DateTime.utc(2026, 11, 1)),
          );
          expect(feed.requests, hasLength(2));
        });
      },
    );
  }

  for (final invalidation in [
    'delete',
    'pause',
    'URL edit',
    'reset',
    'dispose',
    'account cleanup',
  ]) {
    test(
      'held response after $invalidation cannot publish or recreate the outgoing cache',
      () async {
        await withFeed(() async {
          await seed();
          final effects = _Effects(provider);
          final gate = feed.holdNext();
          final syncing = capture(provider.syncAll());
          await gate.entered.future.timeout(_wait);
          switch (invalidation) {
            case 'delete':
              expect(
                await capture(
                  provider.removeSubscription('old'),
                ).timeout(_wait),
                isNull,
              );
            case 'pause':
              expect(
                await capture(
                  provider.updateSubscription(
                    provider.subscriptions.single.copyWith(enabled: false),
                  ),
                ).timeout(_wait),
                isNull,
              );
            case 'URL edit':
              expect(
                await capture(
                  provider.updateSubscription(
                    provider.subscriptions.single.copyWith(
                      url: 'https://feed.test/changed.ics',
                    ),
                  ),
                ).timeout(_wait),
                isNull,
              );
              expect(provider.subscriptions.single.lastSyncedAt, isNull);
              expect(
                provider.allEvents(),
                isEmpty,
                reason: 'the old URL cache is no longer an active source',
              );
            case 'reset':
              provider.resetLocalState();
            case 'dispose':
              provider.dispose();
              disposed = true;
            case 'account cleanup':
              // Isolate account invalidation from provider reset, and finish
              // cleanup before releasing the outgoing network response.
              expect(
                await capture(
                  AccountLocalDataCleaner.clearSharedPreferences(),
                ).timeout(_wait),
                isNull,
              );
              await expectStorage({
                _subscriptionsKey: null,
                _cacheKey('old'): null,
              });
          }
          final expectedSubscriptions = _subscriptionSnapshot(provider);
          final expectedEvents = _eventTitles(provider);
          final expectedRaw = <String, String?>{
            _subscriptionsKey: prefs.getString(_subscriptionsKey),
            _cacheKey('old'): prefs.getString(_cacheKey('old')),
          };

          gate.response.complete(_response());
          final outcome = await syncing;
          expect(
            outcome,
            isNot(isA<FlutterError>()),
            reason: 'the outgoing run must not notify a disposed provider',
          );

          await expectStorage(expectedRaw);
          expect(_subscriptionSnapshot(provider), expectedSubscriptions);
          expect(_eventTitles(provider), expectedEvents);
          expect(_eventTitles(provider), isNot(contains(_newTitle)));
          expect(
            effects.eventTitles.expand((titles) => titles),
            isNot(contains(_newTitle)),
          );
          if (invalidation == 'delete') {
            expect(provider.allEvents(), isEmpty);
          }
          if (invalidation == 'delete' || invalidation == 'account cleanup') {
            expect(prefs.getString(_cacheKey('old')), isNull);
          }
          if (invalidation == 'pause') expect(provider.allEvents(), isEmpty);
          if (invalidation == 'URL edit') {
            expect(
              provider.subscriptions.single.url,
              'https://feed.test/changed.ics',
            );
            expect(provider.subscriptions.single.lastSyncedAt, isNull);
          }
          if (invalidation == 'reset' ||
              invalidation == 'dispose' ||
              invalidation == 'account cleanup') {
            expect(
              provider.lastError,
              isNull,
              reason: 'outgoing run must not publish its error',
            );
          }
        });
      },
    );
  }

  test(
    'a 200 noncalendar response cannot erase a confirmed event cache',
    () async {
      await withFeed(() async {
        final raws = await seed();
        final originalSubscriptions = _subscriptionSnapshot(provider);
        feed.response = _response(body: '<html>Feed unavailable</html>');

        final failure = await capture(provider.syncAll());

        expect(
          failure != null || provider.lastError != null,
          isTrue,
          reason: 'a noncalendar body must expose a failure outcome',
        );
        await expectStorage(raws);
        expect(_eventTitles(provider), [_oldTitle]);
        expect(_subscriptionSnapshot(provider), originalSubscriptions);
      });
    },
  );

  test(
    'HTTP failure retains confirmed data and produces a failure outcome',
    () async {
      await withFeed(() async {
        final raws = await seed();
        final originalSubscriptions = _subscriptionSnapshot(provider);
        feed.response = _response(status: 503, body: 'Feed unavailable');

        final failure = await capture(provider.syncAll());

        await expectStorage(raws);
        expect(_eventTitles(provider), [_oldTitle]);
        expect(_subscriptionSnapshot(provider), originalSubscriptions);
        expect(
          failure != null || provider.lastError != null,
          isTrue,
          reason:
              'existing Future<void>/lastError API must not report silent success',
        );
      });
    },
  );

  test(
    'valid empty calendar commits zero events and an acknowledged timestamp',
    () async {
      await withFeed(() async {
        await seed();
        feed.response = _response(
          body: 'BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR\n',
        );

        expect(await capture(provider.syncAll()), isNull);

        expect(provider.allEvents(), isEmpty);
        expect(_storedEventTitles(prefs, 'old'), isEmpty);
        expect(provider.subscriptions.single.lastSyncedAt, isNotNull);
        expect(
          provider.subscriptions.single.lastSyncedAt,
          isNot(DateTime.utc(2026, 11, 1)),
        );
        expect(
          _storedSubscriptions(prefs).single.lastSyncedAt,
          provider.subscriptions.single.lastSyncedAt,
        );
      });
    },
  );
}

String _cacheKey(String id) => 'duoyi_ics_events_$id';

IcsSubscription _subscription(String id, {DateTime? synced}) => IcsSubscription(
  id: id,
  name: 'Literal 用户订阅 $id',
  url: 'https://feed.test/$id.ics',
  lastSyncedAt: synced,
);

Map<String, Object?> _cachedEvent() => {
  'id': 'ics_old_confirmed@test',
  'title': _oldTitle,
  'date': '2026-11-09T10:00:00.000',
  'endDate': '2026-11-09T11:00:00.000',
  'subtitle': 'Literal 原文',
  'colorValue': 0xFF42A5F5,
  'timeHour': 10,
  'timeMinute': 0,
};

List<Map<String, dynamic>> _subscriptionSnapshot(
  CalendarSyncProvider provider,
) => provider.subscriptions.map((sub) => sub.toJson()).toList();

List<String> _eventTitles(CalendarSyncProvider provider) =>
    provider.allEvents().map((event) => event.title).toList();

List<IcsSubscription> _storedSubscriptions(SharedPreferences prefs) =>
    (jsonDecode(prefs.getString(_subscriptionsKey) ?? '[]') as List)
        .map(
          (item) =>
              IcsSubscription.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();

List<String> _storedEventTitles(SharedPreferences prefs, String id) =>
    (jsonDecode(prefs.getString(_cacheKey(id)) ?? '[]') as List)
        .map((item) => (item as Map)['title'] as String)
        .toList();

http.Response _response({int status = 200, String body = _freshCalendar}) =>
    http.Response(
      body,
      status,
      headers: {'content-type': 'text/calendar; charset=utf-8'},
    );

class _Effects {
  _Effects(CalendarSyncProvider provider) {
    provider.addListener(() {
      subscriptionIds.add(provider.subscriptions.map((sub) => sub.id).toList());
      subscriptionSnapshots.add(_subscriptionSnapshot(provider));
      eventTitles.add(_eventTitles(provider));
    });
  }
  final subscriptionIds = <List<String>>[];
  final subscriptionSnapshots = <List<Map<String, dynamic>>>[];
  final eventTitles = <List<String>>[];
}

class _WriteGate {
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _HttpGate {
  final entered = Completer<void>();
  final response = Completer<http.Response>();
}

class _Feed {
  http.Response response = _response();
  final requests = <Uri>[];
  final _next = <_HttpGate>[];
  final _all = <_HttpGate>[];

  _HttpGate holdNext() {
    final gate = _HttpGate();
    _next.add(gate);
    _all.add(gate);
    return gate;
  }

  Future<http.Response> respond(http.Request request) async {
    requests.add(request.url);
    if (_next.isEmpty) return response;
    final gate = _next.removeAt(0);
    gate.entered.complete();
    return gate.response.future;
  }

  void releaseAll() {
    for (final gate in _all) {
      if (!gate.response.isCompleted) gate.response.complete(response);
    }
  }
}

class _IcsStore extends InMemorySharedPreferencesStore {
  _IcsStore() : super.withData(<String, Object>{});
  final writes = <String>[];
  final _holds = <String, _WriteGate>{};
  final _all = <_WriteGate>[];
  final _rejections = <String, bool>{};

  _WriteGate holdNext(String key) {
    final gate = _WriteGate();
    _holds[key] = gate;
    _all.add(gate);
    return gate;
  }

  void rejectNext(String key, {bool throws = false}) =>
      _rejections[key] = throws;

  void releaseAll() {
    for (final gate in _all) {
      if (!gate.release.isCompleted) gate.release.complete();
    }
  }

  Future<String?> diskRaw(String key) async =>
      (await getAll())['flutter.$key'] as String?;

  Future<bool> write(String key, Future<bool> Function() operation) async {
    final localKey = key.startsWith('flutter.') ? key.substring(8) : key;
    writes.add(localKey);
    final reject = _rejections.containsKey(localKey);
    final throws = _rejections.remove(localKey) ?? false;
    final gate = _holds.remove(localKey);
    if (gate != null) {
      gate.entered.complete();
      await gate.release.future;
    }
    // Model a platform that changes backing storage before rejecting the ACK.
    final saved = await operation();
    if (reject) {
      if (throws) throw StateError('synthetic $localKey write failure');
      return false;
    }
    return saved;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      write(key, () => super.setValue(type, key, value));

  @override
  Future<bool> remove(String key) => write(key, () => super.remove(key));
}
