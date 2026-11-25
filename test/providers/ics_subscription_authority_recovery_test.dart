// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/ics_subscription_storage.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _listKey = 'duoyi_ics_subscriptions_v1';
const _wait = Duration(seconds: 3);
const _fetchedTitle = 'Fetched 用户事件';
const _calendar = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Duoyi//ICS authority fixture//EN
BEGIN:VEVENT
UID:fetched@test
DTSTAMP:20261109T100000Z
SUMMARY:Fetched 用户事件
DTSTART:20261109T110000
DTEND:20261109T120000
END:VEVENT
END:VCALENDAR
''';
const _emptyCalendar = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Duoyi//ICS authority fixture//EN
END:VCALENDAR
''';

// Exercises the public authority/result/recovery boundary. This fixture retains
// resolved result values and can separately hold or reject compensation writes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;

  setUp(() async {
    f = await _Fixture.create();
  });

  tearDown(() async {
    await f.close();
  });

  for (final operation in ['add', 'update', 'delete']) {
    test(
      'held $operation cancels revoked origin and restores exact confirmed state',
      () => f.withFeed(() async {
        final raw = await f.seed();
        final rows = _rows(f.provider);
        final titles = _titles(f.provider);
        var current = true;
        final gate = _WriteStep(hold: true);
        f.store.plan(operation == 'delete' ? _cacheKey('old') : _listKey, [
          gate,
        ]);
        Future<void> mutate() {
          if (operation == 'add') {
            return f.provider.addSubscription(
              _subscription('draft'),
              isCurrent: () => current,
            );
          }
          if (operation == 'update') {
            return f.provider.updateSubscription(
              _row(f.provider, 'old').copyWith(name: 'Edited 用户订阅'),
              isCurrent: () => current,
            );
          }
          return f.provider.removeSubscription('old', isCurrent: () => current);
        }

        final changing = f.watch(mutate());
        await gate.entered.future.timeout(_wait);
        expect(_rows(f.provider), rows);
        expect(_titles(f.provider), titles);
        expect(f.notifications.rows, everyElement(rows));
        current = false;
        final notificationCount = f.notifications.rows.length;
        gate.release.complete();

        expect(
          (await changing.timeout(_wait)).error,
          isA<AccountPreferenceWriteCanceled>(),
        );
        await f.expectRaw(raw);
        expect(_rows(f.provider), rows);
        expect(_titles(f.provider), titles);
        expect(f.notifications.rows, hasLength(notificationCount));
        expect(f.feed.requests, isEmpty);
      }),
    );
  }

  test(
    'origin predicate throwing after held ACK is cancellation with confirmed rollback',
    () async {
      final raw = await f.seed();
      final rows = _rows(f.provider);
      var throws = false;
      final gate = _WriteStep(hold: true);
      f.store.plan(_listKey, [gate]);
      final changing = f.watch(
        f.provider.addSubscription(
          _subscription('draft'),
          isCurrent: () {
            if (throws) throw StateError('revoked UI authority');
            return true;
          },
        ),
      );
      await gate.entered.future.timeout(_wait);
      throws = true;
      gate.release.complete();

      expect(
        (await changing.timeout(_wait)).error,
        isA<AccountPreferenceWriteCanceled>(),
      );
      await f.expectRaw(raw);
      expect(_rows(f.provider), rows);
      expect(f.provider.icsStorageNeedsReconciliation, isFalse);
    },
  );

  test(
    'reset during held update revokes lifetime and cannot republish old rows',
    () async {
      final raw = await f.seed();
      final generation = f.provider.icsLifetimeGeneration;
      final gate = _WriteStep(hold: true);
      f.store.plan(_listKey, [gate]);
      final changing = f.watch(
        f.provider.updateSubscription(
          _row(f.provider, 'old').copyWith(name: 'Edited 用户订阅'),
        ),
      );
      await gate.entered.future.timeout(_wait);
      f.provider.resetLocalState();
      expect(f.provider.icsLifetimeGeneration, greaterThan(generation));
      final notificationCount = f.notifications.rows.length;
      gate.release.complete();

      expect(
        (await changing.timeout(_wait)).error,
        isA<AccountPreferenceWriteCanceled>(),
      );
      await f.expectRaw(raw);
      expect(f.provider.subscriptions, isEmpty);
      expect(f.provider.allEvents(), isEmpty);
      expect(f.notifications.rows, hasLength(notificationCount));
    },
  );

  test(
    'dispose during held second delete write restores both keys without notifying',
    () async {
      final raw = await f.seed();
      final rows = _rows(f.provider);
      final gate = _WriteStep(hold: true);
      f.store.plan(_cacheKey('old'), [gate]);
      final changing = f.watch(f.provider.removeSubscription('old'));
      await gate.entered.future.timeout(_wait);
      expect(_rows(f.provider), rows);
      f.disposeProvider(f.provider);
      final notificationCount = f.notifications.rows.length;
      gate.release.complete();

      expect(
        (await changing.timeout(_wait)).error,
        isA<AccountPreferenceWriteCanceled>(),
      );
      await f.expectRaw(raw);
      expect(_rows(f.provider), rows);
      expect(f.notifications.rows, hasLength(notificationCount));
    },
  );

  test(
    'cleanup drains held and queued writes and rejects a new boundary mutation',
    () async {
      await f.seed();
      final peer = await f.peer();
      final gate = _WriteStep(hold: true);
      f.store.plan(_listKey, [gate]);
      final first = f.watch(f.provider.addSubscription(_subscription('first')));
      await gate.entered.future.timeout(_wait);
      final queued = f.watch(peer.addSubscription(_subscription('queued')));
      var cleanupFinished = false;
      final cleanup = f.watch(AccountLocalDataCleaner.clearSharedPreferences());
      unawaited(
        cleanup.then<void>((_) {
          cleanupFinished = true;
        }),
      );
      expect(AccountPreferenceWrites.isBoundaryActive, isTrue);
      expect(
        await f.failure(
          f.provider.addSubscription(_subscription('during-boundary')),
        ),
        isA<AccountPreferenceWriteCanceled>(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cleanupFinished, isFalse);
      expect(f.store.writes, [_listKey]);
      expect(_rows(f.provider).map((row) => row['id']), ['old', 'other']);
      gate.release.complete();

      expect(
        (await first.timeout(_wait)).error,
        isA<AccountPreferenceWriteCanceled>(),
      );
      expect(
        (await queued.timeout(_wait)).error,
        isA<AccountPreferenceWriteCanceled>(),
      );
      expect((await cleanup.timeout(_wait)).error, isNull);
      expect(AccountPreferenceWrites.isBoundaryActive, isFalse);
      await f.expectRaw({
        _listKey: null,
        _cacheKey('old'): null,
        _cacheKey('other'): null,
      });
      expect(f.provider.icsStorageNeedsReconciliation, isFalse);

      await f.ok(peer.addSubscription(_subscription('fresh')));
      expect(_rows(peer).map((row) => row['id']), ['fresh']);
      expect(_storedRows(f.prefs).map((row) => row['id']), ['fresh']);
    },
  );

  test(
    'stable ID with a different configuration rejects without storage or metadata changes',
    () async {
      final raw = await f.seed();
      final original = _row(f.provider, 'old');
      final rows = _rows(f.provider);

      expect(
        await f.failure(
          f.provider.addSubscription(
            original.copyWith(
              name: 'Conflicting 用户订阅',
              url: 'https://feed.test/different.ics',
            ),
          ),
        ),
        isA<StateError>(),
      );

      await f.expectRaw(raw);
      expect(_rows(f.provider), rows);
      expect(f.store.writes, isEmpty);
      await f.ok(
        f.provider.addSubscription(original.copyWith(clearLastSyncedAt: true)),
      );
      await f.expectRaw(raw);
      expect(_row(f.provider, 'old').lastSyncedAt, original.lastSyncedAt);
      expect(f.store.writes, isEmpty);
    },
  );

  for (final aba in ['pause/resume', 'delete/readd']) {
    test(
      'cross-provider $aba keeps an identical-source old response canceled',
      () => f.withFeed(() async {
        await f.seed();
        final peer = await f.peer();
        final original = _row(peer, 'old');
        final gate = f.feed.holdNext();
        final refreshing = f.watch(f.provider.syncSubscription('old'));
        await gate.entered.future.timeout(_wait);
        if (aba == 'pause/resume') {
          await f.ok(
            peer.updateSubscription(original.copyWith(enabled: false)),
          );
          await f.ok(peer.updateSubscription(original));
        } else {
          await f.ok(peer.removeSubscription('old'));
          await f.ok(peer.addSubscription(original));
        }
        final raw = await f.rawSnapshot();
        final rows = _rows(peer);
        gate.response.complete(_response());
        final result = _refreshValue(await refreshing.timeout(_wait));

        expect(result.subscriptionId, 'old');
        expect(result.status, IcsRefreshStatus.canceled);
        expect(result.isSuccess, isFalse);
        await f.expectRaw(raw);
        expect(_rows(peer), rows);
        expect(_titles(peer), isNot(contains(_fetchedTitle)));
        expect(_titles(f.provider), isNot(contains(_fetchedTitle)));
        expect(_row(peer, 'old').lastSyncedAt, original.lastSyncedAt);
        expect(f.feed.requests, [Uri.parse(original.url)]);
      }),
    );
  }

  test(
    'targeted HTTP and malformed-body failures retain source-owned confirmed baselines',
    () => f.withFeed(() async {
      final raw = await f.seed();
      final rows = _rows(f.provider);
      f.feed.response = _response(status: 503, body: 'Feed unavailable');

      final result = await f.refresh(f.provider.syncSubscription('old'));

      expect(result.subscriptionId, 'old');
      expect(result.status, IcsRefreshStatus.httpFailure);
      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
      expect(f.provider.icsRefreshResults['old'], same(result));
      await f.expectRaw(raw);
      expect(_rows(f.provider), rows);
      expect(_titles(f.provider), [
        _confirmedTitle('old'),
        _confirmedTitle('other'),
      ]);
      expect(f.feed.requests, [Uri.parse(_subscription('old').url)]);
      expect(f.store.writes, isEmpty);

      f.feed.response = _response(
        body: _calendar.replaceFirst('END:VEVENT\n', ''),
      );
      final malformed = await f.refresh(f.provider.syncSubscription('old'));
      expect(malformed.subscriptionId, 'old');
      expect(malformed.status, IcsRefreshStatus.invalidCalendar);
      expect(f.provider.icsRefreshResults['old'], same(malformed));
      expect(malformed.isSuccess, isFalse);
      expect(malformed.error, isA<FormatException>());
      await f.expectRaw(raw);
      expect(_rows(f.provider), rows);
      expect(f.feed.requests, [
        Uri.parse(_subscription('old').url),
        Uri.parse(_subscription('old').url),
      ]);
      expect(f.store.writes, isEmpty);
    }),
  );

  test(
    'indeterminate mutation notifies current observers without publishing draft',
    () async {
      await f.seed();
      final rows = _rows(f.provider);
      await f.makeUncertainAdd();
      expect(f.provider.icsStorageNeedsReconciliation, isTrue);
      expect(
        f.notifications.rows,
        [rows],
        reason: 'the parent recovery banner must learn the current diagnostic',
      );
      expect(_rows(f.provider), rows);
    },
  );

  test(
    'CalDAV diagnostic survives unrelated ICS failure and hides after account revoke',
    () => f.withFeed(() async {
      await f.seed();
      await f.provider.testWriteTarget();
      final diagnostic = f.provider.lastCalDavError;
      expect(diagnostic, isNotNull);
      f.feed.response = _response(status: 503, body: 'Feed unavailable');
      await f.refresh(f.provider.syncSubscription('old'));
      expect(f.provider.lastCalDavError, diagnostic);
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      expect(f.provider.lastCalDavError, isNull);
    }),
  );

  test(
    'per-source results retain the owned failure when a stale origin cancels',
    () => f.withFeed(() async {
      await f.seed();
      f.feed.response = _response(status: 503, body: 'Feed unavailable');
      final failure = await f.refresh(f.provider.syncSubscription('old'));
      expect(f.provider.lastError, isNotNull);
      expect(
        f.provider.lastCalDavError,
        isNull,
        reason: 'an ICS failure must not become a CalDAV card error',
      );
      final notices = f.notifications.rows.length;
      final requests = f.feed.requests.length;
      final error = f.provider.lastError;
      for (final predicate in <bool Function()>[
        () => false,
        () => throw StateError('revoked UI'),
      ]) {
        final canceled = await f.refresh(
          f.provider.syncSubscription('old', isCurrent: predicate),
        );
        expect(canceled.status, IcsRefreshStatus.canceled);
        expect(f.provider.isSyncing, isFalse);
        expect(f.provider.lastError, error);
        expect(f.provider.icsRefreshResults['old'], same(failure));
        expect(f.notifications.rows, hasLength(notices));
        expect(f.feed.requests, hasLength(requests));
      }
      await f.ok(
        f.provider.updateSubscription(
          _row(f.provider, 'old').copyWith(url: 'https://feed.test/new.ics'),
        ),
      );
      expect(f.provider.icsRefreshResults.containsKey('old'), isFalse);
      await f.refresh(f.provider.syncSubscription('old'));
      expect(f.provider.icsRefreshResults.containsKey('old'), isTrue);
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      expect(f.provider.icsRefreshResults, isEmpty);
    }),
  );

  test(
    'global refresh rejects an already revoked caller without HTTP or writes',
    () => f.withFeed(() async {
      final raw = await f.seed();
      final notifications = f.notifications.rows.length;
      await f.provider.syncAll(isCurrent: () => false);
      await f.expectRaw(raw);
      expect(f.feed.requests, isEmpty);
      expect(f.provider.isSyncing, isFalse);
      expect(f.notifications.rows, hasLength(notifications));
    }),
  );

  test(
    'global refresh revocation during HTTP preserves cache and stops later sources',
    () => f.withFeed(() async {
      final raw = await f.seed();
      final rows = _rows(f.provider);
      var current = true;
      final gate = f.feed.holdNext();
      final operation = f.watch(f.provider.syncAll(isCurrent: () => current));
      await gate.entered.future.timeout(_wait);
      current = false;
      final notifications = f.notifications.rows.length;
      gate.response.complete(_response());
      expect((await operation.timeout(_wait)).error, isNull);
      await f.expectRaw(raw);
      expect(_rows(f.provider), rows);
      expect(f.feed.requests, hasLength(1));
      expect(f.provider.icsRefreshResults, isEmpty);
      expect(f.provider.isSyncing, isFalse);
      expect(f.notifications.rows, hasLength(notifications));
    }),
  );

  test(
    'stale provider reads latest URL and stale later source cannot revoke a newer request',
    () => f.withFeed(() async {
      final raw = await f.seed();
      final peer = await f.peer();
      final oldUrl = _row(f.provider, 'old').url;
      final currentUrl = 'https://feed.test/current.ics';
      await f.ok(
        peer.updateSubscription(_row(peer, 'old').copyWith(url: currentUrl)),
      );
      expect(
        _row(f.provider, 'old').url,
        oldUrl,
        reason: 'the outgoing provider is deliberately stale before syncAll',
      );
      final priorGate = f.feed.holdNext();
      final prior = f.watch(peer.syncSubscription('old'));
      await priorGate.entered.future.timeout(_wait);
      final oldGate = f.feed.holdNext();
      final all = f.watch(f.provider.syncAll());
      await oldGate.entered.future.timeout(_wait);
      expect(
        f.feed.requests,
        [Uri.parse(currentUrl), Uri.parse(currentUrl)],
        reason:
            'syncAll must read durable source configuration, never the obsolete provider URL',
      );
      priorGate.response.complete(_response());
      expect(
        _refreshValue(await prior.timeout(_wait)).status,
        IcsRefreshStatus.canceled,
        reason:
            'a current syncAll request may supersede the earlier targeted request',
      );
      final other = _row(peer, 'other');
      await f.ok(peer.updateSubscription(other.copyWith(enabled: false)));
      await f.ok(peer.updateSubscription(other));
      final newGate = f.feed.holdNext();
      final targeted = f.watch(peer.syncSubscription('other'));
      await newGate.entered.future.timeout(_wait);
      oldGate.response.complete(_response());

      expect((await all.timeout(_wait)).error, isNull);
      expect(peer.isSyncing, isTrue);
      expect(
        f.feed.requests,
        [Uri.parse(currentUrl), Uri.parse(currentUrl), Uri.parse(other.url)],
        reason:
            'the stale other-source snapshot must neither dispatch nor claim request ownership',
      );
      expect(await f.store.raw(_cacheKey('other')), raw[_cacheKey('other')]);
      newGate.response.complete(_response());
      final result = _refreshValue(await targeted.timeout(_wait));

      expect(result.subscriptionId, 'other');
      expect(result.status, IcsRefreshStatus.refreshed);
      expect(result.eventCount, 1);
      expect(result.error, isNull);
      expect(peer.isSyncing, isFalse);
      expect(_row(f.provider, 'old').url, currentUrl);
      expect(peer.allEvents().map((event) => event.id), [
        'ics_old_fetched@test',
        'ics_other_fetched@test',
      ]);
    }),
  );

  test(
    'targeted valid empty result confirms zero events without refreshing unrelated source',
    () => f.withFeed(() async {
      final raw = await f.seed();
      final originalOther = _row(f.provider, 'other').toJson();
      final oldTimestamp = _row(f.provider, 'old').lastSyncedAt;
      f.feed.response = _response(body: _emptyCalendar);

      final result = await f.refresh(f.provider.syncSubscription('old'));

      expect(result.subscriptionId, 'old');
      expect(result.status, IcsRefreshStatus.refreshed);
      expect(result.isSuccess, isTrue);
      expect(result.eventCount, 0);
      expect(result.error, isNull);
      expect(_titles(f.provider), [_confirmedTitle('other')]);
      expect(_row(f.provider, 'old').lastSyncedAt, isNotNull);
      expect(_row(f.provider, 'old').lastSyncedAt, isNot(oldTimestamp));
      expect(_row(f.provider, 'other').toJson(), originalOther);
      final accepted = await f.rawSnapshot();
      await f.expectRaw(accepted);
      expect(jsonDecode(accepted[_cacheKey('old')]!), isEmpty);
      expect(accepted[_cacheKey('other')], raw[_cacheKey('other')]);
      expect(
        _storedRows(
          f.prefs,
        ).firstWhere((row) => row['id'] == 'old')['lastSyncedAt'],
        _row(f.provider, 'old').lastSyncedAt!.toIso8601String(),
      );
      expect(f.feed.requests, [Uri.parse(_subscription('old').url)]);
    }),
  );

  test(
    'targeted metadata rejection reports storageFailure then one refresh retry commits',
    () => f.withFeed(() async {
      final raw = await f.seed();
      final rows = _rows(f.provider);
      f.store.plan(_listKey, [_WriteStep(mode: _WriteMode.afterFalse)]);

      final failure = await f.refresh(f.provider.syncSubscription('old'));

      expect(failure.subscriptionId, 'old');
      expect(failure.status, IcsRefreshStatus.storageFailure);
      expect(failure.isSuccess, isFalse);
      expect(failure.error, isNotNull);
      expect(f.provider.icsStorageNeedsReconciliation, isFalse);
      await f.expectRaw(raw);
      expect(_rows(f.provider), rows);
      expect(
        f.notifications.titles.expand((titles) => titles),
        isNot(contains(_fetchedTitle)),
      );

      final retry = await f.refresh(f.provider.syncSubscription('old'));
      expect(retry.status, IcsRefreshStatus.refreshed);
      expect(retry.eventCount, 1);
      expect(retry.error, isNull);
      expect(_titles(f.provider), [_fetchedTitle, _confirmedTitle('other')]);
      expect(_rows(f.provider).map((row) => row['id']), ['old', 'other']);
      final accepted = await f.rawSnapshot();
      await f.expectRaw(accepted);
      expect(accepted[_cacheKey('other')], raw[_cacheKey('other')]);
      expect(f.feed.requests, hasLength(2));
    }),
  );

  test(
    'replacement waits for failed compensation and requires explicit reconciliation before retry',
    () async {
      final raw = await f.seed();
      final rows = _rows(f.provider);
      final compensation = _WriteStep(mode: _WriteMode.beforeFalse, hold: true);
      f.store.plan(_listKey, [
        _WriteStep(mode: _WriteMode.afterThrow),
        compensation,
      ]);
      final changing = f.watch(
        f.provider.addSubscription(_subscription('draft')),
      );
      await compensation.entered.future.timeout(_wait);
      final peer = f.newProvider();
      var replacementFinished = false;
      final loading = f.watch(peer.loadFromStorage());
      unawaited(
        loading.then<void>((_) {
          replacementFinished = true;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(replacementFinished, isFalse);
      expect(_rows(f.provider), rows);
      compensation.release.complete();

      final diagnostic = (await changing.timeout(_wait)).error;
      expect(diagnostic, isA<IcsStorageIndeterminate>());
      expect((await loading.timeout(_wait)).error, same(diagnostic));
      expect(peer.icsStorageNeedsReconciliation, isTrue);
      expect(peer.icsStorageFailure, same(diagnostic));
      final writeCount = f.store.writes.length;
      expect(
        await f.failure(peer.addSubscription(_subscription('draft'))),
        same(diagnostic),
      );
      expect(f.store.writes, hasLength(writeCount));

      await f.ok(peer.reconcileIcsStorage());
      expect(peer.icsStorageNeedsReconciliation, isFalse);
      expect(peer.icsStorageFailure, isNull);
      await f.expectRaw(raw);
      expect(_rows(peer), rows);
      await f.ok(peer.addSubscription(_subscription('draft')));
      expect(
        peer.subscriptions.where((row) => row.id == 'draft'),
        hasLength(1),
      );
    },
  );

  test(
    'reconciliation restores only attempted delta and preserves independent unrelated raw edits',
    () async {
      final raw = await f.seed();
      await f.makeUncertainAdd();
      final peer = f.newProvider();
      final independent = _decodeRows((await f.store.raw(_listKey))!);
      independent.firstWhere((row) => row['id'] == 'other')['name'] =
          'Independent 用户订阅';
      independent.add(_subscription('external').toJson());
      final otherCache =
          '[\n${jsonEncode(_cachedEvent('other', title: 'Independent 缓存事件'))}\n]\n';
      await f.store.putRaw(_listKey, jsonEncode(independent));
      await f.store.putRaw(_cacheKey('other'), otherCache);

      await f.ok(peer.reconcileIcsStorage());

      expect(peer.icsStorageNeedsReconciliation, isFalse);
      expect(_rows(peer).map((row) => row['id']), ['old', 'other', 'external']);
      expect(_row(peer, 'other').name, 'Independent 用户订阅');
      expect(_row(peer, 'old').toJson(), _decodeRows(raw[_listKey]!).first);
      expect(await f.store.raw(_cacheKey('old')), raw[_cacheKey('old')]);
      expect(await f.store.raw(_cacheKey('other')), otherCache);
      expect(_titles(peer), [_confirmedTitle('old'), 'Independent 缓存事件']);
      await f.ok(peer.addSubscription(_subscription('draft')));
      expect(_rows(peer).map((row) => row['id']), [
        'old',
        'other',
        'external',
        'draft',
      ]);
      expect(_row(peer, 'other').name, 'Independent 用户订阅');
    },
  );

  test(
    'independent affected row edit during ACK blocks compensation and explicit reconciliation',
    () async {
      final raw = await f.seed();
      final rows = _rows(f.provider);
      final gate = _WriteStep(
        mode: _WriteMode.afterThrow,
        hold: true,
        holdAfterApply: true,
      );
      f.store.plan(_listKey, [gate]);
      final changing = f.watch(
        f.provider.updateSubscription(
          _row(f.provider, 'old').copyWith(name: 'Attempted 用户订阅'),
        ),
      );
      await gate.entered.future.timeout(_wait);
      final independent = _decodeRows((await f.store.raw(_listKey))!);
      independent.firstWhere((row) => row['id'] == 'old')['name'] =
          'Independent affected 用户订阅';
      final independentRaw = jsonEncode(independent);
      await f.store.putRaw(_listKey, independentRaw);
      gate.release.complete();
      final diagnostic = (await changing.timeout(_wait)).error;
      expect(diagnostic, isA<IcsStorageIndeterminate>());
      expect(
        await f.store.raw(_listKey),
        independentRaw,
        reason:
            'automatic compensation must not overwrite the independent affected row',
      );
      final peer = f.newProvider();
      final writeCount = f.store.writes.length;

      expect(await f.failure(peer.reconcileIcsStorage()), same(diagnostic));

      expect(f.store.writes, hasLength(writeCount));
      expect(peer.icsStorageNeedsReconciliation, isTrue);
      expect(await f.store.raw(_listKey), independentRaw);
      expect(await f.store.raw(_cacheKey('old')), raw[_cacheKey('old')]);
      expect(await f.store.raw(_cacheKey('other')), raw[_cacheKey('other')]);
      expect(_rows(f.provider), rows);
      expect(
        await f.failure(peer.addSubscription(_subscription('draft'))),
        same(diagnostic),
      );
      expect(f.store.writes, hasLength(writeCount));
    },
  );

  test(
    'independent affected cache blocks reconciliation without overwriting unrelated list edits',
    () => f.withFeed(() async {
      await f.seed();
      f.store.plan(_cacheKey('old'), [
        _WriteStep(),
        _WriteStep(mode: _WriteMode.beforeFalse),
      ]);
      f.store.plan(_listKey, [_WriteStep(mode: _WriteMode.afterThrow)]);
      final failure = await f.refresh(f.provider.syncSubscription('old'));
      expect(failure.status, IcsRefreshStatus.storageFailure);
      expect(failure.error, isA<IcsStorageIndeterminate>());
      final peer = f.newProvider();
      final cache =
          '[\n${jsonEncode(_cachedEvent('old', title: 'Independent affected 缓存'))}\n]\n';
      final rows = _decodeRows((await f.store.raw(_listKey))!);
      rows.firstWhere((row) => row['id'] == 'other')['name'] =
          'Independent unrelated 用户订阅';
      final list = jsonEncode(rows);
      await f.store.putRaw(_cacheKey('old'), cache);
      await f.store.putRaw(_listKey, list);
      final writeCount = f.store.writes.length;

      expect(await f.failure(peer.reconcileIcsStorage()), same(failure.error));

      expect(peer.icsStorageNeedsReconciliation, isTrue);
      expect(f.store.writes, hasLength(writeCount));
      expect(await f.store.raw(_cacheKey('old')), cache);
      expect(await f.store.raw(_listKey), list);
      expect(_titles(f.provider), isNot(contains(_fetchedTitle)));
    }),
  );
}

String _cacheKey(String id) => 'duoyi_ics_events_$id';
String _confirmedTitle(String id) => 'Confirmed 用户事件 $id';

IcsSubscription _subscription(String id, {DateTime? synced}) => IcsSubscription(
  id: id,
  name: 'Literal 用户订阅 $id',
  url: 'https://feed.test/$id.ics',
  lastSyncedAt: synced,
);

Map<String, Object?> _cachedEvent(String id, {String? title}) => {
  'id': 'ics_${id}_confirmed@test',
  'title': title ?? _confirmedTitle(id),
  'date': '2026-11-09T10:00:00.000',
  'endDate': '2026-11-09T11:00:00.000',
  'subtitle': 'Literal 原文',
  'colorValue': 0xFF42A5F5,
  'timeHour': 10,
  'timeMinute': 0,
};

IcsSubscription _row(CalendarSyncProvider provider, String id) =>
    provider.subscriptions.singleWhere((row) => row.id == id);
List<Map<String, dynamic>> _rows(CalendarSyncProvider provider) =>
    provider.subscriptions.map((row) => row.toJson()).toList();
List<String> _titles(CalendarSyncProvider provider) =>
    provider.allEvents().map((event) => event.title).toList();
List<Map<String, dynamic>> _decodeRows(String raw) => (jsonDecode(raw) as List)
    .map((row) => Map<String, dynamic>.from(row as Map))
    .toList();
List<Map<String, dynamic>> _storedRows(SharedPreferences prefs) =>
    _decodeRows(prefs.getString(_listKey) ?? '[]');
http.Response _response({int status = 200, String body = _calendar}) =>
    http.Response(
      body,
      status,
      headers: {'content-type': 'text/calendar; charset=utf-8'},
    );

class _Outcome<T> {
  const _Outcome({this.value, this.error});
  final T? value;
  final Object? error;
}

IcsRefreshResult _refreshValue(_Outcome<IcsRefreshResult> outcome) {
  expect(
    outcome.error,
    isNull,
    reason: 'targeted refresh resolves its semantic result',
  );
  expect(outcome.value, isNotNull);
  return outcome.value!;
}

class _Fixture {
  _Fixture(this.previousStore, this.store, this.prefs) {
    provider = newProvider();
    notifications = _Notifications(provider);
  }
  final SharedPreferencesStorePlatform previousStore;
  final _Store store;
  final SharedPreferences prefs;
  final feed = _Feed();
  final pending = <Future<void>>[];
  final providers = <CalendarSyncProvider>[];
  final disposed = <CalendarSyncProvider>{};
  late final CalendarSyncProvider provider;
  late final _Notifications notifications;

  static Future<_Fixture> create() async {
    final previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    // Clear the shared coordinator through its public account boundary, using
    // only this fixture's store; never reset private global state manually.
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    store.writes.clear();
    return _Fixture(previous, store, prefs);
  }

  CalendarSyncProvider newProvider() {
    final result = CalendarSyncProvider();
    providers.add(result);
    return result;
  }

  Future<CalendarSyncProvider> peer() async {
    final result = newProvider();
    await ok(result.loadFromStorage());
    return result;
  }

  void disposeProvider(CalendarSyncProvider value) {
    if (disposed.add(value)) value.dispose();
  }

  Future<_Outcome<T>> watch<T>(Future<T> operation) {
    final result = operation.then<_Outcome<T>>(
      (value) => _Outcome<T>(value: value),
      onError: (Object error, StackTrace _) => _Outcome<T>(error: error),
    );
    pending.add(result.then<void>((_) {}));
    return result;
  }

  Future<void> ok(Future<void> operation) async {
    expect((await watch(operation).timeout(_wait)).error, isNull);
  }

  Future<Object> failure(Future<void> operation) async {
    final outcome = await watch(operation).timeout(_wait);
    expect(outcome.error, isNotNull);
    return outcome.error!;
  }

  Future<IcsRefreshResult> refresh(Future<IcsRefreshResult> operation) async =>
      _refreshValue(await watch(operation).timeout(_wait));

  Future<void> withFeed(Future<void> Function() body) =>
      http.runWithClient(body, () => MockClient(feed.respond));

  Future<Map<String, String?>> seed() async {
    final old = _subscription('old', synced: DateTime.utc(2026, 11, 1));
    final other = _subscription('other', synced: DateTime.utc(2026, 11, 2));
    final raw = <String, String?>{
      _listKey:
          '[\n  ${jsonEncode(old.toJson())},\n  ${jsonEncode(other.toJson())}\n]\n',
      _cacheKey('old'): '[\n  ${jsonEncode(_cachedEvent('old'))}\n]\n',
      _cacheKey('other'): '[\n  ${jsonEncode(_cachedEvent('other'))}\n]\n',
    };
    for (final entry in raw.entries) {
      expect(await prefs.setString(entry.key, entry.value!), isTrue);
    }
    await ok(provider.loadFromStorage());
    notifications.rows.clear();
    notifications.titles.clear();
    store.writes.clear();
    return raw;
  }

  Future<Map<String, String?>> rawSnapshot() async => {
    _listKey: await store.raw(_listKey),
    _cacheKey('old'): await store.raw(_cacheKey('old')),
    _cacheKey('other'): await store.raw(_cacheKey('other')),
  };

  Future<void> expectRaw(Map<String, String?> raw) async {
    for (final entry in raw.entries) {
      expect(
        await store.raw(entry.key),
        entry.value,
        reason: 'backing ${entry.key}',
      );
      expect(
        prefs.getString(entry.key),
        entry.value,
        reason: 'cached ${entry.key}',
      );
    }
    await prefs.reload();
    for (final entry in raw.entries) {
      expect(
        prefs.getString(entry.key),
        entry.value,
        reason: 'reloaded ${entry.key}',
      );
    }
  }

  Future<IcsStorageIndeterminate> makeUncertainAdd() async {
    store.plan(_listKey, [
      _WriteStep(mode: _WriteMode.afterThrow),
      _WriteStep(mode: _WriteMode.beforeFalse),
    ]);
    final error = await failure(
      provider.addSubscription(_subscription('draft')),
    );
    expect(error, isA<IcsStorageIndeterminate>());
    return error as IcsStorageIndeterminate;
  }

  Future<void> close() async {
    // Release active/queued holds first; remove unused injections so fixture
    // retirement cannot inherit a failure intended for an unissued test write.
    store.releaseAll();
    feed.releaseAll();
    store.clearPendingScripts();
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    } finally {
      for (final value in providers) {
        disposeProvider(value);
      }
      SharedPreferencesStorePlatform.instance = previousStore;
    }
  }
}

class _Notifications {
  _Notifications(CalendarSyncProvider provider) {
    provider.addListener(() {
      rows.add(_rows(provider));
      titles.add(_titles(provider));
    });
  }
  final rows = <List<Map<String, dynamic>>>[];
  final titles = <List<String>>[];
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

enum _WriteMode { apply, afterFalse, afterThrow, beforeFalse }

class _WriteStep {
  _WriteStep({
    this.mode = _WriteMode.apply,
    this.hold = false,
    this.holdAfterApply = false,
  });
  final _WriteMode mode;
  final bool hold;
  final bool holdAfterApply;
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData(<String, Object>{});
  final writes = <String>[];
  final _plans = <String, List<_WriteStep>>{};
  final _all = <_WriteStep>[];

  void plan(String key, List<_WriteStep> steps) {
    _plans.putIfAbsent(key, () => []).addAll(steps);
    _all.addAll(steps);
  }

  void releaseAll() {
    for (final step in _all) {
      if (!step.release.isCompleted) step.release.complete();
    }
  }

  void clearPendingScripts() => _plans.clear();
  Future<String?> raw(String key) async =>
      (await getAll())['flutter.$key'] as String?;

  // Simulate an independent raw writer without updating the legacy preferences
  // cache or consuming the test operation's scripted platform ACKs.
  Future<void> putRaw(String key, String? value) async {
    final saved = value == null
        ? await super.remove('flutter.$key')
        : await super.setValue('String', 'flutter.$key', value);
    expect(saved, isTrue);
  }

  Future<bool> write(String key, Future<bool> Function() operation) async {
    final local = key.startsWith('flutter.') ? key.substring(8) : key;
    writes.add(local);
    final planned = _plans[local];
    final step = planned == null || planned.isEmpty
        ? null
        : planned.removeAt(0);
    if (step != null) {
      if (!step.holdAfterApply) {
        step.entered.complete();
        if (step.hold) await step.release.future;
      }
      if (step.mode == _WriteMode.beforeFalse) return false;
    }
    final saved = await operation();
    if (step != null && step.holdAfterApply) {
      step.entered.complete();
      if (step.hold) await step.release.future;
    }
    if (step?.mode == _WriteMode.afterFalse) return false;
    if (step?.mode == _WriteMode.afterThrow) {
      throw StateError('synthetic $local write-then-throw');
    }
    return saved;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      write(key, () => super.setValue(type, key, value));

  @override
  Future<bool> remove(String key) => write(key, () => super.remove(key));
}
