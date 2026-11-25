// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/domain_event_bus.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/reminder_scheduler.dart'
    show ReminderReconciliationBatch, ReminderScheduleSyncException;
import 'package:duoyi/services/reminder_sync_issue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('dispose suppresses an in-flight current sync result', () async {
    final issue = _issue('completed after dispose');
    final scheduler = _GatedTypedTargetScheduler();
    final provider = TodoProvider()..scheduler = scheduler;
    var notifications = 0;
    provider.addListener(() => notifications++);

    final pending = provider.addTodoWithResult(
      TodoItem(id: 'dispose-current-sync', title: 'current sync'),
      reportReminderScheduleFailure: true,
    );
    await scheduler.started.future.timeout(const Duration(seconds: 1));

    final revisionBeforeDispose = provider.revision;
    final todoIdsBeforeDispose = provider.todos.map((todo) => todo.id).toList();
    final notificationsBeforeDispose = notifications;
    provider.dispose();

    scheduler.complete(issue);
    await pending;

    expect(provider.revision, revisionBeforeDispose);
    expect(
      provider.todos.map((todo) => todo.id).toList(),
      todoIdsBeforeDispose,
    );
    expect(provider.lastReminderSyncIssue, isNull);
    expect(provider.lastReminderSyncIssueCopy, isNull);
    expect(provider.lastReminderScheduleIssue, isNull);
    expect(provider.lastReminderScheduleIssueCopy, isNull);
    expect(notifications, notificationsBeforeDispose);
  });

  test('dispose suppresses timed-out typed late success', () async {
    final scheduler = _GatedTypedTargetScheduler();
    final provider = TodoProvider()
      ..scheduler = scheduler
      ..reminderSyncTimeout = const Duration(milliseconds: 20);
    var notifications = 0;
    provider.addListener(() => notifications++);

    final result = await provider.addTodoWithResult(
      TodoItem(id: 'dispose-late-success', title: 'late success'),
      reportReminderScheduleFailure: true,
    );
    expect(result, isNotNull);
    expect(result!.issue, isNull);
    expect(result.issueCopy, isNull);
    expect(result.succeededAt, isNull);
    expect(provider.lastReminderSyncIssue, isNull);
    expect(provider.lastReminderSyncIssueCopy, isNull);
    final notificationsBeforeDispose = notifications;

    provider.dispose();
    scheduler.completeSuccess();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(provider.lastReminderSyncIssue, isNull);
    expect(provider.lastReminderSyncIssueCopy, isNull);
    expect(provider.lastReminderScheduleIssue, isNull);
    expect(provider.lastReminderScheduleIssueCopy, isNull);
    expect(provider.lastReminderSyncSucceededAt, isNull);
    expect(notifications, notificationsBeforeDispose);
  });

  test('dispose suppresses timed-out late aggregate error', () async {
    final issue = ReminderSyncIssue([
      const ReminderSyncIssueEntry(
        'late aggregate raw',
        notice: ReminderSyncIssueNotice.genericFailure,
      ),
    ]);
    final scheduler = _GatedAggregateErrorScheduler(
      ReminderScheduleSyncException(const [
        'late aggregate raw',
      ], issueCopy: issue),
    );
    final provider = TodoProvider()
      ..scheduler = scheduler
      ..reminderSyncTimeout = const Duration(milliseconds: 20);
    var notifications = 0;
    provider.addListener(() => notifications++);

    final result = await provider.addTodoWithResult(
      TodoItem(id: 'dispose-late-error', title: 'late aggregate error'),
    );
    expect(result, isNotNull);
    expect(result!.issue, isNull);
    expect(result.issueCopy, isNull);
    expect(result.succeededAt, isNull);
    expect(provider.lastReminderSyncIssue, isNull);
    expect(provider.lastReminderSyncIssueCopy, isNull);
    final notificationsBeforeDispose = notifications;

    provider.dispose();
    scheduler.completeSync();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(provider.lastReminderSyncIssue, isNull);
    expect(provider.lastReminderSyncIssueCopy, isNull);
    expect(provider.lastReminderScheduleIssue, isNull);
    expect(provider.lastReminderScheduleIssueCopy, isNull);
    expect(provider.lastReminderSyncSucceededAt, isNull);
    expect(notifications, notificationsBeforeDispose);
  });

  test(
    'dispose during storage load prevents late hydration and notification',
    () async {
      final todo = TodoItem(id: 'disposed-load', title: 'late hydration');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'todos': jsonEncode(<Map<String, dynamic>>[todo.toJson()]),
      });
      final provider = TodoProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);
      final revisionBeforeDispose = provider.revision;

      final pendingLoad = provider.loadFromStorage();
      provider.dispose();
      await pendingLoad;

      expect(provider.todos, isEmpty);
      expect(provider.revision, revisionBeforeDispose);
      expect(notifications, 0);
    },
  );

  test(
    'same-account reminder sync success still applies before dispose',
    () async {
      final provider = TodoProvider()..scheduler = RecordingReminderScheduler();

      final result = await provider.addTodoWithResult(
        TodoItem(id: 'same-account-success', title: 'successful sync'),
        reportReminderScheduleFailure: true,
      );

      expect(result, isNotNull);
      expect(result!.issue, isNull);
      expect(result.issueCopy, isNull);
      expect(result.succeededAt, isNotNull);
      expect(provider.lastReminderSyncIssue, isNull);
      expect(provider.lastReminderSyncIssueCopy, isNull);
      expect(provider.lastReminderSyncSucceededAt, isNotNull);
      expect(provider.lastReminderScheduleIssue, isNull);
      expect(provider.lastReminderScheduleIssueCopy, isNull);

      provider.dispose();
    },
  );

  test(
    'disposed hydrated provider returns neutral CRUD results without mutation',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = TodoProvider();
      await provider.loadFromStorage();
      final issue = _issue('seed reminder failure');
      final scheduler = _SeedIssueRecordingScheduler(issue);
      provider.scheduler = scheduler;
      final tasks = <TodoItem>[
        TodoItem(
          id: 'disposed-completed',
          title: 'completed task',
          isCompleted: true,
          sortOrder: 0,
          date: DateTime(2026, 10, 1),
        ),
        TodoItem(
          id: 'disposed-schedule',
          title: 'schedule after dispose',
          quadrant: EisenhowerQuadrant.notUrgentNotImportant,
          priority: TodoPriority.low,
          sortOrder: 1,
          date: DateTime(2026, 10, 1),
          dueDate: DateTime(2026, 10, 1),
        ),
        TodoItem(
          id: 'disposed-quadrant',
          title: 'update after dispose',
          quadrant: EisenhowerQuadrant.notUrgentNotImportant,
          priority: TodoPriority.low,
          sortOrder: 2,
          date: DateTime(2026, 10, 2),
        ),
      ];
      for (final task in tasks) {
        final seeded = await provider.addTodoWithResult(
          task,
          reportReminderScheduleFailure: true,
        );
        expect(seeded!.issue, issue.raw);
      }

      final prefs = await SharedPreferences.getInstance();
      final storedBeforeDispose = prefs.getString('todos');
      final todosBeforeDispose = List<TodoItem>.of(provider.todos);
      final todoJsonBeforeDispose = provider.todos
          .map((todo) => jsonEncode(todo.toJson()))
          .toList();
      final revisionBeforeDispose = provider.revision;
      final completionRateBeforeDispose = provider.mineCompletionRate;
      final activeIdsBeforeDispose = provider.activeTodos
          .map((todo) => todo.id)
          .toList();
      final completedIdsBeforeDispose = provider.completedTodos
          .map((todo) => todo.id)
          .toList();
      final rawIssueBeforeDispose = provider.lastReminderSyncIssue;
      final issueCopyBeforeDispose = provider.lastReminderSyncIssueCopy;
      final rawScheduleIssueBeforeDispose = provider.lastReminderScheduleIssue;
      final scheduleIssueCopyBeforeDispose =
          provider.lastReminderScheduleIssueCopy;
      final targetCallsBeforeDispose = scheduler.targetCalls;
      final fullCallsBeforeDispose = scheduler.fullCalls;
      var notifications = 0;
      provider.addListener(() => notifications++);
      final notificationsBeforeDispose = notifications;

      provider.dispose();

      final imported = await provider.importTodos([
        TodoItem(
          id: 'new-after-dispose',
          title: 'newly imported after dispose',
          date: DateTime(2026, 10, 3),
        ),
      ]);
      expect(imported.inserted, 0);
      expect(imported.skippedDuplicates, 0);
      expect(imported.reminderSyncIssue, isNull);
      expect(
        await provider.updateTodosQuadrant([
          'disposed-schedule',
          'disposed-quadrant',
        ], EisenhowerQuadrant.urgentImportant),
        0,
      );
      expect(
        await provider.updateTodosPriority([
          'disposed-schedule',
          'disposed-quadrant',
        ], TodoPriority.urgent),
        0,
      );
      await provider.reorder([
        'disposed-quadrant',
        'disposed-schedule',
        'disposed-completed',
      ]);
      expect(
        await provider.scheduleTodoForToday(
          'disposed-schedule',
          now: DateTime(2026, 10, 8, 9),
        ),
        isFalse,
      );

      expect(provider.todos, hasLength(todosBeforeDispose.length));
      for (var index = 0; index < todosBeforeDispose.length; index++) {
        expect(
          identical(provider.todos[index], todosBeforeDispose[index]),
          isTrue,
        );
      }
      expect(
        provider.todos.map((todo) => jsonEncode(todo.toJson())).toList(),
        todoJsonBeforeDispose,
      );
      expect(provider.revision, revisionBeforeDispose);
      expect(provider.mineCompletionRate, completionRateBeforeDispose);
      expect(
        provider.activeTodos.map((todo) => todo.id).toList(),
        activeIdsBeforeDispose,
      );
      expect(
        provider.completedTodos.map((todo) => todo.id).toList(),
        completedIdsBeforeDispose,
      );
      expect(provider.lastReminderSyncIssue, rawIssueBeforeDispose);
      expect(
        identical(provider.lastReminderSyncIssueCopy, issueCopyBeforeDispose),
        isTrue,
      );
      expect(provider.lastReminderScheduleIssue, rawScheduleIssueBeforeDispose);
      expect(
        identical(
          provider.lastReminderScheduleIssueCopy,
          scheduleIssueCopyBeforeDispose,
        ),
        isTrue,
      );
      expect(notifications, notificationsBeforeDispose);
      expect(scheduler.targetCalls, targetCallsBeforeDispose);
      expect(scheduler.fullCalls, fullCallsBeforeDispose);
      expect(
        (await SharedPreferences.getInstance()).getString('todos'),
        storedBeforeDispose,
      );
    },
  );

  test(
    'import aborts without mutation when disposal interrupts hydration',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storedTodo = TodoItem(
        id: 'gated-existing',
        title: 'existing persisted task',
        date: DateTime(2026, 10, 5),
      );
      final storedJson = jsonEncode(<Map<String, dynamic>>[
        storedTodo.toJson(),
      ]);
      final store = _GatedPreferencesStore(<String, Object>{
        'flutter.todos': storedJson,
      });
      SharedPreferencesStorePlatform.instance = store;
      final scheduler = RecordingReminderScheduler();
      final provider = TodoProvider()..scheduler = scheduler;
      var notifications = 0;
      provider.addListener(() => notifications++);

      final pendingImport = provider.importTodos([
        TodoItem(
          id: 'gated-import',
          title: 'must not be imported',
          date: DateTime(2026, 10, 6),
        ),
      ]);
      await store.getAllEntered.future.timeout(const Duration(seconds: 1));
      final revisionBeforeDispose = provider.revision;

      provider.dispose();
      store.releaseGetAll.complete();
      final summary = await pendingImport;

      expect(summary.inserted, 0);
      expect(summary.skippedDuplicates, 0);
      expect(summary.reminderSyncIssue, isNull);
      expect(provider.todos, isEmpty);
      expect(provider.revision, revisionBeforeDispose);
      expect(notifications, 0);
      expect(scheduler.todoSyncs, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString('todos'),
        storedJson,
      );
    },
  );

  test('pending hydrated CRUD awaits return neutral after disposal', () async {
    final todos = <TodoItem>[
      TodoItem(
        id: 'await-quadrant-todo',
        title: 'quadrant await race',
        quadrant: EisenhowerQuadrant.notUrgentNotImportant,
        date: DateTime(2026, 10, 1),
        sortOrder: 0,
      ),
      TodoItem(
        id: 'await-priority-todo',
        title: 'priority await race',
        priority: TodoPriority.low,
        date: DateTime(2026, 10, 1),
        sortOrder: 1,
      ),
      TodoItem(
        id: 'await-schedule-todo',
        title: 'schedule await race',
        date: DateTime(2026, 10, 1),
        dueDate: DateTime(2026, 10, 1),
        sortOrder: 2,
      ),
      TodoItem(
        id: 'await-subtask-todo',
        title: 'subtask await race',
        date: DateTime(2026, 10, 1),
        sortOrder: 3,
      ),
    ];
    final storedJson = jsonEncode(todos.map((todo) => todo.toJson()).toList());
    SharedPreferences.setMockInitialValues(<String, Object>{
      'todos': storedJson,
    });
    final scheduler = RecordingReminderScheduler();
    final provider = TodoProvider()..scheduler = scheduler;
    await provider.loadFromStorage();
    final prefs = await SharedPreferences.getInstance();
    final todosBeforeDispose = List<TodoItem>.of(provider.todos);
    final jsonBeforeDispose = provider.todos
        .map((item) => jsonEncode(item.toJson()))
        .toList();
    final revisionBeforeDispose = provider.revision;
    final completionRateBeforeDispose = provider.mineCompletionRate;
    var notifications = 0;
    provider.addListener(() => notifications++);
    final events = <DomainEvent>[];
    final subscription = DomainEventBus.instance.events.listen(events.add);

    final pendingImport = provider.importTodos([
      TodoItem(id: 'await-import', title: 'pending import'),
    ]);
    final pendingQuadrant = provider.updateTodosQuadrant([
      'await-quadrant-todo',
    ], EisenhowerQuadrant.urgentImportant);
    final pendingPriority = provider.updateTodosPriority([
      'await-priority-todo',
    ], TodoPriority.urgent);
    final pendingReorder = provider.reorder(
      todos.reversed.map((todo) => todo.id).toList(),
    );
    final pendingSchedule = provider.scheduleTodoForToday(
      'await-schedule-todo',
      now: DateTime(2026, 10, 8, 9),
    );
    final pendingSubtask = provider.addSubtask(
      'await-subtask-todo',
      'pending child',
    );

    provider.dispose();
    try {
      final summary = await pendingImport;
      expect(summary.inserted, 0);
      expect(summary.skippedDuplicates, 0);
      expect(summary.reminderSyncIssue, isNull);
      expect(await pendingQuadrant, 0);
      expect(await pendingPriority, 0);
      await pendingReorder;
      expect(await pendingSchedule, isFalse);
      await pendingSubtask;

      expect(provider.todos, hasLength(todosBeforeDispose.length));
      for (var index = 0; index < todosBeforeDispose.length; index++) {
        expect(
          identical(provider.todos[index], todosBeforeDispose[index]),
          isTrue,
        );
      }
      expect(
        provider.todos.map((item) => jsonEncode(item.toJson())).toList(),
        jsonBeforeDispose,
      );
      expect(provider.revision, revisionBeforeDispose);
      expect(provider.mineCompletionRate, completionRateBeforeDispose);
      expect(provider.todos.every((todo) => todo.subtasks.isEmpty), isTrue);
      expect(notifications, 0);
      expect(events, isEmpty);
      expect(scheduler.todoSyncs, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString('todos'),
        storedJson,
      );
      expect(prefs.getString('todos'), storedJson);
    } finally {
      await subscription.cancel();
    }
  });

  test(
    'synchronous import event disposal stops later imported items',
    () async {
      final existing = TodoItem(
        id: 'import-event-existing',
        title: 'existing item',
        date: DateTime(2026, 10, 1),
      );
      final storedJson = jsonEncode(<Map<String, dynamic>>[existing.toJson()]);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'todos': storedJson,
      });
      final scheduler = RecordingReminderScheduler();
      final provider = TodoProvider()..scheduler = scheduler;
      await provider.loadFromStorage();
      final prefs = await SharedPreferences.getInstance();
      final revisionBeforeImport = provider.revision;
      var notifications = 0;
      provider.addListener(() => notifications++);
      final publishedIds = <String>[];
      List<String>? disposedTodos;
      int? revisionAtDispose;
      final subscription = DomainEventBus.instance.events.listen((event) {
        if (event.type != DomainEventType.todoCreated ||
            !{'event-first', 'event-second'}.contains(event.objectId)) {
          return;
        }
        publishedIds.add(event.objectId);
        if (disposedTodos != null) return;
        disposedTodos = provider.todos.map((item) => item.id).toList();
        revisionAtDispose = provider.revision;
        provider.dispose();
      });

      try {
        final summary = await provider.importTodos([
          TodoItem(
            id: 'event-first',
            title: 'first imported item',
            date: DateTime(2026, 10, 2),
          ),
          TodoItem(
            id: 'event-second',
            title: 'second imported item',
            date: DateTime(2026, 10, 3),
          ),
        ]);

        expect(summary.inserted, 0);
        expect(summary.skippedDuplicates, 0);
        expect(summary.reminderSyncIssue, isNull);
        expect(publishedIds, ['event-first']);
        expect(disposedTodos, ['import-event-existing', 'event-first']);
        expect(revisionAtDispose, revisionBeforeImport);
        expect(provider.todos.map((item) => item.id).toList(), disposedTodos);
        expect(provider.revision, revisionAtDispose);
        expect(notifications, 0);
        expect(scheduler.todoSyncs, isEmpty);
        expect(
          (await SharedPreferences.getInstance()).getString('todos'),
          storedJson,
        );
        expect(prefs.getString('todos'), storedJson);
      } finally {
        await subscription.cancel();
        if (disposedTodos == null) provider.dispose();
      }
    },
  );

  test(
    'durable completion event disposal suppresses later notifications and sync',
    () async {
      final recurring = TodoItem(
        id: 'complete-event-recurring',
        title: 'recurring task',
        date: DateTime(2026, 10, 1),
        recurrence: const RecurrenceRule(frequency: RecurrenceFrequency.daily),
      );
      final storedJson = jsonEncode(<Map<String, dynamic>>[recurring.toJson()]);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'todos': storedJson,
      });
      final scheduler = RecordingReminderScheduler();
      final provider = TodoProvider()..scheduler = scheduler;
      await provider.loadFromStorage();
      final prefs = await SharedPreferences.getInstance();
      final revisionBeforeCompletion = provider.revision;
      var notifications = 0;
      provider.addListener(() => notifications++);
      final publishedIds = <String>[];
      List<String>? disposedTodos;
      int? revisionAtDispose;
      final subscription = DomainEventBus.instance.events.listen((event) {
        if (event.type != DomainEventType.todoCompleted ||
            event.objectId != recurring.id) {
          return;
        }
        publishedIds.add(event.objectId);
        disposedTodos = provider.todos.map((item) => item.id).toList();
        revisionAtDispose = provider.revision;
        provider.dispose();
      });

      try {
        final changed = await provider.completeTodos([
          recurring.id,
        ], recordCompletionTime: false);

        expect(changed, 0);
        expect(publishedIds, [recurring.id]);
        expect(disposedTodos, hasLength(2));
        expect(disposedTodos!.first, recurring.id);
        expect(provider.todos, hasLength(2));
        expect(provider.todos.first.id, recurring.id);
        expect(provider.todos.first.isCompleted, isTrue);
        expect(provider.todos.first.recurrence.isActive, isTrue);
        expect(provider.todos.last.isCompleted, isFalse);
        expect(provider.revision, revisionAtDispose);
        expect(revisionAtDispose, revisionBeforeCompletion);
        expect(notifications, 0);
        expect(scheduler.todoSyncs, isEmpty);
        expect(
          (await SharedPreferences.getInstance()).getString('todos'),
          jsonEncode(provider.todos.map((todo) => todo.toJson()).toList()),
        );
        expect(
          prefs.getString('todos'),
          jsonEncode(provider.todos.map((todo) => todo.toJson()).toList()),
        );
      } finally {
        await subscription.cancel();
        if (disposedTodos == null) provider.dispose();
      }
    },
  );
}

