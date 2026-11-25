// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '多仪';

  @override
  String get navToday => '今日';

  @override
  String get navTodo => '待办';

  @override
  String get navHabit => '习惯';

  @override
  String get navCalendar => '日历';

  @override
  String get navFocus => '专注';

  @override
  String get navWidget => '小组件';

  @override
  String get navMine => '我的';

  @override
  String get actionConfirm => '确定';

  @override
  String get actionCancel => '取消';

  @override
  String get actionSave => '保存';

  @override
  String get actionDelete => '删除';

  @override
  String get actionEdit => '编辑';

  @override
  String get actionAdd => '添加';

  @override
  String get actionCreate => '创建';

  @override
  String get actionGenerate => '生成';

  @override
  String get actionComplete => '完成';

  @override
  String get actionOff => '关';

  @override
  String get actionMoveUp => '上移';

  @override
  String get actionMoveDown => '下移';

  @override
  String get actionSnooze => '稍后提醒';

  @override
  String get actionRetry => '重试';

  @override
  String get actionBack => '返回';

  @override
  String get actionClear => '清空';

  @override
  String get actionClose => '关闭';

  @override
  String get settingsLanguage => '界面语言';

  @override
  String get weekdayMon => '周一';

  @override
  String get weekdayTue => '周二';

  @override
  String get weekdayWed => '周三';

  @override
  String get weekdayThu => '周四';

  @override
  String get weekdayFri => '周五';

  @override
  String get weekdaySat => '周六';

  @override
  String get weekdaySun => '周日';

  @override
  String get weekdayUnknown => '周?';

  @override
  String get calendarSolar => '公历';

  @override
  String get calendarLunar => '农历';

  @override
  String get calendarChineseLunar => '农历';

  @override
  String get calendarChineseLunarCalendar => '农历';

  @override
  String get calendarCorrespondingLunar => '对应农历';

  @override
  String get calendarCorrespondingSolar => '对应公历';

  @override
  String get calendarEventEvent => '日程';

  @override
  String get calendarEventTodo => '待办';

  @override
  String get calendarEventHabit => '习惯';

  @override
  String get calendarEventPomodoro => '番茄钟';

  @override
  String get calendarEventAnniversary => '纪念日';

  @override
  String get calendarEventCourse => '课程';

  @override
  String get calendarEventDiary => '日记';

  @override
  String get calendarEventCountdown => '倒数日';

  @override
  String get calendarEventGoal => '目标';

  @override
  String get calendarEventTimeEntry => '时间足迹';

  @override
  String get timeEntrySourceManual => '手动';

  @override
  String get timeEntrySourcePomodoro => '番茄钟';

  @override
  String get timeEntrySourceTodo => '待办';

  @override
  String get timeEntrySourceHabit => '习惯';

  @override
  String get timeEntrySourceGoal => '目标';

  @override
  String get timeEntryCategoryFocus => '专注';

  @override
  String get timeEntryCategoryTodo => '待办';

  @override
  String get timeEntryCategoryHabit => '习惯';

  @override
  String get timeEntryCategoryGoal => '目标';

  @override
  String get timeEntryCategoryStudy => '学习';

  @override
  String get timeEntryCategoryWork => '工作';

  @override
  String get timeEntryCategoryLife => '生活';

  @override
  String get timeEntryCategoryOther => '其他';

  @override
  String get settingsLanguageZh => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageDescription => '选择界面语言。你的待办、笔记和其他记录会保留原文。';

  @override
  String get preferencesTitle => '个性设置';

  @override
  String get preferencesLocalTitle => '本地个性设置';

  @override
  String get preferencesLocalSubtitle => '按功能管理通知、导航入口、日期、交互和本机行为';

  @override
  String get preferencesSectionDate => '日期与日历';

  @override
  String get preferencesSectionDateSubtitle => '影响今日卡片、日历和日期展示';

  @override
  String get preferencesFirstDayTitle => '一周从哪一天开始';

  @override
  String get preferencesFirstDayCurrentMonday => '当前为周一';

  @override
  String get preferencesFirstDayCurrentSunday => '当前为周日';

  @override
  String get preferencesDateFormatTitle => '日期格式';

  @override
  String get preferencesTimezoneTitle => '应用时区';

  @override
  String get preferencesTimezoneFollowSystem => '跟随手机';

  @override
  String get preferencesLunarTitle => '显示农历';

  @override
  String get preferencesLunarSubtitle => '影响日历月视图与今日卡';

  @override
  String get preferencesSectionDefaults => '默认行为';

  @override
  String get preferencesSectionDefaultsSubtitle => '启动入口、快捷捕获和专注时长';

  @override
  String get preferencesDefaultTabTitle => '启动默认 Tab';

  @override
  String get preferencesQuickCaptureTitle => '显示快速捕获按钮';

  @override
  String get preferencesQuickCaptureSubtitle => '今日页右下角的快捷创建按钮';

  @override
  String get preferencesNotificationQuickAddTitle => '通知栏快捷添加';

  @override
  String get preferencesNotificationQuickAddSubtitle =>
      'Android 常驻通知：添加待办或开始专注';

  @override
  String get preferencesNotificationTodayProgressTitle => '通知栏今日任务进展';

  @override
  String get preferencesNotificationTodayProgressSubtitle =>
      '开启后在通知栏常驻显示今日任务摘要，可随任务变化刷新';

  @override
  String get preferencesNotificationStatusBarTitle => '通知栏快捷入口';

  @override
  String get preferencesNotificationStatusBarUnsupported =>
      '通知栏常驻快捷入口和今日进展仅 Android 支持，当前平台保留普通通知提醒。';

  @override
  String get preferencesNotificationStatusBarEnabled => '通知栏入口已开启';

  @override
  String get preferencesNotificationStatusBarDisabled => '通知栏入口已关闭';

  @override
  String get preferencesNotificationStatusBarSyncFailed =>
      '通知栏同步失败，已恢复原设置。请检查系统通知权限和通知渠道。';

  @override
  String get preferencesShowCompletedTitle => '待办页显示已完成';

  @override
  String get preferencesShowCompletedSubtitle =>
      '默认列表显示已完成事项；关闭后仍可通过“已完成”或“包含归档”查看';

  @override
  String get preferencesPomodoroLengthTitle => '默认番茄钟长度';

  @override
  String get preferencesPomodoroLengthSubtitle => '选择“默认”时生效，当前计时保持不变';

  @override
  String get preferencesSectionBottomNav => '底部导航栏';

  @override
  String get preferencesSectionBottomNavSubtitle =>
      '底部导航最多显示 5 个入口；我的固定显示，小组件可隐藏';

  @override
  String get preferencesSectionInteraction => '交互';

  @override
  String get preferencesSectionInteractionSubtitle => '触感反馈与完成动作';

  @override
  String get preferencesHapticTitle => '震动反馈';

  @override
  String get preferencesHapticSubtitle => '完成/切换/解锁等操作';

  @override
  String get preferencesSectionAutoArchive => '待办自动归档';

  @override
  String get preferencesSectionAutoArchiveSubtitle => '减少已完成项目对列表的干扰';

  @override
  String get preferencesAutoArchiveTitle => '完成 N 天后隐藏';

  @override
  String get preferencesAutoArchiveNever => '从不归档';

  @override
  String get preferencesAutoArchiveAfterDays => '天后自动隐藏';

  @override
  String get preferencesSectionDailyReminder => '每日提醒';

  @override
  String get preferencesSectionDailyReminderSubtitle =>
      '最多三组提醒：时间、任务范围、重复周期、节假日暂停';

  @override
  String get preferencesNavFixed => '固定显示';

  @override
  String get preferencesNavVisible => '已显示';

  @override
  String get preferencesNavHidden => '已隐藏';

  @override
  String get preferencesNotifyPermissionDenied => '系统通知权限未授予';

  @override
  String get preferencesNotifyExactAlarmGranted => '精准闹钟权限已授权';

  @override
  String get preferencesNotifyExactAlarmDenied => '精准闹钟权限未授予';

  @override
  String get preferencesNotifyFullScreenGranted => '弹出屏幕权限已允许';

  @override
  String get preferencesNotifyFullScreenDenied => '弹出屏幕权限未允许';

  @override
  String get preferencesNotifyTestPermissionDenied => '系统通知权限未授权，无法发送测试通知';

  @override
  String get preferencesNotifyTestFailed => '测试通知发送失败：';

  @override
  String get preferencesNotifyTestSent => '测试通知已发送';

  @override
  String get preferencesNotifyPendingCleared => '已取消全部待调度提醒';

  @override
  String get preferencesNotifyOpenSettingsFailed => '无法打开系统设置';

  @override
  String get preferencesRingtoneSection => '内置提醒铃声';

  @override
  String get preferencesReportReminderDailyTime => '每日复盘推送时间';

  @override
  String get preferencesReportReminderWeeklyTime => '周报推送时间';

  @override
  String get preferencesReportReminderMonthlyTime => '月报推送时间';

  @override
  String get preferencesReportReminderYearlyTime => '年报推送时间';

  @override
  String get preferencesReportReminderTimeSubtitle => '修改后会重排下一次报告通知';

  @override
  String get preferencesRingtoneSectionSubtitle => '用于 HyperOS 等默认静音通知场景';

  @override
  String get preferencesRingtoneSectionSubtitleAndroid =>
      'Android 使用应用内置铃声服务，适配 HyperOS 等默认静音通知场景';

  @override
  String get preferencesRingtoneSectionSubtitleApple =>
      'iOS/macOS 使用系统通知声音和 time-sensitive 强提醒，不显示仅 Android 生效的内置铃声选择';

  @override
  String get preferencesRingtoneSectionSubtitleDesktop =>
      '桌面端使用系统通知声音；响铃音量由系统控制';

  @override
  String get preferencesRingtoneSectionSubtitleUnsupported => '当前平台不支持本地响铃提醒';

  @override
  String get preferencesRingtoneSound => '提醒铃声';

  @override
  String get preferencesRingtoneVolume => '响铃音量';

  @override
  String get preferencesRingtoneCurrent => '当前';

  @override
  String get preferencesRingtoneSystemSound => '系统通知声音';

  @override
  String get preferencesRingtoneSystemSoundSubtitleApple =>
      '到点提醒会请求声音、横幅和 time-sensitive 优先级；铃声和音量在系统设置中管理';

  @override
  String get preferencesRingtoneSystemSoundSubtitleDesktop =>
      '到点提醒会交给桌面通知系统；铃声和音量在系统设置中管理';

  @override
  String get preferencesRingtoneUnsupported => '本地响铃不可用';

  @override
  String get preferencesRingtoneUnsupportedSubtitle =>
      'Web 等平台暂不提供本地响铃提醒，请使用系统或邮件提醒兜底';

  @override
  String get preferencesDailyReminderOne => '提醒一';

  @override
  String get preferencesDailyReminderTwo => '提醒二';

  @override
  String get preferencesDailyReminderThree => '提醒三';

  @override
  String get preferencesDailyReminderDisabled => '已关闭';

  @override
  String get preferencesDailyReminderTime => '提醒时间';

  @override
  String get preferencesDailyReminderTimeSubtitle => '到点发送带声音和震动的提醒';

  @override
  String get preferencesDailyReminderTimeSuffix => '时间';

  @override
  String get preferencesDailyReminder1Time => '提醒一时间';

  @override
  String get preferencesDailyReminder2Time => '提醒二时间';

  @override
  String get preferencesDailyReminder3Time => '提醒三时间';

  @override
  String get preferencesDailyReminderTimePickerSubtitle => '设置提醒触发时间';

  @override
  String get preferencesDailyReminderKindTitle => '提醒方式';

  @override
  String get preferencesDailyReminderKindPushDescription => '系统通知栏提醒';

  @override
  String get preferencesDailyReminderKindPopupDescription =>
      '应用前台时弹出提醒，后台使用通知兜底';

  @override
  String get preferencesDailyReminderKindAlarmDescription => '按闹钟方式提醒，适合重要事项';

  @override
  String get preferencesDailyReminderKindOffDescription => '不注册系统通知、弹窗或闹钟';

  @override
  String get preferencesDailyReminderRegisterFailed => '每日提醒注册失败';

  @override
  String get preferencesDailyReminderNotReady => '系统通知未就绪，每日提醒没有开启。';

  @override
  String get preferencesDailyReminderTodayTasks => '任务：今日任务';

  @override
  String get preferencesDailyReminderTodayTasksSubtitle => '提醒中包含今日未完成任务数量';

  @override
  String get preferencesDailyReminderTomorrowPlan => '任务：明日计划';

  @override
  String get preferencesDailyReminderTomorrowPlanSubtitle => '提醒中包含明日已安排任务数量';

  @override
  String get preferencesDailyReminderOverdueTasks => '任务：逾期任务';

  @override
  String get preferencesDailyReminderOverdueTasksSubtitle => '提醒中包含已过期未完成任务';

  @override
  String get preferencesDailyReminderPauseHolidays => '法定节假日暂停提醒';

  @override
  String get preferencesDailyReminderPauseHolidaysSubtitle =>
      '遇到内置节假日时顺延到下一个提醒日';

  @override
  String get preferencesDailyReminderChipTodayTasks => '今日任务';

  @override
  String get preferencesDailyReminderChipTomorrowPlan => '明日计划';

  @override
  String get preferencesDailyReminderChipOverdueTasks => '逾期事项';

  @override
  String get preferencesDailyReminderChipPauseHolidays => '节假日暂停';

  @override
  String get preferencesDailyReminderScopeToday => '今日';

  @override
  String get preferencesDailyReminderScopeOverdue => '逾期';

  @override
  String get preferencesDailyReminderScopeTomorrow => '明日';

  @override
  String get preferencesDailyReminderScopeNone => '无任务范围';

  @override
  String get notificationChannelGeneralName => '多仪 · 通知提醒';

  @override
  String get notificationChannelGeneralDescription => '日常提醒使用柔和提示音、震动并尽量显示横幅';

  @override
  String get notificationChannelAlarmName => '多仪 · 柔和强提醒';

  @override
  String get notificationChannelAlarmDescription => '重要提醒使用柔和内置铃声，可在通知上手动停止';

  @override
  String get notificationChannelQuickAddName => '多仪 · 快捷入口';

  @override
  String get notificationChannelQuickAddDescription => '通知栏常驻快捷添加待办和开始专注';

  @override
  String get notificationTickerReminder => '多仪提醒';

  @override
  String get notificationTickerQuickAdd => '多仪快捷入口';

  @override
  String get notificationQuickAddTitle => '多仪快捷记录';

  @override
  String get notificationQuickAddBody => '下拉通知栏添加待办，或一键开始专注';

  @override
  String get notificationQuickAddActionAddTodo => '添加待办';

  @override
  String get notificationQuickAddActionOpenInput => '打开输入';

  @override
  String get notificationQuickAddActionStartFocus => '开始专注';

  @override
  String get notificationQuickAddInputLabel => '例如：明天下午3点开会';

  @override
  String get notificationStatusBarTodayProgressTitle => '今日任务进展';

  @override
  String get notificationStatusBarQuickHint => '下拉可快速添加待办';

  @override
  String get notificationStatusBarTodayRemainingPrefix => '今日还要完成 ';

  @override
  String get notificationStatusBarTodayRemainingSuffix => ' 项';

  @override
  String get notificationStatusBarDailyCount => '日常 ';

  @override
  String get notificationStatusBarTodoCount => '待办 ';

  @override
  String get notificationStatusBarGoalCount => '目标 ';

  @override
  String get quickTodoTitle => '快速待办';

  @override
  String get quickTodoHint => '一句话描述（如：明天下午3点开会）';

  @override
  String get quickTodoParsedPrefix => '识别到：';

  @override
  String get quickAiTitle => 'AI 快捷创建日程';

  @override
  String get quickAiHint => '例如：准备周五汇报';

  @override
  String get quickAiError => 'AI 创建失败，请检查 AI 配置';

  @override
  String get quickNoteTitle => '随手记';

  @override
  String get quickNoteHint => '写点什么…';

  @override
  String get quickMenuAiSchedule => 'AI 创建日程';

  @override
  String get quickMenuSearch => '全局搜索';

  @override
  String get quickMenuDiary => '写日记';

  @override
  String get quickMenuNote => '记一笔';

  @override
  String get quickMenuTodo => '快速待办';

  @override
  String get quickMenuTemplate => '快捷模板';

  @override
  String get quickTemplateTitle => '快捷模板';

  @override
  String get quickTemplateSubtitle => '一键套用常用待办或习惯默认值';

  @override
  String get quickTemplateSave => '保存模板';

  @override
  String get quickTemplateEmpty => '还没有模板';

  @override
  String get quickTemplateKindTodo => '待办';

  @override
  String get quickTemplateKindHabit => '习惯';

  @override
  String get quickTemplateName => '模板名称';

  @override
  String get quickTemplatePrefix => '标题前缀';

  @override
  String get quickTemplateTags => '标签（逗号或空格分隔）';

  @override
  String get quickTemplateList => '默认清单';

  @override
  String get quickTemplatePriority => '默认优先级';

  @override
  String get quickTemplateReminder15 => '有截止时间时提前 15 分钟提醒';

  @override
  String get quickTemplateHabitCategory => '习惯分组';

  @override
  String get quickTemplateHabitTarget => '每日目标';

  @override
  String get quickTemplateHabitUnit => '单位';

  @override
  String get quickTemplateHabitReminder => '默认 21:00 提醒';

  @override
  String get quickTemplateSaved => '模板已保存';

  @override
  String get quickTemplateApplyHint => '输入本次内容';

  @override
  String get quickTemplateTodoDone => '已按模板创建待办';

  @override
  String get quickTemplateHabitDone => '已按模板创建习惯';

  @override
  String get searchHint => '搜索待办 · 日程 · 习惯 · 笔记 · 日记 …';

  @override
  String get searchEmpty => '输入关键字，搜索全部内容';

  @override
  String get searchNoResultsPrefix => '没找到 ';

  @override
  String get searchNoResultsSuffix => ' 相关结果';

  @override
  String get searchResultsTitle => '搜索结果';

  @override
  String get searchResultsSummaryPrefix => '“';

  @override
  String get searchResultsSummaryMiddle => '” 共 ';

  @override
  String get searchResultsSummarySuffix => ' 条命中';

  @override
  String get searchClear => '清空搜索';

  @override
  String get searchKindTodo => '待办';

  @override
  String get searchKindHabit => '习惯';

  @override
  String get searchKindNote => '笔记';

  @override
  String get searchKindDiary => '日记';

  @override
  String get searchKindAnniversary => '纪念';

  @override
  String get searchKindCountdown => '倒数';

  @override
  String get searchKindGoal => '目标';

  @override
  String get searchKindCourse => '课程';

  @override
  String get searchKindEvent => '日程';

  @override
  String get searchKindTimeEntry => '时间足迹';

  @override
  String get authLoginTitle => '登录';

  @override
  String get authRegisterTitle => '注册账号';

  @override
  String get authLogin => '登录';

  @override
  String get authRegister => '注册';

  @override
  String get authLoginSubtitlePassword => '使用用户名或邮箱登录享受云同步与公告';

  @override
  String get authLoginSubtitleEmailCode => '使用已验证邮箱验证码登录';

  @override
  String get authRegisterSubtitle => '创建一个账号开启多端同步';

  @override
  String get authMaintenance => '服务正在维护中';

  @override
  String get authPasswordLogin => '密码登录';

  @override
  String get authEmailCodeLogin => '邮箱验证码';

  @override
  String get authUsername => '用户名';

  @override
  String get authAccount => '用户名或邮箱';

  @override
  String get authVerifiedEmail => '已验证邮箱';

  @override
  String get authEmail => '邮箱';

  @override
  String get authEmailOptional => '邮箱（可选）';

  @override
  String get authEmailRequiredHelper => '当前站点要求注册时验证邮箱';

  @override
  String get authEmailCode => '邮箱验证码';

  @override
  String get authEmailCodeOptional => '邮箱验证码（可选）';

  @override
  String get authEmailCodeSent => '验证码已发送，请查收邮箱';

  @override
  String get authEmailCodeSentCheckEmail => '验证码已发送，请查看邮箱。';

  @override
  String get authEmailCodeCodePrefix => '验证码：';

  @override
  String get authDisplayNameOptional => '昵称（可选）';

  @override
  String get authForgotPassword => '忘记密码？';

  @override
  String get authPassword => '密码';

  @override
  String get authConfirmPassword => '确认密码';

  @override
  String get authNewPassword => '新密码';

  @override
  String get authInviteCode => '邀请码';

  @override
  String get authSend => '发送';

  @override
  String get authRegistrationClosed => '当前站点已关闭注册';

  @override
  String get authSwitchToLogin => '已有账号？去登录';

  @override
  String get authSwitchToRegister => '没有账号？去注册';

  @override
  String get authPasswordResetTitle => '找回密码';

  @override
  String get authPasswordResetEmailSent => '重置邮件已发送，请查收邮箱。';

  @override
  String get authPasswordResetDone => '密码已重置，请使用新密码登录';

  @override
  String get authPasswordResetConfirm => '确认重置';

  @override
  String get authPasswordResetSendEmail => '发送邮件';

  @override
  String get authResetAccount => '用户名或已绑定邮箱';

  @override
  String get authResetAccountHelper => '验证码会发送到账号已绑定邮箱';

  @override
  String get authErrorEmailRequired => '请先填写邮箱';

  @override
  String get authErrorEmailInvalid => '邮箱格式不正确';

  @override
  String get authErrorUsernameRequired => '请填写用户名';

  @override
  String get authErrorAccountRequired => '请填写用户名或邮箱';

  @override
  String get authErrorUsernameLength => '用户名需为 3-64 个字符';

  @override
  String get authErrorUsernameNoSpace => '用户名不能包含空白字符';

  @override
  String get authErrorEmailCodeRequired => '请先获取并填写邮箱验证码';

  @override
  String get authErrorPasswordShort => '密码至少 6 位';

  @override
  String get authErrorPasswordMismatch => '两次输入的密码不一致';

  @override
  String get authErrorInviteRequired => '请填写邀请码';

  @override
  String get authErrorVerifiedEmailRequired => '请填写已验证邮箱';

  @override
  String get authErrorEmailCodeInputRequired => '请填写邮箱验证码';

  @override
  String get authErrorPasswordRequired => '请填写密码';

  @override
  String get authErrorInvalidCredentials => '账号或密码错误，请重新输入';

  @override
  String get authErrorResetAccountRequired => '请填写用户名或已绑定邮箱';

  @override
  String get authErrorMailCodeRequired => '请填写邮件验证码';

  @override
  String get authErrorNewPasswordShort => '新密码至少 6 位';

  @override
  String get authErrorNewPasswordMismatch => '两次输入的新密码不一致';

  @override
  String get profileTitle => '个人资料';

  @override
  String get profileNickname => '昵称';

  @override
  String get profileDisplayName => '显示名';

  @override
  String get profileDisplayNameEmpty => '未设置昵称';

  @override
  String get profileLocalNickname => '本地昵称';

  @override
  String get profileDefaultUser => '用户';

  @override
  String get profileLocal => '本地资料';

  @override
  String get profileLocalUpdated => '本地资料已更新';

  @override
  String get profileLoginAccount => '登录账号';

  @override
  String get profileEmailVerified => '已验证';

  @override
  String get profileEmailUnverified => '未验证';

  @override
  String get profileEmailUnverifiedOrPending => '未验证或待验证';

  @override
  String get profileEmailUnbound => '未绑定邮箱';

  @override
  String get profileEmailBinding => '邮箱绑定';

  @override
  String get profileEmailLocalDisplay => '邮箱（仅本地展示，不用于登录或找回）';

  @override
  String get profileEmailCodeHelper => '换绑或验证邮箱时填写';

  @override
  String get profileAvatarUrlOrText => '头像 URL 或文字';

  @override
  String get profileAvatarUrlFileOrText => '头像 URL、本地文件或文字';

  @override
  String get profileAvatarHelper => '可选择图片，或填写文字作为头像首字';

  @override
  String get profileAvatarUpload => '上传';

  @override
  String get profileAvatarChoose => '选择';

  @override
  String get profileAvatarEmpty => '头像文件不能为空';

  @override
  String get profileAvatarTooLarge => '头像不能超过 3MB';

  @override
  String get profileAvatarUploaded => '头像已上传';

  @override
  String get profileAvatarSaved => '头像已保存';

  @override
  String get profileAvatarSelected => '头像已选择，点击保存后生效';

  @override
  String get profileCoins => '时光币';

  @override
  String get profileAccountId => '账号';

  @override
  String get profileUsernameLocked => '用户名是账号唯一标识，暂不在资料页修改';

  @override
  String get profileAccountSecurity => '账号安全';

  @override
  String get profileAccountSecuritySubtitle => '密码等敏感操作集中在这里';

  @override
  String get profileBio => '简介';

  @override
  String get profileUpdated => '资料已更新';

  @override
  String get profileSaved => '已保存';

  @override
  String get profileSaveFailed => '无法保存';

  @override
  String get profileChangePassword => '修改登录密码';

  @override
  String get profileChangePasswordSubtitle => '需要输入当前密码';

  @override
  String get profileCurrentPassword => '当前密码';

  @override
  String get profileConfirmNewPassword => '确认新密码';

  @override
  String get profilePasswordUpdated => '登录密码已更新';

  @override
  String get profileErrorNicknameRequired => '请填写昵称';

  @override
  String get habitDetailTitle => '习惯详情';

  @override
  String get habitDetailNotFound => '这个习惯不存在或已被删除';

  @override
  String get habitEditTitle => '编辑习惯';

  @override
  String get habitSaved => '已保存';

  @override
  String get habitFieldName => '习惯名称';

  @override
  String get habitFieldGroup => '分组';

  @override
  String get habitFieldGroupEmptyHint => '留空则归入未分组';

  @override
  String get habitFieldDailyTargetCount => '每日目标次数';

  @override
  String get habitFieldUnit => '单位';

  @override
  String get habitUnitTimes => '次';

  @override
  String get habitUnitWeek => '周';

  @override
  String get habitUnitMonth => '月';

  @override
  String get habitKind => '习惯类型';

  @override
  String get habitKindPositive => '✅ 正向养成';

  @override
  String get habitKindNegative => '🚫 反向戒除';

  @override
  String get habitColor => '颜色';

  @override
  String get habitReminder => '提醒';

  @override
  String get habitErrorNameRequired => '请填写习惯名称';

  @override
  String get habitErrorDailyTarget => '每日目标次数至少为 1';

  @override
  String get habitErrorFlexTarget => '周期目标至少为 1';

  @override
  String get habitErrorDateRange => '结束日期不能早于开始日期';

  @override
  String get habitErrorNotificationPermission => '系统通知未授权，习惯提醒不会响铃或弹出';

  @override
  String get habitErrorReminderRegisterFailed => '习惯提醒注册失败';

  @override
  String get habitFlexRule => '弹性打卡规则';

  @override
  String get habitFlexWeekly => '每周目标';

  @override
  String get habitFlexMonthly => '每月目标';

  @override
  String get habitFlexPeriodTarget => '目标次数';

  @override
  String get habitFlexPeriodTargetHint => '例如每周目标 5 次';

  @override
  String get habitFlexDailyNote => '关闭时按每日目标连续统计';

  @override
  String get habitFlexNegativeNote => '反向戒除按每日不发生统计';

  @override
  String get habitFlexWeeklyGoalPrefix => '每周目标: ';

  @override
  String get habitFlexMonthlyGoalPrefix => '每月目标: ';

  @override
  String get habitFlexThisWeek => '本周';

  @override
  String get habitFlexThisMonth => '本月';

  @override
  String get habitDailyPrefix => '每天';

  @override
  String get habitRecordedPrefix => '已记录 ';

  @override
  String get habitStatCurrentStreak => '当前连续';

  @override
  String get habitStatBestStreak => '最佳纪录';

  @override
  String get habitStatToday => '今日';

  @override
  String get habitHeatmapTitle => '打卡热力图';

  @override
  String get habitRecordsTitle => '最近记录 / 补卡';

  @override
  String get habitRecordsInactive => '未在周期内';

  @override
  String get habitRecordsUndoOnce => '撤回一次';

  @override
  String get habitRecordsRecordOnce => '记录一次';

  @override
  String get habitRecordsMakeUpOnce => '补一次';

  @override
  String get habitTrendTitle => '习惯趋势';

  @override
  String get habitTrendCompleted => '达标';

  @override
  String get habitTrendDailyAverage => '日均';

  @override
  String get habitTrendLongestStreak => '最长连续';

  @override
  String get habitTrendVsPrevious => '较上期';

  @override
  String get habitTrendBucketDetails => '区间明细';

  @override
  String get habitTrendOneYear => '一年';

  @override
  String get habitDateRangeTitle => '习惯周期';

  @override
  String get habitDateRangeStart => '开始日期';

  @override
  String get habitDateRangeEnd => '结束日期';

  @override
  String get habitDateRangeStartEmpty => '立即开始';

  @override
  String get habitDateRangeEndEmpty => '不设结束';

  @override
  String get habitDateRangePickStart => '选择开始日期';

  @override
  String get habitDateRangePickEnd => '选择结束日期';

  @override
  String get habitDateRangeLongTerm => '长期有效';

  @override
  String get habitDateRangeFromSuffix => '起';

  @override
  String get habitDateRangeUntilSuffix => '止';

  @override
  String get noteTitle => '随手记';

  @override
  String get noteEmptyMessage => '随时捕捉闪念与灵感';

  @override
  String get noteEmptyAction => '写便签';

  @override
  String get noteEditTitle => '编辑便签';

  @override
  String get notePreview => '预览';

  @override
  String get noteEdit => '编辑';

  @override
  String get noteSearchHint => '搜索标题、正文或附件';

  @override
  String get noteSearchClear => '清空搜索';

  @override
  String get noteSearchEmpty => '没有匹配的便签';

  @override
  String get noteActive => '全部';

  @override
  String get noteArchived => '归档';

  @override
  String get noteArchivedEmpty => '暂无归档便签';

  @override
  String get noteMore => '更多操作';

  @override
  String get notePin => '置顶';

  @override
  String get noteUnpin => '取消置顶';

  @override
  String get noteArchive => '归档';

  @override
  String get noteRestore => '恢复';

  @override
  String get noteActionFailed => '操作失败，内容未变更，请重试';

  @override
  String get noteLinkPlaceholder => '链接文字';

  @override
  String get noteAttachmentPickFile => '从系统文件选择';

  @override
  String get noteAttachmentPickFileSubtitle => '图片、PDF、文档等都会作为附件保存';

  @override
  String get noteAttachmentAddLink => '添加链接或本地路径';

  @override
  String get noteAttachmentAddLinkSubtitle => '适合网页图片、资料链接和已知文件路径';

  @override
  String get noteAttachmentFileNotSelected => '未选择文件，已切换为手动添加';

  @override
  String get noteAttachmentDialogTitle => '添加附件';

  @override
  String get noteAttachmentName => '名称';

  @override
  String get noteAttachmentUri => '链接或本地路径';

  @override
  String get noteAttachmentUriHint => 'https://... 或 /storage/...';

  @override
  String get noteAttachmentType => '类型（可选）';

  @override
  String get noteAttachmentTypeHint => '例如 image/png、application/pdf';

  @override
  String get noteAttachmentDefaultName => '附件';

  @override
  String get noteEditorHint => '写点什么，支持 Markdown、清单和附件...';

  @override
  String get noteToolbarHeading => '标题';

  @override
  String get noteToolbarBold => '加粗';

  @override
  String get noteToolbarItalic => '斜体';

  @override
  String get noteToolbarQuote => '引用';

  @override
  String get noteToolbarBullet => '项目符号';

  @override
  String get noteToolbarChecklist => '清单';

  @override
  String get noteToolbarCode => '行内代码';

  @override
  String get noteToolbarLink => '链接';

  @override
  String get noteToolbarAttachment => '附件';

  @override
  String get notePreviewEmpty => '空白便签';

  @override
  String get feedbackCategoryFeature => '功能建议';

  @override
  String get feedbackCategoryBug => '问题反馈';

  @override
  String get feedbackCategoryWish => '许愿池';

  @override
  String get feedbackCategoryOther => '其他';

  @override
  String get feedbackHelpFeature => '描述你想新增或优化的功能';

  @override
  String get feedbackHelpBug => '说明复现路径、当前表现和期望表现';

  @override
  String get feedbackHelpWish => '写下你希望增加的场景或能力';

  @override
  String get feedbackHelpOther => '补充其他想让团队知道的信息';

  @override
  String get feedbackStatusResolved => '已处理';

  @override
  String get feedbackStatusClosed => '已关闭';

  @override
  String get feedbackStatusInProgress => '处理中';

  @override
  String get feedbackStatusOpen => '待处理';

  @override
  String get feedbackLoginRecordsRequired => '登录后可查看反馈记录';

  @override
  String get feedbackLoginSubmitRequired => '请先登录后再提交反馈';

  @override
  String get feedbackLoginSubtitle => '登录后可以提交并查看处理记录';

  @override
  String get feedbackLoginSectionSubtitle => '当前未登录，无法提交或查看反馈处理记录';

  @override
  String get feedbackContentEmpty => '反馈内容不能为空';

  @override
  String get feedbackSubmitted => '反馈已提交，感谢！';

  @override
  String get feedbackSubmitPrefix => '提交';

  @override
  String get feedbackSubmitLoginPrefix => '登录后提交';

  @override
  String get feedbackCategoryLabel => '分类';

  @override
  String get feedbackContentLabelPrefix => '描述一下你的';

  @override
  String get feedbackSubmitButton => '提交反馈';

  @override
  String get feedbackSubmitting => '提交中';

  @override
  String get feedbackMineTitle => '我的反馈';

  @override
  String get feedbackLoading => '正在加载';

  @override
  String get feedbackRecent => '最近提交的记录';

  @override
  String get feedbackEmpty => '还没有反馈记录';

  @override
  String get feedbackRefresh => '刷新';

  @override
  String get feedbackAdminReply => '管理员回复';

  @override
  String get announcementTitle => '公告';

  @override
  String get announcementCenter => '公告中心';

  @override
  String get announcementSubtitle => '系统通知、维护说明和版本更新会先出现在这里';

  @override
  String get announcementLatest => '最新公告';

  @override
  String get announcementPullToRefresh => '下拉可刷新';

  @override
  String get announcementEmpty => '暂无公告';

  @override
  String get announcementRefresh => '刷新';

  @override
  String get announcementLoadFailedPrefix => '公告加载失败：';

  @override
  String get announcementLevelInfo => '公告';

  @override
  String get announcementLevelWarning => '提醒';

  @override
  String get announcementLevelCritical => '重要';

  @override
  String get themeTitle => '主题风格';

  @override
  String get themeSectionStyles => '可选风格';

  @override
  String get themeSectionStylesSubtitle => '切换后会同步全局主题';

  @override
  String get themeStyleDefaultName => '多仪';

  @override
  String get themeStyleDefaultDescription => '简洁原版 · 暖橙基调';

  @override
  String get themeStyleRe0Name => '从零开始';

  @override
  String get themeStyleRe0Description => '银发魔女 · 露格尼卡圣域';

  @override
  String get themeStyleGenshinName => '原神';

  @override
  String get themeStyleGenshinDescription => '元素绘卷 · 提瓦特画架';

  @override
  String get themeStyleStarRailName => '星穹铁道';

  @override
  String get themeStyleStarRailDescription => '星穹列车 · 开拓之旅';

  @override
  String get themeStyleWutheringName => '鸣潮';

  @override
  String get themeStyleWutheringDescription => '共鸣终端 · 潮声频谱';

  @override
  String get themeStyleZzzName => '绝区零';

  @override
  String get themeStyleZzzDescription => '委托影像 · 新艾利都';

  @override
  String get themeStyleYanyunName => '燕云十六声';

  @override
  String get themeStyleYanyunDescription => '江湖画案 · 墨痕回转';

  @override
  String get themeStyleBotwName => '希卡之石';

  @override
  String get themeStyleBotwDescription => '希卡之石 · 具现化';

  @override
  String get themeStyleLiquidGlassName => '液态玻璃';

  @override
  String get themeStyleLiquidGlassDescription => 'iOS 玻璃拟态 · 半透明白与高光';

  @override
  String get goalTitle => '目标管理';

  @override
  String get goalRecommendedTemplates => '推荐模板';

  @override
  String get goalEmpty => '设立一个目标，让时间为你累积';

  @override
  String get goalCreate => '新建目标';

  @override
  String get goalNew => '新目标';

  @override
  String get goalStatusActive => '进行中';

  @override
  String get goalStatusPaused => '已暂停';

  @override
  String get goalStatusAchieved => '已达成';

  @override
  String get goalStatusAbandoned => '已放弃';

  @override
  String get goalMilestonePrefix => '里程碑 ';

  @override
  String get goalDaysRemainingPrefix => '还剩 ';

  @override
  String get goalDaysRemainingSuffix => ' 天';

  @override
  String get goalOverduePrefix => '已超期 ';

  @override
  String get goalOverdueSuffix => ' 天';

  @override
  String get exportTitle => '导出为日历 (.ics)';

  @override
  String get exportHeroTitle => '日历导出';

  @override
  String get exportHeroSubtitle =>
      '生成一份 iCalendar 文件，可粘贴到系统日历、Google Calendar 或 Outlook。';

  @override
  String get exportRangeTitle => '导出范围';

  @override
  String get exportRangeSubtitle => '选择要包含的内容';

  @override
  String get exportIncludeAnniversaries => '包含纪念日与生日';

  @override
  String get exportIncludeAnniversariesSubtitle => 'YEARLY 循环事件';

  @override
  String get exportIncludeCalendar => '包含日程总表';

  @override
  String get exportIncludeCalendarSubtitle => '待办、习惯、课程、日记和目标';

  @override
  String get exportPushCaldav => '写回 CalDAV';

  @override
  String get exportGenerateIcs => '生成 .ics';

  @override
  String get exportContentTitle => '导出内容';

  @override
  String get exportCopy => '复制';

  @override
  String get exportCopyDone => '已复制 .ics 内容';

  @override
  String get exportCaldavSuccessPrefix => '已写回 ';

  @override
  String get exportCaldavSuccessSuffix => ' 条日历事件到 CalDAV';

  @override
  String get exportCaldavConflictPrefix => '已写回 ';

  @override
  String get exportCaldavConflictMiddle => ' 条，跳过 ';

  @override
  String get exportCaldavConflictSuffix => ' 条远端已修改事件';

  @override
  String get exportCaldavFailedPrefix => 'CalDAV 写回失败: ';

  @override
  String get appLockTitle => '应用锁';

  @override
  String get appLockHeroTitle => '本机 PIN 锁';

  @override
  String get appLockHeroSubtitle => '用于保护本地数据，切回应用或重新启动时需要验证';

  @override
  String get appLockSectionStatus => '锁定状态';

  @override
  String get appLockSectionStatusSubtitle => '启用后会在启动或切回前台时要求 PIN';

  @override
  String get appLockEnable => '启用应用锁';

  @override
  String get appLockEnabled => '当前已启用';

  @override
  String get appLockDisabledSubtitle => '关闭后不会再要求 PIN';

  @override
  String get appLockChangePin => '更换 PIN';

  @override
  String get appLockChangePinSubtitle => '重新设置 4-8 位数字密码';

  @override
  String get appLockAutoLock => '自动锁定';

  @override
  String get appLockAutoLockImmediate => '立即';

  @override
  String get appLockAutoLockEveryForeground => '每次切回前台都锁定';

  @override
  String get appLockAutoLockAfterPrefix => '离开 ';

  @override
  String get appLockAutoLockAfterSuffix => ' 分钟后锁定';

  @override
  String get appLockAutoLockMinuteLabel => ' 分钟';

  @override
  String get appLockAutoLockOneHour => '1 小时';

  @override
  String get appLockAutoLockFourHours => '4 小时';

  @override
  String get appLockLockNow => '立即锁定';

  @override
  String get appLockLockNowSubtitle => '立刻切回输入 PIN';

  @override
  String get appLockTip => '提示：应用锁仅作用于本机，云端数据不受影响；忘记 PIN 只能清应用数据找回。';

  @override
  String get appLockDialogSetPin => '设置 PIN (4-8 位数字)';

  @override
  String get appLockDialogConfirmPin => '再输一遍确认';

  @override
  String get appLockDialogDisablePin => '输入当前 PIN 以关闭';

  @override
  String get appLockPinHint => '4-8 位数字';

  @override
  String get appLockPinMismatch => '两次输入不一致';

  @override
  String get appLockPinInvalid => '需要 4-8 位数字';

  @override
  String get appLockPinWrong => 'PIN 错误';

  @override
  String get appLockEnabledMessage => '应用锁已启用';

  @override
  String get appLockDisabledMessage => '应用锁已关闭';

  @override
  String get aiHistoryTitle => 'AI 周回顾历史';

  @override
  String get aiHistoryClearTooltip => '清空历史';

  @override
  String get aiHistoryClearTitle => '清空全部回顾?';

  @override
  String get aiHistoryClearContent => '本地保留的 AI 回顾将被删除，无法恢复';

  @override
  String get aiHistoryClearAction => '清空';

  @override
  String get aiHistoryEmpty => '还没有 AI 回顾\n在\"我的\"页生成一份吧';

  @override
  String get aiHistoryCopy => '复制';

  @override
  String get aiHistoryCopyDone => '已复制';

  @override
  String get aiHistoryDelete => '删除';

  @override
  String get syncConflictTitle => '同步冲突记录';

  @override
  String get syncConflictEmpty => '暂无同步冲突记录';

  @override
  String get syncConflictKeepRemote => '保留云端版本';

  @override
  String get syncConflictKeepLocal => '保留本地版本';

  @override
  String get syncConflictType => '类型';

  @override
  String get syncConflictItem => '任务';

  @override
  String get syncConflictWorkspace => '空间';

  @override
  String get syncConflictLocal => '本地';

  @override
  String get syncConflictRemote => '云端';

  @override
  String get todayAlmanacTitle => '万年历';

  @override
  String get todayUnitItem => '项';

  @override
  String get todayUnitTimes => '次';

  @override
  String get todayUnitCourseSection => '节';

  @override
  String get todayUnitPoint => '分';

  @override
  String get todayDiary => '日记';

  @override
  String get todayDiaryWritten => '已写';

  @override
  String get todayDiaryUnwritten => '未写';

  @override
  String get todaySuggestions => '今日建议';

  @override
  String get todaySuggestionsSubtitle => '根据截止时间、优先级和四象限自动推荐';

  @override
  String get todayAddedPrefix => '已加入今日：';

  @override
  String get todayAddToToday => '加入今日';

  @override
  String get todayTodos => '今日待办';

  @override
  String get todayCompleted => '已完成';

  @override
  String get todayCourses => '今日课程';

  @override
  String get todayCoursePeriodPrefix => '第';

  @override
  String get todayCoursePeriodSuffix => '节';

  @override
  String get todayUpcomingAnniversaries => '即将到来的纪念日';

  @override
  String get todayAnniversaryToday => '就是今天';

  @override
  String get todayAnniversaryDaysPrefix => '还有 ';

  @override
  String get todayActiveGoals => '进行中的目标';

  @override
  String get todayGoalCreateSubtitle => '从今日页直接创建，不必进入目标管理';

  @override
  String get todayView => '查看';

  @override
  String get todayProductivityScore => '效率分';

  @override
  String get todayProductivityWeekly => '本周效率';

  @override
  String get todayProductivityFlat => '持平';

  @override
  String get todayProductivitySubtitle => '较上周同段 · 点击查看统计报表';

  @override
  String get todayProductivityCompletionRate => '完成率';

  @override
  String get diaryTitle => '日记';

  @override
  String get diaryWrite => '写日记';

  @override
  String get diaryEmptyMessage => '开始记录每天的心情吧';

  @override
  String get diaryStatsTooltip => '心情统计';

  @override
  String get diarySummaryTitle => '记录概览';

  @override
  String get diarySummarySubtitle => '累计、本月和连续写作状态';

  @override
  String get diarySummaryTotal => '累计';

  @override
  String get diarySummaryThisMonth => '本月';

  @override
  String get diarySummaryStreak => '连续';

  @override
  String get diaryRecentTitle => '最近日记';

  @override
  String get diaryRecentRecordsSuffix => ' 篇记录';

  @override
  String get diaryRecentRecordsSuffixSingular => ' 篇记录';

  @override
  String get diaryEntryCountSuffix => ' 篇';

  @override
  String get diaryEntryCountSuffixSingular => ' 篇';

  @override
  String get diaryStreakDaySingular => '天';

  @override
  String get diaryMoodStatsTitle => '近 30 天心情分布';

  @override
  String get diaryNoData => '暂无数据';

  @override
  String get diaryAiInsights => 'AI 日记洞察';

  @override
  String get diaryAiDeepReviewTooltip => 'AI 深度复盘';

  @override
  String get diaryAiDeepReviewTitle => 'AI 日记深度复盘';

  @override
  String get diaryAiDisabled => 'AI 功能未启用，请联系管理员';

  @override
  String get diaryAiReviewFailedPrefix => 'AI 日记复盘失败：';

  @override
  String get diaryEditorDateTitle => '日记日期';

  @override
  String get diaryEditorMoodPrompt => '今天心情如何？';

  @override
  String get diaryEditorWeather => '天气';

  @override
  String get diaryEditorTagHint => '添加标签 (如: 学习、旅行)';

  @override
  String get diaryEditorContentHint => '写下今天的故事...';

  @override
  String get diaryMoodAwesome => '超棒';

  @override
  String get diaryMoodGood => '开心';

  @override
  String get diaryMoodOkay => '平静';

  @override
  String get diaryMoodBad => '郁闷';

  @override
  String get diaryMoodTerrible => '糟糕';

  @override
  String get diaryWeatherSunny => '晴';

  @override
  String get diaryWeatherCloudy => '多云';

  @override
  String get diaryWeatherOvercast => '阴';

  @override
  String get diaryWeatherRain => '雨';

  @override
  String get diaryWeatherSnow => '雪';

  @override
  String get diaryWeatherWind => '风';

  @override
  String get diaryWeatherFog => '雾';

  @override
  String get diaryWeatherThunder => '雷';

  @override
  String get countdownTitle => '倒数日';

  @override
  String get countdownEmpty => '暂无倒数日记录';

  @override
  String get countdownNearestEmpty => '暂无即将到期的事件';

  @override
  String get countdownNearestPrefix => '下一项：';

  @override
  String get countdownNearestDaysPrefix => '还有 ';

  @override
  String get countdownSummaryTotal => '总数';

  @override
  String get countdownSummaryWithin7Days => '7 天内';

  @override
  String get countdownListTitle => '全部倒数日';

  @override
  String get countdownListSubtitle => '按优先级和剩余天数排序';

  @override
  String get countdownCategoryDefault => '默认';

  @override
  String get countdownEditorEditTitle => '编辑倒数日';

  @override
  String get countdownEditorSubtitle => '分类、到期日和提醒会同步到日历';

  @override
  String get countdownFieldTitle => '事件名称';

  @override
  String get countdownFieldCategory => '分类';

  @override
  String get countdownFieldTargetDate => '目标日期';

  @override
  String get countdownFieldDueReminder => '到期提醒';

  @override
  String get countdownFieldRemindDays => '提前天数';

  @override
  String get countdownFieldRemindTime => '提醒时间';

  @override
  String get countdownReminderClosed => '关闭';

  @override
  String get countdownReminderBeforePrefix => '提前 ';

  @override
  String get countdownReminderBeforeSuffix => ' 天';

  @override
  String get countdownValidationTitleRequired => '请先填写倒数日名称';

  @override
  String get countdownSaved => '倒数日已保存';

  @override
  String get countdownSaveFailedPrefix => '倒数日保存失败：';

  @override
  String get countdownReminderRegisterFailed => '倒数日提醒注册失败';

  @override
  String get countdownReminderNotRegistered => '倒数日已保存，但提醒未注册。请检查通知权限和提醒时间。';

  @override
  String get countdownReminderNotRegisteredPrefix => '倒数日已保存，但提醒未注册：';

  @override
  String get countdownReminderPopupFallbackFailed => '倒数日提醒注册失败：弹出框兜底通知不可用';

  @override
  String get countdownReminderPopupPermissionDenied =>
      '倒数日已保存，但弹出框提醒未注册：系统通知权限未开启。';

  @override
  String get countdownReminderPopupNotRegisteredPrefix => '倒数日已保存，但弹出框提醒未注册：';

  @override
  String get countdownReminderPopupWarning =>
      '倒数日已保存。弹出框只在应用运行时显示，后台或锁屏将使用系统通知兜底。';

  @override
  String get countdownReminderAlarmPermissionDenied =>
      '倒数日已保存，但闹钟提醒未注册：系统通知权限未开启，请开启后重新保存提醒。';

  @override
  String get countdownReminderAlarmChannelMissing => '强提醒渠道未就绪';

  @override
  String get countdownReminderExactAlarmMissing => '精准闹钟权限未开启，提醒可能延后';

  @override
  String get countdownReminderFullscreenMissing => '全屏提醒权限未开启，锁屏弹窗可能不可用';

  @override
  String get countdownReminderSavedWithWarningsPrefix => '倒数日已保存，';

  @override
  String get countdownReminderEmailWarning => '倒数日已保存，邮件提醒会在联网后由服务端发送。';

  @override
  String get countdownReminderExceptionPrefix => '倒数日已保存，但提醒未注册：';

  @override
  String get countdownReminderTimePast => '倒数日已保存，但提醒时间已过去，请重新选择提醒时间。';

  @override
  String get countdownStatusPinned => '置顶';

  @override
  String get countdownStatusExpired => '已过期';

  @override
  String get countdownStatusSoon => '临近';

  @override
  String get countdownStatusRunning => '倒数中';

  @override
  String get countdownTargetPrefix => '目标: ';

  @override
  String get countdownDaysElapsed => '已过';

  @override
  String get countdownDaysRemaining => '还有';

  @override
  String get anniversaryTitle => '纪念日';

  @override
  String get anniversaryBirthday => '生日';

  @override
  String get anniversaryCountdownShort => '倒数';

  @override
  String get anniversaryCustom => '自定义';

  @override
  String get anniversaryTabAll => '全部';

  @override
  String get anniversaryUpcoming30Days => '最近 30 天';

  @override
  String get anniversaryEmpty => '还没有任何纪念';

  @override
  String get anniversaryUpcomingEmpty => '未来 30 天内没有安排';

  @override
  String get anniversarySummaryWithin30Days => '30 天内';

  @override
  String get anniversaryListSuffix => '列表';

  @override
  String get anniversaryListSubtitle => '长按置顶，左滑删除，点击进入编辑';

  @override
  String get anniversaryDeleteTitle => '确认删除？';

  @override
  String get anniversaryDeleteContentSuffix => '将被移除';

  @override
  String get anniversaryOccurrencePrefix => '第';

  @override
  String get anniversaryOccurrenceSuffix => '次';

  @override
  String get anniversaryYearsElapsedPrefix => '已 ';

  @override
  String get anniversaryYearsElapsedSuffix => ' 年';

  @override
  String get anniversaryNextPrefix => '下一次: ';

  @override
  String get anniversaryTodayShort => '今天';

  @override
  String get anniversaryEditorAddTitle => '新增纪念';

  @override
  String get anniversaryEditorEditTitle => '编辑纪念';

  @override
  String get anniversaryFieldTitle => '标题';

  @override
  String get anniversaryFieldTitleHint => '如：妈妈生日 / 结婚纪念日';

  @override
  String get anniversaryFieldDescription => '备注 (可选)';

  @override
  String get anniversaryFieldType => '类型';

  @override
  String get anniversaryFieldDateType => '日期类型';

  @override
  String get anniversaryFieldDatePickerTitle => '选择日期';

  @override
  String get anniversaryFieldDatePickerSubtitle => '公历和农历使用独立组件';

  @override
  String get anniversaryFieldColor => '颜色标识';

  @override
  String get anniversaryValidationTitleRequired => '请先填写标题';

  @override
  String get anniversarySaved => '已保存';

  @override
  String get anniversarySaveFailedPrefix => '保存失败：';

  @override
  String get anniversaryReminderRegisterFailed => '纪念日提醒注册失败';

  @override
  String get anniversaryReminderNotRegistered => '纪念日提醒未注册，请检查通知权限和提醒时间。';

  @override
  String get anniversaryReminderPopupFallbackFailed => '纪念日提醒注册失败：弹出框兜底通知不可用';

  @override
  String get anniversaryReminderPopupPermissionDenied => '弹出框提醒未注册：系统通知权限未开启。';

  @override
  String get anniversaryReminderPopupNotRegisteredPrefix => '弹出框提醒未注册：';

  @override
  String get anniversaryReminderPopupWarning => '弹出框只在应用运行时显示，后台或锁屏将使用系统通知兜底。';

  @override
  String get anniversaryReminderAlarmPermissionDenied =>
      '闹钟提醒未注册：系统通知权限未开启，请开启后重新保存提醒。';

  @override
  String get anniversaryReminderAlarmChannelMissing => '强提醒渠道未就绪';

  @override
  String get anniversaryReminderExactAlarmMissing => '精准闹钟权限未开启，提醒可能延后';

  @override
  String get anniversaryReminderFullscreenMissing => '全屏提醒权限未开启，锁屏弹窗可能不可用';

  @override
  String get anniversaryReminderEmailWarning => '邮件提醒会在联网后由服务端发送。';

  @override
  String get anniversaryReminderExceptionPrefix => '提醒未注册：';

  @override
  String get anniversaryReminderSavedPrefix => '已保存，';

  @override
  String get anniversaryReminderTimePast => '已保存，但提醒时间已过去，请重新选择提醒时间。';

  @override
  String get anniversaryLunarYearSuffix => '年';

  @override
  String get courseWeekPrefix => '第 ';

  @override
  String get courseWeekSuffix => ' 周';

  @override
  String get courseWeekCountSuffix => '周';

  @override
  String get courseWeekCurrentTooltip => '回到本周';

  @override
  String get courseEmptyMessage => '添加课表后就能看到你的一周啦';

  @override
  String get courseAdd => '添加课程';

  @override
  String get courseWeekPickerTitle => '选择周次';

  @override
  String get courseWeekPickerSubtitle => '切换当前查看的课表周';

  @override
  String get courseWeeksAll => '全周';

  @override
  String get courseWeeksOdd => '单周';

  @override
  String get courseWeeksEven => '双周';

  @override
  String get courseWeeksSelectAll => '全选';

  @override
  String get courseSettingsTitle => '课表设置';

  @override
  String get courseSettingsSubtitle => '调整学期起点和显示密度';

  @override
  String get courseSettingsPreviewPrefix => '节次预览：';

  @override
  String get courseEditorAddTitle => '新增课程';

  @override
  String get courseEditorEditTitle => '编辑课程';

  @override
  String get courseEditorSubtitle => '按周次、节次和颜色整理课表';

  @override
  String get courseFieldTermStart => '开学日期 (第 1 周的周一)';

  @override
  String get courseFieldTermStartPicker => '开学日期';

  @override
  String get courseFieldTotalWeeks => '总周数';

  @override
  String get courseFieldSessionsPerDay => '每天节数';

  @override
  String get courseFieldSessionMinutes => '每节分钟数';

  @override
  String get courseFieldFirstSessionTime => '第一节开始时间';

  @override
  String get courseFieldFirstSessionTimeSubtitle => '课程表将按这个时间推算后续节次';

  @override
  String get courseFieldBreakMinutes => '课间分钟数';

  @override
  String get courseFieldName => '课程名';

  @override
  String get courseFieldTeacher => '教师';

  @override
  String get courseFieldLocation => '教室';

  @override
  String get courseFieldWeekday => '星期';

  @override
  String get courseFieldStartSection => '第几节开始';

  @override
  String get courseFieldSectionCount => '连上几节';

  @override
  String get courseFieldClassWeeks => '上课周';

  @override
  String get courseFieldColor => '颜色';

  @override
  String get todoEmpty => '今天没有待办，去添加一个吧';

  @override
  String get todoAdd => '添加待办';

  @override
  String get todoMatrix => '四象限';

  @override
  String get todoList => '列表';

  @override
  String get todoPostpone => '顺延';

  @override
  String get todoPriorityNone => '无';

  @override
  String get todoPriorityLow => '低';

  @override
  String get todoPriorityMedium => '中';

  @override
  String get todoPriorityHigh => '高';

  @override
  String get todoPriorityUrgent => '紧急';

  @override
  String get todoQuickAddReminderPreflightFailedPrefix => '提醒权限检查失败，待办未创建：';

  @override
  String get todoQuickAddReminderSyncFailedPrefix => '待办已创建，但提醒未能确认注册：';

  @override
  String get calendarMonth => '月';

  @override
  String get calendarWeek => '周';

  @override
  String get calendarDay => '日';

  @override
  String get calendarEmpty => '这一天没有事项';

  @override
  String get focusStart => '开始专注';

  @override
  String get focusPause => '暂停';

  @override
  String get focusResume => '继续';

  @override
  String get focusReset => '重置';

  @override
  String get reminderHealth => '通知健康';

  @override
  String get reminderTestNotification => '发送测试通知';

  @override
  String get reminderSnooze5min => '5 分钟后';

  @override
  String get reminderSnooze10min => '10 分钟后';

  @override
  String get reminderSnooze30min => '30 分钟后';

  @override
  String get reminderKindPush => '通知';

  @override
  String get reminderKindPopup => '弹出框';

  @override
  String get reminderKindAlarm => '闹钟';

  @override
  String get reminderKindOff => '关闭';

  @override
  String get reminderTodoTitlePrefix => '提醒：';

  @override
  String get widgetNoScheduleToday => '今日没有日程';

  @override
  String get widgetTodayPrefix => '今日：';

  @override
  String get widgetFocusCountingUp => '正计时专注中';

  @override
  String get widgetFocusCountdown => '专注倒计时';

  @override
  String get widgetShortBreakCountdown => '短休息倒计时';

  @override
  String get widgetLongBreakCountdown => '长休息倒计时';

  @override
  String get widgetFocusNotStarted => '今日还未专注';

  @override
  String get widgetFocusTodayPrefix => '今日专注 ';

  @override
  String get widgetFocusTodaySuffix => ' 次';

  @override
  String get widgetHabitAllDone => '习惯已全部完成';

  @override
  String get widgetHabitProgressPrefix => '习惯完成 ';

  @override
  String get widgetHabitProgressSuffix => '%';

  @override
  String get widgetStreakPrefix => '当前连续 ';

  @override
  String get widgetStreakSuffix => ' 天';

  @override
  String get widgetNextFocusSuffix => ' 分钟专注';

  @override
  String get widgetHabitQuickCheckHint => '点击进入习惯打卡';

  @override
  String get widgetHabitCheckinPrefix => '打卡：';

  @override
  String get widgetDaysRemainingPrefix => '还有 ';

  @override
  String get widgetDaysRemainingSuffix => ' 天';

  @override
  String get widgetCourseSectionPrefix => '';

  @override
  String get widgetCourseSectionSuffix => '节 ';

  @override
  String get widgetTodoTop3Empty => '今天没有未完成待办';

  @override
  String get widgetGoalEmpty => '暂无进行中目标';

  @override
  String get widgetGoalHint => '本周目标保持推进';

  @override
  String get widgetAnniversaryEmpty => '暂无近期纪念日';

  @override
  String get widgetCourseEmpty => '今日暂无课程';

  @override
  String get widgetNoteEmpty => '暂无随手记';

  @override
  String get widgetDiaryEmpty => '暂无日记';

  @override
  String get widgetScheduleOpenCalendar => '打开日历查看完整安排';

  @override
  String get widgetScheduleTimezoneHint => '提醒会跟随系统时区';

  @override
  String get widgetCalendarMonthSummary => '本月日期 · 今日已标记';

  @override
  String get widgetHabitPending => '今日习惯待打卡';

  @override
  String get widgetStreakRecordPrefix => '连续记录 ';

  @override
  String get timeAuditTitle => '时间足迹';

  @override
  String get timeAuditAddManual => '补记';

  @override
  String get timeAuditWeeklyOverview => '本周时间分布';

  @override
  String get timeAuditCopyReport => '复制报告';

  @override
  String get timeAuditReportCopied => '时间足迹报告已复制';

  @override
  String get timeAuditRangeToday => '今日';

  @override
  String get timeAuditRangeWeek => '本周';

  @override
  String get timeAuditRangeMonth => '本月';

  @override
  String get timeAuditRangeAll => '全部';

  @override
  String get timeAuditSegmentToday => '今天';

  @override
  String get timeAuditViewTimeline => '时间线';

  @override
  String get timeAuditViewCategory => '分类';

  @override
  String get timeAuditViewCalendar => '日历';

  @override
  String get timeAuditViewTrend => '趋势';

  @override
  String get timeAuditEmptySuffix => '暂无时间记录';

  @override
  String get timeAuditCategoryView => '分类视图';

  @override
  String get timeAuditSourceBreakdown => '来源分布';

  @override
  String get timeAuditCalendarView => '日历视图';

  @override
  String get timeAuditTrendView => '趋势视图';

  @override
  String get timeAuditInvestmentSuffix => '投入';

  @override
  String get timeAuditEntryCount => '记录数';

  @override
  String get timeAuditEntryCountSuffix => ' 条';

  @override
  String get timeAuditDefaultTitle => '时间记录';

  @override
  String get timeAuditSheetAddTitle => '补记时间';

  @override
  String get timeAuditSheetEditTitle => '编辑时间';

  @override
  String get timeAuditFieldTitle => '标题';

  @override
  String get timeAuditFieldCategory => '分类';

  @override
  String get timeAuditFieldStart => '开始';

  @override
  String get timeAuditFieldEnd => '结束';

  @override
  String get timeAuditFieldMinutes => '分钟数';

  @override
  String get timeAuditFieldNote => '备注';

  @override
  String get timeAuditPickerStartDate => '开始日期';

  @override
  String get timeAuditPickerStartTime => '开始时间';

  @override
  String get timeAuditPickerEndDate => '结束日期';

  @override
  String get timeAuditPickerEndTime => '结束时间';

  @override
  String get timeAuditReportTitle => '时间足迹报告';

  @override
  String get timeAuditReportRange => '范围';

  @override
  String get timeAuditReportTotal => '总投入';

  @override
  String get timeAuditReportCategory => '分类分布';

  @override
  String get timeAuditReportDetails => '明细';

  @override
  String get shareTitle => '共享空间';

  @override
  String get shareCreateInvite => '生成邀请码';

  @override
  String get shareAcceptInvite => '加入空间';

  @override
  String get shareRoleOwner => '拥有者';

  @override
  String get shareRoleEditor => '可编辑';

  @override
  String get shareRoleViewer => '只读';

  @override
  String get unitMinute => '分钟';

  @override
  String get unitMin => '分';

  @override
  String get unitHour => '小时';

  @override
  String get unitDay => '天';

  @override
  String get repeatEveryDay => '每天';

  @override
  String get repeatWeekdays => '工作日';

  @override
  String get habitActiveWeekdays => '生效星期';

  @override
  String get habitActiveWeekdaysHint => '勾选习惯在哪些天生效，未勾选的日子不计入统计';

  @override
  String get habitActiveWeekdaysReminderHint => '每周提醒日与生效星期相互独立，保存后互不改动';

  @override
  String get syncStatusTitle => '云同步';

  @override
  String get syncStateNever => '尚未同步';

  @override
  String get syncStateNeverHint => '登录并开启云同步后，数据会自动备份到云端';

  @override
  String get syncStateSyncing => '正在同步…';

  @override
  String get syncStateSynced => '已同步';

  @override
  String get syncStateFailed => '同步失败';

  @override
  String get syncLastSyncPrefix => '上次同步 ';

  @override
  String get syncPendingBadge => '待同步';

  @override
  String get syncStateAutoRetryHint => '将在后台自动重试';

  @override
  String get greetingSeparator => '，';

  @override
  String get todayNoDue => '无截止';

  @override
  String get todayNoDueDate => '无截止日期';

  @override
  String get todayTodosEmpty => '今天暂无待办，点击查看或添加任务';

  @override
  String get todoStatusOverdue => '逾期';

  @override
  String get todoStatusDueSoon => '临期';

  @override
  String get todoStatusNormal => '正常';

  @override
  String get habitWeeklyTodayPrefix => '今日 ';

  @override
  String get habitWeeklyTodaySuffix => ' 达标';

  @override
  String get habitWeeklyProgress => '进度';

  @override
  String get habitWeekday1 => '一';

  @override
  String get habitWeekday2 => '二';

  @override
  String get habitWeekday3 => '三';

  @override
  String get habitWeekday4 => '四';

  @override
  String get habitWeekday5 => '五';

  @override
  String get habitWeekday6 => '六';

  @override
  String get habitWeekday7 => '日';

  @override
  String get habitGroupUngrouped => '未分组';

  @override
  String get habitGroupTodaySuffix => ' 今日达标';

  @override
  String get habitGroupMoreHabitsPrefix => '还有 ';

  @override
  String get habitGroupMoreHabitsSuffix => ' 个习惯，请进入今日打卡或习惯详情查看';

  @override
  String get habitBestShort => '最佳';

  @override
  String get todoKanbanNoPriority => '无优先级';

  @override
  String get todoKanbanNoDue => '无截止日';

  @override
  String get todoKanbanOverdue => '已逾期';

  @override
  String get todoKanbanToday => '今天';

  @override
  String get todoKanbanWithin7Days => '7 天内';

  @override
  String get todoKanbanLater => '更晚';

  @override
  String get todoKanbanNoTag => '无标签';

  @override
  String get todoKanbanDefaultList => '默认清单';

  @override
  String get authLogout => '退出登录';

  @override
  String get mineBadgeAdmin => '管理员';

  @override
  String get mineViewProfileSemantics => '查看个人资料';

  @override
  String get mineAvatarView => '查看头像';

  @override
  String get mineAvatarEdit => '修改头像';

  @override
  String get mineAvatarTitle => '头像';

  @override
  String get mineMeFallback => '我';

  @override
  String get mineStatsTodos => '待办完成';

  @override
  String get mineStatsStreak => '连续打卡';

  @override
  String get mineStatsFocus => '本周专注';

  @override
  String get mineStatsProductivity => '效率评分';

  @override
  String get mineGroupActionPlan => '行动计划';

  @override
  String get mineGroupReview => '记录回顾';

  @override
  String get mineGroupSchedule => '日程日期';

  @override
  String get mineGroupPersonal => '个性安全';

  @override
  String get mineGroupData => '数据协作';

  @override
  String get mineGroupNotifications => '通知支持';

  @override
  String get mineTilePomodoro => '番茄专注';

  @override
  String get mineTileMoreApps => '更多应用';

  @override
  String get mineTileMoreAppsSubtitle => '查看隐藏功能';

  @override
  String get mineTileStatistics => '统计报表';

  @override
  String get mineTileAchievements => '成就墙';

  @override
  String get mineTileCourses => '课程表';

  @override
  String get mineTileIntegrations => '扩展功能';

  @override
  String get mineTileBackup => '备份';

  @override
  String get mineTileRestore => '恢复数据';

  @override
  String get mineTileNotificationHistory => '通知记录';

  @override
  String get mineTileNotificationHistoryEmpty => '暂无通知记录';

  @override
  String get mineTileNotificationHistoryCountSuffix => ' 条';

  @override
  String get mineTileNotificationSettings => '通知设置';

  @override
  String get mineTileNotificationSettingsSubtitle => '提醒时间、权限、铃声、已注册提醒和记录保留';

  @override
  String get mineTileAdmin => '管理员后台';

  @override
  String get mineTileFeedback => '许愿与反馈';

  @override
  String get mineTileFeedbackSubtitle => '提交建议并分页查看处理记录';

  @override
  String get mineTileCheckUpdates => '检查更新';

  @override
  String get mineLogoutConfirmTitle => '退出登录？';

  @override
  String get mineLogoutConfirmContent =>
      '退出后会清空本机账号数据（时光币、主题、习惯、待办等本地缓存），重新登录后再从当前账号同步。';

  @override
  String get mineLogoutDone => '已退出登录，本机账号数据已清理';

  @override
  String get mineLogoutCleanupFailed => '已退出登录，本机数据清理失败，将在下次登录前重试';

  @override
  String get profileAvatarFileEmpty => '头像文件为空';

  @override
  String get profileAvatarSaveFailedPrefix => '头像保存失败：';

  @override
  String get profileAvatarPreview => '查看头像';

  @override
  String get profileAvatarEdit => '修改头像';

  @override
  String get profileAvatarTitle => '头像';

  @override
  String get mineUpdateBadge => '有更新';

  @override
  String get mineUpdateBadgeVersionPrefix => '新版 ';

  @override
  String get mineUpdateRequiredTitle => '必须更新';

  @override
  String get mineUpdateCheckTitle => '检查更新';

  @override
  String get mineUpdateCurrentVersionPrefix => '当前版本: ';

  @override
  String get mineUpdateRemoteVersionPrefix => '远端版本: ';

  @override
  String get mineUpdateMinSupportedPrefix => '最低支持版本: ';

  @override
  String get mineUpdateForceBannerTitle => '此版本需要强制更新';

  @override
  String get mineUpdateForceBannerMessage =>
      '当前版本低于管理员设置的最低支持版本，或管理员已要求所有用户更新后继续使用。';

  @override
  String get mineUpdateAvailable => '发现新版本';

  @override
  String get mineUpdateUpToDate => '已是最新版本';

  @override
  String get mineUpdateNotes => '更新内容';

  @override
  String get mineUpdatePackageMissingTitle => '未配置安装包地址';

  @override
  String get mineUpdatePackageMissingMessage =>
      '更新策略已生效，但当前没有可下载的安装包地址。请管理员在发布通道补充安装包。';

  @override
  String get mineUpdatePackageBrokenPrefix => '更新策略已生效，但安装包不可用：';

  @override
  String get mineUpdatePackageBrokenSuffix => '。请管理员在发布通道补充安装包。';

  @override
  String get mineUpdateDownloading => '正在下载更新包';

  @override
  String get mineUpdateDownloadingProgressPrefix => '正在下载 ';

  @override
  String get mineUpdateInstalling => '正在打开安装器';

  @override
  String get mineUpdateInstallDownloaded => '安装已下载包';

  @override
  String get mineUpdateDownloadAndInstall => '下载并安装';

  @override
  String get mineUpdatePackageLabel => '安装包';

  @override
  String get mineUpdateChecking => '正在检查更新...';

  @override
  String get mineUpdateWebAvailable => '发现网页新版本，刷新网页即可载入最新代码。';

  @override
  String get mineUpdateWebRefresh => '刷新网页';

  @override
  String get mineAboutTitle => '多仪';

  @override
  String get mineAboutVersionPrefix => '版本: ';

  @override
  String get mineAboutTagline => 'Flutter 跨平台效率工具';

  @override
  String get mineAboutOk => '好的';

  @override
  String get mineAiAssistant => 'AI 助手';

  @override
  String get mineAiAssistantDisabledMessage =>
      '管理员后台配置 AI 后，这里会显示周回顾、任务拆解和建议生成入口。';

  @override
  String get mineAiReviewTitle => 'AI 每周回顾';

  @override
  String get mineAiCollapse => '收起回顾';

  @override
  String get mineAiExpand => '展开回顾';

  @override
  String get mineAiGenerate => '生成';

  @override
  String get mineAiGeneratedToday => '今日已生成';

  @override
  String get mineAiExpandFull => '展开完整回顾';

  @override
  String get mineAiRangeThisWeek => '本周';

  @override
  String get mineAiRangeLastWeek => '上周';

  @override
  String get mineAiHintPrefix => '点击\"生成\"让 AI 根据';

  @override
  String get mineAiHintSuffix => '完成数据写一段总结与建议，当天会保留结果';

  @override
  String get mineAiSummaryHeaderSuffix => '数据：完成 ';

  @override
  String get mineAiSummaryTodosSuffix => ' 项待办，专注 ';

  @override
  String get mineAiSummaryFocusSuffix => ' 分钟，习惯连续打卡 ';

  @override
  String get mineAiSummaryStreakSuffix => ' 天。';

  @override
  String get appLockPinHintEnter => '输入 PIN 解锁';

  @override
  String get backupOverwriteWillDeleteMissing => '备份中不存在的本机数据将被删除。';

  @override
  String get calendarContentDatePickerSubtitle => '手动跳转到指定日期';

  @override
  String get calendarContentDatePickerTitle => '选择日期';

  @override
  String get calendarContentTimePickerStartTime => '开始时间';

  @override
  String get calendarPickerStartDate => '开始日期';

  @override
  String get calendarPickerEndDate => '结束日期';

  @override
  String get calendarPickerStartTime => '开始时间';

  @override
  String get calendarPickerEndTime => '结束时间';

  @override
  String get calendarPickerRescheduleDate => '调整日期';

  @override
  String get calendarPickerAdjustStartTime => '调整开始时间';

  @override
  String get calendarPickerAdjustStartTimeSubtitle => '保留当前日期和时长，自动更新结束时间';

  @override
  String get calendarPickerAdjustDueTime => '调整时间';

  @override
  String get calendarPickerAdjustDueTimeSubtitle => '保留当前日期，只调整当天截止时间';

  @override
  String get pickerActionToday => '今天';

  @override
  String get pickerEmpty => '暂无可选项';

  @override
  String get pickerNotSet => '未设置';

  @override
  String get pickerDateIgnoreYear => '忽略年份';

  @override
  String get pickerDateIgnoreYearDesc => '适合生日、纪念日每年重复';

  @override
  String get pickerDateNextMonth => '下个月';

  @override
  String get pickerDatePrevMonth => '上个月';

  @override
  String get pickerDateTitle => '选择日期';

  @override
  String get pickerLunarDay => '日';

  @override
  String get pickerLunarLeapMonth => '闰月';

  @override
  String get pickerLunarMonth => '月';

  @override
  String get pickerTimeEarlier30m => '提前 30 分';

  @override
  String get pickerTimeLater30m => '延后 30 分';

  @override
  String get pickerTimePresetEvening => '晚上 20:00';

  @override
  String get pickerTimePresetMorning => '上午 09:00';

  @override
  String get pickerTimePresetNextSlot => '下一提醒点';

  @override
  String get pickerTimePresetNoon => '中午 12:00';

  @override
  String get pickerTimePresetNow => '现在';

  @override
  String get pickerTimeTitle => '选择时间';

  @override
  String get pickerWeekdayFri => '五';

  @override
  String get pickerWeekdayMon => '一';

  @override
  String get pickerWeekdaySat => '六';

  @override
  String get pickerWeekdaySun => '日';

  @override
  String get pickerWeekdayThu => '四';

  @override
  String get pickerWeekdayTue => '二';

  @override
  String get pickerWeekdayWed => '三';

  @override
  String get widgetHabitNoneToday => '今天没有安排习惯';

  @override
  String get widgetHabitView => '查看习惯';

  @override
  String get aiScheduleScreenTitle => 'AI 创建日程';

  @override
  String get aiScheduleAiDisabledTitle => 'AI 未启用';

  @override
  String get aiScheduleAiDisabledMessage => '将使用本地时间解析生成草稿，仍可确认创建日程或待办。';

  @override
  String get aiScheduleInputTitle => '输入安排';

  @override
  String get aiScheduleInputSubtitle => '例如：明天下午 3 点和产品开会，提前提醒我';

  @override
  String get aiScheduleInputHint => '输入自然语言安排、待办或提醒';

  @override
  String get aiScheduleEmptyInput => '请输入要创建的日程或待办内容';

  @override
  String get aiScheduleRecognize => '识别并生成确认信息';

  @override
  String get aiScheduleRecognizing => '识别中';

  @override
  String get aiScheduleErrorTitle => 'AI 创建失败';

  @override
  String get aiScheduleDraftTitle => '已生成确认草稿';

  @override
  String get aiScheduleDraftAiMessage => '请核对类型、标题、时间和提醒设置。';

  @override
  String get aiScheduleDraftFallbackMessage =>
      '当前不是完整 AI 识别结果，请确认本地兜底草稿无误后再写入。';

  @override
  String get aiScheduleWarningAiIncomplete => 'AI 识别结果不完整';

  @override
  String get aiScheduleWarningLocalFallback => 'AI 识别未完成';

  @override
  String get aiScheduleWarningAppendix => '请核对下方本地草稿后再确认创建。';

  @override
  String get aiScheduleConfirmCardTitle => '确认创建内容';

  @override
  String get aiScheduleTypeLabel => '类型';

  @override
  String get aiScheduleTitleLabel => '标题';

  @override
  String get aiScheduleStartLabel => '开始';

  @override
  String get aiScheduleEndLabel => '结束';

  @override
  String get aiScheduleReminderLabel => '提醒';

  @override
  String get aiScheduleNotesLabel => '备注';

  @override
  String get aiScheduleSubtasksLabel => '子任务';

  @override
  String get aiScheduleCalendarType => '日程';

  @override
  String get aiScheduleTodoType => '待办';

  @override
  String get aiScheduleReminderEnabled => '已开启系统推送提醒';

  @override
  String get aiScheduleReminderDisabled => '未设置提醒';

  @override
  String get aiScheduleSaving => '保存中';

  @override
  String get aiScheduleCreate => '确认创建';

  @override
  String get aiScheduleDone => '完成';

  @override
  String get aiScheduleViewDetails => '查看详情';

  @override
  String get aiScheduleCreatedEvent => '日程已创建';

  @override
  String get aiScheduleCreatedTask => '待办已创建';

  @override
  String get aiScheduleCreatedEventWithReminderIssue => '日程已创建，但提醒未注册';

  @override
  String get aiScheduleCreatedTaskWithReminderIssue => '待办已创建，但提醒未注册';

  @override
  String aiScheduleCreatedItemSummary(String typeLabel, String title) {
    return '$typeLabel：$title';
  }

  @override
  String aiScheduleStartSummaryCalendar(String value) {
    return '开始时间：$value';
  }

  @override
  String aiScheduleStartSummaryTodo(String value) {
    return '计划时间：$value';
  }

  @override
  String get aiScheduleLocalSaved => '已保存到本机';

  @override
  String get aiScheduleLocalSavedCalendar => '日程已保存到本机';

  @override
  String get aiScheduleLocalSavedTodo => '待办已保存到本机';

  @override
  String get aiScheduleReminderRegistered => '提醒已注册到系统通知';

  @override
  String get aiScheduleTaskReminderSubmitted => '待办提醒已提交系统注册';

  @override
  String get aiScheduleGenericReminderIssue => '提醒未注册';

  @override
  String get aiScheduleAccountChanged => '账号已切换，请重新打开页面后再操作。';

  @override
  String get aiScheduleInputChanged => '输入内容已变更，请重新识别后再创建。';

  @override
  String get aiScheduleGenericSaveFailed => '保存失败，请重试。';

  @override
  String get aiScheduleAlarmPermissionRequired =>
      'AI 待办提醒注册失败：系统通知权限未开启，闹钟提醒未注册。请开启通知权限后重新保存提醒。';

  @override
  String get aiScheduleEventReminderIssueTitle => 'AI 日程提醒注册失败';

  @override
  String get aiScheduleTaskReminderIssueTitle => 'AI 待办提醒注册失败';

  @override
  String get aiScheduleCalendarSubtitle => 'AI 创建';

  @override
  String get aiScheduleCalendarSubtitleAllDay => 'AI 创建 · 全天';

  @override
  String get aiScheduleCalendarReminderTitle => '日程提醒';

  @override
  String get aiScheduleSourceAi => 'AI 已识别输入内容，请确认无误后创建';

  @override
  String get aiScheduleSourceAiWithLocalFallback => 'AI 返回不完整，已用本地解析补全';

  @override
  String get aiScheduleSourceLocalParser => '当前使用本地解析结果，请确认时间和类型';

  @override
  String get aiScheduleWarningReminderNotice => '提醒提示';

  @override
  String get aiScheduleWarningNotice => '提示';

  @override
  String get aiScheduleWarningUnavailable => 'AI 服务暂不可用，已准备本地兜底草稿。';

  @override
  String get aiScheduleWarningNoUsableDraft => 'AI 未返回可用草稿，已准备本地兜底草稿。';

  @override
  String get aiScheduleWarningInvalidResponse => 'AI 返回内容无法读取，已准备本地兜底草稿。';

  @override
  String get aiScheduleWarningMissingReminderTime => '未识别到具体提醒时间，提醒已关闭。';

  @override
  String get aiScheduleWarningReviewDraft => '请核对草稿内容后再确认创建。';

  @override
  String get aiScheduleWarningGenericFallback => '已准备本地草稿供你核对。';

  @override
  String get aiScheduleErrorNotEnabled => 'AI 功能未启用，请联系管理员。';

  @override
  String get aiScheduleErrorQuotaExceeded => '今日 AI 额度已用尽，请明日再试。';

  @override
  String get aiScheduleErrorRateLimit => '请求过于频繁，请稍候重试。';

  @override
  String get aiScheduleErrorTimeout => 'AI 服务响应超时，请稍后重试。';

  @override
  String get aiScheduleErrorGeneric => '创建草稿失败，请重试。';

  @override
  String get widgetHostSupportIosTitle => '从主屏幕添加小组件';

  @override
  String get widgetHostSupportWebTitle => '网页版小组件预览';

  @override
  String get widgetHostSupportMobileTitle => '手机端小组件预览';

  @override
  String get widgetHostSupportIosMessage => '在主屏幕长按空白处，打开小组件图库，搜索“多仪”并添加。';

  @override
  String get widgetHostSupportMobileMessage =>
      '这里可以查看小组件样式；添加到主屏幕需使用 Android 或 iOS 版多仪。';

  @override
  String get widgetHostAddIosAction => '查看添加步骤';

  @override
  String get widgetHostAddMobileAction => '手机端使用方式';

  @override
  String get widgetHostHelpMobileTitle => '在手机端使用小组件';

  @override
  String get widgetAddDialogTitle => '添加到桌面';

  @override
  String get widgetHostHelpIosMessage =>
      '长按主屏幕空白处，点击“编辑”或“+”，进入小组件图库。搜索“多仪”，选择尺寸后点击“添加小组件”。系统提供小、中、大尺寸；支持的 iPad 还可选择超大尺寸。实际尺寸以系统图库为准。\n\niPhone（iOS 16 及以上）或 iPad（iPadOS 17 及以上）：长按锁定屏幕，点“自定”，再点小组件区域并选择多仪。';

  @override
  String get widgetHostHelpMobileMessage =>
      '本页展示小组件样式预览。要在手机主屏幕使用，请安装并打开 Android 或 iOS 版多仪。Android 可从 App 内添加，或长按主屏幕空白处选择小组件；iOS 请从主屏幕的小组件图库搜索“多仪”并添加。';

  @override
  String get widgetHostTipsIosMessage =>
      '实际尺寸在系统小组件图库中选择。小组件显示最近同步的内容；若内容较旧，打开多仪后刷新。';

  @override
  String get widgetHostTipsPreviewMessage =>
      '这里的预览不等同于已添加的桌面小组件。实际添加与使用需在 Android 或 iOS 手机端完成。';

  @override
  String get widgetTipsBannerMessage =>
      '紧凑版和详细版为固定尺寸；标准版在桌面支持时可长按调整大小。要更换尺寸版本，请移除后重新添加。添加时需在系统弹窗中确认；若未出现弹窗，请检查多仪的桌面小组件权限。';

  @override
  String get widgetHostStyleCompactDescription => '紧凑样式，突出核心信息。';

  @override
  String get widgetHostStyleDetailedDescription => '详细样式，展示更多内容。';

  @override
  String get widgetHostStyleStandardDescription => '标准样式，平衡信息与留白。';

  @override
  String widgetHostStyleDescriptionIos(String description) {
    return '$description 实际尺寸在系统图库中选择。';
  }

  @override
  String widgetStyleSyncSuccess(String modeLabel) {
    return '小组件样式已设为$modeLabel。';
  }

  @override
  String widgetPreviewStyleSyncSuccess(String modeLabel) {
    return '预览样式已设为$modeLabel。';
  }

  @override
  String get widgetRefreshTooltip => '刷新小组件';

  @override
  String get widgetPreviewHeaderTitle => '桌面小组件预览';

  @override
  String get widgetStylePanelTitle => '小组件样式';

  @override
  String get widgetCategoryAll => '全部';

  @override
  String get widgetCategoryProductivity => '效率';

  @override
  String get widgetCategoryLife => '生活';

  @override
  String get widgetCatalogTodoTitle => '今日待办';

  @override
  String get widgetCatalogCalendarTitle => '月历';

  @override
  String get widgetCatalogScheduleTitle => '今日日程';

  @override
  String get widgetCatalogGoalTitle => '目标';

  @override
  String get widgetCatalogNoteTitle => '随手记';

  @override
  String get widgetCatalogAnniversaryTitle => '纪念日';

  @override
  String get widgetCatalogTodoSubtitle => '桌面查看与完成待办，支持快速记一笔';

  @override
  String get widgetCatalogFocusSubtitle => '展示今日专注次数、时长与下一轮计划';

  @override
  String get widgetCatalogHabitSubtitle => '查看今日完成率、连续记录与快捷打卡';

  @override
  String get widgetCatalogCalendarSubtitle => '月视图概览与今日标记';

  @override
  String get widgetCatalogScheduleSubtitle => '查看今日按时间排序的日程安排';

  @override
  String get widgetCatalogGoalSubtitle => '展示当前目标与推进进度';

  @override
  String get widgetCatalogCourseSubtitle => '展示今日课程节次、教室与时间';

  @override
  String get widgetCatalogNoteSubtitle => '查看最近更新的便签与随手记';

  @override
  String get widgetCatalogAnniversarySubtitle => '倒数重要日子与累计天数';

  @override
  String get widgetCatalogDiarySubtitle => '回顾最近记录的心情与日记摘要';

  @override
  String get widgetDisplayModeCompactLabel => '紧凑';

  @override
  String get widgetDisplayModeDetailedLabel => '详细';

  @override
  String get widgetDisplayModeStandardLabel => '标准';

  @override
  String get widgetDisplayModeCompactDescription => '紧凑版，固定尺寸，突出核心信息';

  @override
  String get widgetDisplayModeDetailedDescription => '详细版，固定尺寸，内容随可用空间调整';

  @override
  String get widgetDisplayModeStandardDescription =>
      '标准版，内容随可用空间调整；桌面支持时可长按调整大小';

  @override
  String get widgetStyleSyncFailed => '桌面小组件样式同步失败，请重试';

  @override
  String get widgetCannotOpenSettings => '无法打开应用设置，请手动进入系统设置检查多仪权限';

  @override
  String get widgetRefreshSuccess => '小组件已刷新';

  @override
  String get widgetRefreshFailed => '刷新失败，请稍后重试';

  @override
  String get widgetPinSupportCheckingTitle => '正在检查桌面小组件支持';

  @override
  String get widgetPinSupportCheckingMessage => '正在检测当前桌面是否支持直接添加小组件。';

  @override
  String get widgetPinSupportSupportedTitle => '当前桌面支持应用内添加';

  @override
  String get widgetPinSupportSupportedMessage => '可从 App 添加到桌面，请在系统弹窗中确认。';

  @override
  String get widgetPinSupportUnsupportedPlatformTitle => '当前平台不支持应用内添加';

  @override
  String get widgetPinSupportUnsupportedLauncherTitle => '当前桌面不支持应用内添加';

  @override
  String get widgetPinSupportPermissionDeniedTitle => '桌面添加权限未通过';

  @override
  String get widgetPinSupportConfirmationBlockedTitle => '桌面确认弹窗可能被拦截';

  @override
  String get widgetPinSupportInvalidKindTitle => '当前小组件类型不可添加';

  @override
  String get widgetPinSupportFallbackTitle => '当前桌面可能不支持应用内添加';

  @override
  String get widgetPinSupportUnsupportedPlatformMessage =>
      '请在 Android 手机上通过系统小组件列表添加多仪。';

  @override
  String get widgetPinSupportUnsupportedLauncherMessage =>
      '当前桌面启动器未开放应用内添加，请从系统小组件列表选择添加。';

  @override
  String get widgetPinSupportPermissionDeniedMessage =>
      '系统未允许多仪添加桌面小组件，请在系统设置中开启权限后重试。';

  @override
  String get widgetPinSupportConfirmationBlockedMessage =>
      '桌面确认弹窗可能被拦截，请检查后台弹窗或悬浮窗权限后重试。';

  @override
  String get widgetPinSupportInvalidKindMessage => '请更新应用后重试。';

  @override
  String get widgetPinSupportFallbackMessage =>
      '若未弹出确认框，请打开系统设置检查桌面小组件与后台弹窗权限，或从系统小组件列表添加。';

  @override
  String get widgetActionAppSettings => '应用设置';

  @override
  String get widgetActionRecheck => '重新检测';

  @override
  String get widgetActionOpenPermissions => '打开权限设置';

  @override
  String get widgetActionGotIt => '知道了';

  @override
  String get widgetPinHelpUnsupportedMessage =>
      '当前桌面不支持应用内直接添加小组件。请长按桌面空白处，从系统小组件列表添加。';

  @override
  String get widgetPinHelpUnsupportedPlatformMessage =>
      '当前平台不支持直接添加 Android 桌面小组件。请在 Android 手机上从系统小组件列表添加多仪。';

  @override
  String get widgetPinHelpUnsupportedLauncherMessage =>
      '当前桌面启动器未开放应用内添加，请长按桌面空白处从系统小组件列表添加。';

  @override
  String get widgetPinHelpPermissionDeniedMessage =>
      '系统未允许多仪添加桌面小组件。请在系统设置中开启权限后重试，或从系统小组件列表添加。';

  @override
  String get widgetPinHelpConfirmationBlockedMessage =>
      '系统确认弹窗可能被拦截，请检查后台弹窗或悬浮窗权限后重试。';

  @override
  String get widgetPinHelpInvalidKindMessage => '当前小组件类型暂不支持添加，请更新应用后重试。';

  @override
  String get widgetPinHelpUnavailableMessage =>
      '无法发起添加请求，请检查桌面权限后重试，或从系统小组件列表添加。';

  @override
  String get widgetPinHelpRequestedMessage => '已发起添加请求，请在桌面系统弹窗中确认。';

  @override
  String get widgetPinConfirmationInvalidWidgetIdTitle => '添加未完成';

  @override
  String get widgetPinConfirmationInvalidWidgetIdMessage =>
      '桌面未成功创建小组件，请重试或从系统小组件列表添加。';

  @override
  String get widgetPinConfirmationTimeoutTitle => '等待桌面确认';

  @override
  String get widgetPinConfirmationTimeoutMessage =>
      '已发起添加请求，但尚未收到系统确认。请查看桌面是否有确认弹窗，或在系统设置中检查权限。';

  @override
  String get widgetPinConfirmationUnavailableTitle => '添加异常';

  @override
  String get widgetPinConfirmationUnavailableMessage =>
      '桌面未返回添加结果。请重试或从系统小组件列表添加。';

  @override
  String get widgetPinConfirmationSuccessTitle => '已添加';

  @override
  String get widgetPinConfirmationSuccessMessage => '桌面小组件已添加。';

  @override
  String get widgetCheckingDesktopSupport => '正在检查桌面支持';

  @override
  String get widgetPinDisabledAndroidOnly => '仅 Android 支持应用内添加';

  @override
  String get widgetPinDisabledPicker => '请从系统小组件列表添加';

  @override
  String get widgetPinDisabledHelp => '查看添加帮助';

  @override
  String get widgetLoadingStyle => '正在读取样式';

  @override
  String get widgetStyleLoadFailed => '样式读取失败，请重试或重新选择';

  @override
  String get widgetStyleSyncPending => '已保存所选样式，桌面小组件尚未确认同步。请重试或刷新。';

  @override
  String get widgetUpdatingStyle => '正在更新样式';

  @override
  String get widgetRequestingAdd => '正在请求添加';

  @override
  String widgetAddWidgetButtonLabel(
    String modeLabel,
    String launcherRequestLabel,
  ) {
    return '添加$modeLabel $launcherRequestLabel';
  }

  @override
  String widgetPinInitiatedSnackBar(String modeLabel) {
    return '已发起添加，请在系统弹窗中确认添加$modeLabel小组件。';
  }

  @override
  String widgetPinSuccessSnackBar(String modeLabel) {
    return '已添加$modeLabel小组件到桌面。';
  }

  @override
  String get widgetTipsBannerTitle => '桌面小组件使用提示';

  @override
  String get widgetDesktopWebTitle => '电脑网页版显示日历';

  @override
  String get widgetDesktopWebMessage =>
      '桌面小组件依赖 Android 或 iOS 系统；电脑网页版默认隐藏小组件入口，保留月历预览和日历入口。';

  @override
  String get widgetDesktopWebTileSubtitle => '电脑网页版默认展示日历，不显示添加桌面小组件按钮';

  @override
  String get widgetDesktopWebOpenCalendar => '打开日历';

  @override
  String get widgetPreviewTodoTitle => '今日待办';

  @override
  String get widgetPreviewScheduleTitle => '今日日程';

  @override
  String widgetPreviewSampleBadge(String title) {
    return '示例 · $title';
  }

  @override
  String widgetSampleHeaderDate(
    String cellLabel,
    String monthLabel,
    String day,
  ) {
    return '$cellLabel · $monthLabel/$day';
  }

  @override
  String get widgetRefreshPreviewTooltip => '刷新预览';

  @override
  String widgetCalendarMonthHeader(String yearText, String monthLabel) {
    return '$yearText年$monthLabel月';
  }

  @override
  String get widgetTodoItem1 => '整理今日计划';

  @override
  String get widgetTodoItem2 => '项目方案复盘';

  @override
  String get widgetTodoItem3 => '晚间运动 30 分钟';

  @override
  String get widgetTodoSummaryCount => '今日待办 · 3 项';

  @override
  String get widgetTodoQuickAdd => '+ 记一笔';

  @override
  String get widgetFocusMetricSessions => '今日专注';

  @override
  String get widgetFocusMetricDuration => '时长(分)';

  @override
  String get widgetFocusMetricNext => '下一轮(分)';

  @override
  String get widgetFocusTimerUnit => '分钟';

  @override
  String get widgetFocusStartButton => '开始 25 分钟专注';

  @override
  String get widgetFocusLine1 => '今日专注 2 次 · 深度工作 50 分钟';

  @override
  String get widgetFocusLine2 => '下一轮：25 分钟专注';

  @override
  String get widgetFocusLine3 => '点击开始专注';

  @override
  String get widgetHabitTitle => '今日习惯';

  @override
  String get widgetCalendarCurrentDate => '5月17日 · 周日';

  @override
  String get widgetCalendarCurrentDay => '5月17日';

  @override
  String get widgetHabitLine1 => '· 晚间拉伸 · 今日待打卡';

  @override
  String get widgetHabitLine2 => '· 连续记录 5 天';

  @override
  String get widgetHabitCheckInButton => '打卡：晚间拉伸';

  @override
  String get widgetScheduleItem1 => '09:00 今日计划 · 到点提醒';

  @override
  String get widgetScheduleItem2 => '14:30 团队例会';

  @override
  String get widgetScheduleItem3 => '19:00 晚间复盘';

  @override
  String get widgetGoalItem1 => '发版准备 · 68%';

  @override
  String get widgetGoalItem2 => '本周运动 3/5 次';

  @override
  String get widgetGoalItem3 => '晚间复盘 · 今日待推进';

  @override
  String get widgetCourseItem1 => '第 1-2 节 高等数学 · 教 203';

  @override
  String get widgetCourseItem2 => '第 3-4 节 产品设计 · 线上';

  @override
  String get widgetCourseItem3 => '第 5-6 节 英语 · 教 305';

  @override
  String get widgetNoteItem1 => '会议纪要';

  @override
  String get widgetNoteItem2 => '灵感清单';

  @override
  String get widgetNoteItem3 => '读书摘录';

  @override
  String get widgetAnniversaryItem1 => '相识纪念日 · 还有 6 天';

  @override
  String get widgetAnniversaryItem2 => '入职周年 · 还有 18 天';

  @override
  String get widgetAnniversaryItem3 => '旅行纪念 · 还有 32 天';

  @override
  String get widgetDiaryItem1 => '5/17 今天完成了专注复盘';

  @override
  String get widgetDiaryItem2 => '5/16 记录一次散步';

  @override
  String get widgetDiaryItem3 => '5/15 睡前整理心情';

  @override
  String get widgetCalendarMonthJan => '1';

  @override
  String get widgetCalendarMonthFeb => '2';

  @override
  String get widgetCalendarMonthMar => '3';

  @override
  String get widgetCalendarMonthApr => '4';

  @override
  String get widgetCalendarMonthMay => '5';

  @override
  String get widgetCalendarMonthJun => '6';

  @override
  String get widgetCalendarMonthJul => '7';

  @override
  String get widgetCalendarMonthAug => '8';

  @override
  String get widgetCalendarMonthSep => '9';

  @override
  String get widgetCalendarMonthOct => '10';

  @override
  String get widgetCalendarMonthNov => '11';

  @override
  String get widgetCalendarMonthDec => '12';

  @override
  String get dataSettingsThemeSaveFailed => '主题保存失败';

  @override
  String get dataSettingsRewardShopReason => '奖励商店主题装饰';

  @override
  String dataSettingsRedeemThemeTitle(String name) {
    return '兑换主题：$name';
  }

  @override
  String dataSettingsRedeemFocusBackdropTitle(String name) {
    return '兑换专注背景：$name';
  }

  @override
  String dataSettingsRedeemAvatarFrameTitle(String name) {
    return '兑换头像框：$name';
  }

  @override
  String dataSettingsRedeemCardSkinTitle(String name) {
    return '兑换卡片皮肤：$name';
  }

  @override
  String dataSettingsInsufficientCoins(int diff) {
    return '时光币不足，还差 $diff';
  }

  @override
  String dataSettingsThemeApplied(String name) {
    return '已启用 $name';
  }

  @override
  String dataSettingsThemeRedeemedAndApplied(String name) {
    return '已兑换并启用 $name';
  }

  @override
  String dataSettingsWidgetBackgroundSwitched(String label) {
    return '小组件背景已切换为 $label';
  }

  @override
  String get dataSettingsUnlockThemeFirst => '请先解锁该主题';

  @override
  String dataSettingsWidgetCardSkinSwitched(String label) {
    return '小组件卡片皮肤已切换为 $label';
  }

  @override
  String get dataSettingsUnlockCardSkinFirst => '请先解锁该卡片皮肤';

  @override
  String get dataSettingsWidgetFollowCurrentTheme => '跟随当前主题';

  @override
  String get dataSettingsWidgetFollowCardSkin => '跟随卡片皮肤';

  @override
  String get dataSettingsWidgetThemeTitle => '桌面小组件主题';

  @override
  String get dataSettingsWidgetThemeSubtitle => '单独调整桌面小组件背景和卡片皮肤';

  @override
  String get dataSettingsWidgetBackgroundLabel => '背景图';

  @override
  String get dataSettingsWidgetCardSkinLabel => '卡片皮肤';

  @override
  String dataSettingsCoinCount(int count) {
    return '时光币 $count';
  }

  @override
  String dataSettingsCoinCost(int cost) {
    return '$cost 币';
  }

  @override
  String get dataSettingsFocusBackdropSectionTitle => '专注背景';

  @override
  String get dataSettingsFocusBackdropSectionSubtitle => '用时光币兑换番茄钟卡片装饰';

  @override
  String get dataSettingsAvatarFrameSectionTitle => '头像框';

  @override
  String get dataSettingsAvatarFrameSectionSubtitle => '用时光币兑换我的页头像装饰';

  @override
  String get dataSettingsCardSkinSectionTitle => '卡片皮肤';

  @override
  String get dataSettingsCardSkinSectionSubtitle => '用时光币兑换信息卡片质感';

  @override
  String get dataSettingsWidgetSyncNoticeTitle => '小组件主题';

  @override
  String get dataSettingsWidgetSyncNoticeSubtitle => '背景图和卡片皮肤会同步到手机桌面小组件';

  @override
  String get dataSettingsFocusBackdropClassicName => '经典专注';

  @override
  String get dataSettingsFocusBackdropMorningName => '晨光书桌';

  @override
  String get dataSettingsFocusBackdropForestName => '林间深呼吸';

  @override
  String get dataSettingsFocusBackdropOceanName => '海岸静流';

  @override
  String get dataSettingsFocusBackdropNightName => '夜航模式';

  @override
  String get dataSettingsFocusBackdropClassicDescription => '简洁的番茄钟渐变背景';

  @override
  String get dataSettingsFocusBackdropMorningDescription => '适合清晨阅读和学习的暖色背景';

  @override
  String get dataSettingsFocusBackdropForestDescription => '适合长时间深度工作的自然绿色背景';

  @override
  String get dataSettingsFocusBackdropOceanDescription => '适合复盘、写作和低压专注的蓝绿色背景';

  @override
  String get dataSettingsFocusBackdropNightDescription => '适合夜间学习的低亮度深色背景';

  @override
  String get dataSettingsAvatarFrameSimpleName => '简洁头像';

  @override
  String get dataSettingsAvatarFrameGoldenName => '金色勋章框';

  @override
  String get dataSettingsAvatarFrameForestName => '绿叶守护框';

  @override
  String get dataSettingsAvatarFrameAuroraName => '极光能量框';

  @override
  String get dataSettingsAvatarFrameSimpleDescription => '默认头像样式';

  @override
  String get dataSettingsAvatarFrameGoldenDescription => '适合成就达人展示的金色头像框';

  @override
  String get dataSettingsAvatarFrameForestDescription => '适合习惯连续打卡的自然头像框';

  @override
  String get dataSettingsAvatarFrameAuroraDescription => '适合高效专注周的流光头像框';

  @override
  String get dataSettingsCardSkinPlainName => '素净卡片';

  @override
  String get dataSettingsCardSkinPaperName => '纸感计划卡';

  @override
  String get dataSettingsCardSkinMintName => '薄荷清单卡';

  @override
  String get dataSettingsCardSkinStarlightName => '星光玻璃卡';

  @override
  String get dataSettingsCardSkinPlainDescription => '默认信息卡片样式';

  @override
  String get dataSettingsCardSkinPaperDescription => '适合日程和待办整理的柔和纸感';

  @override
  String get dataSettingsCardSkinMintDescription => '适合习惯和专注记录的清爽卡片';

  @override
  String get dataSettingsCardSkinStarlightDescription => '适合夜间复盘的低亮度玻璃质感';

  @override
  String get settingsUiSaveFailed => '设置未保存，请重试。';

  @override
  String get settingsUiDecreaseValue => '减少';

  @override
  String get settingsUiIncreaseValue => '增加';

  @override
  String settingsUiDecreaseSetting(String title) {
    return '减少“$title”';
  }

  @override
  String settingsUiIncreaseSetting(String title) {
    return '增加“$title”';
  }

  @override
  String settingsUiCurrentFirstWeekday(String weekday) {
    return '当前为$weekday';
  }

  @override
  String get settingsUiPreferencesHeroExplanation =>
      '自定义显示与行为偏好，管理底部导航入口与小组件显示。';

  @override
  String get settingsUiPreferencesCategoriesSectionTitle => '个性入口';

  @override
  String get settingsUiPreferencesCategoriesSectionSubtitle => '选择要调整的设置类别';

  @override
  String get settingsUiDisplayAndBehaviorTitle => '显示与行为';

  @override
  String get settingsUiDisplayAndBehaviorSubtitle => '日期格式、应用时区、启动入口、交互与归档';

  @override
  String get settingsUiDisplayAndBehaviorHeroSubtitle =>
      '管理日期格式、应用时区、启动默认项、交互反馈与待办归档。';

  @override
  String get settingsUiNavigationSectionTitle => '导航入口';

  @override
  String get settingsUiNavigationSectionSubtitle => '最多 5 个底部入口；“我的”固定，小组件可隐藏';

  @override
  String get settingsUiJumpToMenuTitle => '快捷定位';

  @override
  String get settingsUiJumpToDate => '日期日历';

  @override
  String get settingsUiJumpToDefaults => '默认行为';

  @override
  String get settingsUiJumpToInteraction => '交互归档';

  @override
  String settingsUiDateFormatIso(String pattern) {
    return '标准 ($pattern)';
  }

  @override
  String settingsUiDateFormatUs(String pattern) {
    return '美式 ($pattern)';
  }

  @override
  String settingsUiDateFormatEurope(String pattern) {
    return '欧式 ($pattern)';
  }

  @override
  String settingsUiDateFormatEastAsian(String pattern) {
    return '中文年月日 ($pattern)';
  }

  @override
  String get settingsUiTimeZoneShanghai => '中国标准时间 (上海)';

  @override
  String get settingsUiTimeZoneMexicoCity => '墨西哥城时间';

  @override
  String get settingsUiTimeZoneTijuana => '蒂华纳时间';

  @override
  String get settingsUiTimeZoneTokyo => '东京时间 (日本)';

  @override
  String get settingsUiTimeZoneHongKong => '香港时间';

  @override
  String get settingsUiTimeZoneSingapore => '新加坡时间';

  @override
  String get settingsUiTimeZoneNewYork => '纽约时间 (美东)';

  @override
  String get settingsUiTimeZoneLosAngeles => '洛杉矶时间 (美西)';

  @override
  String get settingsUiTimeZoneLondon => '伦敦时间';

  @override
  String get settingsUiTimeZoneParis => '巴黎时间 (中欧)';

  @override
  String get settingsUiTimeZoneSydney => '悉尼时间 (澳洲东部)';

  @override
  String get settingsUiNavigationBannerMessage =>
      '底部导航最多显示 5 个入口，我的固定显示；小组件可隐藏，隐藏入口可在“我的”页面访问。';

  @override
  String settingsUiMaxTabsConstraint(int max) {
    return '最多显示 $max 个入口';
  }

  @override
  String get settingsUiNavigationHiddenAtLimit => '已达上限，先隐藏其他项';

  @override
  String settingsUiNavigationMoveUp(String label) {
    return '上移“$label”';
  }

  @override
  String settingsUiNavigationMoveDown(String label) {
    return '下移“$label”';
  }

  @override
  String get settingsUiSelectOption => '选择设置';

  @override
  String get settingsUiSelectFirstDay => '选择一周第一天';

  @override
  String get settingsUiSelectDateFormat => '选择日期格式';

  @override
  String get settingsUiSelectTimeZone => '选择应用时区';

  @override
  String get settingsUiSelectDefaultTab => '选择启动默认 Tab';

  @override
  String get settingsUiSelectAutoLock => '选择自动锁定时间';

  @override
  String settingsUiAutoLockMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String settingsUiAutoLockAfter(int minutes) {
    return '离开 $minutes 分钟后锁定';
  }

  @override
  String habitCopyWeekGoal(int target, String unit) {
    return '每周目标: $target 次/周';
  }

  @override
  String habitCopyMonthGoal(int target, String unit) {
    return '每月目标: $target 次/月';
  }

  @override
  String get habitCopyActionEnd => '结束';

  @override
  String get habitCopyDeleteConfirmTitle => '删除习惯？';

  @override
  String habitCopyDeleteConfirmContent(String habitName) {
    return '会删除“$habitName”和关联记录，不可恢复。';
  }

  @override
  String get habitCopyEndConfirmTitle => '结束习惯？';

  @override
  String habitCopyEndConfirmContent(String habitName) {
    return '结束“$habitName”？历史记录将保留。';
  }

  @override
  String get habitCopyEndHabitAction => '结束习惯';

  @override
  String get habitCopyDeleteHabitAction => '删除习惯';

  @override
  String get habitCopyMoreActions => '更多操作';

  @override
  String get habitCopyEndedFeedback => '习惯已结束，历史记录已保留';

  @override
  String get habitCopyDeletedFeedback => '习惯已删除';

  @override
  String get habitCopySaveSuccess => '习惯已保存';

  @override
  String get habitCopyCheckInFailedWithRetry => '打卡失败，请重试';

  @override
  String get habitCopyUndoFailedWithRetry => '撤销打卡失败，请重试';

  @override
  String get habitCopySaveFailedWithRetry => '保存习惯失败，请重试';

  @override
  String get habitCopyActionFailedWithRetry => '操作失败，请重试';

  @override
  String get habitCopyNameRequired => '请输入习惯名称';

  @override
  String get habitCopyDailyTargetInvalid => '每日目标至少为 1';

  @override
  String get habitCopyReminderSchedulerMissing => '提醒调度器尚未初始化，请重新打开应用后再保存提醒';

  @override
  String get habitCopyNotificationsNotGranted => '系统通知未授权，习惯提醒不会响铃或弹出';

  @override
  String get habitCopyReminderPermissionError => '需要系统通知权限以接收提醒';

  @override
  String get habitCopyReminderRegisterFailed => '提醒注册失败';

  @override
  String habitCopyReminderSyncWarning(String issueText) {
    return '习惯已保存，但提醒未同步：$issueText';
  }

  @override
  String habitCopyPeriodGoalReached(String habitName, String periodLabel) {
    return '「$habitName」$periodLabel目标已达标';
  }

  @override
  String habitCopySingleSessionGoalReached(String habitName) {
    return '「$habitName」今日单次目标已完成';
  }

  @override
  String habitCopyCheckInSuccessNegative(String habitName) {
    return '已记录一次「$habitName」';
  }

  @override
  String habitCopyDateRecordFeedback(String habitName) {
    return '已记录「$habitName」';
  }

  @override
  String habitCopyDateUndoFeedback(String habitName) {
    return '已撤销「$habitName」记录';
  }

  @override
  String get habitCopyUnitCup => '杯';

  @override
  String get habitCopyUnitCups => '杯';

  @override
  String get habitCopyUnitTime => '次';

  @override
  String habitCopyMeasuredCount(int count, String unit) {
    return '$count $unit';
  }

  @override
  String habitCopyCountWithFlexProgress(
    String measuredCount,
    String flexProgressLabel,
  ) {
    return '$measuredCount · $flexProgressLabel';
  }

  @override
  String habitCopyCountRecorded(String measuredCount) {
    return '已记录 $measuredCount';
  }

  @override
  String habitCopyCountRatio(
    String measuredCount,
    int target,
    String targetUnit,
  ) {
    return '$measuredCount / $target $targetUnit';
  }

  @override
  String habitCopyCheckInSuccessStandardReached(String habitName) {
    return '「$habitName」今日已达标';
  }

  @override
  String habitCopyCheckInSuccessStandardProgress(
    String habitName,
    int count,
    int target,
  ) {
    return '已打卡「$habitName」 $count/$target';
  }

  @override
  String get habitCopyPeriodFallback => '本周期';

  @override
  String habitCopyCheckInSuccessFlexProgress(
    String habitName,
    String flexLabel,
  ) {
    return '已打卡「$habitName」 $flexLabel';
  }

  @override
  String get settingsUiAutoArchiveDayOne => '1 天';

  @override
  String settingsUiAutoArchiveDayMany(int days) {
    return '$days 天';
  }

  @override
  String get settingsUiAutoArchiveAfterOneDay => '1 天后自动隐藏';

  @override
  String settingsUiAutoArchiveAfterDays(int days) {
    return '$days 天后自动隐藏';
  }

  @override
  String settingsUiFollowingSystemTimeZone(String timeZoneName) {
    return '跟随手机：$timeZoneName';
  }
}
