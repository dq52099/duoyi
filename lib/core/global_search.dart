import 'package:flutter/material.dart';
import '../models/todo.dart';
import '../models/habit.dart';
import '../models/note.dart';
import '../models/diary_entry.dart';
import '../models/anniversary.dart';
import '../models/goal.dart';
import '../models/course_schedule.dart';
import '../models/countdown.dart';

enum SearchKind {
  todo,
  habit,
  note,
  diary,
  anniversary,
  countdown,
  goal,
  course,
}

class SearchHit {
  final SearchKind kind;
  final String title;
  final String? subtitle;
  final String sourceId;
  final DateTime? when;

  const SearchHit({
    required this.kind,
    required this.title,
    this.subtitle,
    required this.sourceId,
    this.when,
  });

  IconData get icon => switch (kind) {
        SearchKind.todo => Icons.check_circle_outline,
        SearchKind.habit => Icons.repeat,
        SearchKind.note => Icons.edit_note,
        SearchKind.diary => Icons.book_outlined,
        SearchKind.anniversary => Icons.celebration_outlined,
        SearchKind.countdown => Icons.hourglass_bottom,
        SearchKind.goal => Icons.flag_outlined,
        SearchKind.course => Icons.class_outlined,
      };

  String get kindLabel => switch (kind) {
        SearchKind.todo => '待办',
        SearchKind.habit => '习惯',
        SearchKind.note => '笔记',
        SearchKind.diary => '日记',
        SearchKind.anniversary => '纪念',
        SearchKind.countdown => '倒数',
        SearchKind.goal => '目标',
        SearchKind.course => '课程',
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
    int maxPerKind = 10,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    bool hit(String? s) => s != null && s.toLowerCase().contains(q);

    final hits = <SearchHit>[];

    hits.addAll(todos
        .where((t) => hit(t.title) || hit(t.notes) || hit(t.listGroupName))
        .take(maxPerKind)
        .map((t) => SearchHit(
              kind: SearchKind.todo,
              title: t.title,
              subtitle: t.listGroupName ?? t.notes,
              sourceId: t.id,
              when: t.date,
            )));

    hits.addAll(habits
        .where((h) => hit(h.name) || hit(h.category))
        .take(maxPerKind)
        .map((h) => SearchHit(
              kind: SearchKind.habit,
              title: h.name,
              subtitle: h.category,
              sourceId: h.id,
            )));

    hits.addAll(notes
        .where((n) => hit(n.content))
        .take(maxPerKind)
        .map((n) => SearchHit(
              kind: SearchKind.note,
              title: n.title,
              subtitle: n.preview,
              sourceId: n.id,
              when: n.updatedAt,
            )));

    hits.addAll(diaries
        .where((d) => hit(d.content) || d.tags.any(hit))
        .take(maxPerKind)
        .map((d) => SearchHit(
              kind: SearchKind.diary,
              title: d.title,
              subtitle: d.preview,
              sourceId: d.id,
              when: d.date,
            )));

    hits.addAll(anniversaries
        .where((a) => hit(a.title) || hit(a.description))
        .take(maxPerKind)
        .map((a) => SearchHit(
              kind: SearchKind.anniversary,
              title: a.title,
              subtitle: a.description,
              sourceId: a.id,
              when: a.nextOccurrence,
            )));

    hits.addAll(countdowns
        .where((c) => hit(c.title))
        .take(maxPerKind)
        .map((c) => SearchHit(
              kind: SearchKind.countdown,
              title: c.title,
              sourceId: c.id,
              when: c.targetDate,
            )));

    hits.addAll(goals
        .where((g) => hit(g.title) || hit(g.description))
        .take(maxPerKind)
        .map((g) => SearchHit(
              kind: SearchKind.goal,
              title: g.title,
              subtitle: g.description.isEmpty ? null : g.description,
              sourceId: g.id,
              when: g.targetDate,
            )));

    hits.addAll(courses
        .where((c) =>
            hit(c.name) || hit(c.teacher) || hit(c.location) || hit(c.note))
        .take(maxPerKind)
        .map((c) => SearchHit(
              kind: SearchKind.course,
              title: c.name,
              subtitle:
                  '${c.teacher.isEmpty ? '' : '${c.teacher} · '}${c.location}',
              sourceId: c.id,
            )));

    return hits;
  }
}
