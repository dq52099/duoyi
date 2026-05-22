import 'package:duoyi/core/focus_tag_stats.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:test/test.dart';

void main() {
  PomodoroSession session({
    required String id,
    required String? tag,
    required int minutes,
    PomodoroType type = PomodoroType.focus,
    DateTime? startAt,
  }) {
    final start = startAt ?? DateTime(2026, 5, 20, 9, 35);
    final end = start.add(Duration(minutes: minutes));
    return PomodoroSession(
      id: id,
      startTime: start,
      endTime: end,
      durationSeconds: minutes * 60,
      type: type,
      tag: tag,
    );
  }

  test(
    'groups focus sessions by normalized tag and ranks by total minutes',
    () {
      final stats = FocusTagStats.build(
        sessions: [
          session(id: '1', tag: '学习', minutes: 25),
          session(id: '2', tag: '#学习', minutes: 30),
          session(id: '3', tag: '工作', minutes: 40),
          session(id: '4', tag: ' ', minutes: 15),
          session(
            id: '5',
            tag: '学习',
            minutes: 5,
            type: PomodoroType.shortBreak,
          ),
        ],
      );

      expect(stats.map((s) => s.tag), [
        '学习',
        '工作',
        FocusTagStats.untaggedLabel,
      ]);
      expect(stats.first.totalMinutes, 55);
      expect(stats.first.sessionCount, 2);
      expect(stats.first.averageMinutes, 27);
      expect(stats.first.share, closeTo(55 / 110, 0.001));
    },
  );

  test('respects limit after sorting', () {
    final stats = FocusTagStats.build(
      limit: 2,
      sessions: [
        session(id: '1', tag: 'A', minutes: 10),
        session(id: '2', tag: 'B', minutes: 30),
        session(id: '3', tag: 'C', minutes: 20),
      ],
    );

    expect(stats.map((s) => s.tag), ['B', 'C']);
  });

  test('builds day trend for selected focus tags', () {
    final trend = FocusTagStats.buildTrend(
      start: DateTime(2026, 5, 18),
      end: DateTime(2026, 5, 20),
      tags: const ['学习', '工作'],
      bucket: FocusTagTrendBucket.day,
      sessions: [
        session(
          id: '1',
          tag: '学习',
          minutes: 25,
          startAt: DateTime(2026, 5, 18, 9),
        ),
        session(
          id: '2',
          tag: '#学习',
          minutes: 30,
          startAt: DateTime(2026, 5, 20, 9),
        ),
        session(
          id: '3',
          tag: '工作',
          minutes: 40,
          startAt: DateTime(2026, 5, 19, 9),
        ),
        session(
          id: '4',
          tag: '阅读',
          minutes: 50,
          startAt: DateTime(2026, 5, 20, 10),
        ),
      ],
    );

    expect(trend.map((s) => s.tag), ['学习', '工作']);
    expect(trend.first.points.map((p) => p.label), ['5/18', '5/19', '5/20']);
    expect(trend.first.points.map((p) => p.minutes), [25, 0, 30]);
    expect(trend.last.points.map((p) => p.minutes), [0, 40, 0]);
  });

  test('builds month trend for year range', () {
    final trend = FocusTagStats.buildTrend(
      start: DateTime(2026),
      end: DateTime(2026, 3, 20),
      tags: const ['学习'],
      bucket: FocusTagTrendBucket.month,
      sessions: [
        session(
          id: '1',
          tag: '学习',
          minutes: 25,
          startAt: DateTime(2026, 1, 10, 9),
        ),
        session(
          id: '2',
          tag: '学习',
          minutes: 30,
          startAt: DateTime(2026, 3, 1, 9),
        ),
      ],
    );

    expect(trend.single.points.map((p) => p.label), ['1月', '2月', '3月']);
    expect(trend.single.points.map((p) => p.minutes), [25, 0, 30]);
  });
}
