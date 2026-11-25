import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/course_schedule.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';

class CourseProvider extends ChangeNotifier {
  static const _coursesKey = 'duoyi_courses';
  static const _settingsKey = 'duoyi_course_settings';

  List<CourseItem> _courses = [];
  ScheduleSettings _settings = ScheduleSettings();
  int _viewingWeek = 1;
  int _storageGeneration = 0;
  ReminderScheduler? _scheduler;
  VoidCallback? onLocalMutationPersisted;

  set scheduler(ReminderScheduler? value) {
    _scheduler = value;
  }

  List<CourseItem> get courses => List.unmodifiable(_courses);
  ScheduleSettings get settings => _settings;
  int get viewingWeek => _viewingWeek;

  int get currentWeek {
    final week = _settings.weekOf(DateTime.now());
    return week == 0 ? 1 : week;
  }

  Future<void> _syncCourseReminders(
    int generation,
    int accountGeneration,
  ) async {
    final scheduler = _scheduler;
    if (scheduler == null ||
        !_isCurrentStorageGeneration(generation, accountGeneration)) {
      return;
    }
    final snapshot = List<CourseItem>.of(_courses);
    final settingsSnapshot = _settings;
    try {
      await scheduler.syncCourses(snapshot, settings: settingsSnapshot);
    } catch (e, st) {
      debugPrint('[CourseProvider] reminder sync failed: $e\n$st');
    }
  }

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;

    final rawSettings = prefs.getString(_settingsKey);
    if (rawSettings != null) {
      _settings = ScheduleSettings.fromJson(jsonDecode(rawSettings));
    }

    final raw = prefs.getStringList(_coursesKey) ?? [];
    _courses = raw.map((e) => CourseItem.fromJson(jsonDecode(e))).toList();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;

