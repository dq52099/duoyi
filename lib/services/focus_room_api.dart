import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import '../models/focus_room.dart';

Object? _remoteValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    if (json.containsKey(key) && json[key] != null) return json[key];
  }
  return null;
}

String _remoteString(
  Map<String, dynamic> json,
  List<String> keys,
  String fallback,
) {
  final raw = _remoteValue(json, keys);
  final value = raw?.toString();
  return value == null || value.isEmpty ? fallback : value;
}

int _remoteInt(Map<String, dynamic> json, List<String> keys, int fallback) {
  final raw = _remoteValue(json, keys);
  if (raw is num) return raw.round();
  return int.tryParse(raw?.toString() ?? '') ?? fallback;
}

DateTime? _remoteDate(Map<String, dynamic> json, List<String> keys) {
  return DateTime.tryParse(_remoteValue(json, keys)?.toString() ?? '');
}

FocusRoom _focusRoomFromRemote(Map<String, dynamic> json) {
  return FocusRoom(
    id: _remoteString(json, const ['id', 'room_id', 'roomId'], ''),
    name: _remoteString(json, const ['name', 'room_name', 'roomName'], '专注自习室'),
    description: _remoteString(json, const ['description'], ''),
    weeklyTargetSeconds: _remoteInt(
      json,
      const ['weekly_target_seconds', 'weeklyTargetSeconds'],
      5 * 60 * 60,
    ),
    accentColor: _remoteInt(
      json,
      const ['accent_color', 'accentColor'],
      0xFF3949AB,
    ),
    members: const <FocusRoomMemberSeed>[],
    createdAt: DateTime.now(),
  );
}

List<String> _focusRiskFlagsFromRemote(Object? raw) {
  Iterable<Object?> values = const <Object?>[];
  if (raw is List) {
    values = raw;
  } else if (raw is String) {
    final clean = raw.trim();
    if (clean.isEmpty) return const <String>[];
    try {
      final decoded = json.decode(clean);
      if (decoded is List) {
        values = decoded;
      } else {
        values = clean.split('|');
      }
    } catch (_) {
      values = clean.split('|');
    }
  }
  return values
      .map((flag) => flag?.toString().trim() ?? '')
      .where((flag) => flag.isNotEmpty)
      .toList(growable: false);
}

class FocusRoomRemoteEntry {
  final String userId;
  final String displayName;
  final int weeklySeconds;
  final int rawWeeklySeconds;
  final int sessionCount;
  final bool online;
  final bool active;
  final bool isCurrentUser;
  final int rank;
  final DateTime? lastSeenAt;
  final List<String> riskFlags;
  final String riskSummary;

  const FocusRoomRemoteEntry({
    required this.userId,
    required this.displayName,
    required this.weeklySeconds,
    required this.rawWeeklySeconds,
    required this.sessionCount,
    required this.online,
    required this.active,
    required this.isCurrentUser,
    required this.rank,
    this.lastSeenAt,
    this.riskFlags = const <String>[],
    this.riskSummary = '',
  });

  factory FocusRoomRemoteEntry.fromJson(Map<String, dynamic> json) {
    return FocusRoomRemoteEntry(
      userId: _remoteString(json, const ['user_id', 'userId'], ''),
      displayName: _remoteString(
        json,
        const ['display_name', 'displayName', 'username'],
        '同学',
      ),
      weeklySeconds: _remoteInt(
        json,
        const ['weekly_seconds', 'weeklySeconds'],
        0,
      ),
      rawWeeklySeconds: _remoteInt(
        json,
        const ['raw_weekly_seconds', 'rawWeeklySeconds'],
        0,
      ),
      sessionCount: _remoteInt(
        json,
        const ['session_count', 'sessionCount'],
        0,
      ),
      online: json['online'] == true,
      active: json['active'] != false,
      isCurrentUser: json['is_current_user'] == true ||
          json['isCurrentUser'] == true,
      rank: _remoteInt(json, const ['rank'], 0),
      lastSeenAt: _remoteDate(json, const ['last_seen_at', 'lastSeenAt']),
      riskFlags: _focusRiskFlagsFromRemote(
        _remoteValue(json, const ['risk_flags', 'riskFlags']),
      ),
      riskSummary: _remoteString(
        json,
        const ['risk_summary', 'riskSummary'],
        '',
      ),
    );
  }
}

class FocusRoomRemoteRanking {
  final String roomId;
  final int onlineCount;
  final DateTime? updatedAt;
  final List<FocusRoomRemoteEntry> entries;

