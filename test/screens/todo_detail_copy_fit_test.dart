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

enum _Copy { assignee, tag }

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in const [
        (name: 'ordinary', size: Size(390, 844), scaler: TextScaler.noScaling),
        (name: 'narrow', size: Size(320, 844), scaler: TextScaler.linear(1.6)),
        (
          name: 'landscape',
          size: Size(568, 320),
          scaler: TextScaler.linear(2.0),
        ),
        (
          name: 'nonlinear',
          size: Size(332, 844),
          scaler: _CopyNonlinearScaler(),
        ),
      ]) {
        for (final copy in _Copy.values) {
          final name = '$brand-${locale.name}-${layout.name}-${copy.name}';
          testWidgets('Todo readable explanation and tag entry $name', (
            tester,
          ) async {
            final todo = TodoItem(
              id: 'copy-fit/task',
              title: 'Literal task 用户任务',
              notes: 'Original description 原始说明',
              tags: ['Original 原始标签'],
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
              await todos.addTodo(todo);
              await theme.loadFromStorage();
              final preferences = await SharedPreferences.getInstance();
              final stored = preferences.getString('todos');
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
                      ).copyWith(textScaler: layout.scaler),
                      child: RepaintBoundary(key: boundary, child: child!),
                    ),
                    home: Builder(
                      builder: (context) => Scaffold(
                        body: Center(
                          child: TextButton(
                            onPressed: () => TodayDetailRouter.open(
                              context,
                              TodaySectionKind.todos,
                              id: todo.id,
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
              expect(find.byType(BrandRouteSurface), findsOneWidget);
              final route = find.byType(TodoDetailScreen);
              final state = tester.state(route);
              Future<void> revealAndMeasure(String stage) async {
                // Locale changes can shorten earlier lazy-list rows enough to
                // move this target above the retained scroll offset.
                tester
                    .state<ScrollableState>(_detailScroll())
                    .position
                    .jumpTo(0);
                await tester.pumpAndSettle();
                final target = copy == _Copy.assignee
                    ? find.text(TodoDetailUiCopy.assigneePrivateSubtitle)
                    : _tagField();
                await tester.scrollUntilVisible(
                  target,
                  120,
                  scrollable: _detailScroll(),
                );
                await tester.ensureVisible(target);
                await tester.pumpAndSettle();
                await _capture(tester, boundary, '$name-$stage');
                final text = copy == _Copy.assignee
                    ? TodoDetailUiCopy.assigneePrivateSubtitle
                    : TodoDetailUiCopy.newTagHint;
                _expectCompleteText(tester, text, layout.scaler);
                if (copy == _Copy.tag) {
                  expect(_tagField().hitTestable(), findsOneWidget);
                  final fieldRect = tester.getRect(_tagField());
                  expect(fieldRect.left, greaterThanOrEqualTo(0));
                  expect(fieldRect.right, lessThanOrEqualTo(layout.size.width));
                  if (layout.name == 'ordinary') {
                    expect(fieldRect.width, closeTo(140, 0.5));
                  }
                }
                expect(tester.takeException(), isNull);
              }

              await revealAndMeasure('initial');
              I18n.setLocale(
                locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
              );
              await tester.pumpAndSettle();
              expect(tester.state(route), same(state));
              await revealAndMeasure('switched');
              I18n.setLocale(locale);
              await tester.pumpAndSettle();
              if (copy == _Copy.tag) {
                await tester.ensureVisible(_tagField());
                await tester.pumpAndSettle();
                await tester.enterText(_tagField(), 'Draft tag 未保存标签');
                final controller = tester
                    .widget<TextField>(_tagField())
                    .controller!;
                controller.selection = const TextSelection(
                  baseOffset: 2,
                  extentOffset: 8,
                );
                for (final next in [
                  locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
                  locale,
                ]) {
                  I18n.setLocale(next);
                  await tester.pumpAndSettle();
                  expect(tester.state(route), same(state));
                  expect(
                    tester.widget<TextField>(_tagField()).controller,
                    same(controller),
                  );
                  expect(controller.text, 'Draft tag 未保存标签');
                  expect(
                    controller.selection,
                    const TextSelection(baseOffset: 2, extentOffset: 8),
                  );
                }
                await tester.testTextInput.receiveAction(TextInputAction.done);
                await tester.pumpAndSettle();
                expect(controller.text, isEmpty);
                expect(find.text('#Draft tag 未保存标签'), findsOneWidget);
                expect(todos.todos.single.tags, todo.tags);
                expect(preferences.getString('todos'), stored);
                FocusManager.instance.primaryFocus?.unfocus();
                await tester.pumpAndSettle();
                if (locale == AppLocale.en) {
                  await tester.tap(find.byTooltip(TodoDetailUiCopy.save));
                  await tester.pumpAndSettle();
                  expect(find.byType(TodoDetailScreen), findsNothing);
                  expect(todos.todos.single.tags, [
                    ...todo.tags,
                    'Draft tag 未保存标签',
                  ]);
                  final saved =
                      jsonDecode(preferences.getString('todos')!) as List;
                  expect((saved.single as Map)['tags'], [
                    ...todo.tags,
                    'Draft tag 未保存标签',
                  ]);
                } else {
                  await tester.tap(
                    find.widgetWithIcon(IconButton, Icons.arrow_back),
                  );
                  await tester.pumpAndSettle();
                  expect(find.byType(AppDialog), findsOneWidget);
                  await tester.tap(
                    find.widgetWithText(
                      TextButton,
                      TodoDetailUiCopy.discardAction,
                    ),
                  );
                  await tester.pumpAndSettle();
                  expect(find.byType(TodoDetailScreen), findsNothing);
                  expect(todos.todos.single.toJson(), todo.toJson());
                  expect(preferences.getString('todos'), stored);
                }
              } else {
                await tester.tap(
                  find.widgetWithIcon(IconButton, Icons.arrow_back),
                );
                await tester.pumpAndSettle();
                expect(find.byType(TodoDetailScreen), findsNothing);
                expect(preferences.getString('todos'), stored);
              }
              expect(find.text('Open task'), findsOneWidget);
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
}

Finder _tagField() => find.descendant(
  of: find.byType(TodoDetailScreen),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == TodoDetailUiCopy.newTagHint,
  ),
);

Finder _detailScroll() => find
    .descendant(
      of: find.byType(TodoDetailScreen),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    )
    .first;

void _expectCompleteText(WidgetTester tester, String text, TextScaler scaler) {
  final finder = find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText() == text,
  );
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    maxLines: paragraph.maxLines,
    ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null,
  )..layout(maxWidth: paragraph.size.width);
  expect(
    painter.didExceedMaxLines,
    isFalse,
    reason: 'Complete copy required: $text',
  );
  expect(
    painter.height,
    lessThanOrEqualTo(paragraph.size.height + 0.5),
    reason: text,
  );
  expect(
    painter.width,
    lessThanOrEqualTo(paragraph.size.width + 0.5),
    reason: text,
  );
  for (final fontSize in [12.0, 16.0]) {
    expect(
      paragraph.textScaler.scale(fontSize),
      closeTo(scaler.scale(fontSize), 0.01),
    );
  }
  expect(paragraph.text.style?.fontSize, greaterThanOrEqualTo(12));
  painter.dispose();
}

class _CopyNonlinearScaler extends TextScaler {
  const _CopyNonlinearScaler();

  @override
  double scale(double fontSize) => fontSize * (fontSize < 14 ? 1.9 : 1.6);

  @override
  double get textScaleFactor => 1;
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['DUOYI_CAPTURE_TODO_COPY_FIT'] != '1') return;
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    final run = Platform.environment['DUOYI_TODO_COPY_FIT_RUN'] ?? 'current';
    final file = File(
      'evidence/screenshots/todo-detail-copy-fit-20261020/$run/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
