import 'dart:io';

import 'package:duoyi/core/almanac_locale_format.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/desktop_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/quotes.dart';
import 'package:duoyi/core/today_ui_copy.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/theme_picker_screen.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('web shell HTML/manifest keeps branded splash and colors', () {
    final indexHtml = File('web/index.html').readAsStringSync();
    final manifestJson = File('web/manifest.json').readAsStringSync();
    final deepLink = File(
      'lib/services/deep_link_service.dart',
    ).readAsStringSync();
    final geofence = File(
      'lib/services/location_geofence_service.dart',
    ).readAsStringSync();

    expect(indexHtml, contains('<base href="\$FLUTTER_BASE_HREF">'));
    expect(indexHtml, contains('src="web_resume_guard.js"'));
    expect(indexHtml, contains('src="flutter_bootstrap.js"'));
    expect(indexHtml, contains('id="duoyi-splash"'));
    expect(indexHtml, contains('flutter-first-frame'));
    expect(indexHtml, contains('@media (prefers-color-scheme: dark)'));
    expect(indexHtml, contains('<meta name="theme-color" content="#0066D6">'));
    expect(indexHtml, contains('content="#0A84FF"'));
    expect(indexHtml, contains('--duoyi-accent: #0066D6;'));
    expect(indexHtml, contains('--duoyi-accent: #0A84FF;'));
    expect(indexHtml, contains('flutter-view, flt-glass-pane'));
    expect(
      indexHtml,
      contains('<link rel="apple-touch-icon" sizes="180x180" href="icons/apple-touch-icon.png">'),
    );
    expect(
      indexHtml,
      contains('<link rel="icon" type="image/png" sizes="32x32" href="favicon.png">'),
    );
    expect(
      indexHtml,
      contains('<link rel="icon" type="image/png" sizes="192x192" href="icons/Icon-192.png">'),
    );
    expect(
      indexHtml,
      contains('<link rel="shortcut icon" href="favicon.ico">'),
    );
    expect(
      indexHtml,
      contains('<link rel="manifest" href="manifest.json">'),
    );
    expect(File('web/favicon.ico').existsSync(), isTrue);
    expect(indexHtml, contains('src="icons/Icon-192.png"'));
    expect(indexHtml, isNot(contains('duoyiSplashBg')));

    final guardScript = File('web/web_resume_guard.js').readAsStringSync();
    expect(guardScript, contains('HTMLCanvasElement.prototype'));
    expect(guardScript, contains('OffscreenCanvas.prototype'));
    expect(guardScript, contains('webglcontextlost'));
    expect(guardScript, contains('webglcontextrestored'));
    expect(guardScript, contains('visibilitychange'));
    expect(guardScript, contains('pageshow'));
    expect(guardScript, contains('duoyi:web-resume'));
    expect(guardScript, contains('RELOAD_COOLDOWN_MS'));
    expect(guardScript, contains('MAX_RELOADS_IN_WINDOW'));
    expect(guardScript, contains('sessionStorage'));

    expect(manifestJson, contains('"background_color": "#F6F7F9"'));
    expect(manifestJson, contains('"theme_color": "#0066D6"'));
    expect(manifestJson, isNot(contains('#0175C2')));

    expect(deepLink, contains('if (kIsWeb) return'));
    expect(geofence, contains('if (kIsWeb)'));
  });

  test('all brand themes configure non-bold NavigationRailThemeData', () {
    for (final brand in AppBrands.all) {
      final rail = brand.theme.navigationRailTheme;
      final navBar = brand.theme.navigationBarTheme;
      expect(rail.useIndicator, isTrue, reason: brand.id);
      expect(rail.backgroundColor, Colors.transparent, reason: brand.id);
      expect(rail.indicatorColor, navBar.indicatorColor, reason: brand.id);
      expect(
        rail.indicatorShape,
        isA<RoundedRectangleBorder>(),
        reason: brand.id,
      );
      expect(
        rail.selectedLabelTextStyle?.fontWeight,
        DesignTokens.fontWeightRegular,
        reason: brand.id,
      );
      expect(
        rail.unselectedLabelTextStyle?.fontWeight,
        DesignTokens.fontWeightRegular,
        reason: brand.id,
      );
    }
  });

  test('DailyQuotes supports EN without CJK leakage', () {
    expect(DailyQuotes.quotes.length, DailyQuotes.quotesEn.length);
    final cjk = RegExp(r'[\u3400-\u9fff]');
    for (var i = 0; i < DailyQuotes.quotesEn.length; i++) {
      final en = DailyQuotes.at(i, locale: AppLocale.en);
      expect(en.trim(), isNotEmpty);
      expect(en, isNot(matches(cjk)));
    }
    I18n.setLocale(AppLocale.en);
    expect(DailyQuotes.today(), isNot(matches(cjk)));
    expect(DailyQuotes.random(), isNot(matches(cjk)));
  });

  test('TodoBoardUiCopy trims trailing punctuation in sync notices', () {
    I18n.setLocale(AppLocale.zh);
    final warning = TodoBoardUiCopy.syncNoticeWarning('未登录云同步账号。');
    expect(warning, isNot(contains('。。')));
    expect(warning, contains('未登录云同步账号。恢复网络'));

    I18n.setLocale(AppLocale.en);
    final enError = TodoBoardUiCopy.syncNoticeError('Timed out.');
    expect(enError, isNot(contains('..')));
    expect(enError, contains('Timed out. It will retry'));
  });

  test('AlmanacLocaleFormat uses non-breaking ellipsis', () {
    final previewZh = AlmanacLocaleFormat.formatActivitiesPreview(
      '祭祀 祈福 求嗣 动土 安床',
      maxTerms: 3,
      locale: AppLocale.zh,
    );
    expect(previewZh, endsWith('\u00A0…'));

    final previewEn = AlmanacLocaleFormat.formatActivitiesPreview(
      '祭祀 祈福 求嗣 动土',
      maxTerms: 3,
      locale: AppLocale.en,
    );
    expect(previewEn, endsWith('\u00A0…'));
  });

  testWidgets('AppSectionHeader keeps action inline on 390px phone card width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 338,
              child: AppSectionHeader(
                title: '今日待办',
                actionLabel: '查看',
                onAction: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleRect = tester.getRect(find.text('今日待办'));
    final actionRect = tester.getRect(find.text('查看'));
    expect((titleRect.center.dy - actionRect.center.dy).abs(), lessThan(8));
    expect(actionRect.left, greaterThan(titleRect.right));
  });

  testWidgets('TodayScreen switches cleanly between 3-col 1440 and 2-col 1280', (
    tester,
  ) async {
    final providers = _TestProviders();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      providers.dispose();
      tester.view.reset();
    });

    Future<void> pumpAtShellSize(Size windowSize) async {
      tester.view.physicalSize = windowSize;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        providers.wrap(
          Scaffold(
            body: Row(
              children: [
                const SizedBox(width: 229),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: DesktopTokens.maxContentWidth,
                      ),
                      child: const TodayScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpAtShellSize(const Size(1440, 900));
    expect(find.text(TodayUiCopy.quickAccessTitle), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpAtShellSize(const Size(1280, 800));
    expect(find.text(TodayUiCopy.quickAccessTitle), findsNothing);
    final productivityCard = find.text(I18n.tr('today.productivity.weekly'));
    expect(productivityCard, findsOneWidget);
    expect(tester.getTopLeft(productivityCard).dx, greaterThan(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ThemePickerScreen renders 2-column grid on desktop', (
    tester,
  ) async {
    final providers = _TestProviders();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      providers.dispose();
      tester.view.reset();
    });

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(providers.wrap(const ThemePickerScreen()));
    await tester.pumpAndSettle();

    final firstCard = find.byKey(
      ValueKey('theme_card_bg_${AppBrands.defaultBrand.id}'),
    );
    final secondCard = find.byKey(
      ValueKey('theme_card_bg_${AppBrands.re0.id}'),
    );
    expect(firstCard, findsOneWidget);
    expect(secondCard, findsOneWidget);
    expect(
      (tester.getTopLeft(firstCard).dy - tester.getTopLeft(secondCard).dy)
          .abs(),
      lessThan(2),
    );
    expect(
      tester.getTopLeft(secondCard).dx,
      greaterThan(tester.getTopLeft(firstCard).dx + 200),
    );
    expect(tester.takeException(), isNull);
  });
}

class _TestProviders {
  final ThemeProvider theme = ThemeProvider();
  final TodoProvider todo = TodoProvider();
  final HabitProvider habit = HabitProvider();
  final PomodoroProvider pomodoro = PomodoroProvider();
  final DiaryProvider diary = DiaryProvider();
  final AnniversaryProvider anniversary = AnniversaryProvider();
  final CourseProvider course = CourseProvider();
  final GoalProvider goal = GoalProvider();
  final UserProvider user = UserProvider();
  final TimeAuditProvider timeAudit = TimeAuditProvider();
  final CalendarProvider calendar = CalendarProvider();
  final CountdownProvider countdown = CountdownProvider();
  final NoteProvider note = NoteProvider();
  final PreferencesProvider preferences = PreferencesProvider();
  final ShareProvider share = ShareProvider();
  final AuthProvider auth = AuthProvider();
  final AchievementProvider achievement = AchievementProvider();

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider.value(value: todo),
        ChangeNotifierProvider.value(value: habit),
        ChangeNotifierProvider.value(value: pomodoro),
        ChangeNotifierProvider.value(value: diary),
        ChangeNotifierProvider.value(value: anniversary),
        ChangeNotifierProvider.value(value: course),
        ChangeNotifierProvider.value(value: goal),
        ChangeNotifierProvider.value(value: user),
        ChangeNotifierProvider.value(value: timeAudit),
        ChangeNotifierProvider.value(value: calendar),
        ChangeNotifierProvider.value(value: countdown),
        ChangeNotifierProvider.value(value: note),
        ChangeNotifierProvider.value(value: preferences),
        ChangeNotifierProvider.value(value: share),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: achievement),
      ],
      child: MaterialApp(theme: theme.brand.theme, home: child),
    );
  }

  void dispose() {
    theme.dispose();
    todo.dispose();
    habit.dispose();
    pomodoro.dispose();
    diary.dispose();
    anniversary.dispose();
    course.dispose();
    goal.dispose();
    user.dispose();
    timeAudit.dispose();
    calendar.dispose();
    countdown.dispose();
    note.dispose();
    preferences.dispose();
    share.dispose();
    auth.dispose();
    achievement.dispose();
  }
}
