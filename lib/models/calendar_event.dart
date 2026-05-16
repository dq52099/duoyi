import 'package:flutter/material.dart';

enum CalendarEventType {
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
    CalendarEventType.todo => '待办',
    CalendarEventType.habit => '习惯',
    CalendarEventType.pomodoro => '番茄钟',
    CalendarEventType.anniversary => '纪念日',
    CalendarEventType.course => '课程',
    CalendarEventType.diary => '日记',
    CalendarEventType.countdown => '倒数日',
    CalendarEventType.goal => '目标',
    CalendarEventType.timeEntry => '时间足迹',
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
  final TimeOfDay? time;
  final bool hasConflict;
  final int conflictCount;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.type,
    required this.color,
    this.isCompleted = false,
    this.sourceId,
    this.subtitle,
    this.time,
    this.endDate,
    this.hasConflict = false,
    this.conflictCount = 0,
  });

  String get dateKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  bool get canOpen => sourceId != null && sourceId!.isNotEmpty;

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
    TimeOfDay? time,
    bool? hasConflict,
    int? conflictCount,
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
      time: time ?? this.time,
      hasConflict: hasConflict ?? this.hasConflict,
      conflictCount: conflictCount ?? this.conflictCount,
    );
  }
}
