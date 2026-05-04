import 'package:flutter/material.dart';

enum CalendarEventType { todo, habit, pomodoro }

class CalendarEvent {
  final String id;
  final String title;
  final DateTime date;
  final CalendarEventType type;
  final Color color;
  final bool isCompleted;
  final String? sourceId;
  final TimeOfDay? time;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.type,
    required this.color,
    this.isCompleted = false,
    this.sourceId,
    this.time,
  });

  String get dateKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}