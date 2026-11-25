import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/today_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'theme_shop_state': jsonEncode({
        'activeBrand': 'defaultBrand',
        'unlockedBrandIds': <String>['defaultBrand', 'liquidGlass'],
      }),
      'theme_unlocked_brands': <String>['defaultBrand', 'liquidGlass'],
      'active_brand': 'defaultBrand',
    });
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  Future<void> pumpRouterHarness(
    WidgetTester tester, {
    TodoProvider? todos,
    ThemeProvider? theme,
    double textScale = 1,
  }) async {
    final effectiveTheme = theme ?? ThemeProvider();
    if (theme == null) {
      await effectiveTheme.loadFromStorage();
    }
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          if (theme == null)
            ChangeNotifierProvider(create: (_) => effectiveTheme)
          else
            ChangeNotifierProvider<ThemeProvider>.value(value: effectiveTheme),
          if (todos == null)
            ChangeNotifierProvider(create: (_) => TodoProvider())
          else
            ChangeNotifierProvider<TodoProvider>.value(value: todos),
          ChangeNotifierProvider(create: (_) => CourseProvider()),
          ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => NoteProvider()),
          ChangeNotifierProvider(create: (_) => DiaryProvider()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, activeTheme, _) => MaterialApp(
            theme: activeTheme.brand.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => ListView(
                  children: [
                    for (final entry in _missingDetailCases.entries)
                      TextButton(
                        key: ValueKey('open_${entry.key.name}'),
                        onPressed: () => TodayDetailRouter.open(
                          context,
                          entry.key,
                          id: 'missing-${entry.key.name}',
                        ),
                        child: Text(entry.key.name),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final entry in _missingDetailCases.entries) {
    testWidgets('${entry.key.name} missing id opens branded fallback', (
      tester,
    ) async {
      await pumpRouterHarness(tester);

      await tester.tap(find.byKey(ValueKey('open_${entry.key.name}')));
      await tester.pumpAndSettle();

      expect(find.byType(BrandRouteSurface), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '返回'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('fallback translates in place in both directions', (
    tester,
  ) async {
    await pumpRouterHarness(tester);
    await tester.tap(find.byKey(const ValueKey('open_todos')));
    await tester.pumpAndSettle();
    final fallback = tester.element(find.byType(Scaffold).last);
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text('This task is no longer available.'), findsOneWidget);
    expect(find.text('View list'), findsOneWidget);
    expect(tester.element(find.byType(Scaffold).last), same(fallback));
    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    expect(
      find.text(_missingDetailCases[TodaySectionKind.todos]!),
      findsOneWidget,
    );
    expect(tester.element(find.byType(Scaffold).last), same(fallback));
  });

  testWidgets('retry replaces failed route and Back returns to source once', (
    tester,
  ) async {
    final todos = _RecoverableTodos();
    addTearDown(todos.dispose);
    await pumpRouterHarness(tester, todos: todos);
    await tester.tap(find.byKey(const ValueKey('open_todos')));
    await tester.pumpAndSettle();
    expect(find.text(TodayUiCopy.detailOpenFailed), findsOneWidget);
    expect(find.textContaining('synthetic-private-error'), findsNothing);
    // A second failure also replaces the current recovery page.
    await tester.tap(find.text(I18n.tr('action.retry')));
    await tester.pumpAndSettle();
    expect(find.text(TodayUiCopy.detailOpenFailed), findsOneWidget);
    todos.failReads = false;
    await tester.tap(find.text(I18n.tr('action.retry')));
    await tester.pumpAndSettle();
    expect(
      find.text(_missingDetailCases[TodaySectionKind.todos]!),
      findsOneWidget,
    );
    await tester.tap(find.text(I18n.tr('action.back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open_todos')), findsOneWidget);
    expect(find.byType(BrandRouteSurface), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final invalidation in ['covered', 'account', 'storage generation']) {
    testWidgets('retained retry ignores $invalidation source', (tester) async {
      final todos = _RecoverableTodos();
      addTearDown(todos.dispose);
      await pumpRouterHarness(tester, todos: todos);
      await tester.tap(find.byKey(const ValueKey('open_todos')));
      await tester.pumpAndSettle();
      final retry = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, I18n.tr('action.retry')),
          )
          .onPressed!;
      final reads = todos.reads;
      if (invalidation == 'covered') {
        Navigator.of(tester.element(find.byType(Scaffold).last)).push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Cover')),
          ),
        );
        await tester.pumpAndSettle();
      } else if (invalidation == 'account') {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      } else {
        todos.resetLocalState();
      }
      retry();
      await tester.pumpAndSettle();
      expect(todos.reads, reads);
      if (invalidation == 'covered') {
        expect(find.text('Cover'), findsOneWidget);
      } else {
        expect(find.text(TodayUiCopy.detailSourceChanged), findsOneWidget);
        expect(find.text(I18n.tr('action.retry')), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('English recovery scrolls on short screen at enlarged type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    I18n.setLocale(AppLocale.en);
    await pumpRouterHarness(tester, textScale: 3.2);
    await tester.tap(find.byKey(const ValueKey('open_todos')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Back'));
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open_todos')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'missing object fallback replaces route with list screen and pops to source',
    (tester) async {
      await pumpRouterHarness(tester);
      await tester.tap(find.byKey(const ValueKey('open_todos')));
      await tester.pumpAndSettle();

      expect(find.byType(BrandRouteSurface), findsOneWidget);
      expect(
        find.text(_missingDetailCases[TodaySectionKind.todos]!),
        findsOneWidget,
      );

      final openList = find.widgetWithText(
        FilledButton,
        TodayUiCopy.detailOpenList,
      );
      expect(openList, findsOneWidget);
      await tester.tap(openList);
      await tester.pumpAndSettle();

      expect(find.byType(TodoScreen), findsOneWidget);
      expect(
        find.text(_missingDetailCases[TodaySectionKind.todos]!),
        findsNothing,
      );

      Navigator.of(tester.element(find.byType(TodoScreen))).pop();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('open_todos')), findsOneWidget);
      expect(find.byType(BrandRouteSurface), findsNothing);
      expect(find.byType(TodoScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mounted fallback preserves state across live defaultBrand and liquidGlass and zh/en switches',
    (tester) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      await theme.loadFromStorage();
      await pumpRouterHarness(tester, theme: theme);

      await tester.tap(find.byKey(const ValueKey('open_todos')));
      await tester.pumpAndSettle();

      final fallback = tester.element(find.byType(Scaffold).last);
      expect(theme.brand.id, AppBrands.defaultBrand.id);
      expect(find.text(TodayUiCopy.detailTitle('todos')), findsOneWidget);
      expect(
        find.text(_missingDetailCases[TodaySectionKind.todos]!),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, TodayUiCopy.detailOpenList),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, I18n.tr('action.back')),
        findsOneWidget,
      );

      // 1. Live theme switch to liquidGlass while mounted
      await tester.runAsync(() async {
        final switched = await theme.setBrand(AppBrands.liquidGlass.id);
        expect(switched, isTrue);
      });
      await tester.pumpAndSettle();

      expect(theme.brand.id, AppBrands.liquidGlass.id);
      expect(tester.element(find.byType(Scaffold).last), same(fallback));
      expect(find.text(TodayUiCopy.detailTitle('todos')), findsOneWidget);
      expect(
        find.text(_missingDetailCases[TodaySectionKind.todos]!),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, TodayUiCopy.detailOpenList),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, I18n.tr('action.back')),
        findsOneWidget,
      );

      // 2. Live locale switch to English
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();

      expect(tester.element(find.byType(Scaffold).last), same(fallback));
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('This task is no longer available.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'View list'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Back'), findsOneWidget);

      // 3. Live theme switch back to defaultBrand while in English
      await tester.runAsync(() async {
        final reverted = await theme.setBrand(AppBrands.defaultBrand.id);
        expect(reverted, isTrue);
      });
      await tester.pumpAndSettle();

      expect(theme.brand.id, AppBrands.defaultBrand.id);
      expect(tester.element(find.byType(Scaffold).last), same(fallback));
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('This task is no longer available.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'View list'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Back'), findsOneWidget);

      // 4. Verify functional pushReplacement works after transitions
      await tester.tap(find.widgetWithText(FilledButton, 'View list'));
      await tester.pumpAndSettle();

      expect(find.byType(TodoScreen), findsOneWidget);
      expect(find.text('This task is no longer available.'), findsNothing);

      Navigator.of(tester.element(find.byType(TodoScreen))).pop();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('open_todos')), findsOneWidget);
      expect(find.byType(BrandRouteSurface), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account source change invalidates missing fallback and prevents retrying old object',
    (tester) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      await theme.loadFromStorage();
      final todos = _RecoverableTodos()..failReads = false;
      addTearDown(todos.dispose);
      await pumpRouterHarness(tester, todos: todos, theme: theme);

      await tester.tap(find.byKey(const ValueKey('open_todos')));
      await tester.pumpAndSettle();

      final listButton = find.widgetWithText(
        FilledButton,
        TodayUiCopy.detailOpenList,
      );
      expect(listButton, findsOneWidget);
      final openListCallback =
          tester.widget<FilledButton>(listButton).onPressed!;
      final initialReads = todos.reads;

      // Invalidate account generation (simulate account switch / cache purge)
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpAndSettle();

      expect(find.text(TodayUiCopy.detailSourceChanged), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, TodayUiCopy.detailOpenList),
        findsNothing,
      );
      expect(
        find.widgetWithText(FilledButton, I18n.tr('action.back')),
        findsOneWidget,
      );

      // Invoking retained action must not retry or push to the new account
      openListCallback();
      await tester.pumpAndSettle();

      expect(todos.reads, initialReads);
      expect(find.byType(TodoScreen), findsNothing);
      expect(find.text(TodayUiCopy.detailSourceChanged), findsOneWidget);

      // In-place locale toggle after invalidation
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Your account or page content has changed. Go back and open it again.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Back'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'View list'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Back'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('open_todos')), findsOneWidget);
      expect(find.byType(BrandRouteSurface), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account source change on error fallback rejects retry to new account across theme and locale switches',
    (tester) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      await theme.loadFromStorage();
      final todos = _RecoverableTodos()..failReads = true;
      addTearDown(todos.dispose);
      await pumpRouterHarness(tester, todos: todos, theme: theme);

      await tester.tap(find.byKey(const ValueKey('open_todos')));
      await tester.pumpAndSettle();

      expect(find.text(TodayUiCopy.detailOpenFailed), findsOneWidget);
      final retryFinder = find.widgetWithText(
        FilledButton,
        I18n.tr('action.retry'),
      );
      expect(retryFinder, findsOneWidget);
      final retryCallback =
          tester.widget<FilledButton>(retryFinder).onPressed!;

      // Live switch theme and locale before account change
      await tester.runAsync(() async {
        final switched = await theme.setBrand(AppBrands.liquidGlass.id);
        expect(switched, isTrue);
      });
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();

      expect(
        find.text('Could not open this item. Try again or go back.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

      // Account source changes
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Your account or page content has changed. Go back and open it again.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Retry'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Back'), findsOneWidget);

      final readsBefore = todos.reads;
      retryCallback();
      await tester.pumpAndSettle();

      // Must not retry old object query into new account
      expect(todos.reads, readsBefore);
      expect(
        find.text(
          'Your account or page content has changed. Go back and open it again.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Back'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('open_todos')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _RecoverableTodos extends TodoProvider {
  bool failReads = true;
  int reads = 0;

  @override
  List<TodoItem> get todos {
    reads++;
    if (failReads) throw StateError('synthetic-private-error');
    return const [];
  }
}

const _missingDetailCases = <TodaySectionKind, String>{
  TodaySectionKind.todos: '这个待办不存在或已被删除',
  TodaySectionKind.courses: '这节课程不存在或已被删除',
  TodaySectionKind.anniversaries: '这个纪念日不存在或已被删除',
  TodaySectionKind.goals: '这个目标不存在或已被删除',
  TodaySectionKind.habits: '这个习惯不存在或已被删除',
  TodaySectionKind.notes: '这条随手记不存在或已被删除',
  TodaySectionKind.diary: '这篇日记不存在或已被删除',
};
