import 'dart:convert';
import 'dart:io';

import 'package:duoyi/models/focus_room.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/focus_room_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('focus room API uses backend heartbeat ranking and leave endpoints', () {
    final api = File('lib/services/focus_room_api.dart').readAsStringSync();
    final provider = File(
      'lib/providers/focus_room_provider.dart',
    ).readAsStringSync();
    final apiClient = File('lib/services/api_client.dart').readAsStringSync();
    final backend = File('backend/main.py').readAsStringSync();
    final backendTests = File('backend/test_workspaces.py').readAsStringSync();

    expect(api, contains('class FocusRoomApi'));
    expect(api, contains('FocusRoomRemoteRanking'));
    expect(api, contains('_focusRiskFlagsFromRemote'));
    expect(api, contains('final List<String> riskFlags'));
    expect(api, contains('final String riskSummary'));
    expect(api, contains("const ['risk_flags', 'riskFlags']"));
    expect(api, contains("const ['risk_summary', 'riskSummary']"));
    expect(api, contains('class FocusFriend'));
    expect(
      api,
      contains("status: _remoteString(json, const ['status'], 'accepted')"),
    );
    expect(api, contains('class FocusFriendRequest'));
    expect(api, contains('class FocusFriendRequests'));
    expect(api, contains('Future<List<FocusFriend>> listFriends'));
    expect(api, contains('Future<FocusFriend> addFriend'));
    expect(api, contains('Future<void> removeFriend'));
    expect(api, contains('Future<FocusFriendRequests> listFriendRequests'));
    expect(api, contains('Future<FocusFriend> acceptFriendRequest'));
    expect(api, contains('Future<void> rejectFriendRequest'));
    expect(api, contains('Future<void> cancelFriendRequest'));
    expect(api, contains('Future<FocusRoomRemoteRanking> friendRanking'));
    expect(api, contains('Future<FocusRoomRemoteRanking> globalRanking'));
    expect(api, contains('/api/focus-friends'));
    expect(api, contains('/api/focus-friends/requests'));
    expect(
      api,
      contains('/api/focus-friends/\${Uri.encodeComponent(friendUserId)}'),
    );
    expect(
      api,
      contains(
        '/api/focus-friend-requests/\${Uri.encodeComponent(requesterUserId)}/accept',
      ),
    );
    expect(
      api,
      contains(
        '/api/focus-friend-requests/\${Uri.encodeComponent(requesterUserId)}/reject',
      ),
    );
    expect(
      api,
      contains(
        '/api/focus-friend-requests/\${Uri.encodeComponent(friendUserId)}',
      ),
    );
    expect(api, contains('/api/focus-leaderboard/friends'));
    expect(api, contains('/api/focus-leaderboard/global'));
    expect(
      api,
      contains('/api/focus-rooms/\${Uri.encodeComponent(roomId)}/heartbeat'),
    );
    expect(
      api,
      contains('/api/focus-rooms/\${Uri.encodeComponent(roomId)}/ranking'),
    );
    expect(api, contains('Stream<FocusRoomRemoteRanking> rankingEvents'));
    expect(
      api,
      contains('Stream<FocusRoomRemoteRanking> rankingWebSocketEvents'),
    );
    expect(
      api,
      contains('Stream<FocusRoomRemoteRanking> realtimeRankingEvents'),
    );
    expect(api, contains('Stream<FocusRoomRemoteRanking> globalRankingEvents'));
    expect(
      api,
      contains('Stream<FocusRoomRemoteRanking> globalRankingWebSocketEvents'),
    );
    expect(
      api,
      contains('Stream<FocusRoomRemoteRanking> realtimeGlobalRankingEvents'),
    );
    expect(
      api,
      contains("import 'package:web_socket_channel/web_socket_channel.dart';"),
    );
    expect(api, contains('WebSocketChannel.connect'));
    expect(api, contains("base.scheme == 'https' ? 'wss' : 'ws'"));
    expect(
      api,
      contains('/ws/focus-rooms/\${Uri.encodeComponent(roomId)}/events'),
    );
    expect(api, contains('/ws/focus-leaderboard/global/events'));
    expect(api, contains("'token': client.token!"));
    expect(api, contains("yield* rankingWebSocketEvents"));
    expect(api, contains("yield* rankingEvents"));
    expect(
      api,
      contains('/api/focus-rooms/\${Uri.encodeComponent(roomId)}/events?'),
    );
    expect(api, contains('/api/focus-leaderboard/global/events?'));
    expect(api, contains("eventName == 'ranking'"));
    expect(api, contains("line.startsWith('data:')"));
    expect(api, contains('FocusRoomRemoteRanking.fromJson'));
    expect(
      api,
      contains('/api/focus-rooms/\${Uri.encodeComponent(roomId)}/leave'),
    );
    expect(api, contains('class FocusRoomInvite'));
    expect(api, contains('class FocusRoomInviteAcceptResult'));
    expect(api, contains('revoked'));
    expect(api, contains('createdAt'));
    expect(api, contains('maxUses'));
    expect(api, contains('usedCount'));
    expect(api, contains('lastUsedAt'));
    expect(api, contains('Future<FocusRoomInvite> createInvite'));
    expect(api, contains('Future<List<FocusRoomInvite>> listInvites'));
    expect(api, contains('Future<void> revokeInvite'));
    expect(api, contains('Future<FocusRoomInviteAcceptResult> acceptInvite'));
    expect(api, contains('Object? _remoteValue('));
    expect(
      api,
      contains("const ['weekly_target_seconds', 'weeklyTargetSeconds']"),
    );
    expect(api, contains("const ['room_id', 'roomId']"));
    expect(
      api,
      contains('/api/focus-rooms/\${Uri.encodeComponent(room.id)}/invites'),
    );
    expect(
      api,
      contains('/api/focus-rooms/\${Uri.encodeComponent(roomId)}/invites'),
    );
    expect(
      api,
      contains('/api/focus-room-invites/\${Uri.encodeComponent(inviteId)}'),
    );
    expect(
      api,
      contains('/api/focus-room-invites/\${Uri.encodeComponent(code)}/accept'),
    );
    expect(api, contains("'weekly_seconds': weeklySeconds"));
    expect(api, contains("'weeklySeconds': weeklySeconds"));
    expect(api, contains("'session_count': sessionCount"));
    expect(api, contains("'sessionCount': sessionCount"));
    expect(api, contains("'active': active"));
    expect(api, contains("'room_name': room.name"));
    expect(api, contains("'roomName': room.name"));
    expect(api, contains("'max_uses': ?maxUses"));
    expect(api, contains("'maxUses': ?maxUses"));
    expect(api, contains("'display_name': displayName"));
    expect(api, contains("'displayName': displayName"));

    expect(apiClient, contains('Stream<String> streamLines'));
    expect(apiClient, contains("'Accept'] = 'text/event-stream'"));
    expect(apiClient, contains("'Cache-Control'] = 'no-cache'"));
    expect(apiClient, contains("'Authorization'] = 'Bearer \$token'"));
    expect(apiClient, contains('LineSplitter'));

    expect(provider, contains('FocusRoomApi(client)'));
    expect(provider, contains('api.heartbeat'));
    expect(provider, contains('watchRealtimeRankings'));
    expect(provider, contains('realtimeRankingsActive'));
    expect(provider, contains('_rankingEventSubscriptions'));
    expect(provider, contains('_realtimeRetryAfter'));
    expect(provider, contains('.realtimeRankingEvents'));
    expect(provider, contains('FocusRoomApi(client).leave'));
    expect(provider, contains('createInviteForRoom'));
    expect(provider, contains('loadInvitesForRoom'));
    expect(provider, contains('revokeInviteForRoom'));
    expect(provider, contains('_inviteCache'));
    expect(provider, contains('acceptInviteCode'));
    expect(provider, contains('loadFocusFriendsAndRanking'));
    expect(provider, contains('Future<FocusFriend> addFocusFriend'));
    expect(
      provider,
      contains('List<FocusFriendRequest> get incomingFriendRequests'),
    );
    expect(
      provider,
      contains('List<FocusFriendRequest> get outgoingFriendRequests'),
    );
    expect(provider, contains('Future<FocusFriend> acceptFocusFriendRequest'));
    expect(provider, contains('Future<void> rejectFocusFriendRequest'));
    expect(provider, contains('Future<void> cancelFocusFriendRequest'));
    expect(provider, contains('Future<void> removeFocusFriend'));
    expect(provider, contains('FocusRoomApi(client).leave'));
    expect(provider, contains('api.listFriends()'));
    expect(provider, contains('api.listFriendRequests()'));
    expect(provider, contains('api.friendRanking()'));
    expect(provider, contains('api.globalRanking()'));
    expect(provider, contains('api.addFriend(username: clean)'));
    expect(provider, contains('api.acceptFriendRequest(clean)'));
    expect(provider, contains('api.rejectFriendRequest(clean)'));
    expect(provider, contains('api.cancelFriendRequest(clean)'));
    expect(provider, contains('api.removeFriend(clean)'));
    expect(provider, contains('_remoteFriendRanking'));
    expect(provider, contains('_remoteGlobalRanking'));
    expect(provider, contains('_socialRankingFromRemote'));
    expect(provider, contains('FocusRoomRemoteRanking remote'));
    expect(provider, contains('entry.riskFlags.isNotEmpty'));
    expect(provider, contains('entry.riskSummary.trim().isNotEmpty'));
    expect(provider, contains('服务端已校正异常时长'));

    expect(backend, contains('CREATE TABLE IF NOT EXISTS focus_room_presence'));
    expect(backend, contains('CREATE TABLE IF NOT EXISTS focus_room_invites'));
    expect(backend, contains('CREATE TABLE IF NOT EXISTS focus_friends'));
    expect(
      backend,
      contains('CREATE TABLE IF NOT EXISTS focus_friend_request_log'),
    );
    expect(backend, contains('FOCUS_FRIEND_REQUEST_LIMIT_PER_DAY'));
    expect(backend, contains('class FocusFriendCreate(BaseModel)'));
    expect(backend, contains('@app.get("/api/focus-friends")'));
    expect(backend, contains('@app.get("/api/focus-friends/requests")'));
    expect(backend, contains('@app.post("/api/focus-friends")'));
    expect(
      backend,
      contains(
        '@app.post("/api/focus-friend-requests/{requester_user_id}/accept")',
      ),
    );
    expect(
      backend,
      contains(
        '@app.post("/api/focus-friend-requests/{requester_user_id}/reject")',
      ),
    );
    expect(
      backend,
      contains('@app.delete("/api/focus-friend-requests/{friend_user_id}")'),
    );
    expect(
      backend,
      contains('@app.delete("/api/focus-friends/{friend_user_id}")'),
    );
    expect(backend, contains('@app.get("/api/focus-leaderboard/friends")'));
    expect(backend, contains('@app.get("/api/focus-leaderboard/global")'));
    expect(
      backend,
      contains('@app.get("/api/focus-leaderboard/global/events")'),
    );
    expect(
      backend,
      contains('@app.websocket("/ws/focus-leaderboard/global/events")'),
    );
    expect(backend, contains('async def focus_global_leaderboard_events'));
    expect(backend, contains('async def focus_global_leaderboard_events_ws'));
    expect(backend, contains('def _focus_friend_ranking'));
    expect(backend, contains('INSERT INTO focus_friends'));
    expect(backend, contains('INSERT INTO focus_friend_request_log'));
    expect(backend, contains('DELETE FROM focus_friends'));
    expect(backend, contains("status='pending'"));
    expect(backend, contains("status='accepted'"));
    expect(backend, contains('Focus friend request limit reached'));
    expect(backend, contains("scope\": \"friends\""));
    expect(backend, contains('max_uses INTEGER DEFAULT 0'));
    expect(backend, contains('used_count INTEGER DEFAULT 0'));
    expect(backend, contains('last_used_at TEXT'));
    expect(backend, contains('FOCUS_ROOM_ONLINE_SECONDS'));
    expect(backend, contains('FOCUS_ROOM_HEARTBEAT_THROTTLE_SECONDS'));
    expect(backend, contains('FOCUS_ROOM_MAX_SESSION_COUNT_JUMP'));
    expect(
      backend,
      contains('@app.post("/api/focus-rooms/{room_id}/heartbeat")'),
    );
    expect(backend, contains('@app.get("/api/focus-rooms/{room_id}/ranking")'));
    expect(backend, contains('@app.get("/api/focus-rooms/{room_id}/events")'));
    expect(
      backend,
      contains('@app.websocket("/ws/focus-rooms/{room_id}/events")'),
    );
    expect(backend, contains('async def focus_room_events_ws'));
    expect(backend, contains('websocket.query_params.get("token")'));
    expect(backend, contains('_verify_token_value(token)'));
    expect(
      backend,
      contains(
        'await websocket.send_json({"event": "ranking", "data": payload})',
      ),
    );
    expect(backend, contains('websocket.receive_json()'));
    expect(backend, contains('event in ("ping", "ranking")'));
    expect(backend, contains('StreamingResponse'));
    expect(backend, contains('media_type="text/event-stream"'));
    expect(backend, contains('event: ranking'));
    expect(backend, contains('interval_seconds: int = Query(15, ge=2, le=60)'));
    expect(backend, contains('@app.post("/api/focus-rooms/{room_id}/leave")'));
    expect(
      backend,
      contains('@app.post("/api/focus-rooms/{room_id}/invites")'),
    );
    expect(backend, contains('@app.get("/api/focus-rooms/{room_id}/invites")'));
    expect(
      backend,
      contains('@app.delete("/api/focus-room-invites/{invite_id}")'),
    );
    expect(backend, contains('created_by=?'));
    expect(backend, contains('UPDATE focus_room_invites SET revoked=1'));
    expect(
      backend,
      contains('@app.post("/api/focus-room-invites/{code}/accept")'),
    );
    expect(
      backend,
      contains('class FocusRoomInviteCreate(_FocusRoomAliasModel)'),
    );
    expect(backend, contains('class _FocusRoomAliasModel(BaseModel)'));
    expect(backend, contains('AliasChoices("display_name", "displayName")'));
    expect(
      backend,
      contains('@app.post("/api/focus-rooms/{room_id:path}/heartbeat"'),
    );
    expect(backend, contains('max_uses: Optional[int] = Field'));
    expect(
      backend,
      contains('class FocusRoomInviteAccept(_FocusRoomAliasModel)'),
    );
    expect(backend, contains('Focus room invite usage limit reached'));
    expect(backend, contains('used_count=used_count+1'));
    expect(backend, contains('last_used_at=?'));
    expect(backend, contains('first_join'));
    expect(backend, contains('FOCUS_ROOM_MAX_WEEKLY_SECONDS'));
    expect(backend, contains('raw_weekly_seconds'));
    expect(backend, contains('risk_flags TEXT DEFAULT'));
    expect(backend, contains('risk_summary TEXT DEFAULT'));
    expect(backend, contains('heartbeat_throttled'));
    expect(backend, contains('session_count_jump_capped'));
    expect(backend, contains('"risk_flags": risk_flags'));
    expect(
      backend,
      contains('"risk_summary": _focus_risk_summary(risk_flags)'),
    );
    expect(backend, contains('online_count'));

    expect(
      backendTests,
      contains('test_focus_room_heartbeat_marks_user_online_and_ranks_members'),
    );
    expect(
      backendTests,
      contains('test_focus_room_ranking_caps_suspicious_weekly_seconds'),
    );
    expect(
      backendTests,
      contains('test_focus_room_heartbeat_flags_repeated_and_jumpy_sessions'),
    );
    expect(
      backendTests,
      contains('test_focus_room_leave_and_stale_heartbeat_clear_online_status'),
    );
    expect(
      backendTests,
      contains('test_focus_room_events_streams_ranking_sse'),
    );
    expect(
      backendTests,
      contains('test_focus_room_events_websocket_streams_and_responds_to_ping'),
    );
    expect(
      backendTests,
      contains('test_focus_global_leaderboard_events_streams_ranking_sse'),
    );
    expect(
      backendTests,
      contains(
        'test_focus_global_leaderboard_events_websocket_streams_and_responds_to_ping',
      ),
    );
    expect(backendTests, contains('websocket_connect'));
    expect(
      backendTests,
      contains('test_focus_friends_list_and_ranking_use_server_relationships'),
    );
    expect(
      backendTests,
      contains('test_focus_friend_request_reject_cancel_and_limit'),
    );
    expect(
      backendTests,
      contains('test_focus_room_invite_accept_returns_room_and_marks_presence'),
    );
    expect(
      backendTests,
      contains('test_focus_room_invite_rejects_expired_code'),
    );
    expect(
      backendTests,
      contains('test_focus_room_invite_list_and_revoke_are_owner_scoped'),
    );
    expect(
      backendTests,
      contains('test_focus_room_invite_usage_limit_counts_first_join_only'),
    );
    expect(
      backendTests,
      contains(
        'test_focus_room_http_accepts_encoded_room_ids_and_payload_aliases',
      ),
    );
    expect(
      backendTests,
      contains('test_focus_room_events_websocket_accepts_authorization_header'),
    );
  });

  test(
    'FocusRoomApi calls create join heartbeat leave and ranking paths',
    () async {
      final calls = <String>[];
      final bodies = <String, Map<String, dynamic>>{};
      final api = FocusRoomApi(
        ApiClient(
          baseUrl: 'https://duoyi.test/api',
          token: 'token-1',
          httpClient: MockClient((request) async {
            final path = request.url.toString().replaceFirst(
              'https://duoyi.test',
              '',
            );
            final key = '${request.method} $path';
            calls.add(key);
            expect(request.headers['Authorization'], 'Bearer token-1');
            if (request.body.isNotEmpty) {
              bodies[key] = Map<String, dynamic>.from(jsonDecode(request.body));
            }
            return http.Response(
              jsonEncode(_focusRoomApiResponseFor(key)),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      final room = FocusRoom(
        id: 'deep/work room',
        name: '深房',
        description: 'path check',
        weeklyTargetSeconds: 3600,
        accentColor: 0xFF3949AB,
        members: const <FocusRoomMemberSeed>[],
        createdAt: DateTime(2026, 5, 31),
      );
      final expiresAt = DateTime(2026, 6, 7, 8);
      final startedAt = DateTime(2026, 5, 31, 9, 30);

      await api.createInvite(room: room, expiresAt: expiresAt, maxUses: 3);
      await api.acceptInvite(code: 'CODE 123', displayName: '小多');
      await api.heartbeat(
        roomId: room.id,
        displayName: '小多',
        weeklySeconds: 1500,
        sessionCount: 1,
        active: true,
        startedAt: startedAt,
      );
      await api.ranking(room.id);
      await api.leave(room.id);
      await api.friendRanking();
      await api.globalRanking();

      expect(calls, [
        'POST /api/focus-rooms/deep%2Fwork%20room/invites',
        'POST /api/focus-room-invites/CODE%20123/accept',
        'POST /api/focus-rooms/deep%2Fwork%20room/heartbeat',
        'GET /api/focus-rooms/deep%2Fwork%20room/ranking',
        'POST /api/focus-rooms/deep%2Fwork%20room/leave',
        'GET /api/focus-leaderboard/friends',
        'GET /api/focus-leaderboard/global',
      ]);

      expect(
        bodies['POST /api/focus-rooms/deep%2Fwork%20room/invites'],
        containsPair('room_name', '深房'),
      );
      expect(
        bodies['POST /api/focus-rooms/deep%2Fwork%20room/invites'],
        containsPair('roomName', '深房'),
      );
      expect(
        bodies['POST /api/focus-rooms/deep%2Fwork%20room/invites'],
        containsPair('max_uses', 3),
      );
      expect(
        bodies['POST /api/focus-rooms/deep%2Fwork%20room/invites'],
        containsPair('maxUses', 3),
      );
      expect(
        bodies['POST /api/focus-room-invites/CODE%20123/accept'],
        containsPair('display_name', '小多'),
      );
      expect(
        bodies['POST /api/focus-room-invites/CODE%20123/accept'],
        containsPair('displayName', '小多'),
      );
      expect(
        bodies['POST /api/focus-rooms/deep%2Fwork%20room/heartbeat'],
        containsPair('weekly_seconds', 1500),
      );
      expect(
        bodies['POST /api/focus-rooms/deep%2Fwork%20room/heartbeat'],
        containsPair('weeklySeconds', 1500),
      );
      expect(
        bodies['POST /api/focus-rooms/deep%2Fwork%20room/heartbeat'],
        containsPair('started_at', startedAt.toIso8601String()),
      );
      expect(
        bodies['POST /api/focus-rooms/deep%2Fwork%20room/heartbeat'],
        containsPair('startedAt', startedAt.toIso8601String()),
      );
    },
  );

  test('focus room realtime SSE and WebSocket contracts stay aligned', () {
    final api = File('lib/services/focus_room_api.dart').readAsStringSync();
    final provider = File(
      'lib/providers/focus_room_provider.dart',
    ).readAsStringSync();
    final backend = File('backend/main.py').readAsStringSync();
    final deploy = File('DEPLOY.md').readAsStringSync();

    expect(api, contains("line.startsWith('event:')"));
    expect(api, contains("line.startsWith('data:')"));
    expect(api, contains("eventName == null || eventName == 'ranking'"));
    expect(
      api,
      contains("if (event != null && event != 'ranking') return null;"),
    );
    expect(api, contains("if (data is! Map) return null;"));
    expect(api, contains("'interval_seconds': intervalSeconds.toString()"));
    expect(api, contains("'token': client.token!"));
    expect(api, contains("base.scheme == 'https' ? 'wss' : 'ws'"));
    expect(api, contains("yield* rankingWebSocketEvents"));
    expect(api, contains("yield* rankingEvents"));
    expect(api, contains("yield* globalRankingWebSocketEvents"));
    expect(api, contains("yield* globalRankingEvents"));

    expect(provider, contains('.realtimeRankingEvents'));
    expect(provider, contains('.realtimeGlobalRankingEvents'));
    expect(provider, contains('_lastRemoteError = null;'));
    expect(provider, contains('_lastRemoteSyncAt = DateTime.now();'));
    expect(provider, contains('_lastGlobalSyncAt = DateTime.now();'));
    expect(provider, contains('_realtimeRetryAfter = DateTime.now().add'));
    expect(provider, contains('const Duration(seconds: 30)'));
    expect(provider, contains('_queueRealtimeNotify();'));

    expect(backend, contains('@app.get("/api/focus-rooms/{room_id}/events")'));
    expect(
      backend,
      contains('@app.websocket("/ws/focus-rooms/{room_id}/events")'),
    );
    expect(backend, contains('"WS /ws/focus-rooms/{room_id}/events"'));
    expect(
      backend,
      contains('@app.get("/api/focus-leaderboard/global/events")'),
    );
    expect(
      backend,
      contains('@app.websocket("/ws/focus-leaderboard/global/events")'),
    );
    expect(backend, contains('"WS /ws/focus-leaderboard/global/events"'));
    expect(backend, contains('"event: ranking\\n"'));
    expect(
      backend,
      contains('f"data: {json.dumps(payload, ensure_ascii=False)}\\n\\n"'),
    );
    expect(
      backend,
      contains(
        'await websocket.send_json({"event": "ranking", "data": payload})',
      ),
    );
    expect(backend, contains('event in ("ping", "ranking")'));
    expect(deploy, contains('location /ws/'));
    expect(deploy, contains(r'proxy_set_header Upgrade $http_upgrade;'));
    expect(deploy, contains('proxy_set_header Connection "upgrade";'));
  });

  test('focus room remote DTOs tolerate compatible JSON shapes', () {
    final ranking = FocusRoomRemoteRanking.fromJson({
      'room_id': 'room-a',
      'online_count': 2.0,
      'updated_at': '2026-05-31T08:00:00Z',
      'entries': [
        {
          'user_id': 'u1',
          'display_name': '小多',
          'weekly_seconds': 1200.2,
          'raw_weekly_seconds': 1800,
          'session_count': 2,
          'online': true,
          'active': false,
          'is_current_user': true,
          'rank': 1,
          'last_seen_at': '2026-05-31T08:01:00Z',
          'risk_flags': '["heartbeat_throttled","session_count_jump_capped"]',
          'risk_summary': '服务端校正',
        },
        {
          'user_id': 'u2',
          'display_name': '同学',
          'risk_flags': 'daily_cap|future_session',
        },
      ],
    });

    expect(ranking.roomId, 'room-a');
    expect(ranking.onlineCount, 2);
    expect(ranking.entries.first.riskFlags, [
      'heartbeat_throttled',
      'session_count_jump_capped',
    ]);
    expect(ranking.entries.first.riskSummary, '服务端校正');
    expect(ranking.entries.last.riskFlags, ['daily_cap', 'future_session']);
    expect(ranking.entries.last.active, isTrue);

    final invite = FocusRoomInvite.fromJson({
      'id': 'invite-1',
      'code': 'CODE',
      'room': {
        'id': 'room-a',
        'name': '远程自习室',
        'description': 'remote',
        'weeklyTargetSeconds': 2400,
        'accentColor': 0xFF00897B,
      },
      'expires_at': '2026-06-07T08:00:00Z',
      'max_uses': 5.0,
      'used_count': 1.0,
      'last_used_at': '2026-06-01T08:00:00Z',
      'revoked': 1,
      'created_at': '2026-05-31T08:00:00Z',
    });
    expect(invite.room.id, 'room-a');
    expect(invite.room.weeklyTargetSeconds, 2400);
    expect(invite.maxUses, 5);
    expect(invite.usedCount, 1);
    expect(invite.revoked, isTrue);

    final acceptResult = FocusRoomInviteAcceptResult.fromJson({'code': 'CODE'});
    expect(acceptResult.code, 'CODE');
    expect(acceptResult.room.id, isEmpty);
    expect(acceptResult.ranking.entries, isEmpty);

    final requests = FocusFriendRequests.fromJson({
      'items': [
        {'id': 'in-1', 'direction': 'incoming'},
        {'id': 'out-1', 'direction': 'outgoing'},
      ],
    });
    expect(requests.incoming.single.id, 'in-1');
    expect(requests.outgoing.single.id, 'out-1');

    final camelRanking = FocusRoomRemoteRanking.fromJson({
      'roomId': 'room-camel',
      'onlineCount': 1,
      'updatedAt': '2026-05-31T08:00:00Z',
      'items': [
        {
          'userId': 'u-camel',
          'displayName': '驼峰同学',
          'weeklySeconds': 900,
          'rawWeeklySeconds': 1200,
          'sessionCount': 1,
          'isCurrentUser': true,
          'lastSeenAt': '2026-05-31T08:01:00Z',
          'riskFlags': ['weekly_seconds_capped'],
          'riskSummary': '兼容驼峰字段',
        },
      ],
    });
    expect(camelRanking.roomId, 'room-camel');
    expect(camelRanking.onlineCount, 1);
    expect(camelRanking.entries.single.userId, 'u-camel');
    expect(camelRanking.entries.single.displayName, '驼峰同学');
    expect(camelRanking.entries.single.weeklySeconds, 900);
    expect(camelRanking.entries.single.isCurrentUser, isTrue);
    expect(camelRanking.entries.single.riskFlags, ['weekly_seconds_capped']);
  });
}

Map<String, dynamic> _focusRoomApiResponseFor(String key) {
  switch (key) {
    case 'POST /api/focus-rooms/deep%2Fwork%20room/invites':
      return {
        'id': 'invite-1',
        'code': 'CODE 123',
        'room': _remoteRoomJson(),
        'expires_at': '2026-06-07T08:00:00.000',
        'max_uses': 3,
        'used_count': 0,
        'revoked': false,
        'created_at': '2026-05-31T08:00:00.000',
      };
    case 'POST /api/focus-room-invites/CODE%20123/accept':
      return {
        'code': 'CODE 123',
        'room': _remoteRoomJson(),
        'ranking': _remoteRankingJson(),
      };
    case 'POST /api/focus-rooms/deep%2Fwork%20room/heartbeat':
    case 'GET /api/focus-rooms/deep%2Fwork%20room/ranking':
    case 'POST /api/focus-rooms/deep%2Fwork%20room/leave':
    case 'GET /api/focus-leaderboard/friends':
    case 'GET /api/focus-leaderboard/global':
      return _remoteRankingJson();
  }
  return {'detail': 'unexpected $key'};
}

Map<String, dynamic> _remoteRoomJson() => {
  'id': 'deep/work room',
  'name': '深房',
  'description': 'path check',
  'weekly_target_seconds': 3600,
  'accent_color': 0xFF3949AB,
};

Map<String, dynamic> _remoteRankingJson() => {
  'room_id': 'deep/work room',
  'online_count': 1,
  'updated_at': '2026-05-31T08:00:00.000',
  'entries': [
    {
      'user_id': 'u1',
      'display_name': '小多',
      'weekly_seconds': 1500,
      'raw_weekly_seconds': 1500,
      'session_count': 1,
      'online': true,
      'active': true,
      'is_current_user': true,
      'rank': 1,
      'risk_flags': [],
      'risk_summary': '',
    },
  ],
};