    _viewingWeek = currentWeek;
    notifyListeners();
    unawaited(_syncCourseReminders(generation, accountGeneration));
  }

  void resetLocalState() {
    _storageGeneration++;
    _courses = [];
    _settings = ScheduleSettings();
    _viewingWeek = currentWeek;
    notifyListeners();
  }

  Future<void> _save() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    await prefs.setStringList(
      _coursesKey,
      _courses.map((e) => jsonEncode(e.toJson())).toList(),
    );
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    await prefs.setString(_settingsKey, jsonEncode(_settings.toJson()));
    _notifyLocalMutationPersisted();
    notifyListeners();
    await _syncCourseReminders(generation, accountGeneration);
  }

  bool _isCurrentStorageGeneration(
    int storageGeneration,
    int accountGeneration,
  ) {
    return storageGeneration == _storageGeneration &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
  }

  void _notifyLocalMutationPersisted() {
    try {
      onLocalMutationPersisted?.call();
    } catch (e, st) {
      debugPrint('[CourseProvider] local mutation callback failed: $e\n$st');
    }
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
    course.updatedAt = DateTime.now();
    _courses.add(course);
    await _save();
  }

  Future<void> update(CourseItem course) async {
    final idx = _courses.indexWhere((c) => c.id == course.id);
    if (idx != -1) {
      course.updatedAt = DateTime.now();
      _courses[idx] = course;
      await _save();
    }
  }

  Future<void> delete(String id) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final existingCourses = _courses
        .where((course) => course.id == id)
        .toList(growable: false);
    if (existingCourses.isEmpty) return;
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;

    // CourseItem has no workspaceId field in its current serialized model.
    await CloudSyncProvider.recordDeletedItem(
      'courses',
      existingCourses.first.id,
      workspaceId: null,
    );
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    _courses.removeWhere((course) => course.id == id);
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    await _save();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
  }

  /// 按周筛选
  List<CourseItem> coursesOfWeek(int week) =>
      _courses.where((c) => c.activeInWeek(week)).toList();

  /// 查找与指定课程存在同一天、相同周次且节次重叠的冲突课程
  List<CourseItem> findConflicts(
    CourseItem candidate, {
    String? excludeCourseId,
  }) {
    final excluded = excludeCourseId ?? candidate.id;
    return _courses
        .where(
          (existing) => existing.id != excluded && existing.overlapsWith(candidate),
        )
        .toList(growable: false);
  }

  /// 批量导入课程（一次性持久化并通知监听者）
  Future<int> importCourses(Iterable<CourseItem> items) async {
    final now = DateTime.now();
    var added = 0;
    for (final raw in items) {
      if (raw.name.trim().isEmpty) continue;
      final normalizedWeeks = raw.weeks.isEmpty
          ? List<int>.generate(_settings.totalWeeks, (i) => i + 1)
          : (raw.weeks
                .where((w) => w >= 1 && w <= _settings.totalWeeks)
                .toSet()
                .toList()
              ..sort());
      final clampedStart = raw.startSection.clamp(1, _settings.sessionsPerDay);
      final maxCount = (_settings.sessionsPerDay - clampedStart + 1).clamp(
        1,
        _settings.sessionsPerDay,
      );
      final course = CourseItem(
        id: raw.id,
        name: raw.name.trim(),
        teacher: raw.teacher.trim(),
        location: raw.location.trim(),
        weekday: raw.weekday.clamp(1, 7),
        startSection: clampedStart,
        sectionCount: raw.sectionCount.clamp(1, maxCount),
        weeks: normalizedWeeks,
        colorValue: raw.colorValue,
        reminderMinutes: CourseItem.normalizeReminderMinutes(raw.reminderMinutes),
        note: raw.note,
        updatedAt: now,
      );
      _courses.add(course);
      added++;
    }
    if (added > 0) {
      await _save();
    }
    return added;
  }

  /// 解析 CSV 或 iCalendar (.ics) 课表内容用于预览与导入
  static CourseImportPreview parseTimetable(
    String raw, {
    ScheduleSettings? settings,
  }) {
    final cfg = settings ?? ScheduleSettings();
    final cleaned = raw.replaceFirst('\uFEFF', '').trim();
    if (cleaned.isEmpty) {
      return const CourseImportPreview(
        format: 'csv',
        courses: <CourseItem>[],
        warnings: <String>[],
      );
    }
    final upper = cleaned.toUpperCase();
    if (upper.contains('BEGIN:VCALENDAR') || upper.contains('BEGIN:VEVENT')) {
      return _parseIcs(cleaned, cfg);
    }
    return _parseCsv(cleaned, cfg);
  }

  static const List<int> _importPalette = <int>[
    0xFF42A5F5,
    0xFF66BB6A,
    0xFFFFA726,
    0xFF26A69A,
    0xFFAB47BC,
    0xFF5C6BC0,
    0xFFEC407A,
    0xFFEF5350,
  ];

  static CourseImportPreview _parseCsv(String text, ScheduleSettings cfg) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final courses = <CourseItem>[];
    final warnings = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final cells = _splitCsvRow(lines[i]);
      if (cells.isEmpty) continue;
      if (i == 0 && _looksLikeCsvHeader(cells)) continue;
      if (cells.length < 3) {
        warnings.add('Line ${i + 1}: expected >= 3 columns');
        continue;
      }
      final name = cells[0].trim();
      final weekday = _parseWeekday(cells[1]);
      if (name.isEmpty || weekday == null) {
        warnings.add('Line ${i + 1}: invalid course name or weekday');
        continue;
      }

      var startSection = 1;
      var sectionCount = 2;
      var weekColIndex = 4;

      final sectionCell = cells[2].trim();
      final rangeMatch = RegExp(r'^(\d+)\s*[-~到]\s*(\d+)$').firstMatch(
        sectionCell,
      );
      if (rangeMatch != null) {
        final s = int.tryParse(rangeMatch.group(1)!) ?? 1;
        final e = int.tryParse(rangeMatch.group(2)!) ?? s;
        startSection = s.clamp(1, cfg.sessionsPerDay);
        sectionCount = (e >= s ? e - s + 1 : 1).clamp(
          1,
          cfg.sessionsPerDay - startSection + 1,
        );
        weekColIndex = 3;
      } else {
        final parsedStart = int.tryParse(sectionCell);
        if (parsedStart == null) {
          warnings.add('Line ${i + 1}: invalid start section');
          continue;
        }
        startSection = parsedStart.clamp(1, cfg.sessionsPerDay);
        final parsedCount = cells.length > 3 ? int.tryParse(cells[3].trim()) : null;
        sectionCount = (parsedCount ?? 2).clamp(
          1,
          cfg.sessionsPerDay - startSection + 1,
        );
        weekColIndex = 4;
      }

      final weeksText =
          cells.length > weekColIndex ? cells[weekColIndex] : '';
      final weeks = _parseWeeks(weeksText, cfg.totalWeeks);
      final location =
          cells.length > weekColIndex + 1 ? cells[weekColIndex + 1].trim() : '';
      final teacher =
          cells.length > weekColIndex + 2 ? cells[weekColIndex + 2].trim() : '';
      final reminderRaw = cells.length > weekColIndex + 3
          ? int.tryParse(cells[weekColIndex + 3].trim())
          : null;

      courses.add(
        CourseItem(
          name: name,
          weekday: weekday,
          startSection: startSection,
          sectionCount: sectionCount,
          weeks: weeks,
          location: location,
          teacher: teacher,
          colorValue: _importPalette[courses.length % _importPalette.length],
          reminderMinutes: CourseItem.normalizeReminderMinutes(reminderRaw),
        ),
      );
    }

    return CourseImportPreview(
      format: 'csv',
      courses: courses,
      warnings: warnings,
    );
  }

  static CourseImportPreview _parseIcs(String text, ScheduleSettings cfg) {
    final unfolded = text
        .replaceAll('\r\n ', '')
        .replaceAll('\r\n\t', '')
        .replaceAll('\n ', '')
        .replaceAll('\n\t', '');
    final lines = unfolded.split(RegExp(r'\r?\n'));
    final courses = <CourseItem>[];
    final warnings = <String>[];

    Map<String, String>? current;
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line == 'BEGIN:VEVENT') {
        current = <String, String>{};
        continue;
      }
      if (line == 'END:VEVENT') {
        if (current != null) {
          final parsed = _icsEventToCourse(
            current,
            cfg,
            _importPalette[courses.length % _importPalette.length],
          );
          if (parsed != null) {
            courses.add(parsed);
          } else {
            warnings.add(
              current['SUMMARY'] ?? 'Skipped VEVENT with incomplete schedule time',
            );
          }
        }
        current = null;
        continue;
      }
      if (current != null && line.contains(':')) {
        final idx = line.indexOf(':');
        final keyPart = line.substring(0, idx);
        final key = keyPart.split(';').first.trim().toUpperCase();
        final value = _unescapeIcs(line.substring(idx + 1).trim());
        current[key] = value;
      }
    }

    return CourseImportPreview(
      format: 'ics',
      courses: courses,
      warnings: warnings,
    );
  }

  static CourseItem? _icsEventToCourse(
    Map<String, String> event,
    ScheduleSettings cfg,
    int colorValue,
  ) {
    final name = (event['SUMMARY'] ?? '').trim();
    final dtStart = _parseIcsDateTime(event['DTSTART']);
    if (name.isEmpty || dtStart == null) return null;
    final dtEnd = _parseIcsDateTime(event['DTEND']);

    final startMinutes = dtStart.hour * 60 + dtStart.minute;
    var bestSection = 1;
    var bestDelta = 1 << 20;
    for (var s = 1; s <= cfg.sessionsPerDay; s++) {
      final secTime = cfg.sectionStart(dtStart, s);
      final secMinutes = secTime.hour * 60 + secTime.minute;
      final delta = (startMinutes - secMinutes).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestSection = s;
      }
    }

    var sectionCount = 2;
    if (dtEnd != null && dtEnd.isAfter(dtStart)) {
      final durationMinutes = dtEnd.difference(dtStart).inMinutes;
      final unit = (cfg.sessionMinutes + cfg.breakMinutes).clamp(1, 240);
      final estimated =
          ((durationMinutes + cfg.breakMinutes) / unit).round();
      sectionCount = estimated.clamp(
        1,
        cfg.sessionsPerDay - bestSection + 1,
      );
    }

    final location = (event['LOCATION'] ?? '').trim();
    final description = (event['DESCRIPTION'] ?? '').trim();
    var teacher = '';
    for (final line in description.split(RegExp(r'[\r\n]+'))) {
      final tMatch = RegExp(
        r'^(?:teacher|instructor|教师|授课教师)\s*[:：]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line.trim());
      if (tMatch != null) {
        teacher = tMatch.group(1)!.trim();
        break;
      }
    }

    List<int> weeks;
    final rrule = (event['RRULE'] ?? '').toUpperCase();
    final countMatch = RegExp(r'COUNT=(\d+)').firstMatch(rrule);
    final intervalMatch = RegExp(r'INTERVAL=(\d+)').firstMatch(rrule);
    if (countMatch != null) {
      final count = int.tryParse(countMatch.group(1)!) ?? cfg.totalWeeks;
      final interval = int.tryParse(intervalMatch?.group(1) ?? '1') ?? 1;
      final startWeek = cfg.weekOf(dtStart);
      final baseWeek = startWeek > 0 ? startWeek : 1;
      weeks = <int>[
        for (var k = 0; k < count; k++)
          if (baseWeek + k * interval <= cfg.totalWeeks)
            baseWeek + k * interval,
      ];
    } else if (description.isNotEmpty) {
      final descWeeks = _parseWeeks(description, cfg.totalWeeks, strict: true);
      weeks = descWeeks.isNotEmpty
          ? descWeeks
          : List<int>.generate(cfg.totalWeeks, (i) => i + 1);
    } else {
      weeks = List<int>.generate(cfg.totalWeeks, (i) => i + 1);
    }

    return CourseItem(
      name: name,
      teacher: teacher,
      location: location,
      weekday: dtStart.weekday,
      startSection: bestSection,
      sectionCount: sectionCount,
      weeks: weeks,
      colorValue: colorValue,
    );
  }

  static DateTime? _parseIcsDateTime(String? raw) {
    if (raw == null) return null;
    final clean = raw.trim().replaceAll('Z', '');
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?$')
        .firstMatch(clean);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.tryParse(m.group(6) ?? '0') ?? 0,
      );
    }
    return DateTime.tryParse(raw.trim());
  }

  static String _unescapeIcs(String value) => value
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\\', r'\');

  static bool _looksLikeCsvHeader(List<String> cells) {
    final joined = cells.join(',').toLowerCase();
    return joined.contains('课程') ||
        joined.contains('weekday') ||
        joined.contains('startsection') ||
        joined.contains('星期') ||
        (cells.first.trim().toLowerCase() == 'name');
  }

  static List<String> _splitCsvRow(String row) {
    final result = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < row.length; i++) {
      final ch = row[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < row.length && row[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  static int? _parseWeekday(String raw) {
    final v = raw.trim().toLowerCase();
    final numVal = int.tryParse(v);
    if (numVal != null && numVal >= 1 && numVal <= 7) return numVal;
    const mapping = <String, int>{
      '一': 1,
      '周一': 1,
      '星期一': 1,
      'mon': 1,
      'monday': 1,
      '二': 2,
      '周二': 2,
      '星期二': 2,
      'tue': 2,
      'tuesday': 2,
      '三': 3,
      '周三': 3,
      '星期三': 3,
      'wed': 3,
      'wednesday': 3,
      '四': 4,
      '周四': 4,
      '星期四': 4,
      'thu': 4,
      'thursday': 4,
      '五': 5,
      '周五': 5,
      '星期五': 5,
      'fri': 5,
      'friday': 5,
      '六': 6,
      '周六': 6,
      '星期六': 6,
      'sat': 6,
      'saturday': 6,
      '日': 7,
      '天': 7,
      '周日': 7,
      '周天': 7,
      '星期日': 7,
      '星期天': 7,
      'sun': 7,
      'sunday': 7,
    };
    return mapping[v];
  }

  static List<int> _parseWeeks(
    String raw,
    int totalWeeks, {
    bool strict = false,
  }) {
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return strict
          ? const <int>[]
          : List<int>.generate(totalWeeks, (i) => i + 1);
    }
    final oddOnly = trimmed.contains('单') || trimmed.contains('odd');
    final evenOnly = trimmed.contains('双') || trimmed.contains('even');
    if (trimmed == 'odd' || trimmed == '单周' || trimmed == '单') {
      return [
        for (var w = 1; w <= totalWeeks; w++)
          if (w.isOdd) w,
      ];
    }
    if (trimmed == 'even' || trimmed == '双周' || trimmed == '双') {
      return [
        for (var w = 1; w <= totalWeeks; w++)
          if (w.isEven) w,
      ];
    }
    if (trimmed == 'all' || trimmed == '全周') {
      return List<int>.generate(totalWeeks, (i) => i + 1);
    }

    final result = <int>{};
    for (final match in RegExp(r'(\d+)\s*[-~到]\s*(\d+)').allMatches(trimmed)) {
      final start = int.parse(match.group(1)!).clamp(1, totalWeeks);
      final end = int.parse(match.group(2)!).clamp(1, totalWeeks);
      for (var w = start; w <= end; w++) {
        if (oddOnly && !w.isOdd) continue;
        if (evenOnly && !w.isEven) continue;
        result.add(w);
      }
    }
    final withoutRanges = trimmed.replaceAll(RegExp(r'\d+\s*[-~到]\s*\d+'), ' ');
    for (final match in RegExp(r'\b(\d+)\b').allMatches(withoutRanges)) {
      final w = int.tryParse(match.group(1)!);
      if (w != null && w >= 1 && w <= totalWeeks) {
        if (oddOnly && !w.isOdd) continue;
        if (evenOnly && !w.isEven) continue;
        result.add(w);
      }
    }
    if (result.isEmpty) {
      return strict
          ? const <int>[]
          : List<int>.generate(totalWeeks, (i) => i + 1);
    }
    return result.toList()..sort();
  }

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

class CourseImportPreview {
  final String format;
  final List<CourseItem> courses;
  final List<String> warnings;

  const CourseImportPreview({
    required this.format,
    required this.courses,
    required this.warnings,
  });
}
