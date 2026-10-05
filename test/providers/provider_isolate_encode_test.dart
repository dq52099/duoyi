import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';

/// 阈值与各 provider 内部的 `_isolateEncodeMinItems` 对齐（500），
/// 确保测试数据量越过后走 compute 分支。
const int _isolateThreshold = 500;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('PomodoroSession 有界增长', () {
    test('注入 505 条会话后裁剪最旧记录并持久化一致', () async {
      final provider = PomodoroProvider();
      final base = DateTime(2026, 1, 1, 8);
      await provider.debugAddSessionsForTest([
        for (var i = 0; i < _isolateThreshold + 5; i++)
          PomodoroSession(
            id: 's$i',
            startTime: base.add(Duration(minutes: 30 * i)),
            endTime: base.add(Duration(minutes: 30 * i + 25)),
            durationSeconds: 25 * 60,
            type: PomodoroType.focus,
          ),
      ]);

      expect(provider.sessions.length, _isolateThreshold);
      expect(provider.sessions.first.id, 's5', reason: '最旧的 5 条应被裁剪');
      expect(provider.sessions.last.id, 's${_isolateThreshold + 4}');

      // 持久化与内存一致（505 条已越过 isolate 编码阈值，走 compute 分支）。
      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString('pomodoro_sessions')!) as List<dynamic>;
      expect(stored, hasLength(_isolateThreshold));
      expect((stored.first as Map<String, dynamic>)['id'], 's5');
    });
  });

  group('isolate 编码路径行为等价', () {
    test('habit：500 条导入后持久化 JSON 与条数一致', () async {
      final provider = HabitProvider();
      final habits = [
        for (var i = 0; i < _isolateThreshold; i++)
          Habit(id: 'h$i', name: '习惯$i'),
      ];
      final summary = await provider.importHabits(habits);

      expect(summary.inserted, _isolateThreshold);
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString('habits')!) as List<dynamic>;
      expect(stored, hasLength(_isolateThreshold));
      expect((stored.first as Map<String, dynamic>)['name'], '习惯0');
    });

    test('time_audit：505 条导入后持久化 StringList 与条数一致', () async {
      final provider = TimeAuditProvider();
      final base = DateTime(2026, 1, 1, 9);
      final entries = [
        for (var i = 0; i < _isolateThreshold + 5; i++)
          TimeEntry(
            title: '条目$i',
            startAt: base.add(Duration(hours: i)),
            endAt: base.add(Duration(hours: i, minutes: 30)),
          ),
      ];
      await provider.importTimeEntries(entries);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(TimeAuditProvider.storageKey)!;
      expect(stored, hasLength(_isolateThreshold + 5));
      expect(
        (jsonDecode(stored.last) as Map<String, dynamic>)['title'],
        '条目${_isolateThreshold + 4}',
      );
    });

    test('note：505 条导入后持久化 StringList 与条数一致', () async {
      final provider = NoteProvider();
      final now = DateTime(2026, 1, 1, 10);
      final notes = [
        for (var i = 0; i < _isolateThreshold + 5; i++)
          NoteItem(
            id: 'n$i',
            content: '笔记内容$i',
            createdAt: now.add(Duration(minutes: i)),
            updatedAt: now.add(Duration(minutes: i)),
          ),
      ];
      await provider.importNotes(notes);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('duoyi_notes')!;
      expect(stored, hasLength(_isolateThreshold + 5));
      expect(
        (jsonDecode(stored.last) as Map<String, dynamic>)['content'],
        contains('笔记内容${_isolateThreshold + 4}'),
      );
    });

    test('todo_kanban 引用守卫：本测试文件与阈值说明存在', () {
      // 防止未来误删阈值说明（isolate 分支的触发条件文档化）。
      final source = File(
        'lib/providers/pomodoro_provider.dart',
      ).readAsStringSync();
      expect(source, contains('_isolateEncodeMinItems'));
      expect(source, contains('_maxPomodoroSessions'));
      expect(source, contains('compute('));
    });
  });
}
