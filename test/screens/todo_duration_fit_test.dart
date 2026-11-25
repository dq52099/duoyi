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
        (name: 'ordinary', size: Size(390, 844), scaler: TextScaler.noScaling),
        (name: 'narrow', size: Size(320, 844), scaler: TextScaler.linear(1.6)),
        (name: 'landscape', size: Size(568, 320), scaler: TextScaler.linear(2)),
        (name: 'nonlinear', size: Size(332, 844), scaler: _DurationScaler()),
      ]) {
        final name = '$brand-${locale.name}-${layout.name}';
        testWidgets('readable duration guidance and numeric draft $name', (
          tester,
        ) async {
          final todo = TodoItem(
            id: 'duration-fit/task',
            title: 'Literal duration 用户任务',
            notes: 'Original description 原始说明',
            timeTargetSeconds: 1500,
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

            Future<void> reveal() async {
              tester.state<ScrollableState>(_detailScroll()).position.jumpTo(0);
              await tester.pumpAndSettle();
              await tester.scrollUntilVisible(
                _field(),
                120,
                scrollable: _detailScroll(),
              );
              await tester.ensureVisible(_field());
              await tester.pumpAndSettle();
            }

            await reveal();
            final controller = tester.widget<TextField>(_field()).controller!;
            expect(controller.text, '25');
            expect(
              tester.widget<TextField>(_field()).keyboardType,
              TextInputType.number,
            );
            expect(tester.widget<TextField>(_field()).maxLines, 1);
            await tester.tap(find.widgetWithIcon(IconButton, Icons.clear));
            await tester.pumpAndSettle();
            expect(controller.text, isEmpty);
            for (final stage in ['initial', 'switched']) {
              if (stage == 'switched') {
                I18n.setLocale(
                  locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
                );
                await tester.pumpAndSettle();
              }
              await reveal();
              final guidance = find.byWidgetPredicate(
                (widget) =>
                    widget is RichText &&
                    widget.text.toPlainText() ==
                        TodoDetailUiCopy.targetDurationHint,
              );
              await tester.ensureVisible(guidance);
              await tester.pumpAndSettle();
              await _capture(tester, boundary, '$name-$stage');
              _expectComplete(tester, guidance, layout.scaler);
              expect(tester.state(route), same(state));
              expect(
                tester.widget<TextField>(_field()).controller,
                same(controller),
              );
              expect(todos.todos.single.timeTargetSeconds, 1500);
              expect(preferences.getString('todos'), stored);
              expect(tester.takeException(), isNull);
            }
            I18n.setLocale(locale);
            await tester.pumpAndSettle();
            await reveal();
            await tester.tap(
              find.widgetWithText(
                ChoiceChip,
                TodoDetailUiCopy.presetMinutes(15),
              ),
            );
            await tester.pumpAndSettle();
            expect(controller.text, '15');
            expect(
              tester
                  .widget<ChoiceChip>(
                    find.widgetWithText(
                      ChoiceChip,
                      TodoDetailUiCopy.presetMinutes(15),
                    ),
                  )
                  .selected,
              isTrue,
            );
            await tester.enterText(_field(), '3x7');
            await tester.pumpAndSettle();
            expect(controller.text, '37');
            controller.selection = const TextSelection(
              baseOffset: 0,
              extentOffset: 1,
            );
            for (final next in [
              locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
              locale,
            ]) {
              I18n.setLocale(next);
              await tester.pumpAndSettle();
              await reveal();
              expect(tester.state(route), same(state));
              expect(
                tester.widget<TextField>(_field()).controller,
                same(controller),
              );
              expect(controller.text, '37');
              expect(
                controller.selection,
                const TextSelection(baseOffset: 0, extentOffset: 1),
              );
            }
            await tester.enterText(_field(), '0');
            await tester.pumpAndSettle();
            expect(controller.text, isEmpty);
            await tester.enterText(_field(), '12');
            await tester.pumpAndSettle();
            await tester.enterText(_field(), '');
            await tester.pumpAndSettle();
            expect(controller.text, isEmpty);
            for (final minutes in [25, 45, 60]) {
              final preset = find.widgetWithText(
                ChoiceChip,
                TodoDetailUiCopy.presetMinutes(minutes),
              );
              await tester.ensureVisible(preset);
              await tester.pumpAndSettle();
              await tester.tap(preset);
              await tester.pumpAndSettle();
              expect(controller.text, '$minutes');
              expect(tester.widget<ChoiceChip>(preset).selected, isTrue);
            }
            final saveClear = ['landscape', 'nonlinear'].contains(layout.name);
            await reveal();
            await tester.tap(find.widgetWithIcon(IconButton, Icons.clear));
            await tester.pumpAndSettle();
            expect(controller.text, isEmpty);
            if (!saveClear) {
              await tester.tap(
                find.widgetWithText(
                  ChoiceChip,
                  TodoDetailUiCopy.presetMinutes(45),
                ),
              );
              await tester.pumpAndSettle();
              expect(controller.text, '45');
            }
            expect(todos.todos.single.toJson(), todo.toJson());
            expect(preferences.getString('todos'), stored);
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            if (locale == AppLocale.en) {
              await tester.tap(find.byTooltip(TodoDetailUiCopy.save));
              await tester.pumpAndSettle();
              final expected = saveClear ? null : 2700;
              expect(todos.todos.single.timeTargetSeconds, expected);
              final saved = jsonDecode(preferences.getString('todos')!) as List;
              expect((saved.single as Map)['timeTargetSeconds'], expected);
            } else {
              await tester.tap(
                find.widgetWithIcon(IconButton, Icons.arrow_back),
              );
              await tester.pumpAndSettle();
              expect(find.byType(AppDialog), findsOneWidget);
              await tester.tap(
                find.widgetWithText(TextButton, TodoDetailUiCopy.discardAction),
              );
              await tester.pumpAndSettle();
              expect(todos.todos.single.toJson(), todo.toJson());
              expect(preferences.getString('todos'), stored);
            }
            expect(find.byType(TodoDetailScreen), findsNothing);
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

Finder _field() => find.descendant(
  of: find.byType(TodoDetailScreen),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.suffixText == TodoDetailUiCopy.minutesSuffix,
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

void _expectComplete(WidgetTester tester, Finder finder, TextScaler scaler) {
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
    reason: 'Complete duration guidance',
  );
  expect(painter.height, lessThanOrEqualTo(paragraph.size.height + 0.5));
  for (final size in [12.0, 16.0]) {
    expect(paragraph.textScaler.scale(size), closeTo(scaler.scale(size), 0.01));
  }
  expect(paragraph.text.style?.fontSize, greaterThanOrEqualTo(12));
  final input = tester.widget<EditableText>(
    find.descendant(of: _field(), matching: find.byType(EditableText)),
  );
  expect(
    paragraph.text.style?.fontSize,
    greaterThanOrEqualTo(input.style.fontSize!),
    reason: 'Guidance must retain the numeric input font size',
  );
  painter.dispose();
}

class _DurationScaler extends TextScaler {
  const _DurationScaler();
  @override
  double scale(double fontSize) => fontSize * (fontSize < 14 ? 1.9 : 1.6);
  @override
  double get textScaleFactor => 1;
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['DUOYI_CAPTURE_TODO_DURATION'] != '1') return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    final run = Platform.environment['DUOYI_TODO_DURATION_RUN'] ?? 'current';
    final file = File(
      'evidence/screenshots/todo-duration-fit-20261020/$run/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
