import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'startup keeps heavy reload sync notification and widget work staggered',
    () {
      final main = File('lib/main.dart').readAsStringSync();

      expect(main, contains('Future<void> _runStartupIdleQueue('));
      expect(main, contains('Future<void> _runStartupStaggeredTask('));
      expect(main, contains('Future<void> _runSyncReloadTasksInBatches('));
      expect(
        main,
        isNot(contains('Future<void> ensureNotificationLaunchStartup()')),
        reason: '启动阶段不能再完整初始化通知和闹钟渠道，避免冷启动抢首屏。',
      );
      expect(
        main,
        isNot(contains('unawaited(ensureNotificationLaunchStartup())')),
      );
      expect(
        main,
        contains('LocalNotifications.instance.initForLaunchPayload()'),
      );
      expect(main, contains('AlarmService.instance.initForLaunchPayload()'));
      expect(main, contains('Future<void> ensureHomeWidgetLaunchStartup()'));
      expect(main, contains('await _yieldForNextFrame();'));
      expect(main, contains("'deferred local storage'"));
      expect(main, contains("'deferred platform services'"));
      expect(main, contains("'startup notification launch payloads'"));
      expect(main, contains("'startup deep links'"));
      expect(main, contains("'home widget initial launch'"));
      expect(main, contains("'server config refresh'"));
      expect(main, contains("'auth profile refresh'"));
      expect(main, contains("'notification quick add'"));
      expect(main, contains("'initial home widget push'"));
      expect(main, contains('initialDelay: const Duration(seconds: 75)'));
      expect(main, contains('gap: const Duration(seconds: 12)'));
      expect(
        main,
        contains('const Duration(seconds: 14)'),
        reason: '首帧后的延迟本地加载不能和首屏渲染立即抢资源。',
      );
      expect(main, contains('delay: const Duration(milliseconds: 2400)'));
      expect(main, contains('delay: const Duration(milliseconds: 1100)'));
      expect(main, contains('delay: const Duration(seconds: 8)'));
      expect(main, contains('delay: const Duration(seconds: 65)'));
      expect(
        main,
        contains('Future<void>.delayed(const Duration(seconds: 90)'),
      );
      expect(main, contains('queueStartupReminderResync('));
      expect(
        main,
        contains('delay: const Duration(seconds: 3)'),
        reason: '已登录冷启动要尽早重建前台 popup 计时器和闹钟队列，避免 1 分钟提醒漏触发。',
      );
      final reminderResync = main.substring(
        main.indexOf('Future<void> resyncReminders() async'),
        main.indexOf('Future<void> queueFullReminderResync'),
      );
      expect(
        RegExp(
          r"await _yieldForNextFrame\(const Duration\(milliseconds: 16\)\);",
        ).allMatches(reminderResync).length,
        greaterThanOrEqualTo(5),
        reason: '登录后完整提醒重放要分段让出帧，避免 Mine 首屏滚动被调度循环卡住。',
      );
      expect(main, contains('? const Duration(seconds: 120)'));
      expect(main, contains('Duration cloudSyncDelayAfterAuth({'));
      expect(main, contains('if (cloudSyncProvider.hasPendingChanges)'));
      expect(main, contains('return const Duration(milliseconds: 900);'));
      expect(
        main,
        contains('delay: cloudSyncDelayAfterAuth(initialStartup: true)'),
      );
      expect(
        main,
        contains('delay: cloudSyncDelayAfterAuth(initialStartup: false)'),
      );
      final startupTasks = main.substring(
        main.indexOf('Future<void> runPostFrameStartupTasks() async'),
        main.indexOf('// 首屏关键配置已完成'),
      );
      expect(
        startupTasks,
        isNot(contains('Duration(seconds: 30)')),
        reason: '30 秒附近不能再启动重型同步、通知或小组件任务。',
      );
      expect(
        startupTasks,
        contains(
          'if (initialNotificationPayloads.isNotEmpty) {\n'
          '            await ensureReminderProvidersStartup();\n'
          '          }\n'
          '          for (final payload in initialNotificationPayloads.toSet()',
        ),
        reason: '冷启动通知 action 必须在提醒 Provider hydration 后再派发。',
      );
      expect(main, contains('achievementProvider.resumeUnlockFeedback'));
      expect(main, contains('Timer(const Duration(milliseconds: 2200)'));
      expect(
        main,
        contains('const homeWidgetPushMinInterval = Duration(seconds: 8)'),
        reason: '登录和同步恢复的连续 provider 变化需要合并小组件推送，避免短时间多次刷新。',
      );
      expect(main, contains('Timer? userStatsRefreshDebounce'));
      expect(main, contains('void refreshUserStatsNow()'));
      expect(main, contains('void queueUserStatsRefresh({'));
      expect(
        main,
        contains('Duration delay = const Duration(milliseconds: 700)'),
        reason: '登录同步恢复会连续触发 todo/habit/pomodoro notify，用户统计要合并后再扫集合。',
      );
      expect(main, contains('todoProvider.addListener(queueUserStatsRefresh)'));
      expect(
        main,
        contains('habitProvider.addListener(queueUserStatsRefresh)'),
      );
      expect(
        main,
        contains('userStatsRefreshDebounce?.cancel();'),
        reason: '用户统计刷新必须防抖，避免 Mine 刚进入时被多次同步写入打断滚动。',
      );
      expect(main, contains('DateTime? lastHomeWidgetPushStartedAt'));
      expect(
        main,
        contains('scheduleHomeWidgetPushDebounce(homeWidgetPushDelay(),'),
      );
      expect(main, contains('var homeWidgetPushInFlight = false'));
      expect(main, contains('homeWidgetPushQueued = true'));
      expect(main, contains('String lastHomeWidgetDataSignature = \'\';'));
      expect(main, contains('String homeWidgetDataRevisionSignature()'));
      expect(main, contains('_homeWidgetDataRevisionSignature('));
      final widgetDataSignatureStart = main.indexOf(
        'String _homeWidgetDataRevisionSignature(',
      );
      final widgetDataSignatureEnd = main.indexOf(
        '\nint _homeWidgetTodoRevision(',
        widgetDataSignatureStart,
      );
      expect(widgetDataSignatureStart, greaterThanOrEqualTo(0));
      expect(widgetDataSignatureEnd, greaterThan(widgetDataSignatureStart));
      final widgetDataSignature = main.substring(
        widgetDataSignatureStart,
        widgetDataSignatureEnd,
      );
      expect(widgetDataSignature, contains('now.timeZoneOffset.inMinutes'));
      expect(widgetDataSignature, contains('I18n.current.name'));
      final localeListenerStart = main.indexOf(
        '  localeProvider.addListener(() {',
      );
      final localeListenerEnd = main.indexOf('\n  });', localeListenerStart);
      expect(localeListenerStart, greaterThanOrEqualTo(0));
      expect(localeListenerEnd, greaterThan(localeListenerStart));
      final localeListener = main.substring(
        localeListenerStart,
        localeListenerEnd,
      );
      expect(localeListener, contains('queueHomeWidgetPush();'));
      expect(
        main,
        contains('if (dataSignature != lastHomeWidgetDataSignature)'),
        reason: '登录和同步恢复会连续触发多个 provider notify，小组件应先做轻量数据签名去重。',
      );
      expect(
        main,
        contains('lastHomeWidgetDataSignature = \'\';'),
        reason: '小组件推送失败后必须允许下一次相同数据重试。',
      );
      expect(
        main,
        contains(
          'Object.hashAll(provider.events.map(_homeWidgetCalendarEventRevision))',
        ),
        reason: '签名需要覆盖外部日历源变化，但不能进入 buildEventsForDateSnapshot 重建。',
      );
      final homeWidgetService = File(
        'lib/services/home_widget_service.dart',
      ).readAsStringSync();
      expect(homeWidgetService, contains('_lastSavedPayloadValues'));
      expect(
        homeWidgetService,
        contains('Future<_HomeWidgetPayloadSaveResult> _saveWidgetPayload('),
      );
      expect(
        homeWidgetService,
        contains(
          'if (!force && _lastSavedPayloadValues[entry.key] == entry.value)',
        ),
        reason: '小组件数据推送必须按 key 跳过未变化值，避免登录后全量写平台通道。',
      );
      expect(homeWidgetService, contains('...theme.payloadValues'));
      expect(homeWidgetService, contains('_lastSavedPayloadValues.clear();'));
      final homeWidgetEvents = main.substring(
        main.indexOf('List<CalendarEvent> _homeWidgetEventsForToday('),
        main.indexOf('String _homeWidgetEventLabel('),
      );
      expect(
        homeWidgetEvents,
        contains('calendar.buildEventsForDateSnapshot('),
      );
      expect(
        homeWidgetEvents,
        isNot(contains('calendar.rebuild(')),
        reason: '小组件刷新不能修改 CalendarProvider 状态，否则登录后数据恢复会拖慢 Mine 滚动。',
      );
      expect(main, contains('var deferredLocalStorageHydrated = false'));
      expect(main, contains('deferredLocalStorageHydrated = true'));
      expect(main, contains('if (!deferredLocalStorageHydrated) return;'));
      expect(main, contains('bool allowBeforeDeferredHydration = false'));
      expect(main, contains('typedef _MainShellPreferencesSlice'));
      expect(main, contains('.select<PreferencesProvider,'));
      expect(main, contains('_MainShellPreferencesSlice>((provider)'));
      expect(main, isNot(contains('context.watch<PreferencesProvider>()')));
      expect(main, contains('queueNotificationQuickAddSync();'));
      expect(main, contains('withoutLoadingNotification('));
      expect(main, contains('() => shareProvider.load(force: true)'));
      expect(main, contains('shareProvider.load(notifyLoading: false)'));

      final shareProvider = File(
        'lib/providers/share_provider.dart',
      ).readAsStringSync();
      expect(shareProvider, contains('bool notifyLoading = true'));
      expect(
        shareProvider,
        contains('Future<T> withoutLoadingNotification<T>'),
      );
      expect(shareProvider, contains('final shouldNotify ='));
      expect(
        shareProvider,
        contains(
          'beforeWorkspacesRevision != _workspaceListRevision(_workspaces)',
        ),
      );
      expect(
        shareProvider,
        contains('beforeMentionsRevision != _mentionListRevision(_mentions)'),
      );

      final diaryProvider = File(
        'lib/providers/diary_provider.dart',
      ).readAsStringSync();
      expect(diaryProvider, contains('List<DiaryEntry>? _sortedEntriesCache'));
      expect(
        diaryProvider,
        contains('Map<String, DiaryEntry>? _entriesByDateCache'),
      );
      expect(diaryProvider, contains('void _invalidateCaches()'));
      expect(
        diaryProvider,
        isNot(contains('_entries..sort')),
        reason: 'Mine/统计/日历读取日记时不能在 getter 内原地排序，否则登录同步恢复会放大滚动卡顿。',
      );

      final localNotifications = File(
        'lib/services/local_notifications_io.dart',
      ).readAsStringSync();
      expect(
        localNotifications,
        contains('Future<void> initForLaunchPayload() async'),
      );
      expect(localNotifications, contains('await _ensurePluginInitialized();'));
      expect(localNotifications, contains('await _probeLaunchPayload();'));

      final alarmService = File(
        'lib/services/alarm_service.dart',
      ).readAsStringSync();
      expect(
        alarmService,
        contains('Future<void> initForLaunchPayload() async'),
      );
      expect(alarmService, contains('await _ensurePluginInitialized();'));
      expect(alarmService, contains('await _probeLaunchPayload();'));

      final background = File(
        'lib/widgets/brand_background.dart',
      ).readAsStringSync();
      expect(background, contains('LayoutBuilder('));
      expect(background, contains('MediaQuery.devicePixelRatioOf(context)'));
      expect(background, contains('cacheWidth: cacheWidth'));
      expect(background, contains('cacheHeight: cacheHeight'));

      final cachedAvatar = File(
        'lib/widgets/cached_avatar_image.dart',
      ).readAsStringSync();
      expect(
        cachedAvatar,
        contains('cacheWidth: _decodePixels(context, widget.width)'),
      );
      expect(
        cachedAvatar,
        contains('cacheHeight: _decodePixels(context, widget.height)'),
      );
      expect(
        cachedAvatar,
        contains('static Future<Directory>? _cacheRootFuture'),
      );
      expect(cachedAvatar, isNot(contains("package:http/http.dart")));
      expect(cachedAvatar, isNot(contains('http.get(')));
      expect(cachedAvatar, isNot(contains('frameBuilder:')));
      final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
      expect(
        mine,
        contains('body: ListView.builder('),
        reason: 'Mine 页菜单较多，登录态刷新时必须懒构建可见项，避免整页同步重建拖慢滚动。',
      );
      expect(mine, contains('itemBuilder: (context, index)'));
      expect(
        mine,
        contains(
          'final avatarPixels = _avatarDecodePixels(context, radius * 2)',
        ),
      );
      expect(mine, contains('cacheWidth: avatarPixels'));
      expect(mine, contains('cacheHeight: avatarPixels'));

      final notificationSettings = File(
        'lib/screens/notification_history_screen.dart',
      ).readAsStringSync();
      expect(
        notificationSettings,
        contains("key: const ValueKey('notification_settings_scroll_view')"),
      );
      expect(notificationSettings, contains('CustomScrollView('));
      expect(notificationSettings, contains('SliverSafeArea('));
      expect(notificationSettings, contains('通知状态读取失败，请稍后重试或打开系统通知设置检查。'));
      expect(
        main,
        isNot(contains('_builtTabs.contains(tab) && tab == safeIndex')),
        reason: '已访问底部 tab 必须保留挂载，避免返回日历/习惯/专注时整页重建。',
      );
    },
  );
}
