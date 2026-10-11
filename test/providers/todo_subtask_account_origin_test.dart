import 'dart:async';
import 'dart:convert';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/recording_reminder_scheduler.dart';

enum _Action { add, toggle, delete, deleteLast, reorder }

TodoItem _todo(String title, _Action action) => TodoItem(
  id: 'same-id',
  title: title,
  subtasks: [
    Subtask(id: 'same-subtask', title: 'first', sortOrder: 0),
    if (action != _Action.deleteLast)
      Subtask(id: 'second-subtask', title: 'second', sortOrder: 1),
  ],
);

String _payload(TodoItem todo) => jsonEncode([todo.toJson()]);

Future<void> _mutate(TodoProvider provider, _Action action, {int? origin}) =>
    switch (action) {
      _Action.add => provider.addSubtask(
        'same-id',
        'new child',
        expectedAccountDataGeneration: origin,
      ),
      _Action.toggle => provider.toggleSubtask(
        'same-id',
        'same-subtask',
        expectedAccountDataGeneration: origin,
      ),
      _Action.delete || _Action.deleteLast => provider.deleteSubtask(
        'same-id',
        'same-subtask',
        expectedAccountDataGeneration: origin,
      ),
      _Action.reorder => provider.reorderSubtasks('same-id', [
        'second-subtask',
        'same-subtask',
      ], expectedAccountDataGeneration: origin),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final action in _Action.values) {
    group('$action', () {
      setUp(
        () => SharedPreferences.setMockInitialValues({
          'todos': _payload(_todo('old', action)),
        }),
      );

      test('$action rejects explicit stale origin before hydration', () async {
        final provider = _GatedLoadTodoProvider();
        addTearDown(provider.dispose);
        final origin = AccountLocalDataCleaner.accountDataGeneration;
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        await _mutate(provider, action, origin: origin);
        expect(provider.started.isCompleted, isFalse);
        final pending = _mutate(provider, action);
        await provider.started.future;
        provider.release.complete();
        await pending;
        expect(
          provider.todos.single.toJson(),
          isNot(_todo('old', action).toJson()),
        );
      });

      for (final switchAccount in [false, true]) {
        test(
          '$action cancels hydration after reset (account=$switchAccount)',
          () async {
            final provider = _GatedLoadTodoProvider();
            final scheduler = RecordingReminderScheduler();
            provider.scheduler = scheduler;
            addTearDown(provider.dispose);
            final pending = _mutate(provider, action);
            await provider.started.future;
            if (switchAccount) {
              AccountLocalDataCleaner.invalidateInFlightAccountWrites();
            }
            provider.resetLocalState();
            final next = _todo('next', action);
            final stored = _payload(next);
            SharedPreferences.setMockInitialValues({'todos': stored});
            provider.release.complete();
            await pending;
            expect(provider.todos.single.toJson(), next.toJson());
            expect(
              (await SharedPreferences.getInstance()).getString('todos'),
              stored,
            );
            expect(scheduler.todoSyncs, isEmpty);
            // Stale actions release both the action-specific and shared ID claim.
            await _mutate(provider, action);
            expect(provider.todos.single.toJson(), isNot(next.toJson()));
          },
        );
      }

      test('$action cannot write a new account from a queued save', () async {
        final scheduler = RecordingReminderScheduler();
        final provider = TodoProvider()..scheduler = scheduler;
        addTearDown(provider.dispose);
        await provider.loadFromStorage();
        final started = Completer<void>();
        final release = Completer<void>();
        var writes = 0;
        provider.onLocalMutationPersisted = () async {
          if (++writes != 1) return;
          started.complete();
          await release.future;
        };
        final blocker = provider.addTodo(
          TodoItem(id: 'blocker', title: 'queue gate'),
        );
        await started.future;
        final pending = _mutate(provider, action);
        await Future<void>.delayed(Duration.zero);
        expect(
          provider.todos.firstWhere((t) => t.id == 'same-id').toJson(),
          isNot(_todo('old', action).toJson()),
        );
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        provider.resetLocalState();
        final next = _todo('next', action);
        final stored = _payload(next);
        SharedPreferences.setMockInitialValues({'todos': stored});
        release.complete();
        await blocker;
        await pending;
        expect(provider.todos, isEmpty);
        expect(
          (await SharedPreferences.getInstance()).getString('todos'),
          stored,
        );
        expect(writes, 1);
        expect(scheduler.todoSyncs, isEmpty);
        provider.onLocalMutationPersisted = null;
        await _mutate(provider, action);
        expect(provider.todos.single.title, 'next');
        expect(provider.todos.single.toJson(), isNot(next.toJson()));
      });

      test('$action cancels disposal during hydration', () async {
        final provider = _GatedLoadTodoProvider();
        final stored = (await SharedPreferences.getInstance()).getString(
          'todos',
        );
        final pending = _mutate(provider, action);
        await provider.started.future;
        provider.dispose();
        provider.release.complete();
        await pending;
        expect(provider.todos, isEmpty);
        expect(
          (await SharedPreferences.getInstance()).getString('todos'),
          stored,
        );
      });
    });
  }

  for (final action in [_Action.toggle, _Action.deleteLast]) {
    test('$action listener reset suppresses reminder work', () async {
      SharedPreferences.setMockInitialValues({
        'todos': _payload(_todo('old', action)),
      });
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
        SharedPreferences.setMockInitialValues({
          'todos': _payload(_todo('next', action)),
        });
      });
      await _mutate(provider, action);
      expect(switched, isTrue);
      expect(scheduler.todoSyncs, isEmpty);
    });
  }

  test('detail update queued save cannot overwrite a new account', () async {
    final old = _todo('old', _Action.add);
    SharedPreferences.setMockInitialValues({'todos': _payload(old)});
    final scheduler = RecordingReminderScheduler();
    final provider = TodoProvider()..scheduler = scheduler;
    addTearDown(provider.dispose);
    await provider.loadFromStorage();
    final started = Completer<void>();
    final release = Completer<void>();
    var writes = 0;
    provider.onLocalMutationPersisted = () async {
      if (++writes != 1) return;
      started.complete();
      await release.future;
    };
    final blocker = provider.addTodo(
      TodoItem(id: 'blocker', title: 'queue gate'),
    );
    await started.future;
    final pending = provider.updateTodo(
      old.id,
      old.copyWith(title: 'old draft'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(provider.todos.firstWhere((t) => t.id == old.id).title, 'old draft');
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    provider.resetLocalState();
    final next = _todo('next', _Action.add);
    final stored = _payload(next);
    SharedPreferences.setMockInitialValues({'todos': stored});
    release.complete();
    await blocker;
    expect(await pending, isFalse);
    expect(provider.todos, isEmpty);
    expect((await SharedPreferences.getInstance()).getString('todos'), stored);
    expect(writes, 1);
    expect(scheduler.todoSyncs, isEmpty);
    provider.onLocalMutationPersisted = null;
    expect(
      await provider.updateTodo(next.id, next.copyWith(title: 'new draft')),
      isTrue,
    );
    expect(provider.todos.single.title, 'new draft');
  });

  test('detail update listener reset suppresses reminder work', () async {
    final old = _todo('old', _Action.add);
    SharedPreferences.setMockInitialValues({'todos': _payload(old)});
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
      SharedPreferences.setMockInitialValues({
        'todos': _payload(_todo('next', _Action.add)),
      });
    });
    expect(
      await provider.updateTodo(old.id, old.copyWith(title: 'old draft')),
      isFalse,
    );
    expect(switched, isTrue);
    expect(scheduler.todoSyncs, isEmpty);
  });
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
