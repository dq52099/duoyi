import 'package:duoyi/core/calendar_aggregator.dart';
import 'package:duoyi/core/calendar_event_display_text.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/models/course_schedule.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final mood in <Mood?>[null, Mood.good]) {
    test('empty diary title follows locale without rebuilding, mood=$mood', () {
      final date = DateTime(2026, 10, 11);
      final entry = DiaryEntry(
        id: 'empty-diary',
        date: date,
        content: ' \n ',
        mood: mood,
      );
      final event = _buildEvents(diaries: [entry]).single;
      final snapshot = event.toJson();
      final metadata = event.displayMetadata! as DiaryDisplayMetadata;
      expect(metadata.fallbackTitleDate, date);
      expect(event.title, '10月11日的日记');
      expect(CalendarEventDisplayText.resolveTitle(event), event.title);
      expect(
        CalendarEventDisplayText.resolveSubtitle(event),
        mood == null ? null : '开心',
      );

      I18n.setLocale(AppLocale.en);
      expect(CalendarEventDisplayText.resolveTitle(event), 'Diary for 10/11');
      expect(
        CalendarEventDisplayText.resolveSubtitle(event),
        mood == null ? null : 'Good',
      );
      expect(event.title, '10月11日的日记');
      expect(event.toJson(), snapshot);
      expect(event.sourceId, entry.id);
      expect(event.date, date);
      expect(snapshot, isNot(contains('displayMetadata')));
      final restored = CalendarEvent.fromJson(snapshot);
      expect(restored.displayMetadata, isNull);
      expect(CalendarEventDisplayText.resolveTitle(restored), event.title);
      expect(
        CalendarEventDisplayText.resolveTitle(
          event.copyWith(hasConflict: true),
        ),
        'Diary for 10/11',
      );

      I18n.setLocale(AppLocale.zh);
      expect(CalendarEventDisplayText.resolveTitle(event), '10月11日的日记');
    });
  }

  test('diary title matching a fallback stays authored across locales', () {
    final event = _buildEvents(
      diaries: [
        DiaryEntry(
          id: 'authored-diary',
          date: DateTime(2026, 10, 11),
          content: '10月11日的日记\n用户正文',
          mood: Mood.good,
        ),
      ],
    ).single;
    final metadata = event.displayMetadata! as DiaryDisplayMetadata;
    expect(metadata.fallbackTitleDate, isNull);
    I18n.setLocale(AppLocale.en);
    expect(CalendarEventDisplayText.resolveTitle(event), '10月11日的日记');
    expect(CalendarEventDisplayText.resolveSubtitle(event), 'Good');
  });

  test('title-only diary metadata retains a literal subtitle', () {
    final event = CalendarEvent(
      id: 'title-only',
      title: '10月11日的日记',
      subtitle: '开心',
      date: DateTime(2026, 10, 11),
      type: CalendarEventType.diary,
      color: Colors.teal,
      displayMetadata: DiaryDisplayMetadata(
        fallbackTitleDate: DateTime(2026, 10, 11),
      ),
    );
    I18n.setLocale(AppLocale.en);
    expect(CalendarEventDisplayText.resolveTitle(event), 'Diary for 10/11');
    expect(CalendarEventDisplayText.resolveSubtitle(event), '开心');
  });

  test(
    'generated Pomodoro fallback title and duration follow the current locale',
    () {
      final event = _buildEvents(
        pomodoroSessions: [_pomodoroSession(id: 'generated')],
      ).singleWhere((event) => event.id == 'pomodoro_generated');

      expect(event.title, '专注 25 分钟');
      expect(event.displayMetadata, isA<PomodoroDisplayMetadata>());
      expect(CalendarEventDisplayText.resolveTitle(event), '专注 25 分钟');
      expect(CalendarEventDisplayText.resolveSubtitle(event), '25分钟');

      I18n.setLocale(AppLocale.en);
      expect(CalendarEventDisplayText.resolveTitle(event), 'Focus 25 min');
      expect(CalendarEventDisplayText.resolveSubtitle(event), '25 min');

      I18n.setLocale(AppLocale.zh);
      expect(CalendarEventDisplayText.resolveTitle(event), '专注 25 分钟');
      expect(CalendarEventDisplayText.resolveSubtitle(event), '25分钟');
    },
  );

  test(
    'aggregated todo due-date metadata localizes while preserving its authored title',
    () {
      const authoredTitle = '用户写的待办';
      final dueDate = DateTime(2026, 10, 14, 9, 30);
      final events = _buildEvents(
        todos: [
          TodoItem(
            id: 'todo-due',
            title: authoredTitle,
            date: DateTime(2026, 10, 11),
            dueDate: dueDate,
          ),
        ],
      );
      final event = _event(events, 'todo_todo-due');
      final metadata = event.displayMetadata! as TodoDisplayMetadata;

      expect(metadata.dueDate, dueDate);
      expect(CalendarEventDisplayText.resolveTitle(event), authoredTitle);
      expect(CalendarEventDisplayText.resolveSubtitle(event), '截止 10/14 09:30');

      I18n.setLocale(AppLocale.en);
      expect(CalendarEventDisplayText.resolveTitle(event), authoredTitle);
      expect(
        CalendarEventDisplayText.resolveSubtitle(event),
        'Due 10/14 09:30',
      );

      I18n.setLocale(AppLocale.zh);
      expect(CalendarEventDisplayText.resolveTitle(event), authoredTitle);
      expect(CalendarEventDisplayText.resolveSubtitle(event), '截止 10/14 09:30');
    },
  );

  test(
    'aggregated time-entry category and duration localize while preserving its authored title',
    () {
      const authoredTitle = '用户记录的工作内容';
      final startAt = DateTime(2026, 10, 11, 9);
      final events = _buildEvents(
        timeEntries: [
          TimeEntry(
            id: 'work-entry',
            title: authoredTitle,
            startAt: startAt,
            endAt: startAt.add(const Duration(minutes: 45)),
            category: TimeEntryCategory.work,
          ),
        ],
      );
      final event = _event(events, 'time_work-entry');
      final metadata = event.displayMetadata! as TimeEntryDisplayMetadata;

      expect(metadata.category, TimeEntryCategory.work);
      expect(metadata.durationSeconds, 45 * 60);
      expect(CalendarEventDisplayText.resolveTitle(event), authoredTitle);
      expect(CalendarEventDisplayText.resolveSubtitle(event), '工作 · 45分钟');

      I18n.setLocale(AppLocale.en);
      expect(CalendarEventDisplayText.resolveTitle(event), authoredTitle);
      expect(CalendarEventDisplayText.resolveSubtitle(event), 'Work · 45 min');

      I18n.setLocale(AppLocale.zh);
      expect(CalendarEventDisplayText.resolveTitle(event), authoredTitle);
      expect(CalendarEventDisplayText.resolveSubtitle(event), '工作 · 45分钟');
    },
  );

  test(
    'authored Pomodoro title is preserved while its generated duration localizes',
    () {
      final event = _buildEvents(
        pomodoroSessions: [
          _pomodoroSession(id: 'custom', taskName: '专注 25 分钟'),
        ],
      ).singleWhere((event) => event.id == 'pomodoro_custom');

      expect(event.displayMetadata, isNotNull);
      expect(event.title, '专注 25 分钟');

      I18n.setLocale(AppLocale.en);
      expect(CalendarEventDisplayText.resolveTitle(event), '专注 25 分钟');
      expect(CalendarEventDisplayText.resolveSubtitle(event), '25 min');
    },
  );

  test(
    'aggregated anniversary, countdown, goal, and diary metadata localizes',
    () {
      final today = _dateOnly(DateTime.now());
      final events = _buildEvents(
        anniversaries: [
          Anniversary(
            id: 'anniversary',
            title: '周年日',
            originDate: today.add(const Duration(days: 10)),
          ),
        ],
        countdowns: [
          CountdownItem(
            id: 'countdown',
            title: '项目截止',
            targetDate: today.add(const Duration(days: 8)),
          ),
        ],
        goals: [
          GoalItem(
            id: 'goal',
            title: '完成计划',
            targetDate: DateTime(2026, 12, 1),
            autoProgress: false,
            progress: 0.42,
          ),
        ],
        diaries: [
          DiaryEntry(
            id: 'diary',
            date: today,
            content: '今天的记录',
            mood: Mood.good,
          ),
        ],
      );

      final anniversary = _event(events, 'anniversary_anniversary');
      final anniversaryMeta =
          anniversary.displayMetadata! as AnniversaryDisplayMetadata;
      final countdown = _event(events, 'countdown_countdown');
      final countdownMeta =
          countdown.displayMetadata! as CountdownDisplayMetadata;
      final goal = _event(events, 'goal_goal');
      final goalMeta = goal.displayMetadata! as GoalDisplayMetadata;
      final diary = _event(events, 'diary_diary');
      expect(diary.displayMetadata, isA<DiaryDisplayMetadata>());

      I18n.setLocale(AppLocale.en);
      expect(
        CalendarEventDisplayText.resolveSubtitle(anniversary),
        'In ${anniversaryMeta.daysRemaining} days',
      );
      expect(
        CalendarEventDisplayText.resolveSubtitle(countdown),
        'In ${countdownMeta.daysRemaining} days',
      );
      expect(
        CalendarEventDisplayText.resolveSubtitle(goal),
        'Progress ${goalMeta.progressPercent}%',
      );
      expect(CalendarEventDisplayText.resolveSubtitle(diary), 'Good');

      I18n.setLocale(AppLocale.zh);
      expect(
        CalendarEventDisplayText.resolveSubtitle(anniversary),
        '还有 ${anniversaryMeta.daysRemaining} 天',
      );
      expect(
        CalendarEventDisplayText.resolveSubtitle(countdown),
        '还有 ${countdownMeta.daysRemaining} 天',
      );
      expect(
        CalendarEventDisplayText.resolveSubtitle(goal),
        '进度 ${goalMeta.progressPercent}%',
      );
      expect(CalendarEventDisplayText.resolveSubtitle(diary), '开心');
    },
  );

  test('course translation preserves authored room and teacher text', () {
    const room = 'A楼 201';
    const teacher = '王老师';
    final events = _buildEvents(
      courses: [
        CourseItem(
          id: 'course',
          name: '数学',
          teacher: teacher,
          location: room,
          weekday: 1,
          startSection: 1,
          sectionCount: 2,
          weeks: const [1],
        ),
      ],
      courseSettings: ScheduleSettings(termStart: DateTime(2026, 9, 7)),
    );
    final event = _event(events, 'course_course_1_1');
    final metadata = event.displayMetadata! as CourseDisplayMetadata;

    expect(metadata.location, room);
    expect(metadata.teacher, teacher);
    I18n.setLocale(AppLocale.en);
    expect(
      CalendarEventDisplayText.resolveSubtitle(event),
      'Week 1 · Section 1-2 · 08:00-09:40 · $room · $teacher',
    );
  });

  test('custom anniversary subtitle without metadata stays unchanged', () {
    _expectUntranslatedSubtitle(
      type: CalendarEventType.anniversary,
      subtitle: '还有 3 天',
    );
  });

  test('custom countdown subtitle without metadata stays unchanged', () {
    _expectUntranslatedSubtitle(
      type: CalendarEventType.countdown,
      subtitle: '已过 5 天',
    );
  });

  test('custom goal subtitle without metadata stays unchanged', () {
    _expectUntranslatedSubtitle(
      type: CalendarEventType.goal,
      subtitle: '进度 42%',
    );
  });

  test('custom diary subtitle without metadata stays unchanged', () {
    _expectUntranslatedSubtitle(type: CalendarEventType.diary, subtitle: '开心');
  });

  test(
    'raw todo, time-entry, and Pomodoro text stays exact without metadata',
    () {
      final start = DateTime(2026, 10, 12, 9, 30);
      final events = [
        CalendarEvent(
          id: 'raw-todo',
          title: '专注 25 分钟',
          date: start,
          type: CalendarEventType.todo,
          color: const Color(0xFF123456),
          subtitle: '截止 10/12 09:30',
        ),
        CalendarEvent(
          id: 'raw-time-entry',
          title: '工作 · 45分钟',
          date: start,
          type: CalendarEventType.timeEntry,
          color: const Color(0xFF234567),
          subtitle: '专注 · 1小时',
        ),
        CalendarEvent(
          id: 'raw-pomodoro',
          title: '专注 25 分钟',
          date: start,
          type: CalendarEventType.pomodoro,
          color: const Color(0xFF345678),
          subtitle: '25分钟',
        ),
      ];

      expect(events.every((event) => event.displayMetadata == null), isTrue);
      for (final event in events) {
        expect(CalendarEventDisplayText.resolveTitle(event), event.title);
        expect(CalendarEventDisplayText.resolveSubtitle(event), event.subtitle);
      }

      I18n.setLocale(AppLocale.en);
      for (final event in events) {
        expect(CalendarEventDisplayText.resolveTitle(event), event.title);
        expect(CalendarEventDisplayText.resolveSubtitle(event), event.subtitle);
      }
    },
  );

  test(
    'legacy user and ICS event JSON remains compatible without metadata',
    () {
      final start = DateTime(2026, 10, 12, 9, 30);
      final userEvent = CalendarEvent(
        id: 'user-event',
        title: '专注 25 分钟',
        date: start,
        endDate: start.add(const Duration(hours: 1)),
        type: CalendarEventType.event,
        color: const Color(0xFF123456),
        subtitle: '手写备注',
        note: '用户自定义内容',
        time: const TimeOfDay(hour: 9, minute: 30),
        updatedAt: DateTime(2026, 10, 1),
      );
      final icsEvent = CalendarEvent(
        id: 'ics_feed-uid',
        title: '专注 25 分钟',
        date: start,
        endDate: start.add(const Duration(minutes: 45)),
        type: CalendarEventType.timeEntry,
        color: const Color(0xFF654321),
        subtitle: '会议室 A',
        time: const TimeOfDay(hour: 9, minute: 30),
      );

      for (final event in [userEvent, icsEvent]) {
        final json = event.toJson();
        expect(json, isNot(contains('displayMetadata')));
        final roundTrip = CalendarEvent.fromJson(json);

        expect(roundTrip.id, event.id);
        expect(roundTrip.title, event.title);
        expect(roundTrip.date, event.date);
        expect(roundTrip.endDate, event.endDate);
        expect(roundTrip.type, event.type);
        expect(roundTrip.color, event.color);
        expect(roundTrip.subtitle, event.subtitle);
        expect(roundTrip.time, event.time);
        expect(roundTrip.displayMetadata, isNull);

        I18n.setLocale(AppLocale.en);
        expect(CalendarEventDisplayText.resolveTitle(roundTrip), event.title);
        expect(
          CalendarEventDisplayText.resolveSubtitle(roundTrip),
          event.subtitle,
        );
      }
    },
  );
}

