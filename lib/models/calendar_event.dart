import 'package:flutter/material.dart';

import '../core/i18n.dart';
import 'habit.dart';
import 'time_entry.dart';

enum CalendarEventType {
  event,
  todo,
  habit,
  pomodoro,
  anniversary,
  course,
  diary,
  countdown,
  goal,
  timeEntry,
}

extension CalendarEventTypeX on CalendarEventType {
  String get label => switch (this) {
    CalendarEventType.event => I18n.tr('calendar_event.event'),
    CalendarEventType.todo => I18n.tr('calendar_event.todo'),
    CalendarEventType.habit => I18n.tr('calendar_event.habit'),
    CalendarEventType.pomodoro => I18n.tr('calendar_event.pomodoro'),
    CalendarEventType.anniversary => I18n.tr('calendar_event.anniversary'),
    CalendarEventType.course => I18n.tr('calendar_event.course'),
    CalendarEventType.diary => I18n.tr('calendar_event.diary'),
    CalendarEventType.countdown => I18n.tr('calendar_event.countdown'),
    CalendarEventType.goal => I18n.tr('calendar_event.goal'),
    CalendarEventType.timeEntry => I18n.tr('calendar_event.time_entry'),
  };
}

class CalendarEvent {
  final String id;
  final String title;
  final DateTime date;
  final DateTime? endDate;
  final CalendarEventType type;
  final Color color;
  final bool isCompleted;
  final String? sourceId;
  final String? subtitle;
  final String? projectId;
  final String? projectName;
  final String? workspaceId;
  final TimeOfDay? time;
  final bool hasConflict;
  final int conflictCount;
  final String? note;
  final DateTime? updatedAt;
  final int? reminderMinutes;
  final CalendarEventDisplayMetadata? displayMetadata;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.type,
    required this.color,
    this.isCompleted = false,
    this.sourceId,
    this.subtitle,
    this.projectId,
    this.projectName,
    this.workspaceId,
    this.time,
    this.endDate,
    this.hasConflict = false,
    this.conflictCount = 0,
    this.note,
    this.updatedAt,
    this.reminderMinutes,
    this.displayMetadata,
  });

  String get dateKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  bool get canOpen => sourceId != null && sourceId!.isNotEmpty;

  String? get projectKey {
    if (projectId != null && projectId!.isNotEmpty) return projectId;
    if (projectName != null && projectName!.isNotEmpty) return projectName;
    return null;
  }

  CalendarEvent copyWith({
    String? id,
    String? title,
    DateTime? date,
    DateTime? endDate,
    CalendarEventType? type,
    Color? color,
    bool? isCompleted,
    String? sourceId,
    String? subtitle,
    String? projectId,
    String? projectName,
    String? workspaceId,
    TimeOfDay? time,
    bool? hasConflict,
    int? conflictCount,
    String? note,
    DateTime? updatedAt,
    int? reminderMinutes,
    bool clearReminderMinutes = false,
    CalendarEventDisplayMetadata? displayMetadata,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      endDate: endDate ?? this.endDate,
      type: type ?? this.type,
      color: color ?? this.color,
      isCompleted: isCompleted ?? this.isCompleted,
      sourceId: sourceId ?? this.sourceId,
      subtitle: subtitle ?? this.subtitle,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      workspaceId: workspaceId ?? this.workspaceId,
      time: time ?? this.time,
      hasConflict: hasConflict ?? this.hasConflict,
      conflictCount: conflictCount ?? this.conflictCount,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
      reminderMinutes: clearReminderMinutes
          ? null
          : (reminderMinutes ?? this.reminderMinutes),
      displayMetadata: displayMetadata ?? this.displayMetadata,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': date.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'type': type.name,
    'color': color.toARGB32(),
    'isCompleted': isCompleted,
    'sourceId': sourceId,
    'subtitle': subtitle,
    'projectId': projectId,
    'projectName': projectName,
    'workspaceId': workspaceId,
    'time': time == null ? null : '${time!.hour}:${time!.minute}',
    'hasConflict': hasConflict,
    'conflictCount': conflictCount,
    'note': note,
    'updatedAt': updatedAt?.toIso8601String(),
    if (reminderMinutes != null) 'reminderMinutes': reminderMinutes,
  };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    final parsedType = CalendarEventType.values.firstWhere(
      (type) => type.name == json['type'],
      orElse: () => CalendarEventType.event,
    );
    final timeRaw = json['time']?.toString();
    final timeParts = timeRaw?.split(':');
    TimeOfDay? parsedTime;
    if (timeParts != null && timeParts.length == 2) {
      final hour = int.tryParse(timeParts[0]);
      final minute = int.tryParse(timeParts[1]);
      if (hour != null && minute != null) {
        parsedTime = TimeOfDay(hour: hour, minute: minute);
      }
    }
    final rawColor = json['color'];
    final rawReminder = json['reminderMinutes'];
    return CalendarEvent(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      date: DateTime.parse(json['date'] as String),
      endDate: json['endDate'] == null
          ? null
          : DateTime.parse(json['endDate'] as String),
      type: parsedType,
      color: Color(rawColor is int ? rawColor : 0xFF5B6EE1),
      isCompleted: json['isCompleted'] == true,
      sourceId: json['sourceId']?.toString(),
      subtitle: json['subtitle']?.toString(),
      projectId: json['projectId']?.toString(),
      projectName: json['projectName']?.toString(),
      workspaceId: json['workspaceId']?.toString(),
      time: parsedTime,
      hasConflict: json['hasConflict'] == true,
      conflictCount: (json['conflictCount'] as num?)?.toInt() ?? 0,
      note: json['note']?.toString(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      reminderMinutes: rawReminder is num
          ? rawReminder.toInt()
          : int.tryParse(rawReminder?.toString() ?? ''),
    );
  }
}

