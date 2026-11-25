import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_detail_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../test_support/recording_reminder_scheduler.dart';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in const [
        (name: 'narrow', size: Size(320, 844), scale: 1.6, inset: 240.0),
        (name: 'landscape', size: Size(568, 320), scale: 2.0, inset: 100.0),
      ]) {
        final name = '$brand-${locale.name}-${layout.name}';
        testWidgets('paired widget Todo detail and discard layout $name', (
          tester,
        ) async {
          final original = TodoItem(
            id: 'todo/object',
            title: 'Literal task 用户任务',
            notes: 'Original description 原始说明',
            quadrant: EisenhowerQuadrant.notUrgentNotImportant,
            tags: ['Literal tag 原始标签'],
            dueDate: DateTime(2027, 1, 1),
            timeTargetSeconds: 1500,
            subtasks: [Subtask(id: 'child', title: 'Literal subtask 用户子任务')],
          );
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          final todos = TodoProvider()
            ..scheduler = RecordingReminderScheduler();
          final theme = ThemeProvider();
          final boundary = GlobalKey();
          final previousShadows = debugDisableShadows;
          try {
            I18n.setLocale(locale);
            debugDisableShadows = false;
            await todos.addTodo(original);
            await theme.loadFromStorage();
            final preferences = await SharedPreferences.getInstance();
            final stored = preferences.getString('todos');
            expect(theme.brand.id, brand);
            await tester.runAsync(
              () => loadWeeklyReviewScreenshotFonts(
                emojiFontPath:
                    'evidence/widget-detail-theme-20261020/fonts/NotoColorEmoji.ttf',
              ),
            );
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<TodoProvider>.value(value: todos),
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ],
                child: MaterialApp(
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed: () => TodayDetailRouter.open(
                            context,
                            TodaySectionKind.todos,
                            id: original.id,
                          ),
                          child: const Text('Open task'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open task'));
            await tester.pumpAndSettle();
            final route = find.byType(TodoDetailScreen);
            final state = tester.state(route);
            expect(find.byType(BrandRouteSurface), findsOneWidget);
            expect(find.text(TodoDetailUiCopy.screenTitle), findsOneWidget);
            expect(tester.takeException(), isNull);
            await _capture(tester, boundary, '$name-top');

            final quadrant = find.byType(AppDropdownField<EisenhowerQuadrant>);
            await tester.scrollUntilVisible(
              quadrant,
              120,
              scrollable: _detailScroll(),
            );
            await tester.pumpAndSettle();
            expect(quadrant.hitTestable(), findsOneWidget);
            await _capture(tester, boundary, '$name-controls');
            await tester.tap(quadrant);
            await tester.pumpAndSettle();
            await _capture(tester, boundary, '$name-quadrant-menu');
            final menuItems = find.byWidgetPredicate(
              (widget) => widget is PopupMenuItem<EisenhowerQuadrant>,
            );
            expect(menuItems, findsNWidgets(4));
            for (final label in [
              TodoDetailUiCopy.quadrantQ1,
              TodoDetailUiCopy.quadrantQ2,
              TodoDetailUiCopy.quadrantQ3,
              TodoDetailUiCopy.quadrantQ4,
            ]) {
              final option = find.descendant(
                of: menuItems,
                matching: find.text(label),
              );
              await tester.ensureVisible(option);
              await tester.pumpAndSettle();
              _expectCompleteOption(tester, option);
            }
            await _capture(tester, boundary, '$name-quadrant-last');
            Navigator.of(tester.element(menuItems.first)).pop();
            await tester.pumpAndSettle();
            expect(menuItems, findsNothing);
            expect(todos.todos.single.quadrant, original.quadrant);
            await tester.tap(quadrant);
            await tester.pumpAndSettle();
            final alternate = find.descendant(
              of: menuItems,
              matching: find.text(TodoDetailUiCopy.quadrantQ3),
            );
            await tester.ensureVisible(alternate);
            await tester.pumpAndSettle();
            await tester.tap(alternate);
            await tester.pumpAndSettle();
            expect(menuItems, findsNothing);
            expect(
              find.descendant(
                of: quadrant,
                matching: find.text(TodoDetailUiCopy.quadrantQ3),
              ),
              findsOneWidget,
            );
            expect(todos.todos.single.quadrant, original.quadrant);

            final position = tester
                .state<ScrollableState>(_detailScroll())
                .position;
            for (var attempt = 0; attempt < 20; attempt++) {
              position.jumpTo(position.maxScrollExtent);
              await tester.pumpAndSettle();
              if (position.extentAfter < 1) break;
            }
            expect(position.extentAfter, lessThan(1));
            expect(
              find.text('Literal subtask 用户子任务').hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await _capture(tester, boundary, '$name-bottom');

            position.jumpTo(0);
            await tester.pumpAndSettle();
            await tester.enterText(_titleField(), 'Unsaved task 未保存任务');
            final controller = tester
                .widget<TextField>(_titleField())
                .controller!;
            controller.selection = const TextSelection(
              baseOffset: 2,
              extentOffset: 8,
            );
            final selection = controller.selection;
            FocusManager.instance.primaryFocus?.unfocus();
            for (final next in [
              locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
              locale,
            ]) {
              I18n.setLocale(next);
              await tester.pumpAndSettle();
              expect(tester.state(route), same(state));
              expect(
                tester.widget<TextField>(_titleField()).controller,
                same(controller),
              );
              expect(controller.text, 'Unsaved task 未保存任务');
              expect(controller.selection, selection);
              expect(find.text(TodoDetailUiCopy.screenTitle), findsOneWidget);
              if (next != locale) {
                await _capture(tester, boundary, '$name-switched');
              }
            }

            tester.view.viewInsets = FakeViewPadding(bottom: layout.inset);
            await tester.pumpAndSettle();
            final back = find.widgetWithIcon(IconButton, Icons.arrow_back);
            expect(back.hitTestable(), findsOneWidget);
            expect(
              tester.getRect(back).bottom,
              lessThanOrEqualTo(layout.size.height - layout.inset),
            );
            await tester.tap(back);
            await tester.pumpAndSettle();
            expect(find.byType(AppDialog), findsOneWidget);
            expect(
              find.text(TodoDetailUiCopy.discardDialogTitle),
              findsOneWidget,
            );
            final cancel = find.widgetWithText(
              TextButton,
              TodoDetailUiCopy.cancel,
            );
            expect(cancel.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            await _capture(tester, boundary, '$name-discard-inset');
            await tester.tap(cancel);
            await tester.pumpAndSettle();
            expect(find.byType(AppDialog), findsNothing);
            expect(controller.text, 'Unsaved task 未保存任务');
            expect(tester.state(route), same(state));

            tester.view.viewInsets = const FakeViewPadding();
            await tester.pumpAndSettle();
            await tester.tap(back);
            await tester.pumpAndSettle();
            I18n.setLocale(
              locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
            );
            await tester.pumpAndSettle();
            expect(
              find.text(TodoDetailUiCopy.discardDialogTitle),
              findsOneWidget,
            );
            await _capture(tester, boundary, '$name-discard-switched');
            await tester.tap(
              find.widgetWithText(TextButton, TodoDetailUiCopy.discardAction),
            );
            await tester.pumpAndSettle();
            expect(find.byType(TodoDetailScreen), findsNothing);
            expect(find.text('Open task'), findsOneWidget);
            expect(todos.todos.single.toJson(), original.toJson());
            expect(preferences.getString('todos'), stored);
            expect(jsonDecode(stored!), [original.toJson()]);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            todos.dispose();
            theme.dispose();
            tester.view.reset();
            debugDisableShadows = previousShadows;
            I18n.setLocale(AppLocale.zh);
          }
        });
      }
    }
  }
}

