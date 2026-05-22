import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/smart_todo_draft.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind, ReminderRuleType;
import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/models/todo.dart';

void main() {
  final now = DateTime(2026, 5, 15, 10, 0);

  test('fromText strips date phrase and creates alarm reminder for time', () {
    final draft = SmartTodoDraftBuilder.fromText('明天下午3点开会', now: now);

    expect(draft.title, '开会');
    expect(draft.date, DateTime(2026, 5, 16, 15, 0));
    expect(draft.dueDate, DateTime(2026, 5, 16, 15, 0));
    expect(draft.reminderAt, DateTime(2026, 5, 16, 15, 0));
    expect(draft.hasReminder, isTrue);
    expect(draft.reminder.enabled, isTrue);
    expect(draft.reminder.kind, ReminderKind.alarm);
    expect(draft.reminder.hour, 15);
    expect(draft.reminder.minute, 0);
    expect(draft.reminderPlan.rules.single.type, ReminderRuleType.absolute);
  });

  test('fromText keeps date-only tasks without enabling reminder', () {
    final draft = SmartTodoDraftBuilder.fromText('后天买牛奶', now: now);

    expect(draft.title, '买牛奶');
    expect(draft.date, DateTime(2026, 5, 17));
    expect(draft.dueDate, isNull);
    expect(draft.hasReminder, isFalse);
  });

  test(
    'fromText supports relative day phrases from natural language input',
    () {
      final draft = SmartTodoDraftBuilder.fromText('三天后下午3点开会', now: now);

      expect(draft.title, '开会');
      expect(draft.date, DateTime(2026, 5, 18, 15));
      expect(draft.dueDate, DateTime(2026, 5, 18, 15));
      expect(draft.reminderAt, DateTime(2026, 5, 18, 15));
      expect(draft.hasReminder, isTrue);
      expect(draft.reminder.hour, 15);
    },
  );

  test('fromText supports compact tonight phrase with Chinese hour', () {
    final draft = SmartTodoDraftBuilder.fromText('今晚八点交报告', now: now);

    expect(draft.title, '交报告');
    expect(draft.date, DateTime(2026, 5, 15, 20));
    expect(draft.dueDate, DateTime(2026, 5, 15, 20));
    expect(draft.hasReminder, isTrue);
    expect(draft.reminder.hour, 20);
  });

  test('fromText supports absolute month-day phrase', () {
    final draft = SmartTodoDraftBuilder.fromText('5月20日下午三点开会', now: now);

    expect(draft.title, '开会');
    expect(draft.date, DateTime(2026, 5, 20, 15));
    expect(draft.dueDate, DateTime(2026, 5, 20, 15));
    expect(draft.hasReminder, isTrue);
    expect(draft.reminder.hour, 15);
  });

  test('fromText supports colloquial weekend and month-end phrases', () {
    final weekend = SmartTodoDraftBuilder.fromText('周末下午4点陪家人', now: now);
    expect(weekend.title, '陪家人');
    expect(weekend.date, DateTime(2026, 5, 16, 16));
    expect(weekend.hasReminder, isTrue);
    expect(weekend.reminder.hour, 16);

    final monthEnd = SmartTodoDraftBuilder.fromText('月底对账', now: now);
    expect(monthEnd.title, '对账');
    expect(monthEnd.date, DateTime(2026, 5, 31));
    expect(monthEnd.hasReminder, isFalse);

    final nextMonth = SmartTodoDraftBuilder.fromText('下个月5号下午2点体检', now: now);
    expect(nextMonth.title, '体检');
    expect(nextMonth.date, DateTime(2026, 6, 5, 14));
    expect(nextMonth.hasReminder, isTrue);
  });

  test('fromText supports English date and time phrases', () {
    final draft = SmartTodoDraftBuilder.fromText(
      'tomorrow at 3pm submit report',
      now: now,
    );

    expect(draft.title, 'submit report');
    expect(draft.date, DateTime(2026, 5, 16, 15));
    expect(draft.dueDate, DateTime(2026, 5, 16, 15));
    expect(draft.hasReminder, isTrue);
    expect(draft.reminder.hour, 15);
  });

  test('fromText turns Chinese weekly phrases into recurrence rules', () {
    final draft = SmartTodoDraftBuilder.fromText('每周一三五晚上8点健身', now: now);

    expect(draft.title, '健身');
    expect(draft.date, DateTime(2026, 5, 15, 20));
    expect(draft.hasReminder, isTrue);
    expect(draft.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(draft.recurrence.byWeekdays, [0, 2, 4]);
  });

  test('fromText supports daily recurrence without enabling reminder', () {
    final draft = SmartTodoDraftBuilder.fromText('每天背单词', now: now);

    expect(draft.title, '背单词');
    expect(draft.date, DateTime(2026, 5, 15));
    expect(draft.hasReminder, isFalse);
    expect(draft.recurrence.frequency, RecurrenceFrequency.daily);
  });

  test('fromText strips Chinese recurrence connector particle', () {
    final draft = SmartTodoDraftBuilder.fromText('每周二四的英语课', now: now);

    expect(draft.title, '英语课');
    expect(draft.date, DateTime(2026, 5, 19));
    expect(draft.hasReminder, isFalse);
    expect(draft.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(draft.recurrence.byWeekdays, [1, 3]);
  });

  test('fromText strips daily connector particle', () {
    final draft = SmartTodoDraftBuilder.fromText('每天的站会', now: now);

    expect(draft.title, '站会');
    expect(draft.date, DateTime(2026, 5, 15));
    expect(draft.recurrence.frequency, RecurrenceFrequency.daily);
  });

  test('fromText supports Chinese interval day recurrence', () {
    final draft = SmartTodoDraftBuilder.fromText('每两天上午9点喝水', now: now);

    expect(draft.title, '喝水');
    expect(draft.date, DateTime(2026, 5, 17, 9));
    expect(draft.hasReminder, isTrue);
    expect(draft.recurrence.frequency, RecurrenceFrequency.daily);
    expect(draft.recurrence.interval, 2);
  });

  test('fromText supports Chinese interval week recurrence', () {
    final draft = SmartTodoDraftBuilder.fromText('每2周一上午9点写周报', now: now);

    expect(draft.title, '写周报');
    expect(draft.date, DateTime(2026, 5, 18, 9));
    expect(draft.hasReminder, isTrue);
    expect(draft.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(draft.recurrence.interval, 2);
    expect(draft.recurrence.byWeekdays, [0]);
  });

  test('fromText supports Chinese weekend recurrence', () {
    final draft = SmartTodoDraftBuilder.fromText('每周末上午10点陪家人', now: now);

    expect(draft.title, '陪家人');
    expect(draft.date, DateTime(2026, 5, 16, 10));
    expect(draft.hasReminder, isTrue);
    expect(draft.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(draft.recurrence.byWeekdays, [5, 6]);
  });

  test('fromText supports monthly recurrence with month day', () {
    final draft = SmartTodoDraftBuilder.fromText('每月15日下午3点交房租', now: now);

    expect(draft.title, '交房租');
    expect(draft.date, DateTime(2026, 5, 15, 15));
    expect(draft.hasReminder, isTrue);
    expect(draft.recurrence.frequency, RecurrenceFrequency.monthly);
    expect(draft.recurrence.byMonthDay, 15);
  });

  test('fromText monthly recurrence skips months without that day', () {
    final draft = SmartTodoDraftBuilder.fromText(
      '每月31日上午9点对账',
      now: DateTime(2026, 2, 28, 10),
    );

    expect(draft.title, '对账');
    expect(draft.date, DateTime(2026, 3, 31, 9));
    expect(draft.recurrence.frequency, RecurrenceFrequency.monthly);
    expect(draft.recurrence.byMonthDay, 31);
  });

  test('fromText strips monthly connector particle', () {
    final draft = SmartTodoDraftBuilder.fromText('每月1日的预算复盘', now: now);

    expect(draft.title, '预算复盘');
    expect(draft.date, DateTime(2026, 6, 1));
    expect(draft.hasReminder, isFalse);
    expect(draft.recurrence.frequency, RecurrenceFrequency.monthly);
    expect(draft.recurrence.byMonthDay, 1);
  });

  test('fromText supports Chinese interval month recurrence', () {
    final draft = SmartTodoDraftBuilder.fromText('每两个月15日下午3点交房租', now: now);

    expect(draft.title, '交房租');
    expect(draft.date, DateTime(2026, 5, 15, 15));
    expect(draft.hasReminder, isTrue);
    expect(draft.recurrence.frequency, RecurrenceFrequency.monthly);
    expect(draft.recurrence.interval, 2);
    expect(draft.recurrence.byMonthDay, 15);
  });

  test('fromText supports Chinese recurrence end date', () {
    final draft = SmartTodoDraftBuilder.fromText('每天上午9点背单词直到5月20日', now: now);

    expect(draft.title, '背单词');
    expect(draft.date, DateTime(2026, 5, 16, 9));
    expect(draft.hasReminder, isTrue);
    expect(draft.recurrence.frequency, RecurrenceFrequency.daily);
    expect(draft.recurrence.endDate, DateTime(2026, 5, 20));
  });

  test('fromText supports Chinese recurrence occurrence count', () {
    final draft = SmartTodoDraftBuilder.fromText('每周一上午9点写周报共10次', now: now);

    expect(draft.title, '写周报');
    expect(draft.date, DateTime(2026, 5, 18, 9));
    expect(draft.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(draft.recurrence.byWeekdays, [0]);
    expect(draft.recurrence.maxOccurrences, 10);
  });

  test('fromText supports English workday recurrence and skips past time', () {
    final draft = SmartTodoDraftBuilder.fromText(
      'every weekday at 9am standup',
      now: now,
    );

    expect(draft.title, 'standup');
    expect(draft.date, DateTime(2026, 5, 18, 9));
    expect(draft.hasReminder, isTrue);
    expect(draft.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(draft.recurrence.byWeekdays, [0, 1, 2, 3, 4]);
  });

  test('fromText supports English weekly recurrence', () {
    final draft = SmartTodoDraftBuilder.fromText(
      'every Monday at 9am submit report',
      now: now,
    );

    expect(draft.title, 'submit report');
    expect(draft.date, DateTime(2026, 5, 18, 9));
    expect(draft.hasReminder, isTrue);
    expect(draft.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(draft.recurrence.byWeekdays, [0]);
  });

  test('fromText supports English weekend recurrence', () {
    final draft = SmartTodoDraftBuilder.fromText(
      'every weekend at 10am family time',
      now: now,
    );

    expect(draft.title, 'family time');
    expect(draft.date, DateTime(2026, 5, 16, 10));
    expect(draft.hasReminder, isTrue);
    expect(draft.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(draft.recurrence.byWeekdays, [5, 6]);
  });

  test('fromText supports English interval recurrences', () {
    final daily = SmartTodoDraftBuilder.fromText(
      'every other day at 9am stretch',
      now: now,
    );
    expect(daily.title, 'stretch');
    expect(daily.date, DateTime(2026, 5, 17, 9));
    expect(daily.recurrence.frequency, RecurrenceFrequency.daily);
    expect(daily.recurrence.interval, 2);

    final weekly = SmartTodoDraftBuilder.fromText(
      'every 2 weeks Monday at 9am submit report',
      now: now,
    );
    expect(weekly.title, 'submit report');
    expect(weekly.date, DateTime(2026, 5, 18, 9));
    expect(weekly.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(weekly.recurrence.interval, 2);
    expect(weekly.recurrence.byWeekdays, [0]);
  });

  test('fromText supports English recurrence end date', () {
    final draft = SmartTodoDraftBuilder.fromText(
      'every Monday at 9am submit report until May 20',
      now: now,
    );

    expect(draft.title, 'submit report');
    expect(draft.date, DateTime(2026, 5, 18, 9));
    expect(draft.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(draft.recurrence.byWeekdays, [0]);
    expect(draft.recurrence.endDate, DateTime(2026, 5, 20));
  });

  test('fromText supports English recurrence occurrence count', () {
    final draft = SmartTodoDraftBuilder.fromText(
      'every other day at 9am stretch for 6 times',
      now: now,
    );

    expect(draft.title, 'stretch');
    expect(draft.date, DateTime(2026, 5, 17, 9));
    expect(draft.recurrence.frequency, RecurrenceFrequency.daily);
    expect(draft.recurrence.interval, 2);
    expect(draft.recurrence.maxOccurrences, 6);
  });

  test('fromText does not treat bare English title numbers as time', () {
    final draft = SmartTodoDraftBuilder.fromText(
      'every Monday 2 reports',
      now: now,
    );

    expect(draft.title, '2 reports');
    expect(draft.date, DateTime(2026, 5, 18));
    expect(draft.hasReminder, isFalse);
    expect(draft.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(draft.recurrence.byWeekdays, [0]);
  });

  test('toTodo preserves parsed date and generated reminder fields', () {
    final todo =
        SmartTodoDraftBuilder.fromText(
          '每周一上午9点写周报',
          now: now,
          defaultReminderKind: ReminderKind.push,
        ).toTodo(
          quadrant: EisenhowerQuadrant.urgentImportant,
          priority: TodoPriority.high,
          listGroupName: '工作',
          workspaceId: 'workspace-1',
          createdBy: 'u1',
          updatedBy: 'u1',
          subtasks: [Subtask(title: '整理数据')],
        );

    expect(todo.title, '写周报');
    expect(todo.date, DateTime(2026, 5, 18, 9, 0));
    expect(todo.dueDate, DateTime(2026, 5, 18, 9, 0));
    expect(todo.hasReminder, isTrue);
    expect(todo.reminder.kind, ReminderKind.push);
    expect(todo.reminderPlan.enabled, isTrue);
    expect(todo.recurrence.frequency, RecurrenceFrequency.weekly);
    expect(todo.recurrence.byWeekdays, [0]);
    expect(todo.quadrant, EisenhowerQuadrant.urgentImportant);
    expect(todo.priority, TodoPriority.high);
    expect(todo.listGroupName, '工作');
    expect(todo.workspaceId, 'workspace-1');
    expect(todo.subtasks.single.title, '整理数据');
  });
}
