// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/services/caldav_writer.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _uidsKey = 'duoyi_caldav_pushed_uids_v1';
const _etagsKey = 'duoyi_caldav_pushed_etags_v1';
const _targetKey = 'duoyi_caldav_write_target_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previousStore;

  setUp(() {
    previousStore = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    SharedPreferencesStorePlatform.instance = previousStore;
  });

  test(
    'full push keeps stable UIDs and ETags and deletes stale remote UIDs',
    () async {
      final existingUid = _uid('existing', CalendarEventType.event);
      final newUid = _uid('new', CalendarEventType.todo);
      final staleUid = _uid('stale', CalendarEventType.event);
      SharedPreferences.setMockInitialValues({
        _uidsKey: [existingUid, staleUid],
        _etagsKey: jsonEncode({
          existingUid: '"old-existing"',
          staleUid: '"stale"',
        }),
      });
      final writer = _FakeWriter()
        ..queueEtags(existingUid, ['"old-existing"', '"next-existing"'])
        ..queueEtags(newUid, ['"new-etag"'])
        ..queueEtags(staleUid, ['"stale"']);
      final fixture = await _fixture(writer);

      try {
        final count = await fixture.provider.pushEventsToCalDav([
          _event('existing', 'Existing title'),
          _event('new', 'New title', type: CalendarEventType.todo),
        ]);

        expect(count, 2);
        expect(writer.updates.map((call) => call.uid), [existingUid, newUid]);
        expect(writer.updates[0].ifMatch, '"old-existing"');
        expect(writer.updates[1].ifMatch, isNull);
        expect(writer.deletes, [staleUid]);
        expect(writer.deleteIfMatch[staleUid], '"stale"');
        expect(writer.calls, [
          'etag:$existingUid',
          'update:$existingUid',
          'etag:$existingUid',
          'update:$newUid',
          'etag:$newUid',
          'etag:$staleUid',
          'delete:$staleUid',
        ]);

        final prefs = fixture.preferences;
        expect(prefs.getStringList(_uidsKey), [existingUid, newUid]);
        expect(
          jsonDecode(prefs.getString(_etagsKey)!) as Map<String, dynamic>,
          {existingUid: '"next-existing"', newUid: '"new-etag"'},
        );
        final persistedTarget = CalDavWriteTarget.fromJson(
          jsonDecode(prefs.getString(_targetKey)!) as Map<String, dynamic>,
        );
        expect(persistedTarget.enabled, isTrue);
        expect(persistedTarget.lastTestedAt, isNotNull);
        expect(fixture.provider.writeTarget!.enabled, isTrue);
      } finally {
        fixture.dispose();
      }
    },
  );

  test('skipRemoteChanges leaves a changed remote event untouched', () async {
    final uid = _uid('remote-change', CalendarEventType.event);
    SharedPreferences.setMockInitialValues({
      _uidsKey: [uid],
      _etagsKey: jsonEncode({uid: '"local-etag"'}),
    });
    final writer = _FakeWriter()..queueEtags(uid, ['"remote-etag"']);
    final fixture = await _fixture(
      writer,
      conflictPolicy: CalDavConflictPolicy.skipRemoteChanges,
    );

    try {
      final count = await fixture.provider.pushEventsToCalDav([
        _event('remote-change', 'Local title'),
      ]);

      expect(count, 0);
      expect(writer.calls, ['etag:$uid']);
      expect(writer.updates, isEmpty);
      expect(writer.deletes, isEmpty);
      expect(fixture.provider.lastCalDavConflicts, hasLength(1));
      expect(fixture.provider.lastCalDavConflicts.single.uid, uid);
      expect(fixture.preferences.getStringList(_uidsKey), [uid]);
      expect(jsonDecode(fixture.preferences.getString(_etagsKey)!) as Map, {
        uid: '"local-etag"',
      });
    } finally {
      fixture.dispose();
    }
  });

  for (final stage in ['update', 'etag', 'delete']) {
    test(
      'owner invalidation after awaited $stage stops push and metadata commit',
      () async {
        final staleUid = _uid('stale-await', CalendarEventType.event);
        final seedUids = stage == 'delete' ? [staleUid] : <String>[];
        final seedEtags = stage == 'delete'
            ? jsonEncode({staleUid: '"stale-etag"'})
            : null;
        SharedPreferences.setMockInitialValues({
          if (seedUids.isNotEmpty) _uidsKey: seedUids,
          _etagsKey: ?seedEtags,
        });
        final writer = _FakeWriter()..holdOn(stage);
        final fixture = await _fixture(
          writer,
          conflictPolicy: CalDavConflictPolicy.overwriteRemote,
        );
        var ownerCurrent = true;
        final events = stage == 'delete'
            ? const <CalendarEvent>[]
            : [
                _event('first', 'First'),
                _event('second', 'Must not reach writer'),
              ];
        final pending = fixture.provider.pushEventsToCalDav(
          events,
          isCurrent: () => ownerCurrent,
        );
        final outcome = _capture(pending);

        try {
          await writer.gateStarted.future;
          ownerCurrent = false;
          writer.gateRelease.complete();
          expect(await outcome, isA<AccountPreferenceWriteCanceled>());

          expect(fixture.provider.writeTarget, same(fixture.target));
          expect(writer.calls, switch (stage) {
            'update' => ['update:${_uid('first', CalendarEventType.event)}'],
            'etag' => [
              'update:${_uid('first', CalendarEventType.event)}',
              'etag:${_uid('first', CalendarEventType.event)}',
            ],
            _ => ['delete:$staleUid'],
          });
          expect(fixture.preferences.getStringList(_uidsKey) ?? [], seedUids);
          expect(fixture.preferences.getString(_etagsKey), seedEtags);
          expect(
            fixture.preferences.getString(_targetKey),
            jsonEncode(fixture.target.toJson()),
          );
        } finally {
          if (!writer.gateRelease.isCompleted) writer.gateRelease.complete();
          await outcome;
          fixture.dispose();
        }
      },
    );
  }

  test('reset during update cannot revive the cleared target', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final writer = _FakeWriter()..holdOn('update');
    final fixture = await _fixture(writer);
    final pending = fixture.provider.pushEventsToCalDav([
      _event('held-reset', 'Held reset'),
    ]);
    final outcome = _capture(pending);

    try {
      await writer.gateStarted.future;
      fixture.provider.resetLocalState();
      writer.gateRelease.complete();

      expect(await outcome, isA<AccountPreferenceWriteCanceled>());
      expect(fixture.provider.writeTarget, isNull);
      expect(fixture.preferences.getStringList(_uidsKey), isNull);
      expect(fixture.preferences.getString(_etagsKey), isNull);
      expect(
        fixture.preferences.getString(_targetKey),
        jsonEncode(fixture.target.toJson()),
      );
      expect(writer.calls, [
        'update:${_uid('held-reset', CalendarEventType.event)}',
      ]);
    } finally {
      if (!writer.gateRelease.isCompleted) writer.gateRelease.complete();
      await outcome;
      fixture.dispose();
    }
  });

  test('target A to B to A does not restore an older push lease', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final writer = _FakeWriter()..holdOn('update');
    final fixture = await _fixture(writer);
    final targetA = fixture.target;
    final pending = fixture.provider.pushEventsToCalDav([
      _event('held-aba', 'Held A to B to A'),
    ]);
    final outcome = _capture(pending);

    try {
      await writer.gateStarted.future;
      final targetB = _target(
        collectionUrl: 'https://other.example.test/calendars/b/',
        authorizationHeader: 'Bearer account-B',
        conflictPolicy: CalDavConflictPolicy.overwriteRemote,
      );
      await fixture.provider.saveWriteTarget(targetB);
      await fixture.provider.saveWriteTarget(targetA);
      expect(fixture.provider.writeTarget, same(targetA));
      writer.gateRelease.complete();

      expect(await outcome, isA<AccountPreferenceWriteCanceled>());
      expect(fixture.provider.writeTarget, same(targetA));
      expect(fixture.preferences.getStringList(_uidsKey), isNull);
      expect(fixture.preferences.getString(_etagsKey), isNull);
      expect(
        fixture.preferences.getString(_targetKey),
        jsonEncode(targetA.toJson()),
      );
      expect(writer.calls, [
        'update:${_uid('held-aba', CalendarEventType.event)}',
      ]);
    } finally {
      if (!writer.gateRelease.isCompleted) writer.gateRelease.complete();
      await outcome;
      fixture.dispose();
    }
  });

  test(
    'a concurrent push is rejected while the first push owns the writer',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final writer = _FakeWriter()..holdOn('update');
      final fixture = await _fixture(writer);
      final first = _capture(
        fixture.provider.pushEventsToCalDav([_event('single-writer', 'First')]),
      );

      try {
        await writer.gateStarted.future;
        final second = _capture(
          fixture.provider.pushEventsToCalDav([
            _event('second-push', 'Second'),
          ]),
        );
        expect(await second, isA<StateError>());
        expect(writer.updates, hasLength(1));

        writer.gateRelease.complete();
        expect(await first, 1);
        expect(writer.updates, hasLength(1));
      } finally {
        if (!writer.gateRelease.isCompleted) writer.gateRelease.complete();
        await first;
        fixture.dispose();
      }
    },
  );

  for (final invalidation in ['reset', 'cleaner']) {
    test(
      'write target test does not delete or restore its event after create and $invalidation',
      () async {
        final writer = _FakeWriter()..holdOn('create');
        final fixture = await _fixture(writer);
        final originalTargetJson = jsonEncode(fixture.target.toJson());
        final outcome = _capture(fixture.provider.testWriteTarget());

        try {
          await writer.gateStarted.future;
          if (invalidation == 'reset') {
            fixture.provider.resetLocalState();
          } else {
            await AccountLocalDataCleaner.clearSharedPreferences();
          }
          writer.gateRelease.complete();

          expect(await outcome, isNull);
          expect(writer.creates, hasLength(1));
          expect(writer.deletes, isEmpty);
          if (invalidation == 'reset') {
            expect(fixture.provider.writeTarget, isNull);
            expect(
              fixture.preferences.getString(_targetKey),
              originalTargetJson,
            );
          } else {
            expect(fixture.provider.writeTarget, same(fixture.target));
            expect(fixture.preferences.getString(_targetKey), isNull);
          }
        } finally {
          if (!writer.gateRelease.isCompleted) writer.gateRelease.complete();
          await outcome;
          fixture.dispose();
        }
      },
    );
  }

  test(
    'target change during write target delete does not restore old target',
    () async {
      final writer = _FakeWriter()..holdOn('delete');
      final fixture = await _fixture(writer);
      final targetB = _target(
        collectionUrl: 'https://other.example.test/calendars/b/',
        authorizationHeader: 'Bearer account-B',
      );
      final testOutcome = _capture(fixture.provider.testWriteTarget());

      try {
        await writer.gateStarted.future;
        final saveOutcome = _capture(fixture.provider.saveWriteTarget(targetB));
        expect(await saveOutcome, isNull);
        writer.gateRelease.complete();

        expect(await testOutcome, isNull);
        expect(writer.creates, hasLength(1));
        expect(writer.deletes, hasLength(1));
        expect(fixture.provider.writeTarget, same(targetB));
        expect(
          fixture.preferences.getString(_targetKey),
          jsonEncode(targetB.toJson()),
        );
      } finally {
        if (!writer.gateRelease.isCompleted) writer.gateRelease.complete();
        await testOutcome;
        fixture.dispose();
      }
    },
  );

  test(
    'a push is rejected while a write target test owns the writer',
    () async {
      final writer = _FakeWriter()..holdOn('create');
      final fixture = await _fixture(writer);
      final testOutcome = _capture(fixture.provider.testWriteTarget());

      try {
        await writer.gateStarted.future;
        final pushOutcome = _capture(
          fixture.provider.pushEventsToCalDav([
            _event('during-test', 'Blocked'),
          ]),
        );
        expect(await pushOutcome, isA<StateError>());
        expect(writer.updates, isEmpty);
        expect(writer.deletes, isEmpty);

        writer.gateRelease.complete();
        expect(await testOutcome, isNull);
        expect(writer.creates, hasLength(1));
        expect(writer.deletes, hasLength(1));
      } finally {
        if (!writer.gateRelease.isCompleted) writer.gateRelease.complete();
        await testOutcome;
        fixture.dispose();
      }
    },
  );

  test('a write target test is skipped while a push owns the writer', () async {
    final writer = _FakeWriter()..holdOn('update');
    final fixture = await _fixture(writer);
    final pushOutcome = _capture(
      fixture.provider.pushEventsToCalDav([_event('during-push', 'First')]),
    );

    try {
      await writer.gateStarted.future;
      expect(await _capture(fixture.provider.testWriteTarget()), isNull);
      expect(writer.creates, isEmpty);
      expect(writer.calls, [
        'update:${_uid('during-push', CalendarEventType.event)}',
      ]);

      writer.gateRelease.complete();
      expect(await pushOutcome, 1);
      expect(writer.creates, isEmpty);
    } finally {
      if (!writer.gateRelease.isCompleted) writer.gateRelease.complete();
      await pushOutcome;
      fixture.dispose();
    }
  });

  test(
    'pending target save blocks new push and test requests on the old target',
    () async {
      final store = _PausingPreferenceStore();
      SharedPreferencesStorePlatform.instance = store;
      final writer = _FakeWriter();
      final fixture = await _fixture(writer);
      final targetB = _target(
        collectionUrl: 'https://other.example.test/calendars/b/',
        authorizationHeader: 'Bearer account-B',
      );
      store.hold('flutter.$_targetKey');
      final saveOutcome = _capture(fixture.provider.saveWriteTarget(targetB));
      Future<Object?>? pushOutcome;
      Future<Object?>? testOutcome;

      try {
        await store.writeStarted.future;
        expect(fixture.provider.writeTarget, same(fixture.target));
        pushOutcome = _capture(
          fixture.provider.pushEventsToCalDav([
            _event('pending-target', 'Blocked'),
          ]),
        );
        testOutcome = _capture(fixture.provider.testWriteTarget());
        await Future<void>.delayed(Duration.zero);

        expect(writer.calls, isEmpty);

        store.writeRelease.complete();
        expect(await saveOutcome, isNull);
        expect(
          await pushOutcome,
          anyOf(isA<StateError>(), isA<AccountPreferenceWriteCanceled>()),
        );
        expect(await testOutcome, isNull);
        expect(fixture.provider.writeTarget, same(targetB));
        expect(writer.calls, isEmpty);
      } finally {
        if (!store.writeRelease.isCompleted) store.writeRelease.complete();
        await saveOutcome;
        if (pushOutcome != null) await pushOutcome;
        if (testOutcome != null) await testOutcome;
        fixture.dispose();
      }
    },
  );

  test(
    'an in-flight push is invalidated when a target save is requested',
    () async {
      final store = _PausingPreferenceStore();
      SharedPreferencesStorePlatform.instance = store;
      final writer = _FakeWriter()..holdOn('update');
      final fixture = await _fixture(writer);
      final targetB = _target(
        collectionUrl: 'https://other.example.test/calendars/b/',
        authorizationHeader: 'Bearer account-B',
      );
      final pushOutcome = _capture(
        fixture.provider.pushEventsToCalDav([
          _event('intent-invalidates', 'A'),
        ]),
      );
      Future<Object?>? saveOutcome;
      store.hold('flutter.$_targetKey');

      try {
        await writer.gateStarted.future;
        saveOutcome = _capture(fixture.provider.saveWriteTarget(targetB));
        await store.writeStarted.future;
        expect(fixture.provider.writeTarget, same(fixture.target));

        writer.gateRelease.complete();
        expect(await pushOutcome, isA<AccountPreferenceWriteCanceled>());
        expect(writer.calls, [
          'update:${_uid('intent-invalidates', CalendarEventType.event)}',
        ]);

        store.writeRelease.complete();
        expect(await saveOutcome, isNull);
        expect(fixture.provider.writeTarget, same(targetB));
      } finally {
        if (!writer.gateRelease.isCompleted) writer.gateRelease.complete();
        if (!store.writeRelease.isCompleted) store.writeRelease.complete();
        await pushOutcome;
        if (saveOutcome != null) await saveOutcome;
        fixture.dispose();
      }
    },
  );

  test('account cleanup drains a held CalDAV metadata transaction', () async {
    final store = _PausingPreferenceStore();
    SharedPreferencesStorePlatform.instance = store;
    final writer = _FakeWriter();
    final fixture = await _fixture(writer);
    store.hold('flutter.$_uidsKey');
    final pushOutcome = _capture(
      fixture.provider.pushEventsToCalDav([_event('cleanup-held', 'Held')]),
    );
    var cleanupCompleted = false;
    Future<void>? cleanup;

    try {
      await store.writeStarted.future;
      cleanup = AccountLocalDataCleaner.clearSharedPreferences().whenComplete(
        () => cleanupCompleted = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cleanupCompleted, isFalse);

      store.writeRelease.complete();
      expect(await pushOutcome, isA<AccountPreferenceWriteCanceled>());
      await cleanup;
      expect(cleanupCompleted, isTrue);
      expect(fixture.preferences.getStringList(_uidsKey), isNull);
      expect(fixture.preferences.getString(_etagsKey), isNull);
      expect(fixture.preferences.getString(_targetKey), isNull);
    } finally {
      if (!store.writeRelease.isCompleted) store.writeRelease.complete();
      await pushOutcome;
      if (cleanup != null) await cleanup;
      fixture.dispose();
    }
  });

  test(
    'a disposed provider rollback cannot overwrite the next provider target',
    () async {
      final store = _PausingPreferenceStore();
      SharedPreferencesStorePlatform.instance = store;
      final writer = _FakeWriter();
      final firstFixture = await _fixture(writer);
      final targetB = _target(
        collectionUrl: 'https://other.example.test/calendars/b/',
        authorizationHeader: 'Bearer account-B',
      );
      store.hold('flutter.$_targetKey');
      final pushOutcome = _capture(
        firstFixture.provider.pushEventsToCalDav([_event('old-provider', 'A')]),
      );
      CalendarSyncProvider? secondProvider;
      Future<Object?>? saveOutcome;
      var firstProviderDisposed = false;
      var secondSaveCompleted = false;

      try {
        await store.writeStarted.future;
        firstFixture.provider.dispose();
        firstProviderDisposed = true;
        secondProvider = CalendarSyncProvider(
          calDavWriterFactory: (_, _) => writer,
        );
        saveOutcome = _capture(secondProvider.saveWriteTarget(targetB));
        saveOutcome.then((_) => secondSaveCompleted = true);
        await Future<void>.delayed(Duration.zero);
        expect(secondSaveCompleted, isFalse);
        expect(store.heldWriteAttempts, 1);

        store.writeRelease.complete();
        expect(await pushOutcome, isA<AccountPreferenceWriteCanceled>());
        expect(await saveOutcome, isNull);
        expect(secondSaveCompleted, isTrue);
        expect(secondProvider.writeTarget, same(targetB));
        expect(
          firstFixture.preferences.getString(_targetKey),
          jsonEncode(targetB.toJson()),
        );
        expect(firstFixture.preferences.getStringList(_uidsKey), isNull);
        expect(firstFixture.preferences.getString(_etagsKey), isNull);
      } finally {
        if (!store.writeRelease.isCompleted) store.writeRelease.complete();
        await pushOutcome;
        if (saveOutcome != null) await saveOutcome;
        if (!firstProviderDisposed) firstFixture.dispose();
        secondProvider?.dispose();
      }
    },
  );

  test('a rejected metadata save does not report push success', () async {
    final store = _RejectTargetStore();
    SharedPreferencesStorePlatform.instance = store;
    final writer = _FakeWriter()
      ..queueEtags(_uid('save-fails', CalendarEventType.event), [
        '"saved-etag"',
      ]);
    final fixture = await _fixture(writer);
    final originalTargetJson = jsonEncode(fixture.target.toJson());
    store.rejectTargetWrite = true;

    try {
      final outcome = _capture(
        fixture.provider.pushEventsToCalDav([
          _event('save-fails', 'Save failure'),
        ]),
      );
      expect(await outcome, isA<StateError>());
      expect(fixture.provider.lastError, isNotNull);
      expect(fixture.provider.lastCalDavError, fixture.provider.lastError);
      expect(fixture.provider.writeTarget, same(fixture.target));
      expect(fixture.preferences.getStringList(_uidsKey), isNull);
      expect(fixture.preferences.getString(_etagsKey), isNull);
      expect(fixture.preferences.getString(_targetKey), originalTargetJson);
    } finally {
      fixture.dispose();
    }
  });

  test(
    'guarded HEAD 405 does not issue fallback GET after owner invalidation',
    () async {
      var ownerCurrent = true;
      final methods = <String>[];
      final client = MockClient((request) async {
        methods.add(request.method);
        ownerCurrent = false;
        return http.Response('', 405);
      });
      final writer = HttpCalDavWriter(
        collectionUrl: 'https://caldav.example.test/user/default/',
        client: client,
        isCurrent: () => ownerCurrent,
      );

      try {
        await expectLater(
          writer.remoteEtag('event-1'),
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        expect(methods, ['HEAD']);
      } finally {
        client.close();
      }
    },
  );
}

