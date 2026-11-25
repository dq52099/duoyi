import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/goal_edit_screen.dart';
import 'package:duoyi/screens/note_screen.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

enum _Object { note, goal }

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final object in _Object.values) {
        for (final layout in const [
          (
            name: 'narrow',
            size: Size(320, 844),
            scaler: TextScaler.linear(1.6),
            inset: 240.0,
            selected: false,
            fullEvidence: true,
          ),
          (
            name: 'landscape',
            size: Size(568, 320),
            scaler: TextScaler.linear(2),
            inset: 100.0,
            selected: false,
            fullEvidence: true,
          ),
          (
            name: 'selected-normal',
            size: Size(320, 844),
            scaler: TextScaler.noScaling,
            inset: 240.0,
            selected: true,
            fullEvidence: false,
          ),
          (
            name: 'selected-large',
            size: Size(320, 844),
            scaler: TextScaler.linear(1.6),
            inset: 240.0,
            selected: true,
            fullEvidence: false,
          ),
          (
            name: 'selected-nonlinear',
            size: Size(332, 844),
            scaler: _GoalNonlinearScaler(),
            inset: 240.0,
            selected: true,
            fullEvidence: false,
          ),
          (
            name: 'empty-nonlinear',
            size: Size(332, 844),
            scaler: _GoalNonlinearScaler(),
            inset: 240.0,
            selected: false,
            fullEvidence: false,
          ),
        ]) {
          if (object == _Object.note && !layout.fullEvidence) continue;
          final name = '$brand-${locale.name}-${object.name}-${layout.name}';
          testWidgets('widget object route preserves paired theme draft $name', (
            tester,
          ) async {
            final date = DateTime(2024, 1, 2);
            final note = NoteItem(
              id: 'note/object',
              content: '# Literal note 用户笔记\nOriginal body 原始正文',
              createdAt: date,
              updatedAt: date,
            );
            final goal = GoalItem(
              id: 'goal/object',
              title: 'Literal goal 用户目标',
              description: 'Original description 原始说明',
              startDate: layout.selected ? DateTime(2026, 12, 31) : null,
              targetDate: layout.selected ? DateTime(2027, 1, 1) : null,
              createdAt: date,
              updatedAt: date,
            );
            final storedNotes = [jsonEncode(note.toJson())];
            final storedGoals = [jsonEncode(goal.toJson())];
            SharedPreferences.setMockInitialValues({
              'active_brand': brand,
              'duoyi_notes': storedNotes,
              'duoyi_goals': storedGoals,
            });
            final notes = NoteProvider();
            final goals = GoalProvider();
            final sounds = CustomFocusSoundProvider();
            final theme = ThemeProvider();
            final boundary = GlobalKey();
            final previousShadows = debugDisableShadows;
            Future<void> capture(String stage) async {
              if (layout.fullEvidence || stage == 'top') {
                await _capture(tester, boundary, '$name-$stage');
              }
            }

            try {
              I18n.setLocale(locale);
              debugDisableShadows = false;
              // Provider queues were created in this test's fakeAsync zone.
              await notes.loadFromStorage();
              await goals.loadFromStorage();
              await theme.loadFromStorage();
              await tester.runAsync(() async {
                await loadWeeklyReviewScreenshotFonts(
                  emojiFontPath:
                      'evidence/widget-detail-theme-20261020/fonts/NotoColorEmoji.ttf',
                );
              });
              expect(theme.brand.id, brand);
              tester.view.physicalSize = layout.size;
              tester.view.devicePixelRatio = 1;
              await tester.pumpWidget(
                MultiProvider(
                  providers: [
                    ChangeNotifierProvider<NoteProvider>.value(value: notes),
                    ChangeNotifierProvider<GoalProvider>.value(value: goals),
                    ChangeNotifierProvider<CustomFocusSoundProvider>.value(
                      value: sounds,
                    ),
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
                              object == _Object.note
                                  ? TodaySectionKind.notes
                                  : TodaySectionKind.goals,
                              id: object == _Object.note ? note.id : goal.id,
                            ),
                            child: const Text('Open object'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.tap(find.text('Open object'));
              await tester.pumpAndSettle();
              final route = object == _Object.note
                  ? find.byType(NoteEditScreen)
                  : find.byType(GoalEditScreen);
              expect(route, findsOneWidget);
              expect(find.byType(BrandRouteSurface), findsOneWidget);
              final state = tester.state(route);
              expect(tester.takeException(), isNull);
              await capture('top');
              if (object == _Object.goal) {
                _expectDateTextFits(tester);
                if (layout.name == 'selected-normal') {
                  final start = tester.getTopLeft(
                    find.byKey(const ValueKey('goal_start_date_field')),
                  );
                  final target = tester.getTopLeft(
                    find.byKey(const ValueKey('goal_target_date_field')),
                  );
                  expect(
                    (start.dy - target.dy).abs(),
                    lessThan(4),
                    reason:
                        'Ordinary narrow fields retain their accepted same-row layout',
                  );
                }
              }

              final field = find
                  .descendant(of: route, matching: find.byType(TextField))
                  .first;
              await tester.ensureVisible(field);
              await tester.enterText(field, 'Unsaved draft 未保存草稿');
              final controller = tester.widget<TextField>(field).controller!;
              controller.selection = const TextSelection(
                baseOffset: 2,
                extentOffset: 8,
              );
              final fieldElement = tester.element(field);
              final other = locale == AppLocale.zh
                  ? AppLocale.en
                  : AppLocale.zh;
              for (final next in [other, locale]) {
                I18n.setLocale(next);
                await tester.pumpAndSettle();
                expect(tester.state(route), same(state));
                expect(tester.element(field), same(fieldElement));
                expect(
                  tester.widget<TextField>(field).controller,
                  same(controller),
                );
                expect(controller.text, 'Unsaved draft 未保存草稿');
                expect(
                  controller.selection,
                  const TextSelection(baseOffset: 2, extentOffset: 8),
                );
                final title =
                    tester.widget<AppBar>(find.byType(AppBar)).title! as Text;
                expect(
                  title.data,
                  object == _Object.note
                      ? I18n.tr('note.edit.title')
                      : (next == AppLocale.en ? 'Edit goal' : '编辑目标'),
                );
                expect(tester.takeException(), isNull);
                if (object == _Object.goal) _expectDateTextFits(tester);
                if (next == other) await capture('switched');
              }

              if (object == _Object.goal && layout.name == 'selected-normal') {
                for (final pair in [
                  (
                    'goal_start_date_field',
                    locale == AppLocale.en ? 'On creation' : '创建即开启',
                  ),
                  (
                    'goal_target_date_field',
                    locale == AppLocale.en ? 'No deadline' : '无期限',
                  ),
                ]) {
                  final dateField = find.byKey(ValueKey(pair.$1));
                  final clear = find.descendant(
                    of: dateField,
                    matching: find.byIcon(Icons.close),
                  );
                  await tester.ensureVisible(clear);
                  await tester.tap(clear);
                  await tester.pumpAndSettle();
                  expect(
                    find.descendant(
                      of: dateField,
                      matching: find.text(pair.$2),
                    ),
                    findsOneWidget,
                  );
                  _expectDateTextFits(tester);
                  expect(tester.takeException(), isNull);
                }
              }

              if (object == _Object.note) {
                FocusManager.instance.primaryFocus?.unfocus();
                await tester.pumpAndSettle();
                final horizontal = find
                    .descendant(of: route, matching: find.byType(Scrollable))
                    .evaluate()
                    .where((element) {
                      final direction =
                          (element.widget as Scrollable).axisDirection;
                      return direction == AxisDirection.right ||
                          direction == AxisDirection.left;
                    })
                    .single;
                final toolbar =
                    (horizontal as StatefulElement).state as ScrollableState;
                toolbar.position.jumpTo(toolbar.position.maxScrollExtent);
                await tester.ensureVisible(
                  find.byTooltip(I18n.tr('note.toolbar.attachment')),
                );
                await tester.pumpAndSettle();
                expect(
                  find
                      .byTooltip(I18n.tr('note.toolbar.attachment'))
                      .hitTestable(),
                  findsOneWidget,
                );
                await capture('toolbar-tail');
                toolbar.position.jumpTo(toolbar.position.minScrollExtent);
                await tester.tap(find.byTooltip(I18n.tr('note.preview')));
                await tester.pumpAndSettle();
                expect(find.byTooltip(I18n.tr('note.edit')), findsOneWidget);
                expect(
                  find.text('Unsaved draft 未保存草稿', findRichText: true),
                  findsOneWidget,
                );
                await capture('preview');
                await tester.tap(find.byTooltip(I18n.tr('note.edit')));
                await tester.pumpAndSettle();
                expect(
                  tester.widget<TextField>(field).controller,
                  same(controller),
                );
                expect(controller.text, 'Unsaved draft 未保存草稿');
              }

              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              final scrollable = find
                  .descendant(of: route, matching: find.byType(Scrollable))
                  .first;
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              // Visit intermediate sections rather than jumping past lazy rows.
              for (
                var step = 0;
                step < 100 && position.extentAfter > 1;
                step++
              ) {
                position.jumpTo(
                  (position.pixels + position.viewportDimension * 0.65).clamp(
                    position.minScrollExtent,
                    position.maxScrollExtent,
                  ),
                );
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
              }
              expect(position.extentAfter, lessThanOrEqualTo(1));
              await capture('bottom');

              // Insets exercise the real route layout, without claiming a device IME.
              position.jumpTo(position.minScrollExtent);
              tester.view.viewInsets = FakeViewPadding(bottom: layout.inset);
              await tester.pumpAndSettle();
              final back = find.byType(BackButton);
              expect(back.hitTestable(), findsOneWidget);
              final backRect = tester.getRect(back);
              expect(backRect.top, greaterThanOrEqualTo(0));
              expect(
                backRect.bottom,
                lessThanOrEqualTo(layout.size.height - layout.inset),
              );
              expect(backRect.right, lessThanOrEqualTo(layout.size.width));
              expect(tester.takeException(), isNull);
              await capture('inset-back');
              await tester.tap(back);
              await tester.pumpAndSettle();
              expect(find.text('Open object'), findsOneWidget);
              expect(route, findsNothing);
              final prefs = await SharedPreferences.getInstance();
              expect(prefs.getStringList('duoyi_notes'), storedNotes);
              expect(prefs.getStringList('duoyi_goals'), storedGoals);
              expect(notes.notes.single.toJson(), note.toJson());
              expect(goals.goals.single.toJson(), goal.toJson());
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              notes.dispose();
              goals.dispose();
              sounds.dispose();
              theme.dispose();
              tester.view.reset();
              I18n.setLocale(AppLocale.zh);
              debugDisableShadows = previousShadows;
            }
          });
        }
      }
    }
  }
}

