/// Duoyi widget screen and preview UI localization strings (Task: iOS style & i18n).
library;

import '../l10n/generated/app_localizations.dart';
import '../services/android_widget_manager.dart';
import 'i18n.dart';

enum WidgetCategory { all, productivity, life }

enum WidgetHostPlatform { android, ios, web, desktop }

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

  static AppLocalizations _l10n() =>
      lookupAppLocalizations(I18n.current.flutterLocale);

  static bool get isZh => I18n.current == AppLocale.zh;

  static String hostSupportTitle(WidgetHostPlatform platform) =>
      switch (platform) {
        WidgetHostPlatform.ios => _l10n().widgetHostSupportIosTitle,
        WidgetHostPlatform.web => _l10n().widgetHostSupportWebTitle,
        _ => _l10n().widgetHostSupportMobileTitle,
      };

  static String hostSupportMessage(WidgetHostPlatform platform) =>
      platform == WidgetHostPlatform.ios
      ? _l10n().widgetHostSupportIosMessage
      : _l10n().widgetHostSupportMobileMessage;

  static String hostAddAction(WidgetHostPlatform platform) =>
      platform == WidgetHostPlatform.ios
      ? _l10n().widgetHostAddIosAction
      : _l10n().widgetHostAddMobileAction;

  static String hostHelpTitle(WidgetHostPlatform platform) =>
      platform == WidgetHostPlatform.ios
      ? addDialogTitle
      : _l10n().widgetHostHelpMobileTitle;

  static String hostHelpMessage(WidgetHostPlatform platform) =>
      platform == WidgetHostPlatform.ios
      ? _l10n().widgetHostHelpIosMessage
      : _l10n().widgetHostHelpMobileMessage;

  static String hostTipsMessage(WidgetHostPlatform platform) =>
      platform == WidgetHostPlatform.android
      ? widgetTipsBannerMessage
      : platform == WidgetHostPlatform.ios
      ? _l10n().widgetHostTipsIosMessage
      : _l10n().widgetHostTipsPreviewMessage;

  static String hostStyleDescription(String id, WidgetHostPlatform platform) {
    if (platform == WidgetHostPlatform.android) {
      return displayModeDescription(id);
    }
    final l10n = _l10n();
    final description = switch (id) {
      'compact' => l10n.widgetHostStyleCompactDescription,
      'detailed' => l10n.widgetHostStyleDetailedDescription,
      _ => l10n.widgetHostStyleStandardDescription,
    };
    if (platform != WidgetHostPlatform.ios) return description;
    return l10n.widgetHostStyleDescriptionIos(description);
  }

  static String hostStyleSyncSuccess(
    String label,
    WidgetHostPlatform platform,
  ) {
    if (platform == WidgetHostPlatform.android) return styleSyncSuccess(label);
    if (platform == WidgetHostPlatform.ios) {
      return _l10n().widgetStyleSyncSuccess(label);
    }
    return _l10n().widgetPreviewStyleSyncSuccess(label);
  }

  // Screen header & control strings
  static String get screenTitle => _l10n().navWidget;
  static String get refreshTooltip => _l10n().widgetRefreshTooltip;
  static String get previewHeaderTitle => _l10n().widgetPreviewHeaderTitle;
  static String get stylePanelTitle => _l10n().widgetStylePanelTitle;

  // Category labels
  static String categoryLabel(WidgetCategory category) {
    final l10n = _l10n();
    return switch (category) {
      WidgetCategory.all => l10n.widgetCategoryAll,
      WidgetCategory.productivity => l10n.widgetCategoryProductivity,
      WidgetCategory.life => l10n.widgetCategoryLife,
    };
  }

  // Catalog item titles
  static String catalogTitle(DuoyiWidgetKind kind) {
    final l10n = _l10n();
    return switch (kind) {
      DuoyiWidgetKind.todo => l10n.widgetCatalogTodoTitle,
      DuoyiWidgetKind.focus => l10n.navFocus,
      DuoyiWidgetKind.habit => l10n.navHabit,
      DuoyiWidgetKind.calendar => l10n.widgetCatalogCalendarTitle,
      DuoyiWidgetKind.schedule => l10n.widgetCatalogScheduleTitle,
      DuoyiWidgetKind.goal => l10n.widgetCatalogGoalTitle,
      DuoyiWidgetKind.course => l10n.mineTileCourses,
      DuoyiWidgetKind.note => l10n.widgetCatalogNoteTitle,
      DuoyiWidgetKind.anniversary => l10n.widgetCatalogAnniversaryTitle,
      DuoyiWidgetKind.diary => l10n.diaryTitle,
    };
  }

  // Catalog item subtitles
  static String catalogSubtitle(DuoyiWidgetKind kind) {
    final l10n = _l10n();
    return switch (kind) {
      DuoyiWidgetKind.todo => l10n.widgetCatalogTodoSubtitle,
      DuoyiWidgetKind.focus => l10n.widgetCatalogFocusSubtitle,
      DuoyiWidgetKind.habit => l10n.widgetCatalogHabitSubtitle,
      DuoyiWidgetKind.calendar => l10n.widgetCatalogCalendarSubtitle,
      DuoyiWidgetKind.schedule => l10n.widgetCatalogScheduleSubtitle,
      DuoyiWidgetKind.goal => l10n.widgetCatalogGoalSubtitle,
      DuoyiWidgetKind.course => l10n.widgetCatalogCourseSubtitle,
      DuoyiWidgetKind.note => l10n.widgetCatalogNoteSubtitle,
      DuoyiWidgetKind.anniversary => l10n.widgetCatalogAnniversarySubtitle,
      DuoyiWidgetKind.diary => l10n.widgetCatalogDiarySubtitle,
    };
  }

  // Display mode labels & descriptions
  static String displayModeLabel(String id) {
    final l10n = _l10n();
    return switch (id) {
      'compact' => l10n.widgetDisplayModeCompactLabel,
      'detailed' => l10n.widgetDisplayModeDetailedLabel,
      _ => l10n.widgetDisplayModeStandardLabel,
    };
  }

  static String displayModeDescription(String id) {
    final l10n = _l10n();
    return switch (id) {
      'compact' => l10n.widgetDisplayModeCompactDescription,
      'detailed' => l10n.widgetDisplayModeDetailedDescription,
      _ => l10n.widgetDisplayModeStandardDescription,
    };
  }

  // SnackBar / feedback messages
  static String get styleSyncFailed => _l10n().widgetStyleSyncFailed;
  static String get actionRetry => _l10n().actionRetry;
  static String styleSyncSuccess(String modeLabel) =>
      _l10n().widgetStyleSyncSuccess(modeLabel);
  static String get cannotOpenSettings => _l10n().widgetCannotOpenSettings;
  static String get refreshSuccess => _l10n().widgetRefreshSuccess;
  static String get refreshFailed => _l10n().widgetRefreshFailed;

  // Pin support banner
  static String get pinSupportCheckingTitle =>
      _l10n().widgetPinSupportCheckingTitle;
  static String get pinSupportCheckingMessage =>
      _l10n().widgetPinSupportCheckingMessage;
  static String get pinSupportSupportedTitle =>
      _l10n().widgetPinSupportSupportedTitle;
  static String get pinSupportSupportedMessage =>
      _l10n().widgetPinSupportSupportedMessage;

  static String pinSupportResultTitle(AndroidWidgetPinResult? support) {
    final l10n = _l10n();
    return switch (support) {
      AndroidWidgetPinResult.unsupportedPlatform =>
        l10n.widgetPinSupportUnsupportedPlatformTitle,
      AndroidWidgetPinResult.unsupportedLauncher =>
        l10n.widgetPinSupportUnsupportedLauncherTitle,
      AndroidWidgetPinResult.permissionDenied =>
        l10n.widgetPinSupportPermissionDeniedTitle,
      AndroidWidgetPinResult.confirmationBlocked =>
        l10n.widgetPinSupportConfirmationBlockedTitle,
      AndroidWidgetPinResult.invalidKind =>
        l10n.widgetPinSupportInvalidKindTitle,
      _ => l10n.widgetPinSupportFallbackTitle,
    };
  }

  static String pinSupportResultMessage(AndroidWidgetPinResult? support) {
    final l10n = _l10n();
    return switch (support) {
      AndroidWidgetPinResult.unsupportedPlatform =>
        l10n.widgetPinSupportUnsupportedPlatformMessage,
      AndroidWidgetPinResult.unsupportedLauncher =>
        l10n.widgetPinSupportUnsupportedLauncherMessage,
      AndroidWidgetPinResult.permissionDenied =>
        l10n.widgetPinSupportPermissionDeniedMessage,
      AndroidWidgetPinResult.confirmationBlocked =>
        l10n.widgetPinSupportConfirmationBlockedMessage,
      AndroidWidgetPinResult.invalidKind =>
        l10n.widgetPinSupportInvalidKindMessage,
      _ => l10n.widgetPinSupportFallbackMessage,
    };
  }

  static String get actionAppSettings => _l10n().widgetActionAppSettings;
  static String get actionRecheck => _l10n().widgetActionRecheck;
  static String get actionOpenPermissions =>
      _l10n().widgetActionOpenPermissions;
  static String get actionGotIt => _l10n().widgetActionGotIt;
  static String get addDialogTitle => _l10n().widgetAddDialogTitle;

  // Help messages for AndroidWidgetPinResult
  static String pinHelpMessage(AndroidWidgetPinResult result) {
    final l10n = _l10n();
    return switch (result) {
      AndroidWidgetPinResult.unsupported =>
        l10n.widgetPinHelpUnsupportedMessage,
      AndroidWidgetPinResult.unsupportedPlatform =>
        l10n.widgetPinHelpUnsupportedPlatformMessage,
      AndroidWidgetPinResult.unsupportedLauncher =>
        l10n.widgetPinHelpUnsupportedLauncherMessage,
      AndroidWidgetPinResult.permissionDenied =>
        l10n.widgetPinHelpPermissionDeniedMessage,
      AndroidWidgetPinResult.confirmationBlocked =>
        l10n.widgetPinHelpConfirmationBlockedMessage,
      AndroidWidgetPinResult.invalidKind =>
        l10n.widgetPinHelpInvalidKindMessage,
      AndroidWidgetPinResult.unavailable =>
        l10n.widgetPinHelpUnavailableMessage,
      AndroidWidgetPinResult.requested => l10n.widgetPinHelpRequestedMessage,
    };
  }

  // Pin confirmation failures
  static (String title, String message) pinConfirmationFailure(
    AndroidWidgetPinFinalStatus status,
  ) {
    final l10n = _l10n();
    return switch (status) {
      AndroidWidgetPinFinalStatus.invalidWidgetId => (
        l10n.widgetPinConfirmationInvalidWidgetIdTitle,
        l10n.widgetPinConfirmationInvalidWidgetIdMessage,
      ),
      AndroidWidgetPinFinalStatus.timeout => (
        l10n.widgetPinConfirmationTimeoutTitle,
        l10n.widgetPinConfirmationTimeoutMessage,
      ),
      AndroidWidgetPinFinalStatus.unavailable => (
        l10n.widgetPinConfirmationUnavailableTitle,
        l10n.widgetPinConfirmationUnavailableMessage,
      ),
      AndroidWidgetPinFinalStatus.success => (
        l10n.widgetPinConfirmationSuccessTitle,
        l10n.widgetPinConfirmationSuccessMessage,
      ),
    };
  }

  // Add button labels
  static String get checkingDesktopSupport =>
      _l10n().widgetCheckingDesktopSupport;

  static String pinDisabledAction(AndroidWidgetPinResult? support) {
    final l10n = _l10n();
    return switch (support) {
      AndroidWidgetPinResult.unsupportedPlatform =>
        l10n.widgetPinDisabledAndroidOnly,
      AndroidWidgetPinResult.unsupportedLauncher =>
        l10n.widgetPinDisabledPicker,
      _ => l10n.widgetPinDisabledHelp,
    };
  }

  static String get loadingStyle => _l10n().widgetLoadingStyle;
  static String get styleLoadFailed => _l10n().widgetStyleLoadFailed;
  static String get styleSyncPending => _l10n().widgetStyleSyncPending;
  static String get updatingStyle => _l10n().widgetUpdatingStyle;
  static String get requestingAdd => _l10n().widgetRequestingAdd;

  static String addWidgetButtonLabel({
    required String modeLabel,
    required String launcherRequestLabel,
  }) => _l10n().widgetAddWidgetButtonLabel(modeLabel, launcherRequestLabel);

  static String pinInitiatedSnackBar(String modeLabel) =>
      _l10n().widgetPinInitiatedSnackBar(modeLabel);

  static String pinSuccessSnackBar(String modeLabel) =>
      _l10n().widgetPinSuccessSnackBar(modeLabel);

  // Tips banner
  static String get widgetTipsBannerTitle => _l10n().widgetTipsBannerTitle;
  static String get widgetTipsBannerMessage => _l10n().widgetTipsBannerMessage;

  // Desktop web fallback
  static String get desktopWebTitle => _l10n().widgetDesktopWebTitle;
  static String get desktopWebMessage => _l10n().widgetDesktopWebMessage;
  static String get desktopWebTileSubtitle =>
      _l10n().widgetDesktopWebTileSubtitle;
  static String get desktopWebOpenCalendar =>
      _l10n().widgetDesktopWebOpenCalendar;

  // Preview card titles
  static String previewTitle(WidgetPreviewKind kind) {
    final l10n = _l10n();
    return switch (kind) {
      WidgetPreviewKind.todo => l10n.widgetPreviewTodoTitle,
      WidgetPreviewKind.focus => l10n.navFocus,
      WidgetPreviewKind.habit => l10n.navHabit,
      WidgetPreviewKind.calendar => l10n.widgetCatalogCalendarTitle,
      WidgetPreviewKind.schedule => l10n.widgetPreviewScheduleTitle,
      WidgetPreviewKind.goal => l10n.widgetCatalogGoalTitle,
      WidgetPreviewKind.course => l10n.mineTileCourses,
      WidgetPreviewKind.note => l10n.noteTitle,
      WidgetPreviewKind.anniversary => l10n.widgetCatalogAnniversaryTitle,
      WidgetPreviewKind.diary => l10n.diaryTitle,
    };
  }

  static String previewSampleBadge(String title) =>
      _l10n().widgetPreviewSampleBadge(title);

  static String sampleHeaderDate(String cellLabel, {DateTime? date}) {
    final d = date ?? DateTime(2026, 5, 17);
    final l10n = _l10n();
    final isChinese = isZh;
    final monthLabel = isChinese
        ? d.month.toString().padLeft(2, '0')
        : _enMonth(d.month, l10n);
    final day = isChinese ? d.day.toString().padLeft(2, '0') : d.day.toString();
    return l10n.widgetSampleHeaderDate(cellLabel, monthLabel, day);
  }

  static String get refreshPreviewTooltip =>
      _l10n().widgetRefreshPreviewTooltip;

  static List<String> get previewNavLabels {
    final l10n = _l10n();
    return List<String>.unmodifiable([
      l10n.navTodo,
      l10n.navHabit,
      l10n.navCalendar,
      l10n.navFocus,
    ]);
  }

  // Calendar body
  static String calendarMonthHeader(int year, int month) {
    final l10n = _l10n();
    final monthLabel = isZh ? month.toString() : _enMonth(month, l10n);
    return l10n.widgetCalendarMonthHeader(year.toString(), monthLabel);
  }

  static String get calendarToday => _l10n().pickerActionToday;

  static List<String> get calendarWeekLabels {
    final l10n = _l10n();
    return List<String>.unmodifiable([
      l10n.habitWeekday1,
      l10n.habitWeekday2,
      l10n.habitWeekday3,
      l10n.habitWeekday4,
      l10n.habitWeekday5,
      l10n.habitWeekday6,
      l10n.habitWeekday7,
    ]);
  }

  // 10 sample preview bodies
  // Todo
  static String get todoItem1 => _l10n().widgetTodoItem1;
  static String get todoItem2 => _l10n().widgetTodoItem2;
  static String get todoItem3 => _l10n().widgetTodoItem3;
  static String get todoSummaryCount => _l10n().widgetTodoSummaryCount;
  static String get todoQuickAdd => _l10n().widgetTodoQuickAdd;

  // Focus
  static String get focusMetricSessions => _l10n().widgetFocusMetricSessions;
  static String get focusMetricDuration => _l10n().widgetFocusMetricDuration;
  static String get focusMetricNext => _l10n().widgetFocusMetricNext;
  static String get focusTimerUnit => _l10n().widgetFocusTimerUnit;
  static String get focusStartButton => _l10n().widgetFocusStartButton;
  static String get focusLine1 => _l10n().widgetFocusLine1;
  static String get focusLine2 => _l10n().widgetFocusLine2;
  static String get focusLine3 => _l10n().widgetFocusLine3;

  // Habit
  static String get habitTitle => _l10n().widgetHabitTitle;
  static String get calendarCurrentDate => _l10n().widgetCalendarCurrentDate;
  static String get calendarCurrentDay => _l10n().widgetCalendarCurrentDay;
  static String get habitLine1 => _l10n().widgetHabitLine1;
  static String get habitLine2 => _l10n().widgetHabitLine2;
  static String get habitCheckInButton => _l10n().widgetHabitCheckInButton;

  // Schedule
  static String get scheduleItem1 => _l10n().widgetScheduleItem1;
  static String get scheduleItem2 => _l10n().widgetScheduleItem2;
  static String get scheduleItem3 => _l10n().widgetScheduleItem3;

  // Goal
  static String get goalItem1 => _l10n().widgetGoalItem1;
  static String get goalItem2 => _l10n().widgetGoalItem2;
  static String get goalItem3 => _l10n().widgetGoalItem3;

  // Course
  static String get courseItem1 => _l10n().widgetCourseItem1;
  static String get courseItem2 => _l10n().widgetCourseItem2;
  static String get courseItem3 => _l10n().widgetCourseItem3;

  // Note
  static String get noteItem1 => _l10n().widgetNoteItem1;
  static String get noteItem2 => _l10n().widgetNoteItem2;
  static String get noteItem3 => _l10n().widgetNoteItem3;

  // Anniversary
  static String get anniversaryItem1 => _l10n().widgetAnniversaryItem1;
  static String get anniversaryItem2 => _l10n().widgetAnniversaryItem2;
  static String get anniversaryItem3 => _l10n().widgetAnniversaryItem3;

  // Diary
  static String get diaryItem1 => _l10n().widgetDiaryItem1;
  static String get diaryItem2 => _l10n().widgetDiaryItem2;
  static String get diaryItem3 => _l10n().widgetDiaryItem3;

  static String _enMonth(int month, [AppLocalizations? l10n]) {
    final localL10n = l10n ?? _l10n();
    return switch (month) {
      1 => localL10n.widgetCalendarMonthJan,
      2 => localL10n.widgetCalendarMonthFeb,
      3 => localL10n.widgetCalendarMonthMar,
      4 => localL10n.widgetCalendarMonthApr,
      5 => localL10n.widgetCalendarMonthMay,
      6 => localL10n.widgetCalendarMonthJun,
      7 => localL10n.widgetCalendarMonthJul,
      8 => localL10n.widgetCalendarMonthAug,
      9 => localL10n.widgetCalendarMonthSep,
      10 => localL10n.widgetCalendarMonthOct,
      11 => localL10n.widgetCalendarMonthNov,
      12 => localL10n.widgetCalendarMonthDec,
      _ => '',
    };
  }
}
