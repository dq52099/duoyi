import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/recording_reminder_scheduler.dart';

TodoItem _todo(String id) => TodoItem(id: id, title: id);
String _payload(List<TodoItem> items) =>
    jsonEncode(items.map((item) => item.toJson()).toList());
String _backup(List<TodoItem> items) => jsonEncode({
  'app': 'duoyi',
  'schema': 1,
  'data': {
    'todos': {'type': 'string', 'value': _payload(items)},
  },
});

Future<List<String>> _storedIds() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('todos');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((item) => (item as Map)['id'] as String)
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TodoProvider provider;
  var disposed = false;

  setUp(() async {
    disposed = false;
    SharedPreferences.setMockInitialValues({
      'todos': _payload([_todo('old')]),
    });
    provider = TodoProvider()..scheduler = RecordingReminderScheduler();
    await provider.loadFromStorage();
  });
  tearDown(() async {
    if (!disposed) provider.dispose();
    await AccountPreferenceWrites.drain();
  });

  test(
    'restore refreshes an already loaded provider before next edit',
    () async {
      expect(
        await provider.runExternalStorageUpdate(
          () => BackupService.importAll(_backup([_todo('restored')])),
        ),
        1,
      );
      expect(provider.todos.single.id, 'restored');
      await provider.addTodo(_todo('next'));
      expect(await _storedIds(), ['restored', 'next']);
    },
  );

  test('wipe clears cache before the next write', () async {
    await provider.runExternalStorageUpdate(BackupService.wipeAll);
    expect(provider.todos, isEmpty);
    expect(await _storedIds(), isEmpty);
    await provider.addTodo(_todo('next'));
    expect(await _storedIds(), ['next']);
  });

  test('older queued writes drain before backup changes storage', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var writes = 0;
    provider.onLocalMutationPersisted = () async {
      if (++writes != 1) return;
      started.complete();
      await release.future;
    };
    final blocker = provider.addTodo(_todo('blocker'));
    await started.future;
    final old = provider.todos.firstWhere((item) => item.id == 'old');
    final update = provider.updateTodo('old', old.copyWith(title: 'draft'));
    await Future<void>.delayed(Duration.zero);
    var externalStarted = false;
    final restore = provider.runExternalStorageUpdate(() async {
      externalStarted = true;
      expect(await _storedIds(), ['old', 'blocker']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('todos'), contains('draft'));
      return BackupService.importAll(_backup([_todo('restored')]));
    });
    await Future<void>.delayed(Duration.zero);
    expect(externalStarted, isFalse);
    release.complete();
    await blocker;
    await update;
    await restore;
    expect(provider.todos.single.id, 'restored');
    expect(await _storedIds(), ['restored']);
  });

  test(
    'a new mutation waits for restore and edits the restored list',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final restore = provider.runExternalStorageUpdate(() async {
        started.complete();
        await release.future;
        return BackupService.importAll(_backup([_todo('restored')]));
      });
      await started.future;
      var completed = false;
      final add = provider.addTodo(_todo('next')).then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(await _storedIds(), ['old']);
      release.complete();
      await restore;
      await add;
      expect(
        provider.todos.map((item) => item.id),
        unorderedEquals(['restored', 'next']),
      );
      expect(await _storedIds(), ['restored', 'next']);
    },
  );

  test('new actions also survive the old-write draining interval', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var writes = 0;
    provider.onLocalMutationPersisted = () async {
      if (++writes != 1) return;
      started.complete();
      await release.future;
    };
    final blocker = provider.addTodo(_todo('blocker'));
    await started.future;
    final restore = provider.runExternalStorageUpdate(
      () => BackupService.importAll(_backup([_todo('old')])),
    );
    final add = provider.addTodo(_todo('next'));
    final subtask = provider.addSubtask('old', 'after restore');
    await Future<void>.delayed(Duration.zero);
    expect(
      provider.todos.map((item) => item.id),
      unorderedEquals(['old', 'blocker']),
    );
    release.complete();
    await blocker;
    await restore;
    await Future.wait([add, subtask]);
    expect(
      provider.todos.map((item) => item.id),
      unorderedEquals(['old', 'next']),
    );
    expect(
      provider.todos
          .firstWhere((item) => item.id == 'old')
          .subtasks
          .single
          .title,
      'after restore',
    );
    expect(await _storedIds(), ['old', 'next']);
  });

  test(
    'invalid backup preserves the original error and releases the gate',
    () async {
      await expectLater(
        provider.runExternalStorageUpdate(
          () => BackupService.importAll('{bad'),
        ),
        throwsFormatException,
      );
      expect(provider.todos.single.id, 'old');
      expect(await _storedIds(), ['old']);
      await provider.addTodo(_todo('next'));
      expect(await _storedIds(), ['old', 'next']);
      await provider.runExternalStorageUpdate(
        () => BackupService.importAll(_backup([_todo('later')])),
      );
      expect(provider.todos.single.id, 'later');
    },
  );

  test('a stale explicit account never starts the storage operation', () async {
    final origin = AccountLocalDataCleaner.accountDataGeneration;
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    var calls = 0;
    await expectLater(
      provider.runExternalStorageUpdate(
        () async => ++calls,
        expectedAccountDataGeneration: origin,
      ),
      throwsA(isA<AccountPreferenceWriteCanceled>()),
    );
    expect(calls, 0);
    expect(await _storedIds(), ['old']);
  });

  test(
    'account change while draining cancels before external storage writes',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      provider.onLocalMutationPersisted = () async {
        started.complete();
        await release.future;
      };
      final blocker = provider.addTodo(_todo('blocker'));
      await started.future;
      var calls = 0;
      final restore = provider.runExternalStorageUpdate(() async => ++calls);
      final canceled = expectLater(
        restore,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      provider.resetLocalState();
      SharedPreferences.setMockInitialValues({
        'todos': _payload([_todo('next')]),
      });
      release.complete();
      await blocker;
      await canceled;
      expect(calls, 0);
      expect(await _storedIds(), ['next']);
      provider.onLocalMutationPersisted = null;
      await provider.addTodo(_todo('new'));
      expect(await _storedIds(), ['next', 'new']);
    },
  );

  test('dispose while draining releases a canceled gate', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    provider.onLocalMutationPersisted = () async {
      started.complete();
      await release.future;
    };
    final blocker = provider.addTodo(_todo('blocker'));
    await started.future;
    var calls = 0;
    final canceled = expectLater(
      provider.runExternalStorageUpdate(() async => ++calls),
      throwsA(isA<AccountPreferenceWriteCanceled>()),
    );
    provider.dispose();
    disposed = true;
    release.complete();
    await blocker;
    await canceled;
    expect(calls, 0);
  });
}
