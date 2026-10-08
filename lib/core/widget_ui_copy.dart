/// Duoyi widget screen and preview UI localization strings (Task: iOS style & i18n).
library;

import '../services/android_widget_manager.dart';
import 'i18n.dart';
import 'i18n_date_format.dart';

enum WidgetCategory { all, productivity, life }

enum WidgetPreviewKind {
  todo,
  focus,
  habit,
  calendar,
  schedule,
  goal,
  course,
  note,
  anniversary,
  diary,
}

class WidgetUiCopy {
  WidgetUiCopy._();

  static bool get isZh => I18n.current == AppLocale.zh;

  // Screen header & control strings
  static String get screenTitle => isZh ? '小组件' : 'Widgets';
  static String get refreshTooltip => isZh ? '刷新小组件' : 'Refresh widgets';
  static String get previewHeaderTitle =>
      isZh ? '桌面小组件预览' : 'Home Screen Widget Preview';
  static String get stylePanelTitle => isZh ? '小组件样式' : 'Widget Style';

  // Category labels
  static String categoryLabel(WidgetCategory category) {
    return switch (I18n.current) {
      AppLocale.en => switch (category) {
        WidgetCategory.all => 'All',
        WidgetCategory.productivity => 'Productivity',
        WidgetCategory.life => 'Lifestyle',
      },
      AppLocale.zh => switch (category) {
        WidgetCategory.all => '全部',
        WidgetCategory.productivity => '效率',
        WidgetCategory.life => '生活',
      },
    };
  }

  // Catalog item titles
  static String catalogTitle(DuoyiWidgetKind kind) {
    return switch (I18n.current) {
      AppLocale.en => switch (kind) {
        DuoyiWidgetKind.todo => 'Today’s tasks',
        DuoyiWidgetKind.focus => 'Focus',
        DuoyiWidgetKind.habit => 'Habits',
        DuoyiWidgetKind.calendar => 'Calendar',
        DuoyiWidgetKind.schedule => 'Today’s schedule',
        DuoyiWidgetKind.goal => 'Goals',
        DuoyiWidgetKind.course => 'Timetable',
        DuoyiWidgetKind.note => 'Quick Notes',
        DuoyiWidgetKind.anniversary => 'Anniversaries',
        DuoyiWidgetKind.diary => 'Diary',
      },
      AppLocale.zh => switch (kind) {
        DuoyiWidgetKind.todo => '今日待办',
        DuoyiWidgetKind.focus => '专注',
        DuoyiWidgetKind.habit => '习惯',
        DuoyiWidgetKind.calendar => '月历',
        DuoyiWidgetKind.schedule => '今日日程',
        DuoyiWidgetKind.goal => '目标',
        DuoyiWidgetKind.course => '课程表',
        DuoyiWidgetKind.note => '随手记',
        DuoyiWidgetKind.anniversary => '纪念日',
        DuoyiWidgetKind.diary => '日记',
      },
    };
  }

  // Catalog item subtitles
  static String catalogSubtitle(DuoyiWidgetKind kind) {
    return switch (I18n.current) {
      AppLocale.en => switch (kind) {
        DuoyiWidgetKind.todo =>
          'View and complete todos on home screen with quick capture',
        DuoyiWidgetKind.focus =>
          'Show today focus sessions, duration, and next plan',
        DuoyiWidgetKind.habit =>
          'Track today completion rate, streaks, and quick check-in',
        DuoyiWidgetKind.calendar => 'Monthly overview with today indicator',
        DuoyiWidgetKind.schedule =>
          'View today schedule items ordered chronologically',
        DuoyiWidgetKind.goal => 'Show active goals and progress status',
        DuoyiWidgetKind.course =>
          'Show today class periods, classrooms, and times',
        DuoyiWidgetKind.note => 'View recently updated memos and quick notes',
        DuoyiWidgetKind.anniversary =>
          'Count down important days and track total days',
        DuoyiWidgetKind.diary =>
          'Review recent mood entries and diary snippets',
      },
      AppLocale.zh => switch (kind) {
        DuoyiWidgetKind.todo => '桌面查看与完成待办，支持快速记一笔',
        DuoyiWidgetKind.focus => '展示今日专注次数、时长与下一轮计划',
        DuoyiWidgetKind.habit => '查看今日完成率、连续记录与快捷打卡',
        DuoyiWidgetKind.calendar => '月视图概览与今日标记',
        DuoyiWidgetKind.schedule => '查看今日按时间排序的日程安排',
        DuoyiWidgetKind.goal => '展示当前目标与推进进度',
        DuoyiWidgetKind.course => '展示今日课程节次、教室与时间',
        DuoyiWidgetKind.note => '查看最近更新的便签与随手记',
        DuoyiWidgetKind.anniversary => '倒数重要日子与累计天数',
        DuoyiWidgetKind.diary => '回顾最近记录的心情与日记摘要',
      },
    };
  }

