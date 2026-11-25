import 'goal.dart' show ReminderKind;

int _readInt(Object? value, int fallback, {int? min, int? max}) {
  var parsed = value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '') ?? fallback;
  if (min != null && parsed < min) parsed = min;
  if (max != null && parsed > max) parsed = max;
  return parsed;
}

String _readText(Object? value, String fallback) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

DateTime _readDate(Object? value, DateTime fallback) {
  return DateTime.tryParse(value?.toString() ?? '') ?? fallback;
}

class CountdownItem {
  // Stable storage value; only the presentation of generated defaults localizes.
  static const defaultCategory = '默认';
  final String id;
  final String title;
  final DateTime targetDate;
  final bool isPinned;
  final String category;
  final bool categoryIsDefault;
  final bool remind;
  final int remindDaysBefore;
  final int remindHour;
  final int remindMinute;
  final ReminderKind reminderKind;
  final DateTime updatedAt;

  CountdownItem({
    required this.id,
    required this.title,
    required this.targetDate,
    this.isPinned = false,
    String? category,
    bool? categoryIsDefault,
    this.remind = false,
    this.remindDaysBefore = 1,
    this.remindHour = 9,
    this.remindMinute = 0,
    this.reminderKind = ReminderKind.push,
    DateTime? updatedAt,
  }) : categoryIsDefault =
           categoryIsDefault == true || (category?.trim().isEmpty ?? true),
       category =
           categoryIsDefault == true || (category?.trim().isEmpty ?? true)
           ? defaultCategory
           : category!,
       updatedAt = updatedAt ?? DateTime.now();

  int get daysRemaining => daysRemainingForDate(DateTime.now());

  int daysRemainingForDate(DateTime date) {
    final today = DateTime.utc(date.year, date.month, date.day);
    final target = DateTime.utc(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    return target.difference(today).inDays;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'targetDate': targetDate.toIso8601String(),
    'isPinned': isPinned,
    'category': category,
    'categoryIsDefault': categoryIsDefault,
    'remind': remind,
    'remindDaysBefore': remindDaysBefore,
    'remindHour': remindHour,
    'remindMinute': remindMinute,
    'reminderKind': reminderKind.index,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory CountdownItem.fromJson(Map<String, dynamic> json) {
    final fallbackDate = DateTime.now().add(const Duration(days: 1));
    final targetDate = _readDate(
      json['targetDate'] ?? json['date'] ?? json['originDate'],
      fallbackDate,
    );
    final reminderKind = _reminderKindFromJson(json['reminderKind']);
    return CountdownItem(
      id: _readText(
        json['id'],
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
      title: _readText(json['title'] ?? json['name'], '未命名倒数日'),
      targetDate: targetDate,
      isPinned: json['isPinned'] == true,
      // Nonempty legacy strings are authored unless explicitly marked.
      category: json['category']?.toString().trim(),
      categoryIsDefault: json['categoryIsDefault'] == true,
      remind: json['remind'] == true && reminderKind != ReminderKind.off,
      remindDaysBefore: _readInt(
        json['remindDaysBefore'],
        1,
        min: 0,
        max: 3650,
      ),
      remindHour: _readInt(json['remindHour'], 9, min: 0, max: 23),
      remindMinute: _readInt(json['remindMinute'], 0, min: 0, max: 59),
      reminderKind: reminderKind,
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  CountdownItem copyWith({
    String? title,
    DateTime? targetDate,
    bool? isPinned,
    String? category,
    bool? categoryIsDefault,
    bool? remind,
    int? remindDaysBefore,
    int? remindHour,
    int? remindMinute,
    ReminderKind? reminderKind,
  }) {
    final nextKind = reminderKind ?? this.reminderKind;
    return CountdownItem(
      id: id,
      title: title ?? this.title,
      targetDate: targetDate ?? this.targetDate,
      isPinned: isPinned ?? this.isPinned,
      category: category ?? this.category,
      categoryIsDefault:
          categoryIsDefault ??
          (category == null ? this.categoryIsDefault : null),
      remind: (remind ?? this.remind) && nextKind != ReminderKind.off,
      remindDaysBefore: remindDaysBefore ?? this.remindDaysBefore,
      remindHour: remindHour ?? this.remindHour,
      remindMinute: remindMinute ?? this.remindMinute,
      reminderKind: nextKind,
      updatedAt: DateTime.now(),
    );
  }
}

ReminderKind _reminderKindFromJson(Object? raw) {
  if (raw is num) {
    final index = raw.toInt();
    if (index >= 0 && index < ReminderKind.values.length) {
      return ReminderKind.values[index];
    }
  }
  if (raw is String) {
    for (final kind in ReminderKind.values) {
      if (kind.name == raw) return kind;
    }
  }
  return ReminderKind.push;
}
