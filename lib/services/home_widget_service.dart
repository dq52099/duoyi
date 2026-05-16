import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../core/brand_strings.dart';
import '../core/platform_info.dart';

/// Pushes today's stats and brand strings out to the Android home widget.
/// 在 web / 其他平台下为空实现。
class HomeWidgetService {
  static const String _androidProviderName = 'DuoyiWidgetProvider';
  static const String _androidTodoProviderName = 'DuoyiTodoWidgetProvider';
  static const String _appGroupId = 'group.com.duoyi.duoyi';

  static bool get _supported {
    if (kIsWeb) return false;
    return PlatformInfo.isAndroid;
  }

  static Future<void> init() async {
    if (!_supported) return;
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
    } catch (_) {}
  }

  static Future<void> push({
    required int todoCount,
    required int habitPercent,
    required int pomodoroToday,
    required BrandStrings strings,
    List<String> todoTop3 = const [],
    List<String> todoTop3Ids = const [],
    String todayEventSummary = '今日没有日程',
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
          'today_event_summary',
          todayEventSummary,
        ),
      ]);
      await HomeWidget.updateWidget(
        name: _androidProviderName,
        androidName: _androidProviderName,
      );
      await HomeWidget.updateWidget(
        name: _androidTodoProviderName,
        androidName: _androidTodoProviderName,
      );
    } catch (_) {}
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
