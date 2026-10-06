import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart' show LocaleProvider;
import 'package:duoyi/core/desktop_tokens.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/l10n/generated/app_localizations.dart';
import 'package:duoyi/main.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 桌面 web 外壳（NavigationRail）宽屏冒烟：
///
/// WebTarget.isDesktopWebBuild 依赖 kIsWeb（VM 上恒为 false），测试通过
/// [WebTarget.debugDesktopWebBuild] 注入开启外壳分支；视口写法沿用
/// today_mine_smoke_test 的 tester.view.physicalSize + devicePixelRatio。
Finder get _maxWidthBox =>
    find.byKey(const ValueKey('desktop_web_body_max_width'));

Widget _wrapShell(ThemeData theme) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
      ChangeNotifierProvider(create: (_) => CalendarProvider()),
      ChangeNotifierProvider(create: (_) => UserProvider()),
      ChangeNotifierProvider(create: (_) => CountdownProvider()),
      ChangeNotifierProvider(create: (_) => NoteProvider()),
      ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
      ChangeNotifierProvider(create: (_) => DiaryProvider()),
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => CourseProvider()),
      ChangeNotifierProvider(create: (_) => AppLockProvider()),
      ChangeNotifierProvider(create: (_) => PreferencesProvider()),
      ChangeNotifierProvider(create: (_) => AchievementProvider()),
      ChangeNotifierProvider(create: (_) => ShareProvider()),
      ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
      ChangeNotifierProvider(create: (_) => NotificationService()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => AiService()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
      ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
      ChangeNotifierProvider(
        create: (_) => AppUpdateService(
          repo: 'dq52099/duoyi',
          currentVersion: AppVersion.name,
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: theme,
      home: MainShell(),
    ),
  );
}

Future<void> _pumpShellAt(
  WidgetTester tester,
  ThemeData theme,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrapShell(theme));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebTarget.debugDesktopWebBuild = true;
  });
  tearDown(() {
    WebTarget.debugDesktopWebBuild = null;
  });

  testWidgets('1280x800 默认主题：桌面壳渲染今日主 tab，无溢出且内容限宽', (tester) async {
    await _pumpShellAt(
      tester,
      AppBrands.defaultBrand.theme,
      const Size(1280, 800),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    final width = tester.getSize(_maxWidthBox).width;
    expect(width, greaterThan(0));
    expect(width, lessThanOrEqualTo(DesktopTokens.maxContentWidth));
  });

  testWidgets('1280x800 液态玻璃主题：切到待办主 tab，无溢出且卡片限宽', (tester) async {
    await _pumpShellAt(
      tester,
      AppBrands.liquidGlass.theme,
      const Size(1280, 800),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    tester.state<MainShellState>(find.byType(MainShell)).navigateTo(1);
    await tester.pumpAndSettle();

    expect(find.byType(TodoScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    final width = tester.getSize(_maxWidthBox).width;
    expect(width, greaterThan(0));
    expect(width, lessThanOrEqualTo(DesktopTokens.maxContentWidth));
  });

  testWidgets('1600x900 默认主题：内容宽度钉在 maxContentWidth', (tester) async {
    await _pumpShellAt(
      tester,
      AppBrands.defaultBrand.theme,
      const Size(1600, 900),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.getSize(_maxWidthBox).width, DesktopTokens.maxContentWidth);
    expect(tester.takeException(), isNull);
  });

  test('web 底导航模糊降级档低于原生档（VM 上 kIsWeb=false 不降级）', () {
    expect(
      DesignTokens.navBarWebBlurSigma,
      lessThan(DesignTokens.navBarIosBlurSigma),
    );
    expect(WebTarget.shouldReduceNavBarBlur, isFalse);
  });
}
