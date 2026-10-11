import 'dart:async';
import 'dart:convert';

import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/reminder_scheduler.dart'
    show ReminderReconciliationBatch;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/recording_reminder_scheduler.dart';

final _now = DateTime(2026, 10, 11, 9);

TodoItem _todo(String title) =>
    TodoItem(id: 'same-id', title: title, date: DateTime(2026, 10, 10));

String _payload(TodoItem item) => jsonEncode([item.toJson()]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'todos': _payload(_todo('old'))});
  });

  test(
    'hydration cannot schedule a same-ID item from the next account',
    () async {
      final provider = _GatedLoadTodoProvider();
      final scheduler = RecordingReminderScheduler();
      provider.scheduler = scheduler;
      addTearDown(provider.dispose);

      final pending = provider.scheduleTodoForToday('same-id', now: _now);
      await provider.started.future;
      expect(
        await provider.scheduleTodoForToday('same-id', now: _now),
        isFalse,
      );

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      provider.resetLocalState();
      final next = _todo('next account');
      final stored = _payload(next);
      SharedPreferences.setMockInitialValues({'todos': stored});
      provider.release.complete();

      var notifications = 0;
      provider.addListener(() => notifications++);
      final revision = provider.revision;
      expect(await pending, isFalse);
      expect(notifications, 1); // current-account hydration only
      expect(provider.revision, revision + 1);
      expect(provider.todos.single.toJson(), next.toJson());
      expect(
        (await SharedPreferences.getInstance()).getString('todos'),
        stored,
      );
      expect(scheduler.todoSyncs, isEmpty);

      // Both per-action and shared mutation claims must be released.
      expect(await provider.scheduleTodoForToday('same-id', now: _now), isTrue);
      expect(provider.todos.single.title, 'next account');
      expect(provider.todos.single.date, DateTime(2026, 10, 11));
      expect(scheduler.todoSyncs, [
        ['same-id'],
      ]);
    },
  );

  test('stale explicit origin is refused before hydration or claims', () async {
    final provider = _GatedLoadTodoProvider();
    addTearDown(provider.dispose);
    final origin = AccountLocalDataCleaner.accountDataGeneration;
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();

    expect(
      await provider.scheduleTodoForToday(
        'same-id',
        now: _now,
        expectedAccountDataGeneration: origin,
      ),
      isFalse,
    );
    expect(provider.started.isCompleted, isFalse);
    final pending = provider.scheduleTodoForToday(
      'same-id',
      now: _now,
      expectedAccountDataGeneration:
          AccountLocalDataCleaner.accountDataGeneration,
    );
    await provider.started.future;
    provider.release.complete();
    expect(await pending, isTrue);
  });

  test('same-account reset during hydration also cancels scheduling', () async {
    final provider = _GatedLoadTodoProvider();
    addTearDown(provider.dispose);
    final pending = provider.scheduleTodoForToday('same-id', now: _now);
    await provider.started.future;
    provider.resetLocalState();
    final replacement = _todo('replacement');
    SharedPreferences.setMockInitialValues({'todos': _payload(replacement)});
    provider.release.complete();

    expect(await pending, isFalse);
    expect(provider.todos.single.toJson(), replacement.toJson());
    expect(await provider.scheduleTodoForToday('same-id', now: _now), isTrue);
  });

  test('dispose during hydration cancels without writing', () async {
    final provider = _GatedLoadTodoProvider();
    final stored = (await SharedPreferences.getInstance()).getString('todos');
    final pending = provider.scheduleTodoForToday('same-id', now: _now);
    await provider.started.future;
    provider.dispose();
    provider.release.complete();
    expect(await pending, isFalse);
    expect(provider.todos, isEmpty);
    expect((await SharedPreferences.getInstance()).getString('todos'), stored);
  });

  test(
    'reset during persisted callback suppresses notify and reminders',
    () async {
      final scheduler = RecordingReminderScheduler();
      final provider = TodoProvider()..scheduler = scheduler;
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      var notifications = 0;
      provider.addListener(() => notifications++);
      final next = _todo('next account');
      provider.onLocalMutationPersisted = () async {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        provider.resetLocalState();
        SharedPreferences.setMockInitialValues({'todos': _payload(next)});
      };

      expect(
        await provider.scheduleTodoForToday('same-id', now: _now),
        isFalse,
      );
      expect(notifications, 1); // reset notification only
      expect(scheduler.todoSyncs, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString('todos'),
        _payload(next),
      );
      provider.onLocalMutationPersisted = null;
      expect(await provider.scheduleTodoForToday('same-id', now: _now), isTrue);
      expect(provider.todos.single.title, 'next account');
    },
  );

  test(
    'stale schedule queued behind a write cannot overwrite the next account',
    () async {
      final scheduler = RecordingReminderScheduler();
      final provider = TodoProvider()..scheduler = scheduler;
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      final writeStarted = Completer<void>();
      final releaseWrite = Completer<void>();
      var persistedCallbacks = 0;
      provider.onLocalMutationPersisted = () async {
        persistedCallbacks++;
        if (persistedCallbacks != 1) return;
        writeStarted.complete();
        await releaseWrite.future;
      };

      final blocker = provider.addTodo(
        TodoItem(id: 'blocker', title: 'queue gate'),
      );
      await writeStarted.future;
      final pending = provider.scheduleTodoForToday('same-id', now: _now);
      await Future<void>.delayed(Duration.zero);
      expect(
        provider.todos.firstWhere((item) => item.id == 'same-id').date,
        DateTime(2026, 10, 11),
      );
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      provider.resetLocalState();
      final next = _todo('next account');
      final stored = _payload(next);
      SharedPreferences.setMockInitialValues({'todos': stored});
      releaseWrite.complete();
      await blocker;

      expect(await pending, isFalse);
      expect(provider.todos, isEmpty); // new account has not hydrated yet
      expect(
        (await SharedPreferences.getInstance()).getString('todos'),
        stored,
      );
      expect(persistedCallbacks, 1);
      expect(scheduler.todoSyncs, isEmpty);
      provider.onLocalMutationPersisted = null;
      expect(await provider.scheduleTodoForToday('same-id', now: _now), isTrue);
      expect(provider.todos.single.title, 'next account');
    },
  );

  test(
    'synchronous notification account switch prevents reminder launch',
    () async {
      final scheduler = RecordingReminderScheduler();
      final provider = TodoProvider()..scheduler = scheduler;
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      var switched = false;
      provider.addListener(() {
        if (switched) return;
        switched = true;
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        provider.resetLocalState();
      });

      expect(
        await provider.scheduleTodoForToday('same-id', now: _now),
        isFalse,
      );
      expect(scheduler.todoSyncs, isEmpty);
      expect(provider.todos, isEmpty);
    },
  );

  test('account switch during awaited reminders suppresses success', () async {
    final scheduler = _GatedScheduler();
    final provider = TodoProvider()..scheduler = scheduler;
    addTearDown(provider.dispose);
    await provider.loadFromStorage();
    final pending = provider.scheduleTodoForToday('same-id', now: _now);
    await scheduler.started.future;
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    provider.resetLocalState();
    final next = _todo('next account');
    SharedPreferences.setMockInitialValues({'todos': _payload(next)});
    await provider.loadFromStorage();
    scheduler.release.complete();

    expect(await pending, isFalse);
    expect(provider.todos.single.toJson(), next.toJson());
    expect(provider.lastReminderSyncAttemptAt, isNull);
    expect(provider.lastReminderSyncSucceededAt, isNull);
    expect(await provider.scheduleTodoForToday('same-id', now: _now), isTrue);
  });

  test('immediate reminder callback reset cancels no-wait success', () async {
    final provider = TodoProvider();
    addTearDown(provider.dispose);
    await provider.loadFromStorage();
    provider.scheduler = _CallbackScheduler(() {
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      provider.resetLocalState();
    });

    expect(
      await provider.scheduleTodoForToday(
        'same-id',
        now: _now,
        waitForReminderSync: false,
      ),
      isFalse,
    );
    expect(provider.todos, isEmpty);
  });

  test(
    'current-origin schedule keeps due time and reminder semantics',
    () async {
      final original = _todo('authored title').copyWith(
        hasReminder: true,
        reminder: const ReminderConfig(enabled: true, hour: 8, minute: 0),
      );
      SharedPreferences.setMockInitialValues({'todos': _payload(original)});
      final scheduler = RecordingReminderScheduler();
      final provider = TodoProvider()..scheduler = scheduler;
      addTearDown(provider.dispose);

      expect(
        await provider.scheduleTodoForToday(
          'same-id',
          now: _now,
          expectedAccountDataGeneration:
              AccountLocalDataCleaner.accountDataGeneration,
        ),
        isTrue,
      );
      final item = provider.todos.single;
      expect(item.title, 'authored title');
      expect(item.date, DateTime(2026, 10, 11));
      expect(item.dueDate, DateTime(2026, 10, 11, 9, 30));
      expect(item.reminderAt, item.dueDate);
      expect(item.reminder.enabled, isTrue);
      expect(item.reminder.hour, 9);
      expect(item.reminder.minute, 30);
      expect(scheduler.todoSyncs, [
        ['same-id'],
      ]);
      expect(
        await provider.scheduleTodoForToday('same-id', now: _now),
        isFalse,
      );
    },
  );

  test(
    'no-wait schedule returns while same-account reminders are pending',
    () async {
      final scheduler = _GatedScheduler();
      final provider = TodoProvider()..scheduler = scheduler;
      addTearDown(provider.dispose);
      final result = await provider.scheduleTodoForToday(
        'same-id',
        now: _now,
        waitForReminderSync: false,
      );
      expect(result, isTrue);
      expect(scheduler.started.isCompleted, isTrue);
      expect(scheduler.release.isCompleted, isFalse);
      scheduler.release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(provider.lastReminderSyncSucceededAt, isNotNull);
    },
  );
}

class _GatedLoadTodoProvider extends TodoProvider {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> loadFromStorage({bool force = false}) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    await super.loadFromStorage(force: force);
  }
}

class _GatedScheduler extends RecordingReminderScheduler {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
    ReminderReconciliationBatch? batch,
  }) async {
    todoSyncs.add(todos.map((todo) => todo.id).toList());
    if (!started.isCompleted) started.complete();
    await release.future;
  }
}

class _CallbackScheduler extends RecordingReminderScheduler {
  _CallbackScheduler(this.callback);
  final void Function() callback;

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
    ReminderReconciliationBatch? batch,
  }) async {
    callback();
  }
}
