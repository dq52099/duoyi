import 'package:flutter/material.dart';
import 'goal_icons.dart';
import 'diary_note_ui_copy.dart';
import 'i18n.dart';
import '../models/todo.dart';
import '../models/habit.dart';
import '../models/note.dart';
import '../models/diary_entry.dart';
import '../models/anniversary.dart';
import '../models/goal.dart';
import '../models/course_schedule.dart';
import '../models/countdown.dart';
import '../models/pomodoro.dart';
import '../models/time_entry.dart';
import '../models/calendar_event.dart';

enum SearchKind {
  todo,
  habit,
  note,
  diary,
  anniversary,
  countdown,
  goal,
  course,
  calendarEvent,
  timeEntry,
  pomodoro,
}

/// Runtime provenance for generated search headings; never inferred from text.
sealed class SearchGeneratedTitle {
  const SearchGeneratedTitle();

  String titleFor(AppLocale locale);
}

class EmptyNoteSearchTitle extends SearchGeneratedTitle {
  const EmptyNoteSearchTitle();

  @override
  String titleFor(AppLocale locale) => DiaryNoteUiCopy(locale).untitledNote;
}

class EmptyDiarySearchTitle extends SearchGeneratedTitle {
  const EmptyDiarySearchTitle(this.date);

  final DateTime date;

  @override
  String titleFor(AppLocale locale) => DiaryNoteUiCopy(locale).diaryTitle(date);
}

class SearchHit {
  final SearchKind kind;
  final String _title;
  final SearchGeneratedTitle? generatedTitle;
  final String? subtitle;
  final String sourceId;
  final DateTime? when;
  final IconData? iconOverride;

  const SearchHit({
    required this.kind,
    required String title,
    this.generatedTitle,
    this.subtitle,
    required this.sourceId,
    this.when,
    this.iconOverride,
  }) : _title = title;

  String get title => titleFor(I18n.current);

  String titleFor(AppLocale locale) =>
      generatedTitle?.titleFor(locale) ?? _title;

  IconData get icon => switch (kind) {
    SearchKind.todo => Icons.check_circle_outline,
    SearchKind.habit => Icons.repeat,
    SearchKind.note => Icons.edit_note,
    SearchKind.diary => Icons.book_outlined,
    SearchKind.anniversary => Icons.celebration_outlined,
    SearchKind.countdown => Icons.hourglass_bottom,
    SearchKind.goal => iconOverride ?? Icons.flag_circle_outlined,
    SearchKind.course => Icons.class_outlined,
    SearchKind.calendarEvent => Icons.event_available_outlined,
    SearchKind.timeEntry => Icons.timelapse_outlined,
    SearchKind.pomodoro => Icons.timer_outlined,
  };

  String get kindLabel => switch (kind) {
    SearchKind.todo => I18n.tr('search.kind.todo'),
    SearchKind.habit => I18n.tr('search.kind.habit'),
    SearchKind.note => I18n.tr('search.kind.note'),
    SearchKind.diary => I18n.tr('search.kind.diary'),
    SearchKind.anniversary => I18n.tr('search.kind.anniversary'),
    SearchKind.countdown => I18n.tr('search.kind.countdown'),
    SearchKind.goal => I18n.tr('search.kind.goal'),
    SearchKind.course => I18n.tr('search.kind.course'),
    SearchKind.calendarEvent => I18n.tr('search.kind.event'),
    SearchKind.timeEntry => I18n.tr('search.kind.time_entry'),
    SearchKind.pomodoro => I18n.current == AppLocale.en ? 'Focus' : '专注记录',
  };
}

