import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/lunar_calendar.dart';
import '../core/quotes.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/user_provider.dart';
import 'diary_screen.dart';
import 'habit_screen.dart';
import 'pomodoro_screen.dart';
import 'today_detail_router.dart';
import 'todo_screen.dart';

/// 今日概览：登录后展示的聚合首屏。
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = context.watch<ThemeProvider>().brand.strings;

    final todoP = context.watch<TodoProvider>();
    final habitP = context.watch<HabitProvider>();
    final pomoP = context.watch<PomodoroProvider>();
    final diaryP = context.watch<DiaryProvider>();
    final anniP = context.watch<AnniversaryProvider>();
    final courseP = context.watch<CourseProvider>();
    final goalP = context.watch<GoalProvider>();
    final user = context.watch<UserProvider>();

    final now = DateTime.now();
    final lunar = LunarCalendar.fromSolar(now);
    final term = LunarCalendar.solarTerm(now);
    final festival =
        LunarCalendar.solarFestival(now) ?? LunarCalendar.lunarFestival(lunar);

    final todayKey = DateTime(now.year, now.month, now.day);
    final todayTodos = todoP.todos.where((t) {
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      return d == todayKey && !t.isCompleted;
    }).toList()
      ..sort((a, b) => a.quadrant.index.compareTo(b.quadrant.index));
    final todayTodoCompleted = todoP.todos.where((t) {
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      return d == todayKey && t.isCompleted;
    }).length;

    final todayCourses = courseP.todayCourses..sort((a, b) => a.startSection.compareTo(b.startSection));
    final todayHabitProgress = habitP.todayCompletionRate;

    // 最近的 3 个纪念日
    final upcomingAnni = [...anniP.items]
      ..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    final soon =
        upcomingAnni.where((a) => a.daysRemaining >= 0).take(3).toList();

    final activeGoals = goalP.activeGoals.take(2).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('${user.profile.greeting}，${user.profile.username}'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          // 日期卡
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primary.withValues(alpha: 0.85),
                  cs.primary.withValues(alpha: 0.55),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${now.month}月${now.day}日 · 星期${_weekday(now.weekday)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '农历 ${lunar.chineseText}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (term != null) _chip(term, Colors.lightGreenAccent),
                          if (festival != null)
                            _chip(festival, Colors.amberAccent),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  '${now.day}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 今日一言
          _QuoteCard(),

          const SizedBox(height: 10),
          // 四个小指标
          Row(
            children: [
              _Metric(
                title: s.navTodo,
                value: '${todayTodos.length}',
                unit: '待办',
                icon: Icons.check_circle_outline,
                color: cs.primary,
                onTap: () => _go(context, const TodoScreen()),
              ),
              _Metric(
                title: s.navHabit,
                value: '${(todayHabitProgress * 100).round()}',
                unit: '%',
                icon: Icons.repeat,
                color: cs.tertiary,
                onTap: () => _go(context, const HabitScreen()),
              ),
              _Metric(
                title: s.navFocus,
                value: '${pomoP.sessionCountToday}',
                unit: '次',
                icon: Icons.timer,
                color: Colors.redAccent,
                onTap: () => _go(context, const PomodoroScreen()),
              ),
              _Metric(
                title: '日记',
                value: diaryP.entryForDate(now) == null ? '未写' : '已写',
                unit: '',
                icon: Icons.book_outlined,
                color: const Color(0xFF26A69A),
                onTap: () => _go(context, const DiaryScreen()),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 今日待办
          if (todayTodos.isNotEmpty || todayTodoCompleted > 0)
            _section(
              '今日待办 · ${todoP.todos.where((t) {
                    final d = DateTime(t.date.year, t.date.month, t.date.day);
                    return d == todayKey;
                  }).length} 项 (已完成 $todayTodoCompleted)',
              onMore: () => TodayDetailRouter.open(
                context,
                TodaySectionKind.todos,
              ),
              child: Column(
                children: todayTodos.take(5).map((t) {
                  return ListTile(
                    dense: true,
                    leading: Checkbox(
                      value: false,
                      shape: const CircleBorder(),
                      onChanged: (_) =>
                          context.read<TodoProvider>().toggleTodo(t.id),
                    ),
                    title: Text(t.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: t.listGroupName == null
                        ? null
                        : Text(t.listGroupName!,
                            style: const TextStyle(fontSize: 11)),
                    onTap: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.todos,
                      id: t.id,
                    ),
                  );
                }).toList(),
              ),
            ),

          // 今日课程
          if (todayCourses.isNotEmpty)
            _section(
              '今日课程 · ${todayCourses.length} 节',
              onMore: () => TodayDetailRouter.open(
                context,
                TodaySectionKind.courses,
              ),
              child: Column(
                children: todayCourses.map((c) {
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          Color(c.colorValue).withValues(alpha: 0.2),
                      child: Text('${c.startSection}',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(c.colorValue),
                              fontWeight: FontWeight.bold)),
                    ),
                    title: Text(c.name),
                    subtitle: Text(
                      '第${c.startSection}-${c.endSection}节${c.location.isEmpty ? '' : ' · ${c.location}'}${c.teacher.isEmpty ? '' : ' · ${c.teacher}'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.courses,
                    ),
                  );
                }).toList(),
              ),
            ),

          // 近期纪念日
          if (soon.isNotEmpty)
            _section(
              '即将到来的纪念日',
              onMore: () => TodayDetailRouter.open(
                context,
                TodaySectionKind.anniversaries,
              ),
              child: Column(
                children: soon.map((a) {
                  final d = a.daysRemaining;
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          Color(a.colorValue).withValues(alpha: 0.15),
                      child: Text(
                        '$d',
                        style: TextStyle(
                          color: Color(a.colorValue),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    title: Text(a.title),
                    subtitle: Text(
                      d == 0 ? '就是今天' : '还有 $d 天',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.anniversaries,
                      id: a.id,
                    ),
                  );
                }).toList(),
              ),
            ),

          // 目标进度
          if (activeGoals.isNotEmpty)
            _section(
              '进行中的目标',
              onMore: () => TodayDetailRouter.open(
                context,
                TodaySectionKind.goals,
              ),
              child: Column(
                children: activeGoals.map((g) {
                  final p = g.computedProgress;
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.flag,
                        color: Color(g.colorValue), size: 18),
                    title: Text(g.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: p,
                            minHeight: 5,
                            color: Color(g.colorValue),
                            backgroundColor:
                                Color(g.colorValue).withValues(alpha: 0.15),
                          ),
                        ),
                        Text('${(p * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                    onTap: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.goals,
                      id: g.id,
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(String title,
      {required Widget child, VoidCallback? onMore}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  if (onMore != null)
                    TextButton(
                      onPressed: onMore,
                      child: const Text('查看',
                          style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
            child,
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.9))),
    );
  }

  String _weekday(int w) =>
      const ['一', '二', '三', '四', '五', '六', '日'][w - 1];

  void _go(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _Metric extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _Metric({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                    children: [
                      TextSpan(text: value),
                      if (unit.isNotEmpty)
                        TextSpan(
                          text: unit,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                ),
                Text(title,
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuoteCard extends StatefulWidget {
  @override
  State<_QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<_QuoteCard> {
  late String _text;

  @override
  void initState() {
    super.initState();
    _text = DailyQuotes.today();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => setState(() => _text = DailyQuotes.random()),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(Icons.format_quote, color: cs.primary.withValues(alpha: 0.6)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_text,
                  style: const TextStyle(fontSize: 13, height: 1.6)),
            ),
            Icon(Icons.refresh,
                size: 16, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }
}
