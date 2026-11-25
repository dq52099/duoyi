import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/core/todo_kanban.dart';
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

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test(
    'default column translations preserve custom names and persisted data',
    () {
      expect(TodoBoardUiCopy.todayRemainingTasks(1), '今日还要完成 1 项');
      I18n.setLocale(AppLocale.en);
      expect(TodoBoardUiCopy.todayRemainingTasks(1), '1 task remaining today');
      expect(TodoBoardUiCopy.todayRemainingTasks(2), '2 tasks remaining today');
    },
  );

  test(
    'default column translation preserves renamed and unknown titles across locales',
    () {
      final defaults = TodoKanbanBoardConfig.defaults();
      final renamed = defaults.copyWith(
        columns: defaults.columns
            .map((column) => column.copyWith(title: '用户原文 ${column.id}'))
            .toList(),
      );
      for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        for (final column in renamed.columns) {
          expect(TodoBoardUiCopy.columnTitle(column), column.title);
        }
        final restored = TodoKanbanBoardConfig.decode(renamed.encode());
        expect(restored.encode(), renamed.encode());
      }
    },
  );

  testWidgets(
    'summary and all sync notices follow locale, with raw diagnostics and task content preserved',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final directory = Platform.environment['DUOYI_TODO_SCREENSHOT_DIR'];
      await tester.runAsync(loadWidgetPolishScreenshotFonts);
      final todos = TodoProvider();
      await todos.addTodo(
        TodoItem(title: '原文 Raw task', priority: TodoPriority.high),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TodoProvider>.value(value: todos),
            ChangeNotifierProvider(create: (_) => HabitProvider()),
            ChangeNotifierProvider(create: (_) => GoalProvider()),
            ChangeNotifierProvider(create: (_) => ShareProvider()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => AiService()),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
          ],
          child: MaterialApp(
            theme: widgetPolishScreenshotTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: child!,
                ),
              ),
            ),
            home: const TodoScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final revision = todos.revision;
      final state = tester.state(find.byType(TodoScreen));
      for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(TodoScreen)), same(state));
        expect(
          find.text(TodoBoardUiCopy.todayRemainingTasks(1)),
          findsOneWidget,
        );
        expect(
          find.text(TodoBoardUiCopy.todaySummaryBreakdown(0, 1, 0)),
          findsOneWidget,
        );
        expect(
          find.byTooltip(TodoBoardUiCopy.todaySummaryChipFilterTodayTooltip),
          findsOneWidget,
        );
        expect(todos.todos.single.title, '原文 Raw task');
        expect(todos.revision, revision);
        final switcher = find.byKey(const ValueKey('todo_view_switcher'));
        expect(switcher, findsOneWidget);
        for (final value in [
          TodoBoardUiCopy.viewMatrix,
          TodoBoardUiCopy.viewList,
          TodoBoardUiCopy.viewKanban,
        ]) {
          final text = find.descendant(
            of: switcher,
            matching: find.text(value),
          );
          expect(text, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(text);
          expect(paragraph.didExceedMaxLines, isFalse);
          final rect = tester.getRect(text);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
          expect(tester.widget<Text>(text).maxLines, 1);
        }
        expect(tester.takeException(), isNull);
        if (directory != null) {
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
              '$directory/summary-${locale.name}-320-scale-1.6.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
      }
      const raw = '原始服务诊断 E_FIXTURE';
      for (final level in TodoCloudSyncNoticeLevel.values) {
        todos.cloudSyncNotice = TodoCloudSyncNotice(message: raw, level: level);
        for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          final expected = switch (level) {
            TodoCloudSyncNoticeLevel.error => TodoBoardUiCopy.syncNoticeError(
              raw,
            ),
            TodoCloudSyncNoticeLevel.warning =>
              TodoBoardUiCopy.syncNoticeWarning(raw),
            TodoCloudSyncNoticeLevel.info => TodoBoardUiCopy.syncNoticeInfo(
              raw,
            ),
          };
          expect(find.text(expected), findsOneWidget);
          expect(todos.cloudSyncNotice!.message, raw);
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      todos.dispose();
    },
  );
}
