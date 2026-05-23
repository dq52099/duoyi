import 'package:uuid/uuid.dart';

import 'goal.dart'
    show ReminderKind, ReminderPlan, ReminderRule, ReminderRuleType;
import 'habit.dart';
import 'todo.dart';
import '../core/smart_todo_draft.dart';

const _quickTemplateUuid = Uuid();

enum QuickCaptureTemplateKind { todo, habit }

class QuickCaptureTemplate {
  final String id;
  final String name;
  final QuickCaptureTemplateKind kind;
  final String titlePrefix;
  final List<String> tags;
  final TodoPriority priority;
  final EisenhowerQuadrant quadrant;
  final String? listGroupName;
  final ReminderPlan reminderPlan;
  final HabitKind habitKind;
  final String? habitCategory;
  final int habitTargetCount;
  final String? habitUnit;
  final List<int> habitActiveWeekdays;
  final int habitColorValue;
  final bool habitRemind;
  final int? habitRemindHour;
  final int? habitRemindMinute;
  final bool builtIn;
  final DateTime createdAt;
  final DateTime updatedAt;

  QuickCaptureTemplate({
    String? id,
    required this.name,
    required this.kind,
    this.titlePrefix = '',
    List<String>? tags,
    this.priority = TodoPriority.none,
    this.quadrant = EisenhowerQuadrant.notUrgentImportant,
    this.listGroupName,
    ReminderPlan? reminderPlan,
    this.habitKind = HabitKind.positive,
    this.habitCategory,
    int habitTargetCount = 1,
    this.habitUnit,
    List<int>? habitActiveWeekdays,
    this.habitColorValue = 0xFF4CAF50,
    this.habitRemind = false,
    this.habitRemindHour,
    this.habitRemindMinute,
    this.builtIn = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? _quickTemplateUuid.v4(),
       tags = List<String>.unmodifiable(_normalizedTags(tags ?? const [])),
       reminderPlan = reminderPlan ?? const ReminderPlan.disabled(),
       habitTargetCount = habitTargetCount < 1 ? 1 : habitTargetCount,
       habitActiveWeekdays = List<int>.unmodifiable(
         (habitActiveWeekdays ?? const [0, 1, 2, 3, 4, 5, 6]).where(
           (day) => day >= 0 && day <= 6,
         ),
       ),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  static List<QuickCaptureTemplate> builtIns() => [
    QuickCaptureTemplate(
      id: 'builtin-work-meeting',
      name: '工作会议',
      kind: QuickCaptureTemplateKind.todo,
      titlePrefix: '会议',
      tags: const ['会议', '工作'],
      priority: TodoPriority.high,
      listGroupName: '工作',
      reminderPlan: ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'builtin-work-meeting-before-15',
            type: ReminderRuleType.relativeToDue,
            kind: ReminderKind.push,
            offsetMinutes: -15,
          ),
        ],
      ),
      builtIn: true,
    ),
    QuickCaptureTemplate(
      id: 'builtin-shopping',
      name: '购物清单',
      kind: QuickCaptureTemplateKind.todo,
      tags: const ['购物'],
      priority: TodoPriority.medium,
      listGroupName: '购物',
      builtIn: true,
    ),
    QuickCaptureTemplate(
      id: 'builtin-reading-habit',
      name: '每日阅读',
      kind: QuickCaptureTemplateKind.habit,
      titlePrefix: '每日阅读',
      habitCategory: '学习提升',
      habitTargetCount: 30,
      habitUnit: '分钟',
      habitColorValue: 0xFF7E57C2,
      habitRemind: true,
      habitRemindHour: 21,
      habitRemindMinute: 0,
      builtIn: true,
    ),
  ];

  String get displayTitlePrefix => titlePrefix.trim();

  String previewSummary() {
    if (kind == QuickCaptureTemplateKind.habit) {
      final unit = habitUnit == null || habitUnit!.isEmpty ? '次' : habitUnit!;
      final reminder = habitRemind && habitRemindHour != null
          ? ' · ${habitRemindHour!.toString().padLeft(2, '0')}:${(habitRemindMinute ?? 0).toString().padLeft(2, '0')}'
          : '';
      final category = habitCategory == null || habitCategory!.isEmpty
          ? ''
          : ' · $habitCategory';
      return '习惯 · $habitTargetCount$unit$category$reminder';
    }
    final parts = <String>[
      if (listGroupName != null && listGroupName!.trim().isNotEmpty)
        listGroupName!.trim(),
      if (priority != TodoPriority.none) priority.label,
      if (tags.isNotEmpty) tags.map((tag) => '#$tag').join(' '),
      if (reminderPlan.enabled && reminderPlan.rules.isNotEmpty) '含提醒',
    ];
    return parts.isEmpty ? '待办模板' : parts.join(' · ');
  }

  TodoItem toTodo(String input) {
    final merged = _mergeTitle(input);
    final draft = SmartTodoDraftBuilder.fromText(merged);
    final todo = draft.toTodo(
      quadrant: quadrant,
      priority: priority,
      listGroupName: _emptyToNull(listGroupName),
    );
    final effectiveReminderPlan = reminderPlan.enabled
        ? reminderPlan
        : todo.reminderPlan;
    final effectiveReminder = effectiveReminderPlan.toLegacyReminderConfig(
      fallback: todo.reminder,
    );
    return todo.copyWith(
      tags: tags,
      reminderPlan: effectiveReminderPlan,
      reminder: effectiveReminder,
      hasReminder: effectiveReminderPlan.enabled,
    );
  }

  Habit toHabit(String input) {
    final name = _mergeTitle(input).trim();
    final reminderEnabled =
        habitRemind && habitRemindHour != null && habitRemindMinute != null;
    return Habit(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.isEmpty ? titlePrefix.trim() : name,
      kind: habitKind,
      category: _emptyToNull(habitCategory),
      tags: tags,
      targetCount: habitTargetCount,
      unit: _emptyToNull(habitUnit),
      activeWeekdays: habitActiveWeekdays,
      colorValue: habitColorValue,
      remind: reminderEnabled,
      remindHour: reminderEnabled ? habitRemindHour : null,
      remindMinute: reminderEnabled ? habitRemindMinute : null,
    );
  }

  QuickCaptureTemplate copyWith({
    String? id,
    String? name,
    QuickCaptureTemplateKind? kind,
    String? titlePrefix,
    List<String>? tags,
    TodoPriority? priority,
    EisenhowerQuadrant? quadrant,
    String? listGroupName,
    ReminderPlan? reminderPlan,
    HabitKind? habitKind,
    String? habitCategory,
    int? habitTargetCount,
    String? habitUnit,
    List<int>? habitActiveWeekdays,
    int? habitColorValue,
    bool? habitRemind,
    int? habitRemindHour,
    int? habitRemindMinute,
    bool? builtIn,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return QuickCaptureTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      titlePrefix: titlePrefix ?? this.titlePrefix,
      tags: tags ?? this.tags,
      priority: priority ?? this.priority,
      quadrant: quadrant ?? this.quadrant,
      listGroupName: listGroupName ?? this.listGroupName,
      reminderPlan: reminderPlan ?? this.reminderPlan,
      habitKind: habitKind ?? this.habitKind,
      habitCategory: habitCategory ?? this.habitCategory,
      habitTargetCount: habitTargetCount ?? this.habitTargetCount,
      habitUnit: habitUnit ?? this.habitUnit,
      habitActiveWeekdays: habitActiveWeekdays ?? this.habitActiveWeekdays,
      habitColorValue: habitColorValue ?? this.habitColorValue,
      habitRemind: habitRemind ?? this.habitRemind,
      habitRemindHour: habitRemindHour ?? this.habitRemindHour,
      habitRemindMinute: habitRemindMinute ?? this.habitRemindMinute,
      builtIn: builtIn ?? this.builtIn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.index,
    'titlePrefix': titlePrefix,
    'tags': tags,
    'priority': priority.index,
    'quadrant': quadrant.index,
    'listGroupName': listGroupName,
    'reminderPlan': reminderPlan.toJson(),
    'habitKind': habitKind.index,
    'habitCategory': habitCategory,
    'habitTargetCount': habitTargetCount,
    'habitUnit': habitUnit,
    'habitActiveWeekdays': habitActiveWeekdays,
    'habitColorValue': habitColorValue,
    'habitRemind': habitRemind,
    'habitRemindHour': habitRemindHour,
    'habitRemindMinute': habitRemindMinute,
    'builtIn': builtIn,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory QuickCaptureTemplate.fromJson(Map<String, dynamic> json) {
    return QuickCaptureTemplate(
      id: json['id']?.toString(),
      name: json['name']?.toString() ?? '快捷模板',
      kind: _enumFromIndex(
        QuickCaptureTemplateKind.values,
        (json['kind'] as num?)?.toInt(),
        QuickCaptureTemplateKind.todo,
      ),
      titlePrefix: json['titlePrefix']?.toString() ?? '',
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList(),
      priority: _enumFromIndex(
        TodoPriority.values,
        (json['priority'] as num?)?.toInt(),
        TodoPriority.none,
      ),
      quadrant: _enumFromIndex(
        EisenhowerQuadrant.values,
        (json['quadrant'] as num?)?.toInt(),
        EisenhowerQuadrant.notUrgentImportant,
      ),
      listGroupName: json['listGroupName']?.toString(),
      reminderPlan: json['reminderPlan'] is Map
          ? ReminderPlan.fromJson(
              Map<String, dynamic>.from(json['reminderPlan'] as Map),
            )
          : const ReminderPlan.disabled(),
      habitKind: _enumFromIndex(
        HabitKind.values,
        (json['habitKind'] as num?)?.toInt(),
        HabitKind.positive,
      ),
      habitCategory: json['habitCategory']?.toString(),
      habitTargetCount: (json['habitTargetCount'] as num?)?.toInt() ?? 1,
      habitUnit: json['habitUnit']?.toString(),
      habitActiveWeekdays: (json['habitActiveWeekdays'] as List?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      habitColorValue: (json['habitColorValue'] as num?)?.toInt() ?? 0xFF4CAF50,
      habitRemind: json['habitRemind'] == true,
      habitRemindHour: (json['habitRemindHour'] as num?)?.toInt(),
      habitRemindMinute: (json['habitRemindMinute'] as num?)?.toInt(),
      builtIn: json['builtIn'] == true,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  String _mergeTitle(String input) {
    final prefix = titlePrefix.trim();
    final body = input.trim();
    if (prefix.isEmpty) return body;
    if (body.isEmpty || body == prefix) return prefix;
    return '$prefix $body';
  }
}

T _enumFromIndex<T>(List<T> values, int? index, T fallback) {
  if (index == null || index < 0 || index >= values.length) return fallback;
  return values[index];
}

List<String> _normalizedTags(Iterable<String> tags) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in tags) {
    final tag = raw.trim().replaceFirst(RegExp(r'^#'), '');
    if (tag.isEmpty || seen.contains(tag)) continue;
    seen.add(tag);
    out.add(tag);
  }
  return out;
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
