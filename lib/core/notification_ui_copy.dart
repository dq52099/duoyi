import '../providers/notification_service.dart'
    show NotificationScheduleIssue, NotificationType;
import 'i18n.dart';

/// Localized UI copy and runtime diagnostic helpers for integrations,
/// notification history, and notification settings routes.
///
/// Follows project design rules:
/// 1. Dynamic locale response based on [I18n.current] / [AppLocale].
/// 2. Clear, user-friendly and actionable error messages; no stack trace or raw technical leak.
/// 3. Accurate mapping of known runtime service/permission diagnostics with safe fallbacks.
/// 4. Preservation of stable system keys, entity identifiers, and user data.
class NotificationUiCopy {
  NotificationUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;

  // ---------------------------------------------------------------------------
  // 扩展功能 (Integrations Screen)
  // ---------------------------------------------------------------------------
  static String get integrationsTitle => isEn ? 'Extensions' : '扩展功能';
  static String get tabCalendar => isEn ? 'Calendar Subscriptions' : '日历订阅';
  static String get tabLocation => isEn ? 'Location Reminders' : '位置提醒';
  static String get tabLanguage => isEn ? 'Language' : '语言';
  static String get localeSaveFailed => isEn
      ? 'Language changed, but could not be saved. Please retry.'
      : '语言已切换，但未能保存，请重试';

  // 日历订阅卡片
  static String get icsHeaderTitle =>
      isEn ? 'Subscribe from ICS URL' : '从 ICS URL 订阅';
  static String get icsHeaderDescription => isEn
      ? 'Add a public calendar link to see its events here. Subscriptions are read-only.'
      : '添加公开日历链接，在多仪中查看日程。订阅为只读，不会修改原日历。';
  static String get emptySubscriptions => isEn
      ? 'No subscriptions yet. Tap + to add an ICS feed, or connect a Google / Outlook account.'
      : '还没有订阅，点击右下角 + 添加 ICS，或添加 Google / Outlook 账号';
  static String get refreshAction => isEn ? 'Refresh' : '刷新';
  static String get addIcsTooltip => isEn ? 'Add ICS' : '添加 ICS';

  // 添加日历对话框
  static String get addSubscriptionDialogTitle =>
      isEn ? 'Add Calendar Subscription' : '添加日历订阅';
  static String get subscriptionNameLabel => isEn ? 'Name' : '名称';
  static String get icsUrlLabel => 'ICS URL';
  static String get nameRequiredError =>
      isEn ? 'Please enter a subscription name' : '请填写订阅名称';
  static String get icsUrlRequiredError =>
      isEn ? 'Please enter an ICS URL' : '请填写 ICS URL';
  static String get invalidUrlError =>
      isEn ? 'Please enter a valid http/https address' : '请输入有效的 http/https 地址';

  // OAuth 日历卡片与弹窗
  static String get oauthCardTitle =>
      isEn ? 'Google / Outlook OAuth Calendar' : 'Google / Outlook OAuth 日历';
  static String get oauthCardDescription => isEn
      ? 'Connect your Google or Outlook account to see private calendar events here.'
      : '连接 Google 或 Outlook 账号，在多仪中查看私有日历日程。';
  static String get addAccountAction => isEn ? 'Add Account' : '添加账号';
  static String get oauthStateMismatch => isEn
      ? 'OAuth callback state mismatch. Please re-authorize.'
      : 'OAuth 回调 state 不匹配，请重新授权';
  static String get addOauthDialogTitle =>
      isEn ? 'Add OAuth Calendar' : '添加 OAuth 日历';
  static String get providerLabel => isEn ? 'Provider' : '服务商';
  static String get displayNameLabel => isEn ? 'Display Name' : '显示名称';
  static String get clientSecretOptionalLabel =>
      isEn ? 'Client Secret (optional)' : 'Client Secret（可选）';
  static String get authUrlSectionTitle => isEn ? 'Authorization Link' : '授权链接';
  static String get authUrlPlaceholder =>
      isEn ? 'Generated after entering Client ID' : '填写 Client ID 后生成';
  static String get copyAction => isEn ? 'Copy' : '复制';
  static String get authUrlCopied =>
      isEn ? 'Authorization link copied' : '授权链接已复制';
  static String get openAction => isEn ? 'Open' : '打开';
  static String get openAuthFailed => isEn
      ? 'Unable to open authorization page. Link preserved.'
      : '无法打开授权页，已保留链接';
  static String get authCodeLabel =>
      isEn ? 'Authorization Code or Callback URL' : '授权码或回调 URL';
  static String get authCodeHint => isEn
      ? 'Paste code, or paste callback URL with ?code='
      : '粘贴 code，或粘贴带 ?code= 的回调 URL';
  static String get saveAndSyncAction => isEn ? 'Save and sync' : '保存并同步';
  static String get oauthFieldsRequired => isEn
      ? 'Please enter name, Client ID, redirect URI, and authorization code'
      : '请填写名称、Client ID、回调地址和授权码';
  static String get oauthConnected =>
      isEn ? 'OAuth calendar connected' : 'OAuth 日历已连接';

