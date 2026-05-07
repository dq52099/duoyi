import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/todo_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../models/pomodoro.dart';

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final todoProvider = context.watch<TodoProvider>();
    final habitProvider = context.watch<HabitProvider>();
    final pomodoroProvider = context.watch<PomodoroProvider>();
    final cs = Theme.of(context).colorScheme;

    // Time audit data (Simulated based on assumptions since real apps track strict time-blocks)
    // 1. Pomodoro Focus Time (Actual accurate time tracked)
    final focusMinutes = pomodoroProvider.totalFocusMinutes.toDouble();

    // 2. Completed Todos (Estimate: 30 mins per completed todo)
    final todoMinutes = (todoProvider.completedTodos.length * 30).toDouble();

    // 3. Completed Habits (Estimate: 15 mins per completed habit streak total today? Or just global completions)
    // For simplicity, let's use global stats
    double habitMinutes = 0.0;
    for (final h in habitProvider.habits) {
      habitMinutes += (h.currentStreak * h.targetCount * 15).toDouble();
    }

    final totalMinutes = focusMinutes + todoMinutes + habitMinutes;

    final dataEmpty = totalMinutes == 0;

    return Scaffold(
      appBar: AppBar(title: const Text('时光足迹 (数据统计)')),
      body: dataEmpty
          ? Center(
              child: Text(
                '暂无数据，请多使用 App 记录生活',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '全局时间投入分布',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '基于您的代办完成、习惯打卡和番茄专注自动估算',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 240,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 50,
                      sections: [
                        PieChartSectionData(
                          color: const Color(0xFFE53935),
                          value: focusMinutes,
                          title:
                              '${((focusMinutes / totalMinutes) * 100).toStringAsFixed(1)}%',
                          radius: focusMinutes == totalMinutes ? 60 : 50,
                          titleStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        PieChartSectionData(
                          color: const Color(0xFF1E88E5),
                          value: todoMinutes,
                          title:
                              '${((todoMinutes / totalMinutes) * 100).toStringAsFixed(1)}%',
                          radius: todoMinutes == totalMinutes ? 60 : 50,
                          titleStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        PieChartSectionData(
                          color: const Color(0xFF4CAF50),
                          value: habitMinutes,
                          title:
                              '${((habitMinutes / totalMinutes) * 100).toStringAsFixed(1)}%',
                          radius: habitMinutes == totalMinutes ? 60 : 50,
                          titleStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _LegendItem(
                  color: const Color(0xFFE53935),
                  label: '深度专注 (番茄钟)',
                  value: '${focusMinutes.toInt()} 分钟',
                ),
                const SizedBox(height: 12),
                _LegendItem(
                  color: const Color(0xFF1E88E5),
                  label: '执行待办 (估算)',
                  value: '${todoMinutes.toInt()} 分钟',
                ),
                const SizedBox(height: 12),
                _LegendItem(
                  color: const Color(0xFF4CAF50),
                  label: '习惯养成 (估算)',
                  value: '${habitMinutes.toInt()} 分钟',
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  '番茄钟时间段分布',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _generatePomodoroTimeline(
                            pomodoroProvider.sessions,
                          ),
                          isCurved: true,
                          color: cs.primary,
                          barWidth: 4,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: cs.primary.withValues(alpha: 0.2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<FlSpot> _generatePomodoroTimeline(List<PomodoroSession> sessions) {
    if (sessions.isEmpty) return [const FlSpot(0, 0)];

    // Group by hour of day (0-23)
    final Map<int, int> hourCounts = {};
    for (int i = 0; i < 24; i++) {
      hourCounts[i] = 0;
    }

    for (final s in sessions) {
      if (s.type == PomodoroType.focus) {
        hourCounts[s.startTime.hour] =
            (hourCounts[s.startTime.hour] ?? 0) + (s.durationSeconds ~/ 60);
      }
    }

    return hourCounts.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.toDouble()))
        .toList();
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
