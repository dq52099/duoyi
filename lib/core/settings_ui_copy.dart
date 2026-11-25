/// Settings UI localization and dynamic copy getters (Task: iOS style & i18n).
library;

import 'i18n.dart';
import 'calendar_date_navigation.dart';
import '../l10n/generated/app_localizations.dart';

class SettingsUiCopy {
  SettingsUiCopy._();

  static bool get isZh => I18n.current == AppLocale.zh;

  static AppLocalizations _l10n() =>
      lookupAppLocalizations(I18n.current.flutterLocale);

  static String get saveFailed => _l10n().settingsUiSaveFailed;

  static String get decreaseValue => _l10n().settingsUiDecreaseValue;
  static String get increaseValue => _l10n().settingsUiIncreaseValue;
  static String decreaseSetting(String title) =>
      _l10n().settingsUiDecreaseSetting(title);
  static String increaseSetting(String title) =>
      _l10n().settingsUiIncreaseSetting(title);

  static String firstWeekdayLabel(int value) {
    final localizations = _l10n();
    return [
      localizations.weekdayMon,
      localizations.weekdayTue,
      localizations.weekdayWed,
      localizations.weekdayThu,
      localizations.weekdayFri,
      localizations.weekdaySat,
      localizations.weekdaySun,
    ][CalendarDateNavigation.normalizeFirstDayOfWeek(value) - 1];
  }

  static String currentFirstWeekday(int value) =>
      _l10n().settingsUiCurrentFirstWeekday(firstWeekdayLabel(value));

  // Preferences Screen
  static String get preferencesTitle => _l10n().preferencesTitle;

  static String get preferencesHeroExplanation =>
      _l10n().settingsUiPreferencesHeroExplanation;

  static String get preferencesCategoriesSectionTitle =>
      _l10n().settingsUiPreferencesCategoriesSectionTitle;

  static String get preferencesCategoriesSectionSubtitle =>
      _l10n().settingsUiPreferencesCategoriesSectionSubtitle;

  static String get displayAndBehaviorTitle =>
      _l10n().settingsUiDisplayAndBehaviorTitle;

  static String get displayAndBehaviorSubtitle =>
      _l10n().settingsUiDisplayAndBehaviorSubtitle;

  static String get displayAndBehaviorHeroSubtitle =>
      _l10n().settingsUiDisplayAndBehaviorHeroSubtitle;

  static String get navigationSectionTitle =>
      _l10n().settingsUiNavigationSectionTitle;

  static String get navigationSectionSubtitle =>
      _l10n().settingsUiNavigationSectionSubtitle;

  // Personalization Section Menu
  static String get jumpToMenuTitle => _l10n().settingsUiJumpToMenuTitle;
  static String get jumpToDate => _l10n().settingsUiJumpToDate;
  static String get jumpToDefaults => _l10n().settingsUiJumpToDefaults;
  static String get jumpToInteraction => _l10n().settingsUiJumpToInteraction;

  // Date Formats
  static const List<String> supportedDateFormatPatterns = [
    'yyyy-MM-dd',
    'MM/dd/yyyy',
    'dd/MM/yyyy',
    'yyyy年M月d日',
  ];

  static String dateFormatLabel(String pattern) {
    return switch (pattern) {
      'yyyy-MM-dd' => _l10n().settingsUiDateFormatIso(pattern),
      'MM/dd/yyyy' => _l10n().settingsUiDateFormatUs(pattern),
      'dd/MM/yyyy' => _l10n().settingsUiDateFormatEurope(pattern),
      'yyyy年M月d日' => _l10n().settingsUiDateFormatEastAsian(pattern),
      _ => pattern,
    };
  }

  /// Sample caption demonstrating the pattern on a fixed reference date (2026-05-07).
  /// Note: Chinese glyphs are intentionally preserved for 'yyyy年M月d日' in all locales
  /// because they represent the exact syntax and appearance of that format.
  static String dateFormatSample(String pattern) {
    return switch (pattern) {
      'yyyy-MM-dd' => '2026-05-07',
      'MM/dd/yyyy' => '05/07/2026',
      'dd/MM/yyyy' => '07/05/2026',
      'yyyy年M月d日' => '2026年5月7日',
      _ => '2026-05-07',
    };
  }

