import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/goal.dart' show ReminderConfig, ReminderKind;
import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/reminder_scheduler.dart'
    show ReminderReconciliationBatch;

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('repeating todo keeps reminder config on generated next todo', () async {
    final provider = TodoProvider();
    final firstDate = DateTime(2026, 5, 10, 9);
    final dueDate = DateTime(2026, 5, 10, 18);
    final todo = TodoItem(
      title: 'repeat with reminder',
      date: firstDate,
      dueDate: dueDate,
      recurrence: const RecurrenceRule(frequency: RecurrenceFrequency.daily),
      // ignore: deprecated_member_use_from_same_package
      hasReminder: true,
      // ignore: deprecated_member_use_from_same_package
      reminderAt: DateTime(2026, 5, 10, 17, 30),
      reminder: const ReminderConfig(
        enabled: true,
        kind: ReminderKind.alarm,
        hour: 17,
        minute: 30,
      ),
    );

    await provider.addTodo(todo);
    await provider.toggleTodo(todo.id);

    expect(provider.todos.length, 2);
    final next = provider.todos.firstWhere((t) => t.id != todo.id);
    expect(next.date, DateTime(2026, 5, 11, 9));
    expect(next.dueDate, DateTime(2026, 5, 11, 18));
    expect(next.recurrence.frequency, RecurrenceFrequency.daily);
    expect(next.reminder.enabled, isTrue);
    expect(next.reminder.kind, ReminderKind.alarm);
    expect(next.reminder.hour, 17);
    expect(next.reminder.minute, 30);
    // ignore: deprecated_member_use_from_same_package
    expect(next.hasReminder, isTrue);
    // ignore: deprecated_member_use_from_same_package
    expect(next.reminderAt, DateTime(2026, 5, 11, 17, 30));
  });

  test('repeating todo honors max occurrence count', () async {
    final provider = TodoProvider();
    final todo = TodoItem(
      title: 'repeat twice',
      date: DateTime(2026, 5, 10, 9),
      recurrence: const RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        maxOccurrences: 2,
      ),
    );

    await provider.addTodo(todo);
    await provider.toggleTodo(todo.id);

    expect(provider.todos.length, 2);
    final second = provider.todos.firstWhere((t) => t.id != todo.id);
    expect(second.date, DateTime(2026, 5, 11, 9));
    expect(second.recurrence.maxOccurrences, 1);

    await provider.toggleTodo(second.id);

    expect(provider.todos.length, 2);
    expect(provider.todos.every((t) => t.isCompleted), isTrue);
  });

  test('todo provider exposes reminder sync diagnostics', () async {
    final missingSchedulerProvider = TodoProvider();
    await missingSchedulerProvider.addTodo(TodoItem(title: 'needs scheduler'));

    expect(
      missingSchedulerProvider.lastReminderSyncIssue,
      'reminder_scheduler_missing',
    );
    expect(missingSchedulerProvider.lastReminderSyncAttemptAt, isNotNull);
    expect(missingSchedulerProvider.lastReminderSyncSucceededAt, isNull);

    final scheduler = RecordingReminderScheduler();
    missingSchedulerProvider.scheduler = scheduler;
    await missingSchedulerProvider.updateTodo(
      missingSchedulerProvider.todos.single.id,
      missingSchedulerProvider.todos.single.copyWith(title: 'synced'),
    );

    expect(missingSchedulerProvider.lastReminderSyncIssue, isNull);
    expect(missingSchedulerProvider.lastReminderSyncSucceededAt, isNotNull);
    expect(scheduler.todoSyncs.last, [
      missingSchedulerProvider.todos.single.id,
    ]);

    scheduler.todoSyncError = StateError('native queue rejected');
    await missingSchedulerProvider.updateTodo(
      missingSchedulerProvider.todos.single.id,
      missingSchedulerProvider.todos.single.copyWith(title: 'failed sync'),
    );

    expect(
      missingSchedulerProvider.lastReminderSyncIssue,
      contains('native queue rejected'),
    );
  });

  test('addTodo waits for reminder sync before completing', () async {
    final provider = TodoProvider();
    final scheduler = _GatedTodoScheduler();
    provider.scheduler = scheduler;
    final todo = TodoItem(id: 'todo-sync-wait', title: 'wait for sync');

    var completed = false;
    final save = provider.addTodo(todo).then((_) {
      completed = true;
    });
    await _waitForScheduler(scheduler);

    expect(scheduler.started, isTrue);
    expect(completed, isFalse);

    scheduler.complete();
    await save;

    expect(completed, isTrue);
    expect(scheduler.todoSyncs.single, ['todo-sync-wait']);
    expect(provider.lastReminderSyncIssue, isNull);
    expect(provider.lastReminderSyncSucceededAt, isNotNull);
  });

  test('addTodo keeps saved todo when reminder sync fails', () async {
    final provider = TodoProvider();
    final scheduler = RecordingReminderScheduler()
      ..todoSyncError = StateError('cancel old reminder failed');
    provider.scheduler = scheduler;
    final todo = TodoItem(id: 'todo-sync-error', title: 'sync error');

    await provider.addTodo(todo);

    expect(provider.todos.single.id, todo.id);
    expect(
      provider.lastReminderSyncIssue,
      contains('cancel old reminder failed'),
    );
  });

  test('awaited todo reminder sync ignores stale background failure', () async {
    final provider = TodoProvider();
    final scheduler = _InterleavedTodoScheduler();
    provider.scheduler = scheduler;

    await provider.addTodo(
      TodoItem(id: 'background-todo', title: 'background'),
      waitForReminderSync: false,
    );
    await scheduler.firstStarted.future.timeout(const Duration(seconds: 1));

    final current = provider.addTodoWithResult(
      TodoItem(id: 'current-todo', title: 'current'),
    );
    await scheduler.secondStarted.future.timeout(const Duration(seconds: 1));

    scheduler.completeFirstWithError(StateError('old background rejected'));
    await scheduler.firstDone.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);

    expect(provider.lastReminderSyncIssue, isNull);

    scheduler.completeSecond();
    final result = await current;
    expect(result, isNotNull);
    expect(result!.issue, isNull);
    expect(provider.lastReminderSyncIssue, isNull);
    expect(provider.todos.map((todo) => todo.id), contains('background-todo'));
    expect(provider.todos.map((todo) => todo.id), contains('current-todo'));
  });
  test(
    'revision increments on every notify for derived-data memoization',
    () async {
      final provider = TodoProvider();
      final before = provider.revision;
      await provider.addTodo(TodoItem(id: 'rev-1', title: '修订一'));
      final afterAdd = provider.revision;
      expect(afterAdd, greaterThan(before));

      await provider.updateTodo(
        'rev-1',
        provider.todos.single.copyWith(title: '修订二'),
      );
      expect(provider.revision, greaterThan(afterAdd));
    },
  );

  test(
    'reminder sync confirmation timeout is not reported as failure',
    () async {
      final provider = TodoProvider()
        ..reminderSyncTimeout = const Duration(milliseconds: 40);
      final scheduler = _GatedTodoScheduler()
        ..gatedFailureResult = 'registrar rejected';
      provider.scheduler = scheduler;
      final todo = TodoItem(id: 'timeout-todo', title: '确认超时');

      await provider.addTodo(todo, reportReminderScheduleFailure: true);

      // 确认超时不等于注册失败：不应给出误导性的失败提示。
      expect(provider.lastReminderSyncIssue, isNull);
      expect(provider.lastReminderScheduleIssue, isNull);

      scheduler.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 底层同步完成后按真实结果补记诊断。
      expect(
        provider.lastReminderScheduleIssue,
        contains('registrar rejected'),
      );
    },
  );
}

