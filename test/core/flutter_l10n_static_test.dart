import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/l10n/generated/app_localizations_en.dart';
import 'package:duoyi/l10n/generated/app_localizations_zh.dart';

void main() {
  test('Flutter 官方 gen-l10n 配置和生成入口已接入', () {
    final l10nConfig = File('l10n.yaml').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final generated = File(
      'lib/l10n/generated/app_localizations.dart',
    ).readAsStringSync();

    expect(l10nConfig, contains('arb-dir: lib/l10n'));
    expect(l10nConfig, contains('output-dir: lib/l10n/generated'));
    expect(pubspec, contains('generate: true'));
    expect(main, contains("import 'l10n/generated/app_localizations.dart';"));
    expect(main, contains('AppLocalizations.supportedLocales'));
    expect(main, contains('AppLocalizations.localizationsDelegates'));
    expect(generated, contains('class AppLocalizations'));
    expect(generated, contains('GlobalMaterialLocalizations.delegate'));
  });

  test('基础 ARB 同时提供中英文应用和导航词条', () {
    final zh = File('lib/l10n/app_zh.arb').readAsStringSync();
    final en = File('lib/l10n/app_en.arb').readAsStringSync();

    for (final key in const [
      'appTitle',
      'navToday',
      'navTodo',
      'navHabit',
      'navCalendar',
      'navFocus',
      'navWidget',
      'navMine',
      'actionConfirm',
      'actionCancel',
      'actionSave',
      'actionAdd',
      'actionDelete',
      'actionCreate',
      'actionClear',
      'weekdayMon',
      'weekdaySun',
      'calendarSolar',
      'calendarLunar',
      'calendarChineseLunarCalendar',
      'calendarCorrespondingLunar',
      'calendarCorrespondingSolar',
      'calendarEventEvent',
      'calendarEventTodo',
      'calendarEventTimeEntry',
      'timeEntrySourceManual',
      'timeEntrySourcePomodoro',
      'timeEntryCategoryFocus',
      'timeEntryCategoryOther',
      'settingsLanguageDescription',
      'preferencesTitle',
      'preferencesLocalTitle',
      'preferencesSectionDate',
      'preferencesSectionDefaults',
      'preferencesSectionBottomNav',
      'preferencesSectionInteraction',
      'preferencesSectionAutoArchive',
      'preferencesNotifyPermissionDenied',
      'preferencesNotifyExactAlarmGranted',
      'preferencesNotifyFullScreenDenied',
      'preferencesRingtoneSection',
      'preferencesDailyReminderOne',
      'preferencesDailyReminderTime',
      'preferencesDailyReminderScopeToday',
      'quickTodoTitle',
      'quickAiTitle',
      'quickMenuTodo',
      'quickMenuTemplate',
      'quickTemplateTitle',
      'quickTemplateSave',
      'searchHint',
      'searchEmpty',
      'searchResultsTitle',
      'searchClear',
      'searchKindTodo',
      'searchKindTimeEntry',
      'authLoginTitle',
      'authRegisterTitle',
      'authPasswordLogin',
      'authEmailCodeLogin',
      'authResetAccount',
      'authErrorUsernameLength',
      'authErrorNewPasswordMismatch',
      'profileTitle',
      'profileAvatarUrlFileOrText',
      'profileChangePassword',
      'profileConfirmNewPassword',
      'noteTitle',
      'noteAttachmentPickFile',
      'noteEditorHint',
      'noteToolbarBold',
      'notePreviewEmpty',
      'feedbackCategoryFeature',
      'feedbackStatusInProgress',
      'feedbackSubmitButton',
      'feedbackAdminReply',
      'announcementTitle',
      'announcementLevelCritical',
      'announcementEmpty',
      'themeTitle',
      'themeStyleDefaultName',
      'themeStyleStarRailDescription',
      'goalTitle',
      'goalStatusActive',
      'goalDaysRemainingSuffix',
      'exportTitle',
      'exportPushCaldav',
      'exportCaldavFailedPrefix',
      'appLockTitle',
      'appLockAutoLock',
      'appLockPinInvalid',
      'aiHistoryTitle',
      'aiHistoryClearAction',
      'aiHistoryEmpty',
      'aiHistoryExpand',
      'aiHistoryCollapse',
      'syncConflictTitle',
      'syncConflictEmpty',
      'syncConflictKeepRemote',
      'todayAlmanacTitle',
      'todayUnitItem',
      'todayUnitTimes',
      'todayUnitCourseSection',
      'todayUnitPoint',
      'todayDiary',
      'todayDiaryWritten',
      'todayDiaryUnwritten',
      'todaySuggestions',
      'todaySuggestionsSubtitle',
      'todayAddedPrefix',
      'todayAddToToday',
      'todayTodos',
      'todayCompleted',
      'todayCourses',
      'todayCoursePeriodPrefix',
      'todayCoursePeriodSuffix',
      'todayUpcomingAnniversaries',
      'todayAnniversaryToday',
      'todayAnniversaryDaysPrefix',
      'todayActiveGoals',
      'todayGoalCreateSubtitle',
      'todayView',
      'todayProductivityScore',
      'todayProductivityWeekly',
      'todayProductivityFlat',
      'todayProductivitySubtitle',
      'todayProductivityCompletionRate',
      'diaryTitle',
      'diaryWrite',
      'diaryEmptyMessage',
      'diaryStatsTooltip',
      'diarySummaryTitle',
      'diarySummarySubtitle',
      'diarySummaryTotal',
      'diarySummaryThisMonth',
      'diarySummaryStreak',
      'diaryRecentTitle',
      'diaryRecentRecordsSuffix',
      'diaryEntryCountSuffix',
      'diaryMoodStatsTitle',
      'diaryNoData',
      'diaryAiInsights',
      'diaryAiDeepReviewTooltip',
      'diaryAiDeepReviewTitle',
      'diaryAiDisabled',
      'diaryAiReviewFailedPrefix',
      'diaryEditorDateTitle',
      'diaryEditorMoodPrompt',
      'diaryEditorWeather',
      'diaryEditorTagHint',
      'diaryEditorContentHint',
      'diaryMoodAwesome',
      'diaryMoodGood',
      'diaryMoodOkay',
      'diaryMoodBad',
      'diaryMoodTerrible',
      'diaryWeatherSunny',
      'diaryWeatherCloudy',
      'diaryWeatherOvercast',
      'diaryWeatherRain',
      'diaryWeatherSnow',
      'diaryWeatherWind',
      'diaryWeatherFog',
      'diaryWeatherThunder',
      'countdownTitle',
      'countdownEmpty',
      'countdownNearestEmpty',
      'countdownNearestPrefix',
      'countdownNearestDaysPrefix',
      'countdownSummaryTotal',
      'countdownSummaryWithin7Days',
      'countdownListTitle',
      'countdownListSubtitle',
      'countdownCategoryDefault',
      'countdownEditorEditTitle',
      'countdownEditorSubtitle',
      'countdownFieldTitle',
      'countdownFieldCategory',
      'countdownFieldTargetDate',
      'countdownFieldDueReminder',
      'countdownFieldRemindDays',
      'countdownFieldRemindTime',
      'countdownReminderClosed',
      'countdownReminderBeforePrefix',
      'countdownReminderBeforeSuffix',
      'countdownStatusPinned',
      'countdownStatusExpired',
      'countdownStatusSoon',
      'countdownStatusRunning',
      'countdownTargetPrefix',
      'countdownDaysElapsed',
      'countdownDaysRemaining',
      'anniversaryTitle',
      'anniversaryBirthday',
      'anniversaryCountdownShort',
      'anniversaryCustom',
      'anniversaryTabAll',
      'anniversaryUpcoming30Days',
      'anniversaryEmpty',
      'anniversaryUpcomingEmpty',
      'anniversaryDeleteTitle',
      'anniversaryDeleteContentSuffix',
      'anniversaryOccurrencePrefix',
      'anniversaryOccurrenceSuffix',
      'anniversaryYearsElapsedPrefix',
      'anniversaryYearsElapsedSuffix',
      'anniversaryNextPrefix',
      'anniversaryTodayShort',
      'anniversaryStatusToday',
      'anniversaryStatusSoon',
      'anniversaryStatusUpcoming',
      'anniversaryDateOriginPrefix',
      'anniversaryEditorAddTitle',
      'anniversaryEditorEditTitle',
      'anniversaryFieldTitle',
      'anniversaryFieldTitleHint',
      'anniversaryFieldDescription',
      'anniversaryFieldType',
      'anniversaryFieldDateType',
      'anniversaryFieldDatePickerTitle',
      'anniversaryFieldDatePickerSubtitle',
      'anniversaryFieldColor',
      'anniversaryReminderCardPrefix',
      'anniversaryLunarYearSuffix',
      'reminderKindEmail',
      'courseWeekPrefix',
      'courseWeekSuffix',
      'courseWeekCountSuffix',
      'courseWeekCurrentTooltip',
      'courseEmptyMessage',
      'courseAdd',
      'courseWeekPickerTitle',
      'courseWeekPickerSubtitle',
      'courseWeeksAll',
      'courseWeeksOdd',
      'courseWeeksEven',
      'courseWeeksSelectAll',
      'courseSettingsTitle',
      'courseSettingsSubtitle',
      'courseSettingsPreviewPrefix',
      'courseEditorAddTitle',
      'courseEditorEditTitle',
      'courseEditorSubtitle',
      'courseFieldTermStart',
      'courseFieldTermStartPicker',
      'courseFieldTotalWeeks',
      'courseFieldSessionsPerDay',
      'courseFieldSessionMinutes',
      'courseFieldFirstSessionTime',
      'courseFieldFirstSessionTimeSubtitle',
      'courseFieldBreakMinutes',
      'courseFieldName',
      'courseFieldTeacher',
      'courseFieldLocation',
      'courseFieldWeekday',
      'courseFieldStartSection',
      'courseFieldSectionCount',
      'courseFieldClassWeeks',
      'courseFieldColor',
      'todoEmpty',
      'todoMatrix',
      'todoPriorityNone',
      'todoPriorityUrgent',
      'calendarMonth',
      'focusStart',
      'reminderHealth',
      'timeAuditTitle',
      'shareTitle',
      'unitMinute',
      'repeatEveryDay',
    ]) {
      expect(zh, contains('"$key"'), reason: 'zh ARB 缺少 $key');
      expect(en, contains('"$key"'), reason: 'en ARB 缺少 $key');
    }
    expect(en, contains('Chinese Lunar Calendar'));
  });

  test('I18n 兼容层所有词条都有官方 ARB 覆盖', () {
    final i18nSource = File('lib/core/i18n.dart').readAsStringSync();
    final zhArb = _arbKeys('lib/l10n/app_zh.arb');
    final enArb = _arbKeys('lib/l10n/app_en.arb');
    final i18nKeys = _i18nKeys(i18nSource);

    expect(i18nKeys, isNotEmpty);
    for (final key in i18nKeys) {
      final arbKey = _arbKeyForI18nKey(key);
      expect(zhArb, contains(arbKey), reason: 'zh ARB 缺少 $key -> $arbKey');
      expect(enArb, contains(arbKey), reason: 'en ARB 缺少 $key -> $arbKey');
    }
  });

  test('ARB 生成类与 I18n 兼容层的高频词条保持一致', () {
    final zh = AppLocalizationsZh();
    final en = AppLocalizationsEn();

    final pairs = <String, ({String zh, String en})>{
      'nav.today': (zh: zh.navToday, en: en.navToday),
      'nav.todo': (zh: zh.navTodo, en: en.navTodo),
      'nav.habit': (zh: zh.navHabit, en: en.navHabit),
      'nav.calendar': (zh: zh.navCalendar, en: en.navCalendar),
      'nav.focus': (zh: zh.navFocus, en: en.navFocus),
      'nav.widget': (zh: zh.navWidget, en: en.navWidget),
      'nav.mine': (zh: zh.navMine, en: en.navMine),
      'action.confirm': (zh: zh.actionConfirm, en: en.actionConfirm),
      'action.cancel': (zh: zh.actionCancel, en: en.actionCancel),
      'action.save': (zh: zh.actionSave, en: en.actionSave),
      'action.delete': (zh: zh.actionDelete, en: en.actionDelete),
      'action.add': (zh: zh.actionAdd, en: en.actionAdd),
      'action.create': (zh: zh.actionCreate, en: en.actionCreate),
      'action.clear': (zh: zh.actionClear, en: en.actionClear),
      'action.close': (zh: zh.actionClose, en: en.actionClose),
      'weekday.mon': (zh: zh.weekdayMon, en: en.weekdayMon),
      'weekday.sun': (zh: zh.weekdaySun, en: en.weekdaySun),
      'calendar.solar': (zh: zh.calendarSolar, en: en.calendarSolar),
      'calendar.lunar': (zh: zh.calendarLunar, en: en.calendarLunar),
      'calendar.chinese_lunar': (
        zh: zh.calendarChineseLunar,
        en: en.calendarChineseLunar,
      ),
      'calendar.chinese_lunar_calendar': (
        zh: zh.calendarChineseLunarCalendar,
        en: en.calendarChineseLunarCalendar,
      ),
      'calendar.corresponding_lunar': (
        zh: zh.calendarCorrespondingLunar,
        en: en.calendarCorrespondingLunar,
      ),
      'calendar.corresponding_solar': (
        zh: zh.calendarCorrespondingSolar,
        en: en.calendarCorrespondingSolar,
      ),
      'calendar_event.event': (
        zh: zh.calendarEventEvent,
        en: en.calendarEventEvent,
      ),
      'calendar_event.todo': (
        zh: zh.calendarEventTodo,
        en: en.calendarEventTodo,
      ),
      'calendar_event.time_entry': (
        zh: zh.calendarEventTimeEntry,
        en: en.calendarEventTimeEntry,
      ),
      'time_entry.source.manual': (
        zh: zh.timeEntrySourceManual,
        en: en.timeEntrySourceManual,
      ),
      'time_entry.source.pomodoro': (
        zh: zh.timeEntrySourcePomodoro,
        en: en.timeEntrySourcePomodoro,
      ),
      'time_entry.category.focus': (
        zh: zh.timeEntryCategoryFocus,
        en: en.timeEntryCategoryFocus,
      ),
      'time_entry.category.other': (
        zh: zh.timeEntryCategoryOther,
        en: en.timeEntryCategoryOther,
      ),
      'settings.language.zh': (
        zh: zh.settingsLanguageZh,
        en: en.settingsLanguageZh,
      ),
      'settings.language.en': (
        zh: zh.settingsLanguageEn,
        en: en.settingsLanguageEn,
      ),
      'settings.language.description': (
        zh: zh.settingsLanguageDescription,
        en: en.settingsLanguageDescription,
      ),
      'preferences.title': (zh: zh.preferencesTitle, en: en.preferencesTitle),
      'preferences.local.title': (
        zh: zh.preferencesLocalTitle,
        en: en.preferencesLocalTitle,
      ),
      'preferences.local.subtitle': (
        zh: zh.preferencesLocalSubtitle,
        en: en.preferencesLocalSubtitle,
      ),
      'preferences.section.date': (
        zh: zh.preferencesSectionDate,
        en: en.preferencesSectionDate,
      ),
      'preferences.section.date.subtitle': (
        zh: zh.preferencesSectionDateSubtitle,
        en: en.preferencesSectionDateSubtitle,
      ),
      'preferences.first_day.title': (
        zh: zh.preferencesFirstDayTitle,
        en: en.preferencesFirstDayTitle,
      ),
      'preferences.first_day.current_monday': (
        zh: zh.preferencesFirstDayCurrentMonday,
        en: en.preferencesFirstDayCurrentMonday,
      ),
      'preferences.first_day.current_sunday': (
        zh: zh.preferencesFirstDayCurrentSunday,
        en: en.preferencesFirstDayCurrentSunday,
      ),
      'preferences.date_format.title': (
        zh: zh.preferencesDateFormatTitle,
        en: en.preferencesDateFormatTitle,
      ),
      'preferences.timezone.title': (
        zh: zh.preferencesTimezoneTitle,
        en: en.preferencesTimezoneTitle,
      ),
      'preferences.timezone.follow_system': (
        zh: zh.preferencesTimezoneFollowSystem,
        en: en.preferencesTimezoneFollowSystem,
      ),
      'preferences.lunar.title': (
        zh: zh.preferencesLunarTitle,
        en: en.preferencesLunarTitle,
      ),
      'preferences.lunar.subtitle': (
        zh: zh.preferencesLunarSubtitle,
        en: en.preferencesLunarSubtitle,
      ),
      'preferences.section.defaults': (
        zh: zh.preferencesSectionDefaults,
        en: en.preferencesSectionDefaults,
      ),
      'preferences.section.defaults.subtitle': (
        zh: zh.preferencesSectionDefaultsSubtitle,
        en: en.preferencesSectionDefaultsSubtitle,
      ),
      'preferences.default_tab.title': (
        zh: zh.preferencesDefaultTabTitle,
        en: en.preferencesDefaultTabTitle,
      ),
      'preferences.quick_capture.title': (
        zh: zh.preferencesQuickCaptureTitle,
        en: en.preferencesQuickCaptureTitle,
      ),
      'preferences.quick_capture.subtitle': (
        zh: zh.preferencesQuickCaptureSubtitle,
        en: en.preferencesQuickCaptureSubtitle,
      ),
      'preferences.notification_quick_add.title': (
        zh: zh.preferencesNotificationQuickAddTitle,
        en: en.preferencesNotificationQuickAddTitle,
      ),
      'preferences.notification_quick_add.subtitle': (
        zh: zh.preferencesNotificationQuickAddSubtitle,
        en: en.preferencesNotificationQuickAddSubtitle,
      ),
      'preferences.show_completed.title': (
        zh: zh.preferencesShowCompletedTitle,
        en: en.preferencesShowCompletedTitle,
      ),
      'preferences.show_completed.subtitle': (
        zh: zh.preferencesShowCompletedSubtitle,
        en: en.preferencesShowCompletedSubtitle,
      ),
      'preferences.pomodoro_length.title': (
        zh: zh.preferencesPomodoroLengthTitle,
        en: en.preferencesPomodoroLengthTitle,
      ),
      'preferences.section.bottom_nav': (
        zh: zh.preferencesSectionBottomNav,
        en: en.preferencesSectionBottomNav,
      ),
      'preferences.section.bottom_nav.subtitle': (
        zh: zh.preferencesSectionBottomNavSubtitle,
        en: en.preferencesSectionBottomNavSubtitle,
      ),
      'preferences.section.interaction': (
        zh: zh.preferencesSectionInteraction,
        en: en.preferencesSectionInteraction,
      ),
      'preferences.section.interaction.subtitle': (
        zh: zh.preferencesSectionInteractionSubtitle,
        en: en.preferencesSectionInteractionSubtitle,
      ),
      'preferences.haptic.title': (
        zh: zh.preferencesHapticTitle,
        en: en.preferencesHapticTitle,
      ),
      'preferences.haptic.subtitle': (
        zh: zh.preferencesHapticSubtitle,
        en: en.preferencesHapticSubtitle,
      ),
      'preferences.section.auto_archive': (
        zh: zh.preferencesSectionAutoArchive,
        en: en.preferencesSectionAutoArchive,
      ),
      'preferences.section.auto_archive.subtitle': (
        zh: zh.preferencesSectionAutoArchiveSubtitle,
        en: en.preferencesSectionAutoArchiveSubtitle,
      ),
      'preferences.auto_archive.title': (
        zh: zh.preferencesAutoArchiveTitle,
        en: en.preferencesAutoArchiveTitle,
      ),
      'preferences.auto_archive.never': (
        zh: zh.preferencesAutoArchiveNever,
        en: en.preferencesAutoArchiveNever,
      ),
      'preferences.auto_archive.after_days': (
        zh: zh.preferencesAutoArchiveAfterDays,
        en: en.preferencesAutoArchiveAfterDays,
      ),
      'preferences.section.daily_reminder': (
        zh: zh.preferencesSectionDailyReminder,
        en: en.preferencesSectionDailyReminder,
      ),
      'preferences.section.daily_reminder.subtitle': (
        zh: zh.preferencesSectionDailyReminderSubtitle,
        en: en.preferencesSectionDailyReminderSubtitle,
      ),
      'preferences.nav.fixed': (
        zh: zh.preferencesNavFixed,
        en: en.preferencesNavFixed,
      ),
      'preferences.nav.visible': (
        zh: zh.preferencesNavVisible,
        en: en.preferencesNavVisible,
      ),
      'preferences.nav.hidden': (
        zh: zh.preferencesNavHidden,
        en: en.preferencesNavHidden,
      ),
      'preferences.notify.permission_denied': (
        zh: zh.preferencesNotifyPermissionDenied,
        en: en.preferencesNotifyPermissionDenied,
      ),
      'preferences.notify.exact_alarm_granted': (
        zh: zh.preferencesNotifyExactAlarmGranted,
        en: en.preferencesNotifyExactAlarmGranted,
      ),
      'preferences.notify.exact_alarm_denied': (
        zh: zh.preferencesNotifyExactAlarmDenied,
        en: en.preferencesNotifyExactAlarmDenied,
      ),
      'preferences.notify.full_screen_granted': (
        zh: zh.preferencesNotifyFullScreenGranted,
        en: en.preferencesNotifyFullScreenGranted,
      ),
      'preferences.notify.full_screen_denied': (
        zh: zh.preferencesNotifyFullScreenDenied,
        en: en.preferencesNotifyFullScreenDenied,
      ),
      'preferences.notify.test_permission_denied': (
        zh: zh.preferencesNotifyTestPermissionDenied,
        en: en.preferencesNotifyTestPermissionDenied,
      ),
      'preferences.notify.test_failed': (
        zh: zh.preferencesNotifyTestFailed,
        en: en.preferencesNotifyTestFailed,
      ),
      'preferences.notify.test_sent': (
        zh: zh.preferencesNotifyTestSent,
        en: en.preferencesNotifyTestSent,
      ),
      'preferences.notify.pending_cleared': (
        zh: zh.preferencesNotifyPendingCleared,
        en: en.preferencesNotifyPendingCleared,
      ),
      'preferences.notify.open_settings_failed': (
        zh: zh.preferencesNotifyOpenSettingsFailed,
        en: en.preferencesNotifyOpenSettingsFailed,
      ),
      'preferences.ringtone.section': (
        zh: zh.preferencesRingtoneSection,
        en: en.preferencesRingtoneSection,
      ),
      'preferences.ringtone.section.subtitle': (
        zh: zh.preferencesRingtoneSectionSubtitle,
        en: en.preferencesRingtoneSectionSubtitle,
      ),
      'preferences.ringtone.section.subtitle.android': (
        zh: zh.preferencesRingtoneSectionSubtitleAndroid,
        en: en.preferencesRingtoneSectionSubtitleAndroid,
      ),
      'preferences.ringtone.section.subtitle.apple': (
        zh: zh.preferencesRingtoneSectionSubtitleApple,
        en: en.preferencesRingtoneSectionSubtitleApple,
      ),
      'preferences.ringtone.section.subtitle.desktop': (
        zh: zh.preferencesRingtoneSectionSubtitleDesktop,
        en: en.preferencesRingtoneSectionSubtitleDesktop,
      ),
      'preferences.ringtone.section.subtitle.unsupported': (
        zh: zh.preferencesRingtoneSectionSubtitleUnsupported,
        en: en.preferencesRingtoneSectionSubtitleUnsupported,
      ),
      'preferences.ringtone.sound': (
        zh: zh.preferencesRingtoneSound,
        en: en.preferencesRingtoneSound,
      ),
      'preferences.ringtone.volume': (
        zh: zh.preferencesRingtoneVolume,
        en: en.preferencesRingtoneVolume,
      ),
      'preferences.ringtone.current': (
        zh: zh.preferencesRingtoneCurrent,
        en: en.preferencesRingtoneCurrent,
      ),
      'preferences.ringtone.system_sound': (
        zh: zh.preferencesRingtoneSystemSound,
        en: en.preferencesRingtoneSystemSound,
      ),
      'preferences.ringtone.system_sound.subtitle.apple': (
        zh: zh.preferencesRingtoneSystemSoundSubtitleApple,
        en: en.preferencesRingtoneSystemSoundSubtitleApple,
      ),
      'preferences.ringtone.system_sound.subtitle.desktop': (
        zh: zh.preferencesRingtoneSystemSoundSubtitleDesktop,
        en: en.preferencesRingtoneSystemSoundSubtitleDesktop,
      ),
      'preferences.ringtone.unsupported': (
        zh: zh.preferencesRingtoneUnsupported,
        en: en.preferencesRingtoneUnsupported,
      ),
      'preferences.ringtone.unsupported.subtitle': (
        zh: zh.preferencesRingtoneUnsupportedSubtitle,
        en: en.preferencesRingtoneUnsupportedSubtitle,
      ),
      'preferences.daily_reminder.one': (
        zh: zh.preferencesDailyReminderOne,
        en: en.preferencesDailyReminderOne,
      ),
      'preferences.daily_reminder.two': (
        zh: zh.preferencesDailyReminderTwo,
        en: en.preferencesDailyReminderTwo,
      ),
      'preferences.daily_reminder.three': (
        zh: zh.preferencesDailyReminderThree,
        en: en.preferencesDailyReminderThree,
      ),
      'preferences.daily_reminder.disabled': (
        zh: zh.preferencesDailyReminderDisabled,
        en: en.preferencesDailyReminderDisabled,
      ),
      'preferences.daily_reminder.time': (
        zh: zh.preferencesDailyReminderTime,
        en: en.preferencesDailyReminderTime,
      ),
      'preferences.daily_reminder.time.subtitle': (
        zh: zh.preferencesDailyReminderTimeSubtitle,
        en: en.preferencesDailyReminderTimeSubtitle,
      ),
      'preferences.daily_reminder.time_suffix': (
        zh: zh.preferencesDailyReminderTimeSuffix,
        en: en.preferencesDailyReminderTimeSuffix,
      ),
      'preferences.daily_reminder.time_picker.subtitle': (
        zh: zh.preferencesDailyReminderTimePickerSubtitle,
        en: en.preferencesDailyReminderTimePickerSubtitle,
      ),
      'preferences.daily_reminder.today_tasks': (
        zh: zh.preferencesDailyReminderTodayTasks,
        en: en.preferencesDailyReminderTodayTasks,
      ),
      'preferences.daily_reminder.today_tasks.subtitle': (
        zh: zh.preferencesDailyReminderTodayTasksSubtitle,
        en: en.preferencesDailyReminderTodayTasksSubtitle,
      ),
      'preferences.daily_reminder.tomorrow_plan': (
        zh: zh.preferencesDailyReminderTomorrowPlan,
        en: en.preferencesDailyReminderTomorrowPlan,
      ),
      'preferences.daily_reminder.tomorrow_plan.subtitle': (
        zh: zh.preferencesDailyReminderTomorrowPlanSubtitle,
        en: en.preferencesDailyReminderTomorrowPlanSubtitle,
      ),
      'preferences.daily_reminder.overdue_tasks': (
        zh: zh.preferencesDailyReminderOverdueTasks,
        en: en.preferencesDailyReminderOverdueTasks,
      ),
      'preferences.daily_reminder.overdue_tasks.subtitle': (
        zh: zh.preferencesDailyReminderOverdueTasksSubtitle,
        en: en.preferencesDailyReminderOverdueTasksSubtitle,
      ),
      'preferences.daily_reminder.pause_holidays': (
        zh: zh.preferencesDailyReminderPauseHolidays,
        en: en.preferencesDailyReminderPauseHolidays,
      ),
      'preferences.daily_reminder.pause_holidays.subtitle': (
        zh: zh.preferencesDailyReminderPauseHolidaysSubtitle,
        en: en.preferencesDailyReminderPauseHolidaysSubtitle,
      ),
      'preferences.daily_reminder.scope.today': (
        zh: zh.preferencesDailyReminderScopeToday,
        en: en.preferencesDailyReminderScopeToday,
      ),
      'preferences.daily_reminder.scope.overdue': (
        zh: zh.preferencesDailyReminderScopeOverdue,
        en: en.preferencesDailyReminderScopeOverdue,
      ),
      'preferences.daily_reminder.scope.tomorrow': (
        zh: zh.preferencesDailyReminderScopeTomorrow,
        en: en.preferencesDailyReminderScopeTomorrow,
      ),
      'preferences.daily_reminder.scope.none': (
        zh: zh.preferencesDailyReminderScopeNone,
        en: en.preferencesDailyReminderScopeNone,
      ),
      'quick.todo.title': (zh: zh.quickTodoTitle, en: en.quickTodoTitle),
      'quick.todo.hint': (zh: zh.quickTodoHint, en: en.quickTodoHint),
      'quick.todo.parsed_prefix': (
        zh: zh.quickTodoParsedPrefix,
        en: en.quickTodoParsedPrefix,
      ),
      'quick.ai.title': (zh: zh.quickAiTitle, en: en.quickAiTitle),
      'quick.ai.hint': (zh: zh.quickAiHint, en: en.quickAiHint),
      'quick.ai.error': (zh: zh.quickAiError, en: en.quickAiError),
      'quick.note.title': (zh: zh.quickNoteTitle, en: en.quickNoteTitle),
      'quick.note.hint': (zh: zh.quickNoteHint, en: en.quickNoteHint),
      'quick.menu.ai_schedule': (
        zh: zh.quickMenuAiSchedule,
        en: en.quickMenuAiSchedule,
      ),
      'quick.menu.search': (zh: zh.quickMenuSearch, en: en.quickMenuSearch),
      'quick.menu.diary': (zh: zh.quickMenuDiary, en: en.quickMenuDiary),
      'quick.menu.note': (zh: zh.quickMenuNote, en: en.quickMenuNote),
      'quick.menu.todo': (zh: zh.quickMenuTodo, en: en.quickMenuTodo),
      'quick.menu.template': (
        zh: zh.quickMenuTemplate,
        en: en.quickMenuTemplate,
      ),
      'quick.template.title': (
        zh: zh.quickTemplateTitle,
        en: en.quickTemplateTitle,
      ),
      'quick.template.subtitle': (
        zh: zh.quickTemplateSubtitle,
        en: en.quickTemplateSubtitle,
      ),
      'quick.template.save': (
        zh: zh.quickTemplateSave,
        en: en.quickTemplateSave,
      ),
      'quick.template.kind.todo': (
        zh: zh.quickTemplateKindTodo,
        en: en.quickTemplateKindTodo,
      ),
      'quick.template.kind.habit': (
        zh: zh.quickTemplateKindHabit,
        en: en.quickTemplateKindHabit,
      ),
      'quick.template.reminder15': (
        zh: zh.quickTemplateReminder15,
        en: en.quickTemplateReminder15,
      ),
      'quick.template.todo_done': (
        zh: zh.quickTemplateTodoDone,
        en: en.quickTemplateTodoDone,
      ),
      'quick.template.habit_done': (
        zh: zh.quickTemplateHabitDone,
        en: en.quickTemplateHabitDone,
      ),
      'search.hint': (zh: zh.searchHint, en: en.searchHint),
      'search.empty': (zh: zh.searchEmpty, en: en.searchEmpty),
      'search.no_results.prefix': (
        zh: zh.searchNoResultsPrefix,
        en: en.searchNoResultsPrefix,
      ),
      'search.no_results.suffix': (
        zh: zh.searchNoResultsSuffix,
        en: en.searchNoResultsSuffix,
      ),
      'search.results.title': (
        zh: zh.searchResultsTitle,
        en: en.searchResultsTitle,
      ),
      'search.results.summary_prefix': (
        zh: zh.searchResultsSummaryPrefix,
        en: en.searchResultsSummaryPrefix,
      ),
      'search.results.summary_middle': (
        zh: zh.searchResultsSummaryMiddle,
        en: en.searchResultsSummaryMiddle,
      ),
      'search.results.summary_suffix': (
        zh: zh.searchResultsSummarySuffix,
        en: en.searchResultsSummarySuffix,
      ),
      'search.clear': (zh: zh.searchClear, en: en.searchClear),
      'search.kind.todo': (zh: zh.searchKindTodo, en: en.searchKindTodo),
      'search.kind.habit': (zh: zh.searchKindHabit, en: en.searchKindHabit),
      'search.kind.note': (zh: zh.searchKindNote, en: en.searchKindNote),
      'search.kind.diary': (zh: zh.searchKindDiary, en: en.searchKindDiary),
      'search.kind.anniversary': (
        zh: zh.searchKindAnniversary,
        en: en.searchKindAnniversary,
      ),
      'search.kind.countdown': (
        zh: zh.searchKindCountdown,
        en: en.searchKindCountdown,
      ),
      'search.kind.goal': (zh: zh.searchKindGoal, en: en.searchKindGoal),
      'search.kind.course': (zh: zh.searchKindCourse, en: en.searchKindCourse),
      'search.kind.event': (zh: zh.searchKindEvent, en: en.searchKindEvent),
      'search.kind.time_entry': (
        zh: zh.searchKindTimeEntry,
        en: en.searchKindTimeEntry,
      ),
      'auth.login.title': (zh: zh.authLoginTitle, en: en.authLoginTitle),
      'auth.register.title': (
        zh: zh.authRegisterTitle,
        en: en.authRegisterTitle,
      ),
      'auth.password_login': (
        zh: zh.authPasswordLogin,
        en: en.authPasswordLogin,
      ),
      'auth.email_code_login': (
        zh: zh.authEmailCodeLogin,
        en: en.authEmailCodeLogin,
      ),
      'auth.reset_account': (zh: zh.authResetAccount, en: en.authResetAccount),
      'auth.error.username_length': (
        zh: zh.authErrorUsernameLength,
        en: en.authErrorUsernameLength,
      ),
      'auth.error.new_password_mismatch': (
        zh: zh.authErrorNewPasswordMismatch,
        en: en.authErrorNewPasswordMismatch,
      ),
      'profile.title': (zh: zh.profileTitle, en: en.profileTitle),
      'profile.avatar.url_file_or_text': (
        zh: zh.profileAvatarUrlFileOrText,
        en: en.profileAvatarUrlFileOrText,
      ),
      'profile.change_password': (
        zh: zh.profileChangePassword,
        en: en.profileChangePassword,
      ),
      'profile.confirm_new_password': (
        zh: zh.profileConfirmNewPassword,
        en: en.profileConfirmNewPassword,
      ),
      'note.title': (zh: zh.noteTitle, en: en.noteTitle),
      'note.empty.message': (zh: zh.noteEmptyMessage, en: en.noteEmptyMessage),
      'note.attachment.pick_file': (
        zh: zh.noteAttachmentPickFile,
        en: en.noteAttachmentPickFile,
      ),
      'note.editor.hint': (zh: zh.noteEditorHint, en: en.noteEditorHint),
      'note.toolbar.bold': (zh: zh.noteToolbarBold, en: en.noteToolbarBold),
      'note.preview.empty': (zh: zh.notePreviewEmpty, en: en.notePreviewEmpty),
      'feedback.category.feature': (
        zh: zh.feedbackCategoryFeature,
        en: en.feedbackCategoryFeature,
      ),
      'feedback.status.in_progress': (
        zh: zh.feedbackStatusInProgress,
        en: en.feedbackStatusInProgress,
      ),
      'feedback.submit.button': (
        zh: zh.feedbackSubmitButton,
        en: en.feedbackSubmitButton,
      ),
      'feedback.admin_reply': (
        zh: zh.feedbackAdminReply,
        en: en.feedbackAdminReply,
      ),
      'announcement.title': (
        zh: zh.announcementTitle,
        en: en.announcementTitle,
      ),
      'announcement.level.critical': (
        zh: zh.announcementLevelCritical,
        en: en.announcementLevelCritical,
      ),
      'announcement.empty': (
        zh: zh.announcementEmpty,
        en: en.announcementEmpty,
      ),
      'theme.title': (zh: zh.themeTitle, en: en.themeTitle),
      'theme.style.default.name': (
        zh: zh.themeStyleDefaultName,
        en: en.themeStyleDefaultName,
      ),
      'theme.style.star_rail.description': (
        zh: zh.themeStyleStarRailDescription,
        en: en.themeStyleStarRailDescription,
      ),
      'goal.title': (zh: zh.goalTitle, en: en.goalTitle),
      'goal.status.active': (zh: zh.goalStatusActive, en: en.goalStatusActive),
      'goal.days_remaining.suffix': (
        zh: zh.goalDaysRemainingSuffix,
        en: en.goalDaysRemainingSuffix,
      ),
      'export.title': (zh: zh.exportTitle, en: en.exportTitle),
      'export.push_caldav': (zh: zh.exportPushCaldav, en: en.exportPushCaldav),
      'export.caldav.failed_prefix': (
        zh: zh.exportCaldavFailedPrefix,
        en: en.exportCaldavFailedPrefix,
      ),
      'app_lock.title': (zh: zh.appLockTitle, en: en.appLockTitle),
      'app_lock.auto_lock': (zh: zh.appLockAutoLock, en: en.appLockAutoLock),
      'app_lock.pin_invalid': (
        zh: zh.appLockPinInvalid,
        en: en.appLockPinInvalid,
      ),
      'ai_history.title': (zh: zh.aiHistoryTitle, en: en.aiHistoryTitle),
      'ai_history.clear.action': (
        zh: zh.aiHistoryClearAction,
        en: en.aiHistoryClearAction,
      ),
      'ai_history.empty': (zh: zh.aiHistoryEmpty, en: en.aiHistoryEmpty),
      'ai_history.expand': (zh: zh.aiHistoryExpand, en: en.aiHistoryExpand),
      'ai_history.collapse': (
        zh: zh.aiHistoryCollapse,
        en: en.aiHistoryCollapse,
      ),
      'sync_conflict.title': (
        zh: zh.syncConflictTitle,
        en: en.syncConflictTitle,
      ),
      'sync_conflict.empty': (
        zh: zh.syncConflictEmpty,
        en: en.syncConflictEmpty,
      ),
      'sync_conflict.keep_remote': (
        zh: zh.syncConflictKeepRemote,
        en: en.syncConflictKeepRemote,
      ),
      'today.almanac.title': (
        zh: zh.todayAlmanacTitle,
        en: en.todayAlmanacTitle,
      ),
      'today.unit.item': (zh: zh.todayUnitItem, en: en.todayUnitItem),
      'today.unit.times': (zh: zh.todayUnitTimes, en: en.todayUnitTimes),
      'today.unit.course_section': (
        zh: zh.todayUnitCourseSection,
        en: en.todayUnitCourseSection,
      ),
      'today.unit.point': (zh: zh.todayUnitPoint, en: en.todayUnitPoint),
      'today.diary': (zh: zh.todayDiary, en: en.todayDiary),
      'today.diary.written': (
        zh: zh.todayDiaryWritten,
        en: en.todayDiaryWritten,
      ),
      'today.diary.unwritten': (
        zh: zh.todayDiaryUnwritten,
        en: en.todayDiaryUnwritten,
      ),
      'today.suggestions': (zh: zh.todaySuggestions, en: en.todaySuggestions),
      'today.suggestions.subtitle': (
        zh: zh.todaySuggestionsSubtitle,
        en: en.todaySuggestionsSubtitle,
      ),
      'today.added_prefix': (zh: zh.todayAddedPrefix, en: en.todayAddedPrefix),
      'today.add_to_today': (zh: zh.todayAddToToday, en: en.todayAddToToday),
      'today.todos': (zh: zh.todayTodos, en: en.todayTodos),
      'today.completed': (zh: zh.todayCompleted, en: en.todayCompleted),
      'today.courses': (zh: zh.todayCourses, en: en.todayCourses),
      'today.course.period_prefix': (
        zh: zh.todayCoursePeriodPrefix,
        en: en.todayCoursePeriodPrefix,
      ),
      'today.course.period_suffix': (
        zh: zh.todayCoursePeriodSuffix,
        en: en.todayCoursePeriodSuffix,
      ),
      'today.upcoming_anniversaries': (
        zh: zh.todayUpcomingAnniversaries,
        en: en.todayUpcomingAnniversaries,
      ),
      'today.anniversary.today': (
        zh: zh.todayAnniversaryToday,
        en: en.todayAnniversaryToday,
      ),
      'today.anniversary.days_prefix': (
        zh: zh.todayAnniversaryDaysPrefix,
        en: en.todayAnniversaryDaysPrefix,
      ),
      'today.active_goals': (zh: zh.todayActiveGoals, en: en.todayActiveGoals),
      'today.goal.create.subtitle': (
        zh: zh.todayGoalCreateSubtitle,
        en: en.todayGoalCreateSubtitle,
      ),
      'today.view': (zh: zh.todayView, en: en.todayView),
      'today.productivity.score': (
        zh: zh.todayProductivityScore,
        en: en.todayProductivityScore,
      ),
      'today.productivity.weekly': (
        zh: zh.todayProductivityWeekly,
        en: en.todayProductivityWeekly,
      ),
      'today.productivity.flat': (
        zh: zh.todayProductivityFlat,
        en: en.todayProductivityFlat,
      ),
      'today.productivity.subtitle': (
        zh: zh.todayProductivitySubtitle,
        en: en.todayProductivitySubtitle,
      ),
      'today.productivity.completion_rate': (
        zh: zh.todayProductivityCompletionRate,
        en: en.todayProductivityCompletionRate,
      ),
      'diary.title': (zh: zh.diaryTitle, en: en.diaryTitle),
      'diary.write': (zh: zh.diaryWrite, en: en.diaryWrite),
      'diary.empty.message': (
        zh: zh.diaryEmptyMessage,
        en: en.diaryEmptyMessage,
      ),
      'diary.stats.tooltip': (
        zh: zh.diaryStatsTooltip,
        en: en.diaryStatsTooltip,
      ),
      'diary.summary.title': (
        zh: zh.diarySummaryTitle,
        en: en.diarySummaryTitle,
      ),
      'diary.summary.subtitle': (
        zh: zh.diarySummarySubtitle,
        en: en.diarySummarySubtitle,
      ),
      'diary.summary.total': (
        zh: zh.diarySummaryTotal,
        en: en.diarySummaryTotal,
      ),
      'diary.summary.this_month': (
        zh: zh.diarySummaryThisMonth,
        en: en.diarySummaryThisMonth,
      ),
      'diary.summary.streak': (
        zh: zh.diarySummaryStreak,
        en: en.diarySummaryStreak,
      ),
      'diary.recent.title': (zh: zh.diaryRecentTitle, en: en.diaryRecentTitle),
      'diary.recent.records_suffix': (
        zh: zh.diaryRecentRecordsSuffix,
        en: en.diaryRecentRecordsSuffix,
      ),
      'diary.entry.count_suffix': (
        zh: zh.diaryEntryCountSuffix,
        en: en.diaryEntryCountSuffix,
      ),
      'diary.mood.stats.title': (
        zh: zh.diaryMoodStatsTitle,
        en: en.diaryMoodStatsTitle,
      ),
      'diary.no_data': (zh: zh.diaryNoData, en: en.diaryNoData),
      'diary.ai.insights': (zh: zh.diaryAiInsights, en: en.diaryAiInsights),
      'diary.ai.deep_review.tooltip': (
        zh: zh.diaryAiDeepReviewTooltip,
        en: en.diaryAiDeepReviewTooltip,
      ),
      'diary.ai.deep_review.title': (
        zh: zh.diaryAiDeepReviewTitle,
        en: en.diaryAiDeepReviewTitle,
      ),
      'diary.ai.disabled': (zh: zh.diaryAiDisabled, en: en.diaryAiDisabled),
      'diary.ai.review_failed_prefix': (
        zh: zh.diaryAiReviewFailedPrefix,
        en: en.diaryAiReviewFailedPrefix,
      ),
      'diary.editor.date_title': (
        zh: zh.diaryEditorDateTitle,
        en: en.diaryEditorDateTitle,
      ),
      'diary.editor.mood_prompt': (
        zh: zh.diaryEditorMoodPrompt,
        en: en.diaryEditorMoodPrompt,
      ),
      'diary.editor.weather': (
        zh: zh.diaryEditorWeather,
        en: en.diaryEditorWeather,
      ),
      'diary.editor.tag_hint': (
        zh: zh.diaryEditorTagHint,
        en: en.diaryEditorTagHint,
      ),
      'diary.editor.content_hint': (
        zh: zh.diaryEditorContentHint,
        en: en.diaryEditorContentHint,
      ),
      'diary.mood.awesome': (zh: zh.diaryMoodAwesome, en: en.diaryMoodAwesome),
      'diary.mood.good': (zh: zh.diaryMoodGood, en: en.diaryMoodGood),
      'diary.mood.okay': (zh: zh.diaryMoodOkay, en: en.diaryMoodOkay),
      'diary.mood.bad': (zh: zh.diaryMoodBad, en: en.diaryMoodBad),
      'diary.mood.terrible': (
        zh: zh.diaryMoodTerrible,
        en: en.diaryMoodTerrible,
      ),
      'diary.weather.sunny': (
        zh: zh.diaryWeatherSunny,
        en: en.diaryWeatherSunny,
      ),
      'diary.weather.cloudy': (
        zh: zh.diaryWeatherCloudy,
        en: en.diaryWeatherCloudy,
      ),
      'diary.weather.overcast': (
        zh: zh.diaryWeatherOvercast,
        en: en.diaryWeatherOvercast,
      ),
      'diary.weather.rain': (zh: zh.diaryWeatherRain, en: en.diaryWeatherRain),
      'diary.weather.snow': (zh: zh.diaryWeatherSnow, en: en.diaryWeatherSnow),
      'diary.weather.wind': (zh: zh.diaryWeatherWind, en: en.diaryWeatherWind),
      'diary.weather.fog': (zh: zh.diaryWeatherFog, en: en.diaryWeatherFog),
      'diary.weather.thunder': (
        zh: zh.diaryWeatherThunder,
        en: en.diaryWeatherThunder,
      ),
      'countdown.title': (zh: zh.countdownTitle, en: en.countdownTitle),
      'countdown.empty': (zh: zh.countdownEmpty, en: en.countdownEmpty),
      'countdown.nearest.empty': (
        zh: zh.countdownNearestEmpty,
        en: en.countdownNearestEmpty,
      ),
      'countdown.nearest.prefix': (
        zh: zh.countdownNearestPrefix,
        en: en.countdownNearestPrefix,
      ),
      'countdown.nearest.days_prefix': (
        zh: zh.countdownNearestDaysPrefix,
        en: en.countdownNearestDaysPrefix,
      ),
      'countdown.summary.total': (
        zh: zh.countdownSummaryTotal,
        en: en.countdownSummaryTotal,
      ),
      'countdown.summary.within_7_days': (
        zh: zh.countdownSummaryWithin7Days,
        en: en.countdownSummaryWithin7Days,
      ),
      'countdown.list.title': (
        zh: zh.countdownListTitle,
        en: en.countdownListTitle,
      ),
      'countdown.list.subtitle': (
        zh: zh.countdownListSubtitle,
        en: en.countdownListSubtitle,
      ),
      'countdown.category.default': (
        zh: zh.countdownCategoryDefault,
        en: en.countdownCategoryDefault,
      ),
      'countdown.editor.edit_title': (
        zh: zh.countdownEditorEditTitle,
        en: en.countdownEditorEditTitle,
      ),
      'countdown.editor.subtitle': (
        zh: zh.countdownEditorSubtitle,
        en: en.countdownEditorSubtitle,
      ),
      'countdown.field.title': (
        zh: zh.countdownFieldTitle,
        en: en.countdownFieldTitle,
      ),
      'countdown.field.category': (
        zh: zh.countdownFieldCategory,
        en: en.countdownFieldCategory,
      ),
      'countdown.field.target_date': (
        zh: zh.countdownFieldTargetDate,
        en: en.countdownFieldTargetDate,
      ),
      'countdown.field.due_reminder': (
        zh: zh.countdownFieldDueReminder,
        en: en.countdownFieldDueReminder,
      ),
      'countdown.field.remind_days': (
        zh: zh.countdownFieldRemindDays,
        en: en.countdownFieldRemindDays,
      ),
      'countdown.field.remind_time': (
        zh: zh.countdownFieldRemindTime,
        en: en.countdownFieldRemindTime,
      ),
      'countdown.reminder.closed': (
        zh: zh.countdownReminderClosed,
        en: en.countdownReminderClosed,
      ),
      'countdown.reminder.before_prefix': (
        zh: zh.countdownReminderBeforePrefix,
        en: en.countdownReminderBeforePrefix,
      ),
      'countdown.reminder.before_suffix': (
        zh: zh.countdownReminderBeforeSuffix,
        en: en.countdownReminderBeforeSuffix,
      ),
      'countdown.status.pinned': (
        zh: zh.countdownStatusPinned,
        en: en.countdownStatusPinned,
      ),
      'countdown.status.expired': (
        zh: zh.countdownStatusExpired,
        en: en.countdownStatusExpired,
      ),
      'countdown.status.soon': (
        zh: zh.countdownStatusSoon,
        en: en.countdownStatusSoon,
      ),
      'countdown.status.running': (
        zh: zh.countdownStatusRunning,
        en: en.countdownStatusRunning,
      ),
      'countdown.target.prefix': (
        zh: zh.countdownTargetPrefix,
        en: en.countdownTargetPrefix,
      ),
      'countdown.days.elapsed': (
        zh: zh.countdownDaysElapsed,
        en: en.countdownDaysElapsed,
      ),
      'countdown.days.remaining': (
        zh: zh.countdownDaysRemaining,
        en: en.countdownDaysRemaining,
      ),
      'anniversary.title': (zh: zh.anniversaryTitle, en: en.anniversaryTitle),
      'anniversary.birthday': (
        zh: zh.anniversaryBirthday,
        en: en.anniversaryBirthday,
      ),
      'anniversary.countdown_short': (
        zh: zh.anniversaryCountdownShort,
        en: en.anniversaryCountdownShort,
      ),
      'anniversary.custom': (
        zh: zh.anniversaryCustom,
        en: en.anniversaryCustom,
      ),
      'anniversary.tab.all': (
        zh: zh.anniversaryTabAll,
        en: en.anniversaryTabAll,
      ),
      'anniversary.upcoming_30_days': (
        zh: zh.anniversaryUpcoming30Days,
        en: en.anniversaryUpcoming30Days,
      ),
      'anniversary.empty': (zh: zh.anniversaryEmpty, en: en.anniversaryEmpty),
      'anniversary.upcoming_empty': (
        zh: zh.anniversaryUpcomingEmpty,
        en: en.anniversaryUpcomingEmpty,
      ),
      'anniversary.delete.title': (
        zh: zh.anniversaryDeleteTitle,
        en: en.anniversaryDeleteTitle,
      ),
      'anniversary.delete.content_suffix': (
        zh: zh.anniversaryDeleteContentSuffix,
        en: en.anniversaryDeleteContentSuffix,
      ),
      'anniversary.occurrence.prefix': (
        zh: zh.anniversaryOccurrencePrefix,
        en: en.anniversaryOccurrencePrefix,
      ),
      'anniversary.occurrence.suffix': (
        zh: zh.anniversaryOccurrenceSuffix,
        en: en.anniversaryOccurrenceSuffix,
      ),
      'anniversary.years_elapsed.prefix': (
        zh: zh.anniversaryYearsElapsedPrefix,
        en: en.anniversaryYearsElapsedPrefix,
      ),
      'anniversary.years_elapsed.suffix': (
        zh: zh.anniversaryYearsElapsedSuffix,
        en: en.anniversaryYearsElapsedSuffix,
      ),
      'anniversary.next.prefix': (
        zh: zh.anniversaryNextPrefix,
        en: en.anniversaryNextPrefix,
      ),
      'anniversary.today_short': (
        zh: zh.anniversaryTodayShort,
        en: en.anniversaryTodayShort,
      ),
      'anniversary.status.today': (
        zh: zh.anniversaryStatusToday,
        en: en.anniversaryStatusToday,
      ),
      'anniversary.status.soon': (
        zh: zh.anniversaryStatusSoon,
        en: en.anniversaryStatusSoon,
      ),
      'anniversary.status.upcoming': (
        zh: zh.anniversaryStatusUpcoming,
        en: en.anniversaryStatusUpcoming,
      ),
      'anniversary.date.origin_prefix': (
        zh: zh.anniversaryDateOriginPrefix,
        en: en.anniversaryDateOriginPrefix,
      ),
      'anniversary.editor.add_title': (
        zh: zh.anniversaryEditorAddTitle,
        en: en.anniversaryEditorAddTitle,
      ),
      'anniversary.editor.edit_title': (
        zh: zh.anniversaryEditorEditTitle,
        en: en.anniversaryEditorEditTitle,
      ),
      'anniversary.field.title': (
        zh: zh.anniversaryFieldTitle,
        en: en.anniversaryFieldTitle,
      ),
      'anniversary.field.title_hint': (
        zh: zh.anniversaryFieldTitleHint,
        en: en.anniversaryFieldTitleHint,
      ),
      'anniversary.field.description': (
        zh: zh.anniversaryFieldDescription,
        en: en.anniversaryFieldDescription,
      ),
      'anniversary.field.type': (
        zh: zh.anniversaryFieldType,
        en: en.anniversaryFieldType,
      ),
      'anniversary.field.date_type': (
        zh: zh.anniversaryFieldDateType,
        en: en.anniversaryFieldDateType,
      ),
      'anniversary.field.date_picker_title': (
        zh: zh.anniversaryFieldDatePickerTitle,
        en: en.anniversaryFieldDatePickerTitle,
      ),
      'anniversary.field.date_picker_subtitle': (
        zh: zh.anniversaryFieldDatePickerSubtitle,
        en: en.anniversaryFieldDatePickerSubtitle,
      ),
      'anniversary.field.color': (
        zh: zh.anniversaryFieldColor,
        en: en.anniversaryFieldColor,
      ),
      'anniversary.lunar.year_suffix': (
        zh: zh.anniversaryLunarYearSuffix,
        en: en.anniversaryLunarYearSuffix,
      ),
      'anniversary.reminder.card_prefix': (
        zh: zh.anniversaryReminderCardPrefix,
        en: en.anniversaryReminderCardPrefix,
      ),
      'reminder.kind.email': (
        zh: zh.reminderKindEmail,
        en: en.reminderKindEmail,
      ),
      'course.week.prefix': (zh: zh.courseWeekPrefix, en: en.courseWeekPrefix),
      'course.week.suffix': (zh: zh.courseWeekSuffix, en: en.courseWeekSuffix),
      'course.week.count_suffix': (
        zh: zh.courseWeekCountSuffix,
        en: en.courseWeekCountSuffix,
      ),
      'course.week.current_tooltip': (
        zh: zh.courseWeekCurrentTooltip,
        en: en.courseWeekCurrentTooltip,
      ),
      'course.empty.message': (
        zh: zh.courseEmptyMessage,
        en: en.courseEmptyMessage,
      ),
      'course.add': (zh: zh.courseAdd, en: en.courseAdd),
      'course.week_picker.title': (
        zh: zh.courseWeekPickerTitle,
        en: en.courseWeekPickerTitle,
      ),
      'course.week_picker.subtitle': (
        zh: zh.courseWeekPickerSubtitle,
        en: en.courseWeekPickerSubtitle,
      ),
      'course.weeks.all': (zh: zh.courseWeeksAll, en: en.courseWeeksAll),
      'course.weeks.odd': (zh: zh.courseWeeksOdd, en: en.courseWeeksOdd),
      'course.weeks.even': (zh: zh.courseWeeksEven, en: en.courseWeeksEven),
      'course.weeks.select_all': (
        zh: zh.courseWeeksSelectAll,
        en: en.courseWeeksSelectAll,
      ),
      'course.settings.title': (
        zh: zh.courseSettingsTitle,
        en: en.courseSettingsTitle,
      ),
      'course.settings.subtitle': (
        zh: zh.courseSettingsSubtitle,
        en: en.courseSettingsSubtitle,
      ),
      'course.settings.preview_prefix': (
        zh: zh.courseSettingsPreviewPrefix,
        en: en.courseSettingsPreviewPrefix,
      ),
      'course.editor.add_title': (
        zh: zh.courseEditorAddTitle,
        en: en.courseEditorAddTitle,
      ),
      'course.editor.edit_title': (
        zh: zh.courseEditorEditTitle,
        en: en.courseEditorEditTitle,
      ),
      'course.editor.subtitle': (
        zh: zh.courseEditorSubtitle,
        en: en.courseEditorSubtitle,
      ),
      'course.field.term_start': (
        zh: zh.courseFieldTermStart,
        en: en.courseFieldTermStart,
      ),
      'course.field.term_start_picker': (
        zh: zh.courseFieldTermStartPicker,
        en: en.courseFieldTermStartPicker,
      ),
      'course.field.total_weeks': (
        zh: zh.courseFieldTotalWeeks,
        en: en.courseFieldTotalWeeks,
      ),
      'course.field.sessions_per_day': (
        zh: zh.courseFieldSessionsPerDay,
        en: en.courseFieldSessionsPerDay,
      ),
      'course.field.session_minutes': (
        zh: zh.courseFieldSessionMinutes,
        en: en.courseFieldSessionMinutes,
      ),
      'course.field.first_session_time': (
        zh: zh.courseFieldFirstSessionTime,
        en: en.courseFieldFirstSessionTime,
      ),
      'course.field.first_session_time_subtitle': (
        zh: zh.courseFieldFirstSessionTimeSubtitle,
        en: en.courseFieldFirstSessionTimeSubtitle,
      ),
      'course.field.break_minutes': (
        zh: zh.courseFieldBreakMinutes,
        en: en.courseFieldBreakMinutes,
      ),
      'course.field.name': (zh: zh.courseFieldName, en: en.courseFieldName),
      'course.field.teacher': (
        zh: zh.courseFieldTeacher,
        en: en.courseFieldTeacher,
      ),
      'course.field.location': (
        zh: zh.courseFieldLocation,
        en: en.courseFieldLocation,
      ),
      'course.field.weekday': (
        zh: zh.courseFieldWeekday,
        en: en.courseFieldWeekday,
      ),
      'course.field.start_section': (
        zh: zh.courseFieldStartSection,
        en: en.courseFieldStartSection,
      ),
      'course.field.section_count': (
        zh: zh.courseFieldSectionCount,
        en: en.courseFieldSectionCount,
      ),
      'course.field.class_weeks': (
        zh: zh.courseFieldClassWeeks,
        en: en.courseFieldClassWeeks,
      ),
      'course.field.color': (zh: zh.courseFieldColor, en: en.courseFieldColor),
      'todo.empty': (zh: zh.todoEmpty, en: en.todoEmpty),
      'todo.add': (zh: zh.todoAdd, en: en.todoAdd),
      'todo.matrix': (zh: zh.todoMatrix, en: en.todoMatrix),
      'todo.list': (zh: zh.todoList, en: en.todoList),
      'todo.postpone': (zh: zh.todoPostpone, en: en.todoPostpone),
      'todo.priority.none': (zh: zh.todoPriorityNone, en: en.todoPriorityNone),
      'todo.priority.low': (zh: zh.todoPriorityLow, en: en.todoPriorityLow),
      'todo.priority.medium': (
        zh: zh.todoPriorityMedium,
        en: en.todoPriorityMedium,
      ),
      'todo.priority.high': (zh: zh.todoPriorityHigh, en: en.todoPriorityHigh),
      'todo.priority.urgent': (
        zh: zh.todoPriorityUrgent,
        en: en.todoPriorityUrgent,
      ),
      'calendar.month': (zh: zh.calendarMonth, en: en.calendarMonth),
      'calendar.week': (zh: zh.calendarWeek, en: en.calendarWeek),
      'calendar.day': (zh: zh.calendarDay, en: en.calendarDay),
      'calendar.empty': (zh: zh.calendarEmpty, en: en.calendarEmpty),
      'focus.start': (zh: zh.focusStart, en: en.focusStart),
      'focus.pause': (zh: zh.focusPause, en: en.focusPause),
      'focus.resume': (zh: zh.focusResume, en: en.focusResume),
      'focus.reset': (zh: zh.focusReset, en: en.focusReset),
      'reminder.health': (zh: zh.reminderHealth, en: en.reminderHealth),
      'reminder.test_notification': (
        zh: zh.reminderTestNotification,
        en: en.reminderTestNotification,
      ),
      'reminder.snooze_5min': (
        zh: zh.reminderSnooze5min,
        en: en.reminderSnooze5min,
      ),
      'reminder.snooze_10min': (
        zh: zh.reminderSnooze10min,
        en: en.reminderSnooze10min,
      ),
      'reminder.snooze_30min': (
        zh: zh.reminderSnooze30min,
        en: en.reminderSnooze30min,
      ),
      'time_audit.title': (zh: zh.timeAuditTitle, en: en.timeAuditTitle),
      'time_audit.add_manual': (
        zh: zh.timeAuditAddManual,
        en: en.timeAuditAddManual,
      ),
      'time_audit.weekly_overview': (
        zh: zh.timeAuditWeeklyOverview,
        en: en.timeAuditWeeklyOverview,
      ),
      'share.title': (zh: zh.shareTitle, en: en.shareTitle),
      'share.create_invite': (
        zh: zh.shareCreateInvite,
        en: en.shareCreateInvite,
      ),
      'share.accept_invite': (
        zh: zh.shareAcceptInvite,
        en: en.shareAcceptInvite,
      ),
      'share.role.owner': (zh: zh.shareRoleOwner, en: en.shareRoleOwner),
      'share.role.editor': (zh: zh.shareRoleEditor, en: en.shareRoleEditor),
      'share.role.viewer': (zh: zh.shareRoleViewer, en: en.shareRoleViewer),
      'unit.minute': (zh: zh.unitMinute, en: en.unitMinute),
      'unit.min': (zh: zh.unitMin, en: en.unitMin),
      'unit.day': (zh: zh.unitDay, en: en.unitDay),
      'repeat.every_day': (zh: zh.repeatEveryDay, en: en.repeatEveryDay),
      'repeat.weekdays': (zh: zh.repeatWeekdays, en: en.repeatWeekdays),
    };

    for (final entry in pairs.entries) {
      I18n.setLocale(AppLocale.zh);
      expect(I18n.tr(entry.key), entry.value.zh, reason: entry.key);
      I18n.setLocale(AppLocale.en);
      expect(I18n.tr(entry.key), entry.value.en, reason: entry.key);
    }
  });
}

Set<String> _arbKeys(String path) {
  final raw = File(path).readAsStringSync();
  final decoded = json.decode(raw) as Map<String, dynamic>;
  return decoded.keys.where((key) => !key.startsWith('@')).toSet();
}

Set<String> _i18nKeys(String source) {
  final matches = RegExp(r"'([^']+)':").allMatches(source);
  return matches
      .map((match) => match.group(1)!)
      .where((key) => key.contains('.'))
      .toSet();
}

String _arbKeyForI18nKey(String key) {
  final parts = key.split(RegExp(r'[._]')).where((part) => part.isNotEmpty);
  final head = parts.first;
  final tail = parts
      .skip(1)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}');
  return '$head${tail.join()}';
}
