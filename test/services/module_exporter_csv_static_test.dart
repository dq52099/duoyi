import 'dart:io';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/services/ics_exporter.dart';

void main() {
  late AppLocale savedLocale;

  setUp(() => savedLocale = I18n.current);
  tearDown(() => I18n.setLocale(savedLocale));

  test('ModuleExporter exposes portable CSV exports for core local data', () {
    final exporter = File('lib/services/ics_exporter.dart').readAsStringSync();

    expect(exporter, contains('static String todosCsv('));
    expect(exporter, contains('static String habitsCsv('));
    expect(exporter, contains('static String timeEntriesCsv('));
    expect(exporter, contains('static String notesCsv('));
    expect(exporter, contains('static String diaryCsv('));
    expect(exporter, contains('static String anniversariesCsv('));
    expect(exporter, contains('static String goalsCsv('));

    expect(exporter, contains('duration_minutes'));
    expect(exporter, contains('milestones_done'));
    expect(exporter, contains('next_occurrence'));
    expect(
      exporter,
      contains('title,content,format,pinned,archived,attachments'),
    );
    expect(exporter, contains('n.pinned'));
    expect(exporter, contains('n.archived'));
    expect(exporter, contains('attachments'));
    expect(exporter, contains("s.contains('\\r')"));
    expect(exporter, contains('s.replaceAll(\'"\', \'""\')'));
  });

  test(
    'BackupScreen exposes CSV chips for migration-friendly module export',
    () {
      final screen = File('lib/screens/backup_screen.dart').readAsStringSync();

      expect(screen, contains('DataSettingsUiCopy.singleModuleExportTitle'));
      expect(screen, contains('DataSettingsUiCopy.singleModuleExportSubtitle'));
      for (final name in const [
        'exportChipTodoCsv',
        'exportChipHabitCsv',
        'exportChipTimeEntryCsv',
        'exportChipNoteCsv',
        'exportChipDiaryCsv',
        'exportChipAnniversaryCsv',
        'exportChipGoalCsv',
      ]) {
        expect(screen, contains('DataSettingsUiCopy.$name'));
      }

      expect(screen, contains('ModuleExporter.timeEntriesCsv(entries)'));
      expect(screen, contains('ModuleExporter.notesCsv(ns)'));
      expect(screen, contains('ModuleExporter.diaryCsv(ds)'));
      expect(screen, contains('ModuleExporter.anniversariesCsv(list)'));
      expect(screen, contains('ModuleExporter.goalsCsv(list)'));
    },
  );

  test('ICS defaults follow locale while protocol identity stays stable', () {
    final event = CalendarEvent(
      id: 'event-1',
      title: '事件, 原题; unchanged\nSecond line',
      date: DateTime(2026, 5, 18),
      type: CalendarEventType.event,
      color: Colors.blue,
    );
    final anniversary = Anniversary(
      id: 'anniversary-1',
      title: '妈妈生日',
      originDate: DateTime(2000, 5, 18),
      type: AnniversaryType.birthday,
    );

    I18n.setLocale(AppLocale.zh);
    final zhEvents = IcsExporter.fromEvents([event]);
    final zhAnniversaries = IcsExporter.fromAnniversaries([anniversary]);
    I18n.setLocale(AppLocale.en);
    final enEvents = IcsExporter.fromEvents([event]);
    final enAnniversaries = IcsExporter.fromAnniversaries([anniversary]);
    final explicitName = IcsExporter.fromEvents([
      event,
    ], calendarName: 'Custom, Calendar;\nLine\rReturn');

    expect(zhEvents, contains('X-WR-CALNAME:多仪 · 日程'));
    expect(enEvents, contains('X-WR-CALNAME:Duoyi · Calendar'));
    expect(zhAnniversaries, contains('X-WR-CALNAME:多仪 · 纪念日'));
    expect(enAnniversaries, contains('X-WR-CALNAME:Duoyi · Anniversaries'));
    expect(enEvents, contains('PRODID:-//Duoyi//ZH//CN'));
    expect(enEvents, contains('UID:event-1@duoyi'));
    expect(enEvents, contains('CATEGORIES:event'));
    expect(enEvents, contains(r'SUMMARY:事件\, 原题\; unchanged\nSecond line'));
    expect(enAnniversaries, contains('UID:anni_anniversary-1@duoyi'));
    expect(enAnniversaries, contains('RRULE:FREQ=YEARLY'));
    expect(enAnniversaries, contains('SUMMARY:妈妈生日'));
    final emptyExplicitName = IcsExporter.fromEvents([event], calendarName: '');
    expect(emptyExplicitName, contains('X-WR-CALNAME:\n'));
    expect(
      explicitName,
      contains(r'X-WR-CALNAME:Custom\, Calendar\;\nLine\nReturn'),
    );
  });

  test(
    'Markdown labels follow locale and leave authored content untouched',
    () {
      final now = DateTime(2026, 5, 18, 10);
      final todos = [
        TodoItem(
          id: 'todo-cn-group',
          title: '保存的待办原文',
          listGroupName: '未分组',
          subtasks: [Subtask(id: 'subtask-1', title: '子任务原文')],
          attachments: const [
            NoteAttachment(name: '合同 原名.pdf', uri: 'file:///合同 原名.pdf'),
          ],
        ),
        TodoItem(
          id: 'todo-en-group',
          title: 'English group original',
          listGroupName: 'Ungrouped',
        ),
        TodoItem(id: 'todo-no-group', title: 'No group original'),
      ];
      final note = NoteItem(
        id: 'note-1',
        content: '用户笔记标题\n正文保留原文',
        attachments: const [
          NoteAttachment(
            name: '原附件名.svg',
            uri: 'https://example.test/file.svg',
          ),
        ],
        pinned: true,
        archived: true,
        createdAt: now,
        updatedAt: now,
      );
      final diary = DiaryEntry(
        id: 'diary-1',
        date: DateTime(2026, 5, 18),
        content: '日记正文原文\n第二行保持原样',
        mood: Mood.good,
        weather: Weather.sunny,
        tags: ['作者标签'],
      );
      final anniversary = Anniversary(
        id: 'anniversary-1',
        title: '妈妈生日',
        description: '纪念说明原文',
        originDate: DateTime(2000, 5, 18),
        type: AnniversaryType.birthday,
        calendarType: AnniversaryCalendarType.lunar,
      );
      final goal = GoalItem(
        id: 'goal-1',
        title: '目标原文标题',
        description: '目标原文说明',
        status: GoalStatus.paused,
        category: GoalCategory.study,
        milestones: [GoalMilestone(id: 'milestone-1', title: '里程碑原文')],
      );

      I18n.setLocale(AppLocale.zh);
      final zhTodos = ModuleExporter.todosMarkdown(todos);
      final zhNotes = ModuleExporter.notesMarkdown([note]);
      final zhDiary = ModuleExporter.diaryMarkdown([diary]);
      final zhAnniversaries = ModuleExporter.anniversariesMarkdown([
        anniversary,
      ]);
      final zhGoals = ModuleExporter.goalsMarkdown([goal]);
      I18n.setLocale(AppLocale.en);
      final enTodos = ModuleExporter.todosMarkdown(todos);
      final enNotes = ModuleExporter.notesMarkdown([note]);
      final enDiary = ModuleExporter.diaryMarkdown([diary]);
      final enAnniversaries = ModuleExporter.anniversariesMarkdown([
        anniversary,
      ]);
      final enGoals = ModuleExporter.goalsMarkdown([goal]);

      expect(zhTodos, startsWith('# 待办清单'));
      expect(enTodos, startsWith('# Todo List'));
      expect(zhTodos.split('\n').where((line) => line == '## 未分组').length, 2);
      expect(
        enTodos.split('\n').where((line) => line == '## Ungrouped').length,
        2,
      );
      expect(enTodos, contains('## 未分组'));
      expect(zhTodos, contains('## Ungrouped'));
      expect(zhTodos, contains('保存的待办原文'));
      expect(enTodos, contains('子任务原文'));
      expect(enTodos, contains('English group original'));
      expect(zhTodos, contains('附件: [合同 原名.pdf](file:///合同 原名.pdf)'));
      expect(enTodos, contains('Attachment: [合同 原名.pdf](file:///合同 原名.pdf)'));

      expect(zhNotes, startsWith('# 笔记'));
      expect(enNotes, startsWith('# Notes'));
      expect(zhNotes, contains('置顶 · 归档'));
      expect(enNotes, contains('Pinned · Archived'));
      expect(zhNotes, contains('附件:'));
      expect(enNotes, contains('Attachments:'));
      expect(enNotes, contains('原附件名.svg'));
      expect(enNotes, contains('正文保留原文'));

      expect(zhDiary, startsWith('# 日记'));
      expect(enDiary, startsWith('# Diary'));
      expect(zhDiary, contains('标签: #作者标签'));
      expect(enDiary, contains('Tags: #作者标签'));
      expect(enDiary, contains('日记正文原文\n第二行保持原样'));

      expect(zhAnniversaries, startsWith('# 纪念日'));
      expect(enAnniversaries, startsWith('# Anniversaries'));
      expect(zhAnniversaries, contains('妈妈生日** — 生日 · 农历'));
      expect(enAnniversaries, contains('妈妈生日** — Birthday · Lunar'));
      expect(zhAnniversaries, contains('下一次:'));
      expect(enAnniversaries, contains('Next:'));
      expect(enAnniversaries, contains('纪念说明原文'));

      expect(zhGoals, startsWith('# 目标'));
      expect(enGoals, startsWith('# Goals'));
      expect(enGoals, contains('目标原文标题'));
      expect(enGoals, contains('目标原文说明'));
      expect(enGoals, contains('里程碑原文'));
    },
  );

  test('CSV headers and historical enum labels are locale invariant', () {
    final now = DateTime(2026, 5, 18, 10);
    final todos = [
      TodoItem(id: 'todo-1', title: '待办', priority: TodoPriority.urgent),
    ];
    final habits = [Habit(id: 'habit-1', name: '习惯', kind: HabitKind.negative)];
    final timeEntries = [
      TimeEntry(
        id: 'time-1',
        title: '时间记录',
        startAt: now,
        endAt: now.add(const Duration(minutes: 30)),
        category: TimeEntryCategory.study,
        source: TimeEntrySource.manual,
      ),
    ];
    final notes = [
      NoteItem(id: 'note-1', content: '笔记', createdAt: now, updatedAt: now),
      NoteItem(
        id: 'note-empty',
        content: ' \n\t ',
        createdAt: DateTime(2026, 5, 19, 8),
        updatedAt: DateTime(2026, 5, 19, 8, 5),
      ),
    ];
    final diary = [
      DiaryEntry(
        id: 'diary-1',
        date: now,
        content: '日记',
        mood: Mood.good,
        weather: Weather.sunny,
      ),
      DiaryEntry(
        id: 'diary-empty',
        date: DateTime(2026, 5, 19),
        content: '',
        createdAt: DateTime(2026, 5, 19, 8),
        updatedAt: DateTime(2026, 5, 19, 8, 5),
      ),
    ];
    final anniversaries = [
      Anniversary(
        id: 'anniversary-1',
        title: '纪念日',
        originDate: DateTime(2000, 5, 18),
        type: AnniversaryType.normal,
        calendarType: AnniversaryCalendarType.lunar,
      ),
    ];
    final goals = [
      GoalItem(
        id: 'goal-1',
        title: '目标',
        status: GoalStatus.paused,
        category: GoalCategory.study,
      ),
    ];

    List<String> exportAll() => [
      ModuleExporter.todosCsv(todos),
      ModuleExporter.habitsCsv(habits),
      ModuleExporter.timeEntriesCsv(timeEntries),
      ModuleExporter.notesCsv(notes),
      ModuleExporter.diaryCsv(diary),
      ModuleExporter.anniversariesCsv(anniversaries),
      ModuleExporter.goalsCsv(goals),
    ];

    I18n.setLocale(AppLocale.zh);
    final zhExports = exportAll();
    I18n.setLocale(AppLocale.en);
    final enExports = exportAll();

    expect(enExports, zhExports);
    expect(
      zhExports[0],
      contains('title,completed,priority,quadrant,list,due,tags,attachments'),
    );
    expect(zhExports[0], contains(',紧急,Q2,'));
    expect(
      zhExports[1],
      contains('name,kind,target,current_streak,best_streak,category,tags'),
    );
    expect(zhExports[1], contains(',negative,'));
    expect(zhExports[2], contains('学习,手动'));
    expect(zhExports[3], contains('无标题笔记'));
    expect(zhExports[3], isNot(contains('Untitled note')));
    expect(zhExports[4], contains('开心,晴'));
    expect(zhExports[4], contains('2026-05-19,,,,,,2026-05-19T08:00:00.000'));
    expect(zhExports[5], contains(',倒数,lunar,'));
    expect(zhExports[6], contains(',paused,study,'));
  });
}
