// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/auto_archive_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    'archive marker waits for acknowledged metadata and retries refusal',
    () async {
      final store = _Store();
      SharedPreferencesStorePlatform.instance = store;
      final cloud = CloudSyncProvider();
      addTearDown(cloud.dispose);
      store.rejectPending = true;
      await expectLater(
        cloud.markArchiveMutationPendingDurably(),
        throwsStateError,
      );
      expect(cloud.hasPendingChanges, isTrue);
      store.holdKey = 'flutter.sync_pending_local_changes';
      var acknowledged = false;
      final marker = cloud.markArchiveMutationPendingDurably().then(
        (value) => acknowledged = value,
      );
      await store.started.future;
      expect(acknowledged, isFalse);
      store.release.complete();
      await marker;
      expect(acknowledged, isTrue);
      expect(
        (await store.getAll())['flutter.sync_pending_local_changes'],
        isTrue,
      );
    },
  );

  test(
    'ordinary boundary cancellation is false and preflight may confirm its old-owner marker',
    () async {
      final cloud = CloudSyncProvider();
      addTearDown(cloud.dispose);
      await AccountPreferenceWrites.boundary(() async {
        expect(await cloud.markArchiveMutationPendingDurably(), isFalse);
        expect(cloud.hasPendingChanges, isFalse);
        var preflightMarker = false;
        cloud.beforeAccountChangeFlush = () async {
          preflightMarker = await cloud.markArchiveMutationPendingDurably();
        };
        // No client: the upload remains pending. Its durable marker must still
        // be written before the preflight checks whether there is anything to flush.
        expect(
          await cloud.flushPendingLocalChangesBeforeAccountChange(),
          isFalse,
        );
        expect(preflightMarker, isTrue);
        expect(
          (await SharedPreferences.getInstance()).getBool(
            'sync_pending_local_changes',
          ),
          isTrue,
        );
      });
    },
  );

  for (final mode in ['push', 'pull']) {
    test(
      '$mode barrier starts before local apply and ends after onSynced',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final entered = Completer<void>();
        final releaseApply = Completer<void>();
        final reloaded = Completer<void>();
        final releaseReload = Completer<void>();
        final exited = Completer<void>();
        final events = <String>[];
        final paths = <String>[];
        final remoteEvents = mode == 'pull'
            ? StreamController<List<int>>()
            : null;
        if (remoteEvents != null) addTearDown(remoteEvents.close);
        final transport = MockClient.streaming((request, body) async {
          await body.drain<void>();
          paths.add(request.url.path);
          if (request.url.path == '/api/sync/events') {
            return http.StreamedResponse(remoteEvents!.stream, 200);
          }
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'server_updated_at': '2100-01-01T00:00:00.000Z',
                  'server_version': 100,
                  if (request.url.path != '/api/sync/status')
                    'todos': [_remoteTodo().toJson()],
                }),
              ),
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        addTearDown(transport.close);
        final cloud = CloudSyncProvider();
        addTearDown(cloud.dispose);
        cloud.apiClientGetter = () => ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'synthetic-token',
          httpClient: transport,
        );
        cloud.serverConfigGetter = () => {'backup_enabled': true};
        cloud.localApplyBarrier = (apply) async {
          events.add('pause');
          expect(prefs.getString('todos'), isNull);
          entered.complete();
          await releaseApply.future;
          await apply();
          events.add('release');
          exited.complete();
        };
        cloud.onSynced = (changed) async {
          expect(changed, contains('todos'));
          expect(prefs.getString('todos'), contains('synthetic-remote'));
          events.add('reload');
          reloaded.complete();
          await releaseReload.future;
        };
        Future<void>? syncing;
        if (mode == 'push') {
          syncing = cloud.syncNow();
        } else {
          cloud.startRemotePolling();
        }
        await entered.future.timeout(const Duration(seconds: 3));
        expect(prefs.getString('todos'), isNull);
        expect(events, ['pause']);
        releaseApply.complete();
        await reloaded.future.timeout(const Duration(seconds: 3));
        expect(exited.isCompleted, isFalse);
        expect(events, ['pause', 'reload']);
        releaseReload.complete();
        await exited.future.timeout(const Duration(seconds: 3));
        if (syncing != null) await syncing;
        cloud.stopRemotePolling();
        expect(events, ['pause', 'reload', 'release']);
        if (mode == 'pull') expect(paths, contains('/api/sync/pull'));
        expect(cloud.lastError, isNull);
      },
    );
  }

  test(
    'backup gate reloads policy without a page before scanning the restored todos',
    () async {
      final f = await _graph(days: 1);
      addTearDown(f.dispose);
      await _settle();
      var pageAlive = true;
      await f.todos.runExternalStorageUpdate(() async {
        await f.storage.setString(
          'todos',
          jsonEncode([_completed('restored', DateTime(2026, 10, 7)).toJson()]),
        );
        await f.storage.setInt('pref_auto_archive_completed_days', 14);
        pageAlive = false;
      });
      await _settle();
      expect(pageAlive, isFalse);
      expect(f.preferences.isStorageLoaded, isTrue);
      expect(f.preferences.autoArchiveCompletedDays, 14);
      expect(f.todos.isStorageHydrated, isTrue);
      expect(f.todos.todos.single.id, 'restored');
      expect(f.todos.todos.single.isArchivedAfterRollover, isFalse);
    },
  );

  test(
    'failed old-owner preflight rehydrates goals after its boundary without a page',
    () async {
      final f = await _graph(days: 0);
      addTearDown(f.dispose);
      await _settle();
      await expectLater(
        AccountPreferenceWrites.boundary(() async {
          await f.coordinator.suspendAndDrain();
          try {
            await f.coordinator.withAuthoritativeReload(() async {
              await f.storage.setStringList('duoyi_goals', [
                jsonEncode(
                  GoalItem(
                    id: 'sync-goal',
                    title: 'Synthetic sync goal',
                  ).toJson(),
                ),
              ]);
              await f.goals.loadFromStorage();
              expect(f.goals.isStorageHydrated, isFalse);
              throw StateError('synthetic preflight kept pending changes');
            });
          } catch (_) {
            f.coordinator.resumeAfterAccountPreflightFailure();
            rethrow;
          }
        }),
        throwsStateError,
      );
      await _settle();
      expect(f.goals.isStorageHydrated, isTrue);
      expect(f.goals.goals.single.id, 'sync-goal');
      expect(f.preferences.isStorageLoaded, isTrue);
      expect(f.todos.isStorageHydrated, isTrue);
    },
  );

  test(
    'backup drains and rolls back a held archive before replacing storage',
    () async {
      final store = _Store();
      final f = await _graph(days: 0, store: store);
      addTearDown(f.dispose);
      await f.todos.addTodo(
        _completed('old-owner-snapshot', DateTime(2026, 10, 1)),
        waitForReminderSync: false,
      );
      await _settle();
      store.holdKey = 'flutter.todos';
      await f.preferences.setAutoArchiveCompletedDays(1);
      await store.started.future;
      expect(f.todos.todos.single.isArchivedAfterRollover, isFalse);
      var applied = false;
      final restore = f.todos.runExternalStorageUpdate(() async {
        applied = true;
        await f.storage.setString(
          'todos',
          jsonEncode([
            _completed('new-restored', DateTime(2026, 10, 1)).toJson(),
          ]),
        );
        await f.storage.setInt('pref_auto_archive_completed_days', 0);
      });
      await _settle();
      expect(applied, isFalse);
      store.release.complete();
      await restore;
      await _settle();
      expect(applied, isTrue);
      expect(f.todos.todos.single.id, 'new-restored');
      expect(f.todos.todos.single.isArchivedAfterRollover, isFalse);
      expect(f.preferences.autoArchiveCompletedDays, 0);
      expect(
        jsonDecode(f.storage.getString('todos')!).single['id'],
        'new-restored',
      );
    },
  );
}

