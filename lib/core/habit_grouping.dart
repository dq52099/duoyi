import '../models/habit.dart';

const String defaultHabitCategoryName = '未分组';

String normalizeHabitCategory(String? category) {
  final value = category?.trim();
  if (value == null || value.isEmpty) return defaultHabitCategoryName;
  return value;
}

String? habitCategoryOrNull(String? category) {
  final normalized = normalizeHabitCategory(category);
  return normalized == defaultHabitCategoryName ? null : normalized;
}

class HabitGroup {
  final String category;
  final List<Habit> habits;

  const HabitGroup({required this.category, required this.habits});

  int get completedTodayCount =>
      habits.where((habit) => habit.isCompletedToday()).length;
}

List<HabitGroup> groupHabitsByCategory(Iterable<Habit> habits) {
  final grouped = <String, List<Habit>>{};
  for (final habit in habits) {
    final category = normalizeHabitCategory(habit.category);
    grouped.putIfAbsent(category, () => <Habit>[]).add(habit);
  }
  return [
    for (final entry in grouped.entries)
      HabitGroup(category: entry.key, habits: List.unmodifiable(entry.value)),
  ];
}
