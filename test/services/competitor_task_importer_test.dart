import 'dart:convert';
import 'dart:io';

import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/services/competitor_task_importer.dart';
import 'package:test/test.dart';

void main() {
  test('CompetitorTaskImporter supports account-level JSON envelopes', () {
    final result = const CompetitorTaskImporter().parse(
      jsonEncode({
        'workspaces': [
          {
            'name': '个人空间',
            'projects': [
              {
                'name': '家庭项目',
                'tasks': [
                  {
                    'title': '换滤芯',
                    'deadline': '2026-06-01 09:30',
                    'tags': '家务',
                  },
                ],
              },
            ],
          },
        ],
        'categories': [
          {
            'name': '健康',
            'todos': [
              {'content': '预约体检'},
            ],
          },
        ],
        'tags': [
          {
            'name': '重要',
            'items': [
              {'task': '准备材料'},
            ],
          },
        ],
      }),
    );

    expect(result.warnings, isEmpty);
    expect(result.skippedRows, 0);
    expect(
      result.todos.map((todo) => todo.title),
      unorderedEquals(['换滤芯', '预约体检', '准备材料']),
    );
    final filterTask = result.todos.singleWhere((todo) => todo.title == '换滤芯');
    final healthTask = result.todos.singleWhere((todo) => todo.title == '预约体检');
    final importantTask = result.todos.singleWhere(
      (todo) => todo.title == '准备材料',
    );
    expect(filterTask.listGroupName, '家庭项目');
    expect(filterTask.tags, contains('家务'));
    expect(healthTask.listGroupName, '健康');
    expect(importantTask.tags, contains('重要'));
    expect(filterTask.dueDate, DateTime(2026, 6, 1, 9, 30));
  });

  test(
    'CompetitorTaskImporter inherits nested list names without overwriting child fields',
    () {
      final result = const CompetitorTaskImporter().parse(
        jsonEncode({
          'projects': [
            {
              'name': '项目 A',
              'lists': [
                {
                  'name': '本周清单',
                  'tasks': [
                    {'title': '沿用清单'},
                    {'title': '已有分类', 'project': '子项目'},
                  ],
                },
              ],
            },
          ],
        }),
      );

      expect(result.warnings, isEmpty);
      expect(result.todos, hasLength(2));
      expect(result.todos[0].listGroupName, '本周清单');
      expect(result.todos[1].listGroupName, '子项目');
    },
  );

  test('CompetitorTaskImporter supports id-keyed account JSON maps', () {
    final result = const CompetitorTaskImporter().parse(
      jsonEncode({
        'projects': {
          'p1': {
            'name': '客户项目',
            'tasks': {
              't1': {
                'title': '回访客户',
                'labels': ['CRM', '重要'],
              },
              't2': {'title': '单独清单', 'list': '售后'},
            },
          },
        },
        'tasks': {
          't3': {'title': '顶层任务', 'category': '收件箱'},
        },
      }),
    );

    expect(result.warnings, isEmpty);
    expect(
      result.todos.map((todo) => todo.title),
      unorderedEquals(['回访客户', '单独清单', '顶层任务']),
    );
    final inherited = result.todos.singleWhere((todo) => todo.title == '回访客户');
    final explicit = result.todos.singleWhere((todo) => todo.title == '单独清单');
    final topLevel = result.todos.singleWhere((todo) => todo.title == '顶层任务');
    expect(inherited.listGroupName, '客户项目');
    expect(inherited.tags, containsAll(['CRM', '重要']));
    expect(explicit.listGroupName, '售后');
    expect(topLevel.listGroupName, '收件箱');
  });

  test('CompetitorTaskImporter parses Chinese CSV task fields', () {
    const csv =
        '标题,清单,标签,开始时间,结束时间,重复,提醒,完成,完成时间\n'
        '写周报,工作,"复盘;重要",2026-05-20,2026-05-21 18:00,每周,09:15,是,2026-05-21 17:30\n';

    final result = const CompetitorTaskImporter().parse(csv);

    expect(result.warnings, isEmpty);
    expect(result.todos, hasLength(1));
    final todo = result.todos.single;
    expect(todo.title, '写周报');
    expect(todo.listGroupName, '工作');
    expect(todo.tags, containsAll(['复盘', '重要']));
    expect(todo.date, DateTime(2026, 5, 20));
    expect(todo.dueDate, DateTime(2026, 5, 21, 18));
    expect(todo.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(todo.hasReminder, isTrue);
    expect(todo.reminder.hour, 9);
    expect(todo.reminder.minute, 15);
    expect(todo.isCompleted, isTrue);
    expect(todo.completedAt, DateTime(2026, 5, 21, 17, 30));
  });

  test('CompetitorTaskImporter applies editable field mappings for CSV', () {
    const csv = '任务名,分组名,截止,重要度\n买牛奶,生活,2026-06-02 08:00,高\n';

    final result = const CompetitorTaskImporter().parse(
      csv,
      fieldMapping: const CompetitorFieldMapping({
        'title': '任务名',
        'list': '分组名',
        'due': '截止',
        'priority': '重要度',
      }),
    );

    expect(result.warnings, isEmpty);
    expect(result.todos, hasLength(1));
    final todo = result.todos.single;
    expect(todo.title, '买牛奶');
    expect(todo.listGroupName, '生活');
    expect(todo.dueDate, DateTime(2026, 6, 2, 8));
    expect(todo.priority, TodoPriority.high);
  });

  test('CompetitorTaskImporter applies editable field mappings for JSON', () {
    final result = const CompetitorTaskImporter().parse(
      jsonEncode([
        {'任务名': '回访客户', '分组': 'CRM', '日期': '2026-06-03'},
      ]),
      fieldMapping: const CompetitorFieldMapping({
        'title': '任务名',
        'list': '分组',
        'due': '日期',
      }),
    );

    expect(result.warnings, isEmpty);
    expect(result.todos.single.title, '回访客户');
    expect(result.todos.single.listGroupName, 'CRM');
    expect(result.todos.single.dueDate, DateTime(2026, 6, 3));
  });

  test('CompetitorTaskImporter keeps generic content as a task signal', () {
    final source = File(
      'lib/services/competitor_task_importer.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("'title',\n      'content',\n      'name',\n      'task'"),
    );
    expect(source, isNot(contains("'body',\n              'content'")));
    expect(source, contains("'body',\n              'note'"));
  });

  test(
    'CompetitorTaskImporter supports mixed tasks, habits, notes, events and date modules with countdown creation',
    () {
      final source = File(
        'lib/services/competitor_task_importer.dart',
      ).readAsStringSync();

      expect(source, contains('final List<Habit> habits;'));
      expect(source, contains('final List<NoteItem> notes;'));
      expect(source, contains('final List<CalendarEvent> calendarEvents;'));
      expect(source, contains('final List<Anniversary> anniversaries;'));
      expect(source, contains('final List<CountdownItem> countdowns;'));
      expect(source, contains("('habits', 'habit')"));
      expect(source, contains("('notes', 'note')"));
      expect(source, contains("('events', 'event')"));
      expect(source, contains("('calendarEvents', 'event')"));
      expect(source, contains("('anniversaries', 'anniversary')"));
      expect(source, contains("('birthdays', 'birthday')"));
      expect(source, contains("('countdowns', 'countdown')"));
      expect(source, contains("const {'habit', 'habits', '习惯', '打卡'}"));
      expect(source, contains('Habit? _habitFromMap('));
      expect(source, contains('NoteItem? _noteFromMap('));
      expect(source, contains('CalendarEvent? _calendarEventFromMap('));
      expect(source, contains('Anniversary? _anniversaryFromMap('));
      expect(source, contains('CountdownItem? _countdownFromMap('));
    },
  );

  test('CompetitorTaskImporter parses explicit countdown rows', () {
    final result = const CompetitorTaskImporter().parse(
      'type,title,date\ncountdown,考试,2026-06-01\n',
    );

    expect(result.totalImported, 1);
    expect(result.skippedRows, 0);
    expect(result.warnings, isEmpty);
    expect(result.countdowns.single.title, '考试');
    expect(result.countdowns.single.targetDate, DateTime(2026, 6, 1));
  });

  test('CompetitorTaskImporter parses time entries from CSV', () {
    const csv =
        'type,title,start,end,duration,category,source,note\n'
        'time_entry,阅读,2026-05-20 20:00,2026-05-20 21:30,,学习,manual,纸质书\n'
        'time_entry,写方案,2026-05-21 09:00,,90,工作,todo,\n';

    final result = const CompetitorTaskImporter().parse(csv);

    expect(result.warnings, isEmpty);
    expect(result.timeEntries, hasLength(2));
    final reading = result.timeEntries.first;
    expect(reading.title, '阅读');
    expect(reading.startAt, DateTime(2026, 5, 20, 20));
    expect(reading.endAt, DateTime(2026, 5, 20, 21, 30));
    expect(reading.category, TimeEntryCategory.study);
    expect(reading.source, TimeEntrySource.manual);
    expect(reading.note, '纸质书');

    final work = result.timeEntries.last;
    expect(work.title, '写方案');
    expect(work.endAt, DateTime(2026, 5, 21, 10, 30));
    expect(work.category, TimeEntryCategory.work);
    expect(work.source, TimeEntrySource.todo);
  });

  test('CompetitorTaskImporter parses time entries from JSON envelope', () {
    final result = const CompetitorTaskImporter().parse(
      jsonEncode({
        'time_entries': [
          {
            'title': '晨间复盘',
            'start': '2026-05-22 07:30',
            'duration': '45 分钟',
            'category': '生活',
          },
        ],
      }),
    );

    expect(result.warnings, isEmpty);
    expect(result.timeEntries, hasLength(1));
    expect(result.timeEntries.single.title, '晨间复盘');
    expect(result.timeEntries.single.endAt, DateTime(2026, 5, 22, 8, 15));
    expect(result.timeEntries.single.category, TimeEntryCategory.life);
  });
}
