import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import '../core/brand_strings.dart';
import '../core/platform_info.dart';
import '../providers/theme_provider.dart';
import 'android_widget_manager.dart';

/// Pushes today's stats and brand strings out to Android/iOS home widgets.
/// 在 web / 其他平台下为空实现。
class HomeWidgetService {
  static const String _androidTodoProviderName = 'DuoyiTodoWidgetProvider';
  static const String _androidFocusProviderName =
      'DuoyiFocusHabitWidgetProvider';
  static const String _androidHabitProviderName = 'DuoyiHabitWidgetProvider';
  static const String _androidCalendarProviderName =
      'DuoyiCalendarWidgetProvider';
  static const String _androidScheduleProviderName =
      'DuoyiScheduleWidgetProvider';
  static const String _androidGoalProviderName = 'DuoyiGoalWidgetProvider';
  static const String _androidCourseProviderName = 'DuoyiCourseWidgetProvider';
  static const String _androidNoteProviderName = 'DuoyiNoteWidgetProvider';
  static const String _androidAnniversaryProviderName =
      'DuoyiAnniversaryWidgetProvider';
  static const String _androidDiaryProviderName = 'DuoyiDiaryWidgetProvider';
  static const String _iosTodoWidgetName = 'DuoyiTodoWidget';
  static const String _iosFocusWidgetName = 'DuoyiFocusWidget';
  static const String _iosHabitWidgetName = 'DuoyiHabitWidget';
  static const String _iosCalendarWidgetName = 'DuoyiCalendarWidget';
  static const String _iosScheduleWidgetName = 'DuoyiScheduleWidget';
  static const String _iosGoalWidgetName = 'DuoyiGoalWidget';
  static const String _iosCourseWidgetName = 'DuoyiCourseWidget';
  static const String _iosNoteWidgetName = 'DuoyiNoteWidget';
  static const String _iosAnniversaryWidgetName = 'DuoyiAnniversaryWidget';
  static const String _iosDiaryWidgetName = 'DuoyiDiaryWidget';
  static const String _appGroupId = 'group.com.duoyi.duoyi';

  static bool get _supported {
    if (kIsWeb) return false;
    return PlatformInfo.isAndroid || PlatformInfo.isIOS;
  }

