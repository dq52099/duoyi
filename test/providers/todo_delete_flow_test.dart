import 'dart:convert';

import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'deleteTodo removes persisted task, time footprint, tombstone and reminders',
    () async {
      final timeAudit = TimeAuditProvider();
      final scheduler = RecordingReminderScheduler();
      final provider = TodoProvider()
        ..timeAudit = timeAudit
        ..scheduler = scheduler;
      final todo = TodoItem(id: 'todo-delete-1', title: '删除闭环');
      final entry = TimeEntry(
        id: 'time-entry-delete-1',
        title: todo.title,
        startAt: DateTime(2026, 5, 31, 9),
        endAt: DateTime(2026, 5, 31, 9, 20),
        category: TimeEntryCategory.todo,
        source: TimeEntrySource.todo,
        sourceId: todo.id,
      );

      await provider.addTodo(todo);
      await timeAudit.add(entry);

      await provider.deleteTodo(todo.id);

      expect(provider.todos, isEmpty);
      expect(timeAudit.entries, isEmpty);
      expect(scheduler.todoSyncs.last, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('todos')!) as List<dynamic>, isEmpty);

      final deleted =
          jsonDecode(prefs.getString(CloudSyncProvider.deletedItemsStorageKey)!)
              as Map<String, dynamic>;
      expect(deleted['todos'] as Map<String, dynamic>, contains(todo.id));
      expect(
        deleted['time_entries'] as Map<String, dynamic>,
        contains(entry.id),
      );

      final reloaded = TodoProvider();
      await reloaded.loadFromStorage();
      expect(reloaded.todos, isEmpty);
    },
  );
}
