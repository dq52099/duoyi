import 'dart:io';

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
    expect(api, contains("json['risk_flags']"));
    expect(api, contains("json['risk_summary']"));
    expect(api, contains('class FocusFriend'));
    expect(api, contains('status: json'));
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
    expect(api, contains("'session_count': sessionCount"));
    expect(api, contains("'active': active"));
    expect(api, contains("'room_name': room.name"));
    expect(api, contains("'max_uses': ?maxUses"));
    expect(api, contains("'display_name': displayName"));

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
    expect(backend, contains('class FocusRoomInviteCreate(BaseModel)'));
    expect(backend, contains('max_uses: Optional[int] = None'));
    expect(backend, contains('class FocusRoomInviteAccept(BaseModel)'));
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
  });
}
