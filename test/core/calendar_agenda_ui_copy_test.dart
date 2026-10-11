import 'package:duoyi/core/calendar_agenda_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('weekday headings preserve the Monday-first order in both locales', () {
    I18n.setLocale(AppLocale.zh);
    expect(CalendarAgendaUiCopy.weekdayInitials, [
      '一',
      '二',
      '三',
      '四',
      '五',
      '六',
      '日',
    ]);
    I18n.setLocale(AppLocale.en);
    expect(CalendarAgendaUiCopy.weekdayInitials, [
      'M',
      'T',
      'W',
      'T',
      'F',
      'S',
      'S',
    ]);
  });

  test('month badges and overflow messages use English count agreement', () {
    I18n.setLocale(AppLocale.en);
    expect(CalendarAgendaUiCopy.monthEventBadge(1), '1 item');
    expect(CalendarAgendaUiCopy.monthEventBadge(12), '12 items');
    expect(CalendarAgendaUiCopy.overflowNotice(1), startsWith('1 more item,'));
    expect(CalendarAgendaUiCopy.overflowNotice(2), startsWith('2 more items,'));
    I18n.setLocale(AppLocale.zh);
    expect(CalendarAgendaUiCopy.monthEventBadge(12), '12项');
    expect(CalendarAgendaUiCopy.overflowNotice(2), startsWith('还有 2 项'));
  });

  test(
    'day semantics translate statuses while preserving supplied subtitle',
    () {
      final date = DateTime(2026, 10, 11);
      String label(int count) => CalendarAgendaUiCopy.daySemanticLabel(
        date,
        isToday: true,
        isSelected: true,
        eventCount: count,
        subText: '用户提供的附注',
      );
      I18n.setLocale(AppLocale.en);
      expect(
        label(1),
        '${I18nDateFormat.date(date)}, Today, Selected, 用户提供的附注, 1 event',
      );
      expect(label(2), endsWith('2 events'));
      expect(label(0), endsWith('No events'));
      I18n.setLocale(AppLocale.zh);
      expect(label(1), '2026年10月11日，今天，已选中，用户提供的附注，1 个事项');
      expect(label(0), endsWith('无事项'));
    },
  );

  test('course periods keep section numbers in both locales', () {
    I18n.setLocale(AppLocale.zh);
    expect(CalendarAgendaUiCopy.coursePeriod(1, 1), '第1节');
    expect(CalendarAgendaUiCopy.coursePeriod(1, 2), '第1-2节');
    I18n.setLocale(AppLocale.en);
    expect(CalendarAgendaUiCopy.coursePeriod(1, 1), 'Period 1');
    expect(CalendarAgendaUiCopy.coursePeriod(1, 2), 'Period 1-2');
  });

  test('agenda headings and empty diary prompt follow retained locale', () {
    I18n.setLocale(AppLocale.zh);
    expect(CalendarAgendaUiCopy.timelineSectionTitle, '🕘 时间线');
    expect(CalendarAgendaUiCopy.allDaySectionTitle, '📝 全天/无时间');
    expect(CalendarAgendaUiCopy.emptyDiaryPrompt, '写下这一天的日记');
    I18n.setLocale(AppLocale.en);
    expect(CalendarAgendaUiCopy.timelineSectionTitle, '🕘 Timeline');
    expect(CalendarAgendaUiCopy.allDaySectionTitle, '📝 All-day / Untimed');
    expect(
      CalendarAgendaUiCopy.emptyDiaryPrompt,
      'Write a diary entry for this day',
    );
  });

  test('drag feedback translates glue and preserves supplied diagnostics', () {
    I18n.setLocale(AppLocale.en);
    expect(
      CalendarAgendaUiCopy.dragAdjustSuccess('9:00 AM'),
      'Adjusted to 9:00 AM',
    );
    expect(
      CalendarAgendaUiCopy.dragReminderWarning('9:00 AM', '设备返回的提示'),
      'Adjusted to 9:00 AM, but reminder was not registered: 设备返回的提示',
    );
    expect(
      CalendarAgendaUiCopy.dragTaskSaveFailed('原始错误'),
      'Failed to save task: 原始错误',
    );
    I18n.setLocale(AppLocale.zh);
    expect(CalendarAgendaUiCopy.dragAdjustSuccess('09:00'), '已调整到 09:00');
    expect(
      CalendarAgendaUiCopy.dragTaskSaveFailed('raw error'),
      '待办保存失败：raw error',
    );
  });
}
