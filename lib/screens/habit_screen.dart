import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/habit_heatmap.dart';
import '../widgets/habit_weekly_card.dart';
import '../widgets/empty_state.dart';
import '../core/habit_templates.dart';
import 'habit_detail_screen.dart';

class HabitScreen extends StatefulWidget {
  const HabitScreen({super.key});

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen>
    with SingleTickerProviderStateMixin {
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
    final templatesByCategory = HabitTemplates.byCategory;

    final colors = [
      0xFF4CAF50,
      0xFF2196F3,
      0xFFFF9800,
      0xFFE91E63,
      0xFF9C27B0,
      0xFF00BCD4,
      0xFFFF5722,
      0xFF607D8B,
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  s.habitCreateTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // --- Recommended Section ---
                const Text(
                  '推荐目标',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                ...templatesByCategory.entries.map((entry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: entry.value.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (ctx, i) {
                            final t = entry.value[i];
                            return ActionChip(
                              avatar: Icon(
                                t.icon,
                                size: 16,
                                color: Color(t.colorValue),
                              ),
                              label: Text(
                                t.name,
                                style: const TextStyle(fontSize: 13),
                              ),
                              backgroundColor: Color(
                                t.colorValue,
                              ).withValues(alpha: 0.05),
                              side: BorderSide(
                                color: Color(
                                  t.colorValue,
                                ).withValues(alpha: 0.2),
                              ),
                              onPressed: () {
                                setSt(() {
                                  nameCtrl.text = t.name;
                                  targetCtrl.text = t.targetCount.toString();
                                  selectedColor = t.colorValue;
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                }),

                const Divider(height: 32),

                // --- Manual Entry ---
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: '习惯名称',
                    hintText: '输入或从上方选择',
                    prefixIcon: const Icon(Icons.edit, size: 20),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: targetCtrl,
                        decoration: InputDecoration(
                          labelText: '每日目标次数',
                          prefixIcon: const Icon(Icons.track_changes, size: 20),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: colors
                            .take(4)
                            .map(
                              (c) => GestureDetector(
                                onTap: () => setSt(() => selectedColor = c),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Color(c),
                                      shape: BoxShape.circle,
                                      border: selectedColor == c
                                          ? Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            )
                                          : null,
                                      boxShadow: selectedColor == c
                                          ? [
                                              BoxShadow(
                                                color: Color(
                                                  c,
                                                ).withValues(alpha: 0.4),
                                                blurRadius: 4,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      if (nameCtrl.text.trim().isNotEmpty) {
                        context.read<HabitProvider>().addHabit(
                          Habit(
                            id: DateTime.now().millisecondsSinceEpoch
                                .toString(),
                            name: nameCtrl.text.trim(),
                            colorValue: selectedColor,
                            targetCount: int.tryParse(targetCtrl.text) ?? 1,
                          ),
                        );
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(selectedColor),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '开启新习惯',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HabitProvider>();
    final s = context.watch<ThemeProvider>().brand.strings;
    final activeHabits = provider.habits
        .where((h) => h.isActiveToday())
        .toList();
    final heatmapData = provider.combinedHeatmap(12);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s.habitTitle),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: s.habitTabToday),
            Tab(text: s.habitTabHeatmap),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // Today check-in
          activeHabits.isEmpty
              ? EmptyState(
                  icon: Icons.repeat,
                  message: s.habitEmpty,
                  actionLabel: s.habitAddAction,
                  onAction: _showAddDialog,
                )
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
                                width: 56,
                                height: 56,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      value: provider.todayOverallProgress,
                                      strokeWidth: 5,
                                      backgroundColor: cs.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                    ),
                                    Text(
                                      '${(provider.todayOverallProgress * 100).toInt()}%',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${activeHabits.where((h) => h.isCompletedToday()).length} / ${activeHabits.length} ${s.habitTodayDone}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${s.habitStreakLabel} ${provider.longestCurrentStreak} 天',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
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
                child: Text(
                  s.habitHeatmapHeading,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              HabitHeatmap(heatmapData: heatmapData),
              const Divider(),
              // All habits list
              ...provider.habits.map(
                (h) => ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(h.colorValue).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.star,
                      color: Color(h.colorValue),
                      size: 18,
                    ),
                  ),
                  title: Text(h.name),
                  subtitle: Text(
                    '${s.habitStreakLabel} ${h.currentStreak} 天 · 最佳 ${h.bestStreak} 天',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HabitDetailScreen(habitId: h.id),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
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
    final isDone = progress >= 1.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: isDone
            ? Border.all(
                color: Color(habit.colorValue).withValues(alpha: 0.3),
                width: 1.5,
              )
            : Border.all(color: Colors.transparent, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Color(habit.colorValue).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isDone ? Icons.star : Icons.star_border,
                    color: Color(habit.colorValue),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                          color: isDone ? Colors.grey : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '目标: ${habit.targetCount} 次/天',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department,
                        size: 14,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${habit.currentStreak} 天',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 8,
                        width:
                            (MediaQuery.of(context).size.width - 150) *
                            progress,
                        decoration: BoxDecoration(
                          color: isDone
                              ? const Color(0xFF4CAF50)
                              : Color(habit.colorValue),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove, size: 20),
                        onPressed: () => provider.decrementHabit(habit.id),
                        color: Colors.grey.shade600,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '${habit.todayCount()}/${habit.targetCount}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDone ? const Color(0xFF4CAF50) : null,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add, size: 20),
                        onPressed: () => provider.incrementHabit(habit.id),
                        color: isDone ? Colors.grey : Color(habit.colorValue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
