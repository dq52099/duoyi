import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../core/brand_strings.dart';
import '../core/platform_info.dart';

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

  static Future<void> init() async {
    if (!_supported) return;
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
    } catch (_) {}
  }

  static Future<void> setDisplayMode(String mode) async {
    if (!_supported) return;
    try {
      await HomeWidget.saveWidgetData<String>('widget_display_mode', mode);
      await _updateAllWidgets();
    } catch (_) {}
  }

  static Future<void> push({
    required int todoCount,
    required int habitPercent,
    required int pomodoroToday,
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
  }) async {
    if (!_supported) return;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<int>('todo_count', todoCount),
        HomeWidget.saveWidgetData<int>('habit_percent', habitPercent),
        HomeWidget.saveWidgetData<int>('pomodoro_today', pomodoroToday),
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
      ]);
      await _updateAllWidgets();
    } catch (_) {}
  }

  static Future<void> _updateAllWidgets() async {
    await HomeWidget.updateWidget(
      name: _androidTodoProviderName,
      androidName: _androidTodoProviderName,
      iOSName: _iosTodoWidgetName,
    );
    await HomeWidget.updateWidget(
      name: _androidFocusProviderName,
      androidName: _androidFocusProviderName,
      iOSName: _iosFocusWidgetName,
    );
    await HomeWidget.updateWidget(
      name: _androidHabitProviderName,
      androidName: _androidHabitProviderName,
      iOSName: _iosHabitWidgetName,
    );
    await HomeWidget.updateWidget(
      name: _androidCalendarProviderName,
      androidName: _androidCalendarProviderName,
      iOSName: _iosCalendarWidgetName,
    );
    await HomeWidget.updateWidget(
      name: _androidScheduleProviderName,
      androidName: _androidScheduleProviderName,
      iOSName: _iosScheduleWidgetName,
    );
    await HomeWidget.updateWidget(
      name: _androidGoalProviderName,
      androidName: _androidGoalProviderName,
      iOSName: _iosGoalWidgetName,
    );
    await HomeWidget.updateWidget(
      name: _androidCourseProviderName,
      androidName: _androidCourseProviderName,
      iOSName: _iosCourseWidgetName,
    );
    await HomeWidget.updateWidget(
      name: _androidNoteProviderName,
      androidName: _androidNoteProviderName,
      iOSName: _iosNoteWidgetName,
    );
    await HomeWidget.updateWidget(
      name: _androidAnniversaryProviderName,
      androidName: _androidAnniversaryProviderName,
      iOSName: _iosAnniversaryWidgetName,
    );
    await HomeWidget.updateWidget(
      name: _androidDiaryProviderName,
      androidName: _androidDiaryProviderName,
      iOSName: _iosDiaryWidgetName,
    );
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
