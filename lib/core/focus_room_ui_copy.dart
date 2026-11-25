import 'i18n_date_format.dart';
import 'i18n.dart';
import '../models/focus_room.dart';
import '../models/pomodoro.dart';

/// App-owned bilingual UI copy for Focus and Focus Room features.
class FocusRoomUiCopy {
  FocusRoomUiCopy._();

  static bool isEn([AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.en;

  // ---------------------------------------------------------------------------
  // Strict Focus (严格专注)
  // ---------------------------------------------------------------------------
  static String strictFocusTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Strict Focus' : '严格专注';

  static String strictFocusSubtitle([AppLocale? locale]) => isEn(locale)
      ? 'Pausing, skipping, resetting, leaving the app, or opening distracting apps will be recorded.'
      : '暂停、跳过、重置、离开应用或打开分心 App 会留下中断记录';

  static String strictFocusConfirmTitle(
    FocusPenaltyReason reason, [
    AppLocale? locale,
  ]) => isEn(locale)
      ? '${reason.labelFor(AppLocale.en)}?'
      : '${reason.labelFor(AppLocale.zh)}？';

  static String strictFocusConfirmContent([AppLocale? locale]) => isEn(locale)
      ? 'Strict focus mode is active. This action will be recorded as a focus interruption and shown in today’s statistics and study room review.'
      : '严格专注已开启。本次操作会记入专注惩罚记录，今日统计和自习室复盘都会显示这次中断。';

  static String keepFocusing([AppLocale? locale]) =>
      isEn(locale) ? 'Keep focusing' : '继续专注';

  static String confirmRecord([AppLocale? locale]) =>
      isEn(locale) ? 'Confirm and record' : '确认记录';

  static String strictFocusTileSubtitle(
    bool enabled,
    int count, [
    AppLocale? locale,
  ]) {
    if (!enabled) return isEn(locale) ? 'Tap to enable' : '手动开启';
    if (count > 0) {
      return isEn(locale) ? '$count interruptions today' : '今日 $count 次中断';
    }
    return isEn(locale) ? 'Interruptions recorded' : '中断会记入 ledger';
  }

  static String enableStrictFocus([AppLocale? locale]) =>
      isEn(locale) ? 'Enable strict focus' : '开启严格专注';

  static String todayPenaltiesCount(int count, [AppLocale? locale]) =>
      isEn(locale) ? '$count interruptions recorded today' : '今日已记录 $count 次中断';

  static String monitorDistractingApps([AppLocale? locale]) =>
      isEn(locale) ? 'Monitor distracting apps' : '监控分心应用';

  static String distractionStatusSubtitle({
    required bool accessibilityGranted,
    required bool accessGranted,
    AppLocale? locale,
  }) {
    if (accessibilityGranted) {
      return isEn(locale) ? 'Accessibility blocking granted' : '辅助功能拦截已授权';
    }
    if (accessGranted) {
      return isEn(locale)
          ? 'Usage access granted; accessibility not granted'
          : '已授权使用情况访问，辅助功能未授权';
    }
    return isEn(locale)
        ? 'Requires Android usage access and accessibility permissions'
        : '需要 Android 使用情况访问和辅助功能权限';
  }

  static String distractingPackageLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Distracting app packages' : '分心应用包名';

  static String usageAccessButton([AppLocale? locale]) =>
      isEn(locale) ? 'Usage access' : '使用情况权限';

  static String accessibilityServiceButton([AppLocale? locale]) =>
      isEn(locale) ? 'Accessibility service' : '辅助功能拦截';

  static String strictFocusExplanation([AppLocale? locale]) => isEn(locale)
      ? 'With accessibility enabled, distracting apps opened during strict focus will be pulled back to Duoyi. Without accessibility, usage access still logs distraction penalties.'
      : '开启辅助功能后，严格专注运行时会把打开的分心 App 拉回多仪；未授权辅助功能时仍会用使用情况访问记录分心 App 惩罚。';

  static String recentPenaltiesHeader([AppLocale? locale]) =>
      isEn(locale) ? 'Recent penalties' : '最近惩罚';

  static String noPenaltiesRecorded([AppLocale? locale]) =>
      isEn(locale) ? 'No records' : '暂无记录';

  static String penaltiesCountSubtitle(int count, [AppLocale? locale]) =>
      isEn(locale) ? '$count records' : '$count 条';

  static String emptyPenaltiesHint([AppLocale? locale]) => isEn(locale)
      ? 'Complete sessions without interruptions to keep this empty.'
      : '保持完整专注后这里会继续为空。';

  static String minutesSuffix(int minutes, [AppLocale? locale]) =>
      isEn(locale) ? '$minutes min' : '$minutes 分钟';

  static String defaultDuration(int minutes, [AppLocale? locale]) =>
      isEn(locale) ? 'Default · $minutes min' : '默认 · $minutes 分钟';

  static String durationSaveFailed([AppLocale? locale]) =>
      isEn(locale) ? 'Could not save the duration. Try again.' : '时长未保存，请重试';

  // ---------------------------------------------------------------------------
  // Focus Rooms (自习室)
  // ---------------------------------------------------------------------------
  static String roomTab([AppLocale? locale]) =>
      isEn(locale) ? 'Study Rooms' : '自习室';

  static String studyRoomTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Study Room' : '专注自习室';

  static String studyRoomLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Study room' : '自习室';

  static String selfDisplayNameFallback([AppLocale? locale]) =>
      isEn(locale) ? 'Me' : '我';

  static String noRoomJoined([AppLocale? locale]) =>
      isEn(locale) ? 'No study room joined' : '未加入自习室';

  static String activeRoomTileSubtitle(bool hasRoom, [AppLocale? locale]) =>
      hasRoom
      ? (isEn(locale)
            ? 'Credited to leaderboard upon completion'
            : '本轮完成后计入排行榜')
      : (isEn(locale) ? 'Choose a focus group for this session' : '选择本轮专注小组');

  static String selectRoomTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Select Study Room' : '选择自习室';

  static String selectRoomSubtitle([AppLocale? locale]) => isEn(locale)
      ? 'Completed sessions are credited to the selected room’s weekly ranking'
      : '完成的专注会计入所选自习室本周排行';

  static String newRoomButton([AppLocale? locale]) =>
      isEn(locale) ? 'New' : '新建';

  static String doNotJoinThisRound([AppLocale? locale]) =>
      isEn(locale) ? 'Do not join this round' : '本轮不加入';

  static String createRoomTitle([AppLocale? locale]) =>
      isEn(locale) ? 'New Study Room' : '新建自习室';

  static String nameLabel([AppLocale? locale]) => isEn(locale) ? 'Name' : '名称';

  static String descriptionLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Description' : '说明';

  static String weeklyGoalMinutesLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Weekly goal (minutes)' : '每周目标（分钟）';

  static String cancel([AppLocale? locale]) => isEn(locale) ? 'Cancel' : '取消';

  static String done([AppLocale? locale]) => isEn(locale) ? 'Done' : '完成';

  static String save([AppLocale? locale]) => isEn(locale) ? 'Save' : '保存';

  static String create([AppLocale? locale]) => isEn(locale) ? 'Create' : '创建';

  static String ok([AppLocale? locale]) => isEn(locale) ? 'OK' : '确定';

  static String joinedSectionSubtitle(
    String? activeRoomName, [
    AppLocale? locale,
  ]) => activeRoomName == null
      ? (isEn(locale)
            ? 'Select a room to credit this focus session to its weekly leaderboard'
            : '选择一个房间后，本轮专注会计入本周排行榜')
      : (isEn(locale)
            ? 'Currently credited to: $activeRoomName'
            : '当前本轮计入：$activeRoomName');

  static String enterInviteCodeAction([AppLocale? locale]) =>
      isEn(locale) ? 'Enter invite code' : '输入邀请码';

  static String liveRoomBadge([AppLocale? locale]) =>
      isEn(locale) ? 'Live room' : '实时房间';

  static String noJoinedRoomsYet([AppLocale? locale]) =>
      isEn(locale) ? 'No study rooms joined yet' : '还没有加入自习室';

  static String userProgressMinutes(
    int currentMinutes,
    int targetMinutes, [
    AppLocale? locale,
  ]) => isEn(locale)
      ? '$currentMinutes / $targetMinutes min'
      : '$currentMinutes / $targetMinutes 分钟';

  static String rankingBadge(bool remote, [AppLocale? locale]) => remote
      ? (isEn(locale) ? 'Server ranking' : '服务端排行')
      : (isEn(locale) ? 'Local ranking' : '本地排行');

  static String onlineBadge(int count, [AppLocale? locale]) =>
      isEn(locale) ? 'Online $count' : '在线 $count';

  static String adjustedEntriesCount(int count, [AppLocale? locale]) =>
      isEn(locale) ? '$count adjusted' : '$count 条已校正';

  static String entrySummary(int minutes, int sessions, [AppLocale? locale]) =>
      isEn(locale)
      ? '$minutes min · $sessions sessions'
      : '$minutes 分钟 · $sessions 次';

  static String defaultFlagReason([AppLocale? locale]) =>
      isEn(locale) ? 'Adjusted unusual duration' : '异常时长已校正';

  static String availableRoomsTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Available Rooms' : '可加入房间';

  static String availableRoomsSubtitle([AppLocale? locale]) => isEn(locale)
      ? 'Tap to join; copy invite code for joined rooms'
      : '点击加入；已加入房间可复制邀请码';

  static String joinedBadge([AppLocale? locale]) =>
      isEn(locale) ? 'Joined' : '已加入';

  static String joinAction([AppLocale? locale]) => isEn(locale) ? 'Join' : '加入';

  static String manageInvitesTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Manage invite codes' : '管理邀请码';

  static String roomGoalSubtitle(
    String description,
    int targetMinutes, [
    AppLocale? locale,
  ]) => isEn(locale)
      ? '$description · $targetMinutes min weekly goal'
      : '$description · 每周目标 $targetMinutes 分钟';

  // ---------------------------------------------------------------------------
  // Leaderboards (排行榜)
  // ---------------------------------------------------------------------------
  static String socialLeaderboardTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Friends & Global Leaderboard' : '好友与全局排行榜';

  static String socialLeaderboardSubtitle([AppLocale? locale]) => isEn(locale)
      ? 'Ranked by weekly credited focus time; abnormal durations are capped automatically'
      : '按本周有效专注时长排名，异常时长会自动封顶';

  static String remoteBadge(FocusLeaderboardScope scope, [AppLocale? locale]) {
    if (scope == FocusLeaderboardScope.friends) {
      return isEn(locale) ? 'Server friends' : '服务端好友';
    }
    return isEn(locale) ? 'Server global' : '服务端全站';
  }

  static String refreshRankingTooltip(
    FocusLeaderboardScope scope, [
    AppLocale? locale,
  ]) {
    if (scope == FocusLeaderboardScope.friends) {
      return isEn(locale) ? 'Refresh friends ranking' : '刷新好友榜';
    }
    return isEn(locale) ? 'Refresh global ranking' : '刷新全局榜';
  }

  static String manageFriendsTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Manage focus friends' : '管理专注好友';

  // ---------------------------------------------------------------------------
  // Invites (邀请码)
  // ---------------------------------------------------------------------------
  static String inviteManagementTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Invite Code Management' : '邀请码管理';

  static String newInviteCodeButton([AppLocale? locale]) =>
      isEn(locale) ? 'New invite code' : '新建邀请码';

  static String noInvitesCreated([AppLocale? locale]) => isEn(locale)
      ? 'No invite codes created for this study room yet.'
      : '还没有为这个自习室创建邀请码。';

  static String copyInviteTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Copy invite code' : '复制邀请码';

  static String revokeInviteTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Revoke invite code' : '撤销邀请码';

  static String copiedInviteSnackBar(String code, [AppLocale? locale]) =>
      isEn(locale) ? 'Copied invite code $code' : '已复制邀请码 $code';

  static String inviteRevokedSnackBar([AppLocale? locale]) =>
      isEn(locale) ? 'Invite code revoked' : '已撤销邀请码';

  static String newInviteDialogTitle([AppLocale? locale]) =>
      isEn(locale) ? 'New Invite Code' : '新建邀请码';

  static String validityLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Validity' : '有效期';

  static String neverExpiresOption([AppLocale? locale]) =>
      isEn(locale) ? 'Never expires' : '不过期';

  static String daysOption(int days, [AppLocale? locale]) =>
      isEn(locale) ? '$days ${days == 1 ? 'day' : 'days'}' : '$days 天';

  static String usageLimitLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Usage limit' : '使用次数';

  static String unlimitedUsesOption([AppLocale? locale]) =>
      isEn(locale) ? 'Unlimited' : '不限次数';

  static String usesCountOption(int uses, [AppLocale? locale]) =>
      isEn(locale) ? '$uses ${uses == 1 ? 'time' : 'times'}' : '$uses 次';

  static String createAndCopyButton([AppLocale? locale]) =>
      isEn(locale) ? 'Create and copy' : '创建并复制';

  static String enterInviteCodeDialogTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Enter Invite Code' : '输入邀请码';

  static String studyRoomInviteCodeLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Study room invite code' : '自习室邀请码';

  static String joinStudyRoomAction([AppLocale? locale]) =>
      isEn(locale) ? 'Join study room' : '加入自习室';

  static String joinedStudyRoomSnackBar(String roomName, [AppLocale? locale]) =>
      isEn(locale) ? 'Joined study room: $roomName' : '已加入自习室：$roomName';

  static String inviteStatusRevoked([AppLocale? locale]) =>
      isEn(locale) ? 'Revoked' : '已撤销';

  static String inviteStatusDepleted([AppLocale? locale]) =>
      isEn(locale) ? 'Depleted' : '已用尽';

  static String inviteStatusPermanent([AppLocale? locale]) =>
      isEn(locale) ? 'Never expires' : '永久有效';

  static String inviteStatusExpired([AppLocale? locale]) =>
      isEn(locale) ? 'Expired' : '已过期';

  static String inviteValidUntil(String formattedDate, [AppLocale? locale]) =>
      isEn(locale) ? 'Valid until $formattedDate' : '有效至 $formattedDate';

  static String inviteUnlimitedUsage([AppLocale? locale]) =>
      isEn(locale) ? 'Unlimited uses' : '不限次数';

  static String inviteUsageCount(int used, int max, [AppLocale? locale]) =>
      isEn(locale) ? '$used/$max uses' : '$used/$max 次';

  static String inviteLastUsed(String formattedDate, [AppLocale? locale]) =>
      isEn(locale) ? 'Last used $formattedDate' : '最近 $formattedDate';

  static String inviteCreatedAt(String formattedDate, [AppLocale? locale]) =>
      isEn(locale) ? 'Created $formattedDate' : '创建 $formattedDate';

  // ---------------------------------------------------------------------------
  // Friends (好友)
  // ---------------------------------------------------------------------------
  static String focusFriendsTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Focus Friends' : '专注好友';

  static String focusFriendsSubtitle(bool remoteActive, [AppLocale? locale]) =>
      remoteActive
      ? (isEn(locale)
            ? 'Server friend relations used for friends leaderboard'
            : '服务端好友关系已用于好友专注榜')
      : (isEn(locale)
            ? 'Sign in to sync friends and online status'
            : '登录后同步好友关系和在线状态');

  static String refreshFriendsTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Refresh friends' : '刷新好友';

  static String sendFriendRequestButton([AppLocale? locale]) =>
      isEn(locale) ? 'Send friend request' : '发送好友申请';

  static String noFriendsOrRequests([AppLocale? locale]) => isEn(locale)
      ? 'No focus friends or pending requests yet.'
      : '还没有专注好友或待处理申请。';

  static String receivedRequestsHeader([AppLocale? locale]) =>
      isEn(locale) ? 'Received requests' : '收到的申请';

  static String sentRequestsHeader([AppLocale? locale]) =>
      isEn(locale) ? 'Sent requests' : '已发出的申请';

  static String existingFriendsHeader([AppLocale? locale]) =>
      isEn(locale) ? 'Friends' : '已有好友';

  static String pendingYourAction([AppLocale? locale]) =>
      isEn(locale) ? 'Pending your action' : '等待你处理';

  static String waitingForResponse([AppLocale? locale]) =>
      isEn(locale) ? 'Waiting for response' : '等待对方同意';

  static String acceptFriendRequestTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Accept friend request' : '同意好友申请';

  static String rejectFriendRequestTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Decline friend request' : '拒绝好友申请';

  static String cancelFriendRequestTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Cancel friend request' : '取消好友申请';

  static String noActiveHistory([AppLocale? locale]) =>
      isEn(locale) ? 'No active history' : '暂无活跃记录';

  static String recentlyActive(String time, [AppLocale? locale]) =>
      isEn(locale) ? 'Active $time' : '最近活跃 $time';

  static String onlineStatusText(String activity, [AppLocale? locale]) =>
      isEn(locale) ? 'Online · $activity' : '在线 · $activity';

  static String offlineStatusText(String activity, [AppLocale? locale]) =>
      isEn(locale) ? 'Offline · $activity' : '离线 · $activity';

  static String removeFriendTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Remove friend' : '移除好友';

  static String sendFriendRequestDialogTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Send Friend Request' : '发送好友申请';

  static String friendUsernameLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Friend username' : '好友用户名';

  static String sendRequestAction([AppLocale? locale]) =>
      isEn(locale) ? 'Send request' : '发送申请';

  static String friendAddedSnackBar(String username, [AppLocale? locale]) =>
      isEn(locale) ? 'Added focus friend: $username' : '已添加专注好友：$username';

  static String friendRequestSentSnackBar(
    String username, [
    AppLocale? locale,
  ]) => isEn(locale) ? 'Sent friend request: $username' : '已发送好友申请：$username';

  static String friendRequestAcceptedSnackBar(
    String username, [
    AppLocale? locale,
  ]) => isEn(locale)
      ? 'Accepted friend request from $username'
      : '已同意 $username 的好友申请';

  static String friendRequestRejectedSnackBar(
    String username, [
    AppLocale? locale,
  ]) => isEn(locale)
      ? 'Declined friend request from $username'
      : '已拒绝 $username 的好友申请';

  static String friendRequestCancelledSnackBar(
    String username, [
    AppLocale? locale,
  ]) => isEn(locale)
      ? 'Cancelled friend request to $username'
      : '已取消发送给 $username 的好友申请';

  static String friendRemovedSnackBar(String username, [AppLocale? locale]) =>
      isEn(locale) ? 'Removed $username' : '已移除 $username';

  // ---------------------------------------------------------------------------
  // Focus DND (专注勿扰)
  // ---------------------------------------------------------------------------
  static String focusDndTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Focus DND' : '专注勿扰';

  static String focusDndSheetTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Focus Do Not Disturb' : '专注勿扰';

  static String focusDndSheetSubtitle([AppLocale? locale]) => isEn(locale)
      ? 'Temporarily enables system DND during focus; restores original status when paused, finished, or reset.'
      : '开始专注时临时开启系统勿扰，暂停、结束或重置后恢复原状态';

  static String authorizeButton([AppLocale? locale]) =>
      isEn(locale) ? 'Authorize' : '去授权';

  static String autoEnableDndSwitch([AppLocale? locale]) =>
      isEn(locale) ? 'Auto enable DND during focus' : '专注时自动开启勿扰';

  static String dndPermissionGranted([AppLocale? locale]) =>
      isEn(locale) ? 'System DND permission granted' : '已获得系统勿扰权限';

  static String dndPermissionRequired([AppLocale? locale]) => isEn(locale)
      ? 'Allow Duoyi to control DND mode in system settings'
      : '需要在系统设置中允许多仪控制勿扰模式';

  static String dndSupportedExplanation([AppLocale? locale]) => isEn(locale)
      ? 'Timer and white noise work without authorization. When granted, DND toggles only while focus is running.'
      : '未授权时不影响计时和白噪音播放；授权后仅在本轮专注进行中切换系统勿扰。';

  static String dndUnsupportedExplanation([AppLocale? locale]) => isEn(locale)
      ? 'Current platform does not support controlling DND via Duoyi. Available on Android 6.0+.'
      : '当前平台不支持通过多仪控制系统勿扰。Android 6.0 及以上可用。';

  static String dndTileSubtitle({
    required bool supported,
    required bool active,
    required bool enabled,
    required bool accessGranted,
    AppLocale? locale,
  }) {
    if (!supported) {
      return isEn(locale) ? 'Unavailable on this platform' : '当前平台不可用';
    }
    if (active) return isEn(locale) ? 'System DND enabled' : '系统勿扰已开启';
    if (enabled && accessGranted) {
      return isEn(locale) ? 'Enables when focus starts' : '开始专注后开启';
    }
    if (enabled) return isEn(locale) ? 'Requires permission' : '需要系统授权';
    return isEn(locale) ? 'Tap to enable' : '手动开启';
  }

  // ---------------------------------------------------------------------------
  // White Noise & Controls & Presets (白噪音与控件)
  // ---------------------------------------------------------------------------
  static String whiteNoiseLabel([AppLocale? locale]) =>
      isEn(locale) ? 'White Noise' : '白噪音';

  static String focusTaskLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Focus Task' : '专注任务';

  static String selectTaskForRound([AppLocale? locale]) =>
      isEn(locale) ? 'Select for this round' : '选择本轮内容';

  static String selectWhiteNoiseTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Select White Noise' : '选择白噪音';

  static String selectWhiteNoiseSubtitle([AppLocale? locale]) =>
      isEn(locale) ? 'Choose a looping ambient sound' : '选择一段稳定循环的自然环境音';

  static String importAudioButton([AppLocale? locale]) =>
      isEn(locale) ? 'Import audio' : '导入音频';

  static String soundPreviewHint([AppLocale? locale]) => isEn(locale)
      ? 'Tap a sound to preview automatically, or test volume beforehand.'
      : '点击声音会自动试听，也可以先点试听确认音量。';

  static String customAudioLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Custom audio' : '自定义音频';

  static String previewAudioTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Preview' : '试听';

  static String deleteCustomAudioTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Delete custom sound' : '删除自定义音频';

  static String focusTaskPresetsSubtitle([AppLocale? locale]) =>
      isEn(locale) ? 'Select a preset or enter manually' : '选择预设或手动输入';

  static String manualInputButton([AppLocale? locale]) =>
      isEn(locale) ? 'Manual input' : '手动输入';

  static String clearAction([AppLocale? locale]) =>
      isEn(locale) ? 'Clear' : '清除';

  static List<String> taskPresets([AppLocale? locale]) => isEn(locale)
      ? const ['Deep Work', 'Reading', 'Writing', 'Review', 'Exercise', 'Study']
      : const ['深度工作', '阅读', '写作', '复盘', '运动', '学习'];

  static String taskNameHint([AppLocale? locale]) =>
      isEn(locale) ? 'Task name' : '任务名称';

  static String taskTagHint([AppLocale? locale]) =>
      isEn(locale) ? 'Tag (optional, used for statistics)' : '标签（用于专注统计分类，可选）';

  // ---------------------------------------------------------------------------
  // Session Editor (会话编辑)
  // ---------------------------------------------------------------------------
  static String editSessionTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Edit Focus Session' : '编辑专注会话';

  static String editSessionSubtitle([AppLocale? locale]) =>
      isEn(locale) ? 'Syncs Pomodoro history and time log' : '同步更新番茄钟历史和时间足迹';

  static String taskNameLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Task' : '任务名';

  static String taskTagLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Tag' : '标签';

  static String dateLabel([AppLocale? locale]) => isEn(locale) ? 'Date' : '日期';

  static String startTimeLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Start time' : '开始时间';

  static String sessionDateTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Session date' : '会话日期';

  static String durationMinutesLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Duration (minutes)' : '时长（分钟）';

  static String focusTypeFocus([AppLocale? locale]) =>
      isEn(locale) ? 'Focus' : '专注';

  static String focusTypeShortBreak([AppLocale? locale]) =>
      isEn(locale) ? 'Short break' : '短休';

  static String focusTypeLongBreak([AppLocale? locale]) =>
      isEn(locale) ? 'Long break' : '长休';

  static String noAssociatedRoom([AppLocale? locale]) =>
      isEn(locale) ? 'None' : '不关联自习室';

  // ---------------------------------------------------------------------------
  // Feedback & Errors
  // ---------------------------------------------------------------------------
  static String serviceUnavailableFallback([AppLocale? locale]) => isEn(locale)
      ? 'Study room service is temporarily unavailable. Please try again later or contact an administrator.'
      : '自习室服务暂不可用，请稍后重试或联系管理员。';

  static String soundVolumePreviewFailed([AppLocale? locale]) => isEn(locale)
      ? 'Focus volume preview failed. Check system volume or audio resources.'
      : '专注音量预览启动失败，请检查系统音量或音频资源';

  static String soundPreviewFailed([AppLocale? locale]) => isEn(locale)
      ? 'Focus sound preview failed. Check system volume or audio resources.'
      : '专注声音预览启动失败，请检查系统音量或音频资源';

  static String customSoundPreviewFailed([AppLocale? locale]) => isEn(locale)
      ? 'Custom focus sound preview failed. Check audio files or system volume.'
      : '自定义专注声音预览启动失败，请检查音频文件或系统音量';

  static String importedAudioSuccess(String label, [AppLocale? locale]) =>
      isEn(locale) ? 'Imported $label' : '已导入 $label';

  static String importedAudioPreviewFailed(String label, [AppLocale? locale]) =>
      isEn(locale)
      ? 'Imported $label, but audio preview failed. Check audio files or system volume.'
      : '已导入 $label，但声音预览启动失败，请检查音频文件或系统音量';

  static String durationRangeError([AppLocale? locale]) => isEn(locale)
      ? 'Duration must be between 1 and 1440 minutes'
      : '专注时长需在 1-1440 分钟之间';

  static String sessionDeletedError([AppLocale? locale]) => isEn(locale)
      ? 'This session does not exist or has been deleted'
      : '这条会话不存在或已被删除';

  static String sessionSavedSuccess([AppLocale? locale]) =>
      isEn(locale) ? 'Focus session saved' : '已保存专注会话';

  // ---------------------------------------------------------------------------
  // History Tab
  // ---------------------------------------------------------------------------
  static String last7DaysTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Last 7 Days' : '最近 7 天';

  static String last7DaysSubtitle([AppLocale? locale]) =>
      isEn(locale) ? 'By focus minutes' : '按专注分钟统计';

  static String todayLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Today' : '今日';

  static String thisWeekLabel([AppLocale? locale]) =>
      isEn(locale) ? 'This week' : '本周';

  static String totalLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Total' : '总计';

  static String sessionsCountSuffix(int count, [AppLocale? locale]) =>
      isEn(locale) ? '$count sessions' : '$count 次';

  static String sessionRecordsTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Session Records' : '会话记录';

  static String focusSessionsSubtitle(int count, [AppLocale? locale]) =>
      isEn(locale) ? '$count focus sessions' : '$count 次专注';

  static String copyWeeklyReportButton([AppLocale? locale]) =>
      isEn(locale) ? 'Copy weekly focus report' : '复制本周专注报告';

  static String copyMonthlyReportButton([AppLocale? locale]) =>
      isEn(locale) ? 'Copy monthly report' : '复制本月报告';

  static String closeAction([AppLocale? locale]) =>
      isEn(locale) ? 'Close' : '关闭';

  static String copyMarkdownAction([AppLocale? locale]) =>
      isEn(locale) ? 'Copy Markdown' : '复制 Markdown';

  static String focusReportCopiedSnackBar([AppLocale? locale]) =>
      isEn(locale) ? 'Focus report Markdown copied' : '专注报告 Markdown 已复制';

  static List<String> chartWeekdayLabels([AppLocale? locale]) => isEn(locale)
      ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
      : const ['一', '二', '三', '四', '五', '六', '日'];

  static String sessionDateGroupHeader(
    DateTime date, [
    AppLocale? locale,
    String? pattern,
  ]) => pattern == null
      ? isEn(locale)
            ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
            : '${date.year}-${date.month}月${date.day}日'
      : I18nDateFormat.date(date, pattern: pattern, locale: locale);
}
