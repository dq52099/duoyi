/// Settings UI localization and dynamic copy getters (Task: iOS style & i18n).
library;

import 'i18n.dart';

class SettingsUiCopy {
  SettingsUiCopy._();

  static bool get isZh => I18n.current == AppLocale.zh;

  static String get saveFailed =>
      isZh ? '设置未保存，请重试。' : 'Could not save this setting. Please try again.';

  static String get decreaseValue => isZh ? '减少' : 'Decrease';
  static String get increaseValue => isZh ? '增加' : 'Increase';

  // Preferences Screen
  static String get preferencesTitle => I18n.tr('preferences.title');

  static String get preferencesHeroExplanation => isZh
      ? '自定义显示与行为偏好，管理底部导航入口与小组件显示。'
      : 'Customize display and behavior preferences, and manage bottom navigation layout and widgets.';

  static String get preferencesCategoriesSectionTitle =>
      isZh ? '个性入口' : 'Personalization';

  static String get preferencesCategoriesSectionSubtitle =>
      isZh ? '选择要调整的设置类别' : 'Choose a category to customize';

  static String get displayAndBehaviorTitle =>
      isZh ? '显示与行为' : 'Display & Behavior';

  static String get displayAndBehaviorSubtitle => isZh
      ? '日期格式、应用时区、启动入口、交互与归档'
      : 'Date formats, time zone, startup tab, haptics, and auto-archive';

  static String get displayAndBehaviorHeroSubtitle => isZh
      ? '管理日期格式、应用时区、启动默认项、交互反馈与待办归档。'
      : 'Manage date format, app time zone, startup defaults, haptic feedback, and auto-archive.';

  static String get navigationSectionTitle => isZh ? '导航入口' : 'Navigation';

  static String get navigationSectionSubtitle => isZh
      ? '最多 5 个底部入口；“我的”固定，小组件可隐藏'
      : 'Up to 5 bottom tabs; "Me" is pinned, Widgets can be hidden';

  // Personalization Section Menu
  static String get jumpToMenuTitle => isZh ? '快捷定位' : 'Jump To';
  static String get jumpToDate => isZh ? '日期日历' : 'Date & Calendar';
  static String get jumpToDefaults => isZh ? '默认行为' : 'Defaults';
  static String get jumpToInteraction => isZh ? '交互归档' : 'Interaction';

  // Date Formats
  static const List<String> supportedDateFormatPatterns = [
    'yyyy-MM-dd',
    'MM/dd/yyyy',
    'dd/MM/yyyy',
    'yyyy年M月d日',
  ];

  static String dateFormatLabel(String pattern) {
    return switch (pattern) {
      'yyyy-MM-dd' => isZh ? '标准 (yyyy-MM-dd)' : 'ISO (yyyy-MM-dd)',
      'MM/dd/yyyy' => isZh ? '美式 (MM/dd/yyyy)' : 'US (MM/dd/yyyy)',
      'dd/MM/yyyy' => isZh ? '欧式 (dd/MM/yyyy)' : 'UK/EU (dd/MM/yyyy)',
      'yyyy年M月d日' => isZh ? '中文年月日 (yyyy年M月d日)' : 'East Asian (yyyy年M月d日)',
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
      'system' => I18n.tr('preferences.timezone.follow_system'),
      'Asia/Shanghai' =>
        isZh ? '中国标准时间 (上海)' : 'China Standard Time (Shanghai)',
      'America/Mexico_City' => isZh ? '墨西哥城时间' : 'Mexico City Time',
      'America/Tijuana' => isZh ? '蒂华纳时间' : 'Tijuana Time',
      'Asia/Tokyo' => isZh ? '东京时间 (日本)' : 'Tokyo Time (Japan)',
      'Asia/Hong_Kong' => isZh ? '香港时间' : 'Hong Kong Time',
      'Asia/Singapore' => isZh ? '新加坡时间' : 'Singapore Time',
      'America/New_York' => isZh ? '纽约时间 (美东)' : 'New York Time (Eastern)',
      'America/Los_Angeles' =>
        isZh ? '洛杉矶时间 (美西)' : 'Los Angeles Time (Pacific)',
      // London observes BST in summer and GMT in winter; use neutral London wording.
      'Europe/London' => isZh ? '伦敦时间' : 'London Time',
      'Europe/Paris' => isZh ? '巴黎时间 (中欧)' : 'Paris Time (Central Europe)',
      'Australia/Sydney' =>
        isZh ? '悉尼时间 (澳洲东部)' : 'Sydney Time (Eastern Australia)',
      _ => id,
    };
  }

  // Navigation / Bottom nav
  static String get navigationBannerMessage => isZh
      ? '底部导航最多显示 5 个入口，我的固定显示；小组件可隐藏，隐藏入口可在“我的”页面访问。'
      : 'The bottom navigation bar displays up to 5 tabs. "Me" is pinned. Widgets can be hidden and accessed from the "Me" tab.';

  static String maxTabsConstraint(int max) =>
      isZh ? '最多显示 $max 个入口' : 'Max $max tabs allowed';

  // Auto-Lock
  static const List<int> autoLockMinuteOptions = [0, 1, 5, 15, 60, 240];

  static String autoLockOptionLabel(int minutes) {
    return switch (minutes) {
      0 => I18n.tr('app_lock.auto_lock.immediate'),
      1 => isZh ? '1 分钟' : '1 min',
      5 => isZh ? '5 分钟' : '5 min',
      15 => isZh ? '15 分钟' : '15 min',
      60 => I18n.tr('app_lock.auto_lock.one_hour'),
      240 => I18n.tr('app_lock.auto_lock.four_hours'),
      _ => isZh ? '$minutes 分钟' : '$minutes min',
    };
  }

  static String autoLockSubtitle(int minutes) {
    if (minutes == 0) {
      return I18n.tr('app_lock.auto_lock.every_foreground');
    }
    return '${I18n.tr('app_lock.auto_lock.after_prefix')}$minutes${I18n.tr('app_lock.auto_lock.after_suffix')}';
  }

  // Picker Sheet Titles
  static String get selectOption => isZh ? '选择设置' : 'Select Option';
  static String get selectFirstDay => isZh ? '选择一周第一天' : 'First Day of Week';
  static String get selectDateFormat => isZh ? '选择日期格式' : 'Date Format';
  static String get selectTimeZone => isZh ? '选择应用时区' : 'App Time Zone';
  static String get selectDefaultTab =>
      isZh ? '选择启动默认 Tab' : 'Default Startup Tab';
  static String get selectAutoLock => isZh ? '选择自动锁定时间' : 'Auto-Lock Timeout';
}
