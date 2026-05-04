import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/habit_heatmap.dart';
import '../widgets/habit_weekly_card.dart';
import '../widgets/empty_state.dart';
import 'habit_detail_screen.dart';

class HabitScreen extends StatefulWidget {
  const HabitScreen({super.key});

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _showAddDialog() {
    final s = context.read<ThemeProvider>().brand.strings;
    final nameCtrl = TextEditingController();
    final targetCtrl = TextEditingController(text: '1');
    var selectedColor = 0xFF4CAF50;

    final colors = [0xFF4CAF50, 0xFF2196F3, 0xFFFF9800, 0xFFE91E63, 0xFF9C27B0, 0xFF00BCD4, 0xFFFF5722, 0xFF607D8B];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(s.habitCreateTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '习惯名称')),
              const SizedBox(height: 8),
              TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: '每日目标次数'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: colors.map((c) => GestureDetector(
                  onTap: () => setSt(() => selectedColor = c),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Color(c), shape: BoxShape.circle,
                      border: selectedColor == c ? Border.all(color: Colors.white, width: 3) : null,
                      boxShadow: selectedColor == c ? [BoxShadow(color: Color(c).withValues(alpha: 0.5), blurRadius: 6)] : null,
                    ),
                  ),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  context.read<HabitProvider>().addHabit(Habit(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameCtrl.text.trim(),
                        colorValue: selectedColor,
                        targetCount: int.tryParse(targetCtrl.text) ?? 1,
                      ));
                  Navigator.pop(ctx);
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HabitProvider>();
    final s = context.watch<ThemeProvider>().brand.strings;
    final activeHabits = provider.habits.where((h) => h.isActiveToday()).toList();
    final heatmapData = provider.combinedHeatmap(12);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s.habitTitle),
        bottom: TabBar(controller: _tabCtrl, tabs: [Tab(text: s.habitTabToday), Tab(text: s.habitTabHeatmap)]),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // Today check-in
          activeHabits.isEmpty
              ? EmptyState(icon: Icons.repeat, message: s.habitEmpty, actionLabel: s.habitAddAction, onAction: _showAddDialog)
              : ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 56, height: 56,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircularProgressIndicator(value: provider.todayOverallProgress, strokeWidth: 5, backgroundColor: cs.primary.withValues(alpha: 0.12)),
                                    Text('${(provider.todayOverallProgress * 100).toInt()}%',
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.primary)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${activeHabits.where((h) => h.isCompletedToday()).length} / ${activeHabits.length} ${s.habitTodayDone}',
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text('${s.habitStreakLabel} ${provider.longestCurrentStreak} 天', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const HabitWeeklyCard(),
                    ...activeHabits.map((h) => _HabitCheckinCard(habit: h)),
                  ],
                ),
          // Heatmap
          ListView(
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(s.habitHeatmapHeading, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              HabitHeatmap(heatmapData: heatmapData),
              const Divider(),
              // All habits list
              ...provider.habits.map((h) => ListTile(
                    leading: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: Color(h.colorValue).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.star, color: Color(h.colorValue), size: 18),
                    ),
                    title: Text(h.name),
                    subtitle: Text('${s.habitStreakLabel} ${h.currentStreak} 天 · 最佳 ${h.bestStreak} 天', style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: h.id))),
                  )),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
    );
  }
}

class _HabitCheckinCard extends StatelessWidget {
  final Habit habit;
  const _HabitCheckinCard({required this.habit});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<HabitProvider>();
    final progress = habit.todayProgress();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: Color(habit.colorValue).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.star, color: Color(habit.colorValue)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(habit.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      Text('目标: ${{habit.targetCount}} 次/天', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Text('连续 ${habit.currentStreak} 天', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: Colors.grey.shade200),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline, size: 22),
                  onPressed: () => provider.decrementHabit(habit.id),
                ),
                Text('${habit.todayCount()}/${habit.targetCount}',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: progress >= 1 ? Colors.green : null)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.add_circle, size: 22, color: Color(habit.colorValue)),
                  onPressed: () => provider.incrementHabit(habit.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}