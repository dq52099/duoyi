// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _wait = Duration(seconds: 5);
const _beforeTodo = '{"id":"before","title":"Original task"}';
const _importedTodo = '{"id":"imported","title":"Imported task"}';
const _successorTodo = '{"id":"successor","title":"Successor task"}';
const _initial = <String, Object>{
  'todos': <String>[_beforeTodo],
  'user_profile': 'original profile',
  'duoyi_notes': <String>['original note'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _AuthorityBackingStore store;
  late SharedPreferences preferences;
  late int preferenceGeneration;
  late int accountGeneration;

  setUp(() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    SharedPreferences.setMockInitialValues(_initial);
    store = _AuthorityBackingStore(_initial);
    SharedPreferencesStorePlatform.instance = store;
    preferences = await SharedPreferences.getInstance();
    preferenceGeneration = AccountPreferenceWrites.generation;
    accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
  });

  tearDown(() async {
    // A failed assertion must not leave this test's issued write blocking drain.
    store.releaseAll();
    await AccountPreferenceWrites.drain().timeout(_wait);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  void expectSameAccount() {
    expect(AccountPreferenceWrites.generation, preferenceGeneration);
    expect(AccountLocalDataCleaner.accountDataGeneration, accountGeneration);
  }

  test('current import authority commits real backing values', () async {
    expect(
      await BackupService.importAll(
        _backup(<String, Object>{
          'todos': _list(<String>[_importedTodo]),
          'user_profile': _string('imported profile'),
          'pref_haptic_feedback': <String, Object>{
            'type': 'bool',
            'value': false,
          },
        }),
        canWrite: () => true,
      ),
      3,
    );

    await _expectBackingAndReload(preferences, store, <String, Object>{
      ..._initial,
      'todos': <String>[_importedTodo],
      'user_profile': 'imported profile',
      'pref_haptic_feedback': false,
    });
    expect(store.valuesWritten('flutter.todos'), <Object>[
      <String>[_importedTodo],
    ]);
    expect(store.valuesWritten('flutter.user_profile'), <Object>[
      'imported profile',
    ]);
    expect(store.removedKeys, isEmpty);
    expectSameAccount();
  });

  test('already revoked import authority performs zero writes', () async {
    final outcome = _outcome(
      BackupService.importAll(
        _backup(<String, Object>{
          'todos': _list(<String>[_importedTodo]),
          'user_profile': _string('must not be written'),
        }),
        clearMissing: true,
        canWrite: () => false,
      ),
    );

    expect(await outcome.timeout(_wait), isA<AccountPreferenceWriteCanceled>());
    expect(store.writes, isEmpty);
    expect(store.removedKeys, isEmpty);
    await _expectBackingAndReload(preferences, store, _initial);
    expectSameAccount();
  });

  test(
    'queued import revoked while a predecessor is held writes nothing',
    () async {
      final held = store.hold(
        'flutter.user_profile',
        _WritePhase.beforePersist,
      );
      final predecessor = _outcome(
        BackupService.importAll(
          _backup(<String, Object>{
            'user_profile': _string('queue predecessor'),
          }),
          canWrite: () => true,
        ),
      );
      await held.entered.future.timeout(_wait);

      var authorized = true;
      var queuedFinished = false;
      final queued =
          _outcome(
            BackupService.importAll(
              _backup(<String, Object>{
                'todos': _list(<String>[_importedTodo]),
              }),
              canWrite: () => authorized,
            ),
          ).then((value) {
            queuedFinished = true;
            return value;
          });
      await Future<void>.delayed(Duration.zero);
      expect(queuedFinished, isFalse);
      expect(store.valuesWritten('flutter.todos'), isEmpty);

      authorized = false;
      held.release();
      expect(await predecessor.timeout(_wait), 1);
      expect(
        await queued.timeout(_wait),
        isA<AccountPreferenceWriteCanceled>(),
      );
      expect(store.valuesWritten('flutter.todos'), isEmpty);
      expect(store.valuesWritten('flutter.user_profile'), <Object>[
        'queue predecessor',
      ]);
      expect(store.removedKeys, isEmpty);
      await _expectBackingAndReload(preferences, store, <String, Object>{
        ..._initial,
        'user_profile': 'queue predecessor',
      });
      expectSameAccount();
    },
  );

  test(
    'mid-write authority loss settles and restores its owned preimage',
    () async {
      final held = store.hold(
        'flutter.user_profile',
        _WritePhase.beforePersist,
      );
      var authorized = true;
      final imported = _outcome(
        BackupService.importAll(
          _backup(<String, Object>{
            'todos': _list(<String>[_importedTodo]),
            'pref_haptic_feedback': <String, Object>{
              'type': 'bool',
              'value': false,
            },
            'user_profile': _string('issued profile'),
            'duoyi_notes': _list(<String>['must not be issued']),
          }),
          canWrite: () => authorized,
        ),
      );
      await held.entered.future.timeout(_wait);
      expect(await store.getAll(), <String, Object>{
        ..._prefixed(_initial),
        'flutter.todos': <String>[_importedTodo],
        'flutter.pref_haptic_feedback': false,
      });

      authorized = false;
      held.release();
      expect(
        await imported.timeout(_wait),
        isA<AccountPreferenceWriteCanceled>(),
      );
      await _expectBackingAndReload(preferences, store, _initial);
      expect(store.valuesWritten('flutter.todos'), <Object>[
        <String>[_importedTodo],
        <String>[_beforeTodo],
      ]);
      expect(store.valuesWritten('flutter.user_profile'), <Object>[
        'issued profile',
        'original profile',
      ]);
      expect(store.valuesWritten('flutter.duoyi_notes'), isEmpty);
      expect(store.removedKeys, <String>['flutter.pref_haptic_feedback']);

      // The canceled caller's predicate must not poison the following request.
      expect(
        await BackupService.importAll(
          _backup(<String, Object>{
            'user_profile': _string('fresh request profile'),
          }),
          canWrite: () => true,
        ),
        1,
      );
      await _expectBackingAndReload(preferences, store, <String, Object>{
        ..._initial,
        'user_profile': 'fresh request profile',
      });
      expectSameAccount();
    },
  );

  test(
    'revocation while a persisted write awaits ACK cancels and restores',
    () async {
      final held = store.hold('flutter.todos', _WritePhase.afterPersist);
      var authorized = true;
      var finished = false;
      final imported =
          _outcome(
            BackupService.importAll(
              _backup(<String, Object>{
                'todos': _list(<String>[_importedTodo]),
                'duoyi_notes': _list(<String>['must not be issued']),
                'user_profile': _string('must not be issued'),
              }),
              canWrite: () => authorized,
            ),
          ).then((value) {
            finished = true;
            return value;
          });
      await held.entered.future.timeout(_wait);
      expect(await store.getAll(), <String, Object>{
        ..._prefixed(_initial),
        'flutter.todos': <String>[_importedTodo],
      });
      expect(finished, isFalse);

      authorized = false;
      held.release();
      expect(
        await imported.timeout(_wait),
        isA<AccountPreferenceWriteCanceled>(),
      );
      await _expectBackingAndReload(preferences, store, _initial);
      expect(store.valuesWritten('flutter.todos'), <Object>[
        <String>[_importedTodo],
        <String>[_beforeTodo],
      ]);
      expect(store.valuesWritten('flutter.duoyi_notes'), isEmpty);
      expect(store.valuesWritten('flutter.user_profile'), isEmpty);
      expect(store.removedKeys, isEmpty);
      expectSameAccount();
    },
  );

  test(
    'revoked import rollback cannot overwrite successor backing values',
    () async {
      final held = store.hold('flutter.todos', _WritePhase.afterPersist);
      var authorized = true;
      var finished = false;
      final imported =
          _outcome(
            BackupService.importAll(
              _backup(<String, Object>{
                'todos': _list(<String>[_importedTodo]),
                'user_profile': _string('departing import profile'),
              }),
              canWrite: () => authorized,
            ),
          ).then((value) {
            finished = true;
            return value;
          });
      await held.entered.future.timeout(_wait);
      expect((await store.getAll())['flutter.todos'], <String>[_importedTodo]);

      authorized = false;
      // Real successor writes happen before the departing platform ACK returns.
      // They deliberately do not wait in BackupService's old import queue.
      expect(
        await preferences.setStringList('todos', <String>[_successorTodo]),
        isTrue,
      );
      expect(
        await preferences.setString('user_profile', 'successor profile'),
        isTrue,
      );
      final successor = <String, Object>{
        ..._initial,
        'todos': <String>[_successorTodo],
        'user_profile': 'successor profile',
      };
      expect(await store.getAll(), _prefixed(successor));
      expect(finished, isFalse);

      held.release();
      expect(
        await imported.timeout(_wait),
        isA<AccountPreferenceWriteCanceled>(),
      );
      await _expectBackingAndReload(preferences, store, successor);
      expect(
        store.valuesWritten('flutter.todos'),
        <Object>[
          <String>[_importedTodo],
          <String>[_successorTodo],
        ],
        reason: 'Even a transient preimage replay would clobber the successor.',
      );
      expect(store.valuesWritten('flutter.user_profile'), <Object>[
        'successor profile',
      ]);
      expect(store.removedKeys, isEmpty);
      expectSameAccount();
    },
  );
}

String _backup(Map<String, Object> data) =>
    json.encode(<String, Object>{'app': 'duoyi', 'schema': 1, 'data': data});

Map<String, Object> _list(List<String> values) => <String, Object>{
  'type': 'stringList',
  'value': values,
};

Map<String, Object> _string(String value) => <String, Object>{
  'type': 'string',
  'value': value,
};

Map<String, Object> _prefixed(Map<String, Object> values) => <String, Object>{
  for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
};

Future<Object?> _outcome(Future<int> request) => request.then<Object?>(
  (value) => value,
  onError: (Object error, StackTrace _) => error,
);

Future<void> _expectBackingAndReload(
  SharedPreferences preferences,
  _AuthorityBackingStore store,
  Map<String, Object> expected,
) async {
  expect(
    await store.getAll(),
    _prefixed(expected),
    reason: 'Actual platform backing values',
  );
  await preferences.reload();
  expect(
    <String, Object?>{
      for (final key in preferences.getKeys()) key: preferences.get(key),
    },
    expected,
    reason: 'Reloaded SharedPreferences must agree with backing',
  );
}

enum _WritePhase { beforePersist, afterPersist }

class _HeldWrite {
  _HeldWrite(this.key, this.phase);

  final String key;
  final _WritePhase phase;
  final entered = Completer<void>();
  final _released = Completer<void>();
  bool claimed = false;

  Future<void> pause() async {
    entered.complete();
    await _released.future;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

class _StoredWrite {
  _StoredWrite(this.key, Object value)
    : value = value is List<String> ? List<String>.unmodifiable(value) : value;

  final String key;
  final Object value;
}

// Same official backing implementation used by backup_write_boundary_test.
// The overrides only record or pause actual platform writes; persistence and
// reads still run through InMemorySharedPreferencesStore's implementation.
class _AuthorityBackingStore extends InMemorySharedPreferencesStore {
  _AuthorityBackingStore(Map<String, Object> initial)
    : super.withData(_prefixed(initial));

  final writes = <_StoredWrite>[];
  final removedKeys = <String>[];
  final _holds = <_HeldWrite>[];

  _HeldWrite hold(String key, _WritePhase phase) {
    final held = _HeldWrite(key, phase);
    _holds.add(held);
    return held;
  }

  List<Object> valuesWritten(String key) => <Object>[
    for (final write in writes)
      if (write.key == key) write.value,
  ];

  void releaseAll() {
    for (final held in _holds) {
      held.release();
    }
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add(_StoredWrite(key, value));
    _HeldWrite? held;
    for (final candidate in _holds) {
      if (!candidate.claimed && candidate.key == key) {
        candidate.claimed = true;
        held = candidate;
        break;
      }
    }
    if (held != null && held.phase == _WritePhase.beforePersist) {
      await held.pause();
    }
    final saved = await super.setValue(valueType, key, value);
    if (held != null && held.phase == _WritePhase.afterPersist) {
      await held.pause();
    }
    return saved;
  }

  @override
  Future<bool> remove(String key) async {
    removedKeys.add(key);
    return super.remove(key);
  }
}