  // Display mode labels & descriptions
  static String displayModeLabel(String id) {
    return switch (I18n.current) {
      AppLocale.en => switch (id) {
        'compact' => 'Compact',
        'detailed' => 'Detailed',
        _ => 'Standard',
      },
      AppLocale.zh => switch (id) {
        'compact' => '紧凑',
        'detailed' => '详细',
        _ => '标准',
      },
    };
  }

  static String displayModeDescription(String id) {
    return switch (I18n.current) {
      AppLocale.en => switch (id) {
        'compact' =>
          'Compact size showing one key line. Long press on home screen to resize.',
        'detailed' =>
          'Detailed size showing three lines. Long press on home screen to resize.',
        _ =>
          'Standard size showing two lines. Long press on home screen to resize.',
      },
      AppLocale.zh => switch (id) {
        'compact' => '紧凑尺寸，展示核心一行内容，长按桌面可调整大小',
        'detailed' => '详细尺寸，展示三行内容，长按桌面可调整大小',
        _ => '标准尺寸，展示两行内容，长按桌面可调整大小',
      },
    };
  }

  // SnackBar / feedback messages
  static String get styleSyncFailed => isZh
      ? '桌面小组件样式同步失败，请重试'
      : 'Failed to sync widget style to home screen. Please retry.';
  static String get actionRetry => isZh ? '重试' : 'Retry';
  static String styleSyncSuccess(String modeLabel) => isZh
      ? '小组件样式已设为$modeLabel。长按桌面小组件可调整大小。'
      : 'Widget style set to $modeLabel. Long press home screen widget to resize.';
  static String get cannotOpenSettings => isZh
      ? '无法打开应用设置，请手动进入系统设置检查多仪权限'
      : 'Unable to open app settings. Please check Duoyi permissions in system settings.';
  static String get refreshSuccess => isZh ? '小组件已刷新' : 'Widgets refreshed';
  static String get refreshFailed =>
      isZh ? '刷新失败，请稍后重试' : 'Failed to refresh. Please try again later.';

  // Pin support banner
  static String get pinSupportCheckingTitle =>
      isZh ? '正在检查桌面小组件支持' : 'Checking home screen widget support';
  static String get pinSupportCheckingMessage => isZh
      ? '正在检测当前桌面是否支持直接添加小组件。'
      : 'Checking whether current launcher supports adding widgets directly.';
  static String get pinSupportSupportedTitle =>
      isZh ? '当前桌面支持应用内添加' : 'Current launcher supports adding from app';
  static String get pinSupportSupportedMessage => isZh
      ? '可直接添加到桌面，添加后需系统弹窗确认；长按桌面小组件可调整大小。'
      : 'Add directly to home screen with system confirmation dialog. Long press to resize.';

  static String pinSupportResultTitle(AndroidWidgetPinResult? support) {
    return switch (I18n.current) {
      AppLocale.en => switch (support) {
        AndroidWidgetPinResult.unsupportedPlatform =>
          'Platform does not support in-app pinning',
        AndroidWidgetPinResult.unsupportedLauncher =>
          'Current launcher does not support in-app pinning',
        AndroidWidgetPinResult.permissionDenied =>
          'Home screen permission denied',
        AndroidWidgetPinResult.confirmationBlocked =>
          'Confirmation dialog may be blocked',
        AndroidWidgetPinResult.invalidKind => 'Widget kind cannot be pinned',
        _ => 'Current launcher may not support in-app pinning',
      },
      AppLocale.zh => switch (support) {
        AndroidWidgetPinResult.unsupportedPlatform => '当前平台不支持应用内添加',
        AndroidWidgetPinResult.unsupportedLauncher => '当前桌面不支持应用内添加',
        AndroidWidgetPinResult.permissionDenied => '桌面添加权限未通过',
        AndroidWidgetPinResult.confirmationBlocked => '桌面确认弹窗可能被拦截',
        AndroidWidgetPinResult.invalidKind => '当前小组件类型不可添加',
        _ => '当前桌面可能不支持应用内添加',
      },
    };
  }