  // Timezones
  static const List<String> supportedTimeZoneIds = [
    'system',
    'Asia/Shanghai',
    'America/Mexico_City',
    'America/Tijuana',
    'Asia/Tokyo',
    'Asia/Hong_Kong',
    'Asia/Singapore',
    'America/New_York',
    'America/Los_Angeles',
    'Europe/London',
    'Europe/Paris',
    'Australia/Sydney',
  ];

  static String timeZoneDisplayName(String id) {
    return switch (id) {
      'system' => _l10n().preferencesTimezoneFollowSystem,
      'Asia/Shanghai' => _l10n().settingsUiTimeZoneShanghai,
      'America/Mexico_City' => _l10n().settingsUiTimeZoneMexicoCity,
      'America/Tijuana' => _l10n().settingsUiTimeZoneTijuana,
      'Asia/Tokyo' => _l10n().settingsUiTimeZoneTokyo,
      'Asia/Hong_Kong' => _l10n().settingsUiTimeZoneHongKong,
      'Asia/Singapore' => _l10n().settingsUiTimeZoneSingapore,
      'America/New_York' => _l10n().settingsUiTimeZoneNewYork,
      'America/Los_Angeles' => _l10n().settingsUiTimeZoneLosAngeles,
      // London observes BST in summer and GMT in winter; use neutral London wording.
      'Europe/London' => _l10n().settingsUiTimeZoneLondon,
      'Europe/Paris' => _l10n().settingsUiTimeZoneParis,
      'Australia/Sydney' => _l10n().settingsUiTimeZoneSydney,
      _ => id,
    };
  }

  // Navigation / Bottom nav
  static String get navigationBannerMessage =>
      _l10n().settingsUiNavigationBannerMessage;

  static String maxTabsConstraint(int max) =>
      _l10n().settingsUiMaxTabsConstraint(max);

  static String get navigationHiddenAtLimit =>
      _l10n().settingsUiNavigationHiddenAtLimit;

  static String navigationMoveUp(String label) =>
      _l10n().settingsUiNavigationMoveUp(label);

  static String navigationMoveDown(String label) =>
      _l10n().settingsUiNavigationMoveDown(label);

  // Auto-Lock
  static const List<int> autoLockMinuteOptions = [0, 1, 5, 15, 60, 240];

  static String autoLockOptionLabel(int minutes) {
    return switch (minutes) {
      0 => _l10n().appLockAutoLockImmediate,
      1 => _l10n().settingsUiAutoLockMinutes(minutes),
      5 => _l10n().settingsUiAutoLockMinutes(minutes),
      15 => _l10n().settingsUiAutoLockMinutes(minutes),
      60 => _l10n().appLockAutoLockOneHour,
      240 => _l10n().appLockAutoLockFourHours,
      _ => _l10n().settingsUiAutoLockMinutes(minutes),
    };
  }

  static String autoLockSubtitle(int minutes) {
    if (minutes == 0) {
      return _l10n().appLockAutoLockEveryForeground;
    }
    return _l10n().settingsUiAutoLockAfter(minutes);
  }

  static String autoArchiveValueLabel(int days) {
    final localizations = _l10n();
    return switch (days) {
      0 => localizations.actionOff,
      1 => localizations.settingsUiAutoArchiveDayOne,
      _ => localizations.settingsUiAutoArchiveDayMany(days),
    };
  }

  static String autoArchiveSubtitle(int days) {
    final localizations = _l10n();
    return switch (days) {
      0 => localizations.preferencesAutoArchiveNever,
      1 => localizations.settingsUiAutoArchiveAfterOneDay,
      _ => localizations.settingsUiAutoArchiveAfterDays(days),
    };
  }

  static String followSystemTimeZoneSubtitle(String resolvedId) =>
      _l10n().settingsUiFollowingSystemTimeZone(timeZoneDisplayName(resolvedId));

  // Picker Sheet Titles
  static String get selectOption => _l10n().settingsUiSelectOption;
  static String get selectFirstDay => _l10n().settingsUiSelectFirstDay;
  static String get selectDateFormat => _l10n().settingsUiSelectDateFormat;
  static String get selectTimeZone => _l10n().settingsUiSelectTimeZone;
  static String get selectDefaultTab => _l10n().settingsUiSelectDefaultTab;
  static String get selectAutoLock => _l10n().settingsUiSelectAutoLock;
}
