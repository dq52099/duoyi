import 'dart:async';

import 'package:duoyi/core/i18n.dart' show AppLocale;
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/reminder_scheduler.dart'
    show ReminderReconciliationBatch, ReminderScheduleSyncException;
import 'package:duoyi/services/reminder_sync_issue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'legacy target override is called once and keeps unknown Chinese raw',
    () async {
      const raw = '系统返回了未知提醒错误：原文应保留';
      final scheduler = _LegacyTargetScheduler(raw);
      final provider = TodoProvider()..scheduler = scheduler;

      final result = await _addWithTargetReport(provider, 'legacy-target');

      expect(scheduler.targetCalls, 1);
      expect(scheduler.todoSyncCalls, 0);
      expect(result.issue, raw);
      expect(result.issueCopy, isNotNull);
      expect(result.issueCopy!.raw, raw);
      expect(result.issueCopy!.entries.single.copy, isNull);
      expect(result.issueCopy!.entries.single.notice, isNull);
      expect(result.issueCopy!.render(locale: AppLocale.zh), raw);
      expect(result.issueCopy!.render(locale: AppLocale.en), raw);
    },
  );

  test('typed target result preserves issue metadata identity', () async {
    final issue = _issue(
      'target failure',
      ReminderSyncIssueNotice.schedulerMissing,
    );
    final scheduler = _TypedTargetScheduler(Future.value(issue));
    final provider = TodoProvider()..scheduler = scheduler;

    final result = await _addWithTargetReport(provider, 'typed-target');

    expect(scheduler.targetCalls, 1);
    expect(result.issue, issue.raw);
    expect(identical(result.issueCopy, issue), isTrue);
    expect(identical(provider.lastReminderSyncIssueCopy, issue), isTrue);
    expect(identical(provider.lastReminderScheduleIssueCopy, issue), isTrue);
    expect(provider.lastReminderScheduleIssue, issue.raw);
  });

  test('full-list typed exception retains issue order and identity', () async {
    final issue = ReminderSyncIssue([
      const ReminderSyncIssueEntry(
        'first raw failure',
        notice: ReminderSyncIssueNotice.registrationUnconfirmed,
      ),
      const ReminderSyncIssueEntry(
        'second raw failure',
        notice: ReminderSyncIssueNotice.ruleNotRegistered,
      ),
    ]);
    final scheduler = _ThrowingSyncTodosScheduler(
      ReminderScheduleSyncException(const [
        'first raw failure',
        'second raw failure',
      ], issueCopy: issue),
    );
    final provider = TodoProvider()..scheduler = scheduler;

    final result = await _add(provider, 'full-list');

    expect(scheduler.syncCalls, 1);
    expect(result.issue, 'first raw failure；second raw failure');
    expect(identical(result.issueCopy, issue), isTrue);
    expect(result.issueCopy!.entries.map((entry) => entry.raw).toList(), [
      'first raw failure',
      'second raw failure',
    ]);
  });

  test('late empty full-list exception keeps empty raw and metadata', () async {
    final scheduler = _LateErrorSyncTodosScheduler(
      const ReminderScheduleSyncException([]),
    );
    final provider = TodoProvider()
      ..scheduler = scheduler
      ..reminderSyncTimeout = const Duration(milliseconds: 20);

    final result = await _add(provider, 'late-empty-aggregate');
    expect(result.issue, isNull);
    expect(result.issueCopy, isNull);
    expect(result.succeededAt, isNull);

    scheduler.completeSync();
    await _waitForLateRawIssue(provider, '');

    expect(provider.lastReminderSyncIssue, isEmpty);
    expect(provider.lastReminderSyncIssueCopy, isNull);
    expect(provider.lastReminderScheduleIssue, isNull);
    expect(provider.lastReminderScheduleIssueCopy, isNull);
  });

  test(
    'timeout reports no success then applies same-request late metadata',
    () async {
      final issue = _issue(
        'late target failure',
        ReminderSyncIssueNotice.schedulerMissing,
      );
      final gate = Completer<ReminderSyncIssue?>();
      final scheduler = _TypedTargetScheduler(gate.future);
      final provider = TodoProvider()
        ..scheduler = scheduler
        ..reminderSyncTimeout = const Duration(milliseconds: 20);

      final result = await _addWithTargetReport(provider, 'same-request');

      expect(result.issue, isNull);
      expect(result.issueCopy, isNull);
      expect(result.succeededAt, isNull);
      expect(provider.lastReminderSyncIssue, isNull);
      expect(provider.lastReminderSyncIssueCopy, isNull);
      expect(provider.lastReminderSyncSucceededAt, isNull);

      gate.complete(issue);
      await _waitForLateIssue(provider, issue);

      expect(provider.lastReminderSyncIssue, issue.raw);
      expect(identical(provider.lastReminderSyncIssueCopy, issue), isTrue);
      expect(identical(provider.lastReminderScheduleIssueCopy, issue), isTrue);
    },
  );

  test(
    'late metadata is ignored after a newer reminder sync request',
    () async {
      final lateIssue = _issue(
        'stale request',
        ReminderSyncIssueNotice.schedulerMissing,
      );
      final currentIssue = _issue(
        'current request',
        ReminderSyncIssueNotice.ruleNotRegistered,
      );
      final first = Completer<ReminderSyncIssue?>();
      final scheduler = _SequencedTypedTargetScheduler([
        first.future,
        Future.value(currentIssue),
      ]);
      final provider = TodoProvider()
        ..scheduler = scheduler
        ..reminderSyncTimeout = const Duration(milliseconds: 20);

      final timedOut = await _addWithTargetReport(provider, 'stale-request');
      expect(timedOut.succeededAt, isNull);

      final current = await _addWithTargetReport(provider, 'current-request');
      expect(current.issue, currentIssue.raw);
      expect(
        identical(provider.lastReminderSyncIssueCopy, currentIssue),
        isTrue,
      );

      first.complete(lateIssue);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(provider.lastReminderSyncIssue, currentIssue.raw);
      expect(
        identical(provider.lastReminderSyncIssueCopy, currentIssue),
        isTrue,
      );
      expect(
        identical(provider.lastReminderScheduleIssueCopy, currentIssue),
        isTrue,
      );
    },
  );

  test(
    'account reset clears issue pairs and suppresses late metadata',
    () async {
      final previousIssue = _issue(
        'previous request',
        ReminderSyncIssueNotice.schedulerMissing,
      );
      final lateIssue = _issue(
        'previous account',
        ReminderSyncIssueNotice.ruleNotRegistered,
      );
      final gate = Completer<ReminderSyncIssue?>();
      final scheduler = _SequencedTypedTargetScheduler([
        Future.value(previousIssue),
        gate.future,
      ]);
      final provider = TodoProvider()
        ..scheduler = scheduler
        ..reminderSyncTimeout = const Duration(milliseconds: 20);

      await _addWithTargetReport(provider, 'before-account-reset');
      expect(provider.lastReminderSyncIssue, previousIssue.raw);
      expect(
        identical(provider.lastReminderSyncIssueCopy, previousIssue),
        isTrue,
      );
      expect(provider.lastReminderScheduleIssue, previousIssue.raw);
      expect(
        identical(provider.lastReminderScheduleIssueCopy, previousIssue),
        isTrue,
      );

      final pending = provider.addTodoWithResult(
        TodoItem(id: 'account-reset-pending', title: 'account reset pending'),
        reportReminderScheduleFailure: true,
      );
      await scheduler.secondTargetStarted.future.timeout(
        const Duration(seconds: 1),
      );
      expect(provider.lastReminderSyncIssue, previousIssue.raw);
      expect(
        identical(provider.lastReminderSyncIssueCopy, previousIssue),
        isTrue,
      );

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      provider.resetLocalState();
      expect(provider.lastReminderSyncIssue, isNull);
      expect(provider.lastReminderSyncIssueCopy, isNull);
      expect(provider.lastReminderScheduleIssue, isNull);
      expect(provider.lastReminderScheduleIssueCopy, isNull);

      final timedOut = await pending;
      expect(timedOut, isNotNull);
      expect(timedOut!.issue, isNull);
      expect(timedOut.issueCopy, isNull);
      expect(timedOut.succeededAt, isNull);
      gate.complete(lateIssue);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(provider.lastReminderSyncIssue, isNull);
      expect(provider.lastReminderSyncIssueCopy, isNull);
      expect(provider.lastReminderScheduleIssue, isNull);
      expect(provider.lastReminderScheduleIssueCopy, isNull);
      expect(provider.lastReminderSyncSucceededAt, isNull);
    },
  );

  test(
    'scheduler missing owns a copy that is cleared on replacement',
    () async {
      final provider = TodoProvider();

      final result = await provider.addTodoWithResult(
        TodoItem(id: 'missing-scheduler', title: 'missing scheduler'),
      );

      expect(result, isNotNull);
      expect(result!.issue, 'reminder_scheduler_missing');
      expect(result.issueCopy, isNotNull);
      expect(result.issueCopy!.raw, 'reminder_scheduler_missing');
      expect(result.issueCopy!.entries, hasLength(1));
      expect(
        result.issueCopy!.entries.single.notice,
        ReminderSyncIssueNotice.schedulerMissing,
      );
      expect(provider.lastReminderSyncIssue, 'reminder_scheduler_missing');
      expect(
        identical(provider.lastReminderSyncIssueCopy, result.issueCopy),
        isTrue,
      );

      provider.scheduler = RecordingReminderScheduler();

      expect(provider.lastReminderSyncIssue, isNull);
      expect(provider.lastReminderSyncIssueCopy, isNull);
    },
  );

  test(
    'empty typed exception retains the original generic failure fallback',
    () async {
      final scheduler = _ThrowingSyncTodosScheduler(
        const ReminderScheduleSyncException([]),
      );
      final provider = TodoProvider()..scheduler = scheduler;

      final result = await _add(provider, 'empty-aggregate');

      expect(result.issue, '提醒未注册成功，请检查通知权限、提醒方式和提醒时间。');
      expect(result.issueCopy, isNotNull);
      expect(
        result.issueCopy!.render(locale: AppLocale.zh),
        '提醒未注册成功，请检查通知权限、提醒方式和提醒时间。',
      );
      expect(
        result.issueCopy!.render(locale: AppLocale.en),
        'The reminder was not registered. Check notification permission, reminder type and time.',
      );
    },
  );
}

