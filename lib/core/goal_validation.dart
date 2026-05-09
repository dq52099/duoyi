/// Pure-Dart validation helpers for [GoalItem] edit forms.
///
/// 这份文件**禁止**引入 `package:flutter/*` 依赖：所有校验都必须是纯函数，
/// 以便在普通 `test/` 单测中无需初始化 widget binding 即可执行。
///
/// UI 层（`GoalEditScreen`，由 Task 4.2 实现）可直接消费：
/// - [validateGoal] / [isGoalValid]：在点击"保存"时做整体校验。
/// - [validateRandomMinGapDaysInt] / [validateDailyTargetCountInt]：
///   可作为 `TextFormField.validator` 的字段级校验器（`String?` 语义）。
///
/// 具体规则对应 `requirements.md` Requirement 1 中的 1.6 / 1.7 / 1.8 / 1.10。
library;

import '../models/goal.dart';
import '../models/recurrence.dart';

/// 字段标识常量：用于在 UI 中按 `GoalValidationIssue.field` 反查到具体输入框。
///
/// 保持为 `const String` 而非枚举，便于直接当 Form field name / `FormBuilder`
/// key 使用，也避免 JSON 序列化时的转义问题。
class GoalValidationField {
  GoalValidationField._();

  static const String fixedWeekdays = 'fixedWeekdays';
  static const String fixedMonthDays = 'fixedMonthDays';
  static const String randomMinGapDays = 'randomMinGapDays';
  static const String randomMaxPerWeek = 'randomMaxPerWeek';
  static const String randomMaxPerMonth = 'randomMaxPerMonth';
  static const String dailyTargetCount = 'dailyTargetCount';
  static const String timeTargetSeconds = 'timeTargetSeconds';
  static const String hour = 'hour';
  static const String minute = 'minute';
}

/// 单条校验问题：
/// - [field]：触发该错误的字段标识（对应 [GoalValidationField]）。
/// - [message]：给用户看的中文提示（可直接展示在 SnackBar / FormField 下方）。
class GoalValidationIssue {
  final String field;
  final String message;

  const GoalValidationIssue(this.field, this.message);

  @override
  String toString() => 'GoalValidationIssue($field: $message)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoalValidationIssue &&
          other.field == field &&
          other.message == message;

  @override
  int get hashCode => Object.hash(field, message);
}

/// 对 [GoalItem] 做整体校验，返回所有违反规则的 [GoalValidationIssue]。
///
/// - 若返回空列表（`const <GoalValidationIssue>[]`），说明所有字段合法。
/// - 校验规则见文件头注释；规则尽量宽松：空值或"未启用"的模块不会报错。
List<GoalValidationIssue> validateGoal(GoalItem g) {
  final issues = <GoalValidationIssue>[];

  final scheduling = g.scheduling;
  final recurrence = g.recurrence;

  // --- scheduling.fixed + recurrence.weekly: fixedWeekdays ⊆ [0..6] ---
  if (scheduling.mode == SchedulingMode.fixed &&
      recurrence.frequency == RecurrenceFrequency.weekly) {
    final days = scheduling.fixedWeekdays;
    if (days != null && days.isNotEmpty) {
      if (days.any((d) => d < 0 || d > 6)) {
        issues.add(const GoalValidationIssue(
          GoalValidationField.fixedWeekdays,
          '固定星期只能在 0(周一)~6(周日) 范围内',
        ));
      } else if (days.toSet().length != days.length) {
        issues.add(const GoalValidationIssue(
          GoalValidationField.fixedWeekdays,
          '固定星期不能重复选择',
        ));
      }
    }
  }

  // --- scheduling.fixed + recurrence.monthly: fixedMonthDays ⊆ [1..31] ---
  if (scheduling.mode == SchedulingMode.fixed &&
      recurrence.frequency == RecurrenceFrequency.monthly) {
    final days = scheduling.fixedMonthDays;
    if (days != null && days.isNotEmpty) {
      if (days.any((d) => d < 1 || d > 31)) {
        issues.add(const GoalValidationIssue(
          GoalValidationField.fixedMonthDays,
          '固定日期只能在每月 1~31 号之间',
        ));
      } else if (days.toSet().length != days.length) {
        issues.add(const GoalValidationIssue(
          GoalValidationField.fixedMonthDays,
          '固定日期不能重复选择',
        ));
      }
    }
  }

  // --- scheduling.random: gap/ceiling 合法性 ---
  if (scheduling.mode == SchedulingMode.random) {
    final gap = scheduling.randomMinGapDays;
    if (gap != null && gap < 1) {
      issues.add(const GoalValidationIssue(
        GoalValidationField.randomMinGapDays,
        '随机模式下最小间隔天数需 ≥ 1',
      ));
    }
    final perWeek = scheduling.randomMaxPerWeek;
    if (perWeek != null && perWeek < 1) {
      issues.add(const GoalValidationIssue(
        GoalValidationField.randomMaxPerWeek,
        '每周最多派发次数需 ≥ 1',
      ));
    }
    final perMonth = scheduling.randomMaxPerMonth;
    if (perMonth != null && perMonth < 1) {
      issues.add(const GoalValidationIssue(
        GoalValidationField.randomMaxPerMonth,
        '每月最多派发次数需 ≥ 1',
      ));
    }
  }

  // --- 每日目标次数 ≥ 0（允许清零）---
  final dailyCount = g.dailyTargetCount;
  if (dailyCount != null && dailyCount < 0) {
    issues.add(const GoalValidationIssue(
      GoalValidationField.dailyTargetCount,
      '每日目标次数不能为负数',
    ));
  }

  // --- 目标时长（秒） ≥ 0 ---
  final timeTarget = g.timeTargetSeconds;
  if (timeTarget != null && timeTarget < 0) {
    issues.add(const GoalValidationIssue(
      GoalValidationField.timeTargetSeconds,
      '目标时长不能为负数',
    ));
  }

  // --- 已启用提醒时，hour/minute 必须合法 ---
  final reminder = g.reminder;
  if (reminder.enabled) {
    final hour = reminder.hour;
    if (hour == null || hour < 0 || hour > 23) {
      issues.add(const GoalValidationIssue(
        GoalValidationField.hour,
        '提醒小时需在 0~23 之间',
      ));
    }
    final minute = reminder.minute;
    if (minute == null || minute < 0 || minute > 59) {
      issues.add(const GoalValidationIssue(
        GoalValidationField.minute,
        '提醒分钟需在 0~59 之间',
      ));
    }
  }

  return issues.isEmpty ? const <GoalValidationIssue>[] : issues;
}

/// `validateGoal(g).isEmpty` 的语法糖。
bool isGoalValid(GoalItem g) => validateGoal(g).isEmpty;

/// 字段级校验器：`randomMinGapDays`（随机模式下最小间隔天数）。
///
/// - 返回 `null` 表示合法（含 `v == null` 的"未填写"）。
/// - 返回 `String` 即错误描述，可直接塞给 `TextFormField.validator`。
String? validateRandomMinGapDaysInt(int? v) {
  if (v == null) return null;
  if (v < 1) return '随机模式下最小间隔天数需 ≥ 1';
  return null;
}

/// 字段级校验器：`dailyTargetCount`（每日目标次数，允许 0）。
String? validateDailyTargetCountInt(int? v) {
  if (v == null) return null;
  if (v < 0) return '每日目标次数不能为负数';
  return null;
}