class _GoalNonlinearScaler extends TextScaler {
  const _GoalNonlinearScaler();
  @override
  double scale(double fontSize) => fontSize < 10 ? fontSize : fontSize * 1.8;
  @override
  double get textScaleFactor => 1;
}

void _expectDateTextFits(WidgetTester tester) {
  for (final key in ['goal_start_date_field', 'goal_target_date_field']) {
    final field = find.byKey(ValueKey(key));
    final fieldElement = tester.element(field);
    for (final element
        in find
            .descendant(of: field, matching: find.byType(RichText))
            .evaluate()) {
      var isIcon = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is Icon) isIcon = true;
        return !isIcon && !identical(ancestor, fieldElement);
      });
      if (isIcon) continue;
      final paragraph = element.renderObject! as RenderParagraph;
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
            '$key must display the full date label/value: ${paragraph.text.toPlainText()}',
      );
      expect(
        painter.height,
        lessThanOrEqualTo(paragraph.size.height + 0.5),
        reason: '$key must not clip wrapped date text vertically',
      );
      expect(
        paragraph.textScaler.scale(11),
        closeTo(MediaQuery.textScalerOf(fieldElement).scale(11), 0.01),
        reason: '$key preserves requested text scaling',
      );
      expect(
        paragraph.text.style?.fontSize ??
            DefaultTextStyle.of(element).style.fontSize ??
            14,
        greaterThanOrEqualTo(11),
        reason: '$key must not shrink its existing date typography',
      );
      painter.dispose();
    }
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['DUOYI_CAPTURE_NOTE_GOAL_THEME'] != '1') return;
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    final run = Platform.environment['DUOYI_NOTE_GOAL_THEME_RUN'] ?? 'current';
    final path =
        'evidence/screenshots/widget-note-goal-theme-20261020/$run/$name.png';
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
