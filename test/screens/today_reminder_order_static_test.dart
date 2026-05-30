import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('今日提醒按优先级展示且今日建议默认收起放在末尾', () {
    final today = File('lib/screens/today_screen.dart').readAsStringSync();

    expect(
      today,
      contains('final reminderGroups = _TodayReminderGroups.build'),
    );
    expect(today, contains('class _TodayReminderGroups'));
    expect(today, contains("title: '今日提醒'"));
    expect(today, contains('今日待提醒 > 即将开始 > 已逾期事项（弱化）'));
    expect(today, contains("title: '今日待提醒事项'"));
    expect(today, contains("title: '即将开始事项'"));
    expect(today, contains("title: '已逾期事项'"));
    expect(today, contains('overdue: true'));
    expect(
      today,
      contains('cs.surfaceContainerHighest.withValues(alpha: 0.18)'),
    );
    expect(today, contains('cs.onSurface.withValues(alpha: 0.56)'));
    expect(today, contains('cs.onSurfaceVariant.withValues(alpha: 0.74)'));
    expect(today, contains('ExpansionTile('));
    expect(today, contains('initiallyExpanded: false'));
    expect(today, contains('maintainState: true'));
    expect(today, contains('默认收起'));

    expect(
      today,
      contains(
        'final showReminderSection =\n        !reminderGroups.isEmpty || suggestions.isNotEmpty;',
      ),
    );
    final reminderIndex = today.indexOf('if (showReminderSection)');
    final todoIndex = today.indexOf('// 今日待办');
    final goalIndex = today.indexOf('// 目标进度');
    expect(reminderIndex, greaterThanOrEqualTo(0));
    expect(todoIndex, greaterThan(reminderIndex));
    expect(goalIndex, greaterThan(todoIndex));

    final sectionStart = today.indexOf('class _TodayReminderSection');
    final sectionEnd = today.indexOf('class _ReminderGroupBlock');
    expect(sectionStart, greaterThanOrEqualTo(0));
    expect(sectionEnd, greaterThan(sectionStart));
    final section = today.substring(sectionStart, sectionEnd);

    final dueIndex = section.indexOf("title: '今日待提醒事项'");
    final upcomingIndex = section.indexOf("title: '即将开始事项'");
    final overdueIndex = section.indexOf("title: '已逾期事项'");
    final suggestionIndex = section.indexOf('if (suggestions.isNotEmpty)');
    expect(dueIndex, greaterThanOrEqualTo(0));
    expect(upcomingIndex, greaterThan(dueIndex));
    expect(overdueIndex, greaterThan(upcomingIndex));
    expect(suggestionIndex, greaterThan(overdueIndex));
  });
}
