import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

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
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/account_ui_copy.dart';
import 'package:duoyi/core/todo_ui_copy.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/screens/lock_settings_screen.dart';
import 'package:duoyi/screens/more_apps_screen.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/brand_background.dart';

import '../support/widget_polish_screenshot_font.dart';
import '../support/rendered_information_chip_contrast.dart';

Widget _wrap(
  Widget child, {
  AuthProvider? authProvider,
  UserProvider? userProvider,
  TodoProvider? todoProvider,
  ThemeProvider? themeProvider,
  AppUpdateService? updater,
  ThemeData? theme,
  double? textScale,
  bool liveTheme = false,
  bool screenshotFonts = false,
}) {
  ThemeData? appTheme() {
    final base = liveTheme ? themeProvider!.brand.theme : theme;
    if (!screenshotFonts || base == null) return base;
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: 'DuoyiScreenshotLatin',
        fontFamilyFallback: const ['DuoyiScreenshot'],
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: 'DuoyiScreenshotLatin',
        fontFamilyFallback: const ['DuoyiScreenshot'],
      ),
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: 'DuoyiScreenshotLatin',
          fontFamilyFallback: const ['DuoyiScreenshot'],
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        contentTextStyle: base.snackBarTheme.contentTextStyle?.copyWith(
          fontFamily: 'DuoyiScreenshotLatin',
          fontFamilyFallback: const ['DuoyiScreenshot'],
        ),
      ),
    );
  }

  Widget buildApp() => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    builder: textScale == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
    home: child,
  );
  return MultiProvider(
    providers: [
      if (todoProvider == null)
        ChangeNotifierProvider(create: (_) => TodoProvider())
      else
        ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      if (themeProvider == null)
        ChangeNotifierProvider(create: (_) => ThemeProvider())
      else
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
      ChangeNotifierProvider(create: (_) => CalendarProvider()),
      if (userProvider == null)
        ChangeNotifierProvider(create: (_) => UserProvider())
      else
        ChangeNotifierProvider<UserProvider>.value(value: userProvider),
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
      if (authProvider == null)
        ChangeNotifierProvider(create: (_) => AuthProvider())
      else
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider(create: (_) => AiService()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
      ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
      if (updater != null)
        ChangeNotifierProvider<AppUpdateService>.value(value: updater)
      else
        ChangeNotifierProvider(
          create: (_) => AppUpdateService(
            repo: 'dq52099/duoyi',
            currentVersion: AppVersion.name,
          ),
        ),
    ],
    child: liveTheme
        ? AnimatedBuilder(
            animation: themeProvider!,
            builder: (context, child) => buildApp(),
          )
        : buildApp(),
  );
}

double? _topOrScrolledAway(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return null;
  return tester.getTopLeft(finder).dy;
}

Finder _todayCompletionButton(Finder tile) {
  final toggle = find.descendant(
    of: tile,
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.checked != null,
    ),
  );
  return find.descendant(of: toggle, matching: find.byType(InkWell));
}

