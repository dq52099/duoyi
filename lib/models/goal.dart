import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// 目标里程碑
class GoalMilestone {
  String id;
  String title;
  bool isCompleted;
  DateTime? completedAt;

  GoalMilestone({
    String? id,
    required this.title,
    this.isCompleted = false,
    this.completedAt,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        'completedAt': completedAt?.toIso8601String(),
      };

  factory GoalMilestone.fromJson(Map<String, dynamic> json) => GoalMilestone(
        id: json['id'],
        title: json['title'] ?? '',
        isCompleted: json['isCompleted'] ?? false,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'])
            : null,
      );
}

enum GoalStatus { active, paused, achieved, abandoned }

/// 长期目标
class GoalItem {
  final String id;
  String title;
  String description;
  String icon;
  int colorValue;
  DateTime? startDate;
  DateTime? targetDate;
  GoalStatus status;
  double progress; // 0.0 - 1.0，自动算或手动
  bool autoProgress; // true=由里程碑计算，false=手动
  List<GoalMilestone> milestones;
  String? category;
  int sortOrder;
  DateTime createdAt;
  DateTime updatedAt;

  GoalItem({
    String? id,
    required this.title,
    this.description = '',
    this.icon = 'flag',
    this.colorValue = 0xFFFFA726,
    this.startDate,
    this.targetDate,
    this.status = GoalStatus.active,
    this.progress = 0,
    this.autoProgress = true,
    List<GoalMilestone>? milestones,
    this.category,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        milestones = milestones ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get computedProgress {
    if (!autoProgress) return progress;
    if (milestones.isEmpty) return status == GoalStatus.achieved ? 1.0 : 0.0;
    final done = milestones.where((m) => m.isCompleted).length;
    return (done / milestones.length).clamp(0.0, 1.0);
  }

  int get daysRemaining {
    if (targetDate == null) return -1;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final t = DateTime(targetDate!.year, targetDate!.month, targetDate!.day);
    return t.difference(today).inDays;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'icon': icon,
        'colorValue': colorValue,
        'startDate': startDate?.toIso8601String(),
        'targetDate': targetDate?.toIso8601String(),
        'status': status.index,
        'progress': progress,
        'autoProgress': autoProgress,
        'milestones': milestones.map((m) => m.toJson()).toList(),
        'category': category,
        'sortOrder': sortOrder,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory GoalItem.fromJson(Map<String, dynamic> json) => GoalItem(
        id: json['id'],
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        icon: json['icon'] ?? 'flag',
        colorValue: json['colorValue'] ?? 0xFFFFA726,
        startDate: json['startDate'] != null
            ? DateTime.parse(json['startDate'])
            : null,
        targetDate: json['targetDate'] != null
            ? DateTime.parse(json['targetDate'])
            : null,
        status: GoalStatus.values[json['status'] ?? 0],
        progress: (json['progress'] ?? 0).toDouble(),
        autoProgress: json['autoProgress'] ?? true,
        milestones: (json['milestones'] as List<dynamic>?)
                ?.map((m) => GoalMilestone.fromJson(m))
                .toList() ??
            [],
        category: json['category'],
        sortOrder: json['sortOrder'] ?? 0,
        createdAt: DateTime.parse(json['createdAt']),
        updatedAt: DateTime.parse(json['updatedAt']),
      );
}
