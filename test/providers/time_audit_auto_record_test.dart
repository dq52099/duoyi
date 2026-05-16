import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/goal.dart' show FocusLink;
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/time_audit_provider.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('TimeAuditProvider 自动记录', () {
    test('recordPomodoroSession 写入一条 focus 类别条目', () async {
      final provider = TimeAuditProvider();
      await provider.loadFromStorage();
      await provider.recordPomodoroSession(
        sessionId: 'sess1',
        title: '专注 25min',
        startAt: DateTime(2026, 5, 12, 9),
        endAt: DateTime(2026, 5, 12, 9, 25),
      );
      expect(provider.entries.length, 1);
      final entry = provider.entries.first;
      expect(entry.category, TimeEntryCategory.focus);
      expect(entry.source, TimeEntrySource.pomodoro);
      expect(entry.sourceId, 'sess1');
      expect(entry.durationSeconds, 1500);
    });

    test('相同 sessionId 重复调用不会创建重复条目', () async {
      final provider = TimeAuditProvider();
      await provider.loadFromStorage();
      await provider.recordPomodoroSession(
        sessionId: 'sess1',
        title: '专注',
        startAt: DateTime(2026, 5, 12, 9),
        endAt: DateTime(2026, 5, 12, 9, 25),
      );
      await provider.recordPomodoroSession(
        sessionId: 'sess1',
        title: '专注',
        startAt: DateTime(2026, 5, 12, 9),
        endAt: DateTime(2026, 5, 12, 9, 25),
      );
      expect(provider.entries.length, 1);
    });

    test('recordTodoCompletion 在带 focusLink 时长时写入', () async {
      final provider = TimeAuditProvider();
      await provider.loadFromStorage();
      final completedAt = DateTime(2026, 5, 12, 10, 30);
      final todo = TodoItem(
        id: 't1',
        title: '一个任务',
        date: DateTime(2026, 5, 12),
        createdAt: DateTime(2026, 5, 12, 8),
        focusLink: const FocusLink(enabled: true, focusSeconds: 1800),
        isCompleted: true,
        completedAt: completedAt,
      );
      await provider.recordTodoCompletion(todo);
      expect(provider.entries.length, 1);
      final entry = provider.entries.first;
      expect(entry.category, TimeEntryCategory.todo);
      expect(entry.source, TimeEntrySource.todo);
      expect(entry.sourceId, 't1');
    });

    test('removeTodoCompletion 撤销自动记录', () async {
      final provider = TimeAuditProvider();
      await provider.loadFromStorage();
      final completedAt = DateTime(2026, 5, 12, 10, 30);
      final todo = TodoItem(
        id: 't1',
        title: '一个任务',
        date: DateTime(2026, 5, 12),
        createdAt: DateTime(2026, 5, 12, 8),
        focusLink: const FocusLink(enabled: true, focusSeconds: 1800),
        isCompleted: true,
        completedAt: completedAt,
      );
      await provider.recordTodoCompletion(todo);
      expect(provider.entries.length, 1);
      await provider.removeTodoCompletion(todo);
      expect(provider.entries.length, 0);
    });
  });

  group('TimeAuditProvider 持久化', () {
    test('loadFromStorage 后修改可重新加载', () async {
      final provider = TimeAuditProvider();
      await provider.loadFromStorage();
      await provider.add(
        TimeEntry(
          id: 'e1',
          title: '手动记录',
          startAt: DateTime(2026, 5, 12, 14),
          endAt: DateTime(2026, 5, 12, 15),
          category: TimeEntryCategory.work,
          source: TimeEntrySource.manual,
        ),
      );
      final reload = TimeAuditProvider();
      await reload.loadFromStorage();
      expect(reload.entries.any((e) => e.id == 'e1'), isTrue);
    });
  });
}
