import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/focus_room.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:test/test.dart';

void main() {
  late AppLocale savedLocale;

  setUp(() {
    savedLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(savedLocale));

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

  test(
    'cached local ranking reasons localize without changing score or inputs',
    () {
      final now = DateTime(2026, 5, 20, 12);
      final sessions = [
        PomodoroSession(
          id: 'long-session',
          startTime: DateTime(2026, 5, 18, 8),
          endTime: DateTime(2026, 5, 18, 16),
          durationSeconds: 8 * 60 * 60,
          type: PomodoroType.focus,
        ),
        for (var index = 0; index < 4; index++)
          PomodoroSession(
            id: 'daily-$index',
            startTime: DateTime(2026, 5, 19, 8 + index * 4),
            endTime: DateTime(2026, 5, 19, 12 + index * 4),
            durationSeconds: 4 * 60 * 60,
            type: PomodoroType.focus,
          ),
        PomodoroSession(
          id: 'future-session',
          startTime: DateTime(2026, 5, 21, 8),
          endTime: DateTime(2026, 5, 21, 9),
          durationSeconds: 60 * 60,
          type: PomodoroType.focus,
        ),
      ];
      const seeds = [
        FocusRoomMemberSeed(
          id: 'weekly-cap',
          name: '周上限成员',
          weeklySeconds: 91 * 60 * 60,
          sessionCount: 30,
        ),
        FocusRoomMemberSeed(
          id: 'normal',
          name: '普通成员',
          weeklySeconds: 15 * 60 * 60,
          sessionCount: 20,
        ),
      ];
      final sessionsJsonBefore = jsonEncode(
        sessions.map((session) => session.toJson()).toList(),
      );
      final seedsJsonBefore = jsonEncode(
        seeds.map((seed) => seed.toJson()).toList(),
      );
      FocusSocialRanking rank() => buildFocusSocialRanking(
        scope: FocusLeaderboardScope.global,
        now: now,
        sessions: sessions,
        seedMembers: seeds,
      );

      I18n.setLocale(AppLocale.zh);
      final ranking = rank();
      final currentUser = ranking.entries.firstWhere(
        (entry) => entry.isCurrentUser,
      );
      final cappedSeed = ranking.entries.firstWhere(
        (entry) => entry.id == 'weekly-cap',
      );
      final normal = ranking.entries.firstWhere(
        (entry) => entry.id == 'normal',
      );
      final scoresAndRanks = [
        for (final entry in ranking.entries)
          [
            entry.id,
            entry.rawWeeklySeconds,
            entry.weeklySeconds,
            entry.sessionCount,
            entry.rank,
            entry.flagged,
            entry.generatedFlagReasons,
          ],
      ];
      final enumMask =
          FocusFlagReasonCode.longSessionCap.mask |
          FocusFlagReasonCode.dailyCap.mask |
          FocusFlagReasonCode.futureSessionIgnored.mask;

      expect(ranking.title, '全局专注榜');
      expect(ranking.subtitle, '按全站本周有效专注时长排名');
      expect(currentUser.id, 'current_user');
      expect(currentUser.rank, 2);
      expect(currentUser.rawWeeklySeconds, 24 * 60 * 60);
      expect(currentUser.weeklySeconds, 16 * 60 * 60);
      expect(currentUser.sessionCount, 5);
      expect(currentUser.flagged, isTrue);
      expect(currentUser.generatedFlagReasons, enumMask);
      expect(
        currentUser.flagReasonFor(AppLocale.zh),
        '单次专注超过 4 小时已封顶；单日有效专注超过 12 小时已封顶；忽略未来专注记录',
      );
      expect(cappedSeed.rank, 1);
      expect(cappedSeed.rawWeeklySeconds, 91 * 60 * 60);
      expect(cappedSeed.weeklySeconds, 84 * 60 * 60);
      expect(
        cappedSeed.generatedFlagReasons,
        FocusFlagReasonCode.weeklyCap.mask,
      );
      expect(cappedSeed.flagReasonFor(AppLocale.zh), '超过每周有效时长上限');
      expect(normal.rank, 3);
      expect(normal.generatedFlagReasons, 0);

      I18n.setLocale(AppLocale.en);
      expect(ranking.title, 'Global focus ranking');
      expect(
        ranking.subtitle,
        'Ranked by credited focus time across all users this week',
      );
      expect(
        currentUser.flagReason,
        'Sessions over 4 hours were capped; Daily credited focus over 12 hours was capped; Future focus records were ignored',
      );
      expect(currentUser.flagReasonFor(AppLocale.en), currentUser.flagReason);
      expect(cappedSeed.flagReason, 'Weekly credited time exceeded the limit');
      expect(ranking.entries.map((entry) => entry.rank).toList(), [1, 2, 3]);
      expect([
        for (final entry in ranking.entries)
          [
            entry.id,
            entry.rawWeeklySeconds,
            entry.weeklySeconds,
            entry.sessionCount,
            entry.rank,
            entry.flagged,
            entry.generatedFlagReasons,
          ],
      ], scoresAndRanks);
      expect(
        jsonEncode(sessions.map((session) => session.toJson()).toList()),
        sessionsJsonBefore,
      );
      expect(
        jsonEncode(seeds.map((seed) => seed.toJson()).toList()),
        seedsJsonBefore,
      );
      expect(I18n.current, AppLocale.en);
    },
  );

  test(
    'literal reason matching app copy remains literal without provenance',
    () {
      const entry = FocusRoomRankingEntry(
        id: 'remote-literal',
        name: '服务端成员',
        weeklySeconds: 600,
        sessionCount: 1,
        isCurrentUser: false,
        flagged: true,
        flagReason: '单次专注超过 4 小时已封顶',
        rank: 1,
      );

      I18n.setLocale(AppLocale.zh);
      expect(entry.flagReason, '单次专注超过 4 小时已封顶');
      I18n.setLocale(AppLocale.en);
      expect(entry.flagReasonFor(AppLocale.zh), '单次专注超过 4 小时已封顶');
      expect(entry.flagReasonFor(AppLocale.en), '单次专注超过 4 小时已封顶');
      expect(entry.flagReason, '单次专注超过 4 小时已封顶');
      expect(entry.generatedFlagReasons, 0);
    },
  );

  test('social ranking headings follow locale for both scopes', () {
    final friends = FocusSocialRanking(
      scope: FocusLeaderboardScope.friends,
      entries: const [],
      weekStart: DateTime(2026, 5, 18),
      weekEnd: DateTime(2026, 5, 25),
      suspiciousEntryCount: 0,
    );
    final global = FocusSocialRanking(
      scope: FocusLeaderboardScope.global,
      entries: const [],
      weekStart: DateTime(2026, 5, 18),
      weekEnd: DateTime(2026, 5, 25),
      suspiciousEntryCount: 0,
    );

    I18n.setLocale(AppLocale.zh);
    expect(friends.title, '好友专注榜');
    expect(friends.subtitle, '按好友本周有效专注时长排名');
    expect(global.title, '全局专注榜');
    expect(global.subtitle, '按全站本周有效专注时长排名');

    I18n.setLocale(AppLocale.en);
    expect(friends.title, 'Friends focus ranking');
    expect(
      friends.subtitle,
      'Ranked by friends’ credited focus time this week',
    );
    expect(global.title, 'Global focus ranking');
    expect(
      global.subtitle,
      'Ranked by credited focus time across all users this week',
    );
    expect(friends.titleFor(AppLocale.zh), '好友专注榜');
    expect(I18n.current, AppLocale.en);
  });

  test('FocusRoom JSON remains compatible with sparse stored payloads', () {
    final room = FocusRoom.fromJson({
      'id': 42,
      'name': '兼容自习室',
      'description': null,
      'weeklyTargetSeconds': 3600.6,
      'accentColor': 0xFF00897B,
      'members': [
        {'id': 7, 'name': null, 'weeklySeconds': 1200.4, 'sessionCount': 3.2},
        'ignored legacy item',
      ],
      'createdAt': '2026-05-31T08:00:00.000Z',
    });

    expect(room.id, '42');
    expect(room.name, '兼容自习室');
    expect(room.description, '');
    expect(room.weeklyTargetSeconds, 3601);
    expect(room.accentColor, 0xFF00897B);
    expect(room.members, hasLength(1));
    expect(room.members.single.id, '7');
    expect(room.members.single.name, '同学');
    expect(room.members.single.weeklySeconds, 1200);
    expect(room.members.single.sessionCount, 3);
    expect(room.createdAt.toUtc(), DateTime.utc(2026, 5, 31, 8));

    final encoded = room.toJson();
    expect(encoded, containsPair('weeklyTargetSeconds', 3601));
    expect(encoded, containsPair('accentColor', 0xFF00897B));
    expect(
      encoded,
      containsPair('createdAt', room.createdAt.toIso8601String()),
    );

    final restored = FocusRoom.fromJson(encoded);
    expect(restored.id, room.id);
    expect(restored.members.single.toJson(), room.members.single.toJson());

    final sparse = FocusRoom.fromJson({
      'members': [
        {'id': 'peer-only'},
      ],
      'createdAt': 'not-a-date',
    });
    expect(sparse.id, isEmpty);
    expect(sparse.name, '专注自习室');
    expect(sparse.weeklyTargetSeconds, 0);
    expect(sparse.accentColor, 0xFFE53935);
    expect(sparse.members.single.name, '同学');
    expect(sparse.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
  });
}