  const FocusRoomRemoteRanking({
    required this.roomId,
    required this.onlineCount,
    required this.updatedAt,
    required this.entries,
  });

  factory FocusRoomRemoteRanking.fromJson(Map<String, dynamic> json) {
    return FocusRoomRemoteRanking(
      roomId: _remoteString(json, const ['room_id', 'roomId'], ''),
      onlineCount: _remoteInt(json, const ['online_count', 'onlineCount'], 0),
      updatedAt: _remoteDate(json, const ['updated_at', 'updatedAt']),
      entries:
          (_remoteValue(json, const ['entries', 'items']) as List?)
              ?.whereType<Map>()
              .map(
                (entry) => FocusRoomRemoteEntry.fromJson(
                  Map<String, dynamic>.from(entry),
                ),
              )
              .toList() ??
          const <FocusRoomRemoteEntry>[],
    );
  }
}

class FocusFriend {
  final String userId;
  final String username;
  final String status;
  final bool online;
  final DateTime? lastActiveAt;
  final DateTime? createdAt;

  const FocusFriend({
    required this.userId,
    required this.username,
    required this.status,
    required this.online,
    this.lastActiveAt,
    this.createdAt,
  });

  factory FocusFriend.fromJson(Map<String, dynamic> json) {
    return FocusFriend(
      userId: _remoteString(json, const ['user_id', 'userId', 'id'], ''),
      username: _remoteString(
        json,
        const ['username', 'display_name', 'displayName'],
        '同学',
      ),
      status: _remoteString(json, const ['status'], 'accepted'),
      online: json['online'] == true,
      lastActiveAt: _remoteDate(
        json,
        const ['last_active_at', 'lastActiveAt'],
      ),
      createdAt: _remoteDate(json, const ['created_at', 'createdAt']),
    );
  }
}

class FocusFriendRequest {
  final String id;
  final String userId;
  final String username;
  final String direction;
  final String status;
  final bool online;
  final DateTime? createdAt;

  const FocusFriendRequest({
    required this.id,
    required this.userId,
    required this.username,
    required this.direction,
    required this.status,
    required this.online,
    this.createdAt,
  });

  bool get incoming => direction == 'incoming';
  bool get outgoing => direction == 'outgoing';

  factory FocusFriendRequest.fromJson(Map<String, dynamic> json) {
    return FocusFriendRequest(
      id: _remoteString(json, const ['id'], ''),
      userId: _remoteString(json, const ['user_id', 'userId'], ''),
      username: _remoteString(
        json,
        const ['username', 'display_name', 'displayName'],
        '同学',
      ),
      direction: _remoteString(json, const ['direction'], ''),
      status: _remoteString(json, const ['status'], 'pending'),
      online: json['online'] == true,
      createdAt: _remoteDate(json, const ['created_at', 'createdAt']),
    );
  }
}

class FocusFriendRequests {
  final List<FocusFriendRequest> incoming;
  final List<FocusFriendRequest> outgoing;

  const FocusFriendRequests({required this.incoming, required this.outgoing});

  factory FocusFriendRequests.fromJson(Map<String, dynamic> json) {
    List<FocusFriendRequest> parseList(Object? raw) {
      return (raw as List?)
              ?.whereType<Map>()
              .map(
                (item) => FocusFriendRequest.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList() ??
          const <FocusFriendRequest>[];
    }

    final incoming = parseList(json['incoming']);
    final outgoing = parseList(json['outgoing']);
    if (incoming.isNotEmpty || outgoing.isNotEmpty) {
      return FocusFriendRequests(incoming: incoming, outgoing: outgoing);
    }
    final items = parseList(json['items']);
    return FocusFriendRequests(
      incoming: items.where((item) => item.incoming).toList(),
      outgoing: items.where((item) => item.outgoing).toList(),
    );
  }
}

class FocusRoomInvite {
  final String id;
  final String code;
  final FocusRoom room;
  final DateTime? expiresAt;
  final int maxUses;
  final int usedCount;
  final DateTime? lastUsedAt;
  final bool revoked;
  final DateTime? createdAt;

  const FocusRoomInvite({
    required this.id,
    required this.code,
    required this.room,
    this.expiresAt,
    this.maxUses = 0,
    this.usedCount = 0,
    this.lastUsedAt,
    this.revoked = false,
    this.createdAt,
  });

