import '../models/habit.dart';
import 'habit_trend.dart';

enum HabitInsightKind { overview, rising, slipping, streak, attention }

class HabitInsight {
  final HabitInsightKind kind;
  final String title;
  final String message;
  final String? habitId;
  final double score;

  const HabitInsight({
    required this.kind,
    required this.title,
    required this.message,
    this.habitId,
    this.score = 0,
  });
}

class HabitInsightEngine {
  const HabitInsightEngine._();

  static List<HabitInsight> buildInsights(
    Iterable<Habit> habits, {
    DateTime? today,
    HabitTrendWindow window = HabitTrendWindow.days30,
    int limit = 5,
  }) {
    final summaries = [
      for (final habit in habits)
        _HabitWithSummary(
          habit,
          buildHabitTrendSummary(habit, window: window, today: today),
        ),
    ].where((item) => item.summary.activeDays > 0).toList(growable: false);
    if (summaries.isEmpty) return const <HabitInsight>[];

    final insights = <HabitInsight>[];
    insights.add(_overviewInsight(summaries, window));
    _bestRising(summaries)?.let(insights.add);
    _mostSlipping(summaries)?.let(insights.add);
    _bestStreak(summaries)?.let(insights.add);
    _needsAttention(summaries)?.let(insights.add);

    return insights.take(limit).toList(growable: false);
  }

  static HabitInsight _overviewInsight(
    List<_HabitWithSummary> summaries,
    HabitTrendWindow window,
  ) {
    final activeDays = summaries.fold<int>(
      0,
      (sum, item) => sum + item.summary.activeDays,
    );
    final completedDays = summaries.fold<int>(
      0,
      (sum, item) => sum + item.summary.completedDays,
    );
    final rate = activeDays == 0 ? 0.0 : completedDays / activeDays;
    final percent = (rate * 100).round();
    final title = percent >= 80
        ? '习惯状态稳定'
        : percent >= 50
        ? '习惯状态可提升'
        : '习惯需要收紧';
    return HabitInsight(
      kind: HabitInsightKind.overview,
      title: title,
      message:
          '${window.label}平均达标率 $percent%，已完成 $completedDays/$activeDays 个活跃日。',
      score: rate,
    );
  }

  static HabitInsight? _bestRising(List<_HabitWithSummary> summaries) {
    final candidates =
        summaries
            .where((item) => item.summary.completionRateDelta >= 0.12)
            .toList()
          ..sort(
            (a, b) => b.summary.completionRateDelta.compareTo(
              a.summary.completionRateDelta,
            ),
          );
    if (candidates.isEmpty) return null;
    final item = candidates.first;
    final delta = (item.summary.completionRateDelta * 100).round();
    return HabitInsight(
      kind: HabitInsightKind.rising,
      title: '${item.habit.name} 正在变好',
      message: '较上一周期提升 $delta 个百分点，继续保持当前节奏。',
      habitId: item.habit.id,
      score: item.summary.completionRateDelta,
    );
  }

  static HabitInsight? _mostSlipping(List<_HabitWithSummary> summaries) {
    final candidates =
        summaries
            .where((item) => item.summary.completionRateDelta <= -0.12)
            .toList()
          ..sort(
            (a, b) => a.summary.completionRateDelta.compareTo(
              b.summary.completionRateDelta,
            ),
          );
    if (candidates.isEmpty) return null;
    final item = candidates.first;
    final delta = (item.summary.completionRateDelta.abs() * 100).round();
    return HabitInsight(
      kind: HabitInsightKind.slipping,
      title: '${item.habit.name} 有下滑',
      message: '较上一周期下降 $delta 个百分点，建议降低目标或调整提醒时间。',
      habitId: item.habit.id,
      score: item.summary.completionRateDelta.abs(),
    );
  }

  static HabitInsight? _bestStreak(List<_HabitWithSummary> summaries) {
    final candidates =
        summaries
            .where((item) => item.summary.longestCompletedStreak >= 7)
            .toList()
          ..sort(
            (a, b) => b.summary.longestCompletedStreak.compareTo(
              a.summary.longestCompletedStreak,
            ),
          );
    if (candidates.isEmpty) return null;
    final item = candidates.first;
    return HabitInsight(
      kind: HabitInsightKind.streak,
      title: '${item.habit.name} 连续性最好',
      message: '窗口内最长连续达标 ${item.summary.longestCompletedStreak} 天，可作为稳定习惯保留。',
      habitId: item.habit.id,
      score: item.summary.longestCompletedStreak.toDouble(),
    );
  }

  static HabitInsight? _needsAttention(List<_HabitWithSummary> summaries) {
    final candidates =
        summaries
            .where(
              (item) =>
                  item.summary.activeDays >= 7 &&
                  item.summary.completionRate < 0.35,
            )
            .toList()
          ..sort(
            (a, b) =>
                a.summary.completionRate.compareTo(b.summary.completionRate),
          );
    if (candidates.isEmpty) return null;
    final item = candidates.first;
    final percent = (item.summary.completionRate * 100).round();
    return HabitInsight(
      kind: HabitInsightKind.attention,
      title: '${item.habit.name} 需要关注',
      message: '当前达标率 $percent%，可以先改成更小目标，避免连续挫败。',
      habitId: item.habit.id,
      score: 1 - item.summary.completionRate,
    );
  }
}

class _HabitWithSummary {
  final Habit habit;
  final HabitTrendSummary summary;

  const _HabitWithSummary(this.habit, this.summary);
}

extension _NullableInsightX on HabitInsight? {
  void let(void Function(HabitInsight insight) callback) {
    final value = this;
    if (value != null) callback(value);
  }
}
