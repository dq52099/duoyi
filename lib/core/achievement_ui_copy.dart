import '../providers/achievement_provider.dart';
import 'achievements.dart';
import 'growth_levels.dart';
import 'i18n.dart';
import 'productivity_challenges.dart';

/// Render catalog copy by identity without translating stored user text.
class AchievementUiCopy {
  static String text(String zh, String en, {AppLocale? locale}) =>
      (locale ?? I18n.current) == AppLocale.en ? en : zh;

  static const _badges = <String, (String, String)>{
    'first_todo': ('First step', 'Complete your first task'),
    'todo_10': ('Getting things done', 'Complete 10 tasks'),
    'todo_100': ('Task achiever', 'Complete 100 tasks'),
    'todo_500': ('Time well spent', 'Complete 500 tasks'),
    'habit_start': ('A new routine', 'Create your first habit'),
    'streak_7': ('Seven days strong', 'Keep a 7-day habit streak'),
    'streak_30': ('A month of consistency', 'Keep a 30-day habit streak'),
    'streak_100': ('A lasting foundation', 'Keep a 100-day habit streak'),
    'focus_1h': ('Finding focus', 'Focus for 60 minutes in total'),
    'focus_10h': ('Into the flow', 'Focus for 10 hours in total'),
    'focus_100h': ('Focus mastery', 'Focus for 100 hours in total'),
    'diary_first': ('The first page', 'Write your first diary entry'),
    'diary_streak_7': (
      'A week of reflection',
      'Write a diary entry 7 days in a row',
    ),
    'diary_30': ('Your story grows', 'Write 30 diary entries'),
    'goal_first': ('A goal in mind', 'Create your first goal'),
    'goal_achieved': ('Follow through', 'Achieve a goal'),
    'goal_5': ('Five goals reached', 'Achieve 5 goals'),
    'polymath': ('All-round explorer', 'Use at least 5 modules'),
    'theme_explorer': ('A change of scenery', 'Switch themes at least 3 times'),
  };
  static const _challenges = <String, (String, String)>{
    'daily_todo_clear': ('Move your list forward', 'Complete 3 tasks today'),
    'daily_focus_start': ('Make time to focus', 'Focus for 25 minutes today'),
    'daily_habit_anchor': (
      'Keep your routine',
      'Complete 2 habit check-ins today',
    ),
    'daily_reflection': ('Reflect on today', 'Write 1 diary entry today'),
    'weekly_todo_sprint': (
      'Weekly task progress',
      'Complete 15 tasks this week',
    ),
    'weekly_focus_deep_work': (
      'A week of deep work',
      'Focus for 180 minutes this week',
    ),
    'weekly_habit_chain': (
      'Build a habit chain',
      'Complete 10 habit check-ins this week',
    ),
    'weekly_reflection': (
      'Three reflections',
      'Write 3 diary entries this week',
    ),
    'weekly_active_days': (
      'Five active days',
      'Record tasks, habits, focus or diary entries on 5 days this week',
    ),
  };
  static const _levels = [
    'Time apprentice',
    'Task newcomer',
    'Routine builder',
    'Focused learner',
    'Habit builder',
    'Weekly planner',
    'Deep worker',
    'Reflective practitioner',
    'Productivity coach',
    'Long-term thinker',
    'Time navigator',
    'Goal partner',
    'Flow expert',
    'Duoyi master',
    'Time strategist',
  ];

  static String badgeTitle(Achievement badge, {AppLocale? locale}) =>
      text(badge.title, _badges[badge.id]?.$1 ?? badge.title, locale: locale);
  static String badgeDescription(Achievement badge, {AppLocale? locale}) =>
      text(
        badge.description,
        _badges[badge.id]?.$2 ?? badge.description,
        locale: locale,
      );
  static String challengeTitle(ProductivityChallenge item) =>
      text(item.title, _challenges[item.id]?.$1 ?? item.title);
  static String challengeDescription(ProductivityChallenge item) =>
      text(item.description, _challenges[item.id]?.$2 ?? item.description);
  static String challengePeriod(ProductivityChallenge item) =>
      item.period == ProductivityChallengePeriod.daily
      ? text('今日挑战', 'Today')
      : text('本周挑战', 'This week');
  static String levelTitle(GrowthLevel level) => text(
    level.title,
    level.level >= 1 && level.level <= _levels.length
        ? _levels[level.level - 1]
        : level.title,
  );
  static String unlockMessage(Achievement badge) =>
      text('解锁成就：', 'Achievement unlocked: ') + badgeTitle(badge);

  static (String, String)? _knownLedgerCopy(RewardLedgerEntry entry) {
    final parts = entry.id.split(':');
    if (parts.length == 2 && parts.first == 'achievement') {
      final badge = Achievements.all
          .where((badge) => badge.id == parts[1])
          .firstOrNull;
      if (badge != null) return (unlockMessage(badge), badgeDescription(badge));
    }
    if (parts.length == 3 &&
        parts.first == 'challenge' &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(parts[2])) {
      final copy = _challenges[parts[1]];
      if (copy != null) {
        final title = text(entry.title, 'Challenge completed: ${copy.$1}');
        final period = parts[1].startsWith('daily_')
            ? text('今日挑战', 'Today’s challenge')
            : text('本周挑战', 'Weekly challenge');
        return (title, '$period · ${parts[2]}');
      }
    }
    if (parts.length >= 3 && parts.first == 'event' && parts[2].isNotEmpty) {
      final copy = switch (parts[1]) {
        'todo' => ('Task completed', 'Task completion reward'),
        'habit' => ('Habit check-in', 'Habit check-in reward'),
        'focus' => ('Focus completed', 'Focus time reward'),
        'goal' => ('Goal achieved', 'Goal achievement reward'),
        'milestone' => ('Milestone completed', 'Goal milestone reward'),
        'diary' => ('Diary entry written', 'Diary entry reward'),
        _ => null,
      };
      if (copy != null) {
        return (text(entry.title, copy.$1), text(entry.reason, copy.$2));
      }
    }
    return null;
  }

  static String ledgerTitle(RewardLedgerEntry entry) =>
      _knownLedgerCopy(entry)?.$1 ?? entry.title;
  static String ledgerReason(RewardLedgerEntry entry) =>
      _knownLedgerCopy(entry)?.$2 ?? entry.reason;
}