Future<Object?> _capture<T>(Future<T> future) =>
    future.then<Object?>((value) => value, onError: (Object error) => error);

Future<_Fixture> _fixture(
  _FakeWriter writer, {
  CalDavConflictPolicy conflictPolicy = CalDavConflictPolicy.skipRemoteChanges,
}) async {
  final target = _target(conflictPolicy: conflictPolicy);
  final provider = CalendarSyncProvider(calDavWriterFactory: (_, _) => writer);
  await provider.saveWriteTarget(target);
  return _Fixture(
    provider: provider,
    writer: writer,
    target: target,
    preferences: await SharedPreferences.getInstance(),
  );
}

CalDavWriteTarget _target({
  String collectionUrl = 'https://caldav.example.test/user/default/',
  String authorizationHeader = 'Bearer account-A',
  CalDavConflictPolicy conflictPolicy = CalDavConflictPolicy.skipRemoteChanges,
}) => CalDavWriteTarget(
  collectionUrl: collectionUrl,
  authorizationHeader: authorizationHeader,
  enabled: true,
  conflictPolicy: conflictPolicy,
);

CalendarEvent _event(
  String id,
  String title, {
  CalendarEventType type = CalendarEventType.event,
}) => CalendarEvent(
  id: id,
  title: title,
  date: DateTime(2026, 10, 16),
  type: type,
  color: Colors.blue,
);

