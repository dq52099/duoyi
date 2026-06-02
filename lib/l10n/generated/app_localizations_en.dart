// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Duoyi';

  @override
  String get navToday => 'Today';

  @override
  String get navTodo => 'Tasks';

  @override
  String get navHabit => 'Habits';

  @override
  String get navCalendar => 'Calendar';

  @override
  String get navFocus => 'Focus';

  @override
  String get navWidget => 'Widgets';

  @override
  String get navMine => 'Me';

  @override
  String get actionConfirm => 'OK';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionCreate => 'Create';

  @override
  String get actionGenerate => 'Generate';

  @override
  String get actionComplete => 'Done';

  @override
  String get actionOff => 'Off';

  @override
  String get actionMoveUp => 'Move up';

  @override
  String get actionMoveDown => 'Move down';

  @override
  String get actionSnooze => 'Snooze';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionBack => 'Back';

  @override
  String get actionClear => 'Clear';

  @override
  String get actionClose => 'Close';

  @override
  String get settingsLanguage => 'Display language';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get weekdayUnknown => '?';

  @override
  String get calendarSolar => 'Gregorian';

  @override
  String get calendarLunar => 'Lunar';

  @override
  String get calendarChineseLunar => 'Chinese lunar';

  @override
  String get calendarChineseLunarCalendar => 'Chinese Lunar Calendar';

  @override
  String get calendarCorrespondingLunar => 'Corresponding Chinese lunar date';

  @override
  String get calendarCorrespondingSolar => 'Corresponding Gregorian date';

  @override
  String get calendarEventEvent => 'Event';

  @override
  String get calendarEventTodo => 'Task';

  @override
  String get calendarEventHabit => 'Habit';

  @override
  String get calendarEventPomodoro => 'Pomodoro';

  @override
  String get calendarEventAnniversary => 'Anniversary';

  @override
  String get calendarEventCourse => 'Course';

  @override
  String get calendarEventDiary => 'Diary';

  @override
  String get calendarEventCountdown => 'Countdown';

  @override
  String get calendarEventGoal => 'Goal';

  @override
  String get calendarEventTimeEntry => 'Time log';

  @override
  String get timeEntrySourceManual => 'Manual';

  @override
  String get timeEntrySourcePomodoro => 'Pomodoro';

  @override
  String get timeEntrySourceTodo => 'Task';

  @override
  String get timeEntrySourceHabit => 'Habit';

  @override
  String get timeEntrySourceGoal => 'Goal';

  @override
  String get timeEntryCategoryFocus => 'Focus';

  @override
  String get timeEntryCategoryTodo => 'Task';

  @override
  String get timeEntryCategoryHabit => 'Habit';

  @override
  String get timeEntryCategoryGoal => 'Goal';

  @override
  String get timeEntryCategoryStudy => 'Study';

  @override
  String get timeEntryCategoryWork => 'Work';

  @override
  String get timeEntryCategoryLife => 'Life';

  @override
  String get timeEntryCategoryOther => 'Other';

  @override
  String get settingsLanguageZh => 'Simplified Chinese';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageDescription =>
      'In v2, common terms such as actions, navigation, reminders, and sharing have English translations. Untranslated page copy falls back to Chinese while coverage expands.';

  @override
  String get preferencesTitle => 'Personal settings';

  @override
  String get preferencesLocalTitle => 'Local personal settings';

  @override
  String get preferencesLocalSubtitle =>
      'Manage notifications, navigation, dates, interactions, and local behavior by feature';

  @override
  String get preferencesSectionDate => 'Date and calendar';

  @override
  String get preferencesSectionDateSubtitle =>
      'Affects Today cards, calendar, and date display';

  @override
  String get preferencesFirstDayTitle => 'First day of week';

  @override
  String get preferencesFirstDayCurrentMonday => 'Currently Monday';

  @override
  String get preferencesFirstDayCurrentSunday => 'Currently Sunday';

  @override
  String get preferencesDateFormatTitle => 'Date format';

  @override
  String get preferencesTimezoneTitle => 'App time zone';

  @override
  String get preferencesTimezoneFollowSystem => 'Follow phone';

  @override
  String get preferencesLunarTitle => 'Show lunar calendar';

  @override
  String get preferencesLunarSubtitle => 'Affects month view and Today cards';

  @override
  String get preferencesSectionDefaults => 'Default behavior';

  @override
  String get preferencesSectionDefaultsSubtitle =>
      'Startup tab, quick capture, and focus length';

  @override
  String get preferencesDefaultTabTitle => 'Default startup tab';

  @override
  String get preferencesQuickCaptureTitle => 'Show quick capture button';

  @override
  String get preferencesQuickCaptureSubtitle =>
      'Shortcut button on the Today page';

  @override
  String get preferencesNotificationQuickAddTitle => 'Notification quick add';

  @override
  String get preferencesNotificationQuickAddSubtitle =>
      'Android ongoing shortcut for tasks and focus';

  @override
  String get preferencesNotificationTodayProgressTitle =>
      'Today progress in notification bar';

  @override
  String get preferencesNotificationTodayProgressSubtitle =>
      'Keep today task progress in the notification bar and refresh it as tasks change';

  @override
  String get preferencesNotificationStatusBarTitle =>
      'Notification bar shortcuts';

  @override
  String get preferencesNotificationStatusBarUnsupported =>
      'Ongoing notification shortcuts and today progress are Android-only. This platform keeps regular reminders.';

  @override
  String get preferencesNotificationStatusBarEnabled =>
      'Notification bar entry enabled';

  @override
  String get preferencesNotificationStatusBarDisabled =>
      'Notification bar entry disabled';

  @override
  String get preferencesNotificationStatusBarSyncFailed =>
      'Notification bar sync failed, so the previous setting was restored. Check notification permission and channels.';

  @override
  String get preferencesShowCompletedTitle => 'Show completed tasks';

  @override
  String get preferencesShowCompletedSubtitle =>
      'Hide completed items to focus on open work';

  @override
  String get preferencesPomodoroLengthTitle => 'Default Pomodoro length';

  @override
  String get preferencesSectionBottomNav => 'Bottom navigation';

  @override
  String get preferencesSectionBottomNavSubtitle =>
      'Show up to five bottom tabs; Me stays fixed, Widgets can be hidden';

  @override
  String get preferencesSectionInteraction => 'Interaction';

  @override
  String get preferencesSectionInteractionSubtitle =>
      'Haptics and completion behavior';

  @override
  String get preferencesHapticTitle => 'Haptic feedback';

  @override
  String get preferencesHapticSubtitle =>
      'Completion, switching, unlocking, and more';

  @override
  String get preferencesSectionAutoArchive => 'Task auto archive';

  @override
  String get preferencesSectionAutoArchiveSubtitle =>
      'Reduce clutter from completed tasks';

  @override
  String get preferencesAutoArchiveTitle => 'Hide after N completed days';

  @override
  String get preferencesAutoArchiveNever => 'Never archive';

  @override
  String get preferencesAutoArchiveAfterDays => 'days before auto hide';

  @override
  String get preferencesSectionDailyReminder => 'Daily reminders';

  @override
  String get preferencesSectionDailyReminderSubtitle =>
      'Up to three reminders with time, scope, repeat days, and holiday pause';

  @override
  String get preferencesNavFixed => 'Always visible';

  @override
  String get preferencesNavVisible => 'Visible';

  @override
  String get preferencesNavHidden => 'Hidden';

  @override
  String get preferencesNotifyPermissionDenied =>
      'System notification permission was not granted';

  @override
  String get preferencesNotifyExactAlarmGranted =>
      'Exact alarm permission is enabled';

  @override
  String get preferencesNotifyExactAlarmDenied =>
      'Exact alarm permission was not granted';

  @override
  String get preferencesNotifyFullScreenGranted =>
      'Full-screen alert permission is enabled';

  @override
  String get preferencesNotifyFullScreenDenied =>
      'Full-screen alert permission was not granted';

  @override
  String get preferencesNotifyTestPermissionDenied =>
      'Notification permission is disabled, so the test notification cannot be sent';

  @override
  String get preferencesNotifyTestFailed => 'Test notification failed: ';

  @override
  String get preferencesNotifyTestSent => 'Test notification sent';

  @override
  String get preferencesNotifyPendingCleared =>
      'All scheduled reminders were canceled';

  @override
  String get preferencesNotifyOpenSettingsFailed =>
      'Unable to open system settings';

  @override
  String get preferencesRingtoneSection => 'Built-in reminder sounds';

  @override
  String get preferencesRingtoneSectionSubtitle =>
      'For HyperOS and other devices where default notifications are muted';

  @override
  String get preferencesRingtoneSectionSubtitleAndroid =>
      'Android uses the in-app ringtone service for devices where default notifications may be muted';

  @override
  String get preferencesRingtoneSectionSubtitleApple =>
      'iOS and macOS use system notification sounds and time-sensitive alerts, so Android-only ringtone choices are hidden';

  @override
  String get preferencesRingtoneSectionSubtitleDesktop =>
      'Desktop reminders use the system notification sound; volume is controlled by the OS';

  @override
  String get preferencesRingtoneSectionSubtitleUnsupported =>
      'Local ringing reminders are not supported on this platform';

  @override
  String get preferencesRingtoneSound => 'Reminder sound';

  @override
  String get preferencesRingtoneVolume => 'Ring volume';

  @override
  String get preferencesRingtoneCurrent => 'Current';

  @override
  String get preferencesRingtoneSystemSound => 'System notification sound';

  @override
  String get preferencesRingtoneSystemSoundSubtitleApple =>
      'Reminders request sound, banners, and time-sensitive priority; ringtone and volume are managed in system settings';

  @override
  String get preferencesRingtoneSystemSoundSubtitleDesktop =>
      'Reminders are delivered through the desktop notification system; ringtone and volume are managed in system settings';

  @override
  String get preferencesRingtoneUnsupported => 'Local ringing unavailable';

  @override
  String get preferencesRingtoneUnsupportedSubtitle =>
      'This platform does not provide local ringing reminders yet; use system or email reminders as a fallback';

  @override
  String get preferencesDailyReminderOne => 'Reminder 1';

  @override
  String get preferencesDailyReminderTwo => 'Reminder 2';

  @override
  String get preferencesDailyReminderThree => 'Reminder 3';

  @override
  String get preferencesDailyReminderDisabled => 'Off';

  @override
  String get preferencesDailyReminderTime => 'Reminder time';

  @override
  String get preferencesDailyReminderTimeSubtitle =>
      'Send a reminder with sound and vibration at the selected time';

  @override
  String get preferencesDailyReminderTimeSuffix => ' time';

  @override
  String get preferencesDailyReminderTimePickerSubtitle =>
      'Set when this reminder fires';

  @override
  String get preferencesDailyReminderKindTitle => 'Reminder method';

  @override
  String get preferencesDailyReminderKindPushDescription =>
      'System notification reminder';

  @override
  String get preferencesDailyReminderKindPopupDescription =>
      'Show a pop-up while the app is foregrounded, with notification fallback in background';

  @override
  String get preferencesDailyReminderKindAlarmDescription =>
      'Use alarm-style reminder for important items';

  @override
  String get preferencesDailyReminderKindOffDescription =>
      'Do not register a system notification, pop-up, or alarm';

  @override
  String get preferencesDailyReminderRegisterFailed =>
      'Daily reminder registration failed';

  @override
  String get preferencesDailyReminderNotReady =>
      'System notifications are not ready, so the daily reminder was not enabled.';

  @override
  String get preferencesDailyReminderTodayTasks => 'Tasks: today';

  @override
  String get preferencesDailyReminderTodayTasksSubtitle =>
      'Include the number of unfinished tasks due today';

  @override
  String get preferencesDailyReminderTomorrowPlan => 'Tasks: tomorrow plan';

  @override
  String get preferencesDailyReminderTomorrowPlanSubtitle =>
      'Include the number of scheduled tasks for tomorrow';

  @override
  String get preferencesDailyReminderOverdueTasks => 'Tasks: overdue';

  @override
  String get preferencesDailyReminderOverdueTasksSubtitle =>
      'Include unfinished overdue tasks';

  @override
  String get preferencesDailyReminderPauseHolidays =>
      'Pause on public holidays';

  @override
  String get preferencesDailyReminderPauseHolidaysSubtitle =>
      'Skip built-in holidays and resume on the next reminder day';

  @override
  String get preferencesDailyReminderChipTodayTasks => 'Today tasks';

  @override
  String get preferencesDailyReminderChipTomorrowPlan => 'Tomorrow plan';

  @override
  String get preferencesDailyReminderChipOverdueTasks => 'Overdue';

  @override
  String get preferencesDailyReminderChipPauseHolidays => 'Holiday pause';

  @override
  String get preferencesDailyReminderScopeToday => 'Today';

  @override
  String get preferencesDailyReminderScopeOverdue => 'Overdue';

  @override
  String get preferencesDailyReminderScopeTomorrow => 'Tomorrow';

  @override
  String get preferencesDailyReminderScopeNone => 'No task scope';

  @override
  String get notificationChannelGeneralName => 'Duoyi reminders';

  @override
  String get notificationChannelGeneralDescription =>
      'Daily reminders use a gentle sound, vibration, and banners when available';

  @override
  String get notificationChannelAlarmName => 'Duoyi strong reminders';

  @override
  String get notificationChannelAlarmDescription =>
      'Important reminders use the built-in gentle ringtone and can be stopped from the notification';

  @override
  String get notificationChannelQuickAddName => 'Duoyi quick shortcuts';

  @override
  String get notificationChannelQuickAddDescription =>
      'Ongoing notification for quick task capture and focus start';

  @override
  String get notificationTickerReminder => 'Duoyi reminder';

  @override
  String get notificationTickerQuickAdd => 'Duoyi quick shortcut';

  @override
  String get notificationQuickAddTitle => 'Duoyi quick capture';

  @override
  String get notificationQuickAddBody =>
      'Pull down the notification shade to add a task or start focus';

  @override
  String get notificationQuickAddActionAddTodo => 'Add task';

  @override
  String get notificationQuickAddActionOpenInput => 'Open input';

  @override
  String get notificationQuickAddActionStartFocus => 'Start focus';

  @override
  String get notificationQuickAddInputLabel =>
      'Example: meeting tomorrow at 3 PM';

  @override
  String get notificationStatusBarTodayProgressTitle => 'Today progress';

  @override
  String get notificationStatusBarQuickHint =>
      'Pull down to quickly add a task';

  @override
  String get notificationStatusBarTodayRemainingPrefix => '';

  @override
  String get notificationStatusBarTodayRemainingSuffix => ' tasks left today';

  @override
  String get notificationStatusBarDailyCount => 'Daily ';

  @override
  String get notificationStatusBarRepresentativeCount => 'Key ';

  @override
  String get notificationStatusBarGoalCount => 'Goals ';

  @override
  String get quickTodoTitle => 'Quick task';

  @override
  String get quickTodoHint =>
      'Describe it in one line, e.g. meeting tomorrow at 3 PM';

  @override
  String get quickTodoParsedPrefix => 'Detected: ';

  @override
  String get quickAiTitle => 'AI schedule capture';

  @override
  String get quickAiHint => 'Example: prepare Friday report';

  @override
  String get quickAiError => 'AI creation failed. Check AI settings.';

  @override
  String get quickNoteTitle => 'Quick note';

  @override
  String get quickNoteHint => 'Write something...';

  @override
  String get quickMenuAiSchedule => 'AI schedule';

  @override
  String get quickMenuSearch => 'Search';

  @override
  String get quickMenuDiary => 'Diary';

  @override
  String get quickMenuNote => 'Note';

  @override
  String get quickMenuTodo => 'Quick task';

  @override
  String get quickMenuTemplate => 'Templates';

  @override
  String get quickTemplateTitle => 'Quick templates';

  @override
  String get quickTemplateSubtitle =>
      'Apply saved defaults for common tasks or habits';

  @override
  String get quickTemplateSave => 'Save template';

  @override
  String get quickTemplateEmpty => 'No templates yet';

  @override
  String get quickTemplateKindTodo => 'Task';

  @override
  String get quickTemplateKindHabit => 'Habit';

  @override
  String get quickTemplateName => 'Template name';

  @override
  String get quickTemplatePrefix => 'Title prefix';

  @override
  String get quickTemplateTags => 'Tags, separated by commas or spaces';

  @override
  String get quickTemplateList => 'Default list';

  @override
  String get quickTemplatePriority => 'Default priority';

  @override
  String get quickTemplateReminder15 => 'Remind 15 minutes before due time';

  @override
  String get quickTemplateHabitCategory => 'Habit category';

  @override
  String get quickTemplateHabitTarget => 'Daily target';

  @override
  String get quickTemplateHabitUnit => 'Unit';

  @override
  String get quickTemplateHabitReminder => 'Default 21:00 reminder';

  @override
  String get quickTemplateSaved => 'Template saved';

  @override
  String get quickTemplateApplyHint => 'Enter this item';

  @override
  String get quickTemplateTodoDone => 'Task created from template';

  @override
  String get quickTemplateHabitDone => 'Habit created from template';

  @override
  String get searchHint => 'Search tasks, events, habits, notes, diaries...';

  @override
  String get searchEmpty => 'Enter keywords to search everything';

  @override
  String get searchNoResultsPrefix => 'No results for ';

  @override
  String get searchNoResultsSuffix => '';

  @override
  String get searchResultsTitle => 'Search results';

  @override
  String get searchResultsSummaryPrefix => '\"';

  @override
  String get searchResultsSummaryMiddle => '\" found ';

  @override
  String get searchResultsSummarySuffix => ' matches';

  @override
  String get searchClear => 'Clear search';

  @override
  String get searchKindTodo => 'Task';

  @override
  String get searchKindHabit => 'Habit';

  @override
  String get searchKindNote => 'Note';

  @override
  String get searchKindDiary => 'Diary';

  @override
  String get searchKindAnniversary => 'Anniversary';

  @override
  String get searchKindCountdown => 'Countdown';

  @override
  String get searchKindGoal => 'Goal';

  @override
  String get searchKindCourse => 'Course';

  @override
  String get searchKindEvent => 'Event';

  @override
  String get searchKindTimeEntry => 'Time log';

  @override
  String get authLoginTitle => 'Sign in';

  @override
  String get authRegisterTitle => 'Create account';

  @override
  String get authLogin => 'Sign in';

  @override
  String get authRegister => 'Register';

  @override
  String get authLoginSubtitlePassword =>
      'Sign in with username or email for cloud sync and announcements';

  @override
  String get authLoginSubtitleEmailCode => 'Sign in with a verified email code';

  @override
  String get authRegisterSubtitle =>
      'Create an account to enable sync across devices';

  @override
  String get authMaintenance => 'Service is under maintenance';

  @override
  String get authPasswordLogin => 'Password';

  @override
  String get authEmailCodeLogin => 'Email code';

  @override
  String get authUsername => 'Username';

  @override
  String get authAccount => 'Username or email';

  @override
  String get authVerifiedEmail => 'Verified email';

  @override
  String get authEmail => 'Email';

  @override
  String get authEmailOptional => 'Email (optional)';

  @override
  String get authEmailRequiredHelper =>
      'This site requires email verification to register';

  @override
  String get authEmailCode => 'Email code';

  @override
  String get authEmailCodeOptional => 'Email code (optional)';

  @override
  String get authEmailCodeSent => 'Verification code sent. Check your email.';

  @override
  String get authEmailCodeCodePrefix => 'Code: ';

  @override
  String get authDisplayNameOptional => 'Nickname (optional)';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authPassword => 'Password';

  @override
  String get authConfirmPassword => 'Confirm password';

  @override
  String get authNewPassword => 'New password';

  @override
  String get authInviteCode => 'Invite code';

  @override
  String get authSend => 'Send';

  @override
  String get authRegistrationClosed => 'Registration is currently closed';

  @override
  String get authSwitchToLogin => 'Already have an account? Sign in';

  @override
  String get authSwitchToRegister => 'No account? Register';

  @override
  String get authPasswordResetTitle => 'Reset password';

  @override
  String get authPasswordResetEmailSent =>
      'Password reset email sent. Check your mailbox.';

  @override
  String get authPasswordResetDone =>
      'Password reset. Sign in with your new password.';

  @override
  String get authPasswordResetConfirm => 'Reset password';

  @override
  String get authPasswordResetSendEmail => 'Send email';

  @override
  String get authResetAccount => 'Username or bound email';

  @override
  String get authResetAccountHelper =>
      'The code will be sent to the email bound to this account';

  @override
  String get authErrorEmailRequired => 'Enter your email first';

  @override
  String get authErrorEmailInvalid => 'Email format is invalid';

  @override
  String get authErrorUsernameRequired => 'Enter a username';

  @override
  String get authErrorAccountRequired => 'Enter username or email';

  @override
  String get authErrorUsernameLength => 'Username must be 3-64 characters';

  @override
  String get authErrorUsernameNoSpace => 'Username cannot contain whitespace';

  @override
  String get authErrorEmailCodeRequired =>
      'Request and enter the email code first';

  @override
  String get authErrorPasswordShort => 'Password must be at least 6 characters';

  @override
  String get authErrorPasswordMismatch => 'The two passwords do not match';

  @override
  String get authErrorInviteRequired => 'Enter an invite code';

  @override
  String get authErrorVerifiedEmailRequired => 'Enter a verified email';

  @override
  String get authErrorEmailCodeInputRequired => 'Enter the email code';

  @override
  String get authErrorPasswordRequired => 'Enter your password';

  @override
  String get authErrorInvalidCredentials =>
      'Incorrect account or password. Please try again.';

  @override
  String get authErrorResetAccountRequired => 'Enter username or bound email';

  @override
  String get authErrorMailCodeRequired => 'Enter the email code';

  @override
  String get authErrorNewPasswordShort =>
      'New password must be at least 6 characters';

  @override
  String get authErrorNewPasswordMismatch =>
      'The two new passwords do not match';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileNickname => 'Nickname';

  @override
  String get profileDisplayName => 'Display name';

  @override
  String get profileDisplayNameEmpty => 'No nickname set';

  @override
  String get profileLocalNickname => 'Local nickname';

  @override
  String get profileDefaultUser => 'User';

  @override
  String get profileLocal => 'Local profile';

  @override
  String get profileLocalUpdated => 'Local profile updated';

  @override
  String get profileLoginAccount => 'Sign in';

  @override
  String get profileEmailVerified => 'Verified';

  @override
  String get profileEmailUnverified => 'Unverified';

  @override
  String get profileEmailUnverifiedOrPending => 'Unverified or pending';

  @override
  String get profileEmailUnbound => 'No email bound';

  @override
  String get profileEmailBinding => 'Email binding';

  @override
  String get profileEmailLocalDisplay =>
      'Email (local display only, not for sign-in or recovery)';

  @override
  String get profileEmailCodeHelper =>
      'Required when changing or verifying email';

  @override
  String get profileAvatarUrlOrText => 'Avatar URL or text';

  @override
  String get profileAvatarUrlFileOrText => 'Avatar URL, local file, or text';

  @override
  String get profileAvatarHelper =>
      'Choose an image or use text as avatar initials';

  @override
  String get profileAvatarUpload => 'Upload';

  @override
  String get profileAvatarChoose => 'Choose';

  @override
  String get profileAvatarEmpty => 'Avatar file cannot be empty';

  @override
  String get profileAvatarTooLarge => 'Avatar must be no larger than 3 MB';

  @override
  String get profileAvatarUploaded => 'Avatar uploaded';

  @override
  String get profileAvatarSaved => 'Avatar saved';

  @override
  String get profileAvatarSelected => 'Avatar selected. Save to apply it.';

  @override
  String get profileCoins => 'Coins';

  @override
  String get profileAccountId => 'Account';

  @override
  String get profileUsernameLocked =>
      'Username is the unique account ID and cannot be changed here.';

  @override
  String get profileAccountSecurity => 'Account security';

  @override
  String get profileAccountSecuritySubtitle =>
      'Password and sensitive actions are grouped here';

  @override
  String get profileBio => 'Bio';

  @override
  String get profileUpdated => 'Profile updated';

  @override
  String get profileSaved => 'Saved';

  @override
  String get profileSaveFailed => 'Unable to save';

  @override
  String get profileChangePassword => 'Change login password';

  @override
  String get profileChangePasswordSubtitle => 'Current password is required';

  @override
  String get profileCurrentPassword => 'Current password';

  @override
  String get profileConfirmNewPassword => 'Confirm new password';

  @override
  String get profilePasswordUpdated => 'Login password updated';

  @override
  String get profileErrorNicknameRequired => 'Enter a nickname';

  @override
  String get habitDetailTitle => 'Habit details';

  @override
  String get habitDetailNotFound => 'This habit no longer exists';

  @override
  String get habitEditTitle => 'Edit habit';

  @override
  String get habitSaved => 'Saved';

  @override
  String get habitFieldName => 'Habit name';

  @override
  String get habitFieldGroup => 'Group';

  @override
  String get habitFieldGroupEmptyHint => 'Leave empty to keep it ungrouped';

  @override
  String get habitFieldDailyTargetCount => 'Daily target';

  @override
  String get habitFieldUnit => 'Unit';

  @override
  String get habitUnitTimes => 'times';

  @override
  String get habitUnitWeek => 'weeks';

  @override
  String get habitUnitMonth => 'months';

  @override
  String get habitKind => 'Habit type';

  @override
  String get habitKindPositive => '✅ Build habit';

  @override
  String get habitKindNegative => '🚫 Avoid habit';

  @override
  String get habitColor => 'Color';

  @override
  String get habitReminder => 'Reminder';

  @override
  String get habitErrorNameRequired => 'Enter a habit name';

  @override
  String get habitErrorDailyTarget => 'Daily target must be at least 1';

  @override
  String get habitErrorFlexTarget => 'Period target must be at least 1';

  @override
  String get habitErrorDateRange => 'End date cannot be before start date';

  @override
  String get habitErrorNotificationPermission =>
      'Notification permission is not granted, so habit reminders will not ring or pop up';

  @override
  String get habitErrorReminderRegisterFailed =>
      'Habit reminder registration failed';

  @override
  String get habitFlexRule => 'Flexible check-in rule';

  @override
  String get habitFlexWeekly => 'Weekly target';

  @override
  String get habitFlexMonthly => 'Monthly target';

  @override
  String get habitFlexPeriodTarget => 'Target count';

  @override
  String get habitFlexPeriodTargetHint => 'For example, weekly target 5';

  @override
  String get habitFlexDailyNote => 'Off uses the daily target for streaks';

  @override
  String get habitFlexNegativeNote =>
      'Avoid habits are counted by days without records';

  @override
  String get habitFlexWeeklyGoalPrefix => 'Weekly target: ';

  @override
  String get habitFlexMonthlyGoalPrefix => 'Monthly target: ';

  @override
  String get habitFlexThisWeek => 'This week';

  @override
  String get habitFlexThisMonth => 'This month';

  @override
  String get habitDailyPrefix => 'Daily';

  @override
  String get habitRecordedPrefix => 'Recorded ';

  @override
  String get habitStatCurrentStreak => 'Current streak';

  @override
  String get habitStatBestStreak => 'Best streak';

  @override
  String get habitStatToday => 'Today';

  @override
  String get habitHeatmapTitle => 'Check-in heatmap';

  @override
  String get habitRecordsTitle => 'Recent records / make-up';

  @override
  String get habitRecordsInactive => 'Outside active period';

  @override
  String get habitRecordsUndoOnce => 'Undo one';

  @override
  String get habitRecordsRecordOnce => 'Record once';

  @override
  String get habitRecordsMakeUpOnce => 'Make up once';

  @override
  String get habitTrendTitle => 'Habit trend';

  @override
  String get habitTrendCompleted => 'Completed';

  @override
  String get habitTrendDailyAverage => 'Daily avg';

  @override
  String get habitTrendLongestStreak => 'Longest streak';

  @override
  String get habitTrendVsPrevious => 'Vs previous';

  @override
  String get habitTrendBucketDetails => 'Period details';

  @override
  String get habitTrendOneYear => '1 year';

  @override
  String get habitDateRangeTitle => 'Habit period';

  @override
  String get habitDateRangeStart => 'Start date';

  @override
  String get habitDateRangeEnd => 'End date';

  @override
  String get habitDateRangeStartEmpty => 'Start now';

  @override
  String get habitDateRangeEndEmpty => 'No end date';

  @override
  String get habitDateRangePickStart => 'Select start date';

  @override
  String get habitDateRangePickEnd => 'Select end date';

  @override
  String get habitDateRangeLongTerm => 'Long-term';

  @override
  String get habitDateRangeFromSuffix => 'from';

  @override
  String get habitDateRangeUntilSuffix => 'until';

  @override
  String get noteTitle => 'Notes';

  @override
  String get noteEmptyMessage => 'Capture thoughts and ideas anytime';

  @override
  String get noteEmptyAction => 'Write note';

  @override
  String get noteEditTitle => 'Edit note';

  @override
  String get notePreview => 'Preview';

  @override
  String get noteEdit => 'Edit';

  @override
  String get noteSearchHint => 'Search title, body, or attachments';

  @override
  String get noteSearchClear => 'Clear search';

  @override
  String get noteSearchEmpty => 'No matching notes';

  @override
  String get noteActive => 'All';

  @override
  String get noteArchived => 'Archived';

  @override
  String get noteArchivedEmpty => 'No archived notes';

  @override
  String get noteMore => 'More actions';

  @override
  String get notePin => 'Pin';

  @override
  String get noteUnpin => 'Unpin';

  @override
  String get noteArchive => 'Archive';

  @override
  String get noteRestore => 'Restore';

  @override
  String get noteLinkPlaceholder => 'Link text';

  @override
  String get noteAttachmentPickFile => 'Choose from system files';

  @override
  String get noteAttachmentPickFileSubtitle =>
      'Images, PDFs, and documents are saved as attachments';

  @override
  String get noteAttachmentAddLink => 'Add link or local path';

  @override
  String get noteAttachmentAddLinkSubtitle =>
      'For web images, references, and known file paths';

  @override
  String get noteAttachmentFileNotSelected =>
      'No file selected. Switched to manual entry.';

  @override
  String get noteAttachmentDialogTitle => 'Add attachment';

  @override
  String get noteAttachmentName => 'Name';

  @override
  String get noteAttachmentUri => 'Link or local path';

  @override
  String get noteAttachmentUriHint => 'https://... or /storage/...';

  @override
  String get noteAttachmentType => 'Type (optional)';

  @override
  String get noteAttachmentTypeHint => 'Example: image/png, application/pdf';

  @override
  String get noteAttachmentDefaultName => 'Attachment';

  @override
  String get noteEditorHint =>
      'Write something. Markdown, checklists, and attachments are supported...';

  @override
  String get noteToolbarHeading => 'Heading';

  @override
  String get noteToolbarBold => 'Bold';

  @override
  String get noteToolbarItalic => 'Italic';

  @override
  String get noteToolbarQuote => 'Quote';

  @override
  String get noteToolbarBullet => 'Bulleted list';

  @override
  String get noteToolbarChecklist => 'Checklist';

  @override
  String get noteToolbarCode => 'Inline code';

  @override
  String get noteToolbarLink => 'Link';

  @override
  String get noteToolbarAttachment => 'Attachment';

  @override
  String get notePreviewEmpty => 'Blank note';

  @override
  String get feedbackCategoryFeature => 'Feature request';

  @override
  String get feedbackCategoryBug => 'Bug report';

  @override
  String get feedbackCategoryWish => 'Wish list';

  @override
  String get feedbackCategoryOther => 'Other';

  @override
  String get feedbackHelpFeature =>
      'Describe the feature you want to add or improve';

  @override
  String get feedbackHelpBug =>
      'Describe reproduction steps, current behavior, and expected behavior';

  @override
  String get feedbackHelpWish =>
      'Describe the scenario or capability you want added';

  @override
  String get feedbackHelpOther => 'Add anything else you want the team to know';

  @override
  String get feedbackStatusResolved => 'Resolved';

  @override
  String get feedbackStatusClosed => 'Closed';

  @override
  String get feedbackStatusInProgress => 'In progress';

  @override
  String get feedbackStatusOpen => 'Open';

  @override
  String get feedbackLoginRecordsRequired => 'Sign in to view feedback history';

  @override
  String get feedbackLoginSubmitRequired =>
      'Sign in before submitting feedback';

  @override
  String get feedbackLoginSubtitle =>
      'Sign in to submit feedback and view handling history';

  @override
  String get feedbackLoginSectionSubtitle =>
      'You are not signed in, so feedback cannot be submitted or reviewed';

  @override
  String get feedbackContentEmpty => 'Feedback content cannot be empty';

  @override
  String get feedbackSubmitted => 'Feedback submitted. Thank you!';

  @override
  String get feedbackSubmitPrefix => 'Submit ';

  @override
  String get feedbackSubmitLoginPrefix => 'Sign in to submit ';

  @override
  String get feedbackCategoryLabel => 'Category';

  @override
  String get feedbackContentLabelPrefix => 'Describe your ';

  @override
  String get feedbackSubmitButton => 'Submit feedback';

  @override
  String get feedbackSubmitting => 'Submitting';

  @override
  String get feedbackMineTitle => 'My feedback';

  @override
  String get feedbackLoading => 'Loading';

  @override
  String get feedbackRecent => 'Recent submissions';

  @override
  String get feedbackEmpty => 'No feedback yet';

  @override
  String get feedbackRefresh => 'Refresh';

  @override
  String get feedbackAdminReply => 'Admin reply';

  @override
  String get announcementTitle => 'Announcements';

  @override
  String get announcementCenter => 'Announcement Center';

  @override
  String get announcementSubtitle =>
      'System notices, maintenance updates, and release notes appear here first';

  @override
  String get announcementLatest => 'Latest announcements';

  @override
  String get announcementPullToRefresh => 'Pull down to refresh';

  @override
  String get announcementEmpty => 'No announcements';

  @override
  String get announcementRefresh => 'Refresh';

  @override
  String get announcementLoadFailedPrefix => 'Announcements failed to load: ';

  @override
  String get announcementLevelInfo => 'Announcement';

  @override
  String get announcementLevelWarning => 'Notice';

  @override
  String get announcementLevelCritical => 'Important';

  @override
  String get themeTitle => 'Theme style';

  @override
  String get themeSectionStyles => 'Available styles';

  @override
  String get themeSectionStylesSubtitle => 'Changes apply to the whole app';

  @override
  String get themeStyleDefaultName => 'Duoyi';

  @override
  String get themeStyleDefaultDescription =>
      'Clean original · warm orange base';

  @override
  String get themeStyleRe0Name => 'Re:Zero';

  @override
  String get themeStyleRe0Description =>
      'Silver-haired witch · Lugunica sanctuary';

  @override
  String get themeStyleGenshinName => 'Genshin Impact';

  @override
  String get themeStyleGenshinDescription => 'Elemental scroll · Teyvat easel';

  @override
  String get themeStyleStarRailName => 'Honkai: Star Rail';

  @override
  String get themeStyleStarRailDescription =>
      'Astral Express · trailblazing journey';

  @override
  String get themeStyleWutheringName => 'Wuthering Waves';

  @override
  String get themeStyleWutheringDescription =>
      'Resonance terminal · tidal spectrum';

  @override
  String get themeStyleZzzName => 'Zenless Zone Zero';

  @override
  String get themeStyleZzzDescription => 'Commission footage · New Eridu';

  @override
  String get themeStyleYanyunName => 'Where Winds Meet';

  @override
  String get themeStyleYanyunDescription => 'Jianghu sketchbook · ink trails';

  @override
  String get themeStyleBotwName => 'Sheikah Slate';

  @override
  String get themeStyleBotwDescription => 'Sheikah Slate · materialized';

  @override
  String get goalTitle => 'Goals';

  @override
  String get goalRecommendedTemplates => 'Recommended templates';

  @override
  String get goalEmpty => 'Set a goal and let time compound for you';

  @override
  String get goalCreate => 'Create goal';

  @override
  String get goalNew => 'New goal';

  @override
  String get goalStatusActive => 'Active';

  @override
  String get goalStatusPaused => 'Paused';

  @override
  String get goalStatusAchieved => 'Achieved';

  @override
  String get goalStatusAbandoned => 'Abandoned';

  @override
  String get goalMilestonePrefix => 'Milestones ';

  @override
  String get goalDaysRemainingPrefix => '';

  @override
  String get goalDaysRemainingSuffix => ' days left';

  @override
  String get goalOverduePrefix => '';

  @override
  String get goalOverdueSuffix => ' days overdue';

  @override
  String get exportTitle => 'Export as calendar (.ics)';

  @override
  String get exportHeroTitle => 'Calendar export';

  @override
  String get exportHeroSubtitle =>
      'Generate an iCalendar file for system calendars, Google Calendar, or Outlook.';

  @override
  String get exportRangeTitle => 'Export range';

  @override
  String get exportRangeSubtitle => 'Choose what to include';

  @override
  String get exportIncludeAnniversaries =>
      'Include anniversaries and birthdays';

  @override
  String get exportIncludeAnniversariesSubtitle => 'YEARLY recurring events';

  @override
  String get exportIncludeCalendar => 'Include full schedule';

  @override
  String get exportIncludeCalendarSubtitle =>
      'Tasks, habits, courses, diary, and goals';

  @override
  String get exportPushCaldav => 'Push to CalDAV';

  @override
  String get exportGenerateIcs => 'Generate .ics';

  @override
  String get exportContentTitle => 'Export content';

  @override
  String get exportCopy => 'Copy';

  @override
  String get exportCopyDone => '.ics content copied';

  @override
  String get exportCaldavSuccessPrefix => 'Pushed ';

  @override
  String get exportCaldavSuccessSuffix => ' calendar events to CalDAV';

  @override
  String get exportCaldavConflictPrefix => 'Pushed ';

  @override
  String get exportCaldavConflictMiddle => ', skipped ';

  @override
  String get exportCaldavConflictSuffix => ' remote modified events';

  @override
  String get exportCaldavFailedPrefix => 'CalDAV push failed: ';

  @override
  String get appLockTitle => 'App lock';

  @override
  String get appLockHeroTitle => 'Local PIN lock';

  @override
  String get appLockHeroSubtitle =>
      'Protect local data and require verification when returning or restarting';

  @override
  String get appLockSectionStatus => 'Lock status';

  @override
  String get appLockSectionStatusSubtitle =>
      'Require a PIN at startup or when returning to the foreground';

  @override
  String get appLockEnable => 'Enable app lock';

  @override
  String get appLockEnabled => 'Enabled';

  @override
  String get appLockDisabledSubtitle =>
      'No PIN will be required while disabled';

  @override
  String get appLockChangePin => 'Change PIN';

  @override
  String get appLockChangePinSubtitle => 'Set a new 4-8 digit PIN';

  @override
  String get appLockAutoLock => 'Auto lock';

  @override
  String get appLockAutoLockImmediate => 'Immediately';

  @override
  String get appLockAutoLockEveryForeground => 'Lock whenever the app returns';

  @override
  String get appLockAutoLockAfterPrefix => 'Lock after ';

  @override
  String get appLockAutoLockAfterSuffix => ' min in background';

  @override
  String get appLockAutoLockMinuteLabel => ' min';

  @override
  String get appLockAutoLockOneHour => '1 hour';

  @override
  String get appLockAutoLockFourHours => '4 hours';

  @override
  String get appLockLockNow => 'Lock now';

  @override
  String get appLockLockNowSubtitle => 'Return to PIN entry immediately';

  @override
  String get appLockTip =>
      'Tip: App lock only protects this device. Cloud data is not affected. If you forget the PIN, clearing app data is the only recovery path.';

  @override
  String get appLockDialogSetPin => 'Set PIN (4-8 digits)';

  @override
  String get appLockDialogConfirmPin => 'Enter it again to confirm';

  @override
  String get appLockDialogDisablePin => 'Enter current PIN to disable';

  @override
  String get appLockPinHint => '4-8 digits';

  @override
  String get appLockPinMismatch => 'The two PIN entries do not match';

  @override
  String get appLockPinInvalid => 'A 4-8 digit PIN is required';

  @override
  String get appLockPinWrong => 'Incorrect PIN';

  @override
  String get appLockEnabledMessage => 'App lock enabled';

  @override
  String get appLockDisabledMessage => 'App lock disabled';

  @override
  String get aiHistoryTitle => 'AI weekly review history';

  @override
  String get aiHistoryClearTooltip => 'Clear history';

  @override
  String get aiHistoryClearTitle => 'Clear all reviews?';

  @override
  String get aiHistoryClearContent =>
      'Locally saved AI reviews will be deleted and cannot be recovered';

  @override
  String get aiHistoryClearAction => 'Clear';

  @override
  String get aiHistoryEmpty =>
      'No AI reviews yet\nGenerate one from the Me page';

  @override
  String get aiHistoryCopy => 'Copy';

  @override
  String get aiHistoryCopyDone => 'Copied';

  @override
  String get aiHistoryDelete => 'Delete';

  @override
  String get syncConflictTitle => 'Sync conflict log';

  @override
  String get syncConflictEmpty => 'No sync conflicts yet';

  @override
  String get syncConflictKeepRemote => 'Kept cloud version';

  @override
  String get syncConflictKeepLocal => 'Kept local version';

  @override
  String get syncConflictType => 'Type';

  @override
  String get syncConflictItem => 'Item';

  @override
  String get syncConflictWorkspace => 'Space';

  @override
  String get syncConflictLocal => 'Local';

  @override
  String get syncConflictRemote => 'Cloud';

  @override
  String get todayAlmanacTitle => 'Almanac';

  @override
  String get todayUnitItem => 'items';

  @override
  String get todayUnitTimes => 'times';

  @override
  String get todayUnitCourseSection => 'classes';

  @override
  String get todayUnitPoint => 'pts';

  @override
  String get todayDiary => 'Diary';

  @override
  String get todayDiaryWritten => 'Done';

  @override
  String get todayDiaryUnwritten => 'Not yet';

  @override
  String get todaySuggestions => 'Today suggestions';

  @override
  String get todaySuggestionsSubtitle =>
      'Recommended by due time, priority, and Eisenhower quadrant';

  @override
  String get todayAddedPrefix => 'Added to today: ';

  @override
  String get todayAddToToday => 'Add to today';

  @override
  String get todayTodos => 'Today tasks';

  @override
  String get todayCompleted => 'Completed';

  @override
  String get todayCourses => 'Today classes';

  @override
  String get todayCoursePeriodPrefix => 'Periods ';

  @override
  String get todayCoursePeriodSuffix => '';

  @override
  String get todayUpcomingAnniversaries => 'Upcoming anniversaries';

  @override
  String get todayAnniversaryToday => 'Today';

  @override
  String get todayAnniversaryDaysPrefix => 'In ';

  @override
  String get todayActiveGoals => 'Active goals';

  @override
  String get todayGoalCreateSubtitle =>
      'Create directly from Today without opening goal management';

  @override
  String get todayView => 'View';

  @override
  String get todayProductivityScore => 'Score';

  @override
  String get todayProductivityWeekly => 'This week';

  @override
  String get todayProductivityFlat => 'Flat';

  @override
  String get todayProductivitySubtitle =>
      'Compared with the same days last week · open statistics';

  @override
  String get todayProductivityCompletionRate => 'Completion';

  @override
  String get diaryTitle => 'Diary';

  @override
  String get diaryWrite => 'Write diary';

  @override
  String get diaryEmptyMessage => 'Start recording your mood each day';

  @override
  String get diaryStatsTooltip => 'Mood stats';

  @override
  String get diarySummaryTitle => 'Writing overview';

  @override
  String get diarySummarySubtitle => 'Total, this month, and current streak';

  @override
  String get diarySummaryTotal => 'Total';

  @override
  String get diarySummaryThisMonth => 'This month';

  @override
  String get diarySummaryStreak => 'Streak';

  @override
  String get diaryRecentTitle => 'Recent diary';

  @override
  String get diaryRecentRecordsSuffix => ' entries';

  @override
  String get diaryEntryCountSuffix => ' entries';

  @override
  String get diaryMoodStatsTitle => 'Mood distribution, last 30 days';

  @override
  String get diaryNoData => 'No data yet';

  @override
  String get diaryAiInsights => 'AI diary insights';

  @override
  String get diaryAiDeepReviewTooltip => 'AI deep review';

  @override
  String get diaryAiDeepReviewTitle => 'AI diary deep review';

  @override
  String get diaryAiDisabled => 'AI is not enabled. Contact the administrator.';

  @override
  String get diaryAiReviewFailedPrefix => 'AI diary review failed: ';

  @override
  String get diaryEditorDateTitle => 'Diary date';

  @override
  String get diaryEditorMoodPrompt => 'How do you feel today?';

  @override
  String get diaryEditorWeather => 'Weather';

  @override
  String get diaryEditorTagHint => 'Add tag (e.g. study, travel)';

  @override
  String get diaryEditorContentHint => 'Write today\'s story...';

  @override
  String get diaryMoodAwesome => 'Great';

  @override
  String get diaryMoodGood => 'Good';

  @override
  String get diaryMoodOkay => 'Calm';

  @override
  String get diaryMoodBad => 'Low';

  @override
  String get diaryMoodTerrible => 'Terrible';

  @override
  String get diaryWeatherSunny => 'Sunny';

  @override
  String get diaryWeatherCloudy => 'Cloudy';

  @override
  String get diaryWeatherOvercast => 'Overcast';

  @override
  String get diaryWeatherRain => 'Rain';

  @override
  String get diaryWeatherSnow => 'Snow';

  @override
  String get diaryWeatherWind => 'Wind';

  @override
  String get diaryWeatherFog => 'Fog';

  @override
  String get diaryWeatherThunder => 'Thunder';

  @override
  String get countdownTitle => 'Countdown';

  @override
  String get countdownEmpty => 'No countdowns yet';

  @override
  String get countdownNearestEmpty => 'No upcoming events';

  @override
  String get countdownNearestPrefix => 'Next: ';

  @override
  String get countdownNearestDaysPrefix => 'in ';

  @override
  String get countdownSummaryTotal => 'Total';

  @override
  String get countdownSummaryWithin7Days => 'Within 7 days';

  @override
  String get countdownListTitle => 'All countdowns';

  @override
  String get countdownListSubtitle => 'Sorted by priority and remaining days';

  @override
  String get countdownCategoryDefault => 'Default';

  @override
  String get countdownEditorEditTitle => 'Edit countdown';

  @override
  String get countdownEditorSubtitle =>
      'Category, target date, and reminders sync to calendar';

  @override
  String get countdownFieldTitle => 'Event name';

  @override
  String get countdownFieldCategory => 'Category';

  @override
  String get countdownFieldTargetDate => 'Target date';

  @override
  String get countdownFieldDueReminder => 'Due reminder';

  @override
  String get countdownFieldRemindDays => 'Days before';

  @override
  String get countdownFieldRemindTime => 'Reminder time';

  @override
  String get countdownReminderClosed => 'Off';

  @override
  String get countdownReminderBeforePrefix => '';

  @override
  String get countdownReminderBeforeSuffix => ' days before';

  @override
  String get countdownValidationTitleRequired => 'Enter a countdown name first';

  @override
  String get countdownSaved => 'Countdown saved';

  @override
  String get countdownSaveFailedPrefix => 'Failed to save countdown: ';

  @override
  String get countdownReminderRegisterFailed =>
      'Countdown reminder registration failed';

  @override
  String get countdownReminderNotRegistered =>
      'Countdown saved, but the reminder was not registered. Check notification permission and reminder time.';

  @override
  String get countdownReminderNotRegisteredPrefix =>
      'Countdown saved, but the reminder was not registered: ';

  @override
  String get countdownReminderPopupFallbackFailed =>
      'Countdown reminder registration failed: pop-up notification fallback unavailable';

  @override
  String get countdownReminderPopupPermissionDenied =>
      'Countdown saved, but the pop-up reminder was not registered: notification permission is off.';

  @override
  String get countdownReminderPopupNotRegisteredPrefix =>
      'Countdown saved, but the pop-up reminder was not registered: ';

  @override
  String get countdownReminderPopupWarning =>
      'Countdown saved. Pop-ups show only while the app is running; system notification is used as background or lock-screen fallback.';

  @override
  String get countdownReminderAlarmPermissionDenied =>
      'Countdown saved, but the alarm reminder was not registered: enable notification permission and save again.';

  @override
  String get countdownReminderAlarmChannelMissing =>
      'Alarm channel is not ready';

  @override
  String get countdownReminderExactAlarmMissing =>
      'Exact alarm permission is off, so the reminder may be delayed';

  @override
  String get countdownReminderFullscreenMissing =>
      'Full-screen reminder permission is off, so lock-screen pop-up may not work';

  @override
  String get countdownReminderSavedWithWarningsPrefix => 'Countdown saved, ';

  @override
  String get countdownReminderEmailWarning =>
      'Countdown saved, and email reminders will be sent by the server when online.';

  @override
  String get countdownReminderExceptionPrefix =>
      'Countdown saved, but the reminder was not registered: ';

  @override
  String get countdownReminderTimePast =>
      'Countdown saved, but the reminder time is already in the past. Please choose another reminder time.';

  @override
  String get countdownStatusPinned => 'Pinned';

  @override
  String get countdownStatusExpired => 'Expired';

  @override
  String get countdownStatusSoon => 'Soon';

  @override
  String get countdownStatusRunning => 'Counting down';

  @override
  String get countdownTargetPrefix => 'Target: ';

  @override
  String get countdownDaysElapsed => 'Elapsed';

  @override
  String get countdownDaysRemaining => 'Left';

  @override
  String get anniversaryTitle => 'Anniversary';

  @override
  String get anniversaryBirthday => 'Birthday';

  @override
  String get anniversaryCountdownShort => 'Countdown';

  @override
  String get anniversaryCustom => 'Custom';

  @override
  String get anniversaryTabAll => 'All';

  @override
  String get anniversaryUpcoming30Days => 'Next 30 days';

  @override
  String get anniversaryEmpty => 'No anniversaries yet';

  @override
  String get anniversaryUpcomingEmpty => 'No events in the next 30 days';

  @override
  String get anniversaryDeleteTitle => 'Delete?';

  @override
  String get anniversaryDeleteContentSuffix => 'will be removed';

  @override
  String get anniversaryOccurrencePrefix => '#';

  @override
  String get anniversaryOccurrenceSuffix => '';

  @override
  String get anniversaryYearsElapsedPrefix => '';

  @override
  String get anniversaryYearsElapsedSuffix => ' years';

  @override
  String get anniversaryNextPrefix => 'Next: ';

  @override
  String get anniversaryTodayShort => 'Today';

  @override
  String get anniversaryEditorAddTitle => 'Add anniversary';

  @override
  String get anniversaryEditorEditTitle => 'Edit anniversary';

  @override
  String get anniversaryFieldTitle => 'Title';

  @override
  String get anniversaryFieldTitleHint =>
      'e.g. Mom birthday / wedding anniversary';

  @override
  String get anniversaryFieldDescription => 'Note (optional)';

  @override
  String get anniversaryFieldType => 'Type';

  @override
  String get anniversaryFieldDateType => 'Date type';

  @override
  String get anniversaryFieldDatePickerTitle => 'Select date';

  @override
  String get anniversaryFieldDatePickerSubtitle =>
      'Solar and lunar dates use separate pickers';

  @override
  String get anniversaryFieldColor => 'Color marker';

  @override
  String get anniversaryValidationTitleRequired => 'Enter a title first';

  @override
  String get anniversarySaved => 'Saved';

  @override
  String get anniversarySaveFailedPrefix => 'Failed to save anniversary: ';

  @override
  String get anniversaryReminderRegisterFailed =>
      'Anniversary reminder registration failed';

  @override
  String get anniversaryReminderNotRegistered =>
      'Anniversary reminder was not registered. Check notification permission and reminder time.';

  @override
  String get anniversaryReminderPopupFallbackFailed =>
      'Anniversary reminder registration failed: pop-up notification fallback unavailable';

  @override
  String get anniversaryReminderPopupPermissionDenied =>
      'Pop-up reminder was not registered: notification permission is off.';

  @override
  String get anniversaryReminderPopupNotRegisteredPrefix =>
      'Pop-up reminder was not registered: ';

  @override
  String get anniversaryReminderPopupWarning =>
      'Pop-ups show only while the app is running; system notification is used as background or lock-screen fallback.';

  @override
  String get anniversaryReminderAlarmPermissionDenied =>
      'Alarm reminder was not registered: enable notification permission and save again.';

  @override
  String get anniversaryReminderAlarmChannelMissing =>
      'Alarm channel is not ready';

  @override
  String get anniversaryReminderExactAlarmMissing =>
      'Exact alarm permission is off, so the reminder may be delayed';

  @override
  String get anniversaryReminderFullscreenMissing =>
      'Full-screen reminder permission is off, so lock-screen pop-up may not work';

  @override
  String get anniversaryReminderEmailWarning =>
      'Email reminder will be sent by the server when online.';

  @override
  String get anniversaryReminderExceptionPrefix =>
      'Reminder was not registered: ';

  @override
  String get anniversaryReminderSavedPrefix => 'Saved, ';

  @override
  String get anniversaryReminderTimePast =>
      'Saved, but the reminder time is already in the past. Please choose another reminder time.';

  @override
  String get anniversaryLunarYearSuffix => '';

  @override
  String get courseWeekPrefix => 'Week ';

  @override
  String get courseWeekSuffix => '';

  @override
  String get courseWeekCountSuffix => ' weeks';

  @override
  String get courseWeekCurrentTooltip => 'Back to current week';

  @override
  String get courseEmptyMessage => 'Add courses to see your weekly schedule';

  @override
  String get courseAdd => 'Add course';

  @override
  String get courseWeekPickerTitle => 'Select week';

  @override
  String get courseWeekPickerSubtitle => 'Switch the timetable week';

  @override
  String get courseWeeksAll => 'All weeks';

  @override
  String get courseWeeksOdd => 'Odd weeks';

  @override
  String get courseWeeksEven => 'Even weeks';

  @override
  String get courseWeeksSelectAll => 'Select all';

  @override
  String get courseSettingsTitle => 'Timetable settings';

  @override
  String get courseSettingsSubtitle => 'Adjust term start and display density';

  @override
  String get courseSettingsPreviewPrefix => 'Session preview: ';

  @override
  String get courseEditorAddTitle => 'Add course';

  @override
  String get courseEditorEditTitle => 'Edit course';

  @override
  String get courseEditorSubtitle => 'Organize by week, session, and color';

  @override
  String get courseFieldTermStart => 'Term start date (Monday of week 1)';

  @override
  String get courseFieldTermStartPicker => 'Term start date';

  @override
  String get courseFieldTotalWeeks => 'Total weeks';

  @override
  String get courseFieldSessionsPerDay => 'Sessions per day';

  @override
  String get courseFieldSessionMinutes => 'Minutes per session';

  @override
  String get courseFieldFirstSessionTime => 'First session start';

  @override
  String get courseFieldFirstSessionTimeSubtitle =>
      'Later sessions are calculated from this time';

  @override
  String get courseFieldBreakMinutes => 'Break minutes';

  @override
  String get courseFieldName => 'Course name';

  @override
  String get courseFieldTeacher => 'Teacher';

  @override
  String get courseFieldLocation => 'Classroom';

  @override
  String get courseFieldWeekday => 'Weekday';

  @override
  String get courseFieldStartSection => 'Start session';

  @override
  String get courseFieldSectionCount => 'Session count';

  @override
  String get courseFieldClassWeeks => 'Class weeks';

  @override
  String get courseFieldColor => 'Color';

  @override
  String get todoEmpty => 'Nothing scheduled today. Add one?';

  @override
  String get todoAdd => 'Add task';

  @override
  String get todoMatrix => 'Matrix';

  @override
  String get todoList => 'List';

  @override
  String get todoPostpone => 'Postpone';

  @override
  String get todoPriorityNone => 'None';

  @override
  String get todoPriorityLow => 'Low';

  @override
  String get todoPriorityMedium => 'Medium';

  @override
  String get todoPriorityHigh => 'High';

  @override
  String get todoPriorityUrgent => 'Urgent';

  @override
  String get calendarMonth => 'Month';

  @override
  String get calendarWeek => 'Week';

  @override
  String get calendarDay => 'Day';

  @override
  String get calendarEmpty => 'No events on this day';

  @override
  String get focusStart => 'Start focus';

  @override
  String get focusPause => 'Pause';

  @override
  String get focusResume => 'Resume';

  @override
  String get focusReset => 'Reset';

  @override
  String get reminderHealth => 'Notifications';

  @override
  String get reminderTestNotification => 'Send test notification';

  @override
  String get reminderSnooze5min => 'In 5 min';

  @override
  String get reminderSnooze10min => 'In 10 min';

  @override
  String get reminderSnooze30min => 'In 30 min';

  @override
  String get reminderKindPush => 'Notification';

  @override
  String get reminderKindPopup => 'Pop-up';

  @override
  String get reminderKindAlarm => 'Alarm';

  @override
  String get reminderKindOff => 'Off';

  @override
  String get timeAuditTitle => 'Time Tracking';

  @override
  String get timeAuditAddManual => 'Add entry';

  @override
  String get timeAuditWeeklyOverview => 'This week';

  @override
  String get timeAuditCopyReport => 'Copy report';

  @override
  String get timeAuditReportCopied => 'Time tracking report copied';

  @override
  String get timeAuditRangeToday => 'Today';

  @override
  String get timeAuditRangeWeek => 'This week';

  @override
  String get timeAuditRangeMonth => 'This month';

  @override
  String get timeAuditRangeAll => 'All';

  @override
  String get timeAuditSegmentToday => 'Today';

  @override
  String get timeAuditViewTimeline => 'Timeline';

  @override
  String get timeAuditViewCategory => 'Category';

  @override
  String get timeAuditViewCalendar => 'Calendar';

  @override
  String get timeAuditViewTrend => 'Trend';

  @override
  String get timeAuditEmptySuffix => ' has no time entries';

  @override
  String get timeAuditCategoryView => 'Category view';

  @override
  String get timeAuditSourceBreakdown => 'Source breakdown';

  @override
  String get timeAuditCalendarView => 'Calendar view';

  @override
  String get timeAuditTrendView => 'Trend view';

  @override
  String get timeAuditInvestmentSuffix => ' investment';

  @override
  String get timeAuditEntryCount => 'Entries';

  @override
  String get timeAuditEntryCountSuffix => ' entries';

  @override
  String get timeAuditDefaultTitle => 'Time entry';

  @override
  String get timeAuditSheetAddTitle => 'Add time entry';

  @override
  String get timeAuditSheetEditTitle => 'Edit time entry';

  @override
  String get timeAuditFieldTitle => 'Title';

  @override
  String get timeAuditFieldCategory => 'Category';

  @override
  String get timeAuditFieldStart => 'Start';

  @override
  String get timeAuditFieldEnd => 'End';

  @override
  String get timeAuditFieldMinutes => 'Minutes';

  @override
  String get timeAuditFieldNote => 'Note';

  @override
  String get timeAuditPickerStartDate => 'Start date';

  @override
  String get timeAuditPickerStartTime => 'Start time';

  @override
  String get timeAuditPickerEndDate => 'End date';

  @override
  String get timeAuditPickerEndTime => 'End time';

  @override
  String get timeAuditReportTitle => 'Time tracking report';

  @override
  String get timeAuditReportRange => 'Range';

  @override
  String get timeAuditReportTotal => 'Total investment';

  @override
  String get timeAuditReportCategory => 'Category breakdown';

  @override
  String get timeAuditReportDetails => 'Details';

  @override
  String get shareTitle => 'Shared Spaces';

  @override
  String get shareCreateInvite => 'Create invite code';

  @override
  String get shareAcceptInvite => 'Join space';

  @override
  String get shareRoleOwner => 'Owner';

  @override
  String get shareRoleEditor => 'Editor';

  @override
  String get shareRoleViewer => 'Viewer';

  @override
  String get unitMinute => 'minutes';

  @override
  String get unitMin => 'min';

  @override
  String get unitHour => 'hours';

  @override
  String get unitDay => 'days';

  @override
  String get repeatEveryDay => 'Every day';

  @override
  String get repeatWeekdays => 'Weekdays';
}
