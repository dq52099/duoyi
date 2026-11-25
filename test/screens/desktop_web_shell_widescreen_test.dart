import '../support/habit_public_text_bounds.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart' show LocaleProvider, I18n, AppLocale;
import 'package:duoyi/core/desktop_tokens.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/l10n/generated/app_localizations.dart';
import 'package:duoyi/main.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/todo.dart';
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
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/eisenhower_matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

/// 宽屏外壳（NavigationRail）冒烟：
///
/// 外壳分派自运行时宽度判定（WebTarget.isWidescreenLayout，≥900 rail 壳）
/// 后不再依赖编译期档位；[WebTarget.debugDesktopWebBuild] 注入仅用于
/// 对齐桌面包的 tab 集过滤（隐藏小组件 tab）。视口写法沿用
/// today_mine_smoke_test 的 tester.view.physicalSize + devicePixelRatio。
Finder get _maxWidthBox =>
    find.byKey(const ValueKey('desktop_web_body_max_width'));

Widget _wrapShell(
  ThemeData theme, {
  HabitProvider? habitProvider,
  TodoProvider? todoProvider,
  ThemeProvider? themeProvider,
  GlobalKey? captureKey,
  double textScaleFactor = 1,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => todoProvider ?? TodoProvider()),
      ChangeNotifierProvider(create: (_) => habitProvider ?? HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      if (themeProvider == null)
        ChangeNotifierProvider(create: (_) => ThemeProvider())
      else
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
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
      locale: Locale(I18n.current == AppLocale.en ? 'en' : 'zh'),
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
        child: captureKey == null
            ? child!
            : RepaintBoundary(key: captureKey, child: child!),
      ),
      home: MainShell(),
    ),
  );
}

Future<void> _pumpShellAt(
  WidgetTester tester,
  ThemeData theme,
  Size size, {
  HabitProvider? habitProvider,
  TodoProvider? todoProvider,
  double textScaleFactor = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _wrapShell(
      theme,
      habitProvider: habitProvider,
      todoProvider: todoProvider,
      textScaleFactor: textScaleFactor,
    ),
  );
  await tester.pumpAndSettle();
}

Finder _habitCheckinCard(String id) =>
    find.byKey(ValueKey('habit_checkin_card_$id'));

Finder _habitTodayScrollable() => find.descendant(
  of: find.byKey(const ValueKey('habit_today_scroll_view')),
  matching: find.byType(Scrollable),
).first;

void _expectHabitContained(Rect inner, Rect outer, String reason) {
  expect(inner.width, greaterThan(0), reason: reason);
  expect(inner.height, greaterThan(0), reason: reason);
  expect(inner.left, greaterThanOrEqualTo(outer.left - .5), reason: reason);
  expect(inner.top, greaterThanOrEqualTo(outer.top - .5), reason: reason);
  expect(inner.right, lessThanOrEqualTo(outer.right + .5), reason: reason);
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + .5), reason: reason);
}

