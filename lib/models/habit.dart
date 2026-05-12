/// 习惯类型：正向=养成；负向=戒除 (记录"今天没做到")。
enum HabitKind { positive, negative }

int _readInt(Object? value, int fallback) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

class Habit {
  final String id;
  String name;
  String icon;
  int colorValue;
  HabitKind kind;
  List<int> activeWeekdays;
  int targetCount;
  String? unit; // 计量单位，如 '次/杯/分钟'
  int currentStreak;
  int bestStreak;
  Map<String, int> completions;
  String? category;
  List<String> tags;
  int weeklyTarget;
  DateTime? startDate;
  DateTime? endDate;
  int sortOrder;
  bool remind;
  int? remindHour;
  int? remindMinute;
  DateTime createdAt;

  Habit({
    required this.id,
    required this.name,
    this.icon = 'star',
    this.colorValue = 0xFF4CAF50,
    this.kind = HabitKind.positive,
    List<int>? activeWeekdays,
    this.targetCount = 1,
    this.unit,
    this.currentStreak = 0,
    this.bestStreak = 0,
    Map<String, int>? completions,
    this.category,
    List<String>? tags,
    this.weeklyTarget = 7,
    this.startDate,
    this.endDate,
    this.sortOrder = 0,
    this.remind = false,
    this.remindHour,
    this.remindMinute,
    DateTime? createdAt,
  }) : activeWeekdays = activeWeekdays ?? [0, 1, 2, 3, 4, 5, 6],
       completions = completions ?? {},
       tags = tags ?? [],
       createdAt = createdAt ?? DateTime.now();

