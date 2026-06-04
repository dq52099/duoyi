import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';

/// 子任务聚合属性测试（Task 6.2）。
///
/// Feature: app-alignment-overhaul
/// Property 6 (P6): All subtasks done ⇔ subtaskProgress = 1.0
/// Property 7 (P7): autoToggleByChildren=true → parent auto-completes iff
///                  all subtasks done（含反向：撤销任一子任务父任务回到未完成）
///
/// Validates: Requirements 2.6, 2.7, 2.8, 2.9
///
/// 测试形态：
///   - 使用手写的 `Random(42)` 种子 + 固定排列生成"随机但可复现"的 N=50
///     次迭代；每次迭代随机选择子任务数量、随机排列勾选顺序。
///   - 模型层（TodoItem.subtaskProgress）与 Provider 层
///     （TodoProvider.toggleSubtask/recomputeParent）各自独立断言。
///   - Provider 相关测试依赖 SharedPreferences，由 `setUp` 用
///     `SharedPreferences.setMockInitialValues({})` 注入内存 mock。
void main() {
  // TodoProvider._saveToStorage 会访问 SharedPreferences，
  // 必须先初始化 Widgets binding + 注入 mock。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// 固定种子，保证"随机"测试在 CI / 本地完全可复现。
  const int kSeed = 42;

  /// P6 / P7 迭代轮次（模型层）。
  const int kModelIterations = 50;

  /// P7 迭代轮次（Provider 层，涉及 SharedPreferences，保守一些）。
  const int kProviderIterations = 50;

  /// 构造一个带 [subtaskCount] 个子任务的 TodoItem。
  ///
  /// - 子任务标题为 `sub-{i}`；
  /// - 父任务默认 `autoToggleByChildren = true`，对 P7 反例测试可通过参数覆盖；
  /// - 其它字段使用最小有效值。
  TodoItem buildTodoWithSubtasks({
    required int subtaskCount,
    bool autoToggleByChildren = true,
    String? title,
  }) {
    final subtasks = List<Subtask>.generate(
      subtaskCount,
      (i) => Subtask(title: 'sub-$i', sortOrder: i),
    );
    return TodoItem(
      title: title ?? 'parent',
      subtasks: subtasks,
      autoToggleByChildren: autoToggleByChildren,
    );
  }

  /// 生成一个 [0, n) 的随机排列（Fisher–Yates, 用指定 rng）。
  List<int> shuffledIndices(int n, Random rng) {
    final list = List<int>.generate(n, (i) => i);
    for (int i = n - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }

  group('P6 (模型层) - subtaskProgress ↔ all subtasks completed', () {
    test('forward: 全部子任务 isCompleted=true ⟹ subtaskProgress = 1.0', () {
      final rng = Random(kSeed);
      for (int iter = 0; iter < kModelIterations; iter++) {
        final n = 1 + rng.nextInt(10); // subtasks count ∈ [1, 10]
        final todo = buildTodoWithSubtasks(subtaskCount: n);

        // 以随机顺序勾选全部子任务，避免只覆盖"顺序勾选"。
        for (final i in shuffledIndices(n, rng)) {
          todo.subtasks[i].isCompleted = true;
        }

        expect(
          todo.subtaskProgress,
          1.0,
          reason: 'iter=$iter n=$n — 全部子任务勾选后 subtaskProgress 应为 1.0',
        );
      }
    });

    test('backward: 任一子任务被撤回 ⟹ subtaskProgress < 1.0', () {
      final rng = Random(kSeed);
      for (int iter = 0; iter < kModelIterations; iter++) {
        final n = 1 + rng.nextInt(10);
        final todo = buildTodoWithSubtasks(subtaskCount: n);
        for (final s in todo.subtasks) {
          s.isCompleted = true;
        }
        assert(todo.subtaskProgress == 1.0);

        final undoIdx = rng.nextInt(n);
        todo.subtasks[undoIdx].isCompleted = false;

        expect(
          todo.subtaskProgress < 1.0,
          isTrue,
          reason:
              'iter=$iter n=$n 撤回 idx=$undoIdx — '
              'subtaskProgress=${todo.subtaskProgress} 应 <1.0',
        );
        // 同时再补充一个精确等式断言：done = n - 1。
        expect(todo.subtaskProgress, closeTo((n - 1) / n, 1e-12));
      }
    });
  });

  group('P6 formula - subtaskProgress == done / total', () {
    test('K/N 随机配置下 subtaskProgress = K/N', () {
      final rng = Random(kSeed);
      for (int iter = 0; iter < kModelIterations; iter++) {
        final n = 1 + rng.nextInt(10);
        final todo = buildTodoWithSubtasks(subtaskCount: n);

        // 随机挑选 K ∈ [0, n] 个子任务标记完成。
        final k = rng.nextInt(n + 1);
        final picks = shuffledIndices(n, rng).take(k);
        for (final idx in picks) {
          todo.subtasks[idx].isCompleted = true;
        }

        final expected = k / n;
        expect(
          todo.subtaskProgress,
          closeTo(expected, 1e-12),
          reason:
              'iter=$iter n=$n k=$k — '
              'progress=${todo.subtaskProgress}, 期望=$expected',
        );
      }
    });
  });

  group('P7 (Provider 层) - autoToggleByChildren=true 双向联动', () {
    test(
      'forward: 逐个勾选全部子任务 ⟹ 父任务 isCompleted=true & completedAt!=null',
      () async {
        final rng = Random(kSeed);
        final provider = TodoProvider();

        for (int iter = 0; iter < kProviderIterations; iter++) {
          final n = 1 + rng.nextInt(8); // 1..8
          final todo = buildTodoWithSubtasks(
            subtaskCount: n,
            title: 'forward-$iter',
          );
          await provider.addTodo(todo);

          // _notify() 会排序 _todos；始终通过 id 查找最新引用。
          final todoId = todo.id;

          // 以随机顺序依次 toggle 每个子任务。
          final order = shuffledIndices(n, rng);
          for (int step = 0; step < order.length; step++) {
            // 注意：每轮都要重新拿 parent 的快照，因为 toggleSubtask 会触发
            // recomputeParent，可能改变 isCompleted。
            final parentBefore = provider.todos.firstWhere(
              (t) => t.id == todoId,
            );
            final subId = parentBefore.subtasks[order[step]].id;

            final before = DateTime.now();
            await provider.toggleSubtask(todoId, subId);
            final after = DateTime.now();

            final parentNow = provider.todos.firstWhere((t) => t.id == todoId);
            final isLast = step == order.length - 1;
            if (isLast) {
              expect(
                parentNow.isCompleted,
                isTrue,
                reason: 'iter=$iter n=$n 最后一次勾选后父任务应 isCompleted=true',
              );
              expect(
                parentNow.completedAt,
                isNotNull,
                reason: 'iter=$iter n=$n — completedAt 应被写入',
              );
              // completedAt 应落在本次 toggle 的时间窗内（宽松一些，允许
              // 系统时钟抖动；toggle 后最多 2 秒以内）。
              final ca = parentNow.completedAt!;
              expect(
                ca.isBefore(before.subtract(const Duration(seconds: 1))),
                isFalse,
                reason: 'completedAt=$ca 应不早于 toggle 开始时间 $before',
              );
              expect(
                ca.isAfter(after.add(const Duration(seconds: 2))),
                isFalse,
                reason: 'completedAt=$ca 应不迟于 toggle 结束太久（now=$after）',
              );
            } else {
              // 中途：autoToggle 只在"全部完成"时把 parent 置 true。
              expect(
                parentNow.isCompleted,
                isFalse,
                reason: 'iter=$iter n=$n step=$step 中间步父任务不应过早完成',
              );
              expect(
                parentNow.completedAt,
                isNull,
                reason: 'iter=$iter step=$step 中间步父任务 completedAt 应为 null',
              );
            }
          }
        }
      },
    );

    test('reverse: 全部完成后撤回任一子任务 ⟹ 父任务回落 isCompleted=false & '
        'completedAt=null', () async {
      final rng = Random(kSeed);
      final provider = TodoProvider();

      for (int iter = 0; iter < kProviderIterations; iter++) {
        final n = 1 + rng.nextInt(8);
        final todo = buildTodoWithSubtasks(
          subtaskCount: n,
          title: 'reverse-$iter',
        );
        await provider.addTodo(todo);
        final todoId = todo.id;

        // 先把父任务推到 isCompleted=true 状态。
        final order = shuffledIndices(n, rng);
        for (final idx in order) {
          final parent = provider.todos.firstWhere((t) => t.id == todoId);
          await provider.toggleSubtask(todoId, parent.subtasks[idx].id);
        }

        final completed = provider.todos.firstWhere((t) => t.id == todoId);
        assert(completed.isCompleted, 'precondition: parent should be done');
        assert(completed.completedAt != null);

        // 反向：撤回随机一个子任务。
        final undoIdx = rng.nextInt(n);
        final undoSubId = completed.subtasks[undoIdx].id;
        await provider.toggleSubtask(todoId, undoSubId);

        final after = provider.todos.firstWhere((t) => t.id == todoId);
        expect(
          after.isCompleted,
          isFalse,
          reason:
              'iter=$iter n=$n 撤回 idx=$undoIdx — '
              'autoToggle=true 下父任务应回到未完成',
        );
        expect(
          after.completedAt,
          isNull,
          reason: 'iter=$iter — completedAt 应被清空',
        );
        // 不变式 P6：progress 也应严格 <1.0。
        expect(after.subtaskProgress < 1.0, isTrue);
      }
    });
  });

  group('autoToggleByChildren=false — 父任务与子任务解耦', () {
    test('autoToggle=false 下勾选全部子任务，父任务仍保持 isCompleted=false', () async {
      final rng = Random(kSeed);
      final provider = TodoProvider();

      for (int iter = 0; iter < kProviderIterations; iter++) {
        final n = 1 + rng.nextInt(8);
        final todo = buildTodoWithSubtasks(
          subtaskCount: n,
          autoToggleByChildren: false,
          title: 'manual-$iter',
        );
        await provider.addTodo(todo);
        final todoId = todo.id;

        for (final idx in shuffledIndices(n, rng)) {
          final parent = provider.todos.firstWhere((t) => t.id == todoId);
          await provider.toggleSubtask(todoId, parent.subtasks[idx].id);
        }

        final parent = provider.todos.firstWhere((t) => t.id == todoId);
        // 全部子任务确实勾选了。
        expect(parent.subtaskProgress, 1.0);
        // 但父任务完成态不受驱动。
        expect(
          parent.isCompleted,
          isFalse,
          reason: 'iter=$iter n=$n — autoToggle=false 下父任务不应被子任务自动置完成',
        );
        expect(
          parent.completedAt,
          isNull,
          reason: 'iter=$iter — 未完成时 completedAt 必须为 null',
        );
      }
    });
  });
}
