import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';

/// 顺延算法属性测试（Task 8.2）。
///
/// Feature: app-alignment-overhaul
/// Property 12 (P12): ∀ overdue todo，postponeOverdue 之后
///                    dueDate ≥ today 00:00 ∧ hour/minute 不变。
/// Property 13 (P13): postponeOverdue 幂等 —— 连续调用两次，除
///                    postponeHistory 追加一条外，dueDate 保持不变。
///
/// Validates: Requirements 2.10, 2.11
///
/// 测试形态：
///   - 使用 `Random(42)` 种子 + ~50 次迭代生成"随机但可复现"的 dueDate 组合；
///   - 通过 `provider.todos` 观察 `postponeOverdue` 的副作用；
///   - 依赖 SharedPreferences，由 `setUp` 注入内存 mock。
void main() {
  // TodoProvider._saveToStorage 会访问 SharedPreferences，
  // 必须先初始化 Widgets binding + 注入 mock。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// 固定种子，保证"随机"测试在 CI / 本地完全可复现。
  const int kSeed = 42;

  /// 迭代轮次。
  const int kIterations = 50;

  /// "今天 00:00"基准。所有测试都用同一个 today，避免跨越午夜带来抖动。
  final DateTime today = DateTime(2025, 6, 15);
  final DateTime todayMidnight =
      DateTime(today.year, today.month, today.day);

  /// 构造一个过期 TodoItem：dueDate 在 today 之前的 [1, 5] 天，
  /// hour ∈ [0, 23]，minute ∈ [0, 59]。
  TodoItem buildOverdue({
    required DateTime today,
    required Random rng,
    required int title,
  }) {
    final daysBefore = rng.nextInt(5) + 1; // 1..5
    final hour = rng.nextInt(24); // 0..23
    final minute = rng.nextInt(60); // 0..59
    final base = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: daysBefore));
    final due = DateTime(base.year, base.month, base.day, hour, minute);
    return TodoItem(title: 'overdue-$title', dueDate: due);
  }

  /// 构造一个未过期 TodoItem：dueDate 严格晚于 today 00:00。
  /// 选择范围：today + [0, 5] 天，若是当天则 hour ≥ 1 保证 > todayMidnight。
  TodoItem buildFuture({
    required DateTime today,
    required Random rng,
    required int title,
  }) {
    final daysAfter = rng.nextInt(6); // 0..5
    final base = DateTime(today.year, today.month, today.day)
        .add(Duration(days: daysAfter));
    final hour = daysAfter == 0
        ? 1 + rng.nextInt(23) // today：至少 01:00，确保 >= 00:00
        : rng.nextInt(24);
    final minute = rng.nextInt(60);
    final due = DateTime(base.year, base.month, base.day, hour, minute);
    return TodoItem(title: 'future-$title', dueDate: due);
  }

  /// 构造一个已完成的过期 TodoItem：isCompleted=true 且 dueDate < today。
  TodoItem buildCompletedPast({
    required DateTime today,
    required Random rng,
    required int title,
  }) {
    final daysBefore = rng.nextInt(5) + 1;
    final base = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: daysBefore));
    final due = DateTime(
      base.year,
      base.month,
      base.day,
      rng.nextInt(24),
      rng.nextInt(60),
    );
    return TodoItem(
      title: 'done-past-$title',
      dueDate: due,
      isCompleted: true,
      completedAt: due,
    );
  }

  /// 构造一个没有 dueDate 的 TodoItem。
  TodoItem buildNoDue({required int title}) =>
      TodoItem(title: 'no-due-$title');

  group('P12 - postponeOverdue monotonicity', () {
    test(
      '∀ overdue todo，顺延后 dueDate ≥ today 00:00 且 hour/minute 保持不变',
      () async {
        final rng = Random(kSeed);
        for (int iter = 0; iter < kIterations; iter++) {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final provider = TodoProvider();

          // 1..8 个 overdue todos
          final n = 1 + rng.nextInt(8);
          final originals = <String, DateTime>{}; // id → 原 dueDate
          for (int i = 0; i < n; i++) {
            final t = buildOverdue(today: today, rng: rng, title: i);
            originals[t.id] = t.dueDate!;
            await provider.addTodo(t);
          }

          await provider.postponeOverdue(today);

          for (final entry in originals.entries) {
            final t = provider.todos.firstWhere((x) => x.id == entry.key);
            final prev = entry.value;
            expect(
              t.dueDate,
              isNotNull,
              reason: 'iter=$iter id=${t.id} — dueDate 不应为 null',
            );
            final due = t.dueDate!;
            // dueDate ≥ today 00:00
            expect(
              due.isBefore(todayMidnight),
              isFalse,
              reason: 'iter=$iter — 顺延后 dueDate=$due 应 ≥ $todayMidnight',
            );
            // hour / minute 保持不变
            expect(
              due.hour,
              prev.hour,
              reason: 'iter=$iter — hour 必须与原 dueDate 一致',
            );
            expect(
              due.minute,
              prev.minute,
              reason: 'iter=$iter — minute 必须与原 dueDate 一致',
            );
            // 顺延必须落在今日（而不是随便某个未来日）
            expect(due.year, todayMidnight.year);
            expect(due.month, todayMidnight.month);
            expect(due.day, todayMidnight.day);
            // 追加了一条 auto_daily_rollover 记录
            expect(
              t.postponeHistory.length,
              1,
              reason: 'iter=$iter — 首次顺延应追加恰好一条 PostponeRecord',
            );
            expect(t.postponeHistory.first.reason, 'auto_daily_rollover');
            expect(t.postponeHistory.first.from, prev);
            expect(t.postponeHistory.first.to, due);
          }
        }
      },
    );
  });

  group('P12 - non-overdue / completed / null dueDate 不受影响', () {
    test(
      'future dueDate：dueDate 原样不变，postponeHistory 保持为空',
      () async {
        final rng = Random(kSeed);
        for (int iter = 0; iter < kIterations; iter++) {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final provider = TodoProvider();

          final n = 1 + rng.nextInt(8);
          final originals = <String, DateTime>{};
          for (int i = 0; i < n; i++) {
            final t = buildFuture(today: today, rng: rng, title: i);
            originals[t.id] = t.dueDate!;
            await provider.addTodo(t);
          }

          await provider.postponeOverdue(today);

          for (final entry in originals.entries) {
            final t = provider.todos.firstWhere((x) => x.id == entry.key);
            expect(
              t.dueDate,
              entry.value,
              reason: 'iter=$iter id=${t.id} — future todo dueDate 不应改变',
            );
            expect(
              t.postponeHistory,
              isEmpty,
              reason: 'iter=$iter — 未过期 todo 不应追加 PostponeRecord',
            );
          }
        }
      },
    );

    test(
      'isCompleted=true 即使 dueDate < today：dueDate 原样不变',
      () async {
        final rng = Random(kSeed);
        for (int iter = 0; iter < kIterations; iter++) {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final provider = TodoProvider();

          final n = 1 + rng.nextInt(8);
          final originals = <String, DateTime>{};
          for (int i = 0; i < n; i++) {
            final t = buildCompletedPast(today: today, rng: rng, title: i);
            originals[t.id] = t.dueDate!;
            await provider.addTodo(t);
          }

          await provider.postponeOverdue(today);

          for (final entry in originals.entries) {
            final t = provider.todos.firstWhere((x) => x.id == entry.key);
            expect(
              t.dueDate,
              entry.value,
              reason: 'iter=$iter id=${t.id} — '
                  '已完成 todo 的 dueDate 不应被顺延',
            );
            expect(
              t.postponeHistory,
              isEmpty,
              reason: 'iter=$iter — 已完成 todo 不应追加 PostponeRecord',
            );
          }
        }
      },
    );

    test(
      'dueDate 为 null：不改动任何字段',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final provider = TodoProvider();

        for (int i = 0; i < 10; i++) {
          await provider.addTodo(buildNoDue(title: i));
        }

        await provider.postponeOverdue(today);

        for (final t in provider.todos) {
          expect(t.dueDate, isNull);
          expect(t.postponeHistory, isEmpty);
        }
      },
    );
  });

  group('P13 - postponeOverdue idempotency', () {
    test(
      '连续两次 postponeOverdue：dueDate 不变，postponeHistory 不再增长',
      () async {
        final rng = Random(kSeed);
        for (int iter = 0; iter < kIterations; iter++) {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final provider = TodoProvider();

          final n = 1 + rng.nextInt(8);
          for (int i = 0; i < n; i++) {
            await provider.addTodo(
              buildOverdue(today: today, rng: rng, title: i),
            );
          }

          await provider.postponeOverdue(today);

          // 快照第一次调用之后的结果
          final firstRunDue = <String, DateTime>{
            for (final t in provider.todos) t.id: t.dueDate!,
          };
          final firstRunHistLen = <String, int>{
            for (final t in provider.todos) t.id: t.postponeHistory.length,
          };

          await provider.postponeOverdue(today);

          for (final t in provider.todos) {
            expect(
              t.dueDate,
              firstRunDue[t.id],
              reason: 'iter=$iter id=${t.id} — '
                  '第二次调用 dueDate 必须与第一次调用后相同',
            );
            expect(
              t.postponeHistory.length,
              firstRunHistLen[t.id],
              reason: 'iter=$iter id=${t.id} — '
                  '第二次调用不应追加新的 PostponeRecord',
            );
          }
        }
      },
    );

    test(
      'mixed todos（overdue + future + completed + null）：二次调用结果一致',
      () async {
        final rng = Random(kSeed);
        for (int iter = 0; iter < kIterations; iter++) {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final provider = TodoProvider();

          // 每种至少 1 个
          final overdueCount = 1 + rng.nextInt(4);
          final futureCount = 1 + rng.nextInt(4);
          final completedCount = 1 + rng.nextInt(4);
          final nullCount = 1 + rng.nextInt(4);

          for (int i = 0; i < overdueCount; i++) {
            await provider.addTodo(
              buildOverdue(today: today, rng: rng, title: i),
            );
          }
          for (int i = 0; i < futureCount; i++) {
            await provider.addTodo(
              buildFuture(today: today, rng: rng, title: i),
            );
          }
          for (int i = 0; i < completedCount; i++) {
            await provider.addTodo(
              buildCompletedPast(today: today, rng: rng, title: i),
            );
          }
          for (int i = 0; i < nullCount; i++) {
            await provider.addTodo(buildNoDue(title: i));
          }

          await provider.postponeOverdue(today);

          // 快照：记录每个 todo 的 dueDate 与 postponeHistory 长度
          final firstRunDue = <String, DateTime?>{
            for (final t in provider.todos) t.id: t.dueDate,
          };
          final firstRunHistLen = <String, int>{
            for (final t in provider.todos) t.id: t.postponeHistory.length,
          };

          await provider.postponeOverdue(today);

          // 第二次调用必须是 no-op：所有 todos 的 dueDate 与历史长度都保持不变。
          expect(
            provider.todos.length,
            firstRunDue.length,
            reason: 'iter=$iter — todos 数量不应改变',
          );
          for (final t in provider.todos) {
            expect(
              t.dueDate,
              firstRunDue[t.id],
              reason: 'iter=$iter id=${t.id} — dueDate 应保持不变',
            );
            expect(
              t.postponeHistory.length,
              firstRunHistLen[t.id],
              reason: 'iter=$iter id=${t.id} — '
                  'postponeHistory 长度应保持不变',
            );
          }

          // 额外：之前本来就过期的 todos 历史长度必须恰好为 1。
          final overdueWithHistory = provider.todos
              .where((t) => t.postponeHistory.isNotEmpty)
              .toList();
          expect(
            overdueWithHistory.length,
            overdueCount,
            reason:
                'iter=$iter — 只有 overdue 那部分应产生 postponeHistory 记录',
          );
          for (final t in overdueWithHistory) {
            expect(t.postponeHistory.length, 1);
            expect(t.postponeHistory.first.reason, 'auto_daily_rollover');
          }
        }
      },
    );
  });
}
