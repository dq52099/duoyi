import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/core/completion_visibility_policy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';

/// 当日完成不销毁属性测试（Task 10.3）。
///
/// Feature: app-alignment-overhaul
/// Property 4 (P4): Today completion non-destructive
///   ∀ TodoItem t，当日执行 `toggleTodo(t.id)` 将 `isCompleted` false → true 后：
///   `t ∈ provider.todos` ∧ `shouldShowInToday(t, now) = true`
///                       ∧ `visualState(t) = completed`。
///
/// Validates: Requirements 3.1
///
/// 测试形态：
///   - 使用手写的 `Random(42)` 种子 + 固定排列生成"随机但可复现"的 N=50
///     次迭代；每次迭代随机选择当日 todo 数量、随机 pick 一条 toggle。
///   - forward / reverse 两个方向分别验证：
///       * forward：prev 未完成 → toggle 后应处于 completed 可视状态。
///       * reverse：prev 已完成 → toggle 后回到 normal/dueSoon/overdue 等非
///         completed 状态，completedAt 清空，且依旧留在 todos 中。
///   - shouldShowInToday 的日期边界（今天 / 昨天 / 明天）与 archived 旁路
///     单独成组。
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

  /// 迭代轮次（50，对齐 todo_subtask_aggregation_pbt_test.dart）。
  const int kIterations = 50;

  /// 构造一个"日期落在今日"的 TodoItem。
  ///
  /// - `date` 使用 `now` 的日（小时随机散布 0..23），确保 `shouldShowInToday`
  ///   的 dateOnly 比较落在同一天；
  /// - 故意不设置 `dueDate`，保持 `visualState` 在未完成时是 `normal`，避免
  ///   无意间命中 `dueSoon / overdue` 分支影响"反向"断言。
  TodoItem buildTodayTodo({
    required DateTime now,
    required int index,
    required Random rng,
  }) {
    final hour = rng.nextInt(24);
    final minute = rng.nextInt(60);
    final date = DateTime(now.year, now.month, now.day, hour, minute);
    return TodoItem(title: 'today-$index', date: date);
  }

  group('P4 - 当日完成不销毁', () {
    test(
      'forward: 对今日 todos 中随机一条 toggle 为完成后，'
      '仍在 provider.todos；shouldShowInToday=true；visualState=completed',
      () async {
        final rng = Random(kSeed);

        for (int iter = 0; iter < kIterations; iter++) {
          // 每轮独立 provider，避免跨迭代污染。
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final provider = TodoProvider();

          final now = DateTime.now();
          final n = 1 + rng.nextInt(8); // todos 数量 ∈ [1, 8]

          // 批量添加当日 todos。
          final ids = <String>[];
          for (int i = 0; i < n; i++) {
            final todo = buildTodayTodo(now: now, index: i, rng: rng);
            await provider.addTodo(todo);
            ids.add(todo.id);
          }

          // 随机挑一条（未完成）toggle。
          final pickIdx = rng.nextInt(n);
          final pickId = ids[pickIdx];

          final before = provider.todos.firstWhere((t) => t.id == pickId);
          assert(
            before.isCompleted == false,
            'precondition: newly-created todo should be !isCompleted',
          );

          final tBefore = DateTime.now();
          await provider.toggleTodo(pickId);
          final tAfter = DateTime.now();

          // P4 断言：物理上保留。
          expect(
            provider.todos.any((t) => t.id == pickId),
            isTrue,
            reason: 'iter=$iter n=$n — toggle 完成后 todo 应仍在 provider.todos',
          );

          final updated = provider.todos.firstWhere((t) => t.id == pickId);

          // P4 断言：isCompleted 与 completedAt。
          expect(
            updated.isCompleted,
            isTrue,
            reason: 'iter=$iter — toggle 后 isCompleted 应为 true',
          );
          expect(
            updated.completedAt,
            isNotNull,
            reason: 'iter=$iter — toggle 后 completedAt 应被写入',
          );

          // completedAt 落在 toggle 的时间窗内（宽松 ±2s 兜住系统抖动）。
          final ca = updated.completedAt!;
          expect(
            ca.isBefore(tBefore.subtract(const Duration(seconds: 1))),
            isFalse,
            reason: 'iter=$iter — completedAt=$ca 不应早于 $tBefore',
          );
          expect(
            ca.isAfter(tAfter.add(const Duration(seconds: 2))),
            isFalse,
            reason: 'iter=$iter — completedAt=$ca 不应迟于 $tAfter+2s',
          );

          // P4 断言：仍在今日视图可见。
          expect(
            CompletionVisibilityPolicy.shouldShowInToday(updated, now),
            isTrue,
            reason: 'iter=$iter n=$n — 当日完成的 todo 必须仍被 shouldShowInToday 认可',
          );

          // P4 断言：可视状态 = completed。
          expect(
            CompletionVisibilityPolicy.visualState(updated, now: now),
            TodoVisualState.completed,
            reason: 'iter=$iter — toggle 后 visualState 必须为 completed',
          );
        }
      },
    );

    test('reverse: 对已完成 todo 再次 toggle 后 '
        '回到非 completed 可视状态；completedAt=null；仍在 provider.todos 且可见', () async {
      final rng = Random(kSeed);

      for (int iter = 0; iter < kIterations; iter++) {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final provider = TodoProvider();

        final now = DateTime.now();
        final n = 1 + rng.nextInt(8);

        final ids = <String>[];
        for (int i = 0; i < n; i++) {
          final todo = buildTodayTodo(now: now, index: i, rng: rng);
          await provider.addTodo(todo);
          ids.add(todo.id);
        }

        final pickIdx = rng.nextInt(n);
        final pickId = ids[pickIdx];

        // 先完成，再 un-complete。
        await provider.toggleTodo(pickId);
        final completed = provider.todos.firstWhere((t) => t.id == pickId);
        assert(completed.isCompleted);
        assert(completed.completedAt != null);

        await provider.toggleTodo(pickId);

        // 仍在 provider.todos 中（绝不物理删除）。
        expect(
          provider.todos.any((t) => t.id == pickId),
          isTrue,
          reason: 'iter=$iter — un-complete 不应物理删除 todo',
        );

        final after = provider.todos.firstWhere((t) => t.id == pickId);
        expect(
          after.isCompleted,
          isFalse,
          reason: 'iter=$iter — un-complete 后 isCompleted 应为 false',
        );
        expect(
          after.completedAt,
          isNull,
          reason: 'iter=$iter — un-complete 后 completedAt 应被清空',
        );

        // visualState 离开 completed 档位。
        final vs = CompletionVisibilityPolicy.visualState(after, now: now);
        expect(
          vs == TodoVisualState.completed,
          isFalse,
          reason:
              'iter=$iter — un-complete 后 visualState 不应再是 completed '
              '(actual=$vs)',
        );
        // buildTodayTodo 不设置 dueDate，因此此时必定是 normal。
        expect(
          vs,
          TodoVisualState.normal,
          reason: 'iter=$iter — 未设置 dueDate 的当日 todo 应为 normal',
        );

        // 仍然今日可见。
        expect(
          CompletionVisibilityPolicy.shouldShowInToday(after, now),
          isTrue,
          reason: 'iter=$iter — un-complete 后仍应在今日视图可见',
        );
      }
    });
  });

  group('shouldShowInToday - 日期边界', () {
    test('明日日期的 todo → shouldShowInToday = false；'
        '昨日日期的 todo → shouldShowInToday = false', () {
      final rng = Random(kSeed);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (int iter = 0; iter < kIterations; iter++) {
        // 随机向前/向后偏移 1..7 天。
        final offsetDays = 1 + rng.nextInt(7);
        final hour = rng.nextInt(24);
        final minute = rng.nextInt(60);

        final tomorrow = today.add(Duration(days: offsetDays));
        final tomorrowTodo = TodoItem(
          title: 'tomorrow-$iter',
          date: DateTime(
            tomorrow.year,
            tomorrow.month,
            tomorrow.day,
            hour,
            minute,
          ),
        );
        expect(
          CompletionVisibilityPolicy.shouldShowInToday(tomorrowTodo, now),
          isFalse,
          reason: 'iter=$iter offset=+$offsetDays — 未来日期不应出现在今日视图',
        );

        final yesterday = today.subtract(Duration(days: offsetDays));
        final yesterdayTodo = TodoItem(
          title: 'yesterday-$iter',
          date: DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            hour,
            minute,
          ),
        );
        expect(
          CompletionVisibilityPolicy.shouldShowInToday(yesterdayTodo, now),
          isFalse,
          reason: 'iter=$iter offset=-$offsetDays — 过去日期不应出现在今日视图',
        );
      }
    });
  });

  group('shouldShowInToday - archived 旁路', () {
    test('isArchivedAfterRollover=true 的 todo → shouldShowInToday = false '
        '（不论 date 是否在今日）', () {
      final rng = Random(kSeed);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (int iter = 0; iter < kIterations; iter++) {
        // 一半测试样本落在今日，一半落在过去 1..30 天，确保 archived 短路
        // 在所有 date 情况下都生效。
        final useToday = rng.nextBool();
        final hour = rng.nextInt(24);
        final minute = rng.nextInt(60);

        late DateTime d;
        if (useToday) {
          d = DateTime(today.year, today.month, today.day, hour, minute);
        } else {
          final pastOffset = 1 + rng.nextInt(30);
          final past = today.subtract(Duration(days: pastOffset));
          d = DateTime(past.year, past.month, past.day, hour, minute);
        }

        final archived = TodoItem(
          title: 'archived-$iter',
          date: d,
          isCompleted: true,
          completedAt: now.subtract(const Duration(days: 1)),
          isArchivedAfterRollover: true,
        );

        expect(
          CompletionVisibilityPolicy.shouldShowInToday(archived, now),
          isFalse,
          reason: 'iter=$iter useToday=$useToday — archived 的 todo 应短路为不可见',
        );
      }
    });
  });
}