  Habit copyWith({
    String? name,
    String? icon,
    int? colorValue,
    HabitKind? kind,
    List<int>? activeWeekdays,
    int? targetCount,
    String? unit,
    int? currentStreak,
    int? bestStreak,
    Map<String, int>? completions,
    String? category,
    List<String>? tags,
    int? weeklyTarget,
    DateTime? startDate,
    DateTime? endDate,
    int? sortOrder,
    bool? remind,
    int? remindHour,
    int? remindMinute,
    DateTime? createdAt,
  }) {
    return Habit(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      colorValue: colorValue ?? this.colorValue,
      kind: kind ?? this.kind,
      activeWeekdays: activeWeekdays ?? List<int>.from(this.activeWeekdays),
      targetCount: targetCount ?? this.targetCount,
      unit: unit ?? this.unit,
      currentStreak: currentStreak ?? this.currentStreak,
      bestStreak: bestStreak ?? this.bestStreak,
      completions: completions != null
          ? Map<String, int>.from(completions)
          : Map<String, int>.from(this.completions),
      category: category ?? this.category,
      tags: tags ?? List<String>.from(this.tags),
      weeklyTarget: weeklyTarget ?? this.weeklyTarget,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      sortOrder: sortOrder ?? this.sortOrder,
      remind: remind ?? this.remind,
      remindHour: remindHour ?? this.remindHour,
      remindMinute: remindMinute ?? this.remindMinute,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'colorValue': colorValue,
    'kind': kind.index,
    'activeWeekdays': activeWeekdays,
    'targetCount': targetCount,
    'unit': unit,
    'currentStreak': currentStreak,
    'bestStreak': bestStreak,
    'completions': completions,
    'category': category,
    'tags': tags,
    'weeklyTarget': weeklyTarget,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'sortOrder': sortOrder,
    'remind': remind,
    'remindHour': remindHour,
    'remindMinute': remindMinute,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Habit.fromJson(Map<String, dynamic> json) {
    final kindIndex = _readInt(json['kind'], 0);
    final weekdaysRaw = json['activeWeekdays'] as List<dynamic>?;
    final completionsRaw = json['completions'];
    final createdAtRaw = json['createdAt']?.toString();
    final target = _readInt(json['targetCount'], 1);

    return Habit(
      id: (json['id'] ?? DateTime.now().microsecondsSinceEpoch).toString(),
      name: (json['name'] ?? '未命名习惯').toString(),
      icon: (json['icon'] ?? 'star').toString(),
      colorValue: _readInt(json['colorValue'], 0xFF4CAF50),
      kind: HabitKind
          .values[kindIndex.clamp(0, HabitKind.values.length - 1).toInt()],
      activeWeekdays:
          weekdaysRaw
              ?.map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
              .whereType<int>()
              .where((e) => e >= 0 && e <= 6)
              .toList() ??
          [0, 1, 2, 3, 4, 5, 6],
      targetCount: target < 1 ? 1 : target,
      unit: json['unit']?.toString(),
      currentStreak: _readInt(json['currentStreak'], 0),
      bestStreak: _readInt(json['bestStreak'], 0),
      completions: completionsRaw is Map
          ? completionsRaw.map((key, value) {
              final count = _readInt(value, 0);
              return MapEntry(key.toString(), count < 0 ? 0 : count);
            })
          : {},
      category: json['category']?.toString(),
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          [],
      weeklyTarget: _readInt(json['weeklyTarget'], 7),
      startDate: json['startDate'] != null
          ? DateTime.tryParse(json['startDate'].toString())
          : null,
      endDate: json['endDate'] != null
          ? DateTime.tryParse(json['endDate'].toString())
          : null,
      sortOrder: _readInt(json['sortOrder'], 0),
      remind: json['remind'] == true,
      remindHour: json['remindHour'] == null
          ? null
          : _readInt(json['remindHour'], 0).clamp(0, 23).toInt(),
      remindMinute: json['remindMinute'] == null
          ? null
          : _readInt(json['remindMinute'], 0).clamp(0, 59).toInt(),
      createdAt: createdAtRaw == null
          ? DateTime.now()
          : DateTime.tryParse(createdAtRaw) ?? DateTime.now(),
    );
  }

  int todayCount() => completions[todayKey()] ?? 0;
  double todayProgress() =>
      targetCount > 0 ? (todayCount() / targetCount).clamp(0.0, 1.0) : 0.0;

  String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String todayKey() => dateKey(DateTime.now());

  int countForDate(DateTime d) => completions[dateKey(d)] ?? 0;
  double progressForDate(DateTime d) =>
      targetCount > 0 ? (countForDate(d) / targetCount).clamp(0.0, 1.0) : 0.0;

  /// 正向习惯：今日完成 >= 目标即"达标"；
  /// 负向习惯：今日为零即"戒除成功"。
  bool isCompletedToday() => kind == HabitKind.positive
      ? todayCount() >= targetCount
      : todayCount() == 0;

  bool isCompletedForDate(DateTime d) => kind == HabitKind.positive
      ? countForDate(d) >= targetCount
      : countForDate(d) == 0;

  bool isActiveToday() => activeWeekdays.contains(DateTime.now().weekday - 1);

  /// 本地格式显示：  "2 杯 / 8 杯"
  String formatCountForDate(DateTime d) {
    final c = countForDate(d);
    final u = unit ?? '次';
    return kind == HabitKind.positive
        ? '$c $u / $targetCount $u'
        : '$c $u'; // 负向只显示实际次数
  }

  Map<String, int> heatmapData(int weeks) {
    final data = <String, int>{};
    final now = DateTime.now();
    final safeTarget = targetCount < 1 ? 1 : targetCount;
    for (int w = 0; w < weeks; w++) {
      for (int d = 0; d < 7; d++) {
        final date = now.subtract(Duration(days: w * 7 + (6 - d)));
        final key = dateKey(date);
        final count = completions[key] ?? 0;
        if (kind == HabitKind.positive) {
          if (count > 0) {
            data[key] = ((count / safeTarget) * 5).ceil().clamp(1, 5);
          } else {
            data[key] = 0;
          }
        } else {
          // 负向：0 = 成功(满格)；>0 = 破戒
          data[key] = count == 0 ? 5 : 0;
        }
      }
    }
    return data;
  }

  int completionCountInRange(DateTime start, DateTime end) {
    int count = 0;
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      if (kind == HabitKind.positive
          ? countForDate(d) > 0
          : countForDate(d) == 0) {
        count++;
      }
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
