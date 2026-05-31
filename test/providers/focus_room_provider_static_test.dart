import 'dart:convert';
import 'dart:io';

import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('FocusRoomProvider persists joined rooms and exposes rankings', () {
    final provider = File(
      'lib/providers/focus_room_provider.dart',
    ).readAsStringSync();

    expect(
      provider,
      contains('class FocusRoomProvider extends ChangeNotifier'),
    );
    expect(provider, contains("static const storageKey = 'duoyi_focus_rooms'"));
    expect(provider, contains("static const defaultRoomId = 'deep_work_room'"));
    expect(provider, contains('Future<void> joinRoom'));
    expect(
      provider,
      contains(
        'if (_joinedRoomIds.contains(id) && _activeRoomId == id) return;',
      ),
    );
    expect(provider, contains('Future<void> leaveRoom'));
    expect(provider, contains('Future<void> setActiveRoom'));
    expect(provider, contains('if (_activeRoomId == id) return;'));
    expect(provider, contains('Future<FocusRoom> createRoom'));
    expect(provider, contains('Future<FocusRoomInvite> createInviteForRoom'));
    expect(provider, contains('int? maxUses'));
    expect(
      provider,
      contains('Future<List<FocusRoomInvite>> loadInvitesForRoom'),
    );
    expect(provider, contains('Future<void> revokeInviteForRoom'));
    expect(provider, contains('Future<FocusRoom> acceptInviteCode'));
    expect(provider, contains('List<FocusRoomInvite> invitesForRoom'));
    expect(provider, contains('_inviteCache'));
    expect(provider, contains("throw const ApiException('请输入自习室邀请码')"));
    expect(provider, contains("throw const ApiException('请先登录后再加入自习室')"));
    expect(provider, contains("throw const ApiException('请先登录后再管理自习室邀请码')"));
    expect(provider, contains("throw const ApiException('请先登录后再撤销自习室邀请码')"));
    expect(provider, contains('FocusRoomRanking rankingFor'));
    expect(provider, contains('FocusRoomRanking effectiveRankingFor'));
    expect(provider, contains('Future<void> syncRemoteRankings'));
    expect(provider, contains('void watchRealtimeRankings'));
    expect(provider, contains('void stopRealtimeRankings'));
    expect(provider, contains('bool get realtimeRankingsActive'));
    expect(provider, contains('bool get remoteFriendRankingActive'));
    expect(provider, contains('bool get remoteGlobalRankingActive'));
    expect(provider, contains('bool get friendLoading'));
    expect(provider, contains('bool get globalLoading'));
    expect(provider, contains('List<FocusFriend> get focusFriends'));
    expect(
      provider,
      contains('List<FocusFriendRequest> get incomingFriendRequests'),
    );
    expect(
      provider,
      contains('List<FocusFriendRequest> get outgoingFriendRequests'),
    );
    expect(provider, contains('_friendRefreshInterval'));
    expect(provider, contains('_globalRefreshInterval'));
    expect(provider, contains('_remoteGlobalRanking'));
    expect(provider, contains('_globalRankingEventSubscription'));
    expect(provider, contains('_lastGlobalSyncAt'));
    expect(provider, contains('_remoteFriendRanking'));
    expect(provider, contains('Future<void> loadFocusFriendsAndRanking'));
    expect(provider, contains('Future<void> loadGlobalRanking'));
    expect(provider, contains('Future<FocusFriend> addFocusFriend'));
    expect(provider, contains('Future<FocusFriend> acceptFocusFriendRequest'));
    expect(provider, contains('Future<void> rejectFocusFriendRequest'));
    expect(provider, contains('Future<void> cancelFocusFriendRequest'));
    expect(provider, contains('Future<void> removeFocusFriend'));
    expect(provider, contains("throw const ApiException('请输入好友用户名')"));
    expect(provider, contains("throw const ApiException('请先登录后再添加专注好友')"));
    expect(provider, contains("throw const ApiException('好友申请不存在')"));
    expect(provider, contains("throw const ApiException('请先登录后再处理专注好友申请')"));
    expect(provider, contains("throw const ApiException('请先登录后再取消专注好友申请')"));
    expect(provider, contains("throw const ApiException('请先登录后再移除专注好友')"));
    expect(provider, contains('api.listFriends()'));
    expect(provider, contains('api.listFriendRequests()'));
    expect(provider, contains('api.friendRanking()'));
    expect(provider, contains('api.globalRanking()'));
    expect(provider, contains('api.addFriend(username: clean)'));
    expect(provider, contains('api.acceptFriendRequest(clean)'));
    expect(provider, contains('api.rejectFriendRequest(clean)'));
    expect(provider, contains('api.cancelFriendRequest(clean)'));
    expect(provider, contains('api.removeFriend(clean)'));
    expect(provider, contains('_socialRankingFromRemote'));
    expect(provider, contains('_refreshGlobalRanking'));
    expect(provider, contains('await _refreshGlobalRanking(api)'));
    expect(provider, contains('scope == FocusLeaderboardScope.friends'));
    expect(provider, contains('scope == FocusLeaderboardScope.global'));
    expect(provider, contains('return _remoteGlobalRanking!'));
    expect(provider, contains('entry.riskFlags.isNotEmpty'));
    expect(provider, contains('entry.riskSummary.trim().isNotEmpty'));
    expect(provider, contains('服务端已校正异常时长'));
    expect(provider, contains('_rankingEventSubscriptions'));
    expect(provider, contains('_realtimeRetryAfter'));
    expect(provider, contains('.realtimeRankingEvents'));
    expect(provider, contains('.realtimeGlobalRankingEvents'));
    expect(provider, contains('_globalRankingEventSubscription != null'));
    expect(provider, contains('_cancelRealtimeRanking'));
    expect(provider, contains('_cancelAllRealtimeRankings'));
    expect(provider, contains('_cancelAllRealtimeRankings(notify: false)'));
    expect(provider, contains('ApiClient? Function()? apiClientGetter'));
    expect(
      provider,
      contains(
        ').createInvite(room: room, expiresAt: expiresAt, maxUses: maxUses)',
      ),
    );
    expect(provider, contains('FocusRoomApi(client).listInvites(roomId)'));
    expect(provider, contains('FocusRoomApi(client).revokeInvite(inviteId)'));
    expect(
      provider,
      contains('acceptInvite(code: clean, displayName: displayName)'),
    );
    expect(provider, contains('_upsertRoom(result.room)'));
    expect(provider, contains('void _upsertRoom(FocusRoom room)'));
    expect(provider, contains('FocusRoomApi(client).leave'));
    expect(provider, contains('_remoteRankings'));
    expect(provider, contains('_remoteRefreshInterval'));
    expect(provider, contains('remote: true'));
    expect(provider, contains('onlineCount: remote.onlineCount'));
    expect(provider, contains('onLocalChanged?.call()'));
    expect(provider, contains('buildFocusRoomRanking'));
    expect(provider, contains("'joinedRoomIds'"));
    expect(provider, contains("'activeRoomId'"));
    expect(provider, contains('深度工作自习室'));
    expect(provider, contains('考试冲刺自习室'));
    expect(provider, contains('阅读自习室'));
  });

  test(
    'FocusRoomProvider surfaces server errors and falls back to local ranking',
    () async {
      final provider = FocusRoomProvider();
      final requests = <String>[];
      provider.apiClientGetter = () => ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          return http.Response(
            jsonEncode({'detail': 'focus room server unavailable'}),
            500,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final sessions = [
        PomodoroSession(
          id: 'local-session',
          startTime: DateTime(2026, 5, 25, 9),
          endTime: DateTime(2026, 5, 25, 9, 25),
          durationSeconds: 25 * 60,
          type: PomodoroType.focus,
          focusRoomId: FocusRoomProvider.defaultRoomId,
        ),
      ];

      await provider.syncRemoteRankings(
        sessions,
        displayName: '小多',
        force: true,
      );

      expect(
        requests,
        contains('POST /api/focus-rooms/deep_work_room/heartbeat'),
      );
      expect(
        provider.lastRemoteError,
        contains('focus room server unavailable'),
      );

      final ranking = provider.effectiveRankingFor(
        FocusRoomProvider.defaultRoomId,
        sessions,
        now: DateTime(2026, 5, 25, 10),
        currentUserName: '小多',
      );
      final currentUser = ranking.entries.firstWhere((e) => e.isCurrentUser);
      expect(ranking.remote, isFalse);
      expect(currentUser.name, '小多');
      expect(currentUser.weeklySeconds, 25 * 60);
    },
  );
}