  static String pinSupportResultMessage(AndroidWidgetPinResult? support) {
    return switch (I18n.current) {
      AppLocale.en => switch (support) {
        AndroidWidgetPinResult.unsupportedPlatform =>
          'Please add Duoyi via the system widget picker on Android.',
        AndroidWidgetPinResult.unsupportedLauncher =>
          'Current launcher has not enabled in-app pinning. Please add from system widget picker.',
        AndroidWidgetPinResult.permissionDenied =>
          'System did not allow Duoyi to add widgets. Enable permission in settings and retry.',
        AndroidWidgetPinResult.confirmationBlocked =>
          'Confirmation dialog may be blocked. Please check background pop-up permissions.',
        AndroidWidgetPinResult.invalidKind =>
          'Please update the app and retry.',
        _ =>
          'If no dialog appears, check widget and pop-up permissions in system settings, or add via system widget picker.',
      },
      AppLocale.zh => switch (support) {
        AndroidWidgetPinResult.unsupportedPlatform =>
          '请在 Android 手机上通过系统小组件列表添加多仪。',
        AndroidWidgetPinResult.unsupportedLauncher =>
          '当前桌面启动器未开放应用内添加，请从系统小组件列表选择添加。',
        AndroidWidgetPinResult.permissionDenied =>
          '系统未允许多仪添加桌面小组件，请在系统设置中开启权限后重试。',
        AndroidWidgetPinResult.confirmationBlocked =>
          '桌面确认弹窗可能被拦截，请检查后台弹窗或悬浮窗权限后重试。',
        AndroidWidgetPinResult.invalidKind => '请更新应用后重试。',
        _ => '若未弹出确认框，请打开系统设置检查桌面小组件与后台弹窗权限，或从系统小组件列表添加。',
      },
    };
  }

  static String get actionAppSettings => isZh ? '应用设置' : 'App Settings';
  static String get actionRecheck => isZh ? '重新检测' : 'Recheck';
  static String get actionOpenPermissions =>
      isZh ? '打开权限设置' : 'Open Permissions';
  static String get actionGotIt => isZh ? '知道了' : 'Got It';
  static String get addDialogTitle => isZh ? '添加到桌面' : 'Add to Home Screen';

  // Help messages for AndroidWidgetPinResult
  static String pinHelpMessage(AndroidWidgetPinResult result) {
    return switch (I18n.current) {
      AppLocale.en => switch (result) {
        AndroidWidgetPinResult.unsupported =>
          'Current launcher does not support direct pinning. Long press an empty area on your home screen to add from the widget picker.',
        AndroidWidgetPinResult.unsupportedPlatform =>
          'Current platform does not support adding Android widgets. Please add Duoyi from the system widget picker on Android.',
        AndroidWidgetPinResult.unsupportedLauncher =>
          'Current launcher has not enabled in-app pinning. Long press an empty area on home screen to add from widget picker.',
        AndroidWidgetPinResult.permissionDenied =>
          'System did not allow Duoyi to add widgets. Enable permission in system settings and retry, or add from widget picker.',
        AndroidWidgetPinResult.confirmationBlocked =>
          'System confirmation dialog may be blocked. Please check background pop-up permissions.',
        AndroidWidgetPinResult.invalidKind =>
          'This widget type is not supported yet. Update the app and try again.',
        AndroidWidgetPinResult.unavailable =>
          'Failed to send request. Check home screen permissions and retry, or add from widget picker.',
        AndroidWidgetPinResult.requested =>
          'Pin request initiated. Please confirm in the system dialog.',
      },
      AppLocale.zh => switch (result) {
        AndroidWidgetPinResult.unsupported =>
          '当前桌面不支持应用内直接添加小组件。请长按桌面空白处，从系统小组件列表添加。',
        AndroidWidgetPinResult.unsupportedPlatform =>
          '当前平台不支持直接添加 Android 桌面小组件。请在 Android 手机上从系统小组件列表添加多仪。',
        AndroidWidgetPinResult.unsupportedLauncher =>
          '当前桌面启动器未开放应用内添加，请长按桌面空白处从系统小组件列表添加。',
        AndroidWidgetPinResult.permissionDenied =>
          '系统未允许多仪添加桌面小组件。请在系统设置中开启权限后重试，或从系统小组件列表添加。',
        AndroidWidgetPinResult.confirmationBlocked =>
          '系统确认弹窗可能被拦截，请检查后台弹窗或悬浮窗权限后重试。',
        AndroidWidgetPinResult.invalidKind => '当前小组件类型暂不支持添加，请更新应用后重试。',
        AndroidWidgetPinResult.unavailable =>
          '无法发起添加请求，请检查桌面权限后重试，或从系统小组件列表添加。',
        AndroidWidgetPinResult.requested => '已发起添加请求，请在桌面系统弹窗中确认。',
      },
    };
  }