/// 跨实体模糊搜索；纯内存，不进网络。
class GlobalSearch {
  static List<SearchHit> run({
    required String query,
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<NoteItem> notes,
    required List<DiaryEntry> diaries,
    required List<Anniversary> anniversaries,
    required List<CountdownItem> countdowns,
    required List<GoalItem> goals,
    required List<CourseItem> courses,
    List<CalendarEvent> calendarEvents = const [],
    List<TimeEntry> timeEntries = const [],
    List<PomodoroSession> pomodoroSessions = const [],
    int maxPerKind = 10,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    bool hit(String? s) => s != null && s.toLowerCase().contains(q);

    final hits = <SearchHit>[];

    hits.addAll(
      todos
          .where(
            (t) =>
                hit(t.title) ||
                hit(t.notes) ||
                hit(t.listGroupName) ||
                t.tags.any(hit),
          )
          .take(maxPerKind)
          .map(
            (t) => SearchHit(
              kind: SearchKind.todo,
              title: t.title,
              subtitle: (t.listGroupName?.trim().isNotEmpty ?? false)
                  ? t.listGroupName
                  : (t.notes.trim().isNotEmpty
                        ? t.notes
                        : (t.tags.isEmpty
                              ? null
                              : t.tags.map((tag) => '#$tag').join(' '))),
              sourceId: t.id,
              when: t.date,
            ),
          ),
    );

    hits.addAll(
      habits
          .where((h) => hit(h.name) || hit(h.category) || h.tags.any(hit))
          .take(maxPerKind)
          .map(
            (h) => SearchHit(
              kind: SearchKind.habit,
              title: h.name,
              subtitle:
                  h.category ??
                  (h.tags.isEmpty
                      ? null
                      : h.tags.map((tag) => '#$tag').join(' ')),
              sourceId: h.id,
            ),
          ),
    );

    hits.addAll(
      notes
          .where(
            (n) =>
                hit(n.content) ||
                hit(n.folder) ||
                n.tags.any(hit) ||
                n.attachments.any((a) => hit(a.name)),
          )
          .take(maxPerKind)
          .map((n) {
            final fallbackMeta = [
              if (n.folder != null && n.folder!.trim().isNotEmpty)
                n.folder!.trim(),
              if (n.tags.isNotEmpty) n.tags.map((tag) => '#$tag').join(' '),
              if (n.attachments.isNotEmpty)
                n.attachments.map((a) => a.name).join(' · '),
            ].join(' · ');
            return SearchHit(
              kind: SearchKind.note,
              title: n.title,
              generatedTitle: n.content.trim().isEmpty
                  ? const EmptyNoteSearchTitle()
                  : null,
              subtitle: n.preview.isNotEmpty
                  ? n.preview
                  : (fallbackMeta.isEmpty ? null : fallbackMeta),
              sourceId: n.id,
              when: n.updatedAt,
            );
          }),
    );

    hits.addAll(
      diaries
          .where((d) => hit(d.content) || d.tags.any(hit))
          .take(maxPerKind)
          .map(
            (d) => SearchHit(
              kind: SearchKind.diary,
              title: d.title,
              generatedTitle: d.content.trim().isEmpty
                  ? EmptyDiarySearchTitle(d.date)
                  : null,
              subtitle: d.preview,
              sourceId: d.id,
              when: d.date,
            ),
          ),
    );

    hits.addAll(
      anniversaries
          .where((a) => hit(a.title) || hit(a.description))
          .take(maxPerKind)
          .map(
            (a) => SearchHit(
              kind: SearchKind.anniversary,
              title: a.title,
              subtitle: a.description,
              sourceId: a.id,
              when: a.nextOccurrence,
            ),
          ),
    );

    hits.addAll(
      countdowns
          .where((c) => hit(c.title))
          .take(maxPerKind)
          .map(
            (c) => SearchHit(
              kind: SearchKind.countdown,
              title: c.title,
              sourceId: c.id,
              when: c.targetDate,
            ),
          ),
    );

    hits.addAll(
      goals
          .where((g) => hit(g.title) || hit(g.description))
          .take(maxPerKind)
          .map(
            (g) => SearchHit(
              kind: SearchKind.goal,
              title: g.title,
              subtitle: g.description.isEmpty ? null : g.description,
              sourceId: g.id,
              when: g.targetDate,
              iconOverride: goalIconFromName(g.icon),
            ),
          ),
    );

    hits.addAll(
      courses
          .where(
            (c) =>
                hit(c.name) || hit(c.teacher) || hit(c.location) || hit(c.note),
          )
          .take(maxPerKind)
          .map(
            (c) => SearchHit(
              kind: SearchKind.course,
              title: c.name,
              subtitle:
                  '${c.teacher.isEmpty ? '' : '${c.teacher} · '}${c.location}',
              sourceId: c.id,
            ),
          ),
    );

    hits.addAll(
      calendarEvents
          .where((event) => event.type == CalendarEventType.event)
          .where(
            (event) =>
                hit(event.title) ||
                hit(event.subtitle) ||
                hit(event.note) ||
                hit(event.projectName),
          )
          .take(maxPerKind)
          .map(
            (event) => SearchHit(
              kind: SearchKind.calendarEvent,
              title: event.title,
              subtitle: event.subtitle ?? event.note ?? event.projectName,
              sourceId: event.sourceId?.isNotEmpty == true
                  ? event.sourceId!
                  : event.id,
              when: event.date,
            ),
          ),
    );

    hits.addAll(
      timeEntries
          .where((e) => hit(e.title) || hit(e.note))
          .take(maxPerKind)
          .map(
            (e) => SearchHit(
              kind: SearchKind.timeEntry,
              title: e.title,
              subtitle: e.note,
              sourceId: e.id,
              when: e.startAt,
            ),
          ),
    );

    hits.addAll(
      pomodoroSessions
          .where((s) => hit(s.taskName) || hit(s.tag))
          .take(maxPerKind)
          .map((s) {
            final mins = (s.durationSeconds / 60).round();
            final trimmedTask = s.taskName?.trim() ?? '';
            final trimmedTag = s.tag?.trim() ?? '';
            final title = trimmedTask.isNotEmpty
                ? trimmedTask
                : trimmedTag.isNotEmpty
                ? '#$trimmedTag'
                : (I18n.current == AppLocale.en ? 'Focus session' : '专注记录');
            final durationText = I18n.current == AppLocale.en
                ? '${mins}m'
                : '$mins分钟';
            final subtitle = trimmedTag.isNotEmpty
                ? '#$trimmedTag · $durationText'
                : durationText;
            return SearchHit(
              kind: SearchKind.pomodoro,
              title: title,
              subtitle: subtitle,
              sourceId: s.id,
              when: s.startTime,
            );
          }),
    );

    return hits;
  }
}
