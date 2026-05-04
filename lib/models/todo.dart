import 'package:uuid/uuid.dart';

const uuid = Uuid();

enum EisenhowerQuadrant {
  urgentImportant,      // Q1 - red: Do First
  notUrgentImportant,   // Q2 - blue: Schedule
  urgentNotImportant,   // Q3 - yellow: Delegate
  notUrgentNotImportant // Q4 - grey: Eliminate
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
  String? listGroupId;
  String? listGroupName;
  DateTime? dueDate;
  DateTime date;
  bool hasReminder;
  List<Subtask> subtasks;
  int sortOrder;
  DateTime createdAt;
  DateTime updatedAt;

  TodoItem({
    String? id,
    required this.title,
    this.notes = '',
    this.isCompleted = false,
    this.quadrant = EisenhowerQuadrant.notUrgentImportant,
    this.listGroupId,
    this.listGroupName,
    this.dueDate,
    DateTime? date,
    this.hasReminder = false,
    List<Subtask>? subtasks,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? uuid.v4(),
        date = date ?? DateTime.now(),
        subtasks = subtasks ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'isCompleted': isCompleted,
        'quadrant': quadrant.index,
        'listGroupId': listGroupId,
        'listGroupName': listGroupName,
        'dueDate': dueDate?.toIso8601String(),
        'date': date.toIso8601String(),
        'hasReminder': hasReminder,
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
        'sortOrder': sortOrder,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
        id: json['id'],
        title: json['title'],
        notes: json['notes'] ?? '',
        isCompleted: json['isCompleted'] ?? false,
        quadrant: EisenhowerQuadrant.values[json['quadrant'] ?? 1],
        listGroupId: json['listGroupId'],
        listGroupName: json['listGroupName'],
        dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
        date: DateTime.parse(json['date']),
        hasReminder: json['hasReminder'] ?? false,
        subtasks: (json['subtasks'] as List<dynamic>?)
                ?.map((s) => Subtask.fromJson(s))
                .toList() ??
            [],
        sortOrder: json['sortOrder'] ?? 0,
        createdAt: DateTime.parse(json['createdAt']),
        updatedAt: DateTime.parse(json['updatedAt']),
      );

  TodoItem copyWith({
    String? title,
    String? notes,
    bool? isCompleted,
    EisenhowerQuadrant? quadrant,
    String? listGroupId,
    String? listGroupName,
    DateTime? dueDate,
    DateTime? date,
    bool? hasReminder,
    List<Subtask>? subtasks,
    int? sortOrder,
  }) =>
      TodoItem(
        id: id,
        title: title ?? this.title,
        notes: notes ?? this.notes,
        isCompleted: isCompleted ?? this.isCompleted,
        quadrant: quadrant ?? this.quadrant,
        listGroupId: listGroupId ?? this.listGroupId,
        listGroupName: listGroupName ?? this.listGroupName,
        dueDate: dueDate ?? this.dueDate,
        date: date ?? this.date,
        hasReminder: hasReminder ?? this.hasReminder,
        subtasks: subtasks ?? this.subtasks,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  double get subtaskProgress =>
      subtasks.isEmpty ? 0.0 : subtasks.where((s) => s.isCompleted).length / subtasks.length;
}