TodoItem _remoteTodo() => TodoItem(
  id: 'synthetic-remote',
  title: 'Synthetic remote todo',
  updatedAt: DateTime(2100),
);
TodoItem _completed(String id, DateTime completion) => TodoItem(
  id: id,
  title: 'Synthetic $id',
  isCompleted: true,
  completedAt: completion,
);
Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<_Graph> _graph({required int days, _Store? store}) async {
  if (store != null) SharedPreferencesStorePlatform.instance = store;
  final storage = await SharedPreferences.getInstance();
  await storage.setInt('pref_auto_archive_completed_days', days);
  final f = _Graph(storage);
  await f.preferences.loadFromStorage();
  await f.todos.loadFromStorage();
  await f.goals.loadFromStorage();
  f.coordinator.bind(
    todos: f.todos,
    preferences: f.preferences,
    auth: f.auth,
    goals: f.goals,
  );
  return f;
}

class _Graph {
  _Graph(this.storage);
  final SharedPreferences storage;
  final preferences = PreferencesProvider();
  final todos = TodoProvider();
  final goals = GoalProvider();
  final auth = AuthProvider();
  final coordinator = AutoArchiveCoordinator(now: () => DateTime(2026, 10, 14));
  void dispose() {
    coordinator.dispose();
    preferences.dispose();
    todos.dispose();
    goals.dispose();
    auth.dispose();
  }
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  bool rejectPending = false;
  String? holdKey;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.sync_pending_local_changes' && rejectPending) {
      rejectPending = false;
      return false;
    }
    if (key == holdKey) {
      holdKey = null;
      started.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}
