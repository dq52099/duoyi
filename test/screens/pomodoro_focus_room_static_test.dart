import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Pomodoro screen exposes self-study room picker and rankings', () {
    final screen = File('lib/screens/pomodoro_screen.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final backup = File('lib/services/backup_service.dart').readAsStringSync();
    final sync = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(screen, contains("const Tab(text: '自习室')"));
    expect(screen, contains('_FocusRoomTile'));
    expect(screen, contains('_FocusRoomTab'));
    expect(screen, contains('_FocusRoomRankingCard'));
    expect(screen, contains('_FocusSocialRankingCard'));
    expect(screen, contains('_FocusRankingEntryRow'));
    expect(screen, contains('好友与全局排行榜'));
    expect(screen, contains('FocusLeaderboardScope.friends'));
    expect(screen, contains('FocusLeaderboardScope.global'));
    expect(screen, contains('异常时长会自动封顶'));
    expect(screen, contains('选择自习室'));
    expect(screen, contains('新建自习室'));
    expect(screen, contains('完成的专注会计入所选自习室本周排行'));
    expect(screen, contains('rooms.effectiveRankingFor'));
    expect(screen, contains('syncRemoteRankings'));
    expect(screen, contains('watchRealtimeRankings'));
    expect(screen, contains('realtimeRankingsActive'));
    expect(screen, contains('loadFocusFriendsAndRanking'));
    expect(screen, contains('loadGlobalRanking'));
    expect(screen, contains('remoteFriendRankingActive'));
    expect(screen, contains('friendLoading'));
    expect(screen, contains('globalLoading'));
    expect(screen, contains('_showFocusFriendSheet'));
    expect(screen, contains('_showAddFocusFriendDialog'));
    expect(screen, contains('_addFocusFriend'));
    expect(screen, contains('_acceptFocusFriendRequest'));
    expect(screen, contains('_rejectFocusFriendRequest'));
    expect(screen, contains('_cancelFocusFriendRequest'));
    expect(screen, contains('_removeFocusFriend'));
    expect(screen, contains('_FocusFriendTile'));
    expect(screen, contains('_FocusFriendRequestTile'));
    expect(screen, contains('专注好友'));
    expect(screen, contains('服务端好友关系已用于好友专注榜'));
    expect(screen, contains('发送好友申请'));
    expect(screen, contains('收到的申请'));
    expect(screen, contains('已发出的申请'));
    expect(screen, contains('等待你处理'));
    expect(screen, contains('等待对方同意'));
    expect(screen, contains('同意好友申请'));
    expect(screen, contains('拒绝好友申请'));
    expect(screen, contains('取消好友申请'));
    expect(screen, contains('好友用户名'));
    expect(screen, contains('移除好友'));
    expect(screen, contains('服务端好友'));
    expect(screen, contains('服务端全站'));
    expect(screen, contains('刷新好友榜'));
    expect(screen, contains('刷新全局榜'));
    expect(screen, contains('实时房间'));
    expect(screen, contains('服务端排行'));
    expect(screen, contains('本地排行'));
    expect(screen, contains("label: '在线 \${ranking.onlineCount}'"));
    expect(screen, contains('服务端排行暂不可用'));
    expect(screen, contains('输入邀请码'));
    expect(screen, contains('自习室邀请码'));
    expect(screen, contains('加入自习室'));
    expect(screen, contains('邀请码管理'));
    expect(screen, contains('管理邀请码'));
    expect(screen, contains('复制邀请码'));
    expect(screen, contains('撤销邀请码'));
    expect(screen, contains('新建邀请码'));
    expect(screen, contains('有效期'));
    expect(screen, contains('使用次数'));
    expect(screen, contains('创建并复制'));
    expect(screen, contains('不过期'));
    expect(screen, contains('不限次数'));
    expect(screen, contains('1 天'));
    expect(screen, contains('7 天'));
    expect(screen, contains('30 天'));
    expect(screen, contains('_FocusRoomInviteTile'));
    expect(screen, contains('Clipboard.setData'));
    expect(screen, contains('createInviteForRoom'));
    expect(screen, contains('loadInvitesForRoom'));
    expect(screen, contains('revokeInviteForRoom'));
    expect(screen, contains('acceptInviteCode'));
    expect(screen, contains('_showFocusRoomInviteSheet'));
    expect(screen, contains('_showCreateFocusRoomInviteDialog'));
    expect(screen, contains('_createAndCopyFocusRoomInvite'));
    expect(screen, contains('_focusRoomInviteUsable'));
    expect(screen, contains('_focusRoomInviteDepleted'));
    expect(screen, contains('_showAcceptFocusRoomInviteDialog'));
    expect(screen, contains('rooms.socialRankingFor'));
    expect(screen, contains('pomodoro.setFocusRoomId'));
    expect(
      screen,
      contains('context.select<PomodoroProvider, int>'),
      reason: '自习室页只应随会话持久化修订刷新，避免秒表 tick 导致闪屏',
    );
    expect(
      screen,
      contains('provider.persistedRevision'),
      reason: '自习室排行同步 keyed by persistedRevision, not remainingSeconds',
    );
    expect(
      screen,
      isNot(contains('final pomodoro = context.watch<PomodoroProvider>()')),
    );

    expect(main, contains('FocusRoomProvider()'));
    expect(main, contains('FocusRoomProvider? _focusRoomProvider'));
    expect(
      main,
      contains('_focusRoomProvider = context.read<FocusRoomProvider>()'),
    );
    expect(main, contains('_focusRoomProvider?.stopRealtimeRankings()'));
    expect(main, contains('focusRoomProvider.loadFromStorage()'));
    expect(main, contains('focusRoomProvider.apiClientGetter'));
    expect(main, contains('focusRoomProvider.onLocalChanged = markDirty'));
    expect(
      main,
      contains('ChangeNotifierProvider.value(value: focusRoomProvider)'),
    );
    expect(backup, contains("'duoyi_focus_rooms'"));
    expect(sync, contains("'duoyi_focus_rooms': 'focus_rooms'"));
  });
}