void _expectUntranslatedSubtitle({
  required CalendarEventType type,
  required String subtitle,
}) {
  final event = CalendarEvent(
    id: 'authored-${type.name}',
    title: '自定义标题',
    date: DateTime(2026, 10, 12),
    type: type,
    color: const Color(0xFF5B6EE1),
    subtitle: subtitle,
  );
  expect(event.displayMetadata, isNull);

  I18n.setLocale(AppLocale.en);
  expect(CalendarEventDisplayText.resolveSubtitle(event), subtitle);
}

List<CalendarEvent> _buildEvents({
  List<TodoItem> todos = const [],
  List<PomodoroSession> pomodoroSessions = const [],
  List<Anniversary> anniversaries = const [],
  List<CountdownItem> countdowns = const [],
  List<GoalItem> goals = const [],
  List<DiaryEntry> diaries = const [],
  List<CourseItem> courses = const [],
  ScheduleSettings? courseSettings,
  List<TimeEntry> timeEntries = const [],
}) => CalendarAggregator.buildEvents(
  todos: todos,
  habits: const <Habit>[],
  pomodoroSessions: pomodoroSessions,
  colorScheme: const ColorScheme.light(),
  anniversaries: anniversaries,
  countdowns: countdowns,
  goals: goals,
  diaries: diaries,
  courses: courses,
  courseSettings: courseSettings,
  timeEntries: timeEntries,
  now: DateTime(2026, 10, 11, 12),
);

PomodoroSession _pomodoroSession({required String id, String? taskName}) {
  final start = DateTime(2026, 10, 11, 9);
  return PomodoroSession(
    id: id,
    startTime: start,
    endTime: start.add(const Duration(minutes: 25)),
    durationSeconds: 1500,
    type: PomodoroType.focus,
    taskName: taskName,
  );
}

CalendarEvent _event(List<CalendarEvent> events, String id) =>
    events.singleWhere((event) => event.id == id);

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
