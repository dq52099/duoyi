import 'dart:collection';

import '../models/habit.dart';
import 'habit_trend.dart';
import 'i18n.dart';

enum HabitInsightKind { overview, rising, slipping, streak, attention }

class HabitInsight {
  final HabitInsightKind kind;
  final String _title;
  final String _message;
  final HabitInsightText? generatedText;
  final String? habitId;
  final double score;

  const HabitInsight({
    required this.kind,
    required String title,
    required String message,
    this.generatedText,
    this.habitId,
    this.score = 0,
  }) : _title = title,
       _message = message;

  String titleFor(AppLocale locale) =>
      generatedText?.titleFor(locale) ?? _title;
  String messageFor(AppLocale locale) =>
      generatedText?.messageFor(locale) ?? _message;

  String get title => titleFor(I18n.current);
  String get message => messageFor(I18n.current);
}

/// Immutable presentation facts for cached, app-generated insight text.
sealed class HabitInsightText {
  const HabitInsightText();

  String titleFor(AppLocale locale);
  String messageFor(AppLocale locale);
}

final class HabitOverviewInsightText extends HabitInsightText {
  final HabitTrendWindow window;
  final int percent;
  final int completedDays;
  final int activeDays;

  const HabitOverviewInsightText({
    required this.window,
    required this.percent,
    required this.completedDays,
    required this.activeDays,
  });

  @override
  String titleFor(AppLocale locale) {
    if (locale == AppLocale.en) {
      return percent >= 80
          ? 'Habits are steady'
          : percent >= 50
          ? 'Room to improve'
          : 'Habits need attention';
    }
    return percent >= 80
        ? '习惯状态稳定'
        : percent >= 50
        ? '习惯状态可提升'
        : '习惯需要收紧';
  }

  @override
  String messageFor(AppLocale locale) {
    if (locale == AppLocale.en) {
      final period = window == HabitTrendWindow.days365
          ? '1 year'
          : '${window.days} days';
      return '$period average completion: $percent%; '
          '$completedDays/$activeDays active days completed.';
    }
    return '${window.label}平均达标率 $percent%，已完成 $completedDays/$activeDays 个活跃日。';
  }
}

final class HabitChangeInsightText extends HabitInsightText {
  final String habitName;
  final int delta;
  final bool rising;

  const HabitChangeInsightText({
    required this.habitName,
    required this.delta,
    required this.rising,
  });

  @override
  String titleFor(AppLocale locale) => locale == AppLocale.en
      ? '$habitName ${rising ? 'is improving' : 'is slipping'}'
      : '$habitName ${rising ? '正在变好' : '有下滑'}';

  @override
  String messageFor(AppLocale locale) {
    if (locale == AppLocale.en) {
      return rising
          ? 'Up $delta percentage points from the previous period. Keep your current pace.'
          : 'Down $delta percentage points from the previous period. Try a smaller goal or a different reminder time.';
    }
    return rising
        ? '较上一周期提升 $delta 个百分点，继续保持当前节奏。'
        : '较上一周期下降 $delta 个百分点，建议降低目标或调整提醒时间。';
  }
}

final class HabitStreakInsightText extends HabitInsightText {
  final String habitName;
  final int days;

  const HabitStreakInsightText({required this.habitName, required this.days});

  @override
  String titleFor(AppLocale locale) => locale == AppLocale.en
      ? '$habitName has the strongest streak'
      : '$habitName 连续性最好';

  @override
  String messageFor(AppLocale locale) => locale == AppLocale.en
      ? 'Your longest streak in this period is $days ${days == 1 ? 'day' : 'days'}. Keep this steady habit.'
      : '窗口内最长连续达标 $days 天，可作为稳定习惯保留。';
}

final class HabitAttentionInsightText extends HabitInsightText {
  final String habitName;
  final int percent;

  const HabitAttentionInsightText({
    required this.habitName,
    required this.percent,
  });

  @override
  String titleFor(AppLocale locale) =>
      locale == AppLocale.en ? '$habitName needs attention' : '$habitName 需要关注';

