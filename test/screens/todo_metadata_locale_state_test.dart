import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/models/goal.dart' show ReminderConfig;
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  late AppLocale previousLocale;

  setUp(() {
    previousLocale = I18n.current;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(previousLocale));

  testWidgets(
    'Todo metadata follows zh-en-zh while rows, authored titles, and provider revision stay put',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadWeeklyReviewScreenshotFonts);
      final screenshotDirectory =
          Platform.environment['DUOYI_TODO_SCREENSHOT_DIR'];
      final screenshotKey = GlobalKey();
      final textScale = ValueNotifier<double>(1.6);
      addTearDown(textScale.dispose);

      final now = DateTime.now();
      final todos = TodoProvider();
      await todos.addTodo(
        TodoItem(
          id: 'todo-meta-due-soon',
          title: '保留原始标题：准备项目评审',
          dueDate: now.add(const Duration(minutes: 45)),
          timeTargetSeconds: 25 * 60,
          reminder: const ReminderConfig(enabled: true, hour: 21, minute: 5),
          workspaceId: 'fixture-shared-space',
        ),
      );
      await todos.addTodo(
        TodoItem(
          id: 'todo-meta-overdue',
          title: '保留原始标题：整理会议记录',
          dueDate: now.subtract(const Duration(hours: 2)),
        ),
      );

      final habits = HabitProvider();
      final goals = GoalProvider();
      final share = ShareProvider();
      final theme = ThemeProvider();
      final ai = AiService();
      final auth = AuthProvider();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        todos.dispose();
        habits.dispose();
        goals.dispose();
        share.dispose();
        theme.dispose();
        ai.dispose();
        auth.dispose();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TodoProvider>.value(value: todos),
            ChangeNotifierProvider<HabitProvider>.value(value: habits),
            ChangeNotifierProvider<GoalProvider>.value(value: goals),
            ChangeNotifierProvider<ShareProvider>.value(value: share),
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
            ChangeNotifierProvider<AiService>.value(value: ai),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: MaterialApp(
            theme: AppBrands.defaultBrand.theme,
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: textScale,
              builder: (context, scale, _) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                  key: screenshotKey,
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: child!,
                  ),
                ),
              ),
            ),
            home: const TodoScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final screenState = tester.state(find.byType(TodoScreen));
      final listLabel = find.text(TodoBoardUiCopy.viewList);
      final viewSwitcher = find.ancestor(
        of: listLabel,
        matching: find.byWidgetPredicate((widget) => widget is SegmentedButton),
      );
      expect(viewSwitcher, findsOneWidget);
      await tester.tap(find.descendant(of: viewSwitcher, matching: listLabel));
      await tester.pumpAndSettle();
      // The shared fixture has no edit grant, so it uses the ordinary lazy list.
      final list = find.byKey(const ValueKey('todo_list_scroll'));
      expect(list, findsOneWidget);
      final listElement = tester.element(list);
      final revision = todos.revision;

      for (final scale in [1.6, 2.0]) {
        textScale.value = scale;
        await tester.pumpAndSettle();
        for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();

          expect(tester.state(find.byType(TodoScreen)), same(screenState));
          expect(tester.element(list), same(listElement));
          expect(todos.revision, revision);
          expect(
            todos.todos.map((todo) => todo.title),
            containsAll(['保留原始标题：准备项目评审', '保留原始标题：整理会议记录']),
          );

          await _revealRow(tester, list, find.text('保留原始标题：准备项目评审'));
          await tester.pumpAndSettle();
          final reminderTime = I18nDateFormat.timeOfDay(hour: 21, minute: 5);
          expect(reminderTime, locale == AppLocale.en ? '9:05 PM' : '21:05');
          for (final label in [
            TodoBoardUiCopy.badgeDueSoon,
            TodoBoardUiCopy.badgeTargetMinutes(25),
            TodoBoardUiCopy.badgeNextReminder(reminderTime),
            TodoBoardUiCopy.badgeShared,
          ]) {
            final text = find.descendant(
              of: find.byKey(const ValueKey('list-todo-todo-meta-due-soon')),
              matching: find.text(label),
            );
            expect(text, findsOneWidget, reason: 'locale $locale: $label');
            _expectTextWithinViewport(tester, text);
          }
          expect(tester.takeException(), isNull);
          if (scale == 1.6 && screenshotDirectory != null) {
            await _captureScreenshot(
              tester,
              screenshotKey,
              screenshotDirectory,
              'todo-metadata-${locale.name}-320-scale-1.6.png',
            );
          }

          await _revealRow(tester, list, find.text('保留原始标题：整理会议记录'));
          await tester.pumpAndSettle();
          final overdue = find.descendant(
            of: find.byKey(const ValueKey('list-todo-todo-meta-overdue')),
            matching: find.text(TodoBoardUiCopy.badgeOverdue),
          );
          expect(overdue, findsOneWidget);
          _expectTextWithinViewport(tester, overdue);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}

Future<void> _revealRow(WidgetTester tester, Finder list, Finder row) async {
  final scrollable = find.descendant(
    of: list,
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(row, 150, scrollable: scrollable);
}

Future<void> _captureScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String directory,
  String fileName,
) async {
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$directory/$fileName');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void _expectTextWithinViewport(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.didExceedMaxLines, isFalse);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(320));
}