Finder _titleField() => find.descendant(
  of: find.byType(TodoDetailScreen),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.labelText == TodoDetailUiCopy.taskTitleLabel,
  ),
);

void _expectCompleteOption(WidgetTester tester, Finder option) {
  final richText = find.descendant(of: option, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(richText);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
    maxLines: paragraph.maxLines,
    ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null,
  )..layout(maxWidth: paragraph.size.width);
  expect(
    painter.didExceedMaxLines,
    isFalse,
    reason:
        'The opened menu must show the full choice: ${paragraph.text.toPlainText()}',
  );
  expect(painter.height, lessThanOrEqualTo(paragraph.size.height + 0.5));
  expect(
    paragraph.textScaler.scale(14),
    closeTo(MediaQuery.textScalerOf(tester.element(option)).scale(14), 0.01),
    reason: 'The menu keeps the requested text scale',
  );
  painter.dispose();
}

Finder _detailScroll() => find
    .descendant(
      of: find.byType(TodoDetailScreen),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    )
    .first;

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['DUOYI_CAPTURE_TODO_DETAIL_THEME'] != '1') return;
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    final run =
        Platform.environment['DUOYI_TODO_DETAIL_THEME_RUN'] ?? 'current';
    final file = File(
      'evidence/screenshots/widget-todo-detail-theme-20261020/$run/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