Future<void> _captureTodayCompletion(WidgetTester tester, String name) async {
  final directory = Platform.environment['DUOYI_TODAY_COMPLETION_SCREENSHOTS'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('today-completion-evidence')),
    );
    final picture = await boundary.toImage(pixelRatio: 1);
    final data = await picture.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    final file = File('$directory/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _expectTodayCompletionContrast(
  WidgetTester tester,
  Finder tile,
  String brand,
) async {
  final text = find.descendant(
    of: tile,
    matching: find.text(I18n.tr('today.completed')),
  );
  final foreground = tester.widget<Text>(text).style!.color!;
  final box = tester.renderObject<RenderBox>(
    find.ancestor(of: text, matching: find.byType(DecoratedBox)).first,
  );
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('today-completion-evidence')),
  );
  final rect = MatrixUtils.transformRect(
    box.getTransformTo(boundary),
    Offset.zero & box.size,
  );
  final rows = await tester.runAsync(() async {
    final picture = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await picture.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return [
        for (final fraction in [0.25, 0.5, 0.75])
          (() {
            final point = Offset(
              rect.left + rect.width * fraction,
              rect.top + 1,
            );
            final offset =
                (point.dy.floor() * picture.width + point.dx.floor()) * 4;
            final background = Color.fromARGB(
              255,
              data.getUint8(offset),
              data.getUint8(offset + 1),
              data.getUint8(offset + 2),
            );
            return <String, Object>{
              'brand': brand,
              'foreground': foreground.toARGB32(),
              'background': background.toARGB32(),
              'contrast': appContrastRatio(
                Color.alphaBlend(foreground, background),
                background,
              ),
            };
          })(),
      ];
    } finally {
      picture.dispose();
    }
  });
  final destination =
      Platform.environment['DUOYI_TODAY_COMPLETION_MEASUREMENTS'];
  if (destination != null) {
    File(
      destination,
    ).writeAsStringSync('${jsonEncode(rows)}\n', mode: FileMode.append);
  }
  for (final row in rows!) {
    expect(
      row['contrast'],
      greaterThanOrEqualTo(4.5),
      reason: 'Completed status against actual raster padding: $row',
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    testWidgets('Today completion remains visible and can reopen $brand', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'active_brand': brand,
        'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      });
      final theme = ThemeProvider();
      await theme.loadFromStorage();
      final todos = TodoProvider();
      final task = TodoItem(
        id: 'today-completion-retention',
        title: '保留完成任务并允许取消',
        date: DateTime.now(),
      );
      await todos.addTodo(task);
      await tester.runAsync(loadWidgetPolishScreenshotFonts);
      await tester.pumpWidget(
        _wrap(
          const RepaintBoundary(
            key: ValueKey('today-completion-evidence'),
            child: BrandBackground(child: TodayScreen()),
          ),
          todoProvider: todos,
          themeProvider: theme,
          textScale: 2,
          liveTheme: true,
          screenshotFonts: true,
        ),
      );
      await tester.pumpAndSettle();
      final tile = find.byKey(ValueKey('today_todo_${task.id}'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await _captureTodayCompletion(tester, '$brand-pending');
      await tester.tap(_todayCompletionButton(tile));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TodoUiCopy.actionContinue));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TodoUiCopy.actionSkip));
      await tester.pumpAndSettle();
      expect(todos.todos.single.isCompleted, isTrue);
      expect(
        tile,
        findsOneWidget,
        reason: 'ROOT-7: completing must retain the row',
      );
      final title = tester.widget<Text>(
        find.descendant(of: tile, matching: find.text(task.title)),
      );
      expect(title.style?.decoration, TextDecoration.lineThrough);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await _expectTodayCompletionContrast(tester, tile, brand);
      await _captureTodayCompletion(tester, '$brand-completed');
      await tester.tap(_todayCompletionButton(tile));
      await tester.pumpAndSettle();
      expect(todos.todos.single.isCompleted, isFalse);
      expect(todos.todos.single.completedAt, isNull);
      expect(todos.todos.single.isArchivedAfterRollover, isFalse);
      expect(tile, findsOneWidget);
      expect(
        find.text(TodoBoardUiCopy.restoredFeedback(task.title)),
        findsOneWidget,
      );
      expect(find.text(TodoUiCopy.completedFeedback(task.title)), findsNothing);
      final stored = TodoProvider();
      await stored.loadFromStorage();
      expect(stored.todos.single.isCompleted, isFalse);
      expect(stored.todos.single.completedAt, isNull);
      stored.dispose();
      await _captureTodayCompletion(tester, '$brand-reopened');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      todos.dispose();
      theme.dispose();
    });

    testWidgets('Today completed reminder checkbox can reopen $brand', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'active_brand': brand,
        'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      });
      final todos = TodoProvider();
      final now = DateTime.now();
      final task = TodoItem(
        id: 'today-reminder-reopen',
        title: '已完成提醒可以取消',
        date: now,
        dueDate: DateTime(now.year, now.month, now.day, 23, 59),
        isCompleted: true,
        completedAt: now,
      );
      await todos.addTodo(task);
      final theme = ThemeProvider();
      await theme.loadFromStorage();
      await tester.pumpWidget(
        _wrap(
          const TodayScreen(),
          todoProvider: todos,
          themeProvider: theme,
          liveTheme: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('today_reminder_header_toggle')),
      );
      await tester.pumpAndSettle();
      final tile = find.byKey(ValueKey('today_reminder_todo_${task.id}'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(_todayCompletionButton(tile));
      await tester.pumpAndSettle();
      expect(todos.todos.single.isCompleted, isFalse);
      expect(todos.todos.single.completedAt, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      todos.dispose();
      theme.dispose();
    });
  }

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    testWidgets('Mine update live root theme roundtrip $brand', (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'active_brand': brand,
        'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      });
      final theme = ThemeProvider();
      final updater = _HeldMineUpdater();
      addTearDown(theme.dispose);
      addTearDown(updater.dispose);
      await theme.loadFromStorage();
      await tester.pumpWidget(
        _wrap(
          const MineScreen(),
          themeProvider: theme,
          updater: updater,
          textScale: 2,
          liveTheme: true,
        ),
      );
      await tester.pumpAndSettle();
      final onTap = await _mineUpdateCallback(tester);
      onTap();
      await tester.pump();
      expect(updater.calls, 1);
      updater.finish();
      await tester.pumpAndSettle();
      final dialog = tester.element(find.byType(AppDialog));
      final route = ModalRoute.of(dialog)!;
      final screen = tester.state(find.byType(MineScreen));
      void expectRetained() {
        final current = tester.element(find.byType(AppDialog));
        expect(current, same(dialog));
        expect(ModalRoute.of(current), same(route));
        expect(route.isCurrent, isTrue);
        expect(Theme.of(current).colorScheme, theme.brand.theme.colorScheme);
        expect(tester.state(find.byType(MineScreen)), same(screen));
        expect(updater.calls, 1);
        expect(tester.takeException(), isNull);
      }

      expectRetained();
      for (final next in [
        brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand',
        brand,
      ]) {
        var done = false;
        final change = theme.setBrand(next).whenComplete(() => done = true);
        for (var frame = 0; frame < 100 && !done; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(done, isTrue);
        expect(await change, isTrue);
        await tester.pumpAndSettle();
        expect(theme.brand.id, next);
        expectRetained();
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expectRetained();
      }
      Navigator.of(dialog).pop();
      await tester.pumpAndSettle();
      expect(route.isActive, isFalse);
      expect(find.byType(AppDialog), findsNothing);
      expect(tester.state(find.byType(MineScreen)), same(screen));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  for (final changedSource in ['covered', 'account', 'forced', 'provider']) {
    testWidgets('Mine update completion ignores $changedSource source', (
      tester,
    ) async {
      final updater = _HeldMineUpdater();
      addTearDown(updater.dispose);
      await tester.pumpWidget(_wrap(const MineScreen(), updater: updater));
      await tester.pumpAndSettle();
      final onTap = await _mineUpdateCallback(tester);
      onTap();
      onTap();
      await tester.pump();
      expect(updater.calls, 1);
      expect(_mineUpdateInkWell(tester).onTap, isNull);
      if (changedSource == 'covered') {
        Navigator.of(tester.element(find.byType(MineScreen))).push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Cover')),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
      } else if (changedSource == 'account') {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      } else if (changedSource == 'forced') {
        updater.forceUpdate = true;
      } else {
        final replacement = _HeldMineUpdater();
        addTearDown(replacement.dispose);
        await tester.pumpWidget(
          _wrap(const MineScreen(), updater: replacement),
        );
        await tester.pump();
      }
      updater.finish();
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      if (changedSource == 'covered') {
        expect(find.text('Cover'), findsOneWidget);
        Navigator.of(tester.element(find.text('Cover'))).pop();
        await tester.pumpAndSettle();
        expect(_mineUpdateInkWell(tester).onTap, isNotNull);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Mine update owns one dialog through locale change and dismissal',
    (tester) async {
      final updater = _HeldMineUpdater();
      addTearDown(updater.dispose);
      await tester.pumpWidget(_wrap(const MineScreen(), updater: updater));
      await tester.pumpAndSettle();
      final onTap = await _mineUpdateCallback(tester);
      onTap();
      await tester.pump();
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      onTap();
      expect(updater.calls, 1);
      updater.finish();
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      onTap();
      expect(updater.calls, 1);
      final navigator = Navigator.of(tester.element(find.byType(AppDialog)));
      navigator.pop();
      await tester.pump();
      onTap();
      expect(updater.calls, 1, reason: 'Guard includes the exit animation');
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      onTap();
      await tester.pump();
      expect(updater.calls, 2);
      updater.finish();
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final fixture in [
    for (final locale in AppLocale.values)
      for (final brand in [AppBrands.defaultBrand, AppBrands.liquidGlass])
        (locale: locale, brand: brand),
  ]) {
    final locale = fixture.locale;
    final brand = fixture.brand;
    final name =
        'Mine overview preserves enlarged labels: '
        '${locale.name} ${brand.id}';
    testWidgets(name, (tester) async {
      addTearDown(tester.view.reset);
      I18n.setLocale(locale);
      for (final presentation in [
        (width: 320.0, scale: 1.6),
        if (brand.id == AppBrands.defaultBrand.id) ...[
          (width: 320.0, scale: 3.2),
          (width: 960.0, scale: 3.2),
        ],
      ]) {
        for (final loggedIn in [
          if (brand.id == AppBrands.defaultBrand.id) false,
          true,
        ]) {
          tester.view.physicalSize = Size(presentation.width, 844);
          tester.view.devicePixelRatio = 1;
          await tester.runAsync(loadWidgetPolishScreenshotFonts);
          SharedPreferences.setMockInitialValues({'active_brand': brand.id});
          final themeProvider = ThemeProvider();
          addTearDown(themeProvider.dispose);
          await themeProvider.loadFromStorage();
          expect(themeProvider.brand.id, brand.id);
          final base = brand.theme;
          final theme = base.copyWith(
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
          final auth = AuthProvider(
            initialState: loggedIn
                ? const AuthState(
                    userId: 'overview-user',
                    username: 'overview',
                    displayName: 'Overview',
                    token: 'synthetic-overview-token',
                  )
                : const AuthState(),
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient((_) async => http.Response('{}', 404)),
            ),
          );
          addTearDown(auth.dispose);
          final captureKey = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: captureKey,
              child: _wrap(
                const BrandBackground(
                  child: MineScreen(useShellBackground: true),
                ),
                authProvider: auth,
                themeProvider: themeProvider,
                theme: theme,
                textScale: presentation.scale,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final header = find.byKey(const ValueKey('mine_header_stable_box'));
          final status = find.descendant(
            of: header,
            matching: find.text(
              loggedIn
                  ? AccountUiCopy.statusLoggedIn
                  : AccountUiCopy.statusNotLoggedIn,
            ),
          );
          expect(status, findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(status).didExceedMaxLines,
            isFalse,
          );
          if (locale == AppLocale.en) {
            final paragraph = tester.renderObject<RenderParagraph>(status);
            final text = paragraph.text.toPlainText();
            for (final word in RegExp(r'\S+').allMatches(text)) {
              expect(
                paragraph
                    .getBoxesForSelection(
                      TextSelection(
                        baseOffset: word.start,
                        extentOffset: word.end,
                      ),
                    )
                    .length,
                1,
                reason: 'Account status must wrap at words: ${word.group(0)}',
              );
            }
          }
          expect(
            find.descendant(of: header, matching: find.byType(FittedBox)),
            findsNothing,
          );
          if (loggedIn &&
              presentation.width == 320 &&
              presentation.scale == 1.6) {
            await expectInformationChipContrast(tester, captureKey, [
              AccountUiCopy.statusLoggedIn,
            ]);
            await _captureMineOverview(
              tester,
              captureKey,
              '${brand.id}-${locale.name}-logged-in-1.6-top',
            );
          }
          final action = loggedIn
              ? find.byKey(const ValueKey('mine_top_logout_button'))
              : find.widgetWithText(FilledButton, I18n.tr('auth.login'));
          expect(tester.getSize(action).shortestSide, greaterThanOrEqualTo(44));
          final label = loggedIn ? null : find.text(I18n.tr('auth.login'));
          if (label != null) {
            expect(
              tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
              isFalse,
            );
          }
          final captureName = '${locale.name}-${presentation.scale}';
          if (!loggedIn && presentation.width == 320) {
            await _captureMineOverview(tester, captureKey, '$captureName-top');
          }
          final scrollable = find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.restorationId == 'mine_screen_list',
          );
          for (final key in [
            'mine.stats.todos',
            'mine.stats.streak',
            'mine.stats.focus',
            'mine.stats.productivity',
          ]) {
            final title = find.text(I18n.tr(key));
            await tester.scrollUntilVisible(title, 160, scrollable: scrollable);
            await tester.pumpAndSettle();
            expect(tester.widget<Text>(title).maxLines, isNull, reason: key);
            expect(
              tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
              isFalse,
              reason: key,
            );
            final metric = find.ancestor(
              of: title,
              matching: find.byType(AppMetricCard),
            );
            for (final text
                in find
                    .descendant(of: metric, matching: find.byType(Text))
                    .evaluate()) {
              final paragraph = tester.renderObject<RenderParagraph>(
                find.byWidget(text.widget),
              );
              expect(paragraph.didExceedMaxLines, isFalse, reason: key);
              expect(
                paragraph.textScaler.scale(11),
                closeTo(11 * presentation.scale, 0.001),
              );
            }
            expect(tester.takeException(), isNull);
          }
          if (!loggedIn && presentation.width == 320) {
            await _captureMineOverview(
              tester,
              captureKey,
              '$captureName-stats',
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });
  }

  for (final locale in AppLocale.values) {
    testWidgets(
      'Mine menu labels wrap and follow iOS surfaces: ${locale.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        I18n.setLocale(locale);
        await tester.runAsync(loadWidgetPolishScreenshotFonts);
        final text = AppBrands.defaultBrand.theme.textTheme.apply(
          fontFamily: 'DuoyiScreenshotLatin',
          fontFamilyFallback: const ['DuoyiScreenshot'],
        );
        final base = AppBrands.defaultBrand.theme;
        final theme = base.copyWith(
          textTheme: text,
          primaryTextTheme: text,
          appBarTheme: base.appBarTheme.copyWith(
            titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
              fontFamily: 'DuoyiScreenshotLatin',
              fontFamilyFallback: const ['DuoyiScreenshot'],
            ),
          ),
        );
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: _wrap(const MineScreen(), theme: theme, textScale: 1.6),
          ),
        );
        await tester.pumpAndSettle();
        final scrollable = find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.restorationId == 'mine_screen_list',
        );
        Future<void> capture(String name) async {
          final directory =
              Platform.environment['DUOYI_ME_ENTRY_SCREENSHOT_DIR'];
          if (directory == null || directory.isEmpty) return;
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary =
                captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            final file = File('$directory/mine-${locale.name}-$name.png');
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(data!.buffer.asUint8List());
          });
        }

        await capture('top');
        for (final key in [
          'mine.tile.more_apps',
          'preferences.title',
          'app_lock.title',
          'mine.tile.integrations',
          'sync_conflict.title',
          'mine.tile.notification_history',
          'mine.tile.notification_settings',
          'mine.tile.feedback',
        ]) {
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();
          final label = find.text(I18n.tr(key));
          await tester.scrollUntilVisible(label, 240, scrollable: scrollable);
          await tester.pumpAndSettle();
          final paragraph = tester.renderObject<RenderParagraph>(label);
          expect(paragraph.didExceedMaxLines, isFalse, reason: key);
          expect(tester.widget<Text>(label).softWrap, isTrue);
          final action = find
              .ancestor(of: label, matching: find.byType(InkWell))
              .first;
          expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
          final card = tester.widget<AppSurfaceCard>(
            find
                .ancestor(of: label, matching: find.byType(AppSurfaceCard))
                .first,
          );
          expect(card.borderRadius, isNull);
          expect(card.border, theme.extension<AppSurfaceStyle>()!.cardBorder);
          expect(card.color, isNull);
          if (key == 'preferences.title' ||
              key == 'mine.tile.notification_settings') {
            await capture(key.split('.').last);
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final size in [(width: 390.0, scale: 1.0), (width: 320.0, scale: 1.6)]) {
    testWidgets('Mine App Lock retained route ${size.width}/${size.scale}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(size.width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(const MineScreen(), textScale: size.scale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final entrance = find.text(I18n.tr('app_lock.title'));
      await tester.scrollUntilVisible(
        entrance,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(entrance);
      await tester.pumpAndSettle();
      await tester.tap(entrance);
      await tester.pumpAndSettle();
      final route = find.byType(LockSettingsScreen);
      final originalState = tester.state<State<LockSettingsScreen>>(route);
      final lock = tester.element(route).read<AppLockProvider>();
      final prefs = await SharedPreferences.getInstance();
      var lockNotifications = 0;
      void recordNotification() => lockNotifications++;
      lock.addListener(recordNotification);
      addTearDown(() => lock.removeListener(recordNotification));

      Future<void> toggle() async {
        await tester.ensureVisible(find.byType(Switch).first);
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> confirm(String pin) async {
        await tester.enterText(find.byType(TextField).last, pin);
        await tester.tap(
          find.widgetWithText(FilledButton, I18n.tr('action.confirm')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await toggle();
      await tester.enterText(find.byType(TextField).last, '2468');
      final field = tester.widget<EditableText>(find.byType(EditableText).last);
      final controller = field.controller;
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      final focus = field.focusNode;
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        final retained = tester.widget<EditableText>(
          find.byType(EditableText).last,
        );
        expect(
          tester.state<State<LockSettingsScreen>>(route),
          same(originalState),
        );
        expect(retained.controller, same(controller));
        expect(retained.focusNode, same(focus));
        expect(retained.controller.text, '2468');
        expect(
          retained.controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 3),
        );
        expect(retained.focusNode.hasFocus, isTrue);
        expect(retained.obscureText, isTrue);
        expect(find.text(I18n.tr('app_lock.dialog.set_pin')), findsOneWidget);
        expect(lock.enabled, isFalse);
        expect(lockNotifications, 0);
        expect(prefs.getString('app_lock_pin_hash'), isNull);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(
        find.widgetWithText(TextButton, I18n.tr('action.cancel')),
      );
      await tester.pumpAndSettle();
      expect(lock.enabled, isFalse);
      expect(lockNotifications, 0);

      await toggle();
      await tester.enterText(find.byType(TextField).last, '2468');
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.text(I18n.tr('app_lock.dialog.confirm_pin')), findsOneWidget);
      expect(
        tester.state<State<LockSettingsScreen>>(route),
        same(originalState),
      );
      await confirm('2468');
      expect(lock.enabled, isTrue);
      expect(await lock.verify('2468'), isTrue);
      expect(lockNotifications, 1);

      await toggle();
      await confirm('1357');
      expect(lock.enabled, isTrue);
      expect(lockNotifications, 1);
      await toggle();
      await confirm('2468');
      expect(lock.enabled, isFalse);
      expect(lockNotifications, 2);
      await tester.pump(const Duration(seconds: 5));
      lock.removeListener(recordNotification);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Today greeting changes on a locale notifier alone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const TodayScreen()));
    await tester.pumpAndSettle();
    final zhGreeting = AppBrands.defaultBrand.strings.greetingFor(
      DateTime.now(),
    );
    expect(find.textContaining(zhGreeting), findsWidgets);
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    final enGreeting = AppBrands.defaultBrand.strings.greetingFor(
      DateTime.now(),
    );
    expect(enGreeting, isNot(zhGreeting));
    expect(find.textContaining(enGreeting), findsWidgets);
    expect(find.textContaining(zhGreeting), findsNothing);
    expect(find.text(I18n.tr('today.todos')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Today open delete confirmation stays bound to its original account',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final todos = TodoProvider();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await todos.addTodo(
        TodoItem(id: 'old-account-task', title: '原账号任务', date: today),
      );
      await tester.pumpWidget(_wrap(const TodayScreen(), todoProvider: todos));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('原账号任务'));
      await tester.pumpAndSettle();
      await tester.drag(find.text('原账号任务'), const Offset(-180, 0));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(const ValueKey('today_todo_swipe_delete_button'))
            .hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(find.text('删除任务？'), findsOneWidget);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      todos.resetLocalState();
      // Account cleanup replaces persisted data before the next hydration.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('todos');
      await todos.addTodo(
        TodoItem(id: 'old-account-task', title: '新账号任务', date: today),
      );
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('原账号任务'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.delete')),
      );
      await tester.pumpAndSettle();
      expect(todos.todos.map((todo) => todo.id), ['old-account-task']);
      expect(todos.todos.single.title, '新账号任务');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retained Today suggestion callback rejects a same-ID new account',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final todos = TodoProvider();
      final old = TodoItem(
        id: 'suggestion-account-collision',
        title: '原账号建议',
        date: DateTime.now().add(const Duration(days: 2)),
        priority: TodoPriority.urgent,
      );
      await todos.addTodo(old);
      await tester.pumpWidget(_wrap(const TodayScreen(), todoProvider: todos));
      await tester.pumpAndSettle();
      final section = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_TodayReminderSection',
      );
      expect(section, findsOneWidget);
      final dynamic openedSection = tester.widget(section);
      final callback =
          openedSection.onAddToday as Future<void> Function(TodoItem);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      todos.resetLocalState();
      final next = TodoItem(
        id: old.id,
        title: '新账号建议',
        date: DateTime.now().add(const Duration(days: 2)),
        priority: TodoPriority.urgent,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('todos', jsonEncode([next.toJson()]));
      await todos.loadFromStorage();
      await tester.pumpAndSettle();
      final persisted = prefs.getString('todos');
      await callback(old);
      await tester.pumpAndSettle();

      expect(todos.todos.single.toJson(), next.toJson());
      expect(prefs.getString('todos'), persisted);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retained Today row button rejects rebinding to a same-ID new account',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final todos = TodoProvider();
      final old = TodoItem(
        id: 'retained-row-collision',
        title: '原账号建议按钮',
        date: DateTime.now().add(const Duration(days: 2)),
        priority: TodoPriority.urgent,
      );
      await todos.addTodo(old);
      await tester.pumpWidget(_wrap(const TodayScreen(), todoProvider: todos));
      await tester.pumpAndSettle();
      final reminderToggle = find.byKey(
        const ValueKey('today_reminder_header_toggle'),
      );
      await tester.scrollUntilVisible(
        reminderToggle,
        360,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(reminderToggle);
      await tester.pumpAndSettle();
      final header = find.text(I18n.tr('today.suggestions'));
      await tester.scrollUntilVisible(
        header,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(header);
      await tester.pumpAndSettle();
      final button = find.byKey(ValueKey('today_suggestion_add_${old.id}'));
      final retainedCallback = tester.widget<TextButton>(button).onPressed!;

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      todos.resetLocalState();
      final next = TodoItem(
        id: old.id,
        title: '新账号建议按钮',
        date: DateTime.now().add(const Duration(days: 3)),
        priority: TodoPriority.urgent,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('todos', jsonEncode([next.toJson()]));
      await todos.loadFromStorage();
      await tester.pumpAndSettle();
      final persisted = prefs.getString('todos');
      retainedCallback();
      await tester.pumpAndSettle();
      expect(todos.todos.single.toJson(), next.toJson());
      expect(prefs.getString('todos'), persisted);
      expect(find.byType(SnackBar), findsNothing);

      // The freshly built B row remains usable after rejecting A's callback.
      final currentCallback = tester.widget<TextButton>(button).onPressed;
      expect(currentCallback, isNotNull);
      currentCallback!();
      await tester.pumpAndSettle();
      final today = DateTime.now();
      expect(todos.todos.single.title, next.title);
      expect(
        todos.todos.single.date,
        DateTime(today.year, today.month, today.day),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Today expanded reminders and scroll survive locale switching', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final todos = TodoProvider();
    final now = DateTime.now();
    await todos.addTodo(
      TodoItem(
        title: '用户填写的逾期事项',
        date: now.subtract(const Duration(days: 1)),
        dueDate: now.subtract(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(_wrap(const TodayScreen(), todoProvider: todos));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('today_reminder_header_toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('用户填写的逾期事项'), findsWidgets);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final offset = scroll.position.pixels;
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text('用户填写的逾期事项'), findsWidgets);
    expect(scroll.position.pixels, closeTo(offset, 0.1));
    expect(find.text('已逾期事项'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('priority theme paired page screenshots', (tester) async {
    final directory =
        Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
    if (directory == null || directory.isEmpty) return;
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
          for (final width in [320.0, 1024.0]) {
            final scale = width == 320 ? 1.6 : 1.0;
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            for (final page in ['today', 'mine']) {
              final key = GlobalKey();
              await tester.pumpWidget(
                _wrap(
                  RepaintBoundary(
                    key: key,
                    child: BrandBackground(
                      child: page == 'today'
                          ? const TodayScreen()
                          : const MineScreen(),
                    ),
                  ),
                  themeProvider: provider,
                  theme: theme,
                  textScale: scale,
                ),
              );
              await _pumpTodayLayoutFrame(tester);
              expect(
                tester.takeException(),
                isNull,
                reason: '${brand.id}/$page/${locale.name}/$width',
              );
              await tester.runAsync(() async {
                final boundary =
                    key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                image.dispose();
                final file = File(
                  '$directory/${brand.id}-$page-${locale.name}-${width.toInt()}-scale-$scale.png',
                );
                file.parent.createSync(recursive: true);
                file.writeAsBytesSync(bytes!.buffer.asUint8List());
              });
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
            }
          }
          provider.dispose();
        }
      }
    } finally {
      debugDisableShadows = previousDisableShadows;
    }
  });

  testWidgets('Today keeps todo section visible when there is no task', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const TodayScreen()));
    await tester.pumpAndSettle();

    expect(find.text('今日待办'), findsOneWidget);
    expect(find.text('今天暂无待办，点击查看或添加任务'), findsOneWidget);
  });

  testWidgets('English Today fits narrow and wide views with large text', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await tester.runAsync(loadWidgetPolishScreenshotFonts);
    I18n.setLocale(AppLocale.en);
    final theme = AppBrands.defaultBrand.theme;
    final screenshotTheme = theme.copyWith(
      textTheme: theme.textTheme.apply(
        fontFamily: 'DuoyiScreenshotLatin',
        fontFamilyFallback: const ['DuoyiScreenshot'],
      ),
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: 'DuoyiScreenshotLatin',
          fontFamilyFallback: const ['DuoyiScreenshot'],
        ),
      ),
    );
    for (final width in <double>[320, 390, 1120, 1440]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      final todos = TodoProvider();
      await todos.addTodo(
        TodoItem(
          title: 'User title 用户内容 should remain unchanged',
          date: DateTime.now(),
        ),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          RepaintBoundary(
            key: key,
            child: const ColoredBox(
              color: DesignTokens.defaultPageBackground,
              child: TodayScreen(),
            ),
          ),
          todoProvider: todos,
          theme: screenshotTheme,
          textScale: 1.6,
        ),
      );
      await _pumpTodayLayoutFrame(tester);
      expect(find.text(I18n.tr('today.todos')), findsOneWidget);
      expect(
        find.text('User title 用户内容 should remain unchanged'),
        findsWidgets,
      );
      expect(find.text('今日待办'), findsNothing);
      expect(
        tester.takeException(),
        isNull,
        reason: 'English width=$width scale=1.6',
      );
      if (Platform.environment['DUOYI_CAPTURE_TODAY_SCREENSHOTS'] == '1') {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final directory =
              Platform.environment['DUOYI_TODAY_SCREENSHOT_DIR'] ??
              'evidence/screenshots/home-locale-20261011';
          final file = File(
            '$directory/home-en-${width.toInt()}-scale-1.6.png',
          );
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Today todo shows no-due and not-overdue tasks', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todoProvider = TodoProvider();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));

    await todoProvider.addTodo(TodoItem(title: '无截止任务', date: tomorrow));
    await todoProvider.addTodo(
      TodoItem(title: '今天截止任务', date: yesterday, dueDate: today),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '昨天截止任务',
        date: today,
        dueDate: yesterday.add(const Duration(hours: 18)),
      ),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '明天截止任务',
        date: today,
        dueDate: tomorrow.add(const Duration(hours: 9)),
      ),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '已完成任务',
        date: today,
        dueDate: today.add(const Duration(hours: 10)),
        isCompleted: true,
        completedAt: now,
      ),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '昨日完成任务',
        date: yesterday,
        isCompleted: true,
        completedAt: yesterday,
      ),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '已归档任务',
        date: today,
        isCompleted: true,
        completedAt: now,
        isArchivedAfterRollover: true,
      ),
    );

    await tester.pumpWidget(
      _wrap(const TodayScreen(), todoProvider: todoProvider),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日待办'), findsOneWidget);
    expect(find.text('无截止任务'), findsOneWidget);
    expect(find.text('无截止日期'), findsOneWidget);
    expect(find.text('今天截止任务'), findsOneWidget);
    expect(find.text('昨天截止任务'), findsNothing);
    expect(find.text('明天截止任务'), findsOneWidget);
    expect(find.text('已完成任务'), findsOneWidget);
    expect(find.text('昨日完成任务'), findsNothing);
    expect(find.text('已归档任务'), findsNothing);
  });

  testWidgets(
    'Today homepage layout fits audited widths and scrolls as content',
    (tester) async {
      addTearDown(tester.view.reset);
      final widths = <double>[320, 390, 430, 1440];
      await tester.runAsync(loadWidgetPolishScreenshotFonts);
      final theme = AppBrands.defaultBrand.theme;
      final screenshotTheme = theme.copyWith(
        textTheme: theme.textTheme.apply(
          fontFamily: 'DuoyiScreenshotLatin',
          fontFamilyFallback: const ['DuoyiScreenshot'],
        ),
        appBarTheme: theme.appBarTheme.copyWith(
          titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
            fontFamily: 'DuoyiScreenshotLatin',
            fontFamilyFallback: const ['DuoyiScreenshot'],
          ),
        ),
      );

      for (final width in widths) {
        tester.view.physicalSize = Size(width, width >= 900 ? 900 : 820);
        tester.view.devicePixelRatio = 1.0;

        final todoProvider = TodoProvider();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        await todoProvider.addTodo(
          TodoItem(
            title: '今日待办长标题需要省略但不能遮挡完成按钮和右侧内容',
            date: today,
            dueDate: now.add(const Duration(hours: 4)),
            priority: TodoPriority.high,
            quadrant: EisenhowerQuadrant.notUrgentImportant,
            listGroupName: '工作',
          ),
        );
        await todoProvider.addTodo(
          TodoItem(title: '无截止布局任务', date: today.add(const Duration(days: 3))),
        );

        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          _wrap(
            RepaintBoundary(
              key: boundaryKey,
              child: const ColoredBox(
                color: DesignTokens.defaultPageBackground,
                child: TodayScreen(),
              ),
            ),
            todoProvider: todoProvider,
            theme: screenshotTheme,
          ),
        );
        await _pumpTodayLayoutFrame(tester);
        final almanac = find.textContaining(I18n.tr('today.almanac.title'));
        final cardInk = find
            .ancestor(of: almanac, matching: find.byType(Ink))
            .first;
        expect(
          (tester.widget<Ink>(cardInk).decoration! as BoxDecoration).boxShadow,
          isEmpty,
        );
        if (Platform.environment['DUOYI_CAPTURE_TODAY_SCREENSHOTS'] == '1') {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            final directory =
                Platform.environment['DUOYI_TODAY_SCREENSHOT_DIR'] ??
                'evidence/screenshots/home-calendar-20261012';
            final file = File('$directory/home-${width.toInt()}.png');
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(data!.buffer.asUint8List());
          });
        }

        final list = find.byKey(const ValueKey('today_screen_list'));
        final appBar = find.byType(AppBar);
        final isDesktopLayout = width >= 1100;
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(list, findsOneWidget);
        if (isDesktopLayout) {
          expect(appBar, findsNothing);
          expect(find.text('今日'), findsWidgets);
        } else {
          expect(appBar, findsOneWidget);
        }
        expect(find.text('今日待办'), findsOneWidget);
        expect(find.text('今日待办长标题需要省略但不能遮挡完成按钮和右侧内容'), findsWidgets);
        expect(find.text('无截止日期'), findsWidgets);
        expect(tester.takeException(), isNull);

        if (scrollable.position.maxScrollExtent > 0) {
          scrollable.position.jumpTo(0);
          await _pumpTodayLayoutFrame(tester);
          final appBarTop = isDesktopLayout
              ? null
              : tester.getTopLeft(appBar).dy;
          final beforePixels = scrollable.position.pixels;
          await tester.drag(list, const Offset(0, -280));
          await _pumpTodayLayoutFrame(tester);

          if (!isDesktopLayout) {
            expect(tester.getTopLeft(appBar).dy, closeTo(appBarTop!, 0.1));
          }
          expect(scrollable.position.pixels, greaterThan(beforePixels));
        }
        expect(tester.takeException(), isNull);
      }

      tester.view.reset();
    },
  );

  test('今日和我的概览/入口样式保持独立且不过度放大', () {
    final today = File('lib/screens/today_screen.dart').readAsStringSync();
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    final surface = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();

    expect(today, contains('constraints.maxWidth < (desktop ? 640 : 520)'));
    expect(today, contains('? (useTwoColumns ? 2.75 : 2.85)'));
    expect(today, contains(': (useTwoColumns ? 2.55 : 3.65)'));
    expect(mine, contains('class _MineStatsGrid extends StatelessWidget'));
    expect(mine, contains("ValueKey('mine_stats_stable_grid')"));
    expect(mine, contains('RepaintBoundary('));
    expect(mine, isNot(contains('GridView.count(')));
    expect(surface, contains('fontSize: 12'));
    expect(surface, contains('fontSize: 11'));
    expect(surface, contains('fontSize: DesignTokens.fontSizeMd'));
    expect(surface, contains('iconBoxSize = 28'));

    expect(mine, contains('class _TileGroup'));
    expect(mine, contains('AppSurfaceCard('));
    expect(mine, contains('Divider('));
    expect(
      mine,
      contains(
        'borderRadius: BorderRadius.circular(DesignTokens.radiusControl)',
      ),
    );
    expect(mine, contains('final compact = constraints.maxWidth < 360'));
    expect(mine, contains("label: I18n.tr('goal.title')"));
    expect(mine, contains("label: I18n.tr('anniversary.birthday')"));
    expect(mine, contains("label: I18n.tr('anniversary.title')"));
    expect(mine, contains('child: anniversary.MemorialAnniversaryScreen()'));
    expect(mine, contains('child: anniversary.BirthdayScreen()'));
    expect(mine, contains("label: I18n.tr('countdown.title')"));
    expect(mine, contains('child: CountdownScreen()'));
    expect(mine, contains("label: I18n.tr('mine.tile.backup')"));
    expect(mine, contains("label: I18n.tr('mine.tile.restore')"));
    expect(mine, contains("label: I18n.tr('mine.tile.feedback')"));
    expect(mine, contains('FeedbackScreen(initialCategory: category)'));
    expect(mine, contains("label: I18n.tr('mine.tile.integrations')"));
    expect(mine, isNot(contains('AlmanacEntryMode.almanac')));
    expect(mine, contains('AlmanacEntryMode.calendar'));
    expect(mine, contains('BackupEntryMode.backup'));
    expect(mine, contains('BackupEntryMode.restore'));
    expect(mine, isNot(contains("label: '纪念日 · 生日 · 倒数'")));
    expect(mine, isNot(contains("label: '黄历 · 万年历'")));
    expect(mine, isNot(contains("label: '备份 · 恢复'")));
    expect(mine, isNot(contains("label: '功能建议'")));
    expect(mine, isNot(contains("label: '问题反馈'")));
    expect(mine, isNot(contains("label: '许愿池'")));

    // Compare the group insertion, since its title is declared in a helper.
    final actionPlan = mine.indexOf("title: I18n.tr('mine.group.action_plan')");
    final recordReview = mine.indexOf('return capped(_MineRecordReviewGroup(');
    final schedule = mine.indexOf("title: I18n.tr('mine.group.schedule')");
    expect(actionPlan, greaterThanOrEqualTo(0));
    expect(recordReview, greaterThanOrEqualTo(0));
    expect(schedule, greaterThanOrEqualTo(0));
    expect(actionPlan, lessThan(recordReview));
    expect(recordReview, lessThan(schedule));
    expect(
      mine.indexOf("title: I18n.tr('mine.group.personal')"),
      lessThan(mine.indexOf("title: I18n.tr('mine.group.data')")),
    );
  });

  testWidgets('TodayScreen and MineScreen render on desktop width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const TodayScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('待办'), findsWidgets);
    expect(find.text('习惯'), findsWidgets);
    expect(find.text('专注'), findsWidgets);
    expect(find.text('日记'), findsWidgets);
    expect(find.text('今日代表'), findsNothing);

    await tester.pumpWidget(_wrap(const MineScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(MineScreen), findsOneWidget);
    expect(find.text('行动计划'), findsOneWidget);
    expect(find.text('记录回顾'), findsOneWidget);
    expect(find.text('日程日期'), findsOneWidget);
    expect(find.text('智能工具'), findsNothing);
    expect(find.text('个性安全'), findsOneWidget);
    expect(find.text('目标管理'), findsOneWidget);
    expect(find.text('效率评分'), findsOneWidget);
    expect(find.textContaining('时光币'), findsNothing);
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('修改登录密码'), findsNothing);
    expect(find.text('综合评分'), findsNothing);
    expect(find.text('纪念日'), findsOneWidget);
    expect(find.text('生日'), findsOneWidget);
    expect(find.text('倒数日'), findsOneWidget);
    expect(find.text('黄历'), findsNothing);
    expect(find.text('万年历'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('通知支持'),
      600,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('数据协作'), findsOneWidget);
    expect(find.text('通知支持'), findsOneWidget);
    expect(find.text('导出为日历 (.ics)'), findsOneWidget);
    expect(find.text('备份'), findsOneWidget);
    expect(find.text('恢复数据'), findsOneWidget);
    expect(find.text('许愿与反馈'), findsOneWidget);
    expect(find.text('纪念日 · 生日 · 倒数'), findsNothing);
    expect(find.text('黄历 · 万年历'), findsNothing);
    expect(find.text('备份 · 恢复'), findsNothing);
    expect(find.text('功能建议'), findsNothing);
    expect(find.text('问题反馈'), findsNothing);
    expect(find.text('许愿池'), findsNothing);
  });

  testWidgets('Mine keeps top bar fixed while content scrolls on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const MineScreen()));
    await tester.pumpAndSettle();

    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('我的'),
    );
    final header = find.byKey(const ValueKey('mine_header_stable_box'));
    final scrollableFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.restorationId == 'mine_screen_list',
    );

    expect(
      find.byKey(const ValueKey('mine_desktop_fixed_overview_layout')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mine_fixed_overview_panel')),
      findsNothing,
    );
    expect(find.byType(AppBar), findsOneWidget);
    expect(title, findsOneWidget);
    expect(scrollableFinder, findsOneWidget);

    final scrollable = tester.state<ScrollableState>(scrollableFinder);
    final targetOffset = scrollable.position.maxScrollExtent < 260
        ? scrollable.position.maxScrollExtent
        : 260.0;
    expect(targetOffset, greaterThan(0));

    final stats = find.text('待办完成');
    final aiAssistant = find.text('AI 助手');
    final beforeTitleTop = tester.getTopLeft(title).dy;
    final beforeHeaderTop = tester.getTopLeft(header).dy;
    final beforeStatsTop = tester.getTopLeft(stats).dy;
    final beforeAiAssistantTop = tester.getTopLeft(aiAssistant).dy;

    scrollable.position.jumpTo(targetOffset);
    await tester.pump();

    expect(scrollable.position.pixels, closeTo(targetOffset, 0.1));
    expect(tester.getTopLeft(title).dy, closeTo(beforeTitleTop, 0.1));
    expect(
      _topOrScrolledAway(tester, header),
      anyOf(isNull, lessThan(beforeHeaderTop)),
    );
    expect(
      _topOrScrolledAway(tester, stats),
      anyOf(isNull, lessThan(beforeStatsTop)),
    );
    expect(
      _topOrScrolledAway(tester, aiAssistant),
      anyOf(isNull, lessThan(beforeAiAssistantTop)),
    );
  });

  testWidgets('Mine avatar preview and profile info navigation are distinct', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const MineScreen()));
    await tester.pumpAndSettle();

    final avatarButton = find.byKey(
      const ValueKey('mine_avatar_preview_button'),
    );
    await tester.tapAt(tester.getTopLeft(avatarButton) + const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('头像'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(ProfileScreen), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final editRect = tester.getRect(
      find.byKey(const ValueKey('mine_avatar_edit_button')),
    );
    expect(editRect.width, greaterThan(43.5));
    expect(editRect.height, greaterThan(43.5));

    await tester.tap(find.text('用户').first);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('个人资料'), findsOneWidget);
  });

  testWidgets('Mine avatar rejects a picker result from the previous account', (
    tester,
  ) async {
    final selector = _HeldAvatarSelector();
    final previous = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    final auth = _AvatarAuth();
    final user = UserProvider();
    addTearDown(auth.dispose);
    addTearDown(user.dispose);
    await tester.pumpWidget(
      _wrap(const MineScreen(), authProvider: auth, userProvider: user),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mine_avatar_edit_button')));
    await tester.pump();
    expect(selector.calls, 1);
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    user.resetLocalState();
    final file = _HeldAvatarFile();
    selector.result.complete(file);
    await tester.pumpAndSettle();
    expect(file.reads, 0);
    expect(auth.uploads, 0);
    expect(user.profile.avatarUrl, isEmpty);
    expect(find.text(AccountUiCopy.feedbackAvatarSaved), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mine avatar rechecks account after held file read', (
    tester,
  ) async {
    final selector = _HeldAvatarSelector();
    final previous = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    final auth = _AvatarAuth();
    final user = UserProvider();
    addTearDown(auth.dispose);
    addTearDown(user.dispose);
    await tester.pumpWidget(
      _wrap(const MineScreen(), authProvider: auth, userProvider: user),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mine_avatar_edit_button')));
    final file = _HeldAvatarFile();
    selector.result.complete(file);
    await tester.pumpAndSettle();
    expect(file.reads, 1);
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    user.resetLocalState();
    file.bytes.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pumpAndSettle();
    expect(auth.uploads, 0);
    expect(user.profile.avatarUrl, isEmpty);
    expect(find.text(AccountUiCopy.feedbackAvatarSaved), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mine avatar completion preserves a newer covering route', (
    tester,
  ) async {
    final selector = _HeldAvatarSelector();
    final previous = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    final auth = _AvatarAuth()..holdUpload = true;
    addTearDown(auth.dispose);
    await tester.pumpWidget(_wrap(const MineScreen(), authProvider: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mine_avatar_edit_button')));
    selector.result.complete(
      XFile.fromData(Uint8List.fromList([1]), name: 'old.png'),
    );
    await tester.pumpAndSettle();
    expect(auth.uploads, 1);
    Navigator.of(tester.element(find.byType(MineScreen))).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('newer avatar route')),
      ),
    );
    await tester.pumpAndSettle();
    auth.uploadRelease.complete();
    await tester.pumpAndSettle();
    expect(find.text('newer avatar route'), findsOneWidget);
    expect(find.text(AccountUiCopy.feedbackAvatarSaved), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final nextUserId in ['next-account', 'mine-origin']) {
    testWidgets(
      'Mine held logout confirmation rejects replacement session: $nextUserId',
      (tester) async {
        final requests = <String>[];
        final auth = _mineSessionAuth(requests);
        addTearDown(auth.dispose);
        await tester.pumpWidget(_wrap(const MineScreen(), authProvider: auth));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mine_top_logout_button')));
        await tester.pumpAndSettle();
        expect(find.text(I18n.tr('mine.logout.confirm_title')), findsOneWidget);
        await _settleMineSessionOperation(tester, () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'auth_state',
            jsonEncode(
              AuthState(
                userId: nextUserId,
                username: 'replacement',
                token: 'replacement-session-token',
              ).toJson(),
            ),
          );
          await auth.loadFromStorage(refreshServerConfig: false);
        });
        await tester.pumpAndSettle();
        expect(auth.state.userId, nextUserId);
        expect(auth.state.token, 'replacement-session-token');
        await tester.tap(
          find.widgetWithText(FilledButton, I18n.tr('auth.logout')),
        );
        await tester.pumpAndSettle();
        expect(requests.where((path) => path == '/api/auth/logout'), isEmpty);
        expect(auth.state.userId, nextUserId);
        expect(auth.state.isLoggedIn, isTrue);
        expect(find.text(I18n.tr('mine.logout.done')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final confirm in [false, true]) {
    testWidgets(
      'covered Mine logout ${confirm ? 'confirmation' : 'cancel'} cannot pop a newer route',
      (tester) async {
        final requests = <String>[];
        final auth = _mineSessionAuth(requests);
        addTearDown(auth.dispose);
        await tester.pumpWidget(_wrap(const MineScreen(), authProvider: auth));
        await tester.pumpAndSettle();
        final navigator = Navigator.of(tester.element(find.byType(MineScreen)));
        addTearDown(() async {
          if (navigator.mounted) {
            navigator.popUntil((route) => route.isFirst);
            await tester.pumpAndSettle();
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
        await tester.tap(find.byKey(const ValueKey('mine_top_logout_button')));
        await tester.pumpAndSettle();
        final VoidCallback callback = confirm
            ? tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, I18n.tr('auth.logout')),
                  )
                  .onPressed!
            : tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, I18n.tr('action.cancel')),
                  )
                  .onPressed!;
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Newer Mine route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        callback();
        await tester.pumpAndSettle();
        expect(find.text('Newer Mine route'), findsOneWidget);
        expect(requests.where((path) => path == '/api/auth/logout'), isEmpty);
        expect(auth.state.isLoggedIn, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('covered Mine avatar callback cannot open the file picker', (
    tester,
  ) async {
    final selector = _HeldAvatarSelector();
    final previous = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    final auth = _AvatarAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(_wrap(const MineScreen(), authProvider: auth));
    await tester.pumpAndSettle();
    final callback = tester
        .widget<InkWell>(
          find.descendant(
            of: find.byKey(const ValueKey('mine_avatar_edit_button')),
            matching: find.byType(InkWell),
          ),
        )
        .onTap!;
    final navigator = Navigator.of(tester.element(find.byType(MineScreen)));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Newer avatar route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    callback();
    selector.result.complete(null);
    await tester.pumpAndSettle();
    expect(selector.calls, 0);
    expect(auth.uploads, 0);
    expect(find.text('Newer avatar route'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'retained Mine header logout and avatar callbacks reject a same-user token rotation',
    (tester) async {
      final selector = _HeldAvatarSelector();
      final previous = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = selector;
      addTearDown(() => FileSelectorPlatform.instance = previous);
      final requests = <String>[];
      final auth = _mineSessionAuth(requests);
      addTearDown(auth.dispose);
      await tester.pumpWidget(_wrap(const MineScreen(), authProvider: auth));
      await tester.pumpAndSettle();

      final logoutCallback = tester
          .widget<IconButton>(
            find.byKey(const ValueKey('mine_top_logout_button')),
          )
          .onPressed!;
      final avatarButton = find.byKey(
        const ValueKey('mine_avatar_edit_button'),
      );
      final avatarCallback = tester
          .widget<InkWell>(
            find.descendant(of: avatarButton, matching: find.byType(InkWell)),
          )
          .onTap!;
      final originalGeneration = auth.sessionGeneration;

      await _settleMineSessionOperation(tester, () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'auth_state',
          jsonEncode(
            const AuthState(
              userId: 'mine-origin',
              username: 'replacement-token',
              token: 'rotated-session-token',
            ).toJson(),
          ),
        );
        await auth.loadFromStorage(refreshServerConfig: false);
      });
      await tester.pumpAndSettle();
      expect(auth.state.userId, 'mine-origin');
      expect(auth.state.token, 'rotated-session-token');
      expect(auth.sessionGeneration, greaterThan(originalGeneration));

      logoutCallback();
      await tester.pumpAndSettle();
      avatarCallback();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(selector.calls, 0);
      expect(auth.uploads, 0);
      expect(requests.where((path) => path == '/api/auth/logout'), isEmpty);

      final freshAvatarCallback = tester
          .widget<InkWell>(
            find.descendant(of: avatarButton, matching: find.byType(InkWell)),
          )
          .onTap!;
      freshAvatarCallback();
      await tester.pump();
      expect(selector.calls, 1);
      selector.result.complete(null);
      await tester.pumpAndSettle();
      expect(auth.state.isLoggedIn, isTrue);
      expect(requests.where((path) => path == '/api/auth/logout'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'covered avatar preview edit callback cannot pop the new route or open the picker',
    (tester) async {
      final selector = _HeldAvatarSelector();
      final previous = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = selector;
      addTearDown(() => FileSelectorPlatform.instance = previous);
      final auth = _AvatarAuth();
      addTearDown(auth.dispose);
      await tester.pumpWidget(_wrap(const MineScreen(), authProvider: auth));
      await tester.pumpAndSettle();
      final navigator = Navigator.of(tester.element(find.byType(MineScreen)));

      final preview = find.byKey(const ValueKey('mine_avatar_preview_button'));
      await tester.tapAt(tester.getTopLeft(preview) + const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      final editButton = find.ancestor(
        of: find.byTooltip(I18n.tr('mine.avatar.edit')),
        matching: find.byType(IconButton),
      );
      expect(editButton, findsOneWidget);
      final callback = tester.widget<IconButton>(editButton).onPressed!;
      addTearDown(() async {
        if (navigator.mounted) {
          navigator.popUntil((route) => route.isFirst);
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });

      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Newer preview route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      callback();
      selector.result.complete(null);
      await tester.pumpAndSettle();
      expect(selector.calls, 0);
      expect(auth.uploads, 0);
      expect(find.text('Newer preview route'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Mine held avatar picker error is silent after session expiry', (
    tester,
  ) async {
    final selector = _HeldAvatarSelector();
    final previous = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    final auth = _mineSessionAuth([]);
    addTearDown(auth.dispose);
    await tester.pumpWidget(_wrap(const MineScreen(), authProvider: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mine_avatar_edit_button')));
    await tester.pump();
    expect(selector.calls, 1);
    await _settleMineSessionOperation(
      tester,
      () => auth.refreshMe(force: true),
    );
    await tester.pumpAndSettle();
    expect(auth.state.isLoggedIn, isFalse);
    selector.result.completeError(StateError('synthetic old picker failure'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(I18n.tr('profile.avatar.save_failed_prefix')),
      findsNothing,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Mine old avatar preview cannot start guest edit after expiry', (
    tester,
  ) async {
    final selector = _HeldAvatarSelector();
    final previous = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    final auth = _mineSessionAuth([]);
    addTearDown(auth.dispose);
    await tester.pumpWidget(_wrap(const MineScreen(), authProvider: auth));
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('mine_avatar_preview_button'));
    await tester.tapAt(tester.getTopLeft(preview) + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await _settleMineSessionOperation(
      tester,
      () => auth.refreshMe(force: true),
    );
    await tester.pumpAndSettle();
    expect(auth.state.isLoggedIn, isFalse);
    await tester.tap(find.byTooltip(I18n.tr('mine.avatar.edit')));
    await tester.pumpAndSettle();
    final calls = selector.calls;
    if (calls > 0) {
      selector.result.complete(null);
      await tester.pumpAndSettle();
    }
    expect(calls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('MineScreen exposes logout in the top user info row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final requests = <String>[];
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'u-1',
        username: 'old-user',
        displayName: '旧昵称',
        token: 'token-1',
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'POST' &&
              request.url.path == '/api/auth/logout') {
            return http.Response(
              json.encode({'status': 'ok'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );

    await tester.pumpWidget(_wrap(const MineScreen(), authProvider: auth));
    await tester.pumpAndSettle();

    final userInfoRow = find.byKey(const ValueKey('mine_user_info_row'));
    final logoutButton = find.descendant(
      of: userInfoRow,
      matching: find.byKey(const ValueKey('mine_top_logout_button')),
    );
    expect(userInfoRow, findsOneWidget);
    expect(logoutButton, findsOneWidget);

    await tester.tap(logoutButton);
    await tester.pumpAndSettle();

    expect(find.text('退出登录？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pumpAndSettle();

    expect(requests, ['POST /api/auth/logout']);
    expect(auth.state.isLoggedIn, isFalse);
    expect(find.textContaining('已退出登录'), findsOneWidget);
    expect(find.textContaining('本机账号数据已清理'), findsOneWidget);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    expect(find.text(I18n.tr('mine.logout.done')), findsOneWidget);
    expect(find.textContaining('已退出登录'), findsNothing);
  });

  testWidgets('Today todo left swipe exposes detail and delete actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todoProvider = TodoProvider();
    final today = DateTime.now();
    await todoProvider.addTodo(
      TodoItem(
        title: '今日左滑删除',
        date: DateTime(today.year, today.month, today.day),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => PomodoroProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => DiaryProvider()),
          ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
          ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
          ChangeNotifierProvider(create: (_) => CourseProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日左滑删除'), findsOneWidget);
    await tester.ensureVisible(find.text('今日左滑删除'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('today_todo_swipe_detail_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('today_todo_swipe_delete_button')),
      findsNothing,
    );

    await tester.drag(find.text('今日左滑删除'), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('today_todo_swipe_detail_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('today_todo_swipe_delete_button')),
      findsNothing,
    );

    await tester.drag(find.text('今日左滑删除'), const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('today_todo_swipe_detail_button')),
      findsNothing,
    );
    expect(
      find
          .byKey(const ValueKey('today_todo_swipe_delete_button'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(todoProvider.todos, hasLength(1));

    await tester.tap(
      find
          .byKey(const ValueKey('today_todo_swipe_delete_button'))
          .hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(find.text('删除任务？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(todoProvider.todos, isEmpty);
    expect(find.text('今日左滑删除'), findsNothing);
  });

  testWidgets('Today reminders visually separate overdue and normal items', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todoProvider = TodoProvider();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await todoProvider.addTodo(
      TodoItem(
        title: '逾期提醒任务',
        date: today.subtract(const Duration(days: 1)),
        dueDate: now.subtract(const Duration(hours: 1)),
      ),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '正常提醒任务',
        date: today.add(const Duration(days: 1)),
        dueDate: now.add(const Duration(minutes: 45)),
      ),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '已完成提醒任务',
        date: today,
        dueDate: now.add(const Duration(minutes: 30)),
        isCompleted: true,
        completedAt: now,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => PomodoroProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => DiaryProvider()),
          ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
          ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
          ChangeNotifierProvider(create: (_) => CourseProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日提醒'), findsOneWidget);
    expect(find.text('已逾期事项'), findsNothing);
    expect(find.text('逾期提醒任务'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('today_reminder_header_toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('已逾期事项'), findsOneWidget);
    expect(
      find.text('今日待提醒事项').evaluate().isNotEmpty ||
          find.text('即将开始事项').evaluate().isNotEmpty,
      isTrue,
    );
    expect(find.text('逾期提醒任务'), findsOneWidget);
    expect(find.text('正常提醒任务'), findsWidgets);
    expect(find.text('已完成提醒任务'), findsWidgets);
    expect(find.text('逾期'), findsWidgets);

    final overdueTitle = tester.widget<Text>(find.text('逾期提醒任务'));
    final normalTitle = tester.widgetList<Text>(find.text('正常提醒任务')).last;
    final completedTitle = tester
        .widgetList<Text>(find.text('已完成提醒任务'))
        .firstWhere(
          (widget) => widget.style?.decoration == TextDecoration.lineThrough,
        );
    expect(overdueTitle.style?.color, isNot(equals(normalTitle.style?.color)));
    expect(completedTitle.style?.decoration, TextDecoration.lineThrough);
    expect(
      completedTitle.style?.color,
      isNot(equals(normalTitle.style?.color)),
    );

    bool reminderTileDecoration(Widget widget) {
      if (widget is! Container) return false;
      return widget.margin ==
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3) &&
          widget.decoration is BoxDecoration;
    }

    final overdueDecoratedTile = find.ancestor(
      of: find.text('逾期提醒任务'),
      matching: find.byWidgetPredicate(reminderTileDecoration),
    );
    final normalDecoratedTile = find.ancestor(
      of: find.text('正常提醒任务'),
      matching: find.byWidgetPredicate(reminderTileDecoration),
    );
    expect(overdueDecoratedTile, findsOneWidget);
    expect(normalDecoratedTile, findsWidgets);
  });

  testWidgets('Future not-overdue todo appears directly in today', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todoProvider = TodoProvider();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await todoProvider.addTodo(
      TodoItem(
        title: '明天未逾期待办',
        date: today.add(const Duration(days: 1)),
        dueDate: today.add(const Duration(days: 1, hours: 18)),
        priority: TodoPriority.high,
        quadrant: EisenhowerQuadrant.notUrgentImportant,
        listGroupName: '工作',
      ),
    );

    await tester.pumpWidget(
      _wrap(const TodayScreen(), todoProvider: todoProvider),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日待办'), findsOneWidget);
    expect(find.text('明天未逾期待办'), findsOneWidget);

    final stored = todoProvider.todos.single;
    expect(
      DateTime(stored.date.year, stored.date.month, stored.date.day),
      today.add(const Duration(days: 1)),
    );
    expect(stored.dueDate, isNotNull);
    expect(
      DateTime(
        stored.dueDate!.year,
        stored.dueDate!.month,
        stored.dueDate!.day,
      ),
      today.add(const Duration(days: 1)),
    );
    expect(find.text('今日待办'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('today_todo_template_icon_工作')),
      findsWidgets,
    );
    expect(find.text(I18n.tr('today.add_to_today')), findsNothing);
  });

  testWidgets(
    'More applications opens as a real route and hidden apps render',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const MineScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('更多应用'));
      await tester.pumpAndSettle();

      expect(find.byType(MoreApplicationsScreen), findsOneWidget);
      expect(find.text('隐藏入口'), findsOneWidget);
      expect(find.text('日历'), findsOneWidget);
      expect(find.text('番茄专注'), findsNothing);

      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarScreen), findsOneWidget);
      expect(find.text('日历'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Today suggestions keep add button inside narrow tiles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todoProvider = TodoProvider();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final later = today.add(const Duration(days: 2));
    await todoProvider.addTodo(
      TodoItem(
        title: '非常非常长的今日建议任务标题需要省略但按钮不能遮挡',
        date: later,
        priority: TodoPriority.urgent,
        quadrant: EisenhowerQuadrant.urgentImportant,
      ),
    );

    await tester.pumpWidget(
      _wrap(const TodayScreen(), todoProvider: todoProvider),
    );
    await tester.pumpAndSettle();

    final reminderToggle = find.byKey(
      const ValueKey('today_reminder_header_toggle'),
    );
    await tester.scrollUntilVisible(
      reminderToggle,
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(reminderToggle, findsOneWidget);

    await tester.tap(reminderToggle);
    await tester.pumpAndSettle();
    final suggestionsHeader = find.text(I18n.tr('today.suggestions'));
    await tester.scrollUntilVisible(
      suggestionsHeader,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(suggestionsHeader);
    await tester.pumpAndSettle();

    final addButton = find.byKey(
      ValueKey('today_suggestion_add_${todoProvider.todos.single.id}'),
    );
    expect(addButton, findsOneWidget);
    expect(tester.getRect(addButton).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AnniversaryScreen can open a specific tab directly', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AnniversaryScreen(initialTab: 1)));
    await tester.pumpAndSettle();

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller?.index, 1);
    expect(find.text('生日'), findsWidgets);
    expect(find.text('纪念日 · 生日 · 倒数'), findsNothing);
  });

  testWidgets('Birthday and countdown entries use independent pages', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const BirthdayScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(BirthdayScreen), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('生日'), findsWidgets);

    await tester.pumpWidget(_wrap(const CountdownScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(CountdownScreen), findsOneWidget);
    expect(find.text('倒数日'), findsWidgets);
    expect(find.byType(AnniversaryScreen), findsNothing);
  });

  testWidgets('CountdownScreen can add countdowns from the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const CountdownScreen()));
    await tester.pumpAndSettle();

    expect(find.text('暂无倒数日记录'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);
    final provider = Provider.of<CountdownProvider>(
      tester.element(find.byType(CountdownScreen)),
      listen: false,
    );
    expect(provider.items, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Mine notification records open as a scalable page separate from preferences',
    (tester) async {
      final now = DateTime(2026, 5, 22, 8, 30);
      final storedHistory = List.generate(55, (i) {
        return jsonEncode({
          'id': 'history-$i',
          'title': '通知标题 $i',
          'body': i == 54 ? '最后一页记录' : '通知内容 $i',
          'scheduledTime': now.subtract(Duration(minutes: i)).toIso8601String(),
          'type': i.isEven
              ? NotificationType.todo.index
              : NotificationType.general.index,
          'relatedId': 'related-$i',
        });
      });
      SharedPreferences.setMockInitialValues({
        'duoyi_notif_history': storedHistory,
      });

      final notificationService = NotificationService();
      await notificationService.loadHistoryForTest();

      await tester.pumpWidget(
        MultiProvider(
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
            ChangeNotifierProvider<NotificationService>.value(
              value: notificationService,
            ),
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
          child: const MaterialApp(home: MineScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('通知支持'),
        700,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('通知记录'), findsOneWidget);
      expect(find.text('通知设置'), findsOneWidget);
      expect(find.text('55 条'), findsWidgets);

      await tester.ensureVisible(find.text('通知记录'));
      final historyLabelCenter = tester.getCenter(find.text('通知记录').first);
      await tester.tapAt(historyLabelCenter + const Offset(0, 28));
      await tester.pumpAndSettle();

      expect(find.text('通知记录'), findsWidgets);
      expect(find.byTooltip('上一页'), findsOneWidget);
      expect(find.byTooltip('下一页'), findsOneWidget);
      expect(find.textContaining('第 1 / 2 页'), findsOneWidget);
      expect(find.textContaining('每页 50 条'), findsOneWidget);
      expect(find.text('通知标题 0'), findsOneWidget);
      expect(find.text('最后一页记录'), findsNothing);

      await tester.scrollUntilVisible(
        find.byTooltip('下一页'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('通知标题 54'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('通知标题 54'), findsOneWidget);
      expect(find.text('最后一页记录'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'related-54');
      await tester.pumpAndSettle();
      expect(find.text('通知标题 54'), findsOneWidget);
      expect(find.textContaining('已筛出 1 / 55 条'), findsOneWidget);
    },
  );

  testWidgets('ProfileScreen edits and persists local profile fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final userProvider = UserProvider();
    await userProvider.updateProfile(
      username: '旧昵称',
      displayName: '旧显示名',
      email: 'old@example.com',
      avatarUrl: 'https://example.com/old.png',
      bio: '旧简介',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('登录账号'), findsOneWidget);
    expect(find.text('旧显示名'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, '显示名'), '新显示名');
    await tester.enterText(find.widgetWithText(TextField, '本地昵称'), '新昵称');
    expect(find.text('邮箱（仅本地展示，不用于登录或找回）'), findsOneWidget);
    final localEmail = find.byKey(const ValueKey('profile_local_email_field'));
    expect(localEmail, findsOneWidget);
    expect(
      tester.widget<TextField>(localEmail).controller!.text,
      'old@example.com',
    );
    await tester.ensureVisible(localEmail);
    await tester.enterText(localEmail, 'new@example.com');
    await tester.enterText(find.widgetWithText(TextField, '简介'), '新的个人简介');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(userProvider.profile.username, '旧昵称');
    expect(userProvider.profile.displayName, '新显示名');
    expect(userProvider.profile.avatarInitials, '新');
    expect(userProvider.profile.avatarUrl, 'https://example.com/old.png');
    expect(userProvider.profile.email, 'new@example.com');
    expect(userProvider.profile.bio, '新的个人简介');
    expect(find.text('本地资料已更新'), findsWidgets);
  });

  testWidgets('ProfileScreen edits account profile through auth API', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final requests = <String>[];
    final requestBodies = <Map<String, dynamic>>[];
    var serverEmail = 'old@example.com';
    var serverDisplayName = '旧昵称';
    var serverBio = '旧简介';
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'u-1',
        username: 'old-user',
        email: 'old@example.com',
        emailVerified: true,
        displayName: '旧昵称',
        avatar: 'https://example.com/old.png',
        bio: '旧简介',
        token: 'token-1',
        coinBalance: 88,
        lifetimeCoins: 144,
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'POST' &&
              request.url.path == '/api/me/profile') {
            expect(request.headers['authorization'], 'Bearer token-1');
            final body = json.decode(request.body) as Map<String, dynamic>;
            requestBodies.add(body);
            if (body.containsKey('display_name')) {
              serverDisplayName = body['display_name'] as String;
            }
            if (body.containsKey('bio')) {
              serverBio = body['bio'] as String;
            }
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'old-user',
                'email': serverEmail,
                'email_verified': false,
                'display_name': serverDisplayName,
                'avatar': 'https://example.com/old.png',
                'bio': serverBio,
                'is_admin': false,
                'coin_balance': 88,
                'lifetime_coins': 144,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'POST' && request.url.path == '/api/me/email') {
            expect(request.headers['authorization'], 'Bearer token-1');
            final body = json.decode(request.body) as Map<String, dynamic>;
            requestBodies.add(body);
            serverEmail = body['email'] as String;
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'old-user',
                'email': serverEmail,
                'email_verified': true,
                'display_name': serverDisplayName,
                'avatar': 'https://example.com/old.png',
                'bio': serverBio,
                'is_admin': false,
                'coin_balance': 88,
                'lifetime_coins': 144,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );
    final userProvider = UserProvider();
    await userProvider.updateProfile(username: '旧本地昵称');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('修改登录密码'), findsOneWidget);
    expect(find.text('old@example.com'), findsOneWidget);
    expect(find.text('已验证'), findsWidgets);
    expect(find.textContaining('时光币 88'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '昵称'), '新昵称');
    final usernameField = tester.widget<TextField>(
      find.widgetWithText(TextField, '用户名'),
    );
    expect(usernameField.readOnly, isTrue);
    await tester.enterText(find.widgetWithText(TextField, '简介'), '新的账号简介');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '邮箱'), findsNothing);
    expect(find.widgetWithText(TextField, '邮箱验证码'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '邮箱绑定'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '邮箱'),
      'new@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, '邮箱验证码'), '123456');
    await tester.tap(find.widgetWithText(FilledButton, '邮箱绑定'));
    await tester.pumpAndSettle();

    expect(requests, contains('POST /api/me/profile'));
    expect(requests, contains('POST /api/me/email'));
    expect(requestBodies, [
      {'display_name': '新昵称', 'displayName': '新昵称', 'bio': '新的账号简介'},
      {
        'email': 'new@example.com',
        'code': '123456',
        'email_code': '123456',
        'emailCode': '123456',
      },
    ]);
    expect(auth.state.username, 'old-user');
    expect(auth.state.email, 'new@example.com');
    expect(auth.state.emailVerified, isTrue);
    expect(auth.state.displayName, '新昵称');
    expect(auth.state.avatar, 'https://example.com/old.png');
    expect(auth.state.bio, '新的账号简介');
    expect(auth.state.coinBalance, 88);
    expect(auth.state.lifetimeCoins, 144);
    expect(userProvider.profile.username, 'old-user');
    expect(userProvider.profile.displayName, '新昵称');
    expect(userProvider.profile.email, 'new@example.com');
    expect(userProvider.profile.emailVerified, isTrue);
    expect(userProvider.profile.avatarUrl, 'https://example.com/old.png');
    expect(userProvider.profile.bio, '新的账号简介');
    expect(find.text('资料已更新'), findsWidgets);
  });
}

InkWell _mineUpdateInkWell(WidgetTester tester) => tester.widget<InkWell>(
  find
      .ancestor(
        of: find.text(I18n.tr('mine.tile.check_updates')),
        matching: find.byType(InkWell),
      )
      .first,
);

Future<VoidCallback> _mineUpdateCallback(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text(I18n.tr('mine.tile.check_updates')),
    600,
    scrollable: find.byType(Scrollable).last,
  );
  return _mineUpdateInkWell(tester).onTap!;
}

class _HeldMineUpdater extends AppUpdateService {
  _HeldMineUpdater() : super(repo: 'synthetic/duoyi', currentVersion: '1.0.0');

  Completer<void>? _pending;
  int calls = 0;
  bool forceUpdate = false;

  @override
  bool get checking => _pending != null;
  @override
  bool get mustUpdate => forceUpdate;

  @override
  Future<void> checkNow() async {
    calls++;
    final pending = Completer<void>();
    _pending = pending;
    notifyListeners();
    await pending.future;
  }

  void finish() {
    final pending = _pending!;
    _pending = null;
    notifyListeners();
    pending.complete();
  }
}

Future<void> _pumpTodayLayoutFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _captureMineOverview(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final directory = Platform.environment['DUOYI_ME_ENTRY_SCREENSHOT_DIR'];
  if (directory == null || directory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$directory/overview-$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

class _HeldAvatarSelector extends FileSelectorPlatform {
  final result = Completer<XFile?>();
  int calls = 0;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) {
    calls++;
    return result.future;
  }
}

Future<void> _settleMineSessionOperation(
  WidgetTester tester,
  Future<void> Function() operation,
) async {
  var finished = false;
  final pending = operation().whenComplete(() => finished = true);
  for (var frame = 0; frame < 100 && !finished; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finished, isTrue, reason: 'Synthetic auth lifecycle must settle');
  await pending;
}

_MineSessionAuth _mineSessionAuth(List<String> requests) {
  return _MineSessionAuth(requests);
}

class _MineSessionAuth extends AuthProvider {
  _MineSessionAuth(List<String> requests)
    : super(
        initialState: const AuthState(
          userId: 'mine-origin',
          username: 'origin',
          token: 'origin-session-token',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'origin-session-token',
          httpClient: MockClient((request) async {
            requests.add(request.url.path);
            if (request.url.path == '/api/auth/me' ||
                request.url.path == '/api/me') {
              return http.Response('{}', 401);
            }
            return http.Response('{}', 200);
          }),
        ),
      );

  int uploads = 0;

  @override
  Future<void> uploadAvatarBytes({
    required String filename,
    required Uint8List bytes,
    AuthSessionLease? sessionLease,
  }) async {
    uploads++;
    if (sessionLease != null) requireCurrentSessionLease(sessionLease);
  }
}

class _HeldAvatarFile extends XFile {
  _HeldAvatarFile() : super('/synthetic/held-avatar.png');
  final bytes = Completer<Uint8List>();
  int reads = 0;

  @override
  Future<Uint8List> readAsBytes() {
    reads++;
    return bytes.future;
  }
}

class _AvatarAuth extends AuthProvider {
  _AvatarAuth()
    : super(
        initialState: const AuthState(
          userId: 'avatar-origin',
          username: 'avatar-user',
          token: 'synthetic-avatar-token',
        ),
      );

  int uploads = 0;
  bool holdUpload = false;
  final uploadRelease = Completer<void>();

  @override
  Future<void> uploadAvatarBytes({
    required String filename,
    required Uint8List bytes,
    AuthSessionLease? sessionLease,
  }) async {
    uploads++;
    if (holdUpload) await uploadRelease.future;
    if (sessionLease != null) requireCurrentSessionLease(sessionLease);
  }
}