  static String formatOauthConnectError(Object? error) {
    if (error == null) {
      return isEn
          ? 'Connection failed. Please check network and authorization code.'
          : '连接失败，请检查网络与授权码';
    }
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('state') || lower.contains('mismatch')) {
      return isEn
          ? 'OAuth state mismatch. Please request a new authorization code.'
          : 'OAuth 校验不匹配，请重新发起授权';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('timeout')) {
      return isEn
          ? 'Network timeout while contacting calendar server. Please retry.'
          : '连接日历服务超时，请检查网络后重试';
    }
    if (lower.contains('token') ||
        lower.contains('code') ||
        lower.contains('invalid_grant')) {
      return isEn
          ? 'Authorization code expired or invalid. Please authorize again.'
          : '授权码已失效或格式不正确，请重新获取';
    }
    return isEn
        ? 'Connection failed. Please check your credentials and retry.'
        : '连接失败，请检查授权信息后重试';
  }

  // 账号与订阅条目状态
  static String get statusActive => isEn ? 'Active' : '启用';
  static String get statusPaused => isEn ? 'Paused' : '暂停';
  static String lastSyncedAt(String formatted) =>
      isEn ? 'Last synced $formatted' : '上次同步 $formatted';
  static String get menuPause => isEn ? 'Pause' : '暂停';
  static String get menuResume => isEn ? 'Resume' : '启用';
  static String get menuSync => isEn ? 'Sync' : '同步';
  static String get menuDelete => isEn ? 'Delete' : '删除';

  static String formatCalDavError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('401') ||
        message.contains('403') ||
        message.contains('unauthorized') ||
        message.contains('forbidden')) {
      return isEn
          ? 'Calendar access denied. Check your authorization and permissions.'
          : '日历访问被拒绝，请检查授权信息和权限';
    }
    if (message.contains('timeout') ||
        message.contains('socket') ||
        message.contains('connection')) {
      return isEn
          ? 'Could not connect to the calendar. Check your network and retry.'
          : '无法连接日历服务，请检查网络后重试';
    }
    return isEn
        ? 'Calendar sync failed. Check the calendar address and retry.'
        : '日历同步失败，请检查日历地址后重试';
  }

  // CalDAV 写回目标
  static String get calDavTargetTitle =>
      isEn ? 'CalDAV Writeback Target' : 'CalDAV 写回目标';
  static String get calDavVerified => isEn ? 'Verified' : '已验证';
  static String get calDavUnverified => isEn ? 'Unverified' : '未验证';
  static String get calDavPolicySkip =>
      isEn ? 'Skip remote changes' : '远端变更不覆盖';
  static String get calDavPolicyOverwrite =>
      isEn ? 'Always overwrite remote' : '覆盖远端';
  static String get calDavConfigPrompt => isEn
      ? 'Configure CalDAV collection URL and Authorization header; testing creates and deletes a probe event.'
      : '配置 CalDAV 集合 URL 和 Authorization header，测试时会创建并删除一条探测事件。';
  static String calDavConflictsSkipped(int count) => isEn
      ? '$count remote changes skipped to prevent overwriting edits by others.'
      : '有 $count 条远端变更已跳过，避免覆盖别人改过的日程。';
  static String lastTestedAt(String formatted) =>
      isEn ? 'Last tested $formatted' : '上次测试 $formatted';
  static String get calDavEdit => isEn ? 'Edit' : '编辑';
  static String get calDavConfigure => isEn ? 'Configure' : '配置';
  static String get calDavRemove => isEn ? 'Remove' : '移除';
  static String get calDavTestWriteback => isEn ? 'Test Writeback' : '测试写回';
  static String get calDavDialogTitle =>
      isEn ? 'Configure CalDAV Writeback' : '配置 CalDAV 写回';
  static String get collectionUrlLabel => isEn ? 'Collection URL' : '集合 URL';
  static String get authHeaderLabel => 'Authorization header';
  static String get authHeaderHint =>
      isEn ? 'Bearer ... or Basic ...' : 'Bearer ... 或 Basic ...';
  static String get conflictPolicyLabel =>
      isEn ? 'Remote Conflict Policy' : '远端冲突处理';
  static String get conflictPolicySkipItem =>
      isEn ? 'Skip remote modified events' : '跳过远端已修改事件';
  static String get conflictPolicyOverwriteItem =>
      isEn ? 'Always overwrite remote' : '始终覆盖远端';
  static String get saveAction => isEn ? 'Save' : '保存';

  static String get iCloudDialogTitle =>
      isEn ? 'Configure iCloud Calendar Writeback' : '配置 iCloud 日历写回';
  static String get iCloudUrlLabel =>
      isEn ? 'iCloud CalDAV Collection URL' : 'iCloud CalDAV 集合 URL';
  static String get appSpecificPasswordLabel =>
      isEn ? 'App-Specific Password' : 'App 专用密码';

  // 位置提醒 Tab
  static String get locationHeaderTitle => isEn ? 'Location Reminders' : '位置提醒';
  static String get locationHeaderDescription => isEn
      ? 'Get reminders when you arrive or leave. Allow background location on Android to receive them while the app is closed.'
      : '到达或离开指定地点时提醒你。Android 需允许后台位置，才能在应用关闭时接收提醒。';
  static String get testCurrentLocationAction =>
      isEn ? 'Test Current Location' : '输入当前位置测试';
  static String get grantBackgroundLocationAction =>
      isEn ? 'Grant Background Location' : '授权后台位置';
  static String get systemLocationSettingsTooltip =>
      isEn ? 'Location settings' : '系统位置设置';
  static String get emptyLocationReminders =>
      isEn ? 'No location reminders. Tap + to create.' : '没有位置提醒，点击 + 创建';
  static String get newLocationReminderTooltip =>
      isEn ? 'New location reminder' : '新建位置提醒';
  static String get newLocationReminderTitle =>
      isEn ? 'New Location Reminder' : '新建位置提醒';
  static String get reminderTitleLabel => isEn ? 'Title' : '标题';
  static String get latitudeLabel => isEn ? 'Latitude' : '纬度';
  static String get longitudeLabel => isEn ? 'Longitude' : '经度';
  static String get radiusMetersLabel => isEn ? 'Radius (meters)' : '半径（米）';
  static String get triggerDirectionLabel =>
      isEn ? 'Trigger Direction' : '触发方向';
  static String get triggerEnter => isEn ? 'Arrive' : '进入';
  static String get triggerLeave => isEn ? 'Leave' : '离开';
  static String get reminderTitleRequired =>
      isEn ? 'Please enter a reminder title' : '请填写提醒标题';
  static String get validLatitudeRequired =>
      isEn ? 'Please enter a valid latitude' : '请输入有效纬度';
  static String get validLongitudeRequired =>
      isEn ? 'Please enter a valid longitude' : '请输入有效经度';
  static String get validRadiusRequired =>
      isEn ? 'Please enter a valid radius' : '请输入有效半径';

  static String formatLocationPermissionMessage(String raw) {
    if (!isEn) return raw;
    if (raw.contains('位置权限已授权')) return 'Location permission granted';
    if (raw.contains('需要先授予使用期间位置权限')) {
      return 'Location permission while in use is required first';
    }
    if (raw.contains('需要在系统设置中允许始终访问位置')) {
      return 'Allow "Always" location access in system settings for background geofences to trigger';
    }
    return raw;
  }

  static String locationSynced(int count) => isEn
      ? 'Background location granted. Synced $count system geofences.'
      : '后台位置权限已授权，已同步 $count 条系统 geofence';
  static String get toSettingsAction => isEn ? 'Settings' : '去设置';

  static String get testInputLocationTitle =>
      isEn ? 'Enter Current Location' : '输入当前位置';
  static String get testInputLocationDescription => isEn
      ? 'Feeds coordinates to the location reminder engine to verify arrive/leave trigger rules.'
      : '这会把坐标喂给位置提醒引擎，用来验证到达/离开触发规则。';
  static String get testButton => isEn ? 'Test' : '测试';
  static String get validCoordinatesRequired =>
      isEn ? 'Please enter valid coordinates' : '请输入有效经纬度';
  static String get locationNoHits => isEn
      ? 'Current location did not match any location reminders'
      : '当前位置未命中任何位置提醒';
  static String locationTriggeredHits(int count) =>
      isEn ? 'Triggered $count location reminders' : '已触发 $count 条位置提醒';
  static String locationTriggerSuffix(bool isEnter) => isEn
      ? (isEnter ? 'triggers on arrival' : 'triggers on departure')
      : (isEnter ? '进入触发' : '离开触发');

  // ---------------------------------------------------------------------------
  // 通知记录 (Notification History Screen)
  // ---------------------------------------------------------------------------
  static String get notificationHistoryTitle =>
      isEn ? 'Notification Log' : '通知记录';
  static String get markAllReadTooltip => isEn ? 'Mark all as read' : '全部标为已读';
  static String get clearHistoryTooltip =>
      isEn ? 'Clear notification history' : '清空通知记录';
  static String get confirmClearDialogTitle =>
      isEn ? 'Clear notification history?' : '清空通知记录？';
  static String confirmClearDialogContent(int count) => isEn
      ? 'Clears all $count retained notification logs. Scheduled reminders will not be canceled.'
      : '将清空当前保留的 $count 条通知记录，已调度的提醒不会被取消。';
  static String get clearAction => isEn ? 'Clear' : '清空';
  static String get historyClearedSnack =>
      isEn ? 'Notification history cleared' : '通知记录已清空';
  static String get emptyHistory => isEn ? 'No notifications yet' : '暂无通知记录';
  static String get emptyHistoryFiltered =>
      isEn ? 'No matching notification logs' : '没有匹配的通知记录';
  static String get searchHint =>
      isEn ? 'Search title, content, or related ID' : '搜索标题、内容或关联 ID';
  static String get clearSearchTooltip => isEn ? 'Clear search' : '清空搜索';
  static String get filterAll => isEn ? 'All' : '全部';
  static String get filterUnread => isEn ? 'Unread' : '未读';
  static String get filterRead => isEn ? 'Read' : '已读';

  static String formatHistorySummary({
    required int historyCount,
    required int filteredCount,
    required int unreadCount,
    required int page,
    required int totalPages,
    required int pageSize,
  }) {
    if (filteredCount == historyCount) {
      return isEn
          ? '$historyCount total · $unreadCount unread · Search, filter & page · Page $page of $totalPages · $pageSize per page'
          : '共 $historyCount 条 · 未读 $unreadCount 条 · 支持搜索、筛选和分页浏览 · 第 $page / $totalPages 页 · 每页 $pageSize 条';
    }
    return isEn
        ? '$filteredCount of $historyCount filtered · $unreadCount unread · Page $page of $totalPages'
        : '已筛出 $filteredCount / $historyCount 条 · 未读 $unreadCount 条 · 第 $page / $totalPages 页';
  }

  static String get badgeRead => isEn ? 'Read' : '已读';
  static String get badgeUnread => isEn ? 'Unread' : '未读';
  static String get viewDetailsTooltip => isEn ? 'View details' : '查看详情';
  static String get markAsReadTooltip => isEn ? 'Mark as read' : '标为已读';
  static String get markAsUnreadTooltip => isEn ? 'Mark as unread' : '标为未读';

  static String get detailSheetContentLabel => isEn ? 'Content' : '内容';
  static String get detailSheetNoContent => isEn ? 'No content' : '无内容';
  static String get detailSheetTriggerTime => isEn ? 'Trigger Time' : '触发时间';
  static String get detailSheetRecordId => isEn ? 'Record ID' : '记录编号';
  static String get detailSheetRelatedItem => isEn ? 'Related Item' : '关联对象';
  static String get detailSheetNone => isEn ? 'None' : '无';

  static String get pagerPrevTooltip => isEn ? 'Previous page' : '上一页';
  static String get pagerNextTooltip => isEn ? 'Next page' : '下一页';

  static String notificationTypeLabel(NotificationType type) {
    if (!isEn) {
      return switch (type) {
        NotificationType.todo => '待办',
        NotificationType.habit => '习惯',
        NotificationType.pomodoro => '番茄钟',
        NotificationType.anniversary => '纪念日',
        NotificationType.location => '位置',
        NotificationType.general => '系统',
      };
    }
    return switch (type) {
      NotificationType.todo => 'Task',
      NotificationType.habit => 'Habit',
      NotificationType.pomodoro => 'Pomodoro',
      NotificationType.anniversary => 'Anniversary',
      NotificationType.location => 'Location',
      NotificationType.general => 'System',
    };
  }

  // ---------------------------------------------------------------------------
  // 通知设置 (Notification Settings Screen)
  // ---------------------------------------------------------------------------
  static String get settingsTitle => isEn ? 'Notification Settings' : '通知设置';
  static String get settingsHeroSubtitle => isEn
      ? 'System permissions, reminder times, ringtones, and log retention'
      : '系统权限、提醒时间、铃声和通知记录保留';
  static String get sectionSystem => isEn ? 'System Notifications' : '系统通知';
  static String get permissionGrantedSubtitle =>
      isEn ? 'Notification permission is enabled' : '通知权限已开启';
  static String get permissionDeniedSubtitle =>
      isEn ? 'Notification permission is disabled' : '通知权限未开启';
  static String get permissionTileTitle =>
      isEn ? 'Notification Permission' : '通知权限';
  static String permissionTileSubtitle(bool granted) => granted
      ? (isEn ? 'System allows Duoyi to send reminders' : '系统允许多仪发送提醒')
      : (isEn
            ? 'Enable to receive standard notifications and reminders'
            : '开启后才能收到普通通知和提醒');
  static String get checkAgainAction => isEn ? 'Check again' : '重新检查';
  static String get enableAction => isEn ? 'Enable' : '开启';

  static String get channelGeneralTitle =>
      isEn ? 'Standard Reminder Channel' : '普通提醒渠道';
  static String get channelGeneralSubtitle => isEn
      ? 'Check sound, banner, and lock-screen permissions for standard notifications'
      : '检查普通通知的声音、横幅和锁屏权限';
  static String get channelAlarmTitle =>
      isEn ? 'Strong Reminder Channel' : '强提醒渠道';
  static String get channelAlarmSubtitle => isEn
      ? 'Check sound, banner, and full-screen permissions for alarm reminders'
      : '检查闹钟提醒的声音、横幅和全屏展示权限';
  static String get channelFallbackTitle =>
      isEn ? 'Alarm Fallback Channel' : '闹钟降级兜底';
  static String get channelFallbackSubtitle => isEn
      ? 'Falls back to standard reminders if alarm or built-in ringtone fails; if standard channel is muted, fallback may be silent'
      : '强提醒或内置铃声注册失败时会改用普通提醒；普通提醒渠道静音，兜底也可能无声';
  static String get channelStatusTitle =>
      isEn ? 'Built-in Ringtone Status Channel' : '内置铃声状态渠道';
  static String get channelStatusSubtitle => isEn
      ? 'Check if built-in ringtone foreground status notification is muted or blocked'
      : '检查内置铃声前台状态通知是否被静音或屏蔽';

  static String get testNowTitle =>
      isEn ? 'Send Test Notification Now' : '立即发送测试通知';
  static String get testNowSubtitle => isEn
      ? 'Verify standard notification channel visibility and sound'
      : '验证普通通知渠道是否可见、可响铃';
  static String get testScheduledPushTitle =>
      isEn ? 'Standard Timed Test in 1 Min' : '1 分钟后普通定时';
  static String get testScheduledPushSubtitle => isEn
      ? 'Verify system scheduling pipeline; should receive a standard notification at trigger time'
      : '验证系统定时调度链路，到点应收到普通通知';
  static String get testScheduledPopupTitle =>
      isEn ? 'Pop-up Test in 1 Min' : '1 分钟后弹出测试';
  static String get testScheduledPopupSubtitle => isEn
      ? 'Verifies in-app foreground pop-up only; background and lock screen do not trigger fallback'
      : '仅验证应用前台弹窗；后台和锁屏不触发兜底通知';
  static String get testScheduledPopupFallbackTitle =>
      isEn ? 'Pop-up + Fallback in 1 Min' : '1 分钟后弹出+通知兜底';
  static String get testScheduledPopupFallbackSubtitle => isEn
      ? 'Simulates realistic pop-up; shows pop-up in foreground, standard notification in background'
      : '模拟真实弹出提醒；前台弹框，后台或锁屏走普通通知';
  static String get testScheduledAlarmTitle =>
      isEn ? 'Alarm Test in 1 Min' : '1 分钟后闹钟测试';
  static String get testScheduledAlarmSubtitle => isEn
      ? 'Verifies alarm ringing and notification dismiss actions without forcing full screen'
      : '验证闹钟响铃和通知停止链路，不强制全屏遮挡';
  static String get testScheduledFullScreenTitle =>
      isEn ? 'Full-Screen Alarm in 1 Min' : '1 分钟后全屏闹钟';
  static String get testScheduledFullScreenSubtitle => isEn
      ? 'Wakes up full screen from lock screen or background with ringing and vibration'
      : '锁屏或后台应全屏唤起，并同时响铃震动';
  static String get testScheduledDefaultTitle =>
      isEn ? 'Default Method Test in 1 Min' : '1 分钟后默认方式';
  static String get testScheduledDefaultSubtitle => isEn
      ? 'Schedules a test using the currently active daily reminder method'
      : '按每日提醒里当前启用的提醒方式注册一次测试';
  static String get testStrongRingtoneTitle =>
      isEn ? 'Test Strong Reminder Sound' : '测试强提醒铃声';
  static String get testStrongRingtoneSubtitle => isEn
      ? 'Verify alarm reminders, built-in sounds, and notification dismiss buttons'
      : '验证闹钟提醒、内置铃声和通知停止按钮';

  static String get pendingPushTitle =>
      isEn ? 'Scheduled Standard Reminders' : '已调度普通提醒';
  static String pendingPushSubtitle(int? count) {
    if (count == null) {
      return isEn ? 'Reading pending queue...' : '正在读取待触发队列';
    }
    return isEn ? '$count pending' : '$count 条待触发';
  }

  static String get pendingAlarmTitle =>
      isEn ? 'Scheduled Alarm Reminders' : '已调度闹钟提醒';
  static String pendingAlarmSubtitle(int? count, bool exactGranted) {
    if (count == null) {
      return isEn ? 'Reading strong reminder queue...' : '正在读取强提醒队列';
    }
    if (isEn) {
      return '$count pending · ${exactGranted ? "Exact alarm enabled" : "Exact alarm disabled"}';
    }
    return '$count 条待触发 · ${exactGranted ? "精准闹钟已开启" : "精准闹钟未开启"}';
  }

  static String get exactAlarmButton => isEn ? 'Exact Alarm' : '精准闹钟';
  static String get registeredRemindersTileTitle =>
      isEn ? 'Reminder Registration Status' : '提醒注册状态';
  static String get viewAction => isEn ? 'View' : '查看';

  static String get sectionShortcuts => isEn ? 'Reminder Shortcuts' : '提醒入口';
  static String get sectionShortcutsSubtitle => isEn
      ? 'Controls notification shortcuts and history retention'
      : '控制由通知触发的快捷记录和历史保留';
  static String get historyRetentionTitle =>
      isEn ? 'Notification History Retention' : '通知记录保留';
  static String historyRetentionSubtitle(int limit) => isEn
      ? 'Retain up to $limit notifications. Lower values trim older logs.'
      : '最多保留 $limit 条历史，调低后会裁剪旧记录';
  static String historyRetentionItem(int count) =>
      isEn ? '$count items' : '$count 条';

  static String get historyEntryTitle => isEn ? 'Notification Log' : '通知记录';
  static String historyEntrySubtitle(int historyCount, int unreadCount) => isEn
      ? '$historyCount total, $unreadCount unread'
      : '共 $historyCount 条，未读 $unreadCount 条';

  // 诊断与反馈提示
  static String get statusReadFailed => isEn
      ? 'Failed to read notification status. Please try again later or check system settings.'
      : '通知状态读取失败，请稍后重试或打开系统通知设置检查。';
  static String get permissionGrantedFeedback =>
      isEn ? 'Notification permission enabled' : '通知权限已开启';
  static String get permissionDeniedFeedback =>
      isEn ? 'Notification permission disabled' : '通知权限未开启';
  static String get permissionRequestFailedFeedback => isEn
      ? 'Failed to request notification permission. Please open system settings manually.'
      : '通知权限请求失败，请前往系统设置手动开启。';
  static String get exactAlarmGrantedFeedback =>
      isEn ? 'Exact alarm permission enabled' : '精准闹钟权限已开启';
  static String get exactAlarmDeniedFeedback => isEn
      ? 'Exact alarm permission disabled; alarms may be delayed or downgraded'
      : '精准闹钟权限未开启，闹钟可能延后或降级';
  static String get exactAlarmRequestFailedFeedback => isEn
      ? 'Failed to request exact alarm permission. Please open system settings manually.'
      : '精准闹钟权限请求失败，请前往系统设置手动开启。';
  static String get testNotificationFailedFallback => isEn
      ? 'Test notification not sent. Check notification permissions and channel settings.'
      : '测试通知未发送，请检查通知权限和渠道设置。';
  static String get testNotificationError => isEn
      ? 'Test notification failed. Check notification permissions and channel settings.'
      : '测试通知发送失败，请检查通知权限和渠道设置。';
  static String get scheduledTestFallback => isEn
      ? 'Scheduled test not registered. Check notification, exact alarm, and full-screen permissions.'
      : '定时测试未注册，请检查通知、精准闹钟和全屏提醒权限。';
  static String get scheduledTestIssueNonBlocking => isEn
      ? 'Scheduled test registered, but reminder channels need review.'
      : '定时测试已注册，但提醒通道需要检查。';

  static String formatScheduledDiagnosticSuccess(
    String label,
    String foregroundHint,
  ) => isEn
      ? 'Scheduled a 1-minute $label test$foregroundHint'
      : '已注册 1 分钟后的$label测试$foregroundHint';

  static String get foregroundHintInAppOnly =>
      isEn ? ', requires keeping app in foreground' : '，需保持应用前台';
  static String get foregroundHintFallback => isEn
      ? ', background or lock screen will receive standard notification fallback'
      : '，后台或锁屏应收到普通通知兜底';

  static String get scheduledPermissionDenied => isEn
      ? 'Notification permission is off. Cannot schedule timed test.'
      : '通知权限未开启，无法注册定时测试';
  static String get scheduledTestError => isEn
      ? 'Failed to register timed test. Check notification and exact alarm permissions.'
      : '定时测试注册失败，请检查通知和精确闹钟权限。';
  static String get strongTestPermissionDenied => isEn
      ? 'Notification permission not granted. Strong reminder may not show a stop action.'
      : '通知权限未开启，强提醒可能没有停止按钮';
  static String get strongTestError => isEn
      ? 'Failed to start strong reminder test. Check notification, alarm, and background permissions.'
      : '强提醒测试启动失败，请检查通知、闹钟和后台运行权限。';

  static String formatStrongTestMessage({
    required bool notificationGranted,
    required bool exactAlarmGranted,
    required bool fullScreenGranted,
  }) {
    if (!isEn) {
      final missing = <String>[
        if (!notificationGranted) '通知权限',
        if (!exactAlarmGranted) '精准闹钟权限',
        if (!fullScreenGranted) '全屏提醒权限',
      ];
      if (missing.isEmpty) {
        return '强提醒测试已启动，可在通知上手动停止响铃';
      }
      return '强提醒测试已启动；仍需开启${missing.join('、')}，否则闹钟、全屏或停止按钮可能异常。';
    }
    final missing = <String>[
      if (!notificationGranted) 'notification permission',
      if (!exactAlarmGranted) 'exact alarm permission',
      if (!fullScreenGranted) 'full-screen reminder permission',
    ];
    if (missing.isEmpty) {
      return 'Strong reminder test started. You can stop ringing directly from the notification.';
    }
    return 'Strong reminder test started; still requires ${missing.join(', ')}, otherwise alarms, full-screen display, or stop buttons may not work properly.';
  }

  static String formatScheduleIssue(
    NotificationScheduleIssue? issue, {
    required String fallback,
  }) {
    if (issue == null) return fallback;
    if (issue.copy != null) {
      final locale = I18n.current;
      final separator = locale == AppLocale.zh ? '：' : ': ';
      return '${issue.renderTitle(locale: locale)}$separator${issue.renderMessage(locale: locale)}';
    }
    if (!isEn) return '${issue.title}：${issue.message}';
    final title = formatIssueText(issue.title);
    final msg = formatIssueText(issue.message);
    return '$title: $msg';
  }

  static String formatIssueText(String raw) {
    if (!isEn) return raw;
    if (raw.contains('闹钟测试权限未开启')) return 'Exact alarm permission not granted';
    if (raw.contains('全屏闹钟权限未开启')) {
      return 'Full-screen alarm permission not granted';
    }
    if (raw.contains('精准闹钟权限未开启')) {
      return 'Exact alarm permission is disabled. Cannot reliably schedule alarms. Please enable it in system settings and try again.';
    }
    if (raw.contains('强提醒弹屏权限未开启')) {
      return 'Full-screen intent permission is disabled. Cannot schedule lock-screen alarms. Please enable it in system settings and try again.';
    }
    if (raw.contains('通知权限未开启') || raw.contains('通知权限未授予')) {
      return 'Notification permission is disabled. Please enable it in system settings.';
    }
    if (raw.contains('强提醒渠道未就绪')) return 'Strong reminder channel is not ready';
    if (raw.contains('精准闹钟权限未开启，提醒可能延后')) {
      return 'Exact alarm permission is off. Reminders may be delayed';
    }
    if (raw.contains('全屏提醒权限未开启，锁屏弹窗可能不可用')) {
      return 'Full-screen permission is off. Lock-screen pop-ups may not work';
    }
    return raw;
  }

  static String channelStatusLabel(
    bool exists,
    bool isBlocked,
    bool isSilent,
    bool isLowImportance,
    bool requiresSound,
    bool busy,
    bool hasStatusMap,
  ) {
    if (!hasStatusMap) {
      return busy
          ? (isEn ? 'Checking' : '检测中')
          : (isEn ? 'Not checked' : '未检测');
    }
    if (!exists) return isEn ? 'Not created' : '未创建';
    if (isBlocked) return isEn ? 'Disabled' : '已关闭';
    if (requiresSound && isSilent) return isEn ? 'Muted' : '已静音';
    if (isLowImportance) return isEn ? 'Low priority' : '提醒弱';
    return isEn ? 'Sound normal' : '声音正常';
  }

  // 提醒注册状态独立页 (RegisteredRemindersScreen)
  static String get registeredRemindersTitle =>
      isEn ? 'Reminder Registration Status' : '提醒注册状态';
  static String get filterChipCurrent =>
      isEn ? 'Pending / Unconfirmed' : '待触发/待确认';
  static String get filterChipQueued => isEn ? 'Queued in System' : '系统待触发';
  static String get filterChipPartial => isEn ? 'Partially Queued' : '部分待触发';
  static String get filterChipMissing => isEn ? 'Needs Resaving' : '需重新保存';
  static String get filterChipUnconfirmed => isEn ? 'Unconfirmed' : '待确认';

  static String registeredQueuedPart(int count, String fallback) =>
      isEn ? '$count queued in system' : fallback;
  static String registeredPartialPart(int count, String fallback) =>
      isEn ? '$count partially queued' : fallback;
  static String registeredUnconfirmedPart(int count, String fallback) =>
      isEn ? '$count unconfirmed' : fallback;
  static String registeredMissingPart(int count, String fallback) =>
      isEn ? '$count require resaving' : fallback;

  static String queueStateLabel(String stateName) {
    if (!isEn) {
      return switch (stateName) {
        'queued' => '系统待触发',
        'partial' => '部分待触发',
        'missing' => '需重新保存',
        _ => '待确认',
      };
    }
    return switch (stateName) {
      'queued' => 'Queued in system',
      'partial' => 'Partially queued',
      'missing' => 'Needs resaving',
      _ => 'Unconfirmed',
    };
  }

  static String queueStateSummary(String stateName) {
    if (!isEn) {
      return switch (stateName) {
        'queued' =>
          '系统待触发表示这条提醒登记的有效通知或闹钟编号组还能在系统待触发列表里查到。它不是“保证会响”，只是确认应用已经把系统通道交给系统；实际弹出还受通知权限、精准闹钟、全屏提醒和后台限制影响。',
        'partial' =>
          '部分待触发表示这条提醒只有一部分规则仍能在系统待触发列表里查到。多提醒时间、重复规则或闹钟兜底可能只注册成功了一部分，需要重新保存对应提醒来补齐。',
        'missing' =>
          '需重新保存表示应用注册表里还有这条提醒，但系统待触发列表已经查不到对应编号。常见原因是提醒时间已过、权限关闭、系统清理后台任务，或登录切号后的提醒重放尚未完成。',
        _ =>
          '待确认表示系统待触发列表读取失败，或这条提醒只有应用内弹出、邮件等不完全进入系统队列的通道。应用内弹出只在前台运行时展示，后台和锁屏要看普通通知或闹钟兜底。',
      };
    }
    return switch (stateName) {
      'queued' =>
        'Queued in system indicates the valid notification or alarm IDs are present in the system trigger queue. This confirms delivery to the system, but ringing remains subject to notification permissions, exact alarms, full-screen display, and background restrictions.',
      'partial' =>
        'Partially queued indicates only part of the scheduled reminder rules were found in the system queue. Multiple reminder times, repeat rules, or alarm fallbacks may have partially failed. Resaving the item is recommended.',
      'missing' =>
        'Needs resaving indicates the reminder is in the app registry but absent from the system queue. Common causes include expired trigger times, revoked permissions, system background task pruning, or incomplete account replay.',
      _ =>
        'Unconfirmed indicates the system queue could not be read, or the reminder uses in-app pop-ups or email that do not fully enter the local system queue. In-app pop-ups only display while the app is in the foreground.',
    };
  }

  static String queueStateActionHint(String stateName) {
    if (!isEn) {
      return switch (stateName) {
        'queued' => '不用重复保存。若到点没响，优先检查通知权限、渠道声音、精准闹钟和全屏提醒权限。',
        'partial' => '打开对应事项重新保存提醒；如果是多提醒时间，请逐个确认时间和提醒方式。',
        'missing' =>
          '若仍需要提醒，打开对应事项，把提醒时间调整到未来后重新保存；若提醒已过期且不再需要，可忽略或删除提醒。保存前先确认通知权限、精准闹钟和全屏提醒权限已经开启。',
        _ => '应用内弹出需要保持应用前台；需要后台或锁屏触发时，请选择普通通知或闹钟提醒。',
      };
    }
    return switch (stateName) {
      'queued' =>
        'No need to resave. If it does not ring at trigger time, check notification permissions, channel sound, exact alarms, and full-screen intents.',
      'partial' =>
        'Open the item and resave the reminder. For multiple reminder times, confirm each time and reminder method.',
      'missing' =>
        'If still needed, open the item, set the time to the future, and resave. Verify notification permissions, exact alarms, and full-screen permissions beforehand.',
      _ =>
        'In-app pop-ups require the app to stay in the foreground. Select standard notifications or alarms if background or lock-screen triggers are needed.',
    };
  }

  static String probeBannerMessage({
    required bool isFailed,
    required bool isLoading,
    required int partialCount,
    required int missingCount,
  }) {
    if (!isEn) {
      if (isLoading) {
        return '正在读取系统待触发队列，结果出来前先标记为“待确认”。';
      }
      if (isFailed) {
        return '系统待触发队列读取失败，暂时不能判断系统是否还保留这些提醒；请检查通知/闹钟权限后重试。';
      }
      if (missingCount > 0 && partialCount > 0) {
        return '$missingCount 条提醒在系统队列中查不到，$partialCount 条只确认到一部分；请优先重新保存查不到的提醒。';
      }
      if (missingCount > 0) {
        return '$missingCount 条提醒在系统队列中查不到，需要打开对应事项重新保存。';
      }
      return '$partialCount 条提醒只确认到一部分，多提醒时间或闹钟兜底可能没有全部注册成功。';
    }
    if (isLoading) {
      return 'Reading system pending queue; marked as "Unconfirmed" until resolved.';
    }
    if (isFailed) {
      return 'Failed to read system queue. Unable to verify system reminders. Please check notification and alarm permissions.';
    }
    if (missingCount > 0 && partialCount > 0) {
      return '$missingCount reminders not found in system queue, $partialCount partially confirmed. Please resave missing reminders first.';
    }
    if (missingCount > 0) {
      return '$missingCount reminders not found in system queue. Open the items and resave them.';
    }
    return '$partialCount reminders partially confirmed. Multiple reminder times or alarm fallbacks may not all be registered.';
  }

  static String registeredStatusHint({
    required String filterName,
    required int missingCount,
    required bool accountBoundaryPending,
    required bool accountIsAvailable,
    required bool snapshotFailed,
  }) {
    if (!isEn) {
      if (accountBoundaryPending) {
        return accountIsAvailable
            ? '账号数据已变更，请刷新提醒注册状态。'
            : '账号数据暂不可用，完成账号切换后再查看提醒。';
      }
      if (snapshotFailed) {
        return '读取提醒注册状态失败，可点击右上角或下方按钮重试。';
      }
      final missingHint = missingCount > 0
          ? ' 另有 $missingCount 条需重新保存，已放在“全部”和“需重新保存”里。'
          : '';
      return switch (filterName) {
        'current' =>
          '当前列表默认显示待触发/待确认的提醒。此状态反映系统队列记录或当前可确认情况；实际触发还取决于通知权限、闹钟权限和系统后台限制。$missingHint',
        'all' =>
          '全部显示提醒调度器登记的规则，也包括系统队列中查不到、需要重新保存的提醒。系统待触发=已交给系统；部分待触发=只确认到一部分；待确认=应用内/邮件或读取失败。',
        'queued' => '系统待触发：通知或闹钟有效编号组仍在系统待触发列表里，但是否响铃还取决于系统权限和渠道设置。',
        'partial' => '部分待触发：只确认到一部分提醒规则，多提醒时间或闹钟兜底可能只注册成功一部分，建议重新保存。',
        'missing' => '需重新保存：应用注册表有记录，但系统待触发列表查不到；仍需要提醒时请调整到未来时间后重新保存。',
        _ => '待确认：系统列表读取失败，或只有应用内弹出/邮件等通道；应用内弹出只在前台运行时展示。',
      };
    }
    if (accountBoundaryPending) {
      return accountIsAvailable
          ? 'Account data changed. Please refresh reminder registration status.'
          : 'Account data temporarily unavailable. Please finish account switch.';
    }
    if (snapshotFailed) {
      return 'Failed to load reminder registration status. Tap refresh or the button below to retry.';
    }
    final missingHint = missingCount > 0
        ? ' $missingCount more need resaving, listed under "All" and "Needs resaving".'
        : '';
    return switch (filterName) {
      'current' =>
        'Shows reminders pending trigger or confirmation by default. This reflects system queue records or current confirmed state. Actual delivery depends on notification, alarm, and background restrictions.$missingHint',
      'all' =>
        'Shows all rules in the reminder scheduler, including those missing from the system queue that need resaving. Queued = handed to system; Partially queued = partial match; Unconfirmed = in-app/email or probe failure.',
      'queued' =>
        'Queued in system: Notification or alarm IDs are present in system queue. Sounding depends on permissions and channel settings.',
      'partial' =>
        'Partially queued: Only part of reminder rules confirmed. Multiple times or alarm fallback may have succeeded partially. Resaving recommended.',
      'missing' =>
        'Needs resaving: Present in registry but missing from system queue. Adjust to future time and resave if still needed.',
      _ =>
        'Unconfirmed: System queue probe failed or channel is in-app pop-up / email. In-app pop-ups display only while app is in foreground.',
    };
  }

  static String registeredEmptyMessage({
    required String filterName,
    required int missingCount,
  }) {
    if (!isEn) {
      return switch (filterName) {
        'current' =>
          missingCount > 0
              ? '当前没有待触发/待确认的提醒；另有 $missingCount 条需重新保存'
              : '暂无待触发/待确认的提醒',
        'all' => '暂无已注册提醒',
        'queued' => '暂无系统待触发的提醒',
        'partial' => '暂无部分待触发的提醒',
        'missing' => '暂无需要重新保存的提醒',
        _ => '暂无待确认的提醒',
      };
    }
    return switch (filterName) {
      'current' =>
        missingCount > 0
            ? 'No pending or unconfirmed reminders. $missingCount need resaving'
            : 'No pending or unconfirmed reminders',
      'all' => 'No registered reminders',
      'queued' => 'No reminders queued in system',
      'partial' => 'No partially queued reminders',
      'missing' => 'No reminders needing resaving',
      _ => 'No unconfirmed reminders',
    };
  }

  static String get actionViewMissing =>
      isEn ? 'View items needing resave' : '查看需重新保存';
  static String get snapshotFailedMessage => isEn
      ? 'Failed to read reminder registration status. Please retry.'
      : '读取提醒注册状态失败，请重试。';
  static String get retryAction => isEn ? 'Retry' : '重试';

  static String reminderItemPrefix(String title) =>
      isEn ? 'Reminder: $title' : '提醒事项：$title';
  static String summaryPrefix(String subtitle) =>
      isEn ? 'Summary: $subtitle' : '简述：$subtitle';
  static String rulesRegisteredCount(int count) => isEn
      ? '$count registered reminder rules · Tap for diagnostics and suggestions'
      : '已登记 $count 条提醒规则 · 点开查看判断和处理建议';

  static String pagerFormat({
    required int pageSize,
    required int rangeStart,
    required int rangeEnd,
    required int total,
    required int currentPage,
    required int totalPages,
  }) => isEn
      ? '$pageSize per page · $rangeStart-$rangeEnd of $total · Page $currentPage of $totalPages'
      : '每页 $pageSize 条 · $rangeStart-$rangeEnd / $total · 第 $currentPage/$totalPages 页';

  static String get detailSheetRemoved => isEn
      ? 'This reminder is no longer in the registry. Please return and refresh.'
      : '这条提醒已不在当前注册表中，请返回后刷新列表。';
  static String get closeAction => isEn ? 'Close' : '关闭';

  static String get detailSheetSummary => isEn ? 'Summary' : '简述';
  static String get detailSheetCurrentDiagnostic =>
      isEn ? 'Current diagnostic' : '当前判断';
  static String get detailSheetRecommendation =>
      isEn ? 'Action advice' : '处理建议';
  static String get detailSheetSystemProbe => isEn ? 'System probe' : '系统检查';
  static String probeLabel(String probeStateName) {
    if (!isEn) {
      return switch (probeStateName) {
        'loading' => '正在读取系统待触发列表',
        'resolved' => '系统待触发列表已读取',
        _ => '系统待触发列表读取失败',
      };
    }
    return switch (probeStateName) {
      'loading' => 'Reading system pending queue',
      'resolved' => 'System pending queue read',
      _ => 'Failed to read system pending queue',
    };
  }

  static String get openObjectAction => isEn ? 'Open item' : '打开事项';
  static String get openObjectAndResaveAction =>
      isEn ? 'Open item and resave' : '打开事项并重新保存';

  static String get techDetailsTitle => isEn ? 'Technical details' : '技术详情';
  static String get techSourceObject => isEn ? 'Source object' : '来源对象';
  static String get techRegisteredIds => isEn ? 'Registered IDs' : '登记编号';
  static String get techEvaluationIds => isEn ? 'Evaluation ID sets' : '判定编号';
  static String get techSystemHits => isEn ? 'System hits' : '系统命中';
  static String get techMissingIds => isEn ? 'Missing IDs' : '未命中编号';

  static String techMissingIdsLabel({
    required List<int> missingIds,
    required bool acceptedBySystemQueue,
    required bool canCompareSystemQueue,
  }) {
    if (!canCompareSystemQueue) return isEn ? 'N/A' : '不适用';
    if (missingIds.isEmpty) return isEn ? 'None' : '无';
    final ids = idsPreview(missingIds);
    if (acceptedBySystemQueue) {
      return isEn
          ? 'Compatibility IDs not hit; does not affect evaluation: $ids'
          : '兼容编号未命中，不影响当前判断：$ids';
    }
    return ids;
  }

  static String acceptedIdSetsPreview(List<Set<int>> groups) {
    if (groups.isEmpty) {
      return isEn
          ? 'Not recorded; evaluating all registered IDs'
          : '未记录；按登记编号全量判断';
    }
    const visibleCount = 4;
    final visible = groups
        .take(visibleCount)
        .map((ids) {
          final sorted = ids.toList()..sort();
          return sorted.join('+');
        })
        .join(isEn ? '; ' : '；');
    if (groups.length <= visibleCount) return visible;
    return isEn
        ? '$visible etc. (${groups.length} groups)'
        : '$visible 等 ${groups.length} 组';
  }

  static String idsPreview(List<int> ids) {
    if (ids.isEmpty) return isEn ? 'None' : '无';
    final sorted = ids.toList()..sort();
    const visibleCount = 12;
    final visible = sorted.take(visibleCount).join(isEn ? ', ' : '、');
    if (sorted.length <= visibleCount) return visible;
    return isEn
        ? '$visible etc. (${sorted.length} items)'
        : '$visible 等 ${sorted.length} 个';
  }

  static String get channelStandardNotif =>
      isEn ? 'Standard notification' : '普通通知';
  static String get channelPopUp => isEn ? 'Pop-up' : '弹出框';
  static String get channelPopUpExplanation => isEn
      ? 'In-app pop-ups only display while the app is in the foreground and do not enter the system queue; background or lock screen requires standard notifications or alarm fallbacks.'
      : '应用内弹出只在应用前台运行时展示，不完全进入系统待触发队列；后台或锁屏需要普通通知或闹钟兜底。';
  static String get channelAlarm => isEn ? 'Alarm' : '闹钟';
  static String get channelEmail => isEn ? 'Email' : '邮件';
  static String get channelEmailExplanation => isEn
      ? 'Email reminders do not enter the local device system queue; presence in app registry only.'
      : '邮件提醒不进入本机系统待触发队列，这里只能确认应用注册表仍有记录。';

  static String systemChannelExplanation({
    required List<int> matchedIds,
    required List<int> missingIds,
    required bool acceptedBySystemQueue,
    required String probeStateName,
    required String suffix,
  }) {
    if (!isEn) {
      if (probeStateName == 'loading') {
        return '正在读取系统待触发列表。$suffix';
      }
      if (probeStateName == 'failed') {
        return '系统待触发列表读取失败，不能确认这条提醒是否仍在系统队列中。$suffix';
      }
      if (matchedIds.isEmpty) {
        return '系统队列没有查到这条提醒，若仍需要提醒，请调整到未来时间后重新保存。$suffix';
      }
      if (acceptedBySystemQueue) {
        if (missingIds.isEmpty) {
          return '系统队列已命中这条提醒的有效编号组。$suffix';
        }
        return '系统队列已命中这条提醒的有效编号组；未命中的登记编号多为重复规则、闹钟兜底或旧版兼容编号，不单独代表失效。$suffix';
      }
      if (missingIds.isEmpty) {
        return '系统队列已命中这条提醒的登记编号。$suffix';
      }
      return '系统队列只查到一部分规则；注册表无法进一步拆分缺失规则属于哪次提醒，建议重新保存对应提醒。$suffix';
    }
    if (probeStateName == 'loading') {
      return 'Reading system pending queue. $suffix';
    }
    if (probeStateName == 'failed') {
      return 'Failed to read system queue; cannot confirm if this reminder remains in the system queue. $suffix';
    }
    if (matchedIds.isEmpty) {
      return 'Reminder not found in system queue. If still needed, adjust time to the future and resave. $suffix';
    }
    if (acceptedBySystemQueue) {
      if (missingIds.isEmpty) {
        return 'System queue matched the active ID group for this reminder. $suffix';
      }
      return 'System queue matched the active ID group for this reminder; unhit registered IDs are likely repeat rules, alarm fallbacks, or legacy compatibility IDs. $suffix';
    }
    if (missingIds.isEmpty) {
      return 'System queue matched all registered IDs for this reminder. $suffix';
    }
    return 'System queue matched only part of the rules; resaving this reminder is recommended. $suffix';
  }

  static String get channelPushSuffix => isEn
      ? 'Requires system notification permission and active channels. Queued only confirms delivery to system queue.'
      : '需要系统通知权限和通知渠道正常开启；系统待触发只表示已交给系统队列。';
  static String get channelAlarmSuffix => isEn
      ? 'Requires notification, exact alarm, and full-screen permissions; lock screen display is subject to system background restrictions.'
      : '需要通知权限、精准闹钟和全屏提醒权限；锁屏弹出还受系统后台限制影响。';

  static String registeredReminderTypeLabel(String objectType) {
    if (!isEn) {
      return switch (objectType) {
        'todo' => '待办',
        'goal' => '目标',
        'habit' => '习惯',
        'anniversary' => '纪念日',
        'countdown' => '倒数日',
        'course' => '课程',
        'note' => '随手记',
        'diary' => '日记',
        _ => objectType,
      };
    }
    return switch (objectType) {
      'todo' => 'Task',
      'goal' => 'Goal',
      'habit' => 'Habit',
      'anniversary' => 'Anniversary',
      'countdown' => 'Countdown',
      'course' => 'Course',
      'note' => 'Note',
      'diary' => 'Diary',
      _ => objectType,
    };
  }

  static String unSyncedReminderTitle(String typeLabel) =>
      isEn ? '$typeLabel reminder (title not synced)' : '$typeLabel提醒（标题未同步）';
  static String unSyncedReminderSubtitle(String typeLabel) => isEn
      ? '$typeLabel · Reminder rule not synced; refresh or resave item'
      : '$typeLabel · 提醒规则暂未同步，可刷新或重新保存对应事项';

  // 铃声设置反馈
  static String get ringtoneVolumeSuccess =>
      isEn ? 'Volume updated, playing preview' : '已切换音量并开始试听';
  static String ringtoneSoundSuccess(String label) =>
      isEn ? 'Switched to $label, playing preview' : '已切换为 $label，并开始试听';
  static String get ringtonePreviewing =>
      isEn ? 'Playing current reminder sound preview' : '正在试听当前提醒铃声';
  static String get previewSoundTooltip =>
      isEn ? 'Preview reminder sound' : '试听当前铃声';

  // 报告推送设置 (Report Reminders Section)
  static String get reportRemindersTitle =>
      isEn ? 'Report Notifications' : '报告推送';
  static String get reportRemindersSubtitle => isEn
      ? 'Reminds you to review daily reviews, weekly reports, monthly reports, and annual summaries'
      : '按你的节奏提醒查看每日复盘、周报、月报和年报';
  static String get reportDailyTitle =>
      isEn ? 'Daily Productivity Review' : '每日效率复盘';
  static String get reportWeeklyTitle =>
      isEn ? 'Weekly Productivity Report' : '每周效率周报';
  static String get reportMonthlyTitle =>
      isEn ? 'Monthly Growth Report' : '每月成长月报';
  static String get reportYearlyTitle =>
      isEn ? 'Annual Growth Report' : '每年成长年报';

  static String reportCadenceDaily(String time) =>
      isEn ? 'Daily $time' : '每天 $time';
  static String reportCadenceWeekly(String weekday, String time) =>
      isEn ? 'Every $weekday $time' : '每$weekday $time';
  static String reportCadenceMonthly(int day, String time) =>
      isEn ? 'Monthly on day $day $time' : '每月 $day 日 $time';
  static String reportCadenceYearly(int month, int day, String time) => isEn
      ? 'Yearly on month $month, day $day $time'
      : '每年 $month 月 $day 日 $time';

  static String get reportDynamicSummary => isEn ? 'Dynamic summary' : '动态摘要';
  static String get reportOff => isEn ? 'Off' : '已关闭';
  static String get reportNotificationTime =>
      isEn ? 'Notification Time' : '推送时间';

  static String get reportTimeDailySubtitle => isEn
      ? 'Sends dynamic summary of today’s report at scheduled time'
      : '到点推送今天报告动态摘要';
  static String get reportTimeWeeklySubtitle => isEn
      ? 'Sends dynamic summary of last week’s report at scheduled time'
      : '到点推送上一周报告动态摘要';
  static String get reportTimeMonthlySubtitle => isEn
      ? 'Sends dynamic summary of last month’s report at scheduled time'
      : '到点推送上月报告动态摘要';
  static String get reportTimeYearlySubtitle => isEn
      ? 'Sends dynamic summary of last year’s report at scheduled time'
      : '到点推送上一年报告动态摘要';

  static String reportPickerTitle(String title) =>
      isEn ? '$title Notification Time' : '$title推送时间';
  static String get reportPickerSubtitle => isEn
      ? 'Updating will reschedule the next report notification'
      : '修改后会重排下一次报告通知';

  static String monthChipLabel(int month) => isEn ? 'Month $month' : '$month 月';
  static String dayChipLabel(int day) => isEn ? 'Day $day' : '$day 日';
}
