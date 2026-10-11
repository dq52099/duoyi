import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(AccountPreferenceWrites.drain);

  test(
    'held import and queued old wipe cancel before cleanup finishes',
    () async {
      final store = _BackupStore()..holdSetKey = 'flutter.todos';
      SharedPreferencesStorePlatform.instance = store;
      final imported = BackupService.importAll(
        _backup({
          'todos': {
            'type': 'stringList',
            'value': ['old task'],
          },
          'user_profile': {'type': 'string', 'value': 'old profile'},
        }),
      );
      final canceledImport = expectLater(
        imported,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await store.started.future;
      final canceledWipe = expectLater(
        BackupService.wipeAll(),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );

      var cleaned = false;
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then(
        (_) => cleaned = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isFalse);
      store.release.complete();
      await Future.wait([cleanup, canceledImport, canceledWipe]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('todos'), isNull);
      expect(prefs.getString('user_profile'), isNull);
    expect(store.setKeys, isNot(contains('flutter.user_profile')));

      await prefs.setString('user_profile', 'new profile');
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString('user_profile'), 'new profile');
    },
  );

  test('held wipe cannot delete new account data after cleanup', () async {
    SharedPreferences.setMockInitialValues({
      'todos': ['old task'],
      'user_profile': 'old profile',
    });
    final store = _BackupStore(
      initial: {
        'flutter.todos': ['old task'],
        'flutter.user_profile': 'old profile',
      },
    )..holdRemoveKey = 'flutter.todos';
    SharedPreferencesStorePlatform.instance = store;
    final canceledWipe = expectLater(
      BackupService.wipeAll(),
      throwsA(isA<AccountPreferenceWriteCanceled>()),
    );
    await store.started.future;
    var cleaned = false;
    final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then(
      (_) => cleaned = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(cleaned, isFalse);
    store.release.complete();
    await Future.wait([cleanup, canceledWipe]);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('todos', ['new task']);
    await prefs.setString('user_profile', 'new profile');
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getStringList('todos'), ['new task']);
    expect(prefs.getString('user_profile'), 'new profile');
  });

  test(
    'rejected import rolls back clearMissing and all changed values',
    () async {
      SharedPreferences.setMockInitialValues({
        'todos': ['before'],
        'duoyi_notes': ['keep note'],
        'user_profile': 'before profile',
      });
      final store = _BackupStore(
        initial: {
          'flutter.todos': ['before'],
          'flutter.duoyi_notes': ['keep note'],
          'flutter.user_profile': 'before profile',
        },
      )..rejectSetOnce = 'flutter.user_profile';
      SharedPreferencesStorePlatform.instance = store;

      await expectLater(
        BackupService.importAll(
          _backup({
            'todos': {
              'type': 'stringList',
              'value': ['imported'],
            },
            'user_profile': {'type': 'string', 'value': 'imported profile'},
          }),
          clearMissing: true,
        ),
        throwsStateError,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('todos'), ['before']);
      expect(prefs.getStringList('duoyi_notes'), ['keep note']);
      expect(prefs.getString('user_profile'), 'before profile');

      expect(
        await BackupService.importAll(
          _backup({
            'user_profile': {'type': 'string', 'value': 'next'},
          }),
        ),
        1,
      );
      expect(prefs.getString('user_profile'), 'next');
    },
  );

  test('rejected wipe restores previously removed values', () async {
    SharedPreferences.setMockInitialValues({
      'todos': ['before'],
      'habits': ['habit'],
    });
    final store = _BackupStore(
      initial: {
        'flutter.todos': ['before'],
        'flutter.habits': ['habit'],
      },
    )..rejectRemoveOnce = 'flutter.habits';
    SharedPreferencesStorePlatform.instance = store;
    await expectLater(BackupService.wipeAll(), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('todos'), ['before']);
    expect(prefs.getStringList('habits'), ['habit']);
  });

  test(
    'imports and wipes already inside cleanup report cancellation',
    () async {
      await AccountLocalDataCleaner.runPreferenceBoundary(() async {
        await expectLater(
          BackupService.importAll(
            _backup({
              'user_profile': {'type': 'string', 'value': 'stale'},
            }),
          ),
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        await expectLater(
          BackupService.wipeAll(),
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
      });
      expect(
        (await SharedPreferences.getInstance()).getString('user_profile'),
        isNull,
      );
    },
  );

  test(
    'serialized imports preserve merge changes from the preceding import',
    () async {
      final store = _BackupStore()..holdSetKey = 'flutter.todos';
      SharedPreferencesStorePlatform.instance = store;
      final first = BackupService.importAll(
        _backup({
          'todos': {
            'type': 'stringList',
            'value': ['{"id":"one"}'],
          },
        }),
      );
      await store.started.future;
      final second = BackupService.importAll(
        _backup({
          'todos': {
            'type': 'stringList',
            'value': ['{"id":"two"}'],
          },
        }),
        merge: true,
      );
      store.release.complete();
      expect(await first, 1);
      expect(await second, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('todos'), ['{"id":"one"}', '{"id":"two"}']);
    },
  );
}

String _backup(Map<String, Object> data) =>
    json.encode({'app': 'duoyi', 'schema': 1, 'data': data});

class _BackupStore extends InMemorySharedPreferencesStore {
  _BackupStore({Map<String, Object> initial = const {}})
    : super.withData(initial);
  String? holdSetKey;
  String? holdRemoveKey;
  String? rejectSetOnce;
  String? rejectRemoveOnce;
  final started = Completer<void>();
  final release = Completer<void>();
  final setKeys = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == holdSetKey && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    if (key == rejectSetOnce) {
      rejectSetOnce = null;
      return false;
    }
    setKeys.add(key);
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (key == holdRemoveKey && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    if (key == rejectRemoveOnce) {
      rejectRemoveOnce = null;
      return false;
    }
    return super.remove(key);
  }
}