  factory FocusRoomInvite.fromJson(Map<String, dynamic> json) {
    final rawRoom = json['room'];
    return FocusRoomInvite(
      id: _remoteString(json, const ['id'], ''),
      code: _remoteString(json, const ['code', 'invite_code', 'inviteCode'], ''),
      room: rawRoom is Map
          ? _focusRoomFromRemote(Map<String, dynamic>.from(rawRoom))
          : _focusRoomFromRemote(const <String, dynamic>{}),
      expiresAt: _remoteDate(json, const ['expires_at', 'expiresAt']),
      maxUses: _remoteInt(json, const ['max_uses', 'maxUses'], 0),
      usedCount: _remoteInt(json, const ['used_count', 'usedCount'], 0),
      lastUsedAt: _remoteDate(json, const ['last_used_at', 'lastUsedAt']),
      revoked: json['revoked'] == true || json['revoked'] == 1,
      createdAt: _remoteDate(json, const ['created_at', 'createdAt']),
    );
  }

  FocusRoomInvite copyWith({bool? revoked}) {
    return FocusRoomInvite(
      id: id,
      code: code,
      room: room,
      expiresAt: expiresAt,
      maxUses: maxUses,
      usedCount: usedCount,
      lastUsedAt: lastUsedAt,
      revoked: revoked ?? this.revoked,
      createdAt: createdAt,
    );
  }
}

class FocusRoomInviteAcceptResult {
  final String code;
  final FocusRoom room;
  final FocusRoomRemoteRanking ranking;

  const FocusRoomInviteAcceptResult({
    required this.code,
    required this.room,
    required this.ranking,
  });

  factory FocusRoomInviteAcceptResult.fromJson(Map<String, dynamic> json) {
    final rawRoom = json['room'];
    final rawRanking = json['ranking'];
    return FocusRoomInviteAcceptResult(
      code: _remoteString(json, const ['code', 'invite_code', 'inviteCode'], ''),
      room: rawRoom is Map
          ? _focusRoomFromRemote(Map<String, dynamic>.from(rawRoom))
          : _focusRoomFromRemote(const <String, dynamic>{}),
      ranking: rawRanking is Map
          ? FocusRoomRemoteRanking.fromJson(
              Map<String, dynamic>.from(rawRanking),
            )
          : const FocusRoomRemoteRanking(
              roomId: '',
              onlineCount: 0,
              updatedAt: null,
              entries: <FocusRoomRemoteEntry>[],
            ),
    );
  }
}

class FocusRoomApi {
  final ApiClient client;

  const FocusRoomApi(this.client);

  bool get canUse => client.token != null && client.token!.isNotEmpty;

  void _ensureCanUse(String message) {
    if (!canUse) throw ApiException(message);
  }

  Future<FocusRoomRemoteRanking> heartbeat({
    required String roomId,
    required String displayName,
    required int weeklySeconds,
    required int sessionCount,
    required bool active,
    DateTime? startedAt,
  }) async {
    _ensureCanUse('请先登录后再同步自习室排行');
    final response = await client
        .post('/api/focus-rooms/${Uri.encodeComponent(roomId)}/heartbeat', {
          'display_name': displayName,
          'displayName': displayName,
          'weekly_seconds': weeklySeconds,
          'weeklySeconds': weeklySeconds,
          'session_count': sessionCount,
          'sessionCount': sessionCount,
          'active': active,
          if (startedAt != null) 'started_at': startedAt.toIso8601String(),
          if (startedAt != null) 'startedAt': startedAt.toIso8601String(),
        });
    return FocusRoomRemoteRanking.fromJson(response);
  }

  Future<FocusRoomRemoteRanking> ranking(String roomId) async {
    _ensureCanUse('请先登录后再加载自习室排行');
    final response = await client.get(
      '/api/focus-rooms/${Uri.encodeComponent(roomId)}/ranking',
    );
    return FocusRoomRemoteRanking.fromJson(response);
  }

