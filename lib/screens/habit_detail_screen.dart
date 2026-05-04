import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/habit_provider.dart';
import '../widgets/habit_heatmap.dart';

class HabitDetailScreen extends StatefulWidget {
  final String habitId;

  const HabitDetailScreen({super.key, required this.habitId});

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HabitProvider>();
    final habit = provider.habits.firstWhere(
      (h) => h.id == widget.habitId,
      orElse: () => provider.habits.first,
    );
    final heatmapData = habit.heatmapData(20);
    final cs = Theme.of(context).colorScheme;
    final color = Color(habit.colorValue);

    return Scaffold(
      appBar: AppBar(title: Text(habit.name)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.star, color: color, size: 32),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      habit.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StatChip(
                          label: '当前连续',
                          value: '${habit.currentStreak}天',
                        ),
                        const SizedBox(width: 16),
                        _StatChip(label: '最佳纪录', value: '${habit.bestStreak}天'),
                        const SizedBox(width: 16),
                        _StatChip(
                          label: '今日',
                          value: '${habit.todayCount()}/${habit.targetCount}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '打卡热力图',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
          ),
          HabitHeatmap(heatmapData: heatmapData, weeks: 20),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '最近打卡记录',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 30,
            itemBuilder: (_, i) {
              final d = DateTime.now().subtract(Duration(days: i));
              final count = habit.countForDate(d);
              return ListTile(
                dense: true,
                leading: Text(
                  '${d.month}/${d.day}',
                  style: const TextStyle(fontSize: 13),
                ),
                title: LinearProgressIndicator(
                  value: count / habit.targetCount,
                ),
                trailing: Text(
                  '$count/${habit.targetCount}',
                  style: TextStyle(
                    fontSize: 12,
                    color: count >= habit.targetCount
                        ? Colors.green
                        : Colors.grey,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      ],
    );
  }
}
