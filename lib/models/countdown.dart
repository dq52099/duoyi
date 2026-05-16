class CountdownItem {
  final String id;
  final String title;
  final DateTime targetDate;
  final bool isPinned;
  final String category;
  final bool remind;
  final int remindDaysBefore;
  final int remindHour;
  final int remindMinute;
  final DateTime updatedAt;

  CountdownItem({
    required this.id,
    required this.title,
    required this.targetDate,
    this.isPinned = false,
    this.category = '默认',
    this.remind = false,
    this.remindDaysBefore = 1,
    this.remindHour = 9,
    this.remindMinute = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  int get daysRemaining {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(targetDate.year, targetDate.month, targetDate.day);
    return target.difference(today).inDays;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'targetDate': targetDate.toIso8601String(),
    'isPinned': isPinned,
    'category': category,
    'remind': remind,
    'remindDaysBefore': remindDaysBefore,
    'remindHour': remindHour,
    'remindMinute': remindMinute,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory CountdownItem.fromJson(Map<String, dynamic> json) => CountdownItem(
    id: json['id'],
    title: json['title'],
    targetDate: DateTime.parse(json['targetDate']),
    isPinned: json['isPinned'] ?? false,
    category: json['category']?.toString() ?? '默认',
    remind: json['remind'] == true,
    remindDaysBefore: (json['remindDaysBefore'] as num?)?.toInt() ?? 1,
    remindHour: (json['remindHour'] as num?)?.toInt() ?? 9,
    remindMinute: (json['remindMinute'] as num?)?.toInt() ?? 0,
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.tryParse(json['updatedAt'].toString()),
  );

  CountdownItem copyWith({
    String? title,
    DateTime? targetDate,
    bool? isPinned,
    String? category,
    bool? remind,
    int? remindDaysBefore,
    int? remindHour,
    int? remindMinute,
  }) {
    return CountdownItem(
      id: id,
      title: title ?? this.title,
      targetDate: targetDate ?? this.targetDate,
      isPinned: isPinned ?? this.isPinned,
      category: category ?? this.category,
      remind: remind ?? this.remind,
      remindDaysBefore: remindDaysBefore ?? this.remindDaysBefore,
      remindHour: remindHour ?? this.remindHour,
      remindMinute: remindMinute ?? this.remindMinute,
      updatedAt: DateTime.now(),
    );
  }
}