// Public layout contract: a/b occupy the first row and c starts the next row.
// No sliver type, private card height or grid delegate is part of this oracle.
Future<void> _expectHabitPairGeometry(WidgetTester tester) async {
  final semantics = tester.ensureSemantics();
  try {
    await tester.scrollUntilVisible(
      _habitCheckinCard('a'), 160, scrollable: _habitTodayScrollable(),
    );
    await tester.pumpAndSettle();
    final cards = <String, Rect>{};
    for (final id in ['a', 'b', 'c']) {
      final card = _habitCheckinCard(id);
      expect(card, findsOneWidget);
      final rect = tester.getRect(card);
      final viewport = RenderAbstractViewport.maybeOf(
        tester.renderObject<RenderBox>(card),
      );
      if (viewport is! RenderBox) {
        throw TestFailure('Habit card $id must have a box viewport');
      }
      final viewportBox = viewport as RenderBox;
      final viewportRect = MatrixUtils.transformRect(
        viewportBox.getTransformTo(null), Offset.zero & viewportBox.size,
      );
      _expectHabitContained(rect, viewportRect, '$id: complete visible card');
      cards[id] = rect;

      final title = find.descendant(of: card, matching: find.text('习惯$id'));
      expect(title, findsOneWidget);
      expect(
        tester.getSemantics(title).getSemanticsData().label,
        contains('习惯$id'),
      );
      final paragraphs = find.descendant(
        of: card, matching: find.byType(Text),
      );
      expect(paragraphs.evaluate(), isNotEmpty);
      for (final element in paragraphs.evaluate()) {
        final paragraph = element.findRenderObject()! as RenderParagraph;
        final text = paragraph.text.toPlainText();
        expect(paragraph.didExceedMaxLines, isFalse, reason: text);
        expect(paragraph.overflow, isNot(TextOverflow.ellipsis), reason: text);
        expect(paragraph.maxLines, isNull, reason: text);
        final paragraphRect = MatrixUtils.transformRect(
          paragraph.getTransformTo(null), Offset.zero & paragraph.size,
        );
        _expectHabitContained(paragraphRect, rect, '$id: $text');
        expectHabitTextPaintBounds(
          paragraph, cardRect: rect, reason: '$id: full visible text $text',
        );
        expect(
          (paragraph.localToGlobal(const Offset(1, 0)) -
                  paragraph.localToGlobal(Offset.zero)).distance,
          closeTo(1, .001), reason: '$id: text must not shrink',
        );
      }
      final checkIn = find.descendant(
        of: card, matching: find.byType(FilledButton),
      );
      expect(checkIn, findsOneWidget);
      final buttonRect = tester.getRect(checkIn);
      expect(buttonRect.width, greaterThanOrEqualTo(44));
      expect(buttonRect.height, greaterThanOrEqualTo(44));
      _expectHabitContained(buttonRect, rect, '$id: check-in target');
      final node = tester.getSemantics(checkIn);
      expect(node.rect.width, greaterThanOrEqualTo(44));
      expect(node.rect.height, greaterThanOrEqualTo(44));
      expect(node.getSemanticsData().label, contains('打卡'));
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    }
    final a = cards['a']!, b = cards['b']!, c = cards['c']!;
    expect(a.top, closeTo(b.top, .5));
    expect(a.right, lessThan(b.left));
    expect(a.width, closeTo(b.width, .5));
    expect(c.left, closeTo(a.left, .5));
    expect(c.width, closeTo(a.width, .5));
    expect(c.top, greaterThanOrEqualTo(a.bottom));
    expect(c.top, greaterThanOrEqualTo(b.bottom));
    expect(tester.takeException(), isNull);
  } finally {
    semantics.dispose();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebTarget.debugDesktopWebBuild = true;
  });
  tearDown(() {
    WebTarget.debugDesktopWebBuild = null;
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets('priority paired shell screenshots', (tester) async {
    final directory =
        Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
    if (directory == null || directory.isEmpty) return;
    WebTarget.debugDesktopWebBuild = null;
    addTearDown(tester.view.reset);
    final previousDisableShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = previousDisableShadows);
    try {
      await tester.runAsync(loadWidgetPolishScreenshotFonts);
      for (final brand in [AppBrands.defaultBrand, AppBrands.liquidGlass]) {
        for (final locale in AppLocale.values) {
          I18n.setLocale(locale);
          SharedPreferences.setMockInitialValues({'active_brand': brand.id});
          final provider = ThemeProvider();
          await provider.loadFromStorage();
          expect(provider.brand.id, brand.id);
          final base = brand.theme;
          final theme = base.copyWith(
            navigationBarTheme: base.navigationBarTheme.copyWith(
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => base.navigationBarTheme.labelTextStyle
                    ?.resolve(states)
                    ?.copyWith(
                      fontFamily: 'DuoyiScreenshotLatin',
                      fontFamilyFallback: const ['DuoyiScreenshot'],
                    ),
              ),
            ),
            textTheme: base.textTheme.apply(
              fontFamily: 'DuoyiScreenshotLatin',
              fontFamilyFallback: const ['DuoyiScreenshot'],
            ),
            appBarTheme: base.appBarTheme.copyWith(
              titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
                fontFamily: 'DuoyiScreenshotLatin',
                fontFamilyFallback: const ['DuoyiScreenshot'],
              ),
            ),
          );
          for (final width in [390.0, 899.0, 900.0, 1280.0]) {
            final key = GlobalKey();
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            await tester.pumpWidget(
              _wrapShell(
                theme,
                themeProvider: provider,
                captureKey: key,
                textScaleFactor: width == 390 ? 1.6 : 1,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(TodayScreen), findsOneWidget);
            expect(
              find.byType(NavigationRail),
              width >= 900 ? findsOneWidget : findsNothing,
            );
            expect(
              find.byType(NavigationBar),
              width < 900 ? findsOneWidget : findsNothing,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '${brand.id}/${locale.name}/$width',
            );
            Future<void> capture(String suffix) => tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              image.dispose();
              final file = File(
                '$directory/${brand.id}-shell$suffix-${locale.name}-${width.toInt()}.png',
              );
              file.parent.createSync(recursive: true);
              file.writeAsBytesSync(bytes!.buffer.asUint8List());
            });
            await capture('');
            tester.state<MainShellState>(find.byType(MainShell)).navigateTo(6);
            await tester.pumpAndSettle();
            expect(find.byType(MineScreen), findsOneWidget);
            expect(tester.takeException(), isNull);
            await capture('-mine');
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
          provider.dispose();
        }
      }
    } finally {
      debugDisableShadows = previousDisableShadows;
    }
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
    final todoProvider = TodoProvider();
    await todoProvider.addTodo(
      TodoItem(title: '桌面矩阵导航', quadrant: EisenhowerQuadrant.urgentImportant),
    );
    await _pumpShellAt(
      tester,
      AppBrands.liquidGlass.theme,
      const Size(1280, 800),
      todoProvider: todoProvider,
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    tester.state<MainShellState>(find.byType(MainShell)).navigateTo(1);
    await tester.pumpAndSettle();

    expect(find.byType(TodoScreen), findsOneWidget);
    expect(find.byType(EisenhowerMatrix), findsOneWidget);
    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(find.byType(EisenhowerMatrix), findsNothing);
    expect(find.text('桌面矩阵导航'), findsOneWidget);
    await tester.tap(find.text('四象限'));
    await tester.pumpAndSettle();
    expect(find.byType(EisenhowerMatrix), findsOneWidget);
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

  testWidgets('1280x800 未注入编译期档位（responsive 包）：宽度达阈值仍走 rail 壳', (tester) async {
    WebTarget.debugDesktopWebBuild = null;
    await _pumpShellAt(
      tester,
      AppBrands.defaultBrand.theme,
      const Size(1280, 800),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(
      tester.getSize(_maxWidthBox).width,
      lessThanOrEqualTo(DesktopTokens.maxContentWidth),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('1280x800 宽屏习惯今日打卡走双列懒构建网格', (tester) async {
    final habitProvider = HabitProvider();
    for (final id in ['a', 'b', 'c']) {
      await habitProvider.addHabit(
        Habit(id: id, name: '习惯$id', icon: Icons.book.codePoint.toString()),
      );
    }
    await _pumpShellAt(
      tester,
      AppBrands.defaultBrand.theme,
      const Size(1280, 800),
      habitProvider: habitProvider,
    );

    tester.state<MainShellState>(find.byType(MainShell)).navigateTo(2);
    await tester.pumpAndSettle();

    expect(find.byType(HabitScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('habit_today_checkin_sliver')),
      findsOneWidget,
    );
    await _expectHabitPairGeometry(tester);
    expect(find.byKey(const ValueKey('habit_checkin_card_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('habit_checkin_card_c')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (width, textScaleFactor) in [
    (1120.0, 1.6),
    (1120.0, 2.0),
    (1400.0, 1.6),
    (1400.0, 2.0),
  ]) {
    testWidgets('${width.toInt()}px 宽屏习惯打卡网格随 ${textScaleFactor}x 字体缩放扩高', (
      tester,
    ) async {
      final habitProvider = HabitProvider();
      for (final id in ['a', 'b', 'c']) {
        await habitProvider.addHabit(
          Habit(id: id, name: '习惯$id', icon: Icons.book.codePoint.toString()),
        );
      }
      await _pumpShellAt(
        tester,
        AppBrands.defaultBrand.theme,
        Size(width, 800),
        habitProvider: habitProvider,
        textScaleFactor: textScaleFactor,
      );

      tester.state<MainShellState>(find.byType(MainShell)).navigateTo(2);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('habit_today_checkin_sliver')),
        findsOneWidget,
      );

      final card = find.byKey(const ValueKey('habit_checkin_card_a'));
      await tester.scrollUntilVisible(
        card,
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('habit_today_scroll_view')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await _expectHabitPairGeometry(tester);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'habit cards must not overflow at ${width.toInt()}px and ${textScaleFactor}x text',
      );
    });
  }

  testWidgets('800x600 宽度不足阈值：注入 desktop 档也回落移动底导航壳', (tester) async {
    await _pumpShellAt(
      tester,
      AppBrands.defaultBrand.theme,
      const Size(800, 600),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(_maxWidthBox, findsNothing);
    expect(find.byType(TodayScreen), findsOneWidget);
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
