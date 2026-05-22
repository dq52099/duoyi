import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('日历详情对可回写类型暴露改期和删除动作', () {
    final source = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();

    for (final type in [
      'CalendarEventType.goal',
      'CalendarEventType.anniversary',
      'CalendarEventType.countdown',
    ]) {
      final block = _caseBlock(source, type);
      expect(block, contains("label: '改期'"));
      expect(block, contains('onPressed: () => _reschedule(context)'));
      expect(block, contains("label: '删除'"));
      expect(block, contains('onPressed: () => _delete(context)'));
    }

    for (final type in [
      'CalendarEventType.anniversary',
      'CalendarEventType.countdown',
      'CalendarEventType.course',
      'CalendarEventType.diary',
      'CalendarEventType.habit',
      'CalendarEventType.pomodoro',
    ]) {
      final block = _caseBlock(source, type);
      expect(block, contains("label: '编辑'"));
      expect(block, contains('onPressed: () => _editSourceEvent(context)'));
    }

    for (final type in [
      'CalendarEventType.course',
      'CalendarEventType.diary',
      'CalendarEventType.habit',
      'CalendarEventType.timeEntry',
    ]) {
      final block = _caseBlock(source, type);
      expect(block, contains("label: '删除'"));
      expect(block, contains('onPressed: () => _delete(context)'));
    }
  });

  test('日历详情复用原模块编辑器回写纪念日、倒数日、课程、日记和习惯', () {
    final sheet = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();
    final anniversary = File(
      'lib/screens/anniversary_screen.dart',
    ).readAsStringSync();
    final countdown = File(
      'lib/screens/countdown_screen.dart',
    ).readAsStringSync();
    final course = File(
      'lib/screens/course_schedule_screen.dart',
    ).readAsStringSync();
    final diary = File('lib/screens/diary_screen.dart').readAsStringSync();
    final habit = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();

    expect(sheet, contains("import '../screens/anniversary_screen.dart';"));
    expect(sheet, contains("import '../screens/countdown_screen.dart';"));
    expect(sheet, contains("import '../screens/course_schedule_screen.dart';"));
    expect(sheet, contains("import '../screens/diary_screen.dart';"));
    expect(sheet, contains("import '../screens/habit_detail_screen.dart';"));
    expect(sheet, contains("import '../providers/diary_provider.dart';"));
    expect(sheet, contains('Future<void> _editSourceEvent'));
    expect(sheet, contains('showAnniversaryEditor(context, item: item)'));
    expect(sheet, contains('showCountdownEditor(context, item: item)'));
    expect(sheet, contains('showCourseEditor(context, course: item)'));
    expect(sheet, contains('showDiaryEditor(context, entry: item)'));
    expect(sheet, contains('showHabitEditor(context, item)'));
    expect(sheet, contains('showPomodoroSessionEditor(context, item)'));
    expect(sheet, contains('context.read<DiaryProvider>().delete(sourceId)'));
    expect(
      sheet,
      contains('context.read<HabitProvider>().deleteHabit(sourceId)'),
    );
    expect(
      sheet,
      contains('context.read<PomodoroProvider>().deleteSession(sourceId)'),
    );

    expect(anniversary, contains('Future<void> showAnniversaryEditor'));
    expect(anniversary, contains('_AnniversaryEditSheet(editing: item)'));
    expect(countdown, contains('Future<void> showCountdownEditor'));
    expect(countdown, contains('_CountdownEditSheet(item: item)'));
    expect(course, contains('Future<void> showCourseEditor'));
    expect(
      course,
      contains('_CourseEditSheet(provider: provider, course: course)'),
    );
    expect(diary, contains('Future<void> showDiaryEditor'));
    expect(
      diary,
      contains('DiaryEditScreen(entry: entry, initialDate: initialDate)'),
    );
    expect(habit, contains('Future<void> showHabitEditor'));
    expect(habit, contains('habitProvider.updateHabit(habit.id, updated)'));
    expect(habit, contains('onPressed: () => showHabitEditor(context, habit)'));
    final pomodoro = File(
      'lib/screens/pomodoro_screen.dart',
    ).readAsStringSync();
    final card = File(
      'lib/widgets/pomodoro_session_card.dart',
    ).readAsStringSync();
    expect(pomodoro, contains('Future<void> showPomodoroSessionEditor'));
    expect(pomodoro, contains('provider.updateSession(next)'));
    expect(
      pomodoro,
      contains('onEdit: () => showPomodoroSessionEditor(context, s)'),
    );
    expect(card, contains('final VoidCallback? onEdit;'));
    expect(card, contains("message: '编辑记录'"));
    expect(card, contains('icon: const Icon(Icons.edit_outlined)'));
  });
}

String _caseBlock(String source, String caseLabel) {
  final start = source.indexOf('case $caseLabel:');
  expect(start, isNonNegative, reason: '$caseLabel should exist');
  final rest = source.substring(start + 'case $caseLabel:'.length);
  final nextCase = rest.indexOf('case CalendarEventType.');
  final end = nextCase == -1 ? rest.indexOf('    }\n  }') : nextCase;
  expect(end, isNonNegative, reason: '$caseLabel case should have an end');
  return rest.substring(0, end);
}
