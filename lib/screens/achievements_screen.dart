import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/achievements.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/note_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/todo_provider.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  AchievementContext _ctx(BuildContext context) {
    return AchievementContext(
      totalTodos: context.read<TodoProvider>().todos.length,
      completedTodos:
          context.read<TodoProvider>().completedTodos.length,
      longestHabitStreak:
          context.read<HabitProvider>().longestBestStreak,
      habitCount: context.read<HabitProvider>().habits.length,
      focusMinutes:
          context.read<PomodoroProvider>().totalFocusMinutes,
      focusSessions: context.read<PomodoroProvider>().sessions.length,
      diaryStreak: context.read<DiaryProvider>().currentStreak,
      diaryCount: context.read<DiaryProvider>().entries.length,
      goalsTotal: context.read<GoalProvider>().goals.length,
      goalsAchieved: context
          .read<GoalProvider>()
          .goals
          .where((g) => g.status.name == 'achieved')
          .length,
      anniversaries: context.read<AnniversaryProvider>().items.length,
      courses: context.read<CourseProvider>().courses.length,
      notes: context.read<NoteProvider>().notes.length,
      themeSwitches: context.read<ThemeProvider>().themeSwitchCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctx(context);
    final all = Achievements.all;
    final unlocked = all.where((a) => a.unlocked(c)).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('成就 · $unlocked / ${all.length}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _ProgressHeader(unlocked: unlocked, total: all.length),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.6,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: all.map((a) {
              final unlockedNow = a.unlocked(c);
              final cur = a.current?.call(c);
              final target = a.target;
              final progress = (cur != null && target != null && target > 0)
                  ? (cur / target).clamp(0.0, 1.0)
                  : (unlockedNow ? 1.0 : 0.0);
              return _BadgeCard(
                ach: a,
                unlocked: unlockedNow,
                current: cur,
                target: target,
                progress: progress,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final int unlocked;
  final int total;
  const _ProgressHeader({required this.unlocked, required this.total});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = total == 0 ? 0.0 : unlocked / total;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          cs.primary.withValues(alpha: 0.85),
          cs.primary.withValues(alpha: 0.6),
        ]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('你的成就',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text('$unlocked / $total',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: p,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final Achievement ach;
  final bool unlocked;
  final int? current;
  final int? target;
  final double progress;

  const _BadgeCard({
    required this.ach,
    required this.unlocked,
    required this.current,
    required this.target,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = unlocked ? ach.color : Colors.grey.shade400;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(ach.icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ach.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: unlocked ? null : Colors.grey,
                  ),
                ),
              ),
              if (unlocked)
                Icon(Icons.check_circle,
                    color: color.withValues(alpha: 0.85), size: 16),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ach.description,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
          const Spacer(),
          if (current != null && target != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: color.withValues(alpha: 0.12),
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('$current / $target',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade500)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
