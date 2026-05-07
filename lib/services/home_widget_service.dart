import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../core/brand_strings.dart';
import '../core/platform_info.dart';

/// Pushes today's stats and brand strings out to the Android home widget.
/// 在 web / 其他平台下为空实现。
class HomeWidgetService {
  static const String _androidProviderName = 'DuoyiWidgetProvider';
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
        HomeWidget.saveWidgetData<String>('nav_focus', strings.navFocus),
      ]);
      await HomeWidget.updateWidget(
        name: _androidProviderName,
        androidName: _androidProviderName,
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
