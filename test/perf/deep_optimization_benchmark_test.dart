import 'dart:convert';
import 'dart:collection';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:duoyi/core/todo_filters.dart';
import 'package:duoyi/models/goal.dart' show ReminderPlan;
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 深度优化的性能基线：记录待办 Provider 持久化/排序、待办页派生数据
/// 计算、云同步负载哈希三条热路径在典型数据量下的耗时。
/// 只输出数据不做硬性时间断言（避免 CI 抖动误报），用于优化前后对比。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<TodoItem> buildTodos(int count, int seed) {
    final random = Random(seed);
    return List.generate(count, (i) {
      final day = DateTime(2026, 9, 1 + random.nextInt(28));
      return TodoItem(
        id: 'bench-$seed-$i',
        title: '性能基线任务 $i',
        date: day,
        dueDate: random.nextBool()
            ? day.add(Duration(hours: random.nextInt(12)))
            : null,
        quadrant: EisenhowerQuadrant.values[random.nextInt(4)],
        priority: TodoPriority.values[random.nextInt(5)],
        tags: ['标签${random.nextInt(5)}'],
        listGroupName: '清单${random.nextInt(6)}',
        reminderPlan: ReminderPlan(enabled: random.nextBool(), rules: const []),
      );
    });
  }

  Duration measure(String label, int iterations, void Function() body) {
    body();
    body();
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      body();
    }
    watch.stop();
    final perCall = watch.elapsedMilliseconds / iterations;
    // ignore: avoid_print
    print('BENCH[$label] ${perCall.toStringAsFixed(2)} ms/op');
    return watch.elapsed;
  }

  test('todo provider persistence cost', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 300 条（低于 isolate 编码阈值）代表典型重度用户的每次写入成本。
    final todos = buildTodos(300, 1);
    final provider = TodoProvider();
    await provider.loadFromStorage();
    final watch = Stopwatch()..start();
    for (final todo in todos) {
      await provider.addTodo(todo, waitForReminderSync: false);
    }
    watch.stop();
    // ignore: avoid_print
    print(
      'BENCH[provider.addTodo x300 (含持久化+排序)] '
      '${(watch.elapsedMilliseconds / todos.length).toStringAsFixed(3)} ms/op',
    );
  });

  test('todo provider large-list persistence cost (isolate encode)', () async {
    // 2000 条（超过 isolate 编码阈值）：墙钟时间含 isolate 往返，
    // 但主 isolate 不再被 JSON 编码阻塞（优化的目标是帧不卡顿）。
    // 逐条 addTodo 2000 次意味着每次写入都要 isolate 编码整个列表
    // （O(n²)，实测 ≈56s），会超出默认 30s 用例超时；这里先通过
    // 存储预置 2000 条进入稳态，再测量固定批次的逐条写入成本，
    // 与“2000 条列表上单条新增”的生产场景等价。
    final todos = buildTodos(2000, 11);
    final encoded = jsonEncode(todos.map((todo) => todo.toJson()).toList());
    SharedPreferences.setMockInitialValues(<String, Object>{
      'todos': encoded,
    });
    final provider = TodoProvider();
    await provider.loadFromStorage();
    expect(provider.todos, hasLength(todos.length));
    const measuredAdds = 100;
    final pending = buildTodos(measuredAdds, 12);
    final watch = Stopwatch()..start();
    for (final todo in pending) {
      await provider.addTodo(todo, waitForReminderSync: false);
    }
    watch.stop();
    // ignore: avoid_print
    print(
      'BENCH[provider.addTodo x$measuredAdds @2000 isolate-encode] '
      '${(watch.elapsedMilliseconds / measuredAdds).toStringAsFixed(3)} ms/op',
    );
  });

  test('todo provider startup decode cost (isolate decode)', () async {
    final todos = buildTodos(2000, 4);
    final encoded = jsonEncode(todos.map((todo) => todo.toJson()).toList());
    // ignore: avoid_print
    print('BENCH[startup storage size] ${encoded.length ~/ 1024} KB');
    var total = 0;
    const runs = 3;
    for (var run = 0; run < runs; run++) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'todos': encoded,
      });
      final provider = TodoProvider();
      final watch = Stopwatch()..start();
      await provider.loadFromStorage();
      watch.stop();
      if (run > 0) total += watch.elapsedMilliseconds;
      expect(provider.todos, hasLength(todos.length));
    }
    // ignore: avoid_print
    print(
      'BENCH[provider.loadFromStorage x${runs - 1} @2000 isolate-decode] '
      '${(total / (runs - 1)).toStringAsFixed(2)} ms/run',
    );
  });

  test('todo screen derived data cost (filter+groups+tags+overdue)', () {
    final todos = buildTodos(2000, 2);
    const filter = TodoFilterState<EisenhowerQuadrant, TodoPriority>();
    measure('screen derived block x100 @2000 todos', 100, () {
      final now = DateTime.now();
      final filtered = filterTodos(
        todos,
        filter,
        now: now,
        quadrantOf: (todo) => todo.quadrant,
        priorityOf: (todo) => todo.priority,
        tagsOf: (todo) => todo.tags,
        listGroupNameOf: (todo) => todo.listGroupName,
        dueDateOf: (todo) => todo.dueDate,
        isCompletedOf: (todo) => todo.isCompleted,
        isArchivedAfterRolloverOf: (todo) => todo.isArchivedAfterRollover,
      );
      groupTodosByQuadrant(
        filtered,
        quadrants: EisenhowerQuadrant.values,
        quadrantOf: (todo) => todo.quadrant,
      );
      groupTodosByList(filtered, (todo) => todo.listGroupName);
      final tags = <String>{};
      for (final todo in todos) {
        tags.addAll(todo.tags);
      }
      todos.where((todo) => todo.isOverdue).length;
    });
  });

  test('cloud sync payload hash cost (canonicalize+encode+sha256)', () {
    final todos = buildTodos(2000, 3);
    final payload = todos.map((todo) => todo.toJson()).toList();
    Object? canonicalize(Object? value) {
      if (value is Map) {
        final sorted = SplayTreeMap<String, Object?>();
        for (final entry in value.entries) {
          sorted[entry.key.toString()] = canonicalize(entry.value);
        }
        return sorted;
      }
      if (value is Iterable) {
        return value.map(canonicalize).toList(growable: false);
      }
      return value;
    }

    measure('sync canonicalize+sha256 x10 @2000 todos', 10, () {
      sha256.convert(utf8.encode(json.encode(canonicalize(payload))));
    });
  });

  test('cloud sync per-round main-thread decode cost', () {
    // 每轮同步此前要在主线程解码 1-3 次本地负载；该基准量化单次解码的
    // 主线程阻塞成本（现已随 _buildLocalSyncPayload 移入 isolate）。
    final todos = buildTodos(2000, 5);
    final encoded = jsonEncode(todos.map((todo) => todo.toJson()).toList());
    // ignore: avoid_print
    print('BENCH[sync storage size] ${encoded.length ~/ 1024} KB');
    measure('sync jsonDecode 1x @2000 todos', 20, () {
      jsonDecode(encoded);
    });
  });
}