Future<void> _waitForScheduler(_GatedTodoScheduler scheduler) async {
  for (var i = 0; i < 50; i++) {
    if (scheduler.started) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _GatedTodoScheduler extends RecordingReminderScheduler {
  final Completer<void> _gate = Completer<void>();

  bool get started => todoSyncs.isNotEmpty;

  Object? gatedFailureResult;

  void complete() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
    ReminderReconciliationBatch? batch,
  }) async {
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    await _gate.future;
  }

  @override
  Future<String?> syncTodosAndGetTodoFailure(
    Iterable<TodoItem> todos,
    String todoId, {
    bool allowJustMissedOneShotReminders = true,
  }) async {
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    await _gate.future;
    return gatedFailureResult?.toString();
  }
}

class _InterleavedTodoScheduler extends RecordingReminderScheduler {
  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> secondStarted = Completer<void>();
  final Completer<void> firstDone = Completer<void>();
  final Completer<Object?> _releaseFirst = Completer<Object?>();
  final Completer<void> _releaseSecond = Completer<void>();
  int _calls = 0;

  void completeFirstWithError(Object error) {
    if (!_releaseFirst.isCompleted) _releaseFirst.complete(error);
  }

  void completeSecond() {
    if (!_releaseSecond.isCompleted) _releaseSecond.complete();
  }

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
    ReminderReconciliationBatch? batch,
  }) async {
    _calls++;
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    if (_calls == 1) {
      if (!firstStarted.isCompleted) firstStarted.complete();
      try {
        final error = await _releaseFirst.future;
        if (error != null) throw error;
      } finally {
        if (!firstDone.isCompleted) firstDone.complete();
      }
    } else if (_calls == 2) {
      if (!secondStarted.isCompleted) secondStarted.complete();
      await _releaseSecond.future;
    }
  }
}
