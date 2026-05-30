import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/anniversary.dart';
import '../models/calendar_event.dart';
import '../models/countdown.dart';
import '../models/goal.dart' show ReminderConfig, ReminderKind;
import '../models/habit.dart';
import '../models/note.dart';
import '../models/recurrence.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';

class CompetitorTaskImportResult {
  final List<TodoItem> todos;
  final List<Habit> habits;
  final List<NoteItem> notes;
  final List<CalendarEvent> calendarEvents;
  final List<Anniversary> anniversaries;
  final List<CountdownItem> countdowns;
  final List<TimeEntry> timeEntries;
  final int skippedRows;
  final List<String> warnings;
  final String sourceLabel;

  const CompetitorTaskImportResult({
    required this.todos,
    this.habits = const [],
    this.notes = const [],
    this.calendarEvents = const [],
    this.anniversaries = const [],
    this.countdowns = const [],
    this.timeEntries = const [],
    required this.skippedRows,
    required this.warnings,
    required this.sourceLabel,
  });

  int get totalImported =>
      todos.length +
      habits.length +
      notes.length +
      calendarEvents.length +
      anniversaries.length +
      countdowns.length +
      timeEntries.length;
}

class CompetitorFieldMapping {
  final Map<String, String> targetToSource;

  const CompetitorFieldMapping([this.targetToSource = const {}]);

  bool get isEmpty => targetToSource.entries.every(
    (entry) => entry.key.trim().isEmpty || entry.value.trim().isEmpty,
  );

  String sourceFor(String target) => targetToSource[target] ?? '';
}

class CompetitorTaskImporter {
  const CompetitorTaskImporter();