String _uid(String id, CalendarEventType type) =>
    'duoyi-$id-${type.name}@duoyi.local';

class _Fixture {
  const _Fixture({
    required this.provider,
    required this.writer,
    required this.target,
    required this.preferences,
  });

  final CalendarSyncProvider provider;
  final _FakeWriter writer;
  final CalDavWriteTarget target;
  final SharedPreferences preferences;

  void dispose() => provider.dispose();
}

class _FakeWriter implements CalDavWriter {
  final List<String> calls = [];
  final List<String> creates = [];
  final List<_UpdateCall> updates = [];
  final List<String> deletes = [];
  final Map<String, String?> deleteIfMatch = {};
  final Map<String, Queue<String?>> _etagReplies = {};
  String? _holdOperation;
  final Completer<void> gateStarted = Completer<void>();
  final Completer<void> gateRelease = Completer<void>();

  void queueEtags(String uid, Iterable<String?> etags) {
    _etagReplies[uid] = Queue<String?>.of(etags);
  }

  void holdOn(String operation) => _holdOperation = operation;

  Future<void> _pause(String operation) async {
    if (_holdOperation == operation && !gateStarted.isCompleted) {
      gateStarted.complete();
      await gateRelease.future;
    }
  }

  @override
  Future<String?> remoteEtag(String uid) async {
    calls.add('etag:$uid');
    await _pause('etag');
    final replies = _etagReplies[uid];
    return replies == null || replies.isEmpty ? null : replies.removeFirst();
  }

