import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('en'),
  ];

  /// 应用标题
  ///
  /// In zh, this message translates to:
  /// **'多仪'**
  String get appTitle;

  /// No description provided for @navToday.
  ///
  /// In zh, this message translates to:
  /// **'今日'**
  String get navToday;

  /// No description provided for @navTodo.
  ///
  /// In zh, this message translates to:
  /// **'待办'**
  String get navTodo;

  /// No description provided for @navHabit.
  ///
  /// In zh, this message translates to:
  /// **'习惯'**
  String get navHabit;

  /// No description provided for @navCalendar.
  ///
  /// In zh, this message translates to:
  /// **'日历'**
  String get navCalendar;

  /// No description provided for @navFocus.
  ///
  /// In zh, this message translates to:
  /// **'专注'**
  String get navFocus;

  /// No description provided for @navWidget.
  ///
  /// In zh, this message translates to:
  /// **'小组件'**
  String get navWidget;

  /// No description provided for @navMine.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get navMine;

  /// No description provided for @actionConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get actionConfirm;

  /// No description provided for @actionCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get actionSave;

  /// No description provided for @actionDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get actionDelete;

  /// No description provided for @actionEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get actionEdit;

  /// No description provided for @actionAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get actionAdd;

  /// No description provided for @actionCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get actionCreate;

  /// No description provided for @actionGenerate.
  ///
  /// In zh, this message translates to:
  /// **'生成'**
  String get actionGenerate;

  /// No description provided for @actionComplete.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get actionComplete;

  /// No description provided for @actionOff.
  ///
  /// In zh, this message translates to:
  /// **'关'**
  String get actionOff;

  /// No description provided for @actionMoveUp.
  ///
  /// In zh, this message translates to:
  /// **'上移'**
  String get actionMoveUp;

  /// No description provided for @actionMoveDown.
  ///
  /// In zh, this message translates to:
  /// **'下移'**
  String get actionMoveDown;

  /// No description provided for @actionSnooze.
  ///
  /// In zh, this message translates to:
  /// **'稍后提醒'**
  String get actionSnooze;

  /// No description provided for @actionRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get actionRetry;

  /// No description provided for @actionBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get actionBack;

  /// No description provided for @actionClear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get actionClear;

  /// No description provided for @actionClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get actionClose;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'界面语言'**
  String get settingsLanguage;

  /// No description provided for @weekdayMon.
  ///
  /// In zh, this message translates to:
  /// **'周一'**
  String get weekdayMon;

  /// No description provided for @weekdayTue.
  ///
  /// In zh, this message translates to:
  /// **'周二'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In zh, this message translates to:
  /// **'周三'**
  String get weekdayWed;

  /// No description provided for @weekdayThu.
  ///
  /// In zh, this message translates to:
  /// **'周四'**
  String get weekdayThu;

  /// No description provided for @weekdayFri.
  ///
  /// In zh, this message translates to:
  /// **'周五'**
  String get weekdayFri;

  /// No description provided for @weekdaySat.
  ///
  /// In zh, this message translates to:
  /// **'周六'**
  String get weekdaySat;

  /// No description provided for @weekdaySun.
  ///
  /// In zh, this message translates to:
  /// **'周日'**
  String get weekdaySun;

  /// No description provided for @weekdayUnknown.
  ///
  /// In zh, this message translates to:
  /// **'周?'**
  String get weekdayUnknown;

  /// No description provided for @calendarSolar.
  ///
  /// In zh, this message translates to:
  /// **'公历'**
  String get calendarSolar;

  /// No description provided for @calendarLunar.
  ///
  /// In zh, this message translates to:
  /// **'农历'**
  String get calendarLunar;

  /// No description provided for @calendarChineseLunar.
  ///
  /// In zh, this message translates to:
  /// **'农历'**
  String get calendarChineseLunar;

  /// No description provided for @calendarChineseLunarCalendar.
  ///
  /// In zh, this message translates to:
  /// **'农历'**
  String get calendarChineseLunarCalendar;

  /// No description provided for @calendarCorrespondingLunar.
  ///
  /// In zh, this message translates to:
  /// **'对应农历'**
  String get calendarCorrespondingLunar;

  /// No description provided for @calendarCorrespondingSolar.
  ///
  /// In zh, this message translates to:
  /// **'对应公历'**
  String get calendarCorrespondingSolar;

  /// No description provided for @calendarEventEvent.
  ///
  /// In zh, this message translates to:
  /// **'日程'**
  String get calendarEventEvent;

  /// No description provided for @calendarEventTodo.
  ///
  /// In zh, this message translates to:
  /// **'待办'**
  String get calendarEventTodo;

  /// No description provided for @calendarEventHabit.
  ///
  /// In zh, this message translates to:
  /// **'习惯'**
  String get calendarEventHabit;

  /// No description provided for @calendarEventPomodoro.
  ///
  /// In zh, this message translates to:
  /// **'番茄钟'**
  String get calendarEventPomodoro;

  /// No description provided for @calendarEventAnniversary.
  ///
  /// In zh, this message translates to:
  /// **'纪念日'**
  String get calendarEventAnniversary;

  /// No description provided for @calendarEventCourse.
  ///
  /// In zh, this message translates to:
  /// **'课程'**
  String get calendarEventCourse;

  /// No description provided for @calendarEventDiary.
  ///
  /// In zh, this message translates to:
  /// **'日记'**
  String get calendarEventDiary;

  /// No description provided for @calendarEventCountdown.
  ///
  /// In zh, this message translates to:
  /// **'倒数日'**
  String get calendarEventCountdown;

  /// No description provided for @calendarEventGoal.
  ///
  /// In zh, this message translates to:
  /// **'目标'**
  String get calendarEventGoal;

  /// No description provided for @calendarEventTimeEntry.
  ///
  /// In zh, this message translates to:
  /// **'时间足迹'**
  String get calendarEventTimeEntry;

  /// No description provided for @timeEntrySourceManual.
  ///
  /// In zh, this message translates to:
  /// **'手动'**
  String get timeEntrySourceManual;

  /// No description provided for @timeEntrySourcePomodoro.
  ///
  /// In zh, this message translates to:
  /// **'番茄钟'**
  String get timeEntrySourcePomodoro;

  /// No description provided for @timeEntrySourceTodo.
  ///
  /// In zh, this message translates to:
  /// **'待办'**
  String get timeEntrySourceTodo;

  /// No description provided for @timeEntrySourceHabit.
  ///
  /// In zh, this message translates to:
  /// **'习惯'**
  String get timeEntrySourceHabit;

  /// No description provided for @timeEntrySourceGoal.
  ///
  /// In zh, this message translates to:
  /// **'目标'**
  String get timeEntrySourceGoal;

  /// No description provided for @timeEntryCategoryFocus.
  ///
  /// In zh, this message translates to:
  /// **'专注'**
  String get timeEntryCategoryFocus;

  /// No description provided for @timeEntryCategoryTodo.
  ///
  /// In zh, this message translates to:
  /// **'待办'**
  String get timeEntryCategoryTodo;

  /// No description provided for @timeEntryCategoryHabit.
  ///
  /// In zh, this message translates to:
  /// **'习惯'**
  String get timeEntryCategoryHabit;

  /// No description provided for @timeEntryCategoryGoal.
  ///
  /// In zh, this message translates to:
  /// **'目标'**
  String get timeEntryCategoryGoal;

  /// No description provided for @timeEntryCategoryStudy.
  ///
  /// In zh, this message translates to:
  /// **'学习'**
  String get timeEntryCategoryStudy;

  /// No description provided for @timeEntryCategoryWork.
  ///
  /// In zh, this message translates to:
  /// **'工作'**
  String get timeEntryCategoryWork;

  /// No description provided for @timeEntryCategoryLife.
  ///
  /// In zh, this message translates to:
  /// **'生活'**
  String get timeEntryCategoryLife;

  /// No description provided for @timeEntryCategoryOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get timeEntryCategoryOther;

  /// No description provided for @settingsLanguageZh.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get settingsLanguageZh;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// No description provided for @settingsLanguageDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择界面语言。你的待办、笔记和其他记录会保留原文。'**
  String get settingsLanguageDescription;

  /// No description provided for @preferencesTitle.
  ///
  /// In zh, this message translates to:
  /// **'个性设置'**
  String get preferencesTitle;

  /// No description provided for @preferencesLocalTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地个性设置'**
  String get preferencesLocalTitle;

  /// No description provided for @preferencesLocalSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'按功能管理通知、导航入口、日期、交互和本机行为'**
  String get preferencesLocalSubtitle;

  /// No description provided for @preferencesSectionDate.
  ///
  /// In zh, this message translates to:
  /// **'日期与日历'**
  String get preferencesSectionDate;

  /// No description provided for @preferencesSectionDateSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'影响今日卡片、日历和日期展示'**
  String get preferencesSectionDateSubtitle;

  /// No description provided for @preferencesFirstDayTitle.
  ///
  /// In zh, this message translates to:
  /// **'一周从哪一天开始'**
  String get preferencesFirstDayTitle;

  /// No description provided for @preferencesFirstDayCurrentMonday.
  ///
  /// In zh, this message translates to:
  /// **'当前为周一'**
  String get preferencesFirstDayCurrentMonday;

  /// No description provided for @preferencesFirstDayCurrentSunday.
  ///
  /// In zh, this message translates to:
  /// **'当前为周日'**
  String get preferencesFirstDayCurrentSunday;

  /// No description provided for @preferencesDateFormatTitle.
  ///
  /// In zh, this message translates to:
  /// **'日期格式'**
  String get preferencesDateFormatTitle;

  /// No description provided for @preferencesTimezoneTitle.
  ///
  /// In zh, this message translates to:
  /// **'应用时区'**
  String get preferencesTimezoneTitle;

  /// No description provided for @preferencesTimezoneFollowSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随手机'**
  String get preferencesTimezoneFollowSystem;

  /// No description provided for @preferencesLunarTitle.
  ///
  /// In zh, this message translates to:
  /// **'显示农历'**
  String get preferencesLunarTitle;

  /// No description provided for @preferencesLunarSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'影响日历月视图与今日卡'**
  String get preferencesLunarSubtitle;

  /// No description provided for @preferencesSectionDefaults.
  ///
  /// In zh, this message translates to:
  /// **'默认行为'**
  String get preferencesSectionDefaults;

  /// No description provided for @preferencesSectionDefaultsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'启动入口、快捷捕获和专注时长'**
  String get preferencesSectionDefaultsSubtitle;

  /// No description provided for @preferencesDefaultTabTitle.
  ///
  /// In zh, this message translates to:
  /// **'启动默认 Tab'**
  String get preferencesDefaultTabTitle;

  /// No description provided for @preferencesQuickCaptureTitle.
  ///
  /// In zh, this message translates to:
  /// **'显示快速捕获按钮'**
  String get preferencesQuickCaptureTitle;

  /// No description provided for @preferencesQuickCaptureSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'今日页右下角的快捷创建按钮'**
  String get preferencesQuickCaptureSubtitle;

  /// No description provided for @preferencesNotificationQuickAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'通知栏快捷添加'**
  String get preferencesNotificationQuickAddTitle;

  /// No description provided for @preferencesNotificationQuickAddSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'Android 常驻通知：添加待办或开始专注'**
  String get preferencesNotificationQuickAddSubtitle;

  /// No description provided for @preferencesNotificationTodayProgressTitle.
  ///
  /// In zh, this message translates to:
  /// **'通知栏今日任务进展'**
  String get preferencesNotificationTodayProgressTitle;

  /// No description provided for @preferencesNotificationTodayProgressSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'开启后在通知栏常驻显示今日任务摘要，可随任务变化刷新'**
  String get preferencesNotificationTodayProgressSubtitle;

  /// No description provided for @preferencesNotificationStatusBarTitle.
  ///
  /// In zh, this message translates to:
  /// **'通知栏快捷入口'**
  String get preferencesNotificationStatusBarTitle;

  /// No description provided for @preferencesNotificationStatusBarUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'通知栏常驻快捷入口和今日进展仅 Android 支持，当前平台保留普通通知提醒。'**
  String get preferencesNotificationStatusBarUnsupported;

  /// No description provided for @preferencesNotificationStatusBarEnabled.
  ///
  /// In zh, this message translates to:
  /// **'通知栏入口已开启'**
  String get preferencesNotificationStatusBarEnabled;

  /// No description provided for @preferencesNotificationStatusBarDisabled.
  ///
  /// In zh, this message translates to:
  /// **'通知栏入口已关闭'**
  String get preferencesNotificationStatusBarDisabled;

  /// No description provided for @preferencesNotificationStatusBarSyncFailed.
  ///
  /// In zh, this message translates to:
  /// **'通知栏同步失败，已恢复原设置。请检查系统通知权限和通知渠道。'**
  String get preferencesNotificationStatusBarSyncFailed;

  /// No description provided for @preferencesShowCompletedTitle.
  ///
  /// In zh, this message translates to:
  /// **'待办页显示已完成'**
  String get preferencesShowCompletedTitle;

  /// No description provided for @preferencesShowCompletedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'默认列表显示已完成事项；关闭后仍可通过“已完成”或“包含归档”查看'**
  String get preferencesShowCompletedSubtitle;

  /// No description provided for @preferencesPomodoroLengthTitle.
  ///
  /// In zh, this message translates to:
  /// **'默认番茄钟长度'**
  String get preferencesPomodoroLengthTitle;

  /// No description provided for @preferencesPomodoroLengthSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'选择“默认”时生效，当前计时保持不变'**
  String get preferencesPomodoroLengthSubtitle;

  /// No description provided for @preferencesSectionBottomNav.
  ///
  /// In zh, this message translates to:
  /// **'底部导航栏'**
  String get preferencesSectionBottomNav;

  /// No description provided for @preferencesSectionBottomNavSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'底部导航最多显示 5 个入口；我的固定显示，小组件可隐藏'**
  String get preferencesSectionBottomNavSubtitle;

  /// No description provided for @preferencesSectionInteraction.
  ///
  /// In zh, this message translates to:
  /// **'交互'**
  String get preferencesSectionInteraction;

  /// No description provided for @preferencesSectionInteractionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'触感反馈与完成动作'**
  String get preferencesSectionInteractionSubtitle;

  /// No description provided for @preferencesHapticTitle.
  ///
  /// In zh, this message translates to:
  /// **'震动反馈'**
  String get preferencesHapticTitle;

  /// No description provided for @preferencesHapticSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'完成/切换/解锁等操作'**
  String get preferencesHapticSubtitle;

  /// No description provided for @preferencesSectionAutoArchive.
  ///
  /// In zh, this message translates to:
  /// **'待办自动归档'**
  String get preferencesSectionAutoArchive;

  /// No description provided for @preferencesSectionAutoArchiveSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'减少已完成项目对列表的干扰'**
  String get preferencesSectionAutoArchiveSubtitle;

  /// No description provided for @preferencesAutoArchiveTitle.
  ///
  /// In zh, this message translates to:
  /// **'完成 N 天后隐藏'**
  String get preferencesAutoArchiveTitle;

  /// No description provided for @preferencesAutoArchiveNever.
  ///
  /// In zh, this message translates to:
  /// **'从不归档'**
  String get preferencesAutoArchiveNever;

  /// No description provided for @preferencesAutoArchiveAfterDays.
  ///
  /// In zh, this message translates to:
  /// **'天后自动隐藏'**
  String get preferencesAutoArchiveAfterDays;

  /// No description provided for @preferencesSectionDailyReminder.
  ///
  /// In zh, this message translates to:
  /// **'每日提醒'**
  String get preferencesSectionDailyReminder;

  /// No description provided for @preferencesSectionDailyReminderSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'最多三组提醒：时间、任务范围、重复周期、节假日暂停'**
  String get preferencesSectionDailyReminderSubtitle;

  /// No description provided for @preferencesNavFixed.
  ///
  /// In zh, this message translates to:
  /// **'固定显示'**
  String get preferencesNavFixed;

  /// No description provided for @preferencesNavVisible.
  ///
  /// In zh, this message translates to:
  /// **'已显示'**
  String get preferencesNavVisible;

  /// No description provided for @preferencesNavHidden.
  ///
  /// In zh, this message translates to:
  /// **'已隐藏'**
  String get preferencesNavHidden;

  /// No description provided for @preferencesNotifyPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'系统通知权限未授予'**
  String get preferencesNotifyPermissionDenied;

  /// No description provided for @preferencesNotifyExactAlarmGranted.
  ///
  /// In zh, this message translates to:
  /// **'精准闹钟权限已授权'**
  String get preferencesNotifyExactAlarmGranted;

  /// No description provided for @preferencesNotifyExactAlarmDenied.
  ///
  /// In zh, this message translates to:
  /// **'精准闹钟权限未授予'**
  String get preferencesNotifyExactAlarmDenied;

  /// No description provided for @preferencesNotifyFullScreenGranted.
  ///
  /// In zh, this message translates to:
  /// **'弹出屏幕权限已允许'**
  String get preferencesNotifyFullScreenGranted;

  /// No description provided for @preferencesNotifyFullScreenDenied.
  ///
  /// In zh, this message translates to:
  /// **'弹出屏幕权限未允许'**
  String get preferencesNotifyFullScreenDenied;

  /// No description provided for @preferencesNotifyTestPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'系统通知权限未授权，无法发送测试通知'**
  String get preferencesNotifyTestPermissionDenied;

  /// No description provided for @preferencesNotifyTestFailed.
  ///
  /// In zh, this message translates to:
  /// **'测试通知发送失败：'**
  String get preferencesNotifyTestFailed;

  /// No description provided for @preferencesNotifyTestSent.
  ///
  /// In zh, this message translates to:
  /// **'测试通知已发送'**
  String get preferencesNotifyTestSent;

  /// No description provided for @preferencesNotifyPendingCleared.
  ///
  /// In zh, this message translates to:
  /// **'已取消全部待调度提醒'**
  String get preferencesNotifyPendingCleared;

  /// No description provided for @preferencesNotifyOpenSettingsFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开系统设置'**
  String get preferencesNotifyOpenSettingsFailed;

  /// No description provided for @preferencesRingtoneSection.
  ///
  /// In zh, this message translates to:
  /// **'内置提醒铃声'**
  String get preferencesRingtoneSection;

  /// No description provided for @preferencesReportReminderDailyTime.
  ///
  /// In zh, this message translates to:
  /// **'每日复盘推送时间'**
  String get preferencesReportReminderDailyTime;

  /// No description provided for @preferencesReportReminderWeeklyTime.
  ///
  /// In zh, this message translates to:
  /// **'周报推送时间'**
  String get preferencesReportReminderWeeklyTime;

  /// No description provided for @preferencesReportReminderMonthlyTime.
  ///
  /// In zh, this message translates to:
  /// **'月报推送时间'**
  String get preferencesReportReminderMonthlyTime;

  /// No description provided for @preferencesReportReminderYearlyTime.
  ///
  /// In zh, this message translates to:
  /// **'年报推送时间'**
  String get preferencesReportReminderYearlyTime;

  /// No description provided for @preferencesReportReminderTimeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'修改后会重排下一次报告通知'**
  String get preferencesReportReminderTimeSubtitle;

  /// No description provided for @preferencesRingtoneSectionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'用于 HyperOS 等默认静音通知场景'**
  String get preferencesRingtoneSectionSubtitle;

  /// No description provided for @preferencesRingtoneSectionSubtitleAndroid.
  ///
  /// In zh, this message translates to:
  /// **'Android 使用应用内置铃声服务，适配 HyperOS 等默认静音通知场景'**
  String get preferencesRingtoneSectionSubtitleAndroid;

  /// No description provided for @preferencesRingtoneSectionSubtitleApple.
  ///
  /// In zh, this message translates to:
  /// **'iOS/macOS 使用系统通知声音和 time-sensitive 强提醒，不显示仅 Android 生效的内置铃声选择'**
  String get preferencesRingtoneSectionSubtitleApple;

  /// No description provided for @preferencesRingtoneSectionSubtitleDesktop.
  ///
  /// In zh, this message translates to:
  /// **'桌面端使用系统通知声音；响铃音量由系统控制'**
  String get preferencesRingtoneSectionSubtitleDesktop;

  /// No description provided for @preferencesRingtoneSectionSubtitleUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前平台不支持本地响铃提醒'**
  String get preferencesRingtoneSectionSubtitleUnsupported;

  /// No description provided for @preferencesRingtoneSound.
  ///
  /// In zh, this message translates to:
  /// **'提醒铃声'**
  String get preferencesRingtoneSound;

  /// No description provided for @preferencesRingtoneVolume.
  ///
  /// In zh, this message translates to:
  /// **'响铃音量'**
  String get preferencesRingtoneVolume;

  /// No description provided for @preferencesRingtoneCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前'**
  String get preferencesRingtoneCurrent;

  /// No description provided for @preferencesRingtoneSystemSound.
  ///
  /// In zh, this message translates to:
  /// **'系统通知声音'**
  String get preferencesRingtoneSystemSound;

  /// No description provided for @preferencesRingtoneSystemSoundSubtitleApple.
  ///
  /// In zh, this message translates to:
  /// **'到点提醒会请求声音、横幅和 time-sensitive 优先级；铃声和音量在系统设置中管理'**
  String get preferencesRingtoneSystemSoundSubtitleApple;

  /// No description provided for @preferencesRingtoneSystemSoundSubtitleDesktop.
  ///
  /// In zh, this message translates to:
  /// **'到点提醒会交给桌面通知系统；铃声和音量在系统设置中管理'**
  String get preferencesRingtoneSystemSoundSubtitleDesktop;

  /// No description provided for @preferencesRingtoneUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'本地响铃不可用'**
  String get preferencesRingtoneUnsupported;

  /// No description provided for @preferencesRingtoneUnsupportedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'Web 等平台暂不提供本地响铃提醒，请使用系统或邮件提醒兜底'**
  String get preferencesRingtoneUnsupportedSubtitle;

  /// No description provided for @preferencesDailyReminderOne.
  ///
  /// In zh, this message translates to:
  /// **'提醒一'**
  String get preferencesDailyReminderOne;

  /// No description provided for @preferencesDailyReminderTwo.
  ///
  /// In zh, this message translates to:
  /// **'提醒二'**
  String get preferencesDailyReminderTwo;

  /// No description provided for @preferencesDailyReminderThree.
  ///
  /// In zh, this message translates to:
  /// **'提醒三'**
  String get preferencesDailyReminderThree;

  /// No description provided for @preferencesDailyReminderDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭'**
  String get preferencesDailyReminderDisabled;

  /// No description provided for @preferencesDailyReminderTime.
  ///
  /// In zh, this message translates to:
  /// **'提醒时间'**
  String get preferencesDailyReminderTime;

  /// No description provided for @preferencesDailyReminderTimeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'到点发送带声音和震动的提醒'**
  String get preferencesDailyReminderTimeSubtitle;

  /// No description provided for @preferencesDailyReminderTimeSuffix.
  ///
  /// In zh, this message translates to:
  /// **'时间'**
  String get preferencesDailyReminderTimeSuffix;

  /// No description provided for @preferencesDailyReminder1Time.
  ///
  /// In zh, this message translates to:
  /// **'提醒一时间'**
  String get preferencesDailyReminder1Time;

  /// No description provided for @preferencesDailyReminder2Time.
  ///
  /// In zh, this message translates to:
  /// **'提醒二时间'**
  String get preferencesDailyReminder2Time;

  /// No description provided for @preferencesDailyReminder3Time.
  ///
  /// In zh, this message translates to:
  /// **'提醒三时间'**
  String get preferencesDailyReminder3Time;

  /// No description provided for @preferencesDailyReminderTimePickerSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'设置提醒触发时间'**
  String get preferencesDailyReminderTimePickerSubtitle;

  /// No description provided for @preferencesDailyReminderKindTitle.
  ///
  /// In zh, this message translates to:
  /// **'提醒方式'**
  String get preferencesDailyReminderKindTitle;

  /// No description provided for @preferencesDailyReminderKindPushDescription.
  ///
  /// In zh, this message translates to:
  /// **'系统通知栏提醒'**
  String get preferencesDailyReminderKindPushDescription;

  /// No description provided for @preferencesDailyReminderKindPopupDescription.
  ///
  /// In zh, this message translates to:
  /// **'应用前台时弹出提醒，后台使用通知兜底'**
  String get preferencesDailyReminderKindPopupDescription;

  /// No description provided for @preferencesDailyReminderKindAlarmDescription.
  ///
  /// In zh, this message translates to:
  /// **'按闹钟方式提醒，适合重要事项'**
  String get preferencesDailyReminderKindAlarmDescription;

  /// No description provided for @preferencesDailyReminderKindOffDescription.
  ///
  /// In zh, this message translates to:
  /// **'不注册系统通知、弹窗或闹钟'**
  String get preferencesDailyReminderKindOffDescription;

  /// No description provided for @preferencesDailyReminderRegisterFailed.
  ///
  /// In zh, this message translates to:
  /// **'每日提醒注册失败'**
  String get preferencesDailyReminderRegisterFailed;

  /// No description provided for @preferencesDailyReminderNotReady.
  ///
  /// In zh, this message translates to:
  /// **'系统通知未就绪，每日提醒没有开启。'**
  String get preferencesDailyReminderNotReady;

  /// No description provided for @preferencesDailyReminderTodayTasks.
  ///
  /// In zh, this message translates to:
  /// **'任务：今日任务'**
  String get preferencesDailyReminderTodayTasks;

  /// No description provided for @preferencesDailyReminderTodayTasksSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'提醒中包含今日未完成任务数量'**
  String get preferencesDailyReminderTodayTasksSubtitle;

  /// No description provided for @preferencesDailyReminderTomorrowPlan.
  ///
  /// In zh, this message translates to:
  /// **'任务：明日计划'**
  String get preferencesDailyReminderTomorrowPlan;

  /// No description provided for @preferencesDailyReminderTomorrowPlanSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'提醒中包含明日已安排任务数量'**
  String get preferencesDailyReminderTomorrowPlanSubtitle;

  /// No description provided for @preferencesDailyReminderOverdueTasks.
  ///
  /// In zh, this message translates to:
  /// **'任务：逾期任务'**
  String get preferencesDailyReminderOverdueTasks;

  /// No description provided for @preferencesDailyReminderOverdueTasksSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'提醒中包含已过期未完成任务'**
  String get preferencesDailyReminderOverdueTasksSubtitle;

  /// No description provided for @preferencesDailyReminderPauseHolidays.
  ///
  /// In zh, this message translates to:
  /// **'法定节假日暂停提醒'**
  String get preferencesDailyReminderPauseHolidays;

  /// No description provided for @preferencesDailyReminderPauseHolidaysSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'遇到内置节假日时顺延到下一个提醒日'**
  String get preferencesDailyReminderPauseHolidaysSubtitle;

  /// No description provided for @preferencesDailyReminderChipTodayTasks.
  ///
  /// In zh, this message translates to:
  /// **'今日任务'**
  String get preferencesDailyReminderChipTodayTasks;

  /// No description provided for @preferencesDailyReminderChipTomorrowPlan.
  ///
  /// In zh, this message translates to:
  /// **'明日计划'**
  String get preferencesDailyReminderChipTomorrowPlan;

  /// No description provided for @preferencesDailyReminderChipOverdueTasks.
  ///
  /// In zh, this message translates to:
  /// **'逾期事项'**
  String get preferencesDailyReminderChipOverdueTasks;

  /// No description provided for @preferencesDailyReminderChipPauseHolidays.
  ///
  /// In zh, this message translates to:
  /// **'节假日暂停'**
  String get preferencesDailyReminderChipPauseHolidays;

  /// No description provided for @preferencesDailyReminderScopeToday.
  ///
  /// In zh, this message translates to:
  /// **'今日'**
  String get preferencesDailyReminderScopeToday;

  /// No description provided for @preferencesDailyReminderScopeOverdue.
  ///
  /// In zh, this message translates to:
  /// **'逾期'**
  String get preferencesDailyReminderScopeOverdue;

  /// No description provided for @preferencesDailyReminderScopeTomorrow.
  ///
  /// In zh, this message translates to:
  /// **'明日'**
  String get preferencesDailyReminderScopeTomorrow;

  /// No description provided for @preferencesDailyReminderScopeNone.
  ///
  /// In zh, this message translates to:
  /// **'无任务范围'**
  String get preferencesDailyReminderScopeNone;

  /// No description provided for @notificationChannelGeneralName.
  ///
  /// In zh, this message translates to:
  /// **'多仪 · 通知提醒'**
  String get notificationChannelGeneralName;

  /// No description provided for @notificationChannelGeneralDescription.
  ///
  /// In zh, this message translates to:
  /// **'日常提醒使用柔和提示音、震动并尽量显示横幅'**
  String get notificationChannelGeneralDescription;

  /// No description provided for @notificationChannelAlarmName.
  ///
  /// In zh, this message translates to:
  /// **'多仪 · 柔和强提醒'**
  String get notificationChannelAlarmName;

  /// No description provided for @notificationChannelAlarmDescription.
  ///
  /// In zh, this message translates to:
  /// **'重要提醒使用柔和内置铃声，可在通知上手动停止'**
  String get notificationChannelAlarmDescription;

  /// No description provided for @notificationChannelQuickAddName.
  ///
  /// In zh, this message translates to:
  /// **'多仪 · 快捷入口'**
  String get notificationChannelQuickAddName;

  /// No description provided for @notificationChannelQuickAddDescription.
  ///
  /// In zh, this message translates to:
  /// **'通知栏常驻快捷添加待办和开始专注'**
  String get notificationChannelQuickAddDescription;

  /// No description provided for @notificationTickerReminder.
  ///
  /// In zh, this message translates to:
  /// **'多仪提醒'**
  String get notificationTickerReminder;

  /// No description provided for @notificationTickerQuickAdd.
  ///
  /// In zh, this message translates to:
  /// **'多仪快捷入口'**
  String get notificationTickerQuickAdd;

  /// No description provided for @notificationQuickAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'多仪快捷记录'**
  String get notificationQuickAddTitle;

  /// No description provided for @notificationQuickAddBody.
  ///
  /// In zh, this message translates to:
  /// **'下拉通知栏添加待办，或一键开始专注'**
  String get notificationQuickAddBody;

  /// No description provided for @notificationQuickAddActionAddTodo.
  ///
  /// In zh, this message translates to:
  /// **'添加待办'**
  String get notificationQuickAddActionAddTodo;

  /// No description provided for @notificationQuickAddActionOpenInput.
  ///
  /// In zh, this message translates to:
  /// **'打开输入'**
  String get notificationQuickAddActionOpenInput;

  /// No description provided for @notificationQuickAddActionStartFocus.
  ///
  /// In zh, this message translates to:
  /// **'开始专注'**
  String get notificationQuickAddActionStartFocus;

  /// No description provided for @notificationQuickAddInputLabel.
  ///
  /// In zh, this message translates to:
  /// **'例如：明天下午3点开会'**
  String get notificationQuickAddInputLabel;

  /// No description provided for @notificationStatusBarTodayProgressTitle.
  ///
  /// In zh, this message translates to:
  /// **'今日任务进展'**
  String get notificationStatusBarTodayProgressTitle;

  /// No description provided for @notificationStatusBarQuickHint.
  ///
  /// In zh, this message translates to:
  /// **'下拉可快速添加待办'**
  String get notificationStatusBarQuickHint;

  /// No description provided for @notificationStatusBarTodayRemainingPrefix.
  ///
  /// In zh, this message translates to:
  /// **'今日还要完成 '**
  String get notificationStatusBarTodayRemainingPrefix;

  /// No description provided for @notificationStatusBarTodayRemainingSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 项'**
  String get notificationStatusBarTodayRemainingSuffix;

  /// No description provided for @notificationStatusBarDailyCount.
  ///
  /// In zh, this message translates to:
  /// **'日常 '**
  String get notificationStatusBarDailyCount;

  /// No description provided for @notificationStatusBarTodoCount.
  ///
  /// In zh, this message translates to:
  /// **'待办 '**
  String get notificationStatusBarTodoCount;

  /// No description provided for @notificationStatusBarGoalCount.
  ///
  /// In zh, this message translates to:
  /// **'目标 '**
  String get notificationStatusBarGoalCount;

  /// No description provided for @quickTodoTitle.
  ///
  /// In zh, this message translates to:
  /// **'快速待办'**
  String get quickTodoTitle;

  /// No description provided for @quickTodoHint.
  ///
  /// In zh, this message translates to:
  /// **'一句话描述（如：明天下午3点开会）'**
  String get quickTodoHint;

  /// No description provided for @quickTodoParsedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'识别到：'**
  String get quickTodoParsedPrefix;

  /// No description provided for @quickAiTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 快捷创建日程'**
  String get quickAiTitle;

  /// No description provided for @quickAiHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：准备周五汇报'**
  String get quickAiHint;

  /// No description provided for @quickAiError.
  ///
  /// In zh, this message translates to:
  /// **'AI 创建失败，请检查 AI 配置'**
  String get quickAiError;

  /// No description provided for @quickNoteTitle.
  ///
  /// In zh, this message translates to:
  /// **'随手记'**
  String get quickNoteTitle;

  /// No description provided for @quickNoteHint.
  ///
  /// In zh, this message translates to:
  /// **'写点什么…'**
  String get quickNoteHint;

  /// No description provided for @quickMenuAiSchedule.
  ///
  /// In zh, this message translates to:
  /// **'AI 创建日程'**
  String get quickMenuAiSchedule;

  /// No description provided for @quickMenuSearch.
  ///
  /// In zh, this message translates to:
  /// **'全局搜索'**
  String get quickMenuSearch;

  /// No description provided for @quickMenuDiary.
  ///
  /// In zh, this message translates to:
  /// **'写日记'**
  String get quickMenuDiary;

  /// No description provided for @quickMenuNote.
  ///
  /// In zh, this message translates to:
  /// **'记一笔'**
  String get quickMenuNote;

  /// No description provided for @quickMenuTodo.
  ///
  /// In zh, this message translates to:
  /// **'快速待办'**
  String get quickMenuTodo;

  /// No description provided for @quickMenuTemplate.
  ///
  /// In zh, this message translates to:
  /// **'快捷模板'**
  String get quickMenuTemplate;

  /// No description provided for @quickTemplateTitle.
  ///
  /// In zh, this message translates to:
  /// **'快捷模板'**
  String get quickTemplateTitle;

  /// No description provided for @quickTemplateSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'一键套用常用待办或习惯默认值'**
  String get quickTemplateSubtitle;

  /// No description provided for @quickTemplateSave.
  ///
  /// In zh, this message translates to:
  /// **'保存模板'**
  String get quickTemplateSave;

  /// No description provided for @quickTemplateEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有模板'**
  String get quickTemplateEmpty;

  /// No description provided for @quickTemplateKindTodo.
  ///
  /// In zh, this message translates to:
  /// **'待办'**
  String get quickTemplateKindTodo;

  /// No description provided for @quickTemplateKindHabit.
  ///
  /// In zh, this message translates to:
  /// **'习惯'**
  String get quickTemplateKindHabit;

  /// No description provided for @quickTemplateName.
  ///
  /// In zh, this message translates to:
  /// **'模板名称'**
  String get quickTemplateName;

  /// No description provided for @quickTemplatePrefix.
  ///
  /// In zh, this message translates to:
  /// **'标题前缀'**
  String get quickTemplatePrefix;

  /// No description provided for @quickTemplateTags.
  ///
  /// In zh, this message translates to:
  /// **'标签（逗号或空格分隔）'**
  String get quickTemplateTags;

  /// No description provided for @quickTemplateList.
  ///
  /// In zh, this message translates to:
  /// **'默认清单'**
  String get quickTemplateList;

  /// No description provided for @quickTemplatePriority.
  ///
  /// In zh, this message translates to:
  /// **'默认优先级'**
  String get quickTemplatePriority;

  /// No description provided for @quickTemplateReminder15.
  ///
  /// In zh, this message translates to:
  /// **'有截止时间时提前 15 分钟提醒'**
  String get quickTemplateReminder15;

  /// No description provided for @quickTemplateHabitCategory.
  ///
  /// In zh, this message translates to:
  /// **'习惯分组'**
  String get quickTemplateHabitCategory;

  /// No description provided for @quickTemplateHabitTarget.
  ///
  /// In zh, this message translates to:
  /// **'每日目标'**
  String get quickTemplateHabitTarget;

  /// No description provided for @quickTemplateHabitUnit.
  ///
  /// In zh, this message translates to:
  /// **'单位'**
  String get quickTemplateHabitUnit;

  /// No description provided for @quickTemplateHabitReminder.
  ///
  /// In zh, this message translates to:
  /// **'默认 21:00 提醒'**
  String get quickTemplateHabitReminder;

  /// No description provided for @quickTemplateSaved.
  ///
  /// In zh, this message translates to:
  /// **'模板已保存'**
  String get quickTemplateSaved;

  /// No description provided for @quickTemplateApplyHint.
  ///
  /// In zh, this message translates to:
  /// **'输入本次内容'**
  String get quickTemplateApplyHint;

  /// No description provided for @quickTemplateTodoDone.
  ///
  /// In zh, this message translates to:
  /// **'已按模板创建待办'**
  String get quickTemplateTodoDone;

  /// No description provided for @quickTemplateHabitDone.
  ///
  /// In zh, this message translates to:
  /// **'已按模板创建习惯'**
  String get quickTemplateHabitDone;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索待办 · 日程 · 习惯 · 笔记 · 日记 …'**
  String get searchHint;

  /// No description provided for @searchEmpty.
  ///
  /// In zh, this message translates to:
  /// **'输入关键字，搜索全部内容'**
  String get searchEmpty;

  /// No description provided for @searchNoResultsPrefix.
  ///
  /// In zh, this message translates to:
  /// **'没找到 '**
  String get searchNoResultsPrefix;

  /// No description provided for @searchNoResultsSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 相关结果'**
  String get searchNoResultsSuffix;

  /// No description provided for @searchResultsTitle.
  ///
  /// In zh, this message translates to:
  /// **'搜索结果'**
  String get searchResultsTitle;

  /// No description provided for @searchResultsSummaryPrefix.
  ///
  /// In zh, this message translates to:
  /// **'“'**
  String get searchResultsSummaryPrefix;

  /// No description provided for @searchResultsSummaryMiddle.
  ///
  /// In zh, this message translates to:
  /// **'” 共 '**
  String get searchResultsSummaryMiddle;

  /// No description provided for @searchResultsSummarySuffix.
  ///
  /// In zh, this message translates to:
  /// **' 条命中'**
  String get searchResultsSummarySuffix;

  /// No description provided for @searchClear.
  ///
  /// In zh, this message translates to:
  /// **'清空搜索'**
  String get searchClear;

  /// No description provided for @searchKindTodo.
  ///
  /// In zh, this message translates to:
  /// **'待办'**
  String get searchKindTodo;

  /// No description provided for @searchKindHabit.
  ///
  /// In zh, this message translates to:
  /// **'习惯'**
  String get searchKindHabit;

  /// No description provided for @searchKindNote.
  ///
  /// In zh, this message translates to:
  /// **'笔记'**
  String get searchKindNote;

  /// No description provided for @searchKindDiary.
  ///
  /// In zh, this message translates to:
  /// **'日记'**
  String get searchKindDiary;

  /// No description provided for @searchKindAnniversary.
  ///
  /// In zh, this message translates to:
  /// **'纪念'**
  String get searchKindAnniversary;

  /// No description provided for @searchKindCountdown.
  ///
  /// In zh, this message translates to:
  /// **'倒数'**
  String get searchKindCountdown;

  /// No description provided for @searchKindGoal.
  ///
  /// In zh, this message translates to:
  /// **'目标'**
  String get searchKindGoal;

  /// No description provided for @searchKindCourse.
  ///
  /// In zh, this message translates to:
  /// **'课程'**
  String get searchKindCourse;

  /// No description provided for @searchKindEvent.
  ///
  /// In zh, this message translates to:
  /// **'日程'**
  String get searchKindEvent;

  /// No description provided for @searchKindTimeEntry.
  ///
  /// In zh, this message translates to:
  /// **'时间足迹'**
  String get searchKindTimeEntry;

  /// No description provided for @authLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get authLoginTitle;

  /// No description provided for @authRegisterTitle.
  ///
  /// In zh, this message translates to:
  /// **'注册账号'**
  String get authRegisterTitle;

  /// No description provided for @authLogin.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get authLogin;

  /// No description provided for @authRegister.
  ///
  /// In zh, this message translates to:
  /// **'注册'**
  String get authRegister;

  /// No description provided for @authLoginSubtitlePassword.
  ///
  /// In zh, this message translates to:
  /// **'使用用户名或邮箱登录享受云同步与公告'**
  String get authLoginSubtitlePassword;

  /// No description provided for @authLoginSubtitleEmailCode.
  ///
  /// In zh, this message translates to:
  /// **'使用已验证邮箱验证码登录'**
  String get authLoginSubtitleEmailCode;

  /// No description provided for @authRegisterSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'创建一个账号开启多端同步'**
  String get authRegisterSubtitle;

  /// No description provided for @authMaintenance.
  ///
  /// In zh, this message translates to:
  /// **'服务正在维护中'**
  String get authMaintenance;

  /// No description provided for @authPasswordLogin.
  ///
  /// In zh, this message translates to:
  /// **'密码登录'**
  String get authPasswordLogin;

  /// No description provided for @authEmailCodeLogin.
  ///
  /// In zh, this message translates to:
  /// **'邮箱验证码'**
  String get authEmailCodeLogin;

  /// No description provided for @authUsername.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get authUsername;

  /// No description provided for @authAccount.
  ///
  /// In zh, this message translates to:
  /// **'用户名或邮箱'**
  String get authAccount;

  /// No description provided for @authVerifiedEmail.
  ///
  /// In zh, this message translates to:
  /// **'已验证邮箱'**
  String get authVerifiedEmail;

  /// No description provided for @authEmail.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get authEmail;

  /// No description provided for @authEmailOptional.
  ///
  /// In zh, this message translates to:
  /// **'邮箱（可选）'**
  String get authEmailOptional;

  /// No description provided for @authEmailRequiredHelper.
  ///
  /// In zh, this message translates to:
  /// **'当前站点要求注册时验证邮箱'**
  String get authEmailRequiredHelper;

  /// No description provided for @authEmailCode.
  ///
  /// In zh, this message translates to:
  /// **'邮箱验证码'**
  String get authEmailCode;

  /// No description provided for @authEmailCodeOptional.
  ///
  /// In zh, this message translates to:
  /// **'邮箱验证码（可选）'**
  String get authEmailCodeOptional;

  /// No description provided for @authEmailCodeSent.
  ///
  /// In zh, this message translates to:
  /// **'验证码已发送，请查收邮箱'**
  String get authEmailCodeSent;

  /// No description provided for @authEmailCodeSentCheckEmail.
  ///
  /// In zh, this message translates to:
  /// **'验证码已发送，请查看邮箱。'**
  String get authEmailCodeSentCheckEmail;

  /// No description provided for @authEmailCodeCodePrefix.
  ///
  /// In zh, this message translates to:
  /// **'验证码：'**
  String get authEmailCodeCodePrefix;

  /// No description provided for @authDisplayNameOptional.
  ///
  /// In zh, this message translates to:
  /// **'昵称（可选）'**
  String get authDisplayNameOptional;

  /// No description provided for @authForgotPassword.
  ///
  /// In zh, this message translates to:
  /// **'忘记密码？'**
  String get authForgotPassword;

  /// No description provided for @authPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get authPassword;

  /// No description provided for @authConfirmPassword.
  ///
  /// In zh, this message translates to:
  /// **'确认密码'**
  String get authConfirmPassword;

  /// No description provided for @authNewPassword.
  ///
  /// In zh, this message translates to:
  /// **'新密码'**
  String get authNewPassword;

  /// No description provided for @authInviteCode.
  ///
  /// In zh, this message translates to:
  /// **'邀请码'**
  String get authInviteCode;

  /// No description provided for @authSend.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get authSend;

  /// No description provided for @authRegistrationClosed.
  ///
  /// In zh, this message translates to:
  /// **'当前站点已关闭注册'**
  String get authRegistrationClosed;

  /// No description provided for @authSwitchToLogin.
  ///
  /// In zh, this message translates to:
  /// **'已有账号？去登录'**
  String get authSwitchToLogin;

  /// No description provided for @authSwitchToRegister.
  ///
  /// In zh, this message translates to:
  /// **'没有账号？去注册'**
  String get authSwitchToRegister;

  /// No description provided for @authPasswordResetTitle.
  ///
  /// In zh, this message translates to:
  /// **'找回密码'**
  String get authPasswordResetTitle;

  /// No description provided for @authPasswordResetEmailSent.
  ///
  /// In zh, this message translates to:
  /// **'重置邮件已发送，请查收邮箱。'**
  String get authPasswordResetEmailSent;

  /// No description provided for @authPasswordResetDone.
  ///
  /// In zh, this message translates to:
  /// **'密码已重置，请使用新密码登录'**
  String get authPasswordResetDone;

  /// No description provided for @authPasswordResetConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认重置'**
  String get authPasswordResetConfirm;

  /// No description provided for @authPasswordResetSendEmail.
  ///
  /// In zh, this message translates to:
  /// **'发送邮件'**
  String get authPasswordResetSendEmail;

  /// No description provided for @authResetAccount.
  ///
  /// In zh, this message translates to:
  /// **'用户名或已绑定邮箱'**
  String get authResetAccount;

  /// No description provided for @authResetAccountHelper.
  ///
  /// In zh, this message translates to:
  /// **'验证码会发送到账号已绑定邮箱'**
  String get authResetAccountHelper;

  /// No description provided for @authErrorEmailRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先填写邮箱'**
  String get authErrorEmailRequired;

  /// No description provided for @authErrorEmailInvalid.
  ///
  /// In zh, this message translates to:
  /// **'邮箱格式不正确'**
  String get authErrorEmailInvalid;

  /// No description provided for @authErrorUsernameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写用户名'**
  String get authErrorUsernameRequired;

  /// No description provided for @authErrorAccountRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写用户名或邮箱'**
  String get authErrorAccountRequired;

  /// No description provided for @authErrorUsernameLength.
  ///
  /// In zh, this message translates to:
  /// **'用户名需为 3-64 个字符'**
  String get authErrorUsernameLength;

  /// No description provided for @authErrorUsernameNoSpace.
  ///
  /// In zh, this message translates to:
  /// **'用户名不能包含空白字符'**
  String get authErrorUsernameNoSpace;

  /// No description provided for @authErrorEmailCodeRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先获取并填写邮箱验证码'**
  String get authErrorEmailCodeRequired;

  /// No description provided for @authErrorPasswordShort.
  ///
  /// In zh, this message translates to:
  /// **'密码至少 6 位'**
  String get authErrorPasswordShort;

  /// No description provided for @authErrorPasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的密码不一致'**
  String get authErrorPasswordMismatch;

  /// No description provided for @authErrorInviteRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写邀请码'**
  String get authErrorInviteRequired;

  /// No description provided for @authErrorVerifiedEmailRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写已验证邮箱'**
  String get authErrorVerifiedEmailRequired;

  /// No description provided for @authErrorEmailCodeInputRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写邮箱验证码'**
  String get authErrorEmailCodeInputRequired;

  /// No description provided for @authErrorPasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写密码'**
  String get authErrorPasswordRequired;

  /// No description provided for @authErrorInvalidCredentials.
  ///
  /// In zh, this message translates to:
  /// **'账号或密码错误，请重新输入'**
  String get authErrorInvalidCredentials;

  /// No description provided for @authErrorResetAccountRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写用户名或已绑定邮箱'**
  String get authErrorResetAccountRequired;

  /// No description provided for @authErrorMailCodeRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写邮件验证码'**
  String get authErrorMailCodeRequired;

  /// No description provided for @authErrorNewPasswordShort.
  ///
  /// In zh, this message translates to:
  /// **'新密码至少 6 位'**
  String get authErrorNewPasswordShort;

  /// No description provided for @authErrorNewPasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的新密码不一致'**
  String get authErrorNewPasswordMismatch;

  /// No description provided for @profileTitle.
  ///
  /// In zh, this message translates to:
  /// **'个人资料'**
  String get profileTitle;

  /// No description provided for @profileNickname.
  ///
  /// In zh, this message translates to:
  /// **'昵称'**
  String get profileNickname;

  /// No description provided for @profileDisplayName.
  ///
  /// In zh, this message translates to:
  /// **'显示名'**
  String get profileDisplayName;

  /// No description provided for @profileDisplayNameEmpty.
  ///
  /// In zh, this message translates to:
  /// **'未设置昵称'**
  String get profileDisplayNameEmpty;

  /// No description provided for @profileLocalNickname.
  ///
  /// In zh, this message translates to:
  /// **'本地昵称'**
  String get profileLocalNickname;

  /// No description provided for @profileDefaultUser.
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get profileDefaultUser;

  /// No description provided for @profileLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地资料'**
  String get profileLocal;

  /// No description provided for @profileLocalUpdated.
  ///
  /// In zh, this message translates to:
  /// **'本地资料已更新'**
  String get profileLocalUpdated;

  /// No description provided for @profileLoginAccount.
  ///
  /// In zh, this message translates to:
  /// **'登录账号'**
  String get profileLoginAccount;

  /// No description provided for @profileEmailVerified.
  ///
  /// In zh, this message translates to:
  /// **'已验证'**
  String get profileEmailVerified;

  /// No description provided for @profileEmailUnverified.
  ///
  /// In zh, this message translates to:
  /// **'未验证'**
  String get profileEmailUnverified;

  /// No description provided for @profileEmailUnverifiedOrPending.
  ///
  /// In zh, this message translates to:
  /// **'未验证或待验证'**
  String get profileEmailUnverifiedOrPending;

  /// No description provided for @profileEmailUnbound.
  ///
  /// In zh, this message translates to:
  /// **'未绑定邮箱'**
  String get profileEmailUnbound;

  /// No description provided for @profileEmailBinding.
  ///
  /// In zh, this message translates to:
  /// **'邮箱绑定'**
  String get profileEmailBinding;

  /// No description provided for @profileEmailLocalDisplay.
  ///
  /// In zh, this message translates to:
  /// **'邮箱（仅本地展示，不用于登录或找回）'**
  String get profileEmailLocalDisplay;

  /// No description provided for @profileEmailCodeHelper.
  ///
  /// In zh, this message translates to:
  /// **'换绑或验证邮箱时填写'**
  String get profileEmailCodeHelper;

  /// No description provided for @profileAvatarUrlOrText.
  ///
  /// In zh, this message translates to:
  /// **'头像 URL 或文字'**
  String get profileAvatarUrlOrText;

  /// No description provided for @profileAvatarUrlFileOrText.
  ///
  /// In zh, this message translates to:
  /// **'头像 URL、本地文件或文字'**
  String get profileAvatarUrlFileOrText;

  /// No description provided for @profileAvatarHelper.
  ///
  /// In zh, this message translates to:
  /// **'可选择图片，或填写文字作为头像首字'**
  String get profileAvatarHelper;

  /// No description provided for @profileAvatarUpload.
  ///
  /// In zh, this message translates to:
  /// **'上传'**
  String get profileAvatarUpload;

  /// No description provided for @profileAvatarChoose.
  ///
  /// In zh, this message translates to:
  /// **'选择'**
  String get profileAvatarChoose;

  /// No description provided for @profileAvatarEmpty.
  ///
  /// In zh, this message translates to:
  /// **'头像文件不能为空'**
  String get profileAvatarEmpty;

  /// No description provided for @profileAvatarTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'头像不能超过 3MB'**
  String get profileAvatarTooLarge;

  /// No description provided for @profileAvatarUploaded.
  ///
  /// In zh, this message translates to:
  /// **'头像已上传'**
  String get profileAvatarUploaded;

  /// No description provided for @profileAvatarSaved.
  ///
  /// In zh, this message translates to:
  /// **'头像已保存'**
  String get profileAvatarSaved;

  /// No description provided for @profileAvatarSelected.
  ///
  /// In zh, this message translates to:
  /// **'头像已选择，点击保存后生效'**
  String get profileAvatarSelected;

  /// No description provided for @profileCoins.
  ///
  /// In zh, this message translates to:
  /// **'时光币'**
  String get profileCoins;

  /// No description provided for @profileAccountId.
  ///
  /// In zh, this message translates to:
  /// **'账号'**
  String get profileAccountId;

  /// No description provided for @profileUsernameLocked.
  ///
  /// In zh, this message translates to:
  /// **'用户名是账号唯一标识，暂不在资料页修改'**
  String get profileUsernameLocked;

  /// No description provided for @profileAccountSecurity.
  ///
  /// In zh, this message translates to:
  /// **'账号安全'**
  String get profileAccountSecurity;

  /// No description provided for @profileAccountSecuritySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'密码等敏感操作集中在这里'**
  String get profileAccountSecuritySubtitle;

  /// No description provided for @profileBio.
  ///
  /// In zh, this message translates to:
  /// **'简介'**
  String get profileBio;

  /// No description provided for @profileUpdated.
  ///
  /// In zh, this message translates to:
  /// **'资料已更新'**
  String get profileUpdated;

  /// No description provided for @profileSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get profileSaved;

  /// No description provided for @profileSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法保存'**
  String get profileSaveFailed;

  /// No description provided for @profileChangePassword.
  ///
  /// In zh, this message translates to:
  /// **'修改登录密码'**
  String get profileChangePassword;

  /// No description provided for @profileChangePasswordSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'需要输入当前密码'**
  String get profileChangePasswordSubtitle;

  /// No description provided for @profileCurrentPassword.
  ///
  /// In zh, this message translates to:
  /// **'当前密码'**
  String get profileCurrentPassword;

  /// No description provided for @profileConfirmNewPassword.
  ///
  /// In zh, this message translates to:
  /// **'确认新密码'**
  String get profileConfirmNewPassword;

  /// No description provided for @profilePasswordUpdated.
  ///
  /// In zh, this message translates to:
  /// **'登录密码已更新'**
  String get profilePasswordUpdated;

  /// No description provided for @profileErrorNicknameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写昵称'**
  String get profileErrorNicknameRequired;

  /// No description provided for @habitDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'习惯详情'**
  String get habitDetailTitle;

  /// No description provided for @habitDetailNotFound.
  ///
  /// In zh, this message translates to:
  /// **'这个习惯不存在或已被删除'**
  String get habitDetailNotFound;

  /// No description provided for @habitEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑习惯'**
  String get habitEditTitle;

  /// No description provided for @habitSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get habitSaved;

  /// No description provided for @habitFieldName.
  ///
  /// In zh, this message translates to:
  /// **'习惯名称'**
  String get habitFieldName;

  /// No description provided for @habitFieldGroup.
  ///
  /// In zh, this message translates to:
  /// **'分组'**
  String get habitFieldGroup;

  /// No description provided for @habitFieldGroupEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'留空则归入未分组'**
  String get habitFieldGroupEmptyHint;

  /// No description provided for @habitFieldDailyTargetCount.
  ///
  /// In zh, this message translates to:
  /// **'每日目标次数'**
  String get habitFieldDailyTargetCount;

  /// No description provided for @habitFieldUnit.
  ///
  /// In zh, this message translates to:
  /// **'单位'**
  String get habitFieldUnit;

  /// No description provided for @habitUnitTimes.
  ///
  /// In zh, this message translates to:
  /// **'次'**
  String get habitUnitTimes;

  /// No description provided for @habitUnitWeek.
  ///
  /// In zh, this message translates to:
  /// **'周'**
  String get habitUnitWeek;

  /// No description provided for @habitUnitMonth.
  ///
  /// In zh, this message translates to:
  /// **'月'**
  String get habitUnitMonth;

  /// No description provided for @habitKind.
  ///
  /// In zh, this message translates to:
  /// **'习惯类型'**
  String get habitKind;

  /// No description provided for @habitKindPositive.
  ///
  /// In zh, this message translates to:
  /// **'✅ 正向养成'**
  String get habitKindPositive;

  /// No description provided for @habitKindNegative.
  ///
  /// In zh, this message translates to:
  /// **'🚫 反向戒除'**
  String get habitKindNegative;

  /// No description provided for @habitColor.
  ///
  /// In zh, this message translates to:
  /// **'颜色'**
  String get habitColor;

  /// No description provided for @habitReminder.
  ///
  /// In zh, this message translates to:
  /// **'提醒'**
  String get habitReminder;

  /// No description provided for @habitErrorNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写习惯名称'**
  String get habitErrorNameRequired;

  /// No description provided for @habitErrorDailyTarget.
  ///
  /// In zh, this message translates to:
  /// **'每日目标次数至少为 1'**
  String get habitErrorDailyTarget;

  /// No description provided for @habitErrorFlexTarget.
  ///
  /// In zh, this message translates to:
  /// **'周期目标至少为 1'**
  String get habitErrorFlexTarget;

  /// No description provided for @habitErrorDateRange.
  ///
  /// In zh, this message translates to:
  /// **'结束日期不能早于开始日期'**
  String get habitErrorDateRange;

  /// No description provided for @habitErrorNotificationPermission.
  ///
  /// In zh, this message translates to:
  /// **'系统通知未授权，习惯提醒不会响铃或弹出'**
  String get habitErrorNotificationPermission;

  /// No description provided for @habitErrorReminderRegisterFailed.
  ///
  /// In zh, this message translates to:
  /// **'习惯提醒注册失败'**
  String get habitErrorReminderRegisterFailed;

  /// No description provided for @habitFlexRule.
  ///
  /// In zh, this message translates to:
  /// **'弹性打卡规则'**
  String get habitFlexRule;

  /// No description provided for @habitFlexWeekly.
  ///
  /// In zh, this message translates to:
  /// **'每周目标'**
  String get habitFlexWeekly;

  /// No description provided for @habitFlexMonthly.
  ///
  /// In zh, this message translates to:
  /// **'每月目标'**
  String get habitFlexMonthly;

  /// No description provided for @habitFlexPeriodTarget.
  ///
  /// In zh, this message translates to:
  /// **'目标次数'**
  String get habitFlexPeriodTarget;

  /// No description provided for @habitFlexPeriodTargetHint.
  ///
  /// In zh, this message translates to:
  /// **'例如每周目标 5 次'**
  String get habitFlexPeriodTargetHint;

  /// No description provided for @habitFlexDailyNote.
  ///
  /// In zh, this message translates to:
  /// **'关闭时按每日目标连续统计'**
  String get habitFlexDailyNote;

  /// No description provided for @habitFlexNegativeNote.
  ///
  /// In zh, this message translates to:
  /// **'反向戒除按每日不发生统计'**
  String get habitFlexNegativeNote;

  /// No description provided for @habitFlexWeeklyGoalPrefix.
  ///
  /// In zh, this message translates to:
  /// **'每周目标: '**
  String get habitFlexWeeklyGoalPrefix;

  /// No description provided for @habitFlexMonthlyGoalPrefix.
  ///
  /// In zh, this message translates to:
  /// **'每月目标: '**
  String get habitFlexMonthlyGoalPrefix;

  /// No description provided for @habitFlexThisWeek.
  ///
  /// In zh, this message translates to:
  /// **'本周'**
  String get habitFlexThisWeek;

  /// No description provided for @habitFlexThisMonth.
  ///
  /// In zh, this message translates to:
  /// **'本月'**
  String get habitFlexThisMonth;

  /// No description provided for @habitDailyPrefix.
  ///
  /// In zh, this message translates to:
  /// **'每天'**
  String get habitDailyPrefix;

  /// No description provided for @habitRecordedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'已记录 '**
  String get habitRecordedPrefix;

  /// No description provided for @habitStatCurrentStreak.
  ///
  /// In zh, this message translates to:
  /// **'当前连续'**
  String get habitStatCurrentStreak;

  /// No description provided for @habitStatBestStreak.
  ///
  /// In zh, this message translates to:
  /// **'最佳纪录'**
  String get habitStatBestStreak;

  /// No description provided for @habitStatToday.
  ///
  /// In zh, this message translates to:
  /// **'今日'**
  String get habitStatToday;

  /// No description provided for @habitHeatmapTitle.
  ///
  /// In zh, this message translates to:
  /// **'打卡热力图'**
  String get habitHeatmapTitle;

  /// No description provided for @habitRecordsTitle.
  ///
  /// In zh, this message translates to:
  /// **'最近记录 / 补卡'**
  String get habitRecordsTitle;

  /// No description provided for @habitRecordsInactive.
  ///
  /// In zh, this message translates to:
  /// **'未在周期内'**
  String get habitRecordsInactive;

  /// No description provided for @habitRecordsUndoOnce.
  ///
  /// In zh, this message translates to:
  /// **'撤回一次'**
  String get habitRecordsUndoOnce;

  /// No description provided for @habitRecordsRecordOnce.
  ///
  /// In zh, this message translates to:
  /// **'记录一次'**
  String get habitRecordsRecordOnce;

  /// No description provided for @habitRecordsMakeUpOnce.
  ///
  /// In zh, this message translates to:
  /// **'补一次'**
  String get habitRecordsMakeUpOnce;

  /// No description provided for @habitTrendTitle.
  ///
  /// In zh, this message translates to:
  /// **'习惯趋势'**
  String get habitTrendTitle;

  /// No description provided for @habitTrendCompleted.
  ///
  /// In zh, this message translates to:
  /// **'达标'**
  String get habitTrendCompleted;

  /// No description provided for @habitTrendDailyAverage.
  ///
  /// In zh, this message translates to:
  /// **'日均'**
  String get habitTrendDailyAverage;

  /// No description provided for @habitTrendLongestStreak.
  ///
  /// In zh, this message translates to:
  /// **'最长连续'**
  String get habitTrendLongestStreak;

  /// No description provided for @habitTrendVsPrevious.
  ///
  /// In zh, this message translates to:
  /// **'较上期'**
  String get habitTrendVsPrevious;

  /// No description provided for @habitTrendBucketDetails.
  ///
  /// In zh, this message translates to:
  /// **'区间明细'**
  String get habitTrendBucketDetails;

  /// No description provided for @habitTrendOneYear.
  ///
  /// In zh, this message translates to:
  /// **'一年'**
  String get habitTrendOneYear;

  /// No description provided for @habitDateRangeTitle.
  ///
  /// In zh, this message translates to:
  /// **'习惯周期'**
  String get habitDateRangeTitle;

  /// No description provided for @habitDateRangeStart.
  ///
  /// In zh, this message translates to:
  /// **'开始日期'**
  String get habitDateRangeStart;

  /// No description provided for @habitDateRangeEnd.
  ///
  /// In zh, this message translates to:
  /// **'结束日期'**
  String get habitDateRangeEnd;

  /// No description provided for @habitDateRangeStartEmpty.
  ///
  /// In zh, this message translates to:
  /// **'立即开始'**
  String get habitDateRangeStartEmpty;

  /// No description provided for @habitDateRangeEndEmpty.
  ///
  /// In zh, this message translates to:
  /// **'不设结束'**
  String get habitDateRangeEndEmpty;

  /// No description provided for @habitDateRangePickStart.
  ///
  /// In zh, this message translates to:
  /// **'选择开始日期'**
  String get habitDateRangePickStart;

  /// No description provided for @habitDateRangePickEnd.
  ///
  /// In zh, this message translates to:
  /// **'选择结束日期'**
  String get habitDateRangePickEnd;

  /// No description provided for @habitDateRangeLongTerm.
  ///
  /// In zh, this message translates to:
  /// **'长期有效'**
  String get habitDateRangeLongTerm;

  /// No description provided for @habitDateRangeFromSuffix.
  ///
  /// In zh, this message translates to:
  /// **'起'**
  String get habitDateRangeFromSuffix;

  /// No description provided for @habitDateRangeUntilSuffix.
  ///
  /// In zh, this message translates to:
  /// **'止'**
  String get habitDateRangeUntilSuffix;

  /// No description provided for @noteTitle.
  ///
  /// In zh, this message translates to:
  /// **'随手记'**
  String get noteTitle;

  /// No description provided for @noteEmptyMessage.
  ///
  /// In zh, this message translates to:
  /// **'随时捕捉闪念与灵感'**
  String get noteEmptyMessage;

  /// No description provided for @noteEmptyAction.
  ///
  /// In zh, this message translates to:
  /// **'写便签'**
  String get noteEmptyAction;

  /// No description provided for @noteEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑便签'**
  String get noteEditTitle;

  /// No description provided for @notePreview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get notePreview;

  /// No description provided for @noteEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get noteEdit;

  /// No description provided for @noteSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索标题、正文或附件'**
  String get noteSearchHint;

  /// No description provided for @noteSearchClear.
  ///
  /// In zh, this message translates to:
  /// **'清空搜索'**
  String get noteSearchClear;

  /// No description provided for @noteSearchEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的便签'**
  String get noteSearchEmpty;

  /// No description provided for @noteActive.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get noteActive;

  /// No description provided for @noteArchived.
  ///
  /// In zh, this message translates to:
  /// **'归档'**
  String get noteArchived;

  /// No description provided for @noteArchivedEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无归档便签'**
  String get noteArchivedEmpty;

  /// No description provided for @noteMore.
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get noteMore;

  /// No description provided for @notePin.
  ///
  /// In zh, this message translates to:
  /// **'置顶'**
  String get notePin;

  /// No description provided for @noteUnpin.
  ///
  /// In zh, this message translates to:
  /// **'取消置顶'**
  String get noteUnpin;

  /// No description provided for @noteArchive.
  ///
  /// In zh, this message translates to:
  /// **'归档'**
  String get noteArchive;

  /// No description provided for @noteRestore.
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get noteRestore;

  /// No description provided for @noteActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败，内容未变更，请重试'**
  String get noteActionFailed;

  /// No description provided for @noteLinkPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'链接文字'**
  String get noteLinkPlaceholder;

  /// No description provided for @noteAttachmentPickFile.
  ///
  /// In zh, this message translates to:
  /// **'从系统文件选择'**
  String get noteAttachmentPickFile;

  /// No description provided for @noteAttachmentPickFileSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'图片、PDF、文档等都会作为附件保存'**
  String get noteAttachmentPickFileSubtitle;

  /// No description provided for @noteAttachmentAddLink.
  ///
  /// In zh, this message translates to:
  /// **'添加链接或本地路径'**
  String get noteAttachmentAddLink;

  /// No description provided for @noteAttachmentAddLinkSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'适合网页图片、资料链接和已知文件路径'**
  String get noteAttachmentAddLinkSubtitle;

  /// No description provided for @noteAttachmentFileNotSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择文件，已切换为手动添加'**
  String get noteAttachmentFileNotSelected;

  /// No description provided for @noteAttachmentDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加附件'**
  String get noteAttachmentDialogTitle;

  /// No description provided for @noteAttachmentName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get noteAttachmentName;

  /// No description provided for @noteAttachmentUri.
  ///
  /// In zh, this message translates to:
  /// **'链接或本地路径'**
  String get noteAttachmentUri;

  /// No description provided for @noteAttachmentUriHint.
  ///
  /// In zh, this message translates to:
  /// **'https://... 或 /storage/...'**
  String get noteAttachmentUriHint;

  /// No description provided for @noteAttachmentType.
  ///
  /// In zh, this message translates to:
  /// **'类型（可选）'**
  String get noteAttachmentType;

  /// No description provided for @noteAttachmentTypeHint.
  ///
  /// In zh, this message translates to:
  /// **'例如 image/png、application/pdf'**
  String get noteAttachmentTypeHint;

  /// No description provided for @noteAttachmentDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'附件'**
  String get noteAttachmentDefaultName;

  /// No description provided for @noteEditorHint.
  ///
  /// In zh, this message translates to:
  /// **'写点什么，支持 Markdown、清单和附件...'**
  String get noteEditorHint;

  /// No description provided for @noteToolbarHeading.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get noteToolbarHeading;

  /// No description provided for @noteToolbarBold.
  ///
  /// In zh, this message translates to:
  /// **'加粗'**
  String get noteToolbarBold;

  /// No description provided for @noteToolbarItalic.
  ///
  /// In zh, this message translates to:
  /// **'斜体'**
  String get noteToolbarItalic;

  /// No description provided for @noteToolbarQuote.
  ///
  /// In zh, this message translates to:
  /// **'引用'**
  String get noteToolbarQuote;

  /// No description provided for @noteToolbarBullet.
  ///
  /// In zh, this message translates to:
  /// **'项目符号'**
  String get noteToolbarBullet;

  /// No description provided for @noteToolbarChecklist.
  ///
  /// In zh, this message translates to:
  /// **'清单'**
  String get noteToolbarChecklist;

  /// No description provided for @noteToolbarCode.
  ///
  /// In zh, this message translates to:
  /// **'行内代码'**
  String get noteToolbarCode;

  /// No description provided for @noteToolbarLink.
  ///
  /// In zh, this message translates to:
  /// **'链接'**
  String get noteToolbarLink;

  /// No description provided for @noteToolbarAttachment.
  ///
  /// In zh, this message translates to:
  /// **'附件'**
  String get noteToolbarAttachment;

  /// No description provided for @notePreviewEmpty.
  ///
  /// In zh, this message translates to:
  /// **'空白便签'**
  String get notePreviewEmpty;

  /// No description provided for @feedbackCategoryFeature.
  ///
  /// In zh, this message translates to:
  /// **'功能建议'**
  String get feedbackCategoryFeature;

  /// No description provided for @feedbackCategoryBug.
  ///
  /// In zh, this message translates to:
  /// **'问题反馈'**
  String get feedbackCategoryBug;

  /// No description provided for @feedbackCategoryWish.
  ///
  /// In zh, this message translates to:
  /// **'许愿池'**
  String get feedbackCategoryWish;

  /// No description provided for @feedbackCategoryOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get feedbackCategoryOther;

  /// No description provided for @feedbackHelpFeature.
  ///
  /// In zh, this message translates to:
  /// **'描述你想新增或优化的功能'**
  String get feedbackHelpFeature;

  /// No description provided for @feedbackHelpBug.
  ///
  /// In zh, this message translates to:
  /// **'说明复现路径、当前表现和期望表现'**
  String get feedbackHelpBug;

  /// No description provided for @feedbackHelpWish.
  ///
  /// In zh, this message translates to:
  /// **'写下你希望增加的场景或能力'**
  String get feedbackHelpWish;

  /// No description provided for @feedbackHelpOther.
  ///
  /// In zh, this message translates to:
  /// **'补充其他想让团队知道的信息'**
  String get feedbackHelpOther;

  /// No description provided for @feedbackStatusResolved.
  ///
  /// In zh, this message translates to:
  /// **'已处理'**
  String get feedbackStatusResolved;

  /// No description provided for @feedbackStatusClosed.
  ///
  /// In zh, this message translates to:
  /// **'已关闭'**
  String get feedbackStatusClosed;

  /// No description provided for @feedbackStatusInProgress.
  ///
  /// In zh, this message translates to:
  /// **'处理中'**
  String get feedbackStatusInProgress;

  /// No description provided for @feedbackStatusOpen.
  ///
  /// In zh, this message translates to:
  /// **'待处理'**
  String get feedbackStatusOpen;

  /// No description provided for @feedbackLoginRecordsRequired.
  ///
  /// In zh, this message translates to:
  /// **'登录后可查看反馈记录'**
  String get feedbackLoginRecordsRequired;

  /// No description provided for @feedbackLoginSubmitRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先登录后再提交反馈'**
  String get feedbackLoginSubmitRequired;

  /// No description provided for @feedbackLoginSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'登录后可以提交并查看处理记录'**
  String get feedbackLoginSubtitle;

  /// No description provided for @feedbackLoginSectionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'当前未登录，无法提交或查看反馈处理记录'**
  String get feedbackLoginSectionSubtitle;

  /// No description provided for @feedbackContentEmpty.
  ///
  /// In zh, this message translates to:
  /// **'反馈内容不能为空'**
  String get feedbackContentEmpty;

  /// No description provided for @feedbackSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'反馈已提交，感谢！'**
  String get feedbackSubmitted;

  /// No description provided for @feedbackSubmitPrefix.
  ///
  /// In zh, this message translates to:
  /// **'提交'**
  String get feedbackSubmitPrefix;

  /// No description provided for @feedbackSubmitLoginPrefix.
  ///
  /// In zh, this message translates to:
  /// **'登录后提交'**
  String get feedbackSubmitLoginPrefix;

  /// No description provided for @feedbackCategoryLabel.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get feedbackCategoryLabel;

  /// No description provided for @feedbackContentLabelPrefix.
  ///
  /// In zh, this message translates to:
  /// **'描述一下你的'**
  String get feedbackContentLabelPrefix;

  /// No description provided for @feedbackSubmitButton.
  ///
  /// In zh, this message translates to:
  /// **'提交反馈'**
  String get feedbackSubmitButton;

  /// No description provided for @feedbackSubmitting.
  ///
  /// In zh, this message translates to:
  /// **'提交中'**
  String get feedbackSubmitting;

  /// No description provided for @feedbackMineTitle.
  ///
  /// In zh, this message translates to:
  /// **'我的反馈'**
  String get feedbackMineTitle;

  /// No description provided for @feedbackLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在加载'**
  String get feedbackLoading;

  /// No description provided for @feedbackRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近提交的记录'**
  String get feedbackRecent;

  /// No description provided for @feedbackEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有反馈记录'**
  String get feedbackEmpty;

  /// No description provided for @feedbackRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get feedbackRefresh;

  /// No description provided for @feedbackAdminReply.
  ///
  /// In zh, this message translates to:
  /// **'管理员回复'**
  String get feedbackAdminReply;

  /// No description provided for @announcementTitle.
  ///
  /// In zh, this message translates to:
  /// **'公告'**
  String get announcementTitle;

  /// No description provided for @announcementCenter.
  ///
  /// In zh, this message translates to:
  /// **'公告中心'**
  String get announcementCenter;

  /// No description provided for @announcementSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'系统通知、维护说明和版本更新会先出现在这里'**
  String get announcementSubtitle;

  /// No description provided for @announcementLatest.
  ///
  /// In zh, this message translates to:
  /// **'最新公告'**
  String get announcementLatest;

  /// No description provided for @announcementPullToRefresh.
  ///
  /// In zh, this message translates to:
  /// **'下拉可刷新'**
  String get announcementPullToRefresh;

  /// No description provided for @announcementEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无公告'**
  String get announcementEmpty;

  /// No description provided for @announcementRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get announcementRefresh;

  /// No description provided for @announcementLoadFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'公告加载失败：'**
  String get announcementLoadFailedPrefix;

  /// No description provided for @announcementLevelInfo.
  ///
  /// In zh, this message translates to:
  /// **'公告'**
  String get announcementLevelInfo;

  /// No description provided for @announcementLevelWarning.
  ///
  /// In zh, this message translates to:
  /// **'提醒'**
  String get announcementLevelWarning;

  /// No description provided for @announcementLevelCritical.
  ///
  /// In zh, this message translates to:
  /// **'重要'**
  String get announcementLevelCritical;

  /// No description provided for @themeTitle.
  ///
  /// In zh, this message translates to:
  /// **'主题风格'**
  String get themeTitle;

  /// No description provided for @themeSectionStyles.
  ///
  /// In zh, this message translates to:
  /// **'可选风格'**
  String get themeSectionStyles;

  /// No description provided for @themeSectionStylesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切换后会同步全局主题'**
  String get themeSectionStylesSubtitle;

  /// No description provided for @themeStyleDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'多仪'**
  String get themeStyleDefaultName;

  /// No description provided for @themeStyleDefaultDescription.
  ///
  /// In zh, this message translates to:
  /// **'简洁原版 · 暖橙基调'**
  String get themeStyleDefaultDescription;

  /// No description provided for @themeStyleRe0Name.
  ///
  /// In zh, this message translates to:
  /// **'从零开始'**
  String get themeStyleRe0Name;

  /// No description provided for @themeStyleRe0Description.
  ///
  /// In zh, this message translates to:
  /// **'银发魔女 · 露格尼卡圣域'**
  String get themeStyleRe0Description;

  /// No description provided for @themeStyleGenshinName.
  ///
  /// In zh, this message translates to:
  /// **'原神'**
  String get themeStyleGenshinName;

  /// No description provided for @themeStyleGenshinDescription.
  ///
  /// In zh, this message translates to:
  /// **'元素绘卷 · 提瓦特画架'**
  String get themeStyleGenshinDescription;

  /// No description provided for @themeStyleStarRailName.
  ///
  /// In zh, this message translates to:
  /// **'星穹铁道'**
  String get themeStyleStarRailName;

  /// No description provided for @themeStyleStarRailDescription.
  ///
  /// In zh, this message translates to:
  /// **'星穹列车 · 开拓之旅'**
  String get themeStyleStarRailDescription;

  /// No description provided for @themeStyleWutheringName.
  ///
  /// In zh, this message translates to:
  /// **'鸣潮'**
  String get themeStyleWutheringName;

  /// No description provided for @themeStyleWutheringDescription.
  ///
  /// In zh, this message translates to:
  /// **'共鸣终端 · 潮声频谱'**
  String get themeStyleWutheringDescription;

  /// No description provided for @themeStyleZzzName.
  ///
  /// In zh, this message translates to:
  /// **'绝区零'**
  String get themeStyleZzzName;

  /// No description provided for @themeStyleZzzDescription.
  ///
  /// In zh, this message translates to:
  /// **'委托影像 · 新艾利都'**
  String get themeStyleZzzDescription;

  /// No description provided for @themeStyleYanyunName.
  ///
  /// In zh, this message translates to:
  /// **'燕云十六声'**
  String get themeStyleYanyunName;

  /// No description provided for @themeStyleYanyunDescription.
  ///
  /// In zh, this message translates to:
  /// **'江湖画案 · 墨痕回转'**
  String get themeStyleYanyunDescription;

  /// No description provided for @themeStyleBotwName.
  ///
  /// In zh, this message translates to:
  /// **'希卡之石'**
  String get themeStyleBotwName;

  /// No description provided for @themeStyleBotwDescription.
  ///
  /// In zh, this message translates to:
  /// **'希卡之石 · 具现化'**
  String get themeStyleBotwDescription;

  /// No description provided for @themeStyleLiquidGlassName.
  ///
  /// In zh, this message translates to:
  /// **'液态玻璃'**
  String get themeStyleLiquidGlassName;

  /// No description provided for @themeStyleLiquidGlassDescription.
  ///
  /// In zh, this message translates to:
  /// **'iOS 玻璃拟态 · 半透明白与高光'**
  String get themeStyleLiquidGlassDescription;

  /// No description provided for @goalTitle.
  ///
  /// In zh, this message translates to:
  /// **'目标管理'**
  String get goalTitle;

  /// No description provided for @goalRecommendedTemplates.
  ///
  /// In zh, this message translates to:
  /// **'推荐模板'**
  String get goalRecommendedTemplates;

  /// No description provided for @goalEmpty.
  ///
  /// In zh, this message translates to:
  /// **'设立一个目标，让时间为你累积'**
  String get goalEmpty;

  /// No description provided for @goalCreate.
  ///
  /// In zh, this message translates to:
  /// **'新建目标'**
  String get goalCreate;

  /// No description provided for @goalNew.
  ///
  /// In zh, this message translates to:
  /// **'新目标'**
  String get goalNew;

  /// No description provided for @goalStatusActive.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get goalStatusActive;

  /// No description provided for @goalStatusPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get goalStatusPaused;

  /// No description provided for @goalStatusAchieved.
  ///
  /// In zh, this message translates to:
  /// **'已达成'**
  String get goalStatusAchieved;

  /// No description provided for @goalStatusAbandoned.
  ///
  /// In zh, this message translates to:
  /// **'已放弃'**
  String get goalStatusAbandoned;

  /// No description provided for @goalMilestonePrefix.
  ///
  /// In zh, this message translates to:
  /// **'里程碑 '**
  String get goalMilestonePrefix;

  /// No description provided for @goalDaysRemainingPrefix.
  ///
  /// In zh, this message translates to:
  /// **'还剩 '**
  String get goalDaysRemainingPrefix;

  /// No description provided for @goalDaysRemainingSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 天'**
  String get goalDaysRemainingSuffix;

  /// No description provided for @goalOverduePrefix.
  ///
  /// In zh, this message translates to:
  /// **'已超期 '**
  String get goalOverduePrefix;

  /// No description provided for @goalOverdueSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 天'**
  String get goalOverdueSuffix;

  /// No description provided for @exportTitle.
  ///
  /// In zh, this message translates to:
  /// **'导出为日历 (.ics)'**
  String get exportTitle;

  /// No description provided for @exportHeroTitle.
  ///
  /// In zh, this message translates to:
  /// **'日历导出'**
  String get exportHeroTitle;

  /// No description provided for @exportHeroSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'生成一份 iCalendar 文件，可粘贴到系统日历、Google Calendar 或 Outlook。'**
  String get exportHeroSubtitle;

  /// No description provided for @exportRangeTitle.
  ///
  /// In zh, this message translates to:
  /// **'导出范围'**
  String get exportRangeTitle;

  /// No description provided for @exportRangeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'选择要包含的内容'**
  String get exportRangeSubtitle;

  /// No description provided for @exportIncludeAnniversaries.
  ///
  /// In zh, this message translates to:
  /// **'包含纪念日与生日'**
  String get exportIncludeAnniversaries;

  /// No description provided for @exportIncludeAnniversariesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'YEARLY 循环事件'**
  String get exportIncludeAnniversariesSubtitle;

  /// No description provided for @exportIncludeCalendar.
  ///
  /// In zh, this message translates to:
  /// **'包含日程总表'**
  String get exportIncludeCalendar;

  /// No description provided for @exportIncludeCalendarSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'待办、习惯、课程、日记和目标'**
  String get exportIncludeCalendarSubtitle;

  /// No description provided for @exportPushCaldav.
  ///
  /// In zh, this message translates to:
  /// **'写回 CalDAV'**
  String get exportPushCaldav;

  /// No description provided for @exportGenerateIcs.
  ///
  /// In zh, this message translates to:
  /// **'生成 .ics'**
  String get exportGenerateIcs;

  /// No description provided for @exportContentTitle.
  ///
  /// In zh, this message translates to:
  /// **'导出内容'**
  String get exportContentTitle;

  /// No description provided for @exportCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get exportCopy;

  /// No description provided for @exportCopyDone.
  ///
  /// In zh, this message translates to:
  /// **'已复制 .ics 内容'**
  String get exportCopyDone;

  /// No description provided for @exportCaldavSuccessPrefix.
  ///
  /// In zh, this message translates to:
  /// **'已写回 '**
  String get exportCaldavSuccessPrefix;

  /// No description provided for @exportCaldavSuccessSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 条日历事件到 CalDAV'**
  String get exportCaldavSuccessSuffix;

  /// No description provided for @exportCaldavConflictPrefix.
  ///
  /// In zh, this message translates to:
  /// **'已写回 '**
  String get exportCaldavConflictPrefix;

  /// No description provided for @exportCaldavConflictMiddle.
  ///
  /// In zh, this message translates to:
  /// **' 条，跳过 '**
  String get exportCaldavConflictMiddle;

  /// No description provided for @exportCaldavConflictSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 条远端已修改事件'**
  String get exportCaldavConflictSuffix;

  /// No description provided for @exportCaldavFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'CalDAV 写回失败: '**
  String get exportCaldavFailedPrefix;

  /// No description provided for @appLockTitle.
  ///
  /// In zh, this message translates to:
  /// **'应用锁'**
  String get appLockTitle;

  /// No description provided for @appLockHeroTitle.
  ///
  /// In zh, this message translates to:
  /// **'本机 PIN 锁'**
  String get appLockHeroTitle;

  /// No description provided for @appLockHeroSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'用于保护本地数据，切回应用或重新启动时需要验证'**
  String get appLockHeroSubtitle;

  /// No description provided for @appLockSectionStatus.
  ///
  /// In zh, this message translates to:
  /// **'锁定状态'**
  String get appLockSectionStatus;

  /// No description provided for @appLockSectionStatusSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'启用后会在启动或切回前台时要求 PIN'**
  String get appLockSectionStatusSubtitle;

  /// No description provided for @appLockEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用应用锁'**
  String get appLockEnable;

  /// No description provided for @appLockEnabled.
  ///
  /// In zh, this message translates to:
  /// **'当前已启用'**
  String get appLockEnabled;

  /// No description provided for @appLockDisabledSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'关闭后不会再要求 PIN'**
  String get appLockDisabledSubtitle;

  /// No description provided for @appLockChangePin.
  ///
  /// In zh, this message translates to:
  /// **'更换 PIN'**
  String get appLockChangePin;

  /// No description provided for @appLockChangePinSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'重新设置 4-8 位数字密码'**
  String get appLockChangePinSubtitle;

  /// No description provided for @appLockAutoLock.
  ///
  /// In zh, this message translates to:
  /// **'自动锁定'**
  String get appLockAutoLock;

  /// No description provided for @appLockAutoLockImmediate.
  ///
  /// In zh, this message translates to:
  /// **'立即'**
  String get appLockAutoLockImmediate;

  /// No description provided for @appLockAutoLockEveryForeground.
  ///
  /// In zh, this message translates to:
  /// **'每次切回前台都锁定'**
  String get appLockAutoLockEveryForeground;

  /// No description provided for @appLockAutoLockAfterPrefix.
  ///
  /// In zh, this message translates to:
  /// **'离开 '**
  String get appLockAutoLockAfterPrefix;

  /// No description provided for @appLockAutoLockAfterSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 分钟后锁定'**
  String get appLockAutoLockAfterSuffix;

  /// No description provided for @appLockAutoLockMinuteLabel.
  ///
  /// In zh, this message translates to:
  /// **' 分钟'**
  String get appLockAutoLockMinuteLabel;

  /// No description provided for @appLockAutoLockOneHour.
  ///
  /// In zh, this message translates to:
  /// **'1 小时'**
  String get appLockAutoLockOneHour;

  /// No description provided for @appLockAutoLockFourHours.
  ///
  /// In zh, this message translates to:
  /// **'4 小时'**
  String get appLockAutoLockFourHours;

  /// No description provided for @appLockLockNow.
  ///
  /// In zh, this message translates to:
  /// **'立即锁定'**
  String get appLockLockNow;

  /// No description provided for @appLockLockNowSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'立刻切回输入 PIN'**
  String get appLockLockNowSubtitle;

  /// No description provided for @appLockTip.
  ///
  /// In zh, this message translates to:
  /// **'提示：应用锁仅作用于本机，云端数据不受影响；忘记 PIN 只能清应用数据找回。'**
  String get appLockTip;

  /// No description provided for @appLockDialogSetPin.
  ///
  /// In zh, this message translates to:
  /// **'设置 PIN (4-8 位数字)'**
  String get appLockDialogSetPin;

  /// No description provided for @appLockDialogConfirmPin.
  ///
  /// In zh, this message translates to:
  /// **'再输一遍确认'**
  String get appLockDialogConfirmPin;

  /// No description provided for @appLockDialogDisablePin.
  ///
  /// In zh, this message translates to:
  /// **'输入当前 PIN 以关闭'**
  String get appLockDialogDisablePin;

  /// No description provided for @appLockPinHint.
  ///
  /// In zh, this message translates to:
  /// **'4-8 位数字'**
  String get appLockPinHint;

  /// No description provided for @appLockPinMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入不一致'**
  String get appLockPinMismatch;

  /// No description provided for @appLockPinInvalid.
  ///
  /// In zh, this message translates to:
  /// **'需要 4-8 位数字'**
  String get appLockPinInvalid;

  /// No description provided for @appLockPinWrong.
  ///
  /// In zh, this message translates to:
  /// **'PIN 错误'**
  String get appLockPinWrong;

  /// No description provided for @appLockEnabledMessage.
  ///
  /// In zh, this message translates to:
  /// **'应用锁已启用'**
  String get appLockEnabledMessage;

  /// No description provided for @appLockDisabledMessage.
  ///
  /// In zh, this message translates to:
  /// **'应用锁已关闭'**
  String get appLockDisabledMessage;

  /// No description provided for @aiHistoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 周回顾历史'**
  String get aiHistoryTitle;

  /// No description provided for @aiHistoryClearTooltip.
  ///
  /// In zh, this message translates to:
  /// **'清空历史'**
  String get aiHistoryClearTooltip;

  /// No description provided for @aiHistoryClearTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空全部回顾?'**
  String get aiHistoryClearTitle;

  /// No description provided for @aiHistoryClearContent.
  ///
  /// In zh, this message translates to:
  /// **'本地保留的 AI 回顾将被删除，无法恢复'**
  String get aiHistoryClearContent;

  /// No description provided for @aiHistoryClearAction.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get aiHistoryClearAction;

  /// No description provided for @aiHistoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有 AI 回顾\n在\"我的\"页生成一份吧'**
  String get aiHistoryEmpty;

  /// No description provided for @aiHistoryCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get aiHistoryCopy;

  /// No description provided for @aiHistoryCopyDone.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get aiHistoryCopyDone;

  /// No description provided for @aiHistoryDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get aiHistoryDelete;

  /// No description provided for @syncConflictTitle.
  ///
  /// In zh, this message translates to:
  /// **'同步冲突记录'**
  String get syncConflictTitle;

  /// No description provided for @syncConflictEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无同步冲突记录'**
  String get syncConflictEmpty;

  /// No description provided for @syncConflictKeepRemote.
  ///
  /// In zh, this message translates to:
  /// **'保留云端版本'**
  String get syncConflictKeepRemote;

  /// No description provided for @syncConflictKeepLocal.
  ///
  /// In zh, this message translates to:
  /// **'保留本地版本'**
  String get syncConflictKeepLocal;

  /// No description provided for @syncConflictType.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get syncConflictType;

  /// No description provided for @syncConflictItem.
  ///
  /// In zh, this message translates to:
  /// **'任务'**
  String get syncConflictItem;

  /// No description provided for @syncConflictWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'空间'**
  String get syncConflictWorkspace;

  /// No description provided for @syncConflictLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地'**
  String get syncConflictLocal;

  /// No description provided for @syncConflictRemote.
  ///
  /// In zh, this message translates to:
  /// **'云端'**
  String get syncConflictRemote;

  /// No description provided for @todayAlmanacTitle.
  ///
  /// In zh, this message translates to:
  /// **'万年历'**
  String get todayAlmanacTitle;

  /// No description provided for @todayUnitItem.
  ///
  /// In zh, this message translates to:
  /// **'项'**
  String get todayUnitItem;

  /// No description provided for @todayUnitTimes.
  ///
  /// In zh, this message translates to:
  /// **'次'**
  String get todayUnitTimes;

  /// No description provided for @todayUnitCourseSection.
  ///
  /// In zh, this message translates to:
  /// **'节'**
  String get todayUnitCourseSection;

  /// No description provided for @todayUnitPoint.
  ///
  /// In zh, this message translates to:
  /// **'分'**
  String get todayUnitPoint;

  /// No description provided for @todayDiary.
  ///
  /// In zh, this message translates to:
  /// **'日记'**
  String get todayDiary;

  /// No description provided for @todayDiaryWritten.
  ///
  /// In zh, this message translates to:
  /// **'已写'**
  String get todayDiaryWritten;

  /// No description provided for @todayDiaryUnwritten.
  ///
  /// In zh, this message translates to:
  /// **'未写'**
  String get todayDiaryUnwritten;

  /// No description provided for @todaySuggestions.
  ///
  /// In zh, this message translates to:
  /// **'今日建议'**
  String get todaySuggestions;

  /// No description provided for @todaySuggestionsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'根据截止时间、优先级和四象限自动推荐'**
  String get todaySuggestionsSubtitle;

  /// No description provided for @todayAddedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'已加入今日：'**
  String get todayAddedPrefix;

  /// No description provided for @todayAddToToday.
  ///
  /// In zh, this message translates to:
  /// **'加入今日'**
  String get todayAddToToday;

  /// No description provided for @todayTodos.
  ///
  /// In zh, this message translates to:
  /// **'今日待办'**
  String get todayTodos;

  /// No description provided for @todayCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get todayCompleted;

  /// No description provided for @todayCourses.
  ///
  /// In zh, this message translates to:
  /// **'今日课程'**
  String get todayCourses;

  /// No description provided for @todayCoursePeriodPrefix.
  ///
  /// In zh, this message translates to:
  /// **'第'**
  String get todayCoursePeriodPrefix;

  /// No description provided for @todayCoursePeriodSuffix.
  ///
  /// In zh, this message translates to:
  /// **'节'**
  String get todayCoursePeriodSuffix;

  /// No description provided for @todayUpcomingAnniversaries.
  ///
  /// In zh, this message translates to:
  /// **'即将到来的纪念日'**
  String get todayUpcomingAnniversaries;

  /// No description provided for @todayAnniversaryToday.
  ///
  /// In zh, this message translates to:
  /// **'就是今天'**
  String get todayAnniversaryToday;

  /// No description provided for @todayAnniversaryDaysPrefix.
  ///
  /// In zh, this message translates to:
  /// **'还有 '**
  String get todayAnniversaryDaysPrefix;

  /// No description provided for @todayActiveGoals.
  ///
  /// In zh, this message translates to:
  /// **'进行中的目标'**
  String get todayActiveGoals;

  /// No description provided for @todayGoalCreateSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'从今日页直接创建，不必进入目标管理'**
  String get todayGoalCreateSubtitle;

  /// No description provided for @todayView.
  ///
  /// In zh, this message translates to:
  /// **'查看'**
  String get todayView;

  /// No description provided for @todayProductivityScore.
  ///
  /// In zh, this message translates to:
  /// **'效率分'**
  String get todayProductivityScore;

  /// No description provided for @todayProductivityWeekly.
  ///
  /// In zh, this message translates to:
  /// **'本周效率'**
  String get todayProductivityWeekly;

  /// No description provided for @todayProductivityFlat.
  ///
  /// In zh, this message translates to:
  /// **'持平'**
  String get todayProductivityFlat;

  /// No description provided for @todayProductivitySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'较上周同段 · 点击查看统计报表'**
  String get todayProductivitySubtitle;

  /// No description provided for @todayProductivityCompletionRate.
  ///
  /// In zh, this message translates to:
  /// **'完成率'**
  String get todayProductivityCompletionRate;

  /// No description provided for @diaryTitle.
  ///
  /// In zh, this message translates to:
  /// **'日记'**
  String get diaryTitle;

  /// No description provided for @diaryWrite.
  ///
  /// In zh, this message translates to:
  /// **'写日记'**
  String get diaryWrite;

  /// No description provided for @diaryEmptyMessage.
  ///
  /// In zh, this message translates to:
  /// **'开始记录每天的心情吧'**
  String get diaryEmptyMessage;

  /// No description provided for @diaryStatsTooltip.
  ///
  /// In zh, this message translates to:
  /// **'心情统计'**
  String get diaryStatsTooltip;

  /// No description provided for @diarySummaryTitle.
  ///
  /// In zh, this message translates to:
  /// **'记录概览'**
  String get diarySummaryTitle;

  /// No description provided for @diarySummarySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'累计、本月和连续写作状态'**
  String get diarySummarySubtitle;

  /// No description provided for @diarySummaryTotal.
  ///
  /// In zh, this message translates to:
  /// **'累计'**
  String get diarySummaryTotal;

  /// No description provided for @diarySummaryThisMonth.
  ///
  /// In zh, this message translates to:
  /// **'本月'**
  String get diarySummaryThisMonth;

  /// No description provided for @diarySummaryStreak.
  ///
  /// In zh, this message translates to:
  /// **'连续'**
  String get diarySummaryStreak;

  /// No description provided for @diaryRecentTitle.
  ///
  /// In zh, this message translates to:
  /// **'最近日记'**
  String get diaryRecentTitle;

  /// No description provided for @diaryRecentRecordsSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 篇记录'**
  String get diaryRecentRecordsSuffix;

  /// No description provided for @diaryRecentRecordsSuffixSingular.
  ///
  /// In zh, this message translates to:
  /// **' 篇记录'**
  String get diaryRecentRecordsSuffixSingular;

  /// No description provided for @diaryEntryCountSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 篇'**
  String get diaryEntryCountSuffix;

  /// No description provided for @diaryEntryCountSuffixSingular.
  ///
  /// In zh, this message translates to:
  /// **' 篇'**
  String get diaryEntryCountSuffixSingular;

  /// No description provided for @diaryStreakDaySingular.
  ///
  /// In zh, this message translates to:
  /// **'天'**
  String get diaryStreakDaySingular;

  /// No description provided for @diaryMoodStatsTitle.
  ///
  /// In zh, this message translates to:
  /// **'近 30 天心情分布'**
  String get diaryMoodStatsTitle;

  /// No description provided for @diaryNoData.
  ///
  /// In zh, this message translates to:
  /// **'暂无数据'**
  String get diaryNoData;

  /// No description provided for @diaryAiInsights.
  ///
  /// In zh, this message translates to:
  /// **'AI 日记洞察'**
  String get diaryAiInsights;

  /// No description provided for @diaryAiDeepReviewTooltip.
  ///
  /// In zh, this message translates to:
  /// **'AI 深度复盘'**
  String get diaryAiDeepReviewTooltip;

  /// No description provided for @diaryAiDeepReviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 日记深度复盘'**
  String get diaryAiDeepReviewTitle;

  /// No description provided for @diaryAiDisabled.
  ///
  /// In zh, this message translates to:
  /// **'AI 功能未启用，请联系管理员'**
  String get diaryAiDisabled;

  /// No description provided for @diaryAiReviewFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'AI 日记复盘失败：'**
  String get diaryAiReviewFailedPrefix;

  /// No description provided for @diaryEditorDateTitle.
  ///
  /// In zh, this message translates to:
  /// **'日记日期'**
  String get diaryEditorDateTitle;

  /// No description provided for @diaryEditorMoodPrompt.
  ///
  /// In zh, this message translates to:
  /// **'今天心情如何？'**
  String get diaryEditorMoodPrompt;

  /// No description provided for @diaryEditorWeather.
  ///
  /// In zh, this message translates to:
  /// **'天气'**
  String get diaryEditorWeather;

  /// No description provided for @diaryEditorTagHint.
  ///
  /// In zh, this message translates to:
  /// **'添加标签 (如: 学习、旅行)'**
  String get diaryEditorTagHint;

  /// No description provided for @diaryEditorContentHint.
  ///
  /// In zh, this message translates to:
  /// **'写下今天的故事...'**
  String get diaryEditorContentHint;

  /// No description provided for @diaryMoodAwesome.
  ///
  /// In zh, this message translates to:
  /// **'超棒'**
  String get diaryMoodAwesome;

  /// No description provided for @diaryMoodGood.
  ///
  /// In zh, this message translates to:
  /// **'开心'**
  String get diaryMoodGood;

  /// No description provided for @diaryMoodOkay.
  ///
  /// In zh, this message translates to:
  /// **'平静'**
  String get diaryMoodOkay;

  /// No description provided for @diaryMoodBad.
  ///
  /// In zh, this message translates to:
  /// **'郁闷'**
  String get diaryMoodBad;

  /// No description provided for @diaryMoodTerrible.
  ///
  /// In zh, this message translates to:
  /// **'糟糕'**
  String get diaryMoodTerrible;

  /// No description provided for @diaryWeatherSunny.
  ///
  /// In zh, this message translates to:
  /// **'晴'**
  String get diaryWeatherSunny;

  /// No description provided for @diaryWeatherCloudy.
  ///
  /// In zh, this message translates to:
  /// **'多云'**
  String get diaryWeatherCloudy;

  /// No description provided for @diaryWeatherOvercast.
  ///
  /// In zh, this message translates to:
  /// **'阴'**
  String get diaryWeatherOvercast;

  /// No description provided for @diaryWeatherRain.
  ///
  /// In zh, this message translates to:
  /// **'雨'**
  String get diaryWeatherRain;

  /// No description provided for @diaryWeatherSnow.
  ///
  /// In zh, this message translates to:
  /// **'雪'**
  String get diaryWeatherSnow;

  /// No description provided for @diaryWeatherWind.
  ///
  /// In zh, this message translates to:
  /// **'风'**
  String get diaryWeatherWind;

  /// No description provided for @diaryWeatherFog.
  ///
  /// In zh, this message translates to:
  /// **'雾'**
  String get diaryWeatherFog;

  /// No description provided for @diaryWeatherThunder.
  ///
  /// In zh, this message translates to:
  /// **'雷'**
  String get diaryWeatherThunder;

  /// No description provided for @countdownTitle.
  ///
  /// In zh, this message translates to:
  /// **'倒数日'**
  String get countdownTitle;

  /// No description provided for @countdownEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无倒数日记录'**
  String get countdownEmpty;

  /// No description provided for @countdownNearestEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无即将到期的事件'**
  String get countdownNearestEmpty;

  /// No description provided for @countdownNearestPrefix.
  ///
  /// In zh, this message translates to:
  /// **'下一项：'**
  String get countdownNearestPrefix;

  /// No description provided for @countdownNearestDaysPrefix.
  ///
  /// In zh, this message translates to:
  /// **'还有 '**
  String get countdownNearestDaysPrefix;

  /// No description provided for @countdownSummaryTotal.
  ///
  /// In zh, this message translates to:
  /// **'总数'**
  String get countdownSummaryTotal;

  /// No description provided for @countdownSummaryWithin7Days.
  ///
  /// In zh, this message translates to:
  /// **'7 天内'**
  String get countdownSummaryWithin7Days;

  /// No description provided for @countdownListTitle.
  ///
  /// In zh, this message translates to:
  /// **'全部倒数日'**
  String get countdownListTitle;

  /// No description provided for @countdownListSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'按优先级和剩余天数排序'**
  String get countdownListSubtitle;

  /// No description provided for @countdownCategoryDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get countdownCategoryDefault;

  /// No description provided for @countdownEditorEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑倒数日'**
  String get countdownEditorEditTitle;

  /// No description provided for @countdownEditorSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'分类、到期日和提醒会同步到日历'**
  String get countdownEditorSubtitle;

  /// No description provided for @countdownFieldTitle.
  ///
  /// In zh, this message translates to:
  /// **'事件名称'**
  String get countdownFieldTitle;

  /// No description provided for @countdownFieldCategory.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get countdownFieldCategory;

  /// No description provided for @countdownFieldTargetDate.
  ///
  /// In zh, this message translates to:
  /// **'目标日期'**
  String get countdownFieldTargetDate;

  /// No description provided for @countdownFieldDueReminder.
  ///
  /// In zh, this message translates to:
  /// **'到期提醒'**
  String get countdownFieldDueReminder;

  /// No description provided for @countdownFieldRemindDays.
  ///
  /// In zh, this message translates to:
  /// **'提前天数'**
  String get countdownFieldRemindDays;

  /// No description provided for @countdownFieldRemindTime.
  ///
  /// In zh, this message translates to:
  /// **'提醒时间'**
  String get countdownFieldRemindTime;

  /// No description provided for @countdownReminderClosed.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get countdownReminderClosed;

  /// No description provided for @countdownReminderBeforePrefix.
  ///
  /// In zh, this message translates to:
  /// **'提前 '**
  String get countdownReminderBeforePrefix;

  /// No description provided for @countdownReminderBeforeSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 天'**
  String get countdownReminderBeforeSuffix;

  /// No description provided for @countdownValidationTitleRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先填写倒数日名称'**
  String get countdownValidationTitleRequired;

  /// No description provided for @countdownSaved.
  ///
  /// In zh, this message translates to:
  /// **'倒数日已保存'**
  String get countdownSaved;

  /// No description provided for @countdownSaveFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'倒数日保存失败：'**
  String get countdownSaveFailedPrefix;

  /// No description provided for @countdownReminderRegisterFailed.
  ///
  /// In zh, this message translates to:
  /// **'倒数日提醒注册失败'**
  String get countdownReminderRegisterFailed;

  /// No description provided for @countdownReminderNotRegistered.
  ///
  /// In zh, this message translates to:
  /// **'倒数日已保存，但提醒未注册。请检查通知权限和提醒时间。'**
  String get countdownReminderNotRegistered;

  /// No description provided for @countdownReminderNotRegisteredPrefix.
  ///
  /// In zh, this message translates to:
  /// **'倒数日已保存，但提醒未注册：'**
  String get countdownReminderNotRegisteredPrefix;

  /// No description provided for @countdownReminderPopupFallbackFailed.
  ///
  /// In zh, this message translates to:
  /// **'倒数日提醒注册失败：弹出框兜底通知不可用'**
  String get countdownReminderPopupFallbackFailed;

  /// No description provided for @countdownReminderPopupPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'倒数日已保存，但弹出框提醒未注册：系统通知权限未开启。'**
  String get countdownReminderPopupPermissionDenied;

  /// No description provided for @countdownReminderPopupNotRegisteredPrefix.
  ///
  /// In zh, this message translates to:
  /// **'倒数日已保存，但弹出框提醒未注册：'**
  String get countdownReminderPopupNotRegisteredPrefix;

  /// No description provided for @countdownReminderPopupWarning.
  ///
  /// In zh, this message translates to:
  /// **'倒数日已保存。弹出框只在应用运行时显示，后台或锁屏将使用系统通知兜底。'**
  String get countdownReminderPopupWarning;

  /// No description provided for @countdownReminderAlarmPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'倒数日已保存，但闹钟提醒未注册：系统通知权限未开启，请开启后重新保存提醒。'**
  String get countdownReminderAlarmPermissionDenied;

  /// No description provided for @countdownReminderAlarmChannelMissing.
  ///
  /// In zh, this message translates to:
  /// **'强提醒渠道未就绪'**
  String get countdownReminderAlarmChannelMissing;

  /// No description provided for @countdownReminderExactAlarmMissing.
  ///
  /// In zh, this message translates to:
  /// **'精准闹钟权限未开启，提醒可能延后'**
  String get countdownReminderExactAlarmMissing;

  /// No description provided for @countdownReminderFullscreenMissing.
  ///
  /// In zh, this message translates to:
  /// **'全屏提醒权限未开启，锁屏弹窗可能不可用'**
  String get countdownReminderFullscreenMissing;

  /// No description provided for @countdownReminderSavedWithWarningsPrefix.
  ///
  /// In zh, this message translates to:
  /// **'倒数日已保存，'**
  String get countdownReminderSavedWithWarningsPrefix;

  /// No description provided for @countdownReminderEmailWarning.
  ///
  /// In zh, this message translates to:
  /// **'倒数日已保存，邮件提醒会在联网后由服务端发送。'**
  String get countdownReminderEmailWarning;

  /// No description provided for @countdownReminderExceptionPrefix.
  ///
  /// In zh, this message translates to:
  /// **'倒数日已保存，但提醒未注册：'**
  String get countdownReminderExceptionPrefix;

  /// No description provided for @countdownReminderTimePast.
  ///
  /// In zh, this message translates to:
  /// **'倒数日已保存，但提醒时间已过去，请重新选择提醒时间。'**
  String get countdownReminderTimePast;

  /// No description provided for @countdownStatusPinned.
  ///
  /// In zh, this message translates to:
  /// **'置顶'**
  String get countdownStatusPinned;

  /// No description provided for @countdownStatusExpired.
  ///
  /// In zh, this message translates to:
  /// **'已过期'**
  String get countdownStatusExpired;

  /// No description provided for @countdownStatusSoon.
  ///
  /// In zh, this message translates to:
  /// **'临近'**
  String get countdownStatusSoon;

  /// No description provided for @countdownStatusRunning.
  ///
  /// In zh, this message translates to:
  /// **'倒数中'**
  String get countdownStatusRunning;

  /// No description provided for @countdownTargetPrefix.
  ///
  /// In zh, this message translates to:
  /// **'目标: '**
  String get countdownTargetPrefix;

  /// No description provided for @countdownDaysElapsed.
  ///
  /// In zh, this message translates to:
  /// **'已过'**
  String get countdownDaysElapsed;

  /// No description provided for @countdownDaysRemaining.
  ///
  /// In zh, this message translates to:
  /// **'还有'**
  String get countdownDaysRemaining;

  /// No description provided for @anniversaryTitle.
  ///
  /// In zh, this message translates to:
  /// **'纪念日'**
  String get anniversaryTitle;

  /// No description provided for @anniversaryBirthday.
  ///
  /// In zh, this message translates to:
  /// **'生日'**
  String get anniversaryBirthday;

  /// No description provided for @anniversaryCountdownShort.
  ///
  /// In zh, this message translates to:
  /// **'倒数'**
  String get anniversaryCountdownShort;

  /// No description provided for @anniversaryCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get anniversaryCustom;

  /// No description provided for @anniversaryTabAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get anniversaryTabAll;

  /// No description provided for @anniversaryUpcoming30Days.
  ///
  /// In zh, this message translates to:
  /// **'最近 30 天'**
  String get anniversaryUpcoming30Days;

  /// No description provided for @anniversaryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有任何纪念'**
  String get anniversaryEmpty;

  /// No description provided for @anniversaryUpcomingEmpty.
  ///
  /// In zh, this message translates to:
  /// **'未来 30 天内没有安排'**
  String get anniversaryUpcomingEmpty;

  /// No description provided for @anniversarySummaryWithin30Days.
  ///
  /// In zh, this message translates to:
  /// **'30 天内'**
  String get anniversarySummaryWithin30Days;

  /// No description provided for @anniversaryListSuffix.
  ///
  /// In zh, this message translates to:
  /// **'列表'**
  String get anniversaryListSuffix;

  /// No description provided for @anniversaryListSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'长按置顶，左滑删除，点击进入编辑'**
  String get anniversaryListSubtitle;

  /// No description provided for @anniversaryDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认删除？'**
  String get anniversaryDeleteTitle;

  /// No description provided for @anniversaryDeleteContentSuffix.
  ///
  /// In zh, this message translates to:
  /// **'将被移除'**
  String get anniversaryDeleteContentSuffix;

  /// No description provided for @anniversaryOccurrencePrefix.
  ///
  /// In zh, this message translates to:
  /// **'第'**
  String get anniversaryOccurrencePrefix;

  /// No description provided for @anniversaryOccurrenceSuffix.
  ///
  /// In zh, this message translates to:
  /// **'次'**
  String get anniversaryOccurrenceSuffix;

  /// No description provided for @anniversaryYearsElapsedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'已 '**
  String get anniversaryYearsElapsedPrefix;

  /// No description provided for @anniversaryYearsElapsedSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 年'**
  String get anniversaryYearsElapsedSuffix;

  /// No description provided for @anniversaryNextPrefix.
  ///
  /// In zh, this message translates to:
  /// **'下一次: '**
  String get anniversaryNextPrefix;

  /// No description provided for @anniversaryTodayShort.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get anniversaryTodayShort;

  /// No description provided for @anniversaryEditorAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'新增纪念'**
  String get anniversaryEditorAddTitle;

  /// No description provided for @anniversaryEditorEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑纪念'**
  String get anniversaryEditorEditTitle;

  /// No description provided for @anniversaryFieldTitle.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get anniversaryFieldTitle;

  /// No description provided for @anniversaryFieldTitleHint.
  ///
  /// In zh, this message translates to:
  /// **'如：妈妈生日 / 结婚纪念日'**
  String get anniversaryFieldTitleHint;

  /// No description provided for @anniversaryFieldDescription.
  ///
  /// In zh, this message translates to:
  /// **'备注 (可选)'**
  String get anniversaryFieldDescription;

  /// No description provided for @anniversaryFieldType.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get anniversaryFieldType;

  /// No description provided for @anniversaryFieldDateType.
  ///
  /// In zh, this message translates to:
  /// **'日期类型'**
  String get anniversaryFieldDateType;

  /// No description provided for @anniversaryFieldDatePickerTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择日期'**
  String get anniversaryFieldDatePickerTitle;

  /// No description provided for @anniversaryFieldDatePickerSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'公历和农历使用独立组件'**
  String get anniversaryFieldDatePickerSubtitle;

  /// No description provided for @anniversaryFieldColor.
  ///
  /// In zh, this message translates to:
  /// **'颜色标识'**
  String get anniversaryFieldColor;

  /// No description provided for @anniversaryValidationTitleRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先填写标题'**
  String get anniversaryValidationTitleRequired;

  /// No description provided for @anniversarySaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get anniversarySaved;

  /// No description provided for @anniversarySaveFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：'**
  String get anniversarySaveFailedPrefix;

  /// No description provided for @anniversaryReminderRegisterFailed.
  ///
  /// In zh, this message translates to:
  /// **'纪念日提醒注册失败'**
  String get anniversaryReminderRegisterFailed;

  /// No description provided for @anniversaryReminderNotRegistered.
  ///
  /// In zh, this message translates to:
  /// **'纪念日提醒未注册，请检查通知权限和提醒时间。'**
  String get anniversaryReminderNotRegistered;

  /// No description provided for @anniversaryReminderPopupFallbackFailed.
  ///
  /// In zh, this message translates to:
  /// **'纪念日提醒注册失败：弹出框兜底通知不可用'**
  String get anniversaryReminderPopupFallbackFailed;

  /// No description provided for @anniversaryReminderPopupPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'弹出框提醒未注册：系统通知权限未开启。'**
  String get anniversaryReminderPopupPermissionDenied;

  /// No description provided for @anniversaryReminderPopupNotRegisteredPrefix.
  ///
  /// In zh, this message translates to:
  /// **'弹出框提醒未注册：'**
  String get anniversaryReminderPopupNotRegisteredPrefix;

  /// No description provided for @anniversaryReminderPopupWarning.
  ///
  /// In zh, this message translates to:
  /// **'弹出框只在应用运行时显示，后台或锁屏将使用系统通知兜底。'**
  String get anniversaryReminderPopupWarning;

  /// No description provided for @anniversaryReminderAlarmPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'闹钟提醒未注册：系统通知权限未开启，请开启后重新保存提醒。'**
  String get anniversaryReminderAlarmPermissionDenied;

  /// No description provided for @anniversaryReminderAlarmChannelMissing.
  ///
  /// In zh, this message translates to:
  /// **'强提醒渠道未就绪'**
  String get anniversaryReminderAlarmChannelMissing;

  /// No description provided for @anniversaryReminderExactAlarmMissing.
  ///
  /// In zh, this message translates to:
  /// **'精准闹钟权限未开启，提醒可能延后'**
  String get anniversaryReminderExactAlarmMissing;

  /// No description provided for @anniversaryReminderFullscreenMissing.
  ///
  /// In zh, this message translates to:
  /// **'全屏提醒权限未开启，锁屏弹窗可能不可用'**
  String get anniversaryReminderFullscreenMissing;

  /// No description provided for @anniversaryReminderEmailWarning.
  ///
  /// In zh, this message translates to:
  /// **'邮件提醒会在联网后由服务端发送。'**
  String get anniversaryReminderEmailWarning;

  /// No description provided for @anniversaryReminderExceptionPrefix.
  ///
  /// In zh, this message translates to:
  /// **'提醒未注册：'**
  String get anniversaryReminderExceptionPrefix;

  /// No description provided for @anniversaryReminderSavedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'已保存，'**
  String get anniversaryReminderSavedPrefix;

  /// No description provided for @anniversaryReminderTimePast.
  ///
  /// In zh, this message translates to:
  /// **'已保存，但提醒时间已过去，请重新选择提醒时间。'**
  String get anniversaryReminderTimePast;

  /// No description provided for @anniversaryLunarYearSuffix.
  ///
  /// In zh, this message translates to:
  /// **'年'**
  String get anniversaryLunarYearSuffix;

  /// No description provided for @courseWeekPrefix.
  ///
  /// In zh, this message translates to:
  /// **'第 '**
  String get courseWeekPrefix;

  /// No description provided for @courseWeekSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 周'**
  String get courseWeekSuffix;

  /// No description provided for @courseWeekCountSuffix.
  ///
  /// In zh, this message translates to:
  /// **'周'**
  String get courseWeekCountSuffix;

  /// No description provided for @courseWeekCurrentTooltip.
  ///
  /// In zh, this message translates to:
  /// **'回到本周'**
  String get courseWeekCurrentTooltip;

  /// No description provided for @courseEmptyMessage.
  ///
  /// In zh, this message translates to:
  /// **'添加课表后就能看到你的一周啦'**
  String get courseEmptyMessage;

  /// No description provided for @courseAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加课程'**
  String get courseAdd;

  /// No description provided for @courseWeekPickerTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择周次'**
  String get courseWeekPickerTitle;

  /// No description provided for @courseWeekPickerSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切换当前查看的课表周'**
  String get courseWeekPickerSubtitle;

  /// No description provided for @courseWeeksAll.
  ///
  /// In zh, this message translates to:
  /// **'全周'**
  String get courseWeeksAll;

  /// No description provided for @courseWeeksOdd.
  ///
  /// In zh, this message translates to:
  /// **'单周'**
  String get courseWeeksOdd;

  /// No description provided for @courseWeeksEven.
  ///
  /// In zh, this message translates to:
  /// **'双周'**
  String get courseWeeksEven;

  /// No description provided for @courseWeeksSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get courseWeeksSelectAll;

  /// No description provided for @courseSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'课表设置'**
  String get courseSettingsTitle;

  /// No description provided for @courseSettingsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'调整学期起点和显示密度'**
  String get courseSettingsSubtitle;

  /// No description provided for @courseSettingsPreviewPrefix.
  ///
  /// In zh, this message translates to:
  /// **'节次预览：'**
  String get courseSettingsPreviewPrefix;

  /// No description provided for @courseEditorAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'新增课程'**
  String get courseEditorAddTitle;

  /// No description provided for @courseEditorEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑课程'**
  String get courseEditorEditTitle;

  /// No description provided for @courseEditorSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'按周次、节次和颜色整理课表'**
  String get courseEditorSubtitle;

  /// No description provided for @courseFieldTermStart.
  ///
  /// In zh, this message translates to:
  /// **'开学日期 (第 1 周的周一)'**
  String get courseFieldTermStart;

  /// No description provided for @courseFieldTermStartPicker.
  ///
  /// In zh, this message translates to:
  /// **'开学日期'**
  String get courseFieldTermStartPicker;

  /// No description provided for @courseFieldTotalWeeks.
  ///
  /// In zh, this message translates to:
  /// **'总周数'**
  String get courseFieldTotalWeeks;

  /// No description provided for @courseFieldSessionsPerDay.
  ///
  /// In zh, this message translates to:
  /// **'每天节数'**
  String get courseFieldSessionsPerDay;

  /// No description provided for @courseFieldSessionMinutes.
  ///
  /// In zh, this message translates to:
  /// **'每节分钟数'**
  String get courseFieldSessionMinutes;

  /// No description provided for @courseFieldFirstSessionTime.
  ///
  /// In zh, this message translates to:
  /// **'第一节开始时间'**
  String get courseFieldFirstSessionTime;

  /// No description provided for @courseFieldFirstSessionTimeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'课程表将按这个时间推算后续节次'**
  String get courseFieldFirstSessionTimeSubtitle;

  /// No description provided for @courseFieldBreakMinutes.
  ///
  /// In zh, this message translates to:
  /// **'课间分钟数'**
  String get courseFieldBreakMinutes;

  /// No description provided for @courseFieldName.
  ///
  /// In zh, this message translates to:
  /// **'课程名'**
  String get courseFieldName;

  /// No description provided for @courseFieldTeacher.
  ///
  /// In zh, this message translates to:
  /// **'教师'**
  String get courseFieldTeacher;

  /// No description provided for @courseFieldLocation.
  ///
  /// In zh, this message translates to:
  /// **'教室'**
  String get courseFieldLocation;

  /// No description provided for @courseFieldWeekday.
  ///
  /// In zh, this message translates to:
  /// **'星期'**
  String get courseFieldWeekday;

  /// No description provided for @courseFieldStartSection.
  ///
  /// In zh, this message translates to:
  /// **'第几节开始'**
  String get courseFieldStartSection;

  /// No description provided for @courseFieldSectionCount.
  ///
  /// In zh, this message translates to:
  /// **'连上几节'**
  String get courseFieldSectionCount;

  /// No description provided for @courseFieldClassWeeks.
  ///
  /// In zh, this message translates to:
  /// **'上课周'**
  String get courseFieldClassWeeks;

  /// No description provided for @courseFieldColor.
  ///
  /// In zh, this message translates to:
  /// **'颜色'**
  String get courseFieldColor;

  /// No description provided for @todoEmpty.
  ///
  /// In zh, this message translates to:
  /// **'今天没有待办，去添加一个吧'**
  String get todoEmpty;

  /// No description provided for @todoAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加待办'**
  String get todoAdd;

  /// No description provided for @todoMatrix.
  ///
  /// In zh, this message translates to:
  /// **'四象限'**
  String get todoMatrix;

  /// No description provided for @todoList.
  ///
  /// In zh, this message translates to:
  /// **'列表'**
  String get todoList;

  /// No description provided for @todoPostpone.
  ///
  /// In zh, this message translates to:
  /// **'顺延'**
  String get todoPostpone;

  /// No description provided for @todoPriorityNone.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get todoPriorityNone;

  /// No description provided for @todoPriorityLow.
  ///
  /// In zh, this message translates to:
  /// **'低'**
  String get todoPriorityLow;

  /// No description provided for @todoPriorityMedium.
  ///
  /// In zh, this message translates to:
  /// **'中'**
  String get todoPriorityMedium;

  /// No description provided for @todoPriorityHigh.
  ///
  /// In zh, this message translates to:
  /// **'高'**
  String get todoPriorityHigh;

  /// No description provided for @todoPriorityUrgent.
  ///
  /// In zh, this message translates to:
  /// **'紧急'**
  String get todoPriorityUrgent;

  /// No description provided for @todoQuickAddReminderPreflightFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'提醒权限检查失败，待办未创建：'**
  String get todoQuickAddReminderPreflightFailedPrefix;

  /// No description provided for @todoQuickAddReminderSyncFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'待办已创建，但提醒未能确认注册：'**
  String get todoQuickAddReminderSyncFailedPrefix;

  /// No description provided for @calendarMonth.
  ///
  /// In zh, this message translates to:
  /// **'月'**
  String get calendarMonth;

  /// No description provided for @calendarWeek.
  ///
  /// In zh, this message translates to:
  /// **'周'**
  String get calendarWeek;

  /// No description provided for @calendarDay.
  ///
  /// In zh, this message translates to:
  /// **'日'**
  String get calendarDay;

  /// No description provided for @calendarEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这一天没有事项'**
  String get calendarEmpty;

  /// No description provided for @focusStart.
  ///
  /// In zh, this message translates to:
  /// **'开始专注'**
  String get focusStart;

  /// No description provided for @focusPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get focusPause;

  /// No description provided for @focusResume.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get focusResume;

  /// No description provided for @focusReset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get focusReset;

  /// No description provided for @reminderHealth.
  ///
  /// In zh, this message translates to:
  /// **'通知健康'**
  String get reminderHealth;

  /// No description provided for @reminderTestNotification.
  ///
  /// In zh, this message translates to:
  /// **'发送测试通知'**
  String get reminderTestNotification;

  /// No description provided for @reminderSnooze5min.
  ///
  /// In zh, this message translates to:
  /// **'5 分钟后'**
  String get reminderSnooze5min;

  /// No description provided for @reminderSnooze10min.
  ///
  /// In zh, this message translates to:
  /// **'10 分钟后'**
  String get reminderSnooze10min;

  /// No description provided for @reminderSnooze30min.
  ///
  /// In zh, this message translates to:
  /// **'30 分钟后'**
  String get reminderSnooze30min;

  /// No description provided for @reminderKindPush.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get reminderKindPush;

  /// No description provided for @reminderKindPopup.
  ///
  /// In zh, this message translates to:
  /// **'弹出框'**
  String get reminderKindPopup;

  /// No description provided for @reminderKindAlarm.
  ///
  /// In zh, this message translates to:
  /// **'闹钟'**
  String get reminderKindAlarm;

  /// No description provided for @reminderKindOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get reminderKindOff;

  /// No description provided for @reminderTodoTitlePrefix.
  ///
  /// In zh, this message translates to:
  /// **'提醒：'**
  String get reminderTodoTitlePrefix;

  /// No description provided for @widgetNoScheduleToday.
  ///
  /// In zh, this message translates to:
  /// **'今日没有日程'**
  String get widgetNoScheduleToday;

  /// No description provided for @widgetTodayPrefix.
  ///
  /// In zh, this message translates to:
  /// **'今日：'**
  String get widgetTodayPrefix;

  /// No description provided for @widgetFocusCountingUp.
  ///
  /// In zh, this message translates to:
  /// **'正计时专注中'**
  String get widgetFocusCountingUp;

  /// No description provided for @widgetFocusCountdown.
  ///
  /// In zh, this message translates to:
  /// **'专注倒计时'**
  String get widgetFocusCountdown;

  /// No description provided for @widgetShortBreakCountdown.
  ///
  /// In zh, this message translates to:
  /// **'短休息倒计时'**
  String get widgetShortBreakCountdown;

  /// No description provided for @widgetLongBreakCountdown.
  ///
  /// In zh, this message translates to:
  /// **'长休息倒计时'**
  String get widgetLongBreakCountdown;

  /// No description provided for @widgetFocusNotStarted.
  ///
  /// In zh, this message translates to:
  /// **'今日还未专注'**
  String get widgetFocusNotStarted;

  /// No description provided for @widgetFocusTodayPrefix.
  ///
  /// In zh, this message translates to:
  /// **'今日专注 '**
  String get widgetFocusTodayPrefix;

  /// No description provided for @widgetFocusTodaySuffix.
  ///
  /// In zh, this message translates to:
  /// **' 次'**
  String get widgetFocusTodaySuffix;

  /// No description provided for @widgetHabitAllDone.
  ///
  /// In zh, this message translates to:
  /// **'习惯已全部完成'**
  String get widgetHabitAllDone;

  /// No description provided for @widgetHabitProgressPrefix.
  ///
  /// In zh, this message translates to:
  /// **'习惯完成 '**
  String get widgetHabitProgressPrefix;

  /// No description provided for @widgetHabitProgressSuffix.
  ///
  /// In zh, this message translates to:
  /// **'%'**
  String get widgetHabitProgressSuffix;

  /// No description provided for @widgetStreakPrefix.
  ///
  /// In zh, this message translates to:
  /// **'当前连续 '**
  String get widgetStreakPrefix;

  /// No description provided for @widgetStreakSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 天'**
  String get widgetStreakSuffix;

  /// No description provided for @widgetNextFocusSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 分钟专注'**
  String get widgetNextFocusSuffix;

  /// No description provided for @widgetHabitQuickCheckHint.
  ///
  /// In zh, this message translates to:
  /// **'点击进入习惯打卡'**
  String get widgetHabitQuickCheckHint;

  /// No description provided for @widgetHabitCheckinPrefix.
  ///
  /// In zh, this message translates to:
  /// **'打卡：'**
  String get widgetHabitCheckinPrefix;

  /// No description provided for @widgetDaysRemainingPrefix.
  ///
  /// In zh, this message translates to:
  /// **'还有 '**
  String get widgetDaysRemainingPrefix;

  /// No description provided for @widgetDaysRemainingSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 天'**
  String get widgetDaysRemainingSuffix;

  /// No description provided for @widgetCourseSectionPrefix.
  ///
  /// In zh, this message translates to:
  /// **''**
  String get widgetCourseSectionPrefix;

  /// No description provided for @widgetCourseSectionSuffix.
  ///
  /// In zh, this message translates to:
  /// **'节 '**
  String get widgetCourseSectionSuffix;

  /// No description provided for @widgetTodoTop3Empty.
  ///
  /// In zh, this message translates to:
  /// **'今天没有未完成待办'**
  String get widgetTodoTop3Empty;

  /// No description provided for @widgetGoalEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无进行中目标'**
  String get widgetGoalEmpty;

  /// No description provided for @widgetGoalHint.
  ///
  /// In zh, this message translates to:
  /// **'本周目标保持推进'**
  String get widgetGoalHint;

  /// No description provided for @widgetAnniversaryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无近期纪念日'**
  String get widgetAnniversaryEmpty;

  /// No description provided for @widgetCourseEmpty.
  ///
  /// In zh, this message translates to:
  /// **'今日暂无课程'**
  String get widgetCourseEmpty;

  /// No description provided for @widgetNoteEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无随手记'**
  String get widgetNoteEmpty;

  /// No description provided for @widgetDiaryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无日记'**
  String get widgetDiaryEmpty;

  /// No description provided for @widgetScheduleOpenCalendar.
  ///
  /// In zh, this message translates to:
  /// **'打开日历查看完整安排'**
  String get widgetScheduleOpenCalendar;

  /// No description provided for @widgetScheduleTimezoneHint.
  ///
  /// In zh, this message translates to:
  /// **'提醒会跟随系统时区'**
  String get widgetScheduleTimezoneHint;

  /// No description provided for @widgetCalendarMonthSummary.
  ///
  /// In zh, this message translates to:
  /// **'本月日期 · 今日已标记'**
  String get widgetCalendarMonthSummary;

  /// No description provided for @widgetHabitPending.
  ///
  /// In zh, this message translates to:
  /// **'今日习惯待打卡'**
  String get widgetHabitPending;

  /// No description provided for @widgetStreakRecordPrefix.
  ///
  /// In zh, this message translates to:
  /// **'连续记录 '**
  String get widgetStreakRecordPrefix;

  /// No description provided for @timeAuditTitle.
  ///
  /// In zh, this message translates to:
  /// **'时间足迹'**
  String get timeAuditTitle;

  /// No description provided for @timeAuditAddManual.
  ///
  /// In zh, this message translates to:
  /// **'补记'**
  String get timeAuditAddManual;

  /// No description provided for @timeAuditWeeklyOverview.
  ///
  /// In zh, this message translates to:
  /// **'本周时间分布'**
  String get timeAuditWeeklyOverview;

  /// No description provided for @timeAuditCopyReport.
  ///
  /// In zh, this message translates to:
  /// **'复制报告'**
  String get timeAuditCopyReport;

  /// No description provided for @timeAuditReportCopied.
  ///
  /// In zh, this message translates to:
  /// **'时间足迹报告已复制'**
  String get timeAuditReportCopied;

  /// No description provided for @timeAuditRangeToday.
  ///
  /// In zh, this message translates to:
  /// **'今日'**
  String get timeAuditRangeToday;

  /// No description provided for @timeAuditRangeWeek.
  ///
  /// In zh, this message translates to:
  /// **'本周'**
  String get timeAuditRangeWeek;

  /// No description provided for @timeAuditRangeMonth.
  ///
  /// In zh, this message translates to:
  /// **'本月'**
  String get timeAuditRangeMonth;

  /// No description provided for @timeAuditRangeAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get timeAuditRangeAll;

  /// No description provided for @timeAuditSegmentToday.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get timeAuditSegmentToday;

  /// No description provided for @timeAuditViewTimeline.
  ///
  /// In zh, this message translates to:
  /// **'时间线'**
  String get timeAuditViewTimeline;

  /// No description provided for @timeAuditViewCategory.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get timeAuditViewCategory;

  /// No description provided for @timeAuditViewCalendar.
  ///
  /// In zh, this message translates to:
  /// **'日历'**
  String get timeAuditViewCalendar;

  /// No description provided for @timeAuditViewTrend.
  ///
  /// In zh, this message translates to:
  /// **'趋势'**
  String get timeAuditViewTrend;

  /// No description provided for @timeAuditEmptySuffix.
  ///
  /// In zh, this message translates to:
  /// **'暂无时间记录'**
  String get timeAuditEmptySuffix;

  /// No description provided for @timeAuditCategoryView.
  ///
  /// In zh, this message translates to:
  /// **'分类视图'**
  String get timeAuditCategoryView;

  /// No description provided for @timeAuditSourceBreakdown.
  ///
  /// In zh, this message translates to:
  /// **'来源分布'**
  String get timeAuditSourceBreakdown;

  /// No description provided for @timeAuditCalendarView.
  ///
  /// In zh, this message translates to:
  /// **'日历视图'**
  String get timeAuditCalendarView;

  /// No description provided for @timeAuditTrendView.
  ///
  /// In zh, this message translates to:
  /// **'趋势视图'**
  String get timeAuditTrendView;

  /// No description provided for @timeAuditInvestmentSuffix.
  ///
  /// In zh, this message translates to:
  /// **'投入'**
  String get timeAuditInvestmentSuffix;

  /// No description provided for @timeAuditEntryCount.
  ///
  /// In zh, this message translates to:
  /// **'记录数'**
  String get timeAuditEntryCount;

  /// No description provided for @timeAuditEntryCountSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 条'**
  String get timeAuditEntryCountSuffix;

  /// No description provided for @timeAuditDefaultTitle.
  ///
  /// In zh, this message translates to:
  /// **'时间记录'**
  String get timeAuditDefaultTitle;

  /// No description provided for @timeAuditSheetAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'补记时间'**
  String get timeAuditSheetAddTitle;

  /// No description provided for @timeAuditSheetEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑时间'**
  String get timeAuditSheetEditTitle;

  /// No description provided for @timeAuditFieldTitle.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get timeAuditFieldTitle;

  /// No description provided for @timeAuditFieldCategory.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get timeAuditFieldCategory;

  /// No description provided for @timeAuditFieldStart.
  ///
  /// In zh, this message translates to:
  /// **'开始'**
  String get timeAuditFieldStart;

  /// No description provided for @timeAuditFieldEnd.
  ///
  /// In zh, this message translates to:
  /// **'结束'**
  String get timeAuditFieldEnd;

  /// No description provided for @timeAuditFieldMinutes.
  ///
  /// In zh, this message translates to:
  /// **'分钟数'**
  String get timeAuditFieldMinutes;

  /// No description provided for @timeAuditFieldNote.
  ///
  /// In zh, this message translates to:
  /// **'备注'**
  String get timeAuditFieldNote;

  /// No description provided for @timeAuditPickerStartDate.
  ///
  /// In zh, this message translates to:
  /// **'开始日期'**
  String get timeAuditPickerStartDate;

  /// No description provided for @timeAuditPickerStartTime.
  ///
  /// In zh, this message translates to:
  /// **'开始时间'**
  String get timeAuditPickerStartTime;

  /// No description provided for @timeAuditPickerEndDate.
  ///
  /// In zh, this message translates to:
  /// **'结束日期'**
  String get timeAuditPickerEndDate;

  /// No description provided for @timeAuditPickerEndTime.
  ///
  /// In zh, this message translates to:
  /// **'结束时间'**
  String get timeAuditPickerEndTime;

  /// No description provided for @timeAuditReportTitle.
  ///
  /// In zh, this message translates to:
  /// **'时间足迹报告'**
  String get timeAuditReportTitle;

  /// No description provided for @timeAuditReportRange.
  ///
  /// In zh, this message translates to:
  /// **'范围'**
  String get timeAuditReportRange;

  /// No description provided for @timeAuditReportTotal.
  ///
  /// In zh, this message translates to:
  /// **'总投入'**
  String get timeAuditReportTotal;

  /// No description provided for @timeAuditReportCategory.
  ///
  /// In zh, this message translates to:
  /// **'分类分布'**
  String get timeAuditReportCategory;

  /// No description provided for @timeAuditReportDetails.
  ///
  /// In zh, this message translates to:
  /// **'明细'**
  String get timeAuditReportDetails;

  /// No description provided for @shareTitle.
  ///
  /// In zh, this message translates to:
  /// **'共享空间'**
  String get shareTitle;

  /// No description provided for @shareCreateInvite.
  ///
  /// In zh, this message translates to:
  /// **'生成邀请码'**
  String get shareCreateInvite;

  /// No description provided for @shareAcceptInvite.
  ///
  /// In zh, this message translates to:
  /// **'加入空间'**
  String get shareAcceptInvite;

  /// No description provided for @shareRoleOwner.
  ///
  /// In zh, this message translates to:
  /// **'拥有者'**
  String get shareRoleOwner;

  /// No description provided for @shareRoleEditor.
  ///
  /// In zh, this message translates to:
  /// **'可编辑'**
  String get shareRoleEditor;

  /// No description provided for @shareRoleViewer.
  ///
  /// In zh, this message translates to:
  /// **'只读'**
  String get shareRoleViewer;

  /// No description provided for @unitMinute.
  ///
  /// In zh, this message translates to:
  /// **'分钟'**
  String get unitMinute;

  /// No description provided for @unitMin.
  ///
  /// In zh, this message translates to:
  /// **'分'**
  String get unitMin;

  /// No description provided for @unitHour.
  ///
  /// In zh, this message translates to:
  /// **'小时'**
  String get unitHour;

  /// No description provided for @unitDay.
  ///
  /// In zh, this message translates to:
  /// **'天'**
  String get unitDay;

  /// No description provided for @repeatEveryDay.
  ///
  /// In zh, this message translates to:
  /// **'每天'**
  String get repeatEveryDay;

  /// No description provided for @repeatWeekdays.
  ///
  /// In zh, this message translates to:
  /// **'工作日'**
  String get repeatWeekdays;

  /// No description provided for @habitActiveWeekdays.
  ///
  /// In zh, this message translates to:
  /// **'生效星期'**
  String get habitActiveWeekdays;

  /// No description provided for @habitActiveWeekdaysHint.
  ///
  /// In zh, this message translates to:
  /// **'勾选习惯在哪些天生效，未勾选的日子不计入统计'**
  String get habitActiveWeekdaysHint;

  /// No description provided for @habitActiveWeekdaysReminderHint.
  ///
  /// In zh, this message translates to:
  /// **'每周提醒日与生效星期相互独立，保存后互不改动'**
  String get habitActiveWeekdaysReminderHint;

  /// No description provided for @syncStatusTitle.
  ///
  /// In zh, this message translates to:
  /// **'云同步'**
  String get syncStatusTitle;

  /// No description provided for @syncStateNever.
  ///
  /// In zh, this message translates to:
  /// **'尚未同步'**
  String get syncStateNever;

  /// No description provided for @syncStateNeverHint.
  ///
  /// In zh, this message translates to:
  /// **'登录并开启云同步后，数据会自动备份到云端'**
  String get syncStateNeverHint;

  /// No description provided for @syncStateSyncing.
  ///
  /// In zh, this message translates to:
  /// **'正在同步…'**
  String get syncStateSyncing;

  /// No description provided for @syncStateSynced.
  ///
  /// In zh, this message translates to:
  /// **'已同步'**
  String get syncStateSynced;

  /// No description provided for @syncStateFailed.
  ///
  /// In zh, this message translates to:
  /// **'同步失败'**
  String get syncStateFailed;

  /// No description provided for @syncLastSyncPrefix.
  ///
  /// In zh, this message translates to:
  /// **'上次同步 '**
  String get syncLastSyncPrefix;

  /// No description provided for @syncPendingBadge.
  ///
  /// In zh, this message translates to:
  /// **'待同步'**
  String get syncPendingBadge;

  /// No description provided for @syncStateAutoRetryHint.
  ///
  /// In zh, this message translates to:
  /// **'将在后台自动重试'**
  String get syncStateAutoRetryHint;

  /// No description provided for @greetingSeparator.
  ///
  /// In zh, this message translates to:
  /// **'，'**
  String get greetingSeparator;

  /// No description provided for @todayNoDue.
  ///
  /// In zh, this message translates to:
  /// **'无截止'**
  String get todayNoDue;

  /// No description provided for @todayNoDueDate.
  ///
  /// In zh, this message translates to:
  /// **'无截止日期'**
  String get todayNoDueDate;

  /// No description provided for @todayTodosEmpty.
  ///
  /// In zh, this message translates to:
  /// **'今天暂无待办，点击查看或添加任务'**
  String get todayTodosEmpty;

  /// No description provided for @todoStatusOverdue.
  ///
  /// In zh, this message translates to:
  /// **'逾期'**
  String get todoStatusOverdue;

  /// No description provided for @todoStatusDueSoon.
  ///
  /// In zh, this message translates to:
  /// **'临期'**
  String get todoStatusDueSoon;

  /// No description provided for @todoStatusNormal.
  ///
  /// In zh, this message translates to:
  /// **'正常'**
  String get todoStatusNormal;

  /// No description provided for @habitWeeklyTodayPrefix.
  ///
  /// In zh, this message translates to:
  /// **'今日 '**
  String get habitWeeklyTodayPrefix;

  /// No description provided for @habitWeeklyTodaySuffix.
  ///
  /// In zh, this message translates to:
  /// **' 达标'**
  String get habitWeeklyTodaySuffix;

  /// No description provided for @habitWeeklyProgress.
  ///
  /// In zh, this message translates to:
  /// **'进度'**
  String get habitWeeklyProgress;

  /// No description provided for @habitWeekday1.
  ///
  /// In zh, this message translates to:
  /// **'一'**
  String get habitWeekday1;

  /// No description provided for @habitWeekday2.
  ///
  /// In zh, this message translates to:
  /// **'二'**
  String get habitWeekday2;

  /// No description provided for @habitWeekday3.
  ///
  /// In zh, this message translates to:
  /// **'三'**
  String get habitWeekday3;

  /// No description provided for @habitWeekday4.
  ///
  /// In zh, this message translates to:
  /// **'四'**
  String get habitWeekday4;

  /// No description provided for @habitWeekday5.
  ///
  /// In zh, this message translates to:
  /// **'五'**
  String get habitWeekday5;

  /// No description provided for @habitWeekday6.
  ///
  /// In zh, this message translates to:
  /// **'六'**
  String get habitWeekday6;

  /// No description provided for @habitWeekday7.
  ///
  /// In zh, this message translates to:
  /// **'日'**
  String get habitWeekday7;

  /// No description provided for @habitGroupUngrouped.
  ///
  /// In zh, this message translates to:
  /// **'未分组'**
  String get habitGroupUngrouped;

  /// No description provided for @habitGroupTodaySuffix.
  ///
  /// In zh, this message translates to:
  /// **' 今日达标'**
  String get habitGroupTodaySuffix;

  /// No description provided for @habitGroupMoreHabitsPrefix.
  ///
  /// In zh, this message translates to:
  /// **'还有 '**
  String get habitGroupMoreHabitsPrefix;

  /// No description provided for @habitGroupMoreHabitsSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 个习惯，请进入今日打卡或习惯详情查看'**
  String get habitGroupMoreHabitsSuffix;

  /// No description provided for @habitBestShort.
  ///
  /// In zh, this message translates to:
  /// **'最佳'**
  String get habitBestShort;

  /// No description provided for @todoKanbanNoPriority.
  ///
  /// In zh, this message translates to:
  /// **'无优先级'**
  String get todoKanbanNoPriority;

  /// No description provided for @todoKanbanNoDue.
  ///
  /// In zh, this message translates to:
  /// **'无截止日'**
  String get todoKanbanNoDue;

  /// No description provided for @todoKanbanOverdue.
  ///
  /// In zh, this message translates to:
  /// **'已逾期'**
  String get todoKanbanOverdue;

  /// No description provided for @todoKanbanToday.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get todoKanbanToday;

  /// No description provided for @todoKanbanWithin7Days.
  ///
  /// In zh, this message translates to:
  /// **'7 天内'**
  String get todoKanbanWithin7Days;

  /// No description provided for @todoKanbanLater.
  ///
  /// In zh, this message translates to:
  /// **'更晚'**
  String get todoKanbanLater;

  /// No description provided for @todoKanbanNoTag.
  ///
  /// In zh, this message translates to:
  /// **'无标签'**
  String get todoKanbanNoTag;

  /// No description provided for @todoKanbanDefaultList.
  ///
  /// In zh, this message translates to:
  /// **'默认清单'**
  String get todoKanbanDefaultList;

  /// No description provided for @authLogout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get authLogout;

  /// No description provided for @mineBadgeAdmin.
  ///
  /// In zh, this message translates to:
  /// **'管理员'**
  String get mineBadgeAdmin;

  /// No description provided for @mineViewProfileSemantics.
  ///
  /// In zh, this message translates to:
  /// **'查看个人资料'**
  String get mineViewProfileSemantics;

  /// No description provided for @mineAvatarView.
  ///
  /// In zh, this message translates to:
  /// **'查看头像'**
  String get mineAvatarView;

  /// No description provided for @mineAvatarEdit.
  ///
  /// In zh, this message translates to:
  /// **'修改头像'**
  String get mineAvatarEdit;

  /// No description provided for @mineAvatarTitle.
  ///
  /// In zh, this message translates to:
  /// **'头像'**
  String get mineAvatarTitle;

  /// No description provided for @mineMeFallback.
  ///
  /// In zh, this message translates to:
  /// **'我'**
  String get mineMeFallback;

  /// No description provided for @mineStatsTodos.
  ///
  /// In zh, this message translates to:
  /// **'待办完成'**
  String get mineStatsTodos;

  /// No description provided for @mineStatsStreak.
  ///
  /// In zh, this message translates to:
  /// **'连续打卡'**
  String get mineStatsStreak;

  /// No description provided for @mineStatsFocus.
  ///
  /// In zh, this message translates to:
  /// **'本周专注'**
  String get mineStatsFocus;

  /// No description provided for @mineStatsProductivity.
  ///
  /// In zh, this message translates to:
  /// **'效率评分'**
  String get mineStatsProductivity;

  /// No description provided for @mineGroupActionPlan.
  ///
  /// In zh, this message translates to:
  /// **'行动计划'**
  String get mineGroupActionPlan;

  /// No description provided for @mineGroupReview.
  ///
  /// In zh, this message translates to:
  /// **'记录回顾'**
  String get mineGroupReview;

  /// No description provided for @mineGroupSchedule.
  ///
  /// In zh, this message translates to:
  /// **'日程日期'**
  String get mineGroupSchedule;

  /// No description provided for @mineGroupPersonal.
  ///
  /// In zh, this message translates to:
  /// **'个性安全'**
  String get mineGroupPersonal;

  /// No description provided for @mineGroupData.
  ///
  /// In zh, this message translates to:
  /// **'数据协作'**
  String get mineGroupData;

  /// No description provided for @mineGroupNotifications.
  ///
  /// In zh, this message translates to:
  /// **'通知支持'**
  String get mineGroupNotifications;

  /// No description provided for @mineTilePomodoro.
  ///
  /// In zh, this message translates to:
  /// **'番茄专注'**
  String get mineTilePomodoro;

  /// No description provided for @mineTileMoreApps.
  ///
  /// In zh, this message translates to:
  /// **'更多应用'**
  String get mineTileMoreApps;

  /// No description provided for @mineTileMoreAppsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看隐藏功能'**
  String get mineTileMoreAppsSubtitle;

  /// No description provided for @mineTileStatistics.
  ///
  /// In zh, this message translates to:
  /// **'统计报表'**
  String get mineTileStatistics;

  /// No description provided for @mineTileAchievements.
  ///
  /// In zh, this message translates to:
  /// **'成就墙'**
  String get mineTileAchievements;

  /// No description provided for @mineTileCourses.
  ///
  /// In zh, this message translates to:
  /// **'课程表'**
  String get mineTileCourses;

  /// No description provided for @mineTileIntegrations.
  ///
  /// In zh, this message translates to:
  /// **'扩展功能'**
  String get mineTileIntegrations;

  /// No description provided for @mineTileBackup.
  ///
  /// In zh, this message translates to:
  /// **'备份'**
  String get mineTileBackup;

  /// No description provided for @mineTileRestore.
  ///
  /// In zh, this message translates to:
  /// **'恢复数据'**
  String get mineTileRestore;

  /// No description provided for @mineTileNotificationHistory.
  ///
  /// In zh, this message translates to:
  /// **'通知记录'**
  String get mineTileNotificationHistory;

  /// No description provided for @mineTileNotificationHistoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无通知记录'**
  String get mineTileNotificationHistoryEmpty;

  /// No description provided for @mineTileNotificationHistoryCountSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 条'**
  String get mineTileNotificationHistoryCountSuffix;

  /// No description provided for @mineTileNotificationSettings.
  ///
  /// In zh, this message translates to:
  /// **'通知设置'**
  String get mineTileNotificationSettings;

  /// No description provided for @mineTileNotificationSettingsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'提醒时间、权限、铃声、已注册提醒和记录保留'**
  String get mineTileNotificationSettingsSubtitle;

  /// No description provided for @mineTileAdmin.
  ///
  /// In zh, this message translates to:
  /// **'管理员后台'**
  String get mineTileAdmin;

  /// No description provided for @mineTileFeedback.
  ///
  /// In zh, this message translates to:
  /// **'许愿与反馈'**
  String get mineTileFeedback;

  /// No description provided for @mineTileFeedbackSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'提交建议并分页查看处理记录'**
  String get mineTileFeedbackSubtitle;

  /// No description provided for @mineTileCheckUpdates.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get mineTileCheckUpdates;

  /// No description provided for @mineLogoutConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'退出登录？'**
  String get mineLogoutConfirmTitle;

  /// No description provided for @mineLogoutConfirmContent.
  ///
  /// In zh, this message translates to:
  /// **'退出后会清空本机账号数据（时光币、主题、习惯、待办等本地缓存），重新登录后再从当前账号同步。'**
  String get mineLogoutConfirmContent;

  /// No description provided for @mineLogoutDone.
  ///
  /// In zh, this message translates to:
  /// **'已退出登录，本机账号数据已清理'**
  String get mineLogoutDone;

  /// No description provided for @mineLogoutCleanupFailed.
  ///
  /// In zh, this message translates to:
  /// **'已退出登录，本机数据清理失败，将在下次登录前重试'**
  String get mineLogoutCleanupFailed;

  /// No description provided for @profileAvatarFileEmpty.
  ///
  /// In zh, this message translates to:
  /// **'头像文件为空'**
  String get profileAvatarFileEmpty;

  /// No description provided for @profileAvatarSaveFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'头像保存失败：'**
  String get profileAvatarSaveFailedPrefix;

  /// No description provided for @profileAvatarPreview.
  ///
  /// In zh, this message translates to:
  /// **'查看头像'**
  String get profileAvatarPreview;

  /// No description provided for @profileAvatarEdit.
  ///
  /// In zh, this message translates to:
  /// **'修改头像'**
  String get profileAvatarEdit;

  /// No description provided for @profileAvatarTitle.
  ///
  /// In zh, this message translates to:
  /// **'头像'**
  String get profileAvatarTitle;

  /// No description provided for @mineUpdateBadge.
  ///
  /// In zh, this message translates to:
  /// **'有更新'**
  String get mineUpdateBadge;

  /// No description provided for @mineUpdateBadgeVersionPrefix.
  ///
  /// In zh, this message translates to:
  /// **'新版 '**
  String get mineUpdateBadgeVersionPrefix;

  /// No description provided for @mineUpdateRequiredTitle.
  ///
  /// In zh, this message translates to:
  /// **'必须更新'**
  String get mineUpdateRequiredTitle;

  /// No description provided for @mineUpdateCheckTitle.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get mineUpdateCheckTitle;

  /// No description provided for @mineUpdateCurrentVersionPrefix.
  ///
  /// In zh, this message translates to:
  /// **'当前版本: '**
  String get mineUpdateCurrentVersionPrefix;

  /// No description provided for @mineUpdateRemoteVersionPrefix.
  ///
  /// In zh, this message translates to:
  /// **'远端版本: '**
  String get mineUpdateRemoteVersionPrefix;

  /// No description provided for @mineUpdateMinSupportedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'最低支持版本: '**
  String get mineUpdateMinSupportedPrefix;

  /// No description provided for @mineUpdateForceBannerTitle.
  ///
  /// In zh, this message translates to:
  /// **'此版本需要强制更新'**
  String get mineUpdateForceBannerTitle;

  /// No description provided for @mineUpdateForceBannerMessage.
  ///
  /// In zh, this message translates to:
  /// **'当前版本低于管理员设置的最低支持版本，或管理员已要求所有用户更新后继续使用。'**
  String get mineUpdateForceBannerMessage;

  /// No description provided for @mineUpdateAvailable.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本'**
  String get mineUpdateAvailable;

  /// No description provided for @mineUpdateUpToDate.
  ///
  /// In zh, this message translates to:
  /// **'已是最新版本'**
  String get mineUpdateUpToDate;

  /// No description provided for @mineUpdateNotes.
  ///
  /// In zh, this message translates to:
  /// **'更新内容'**
  String get mineUpdateNotes;

  /// No description provided for @mineUpdatePackageMissingTitle.
  ///
  /// In zh, this message translates to:
  /// **'未配置安装包地址'**
  String get mineUpdatePackageMissingTitle;

  /// No description provided for @mineUpdatePackageMissingMessage.
  ///
  /// In zh, this message translates to:
  /// **'更新策略已生效，但当前没有可下载的安装包地址。请管理员在发布通道补充安装包。'**
  String get mineUpdatePackageMissingMessage;

  /// No description provided for @mineUpdatePackageBrokenPrefix.
  ///
  /// In zh, this message translates to:
  /// **'更新策略已生效，但安装包不可用：'**
  String get mineUpdatePackageBrokenPrefix;

  /// No description provided for @mineUpdatePackageBrokenSuffix.
  ///
  /// In zh, this message translates to:
  /// **'。请管理员在发布通道补充安装包。'**
  String get mineUpdatePackageBrokenSuffix;

  /// No description provided for @mineUpdateDownloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载更新包'**
  String get mineUpdateDownloading;

  /// No description provided for @mineUpdateDownloadingProgressPrefix.
  ///
  /// In zh, this message translates to:
  /// **'正在下载 '**
  String get mineUpdateDownloadingProgressPrefix;

  /// No description provided for @mineUpdateInstalling.
  ///
  /// In zh, this message translates to:
  /// **'正在打开安装器'**
  String get mineUpdateInstalling;

  /// No description provided for @mineUpdateInstallDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'安装已下载包'**
  String get mineUpdateInstallDownloaded;

  /// No description provided for @mineUpdateDownloadAndInstall.
  ///
  /// In zh, this message translates to:
  /// **'下载并安装'**
  String get mineUpdateDownloadAndInstall;

  /// No description provided for @mineUpdatePackageLabel.
  ///
  /// In zh, this message translates to:
  /// **'安装包'**
  String get mineUpdatePackageLabel;

  /// No description provided for @mineUpdateChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查更新...'**
  String get mineUpdateChecking;

  /// No description provided for @mineUpdateWebAvailable.
  ///
  /// In zh, this message translates to:
  /// **'发现网页新版本，刷新网页即可载入最新代码。'**
  String get mineUpdateWebAvailable;

  /// No description provided for @mineUpdateWebRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新网页'**
  String get mineUpdateWebRefresh;

  /// No description provided for @mineAboutTitle.
  ///
  /// In zh, this message translates to:
  /// **'多仪'**
  String get mineAboutTitle;

  /// No description provided for @mineAboutVersionPrefix.
  ///
  /// In zh, this message translates to:
  /// **'版本: '**
  String get mineAboutVersionPrefix;

  /// No description provided for @mineAboutTagline.
  ///
  /// In zh, this message translates to:
  /// **'Flutter 跨平台效率工具'**
  String get mineAboutTagline;

  /// No description provided for @mineAboutOk.
  ///
  /// In zh, this message translates to:
  /// **'好的'**
  String get mineAboutOk;

  /// No description provided for @mineAiAssistant.
  ///
  /// In zh, this message translates to:
  /// **'AI 助手'**
  String get mineAiAssistant;

  /// No description provided for @mineAiAssistantDisabledMessage.
  ///
  /// In zh, this message translates to:
  /// **'管理员后台配置 AI 后，这里会显示周回顾、任务拆解和建议生成入口。'**
  String get mineAiAssistantDisabledMessage;

  /// No description provided for @mineAiReviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 每周回顾'**
  String get mineAiReviewTitle;

  /// No description provided for @mineAiCollapse.
  ///
  /// In zh, this message translates to:
  /// **'收起回顾'**
  String get mineAiCollapse;

  /// No description provided for @mineAiExpand.
  ///
  /// In zh, this message translates to:
  /// **'展开回顾'**
  String get mineAiExpand;

  /// No description provided for @mineAiGenerate.
  ///
  /// In zh, this message translates to:
  /// **'生成'**
  String get mineAiGenerate;

  /// No description provided for @mineAiGeneratedToday.
  ///
  /// In zh, this message translates to:
  /// **'今日已生成'**
  String get mineAiGeneratedToday;

  /// No description provided for @mineAiExpandFull.
  ///
  /// In zh, this message translates to:
  /// **'展开完整回顾'**
  String get mineAiExpandFull;

  /// No description provided for @mineAiRangeThisWeek.
  ///
  /// In zh, this message translates to:
  /// **'本周'**
  String get mineAiRangeThisWeek;

  /// No description provided for @mineAiRangeLastWeek.
  ///
  /// In zh, this message translates to:
  /// **'上周'**
  String get mineAiRangeLastWeek;

  /// No description provided for @mineAiHintPrefix.
  ///
  /// In zh, this message translates to:
  /// **'点击\"生成\"让 AI 根据'**
  String get mineAiHintPrefix;

  /// No description provided for @mineAiHintSuffix.
  ///
  /// In zh, this message translates to:
  /// **'完成数据写一段总结与建议，当天会保留结果'**
  String get mineAiHintSuffix;

  /// No description provided for @mineAiSummaryHeaderSuffix.
  ///
  /// In zh, this message translates to:
  /// **'数据：完成 '**
  String get mineAiSummaryHeaderSuffix;

  /// No description provided for @mineAiSummaryTodosSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 项待办，专注 '**
  String get mineAiSummaryTodosSuffix;

  /// No description provided for @mineAiSummaryFocusSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 分钟，习惯连续打卡 '**
  String get mineAiSummaryFocusSuffix;

  /// No description provided for @mineAiSummaryStreakSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 天。'**
  String get mineAiSummaryStreakSuffix;

  /// No description provided for @appLockPinHintEnter.
  ///
  /// In zh, this message translates to:
  /// **'输入 PIN 解锁'**
  String get appLockPinHintEnter;

  /// 覆盖导入/WebDAV 覆盖恢复确认弹窗：警告用户备份中不存在的本机数据将被删除
  ///
  /// In zh, this message translates to:
  /// **'备份中不存在的本机数据将被删除。'**
  String get backupOverwriteWillDeleteMissing;

  /// No description provided for @calendarContentDatePickerSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'手动跳转到指定日期'**
  String get calendarContentDatePickerSubtitle;

  /// No description provided for @calendarContentDatePickerTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择日期'**
  String get calendarContentDatePickerTitle;

  /// No description provided for @calendarContentTimePickerStartTime.
  ///
  /// In zh, this message translates to:
  /// **'开始时间'**
  String get calendarContentTimePickerStartTime;

  /// No description provided for @calendarPickerStartDate.
  ///
  /// In zh, this message translates to:
  /// **'开始日期'**
  String get calendarPickerStartDate;

  /// No description provided for @calendarPickerEndDate.
  ///
  /// In zh, this message translates to:
  /// **'结束日期'**
  String get calendarPickerEndDate;

  /// No description provided for @calendarPickerStartTime.
  ///
  /// In zh, this message translates to:
  /// **'开始时间'**
  String get calendarPickerStartTime;

  /// No description provided for @calendarPickerEndTime.
  ///
  /// In zh, this message translates to:
  /// **'结束时间'**
  String get calendarPickerEndTime;

  /// No description provided for @calendarPickerRescheduleDate.
  ///
  /// In zh, this message translates to:
  /// **'调整日期'**
  String get calendarPickerRescheduleDate;

  /// No description provided for @calendarPickerAdjustStartTime.
  ///
  /// In zh, this message translates to:
  /// **'调整开始时间'**
  String get calendarPickerAdjustStartTime;

  /// No description provided for @calendarPickerAdjustStartTimeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'保留当前日期和时长，自动更新结束时间'**
  String get calendarPickerAdjustStartTimeSubtitle;

  /// No description provided for @calendarPickerAdjustDueTime.
  ///
  /// In zh, this message translates to:
  /// **'调整时间'**
  String get calendarPickerAdjustDueTime;

  /// No description provided for @calendarPickerAdjustDueTimeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'保留当前日期，只调整当天截止时间'**
  String get calendarPickerAdjustDueTimeSubtitle;

  /// No description provided for @pickerActionToday.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get pickerActionToday;

  /// No description provided for @pickerEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无可选项'**
  String get pickerEmpty;

  /// No description provided for @pickerNotSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get pickerNotSet;

  /// No description provided for @pickerDateIgnoreYear.
  ///
  /// In zh, this message translates to:
  /// **'忽略年份'**
  String get pickerDateIgnoreYear;

  /// No description provided for @pickerDateIgnoreYearDesc.
  ///
  /// In zh, this message translates to:
  /// **'适合生日、纪念日每年重复'**
  String get pickerDateIgnoreYearDesc;

  /// No description provided for @pickerDateNextMonth.
  ///
  /// In zh, this message translates to:
  /// **'下个月'**
  String get pickerDateNextMonth;

  /// No description provided for @pickerDatePrevMonth.
  ///
  /// In zh, this message translates to:
  /// **'上个月'**
  String get pickerDatePrevMonth;

  /// No description provided for @pickerDateTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择日期'**
  String get pickerDateTitle;

  /// No description provided for @pickerLunarDay.
  ///
  /// In zh, this message translates to:
  /// **'日'**
  String get pickerLunarDay;

  /// No description provided for @pickerLunarLeapMonth.
  ///
  /// In zh, this message translates to:
  /// **'闰月'**
  String get pickerLunarLeapMonth;

  /// No description provided for @pickerLunarMonth.
  ///
  /// In zh, this message translates to:
  /// **'月'**
  String get pickerLunarMonth;

  /// No description provided for @pickerTimeEarlier30m.
  ///
  /// In zh, this message translates to:
  /// **'提前 30 分'**
  String get pickerTimeEarlier30m;

  /// No description provided for @pickerTimeLater30m.
  ///
  /// In zh, this message translates to:
  /// **'延后 30 分'**
  String get pickerTimeLater30m;

  /// No description provided for @pickerTimePresetEvening.
  ///
  /// In zh, this message translates to:
  /// **'晚上 20:00'**
  String get pickerTimePresetEvening;

  /// No description provided for @pickerTimePresetMorning.
  ///
  /// In zh, this message translates to:
  /// **'上午 09:00'**
  String get pickerTimePresetMorning;

  /// No description provided for @pickerTimePresetNextSlot.
  ///
  /// In zh, this message translates to:
  /// **'下一提醒点'**
  String get pickerTimePresetNextSlot;

  /// No description provided for @pickerTimePresetNoon.
  ///
  /// In zh, this message translates to:
  /// **'中午 12:00'**
  String get pickerTimePresetNoon;

  /// No description provided for @pickerTimePresetNow.
  ///
  /// In zh, this message translates to:
  /// **'现在'**
  String get pickerTimePresetNow;

  /// No description provided for @pickerTimeTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择时间'**
  String get pickerTimeTitle;

  /// No description provided for @pickerWeekdayFri.
  ///
  /// In zh, this message translates to:
  /// **'五'**
  String get pickerWeekdayFri;

  /// No description provided for @pickerWeekdayMon.
  ///
  /// In zh, this message translates to:
  /// **'一'**
  String get pickerWeekdayMon;

  /// No description provided for @pickerWeekdaySat.
  ///
  /// In zh, this message translates to:
  /// **'六'**
  String get pickerWeekdaySat;

  /// No description provided for @pickerWeekdaySun.
  ///
  /// In zh, this message translates to:
  /// **'日'**
  String get pickerWeekdaySun;

  /// No description provided for @pickerWeekdayThu.
  ///
  /// In zh, this message translates to:
  /// **'四'**
  String get pickerWeekdayThu;

  /// No description provided for @pickerWeekdayTue.
  ///
  /// In zh, this message translates to:
  /// **'二'**
  String get pickerWeekdayTue;

  /// No description provided for @pickerWeekdayWed.
  ///
  /// In zh, this message translates to:
  /// **'三'**
  String get pickerWeekdayWed;

  /// No description provided for @widgetHabitNoneToday.
  ///
  /// In zh, this message translates to:
  /// **'今天没有安排习惯'**
  String get widgetHabitNoneToday;

  /// No description provided for @widgetHabitView.
  ///
  /// In zh, this message translates to:
  /// **'查看习惯'**
  String get widgetHabitView;

  /// No description provided for @aiScheduleScreenTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 创建日程'**
  String get aiScheduleScreenTitle;

  /// No description provided for @aiScheduleAiDisabledTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 未启用'**
  String get aiScheduleAiDisabledTitle;

  /// No description provided for @aiScheduleAiDisabledMessage.
  ///
  /// In zh, this message translates to:
  /// **'将使用本地时间解析生成草稿，仍可确认创建日程或待办。'**
  String get aiScheduleAiDisabledMessage;

  /// No description provided for @aiScheduleInputTitle.
  ///
  /// In zh, this message translates to:
  /// **'输入安排'**
  String get aiScheduleInputTitle;

  /// No description provided for @aiScheduleInputSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'例如：明天下午 3 点和产品开会，提前提醒我'**
  String get aiScheduleInputSubtitle;

  /// No description provided for @aiScheduleInputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入自然语言安排、待办或提醒'**
  String get aiScheduleInputHint;

  /// No description provided for @aiScheduleEmptyInput.
  ///
  /// In zh, this message translates to:
  /// **'请输入要创建的日程或待办内容'**
  String get aiScheduleEmptyInput;

  /// No description provided for @aiScheduleRecognize.
  ///
  /// In zh, this message translates to:
  /// **'识别并生成确认信息'**
  String get aiScheduleRecognize;

  /// No description provided for @aiScheduleRecognizing.
  ///
  /// In zh, this message translates to:
  /// **'识别中'**
  String get aiScheduleRecognizing;

  /// No description provided for @aiScheduleErrorTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 创建失败'**
  String get aiScheduleErrorTitle;

  /// No description provided for @aiScheduleDraftTitle.
  ///
  /// In zh, this message translates to:
  /// **'已生成确认草稿'**
  String get aiScheduleDraftTitle;

  /// No description provided for @aiScheduleDraftAiMessage.
  ///
  /// In zh, this message translates to:
  /// **'请核对类型、标题、时间和提醒设置。'**
  String get aiScheduleDraftAiMessage;

  /// No description provided for @aiScheduleDraftFallbackMessage.
  ///
  /// In zh, this message translates to:
  /// **'当前不是完整 AI 识别结果，请确认本地兜底草稿无误后再写入。'**
  String get aiScheduleDraftFallbackMessage;

  /// No description provided for @aiScheduleWarningAiIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'AI 识别结果不完整'**
  String get aiScheduleWarningAiIncomplete;

  /// No description provided for @aiScheduleWarningLocalFallback.
  ///
  /// In zh, this message translates to:
  /// **'AI 识别未完成'**
  String get aiScheduleWarningLocalFallback;

  /// No description provided for @aiScheduleWarningAppendix.
  ///
  /// In zh, this message translates to:
  /// **'请核对下方本地草稿后再确认创建。'**
  String get aiScheduleWarningAppendix;

  /// No description provided for @aiScheduleConfirmCardTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认创建内容'**
  String get aiScheduleConfirmCardTitle;

  /// No description provided for @aiScheduleTypeLabel.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get aiScheduleTypeLabel;

  /// No description provided for @aiScheduleTitleLabel.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get aiScheduleTitleLabel;

  /// No description provided for @aiScheduleStartLabel.
  ///
  /// In zh, this message translates to:
  /// **'开始'**
  String get aiScheduleStartLabel;

  /// No description provided for @aiScheduleEndLabel.
  ///
  /// In zh, this message translates to:
  /// **'结束'**
  String get aiScheduleEndLabel;

  /// No description provided for @aiScheduleReminderLabel.
  ///
  /// In zh, this message translates to:
  /// **'提醒'**
  String get aiScheduleReminderLabel;

  /// No description provided for @aiScheduleNotesLabel.
  ///
  /// In zh, this message translates to:
  /// **'备注'**
  String get aiScheduleNotesLabel;

  /// No description provided for @aiScheduleSubtasksLabel.
  ///
  /// In zh, this message translates to:
  /// **'子任务'**
  String get aiScheduleSubtasksLabel;

  /// No description provided for @aiScheduleCalendarType.
  ///
  /// In zh, this message translates to:
  /// **'日程'**
  String get aiScheduleCalendarType;

  /// No description provided for @aiScheduleTodoType.
  ///
  /// In zh, this message translates to:
  /// **'待办'**
  String get aiScheduleTodoType;

  /// No description provided for @aiScheduleReminderEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启系统推送提醒'**
  String get aiScheduleReminderEnabled;

  /// No description provided for @aiScheduleReminderDisabled.
  ///
  /// In zh, this message translates to:
  /// **'未设置提醒'**
  String get aiScheduleReminderDisabled;

  /// No description provided for @aiScheduleSaving.
  ///
  /// In zh, this message translates to:
  /// **'保存中'**
  String get aiScheduleSaving;

  /// No description provided for @aiScheduleCreate.
  ///
  /// In zh, this message translates to:
  /// **'确认创建'**
  String get aiScheduleCreate;

  /// No description provided for @aiScheduleDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get aiScheduleDone;

  /// No description provided for @aiScheduleViewDetails.
  ///
  /// In zh, this message translates to:
  /// **'查看详情'**
  String get aiScheduleViewDetails;

  /// No description provided for @aiScheduleCreatedEvent.
  ///
  /// In zh, this message translates to:
  /// **'日程已创建'**
  String get aiScheduleCreatedEvent;

  /// No description provided for @aiScheduleCreatedTask.
  ///
  /// In zh, this message translates to:
  /// **'待办已创建'**
  String get aiScheduleCreatedTask;

  /// No description provided for @aiScheduleCreatedEventWithReminderIssue.
  ///
  /// In zh, this message translates to:
  /// **'日程已创建，但提醒未注册'**
  String get aiScheduleCreatedEventWithReminderIssue;

  /// No description provided for @aiScheduleCreatedTaskWithReminderIssue.
  ///
  /// In zh, this message translates to:
  /// **'待办已创建，但提醒未注册'**
  String get aiScheduleCreatedTaskWithReminderIssue;

  /// Created item summary
  ///
  /// In zh, this message translates to:
  /// **'{typeLabel}：{title}'**
  String aiScheduleCreatedItemSummary(String typeLabel, String title);

  /// Start summary for calendar event
  ///
  /// In zh, this message translates to:
  /// **'开始时间：{value}'**
  String aiScheduleStartSummaryCalendar(String value);

  /// Start summary for todo task
  ///
  /// In zh, this message translates to:
  /// **'计划时间：{value}'**
  String aiScheduleStartSummaryTodo(String value);

  /// No description provided for @aiScheduleLocalSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存到本机'**
  String get aiScheduleLocalSaved;

  /// No description provided for @aiScheduleLocalSavedCalendar.
  ///
  /// In zh, this message translates to:
  /// **'日程已保存到本机'**
  String get aiScheduleLocalSavedCalendar;

  /// No description provided for @aiScheduleLocalSavedTodo.
  ///
  /// In zh, this message translates to:
  /// **'待办已保存到本机'**
  String get aiScheduleLocalSavedTodo;

  /// No description provided for @aiScheduleReminderRegistered.
  ///
  /// In zh, this message translates to:
  /// **'提醒已注册到系统通知'**
  String get aiScheduleReminderRegistered;

  /// No description provided for @aiScheduleTaskReminderSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'待办提醒已提交系统注册'**
  String get aiScheduleTaskReminderSubmitted;

  /// No description provided for @aiScheduleGenericReminderIssue.
  ///
  /// In zh, this message translates to:
  /// **'提醒未注册'**
  String get aiScheduleGenericReminderIssue;

  /// No description provided for @aiScheduleAccountChanged.
  ///
  /// In zh, this message translates to:
  /// **'账号已切换，请重新打开页面后再操作。'**
  String get aiScheduleAccountChanged;

  /// No description provided for @aiScheduleInputChanged.
  ///
  /// In zh, this message translates to:
  /// **'输入内容已变更，请重新识别后再创建。'**
  String get aiScheduleInputChanged;

  /// No description provided for @aiScheduleGenericSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败，请重试。'**
  String get aiScheduleGenericSaveFailed;

  /// No description provided for @aiScheduleAlarmPermissionRequired.
  ///
  /// In zh, this message translates to:
  /// **'AI 待办提醒注册失败：系统通知权限未开启，闹钟提醒未注册。请开启通知权限后重新保存提醒。'**
  String get aiScheduleAlarmPermissionRequired;

  /// No description provided for @aiScheduleEventReminderIssueTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 日程提醒注册失败'**
  String get aiScheduleEventReminderIssueTitle;

  /// No description provided for @aiScheduleTaskReminderIssueTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 待办提醒注册失败'**
  String get aiScheduleTaskReminderIssueTitle;

  /// No description provided for @aiScheduleCalendarSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 创建'**
  String get aiScheduleCalendarSubtitle;

  /// No description provided for @aiScheduleCalendarSubtitleAllDay.
  ///
  /// In zh, this message translates to:
  /// **'AI 创建 · 全天'**
  String get aiScheduleCalendarSubtitleAllDay;

  /// No description provided for @aiScheduleCalendarReminderTitle.
  ///
  /// In zh, this message translates to:
  /// **'日程提醒'**
  String get aiScheduleCalendarReminderTitle;

  /// No description provided for @aiScheduleSourceAi.
  ///
  /// In zh, this message translates to:
  /// **'AI 已识别输入内容，请确认无误后创建'**
  String get aiScheduleSourceAi;

  /// No description provided for @aiScheduleSourceAiWithLocalFallback.
  ///
  /// In zh, this message translates to:
  /// **'AI 返回不完整，已用本地解析补全'**
  String get aiScheduleSourceAiWithLocalFallback;

  /// No description provided for @aiScheduleSourceLocalParser.
  ///
  /// In zh, this message translates to:
  /// **'当前使用本地解析结果，请确认时间和类型'**
  String get aiScheduleSourceLocalParser;

  /// No description provided for @aiScheduleWarningReminderNotice.
  ///
  /// In zh, this message translates to:
  /// **'提醒提示'**
  String get aiScheduleWarningReminderNotice;

  /// No description provided for @aiScheduleWarningNotice.
  ///
  /// In zh, this message translates to:
  /// **'提示'**
  String get aiScheduleWarningNotice;

  /// No description provided for @aiScheduleWarningUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'AI 服务暂不可用，已准备本地兜底草稿。'**
  String get aiScheduleWarningUnavailable;

  /// No description provided for @aiScheduleWarningNoUsableDraft.
  ///
  /// In zh, this message translates to:
  /// **'AI 未返回可用草稿，已准备本地兜底草稿。'**
  String get aiScheduleWarningNoUsableDraft;

  /// No description provided for @aiScheduleWarningInvalidResponse.
  ///
  /// In zh, this message translates to:
  /// **'AI 返回内容无法读取，已准备本地兜底草稿。'**
  String get aiScheduleWarningInvalidResponse;

  /// No description provided for @aiScheduleWarningMissingReminderTime.
  ///
  /// In zh, this message translates to:
  /// **'未识别到具体提醒时间，提醒已关闭。'**
  String get aiScheduleWarningMissingReminderTime;

  /// No description provided for @aiScheduleWarningReviewDraft.
  ///
  /// In zh, this message translates to:
  /// **'请核对草稿内容后再确认创建。'**
  String get aiScheduleWarningReviewDraft;

  /// No description provided for @aiScheduleWarningGenericFallback.
  ///
  /// In zh, this message translates to:
  /// **'已准备本地草稿供你核对。'**
  String get aiScheduleWarningGenericFallback;

  /// No description provided for @aiScheduleErrorNotEnabled.
  ///
  /// In zh, this message translates to:
  /// **'AI 功能未启用，请联系管理员。'**
  String get aiScheduleErrorNotEnabled;

  /// No description provided for @aiScheduleErrorQuotaExceeded.
  ///
  /// In zh, this message translates to:
  /// **'今日 AI 额度已用尽，请明日再试。'**
  String get aiScheduleErrorQuotaExceeded;

  /// No description provided for @aiScheduleErrorRateLimit.
  ///
  /// In zh, this message translates to:
  /// **'请求过于频繁，请稍候重试。'**
  String get aiScheduleErrorRateLimit;

  /// No description provided for @aiScheduleErrorTimeout.
  ///
  /// In zh, this message translates to:
  /// **'AI 服务响应超时，请稍后重试。'**
  String get aiScheduleErrorTimeout;

  /// No description provided for @aiScheduleErrorGeneric.
  ///
  /// In zh, this message translates to:
  /// **'创建草稿失败，请重试。'**
  String get aiScheduleErrorGeneric;

  /// No description provided for @widgetHostSupportIosTitle.
  ///
  /// In zh, this message translates to:
  /// **'从主屏幕添加小组件'**
  String get widgetHostSupportIosTitle;

  /// No description provided for @widgetHostSupportWebTitle.
  ///
  /// In zh, this message translates to:
  /// **'网页版小组件预览'**
  String get widgetHostSupportWebTitle;

  /// No description provided for @widgetHostSupportMobileTitle.
  ///
  /// In zh, this message translates to:
  /// **'手机端小组件预览'**
  String get widgetHostSupportMobileTitle;

  /// No description provided for @widgetHostSupportIosMessage.
  ///
  /// In zh, this message translates to:
  /// **'在主屏幕长按空白处，打开小组件图库，搜索“多仪”并添加。'**
  String get widgetHostSupportIosMessage;

  /// No description provided for @widgetHostSupportMobileMessage.
  ///
  /// In zh, this message translates to:
  /// **'这里可以查看小组件样式；添加到主屏幕需使用 Android 或 iOS 版多仪。'**
  String get widgetHostSupportMobileMessage;

  /// No description provided for @widgetHostAddIosAction.
  ///
  /// In zh, this message translates to:
  /// **'查看添加步骤'**
  String get widgetHostAddIosAction;

  /// No description provided for @widgetHostAddMobileAction.
  ///
  /// In zh, this message translates to:
  /// **'手机端使用方式'**
  String get widgetHostAddMobileAction;

  /// No description provided for @widgetHostHelpMobileTitle.
  ///
  /// In zh, this message translates to:
  /// **'在手机端使用小组件'**
  String get widgetHostHelpMobileTitle;

  /// No description provided for @widgetAddDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加到桌面'**
  String get widgetAddDialogTitle;

  /// No description provided for @widgetHostHelpIosMessage.
  ///
  /// In zh, this message translates to:
  /// **'长按主屏幕空白处，点击“编辑”或“+”，进入小组件图库。搜索“多仪”，选择尺寸后点击“添加小组件”。系统提供小、中、大尺寸；支持的 iPad 还可选择超大尺寸。实际尺寸以系统图库为准。\n\niPhone（iOS 16 及以上）或 iPad（iPadOS 17 及以上）：长按锁定屏幕，点“自定”，再点小组件区域并选择多仪。'**
  String get widgetHostHelpIosMessage;

  /// No description provided for @widgetHostHelpMobileMessage.
  ///
  /// In zh, this message translates to:
  /// **'本页展示小组件样式预览。要在手机主屏幕使用，请安装并打开 Android 或 iOS 版多仪。Android 可从 App 内添加，或长按主屏幕空白处选择小组件；iOS 请从主屏幕的小组件图库搜索“多仪”并添加。'**
  String get widgetHostHelpMobileMessage;

  /// No description provided for @widgetHostTipsIosMessage.
  ///
  /// In zh, this message translates to:
  /// **'实际尺寸在系统小组件图库中选择。小组件显示最近同步的内容；若内容较旧，打开多仪后刷新。'**
  String get widgetHostTipsIosMessage;

  /// No description provided for @widgetHostTipsPreviewMessage.
  ///
  /// In zh, this message translates to:
  /// **'这里的预览不等同于已添加的桌面小组件。实际添加与使用需在 Android 或 iOS 手机端完成。'**
  String get widgetHostTipsPreviewMessage;

  /// No description provided for @widgetTipsBannerMessage.
  ///
  /// In zh, this message translates to:
  /// **'紧凑版和详细版为固定尺寸；标准版在桌面支持时可长按调整大小。要更换尺寸版本，请移除后重新添加。添加时需在系统弹窗中确认；若未出现弹窗，请检查多仪的桌面小组件权限。'**
  String get widgetTipsBannerMessage;

  /// No description provided for @widgetHostStyleCompactDescription.
  ///
  /// In zh, this message translates to:
  /// **'紧凑样式，突出核心信息。'**
  String get widgetHostStyleCompactDescription;

  /// No description provided for @widgetHostStyleDetailedDescription.
  ///
  /// In zh, this message translates to:
  /// **'详细样式，展示更多内容。'**
  String get widgetHostStyleDetailedDescription;

  /// No description provided for @widgetHostStyleStandardDescription.
  ///
  /// In zh, this message translates to:
  /// **'标准样式，平衡信息与留白。'**
  String get widgetHostStyleStandardDescription;

  /// hostStyleDescription / ios 外层
  ///
  /// In zh, this message translates to:
  /// **'{description} 实际尺寸在系统图库中选择。'**
  String widgetHostStyleDescriptionIos(String description);

  /// styleSyncSuccess / —; hostStyleSyncSuccess / ios；android委托styleSyncSuccess
  ///
  /// In zh, this message translates to:
  /// **'小组件样式已设为{modeLabel}。'**
  String widgetStyleSyncSuccess(String modeLabel);

  /// hostStyleSyncSuccess / web/desktop
  ///
  /// In zh, this message translates to:
  /// **'预览样式已设为{modeLabel}。'**
  String widgetPreviewStyleSyncSuccess(String modeLabel);

  /// No description provided for @widgetRefreshTooltip.
  ///
  /// In zh, this message translates to:
  /// **'刷新小组件'**
  String get widgetRefreshTooltip;

  /// No description provided for @widgetPreviewHeaderTitle.
  ///
  /// In zh, this message translates to:
  /// **'桌面小组件预览'**
  String get widgetPreviewHeaderTitle;

  /// No description provided for @widgetStylePanelTitle.
  ///
  /// In zh, this message translates to:
  /// **'小组件样式'**
  String get widgetStylePanelTitle;

  /// No description provided for @widgetCategoryAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get widgetCategoryAll;

  /// No description provided for @widgetCategoryProductivity.
  ///
  /// In zh, this message translates to:
  /// **'效率'**
  String get widgetCategoryProductivity;

  /// No description provided for @widgetCategoryLife.
  ///
  /// In zh, this message translates to:
  /// **'生活'**
  String get widgetCategoryLife;

  /// No description provided for @widgetCatalogTodoTitle.
  ///
  /// In zh, this message translates to:
  /// **'今日待办'**
  String get widgetCatalogTodoTitle;

  /// No description provided for @widgetCatalogCalendarTitle.
  ///
  /// In zh, this message translates to:
  /// **'月历'**
  String get widgetCatalogCalendarTitle;

  /// No description provided for @widgetCatalogScheduleTitle.
  ///
  /// In zh, this message translates to:
  /// **'今日日程'**
  String get widgetCatalogScheduleTitle;

  /// No description provided for @widgetCatalogGoalTitle.
  ///
  /// In zh, this message translates to:
  /// **'目标'**
  String get widgetCatalogGoalTitle;

  /// No description provided for @widgetCatalogNoteTitle.
  ///
  /// In zh, this message translates to:
  /// **'随手记'**
  String get widgetCatalogNoteTitle;

  /// No description provided for @widgetCatalogAnniversaryTitle.
  ///
  /// In zh, this message translates to:
  /// **'纪念日'**
  String get widgetCatalogAnniversaryTitle;

  /// No description provided for @widgetCatalogTodoSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'桌面查看与完成待办，支持快速记一笔'**
  String get widgetCatalogTodoSubtitle;

  /// No description provided for @widgetCatalogFocusSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'展示今日专注次数、时长与下一轮计划'**
  String get widgetCatalogFocusSubtitle;

  /// No description provided for @widgetCatalogHabitSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看今日完成率、连续记录与快捷打卡'**
  String get widgetCatalogHabitSubtitle;

  /// No description provided for @widgetCatalogCalendarSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'月视图概览与今日标记'**
  String get widgetCatalogCalendarSubtitle;

  /// No description provided for @widgetCatalogScheduleSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看今日按时间排序的日程安排'**
  String get widgetCatalogScheduleSubtitle;

  /// No description provided for @widgetCatalogGoalSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'展示当前目标与推进进度'**
  String get widgetCatalogGoalSubtitle;

  /// No description provided for @widgetCatalogCourseSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'展示今日课程节次、教室与时间'**
  String get widgetCatalogCourseSubtitle;

  /// No description provided for @widgetCatalogNoteSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看最近更新的便签与随手记'**
  String get widgetCatalogNoteSubtitle;

  /// No description provided for @widgetCatalogAnniversarySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'倒数重要日子与累计天数'**
  String get widgetCatalogAnniversarySubtitle;

  /// No description provided for @widgetCatalogDiarySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'回顾最近记录的心情与日记摘要'**
  String get widgetCatalogDiarySubtitle;

  /// No description provided for @widgetDisplayModeCompactLabel.
  ///
  /// In zh, this message translates to:
  /// **'紧凑'**
  String get widgetDisplayModeCompactLabel;

  /// No description provided for @widgetDisplayModeDetailedLabel.
  ///
  /// In zh, this message translates to:
  /// **'详细'**
  String get widgetDisplayModeDetailedLabel;

  /// No description provided for @widgetDisplayModeStandardLabel.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get widgetDisplayModeStandardLabel;

  /// No description provided for @widgetDisplayModeCompactDescription.
  ///
  /// In zh, this message translates to:
  /// **'紧凑版，固定尺寸，突出核心信息'**
  String get widgetDisplayModeCompactDescription;

  /// No description provided for @widgetDisplayModeDetailedDescription.
  ///
  /// In zh, this message translates to:
  /// **'详细版，固定尺寸，内容随可用空间调整'**
  String get widgetDisplayModeDetailedDescription;

  /// No description provided for @widgetDisplayModeStandardDescription.
  ///
  /// In zh, this message translates to:
  /// **'标准版，内容随可用空间调整；桌面支持时可长按调整大小'**
  String get widgetDisplayModeStandardDescription;

  /// No description provided for @widgetStyleSyncFailed.
  ///
  /// In zh, this message translates to:
  /// **'桌面小组件样式同步失败，请重试'**
  String get widgetStyleSyncFailed;

  /// No description provided for @widgetCannotOpenSettings.
  ///
  /// In zh, this message translates to:
  /// **'无法打开应用设置，请手动进入系统设置检查多仪权限'**
  String get widgetCannotOpenSettings;

  /// No description provided for @widgetRefreshSuccess.
  ///
  /// In zh, this message translates to:
  /// **'小组件已刷新'**
  String get widgetRefreshSuccess;

  /// No description provided for @widgetRefreshFailed.
  ///
  /// In zh, this message translates to:
  /// **'刷新失败，请稍后重试'**
  String get widgetRefreshFailed;

  /// No description provided for @widgetPinSupportCheckingTitle.
  ///
  /// In zh, this message translates to:
  /// **'正在检查桌面小组件支持'**
  String get widgetPinSupportCheckingTitle;

  /// No description provided for @widgetPinSupportCheckingMessage.
  ///
  /// In zh, this message translates to:
  /// **'正在检测当前桌面是否支持直接添加小组件。'**
  String get widgetPinSupportCheckingMessage;

  /// No description provided for @widgetPinSupportSupportedTitle.
  ///
  /// In zh, this message translates to:
  /// **'当前桌面支持应用内添加'**
  String get widgetPinSupportSupportedTitle;

  /// No description provided for @widgetPinSupportSupportedMessage.
  ///
  /// In zh, this message translates to:
  /// **'可从 App 添加到桌面，请在系统弹窗中确认。'**
  String get widgetPinSupportSupportedMessage;

  /// No description provided for @widgetPinSupportUnsupportedPlatformTitle.
  ///
  /// In zh, this message translates to:
  /// **'当前平台不支持应用内添加'**
  String get widgetPinSupportUnsupportedPlatformTitle;

  /// No description provided for @widgetPinSupportUnsupportedLauncherTitle.
  ///
  /// In zh, this message translates to:
  /// **'当前桌面不支持应用内添加'**
  String get widgetPinSupportUnsupportedLauncherTitle;

  /// No description provided for @widgetPinSupportPermissionDeniedTitle.
  ///
  /// In zh, this message translates to:
  /// **'桌面添加权限未通过'**
  String get widgetPinSupportPermissionDeniedTitle;

  /// No description provided for @widgetPinSupportConfirmationBlockedTitle.
  ///
  /// In zh, this message translates to:
  /// **'桌面确认弹窗可能被拦截'**
  String get widgetPinSupportConfirmationBlockedTitle;

  /// No description provided for @widgetPinSupportInvalidKindTitle.
  ///
  /// In zh, this message translates to:
  /// **'当前小组件类型不可添加'**
  String get widgetPinSupportInvalidKindTitle;

  /// No description provided for @widgetPinSupportFallbackTitle.
  ///
  /// In zh, this message translates to:
  /// **'当前桌面可能不支持应用内添加'**
  String get widgetPinSupportFallbackTitle;

  /// No description provided for @widgetPinSupportUnsupportedPlatformMessage.
  ///
  /// In zh, this message translates to:
  /// **'请在 Android 手机上通过系统小组件列表添加多仪。'**
  String get widgetPinSupportUnsupportedPlatformMessage;

  /// No description provided for @widgetPinSupportUnsupportedLauncherMessage.
  ///
  /// In zh, this message translates to:
  /// **'当前桌面启动器未开放应用内添加，请从系统小组件列表选择添加。'**
  String get widgetPinSupportUnsupportedLauncherMessage;

  /// No description provided for @widgetPinSupportPermissionDeniedMessage.
  ///
  /// In zh, this message translates to:
  /// **'系统未允许多仪添加桌面小组件，请在系统设置中开启权限后重试。'**
  String get widgetPinSupportPermissionDeniedMessage;

  /// No description provided for @widgetPinSupportConfirmationBlockedMessage.
  ///
  /// In zh, this message translates to:
  /// **'桌面确认弹窗可能被拦截，请检查后台弹窗或悬浮窗权限后重试。'**
  String get widgetPinSupportConfirmationBlockedMessage;

  /// No description provided for @widgetPinSupportInvalidKindMessage.
  ///
  /// In zh, this message translates to:
  /// **'请更新应用后重试。'**
  String get widgetPinSupportInvalidKindMessage;

  /// No description provided for @widgetPinSupportFallbackMessage.
  ///
  /// In zh, this message translates to:
  /// **'若未弹出确认框，请打开系统设置检查桌面小组件与后台弹窗权限，或从系统小组件列表添加。'**
  String get widgetPinSupportFallbackMessage;

  /// No description provided for @widgetActionAppSettings.
  ///
  /// In zh, this message translates to:
  /// **'应用设置'**
  String get widgetActionAppSettings;

  /// No description provided for @widgetActionRecheck.
  ///
  /// In zh, this message translates to:
  /// **'重新检测'**
  String get widgetActionRecheck;

  /// No description provided for @widgetActionOpenPermissions.
  ///
  /// In zh, this message translates to:
  /// **'打开权限设置'**
  String get widgetActionOpenPermissions;

  /// No description provided for @widgetActionGotIt.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get widgetActionGotIt;

  /// No description provided for @widgetPinHelpUnsupportedMessage.
  ///
  /// In zh, this message translates to:
  /// **'当前桌面不支持应用内直接添加小组件。请长按桌面空白处，从系统小组件列表添加。'**
  String get widgetPinHelpUnsupportedMessage;

  /// No description provided for @widgetPinHelpUnsupportedPlatformMessage.
  ///
  /// In zh, this message translates to:
  /// **'当前平台不支持直接添加 Android 桌面小组件。请在 Android 手机上从系统小组件列表添加多仪。'**
  String get widgetPinHelpUnsupportedPlatformMessage;

  /// No description provided for @widgetPinHelpUnsupportedLauncherMessage.
  ///
  /// In zh, this message translates to:
  /// **'当前桌面启动器未开放应用内添加，请长按桌面空白处从系统小组件列表添加。'**
  String get widgetPinHelpUnsupportedLauncherMessage;

  /// No description provided for @widgetPinHelpPermissionDeniedMessage.
  ///
  /// In zh, this message translates to:
  /// **'系统未允许多仪添加桌面小组件。请在系统设置中开启权限后重试，或从系统小组件列表添加。'**
  String get widgetPinHelpPermissionDeniedMessage;

  /// No description provided for @widgetPinHelpConfirmationBlockedMessage.
  ///
  /// In zh, this message translates to:
  /// **'系统确认弹窗可能被拦截，请检查后台弹窗或悬浮窗权限后重试。'**
  String get widgetPinHelpConfirmationBlockedMessage;

  /// No description provided for @widgetPinHelpInvalidKindMessage.
  ///
  /// In zh, this message translates to:
  /// **'当前小组件类型暂不支持添加，请更新应用后重试。'**
  String get widgetPinHelpInvalidKindMessage;

  /// No description provided for @widgetPinHelpUnavailableMessage.
  ///
  /// In zh, this message translates to:
  /// **'无法发起添加请求，请检查桌面权限后重试，或从系统小组件列表添加。'**
  String get widgetPinHelpUnavailableMessage;

  /// No description provided for @widgetPinHelpRequestedMessage.
  ///
  /// In zh, this message translates to:
  /// **'已发起添加请求，请在桌面系统弹窗中确认。'**
  String get widgetPinHelpRequestedMessage;

  /// No description provided for @widgetPinConfirmationInvalidWidgetIdTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加未完成'**
  String get widgetPinConfirmationInvalidWidgetIdTitle;

  /// No description provided for @widgetPinConfirmationInvalidWidgetIdMessage.
  ///
  /// In zh, this message translates to:
  /// **'桌面未成功创建小组件，请重试或从系统小组件列表添加。'**
  String get widgetPinConfirmationInvalidWidgetIdMessage;

  /// No description provided for @widgetPinConfirmationTimeoutTitle.
  ///
  /// In zh, this message translates to:
  /// **'等待桌面确认'**
  String get widgetPinConfirmationTimeoutTitle;

  /// No description provided for @widgetPinConfirmationTimeoutMessage.
  ///
  /// In zh, this message translates to:
  /// **'已发起添加请求，但尚未收到系统确认。请查看桌面是否有确认弹窗，或在系统设置中检查权限。'**
  String get widgetPinConfirmationTimeoutMessage;

  /// No description provided for @widgetPinConfirmationUnavailableTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加异常'**
  String get widgetPinConfirmationUnavailableTitle;

  /// No description provided for @widgetPinConfirmationUnavailableMessage.
  ///
  /// In zh, this message translates to:
  /// **'桌面未返回添加结果。请重试或从系统小组件列表添加。'**
  String get widgetPinConfirmationUnavailableMessage;

  /// No description provided for @widgetPinConfirmationSuccessTitle.
  ///
  /// In zh, this message translates to:
  /// **'已添加'**
  String get widgetPinConfirmationSuccessTitle;

  /// No description provided for @widgetPinConfirmationSuccessMessage.
  ///
  /// In zh, this message translates to:
  /// **'桌面小组件已添加。'**
  String get widgetPinConfirmationSuccessMessage;

  /// No description provided for @widgetCheckingDesktopSupport.
  ///
  /// In zh, this message translates to:
  /// **'正在检查桌面支持'**
  String get widgetCheckingDesktopSupport;

  /// No description provided for @widgetPinDisabledAndroidOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅 Android 支持应用内添加'**
  String get widgetPinDisabledAndroidOnly;

  /// No description provided for @widgetPinDisabledPicker.
  ///
  /// In zh, this message translates to:
  /// **'请从系统小组件列表添加'**
  String get widgetPinDisabledPicker;

  /// No description provided for @widgetPinDisabledHelp.
  ///
  /// In zh, this message translates to:
  /// **'查看添加帮助'**
  String get widgetPinDisabledHelp;

  /// No description provided for @widgetLoadingStyle.
  ///
  /// In zh, this message translates to:
  /// **'正在读取样式'**
  String get widgetLoadingStyle;

  /// No description provided for @widgetStyleLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'样式读取失败，请重试或重新选择'**
  String get widgetStyleLoadFailed;

  /// No description provided for @widgetStyleSyncPending.
  ///
  /// In zh, this message translates to:
  /// **'已保存所选样式，桌面小组件尚未确认同步。请重试或刷新。'**
  String get widgetStyleSyncPending;

  /// No description provided for @widgetUpdatingStyle.
  ///
  /// In zh, this message translates to:
  /// **'正在更新样式'**
  String get widgetUpdatingStyle;

  /// No description provided for @widgetRequestingAdd.
  ///
  /// In zh, this message translates to:
  /// **'正在请求添加'**
  String get widgetRequestingAdd;

  /// addWidgetButtonLabel / —
  ///
  /// In zh, this message translates to:
  /// **'添加{modeLabel} {launcherRequestLabel}'**
  String widgetAddWidgetButtonLabel(
    String modeLabel,
    String launcherRequestLabel,
  );

  /// pinInitiatedSnackBar / —
  ///
  /// In zh, this message translates to:
  /// **'已发起添加，请在系统弹窗中确认添加{modeLabel}小组件。'**
  String widgetPinInitiatedSnackBar(String modeLabel);

  /// pinSuccessSnackBar / —
  ///
  /// In zh, this message translates to:
  /// **'已添加{modeLabel}小组件到桌面。'**
  String widgetPinSuccessSnackBar(String modeLabel);

  /// No description provided for @widgetTipsBannerTitle.
  ///
  /// In zh, this message translates to:
  /// **'桌面小组件使用提示'**
  String get widgetTipsBannerTitle;

  /// No description provided for @widgetDesktopWebTitle.
  ///
  /// In zh, this message translates to:
  /// **'电脑网页版显示日历'**
  String get widgetDesktopWebTitle;

  /// No description provided for @widgetDesktopWebMessage.
  ///
  /// In zh, this message translates to:
  /// **'桌面小组件依赖 Android 或 iOS 系统；电脑网页版默认隐藏小组件入口，保留月历预览和日历入口。'**
  String get widgetDesktopWebMessage;

  /// No description provided for @widgetDesktopWebTileSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'电脑网页版默认展示日历，不显示添加桌面小组件按钮'**
  String get widgetDesktopWebTileSubtitle;

  /// No description provided for @widgetDesktopWebOpenCalendar.
  ///
  /// In zh, this message translates to:
  /// **'打开日历'**
  String get widgetDesktopWebOpenCalendar;

  /// No description provided for @widgetPreviewTodoTitle.
  ///
  /// In zh, this message translates to:
  /// **'今日待办'**
  String get widgetPreviewTodoTitle;

  /// No description provided for @widgetPreviewScheduleTitle.
  ///
  /// In zh, this message translates to:
  /// **'今日日程'**
  String get widgetPreviewScheduleTitle;

  /// previewSampleBadge / —
  ///
  /// In zh, this message translates to:
  /// **'示例 · {title}'**
  String widgetPreviewSampleBadge(String title);

  /// sampleHeaderDate / date ?? 2026-05-17
  ///
  /// In zh, this message translates to:
  /// **'{cellLabel} · {monthLabel}/{day}'**
  String widgetSampleHeaderDate(
    String cellLabel,
    String monthLabel,
    String day,
  );

  /// No description provided for @widgetRefreshPreviewTooltip.
  ///
  /// In zh, this message translates to:
  /// **'刷新预览'**
  String get widgetRefreshPreviewTooltip;

  /// calendarMonthHeader / 整数转为原始十进制字符串
  ///
  /// In zh, this message translates to:
  /// **'{yearText}年{monthLabel}月'**
  String widgetCalendarMonthHeader(String yearText, String monthLabel);

  /// No description provided for @widgetTodoItem1.
  ///
  /// In zh, this message translates to:
  /// **'整理今日计划'**
  String get widgetTodoItem1;

  /// No description provided for @widgetTodoItem2.
  ///
  /// In zh, this message translates to:
  /// **'项目方案复盘'**
  String get widgetTodoItem2;

  /// No description provided for @widgetTodoItem3.
  ///
  /// In zh, this message translates to:
  /// **'晚间运动 30 分钟'**
  String get widgetTodoItem3;

  /// No description provided for @widgetTodoSummaryCount.
  ///
  /// In zh, this message translates to:
  /// **'今日待办 · 3 项'**
  String get widgetTodoSummaryCount;

  /// No description provided for @widgetTodoQuickAdd.
  ///
  /// In zh, this message translates to:
  /// **'+ 记一笔'**
  String get widgetTodoQuickAdd;

  /// No description provided for @widgetFocusMetricSessions.
  ///
  /// In zh, this message translates to:
  /// **'今日专注'**
  String get widgetFocusMetricSessions;

  /// No description provided for @widgetFocusMetricDuration.
  ///
  /// In zh, this message translates to:
  /// **'时长(分)'**
  String get widgetFocusMetricDuration;

  /// No description provided for @widgetFocusMetricNext.
  ///
  /// In zh, this message translates to:
  /// **'下一轮(分)'**
  String get widgetFocusMetricNext;

  /// No description provided for @widgetFocusTimerUnit.
  ///
  /// In zh, this message translates to:
  /// **'分钟'**
  String get widgetFocusTimerUnit;

  /// No description provided for @widgetFocusStartButton.
  ///
  /// In zh, this message translates to:
  /// **'开始 25 分钟专注'**
  String get widgetFocusStartButton;

  /// No description provided for @widgetFocusLine1.
  ///
  /// In zh, this message translates to:
  /// **'今日专注 2 次 · 深度工作 50 分钟'**
  String get widgetFocusLine1;

  /// No description provided for @widgetFocusLine2.
  ///
  /// In zh, this message translates to:
  /// **'下一轮：25 分钟专注'**
  String get widgetFocusLine2;

  /// No description provided for @widgetFocusLine3.
  ///
  /// In zh, this message translates to:
  /// **'点击开始专注'**
  String get widgetFocusLine3;

  /// No description provided for @widgetHabitTitle.
  ///
  /// In zh, this message translates to:
  /// **'今日习惯'**
  String get widgetHabitTitle;

  /// No description provided for @widgetCalendarCurrentDate.
  ///
  /// In zh, this message translates to:
  /// **'5月17日 · 周日'**
  String get widgetCalendarCurrentDate;

  /// No description provided for @widgetCalendarCurrentDay.
  ///
  /// In zh, this message translates to:
  /// **'5月17日'**
  String get widgetCalendarCurrentDay;

  /// No description provided for @widgetHabitLine1.
  ///
  /// In zh, this message translates to:
  /// **'· 晚间拉伸 · 今日待打卡'**
  String get widgetHabitLine1;

  /// No description provided for @widgetHabitLine2.
  ///
  /// In zh, this message translates to:
  /// **'· 连续记录 5 天'**
  String get widgetHabitLine2;

  /// No description provided for @widgetHabitCheckInButton.
  ///
  /// In zh, this message translates to:
  /// **'打卡：晚间拉伸'**
  String get widgetHabitCheckInButton;

  /// No description provided for @widgetScheduleItem1.
  ///
  /// In zh, this message translates to:
  /// **'09:00 今日计划 · 到点提醒'**
  String get widgetScheduleItem1;

  /// No description provided for @widgetScheduleItem2.
  ///
  /// In zh, this message translates to:
  /// **'14:30 团队例会'**
  String get widgetScheduleItem2;

  /// No description provided for @widgetScheduleItem3.
  ///
  /// In zh, this message translates to:
  /// **'19:00 晚间复盘'**
  String get widgetScheduleItem3;

  /// No description provided for @widgetGoalItem1.
  ///
  /// In zh, this message translates to:
  /// **'发版准备 · 68%'**
  String get widgetGoalItem1;

  /// No description provided for @widgetGoalItem2.
  ///
  /// In zh, this message translates to:
  /// **'本周运动 3/5 次'**
  String get widgetGoalItem2;

  /// No description provided for @widgetGoalItem3.
  ///
  /// In zh, this message translates to:
  /// **'晚间复盘 · 今日待推进'**
  String get widgetGoalItem3;

  /// No description provided for @widgetCourseItem1.
  ///
  /// In zh, this message translates to:
  /// **'第 1-2 节 高等数学 · 教 203'**
  String get widgetCourseItem1;

  /// No description provided for @widgetCourseItem2.
  ///
  /// In zh, this message translates to:
  /// **'第 3-4 节 产品设计 · 线上'**
  String get widgetCourseItem2;

  /// No description provided for @widgetCourseItem3.
  ///
  /// In zh, this message translates to:
  /// **'第 5-6 节 英语 · 教 305'**
  String get widgetCourseItem3;

  /// No description provided for @widgetNoteItem1.
  ///
  /// In zh, this message translates to:
  /// **'会议纪要'**
  String get widgetNoteItem1;

  /// No description provided for @widgetNoteItem2.
  ///
  /// In zh, this message translates to:
  /// **'灵感清单'**
  String get widgetNoteItem2;

  /// No description provided for @widgetNoteItem3.
  ///
  /// In zh, this message translates to:
  /// **'读书摘录'**
  String get widgetNoteItem3;

  /// No description provided for @widgetAnniversaryItem1.
  ///
  /// In zh, this message translates to:
  /// **'相识纪念日 · 还有 6 天'**
  String get widgetAnniversaryItem1;

  /// No description provided for @widgetAnniversaryItem2.
  ///
  /// In zh, this message translates to:
  /// **'入职周年 · 还有 18 天'**
  String get widgetAnniversaryItem2;

  /// No description provided for @widgetAnniversaryItem3.
  ///
  /// In zh, this message translates to:
  /// **'旅行纪念 · 还有 32 天'**
  String get widgetAnniversaryItem3;

  /// No description provided for @widgetDiaryItem1.
  ///
  /// In zh, this message translates to:
  /// **'5/17 今天完成了专注复盘'**
  String get widgetDiaryItem1;

  /// No description provided for @widgetDiaryItem2.
  ///
  /// In zh, this message translates to:
  /// **'5/16 记录一次散步'**
  String get widgetDiaryItem2;

  /// No description provided for @widgetDiaryItem3.
  ///
  /// In zh, this message translates to:
  /// **'5/15 睡前整理心情'**
  String get widgetDiaryItem3;

  /// No description provided for @widgetCalendarMonthJan.
  ///
  /// In zh, this message translates to:
  /// **'1'**
  String get widgetCalendarMonthJan;

  /// No description provided for @widgetCalendarMonthFeb.
  ///
  /// In zh, this message translates to:
  /// **'2'**
  String get widgetCalendarMonthFeb;

  /// No description provided for @widgetCalendarMonthMar.
  ///
  /// In zh, this message translates to:
  /// **'3'**
  String get widgetCalendarMonthMar;

  /// No description provided for @widgetCalendarMonthApr.
  ///
  /// In zh, this message translates to:
  /// **'4'**
  String get widgetCalendarMonthApr;

  /// No description provided for @widgetCalendarMonthMay.
  ///
  /// In zh, this message translates to:
  /// **'5'**
  String get widgetCalendarMonthMay;

  /// No description provided for @widgetCalendarMonthJun.
  ///
  /// In zh, this message translates to:
  /// **'6'**
  String get widgetCalendarMonthJun;

  /// No description provided for @widgetCalendarMonthJul.
  ///
  /// In zh, this message translates to:
  /// **'7'**
  String get widgetCalendarMonthJul;

  /// No description provided for @widgetCalendarMonthAug.
  ///
  /// In zh, this message translates to:
  /// **'8'**
  String get widgetCalendarMonthAug;

  /// No description provided for @widgetCalendarMonthSep.
  ///
  /// In zh, this message translates to:
  /// **'9'**
  String get widgetCalendarMonthSep;

  /// No description provided for @widgetCalendarMonthOct.
  ///
  /// In zh, this message translates to:
  /// **'10'**
  String get widgetCalendarMonthOct;

  /// No description provided for @widgetCalendarMonthNov.
  ///
  /// In zh, this message translates to:
  /// **'11'**
  String get widgetCalendarMonthNov;

  /// No description provided for @widgetCalendarMonthDec.
  ///
  /// In zh, this message translates to:
  /// **'12'**
  String get widgetCalendarMonthDec;

  /// Theme and widget appearance: themeSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'主题保存失败'**
  String get dataSettingsThemeSaveFailed;

  /// Theme and widget appearance: rewardShopReason.
  ///
  /// In zh, this message translates to:
  /// **'奖励商店主题装饰'**
  String get dataSettingsRewardShopReason;

  /// Theme and widget appearance: redeemThemeTitle.
  ///
  /// In zh, this message translates to:
  /// **'兑换主题：{name}'**
  String dataSettingsRedeemThemeTitle(String name);

  /// Theme and widget appearance: redeemFocusBackdropTitle.
  ///
  /// In zh, this message translates to:
  /// **'兑换专注背景：{name}'**
  String dataSettingsRedeemFocusBackdropTitle(String name);

  /// Theme and widget appearance: redeemAvatarFrameTitle.
  ///
  /// In zh, this message translates to:
  /// **'兑换头像框：{name}'**
  String dataSettingsRedeemAvatarFrameTitle(String name);

  /// Theme and widget appearance: redeemCardSkinTitle.
  ///
  /// In zh, this message translates to:
  /// **'兑换卡片皮肤：{name}'**
  String dataSettingsRedeemCardSkinTitle(String name);

  /// Theme and widget appearance: insufficientCoins.
  ///
  /// In zh, this message translates to:
  /// **'时光币不足，还差 {diff}'**
  String dataSettingsInsufficientCoins(int diff);

  /// Theme and widget appearance: themeApplied.
  ///
  /// In zh, this message translates to:
  /// **'已启用 {name}'**
  String dataSettingsThemeApplied(String name);

  /// Theme and widget appearance: themeRedeemedAndApplied.
  ///
  /// In zh, this message translates to:
  /// **'已兑换并启用 {name}'**
  String dataSettingsThemeRedeemedAndApplied(String name);

  /// Theme and widget appearance: widgetBackgroundSwitched.
  ///
  /// In zh, this message translates to:
  /// **'小组件背景已切换为 {label}'**
  String dataSettingsWidgetBackgroundSwitched(String label);

  /// Theme and widget appearance: unlockThemeFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先解锁该主题'**
  String get dataSettingsUnlockThemeFirst;

  /// Theme and widget appearance: widgetCardSkinSwitched.
  ///
  /// In zh, this message translates to:
  /// **'小组件卡片皮肤已切换为 {label}'**
  String dataSettingsWidgetCardSkinSwitched(String label);

  /// Theme and widget appearance: unlockCardSkinFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先解锁该卡片皮肤'**
  String get dataSettingsUnlockCardSkinFirst;

  /// Theme and widget appearance: widgetFollowCurrentTheme.
  ///
  /// In zh, this message translates to:
  /// **'跟随当前主题'**
  String get dataSettingsWidgetFollowCurrentTheme;

  /// Theme and widget appearance: widgetFollowCardSkin.
  ///
  /// In zh, this message translates to:
  /// **'跟随卡片皮肤'**
  String get dataSettingsWidgetFollowCardSkin;

  /// Theme and widget appearance: widgetThemeTitle.
  ///
  /// In zh, this message translates to:
  /// **'桌面小组件主题'**
  String get dataSettingsWidgetThemeTitle;

  /// Theme and widget appearance: widgetThemeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'单独调整桌面小组件背景和卡片皮肤'**
  String get dataSettingsWidgetThemeSubtitle;

  /// Theme and widget appearance: widgetBackgroundLabel.
  ///
  /// In zh, this message translates to:
  /// **'背景图'**
  String get dataSettingsWidgetBackgroundLabel;

  /// Theme and widget appearance: widgetCardSkinLabel.
  ///
  /// In zh, this message translates to:
  /// **'卡片皮肤'**
  String get dataSettingsWidgetCardSkinLabel;

  /// Theme and widget appearance: coinCount.
  ///
  /// In zh, this message translates to:
  /// **'时光币 {count}'**
  String dataSettingsCoinCount(int count);

  /// Theme and widget appearance: coinCost.
  ///
  /// In zh, this message translates to:
  /// **'{cost} 币'**
  String dataSettingsCoinCost(int cost);

  /// Theme and widget appearance: focusBackdropSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'专注背景'**
  String get dataSettingsFocusBackdropSectionTitle;

  /// Theme and widget appearance: focusBackdropSectionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'用时光币兑换番茄钟卡片装饰'**
  String get dataSettingsFocusBackdropSectionSubtitle;

  /// Theme and widget appearance: avatarFrameSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'头像框'**
  String get dataSettingsAvatarFrameSectionTitle;

  /// Theme and widget appearance: avatarFrameSectionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'用时光币兑换我的页头像装饰'**
  String get dataSettingsAvatarFrameSectionSubtitle;

  /// Theme and widget appearance: cardSkinSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'卡片皮肤'**
  String get dataSettingsCardSkinSectionTitle;

  /// Theme and widget appearance: cardSkinSectionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'用时光币兑换信息卡片质感'**
  String get dataSettingsCardSkinSectionSubtitle;

  /// Theme and widget appearance: widgetSyncNoticeTitle.
  ///
  /// In zh, this message translates to:
  /// **'小组件主题'**
  String get dataSettingsWidgetSyncNoticeTitle;

  /// Theme and widget appearance: widgetSyncNoticeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'背景图和卡片皮肤会同步到手机桌面小组件'**
  String get dataSettingsWidgetSyncNoticeSubtitle;

  /// Built-in reward display name for stable ID classic_focus.
  ///
  /// In zh, this message translates to:
  /// **'经典专注'**
  String get dataSettingsFocusBackdropClassicName;

  /// Built-in reward display name for stable ID morning_focus.
  ///
  /// In zh, this message translates to:
  /// **'晨光书桌'**
  String get dataSettingsFocusBackdropMorningName;

  /// Built-in reward display name for stable ID forest_focus.
  ///
  /// In zh, this message translates to:
  /// **'林间深呼吸'**
  String get dataSettingsFocusBackdropForestName;

  /// Built-in reward display name for stable ID ocean_focus.
  ///
  /// In zh, this message translates to:
  /// **'海岸静流'**
  String get dataSettingsFocusBackdropOceanName;

  /// Built-in reward display name for stable ID night_focus.
  ///
  /// In zh, this message translates to:
  /// **'夜航模式'**
  String get dataSettingsFocusBackdropNightName;

  /// Built-in reward display description for stable ID classic_focus.
  ///
  /// In zh, this message translates to:
  /// **'简洁的番茄钟渐变背景'**
  String get dataSettingsFocusBackdropClassicDescription;

  /// Built-in reward display description for stable ID morning_focus.
  ///
  /// In zh, this message translates to:
  /// **'适合清晨阅读和学习的暖色背景'**
  String get dataSettingsFocusBackdropMorningDescription;

  /// Built-in reward display description for stable ID forest_focus.
  ///
  /// In zh, this message translates to:
  /// **'适合长时间深度工作的自然绿色背景'**
  String get dataSettingsFocusBackdropForestDescription;

  /// Built-in reward display description for stable ID ocean_focus.
  ///
  /// In zh, this message translates to:
  /// **'适合复盘、写作和低压专注的蓝绿色背景'**
  String get dataSettingsFocusBackdropOceanDescription;

  /// Built-in reward display description for stable ID night_focus.
  ///
  /// In zh, this message translates to:
  /// **'适合夜间学习的低亮度深色背景'**
  String get dataSettingsFocusBackdropNightDescription;

  /// Built-in reward display name for stable ID simple_frame.
  ///
  /// In zh, this message translates to:
  /// **'简洁头像'**
  String get dataSettingsAvatarFrameSimpleName;

  /// Built-in reward display name for stable ID golden_frame.
  ///
  /// In zh, this message translates to:
  /// **'金色勋章框'**
  String get dataSettingsAvatarFrameGoldenName;

  /// Built-in reward display name for stable ID forest_frame.
  ///
  /// In zh, this message translates to:
  /// **'绿叶守护框'**
  String get dataSettingsAvatarFrameForestName;

  /// Built-in reward display name for stable ID aurora_frame.
  ///
  /// In zh, this message translates to:
  /// **'极光能量框'**
  String get dataSettingsAvatarFrameAuroraName;

  /// Built-in reward display description for stable ID simple_frame.
  ///
  /// In zh, this message translates to:
  /// **'默认头像样式'**
  String get dataSettingsAvatarFrameSimpleDescription;

  /// Built-in reward display description for stable ID golden_frame.
  ///
  /// In zh, this message translates to:
  /// **'适合成就达人展示的金色头像框'**
  String get dataSettingsAvatarFrameGoldenDescription;

  /// Built-in reward display description for stable ID forest_frame.
  ///
  /// In zh, this message translates to:
  /// **'适合习惯连续打卡的自然头像框'**
  String get dataSettingsAvatarFrameForestDescription;

  /// Built-in reward display description for stable ID aurora_frame.
  ///
  /// In zh, this message translates to:
  /// **'适合高效专注周的流光头像框'**
  String get dataSettingsAvatarFrameAuroraDescription;

  /// Built-in reward display name for stable ID plain_card.
  ///
  /// In zh, this message translates to:
  /// **'素净卡片'**
  String get dataSettingsCardSkinPlainName;

  /// Built-in reward display name for stable ID paper_card.
  ///
  /// In zh, this message translates to:
  /// **'纸感计划卡'**
  String get dataSettingsCardSkinPaperName;

  /// Built-in reward display name for stable ID mint_card.
  ///
  /// In zh, this message translates to:
  /// **'薄荷清单卡'**
  String get dataSettingsCardSkinMintName;

  /// Built-in reward display name for stable ID starlight_card.
  ///
  /// In zh, this message translates to:
  /// **'星光玻璃卡'**
  String get dataSettingsCardSkinStarlightName;

  /// Built-in reward display description for stable ID plain_card.
  ///
  /// In zh, this message translates to:
  /// **'默认信息卡片样式'**
  String get dataSettingsCardSkinPlainDescription;

  /// Built-in reward display description for stable ID paper_card.
  ///
  /// In zh, this message translates to:
  /// **'适合日程和待办整理的柔和纸感'**
  String get dataSettingsCardSkinPaperDescription;

  /// Built-in reward display description for stable ID mint_card.
  ///
  /// In zh, this message translates to:
  /// **'适合习惯和专注记录的清爽卡片'**
  String get dataSettingsCardSkinMintDescription;

  /// Built-in reward display description for stable ID starlight_card.
  ///
  /// In zh, this message translates to:
  /// **'适合夜间复盘的低亮度玻璃质感'**
  String get dataSettingsCardSkinStarlightDescription;

  /// Settings presentation copy: saveFailed
  ///
  /// In zh, this message translates to:
  /// **'设置未保存，请重试。'**
  String get settingsUiSaveFailed;

  /// Settings presentation copy: decreaseValue
  ///
  /// In zh, this message translates to:
  /// **'减少'**
  String get settingsUiDecreaseValue;

  /// Settings presentation copy: increaseValue
  ///
  /// In zh, this message translates to:
  /// **'增加'**
  String get settingsUiIncreaseValue;

  /// Settings presentation copy: decreaseSetting
  ///
  /// In zh, this message translates to:
  /// **'减少“{title}”'**
  String settingsUiDecreaseSetting(String title);

  /// Settings presentation copy: increaseSetting
  ///
  /// In zh, this message translates to:
  /// **'增加“{title}”'**
  String settingsUiIncreaseSetting(String title);

  /// Settings presentation copy: currentFirstWeekday
  ///
  /// In zh, this message translates to:
  /// **'当前为{weekday}'**
  String settingsUiCurrentFirstWeekday(String weekday);

  /// Settings presentation copy: preferencesHeroExplanation
  ///
  /// In zh, this message translates to:
  /// **'自定义显示与行为偏好，管理底部导航入口与小组件显示。'**
  String get settingsUiPreferencesHeroExplanation;

  /// Settings presentation copy: preferencesCategoriesSectionTitle
  ///
  /// In zh, this message translates to:
  /// **'个性入口'**
  String get settingsUiPreferencesCategoriesSectionTitle;

  /// Settings presentation copy: preferencesCategoriesSectionSubtitle
  ///
  /// In zh, this message translates to:
  /// **'选择要调整的设置类别'**
  String get settingsUiPreferencesCategoriesSectionSubtitle;

  /// Settings presentation copy: displayAndBehaviorTitle
  ///
  /// In zh, this message translates to:
  /// **'显示与行为'**
  String get settingsUiDisplayAndBehaviorTitle;

  /// Settings presentation copy: displayAndBehaviorSubtitle
  ///
  /// In zh, this message translates to:
  /// **'日期格式、应用时区、启动入口、交互与归档'**
  String get settingsUiDisplayAndBehaviorSubtitle;

  /// Settings presentation copy: displayAndBehaviorHeroSubtitle
  ///
  /// In zh, this message translates to:
  /// **'管理日期格式、应用时区、启动默认项、交互反馈与待办归档。'**
  String get settingsUiDisplayAndBehaviorHeroSubtitle;

  /// Settings presentation copy: navigationSectionTitle
  ///
  /// In zh, this message translates to:
  /// **'导航入口'**
  String get settingsUiNavigationSectionTitle;

  /// Settings presentation copy: navigationSectionSubtitle
  ///
  /// In zh, this message translates to:
  /// **'最多 5 个底部入口；“我的”固定，小组件可隐藏'**
  String get settingsUiNavigationSectionSubtitle;

  /// Settings presentation copy: jumpToMenuTitle
  ///
  /// In zh, this message translates to:
  /// **'快捷定位'**
  String get settingsUiJumpToMenuTitle;

  /// Settings presentation copy: jumpToDate
  ///
  /// In zh, this message translates to:
  /// **'日期日历'**
  String get settingsUiJumpToDate;

  /// Settings presentation copy: jumpToDefaults
  ///
  /// In zh, this message translates to:
  /// **'默认行为'**
  String get settingsUiJumpToDefaults;

  /// Settings presentation copy: jumpToInteraction
  ///
  /// In zh, this message translates to:
  /// **'交互归档'**
  String get settingsUiJumpToInteraction;

  /// Settings presentation copy: dateFormatLabel
  ///
  /// In zh, this message translates to:
  /// **'标准 ({pattern})'**
  String settingsUiDateFormatIso(String pattern);

  /// Settings presentation copy: dateFormatLabel
  ///
  /// In zh, this message translates to:
  /// **'美式 ({pattern})'**
  String settingsUiDateFormatUs(String pattern);

  /// Settings presentation copy: dateFormatLabel
  ///
  /// In zh, this message translates to:
  /// **'欧式 ({pattern})'**
  String settingsUiDateFormatEurope(String pattern);

  /// Settings presentation copy: dateFormatLabel
  ///
  /// In zh, this message translates to:
  /// **'中文年月日 ({pattern})'**
  String settingsUiDateFormatEastAsian(String pattern);

  /// Settings presentation copy: timeZoneDisplayName
  ///
  /// In zh, this message translates to:
  /// **'中国标准时间 (上海)'**
  String get settingsUiTimeZoneShanghai;

  /// Settings presentation copy: timeZoneDisplayName
  ///
  /// In zh, this message translates to:
  /// **'墨西哥城时间'**
  String get settingsUiTimeZoneMexicoCity;

  /// Settings presentation copy: timeZoneDisplayName
  ///
  /// In zh, this message translates to:
  /// **'蒂华纳时间'**
  String get settingsUiTimeZoneTijuana;

  /// Settings presentation copy: timeZoneDisplayName
  ///
  /// In zh, this message translates to:
  /// **'东京时间 (日本)'**
  String get settingsUiTimeZoneTokyo;

  /// Settings presentation copy: timeZoneDisplayName
  ///
  /// In zh, this message translates to:
  /// **'香港时间'**
  String get settingsUiTimeZoneHongKong;

  /// Settings presentation copy: timeZoneDisplayName
  ///
  /// In zh, this message translates to:
  /// **'新加坡时间'**
  String get settingsUiTimeZoneSingapore;

  /// Settings presentation copy: timeZoneDisplayName
  ///
  /// In zh, this message translates to:
  /// **'纽约时间 (美东)'**
  String get settingsUiTimeZoneNewYork;

  /// Settings presentation copy: timeZoneDisplayName
  ///
  /// In zh, this message translates to:
  /// **'洛杉矶时间 (美西)'**
  String get settingsUiTimeZoneLosAngeles;

  /// Settings presentation copy: timeZoneDisplayName
  ///
  /// In zh, this message translates to:
  /// **'伦敦时间'**
  String get settingsUiTimeZoneLondon;

  /// Settings presentation copy: timeZoneDisplayName
  ///
  /// In zh, this message translates to:
  /// **'巴黎时间 (中欧)'**
  String get settingsUiTimeZoneParis;

  /// Settings presentation copy: timeZoneDisplayName
  ///
  /// In zh, this message translates to:
  /// **'悉尼时间 (澳洲东部)'**
  String get settingsUiTimeZoneSydney;

  /// Settings presentation copy: navigationBannerMessage
  ///
  /// In zh, this message translates to:
  /// **'底部导航最多显示 5 个入口，我的固定显示；小组件可隐藏，隐藏入口可在“我的”页面访问。'**
  String get settingsUiNavigationBannerMessage;

  /// Settings presentation copy: maxTabsConstraint
  ///
  /// In zh, this message translates to:
  /// **'最多显示 {max} 个入口'**
  String settingsUiMaxTabsConstraint(int max);

  /// Settings presentation copy: navigationHiddenAtLimit
  ///
  /// In zh, this message translates to:
  /// **'已达上限，先隐藏其他项'**
  String get settingsUiNavigationHiddenAtLimit;

  /// Settings presentation copy: navigationMoveUp
  ///
  /// In zh, this message translates to:
  /// **'上移“{label}”'**
  String settingsUiNavigationMoveUp(String label);

  /// Settings presentation copy: navigationMoveDown
  ///
  /// In zh, this message translates to:
  /// **'下移“{label}”'**
  String settingsUiNavigationMoveDown(String label);

  /// Settings presentation copy: selectOption
  ///
  /// In zh, this message translates to:
  /// **'选择设置'**
  String get settingsUiSelectOption;

  /// Settings presentation copy: selectFirstDay
  ///
  /// In zh, this message translates to:
  /// **'选择一周第一天'**
  String get settingsUiSelectFirstDay;

  /// Settings presentation copy: selectDateFormat
  ///
  /// In zh, this message translates to:
  /// **'选择日期格式'**
  String get settingsUiSelectDateFormat;

  /// Settings presentation copy: selectTimeZone
  ///
  /// In zh, this message translates to:
  /// **'选择应用时区'**
  String get settingsUiSelectTimeZone;

  /// Settings presentation copy: selectDefaultTab
  ///
  /// In zh, this message translates to:
  /// **'选择启动默认 Tab'**
  String get settingsUiSelectDefaultTab;

  /// Settings presentation copy: selectAutoLock
  ///
  /// In zh, this message translates to:
  /// **'选择自动锁定时间'**
  String get settingsUiSelectAutoLock;

  /// Settings presentation copy: autoLockOptionLabel
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String settingsUiAutoLockMinutes(int minutes);

  /// Settings presentation copy: autoLockSubtitle
  ///
  /// In zh, this message translates to:
  /// **'离开 {minutes} 分钟后锁定'**
  String settingsUiAutoLockAfter(int minutes);

  /// Exact goal copy. Chinese intentionally ignores unit and retains literal 次; English uses default occurrence singular/plural only.
  ///
  /// In zh, this message translates to:
  /// **'每周目标: {target} 次/周'**
  String habitCopyWeekGoal(int target, String unit);

  /// Exact goal copy. Chinese intentionally ignores unit and retains literal 次; English uses default occurrence singular/plural only.
  ///
  /// In zh, this message translates to:
  /// **'每月目标: {target} 次/月'**
  String habitCopyMonthGoal(int target, String unit);

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'结束'**
  String get habitCopyActionEnd;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'删除习惯？'**
  String get habitCopyDeleteConfirmTitle;

  /// Exact copy; habitName is intentionally unused in English.
  ///
  /// In zh, this message translates to:
  /// **'会删除“{habitName}”和关联记录，不可恢复。'**
  String habitCopyDeleteConfirmContent(String habitName);

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'结束习惯？'**
  String get habitCopyEndConfirmTitle;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'结束“{habitName}”？历史记录将保留。'**
  String habitCopyEndConfirmContent(String habitName);

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'结束习惯'**
  String get habitCopyEndHabitAction;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'删除习惯'**
  String get habitCopyDeleteHabitAction;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get habitCopyMoreActions;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'习惯已结束，历史记录已保留'**
  String get habitCopyEndedFeedback;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'习惯已删除'**
  String get habitCopyDeletedFeedback;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'习惯已保存'**
  String get habitCopySaveSuccess;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'打卡失败，请重试'**
  String get habitCopyCheckInFailedWithRetry;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'撤销打卡失败，请重试'**
  String get habitCopyUndoFailedWithRetry;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'保存习惯失败，请重试'**
  String get habitCopySaveFailedWithRetry;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'操作失败，请重试'**
  String get habitCopyActionFailedWithRetry;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'请输入习惯名称'**
  String get habitCopyNameRequired;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'每日目标至少为 1'**
  String get habitCopyDailyTargetInvalid;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'提醒调度器尚未初始化，请重新打开应用后再保存提醒'**
  String get habitCopyReminderSchedulerMissing;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'系统通知未授权，习惯提醒不会响铃或弹出'**
  String get habitCopyNotificationsNotGranted;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'需要系统通知权限以接收提醒'**
  String get habitCopyReminderPermissionError;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'提醒注册失败'**
  String get habitCopyReminderRegisterFailed;

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'习惯已保存，但提醒未同步：{issueText}'**
  String habitCopyReminderSyncWarning(String issueText);

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'「{habitName}」{periodLabel}目标已达标'**
  String habitCopyPeriodGoalReached(String habitName, String periodLabel);

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'「{habitName}」今日单次目标已完成'**
  String habitCopySingleSessionGoalReached(String habitName);

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'已记录一次「{habitName}」'**
  String habitCopyCheckInSuccessNegative(String habitName);

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'已记录「{habitName}」'**
  String habitCopyDateRecordFeedback(String habitName);

  /// Preserve the current HabitUiCopy output exactly; authored placeholders stay literal.
  ///
  /// In zh, this message translates to:
  /// **'已撤销「{habitName}」记录'**
  String habitCopyDateUndoFeedback(String habitName);

  /// Exact lowercase cup key; count == 1 only.
  ///
  /// In zh, this message translates to:
  /// **'杯'**
  String get habitCopyUnitCup;

  /// Exact lowercase cup key; count != 1.
  ///
  /// In zh, this message translates to:
  /// **'杯'**
  String get habitCopyUnitCups;

  /// Default generated occurrence singular; count == 1 only.
  ///
  /// In zh, this message translates to:
  /// **'次'**
  String get habitCopyUnitTime;

  /// Preserve the current HabitUiCopy output exactly.
  ///
  /// In zh, this message translates to:
  /// **'{count} {unit}'**
  String habitCopyMeasuredCount(int count, String unit);

  /// Preserve the current HabitUiCopy output exactly.
  ///
  /// In zh, this message translates to:
  /// **'{measuredCount} · {flexProgressLabel}'**
  String habitCopyCountWithFlexProgress(
    String measuredCount,
    String flexProgressLabel,
  );

  /// Preserve the current HabitUiCopy output exactly.
  ///
  /// In zh, this message translates to:
  /// **'已记录 {measuredCount}'**
  String habitCopyCountRecorded(String measuredCount);

  /// Preserve the current HabitUiCopy output exactly.
  ///
  /// In zh, this message translates to:
  /// **'{measuredCount} / {target} {targetUnit}'**
  String habitCopyCountRatio(
    String measuredCount,
    int target,
    String targetUnit,
  );

  /// Preserve the current HabitUiCopy output exactly.
  ///
  /// In zh, this message translates to:
  /// **'「{habitName}」今日已达标'**
  String habitCopyCheckInSuccessStandardReached(String habitName);

  /// Preserve the current HabitUiCopy output exactly.
  ///
  /// In zh, this message translates to:
  /// **'已打卡「{habitName}」 {count}/{target}'**
  String habitCopyCheckInSuccessStandardProgress(
    String habitName,
    int count,
    int target,
  );

  /// Null flexPrefix only; empty or blank authored prefix must remain literal.
  ///
  /// In zh, this message translates to:
  /// **'本周期'**
  String get habitCopyPeriodFallback;

  /// Preserve the current HabitUiCopy output exactly.
  ///
  /// In zh, this message translates to:
  /// **'已打卡「{habitName}」 {flexLabel}'**
  String habitCopyCheckInSuccessFlexProgress(
    String habitName,
    String flexLabel,
  );

  /// Complete settings label with locale-specific grammar and punctuation.
  ///
  /// In zh, this message translates to:
  /// **'1 天'**
  String get settingsUiAutoArchiveDayOne;

  /// Complete settings label with locale-specific grammar and punctuation.
  ///
  /// In zh, this message translates to:
  /// **'{days} 天'**
  String settingsUiAutoArchiveDayMany(int days);

  /// Complete settings label with locale-specific grammar and punctuation.
  ///
  /// In zh, this message translates to:
  /// **'1 天后自动隐藏'**
  String get settingsUiAutoArchiveAfterOneDay;

  /// Complete settings label with locale-specific grammar and punctuation.
  ///
  /// In zh, this message translates to:
  /// **'{days} 天后自动隐藏'**
  String settingsUiAutoArchiveAfterDays(int days);

  /// Complete settings label with locale-specific grammar and punctuation.
  ///
  /// In zh, this message translates to:
  /// **'跟随手机：{timeZoneName}'**
  String settingsUiFollowingSystemTimeZone(String timeZoneName);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
