import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// 学期/课表设置
class ScheduleSettings {
  DateTime termStart; // 第一周的周一
  int totalWeeks;
  int sessionsPerDay; // 每天节数
  int sessionMinutes; // 每节时长(分钟)

  ScheduleSettings({
    DateTime? termStart,
    this.totalWeeks = 20,
    this.sessionsPerDay = 12,
    this.sessionMinutes = 45,
  }) : termStart = termStart ?? _defaultTermStart();

  static DateTime _defaultTermStart() {
    final now = DateTime.now();
    // 回退到本周一
    return DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
  }

  /// 给定日期对应的第几周(1 基)，越界返回 0
  int weekOf(DateTime date) {
    final start = DateTime(termStart.year, termStart.month, termStart.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = d.difference(start).inDays;
    if (diff < 0) return 0;
    final week = diff ~/ 7 + 1;
    return week > totalWeeks ? 0 : week;
  }

  Map<String, dynamic> toJson() => {
        'termStart': termStart.toIso8601String(),
        'totalWeeks': totalWeeks,
        'sessionsPerDay': sessionsPerDay,
        'sessionMinutes': sessionMinutes,
      };

  factory ScheduleSettings.fromJson(Map<String, dynamic> json) =>
      ScheduleSettings(
        termStart: json['termStart'] != null
            ? DateTime.parse(json['termStart'])
            : null,
        totalWeeks: json['totalWeeks'] ?? 20,
        sessionsPerDay: json['sessionsPerDay'] ?? 12,
        sessionMinutes: json['sessionMinutes'] ?? 45,
      );
}

/// 单节课
class CourseItem {
  final String id;
  String name;
  String teacher;
  String location;
  int weekday; // 1=周一 ... 7=周日
  int startSection; // 1 基
  int sectionCount;
  List<int> weeks; // 上课周列表(1 基)
  int colorValue;
  String? note;

  CourseItem({
    String? id,
    required this.name,
    this.teacher = '',
    this.location = '',
    required this.weekday,
    required this.startSection,
    this.sectionCount = 2,
    List<int>? weeks,
    this.colorValue = 0xFF4CAF50,
    this.note,
  })  : id = id ?? _uuid.v4(),
        weeks = weeks ?? [];

  bool activeInWeek(int week) => weeks.contains(week);

  int get endSection => startSection + sectionCount - 1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'teacher': teacher,
        'location': location,
        'weekday': weekday,
        'startSection': startSection,
        'sectionCount': sectionCount,
        'weeks': weeks,
        'colorValue': colorValue,
        'note': note,
      };

  factory CourseItem.fromJson(Map<String, dynamic> json) => CourseItem(
        id: json['id'],
        name: json['name'] ?? '',
        teacher: json['teacher'] ?? '',
        location: json['location'] ?? '',
        weekday: json['weekday'] ?? 1,
        startSection: json['startSection'] ?? 1,
        sectionCount: json['sectionCount'] ?? 2,
        weeks: (json['weeks'] as List<dynamic>?)?.cast<int>() ?? [],
        colorValue: json['colorValue'] ?? 0xFF4CAF50,
        note: json['note'],
      );
}