  @override
  Future<String> createEvent({
    required String summary,
    required DateTime start,
    required DateTime end,
    String? description,
    String? location,
  }) async {
    final uid = 'duoyi-test-${creates.length + 1}@duoyi.local';
    calls.add('create:$uid');
    creates.add(uid);
    await _pause('create');
    return uid;
  }

  @override
  Future<void> updateEvent({
    required String uid,
    required String summary,
    required DateTime start,
    required DateTime end,
    String? description,
    String? location,
    String? ifMatch,
  }) async {
    calls.add('update:$uid');
    updates.add(
      _UpdateCall(
        uid: uid,
        summary: summary,
        start: start,
        end: end,
        description: description,
        location: location,
        ifMatch: ifMatch,
      ),
    );
    await _pause('update');
  }

  @override
  Future<void> deleteEvent(String uid, {String? ifMatch}) async {
    calls.add('delete:$uid');
    deletes.add(uid);
    deleteIfMatch[uid] = ifMatch;
    await _pause('delete');
  }
}

class _UpdateCall {
  const _UpdateCall({
    required this.uid,
    required this.summary,
    required this.start,
    required this.end,
    required this.description,
    required this.location,
    required this.ifMatch,
  });

  final String uid;
  final String summary;
  final DateTime start;
  final DateTime end;
  final String? description;
  final String? location;
  final String? ifMatch;
}

class _RejectTargetStore extends InMemorySharedPreferencesStore {
  _RejectTargetStore() : super.withData(<String, Object>{});

  bool rejectTargetWrite = false;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (rejectTargetWrite && key == 'flutter.$_targetKey') {
      rejectTargetWrite = false;
      return false;
    }
    return super.setValue(type, key, value);
  }
}

class _PausingPreferenceStore extends InMemorySharedPreferencesStore {
  _PausingPreferenceStore() : super.withData(<String, Object>{});

  String? _holdKey;
  int heldWriteAttempts = 0;
  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> writeRelease = Completer<void>();

  void hold(String key) => _holdKey = key;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == _holdKey) {
      heldWriteAttempts++;
      if (!writeRelease.isCompleted) {
        if (!writeStarted.isCompleted) writeStarted.complete();
        await writeRelease.future;
      }
    }
    return super.setValue(type, key, value);
  }
}