  // Pin confirmation failures
  static (String title, String message) pinConfirmationFailure(
    AndroidWidgetPinFinalStatus status,
  ) {
    return switch (I18n.current) {
      AppLocale.en => switch (status) {
        AndroidWidgetPinFinalStatus.invalidWidgetId => (
          'Addition Incomplete',
          'Widget was not created on home screen. Retry or add from system widget picker.',
        ),
        AndroidWidgetPinFinalStatus.timeout => (
          'Awaiting Confirmation',
          'Request sent, but system confirmation not received. Check home screen for dialog or verify permissions.',
        ),
        AndroidWidgetPinFinalStatus.unavailable => (
          'Addition Error',
          'No result returned by launcher. Retry or add from system widget picker.',
        ),
        AndroidWidgetPinFinalStatus.success => (
          'Added',
          'Home screen widget added.',
        ),
      },
      AppLocale.zh => switch (status) {
        AndroidWidgetPinFinalStatus.invalidWidgetId => (
          '添加未完成',
          '桌面未成功创建小组件，请重试或从系统小组件列表添加。',
        ),
        AndroidWidgetPinFinalStatus.timeout => (
          '等待桌面确认',
          '已发起添加请求，但尚未收到系统确认。请查看桌面是否有确认弹窗，或在系统设置中检查权限。',
        ),
        AndroidWidgetPinFinalStatus.unavailable => (
          '添加异常',
          '桌面未返回添加结果。请重试或从系统小组件列表添加。',
        ),
        AndroidWidgetPinFinalStatus.success => ('已添加', '桌面小组件已添加。'),
      },
    };
  }

  // Add button labels
  static String get checkingDesktopSupport =>
      isZh ? '正在检查桌面支持' : 'Checking support';
  static String pinDisabledAction(AndroidWidgetPinResult? support) {
    return switch (I18n.current) {
      AppLocale.en => switch (support) {
        AndroidWidgetPinResult.unsupportedPlatform =>
          'In-app pin is Android only',
        AndroidWidgetPinResult.unsupportedLauncher =>
          'Add via system widget picker',
        _ => 'View Pin Help',
      },
      AppLocale.zh => switch (support) {
        AndroidWidgetPinResult.unsupportedPlatform => '仅 Android 支持应用内添加',
        AndroidWidgetPinResult.unsupportedLauncher => '请从系统小组件列表添加',
        _ => '查看添加帮助',
      },
    };
  }

  static String get requestingAdd => isZh ? '正在请求添加' : 'Requesting...';
  static String addWidgetButtonLabel({
    required String modeLabel,
    required String launcherRequestLabel,
  }) {
    return isZh
        ? '添加$modeLabel $launcherRequestLabel'
        : 'Add $modeLabel $launcherRequestLabel';
  }

  static String pinInitiatedSnackBar(String modeLabel) => isZh
      ? '已发起添加，请在系统弹窗中确认添加$modeLabel小组件。长按桌面可调整大小。'
      : 'Request sent. Please confirm adding the $modeLabel widget in the system dialog. Long press to resize.';