  @override
  String messageFor(AppLocale locale) => locale == AppLocale.en
      ? 'Current completion is $percent%. Start with a smaller goal to make progress easier.'
      : '当前达标率 $percent%，可以先改成更小目标，避免连续挫败。';
}

class HabitInsightEngine {
  const HabitInsightEngine._();

  static const int _maxCacheEntries = 16;
  static final LinkedHashMap<Object, List<HabitInsight>> _cache =
      LinkedHashMap<Object, List<HabitInsight>>();

  static List<HabitInsight> buildInsights(
    Iterable<Habit> habits, {
    DateTime? today,
    HabitTrendWindow window = HabitTrendWindow.days30,
    int limit = 5,
  }) {
    final anchor = today ?? DateTime.now();
    final fingerprint = _habitsFingerprint(habits);
    final cacheKey = (
      anchor.year,
      anchor.month,
      anchor.day,
      window,
      limit,
      fingerprint.$1,
      fingerprint.$2,
      fingerprint.$3,
    );
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }

    final summaries = [
      for (final habit in habits)
        _HabitWithSummary(
          habit,
          buildHabitTrendSummary(habit, window: window, today: today),
        ),
    ].where((item) => item.summary.activeDays > 0).toList(growable: false);
    if (summaries.isEmpty) {
      const empty = <HabitInsight>[];
      _putCache(cacheKey, empty);
      return empty;
    }

    final insights = <HabitInsight>[];
    insights.add(_overviewInsight(summaries, window));
    _bestRising(summaries)?.let(insights.add);
    _mostSlipping(summaries)?.let(insights.add);
    _bestStreak(summaries)?.let(insights.add);
    _needsAttention(summaries)?.let(insights.add);

    final result = List<HabitInsight>.unmodifiable(insights.take(limit));
    _putCache(cacheKey, result);
    return result;
  }

  static void _putCache(Object key, List<HabitInsight> value) {
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  static (int, int, int) _habitsFingerprint(Iterable<Habit> habits) {
    var count = 0;
    var hashA = 0x811c9dc5;
    var hashB = 0;
    for (final habit in habits) {
      count++;
      var compHash = 0;
      for (final entry in habit.completions.entries) {
        compHash ^= Object.hash(entry.key, entry.value);
      }
      var frozenHash = 0;
      for (final d in habit.frozenDates) {
        frozenHash ^= d.hashCode;
      }
      var weekdaysHash = 0;
      for (final w in habit.activeWeekdays) {
        weekdaysHash = (weekdaysHash * 13 + w) & 0x3fffffff;
      }
      final itemHash = Object.hash(
        habit.id,
        habit.name,
        habit.kind.index,
        habit.targetCount,
        habit.flexTarget ?? -1,
        habit.flexPeriod?.index ?? -1,
        habit.startDate?.millisecondsSinceEpoch ?? -1,
        habit.endDate?.millisecondsSinceEpoch ?? -1,
        habit.createdAt.millisecondsSinceEpoch,
        habit.updatedAt.millisecondsSinceEpoch,
        habit.currentStreak,
        habit.bestStreak,
        habit.completions.length,
        compHash,
        habit.frozenDates.length,
        frozenHash,
        weekdaysHash,
      );
      hashA = Object.hash(hashA, itemHash);
      hashB = ((hashB * 31) ^ itemHash ^ (count * 0x9e3779b9)) & 0x3fffffff;
    }
    return (count, hashA, hashB);
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
      generatedText: HabitOverviewInsightText(
        window: window,
        percent: percent,
        completedDays: completedDays,
        activeDays: activeDays,
      ),
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
      generatedText: HabitChangeInsightText(
        habitName: item.habit.name,
        delta: delta,
        rising: true,
      ),
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
      generatedText: HabitChangeInsightText(
        habitName: item.habit.name,
        delta: delta,
        rising: false,
      ),
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
      generatedText: HabitStreakInsightText(
        habitName: item.habit.name,
        days: item.summary.longestCompletedStreak,
      ),
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
      generatedText: HabitAttentionInsightText(
        habitName: item.habit.name,
        percent: percent,
      ),
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