ReminderSyncIssue _issue(String raw) => ReminderSyncIssue([
  ReminderSyncIssueEntry(raw, notice: ReminderSyncIssueNotice.schedulerMissing),
]);

class _GatedTypedTargetScheduler extends RecordingReminderScheduler {
  final Completer<void> started = Completer<void>();
  final Completer<ReminderSyncIssue?> _issue = Completer<ReminderSyncIssue?>();

  void complete(ReminderSyncIssue issue) {
    if (!_issue.isCompleted) _issue.complete(issue);
  }

  void completeSuccess() {
    if (!_issue.isCompleted) _issue.complete(null);
  }

  @override
  Future<String?> syncTodosAndGetTodoFailure(
    Iterable<TodoItem> todos,
    String todoId, {
    bool allowJustMissedOneShotReminders = true,
  }) {
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    if (!started.isCompleted) started.complete();
    return ReminderTodoFailureFuture(_issue.future);
  }
}

class _GatedAggregateErrorScheduler extends RecordingReminderScheduler {
  _GatedAggregateErrorScheduler(this.error);

  final ReminderScheduleSyncException error;
  final Completer<void> started = Completer<void>();
  final Completer<void> _gate = Completer<void>();

  void completeSync() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
    ReminderReconciliationBatch? batch,
  }) async {
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    if (!started.isCompleted) started.complete();
    await _gate.future;
    throw error;
  }
}

class _SeedIssueRecordingScheduler extends RecordingReminderScheduler {
  _SeedIssueRecordingScheduler(this.issue);

  final ReminderSyncIssue issue;
  int targetCalls = 0;
  int fullCalls = 0;

  @override
  Future<String?> syncTodosAndGetTodoFailure(
    Iterable<TodoItem> todos,
    String todoId, {
    bool allowJustMissedOneShotReminders = true,
  }) {
    targetCalls++;
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    return ReminderTodoFailureFuture(Future.value(issue));
  }

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
    ReminderReconciliationBatch? batch,
  }) async {
    fullCalls++;
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
  }
}

class _GatedPreferencesStore extends InMemorySharedPreferencesStore {
  _GatedPreferencesStore(super.data) : super.withData();

  final Completer<void> getAllEntered = Completer<void>();
  final Completer<void> releaseGetAll = Completer<void>();

  @override
  Future<Map<String, Object>> getAll() async {
    if (!getAllEntered.isCompleted) getAllEntered.complete();
    await releaseGetAll.future;
    return super.getAll();
  }
}
