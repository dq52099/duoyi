import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/course_schedule.dart';

class CourseProvider extends ChangeNotifier {
  static const _coursesKey = 'duoyi_courses';
  static const _settingsKey = 'duoyi_course_settings';

  List<CourseItem> _courses = [];
  ScheduleSettings _settings = ScheduleSettings();
  int _viewingWeek = 1;

  List<CourseItem> get courses => List.unmodifiable(_courses);
  ScheduleSettings get settings => _settings;
  int get viewingWeek => _viewingWeek;

  int get currentWeek {
    final week = _settings.weekOf(DateTime.now());
    return week == 0 ? 1 : week;
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();

    final rawSettings = prefs.getString(_settingsKey);
    if (rawSettings != null) {
      _settings = ScheduleSettings.fromJson(jsonDecode(rawSettings));
    }

    final raw = prefs.getStringList(_coursesKey) ?? [];
    _courses = raw.map((e) => CourseItem.fromJson(jsonDecode(e))).toList();

    _viewingWeek = currentWeek;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _coursesKey, _courses.map((e) => jsonEncode(e.toJson())).toList());
    await prefs.setString(_settingsKey, jsonEncode(_settings.toJson()));
    notifyListeners();
  }

  Future<void> updateSettings(ScheduleSettings s) async {
    _settings = s;
    // 确保 viewingWeek 合法
    if (_viewingWeek > s.totalWeeks) _viewingWeek = s.totalWeeks;
    if (_viewingWeek < 1) _viewingWeek = 1;
    await _save();
  }

  void setViewingWeek(int week) {
    final w = week.clamp(1, _settings.totalWeeks);
    if (w != _viewingWeek) {
      _viewingWeek = w;
      notifyListeners();
    }
  }

  Future<void> add(CourseItem course) async {
    _courses.add(course);
    await _save();
  }

  Future<void> update(CourseItem course) async {
    final idx = _courses.indexWhere((c) => c.id == course.id);
    if (idx != -1) {
      _courses[idx] = course;
      await _save();
    }
  }

  Future<void> delete(String id) async {
    _courses.removeWhere((c) => c.id == id);
    await _save();
  }

  /// 按周筛选
  List<CourseItem> coursesOfWeek(int week) =>
      _courses.where((c) => c.activeInWeek(week)).toList();

  /// 指定日期的课(根据对应周数)
  List<CourseItem> coursesOfDate(DateTime date) {
    final week = _settings.weekOf(date);
    if (week == 0) return [];
    return _courses
        .where((c) => c.weekday == date.weekday && c.activeInWeek(week))
        .toList();
  }

  /// 今天的课
  List<CourseItem> get todayCourses => coursesOfDate(DateTime.now());
}