  static Future<bool> init() async {
    if (!_supported) return true;
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      return true;
    } catch (e, st) {
      debugPrint('[HomeWidget] init failed: $e\n$st');
      return false;
    }
  }

  static Future<bool> setDisplayMode(String mode) async {
    if (!_supported) return true;
    try {
      await HomeWidget.saveWidgetData<String>('widget_display_mode', mode);
      return _updateAllWidgets();
    } catch (e, st) {
      debugPrint('[HomeWidget] setDisplayMode($mode) failed: $e\n$st');
      return false;
    }
  }

  static Future<bool> updateTheme(HomeWidgetThemePayload theme) async {
    if (!_supported) return true;
    try {
      await Future.wait(theme.saveOperations());
      return _updateAllWidgets();
    } catch (e, st) {
      debugPrint('[HomeWidget] updateTheme failed: $e\n$st');
      return false;
    }
  }

  static Future<bool> push({
    required int todoCount,
    required int habitPercent,
    required int pomodoroToday,
    required int focusMinutesToday,
    required BrandStrings strings,
    List<String> todoTop3 = const [],
    List<String> todoTop3Ids = const [],
    List<String> goalHighlights = const [],
    List<String> goalHighlightIds = const [],
    List<String> anniversaryHighlights = const [],
    List<String> anniversaryHighlightIds = const [],
    List<String> courseHighlights = const [],
    List<String> courseHighlightIds = const [],
    List<String> noteHighlights = const [],
    List<String> noteHighlightIds = const [],
    List<String> memorialHighlights = const [],
    List<String> memorialHighlightIds = const [],
    List<String> diaryHighlights = const [],
    List<String> diaryHighlightIds = const [],
    List<String> scheduleHighlights = const [],
    List<String> scheduleHighlightIds = const [],
    String todayEventSummary = '今日没有日程',
    String focusSummary = '今日还未专注',
    String habitSummary = '今日习惯待打卡',
    String streakSummary = '连续记录 0 天',
    String nextFocusLabel = '25 分钟专注',
    bool focusTimerRunning = false,
    int focusTimerRemainingSeconds = 0,
    int focusTimerTotalSeconds = 0,
    int focusTimerEndsAtMillis = 0,
    String focusTimerLabel = '专注倒计时',
    String habitQuickCheckId = '',
    String habitQuickCheckLabel = '点击进入习惯打卡',
    required HomeWidgetThemePayload theme,
  }) async {
    if (!_supported) return true;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<int>('todo_count', todoCount),
        HomeWidget.saveWidgetData<int>('habit_percent', habitPercent),
        HomeWidget.saveWidgetData<int>('pomodoro_today', pomodoroToday),
        HomeWidget.saveWidgetData<int>(
          'focus_minutes_today',
          focusMinutesToday,
        ),
        HomeWidget.saveWidgetData<String>('brand_app_title', strings.appTitle),
        HomeWidget.saveWidgetData<String>('nav_todo', strings.navTodo),
        HomeWidget.saveWidgetData<String>('nav_habit', strings.navHabit),
        HomeWidget.saveWidgetData<String>('nav_calendar', strings.navCalendar),
        HomeWidget.saveWidgetData<String>('nav_focus', strings.navFocus),
        // 今日待办 Top 3
        HomeWidget.saveWidgetData<int>('todo_top3_count', todoCount),
        HomeWidget.saveWidgetData<String>(
          'todo_top3_1',
          todoTop3.isNotEmpty ? '· ${todoTop3[0]}' : '今天没有未完成待办',
        ),
        HomeWidget.saveWidgetData<String>(
          'todo_top3_1_id',
          todoTop3Ids.isNotEmpty ? todoTop3Ids[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'todo_top3_2',
          todoTop3.length > 1 ? '· ${todoTop3[1]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'todo_top3_2_id',
          todoTop3Ids.length > 1 ? todoTop3Ids[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'todo_top3_3',
          todoTop3.length > 2 ? '· ${todoTop3[2]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'todo_top3_3_id',
          todoTop3Ids.length > 2 ? todoTop3Ids[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'goal_highlight_1',
          goalHighlights.isNotEmpty ? '· ${goalHighlights[0]}' : '暂无进行中目标',
        ),
        HomeWidget.saveWidgetData<String>(
          'goal_highlight_1_id',
          goalHighlightIds.isNotEmpty ? goalHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'goal_highlight_2',
          goalHighlights.length > 1 ? '· ${goalHighlights[1]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'goal_highlight_2_id',
          goalHighlightIds.length > 1 ? goalHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'goal_highlight_3',
          goalHighlights.length > 2 ? '· ${goalHighlights[2]}' : '本周目标保持推进',
        ),
        HomeWidget.saveWidgetData<String>(
          'goal_highlight_3_id',
          goalHighlightIds.length > 2 ? goalHighlightIds[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'anniversary_highlight_1',
          anniversaryHighlights.isNotEmpty
              ? '· ${anniversaryHighlights[0]}'
              : '暂无近期纪念日',
        ),
        HomeWidget.saveWidgetData<String>(
          'anniversary_highlight_1_id',
          anniversaryHighlightIds.isNotEmpty ? anniversaryHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'anniversary_highlight_2',
          anniversaryHighlights.length > 1
              ? '· ${anniversaryHighlights[1]}'
              : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'anniversary_highlight_2_id',
          anniversaryHighlightIds.length > 1 ? anniversaryHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'course_highlight_1',
          courseHighlights.isNotEmpty ? '· ${courseHighlights[0]}' : '今日暂无课程',
        ),
        HomeWidget.saveWidgetData<String>(
          'course_highlight_1_id',
          courseHighlightIds.isNotEmpty ? courseHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'course_highlight_2',
          courseHighlights.length > 1 ? '· ${courseHighlights[1]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'course_highlight_2_id',
          courseHighlightIds.length > 1 ? courseHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'course_highlight_3',
          courseHighlights.length > 2 ? '· ${courseHighlights[2]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'course_highlight_3_id',
          courseHighlightIds.length > 2 ? courseHighlightIds[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'note_highlight_1',
          noteHighlights.isNotEmpty ? '· ${noteHighlights[0]}' : '暂无随手记',
        ),
        HomeWidget.saveWidgetData<String>(
          'note_highlight_1_id',
          noteHighlightIds.isNotEmpty ? noteHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'note_highlight_2',
          noteHighlights.length > 1 ? '· ${noteHighlights[1]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'note_highlight_2_id',
          noteHighlightIds.length > 1 ? noteHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'note_highlight_3',
          noteHighlights.length > 2 ? '· ${noteHighlights[2]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'note_highlight_3_id',
          noteHighlightIds.length > 2 ? noteHighlightIds[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'memorial_highlight_1',
          memorialHighlights.isNotEmpty
              ? '· ${memorialHighlights[0]}'
              : '暂无近期纪念日',
        ),
        HomeWidget.saveWidgetData<String>(
          'memorial_highlight_1_id',
          memorialHighlightIds.isNotEmpty ? memorialHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'memorial_highlight_2',
          memorialHighlights.length > 1 ? '· ${memorialHighlights[1]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'memorial_highlight_2_id',
          memorialHighlightIds.length > 1 ? memorialHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'memorial_highlight_3',
          memorialHighlights.length > 2 ? '· ${memorialHighlights[2]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'memorial_highlight_3_id',
          memorialHighlightIds.length > 2 ? memorialHighlightIds[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'diary_highlight_1',
          diaryHighlights.isNotEmpty ? '· ${diaryHighlights[0]}' : '暂无日记',
        ),
        HomeWidget.saveWidgetData<String>(
          'diary_highlight_1_id',
          diaryHighlightIds.isNotEmpty ? diaryHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'diary_highlight_2',
          diaryHighlights.length > 1 ? '· ${diaryHighlights[1]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'diary_highlight_2_id',
          diaryHighlightIds.length > 1 ? diaryHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'diary_highlight_3',
          diaryHighlights.length > 2 ? '· ${diaryHighlights[2]}' : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'diary_highlight_3_id',
          diaryHighlightIds.length > 2 ? diaryHighlightIds[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'today_event_summary',
          todayEventSummary,
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_highlight_1',
          scheduleHighlights.isNotEmpty
              ? '· ${scheduleHighlights[0]}'
              : '· $todayEventSummary',
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_highlight_1_id',
          scheduleHighlightIds.isNotEmpty ? scheduleHighlightIds[0] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_highlight_2',
          scheduleHighlights.length > 1
              ? '· ${scheduleHighlights[1]}'
              : '· 打开日历查看完整安排',
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_highlight_2_id',
          scheduleHighlightIds.length > 1 ? scheduleHighlightIds[1] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_highlight_3',
          scheduleHighlights.length > 2
              ? '· ${scheduleHighlights[2]}'
              : '提醒会跟随系统时区',
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_highlight_3_id',
          scheduleHighlightIds.length > 2 ? scheduleHighlightIds[2] : '',
        ),
        HomeWidget.saveWidgetData<String>(
          'calendar_month_summary',
          '本月日期 · 今日已标记',
        ),
        HomeWidget.saveWidgetData<String>('focus_summary', focusSummary),
        HomeWidget.saveWidgetData<String>('habit_summary', habitSummary),
        HomeWidget.saveWidgetData<String>('streak_summary', streakSummary),
        HomeWidget.saveWidgetData<String>('next_focus_label', nextFocusLabel),
        HomeWidget.saveWidgetData<bool>(
          'focus_timer_running',
          focusTimerRunning,
        ),
        HomeWidget.saveWidgetData<int>(
          'focus_timer_remaining_seconds',
          focusTimerRemainingSeconds,
        ),
        HomeWidget.saveWidgetData<int>(
          'focus_timer_total_seconds',
          focusTimerTotalSeconds,
        ),
        HomeWidget.saveWidgetData<int>(
          'focus_timer_ends_at_millis',
          focusTimerEndsAtMillis,
        ),
        HomeWidget.saveWidgetData<String>('focus_timer_label', focusTimerLabel),
        HomeWidget.saveWidgetData<String>(
          'habit_quick_check_id',
          habitQuickCheckId,
        ),
        HomeWidget.saveWidgetData<String>(
          'habit_quick_check_label',
          habitQuickCheckLabel,
        ),
        ...theme.saveOperations(),
      ]);
      return _updateAllWidgets();
    } catch (e, st) {
      debugPrint('[HomeWidget] push failed: $e\n$st');
      return false;
    }
  }

  static Future<bool> _updateAllWidgets() async {
    if (PlatformInfo.isAndroid) {
      final updated = await AndroidWidgetManager.refreshAllWidgets();
      if (updated == null) {
        debugPrint('[HomeWidget] Android refreshAllWidgets failed');
        return false;
      }
      return true;
    }
    var ok = true;
    for (final target in _widgetUpdateTargets) {
      ok =
          await _updateWidgetFamily(
            androidName: target.androidName,
            iOSName: target.iOSName,
          ) &&
          ok;
    }
    if (!ok) {
      debugPrint('[HomeWidget] one or more widget providers failed to update');
    }
    return ok;
  }

  static Future<bool> _updateWidgetFamily({
    required String androidName,
    required String iOSName,
  }) async {
    var ok = true;
    Future<void> updateOne(String name, {String? ios}) async {
      try {
        await HomeWidget.updateWidget(
          name: name,
          androidName: name,
          iOSName: ios,
        );
      } catch (e, st) {
        ok = false;
        debugPrint('[HomeWidget] updateWidget($name) failed: $e\n$st');
      }
    }

    await updateOne(androidName, ios: iOSName);
    return ok;
  }

  static Stream<Uri?> get widgetClickedStream {
    if (!_supported) return const Stream.empty();
    return HomeWidget.widgetClicked;
  }

  static Future<Uri?> initialLaunchUri() async {
    if (!_supported) return null;
    return HomeWidget.initiallyLaunchedFromHomeWidget();
  }
}

class HomeWidgetThemePayload {
  final String brandId;
  final String cardSkinId;
  final bool dark;
  final Color primary;
  final Color background;
  final Color surface;
  final Color navBackground;
  final Color border;
  final Color text;
  final Color mutedText;
  final Color onPrimary;
  final Color accentStart;
  final Color accentEnd;
  final String backgroundAssetKey;
  final int cornerRadiusDp;
  final int controlRadiusDp;
  final int borderWidthDp;

  const HomeWidgetThemePayload({
    required this.brandId,
    required this.cardSkinId,
    required this.dark,
    required this.primary,
    required this.background,
    required this.surface,
    required this.navBackground,
    required this.border,
    required this.text,
    required this.mutedText,
    required this.onPrimary,
    required this.accentStart,
    required this.accentEnd,
    required this.backgroundAssetKey,
    required this.cornerRadiusDp,
    required this.controlRadiusDp,
    required this.borderWidthDp,
  });

  factory HomeWidgetThemePayload.fromThemeProvider(ThemeProvider provider) {
    final brand = provider.activeWidgetBackgroundBrand;
    final theme = brand.theme;
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final cardSkin = provider.activeWidgetCardSkin;
    final usesCardSkin = cardSkin.id != ThemeProvider.defaultCardSkinId;
    final imageBacked = brand.backgroundAsset != null;
    final accentStart = usesCardSkin ? cardSkin.colors.first : cs.primary;
    final accentEnd = usesCardSkin ? cardSkin.colors.last : cs.secondary;
    final baseBackground = Color.alphaBlend(
      brand.backgroundOverlay.withValues(
        alpha: imageBacked
            ? brand.backgroundOverlayOpacity.clamp(0.56, 0.82).toDouble()
            : brand.backgroundOverlayOpacity,
      ),
      dark ? const Color(0xFF0B0F17) : const Color(0xFFFFFFFF),
    );
    final background = Color.alphaBlend(
      accentEnd.withValues(alpha: imageBacked ? (dark ? 0.22 : 0.14) : 0.08),
      Color.alphaBlend(
        accentStart.withValues(alpha: dark ? 0.22 : 0.12),
        baseBackground,
      ),
    );
    final surface = Color.alphaBlend(
      accentEnd.withValues(
        alpha: usesCardSkin
            ? (dark ? 0.24 : 0.16)
            : imageBacked
            ? (dark ? 0.16 : 0.09)
            : 0.06,
      ),
      Color.alphaBlend(
        brand.backgroundOverlay.withValues(alpha: imageBacked ? 0.18 : 0.0),
        cs.surface,
      ),
    );
    final navBackground = Color.alphaBlend(
      cs.primary.withValues(alpha: imageBacked ? (dark ? 0.24 : 0.12) : 0.10),
      surface,
    );
    final border = Color.alphaBlend(
      accentStart.withValues(alpha: usesCardSkin ? (dark ? 0.50 : 0.34) : 0.18),
      cs.outlineVariant,
    );
    final cornerRadiusDp = switch (cardSkin.id) {
      'paper_card' => 14,
      'mint_card' => 15,
      'starlight_card' => 16,
      _ => 13,
    };
    return HomeWidgetThemePayload(
      brandId: brand.id,
      cardSkinId: cardSkin.id,
      dark: dark,
      primary: cs.primary,
      background: background,
      surface: surface,
      navBackground: navBackground,
      border: border,
      text: cs.onSurface,
      mutedText: cs.onSurfaceVariant,
      onPrimary: cs.onPrimary,
      accentStart: accentStart,
      accentEnd: accentEnd,
      backgroundAssetKey: _backgroundAssetKey(brand.backgroundAsset),
      cornerRadiusDp: cornerRadiusDp,
      controlRadiusDp: 8,
      borderWidthDp: usesCardSkin ? 1 : 0,
    );
  }

  List<Future<bool?>> saveOperations() => [
    HomeWidget.saveWidgetData<String>('widget_theme_brand_id', brandId),
    HomeWidget.saveWidgetData<String>('widget_theme_card_skin_id', cardSkinId),
    HomeWidget.saveWidgetData<bool>('widget_theme_dark', dark),
    HomeWidget.saveWidgetData<String>('widget_theme_primary', _hex(primary)),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_background',
      _hex(background),
    ),
    HomeWidget.saveWidgetData<String>('widget_theme_surface', _hex(surface)),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_nav_background',
      _hex(navBackground),
    ),
    HomeWidget.saveWidgetData<String>('widget_theme_border', _hex(border)),
    HomeWidget.saveWidgetData<String>('widget_theme_text', _hex(text)),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_muted_text',
      _hex(mutedText),
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_on_primary',
      _hex(onPrimary),
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_accent_start',
      _hex(accentStart),
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_accent_end',
      _hex(accentEnd),
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_theme_background_asset_key',
      backgroundAssetKey,
    ),
    HomeWidget.saveWidgetData<int>(
      'widget_theme_corner_radius_dp',
      cornerRadiusDp,
    ),
    HomeWidget.saveWidgetData<int>(
      'widget_theme_control_radius_dp',
      controlRadiusDp,
    ),
    HomeWidget.saveWidgetData<int>(
      'widget_theme_border_width_dp',
      borderWidthDp,
    ),
  ];

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  static String _backgroundAssetKey(String? asset) {
    return switch (asset) {
      'assets/backgrounds/re0.png' => 're0',
      'assets/backgrounds/genshin.png' => 'genshin',
      'assets/backgrounds/star_rail.png' => 'star_rail',
      'assets/backgrounds/wuthering.png' => 'wuthering',
      'assets/backgrounds/zzz.png' => 'zzz',
      'assets/backgrounds/yanyun.png' => 'yanyun',
      'assets/backgrounds/botw.png' => 'botw',
      _ => '',
    };
  }
}

class _HomeWidgetUpdateTarget {
  final String androidName;
  final String iOSName;

  const _HomeWidgetUpdateTarget({
    required this.androidName,
    required this.iOSName,
  });
}

const List<_HomeWidgetUpdateTarget> _widgetUpdateTargets = [
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidTodoProviderName,
    iOSName: HomeWidgetService._iosTodoWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidFocusProviderName,
    iOSName: HomeWidgetService._iosFocusWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidHabitProviderName,
    iOSName: HomeWidgetService._iosHabitWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidCalendarProviderName,
    iOSName: HomeWidgetService._iosCalendarWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidScheduleProviderName,
    iOSName: HomeWidgetService._iosScheduleWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidGoalProviderName,
    iOSName: HomeWidgetService._iosGoalWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidCourseProviderName,
    iOSName: HomeWidgetService._iosCourseWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidNoteProviderName,
    iOSName: HomeWidgetService._iosNoteWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidAnniversaryProviderName,
    iOSName: HomeWidgetService._iosAnniversaryWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidDiaryProviderName,
    iOSName: HomeWidgetService._iosDiaryWidgetName,
  ),
];
