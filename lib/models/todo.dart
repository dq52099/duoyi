import 'package:uuid/uuid.dart';
import 'recurrence.dart';

const uuid = Uuid();

enum EisenhowerQuadrant {
  urgentImportant, // Q1 - red: Do First
  notUrgentImportant, // Q2 - blue: Schedule
  urgentNotImportant, // Q3 - yellow: Delegate
  notUrgentNotImportant, // Q4 - grey: Eliminate
}

/// 优先级(独立于四象限，可组合使用)。
enum TodoPriority { none, low, medium, high, urgent }

extension TodoPriorityX on TodoPriority {
  String get label => switch (this) {
        TodoPriority.none => '无',
        TodoPriority.low => '低',
        TodoPriority.medium => '中',
        TodoPriority.high => '高',
        TodoPriority.urgent => '紧急',
      };

  int get rank => switch (this) {
        TodoPriority.none => 0,
        TodoPriority.low => 1,
        TodoPriority.medium => 2,
        TodoPriority.high => 3,
        TodoPriority.urgent => 4,
      };
}

class Subtask {
  String id;
  String title;
  bool isCompleted;
  int sortOrder;

  Subtask({
    String? id,
    required this.title,
    this.isCompleted = false,
    this.sortOrder = 0,
  }) : id = id ?? uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        'sortOrder': sortOrder,
      };

  factory Subtask.fromJson(Map<String, dynamic> json) => Subtask(
        id: json['id'],
        title: json['title'],
        isCompleted: json['isCompleted'] ?? false,
        sortOrder: json['sortOrder'] ?? 0,
      );
}

class TodoItem {
  final String id;
  String title;
  String notes;
  bool isCompleted;
  EisenhowerQuadrant quadrant;
  TodoPriority priority;
  String? listGroupId;
  String? listGroupName;
  List<String> tags;
  DateTime? dueDate;
  DateTime date;
  bool hasReminder;
  DateTime? reminderAt;
  List<Subtask> subtasks;
  int sortOrder;
  RecurrenceRule recurrence;
  DateTime? completedAt;
  DateTime createdAt;
  DateTime updatedAt;

  TodoItem({
    String? id,
    required this.title,
    this.notes = '',
    this.isCompleted = false,
    this.quadrant = EisenhowerQuadrant.notUrgentImportant,
    this.priority = TodoPriority.none,
    this.listGroupId,
    this.listGroupName,
    List<String>? tags,
    this.dueDate,
    DateTime? date,
    this.hasReminder = false,
    this.reminderAt,
    List<Subtask>? subtasks,
    this.sortOrder = 0,
    RecurrenceRule? recurrence,
    this.completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? uuid.v4(),
        date = date ?? DateTime.now(),
        tags = tags ?? [],
        subtasks = subtasks ?? [],
        recurrence = recurrence ?? const RecurrenceRule(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'isCompleted': isCompleted,
        'quadrant': quadrant.index,
        'priority': priority.index,
        'listGroupId': listGroupId,
        'listGroupName': listGroupName,
        'tags': tags,
        'dueDate': dueDate?.toIso8601String(),
        'date': date.toIso8601String(),
        'hasReminder': hasReminder,
        'reminderAt': reminderAt?.toIso8601String(),
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
        'sortOrder': sortOrder,
        'recurrence': recurrence.toJson(),
        'completedAt': completedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
        id: json['id'],
        title: json['title'],
        notes: json['notes'] ?? '',
        isCompleted: json['isCompleted'] ?? false,
        quadrant: EisenhowerQuadrant.values[json['quadrant'] ?? 1],
        priority: TodoPriority.values[json['priority'] ?? 0],
        listGroupId: json['listGroupId'],
        listGroupName: json['listGroupName'],
        tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
        dueDate:
            json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
        date: DateTime.parse(json['date']),
        hasReminder: json['hasReminder'] ?? false,
        reminderAt: json['reminderAt'] != null
            ? DateTime.tryParse(json['reminderAt'])
            : null,
        subtasks: (json['subtasks'] as List<dynamic>?)
                ?.map((s) => Subtask.fromJson(s))
                .toList() ??
            [],
        sortOrder: json['sortOrder'] ?? 0,
        recurrence: RecurrenceRule.fromJson(
            json['recurrence'] as Map<String, dynamic>?),
        completedAt: json['completedAt'] != null
            ? DateTime.tryParse(json['completedAt'])
            : null,
        createdAt: DateTime.parse(json['createdAt']),
        updatedAt: DateTime.parse(json['updatedAt']),
      );

  TodoItem copyWith({
    String? title,
    String? notes,
    bool? isCompleted,
    EisenhowerQuadrant? quadrant,
    TodoPriority? priority,
    String? listGroupId,
    String? listGroupName,
    List<String>? tags,
    DateTime? dueDate,
    DateTime? date,
    bool? hasReminder,
    DateTime? reminderAt,
    List<Subtask>? subtasks,
    int? sortOrder,
    RecurrenceRule? recurrence,
    DateTime? completedAt,
  }) =>
      TodoItem(
        id: id,
        title: title ?? this.title,
        notes: notes ?? this.notes,
        isCompleted: isCompleted ?? this.isCompleted,
        quadrant: quadrant ?? this.quadrant,
        priority: priority ?? this.priority,
        listGroupId: listGroupId ?? this.listGroupId,
        listGroupName: listGroupName ?? this.listGroupName,
        tags: tags ?? this.tags,
        dueDate: dueDate ?? this.dueDate,
        date: date ?? this.date,
        hasReminder: hasReminder ?? this.hasReminder,
        reminderAt: reminderAt ?? this.reminderAt,
        subtasks: subtasks ?? this.subtasks,
        sortOrder: sortOrder ?? this.sortOrder,
        recurrence: recurrence ?? this.recurrence,
        completedAt: completedAt ?? this.completedAt,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  double get subtaskProgress => subtasks.isEmpty
      ? 0.0
      : subtasks.where((s) => s.isCompleted).length / subtasks.length;

  bool get isOverdue =>
      !isCompleted &&
      dueDate != null &&
      dueDate!.isBefore(DateTime.now());
}
