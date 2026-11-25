import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/settings_ui_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectZhEnZh<T>(T Function() read, T zh, T en) {
  I18n.setLocale(AppLocale.zh);
  expect(read(), zh);
  I18n.setLocale(AppLocale.en);
  expect(read(), en);
  I18n.setLocale(AppLocale.zh);
  expect(read(), zh);
}

void main() {
  late AppLocale originalLocale;
  setUp(() => originalLocale = I18n.current);
  tearDown(() => I18n.setLocale(originalLocale));

  test('settings saveFailed preserves frozen zh en zh output', () {
    _expectZhEnZh(
      () => SettingsUiCopy.saveFailed,
      '设置未保存，请重试。',
      'Could not save this setting. Please try again.',
    );
  });

  test('settings decreaseValue preserves frozen zh en zh output', () {
    _expectZhEnZh(() => SettingsUiCopy.decreaseValue, '减少', 'Decrease');
  });

  test('settings increaseValue preserves frozen zh en zh output', () {
    _expectZhEnZh(() => SettingsUiCopy.increaseValue, '增加', 'Increase');
  });

  test(
    'settings preferencesHeroExplanation preserves frozen zh en zh output',
    () {
      _expectZhEnZh(
        () => SettingsUiCopy.preferencesHeroExplanation,
        '自定义显示与行为偏好，管理底部导航入口与小组件显示。',
        'Customize display and behavior preferences, and manage bottom navigation layout and widgets.',
      );
    },
  );

  test(
    'settings preferencesCategoriesSectionTitle preserves frozen zh en zh output',
    () {
      _expectZhEnZh(
        () => SettingsUiCopy.preferencesCategoriesSectionTitle,
        '个性入口',
        'Personalization',
      );
    },
  );

  test(
    'settings preferencesCategoriesSectionSubtitle preserves frozen zh en zh output',
    () {
      _expectZhEnZh(
        () => SettingsUiCopy.preferencesCategoriesSectionSubtitle,
        '选择要调整的设置类别',
        'Choose a category to customize',
      );
    },
  );

  test('settings displayAndBehaviorTitle preserves frozen zh en zh output', () {
    _expectZhEnZh(
      () => SettingsUiCopy.displayAndBehaviorTitle,
      '显示与行为',
      'Display & Behavior',
    );
  });

  test(
    'settings displayAndBehaviorSubtitle preserves frozen zh en zh output',
    () {
      _expectZhEnZh(
        () => SettingsUiCopy.displayAndBehaviorSubtitle,
        '日期格式、应用时区、启动入口、交互与归档',
        'Date formats, time zone, startup tab, haptics, and auto-archive',
      );
    },
  );

  test(
    'settings displayAndBehaviorHeroSubtitle preserves frozen zh en zh output',
    () {
      _expectZhEnZh(
        () => SettingsUiCopy.displayAndBehaviorHeroSubtitle,
        '管理日期格式、应用时区、启动默认项、交互反馈与待办归档。',
        'Manage date format, app time zone, startup defaults, haptic feedback, and auto-archive.',
      );
    },
  );

  test('settings navigationSectionTitle preserves frozen zh en zh output', () {
    _expectZhEnZh(
      () => SettingsUiCopy.navigationSectionTitle,
      '导航入口',
      'Navigation',
    );
  });

  test(
    'settings navigationSectionSubtitle preserves frozen zh en zh output',
    () {
      _expectZhEnZh(
        () => SettingsUiCopy.navigationSectionSubtitle,
        '最多 5 个底部入口；“我的”固定，小组件可隐藏',
        'Up to 5 bottom tabs; "Me" is pinned, Widgets can be hidden',
      );
    },
  );

  test('settings jumpToMenuTitle preserves frozen zh en zh output', () {
    _expectZhEnZh(() => SettingsUiCopy.jumpToMenuTitle, '快捷定位', 'Jump To');
  });

  test('settings jumpToDate preserves frozen zh en zh output', () {
    _expectZhEnZh(() => SettingsUiCopy.jumpToDate, '日期日历', 'Date & Calendar');
  });

  test('settings jumpToDefaults preserves frozen zh en zh output', () {
    _expectZhEnZh(() => SettingsUiCopy.jumpToDefaults, '默认行为', 'Defaults');
  });

  test('settings jumpToInteraction preserves frozen zh en zh output', () {
    _expectZhEnZh(
      () => SettingsUiCopy.jumpToInteraction,
      '交互归档',
      'Interaction',
    );
  });

  test('settings navigationBannerMessage preserves frozen zh en zh output', () {
    _expectZhEnZh(
      () => SettingsUiCopy.navigationBannerMessage,
      '底部导航最多显示 5 个入口，我的固定显示；小组件可隐藏，隐藏入口可在“我的”页面访问。',
      'The bottom navigation bar displays up to 5 tabs. "Me" is pinned. Widgets can be hidden and accessed from the "Me" tab.',
    );
  });

  test('settings navigationHiddenAtLimit preserves frozen zh en zh output', () {
    _expectZhEnZh(
      () => SettingsUiCopy.navigationHiddenAtLimit,
      '已达上限，先隐藏其他项',
      'Limit reached, hide another tab first',
    );
  });

  test('settings selectOption preserves frozen zh en zh output', () {
    _expectZhEnZh(() => SettingsUiCopy.selectOption, '选择设置', 'Select Option');
  });

  test('settings selectFirstDay preserves frozen zh en zh output', () {
    _expectZhEnZh(
      () => SettingsUiCopy.selectFirstDay,
      '选择一周第一天',
      'First Day of Week',
    );
  });

  test('settings selectDateFormat preserves frozen zh en zh output', () {
    _expectZhEnZh(
      () => SettingsUiCopy.selectDateFormat,
      '选择日期格式',
      'Date Format',
    );
  });

  test('settings selectTimeZone preserves frozen zh en zh output', () {
    _expectZhEnZh(
      () => SettingsUiCopy.selectTimeZone,
      '选择应用时区',
      'App Time Zone',
    );
  });

  test('settings selectDefaultTab preserves frozen zh en zh output', () {
    _expectZhEnZh(
      () => SettingsUiCopy.selectDefaultTab,
      '选择启动默认 Tab',
      'Default Startup Tab',
    );
  });

  test('settings selectAutoLock preserves frozen zh en zh output', () {
    _expectZhEnZh(
      () => SettingsUiCopy.selectAutoLock,
      '选择自动锁定时间',
      'Auto-Lock Timeout',
    );
  });

  test('settings preferencesTitle preserves frozen zh en zh output', () {
    _expectZhEnZh(
      () => SettingsUiCopy.preferencesTitle,
      '个性设置',
      'Personal settings',
    );
  });

  test('settings isZh follows immediate zh en zh locale changes', () {
    _expectZhEnZh(() => SettingsUiCopy.isZh, true, false);
  });

  test(
    'settings supportedDateFormatPatterns preserves exact options in either locale',
    () {
      _expectZhEnZh(
        () => SettingsUiCopy.supportedDateFormatPatterns,
        <String>['yyyy-MM-dd', 'MM/dd/yyyy', 'dd/MM/yyyy', 'yyyy年M月d日'],
        <String>['yyyy-MM-dd', 'MM/dd/yyyy', 'dd/MM/yyyy', 'yyyy年M月d日'],
      );
    },
  );

  test(
    'settings supportedTimeZoneIds preserves exact options in either locale',
    () {
      _expectZhEnZh(
        () => SettingsUiCopy.supportedTimeZoneIds,
        <String>[
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
        ],
        <String>[
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
        ],
      );
    },
  );

  test(
    'settings autoLockMinuteOptions preserves exact options in either locale',
    () {
      _expectZhEnZh(
        () => SettingsUiCopy.autoLockMinuteOptions,
        <int>[0, 1, 5, 15, 60, 240],
        <int>[0, 1, 5, 15, 60, 240],
      );
    },
  );

  test(
    'settings decreaseSetting preserves frozen dynamic and fallback output',
    () {
      for (final entry in const <(String, String, String)>[
        ("", "减少“”", "Decrease "),
        (
          " 控件 \${value} \"原文\" ",
          "减少“ 控件 \${value} \"原文\" ”",
          "Decrease  控件 \${value} \"原文\" ",
        ),
      ]) {
        _expectZhEnZh(
          () => SettingsUiCopy.decreaseSetting(entry.$1),
          entry.$2,
          entry.$3,
        );
      }
    },
  );

  test(
    'settings increaseSetting preserves frozen dynamic and fallback output',
    () {
      for (final entry in const <(String, String, String)>[
        ("", "增加“”", "Increase "),
        (
          " 控件 \${value} \"原文\" ",
          "增加“ 控件 \${value} \"原文\" ”",
          "Increase  控件 \${value} \"原文\" ",
        ),
      ]) {
        _expectZhEnZh(
          () => SettingsUiCopy.increaseSetting(entry.$1),
          entry.$2,
          entry.$3,
        );
      }
    },
  );

  test(
    'settings firstWeekdayLabel preserves frozen dynamic and fallback output',
    () {
      for (final entry in const <(int, String, String)>[
        (-99, "周一", "Mon"),
        (0, "周一", "Mon"),
        (1, "周一", "Mon"),
        (2, "周二", "Tue"),
        (3, "周三", "Wed"),
        (4, "周四", "Thu"),
        (5, "周五", "Fri"),
        (6, "周六", "Sat"),
        (7, "周日", "Sun"),
        (8, "周一", "Mon"),
        (999, "周一", "Mon"),
      ]) {
        _expectZhEnZh(
          () => SettingsUiCopy.firstWeekdayLabel(entry.$1),
          entry.$2,
          entry.$3,
        );
      }
    },
  );

  test(
    'settings currentFirstWeekday preserves frozen dynamic and fallback output',
    () {
      for (final entry in const <(int, String, String)>[
        (-99, "当前为周一", "Currently Mon"),
        (0, "当前为周一", "Currently Mon"),
        (1, "当前为周一", "Currently Mon"),
        (2, "当前为周二", "Currently Tue"),
        (3, "当前为周三", "Currently Wed"),
        (4, "当前为周四", "Currently Thu"),
        (5, "当前为周五", "Currently Fri"),
        (6, "当前为周六", "Currently Sat"),
        (7, "当前为周日", "Currently Sun"),
        (8, "当前为周一", "Currently Mon"),
        (999, "当前为周一", "Currently Mon"),
      ]) {
        _expectZhEnZh(
          () => SettingsUiCopy.currentFirstWeekday(entry.$1),
          entry.$2,
          entry.$3,
        );
      }
    },
  );

  test(
    'settings dateFormatLabel preserves frozen dynamic and fallback output',
    () {
      for (final entry in const <(String, String, String)>[
        ("yyyy-MM-dd", "标准 (yyyy-MM-dd)", "ISO (yyyy-MM-dd)"),
        ("MM/dd/yyyy", "美式 (MM/dd/yyyy)", "US (MM/dd/yyyy)"),
        ("dd/MM/yyyy", "欧式 (dd/MM/yyyy)", "UK/EU (dd/MM/yyyy)"),
        ("yyyy年M月d日", "中文年月日 (yyyy年M月d日)", "East Asian (yyyy年M月d日)"),
        ("", "", ""),
        (
          " y年M月d日 \${pattern} ",
          " y年M月d日 \${pattern} ",
          " y年M月d日 \${pattern} ",
        ),
      ]) {
        _expectZhEnZh(
          () => SettingsUiCopy.dateFormatLabel(entry.$1),
          entry.$2,
          entry.$3,
        );
      }
    },
  );

  test(
    'settings dateFormatSample preserves frozen dynamic and fallback output',
    () {
      for (final entry in const <(String, String, String)>[
        ("yyyy-MM-dd", "2026-05-07", "2026-05-07"),
        ("MM/dd/yyyy", "05/07/2026", "05/07/2026"),
        ("dd/MM/yyyy", "07/05/2026", "07/05/2026"),
        ("yyyy年M月d日", "2026年5月7日", "2026年5月7日"),
        ("", "2026-05-07", "2026-05-07"),
        (" y年M月d日 \${pattern} ", "2026-05-07", "2026-05-07"),
      ]) {
        _expectZhEnZh(
          () => SettingsUiCopy.dateFormatSample(entry.$1),
          entry.$2,
          entry.$3,
        );
      }
    },
  );

  test(
    'settings timeZoneDisplayName preserves frozen dynamic and fallback output',
    () {
      for (final entry in const <(String, String, String)>[
        ("system", "跟随手机", "Follow phone"),
        ("Asia/Shanghai", "中国标准时间 (上海)", "China Standard Time (Shanghai)"),
        ("America/Mexico_City", "墨西哥城时间", "Mexico City Time"),
        ("America/Tijuana", "蒂华纳时间", "Tijuana Time"),
        ("Asia/Tokyo", "东京时间 (日本)", "Tokyo Time (Japan)"),
        ("Asia/Hong_Kong", "香港时间", "Hong Kong Time"),
        ("Asia/Singapore", "新加坡时间", "Singapore Time"),
        ("America/New_York", "纽约时间 (美东)", "New York Time (Eastern)"),
        ("America/Los_Angeles", "洛杉矶时间 (美西)", "Los Angeles Time (Pacific)"),
        ("Europe/London", "伦敦时间", "London Time"),
        ("Europe/Paris", "巴黎时间 (中欧)", "Paris Time (Central Europe)"),
        ("Australia/Sydney", "悉尼时间 (澳洲东部)", "Sydney Time (Eastern Australia)"),
        ("", "", ""),
        (
          " Custom/\${id} “原文” ",
          " Custom/\${id} “原文” ",
          " Custom/\${id} “原文” ",
        ),
      ]) {
        _expectZhEnZh(
          () => SettingsUiCopy.timeZoneDisplayName(entry.$1),
          entry.$2,
          entry.$3,
        );
      }
    },
  );

  test(
    'settings maxTabsConstraint preserves frozen dynamic and fallback output',
    () {
      for (final entry in const <(int, String, String)>[
        (-3, "最多显示 -3 个入口", "Max -3 tabs allowed"),
        (0, "最多显示 0 个入口", "Max 0 tabs allowed"),
        (1, "最多显示 1 个入口", "Max 1 tabs allowed"),
        (5, "最多显示 5 个入口", "Max 5 tabs allowed"),
        (99, "最多显示 99 个入口", "Max 99 tabs allowed"),
      ]) {
        _expectZhEnZh(
          () => SettingsUiCopy.maxTabsConstraint(entry.$1),
          entry.$2,
          entry.$3,
        );
      }
    },
  );

  test(
    'settings navigationMoveUp preserves frozen dynamic and fallback output',
    () {
      for (final entry in const <(String, String, String)>[
        ("", "上移“”", "Move  up"),
        (
          " 控件 \${value} \"原文\" ",
          "上移“ 控件 \${value} \"原文\" ”",
          "Move  控件 \${value} \"原文\"  up",
        ),
      ]) {
        _expectZhEnZh(
          () => SettingsUiCopy.navigationMoveUp(entry.$1),
          entry.$2,
          entry.$3,
        );
      }
    },
  );

  test(
    'settings navigationMoveDown preserves frozen dynamic and fallback output',
    () {
      for (final entry in const <(String, String, String)>[
        ("", "下移“”", "Move  down"),
        (
          " 控件 \${value} \"原文\" ",
          "下移“ 控件 \${value} \"原文\" ”",
          "Move  控件 \${value} \"原文\"  down",
        ),
      ]) {
        _expectZhEnZh(
          () => SettingsUiCopy.navigationMoveDown(entry.$1),
          entry.$2,
          entry.$3,
        );
      }
    },
  );

  test(
    'settings autoLockOptionLabel preserves frozen dynamic and fallback output',
    () {
      for (final entry in const <(int, String, String)>[
        (-3, "-3 分钟", "-3 min"),
        (0, "立即", "Immediately"),
        (1, "1 分钟", "1 min"),
        (5, "5 分钟", "5 min"),
        (15, "15 分钟", "15 min"),
        (60, "1 小时", "1 hour"),
        (240, "4 小时", "4 hours"),
        (999, "999 分钟", "999 min"),
      ]) {
        _expectZhEnZh(
          () => SettingsUiCopy.autoLockOptionLabel(entry.$1),
          entry.$2,
          entry.$3,
        );
      }
    },
  );

  test(
    'settings autoLockSubtitle preserves frozen dynamic and fallback output',
    () {
      for (final entry in const <(int, String, String)>[
        (-3, "离开 -3 分钟后锁定", "Lock after -3 min in background"),
        (0, "每次切回前台都锁定", "Lock whenever the app returns"),
        (1, "离开 1 分钟后锁定", "Lock after 1 min in background"),
        (5, "离开 5 分钟后锁定", "Lock after 5 min in background"),
        (15, "离开 15 分钟后锁定", "Lock after 15 min in background"),
        (60, "离开 60 分钟后锁定", "Lock after 60 min in background"),
        (240, "离开 240 分钟后锁定", "Lock after 240 min in background"),
        (999, "离开 999 分钟后锁定", "Lock after 999 min in background"),
      ]) {
        _expectZhEnZh(
          () => SettingsUiCopy.autoLockSubtitle(entry.$1),
          entry.$2,
          entry.$3,
        );
      }
    },
  );
}
