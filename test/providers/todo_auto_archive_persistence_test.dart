// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Store store;
  late TodoProvider provider;
  late SharedPreferences prefs;
  var notifications = 0;
  var archiveMarkerCalls = 0;
  var localMarkerCalls = 0;
  var archiveMarkerResult = true;
  String? archiveMarkerFailure;

  Future<void> seed(List<TodoItem> todos) async {
    await prefs.setString('todos', _payload(todos));
    await provider.loadFromStorage(force: true);
    store.todoWriteCalls = 0;
    notifications = 0;
    archiveMarkerCalls = 0;
    localMarkerCalls = 0;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    provider = TodoProvider();
    await provider.loadFromStorage();
    notifications = 0;
    archiveMarkerCalls = 0;
    localMarkerCalls = 0;
    archiveMarkerResult = true;
    archiveMarkerFailure = null;
    provider.addListener(() => notifications++);
    provider.onLocalMutationPersisted = () => localMarkerCalls++;
    provider.onArchiveMutationPersisted = () async {
      archiveMarkerCalls++;
      final failure = archiveMarkerFailure;
      archiveMarkerFailure = null;
      if (failure == 'throw') {
        throw StateError('private archive marker diagnostic');
      }
      return failure == 'false' ? false : archiveMarkerResult;
    };
  });

  tearDown(() async {
    await AccountPreferenceWrites.drain();
    provider.dispose();
  });

  test('zero and no-eligible rollovers do not write or publish', () async {
    final today = DateTime(2026, 7, 8, 0, 5);
    await seed([
      _todo(
        'recent-completion',
        completedAt: DateTime(2026, 7, 2, 23, 59),
        isCompleted: true,
      ),
      _todo('completed-today', completedAt: today, isCompleted: true),
      _todo('legacy-no-time', isCompleted: true),
      _todo(
        'active-with-old-time',
        completedAt: DateTime(2026, 6, 1),
        isCompleted: false,
      ),
      _todo(
        'existing-history',
        completedAt: DateTime(2026, 1, 1),
        isCompleted: true,
        archived: true,
      ),
    ]);

    expect(
      await provider.archivePastCompletions(today, completedDays: 0),
      isTrue,
    );
    expect(
      await provider.archivePastCompletions(today, completedDays: 7),
      isTrue,
    );

    expect(store.todoWriteCalls, 0);
    expect(notifications, 0);
    expect(archiveMarkerCalls, 0);
    expect(localMarkerCalls, 0);
    expect(provider.todos.map((todo) => todo.id), [
      'recent-completion',
      'completed-today',
      'legacy-no-time',
      'active-with-old-time',
      'existing-history',
    ]);
    expect(
      provider.todos
          .where((todo) => todo.isArchivedAfterRollover)
          .map((t) => t.id),
      ['existing-history'],
    );
    expect(
      _storedTodos(
        prefs,
      ).where((todo) => todo.isArchivedAfterRollover).map((todo) => todo.id),
      ['existing-history'],
    );
  });

  test('seven-day threshold includes the cutoff civil-day slot', () async {
    final today = DateTime(2026, 7, 8, 0, 5);
    await seed([
      _todo(
        'cutoff-slot',
        completedAt: DateTime(2026, 7, 1, 23, 55),
        isCompleted: true,
      ),
      _todo(
        'after-cutoff',
        completedAt: DateTime(2026, 7, 2),
        isCompleted: true,
      ),
      _todo('today', completedAt: today, isCompleted: true),
      _todo('missing-completed-at', isCompleted: true),
      _todo(
        'not-completed',
        completedAt: DateTime(2026, 1, 1),
        isCompleted: false,
      ),
      _todo(
        'already-history',
        completedAt: DateTime(2026, 1, 1),
        isCompleted: true,
        archived: true,
      ),
    ]);

    expect(
      await provider.archivePastCompletions(today, completedDays: 7),
      isTrue,
    );

    final memory = {for (final todo in provider.todos) todo.id: todo};
    final disk = {for (final todo in _storedTodos(prefs)) todo.id: todo};
    expect(memory['cutoff-slot']!.isArchivedAfterRollover, isTrue);
    expect(disk['cutoff-slot']!.isArchivedAfterRollover, isTrue);
    for (final id in [
      'after-cutoff',
      'today',
      'missing-completed-at',
      'not-completed',
    ]) {
      expect(memory[id]!.isArchivedAfterRollover, isFalse, reason: id);
      expect(disk[id]!.isArchivedAfterRollover, isFalse, reason: id);
    }
    expect(memory['already-history']!.isArchivedAfterRollover, isTrue);
    expect(
      disk.keys,
      containsAll([
        'cutoff-slot',
        'after-cutoff',
        'today',
        'missing-completed-at',
        'not-completed',
        'already-history',
      ]),
    );
    expect(store.todoWriteCalls, 1);
    expect(notifications, 1);
    expect(archiveMarkerCalls, 1);
    expect(localMarkerCalls, 0);
  });

  test('omitted threshold keeps the legacy one-day cutoff', () async {
    final today = DateTime(2026, 7, 8, 0, 1);
    await seed([
      _todo(
        'yesterday',
        completedAt: DateTime(2026, 7, 7, 23, 59),
        isCompleted: true,
      ),
      _todo('older', completedAt: DateTime(2026, 7, 6, 12), isCompleted: true),
      _todo('today', completedAt: today, isCompleted: true),
    ]);

    expect(await provider.archivePastCompletions(today), isTrue);

    final memory = {for (final todo in provider.todos) todo.id: todo};
    expect(memory['yesterday']!.isArchivedAfterRollover, isTrue);
    expect(memory['older']!.isArchivedAfterRollover, isTrue);
    expect(memory['today']!.isArchivedAfterRollover, isFalse);
  });

  test(
    'one-day cutoff follows civil dates across both DST transitions',
    () async {
      expect(Platform.environment['TZ'], 'America/New_York');
      final springCompleted = DateTime(2026, 3, 8, 0, 5);
      final springToday = DateTime(2026, 3, 9, 0, 5);
      expect(
        springCompleted.timeZoneOffset,
        isNot(springToday.timeZoneOffset),
        reason:
            'Run with TZ=America/New_York to exercise the spring transition',
      );
      expect(
        springToday.difference(springCompleted),
        const Duration(hours: 23),
      );

      await seed([
        _todo('spring-cutoff', completedAt: springCompleted, isCompleted: true),
        _todo('spring-today', completedAt: springToday, isCompleted: true),
      ]);
      expect(
        await provider.archivePastCompletions(springToday, completedDays: 1),
        isTrue,
      );
      var memory = {for (final todo in provider.todos) todo.id: todo};
      expect(memory['spring-cutoff']!.isArchivedAfterRollover, isTrue);
      expect(memory['spring-today']!.isArchivedAfterRollover, isFalse);

      final fallCompleted = DateTime(2026, 11, 1, 0, 5);
      final fallToday = DateTime(2026, 11, 2, 0, 5);
      expect(
        fallCompleted.timeZoneOffset,
        isNot(fallToday.timeZoneOffset),
        reason: 'Run with TZ=America/New_York to exercise the fall transition',
      );
      expect(fallToday.difference(fallCompleted), const Duration(hours: 25));

      await seed([
        _todo('fall-cutoff', completedAt: fallCompleted, isCompleted: true),
        _todo('fall-today', completedAt: fallToday, isCompleted: true),
      ]);
      expect(
        await provider.archivePastCompletions(fallToday, completedDays: 1),
        isTrue,
      );
      memory = {for (final todo in provider.todos) todo.id: todo};
      expect(memory['fall-cutoff']!.isArchivedAfterRollover, isTrue);
      expect(memory['fall-today']!.isArchivedAfterRollover, isFalse);
      final disk = {for (final todo in _storedTodos(prefs)) todo.id: todo};
      expect(disk['fall-cutoff']!.isArchivedAfterRollover, isTrue);
      expect(disk['fall-today']!.isArchivedAfterRollover, isFalse);
    },
    skip: Platform.environment['DUOYI_REQUIRE_DST'] != '1',
  );

  test('365-day maximum includes its cutoff civil day', () async {
    final today = DateTime(2025, 3, 1, 0, 5);
    await seed([
      _todo(
        'at-365-day-cutoff',
        completedAt: DateTime(2024, 3, 1, 0, 5),
        isCompleted: true,
      ),
      _todo(
        'inside-365-day-window',
        completedAt: DateTime(2024, 3, 2, 0, 5),
        isCompleted: true,
      ),
      _todo(
        'older-than-cutoff',
        completedAt: DateTime(2024, 2, 29, 0, 5),
        isCompleted: true,
      ),
      _todo('today', completedAt: today, isCompleted: true),
    ]);

    expect(
      await provider.archivePastCompletions(today, completedDays: 365),
      isTrue,
    );

    final memory = {for (final todo in provider.todos) todo.id: todo};
    final disk = {for (final todo in _storedTodos(prefs)) todo.id: todo};
    expect(memory['at-365-day-cutoff']!.isArchivedAfterRollover, isTrue);
    expect(memory['older-than-cutoff']!.isArchivedAfterRollover, isTrue);
    expect(memory['inside-365-day-window']!.isArchivedAfterRollover, isFalse);
    expect(memory['today']!.isArchivedAfterRollover, isFalse);
    expect(disk['at-365-day-cutoff']!.isArchivedAfterRollover, isTrue);
    expect(disk['inside-365-day-window']!.isArchivedAfterRollover, isFalse);
  });

  test(
    'out-of-range completedDays values normalize to the supported limits',
    () async {
      final today = DateTime(2025, 3, 1, 0, 5);
      await seed([
        _todo(
          'negative-threshold-target',
          completedAt: DateTime(2024, 1, 1),
          isCompleted: true,
        ),
      ]);

      expect(
        await provider.archivePastCompletions(today, completedDays: -12),
        isTrue,
      );
      expect(provider.todos.single.isArchivedAfterRollover, isFalse);
      expect(store.todoWriteCalls, 0);
      expect(notifications, 0);

      await seed([
        _todo(
          'at-normalized-365-day-cutoff',
          completedAt: DateTime(2024, 3, 1, 0, 5),
          isCompleted: true,
        ),
        _todo(
          'inside-normalized-365-day-window',
          completedAt: DateTime(2024, 3, 2, 0, 5),
          isCompleted: true,
        ),
      ]);

      expect(
        await provider.archivePastCompletions(today, completedDays: 900),
        isTrue,
      );

      final memory = {for (final todo in provider.todos) todo.id: todo};
      final disk = {for (final todo in _storedTodos(prefs)) todo.id: todo};
      expect(
        memory['at-normalized-365-day-cutoff']!.isArchivedAfterRollover,
        isTrue,
      );
      expect(
        memory['inside-normalized-365-day-window']!.isArchivedAfterRollover,
        isFalse,
      );
      expect(
        disk['at-normalized-365-day-cutoff']!.isArchivedAfterRollover,
        isTrue,
      );
      expect(
        disk['inside-normalized-365-day-window']!.isArchivedAfterRollover,
        isFalse,
      );
      expect(store.todoWriteCalls, 1);
      expect(notifications, 1);
    },
  );

  for (final failure in ['false', 'throw', 'writeThenThrow']) {
    test(
      'storage $failure rolls back before any archive is published',
      () async {
        final today = DateTime(2026, 7, 8);
        await seed([
          _todo('target', completedAt: DateTime(2026, 7, 7), isCompleted: true),
        ]);
        store.failNextTodoWrite = failure;

        await expectLater(
          provider.archivePastCompletions(today),
          throwsA(anything),
        );

        expect(provider.todos.single.isArchivedAfterRollover, isFalse);
        expect(_storedTodos(prefs).single.isArchivedAfterRollover, isFalse);
        expect(notifications, 0);
        expect(archiveMarkerCalls, 0);
        expect(localMarkerCalls, 0);

        expect(await provider.archivePastCompletions(today), isTrue);
        expect(provider.todos.single.isArchivedAfterRollover, isTrue);
        expect(_storedTodos(prefs).single.isArchivedAfterRollover, isTrue);
        expect(notifications, 1);
        expect(archiveMarkerCalls, 1);
        expect(localMarkerCalls, 0);
      },
    );
  }

  test('a changed policy lease rolls a held snapshot back', () async {
    final today = DateTime(2026, 7, 8);
    await seed([
      _todo('target', completedAt: DateTime(2026, 7, 7), isCompleted: true),
    ]);
    var policyCurrent = true;
    store.holdNextTodoWrite();
    final pending = provider.archivePastCompletions(
      today,
      canWrite: () => policyCurrent,
    );
    await store.heldWriteStarted;

    policyCurrent = false;
    store.releaseHeldTodoWrite();
    expect(await pending, isFalse);

    expect(provider.todos.single.isArchivedAfterRollover, isFalse);
    expect(_storedTodos(prefs).single.isArchivedAfterRollover, isFalse);
    expect(notifications, 0);
    expect(archiveMarkerCalls, 0);
    expect(localMarkerCalls, 0);
  });

  test('account cleanup drains a held archive and its rollback', () async {
    final today = DateTime(2026, 7, 8);
    await seed([
      _todo('target', completedAt: DateTime(2026, 7, 7), isCompleted: true),
    ]);
    store.holdNextTodoWrite();
    final pending = provider.archivePastCompletions(today);
    await store.heldWriteStarted;

    var cleanupFinished = false;
    final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then((_) {
      cleanupFinished = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(cleanupFinished, isFalse);
    provider.resetLocalState();
    final notificationsAfterReset = notifications;

    store.releaseHeldTodoWrite();
    expect(await pending, isFalse);
    await cleanup;

    expect(cleanupFinished, isTrue);
    expect(provider.todos, isEmpty);
    expect(notifications, notificationsAfterReset);
    expect(archiveMarkerCalls, 0);
    await prefs.reload();
    expect(prefs.containsKey('todos'), isFalse);
  });

  test(
    'an unrelated edit and insert survive a held archive snapshot',
    () async {
      final today = DateTime(2026, 7, 8);
      await seed([
        _todo(
          'archive-target',
          completedAt: DateTime(2026, 7, 7),
          isCompleted: true,
        ),
        _todo('unrelated', isCompleted: false),
      ]);
      store.holdNextTodoWrite();
      final archive = provider.archivePastCompletions(today);
      await store.heldWriteStarted;

      final unrelated = provider.todos.singleWhere(
        (todo) => todo.id == 'unrelated',
      );
      final edit = provider.updateTodo(
        unrelated.id,
        unrelated.copyWith(title: 'edited while archive is held'),
        waitForReminderSync: false,
      );
      final insert = provider.addTodo(
        _todo('concurrent-insert'),
        waitForReminderSync: false,
      );
      await Future<void>.delayed(Duration.zero);
      store.releaseHeldTodoWrite();

      expect(await archive, isTrue);
      expect(await edit, isTrue);
      await insert;

      final memory = {for (final todo in provider.todos) todo.id: todo};
      final disk = {for (final todo in _storedTodos(prefs)) todo.id: todo};
      expect(memory['archive-target']!.isArchivedAfterRollover, isTrue);
      expect(disk['archive-target']!.isArchivedAfterRollover, isTrue);
      expect(memory['unrelated']!.title, 'edited while archive is held');
      expect(disk['unrelated']!.title, 'edited while archive is held');
      expect(memory.keys, contains('concurrent-insert'));
      expect(disk.keys, contains('concurrent-insert'));
    },
  );

  test('a duplicate busy archive and target edit are not successful', () async {
    final today = DateTime(2026, 7, 8);
    await seed([
      _todo('target', completedAt: DateTime(2026, 7, 7), isCompleted: true),
    ]);
    store.holdNextTodoWrite();
    final pending = provider.archivePastCompletions(today);
    await store.heldWriteStarted;

    expect(await provider.archivePastCompletions(today), isFalse);
    expect(
      await provider.updateTodo(
        'target',
        provider.todos.single.copyWith(title: 'must not win'),
        waitForReminderSync: false,
      ),
      isFalse,
    );
    expect(provider.todos.single.title, 'task target');
    expect(provider.todos.single.isArchivedAfterRollover, isFalse);

    store.releaseHeldTodoWrite();
    expect(await pending, isTrue);
    expect(provider.todos.single.isArchivedAfterRollover, isTrue);
    expect(provider.todos.single.title, 'task target');
    expect(store.todoWriteCalls, 1);
  });

  for (final failure in ['false', 'throw']) {
    test(
      'archive marker $failure leaves the snapshot durable and retryable',
      () async {
        final today = DateTime(2026, 7, 8);
        await seed([
          _todo('target', completedAt: DateTime(2026, 7, 7), isCompleted: true),
        ]);
        archiveMarkerFailure = failure;

        if (failure == 'false') {
          expect(await provider.archivePastCompletions(today), isFalse);
        } else {
          await expectLater(
            provider.archivePastCompletions(today),
            throwsA(isA<StateError>()),
          );
        }

        expect(provider.todos.single.isArchivedAfterRollover, isTrue);
        expect(_storedTodos(prefs).single.isArchivedAfterRollover, isTrue);
        expect(store.todoWriteCalls, 1);
        expect(notifications, 1);
        expect(archiveMarkerCalls, 1);
        expect(localMarkerCalls, 0);

        archiveMarkerResult = false;
        expect(
          await provider.archivePastCompletions(today, completedDays: 0),
          isFalse,
        );
        expect(archiveMarkerCalls, 2);
        expect(store.todoWriteCalls, 1);
        expect(notifications, 1);

        archiveMarkerResult = true;
        expect(
          await provider.archivePastCompletions(today, completedDays: 7),
          isTrue,
        );
        expect(archiveMarkerCalls, 3);
        expect(store.todoWriteCalls, 1);
        expect(notifications, 1);
        expect(provider.todos.single.isArchivedAfterRollover, isTrue);
        expect(_storedTodos(prefs).single.isArchivedAfterRollover, isTrue);
      },
    );
  }

  test(
    'explicit dirty-marker retry does not rewrite or republish the archive',
    () async {
      final today = DateTime(2026, 7, 8);
      await seed([
        _todo('target', completedAt: DateTime(2026, 7, 7), isCompleted: true),
      ]);
      archiveMarkerResult = false;
      expect(await provider.archivePastCompletions(today), isFalse);
      expect(provider.todos.single.isArchivedAfterRollover, isTrue);

      archiveMarkerResult = true;
      expect(await provider.retryPendingArchiveMutationMarker(), isTrue);

      expect(archiveMarkerCalls, 2);
      expect(store.todoWriteCalls, 1);
      expect(notifications, 1);
      expect(provider.todos.single.isArchivedAfterRollover, isTrue);
      expect(_storedTodos(prefs).single.isArchivedAfterRollover, isTrue);
    },
  );

  test('reset clears the old dirty owner before a new owner retries', () async {
    final today = DateTime(2026, 7, 8);
    await seed([
      _todo('old-owner', completedAt: DateTime(2026, 7, 7), isCompleted: true),
    ]);
    archiveMarkerResult = false;
    expect(await provider.archivePastCompletions(today), isFalse);
    expect(archiveMarkerCalls, 1);

    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    provider.resetLocalState();
    await prefs.setString('todos', _payload([_todo('new-owner')]));
    await provider.loadFromStorage();
    store.todoWriteCalls = 0;

    expect(await provider.retryPendingArchiveMutationMarker(), isTrue);
    expect(provider.todos.map((todo) => todo.id), ['new-owner']);
    expect(_storedTodos(prefs).map((todo) => todo.id), ['new-owner']);
    expect(archiveMarkerCalls, 1);
    expect(store.todoWriteCalls, 0);
  });
}

TodoItem _todo(
  String id, {
  DateTime? completedAt,
  bool isCompleted = false,
  bool archived = false,
}) => TodoItem(
  id: id,
  title: 'task $id',
  date: DateTime(2026, 1, 1),
  completedAt: completedAt,
  isCompleted: isCompleted,
  isArchivedAfterRollover: archived,
);

String _payload(Iterable<TodoItem> todos) =>
    jsonEncode(todos.map((todo) => todo.toJson()).toList());

List<TodoItem> _storedTodos(SharedPreferences prefs) {
  final raw = prefs.getString('todos');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((value) => TodoItem.fromJson((value as Map).cast<String, dynamic>()))
      .toList();
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});

  String? failNextTodoWrite;
  bool _holdTodoWrite = false;
  Completer<void>? _heldWriteStarted;
  Completer<void>? _releaseHeldWrite;
  int todoWriteCalls = 0;

  Future<void> get heldWriteStarted => _heldWriteStarted!.future;

  void holdNextTodoWrite() {
    _holdTodoWrite = true;
    _heldWriteStarted = Completer<void>();
    _releaseHeldWrite = Completer<void>();
  }

  void releaseHeldTodoWrite() {
    _releaseHeldWrite!.complete();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.todos') {
      todoWriteCalls++;
      final failure = failNextTodoWrite;
      failNextTodoWrite = null;
      if (failure == 'false') return false;
      if (failure == 'throw') {
        throw StateError('private todo storage diagnostic');
      }
      if (failure == 'writeThenThrow') {
        await super.setValue(type, key, value);
        throw StateError('private todo storage diagnostic after write');
      }
      if (_holdTodoWrite) {
        _holdTodoWrite = false;
        _heldWriteStarted!.complete();
        await _releaseHeldWrite!.future;
      }
    }
    return super.setValue(type, key, value);
  }
}