  static String pinSuccessSnackBar(String modeLabel) =>
      isZh ? '已添加$modeLabel小组件到桌面。' : 'Added $modeLabel widget to home screen.';

  // Tips banner
  static String get widgetTipsBannerTitle =>
      isZh ? '桌面小组件使用提示' : 'Home Screen Widget Tips';
  static String get widgetTipsBannerMessage => isZh
      ? '长按桌面小组件可调整大小。添加小组件需系统弹窗确认；若未弹出确认框，请打开系统设置检查多仪的桌面小组件权限。'
      : 'Long press widgets on the home screen to resize. Adding widgets requires system confirmation; if no dialog appears, check Duoyi permissions in system settings.';

  // Desktop web fallback
  static String get desktopWebTitle => isZh ? '电脑网页版显示日历' : 'Web Calendar View';
  static String get desktopWebMessage => isZh
      ? '桌面小组件依赖 Android 或 iOS 系统；电脑网页版默认隐藏小组件入口，保留月历预览和日历入口。'
      : 'Home screen widgets require Android or iOS. Web desktop hides widget pinning and preserves monthly calendar preview and entry.';
  static String get desktopWebTileSubtitle => isZh
      ? '电脑网页版默认展示日历，不显示添加桌面小组件按钮'
      : 'Web desktop displays calendar by default without widget pin controls';
  static String get desktopWebOpenCalendar => isZh ? '打开日历' : 'Open Calendar';

  // Preview card titles
  static String previewTitle(WidgetPreviewKind kind) {
    return switch (I18n.current) {
      AppLocale.en => switch (kind) {
        WidgetPreviewKind.todo => 'Tasks',
        WidgetPreviewKind.focus => 'Focus',
        WidgetPreviewKind.habit => 'Habits',
        WidgetPreviewKind.calendar => 'Calendar',
        WidgetPreviewKind.schedule => 'Schedule',
        WidgetPreviewKind.goal => 'Goals',
        WidgetPreviewKind.course => 'Timetable',
        WidgetPreviewKind.note => 'Notes',
        WidgetPreviewKind.anniversary => 'Anniversaries',
        WidgetPreviewKind.diary => 'Diary',
      },
      AppLocale.zh => switch (kind) {
        WidgetPreviewKind.todo => '今日待办预览',
        WidgetPreviewKind.focus => '专注预览',
        WidgetPreviewKind.habit => '习惯预览',
        WidgetPreviewKind.calendar => '月历预览',
        WidgetPreviewKind.schedule => '今日日程预览',
        WidgetPreviewKind.goal => '目标预览',
        WidgetPreviewKind.course => '课程表预览',
        WidgetPreviewKind.note => '随手记预览',
        WidgetPreviewKind.anniversary => '纪念日预览',
        WidgetPreviewKind.diary => '日记预览',
      },
    };
  }

  static String previewSampleBadge(String title) =>
      isZh ? '示例 · $title' : 'Sample · $title';

  static String sampleHeaderDate(String cellLabel, {DateTime? date}) {
    final d = date ?? DateTime(2026, 5, 17);
    return switch (I18n.current) {
      AppLocale.en => '$cellLabel · ${I18nDateFormat.monthDay(d)}',
      AppLocale.zh => '$cellLabel · 05/17',
    };
  }

  static String get refreshPreviewTooltip => isZh ? '刷新预览' : 'Refresh preview';

  static List<String> get previewNavLabels => isZh
      ? const ['待办', '习惯', '日历', '专注']
      : const ['Todo', 'Habits', 'Calendar', 'Focus'];

  // Calendar body
  static String calendarMonthHeader(int year, int month) {
    return switch (I18n.current) {
      AppLocale.en => '${_enMonth(month)} $year',
      AppLocale.zh => '$year年$month月',
    };
  }

  static String get calendarToday => isZh ? '今天' : 'Today';

  static List<String> get calendarWeekLabels => isZh
      ? const ['一', '二', '三', '四', '五', '六', '日']
      : const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  // 10 sample preview bodies
  // Todo
  static String get todoItem1 => isZh ? '整理今日计划' : 'Organize daily plan';
  static String get todoItem2 => isZh ? '项目方案复盘' : 'Review project proposal';
  static String get todoItem3 => isZh ? '晚间运动 30 分钟' : '30-min evening workout';
  static String get todoSummaryCount =>
      isZh ? '今日待办 · 3 项' : 'Today’s tasks · 3 items';
  static String get todoQuickAdd => isZh ? '+ 记一笔' : '+ Quick Add';

