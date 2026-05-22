import 'package:duoyi/models/focus_room.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:test/test.dart';

void main() {
  test(
    'buildFocusRoomRanking ranks current user by this week focus sessions',
    () {
      final room = FocusRoom(
        id: 'deep_work_room',
        name: '深度工作自习室',
        description: 'test',
        weeklyTargetSeconds: 3600,
        accentColor: 0xFFE53935,
        createdAt: DateTime(2026, 1, 1),
        members: const [
          FocusRoomMemberSeed(
            id: 'peer-a',
            name: '同学 A',
            weeklySeconds: 2400,
            sessionCount: 2,
          ),
          FocusRoomMemberSeed(
            id: 'peer-b',
            name: '同学 B',
            weeklySeconds: 600,
            sessionCount: 1,
          ),
        ],
      );

      final ranking = buildFocusRoomRanking(
        room: room,
        now: DateTime(2026, 5, 20),
        sessions: [
          PomodoroSession(
            id: 's1',
            startTime: DateTime(2026, 5, 18, 9),
            endTime: DateTime(2026, 5, 18, 9, 25),
            durationSeconds: 1500,
            type: PomodoroType.focus,
            focusRoomId: 'deep_work_room',
          ),
          PomodoroSession(
            id: 's2',
            startTime: DateTime(2026, 5, 19, 9),
            endTime: DateTime(2026, 5, 19, 9, 25),
            durationSeconds: 1500,
            type: PomodoroType.focus,
            focusRoomId: 'deep_work_room',
          ),
          PomodoroSession(
            id: 'other-room',
            startTime: DateTime(2026, 5, 19, 10),
            endTime: DateTime(2026, 5, 19, 10, 25),
            durationSeconds: 1500,
            type: PomodoroType.focus,
            focusRoomId: 'reading_room',
          ),
          PomodoroSession(
            id: 'last-week',
            startTime: DateTime(2026, 5, 15, 9),
            endTime: DateTime(2026, 5, 15, 9, 25),
            durationSeconds: 1500,
            type: PomodoroType.focus,
            focusRoomId: 'deep_work_room',
          ),
        ],
      );

      expect(ranking.weekStart, DateTime(2026, 5, 18));
      expect(ranking.userWeeklySeconds, 3000);
      expect(ranking.userSessionCount, 2);
      expect(ranking.targetProgressPercent, 83);
      expect(ranking.entries.first.isCurrentUser, isTrue);
      expect(ranking.entries.first.rank, 1);
      expect(ranking.entries.map((e) => e.name), ['我', '同学 A', '同学 B']);
    },
  );

  test('buildFocusSocialRanking caps suspicious focus time before ranking', () {
    final ranking = buildFocusSocialRanking(
      scope: FocusLeaderboardScope.global,
      now: DateTime(2026, 5, 20, 12),
      seedMembers: const [
        FocusRoomMemberSeed(
          id: 'normal',
          name: '正常同学',
          weeklySeconds: 5 * 60 * 60,
          sessionCount: 10,
        ),
        FocusRoomMemberSeed(
          id: 'seeded-abnormal',
          name: '异常同学',
          weeklySeconds: 91 * 60 * 60,
          sessionCount: 4,
        ),
      ],
      sessions: [
        PomodoroSession(
          id: 'long-session',
          startTime: DateTime(2026, 5, 18, 8),
          endTime: DateTime(2026, 5, 18, 16),
          durationSeconds: 8 * 60 * 60,
          type: PomodoroType.focus,
        ),
        PomodoroSession(
          id: 'daily-cap-1',
          startTime: DateTime(2026, 5, 19, 8),
          endTime: DateTime(2026, 5, 19, 14),
          durationSeconds: 6 * 60 * 60,
          type: PomodoroType.focus,
        ),
        PomodoroSession(
          id: 'daily-cap-2',
          startTime: DateTime(2026, 5, 19, 15),
          endTime: DateTime(2026, 5, 19, 21),
          durationSeconds: 6 * 60 * 60,
          type: PomodoroType.focus,
        ),
        PomodoroSession(
          id: 'future',
          startTime: DateTime(2026, 5, 21, 8),
          endTime: DateTime(2026, 5, 21, 9),
          durationSeconds: 60 * 60,
          type: PomodoroType.focus,
        ),
      ],
    );

    final currentUser = ranking.entries.firstWhere((e) => e.isCurrentUser);
    final abnormal = ranking.entries.firstWhere(
      (e) => e.id == 'seeded-abnormal',
    );

    expect(ranking.title, '全局专注榜');
    expect(currentUser.rawWeeklySeconds, 20 * 60 * 60);
    expect(currentUser.weeklySeconds, 12 * 60 * 60);
    expect(currentUser.flagged, isTrue);
    expect(currentUser.flagReason, contains('单次专注超过 4 小时已封顶'));
    expect(currentUser.flagReason, contains('忽略未来专注记录'));
    expect(abnormal.weeklySeconds, 84 * 60 * 60);
    expect(abnormal.flagged, isTrue);
    expect(ranking.suspiciousEntryCount, 2);
  });
}