  CompetitorTaskImportResult parse(
    String raw, {
    CompetitorFieldMapping fieldMapping = const CompetitorFieldMapping(),
  }) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const CompetitorTaskImportResult(
        todos: [],
        skippedRows: 0,
        warnings: ['导入内容为空'],
        sourceLabel: '空内容',
      );
    }

    if (text.startsWith('{') || text.startsWith('[')) {
      return _parseJson(text, fieldMapping: fieldMapping);
    }
    return _parseCsv(text, fieldMapping: fieldMapping);
  }

  CompetitorTaskImportResult _parseJson(
    String text, {
    required CompetitorFieldMapping fieldMapping,
  }) {
    final warnings = <String>[];
    Object? decoded;
    try {
      decoded = json.decode(text);
    } catch (e) {
      return CompetitorTaskImportResult(
        todos: const [],
        skippedRows: 0,
        warnings: ['JSON 解析失败: $e'],
        sourceLabel: 'JSON',
      );
    }

    final rows = _extractJsonRows(
      decoded,
    ).map((row) => _applyFieldMapping(row, fieldMapping)).toList();
    final todos = <TodoItem>[];
    final habits = <Habit>[];
    final notes = <NoteItem>[];
    final calendarEvents = <CalendarEvent>[];
    final anniversaries = <Anniversary>[];
    final countdowns = <CountdownItem>[];
    final timeEntries = <TimeEntry>[];
    var skipped = 0;
    for (var i = 0; i < rows.length; i++) {
      final parsed = _itemFromMap(rows[i], warnings, rowNumber: i + 1);
      if (parsed == null) {
        skipped++;
        continue;
      }
      if (parsed is TodoItem) {
        todos.add(parsed);
      } else if (parsed is Habit) {
        habits.add(parsed);
      } else if (parsed is NoteItem) {
        notes.add(parsed);
      } else if (parsed is CalendarEvent) {
        calendarEvents.add(parsed);
      } else if (parsed is Anniversary) {
        anniversaries.add(parsed);
      } else if (parsed is CountdownItem) {
        countdowns.add(parsed);
      } else if (parsed is TimeEntry) {
        timeEntries.add(parsed);
      }
    }

    return CompetitorTaskImportResult(
      todos: todos,
      habits: habits,
      notes: notes,
      calendarEvents: calendarEvents,
      anniversaries: anniversaries,
      countdowns: countdowns,
      timeEntries: timeEntries,
      skippedRows: skipped,
      warnings: warnings,
      sourceLabel: 'JSON',
    );
  }

  List<Map<String, dynamic>> _extractJsonRows(
    Object? decoded, [
    Map<String, dynamic> inherited = const {},
  ]) {
    if (decoded is List) {
      final rows = <Map<String, dynamic>>[];
      for (final item in decoded.whereType<Map>()) {
        final itemMap = Map<String, dynamic>.from(item);
        final nested = _extractJsonRows(itemMap, inherited);
        if (nested.isNotEmpty) {
          rows.addAll(nested);
        } else {
          rows.add(_mergeInherited(itemMap, inherited));
        }
      }
      return rows;
    }
    if (decoded is Map) {
      final rows = <Map<String, dynamic>>[];
      final map = Map<String, dynamic>.from(decoded);
      for (final entry in const [
        ('tasks', 'task'),
        ('todos', 'task'),
        ('habits', 'habit'),
        ('notes', 'note'),
        ('events', 'event'),
        ('calendarEvents', 'event'),
        ('calendar_events', 'event'),
        ('schedules', 'event'),
        ('anniversaries', 'anniversary'),
        ('birthdays', 'birthday'),
        ('countdowns', 'countdown'),
        ('timeEntries', 'time_entry'),
        ('time_entries', 'time_entry'),
        ('timeLogs', 'time_entry'),
        ('time_logs', 'time_entry'),
        ('items', null),
        ('data', null),
      ]) {
        final key = entry.$1;
        final sourceType = entry.$2;
        final value = map[key];
        if (value is List) {
          rows.addAll(
            value.whereType<Map>().map((m) {
              final row = _mergeInherited(
                Map<String, dynamic>.from(m),
                inherited,
              );
              if (sourceType != null) {
                row.putIfAbsent('type', () => sourceType);
              }
              return row;
            }),
          );
        }
        if (value is Map) {
          rows.addAll(
            _extractTypedMapRows(
              Map<String, dynamic>.from(value),
              inherited,
              sourceType,
            ),
          );
        }
      }

      for (final entry in const [
        ('projects', 'project'),
        ('lists', 'list'),
        ('taskLists', 'list'),
        ('task_lists', 'list'),
        ('categories', 'category'),
        ('tags', 'tag'),
        ('collections', 'collection'),
        ('folders', 'folder'),
        ('workspaces', 'workspace'),
      ]) {
        final key = entry.$1;
        final value = map[key];
        if (value == null) continue;
        if (value is List) {
          for (final child in value.whereType<Map>()) {
            final childMap = Map<String, dynamic>.from(child);
            rows.addAll(
              _extractJsonRows(
                childMap,
                _jsonParentContext(childMap, inherited, entry.$2),
              ),
            );
          }
        } else if (value is Map) {
          for (final childMap in _jsonParentMaps(value)) {
            rows.addAll(
              _extractJsonRows(
                childMap,
                _jsonParentContext(childMap, inherited, entry.$2),
              ),
            );
          }
        }
      }
      if (rows.isNotEmpty) return rows;
    }
    return const [];
  }

  List<Map<String, dynamic>> _extractTypedMapRows(
    Map<String, dynamic> value,
    Map<String, dynamic> inherited,
    String? sourceType,
  ) {
    final rows = <Map<String, dynamic>>[];
    final nested = _extractJsonRows(value, inherited);
    if (nested.isNotEmpty) {
      rows.addAll(nested.map((row) => _withSourceType(row, sourceType)));
      return rows;
    }

    final childMaps = _jsonParentMaps(value);
    final isSingleObject =
        childMaps.length == 1 && identical(childMaps.first, value);
    if (childMaps.isNotEmpty && !isSingleObject) {
      for (final childMap in childMaps) {
        final childNested = _extractJsonRows(childMap, inherited);
        if (childNested.isNotEmpty) {
          rows.addAll(
            childNested.map((row) => _withSourceType(row, sourceType)),
          );
        } else if (_looksLikeImportRow(childMap)) {
          rows.add(
            _withSourceType(_mergeInherited(childMap, inherited), sourceType),
          );
        }
      }
      return rows;
    }

    if (_looksLikeImportRow(value)) {
      rows.add(_withSourceType(_mergeInherited(value, inherited), sourceType));
    }
    return rows;
  }

  List<Map<String, dynamic>> _jsonParentMaps(Object value) {
    if (value is! Map) return const [];
    final map = Map<String, dynamic>.from(value);
    final isSingleObject =
        _hasAnyKey(map, const ['name', 'title', 'label', 'text', '名称', '标题']) ||
        _hasAnyKey(map, _jsonCollectionKeys);
    if (isSingleObject) return [map];
    return map.values
        .whereType<Map>()
        .map((child) => Map<String, dynamic>.from(child))
        .toList();
  }

  Map<String, dynamic> _withSourceType(
    Map<String, dynamic> row,
    String? sourceType,
  ) {
    if (sourceType == null) return row;
    final copy = Map<String, dynamic>.from(row);
    copy.putIfAbsent('type', () => sourceType);
    return copy;
  }

  static const _jsonCollectionKeys = [
    'tasks',
    'todos',
    'habits',
    'notes',
    'events',
    'calendarEvents',
    'calendar_events',
    'schedules',
    'anniversaries',
    'birthdays',
    'countdowns',
    'timeEntries',
    'time_entries',
    'timeLogs',
    'time_logs',
    'items',
    'data',
    'projects',
    'lists',
    'taskLists',
    'task_lists',
    'categories',
    'tags',
    'collections',
    'folders',
    'workspaces',
  ];

  bool _looksLikeImportRow(Map<String, dynamic> map) => _hasAnyKey(map, const [
    'type',
    'kind',
    'module',
    'title',
    'content',
    'name',
    'task',
    'todo',
    'item',
    'subject',
    'habit',
    'note',
    'event',
    'schedule',
    'anniversary',
    'birthday',
    'countdown',
    'timeentry',
    'timelog',
    'due',
    'deadline',
    'date',
    'duedate',
    '任务',
    '标题',
    '内容',
    '事项',
    '待办',
    '习惯',
    '笔记',
    '日程',
    '事件',
    '纪念日',
    '生日',
    '倒数日',
    '倒计时',
    '时间足迹',
    '时间记录',
    '模块',
    '类型',
  ]);

  Map<String, dynamic> _jsonParentContext(
    Map<String, dynamic> parent,
    Map<String, dynamic> inherited,
    String kind,
  ) {
    final context = Map<String, dynamic>.from(inherited);
    final name = _firstText(parent, const [
      'name',
      'title',
      'label',
      'text',
      '名称',
      '标题',
    ]);
    if (name == null || name.trim().isEmpty) return context;
    final trimmed = name.trim();
    switch (kind) {
      case 'project':
        context.putIfAbsent('project', () => trimmed);
        break;
      case 'list':
        context.putIfAbsent('list', () => trimmed);
        break;
      case 'category':
        context.putIfAbsent('category', () => trimmed);
        break;
      case 'tag':
        context.putIfAbsent('tag', () => trimmed);
        break;
      case 'folder':
      case 'collection':
        context.putIfAbsent('folder', () => trimmed);
        break;
      case 'workspace':
        context.putIfAbsent('workspace', () => trimmed);
        break;
    }
    return context;
  }

  Map<String, dynamic> _mergeInherited(
    Map<String, dynamic> row,
    Map<String, dynamic> inherited,
  ) {
    final merged = Map<String, dynamic>.from(inherited);
    if (_hasAnyKey(row, const [
      'list',
      'project',
      'category',
      'folder',
      'group',
      'collection',
      'tasklist',
      'taskgroup',
      '清单',
      '项目',
      '分类',
      '列表',
      '目录',
      '文件夹',
      '分组',
    ])) {
      merged.remove('list');
      merged.remove('project');
      merged.remove('category');
      merged.remove('folder');
      merged.remove('collection');
    }
    if (_hasAnyKey(row, const ['tags', 'labels', 'tag', 'label', '标签', '标记'])) {
      merged.remove('tag');
    }
    row.forEach((key, value) {
      merged[key] = value;
    });
    return merged;
  }

  bool _hasAnyKey(Map<String, dynamic> map, List<String> keys) {
    final normalizedKeys = map.keys.map(
      (key) => _normalizeHeader(key.toString()),
    );
    return normalizedKeys.any(
      (key) => keys.map(_normalizeHeader).contains(key),
    );
  }

  CompetitorTaskImportResult _parseCsv(
    String text, {
    required CompetitorFieldMapping fieldMapping,
  }) {
    final warnings = <String>[];
    final table = _parseCsvTable(text);
    if (table.isEmpty) {
      return const CompetitorTaskImportResult(
        todos: [],
        skippedRows: 0,
        warnings: ['CSV 内容为空'],
        sourceLabel: 'CSV',
      );
    }
    if (table.length == 1) {
      return const CompetitorTaskImportResult(
        todos: [],
        skippedRows: 0,
        warnings: ['CSV 只有表头，没有任务行'],
        sourceLabel: 'CSV',
      );
    }

    final headers = table.first.map(_normalizeHeader).toList();
    final todos = <TodoItem>[];
    final habits = <Habit>[];
    final notes = <NoteItem>[];
    final calendarEvents = <CalendarEvent>[];
    final anniversaries = <Anniversary>[];
    final countdowns = <CountdownItem>[];
    final timeEntries = <TimeEntry>[];
    var skipped = 0;
    for (var i = 1; i < table.length; i++) {
      final row = table[i];
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      final map = <String, dynamic>{};
      for (var c = 0; c < headers.length; c++) {
        if (headers[c].isEmpty) continue;
        map[headers[c]] = c < row.length ? row[c] : '';
      }
      final parsed = _itemFromMap(
        _applyFieldMapping(map, fieldMapping),
        warnings,
        rowNumber: i + 1,
      );
      if (parsed == null) {
        skipped++;
        continue;
      }
      if (parsed is TodoItem) {
        todos.add(parsed);
      } else if (parsed is Habit) {
        habits.add(parsed);
      } else if (parsed is NoteItem) {
        notes.add(parsed);
      } else if (parsed is CalendarEvent) {
        calendarEvents.add(parsed);
      } else if (parsed is Anniversary) {
        anniversaries.add(parsed);
      } else if (parsed is CountdownItem) {
        countdowns.add(parsed);
      } else if (parsed is TimeEntry) {
        timeEntries.add(parsed);
      }
    }

    return CompetitorTaskImportResult(
      todos: todos,
      habits: habits,
      notes: notes,
      calendarEvents: calendarEvents,
      anniversaries: anniversaries,
      countdowns: countdowns,
      timeEntries: timeEntries,
      skippedRows: skipped,
      warnings: warnings,
      sourceLabel: 'CSV',
    );
  }

  List<List<String>> _parseCsvTable(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (inQuotes) {
        if (char == '"') {
          final hasEscapedQuote = i + 1 < text.length && text[i + 1] == '"';
          if (hasEscapedQuote) {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(char);
        }
        continue;
      }

      if (char == '"') {
        inQuotes = true;
      } else if (char == ',') {
        row.add(field.toString());
        field.clear();
      } else if (char == '\n') {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else if (char != '\r') {
        field.write(char);
      }
    }

    row.add(field.toString());
    if (row.length > 1 || row.first.trim().isNotEmpty) {
      rows.add(row);
    }
    return rows;
  }

  Map<String, dynamic> _applyFieldMapping(
    Map<String, dynamic> row,
    CompetitorFieldMapping fieldMapping,
  ) {
    if (fieldMapping.isEmpty) return row;
    final result = Map<String, dynamic>.from(row);
    for (final entry in fieldMapping.targetToSource.entries) {
      final target = entry.key.trim();
      final source = entry.value.trim();
      if (target.isEmpty || source.isEmpty) continue;
      dynamic sourceValue;
      var found = false;
      final normalizedSource = _normalizeHeader(source);
      for (final rowEntry in row.entries) {
        if (_normalizeHeader(rowEntry.key.toString()) != normalizedSource) {
          continue;
        }
        sourceValue = rowEntry.value;
        found = true;
        break;
      }
      if (found) {
        result[target] = sourceValue;
      }
    }
    return result;
  }

  Object? _itemFromMap(
    Map<String, dynamic> raw,
    List<String> warnings, {
    required int rowNumber,
  }) {
    final map = <String, dynamic>{};
    raw.forEach((key, value) {
      map[_normalizeHeader(key.toString())] = value;
    });
    final type = _firstText(map, const [
      'type',
      'kind',
      'module',
      '模块',
      '类型',
    ])?.trim().toLowerCase();
    if (type != null) {
      if (const {'habit', 'habits', '习惯', '打卡'}.contains(type)) {
        return _habitFromMap(map, warnings, rowNumber: rowNumber);
      }
      if (const {'note', 'notes', 'memo', '备忘录', '笔记', '便签'}.contains(type)) {
        return _noteFromMap(map, warnings, rowNumber: rowNumber);
      }
      if (const {
        'event',
        'events',
        'calendar',
        'schedule',
        '日程',
        '日历',
        '事件',
      }.contains(type)) {
        return _calendarEventFromMap(map, warnings, rowNumber: rowNumber);
      }
      if (const {'birthday', 'birthdays', '生日'}.contains(type)) {
        return _anniversaryFromMap(
          map,
          warnings,
          rowNumber: rowNumber,
          fallbackType: AnniversaryType.birthday,
        );
      }
      if (const {
        'anniversary',
        'anniversaries',
        'memorial',
        '纪念日',
        '周年',
      }.contains(type)) {
        return _anniversaryFromMap(
          map,
          warnings,
          rowNumber: rowNumber,
          fallbackType: AnniversaryType.memorial,
        );
      }
      if (const {'countdown', 'countdowns', '倒数日', '倒计时'}.contains(type)) {
        return _countdownFromMap(map, warnings, rowNumber: rowNumber);
      }
      if (const {
        'time',
        'timeentry',
        'time_entry',
        'timeentries',
        'time_entries',
        'timelog',
        'time_log',
        'timelogs',
        'time_logs',
        'timeaudit',
        '时间足迹',
        '时间记录',
        '时光足迹',
        '耗时',
      }.contains(type)) {
        return _timeEntryFromMap(map, warnings, rowNumber: rowNumber);
      }
    }
    final hasHabitSignal =
        _firstText(map, const [
              'target',
              'targetcount',
              '目标次数',
              '单位',
              'unit',
              '打卡记录',
            ]) !=
            null ||
        _firstText(map, const ['activeweekdays', 'repeatdays', '打卡日']) != null;
    final hasNoteSignal =
        _firstText(map, const [
              'body',
              'note',
              'notes',
              'memo',
              '正文',
              '笔记内容',
              '备注',
            ]) !=
            null &&
        _firstText(map, const ['due', 'deadline', 'date', 'duedate', '截止']) ==
            null;
    final hasTimeEntrySignal =
        _firstText(map, const ['duration', 'durationminutes', '耗时', '时长']) !=
            null &&
        _firstText(map, const ['start', 'starttime', '开始时间']) != null &&
        _firstText(map, const ['due', 'deadline', '截止']) == null;
    if (hasHabitSignal) {
      return _habitFromMap(map, warnings, rowNumber: rowNumber);
    }
    if (hasTimeEntrySignal) {
      return _timeEntryFromMap(map, warnings, rowNumber: rowNumber);
    }
    if (hasNoteSignal && _firstText(map, const ['task', '任务']) == null) {
      return _noteFromMap(map, warnings, rowNumber: rowNumber);
    }
    return _todoFromMap(map, warnings, rowNumber: rowNumber);
  }

  TodoItem? _todoFromMap(
    Map<String, dynamic> raw,
    List<String> warnings, {
    required int rowNumber,
  }) {
    final map = <String, dynamic>{};
    raw.forEach((key, value) {
      map[_normalizeHeader(key.toString())] = value;
    });

    final title = _firstText(map, const [
      'title',
      'content',
      'name',
      'task',
      'todo',
      'item',
      'subject',
      '任务',
      '标题',
      '内容',
      '事项',
      '待办',
      '名称',
    ]);
    if (title == null || title.trim().isEmpty) {
      warnings.add('第 $rowNumber 行缺少标题，已跳过');
      return null;
    }

    final start = _parseDate(
      _firstText(map, const [
        'start',
        'startdate',
        'starttime',
        'begintime',
        'begin',
        '开始',
        '开始时间',
        '起始时间',
      ]),
    );
    final due = _parseDate(
      _firstText(map, const [
        'due',
        'deadline',
        'date',
        'duedate',
        'end',
        'enddate',
        'endtime',
        'finishtime',
        '截止',
        '截止时间',
        '日期',
        '结束',
        '结束时间',
        '完成期限',
      ]),
    );
    final completed = _parseBool(
      _firstText(map, const [
        'completed',
        'done',
        'status',
        'finished',
        'isdone',
        '完成',
        '已完成',
        '状态',
      ]),
    );
    final parsedCompletedAt = _parseDate(
      _firstText(map, const [
        'completedat',
        'completiontime',
        'finishedat',
        'donetime',
        '完成时间',
        '完成日期',
      ]),
    );
    final reminderAt = _parseDate(
      _firstText(map, const [
        'reminderat',
        'remindat',
        'remindtime',
        'alarmtime',
        '提醒时间',
        '提醒日期',
      ]),
    );
    final remindTime = _parseHourMinute(
      _firstText(map, const ['reminder', 'remind', 'alarm', '提醒', '提醒时间']),
    );
    final reminderEnabled =
        reminderAt != null ||
        remindTime != null ||
        _parseBool(
          _firstText(map, const [
            'hasreminder',
            'remind',
            'reminder',
            'alarm',
            '提醒',
            '是否提醒',
          ]),
        );
    final now = DateTime.now();
    final completedAt = completed ? (parsedCompletedAt ?? now) : null;
    final effectiveDate = start ?? due ?? now;

    return TodoItem(
      title: title.trim(),
      notes:
          _firstText(map, const [
            'notes',
            'description',
            'note',
            'details',
            '备注',
            '描述',
            '详情',
          ])?.trim() ??
          '',
      isCompleted: completed,
      quadrant: _parseQuadrant(
        _firstText(map, const ['quadrant', 'eisenhower', '四象限', '象限']),
      ),
      priority: _parsePriority(
        _firstText(map, const ['priority', 'prio', 'p', 'importance', '优先级']),
      ),
      listGroupName: _emptyToNull(
        _firstText(map, const [
          'list',
          'project',
          'category',
          'folder',
          'group',
          'collection',
          'tasklist',
          'taskgroup',
          '清单',
          '项目',
          '分类',
          '列表',
          '目录',
          '文件夹',
          '分组',
        ]),
      ),
      tags: _parseTags(
        _firstText(map, const ['tags', 'labels', 'tag', 'label', '标签', '标记']),
      ),
      dueDate: due,
      date: DateTime(
        effectiveDate.year,
        effectiveDate.month,
        effectiveDate.day,
      ),
      hasReminder: reminderEnabled,
      reminderAt: reminderAt,
      reminder: reminderEnabled
          ? ReminderConfig(
              enabled: true,
              kind: ReminderKind.push,
              hour: reminderAt?.hour ?? remindTime?.$1,
              minute: reminderAt?.minute ?? remindTime?.$2,
            )
          : const ReminderConfig.disabled(),
      recurrence: _parseRecurrence(
        _firstText(map, const [
          'repeat',
          'recurrence',
          'rrule',
          '重复',
          '重复规则',
          '循环',
        ]),
      ),
      completedAt: completedAt,
      createdAt:
          _parseDate(
            _firstText(map, const [
              'created',
              'createdat',
              'createdtime',
              '创建时间',
            ]),
          ) ??
          now,
      updatedAt:
          _parseDate(
            _firstText(map, const [
              'updated',
              'updatedat',
              'updatedtime',
              '更新时间',
            ]),
          ) ??
          now,
    );
  }

  Habit? _habitFromMap(
    Map<String, dynamic> raw,
    List<String> warnings, {
    required int rowNumber,
  }) {
    final name = _firstText(raw, const [
      'name',
      'title',
      'habit',
      '习惯',
      '标题',
      '名称',
    ]);
    if (name == null || name.trim().isEmpty) {
      warnings.add('第 $rowNumber 行缺少习惯名称，已跳过');
      return null;
    }
    final now = DateTime.now();
    final completions = _parseCompletions(
      _firstText(raw, const ['completions', 'records', 'history', '打卡记录']),
    );
    final remindTime = _parseHourMinute(
      _firstText(raw, const ['remindtime', 'reminder', '提醒时间']),
    );
    return Habit(
      id: 'imported_habit_${now.microsecondsSinceEpoch}_$rowNumber',
      name: name.trim(),
      kind: _parseHabitKind(
        _firstText(raw, const ['kind', 'type', 'habitkind', '类型']),
      ),
      category: _emptyToNull(
        _firstText(raw, const ['category', 'group', 'folder', '分类', '分组']),
      ),
      tags: _parseTags(_firstText(raw, const ['tags', 'labels', 'tag', '标签'])),
      targetCount: _parsePositiveInt(
        _firstText(raw, const ['target', 'targetcount', 'goal', '目标次数']),
        fallback: 1,
      ),
      unit: _emptyToNull(_firstText(raw, const ['unit', '单位'])),
      activeWeekdays: _parseWeekdays(
        _firstText(raw, const ['activeweekdays', 'repeatdays', '重复', '打卡日']),
      ),
      weeklyTarget: _parsePositiveInt(
        _firstText(raw, const ['weeklytarget', '周目标']),
        fallback: 7,
      ),
      completions: completions,
      startDate: _parseDate(
        _firstText(raw, const ['start', 'startdate', '开始']),
      ),
      endDate: _parseDate(_firstText(raw, const ['end', 'enddate', '结束'])),
      remind: _parseBool(_firstText(raw, const ['remind', '提醒'])),
      remindHour: remindTime?.$1,
      remindMinute: remindTime?.$2,
      createdAt:
          _parseDate(_firstText(raw, const ['created', 'createdat', '创建时间'])) ??
          now,
    );
  }

  NoteItem? _noteFromMap(
    Map<String, dynamic> raw,
    List<String> warnings, {
    required int rowNumber,
  }) {
    final title = _firstText(raw, const ['title', 'name', '标题', '名称']);
    final body = _firstText(raw, const [
      'body',
      'content',
      'note',
      'notes',
      'memo',
      '正文',
      '内容',
      '笔记内容',
      '备注',
    ]);
    final content = [title, body]
        .where((part) => part != null && part.trim().isNotEmpty)
        .map((part) => part!.trim())
        .join('\n\n');
    if (content.trim().isEmpty) {
      warnings.add('第 $rowNumber 行缺少笔记内容，已跳过');
      return null;
    }
    final now = DateTime.now();
    final attachments = _parseNoteAttachments(
      _firstText(raw, const ['attachments', 'files', 'links', '附件', '链接']),
    );
    return NoteItem(
      id: 'imported_note_${now.microsecondsSinceEpoch}_$rowNumber',
      content: content,
      attachments: attachments,
      createdAt:
          _parseDate(_firstText(raw, const ['created', 'createdat', '创建时间'])) ??
          now,
      updatedAt:
          _parseDate(_firstText(raw, const ['updated', 'updatedat', '更新时间'])) ??
          now,
    );
  }

  CalendarEvent? _calendarEventFromMap(
    Map<String, dynamic> raw,
    List<String> warnings, {
    required int rowNumber,
  }) {
    final title = _firstText(raw, const [
      'title',
      'name',
      'summary',
      'event',
      'schedule',
      '日程',
      '事件',
      '标题',
      '名称',
    ]);
    if (title == null || title.trim().isEmpty) {
      warnings.add('第 $rowNumber 行缺少日程标题，已跳过');
      return null;
    }
    final start =
        _parseDate(
          _firstText(raw, const [
            'start',
            'starttime',
            'startdate',
            'date',
            '日期',
            '开始',
            '开始时间',
          ]),
        ) ??
        _parseDate(_firstText(raw, const ['due', 'deadline', '截止']));
    if (start == null) {
      warnings.add('第 $rowNumber 行缺少日程日期，已跳过');
      return null;
    }
    final end = _parseDate(
      _firstText(raw, const ['end', 'endtime', 'enddate', '结束', '结束时间']),
    );
    final projectName = _emptyToNull(
      _firstText(raw, const [
        'calendar',
        'project',
        'category',
        '日历',
        '项目',
        '分类',
      ]),
    );
    final note = _emptyToNull(
      _firstText(raw, const ['notes', 'description', 'note', '备注', '描述']),
    );
    final hasTime =
        _firstText(raw, const ['time', 'starttime', '开始时间']) != null ||
        start.hour != 0 ||
        start.minute != 0;
    return CalendarEvent(
      id: 'imported_event_${DateTime.now().microsecondsSinceEpoch}_$rowNumber',
      title: title.trim(),
      date: start,
      endDate: end,
      type: CalendarEventType.event,
      color: const Color(0xFF5B6EE1),
      sourceId: 'imported_event_$rowNumber',
      projectName: projectName,
      subtitle: projectName,
      note: note,
      time: hasTime ? TimeOfDay(hour: start.hour, minute: start.minute) : null,
    );
  }

  Anniversary? _anniversaryFromMap(
    Map<String, dynamic> raw,
    List<String> warnings, {
    required int rowNumber,
    required AnniversaryType fallbackType,
  }) {
    final title = _firstText(raw, const [
      'title',
      'name',
      'anniversary',
      'birthday',
      '纪念日',
      '生日',
      '标题',
      '名称',
    ]);
    if (title == null || title.trim().isEmpty) {
      warnings.add('第 $rowNumber 行缺少纪念日标题，已跳过');
      return null;
    }
    final date = _parseDate(
      _firstText(raw, const [
        'date',
        'origin',
        'origindate',
        'birthday',
        'targetdate',
        '日期',
        '生日',
        '纪念日期',
      ]),
    );
    if (date == null) {
      warnings.add('第 $rowNumber 行缺少纪念日日期，已跳过');
      return null;
    }
    final remindTime = _parseHourMinute(
      _firstText(raw, const ['remindtime', 'reminder', '提醒时间']),
    );
    final calendarType = _parseAnniversaryCalendarType(
      _firstText(raw, const ['calendar', 'calendartype', '历法', '日历类型']),
    );
    return Anniversary.create(
      id: 'imported_anniversary_${DateTime.now().microsecondsSinceEpoch}_$rowNumber',
      title: title.trim(),
      description: _emptyToNull(
        _firstText(raw, const ['description', 'note', 'notes', '备注', '描述']),
      ),
      solarDate: date,
      type: _parseAnniversaryType(
        _firstText(raw, const ['anniversarytype', 'type', 'kind', '类型']),
        fallbackType,
      ),
      calendarType: calendarType,
      isPinned: _parseBool(_firstText(raw, const ['pinned', 'pin', '置顶'])),
      remind: _parseBool(_firstText(raw, const ['remind', '提醒'])),
      remindDaysBefore: _parseNonNegativeInt(
        _firstText(raw, const ['reminddaysbefore', '提前天数']),
        fallback: 1,
      ),
      remindHour: remindTime?.$1 ?? 9,
      remindMinute: remindTime?.$2 ?? 0,
    );
  }

  CountdownItem? _countdownFromMap(
    Map<String, dynamic> raw,
    List<String> warnings, {
    required int rowNumber,
  }) {
    final title = _firstText(raw, const [
      'title',
      'name',
      'countdown',
      '倒数日',
      '倒计时',
      '标题',
      '名称',
    ]);
    if (title == null || title.trim().isEmpty) {
      warnings.add('第 $rowNumber 行缺少倒数日标题，已跳过');
      return null;
    }
    final targetDate = _parseDate(
      _firstText(raw, const [
        'targetdate',
        'target',
        'date',
        'due',
        'deadline',
        'end',
        '截止',
        '日期',
        '目标日期',
      ]),
    );
    if (targetDate == null) {
      warnings.add('第 $rowNumber 行缺少倒数日日期，已跳过');
      return null;
    }
    final remindTime = _parseHourMinute(
      _firstText(raw, const ['remindtime', 'reminder', '提醒时间']),
    );
    return CountdownItem(
      id: 'imported_countdown_${DateTime.now().microsecondsSinceEpoch}_$rowNumber',
      title: title.trim(),
      targetDate: targetDate,
      category:
          _emptyToNull(
            _firstText(raw, const ['category', 'group', 'folder', '分类', '分组']),
          ) ??
          '默认',
      isPinned: _parseBool(_firstText(raw, const ['pinned', 'pin', '置顶'])),
      remind: _parseBool(_firstText(raw, const ['remind', '提醒'])),
      remindDaysBefore: _parseNonNegativeInt(
        _firstText(raw, const ['reminddaysbefore', '提前天数']),
        fallback: 1,
      ),
      remindHour: remindTime?.$1 ?? 9,
      remindMinute: remindTime?.$2 ?? 0,
      reminderKind: ReminderKind.push,
    );
  }

  TimeEntry? _timeEntryFromMap(
    Map<String, dynamic> raw,
    List<String> warnings, {
    required int rowNumber,
  }) {
    final title = _firstText(raw, const [
      'title',
      'name',
      'task',
      'subject',
      'activity',
      'item',
      '标题',
      '名称',
      '事项',
      '活动',
    ]);
    if (title == null || title.trim().isEmpty) {
      warnings.add('第 $rowNumber 行缺少时间足迹标题，已跳过');
      return null;
    }
    final start = _parseDate(
      _firstText(raw, const [
        'start',
        'startat',
        'starttime',
        'begin',
        'begintime',
        'date',
        'time',
        '开始',
        '开始时间',
        '日期',
      ]),
    );
    if (start == null) {
      warnings.add('第 $rowNumber 行缺少时间足迹开始时间，已跳过');
      return null;
    }
    final explicitEnd = _parseDate(
      _firstText(raw, const [
        'end',
        'endat',
        'endtime',
        'finish',
        'finishtime',
        '结束',
        '结束时间',
      ]),
    );
    final durationSeconds = _parseDurationSeconds(
      _firstText(raw, const [
        'duration',
        'durationminutes',
        'minutes',
        'mins',
        'hours',
        'seconds',
        '耗时',
        '时长',
        '分钟',
        '小时',
      ]),
    );
    final end =
        explicitEnd ??
        (durationSeconds == null
            ? null
            : start.add(Duration(seconds: durationSeconds)));
    if (end == null || !end.isAfter(start)) {
      warnings.add('第 $rowNumber 行时间足迹结束时间或时长无效，已跳过');
      return null;
    }
    final now = DateTime.now();
    return TimeEntry(
      id: 'imported_time_${now.microsecondsSinceEpoch}_$rowNumber',
      title: title.trim(),
      startAt: start,
      endAt: end,
      category: _parseTimeEntryCategory(
        _firstText(raw, const ['category', 'typecategory', '分类', '分组']),
      ),
      source: _parseTimeEntrySource(
        _firstText(raw, const ['source', 'origin', '来源']),
      ),
      sourceId: _emptyToNull(
        _firstText(raw, const ['sourceid', 'source_id', '关联ID', '来源ID']),
      ),
      dedupeKey: _emptyToNull(
        _firstText(raw, const ['dedupekey', 'dedupe_key', '去重键']),
      ),
      note:
          _firstText(raw, const [
            'note',
            'notes',
            'description',
            '备注',
            '描述',
          ])?.trim() ??
          '',
      createdAt:
          _parseDate(_firstText(raw, const ['created', 'createdat', '创建时间'])) ??
          now,
      updatedAt:
          _parseDate(_firstText(raw, const ['updated', 'updatedat', '更新时间'])) ??
          now,
    );
  }

  String _normalizeHeader(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_\-]+'), '')
      .replaceAll('（', '(')
      .replaceAll('）', ')');

  String? _firstText(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[_normalizeHeader(key)];
      if (value == null) continue;
      if (value is List) return value.join(',');
      final text = value.toString();
      if (text.trim().isNotEmpty) return text;
    }
    return null;
  }

  String? _emptyToNull(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  DateTime? _parseDate(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;
    final match = RegExp(
      r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})(?:\s+(\d{1,2}):(\d{1,2}))?',
    ).firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.tryParse(match.group(4) ?? '') ?? 0;
    final minute = int.tryParse(match.group(5) ?? '') ?? 0;
    return DateTime(year, month, day, hour, minute);
  }

  RecurrenceRule _parseRecurrence(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return const RecurrenceRule();
    if (const {'none', 'never', 'no', '不重复', '无'}.contains(text)) {
      return const RecurrenceRule();
    }
    if (text.contains('daily') ||
        text.contains('every day') ||
        text.contains('每天')) {
      return const RecurrenceRule(frequency: RecurrenceFrequency.daily);
    }
    if (text.contains('weekly') ||
        text.contains('every week') ||
        text.contains('每周')) {
      return RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        byWeekdays: _parseWeekdays(text),
      );
    }
    if (text.contains('monthly') ||
        text.contains('every month') ||
        text.contains('每月')) {
      return const RecurrenceRule(frequency: RecurrenceFrequency.monthly);
    }
    if (text.contains('yearly') ||
        text.contains('annually') ||
        text.contains('every year') ||
        text.contains('每年')) {
      return const RecurrenceRule(frequency: RecurrenceFrequency.yearly);
    }
    return const RecurrenceRule();
  }

  bool _parseBool(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return false;
    return const {
      '1',
      'true',
      'yes',
      'y',
      'done',
      'completed',
      'complete',
      'finished',
      '已完成',
      '完成',
      '是',
    }.contains(text);
  }

  int _parsePositiveInt(String? value, {required int fallback}) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 1) return fallback;
    return parsed;
  }

  int _parseNonNegativeInt(String? value, {required int fallback}) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) return fallback;
    return parsed;
  }

  AnniversaryType _parseAnniversaryType(
    String? value,
    AnniversaryType fallback,
  ) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return fallback;
    if (const {'birthday', '生日'}.contains(text)) {
      return AnniversaryType.birthday;
    }
    if (const {'memorial', 'anniversary', '纪念日', '周年'}.contains(text)) {
      return AnniversaryType.memorial;
    }
    return fallback;
  }

  AnniversaryCalendarType _parseAnniversaryCalendarType(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return AnniversaryCalendarType.solar;
    if (const {'lunar', '农历', '阴历'}.contains(text)) {
      return AnniversaryCalendarType.lunar;
    }
    return AnniversaryCalendarType.solar;
  }

  HabitKind _parseHabitKind(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return HabitKind.positive;
    if (const {'negative', 'bad', 'quit', '戒除', '负向', '坏习惯'}.contains(text)) {
      return HabitKind.negative;
    }
    return HabitKind.positive;
  }

  List<int> _parseWeekdays(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return const [0, 1, 2, 3, 4, 5, 6];
    if (text.contains('每天') || text.contains('everyday')) {
      return const [0, 1, 2, 3, 4, 5, 6];
    }
    if (text.contains('工作日') || text.contains('weekday')) {
      return const [0, 1, 2, 3, 4];
    }
    const aliases = {
      'mon': 0,
      'monday': 0,
      '周一': 0,
      '星期一': 0,
      'tue': 1,
      'tuesday': 1,
      '周二': 1,
      '星期二': 1,
      'wed': 2,
      'wednesday': 2,
      '周三': 2,
      '星期三': 2,
      'thu': 3,
      'thursday': 3,
      '周四': 3,
      '星期四': 3,
      'fri': 4,
      'friday': 4,
      '周五': 4,
      '星期五': 4,
      'sat': 5,
      'saturday': 5,
      '周六': 5,
      '星期六': 5,
      'sun': 6,
      'sunday': 6,
      '周日': 6,
      '周天': 6,
      '星期日': 6,
      '星期天': 6,
    };
    final result = <int>{};
    for (final part in text.split(RegExp(r'[,;|/、\s]+'))) {
      if (part.isEmpty) continue;
      final number = int.tryParse(part);
      if (number != null && number >= 1 && number <= 7) {
        result.add(number - 1);
        continue;
      }
      final mapped = aliases[part];
      if (mapped != null) result.add(mapped);
    }
    if (result.isEmpty) return const [0, 1, 2, 3, 4, 5, 6];
    return result.toList()..sort();
  }

  Map<String, int> _parseCompletions(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return {};
    final result = <String, int>{};
    for (final part in text.split(RegExp(r'[,;|]'))) {
      final segment = part.trim();
      if (segment.isEmpty) continue;
      final pieces = segment.split(RegExp(r'[:=]'));
      final date = _parseDate(pieces.first.trim());
      if (date == null) continue;
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final count = pieces.length > 1 ? int.tryParse(pieces[1].trim()) ?? 1 : 1;
      result[key] = count < 1 ? 1 : count;
    }
    return result;
  }

  (int, int)? _parseHourMinute(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'(\d{1,2}):(\d{1,2})').firstMatch(text);
    if (match == null) return null;
    return (
      int.parse(match.group(1)!).clamp(0, 23).toInt(),
      int.parse(match.group(2)!).clamp(0, 59).toInt(),
    );
  }

  int? _parseDurationSeconds(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return null;
    final number = double.tryParse(text.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (number == null || number <= 0) return null;
    if (text.contains('小时') || text.contains('hour') || text.endsWith('h')) {
      return (number * 3600).round();
    }
    if (text.contains('秒') || text.contains('second') || text.endsWith('s')) {
      return number.round();
    }
    return (number * 60).round();
  }

  TimeEntryCategory _parseTimeEntryCategory(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return TimeEntryCategory.other;
    if (const {'focus', 'pomodoro', '专注', '番茄', '番茄钟'}.contains(text)) {
      return TimeEntryCategory.focus;
    }
    if (const {'todo', 'task', '待办', '任务'}.contains(text)) {
      return TimeEntryCategory.todo;
    }
    if (const {'habit', '习惯', '打卡'}.contains(text)) {
      return TimeEntryCategory.habit;
    }
    if (const {'goal', '目标'}.contains(text)) return TimeEntryCategory.goal;
    if (const {'study', '学习'}.contains(text)) return TimeEntryCategory.study;
    if (const {'work', '工作'}.contains(text)) return TimeEntryCategory.work;
    if (const {'life', '生活'}.contains(text)) return TimeEntryCategory.life;
    return TimeEntryCategory.other;
  }

  TimeEntrySource _parseTimeEntrySource(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return TimeEntrySource.manual;
    if (const {'pomodoro', 'focus', '番茄', '番茄钟', '专注'}.contains(text)) {
      return TimeEntrySource.pomodoro;
    }
    if (const {'todo', 'task', '待办', '任务'}.contains(text)) {
      return TimeEntrySource.todo;
    }
    if (const {'habit', '习惯', '打卡'}.contains(text)) {
      return TimeEntrySource.habit;
    }
    if (const {'goal', '目标'}.contains(text)) return TimeEntrySource.goal;
    return TimeEntrySource.manual;
  }

  List<NoteAttachment> _parseNoteAttachments(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return const [];
    return text
        .split(RegExp(r'[,;|]'))
        .map((raw) => raw.trim())
        .where((uri) => uri.isNotEmpty)
        .map((uri) {
          final name = Uri.tryParse(uri)?.pathSegments.last;
          return NoteAttachment(
            name: name == null || name.isEmpty ? uri : name,
            uri: uri,
            mimeType: uri.toLowerCase().endsWith('.pdf')
                ? 'application/pdf'
                : '',
          );
        })
        .toList();
  }

  TodoPriority _parsePriority(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return TodoPriority.none;
    if (const {
      'urgent',
      'highest',
      'p0',
      'p1',
      '4',
      '紧急',
      '最高',
    }.contains(text)) {
      return TodoPriority.urgent;
    }
    if (const {'high', 'p2', '3', '高'}.contains(text)) {
      return TodoPriority.high;
    }
    if (const {'medium', 'normal', 'p3', '2', '中', '普通'}.contains(text)) {
      return TodoPriority.medium;
    }
    if (const {'low', 'p4', '1', '低'}.contains(text)) {
      return TodoPriority.low;
    }
    return TodoPriority.none;
  }

  EisenhowerQuadrant _parseQuadrant(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) {
      return EisenhowerQuadrant.notUrgentImportant;
    }
    if (const {'q1', '1', 'urgentimportant', '重要且紧急', '紧急重要'}.contains(text)) {
      return EisenhowerQuadrant.urgentImportant;
    }
    if (const {
      'q2',
      '2',
      'noturgentimportant',
      '重要不紧急',
      '不紧急重要',
    }.contains(text)) {
      return EisenhowerQuadrant.notUrgentImportant;
    }
    if (const {'q3', '3', 'urgentnotimportant', '紧急不重要'}.contains(text)) {
      return EisenhowerQuadrant.urgentNotImportant;
    }
    if (const {'q4', '4', 'noturgentnotimportant', '不重要不紧急'}.contains(text)) {
      return EisenhowerQuadrant.notUrgentNotImportant;
    }
    return EisenhowerQuadrant.notUrgentImportant;
  }

  List<String> _parseTags(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return const [];
    final normalized = text
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '');
    return normalized
        .split(RegExp(r'[,;|]'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
  }
}
