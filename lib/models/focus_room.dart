import 'pomodoro.dart';

enum FocusLeaderboardScope { friends, global }

class FocusRoomMemberSeed {
  final String id;
  final String name;
  final int weeklySeconds;
  final int sessionCount;

  const FocusRoomMemberSeed({
    required this.id,
    required this.name,
    required this.weeklySeconds,
    required this.sessionCount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'weeklySeconds': weeklySeconds,
    'sessionCount': sessionCount,
  };

  factory FocusRoomMemberSeed.fromJson(Map<String, dynamic> json) =>
      FocusRoomMemberSeed(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '同学',
        weeklySeconds: (json['weeklySeconds'] as num?)?.round() ?? 0,
        sessionCount: (json['sessionCount'] as num?)?.round() ?? 0,
      );
}

class FocusRoom {
  final String id;
  final String name;
  final String description;
  final int weeklyTargetSeconds;
  final int accentColor;
  final List<FocusRoomMemberSeed> members;
  final DateTime createdAt;

  const FocusRoom({
    required this.id,
    required this.name,
    required this.description,
    required this.weeklyTargetSeconds,
    required this.accentColor,
    required this.members,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'weeklyTargetSeconds': weeklyTargetSeconds,
    'accentColor': accentColor,
    'members': members.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory FocusRoom.fromJson(Map<String, dynamic> json) => FocusRoom(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '专注自习室',
    description: json['description']?.toString() ?? '',
    weeklyTargetSeconds: (json['weeklyTargetSeconds'] as num?)?.round() ?? 0,
    accentColor: (json['accentColor'] as num?)?.round() ?? 0xFFE53935,
    members:
        (json['members'] as List?)
            ?.whereType<Map>()
            .map((m) => FocusRoomMemberSeed.fromJson(Map.from(m)))
            .toList() ??
        const <FocusRoomMemberSeed>[],
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class FocusRoomRankingEntry {
  final String id;
  final String name;
  final int weeklySeconds;
  final int rawWeeklySeconds;
  final int sessionCount;
  final bool isCurrentUser;
  final bool online;
  final bool active;
  final bool flagged;
  final String? flagReason;
  final int rank;
  final DateTime? lastSeenAt;

  const FocusRoomRankingEntry({
    required this.id,
    required this.name,
    required this.weeklySeconds,
    this.rawWeeklySeconds = 0,
    required this.sessionCount,
    required this.isCurrentUser,
    this.online = false,
    this.active = true,
    this.flagged = false,
    this.flagReason,
    required this.rank,
    this.lastSeenAt,
  });

  int get weeklyMinutes => weeklySeconds ~/ 60;
  int get rawWeeklyMinutes =>
      rawWeeklySeconds <= 0 ? weeklyMinutes : rawWeeklySeconds ~/ 60;
}

class FocusRoomRanking {
  final FocusRoom room;
  final List<FocusRoomRankingEntry> entries;
  final int userWeeklySeconds;
  final int userSessionCount;
  final DateTime weekStart;
  final DateTime weekEnd;
  final bool remote;
  final int onlineCount;
  final DateTime? updatedAt;

  const FocusRoomRanking({
    required this.room,
    required this.entries,
    required this.userWeeklySeconds,
    required this.userSessionCount,
    required this.weekStart,
    required this.weekEnd,
    this.remote = false,
    this.onlineCount = 0,
    this.updatedAt,
  });

  int get userWeeklyMinutes => userWeeklySeconds ~/ 60;
  int get totalWeeklySeconds =>
      entries.fold(0, (sum, entry) => sum + entry.weeklySeconds);
  int get targetProgressPercent => room.weeklyTargetSeconds <= 0
      ? 0
      : ((userWeeklySeconds / room.weeklyTargetSeconds) * 100)
            .clamp(0, 999)
            .round();
}

class FocusSocialRanking {
  final FocusLeaderboardScope scope;
  final List<FocusRoomRankingEntry> entries;
  final DateTime weekStart;
  final DateTime weekEnd;
  final int suspiciousEntryCount;
  final bool remote;
  final int onlineCount;
  final DateTime? updatedAt;

  const FocusSocialRanking({
    required this.scope,
    required this.entries,
    required this.weekStart,
    required this.weekEnd,
    required this.suspiciousEntryCount,
    this.remote = false,
    this.onlineCount = 0,
    this.updatedAt,
  });

  String get title => switch (scope) {
    FocusLeaderboardScope.friends => '好友专注榜',
    FocusLeaderboardScope.global => '全局专注榜',
  };

  String get subtitle => switch (scope) {
    FocusLeaderboardScope.friends => '按好友本周有效专注时长排名',
    FocusLeaderboardScope.global => '按全站本周有效专注时长排名',
  };
}

DateTime focusRoomWeekStart(DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

const int _maxCreditedSessionSeconds = 4 * 60 * 60;
const int _maxCreditedDailySeconds = 12 * 60 * 60;

FocusRoomRanking buildFocusRoomRanking({
  required FocusRoom room,
  required Iterable<PomodoroSession> sessions,
  required DateTime now,
  String currentUserName = '我',
}) {
  final start = focusRoomWeekStart(now);
  final end = start.add(const Duration(days: 7));
  final roomSessions = sessions.where(
    (s) =>
        s.type == PomodoroType.focus &&
        s.focusRoomId == room.id &&
        !s.startTime.isBefore(start) &&
        s.startTime.isBefore(end),
  );
  final userScore = _scoreSessionsWithAntiCheat(
    roomSessions,
    now: now,
    weekStart: start,
    weekEnd: end,
  );
  final rawEntries =
      <FocusRoomRankingEntry>[
        FocusRoomRankingEntry(
          id: 'current_user',
          name: currentUserName,
          weeklySeconds: userScore.creditedSeconds,
          rawWeeklySeconds: userScore.rawSeconds,
          sessionCount: userScore.sessionCount,
          isCurrentUser: true,
          online: true,
          flagged: userScore.flagged,
          flagReason: userScore.flagReason,
          rank: 0,
        ),
        ...room.members.map(
          (m) => FocusRoomRankingEntry(
            id: m.id,
            name: m.name,
            weeklySeconds: m.weeklySeconds,
            rawWeeklySeconds: m.weeklySeconds,
            sessionCount: m.sessionCount,
            isCurrentUser: false,
            online: false,
            rank: 0,
          ),
        ),
      ]..sort((a, b) {
        final bySeconds = b.weeklySeconds.compareTo(a.weeklySeconds);
        if (bySeconds != 0) return bySeconds;
        final bySessions = b.sessionCount.compareTo(a.sessionCount);
        if (bySessions != 0) return bySessions;
        return a.name.compareTo(b.name);
      });

  final ranked = <FocusRoomRankingEntry>[];
  for (var i = 0; i < rawEntries.length; i++) {
    final entry = rawEntries[i];
    ranked.add(
      FocusRoomRankingEntry(
        id: entry.id,
        name: entry.name,
        weeklySeconds: entry.weeklySeconds,
        rawWeeklySeconds: entry.rawWeeklySeconds,
        sessionCount: entry.sessionCount,
        isCurrentUser: entry.isCurrentUser,
        online: entry.online,
        active: entry.active,
        flagged: entry.flagged,
        flagReason: entry.flagReason,
        rank: i + 1,
        lastSeenAt: entry.lastSeenAt,
      ),
    );
  }

  return FocusRoomRanking(
    room: room,
    entries: ranked,
    userWeeklySeconds: userScore.creditedSeconds,
    userSessionCount: userScore.sessionCount,
    weekStart: start,
    weekEnd: end,
  );
}

FocusSocialRanking buildFocusSocialRanking({
  required FocusLeaderboardScope scope,
  required Iterable<PomodoroSession> sessions,
  required Iterable<FocusRoomMemberSeed> seedMembers,
  required DateTime now,
  String currentUserName = '我',
}) {
  final start = focusRoomWeekStart(now);
  final end = start.add(const Duration(days: 7));
  final userSessions = sessions.where(
    (s) =>
        s.type == PomodoroType.focus &&
        !s.startTime.isBefore(start) &&
        s.startTime.isBefore(end),
  );
  final userScore = _scoreSessionsWithAntiCheat(
    userSessions,
    now: now,
    weekStart: start,
    weekEnd: end,
  );
  final rawEntries =
      <FocusRoomRankingEntry>[
        FocusRoomRankingEntry(
          id: 'current_user',
          name: currentUserName,
          weeklySeconds: userScore.creditedSeconds,
          rawWeeklySeconds: userScore.rawSeconds,
          sessionCount: userScore.sessionCount,
          isCurrentUser: true,
          online: true,
          flagged: userScore.flagged,
          flagReason: userScore.flagReason,
          rank: 0,
        ),
        ...seedMembers.map((m) {
          final seeded = _scoreSeedMember(m);
          return FocusRoomRankingEntry(
            id: m.id,
            name: m.name,
            weeklySeconds: seeded.creditedSeconds,
            rawWeeklySeconds: seeded.rawSeconds,
            sessionCount: seeded.sessionCount,
            isCurrentUser: false,
            online: false,
            flagged: seeded.flagged,
            flagReason: seeded.flagReason,
            rank: 0,
          );
        }),
      ]..sort((a, b) {
        final bySeconds = b.weeklySeconds.compareTo(a.weeklySeconds);
        if (bySeconds != 0) return bySeconds;
        final bySessions = b.sessionCount.compareTo(a.sessionCount);
        if (bySessions != 0) return bySessions;
        return a.name.compareTo(b.name);
      });

  final ranked = <FocusRoomRankingEntry>[];
  for (var i = 0; i < rawEntries.length; i++) {
    final entry = rawEntries[i];
    ranked.add(
      FocusRoomRankingEntry(
        id: entry.id,
        name: entry.name,
        weeklySeconds: entry.weeklySeconds,
        rawWeeklySeconds: entry.rawWeeklySeconds,
        sessionCount: entry.sessionCount,
        isCurrentUser: entry.isCurrentUser,
        online: entry.online,
        active: entry.active,
        flagged: entry.flagged,
        flagReason: entry.flagReason,
        rank: i + 1,
        lastSeenAt: entry.lastSeenAt,
      ),
    );
  }

  return FocusSocialRanking(
    scope: scope,
    entries: ranked,
    weekStart: start,
    weekEnd: end,
    suspiciousEntryCount: ranked.where((entry) => entry.flagged).length,
  );
}

class _FocusAntiCheatScore {
  final int rawSeconds;
  final int creditedSeconds;
  final int sessionCount;
  final bool flagged;
  final String? flagReason;

  const _FocusAntiCheatScore({
    required this.rawSeconds,
    required this.creditedSeconds,
    required this.sessionCount,
    required this.flagged,
    this.flagReason,
  });
}

_FocusAntiCheatScore _scoreSeedMember(FocusRoomMemberSeed member) {
  final creditedSeconds = member.weeklySeconds
      .clamp(0, _maxCreditedDailySeconds * 7)
      .toInt();
  final flagged = creditedSeconds != member.weeklySeconds;
  return _FocusAntiCheatScore(
    rawSeconds: member.weeklySeconds,
    creditedSeconds: creditedSeconds,
    sessionCount: member.sessionCount,
    flagged: flagged,
    flagReason: flagged ? '超过每周有效时长上限' : null,
  );
}

_FocusAntiCheatScore _scoreSessionsWithAntiCheat(
  Iterable<PomodoroSession> sessions, {
  required DateTime now,
  required DateTime weekStart,
  required DateTime weekEnd,
}) {
  final daily = <DateTime, int>{};
  var rawSeconds = 0;
  var creditedSeconds = 0;
  var sessionCount = 0;
  var clippedLongSession = false;
  var clippedDailyCap = false;
  var futureSession = false;

  for (final session in sessions) {
    if (session.startTime.isAfter(now)) {
      futureSession = true;
      continue;
    }
    if (session.startTime.isBefore(weekStart) ||
        !session.startTime.isBefore(weekEnd)) {
      continue;
    }
    sessionCount++;
    final raw = session.durationSeconds < 0 ? 0 : session.durationSeconds;
    rawSeconds += raw;
    final sessionCredit = raw.clamp(0, _maxCreditedSessionSeconds).toInt();
    if (sessionCredit != raw) clippedLongSession = true;
    final day = DateTime(
      session.startTime.year,
      session.startTime.month,
      session.startTime.day,
    );
    final alreadyCredited = daily[day] ?? 0;
    final remaining = _maxCreditedDailySeconds - alreadyCredited;
    if (remaining <= 0) {
      clippedDailyCap = true;
      continue;
    }
    final credited = sessionCredit.clamp(0, remaining).toInt();
    if (credited != sessionCredit) clippedDailyCap = true;
    daily[day] = alreadyCredited + credited;
    creditedSeconds += credited;
  }

  final reasons = <String>[
    if (clippedLongSession) '单次专注超过 4 小时已封顶',
    if (clippedDailyCap) '单日有效专注超过 12 小时已封顶',
    if (futureSession) '忽略未来专注记录',
  ];
  return _FocusAntiCheatScore(
    rawSeconds: rawSeconds,
    creditedSeconds: creditedSeconds,
    sessionCount: sessionCount,
    flagged: reasons.isNotEmpty,
    flagReason: reasons.isEmpty ? null : reasons.join('；'),
  );
}
