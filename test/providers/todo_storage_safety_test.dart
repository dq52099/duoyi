import 'dart:convert';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'TodoProvider skips corrupt persisted records and rewrites storage',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'todos': '[123, "bad-record"]',
      });

      final provider = TodoProvider();
      await provider.loadFromStorage();

      expect(provider.todos, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('todos'), '[]');
      expect(
        prefs.getKeys().where((key) => key.startsWith('todos_corrupt_backup_')),
        isNotEmpty,
      );
    },
  );

  test('TodoProvider hydrates storage before first write', () async {
    final existing = TodoItem(
      id: 'existing',
      title: '旧待办',
      date: DateTime(2026, 6, 5),
      createdAt: DateTime(2026, 6, 5, 8),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'todos': jsonEncode([existing.toJson()]),
    });

    final provider = TodoProvider();
    await provider.addTodo(
      TodoItem(
        id: 'quick',
        title: '快捷待办',
        date: DateTime(2026, 6, 5),
        createdAt: DateTime(2026, 6, 5, 9),
      ),
    );

    expect(
      provider.todos.map((todo) => todo.id),
      containsAll(['existing', 'quick']),
    );
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('todos')!) as List<dynamic>;
    expect(
      stored
          .cast<Map<dynamic, dynamic>>()
          .map((raw) => raw['id'] as String)
          .toSet(),
      {'existing', 'quick'},
    );
  });

  test(
    'forced loadFromStorage picks up cloud-synced todos and keeps them',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = TodoProvider();
      await provider.loadFromStorage();
      final local = TodoItem(
        id: 'local-1',
        title: '本地新建',
        date: DateTime(2026, 9, 30),
      );
      await provider.addTodo(local);

      // 模拟云同步回写：同步应答把另一台设备的任务合并进本地存储。
      final remote = TodoItem(
        id: 'remote-1',
        title: '云端任务',
        date: DateTime(2026, 9, 30),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'todos',
        jsonEncode([local.toJson(), remote.toJson()]),
      );

      await provider.loadFromStorage(force: true);

      expect(
        provider.todos.map((todo) => todo.id),
        containsAll(['local-1', 'remote-1']),
      );

      // 关键回归：强制重读之后再做本地写入，不得把同步结果整表覆盖掉。
      await provider.updateTodo(
        'local-1',
        provider.todos
            .firstWhere((todo) => todo.id == 'local-1')
            .copyWith(title: '本地编辑'),
      );
      final storedAfter =
          jsonDecode(prefs.getString('todos')!) as List<dynamic>;
      expect(
        storedAfter.cast<Map<dynamic, dynamic>>().map((raw) => raw['id']),
        containsAll(['local-1', 'remote-1']),
      );
    },
  );

  test(
    'loadFromStorage collapses duplicate ids keeping the newest record',
    () async {
      final older = TodoItem(
        id: 'dup',
        title: '旧版本',
        date: DateTime(2026, 9, 30),
        updatedAt: DateTime(2026, 9, 30, 8),
      );
      final newer = TodoItem(
        id: 'dup',
        title: '新版本',
        date: DateTime(2026, 9, 30),
        updatedAt: DateTime(2026, 9, 30, 9),
      );
      final other = TodoItem(
        id: 'other',
        title: '其他任务',
        date: DateTime(2026, 9, 30),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'todos': jsonEncode([older.toJson(), newer.toJson(), other.toJson()]),
      });

      final provider = TodoProvider();
      await provider.loadFromStorage();

      expect(provider.todos, hasLength(2));
      expect(
        provider.todos.firstWhere((todo) => todo.id == 'dup').title,
        '新版本',
      );
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString('todos')!) as List<dynamic>;
      expect(stored, hasLength(2));
    },
  );

  test(
    'forced loadFromStorage on rewrite-needed storage completes without deadlock',
    () async {
      // 回归：强制重读占用 _storageWriteQueue 尾部，损坏/重复存储触发的
      // 重写若再走队列会与自身互相等待（历史死锁），必须内联落盘。
      final older = TodoItem(
        id: 'dup',
        title: '旧版本',
        date: DateTime(2026, 9, 30),
        updatedAt: DateTime(2026, 9, 30, 8),
      );
      final newer = TodoItem(
        id: 'dup',
        title: '新版本',
        date: DateTime(2026, 9, 30),
        updatedAt: DateTime(2026, 9, 30, 9),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        // 合法数组内的重复 id + 坏记录：分别经 dedupe 与逐条容错触发重写。
        'todos': jsonEncode([older.toJson(), newer.toJson(), 123]),
      });

      final provider = TodoProvider();
      await provider.loadFromStorage(force: true);

      expect(provider.todos, hasLength(1));
      expect(
        provider.todos.single.id,
        'dup',
      );
      expect(provider.todos.single.title, '新版本');
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString('todos')!) as List<dynamic>;
      expect(stored, hasLength(1));
      expect(
        prefs
            .getKeys()
            .where((key) => key.startsWith('todos_corrupt_backup_')),
        isNotEmpty,
      );
      // 死锁回归的另一面：强制重读完成后，后续写入必须仍能正常排队落盘。
      await provider.addTodo(
        TodoItem(id: 'after', title: '重读后新增', date: DateTime(2026, 10, 1)),
      );
      final storedAfter =
          jsonDecode(prefs.getString('todos')!) as List<dynamic>;
      expect(
        storedAfter.cast<Map<dynamic, dynamic>>().map((raw) => raw['id']),
        containsAll(['dup', 'after']),
      );
    },
  );

  test(
    'large corrupt storage decodes off the main isolate and keeps valid records',
    () async {
      // 超过 _isolateDecodeMinChars 的大存储必须走后台解码路径，
      // 且逐条容错语义（跳过坏记录、备份、重写）保持一致。
      final valid = List.generate(900, (i) {
        return TodoItem(
          id: 'iso-$i',
          title: '隔离解码验证任务 $i',
          date: DateTime(2026, 9, 30),
        ).toJson();
      });
      final raw = jsonEncode([...valid, 'bad-record', 123]);
      expect(raw.length, greaterThan(60000));
      SharedPreferences.setMockInitialValues(<String, Object>{'todos': raw});

      final provider = TodoProvider();
      await provider.loadFromStorage();

      expect(provider.todos, hasLength(900));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((key) => key.startsWith('todos_corrupt_backup_')),
        isNotEmpty,
      );
      final rewritten = jsonDecode(prefs.getString('todos')!) as List<dynamic>;
      expect(rewritten, hasLength(900));
    },
  );
}