Future<TodoReminderSyncResult> _add(TodoProvider provider, String id) async {
  final result = await provider.addTodoWithResult(TodoItem(id: id, title: id));
  return result!;
}

Future<TodoReminderSyncResult> _addWithTargetReport(
  TodoProvider provider,
  String id,
) async {
  final result = await provider.addTodoWithResult(
    TodoItem(id: id, title: id),
    reportReminderScheduleFailure: true,
  );
  return result!;
}

ReminderSyncIssue _issue(String raw, ReminderSyncIssueNotice notice) =>
    ReminderSyncIssue([ReminderSyncIssueEntry(raw, notice: notice)]);

Future<void> _waitForLateIssue(
  TodoProvider provider,
  ReminderSyncIssue issue,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (identical(provider.lastReminderSyncIssueCopy, issue)) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Timed out waiting for late reminder issue metadata');
}

Future<void> _waitForLateRawIssue(TodoProvider provider, String raw) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (provider.lastReminderSyncIssue == raw) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Timed out waiting for late reminder issue raw text');
}

class _LegacyTargetScheduler extends RecordingReminderScheduler {
  _LegacyTargetScheduler(this.failure);

  final String failure;
  int targetCalls = 0;
  int todoSyncCalls = 0;

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
    ReminderReconciliationBatch? batch,
  }) async {
    todoSyncCalls++;
    await super.syncTodos(
      todos,
      allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
      batch: batch,
    );
  }

  @override
  Future<String?> syncTodosAndGetTodoFailure(
    Iterable<TodoItem> todos,
    String todoId, {
    bool allowJustMissedOneShotReminders = true,
  }) {
    targetCalls++;
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    return Future<String?>.value(failure);
  }
}

