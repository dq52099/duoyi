import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/reminder_scheduler.dart'
    show ReminderReconciliationBatch;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../test_support/recording_reminder_scheduler.dart';

const _groupName = 'Roadmap';
const _targetWorkspace = 'workspace-target';

TodoItem _todo(
  String id, {
  String? title,
  String groupName = _groupName,
  String workspaceId = 'private',
  String? createdBy,
  String? updatedBy,
}) => TodoItem(
  id: id,
  title: title ?? '$id title',
  notes: '$id notes to preserve',
  date: DateTime(2026, 10, 15),
  listGroupId: 'roadmap-id',
  listGroupName: groupName,
  workspaceId: workspaceId,
  createdBy: createdBy,
  updatedBy: updatedBy,
  tags: ['keep-$id'],
);

String _payload(Iterable<TodoItem> todos) =>
    jsonEncode(todos.map((todo) => todo.toJson()).toList());

List<Map<String, dynamic>> _storedTodos(SharedPreferences prefs) =>
    (jsonDecode(prefs.getString('todos')!) as List)
        .cast<Map<String, dynamic>>();

TodoItem _liveTodo(TodoProvider provider, String id) =>
    provider.todos.singleWhere((todo) => todo.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _TodosStore store;
  late SharedPreferences prefs;
  final providers = <TodoProvider>[];

  Future<void> seed(Iterable<TodoItem> todos) async {
    await prefs.setString('todos', _payload(todos));
    store.todoWrites = 0;
  }

  TodoProvider makeProvider({RecordingReminderScheduler? scheduler}) {
    final provider = TodoProvider();
    if (scheduler != null) provider.scheduler = scheduler;
    providers.add(provider);
    return provider;
  }

  _GatedLoadTodoProvider gatedLoadProvider({
    RecordingReminderScheduler? scheduler,
  }) {
    final provider = _GatedLoadTodoProvider();
    if (scheduler != null) provider.scheduler = scheduler;
    providers.add(provider);
    return provider;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = _TodosStore();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    await seed([
      _todo('same-id', createdBy: 'original-author', updatedBy: 'old-editor'),
    ]);
    providers.clear();
  });

  tearDown(() async {
    if (!store.releaseAck.isCompleted) store.releaseAck.complete();
    for (final provider in providers) {
      provider.dispose();
    }
    await AccountPreferenceWrites.drain();
  });

  test(
    'publishes audited group fields only after storage acknowledges',
    () async {
      final originals = [
        _todo('first', createdBy: 'original-author', updatedBy: 'old-editor'),
        _todo('second', updatedBy: 'second-editor'),
        _todo(
          'other-group',
          groupName: 'Personal',
          createdBy: 'other-author',
          updatedBy: 'other-editor',
        ),
      ];
      await seed(originals);
      final scheduler = RecordingReminderScheduler();
      final provider = makeProvider(scheduler: scheduler);
      await provider.loadFromStorage();
      var persisted = 0;
      var notifications = 0;
      provider.onLocalMutationPersisted = () => persisted++;
      provider.addListener(() => notifications++);

      store.holdNextAck = true;
      final pending = provider.updateListGroupWorkspace(
        _groupName,
        _targetWorkspace,
        userId: 'captured-auditor',
        expectedAccountDataGeneration:
            AccountLocalDataCleaner.accountDataGeneration,
      );
      await store.ackStarted.future;

      expect(_liveTodo(provider, 'first').workspaceId, 'private');
      expect(_liveTodo(provider, 'second').workspaceId, 'private');
      expect(persisted, 0);
      expect(notifications, 0);
      expect(scheduler.todoSyncs, isEmpty);

      store.releaseAck.complete();
      expect(await pending, isTrue);

      final first = _liveTodo(provider, 'first');
      final second = _liveTodo(provider, 'second');
      final untouched = _liveTodo(provider, 'other-group');
      expect(first.workspaceId, _targetWorkspace);
      expect(first.createdBy, 'original-author');
      expect(first.updatedBy, 'captured-auditor');
      expect(first.notes, originals[0].notes);
      expect(first.tags, originals[0].tags);
      expect(second.workspaceId, _targetWorkspace);
      expect(second.createdBy, 'captured-auditor');
      expect(second.updatedBy, 'captured-auditor');
      expect(untouched.toJson(), originals[2].toJson());
      expect(_storedTodos(prefs).map((todo) => todo['updatedBy']), [
        'captured-auditor',
        'captured-auditor',
        'other-editor',
      ]);
      expect(persisted, 1);
      expect(notifications, 1);
      expect(scheduler.todoSyncs, [
        ['first', 'second', 'other-group'],
      ]);
    },
  );

  test(
    'returns false without writing for an empty group or unchanged fields',
    () async {
      await seed([
        _todo(
          'already-shared',
          workspaceId: _targetWorkspace,
          createdBy: 'owner',
          updatedBy: 'member',
        ),
      ]);
      final scheduler = RecordingReminderScheduler();
      final provider = makeProvider(scheduler: scheduler);
      await provider.loadFromStorage();
      var persisted = 0;
      var notifications = 0;
      provider.onLocalMutationPersisted = () => persisted++;
      provider.addListener(() => notifications++);
      final storedBefore = prefs.getString('todos');

      expect(
        await provider.updateListGroupWorkspace(
          'missing group',
          _targetWorkspace,
          userId: 'member',
        ),
        isFalse,
      );
      expect(
        await provider.updateListGroupWorkspace(
          _groupName,
          _targetWorkspace,
          userId: 'member',
        ),
        isFalse,
      );

      expect(store.todoWrites, 0);
      expect(prefs.getString('todos'), storedBefore);
      expect(persisted, 0);
      expect(notifications, 0);
      expect(scheduler.todoSyncs, isEmpty);
    },
  );

  test(
    'stale explicit entry is rejected before hydration and releases claims',
    () async {
      final provider = gatedLoadProvider(
        scheduler: RecordingReminderScheduler(),
      );
      final oldAccountGeneration =
          AccountLocalDataCleaner.accountDataGeneration;
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();

      expect(
        await provider.updateListGroupWorkspace(
          _groupName,
          _targetWorkspace,
          userId: 'old-session',
          expectedAccountDataGeneration: oldAccountGeneration,
        ),
        isFalse,
      );
      expect(provider.started.isCompleted, isFalse);
      expect(store.todoWrites, 0);

      final valid = provider.updateListGroupWorkspace(
        _groupName,
        _targetWorkspace,
        userId: 'current-session',
        expectedAccountDataGeneration:
            AccountLocalDataCleaner.accountDataGeneration,
      );
      await provider.started.future;
      provider.release.complete();
      expect(await valid, isTrue);
      expect(_liveTodo(provider, 'same-id').updatedBy, 'current-session');
    },
  );

  test(
    'captured group membership cannot bind to replacement items after hydration',
    () async {
      final source = makeProvider();
      await source.loadFromStorage();
      final expectedMembers = {
        for (final todo in source.todos.where(
          (todo) => todo.listGroupName == _groupName,
        ))
          todo.id: todo,
      };
      final scheduler = RecordingReminderScheduler();
      final provider = gatedLoadProvider(scheduler: scheduler);
      var persisted = 0;
      provider.onLocalMutationPersisted = () => persisted++;

      final pending = provider.updateListGroupWorkspace(
        _groupName,
        _targetWorkspace,
        userId: 'expired-session',
        expectedGroupMembers: expectedMembers,
      );
      await provider.started.future;
      final replacement = _todo(
        'same-id',
        title: 'replacement item with reused group name',
        createdBy: 'replacement-owner',
      );
      final replacementPayload = _payload([replacement]);
      await prefs.setString('todos', replacementPayload);
      store.todoWrites = 0;
      provider.release.complete();

      expect(await pending, isFalse);
      expect(provider.todos.single.toJson(), replacement.toJson());
      expect(prefs.getString('todos'), replacementPayload);
      expect(store.todoWrites, 0);
      expect(persisted, 0);
      expect(scheduler.todoSyncs, isEmpty);
    },
  );

  for (final switchAccount in [false, true]) {
    test(
      'hydration after reset cannot adopt replacement group data (account=$switchAccount)',
      () async {
        final scheduler = RecordingReminderScheduler();
        final provider = gatedLoadProvider(scheduler: scheduler);
        final originalAccountGeneration =
            AccountLocalDataCleaner.accountDataGeneration;
        var persisted = 0;
        provider.onLocalMutationPersisted = () => persisted++;

        final pending = provider.updateListGroupWorkspace(
          _groupName,
          _targetWorkspace,
          userId: 'expired-session',
          expectedAccountDataGeneration: originalAccountGeneration,
        );
        await provider.started.future;
        if (switchAccount) {
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        }
        provider.resetLocalState();
        final next = _todo(
          'same-id',
          title: 'replacement account item',
          createdBy: 'next-owner',
          updatedBy: 'next-editor',
        );
        final nextPayload = _payload([next]);
        await prefs.setString('todos', nextPayload);
        var hydrationNotifications = 0;
        provider.addListener(() => hydrationNotifications++);
        provider.release.complete();

        expect(await pending, isFalse);
        expect(provider.todos.single.toJson(), next.toJson());
        expect(prefs.getString('todos'), nextPayload);
        expect(hydrationNotifications, 1);
        expect(persisted, 0);
        expect(scheduler.todoSyncs, isEmpty);

        expect(
          await provider.updateListGroupWorkspace(
            _groupName,
            _targetWorkspace,
            userId: 'current-session',
            expectedAccountDataGeneration:
                AccountLocalDataCleaner.accountDataGeneration,
          ),
          isTrue,
        );
        expect(_liveTodo(provider, 'same-id').updatedBy, 'current-session');
      },
    );
  }

  test(
    'duplicate in-flight work returns false and released claims allow a later member',
    () async {
      final scheduler = RecordingReminderScheduler();
      final provider = makeProvider(scheduler: scheduler);
      await provider.loadFromStorage();
      store.holdNextAck = true;

      final first = provider.updateListGroupWorkspace(
        _groupName,
        _targetWorkspace,
        userId: 'member',
      );
      await store.ackStarted.future;
      expect(
        await provider.updateListGroupWorkspace(
          _groupName,
          _targetWorkspace,
          userId: 'member',
        ),
        isFalse,
      );
      store.releaseAck.complete();
      expect(await first, isTrue);
      expect(
        await provider.updateListGroupWorkspace(
          _groupName,
          _targetWorkspace,
          userId: 'member',
        ),
        isFalse,
      ); // acknowledged no-op, not a second success

      await provider.addTodo(_todo('late-member'));
      expect(
        await provider.updateListGroupWorkspace(
          _groupName,
          _targetWorkspace,
          userId: 'member',
        ),
        isTrue,
      );
      expect(_liveTodo(provider, 'late-member').workspaceId, _targetWorkspace);
    },
  );

  test('caller already revoked is refused before hydration', () async {
    final provider = gatedLoadProvider();
    expect(
      await provider.updateListGroupWorkspace(
        _groupName,
        _targetWorkspace,
        canWrite: () => false,
      ),
      isFalse,
    );
    expect(provider.started.isCompleted, isFalse);
    expect(store.todoWrites, 0);
  });

  test(
    'caller revocation while queued leaves only unrelated acknowledged write',
    () async {
      final scheduler = RecordingReminderScheduler();
      final provider = makeProvider(scheduler: scheduler);
      await provider.loadFromStorage();
      store.holdNextAck = true;
      final unrelated = provider.addTodo(
        _todo('queued-other', groupName: 'Other'),
      );
      await store.ackStarted.future;
      var authorized = true;
      var guardCalls = 0;
      final hydrated = Completer<void>();
      final pending = provider.updateListGroupWorkspace(
        _groupName,
        _targetWorkspace,
        canWrite: () {
          if (++guardCalls == 2) hydrated.complete();
          return authorized;
        },
      );
      await hydrated.future;
      authorized = false;
      store.releaseAck.complete();
      await unrelated;
      expect(await pending, isFalse);
      expect(_liveTodo(provider, 'same-id').workspaceId, 'private');
      expect(_liveTodo(provider, 'queued-other').workspaceId, 'private');
      expect(store.todoWrites, 1);
      expect(
        await provider.updateListGroupWorkspace(_groupName, _targetWorkspace),
        isTrue,
      );
    },
  );

  test(
    'rendered membership cannot adopt a replacement during hydration yield',
    () async {
      final provider = makeProvider(scheduler: RecordingReminderScheduler());
      await provider.loadFromStorage();
      final captured = {for (final item in provider.todos) item.id: item};
      final pending = provider.updateListGroupWorkspace(
        _groupName,
        _targetWorkspace,
        expectedGroupMembers: captured,
      );
      final replacement = _todo('same-id', title: 'reused group');
      provider.todos[0] = replacement;
      expect(await pending, isFalse);
      expect(provider.todos.single, same(replacement));
      expect(store.todoWrites, 0);
      expect(
        await provider.updateListGroupWorkspace(
          _groupName,
          _targetWorkspace,
          expectedGroupMembers: {replacement.id: replacement},
        ),
        isTrue,
      );
    },
  );

  test(
    'caller revocation during issued acknowledgement rolls back staged fields',
    () async {
      final scheduler = RecordingReminderScheduler();
      final provider = makeProvider(scheduler: scheduler);
      await provider.loadFromStorage();
      final before = prefs.getString('todos');
      final original = provider.todos.single.toJson();
      var authorized = true;
      var persisted = 0;
      var notifications = 0;
      provider.onLocalMutationPersisted = () => persisted++;
      provider.addListener(() => notifications++);
      store.holdNextAck = true;
      final pending = provider.updateListGroupWorkspace(
        _groupName,
        _targetWorkspace,
        canWrite: () => authorized,
      );
      await store.ackStarted.future;
      authorized = false;
      store.releaseAck.complete();
      expect(await pending, isFalse);
      expect(provider.todos.single.toJson(), original);
      expect(prefs.getString('todos'), before);
      expect(persisted, 0);
      expect(notifications, 0);
      expect(scheduler.todoSyncs, isEmpty);
    },
  );

  test(
    'caller-only revocation during reminder work suppresses late result state',
    () async {
      final scheduler = _GatedReminderScheduler();
      final provider = makeProvider(scheduler: scheduler);
      await provider.loadFromStorage();
      var authorized = true;
      final pending = provider.updateListGroupWorkspace(
        _groupName,
        _targetWorkspace,
        canWrite: () => authorized,
      );
      await scheduler.started.future;
      authorized = false;
      scheduler.release.complete();
      expect(await pending, isFalse);
      expect(provider.todos.single.workspaceId, _targetWorkspace);
      expect(provider.lastReminderSyncAttemptAt, isNull);
      expect(provider.lastReminderSyncSucceededAt, isNull);
    },
  );

  for (final failure in ['false', 'throw', 'writeThenThrow']) {
    test(
      'rejected $failure write preserves live fields and permits retry',
      () async {
        final original = _todo(
          'same-id',
          createdBy: 'original-author',
          updatedBy: 'old-editor',
        );
        await seed([original]);
        final scheduler = RecordingReminderScheduler();
        final provider = makeProvider(scheduler: scheduler);
        await provider.loadFromStorage();
        final storedBefore = prefs.getString('todos');
        var persisted = 0;
        var notifications = 0;
        provider.onLocalMutationPersisted = () => persisted++;
        provider.addListener(() => notifications++);
        store.failure = failure;

        await expectLater(
          provider.updateListGroupWorkspace(
            _groupName,
            _targetWorkspace,
            userId: 'attempted-member',
          ),
          throwsA(isA<StateError>()),
        );

        expect(_liveTodo(provider, 'same-id').toJson(), original.toJson());
        expect(prefs.getString('todos'), storedBefore);
        expect(persisted, 0);
        expect(notifications, 0);
        expect(scheduler.todoSyncs, isEmpty);

        expect(
          await provider.updateListGroupWorkspace(
            _groupName,
            _targetWorkspace,
            userId: 'retry-member',
          ),
          isTrue,
        );
        expect(_liveTodo(provider, 'same-id').updatedBy, 'retry-member');
      },
    );
  }

  test(
    'account boundary during issued platform acknowledgement rolls back before replacement data',
    () async {
      final scheduler = RecordingReminderScheduler();
      final provider = makeProvider(scheduler: scheduler);
      await provider.loadFromStorage();
      var persisted = 0;
      provider.onLocalMutationPersisted = () => persisted++;
      store.holdNextAck = true;

      final pending = provider.updateListGroupWorkspace(
        _groupName,
        _targetWorkspace,
        userId: 'departing-member',
      );
      await store.ackStarted.future;
      expect(_liveTodo(provider, 'same-id').workspaceId, 'private');

      final replacement = _todo(
        'same-id',
        title: 'replacement account item',
        createdBy: 'replacement-owner',
      );
      final replacementPayload = _payload([replacement]);
      final boundary = AccountLocalDataCleaner.runPreferenceBoundary(() async {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        await prefs.setString('todos', replacementPayload);
        await provider.loadFromStorage();
      });
      provider.resetLocalState();
      expect(AccountPreferenceWrites.isBoundaryActive, isTrue);

      store.releaseAck.complete();
      expect(await pending, isFalse);
      await boundary;

      expect(provider.todos.single.toJson(), replacement.toJson());
      expect(prefs.getString('todos'), replacementPayload);
      expect(persisted, 0);
      expect(scheduler.todoSyncs, isEmpty);
    },
  );

  test(
    'persisted callback invalidation suppresses notification, reminders, and success',
    () async {
      final scheduler = RecordingReminderScheduler();
      final provider = makeProvider(scheduler: scheduler);
      await provider.loadFromStorage();
      var authorized = true;
      var persisted = 0;
      var notifications = 0;
      provider.onLocalMutationPersisted = () {
        persisted++;
        authorized = false;
      };
      provider.addListener(() => notifications++);

      expect(
        await provider.updateListGroupWorkspace(
          _groupName,
          _targetWorkspace,
          userId: 'captured-member',
          canWrite: () => authorized,
        ),
        isFalse,
      );

      // Publication follows durable acknowledgement; later revocation cancels
      // follow-up effects, without rolling acknowledged data back in memory.
      expect(_liveTodo(provider, 'same-id').workspaceId, _targetWorkspace);
      expect(_liveTodo(provider, 'same-id').updatedBy, 'captured-member');
      expect(
        (_storedTodos(prefs).single)['workspaceId'],
        _targetWorkspace,
      ); // storage was already acknowledged before the callback revoked access
      expect(persisted, 1);
      expect(notifications, 0);
      expect(scheduler.todoSyncs, isEmpty);
    },
  );

  test(
    'synchronous listener invalidation prevents the reminder launch and success',
    () async {
      final scheduler = RecordingReminderScheduler();
      final provider = makeProvider(scheduler: scheduler);
      await provider.loadFromStorage();
      var invalidated = false;
      provider.addListener(() {
        if (invalidated) return;
        invalidated = true;
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        provider.resetLocalState();
      });

      expect(
        await provider.updateListGroupWorkspace(
          _groupName,
          _targetWorkspace,
          userId: 'captured-member',
        ),
        isFalse,
      );

      expect(invalidated, isTrue);
      expect(provider.todos, isEmpty);
      expect(_storedTodos(prefs).single['workspaceId'], _targetWorkspace);
      expect(scheduler.todoSyncs, isEmpty);
      expect(provider.lastReminderSyncAttemptAt, isNull);
    },
  );

  test(
    'invalidation during an issued reminder batch suppresses success',
    () async {
      final scheduler = _GatedReminderScheduler();
      addTearDown(() {
        if (!scheduler.release.isCompleted) scheduler.release.complete();
      });
      final provider = makeProvider(scheduler: scheduler);
      await provider.loadFromStorage();

      final pending = provider.updateListGroupWorkspace(
        _groupName,
        _targetWorkspace,
        userId: 'captured-member',
      );
      await scheduler.started.future;
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      provider.resetLocalState();
      scheduler.release.complete();

      expect(await pending, isFalse);
      expect(provider.todos, isEmpty);
      expect(scheduler.todoSyncs, [
        ['same-id'],
      ]);
      expect(provider.lastReminderSyncAttemptAt, isNull);
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

  @override
  void dispose() {
    if (!release.isCompleted) release.complete();
    super.dispose();
  }
}

class _GatedReminderScheduler extends RecordingReminderScheduler {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
    ReminderReconciliationBatch? batch,
  }) async {
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    if (!started.isCompleted) started.complete();
    await release.future;
  }
}

class _TodosStore extends InMemorySharedPreferencesStore {
  _TodosStore() : super.withData({});

  String? failure;
  bool holdNextAck = false;
  int todoWrites = 0;
  final ackStarted = Completer<void>();
  final releaseAck = Completer<void>();

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != 'flutter.todos') return super.setValue(type, key, value);
    todoWrites++;

    if (holdNextAck) {
      holdNextAck = false;
      final saved = await super.setValue(type, key, value);
      if (!ackStarted.isCompleted) ackStarted.complete();
      await releaseAck.future;
      return saved;
    }

    final nextFailure = failure;
    failure = null;
    if (nextFailure == 'false') return false;
    if (nextFailure == 'throw') {
      throw StateError('synthetic todos persistence failure');
    }
    if (nextFailure == 'writeThenThrow') {
      await super.setValue(type, key, value);
      throw StateError('synthetic todos acknowledgement failure');
    }
    return super.setValue(type, key, value);
  }
}
