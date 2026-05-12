import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/pomodoro.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import '../providers/diary_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../widgets/surface_components.dart';
import 'time_audit_screen.dart';

enum _Range { week, month, year }

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  _Range _range = _Range.week;

  (DateTime, DateTime) get _rangeBounds {
    final now = DateTime.now();
    switch (_range) {
      case _Range.week:
        final monday = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - 1));
        return (monday, now);
      case _Range.month:
        return (DateTime(now.year, now.month, 1), now);
      case _Range.year:
        return (DateTime(now.year, 1, 1), now);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todoProv = context.watch<TodoProvider>();
    final habitProv = context.watch<HabitProvider>();
    final pomoProv = context.watch<PomodoroProvider>();
    final diaryProv = context.watch<DiaryProvider>();
    final timeAuditProv = context.watch<TimeAuditProvider>();
    final cs = Theme.of(context).colorScheme;

    final (start, end) = _rangeBounds;
    final auditEntries = timeAuditProv.entriesInRange(start, end);
    final auditTotalMinutes =
        timeAuditProv.totalSecondsInRange(start, end) ~/ 60;
    final auditCategorySeconds = timeAuditProv.secondsByCategory(start, end);
    bool inRange(DateTime d) =>
        !d.isBefore(DateTime(start.year, start.month, start.day)) &&
        !d.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59));

    final completedTodos = todoProv.completedTodos.where((t) {
      final ts = t.completedAt ?? t.updatedAt;
      return inRange(ts);
    }).toList();

    final focusSessions = pomoProv.sessions
        .where((s) => s.type == PomodoroType.focus && inRange(s.startTime))
        .toList();
    final focusMinutes =
        focusSessions.fold<int>(0, (sum, s) => sum + s.durationSeconds) ~/ 60;

    final diaryInRange = diaryProv.entries.where((d) => inRange(d.date)).length;

    int habitDoneInRange = 0;
    for (final h in habitProv.habits) {
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        if (h.isCompletedForDate(d)) habitDoneInRange++;
      }
    }

    // 四象限分布(未完成)
    final quadCounts = [
      todoProv.getQuadrantTodos(EisenhowerQuadrant.urgentImportant).length,
      todoProv.getQuadrantTodos(EisenhowerQuadrant.notUrgentImportant).length,
      todoProv.getQuadrantTodos(EisenhowerQuadrant.urgentNotImportant).length,
      todoProv
          .getQuadrantTodos(EisenhowerQuadrant.notUrgentNotImportant)
          .length,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('时光足迹'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<_Range>(
              segments: const [
                ButtonSegment(value: _Range.week, label: Text('本周')),
                ButtonSegment(value: _Range.month, label: Text('本月')),
                ButtonSegment(value: _Range.year, label: Text('本年')),
              ],
              selected: {_range},
              onSelectionChanged: (s) => setState(() => _range = s.first),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 2.5,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _Kpi(
                icon: Icons.check_circle,
                color: cs.primary,
                title: '待办完成',
                value: '${completedTodos.length}',
              ),
              _Kpi(
                icon: Icons.timer,
                color: Colors.redAccent,
                title: '深度专注',
                value: '$focusMinutes 分',
              ),
              _Kpi(
                icon: Icons.repeat,
                color: const Color(0xFF66BB6A),
                title: '习惯打卡',
                value: '$habitDoneInRange 次',
              ),
              _Kpi(
                icon: Icons.book_outlined,
                color: const Color(0xFF26A69A),
                title: '日记',
                value: '$diaryInRange 篇',
              ),
              _Kpi(
                icon: Icons.timelapse_outlined,
                color: const Color(0xFF78909C),
                title: '时间足迹',
                value: '$auditTotalMinutes 分',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _chartCard(
            '时间投入分布',
            SizedBox(
              height: 180,
              child: _buildAuditPie(
                secondsByCategory: auditCategorySeconds,
                cs: cs,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _chartCard(
            '时间线',
            _buildAuditTimeline(auditEntries, cs),
          ),
          const SizedBox(height: 10),
          _chartCard(
            _range == _Range.year ? '每月专注分钟数' : '每日专注分钟数',
            SizedBox(
              height: 180,
              child: _buildFocusSeries(
                sessions: focusSessions,
                range: _range,
                start: start,
                end: end,
                cs: cs,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _chartCard(
            '四象限分布 (未完成)',
            Padding(
              padding: const EdgeInsets.all(12),
              child: _QuadrantBar(counts: quadCounts),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard(String title, Widget child) {
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildAuditPie({
    required Map<TimeEntryCategory, int> secondsByCategory,
    required ColorScheme cs,
  }) {
    final values = secondsByCategory.entries
        .where((entry) => entry.value > 0)
        .toList();
    final total = values.fold<int>(0, (sum, entry) => sum + entry.value);
    if (total == 0) {
      return const Center(
        child: Text('暂无时间足迹', style: TextStyle(color: Colors.grey)),
      );
    }
    PieChartSectionData sec(int v, Color c) => PieChartSectionData(
      value: v.toDouble(),
      color: c,
      radius: 48,
      title: v == 0 ? '' : '${((v / total) * 100).toStringAsFixed(0)}%',
      titleStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
    );
    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 32,
              sectionsSpace: 2,
              sections: [
                for (final entry in values)
                  sec(entry.value, _auditColor(entry.key, cs)),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 100,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in values.take(5))
                _legend(_auditColor(entry.key, cs), entry.key.label),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuditTimeline(List<TimeEntry> entries, ColorScheme cs) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('暂无时间记录', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    final sorted = [...entries]..sort((a, b) => b.startAt.compareTo(a.startAt));
    return Column(
      children: [
        for (final entry in sorted.take(6))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: _auditColor(entry.category, cs)
                  .withValues(alpha: 0.12),
              child: Icon(
                _auditIcon(entry.category),
                color: _auditColor(entry.category, cs),
                size: 16,
              ),
            ),
            title: Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${entry.category.label} · ${_formatDateTime(entry.startAt)} · '
              '${_formatDuration(entry.durationSeconds)}',
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TimeAuditScreen()),
            ),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('查看全部'),
          ),
        ),
      ],
    );
  }

  Color _auditColor(TimeEntryCategory category, ColorScheme cs) =>
      switch (category) {
        TimeEntryCategory.focus => Colors.redAccent,
        TimeEntryCategory.todo => cs.primary,
        TimeEntryCategory.habit => const Color(0xFF66BB6A),
        TimeEntryCategory.goal => const Color(0xFFAB47BC),
        TimeEntryCategory.study => const Color(0xFF26A69A),
        TimeEntryCategory.work => const Color(0xFFFF9800),
        TimeEntryCategory.life => const Color(0xFF8D6E63),
        TimeEntryCategory.other => const Color(0xFF78909C),
      };

  IconData _auditIcon(TimeEntryCategory category) => switch (category) {
    TimeEntryCategory.focus => Icons.timer_outlined,
    TimeEntryCategory.todo => Icons.check_circle_outline,
    TimeEntryCategory.habit => Icons.repeat,
    TimeEntryCategory.goal => Icons.flag_outlined,
    TimeEntryCategory.study => Icons.menu_book_outlined,
    TimeEntryCategory.work => Icons.work_outline,
    TimeEntryCategory.life => Icons.favorite_outline,
    TimeEntryCategory.other => Icons.more_horiz,
  };

  String _formatDateTime(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _formatDuration(int seconds) {
    if (seconds >= 3600) {
      return '${(seconds / 3600).toStringAsFixed(seconds % 3600 == 0 ? 0 : 1)} 小时';
    }
    return '${(seconds / 60).toStringAsFixed(seconds % 60 == 0 ? 0 : 1)} 分钟';
  }

  Widget _legend(Color c, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );

  Widget _buildFocusSeries({
    required List<PomodoroSession> sessions,
    required _Range range,
    required DateTime start,
    required DateTime end,
    required ColorScheme cs,
  }) {
    final buckets = <String, int>{};
    DateTime cursor = DateTime(start.year, start.month, start.day);
    final endNorm = DateTime(end.year, end.month, end.day);

    if (range == _Range.year) {
      for (int m = 1; m <= DateTime.now().month; m++) {
        buckets['$m月'] = 0;
      }
    } else {
      while (!cursor.isAfter(endNorm)) {
        final k = '${cursor.month}/${cursor.day}';
        buckets[k] = 0;
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    for (final s in sessions) {
      final k = range == _Range.year
          ? '${s.startTime.month}月'
          : '${s.startTime.month}/${s.startTime.day}';
      buckets[k] = (buckets[k] ?? 0) + (s.durationSeconds ~/ 60);
    }

    if (buckets.values.every((v) => v == 0)) {
      return const Center(
        child: Text('暂无专注数据', style: TextStyle(color: Colors.grey)),
      );
    }

    final entries = buckets.entries.toList();
    final maxV = buckets.values.isEmpty
        ? 1.0
        : (buckets.values.reduce((a, b) => a > b ? a : b)).toDouble();

    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxV * 1.2).clamp(10, double.infinity),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= entries.length) return const SizedBox();
                if (entries.length > 10 && i % 2 != 0) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    entries[i].key,
                    style: const TextStyle(fontSize: 9),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (int i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].value.toDouble(),
                  color: cs.primary,
                  width: entries.length > 14 ? 5 : 9,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _QuadrantBar extends StatelessWidget {
  final List<int> counts;
  const _QuadrantBar({required this.counts});

  @override
  Widget build(BuildContext context) {
    const labels = ['重要紧急', '重要不紧急', '紧急不重要', '不重要不紧急'];
    const colors = [
      Color(0xFFE53935),
      Color(0xFFF6A339),
      Color(0xFF42A5F5),
      Color(0xFF8E8E8E),
    ];
    final total = counts.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return const Text('暂无未完成任务', style: TextStyle(color: Colors.grey));
    }
    return Column(
      children: List.generate(4, (i) {
        final ratio = total == 0 ? 0.0 : counts[i] / total;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(labels[i], style: const TextStyle(fontSize: 12)),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors[i].withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[i],
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 28,
                child: Text(
                  '${counts[i]}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  const _Kpi({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(10),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
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
