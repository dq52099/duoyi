import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/core/completion_visibility_policy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';

/// Rollover 不变式属性测试（Task 11.3）。
///
/// Feature: app-alignment-overhaul
///
/// Property 5 (P5): Rollover archives only past-day completions
///   ∀ 今日 00:00 触发的 `runDailyRollover(now)` 后：
///   `{t | t.isArchivedAfterRollover = true}` 与
///   `{t | t.isCompleted ∧ t.completedAt != null ∧ dateOnly(t.completedAt) < today}`
///   完全相等。
///
/// Property 19 (P19): Completed implies has completedAt
///   ∀ `t`：`t.isCompleted = true ⟹ t.completedAt ≠ null`。
///
/// Property 20 (P20): Archived implies completed
///   ∀ `t`：`t.isArchivedAfterRollover = true ⟹ t.isCompleted = true`。
///
/// Validates: Requirements 3.4, 3.5, 3.6
///
/// 测试形态：
///   - 使用固定种子 `Random(42)` + 50 次迭代，保证"随机"在 CI / 本地完全可复现。
///   - 每轮独立 `TodoProvider`，独立 SharedPreferences mock，避免污染。
///   - 生成器覆盖四种场景：
///       * `completedPast`    ：isCompleted=true，completedAt 落在今日之前 1..10 天。
///       * `completedToday`   ：isCompleted=true，completedAt 落在今日某时刻。
///       * `notCompleted`     ：isCompleted=false，completedAt=null。
///       * `completedNullAt`  ：isCompleted=true，completedAt=null（边界场景，
///                              按实现不归档）。
///   - P19 与幂等性测试使用"有效生成器"（剔除 `completedNullAt`），因为该边界
///     场景天然违反 P19；P5 与 P20 测试使用"完整生成器"以覆盖所有分支。
void main() {
  // `TodoProvider._saveToStorage` 会访问 SharedPreferences，
  // 必须先初始化 Widgets binding + 注入 mock。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// 固定种子。
  const int kSeed = 42;

  /// 迭代轮次（50，对齐 completion_visibility_pbt_test.dart）。
  const int kIterations = 50;

  /// 截断到"本地日"。
  DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 构造一条 Todo：`kind` 控制场景分支。
  ///
  /// - `completedPast`   ：`isCompleted=true`，`completedAt` 落在过去 1..10 天；
  ///                       `date` 保留在 `completedAt` 所在日便于后续断言可读。
  /// - `completedToday`  ：`isCompleted=true`，`completedAt` 落在今日随机时刻。
  /// - `notCompleted`    ：`isCompleted=false`，`completedAt=null`，`date` 在今日。
  /// - `completedNullAt` ：`isCompleted=true`，`completedAt=null`（边界场景，
  ///                       按实现**不**归档；违反 P19，仅用于 P5 / P20 测试）。
  TodoItem buildTodo({
    required DateTime now,
    required int index,
    required String kind,
    required Random rng,
  }) {
    final today = dateOnly(now);
    switch (kind) {
      case 'completedPast':
        final daysAgo = 1 + rng.nextInt(10);
        final h = rng.nextInt(24);
        final m = rng.nextInt(60);
        final completed = today
            .subtract(Duration(days: daysAgo))
            .add(Duration(hours: h, minutes: m));
        return TodoItem(
          title: 'past-$index',
          date: completed,
          isCompleted: true,
          completedAt: completed,
        );
      case 'completedToday':
        final h = rng.nextInt(24);
        final m = rng.nextInt(60);
        final completed =
            DateTime(today.year, today.month, today.day, h, m);
        return TodoItem(
          title: 'today-$index',
          date: completed,
          isCompleted: true,
          completedAt: completed,
        );
      case 'notCompleted':
        final h = rng.nextInt(24);
        return TodoItem(
          title: 'open-$index',
          date: DateTime(today.year, today.month, today.day, h),
          isCompleted: false,
        );
      case 'completedNullAt':
        return TodoItem(
          title: 'nullat-$index',
          date: today,
          isCompleted: true,
          // 故意留空，模拟历史遗留/异常数据。
          // ignore: avoid_redundant_argument_values
          completedAt: null,
        );
      default:
        throw ArgumentError('unknown kind: $kind');
    }
  }

  /// 批量播种 todos 到 provider。
  ///
  /// `allowNullCompletedAt = true` 时加入 `completedNullAt` 边界场景。
  Future<void> seedTodos(
    TodoProvider provider, {
    required DateTime now,
    required int n,
    required Random rng,
    required bool allowNullCompletedAt,
  }) async {
    final kinds = <String>[
      'completedPast',
      'completedToday',
      'notCompleted',
      if (allowNullCompletedAt) 'completedNullAt',
    ];
    for (int i = 0; i < n; i++) {
      final kind = kinds[rng.nextInt(kinds.length)];
      final t = buildTodo(now: now, index: i, kind: kind, rng: rng);
      await provider.addTodo(t);
    }
  }

  /// 过滤出预期被归档的 id 集合（P5 的 RHS）。
  Set<String> expectedArchivedIds(List<TodoItem> todos, DateTime today) {
    return todos
        .where((t) =>
            t.isCompleted &&
            t.completedAt != null &&
            dateOnly(t.completedAt!).isBefore(today))
        .map((t) => t.id)
        .toSet();
  }

  group('P5 - Rollover archives only past-day completions', () {
    test(
      '归档集合 = {t | isCompleted ∧ completedAt != null ∧ dateOnly(completedAt) < today}',
      () async {
        final rng = Random(kSeed);

        for (int iter = 0; iter < kIterations; iter++) {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final provider = TodoProvider();

          final now = DateTime.now();
          final today = dateOnly(now);
          final n = 1 + rng.nextInt(10); // todos 数量 ∈ [1, 10]

          await seedTodos(
            provider,
            now: now,
            n: n,
            rng: rng,
            allowNullCompletedAt: true,
          );

          // 归档前计算预期集合（rollover 不改变 isCompleted / completedAt）。
          final expected = expectedArchivedIds(provider.todos, today);

          await CompletionVisibilityPolicy.runDailyRollover(provider, now);

          final actual = provider.todos
              .where((t) => t.isArchivedAfterRollover)
              .map((t) => t.id)
              .toSet();

          expect(
            actual,
            equals(expected),
            reason: 'iter=$iter n=$n — 归档集合不等于规约集合\n'
                'expected=$expected\nactual=$actual',
          );
        }
      },
    );
  });

  group('P19 - Completed implies completedAt', () {
    test(
      'runDailyRollover 后，∀ t. isCompleted = true ⟹ completedAt != null',
      () async {
        final rng = Random(kSeed);

        for (int iter = 0; iter < kIterations; iter++) {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final provider = TodoProvider();

          final now = DateTime.now();
          final n = 1 + rng.nextInt(10);

          // 有效生成器：不注入 completedNullAt 边界场景。
          await seedTodos(
            provider,
            now: now,
            n: n,
            rng: rng,
            allowNullCompletedAt: false,
          );

          await CompletionVisibilityPolicy.runDailyRollover(provider, now);

          for (final t in provider.todos) {
            if (t.isCompleted) {
              expect(
                t.completedAt,
                isNotNull,
                reason: 'iter=$iter id=${t.id} — isCompleted=true 必须有 completedAt',
              );
            }
          }
        }
      },
    );
  });

  group('P20 - Archived implies completed', () {
    test(
      'runDailyRollover 后，∀ t. isArchivedAfterRollover = true ⟹ isCompleted = true',
      () async {
        final rng = Random(kSeed);

        for (int iter = 0; iter < kIterations; iter++) {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final provider = TodoProvider();

          final now = DateTime.now();
          final n = 1 + rng.nextInt(10);

          // 允许 completedNullAt 进入样本，验证实现在该边界下也不会产生
          // "archived 但 !isCompleted" 的异常状态。
          await seedTodos(
            provider,
            now: now,
            n: n,
            rng: rng,
            allowNullCompletedAt: true,
          );

          await CompletionVisibilityPolicy.runDailyRollover(provider, now);

          for (final t in provider.todos) {
            if (t.isArchivedAfterRollover) {
              expect(
                t.isCompleted,
                isTrue,
                reason:
                    'iter=$iter id=${t.id} — archived 的 todo 必须 isCompleted=true',
              );
            }
          }
        }
      },
    );
  });

  group('幂等性：二次 runDailyRollover 保持 P5 / P19 / P20', () {
    test(
      '二次调用不改变归档集合；三条不变式在两次之后仍然成立',
      () async {
        final rng = Random(kSeed);

        for (int iter = 0; iter < kIterations; iter++) {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final provider = TodoProvider();

          final now = DateTime.now();
          final today = dateOnly(now);
          final n = 1 + rng.nextInt(10);

          // 有效生成器：保证 P19 在播种阶段已成立，便于观察"二次调用"对
          // 已稳定集合的影响。
          await seedTodos(
            provider,
            now: now,
            n: n,
            rng: rng,
            allowNullCompletedAt: false,
          );

          // 第一次 rollover。
          await CompletionVisibilityPolicy.runDailyRollover(provider, now);
          final firstArchived = provider.todos
              .where((t) => t.isArchivedAfterRollover)
              .map((t) => t.id)
              .toSet();

          // 第二次 rollover：期望完全幂等（就归档集合而言）。
          await CompletionVisibilityPolicy.runDailyRollover(provider, now);
          final secondArchived = provider.todos
              .where((t) => t.isArchivedAfterRollover)
              .map((t) => t.id)
              .toSet();

          expect(
            secondArchived,
            equals(firstArchived),
            reason: 'iter=$iter — 二次 rollover 改变了归档集合',
          );

          // P5：归档集合仍等于规约集合。
          final expected = expectedArchivedIds(provider.todos, today);
          expect(
            secondArchived,
            equals(expected),
            reason: 'iter=$iter — 二次 rollover 后归档集合偏离规约',
          );

          // P19 / P20 在二次 rollover 后仍成立。
          for (final t in provider.todos) {
            if (t.isCompleted) {
              expect(
                t.completedAt,
                isNotNull,
                reason: 'P19 iter=$iter id=${t.id}',
              );
            }
            if (t.isArchivedAfterRollover) {
              expect(
                t.isCompleted,
                isTrue,
                reason: 'P20 iter=$iter id=${t.id}',
              );
            }
          }
        }
      },
    );
  });
}