  // Focus
  static String get focusMetricSessions => isZh ? '今日专注' : 'Sessions';
  static String get focusMetricDuration => isZh ? '时长(分)' : 'Minutes';
  static String get focusMetricNext => isZh ? '下一轮(分)' : 'Next (min)';
  static String get focusStartButton =>
      isZh ? '开始 25 分钟专注' : 'Start 25-min focus';
  static String get focusLine1 =>
      isZh ? '今日专注 2 次 · 深度工作 50 分钟' : 'Today: 2 sessions · 50 min deep work';
  static String get focusLine2 => isZh ? '下一轮：25 分钟专注' : 'Next: 25-min focus';
  static String get focusLine3 => isZh ? '点击开始专注' : 'Tap to start focus';

  // Habit
  static String get habitTitle => isZh ? '今日习惯' : 'Today’s habits';
  static String get habitLine1 =>
      isZh ? '· 晚间拉伸 · 今日待打卡' : '· Evening Stretch · Pending';
  static String get habitLine2 => isZh ? '· 连续记录 5 天' : '· 5-day streak';
  static String get habitCheckInButton =>
      isZh ? '打卡：晚间拉伸' : 'Check-in: Stretch';

  // Schedule
  static String get scheduleItem1 =>
      isZh ? '20:25 厕所 · 到点提醒' : '20:25 Break · Reminder';
  static String get scheduleItem2 => isZh ? '14:30 团队例会' : '14:30 Team sync';
  static String get scheduleItem3 =>
      isZh ? '19:00 晚间复盘' : '19:00 Evening review';

  // Goal
  static String get goalItem1 => isZh ? '发版准备 · 68%' : 'Release prep · 68%';
  static String get goalItem2 => isZh ? '本周运动 3/5 次' : 'Workouts 3/5 this week';
  static String get goalItem3 =>
      isZh ? '晚间复盘 · 今日待推进' : 'Evening review · Pending';

  // Course
  static String get courseItem1 =>
      isZh ? '第 1-2 节 高等数学 · 教 203' : 'Period 1-2 Advanced Math · Rm 203';
  static String get courseItem2 =>
      isZh ? '第 3-4 节 产品设计 · 线上' : 'Period 3-4 Product Design · Online';
  static String get courseItem3 =>
      isZh ? '14:30 团队例会 · 打开日历查看' : '14:30 Team sync · View in calendar';

  // Note
  static String get noteItem1 => isZh ? '会议纪要' : 'Meeting notes';
  static String get noteItem2 => isZh ? '灵感清单' : 'Idea checklist';
  static String get noteItem3 => isZh ? '读书摘录' : 'Book highlights';

  // Anniversary
  static String get anniversaryItem1 =>
      isZh ? '相识纪念日 · 还有 6 天' : 'Anniversary · 6 days left';
  static String get anniversaryItem2 =>
      isZh ? '入职周年 · 还有 18 天' : 'Work Anniversary · 18 days left';
  static String get anniversaryItem3 =>
      isZh ? '旅行纪念 · 还有 32 天' : 'Trip Anniversary · 32 days left';

  // Diary
  static String get diaryItem1 =>
      isZh ? '5/18 今天完成了专注复盘' : 'May 18 Completed focus review today';
  static String get diaryItem2 =>
      isZh ? '5/17 记录一次散步' : 'May 17 Logged an evening walk';
  static String get diaryItem3 =>
      isZh ? '5/16 睡前整理心情' : 'May 16 Bedtime reflection';

  static String _enMonth(int month) => switch (month) {
    1 => 'Jan',
    2 => 'Feb',
    3 => 'Mar',
    4 => 'Apr',
    5 => 'May',
    6 => 'Jun',
    7 => 'Jul',
    8 => 'Aug',
    9 => 'Sep',
    10 => 'Oct',
    11 => 'Nov',
    12 => 'Dec',
    _ => '',
  };
}