class _TypedTargetScheduler extends RecordingReminderScheduler {
  _TypedTargetScheduler(this.issueResult);

  final Future<ReminderSyncIssue?> issueResult;
  int targetCalls = 0;

  @override
  Future<String?> syncTodosAndGetTodoFailure(
    Iterable<TodoItem> todos,
    String todoId, {
    bool allowJustMissedOneShotReminders = true,
  }) {
    targetCalls++;
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    return ReminderTodoFailureFuture(issueResult);
  }
}

class _SequencedTypedTargetScheduler extends RecordingReminderScheduler {
  _SequencedTypedTargetScheduler(this.issueResults);

  final List<Future<ReminderSyncIssue?>> issueResults;
  final Completer<void> secondTargetStarted = Completer<void>();
  int targetCalls = 0;

  @override
  Future<String?> syncTodosAndGetTodoFailure(
    Iterable<TodoItem> todos,
    String todoId, {
    bool allowJustMissedOneShotReminders = true,
  }) {
    final callIndex = targetCalls++;
    if (callIndex == 1 && !secondTargetStarted.isCompleted) {
      secondTargetStarted.complete();
    }
    final issueResult = issueResults[callIndex];
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    return ReminderTodoFailureFuture(issueResult);
  }
}

class _LateErrorSyncTodosScheduler extends RecordingReminderScheduler {
  _LateErrorSyncTodosScheduler(this.error);

  final Object error;
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

class _ThrowingSyncTodosScheduler extends RecordingReminderScheduler {
  _ThrowingSyncTodosScheduler(this.error);

  final Object error;
  int syncCalls = 0;

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
    ReminderReconciliationBatch? batch,
  }) async {
    syncCalls++;
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    throw error;
  }
}