sealed class CalendarEventDisplayMetadata {
  const CalendarEventDisplayMetadata();
}

class PomodoroDisplayMetadata extends CalendarEventDisplayMetadata {
  final int? fallbackMinutes;
  final int durationSeconds;

  const PomodoroDisplayMetadata({
    int? fallbackMinutes,
    int? minutes,
    int? durationSeconds,
  }) : fallbackMinutes = fallbackMinutes ?? minutes,
       durationSeconds =
           durationSeconds ?? (minutes != null ? minutes * 60 : 0);

  bool get isFallbackTitle => fallbackMinutes != null;
  int get minutes => fallbackMinutes ?? (durationSeconds ~/ 60);
}

class TodoDisplayMetadata extends CalendarEventDisplayMetadata {
  final DateTime? dueDate;
  const TodoDisplayMetadata({this.dueDate});
}

class TimeEntryDisplayMetadata extends CalendarEventDisplayMetadata {
  final TimeEntryCategory category;
  final int durationSeconds;

  const TimeEntryDisplayMetadata({
    required this.category,
    required this.durationSeconds,
  });
}

class AnniversaryDisplayMetadata extends CalendarEventDisplayMetadata {
  final int? yearsPassed;
  final int daysRemaining;
  const AnniversaryDisplayMetadata({
    required this.yearsPassed,
    required this.daysRemaining,
  });
}

class CountdownDisplayMetadata extends CalendarEventDisplayMetadata {
  final int daysRemaining;
  const CountdownDisplayMetadata({required this.daysRemaining});
}

class GoalDisplayMetadata extends CalendarEventDisplayMetadata {
  final bool isAchieved;
  final int progressPercent;
  const GoalDisplayMetadata({
    required this.isAchieved,
    required this.progressPercent,
  });
}

class CourseDisplayMetadata extends CalendarEventDisplayMetadata {
  final int week;
  final int startSection;
  final int endSection;
  final String timeRangeLabel;
  final String location;
  final String teacher;
  const CourseDisplayMetadata({
    required this.week,
    required this.startSection,
    required this.endSection,
    required this.timeRangeLabel,
    this.location = '',
    this.teacher = '',
  });
}

class HabitDisplayMetadata extends CalendarEventDisplayMetadata {
  final HabitKind kind;
  final int count;
  final int targetCount;
  final String? unit;
  final String? generatedUnitKey;
  final bool hasFlexRule;
  final HabitFlexProgress? flexProgress;

  const HabitDisplayMetadata({
    required this.kind,
    required this.count,
    required this.targetCount,
    this.unit,
    this.generatedUnitKey,
    this.hasFlexRule = false,
    this.flexProgress,
  });
}

class DiaryDisplayMetadata extends CalendarEventDisplayMetadata {
  final String? moodKey;
  final DateTime? fallbackTitleDate;

  const DiaryDisplayMetadata({this.moodKey, this.fallbackTitleDate});
}