  Stream<FocusRoomRemoteRanking> rankingEvents(
    String roomId, {
    int intervalSeconds = 15,
  }) async* {
    _ensureCanUse('请先登录后再连接自习室实时事件');
    final query = Uri(
      queryParameters: {'interval_seconds': intervalSeconds.toString()},
    ).query;
    String? eventName;
    final dataLines = <String>[];
    await for (final line in client.streamLines(
      '/api/focus-rooms/${Uri.encodeComponent(roomId)}/events?$query',
    )) {
      if (line.isEmpty) {
        if ((eventName == null || eventName == 'ranking') &&
            dataLines.isNotEmpty) {
          final decoded = json.decode(dataLines.join('\n'));
          if (decoded is Map) {
            yield FocusRoomRemoteRanking.fromJson(
              Map<String, dynamic>.from(decoded),
            );
          }
        }
        eventName = null;
        dataLines.clear();
        continue;
      }
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
  }

  Stream<FocusRoomRemoteRanking> rankingWebSocketEvents(
    String roomId, {
    int intervalSeconds = 15,
  }) {
    if (client.baseUrl.isEmpty) {
      throw const ApiException('当前安装包未配置服务器地址，无法连接自习室实时事件。');
    }
    if (!canUse) {
      throw const ApiException('请先登录后再连接自习室实时事件');
    }
    final base = Uri.parse(client.baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final wsUri = base.replace(
      scheme: scheme,
      path: '/ws/focus-rooms/${Uri.encodeComponent(roomId)}/events',
      queryParameters: {
        'token': client.token!,
        'interval_seconds': intervalSeconds.toString(),
      },
    );
    final channel = WebSocketChannel.connect(wsUri);
    return channel.stream
        .map((raw) {
          final decoded = json.decode(raw.toString());
          if (decoded is! Map) return null;
          final event = decoded['event']?.toString();
          final data = decoded['data'];
          if (event != null && event != 'ranking') return null;
          if (data is! Map) return null;
          return FocusRoomRemoteRanking.fromJson(
            Map<String, dynamic>.from(data),
          );
        })
        .where((ranking) => ranking != null)
        .cast<FocusRoomRemoteRanking>();
  }

  Stream<FocusRoomRemoteRanking> realtimeRankingEvents(
    String roomId, {
    int intervalSeconds = 15,
  }) async* {
    try {
      yield* rankingWebSocketEvents(roomId, intervalSeconds: intervalSeconds);
    } catch (_) {
      yield* rankingEvents(roomId, intervalSeconds: intervalSeconds);
    }
  }

  Stream<FocusRoomRemoteRanking> globalRankingEvents({
    int intervalSeconds = 15,
  }) async* {
    _ensureCanUse('请先登录后再连接全局专注榜实时事件');
    final query = Uri(
      queryParameters: {'interval_seconds': intervalSeconds.toString()},
    ).query;
    String? eventName;
    final dataLines = <String>[];
    await for (final line in client.streamLines(
      '/api/focus-leaderboard/global/events?$query',
    )) {
      if (line.isEmpty) {
        if ((eventName == null || eventName == 'ranking') &&
            dataLines.isNotEmpty) {
          final decoded = json.decode(dataLines.join('\n'));
          if (decoded is Map) {
            yield FocusRoomRemoteRanking.fromJson(
              Map<String, dynamic>.from(decoded),
            );
          }
        }
        eventName = null;
        dataLines.clear();
        continue;
      }
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
  }

  Stream<FocusRoomRemoteRanking> globalRankingWebSocketEvents({
    int intervalSeconds = 15,
  }) {
    if (client.baseUrl.isEmpty) {
      throw const ApiException('当前安装包未配置服务器地址，无法连接全局专注榜实时事件。');
    }
    if (!canUse) {
      throw const ApiException('请先登录后再连接全局专注榜实时事件');
    }
    final base = Uri.parse(client.baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final wsUri = base.replace(
      scheme: scheme,
      path: '/ws/focus-leaderboard/global/events',
      queryParameters: {
        'token': client.token!,
        'interval_seconds': intervalSeconds.toString(),
      },
    );
    final channel = WebSocketChannel.connect(wsUri);
    return channel.stream
        .map((raw) {
          final decoded = json.decode(raw.toString());
          if (decoded is! Map) return null;
          final event = decoded['event']?.toString();
          final data = decoded['data'];
          if (event != null && event != 'ranking') return null;
          if (data is! Map) return null;
          return FocusRoomRemoteRanking.fromJson(
            Map<String, dynamic>.from(data),
          );
        })
        .where((ranking) => ranking != null)
        .cast<FocusRoomRemoteRanking>();
  }

  Stream<FocusRoomRemoteRanking> realtimeGlobalRankingEvents({
    int intervalSeconds = 15,
  }) async* {
    try {
      yield* globalRankingWebSocketEvents(intervalSeconds: intervalSeconds);
    } catch (_) {
      yield* globalRankingEvents(intervalSeconds: intervalSeconds);
    }
  }

  Future<FocusRoomRemoteRanking> leave(String roomId) async {
    _ensureCanUse('请先登录后再离开自习室');
    final response = await client.post(
      '/api/focus-rooms/${Uri.encodeComponent(roomId)}/leave',
    );
    return FocusRoomRemoteRanking.fromJson(response);
  }

  Future<List<FocusFriend>> listFriends() async {
    _ensureCanUse('请先登录后再加载专注好友');
    final response = await client.get('/api/focus-friends');
    return (response['items'] as List?)
            ?.whereType<Map>()
            .map(
              (item) => FocusFriend.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList() ??
        const <FocusFriend>[];
  }

  Future<FocusFriendRequests> listFriendRequests() async {
    _ensureCanUse('请先登录后再加载专注好友申请');
    final response = await client.get('/api/focus-friends/requests');
    return FocusFriendRequests.fromJson(response);
  }

  Future<FocusFriend> addFriend({required String username}) async {
    _ensureCanUse('请先登录后再添加专注好友');
    final response = await client.post('/api/focus-friends', {
      'username': username,
    });
    return FocusFriend.fromJson(response);
  }

  Future<void> removeFriend(String friendUserId) async {
    _ensureCanUse('请先登录后再移除专注好友');
    await client.delete(
      '/api/focus-friends/${Uri.encodeComponent(friendUserId)}',
    );
  }

  Future<FocusFriend> acceptFriendRequest(String requesterUserId) async {
    _ensureCanUse('请先登录后再处理专注好友申请');
    final response = await client.post(
      '/api/focus-friend-requests/${Uri.encodeComponent(requesterUserId)}/accept',
    );
    return FocusFriend.fromJson(response);
  }

  Future<void> rejectFriendRequest(String requesterUserId) async {
    _ensureCanUse('请先登录后再处理专注好友申请');
    await client.post(
      '/api/focus-friend-requests/${Uri.encodeComponent(requesterUserId)}/reject',
    );
  }

  Future<void> cancelFriendRequest(String friendUserId) async {
    _ensureCanUse('请先登录后再取消专注好友申请');
    await client.delete(
      '/api/focus-friend-requests/${Uri.encodeComponent(friendUserId)}',
    );
  }

  Future<FocusRoomRemoteRanking> friendRanking() async {
    _ensureCanUse('请先登录后再加载好友专注榜');
    final response = await client.get('/api/focus-leaderboard/friends');
    return FocusRoomRemoteRanking.fromJson(response);
  }

  Future<FocusRoomRemoteRanking> globalRanking() async {
    _ensureCanUse('请先登录后再加载全局专注榜');
    final response = await client.get('/api/focus-leaderboard/global');
    return FocusRoomRemoteRanking.fromJson(response);
  }

  Future<FocusRoomInvite> createInvite({
    required FocusRoom room,
    DateTime? expiresAt,
    int? maxUses,
  }) async {
    _ensureCanUse('请先登录后再创建自习室邀请码');
    final response = await client
        .post('/api/focus-rooms/${Uri.encodeComponent(room.id)}/invites', {
          'room_name': room.name,
          'roomName': room.name,
          'description': room.description,
          'weekly_target_seconds': room.weeklyTargetSeconds,
          'weeklyTargetSeconds': room.weeklyTargetSeconds,
          'accent_color': room.accentColor,
          'accentColor': room.accentColor,
          if (expiresAt != null) 'expires_at': expiresAt.toIso8601String(),
          if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
          'max_uses': ?maxUses,
          'maxUses': ?maxUses,
        });
    return FocusRoomInvite.fromJson(response);
  }

  Future<List<FocusRoomInvite>> listInvites(String roomId) async {
    _ensureCanUse('请先登录后再管理自习室邀请码');
    final response = await client.get(
      '/api/focus-rooms/${Uri.encodeComponent(roomId)}/invites',
    );
    return (response['items'] as List?)
            ?.whereType<Map>()
            .map(
              (item) =>
                  FocusRoomInvite.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList() ??
        const <FocusRoomInvite>[];
  }

  Future<void> revokeInvite(String inviteId) async {
    _ensureCanUse('请先登录后再撤销自习室邀请码');
    await client.delete(
      '/api/focus-room-invites/${Uri.encodeComponent(inviteId)}',
    );
  }

  Future<FocusRoomInviteAcceptResult> acceptInvite({
    required String code,
    required String displayName,
  }) async {
    _ensureCanUse('请先登录后再加入自习室');
    final response = await client.post(
      '/api/focus-room-invites/${Uri.encodeComponent(code)}/accept',
      {'display_name': displayName, 'displayName': displayName},
    );
    return FocusRoomInviteAcceptResult.fromJson(response);
  }
}
