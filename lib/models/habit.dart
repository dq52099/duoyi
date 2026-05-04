class Habit {
  final String id;
  String name;
  String icon;
  int colorValue;
  List<int> activeWeekdays;
  int targetCount;
  int currentStreak;
  int bestStreak;
  Map<String, int> completions;
  String? category;
  int weeklyTarget;
  DateTime? startDate;
  DateTime? endDate;
  int sortOrder;
  DateTime createdAt;

  Habit({
    required this.id,
    required this.name,
    this.icon = 'star',
    this.colorValue = 0xFF4CAF50,
    List<int>? activeWeekdays,
    this.targetCount = 1,
    this.currentStreak = 0,
    this.bestStreak = 0,
    Map<String, int>? completions,
    this.category,
    this.weeklyTarget = 7,
    this.startDate,
    this.endDate,
    this.sortOrder = 0,
    DateTime? createdAt,
  })  : activeWeekdays = activeWeekdays ?? [0, 1, 2, 3, 4, 5, 6],
        completions = completions ?? {},
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'colorValue': colorValue,
        'activeWeekdays': activeWeekdays,
        'targetCount': targetCount,
        'currentStreak': currentStreak,
        'bestStreak': bestStreak,
        'completions': completions,
        'category': category,
        'weeklyTarget': weeklyTarget,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'sortOrder': sortOrder,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
        id: json['id'],
        name: json['name'],
        icon: json['icon'] ?? 'star',
        colorValue: json['colorValue'] ?? 0xFF4CAF50,
        activeWeekdays: List<int>.from(json['activeWeekdays'] ?? [0, 1, 2, 3, 4, 5, 6]),
        targetCount: json['targetCount'] ?? 1,
        currentStreak: json['currentStreak'] ?? 0,
        bestStreak: json['bestStreak'] ?? 0,
        completions: json['completions'] != null
            ? Map<String, int>.from(json['completions'])
            : {},
        category: json['category'],
        weeklyTarget: json['weeklyTarget'] ?? 7,
        startDate: json['startDate'] != null ? DateTime.parse(json['startDate']) : null,
        endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
        sortOrder: json['sortOrder'] ?? 0,
        createdAt: DateTime.parse(json['createdAt']),
      );

  int todayCount() => completions[todayKey()] ?? 0;
  double todayProgress() =>
      targetCount > 0 ? (todayCount() / targetCount).clamp(0.0, 1.0) : 0.0;

  String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String todayKey() => dateKey(DateTime.now());

  int countForDate(DateTime d) => completions[dateKey(d)] ?? 0;
  double progressForDate(DateTime d) =>
      targetCount > 0 ? (countForDate(d) / targetCount).clamp(0.0, 1.0) : 0.0;

  bool isCompletedToday() => todayCount() >= targetCount;
  bool isActiveToday() => activeWeekdays.contains(DateTime.now().weekday - 1);

  /// Returns heatmap data as map of dateKey -> intensity 0-5
  Map<String, int> heatmapData(int weeks) {
    final data = <String, int>{};
    final now = DateTime.now();
    for (int w = 0; w < weeks; w++) {
      for (int d = 0; d < 7; d++) {
        final date = now.subtract(Duration(days: w * 7 + (6 - d)));
        final key = dateKey(date);
        final count = completions[key] ?? 0;
        if (count > 0) {
          data[key] = ((count / targetCount) * 5).ceil().clamp(1, 5);
        } else {
          data[key] = 0;
        }
      }
    }
    return data;
  }

  int completionCountInRange(DateTime start, DateTime end) {
    int count = 0;
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      count += countForDate(d) > 0 ? 1 : 0;
    }
    return count;
  }

  double weeklyCompletionRate() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final completed = completionCountInRange(monday, now);
    final expected = now.weekday;
    return expected > 0 ? completed / expected : 0;
  }
}