// Actual pushed MoreApps/hidden-Today retention and accessibility regression.
// Retains all 16 standard IDs and adds 8 hidden-Today typography cases.
// Do not install while an inventory-owning verification job is active.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/today_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/more_apps_screen.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

const _outputEnv = 'DUOYI_MORE_APPS_RETAINED_ROUTE_EVIDENCE_DIR';
const _reminderId = 'more-apps-hidden-today-overdue-1069';
const _reminderTitle = 'User entered overdue reminder 1069';
const _openKey = ValueKey('open-real-more-apps-1069');
const _layouts = [
  (name: '200x844', size: Size(200, 844)),
  (name: '320x568', size: Size(320, 568)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _registerSuggestionReadability1236();
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in [AppLocale.zh, AppLocale.en]) {
      for (final layout in _layouts) {
        final suffix = '$brand-${locale.name}-${layout.name}-scale2.0';
        testWidgets('more-apps-retained-route-$suffix', (tester) async {
          final fixture = _Fixture(brand, locale, layout.size);
          addTearDown(() => fixture.dispose(tester));
          await fixture.mount(tester);
          final page = find.byType(MoreApplicationsScreen);
          final oldElement = tester.element(page);
          final oldRoute = ModalRoute.of(oldElement);
          final oldScroll = _scrollState(tester, page);
          // Pick a genuinely positive interior offset, not a zero-offset pass.
          oldScroll.position.jumpTo(
            math.min(180, oldScroll.position.maxScrollExtent * .65).toDouble(),
          );
          await tester.pumpAndSettle();
          final before = _observe(
            tester,
            fixture,
            page,
            title: _moreTitle(tester, page),
          );
          await _save(tester, fixture, '$suffix-more-before', before);

          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          final after = _observe(
            tester,
            fixture,
            page,
            title: _moreTitle(tester, page),
          );
          await _save(tester, fixture, '$suffix-more-after', {
            ...after,
            'baseline': before,
          });

          // Both images/JSON are persisted before retention/layout assertions.
          _expectRetained(
            tester,
            fixture,
            page,
            oldElement,
            oldRoute,
            oldScroll,
            before,
            after,
          );
          final title = _moreTitle(tester, page);
          _expectCompleteText(
            tester,
            title,
            I18n.tr('mine.tile.more_apps'),
            // The unchanged Material AppBar clamps only its title to 1.34.
            // The real page and reminder heading still receive the 2x scaler.
            expectedTextScale: 1.34,
          );
          expect(
            find.descendant(
              of: page,
              matching: find.byType(MoreApplicationButton),
            ),
            findsNWidgets(5),
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('more-apps-hidden-today-retained-$suffix', (tester) async {
          final fixture = _Fixture(brand, locale, layout.size);
          addTearDown(() => fixture.dispose(tester));
          await fixture.mount(tester, withReminder: true);
          final more = find.byType(MoreApplicationsScreen);
          final todayButton = find.descendant(
            of: more,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is MoreApplicationButton && widget.app.tab == 0,
            ),
          );
          await Scrollable.ensureVisible(
            tester.element(todayButton),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          // Invoke the actual production entry's InkWell; its own builder and
          // BrandRouteSurface create Today. No synthetic Today or route bypass.
          final tapRegion = find.descendant(
            of: todayButton,
            matching: find.byKey(
              const ValueKey('more_application_button_tap_region'),
            ),
          );
          await tester.tap(tapRegion);
          await tester.pumpAndSettle();
          final page = find.byType(TodayScreen);
          final toggle = find.descendant(
            of: page,
            matching: find.byKey(
              const ValueKey('today_reminder_header_toggle'),
            ),
          );
          await tester.scrollUntilVisible(
            toggle,
            240,
            scrollable: _scrollFinder(page),
            maxScrolls: 60,
          );
          await Scrollable.ensureVisible(tester.element(toggle), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          final oldElement = tester.element(page);
          final oldRoute = ModalRoute.of(oldElement);
          final oldScroll = _scrollState(tester, page);
          if (oldScroll.position.pixels <= 0) {
            oldScroll.position.jumpTo(
              math.min(120, oldScroll.position.maxScrollExtent * .5).toDouble(),
            );
            await tester.pumpAndSettle();
          }
          final before = _observe(
            tester,
            fixture,
            page,
            title: _reminderHeader(page),
            reminder: true,
          );
          await _save(tester, fixture, '$suffix-today-before', before);

          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          final after = _observe(
            tester,
            fixture,
            page,
            title: _reminderHeader(page),
            reminder: true,
          );
          await _save(tester, fixture, '$suffix-today-after', {
            ...after,
            'baseline': before,
          });

          _expectRetained(
            tester,
            fixture,
            page,
            oldElement,
            oldRoute,
            oldScroll,
            before,
            after,
          );
          expect(before['expandedReminder'], isTrue);
          expect(
            after['expandedReminder'],
            isTrue,
            reason: 'The actual overdue reminder tile stays expanded',
          );
          expect(
            find.descendant(
              of: page,
              matching: find.byKey(
                const ValueKey('today_reminder_todo_$_reminderId'),
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: page, matching: find.text(_reminderTitle)),
            findsWidgets,
          );
          _expectCompleteText(
            tester,
            _reminderHeader(page),
            TodayUiCopy.reminderHeaderTitle,
          );
          expect(fixture.todos.todos.single.id, _reminderId);
          expect(fixture.todos.todos.single.title, _reminderTitle);
          // Both PNG/JSON stages are collected before the word oracle.
          _expectReminderTitleWords(before, after);
          expect(tester.takeException(), isNull);
        });

        // Eight additional cases; the sixteen standard IDs above are intact.
        testWidgets(
          'more-apps-hidden-today-retained-$suffix-bold-letter2-word3-1082',
          (tester) async {
            final fixture = _Fixture(
              brand,
              locale,
              layout.size,
              accessibilityTypography: true,
            );
            addTearDown(() => fixture.dispose(tester));
            await fixture.mount(tester, withReminder: true);
            final more = find.byType(MoreApplicationsScreen);
            final todayButton = find.descendant(
              of: more,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is MoreApplicationButton && widget.app.tab == 0,
              ),
            );
            await Scrollable.ensureVisible(
              tester.element(todayButton),
              alignment: .5,
            );
            await tester.pumpAndSettle();
            // Invoke the actual production entry's InkWell; its own builder and
            // BrandRouteSurface create Today. No synthetic Today or route bypass.
            final tapRegion = find.descendant(
              of: todayButton,
              matching: find.byKey(
                const ValueKey('more_application_button_tap_region'),
              ),
            );
            await tester.tap(tapRegion);
            await tester.pumpAndSettle();
            final page = find.byType(TodayScreen);
            final toggle = find.descendant(
              of: page,
              matching: find.byKey(
                const ValueKey('today_reminder_header_toggle'),
              ),
            );
            await tester.scrollUntilVisible(
              toggle,
              240,
              scrollable: _scrollFinder(page),
              maxScrolls: 60,
            );
            await Scrollable.ensureVisible(
              tester.element(toggle),
              alignment: .5,
            );
            await tester.pumpAndSettle();
            // The header also contains an independent View button. Tap its
            // actual expansion chevron so a narrow header's centre cannot
            // select the nested navigation action instead of expansion.
            final expansionChevron = find.descendant(
              of: toggle,
              matching: find.byIcon(Icons.keyboard_arrow_down),
            );
            expect(expansionChevron, findsOneWidget);
            await tester.tap(expansionChevron);
            await tester.pumpAndSettle();
            final oldElement = tester.element(page);
            final oldRoute = ModalRoute.of(oldElement);
            final oldScroll = _scrollState(tester, page);
            if (oldScroll.position.pixels <= 0) {
              oldScroll.position.jumpTo(
                math
                    .min(120, oldScroll.position.maxScrollExtent * .5)
                    .toDouble(),
              );
              await tester.pumpAndSettle();
            }
            final before = _observe(
              tester,
              fixture,
              page,
              title: _reminderHeader(page),
              reminder: true,
            );
            await _save(
              tester,
              fixture,
              '$suffix-bold-letter2-word3-1082-today-before',
              before,
            );

            I18n.setLocale(
              locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
            );
            await tester.pumpAndSettle();
            final after = _observe(
              tester,
              fixture,
              page,
              title: _reminderHeader(page),
              reminder: true,
            );
            await _save(
              tester,
              fixture,
              '$suffix-bold-letter2-word3-1082-today-after',
              {...after, 'baseline': before},
            );

            _expectRetained(
              tester,
              fixture,
              page,
              oldElement,
              oldRoute,
              oldScroll,
              before,
              after,
            );
            expect(before['expandedReminder'], isTrue);
            expect(
              after['expandedReminder'],
              isTrue,
              reason: 'The actual overdue reminder tile stays expanded',
            );
            expect(
              find.descendant(
                of: page,
                matching: find.byKey(
                  const ValueKey('today_reminder_todo_$_reminderId'),
                ),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(of: page, matching: find.text(_reminderTitle)),
              findsWidgets,
            );
            _expectCompleteText(
              tester,
              _reminderHeader(page),
              TodayUiCopy.reminderHeaderTitle,
            );
            expect(fixture.todos.todos.single.id, _reminderId);
            expect(fixture.todos.todos.single.title, _reminderTitle);
            // Confirm the real Text renderer applied every requested override.
            // Both evidence stages already exist before these assertions run.
            _expectAccessibilityTypography(before, after);
            // Both PNG/JSON stages are collected before the word oracle.
            _expectReminderTitleWords(before, after);
            expect(tester.takeException(), isNull);
          },
        );
        // Separate touch registrations; the original24 cases above are intact.
        for (final touchTypography in [false, true]) {
          final mode = touchTypography ? 'bold-letter2-word3' : 'standard';
          testWidgets('today-touch-1099-$suffix-$mode', (tester) async {
            final semantics = tester.ensureSemantics();
            final history = <String, Object?>{'phase': 'mount'};
            final flutterErrors1145 = <Map<String, Object?>>[];
            final originalErrorHandler1145 = FlutterError.onError!;
            void captureError1145(FlutterErrorDetails details) {
              try {
                flutterErrors1145.add(_touchErrorDetails1145(details, history));
              } catch (error, stack) {
                flutterErrors1145.add({
                  'phase': history['phase'],
                  'diagnosticCaptureError': error.toString(),
                  'diagnosticCaptureStack': stack.toString(),
                });
              } finally {
                // The original handler receives the SAME details exactly once,
                // even if diagnostic serialization fails. Never consume errors.
                originalErrorHandler1145(details);
              }
            }
            FlutterError.onError = captureError1145;
            try {
              final todos = _TouchTodoProvider1099();
              final share = _TouchShareProvider1099();
              final fixture = _Fixture(
                brand,
                locale,
                layout.size,
                accessibilityTypography: touchTypography,
                todosOverride: todos,
                shareOverride: share,
              );
              addTearDown(() => fixture.dispose(tester));
              final now = DateTime.now();
              final overdue = TodoItem(
                id: _reminderId,
                title: 'Touch overdue1099',
                workspaceId: _touchWorkspace1099,
                date: now.subtract(const Duration(days: 1)),
                dueDate: now.subtract(const Duration(hours: 1)),
              );
              await fixture.mount(
                tester,
                withReminder: true,
                reminderOverride: overdue,
              );
              final prefix = '$suffix-$mode-touch1099';
              try {
                final tomorrow = DateTime(now.year, now.month, now.day + 1);
                history['phase'] = 'seed';
                await _touchAwait1127(tester, 'seed', () => todos.addTodo(
                  TodoItem(
                    id: _touchSuggestion1099,
                    title: 'Touch add1099',
                    workspaceId: _touchWorkspace1099,
                    date: tomorrow,
                    dueDate: tomorrow.add(const Duration(hours: 12)),
                    priority: TodoPriority.urgent,
                  ),
                  // This controls fixture seeding only. Production action calls
                  // retain their real reminder-sync arguments below.
                  waitForReminderSync: false,
                ));
                await tester.pumpAndSettle();
                await _exerciseTouch1099(
                  tester, fixture, todos, share, prefix, history,
                );
                FlutterError.onError = originalErrorHandler1145;
                expect(tester.takeException(), isNull);
              } finally {
                FlutterError.onError = originalErrorHandler1145;
                // Preserve the actual route even when acquisition/action fails.
                await _save(tester, fixture, '$prefix-terminal', {
                  ..._touchState1099(tester, fixture, todos),
                  'history': history,
                  'flutterErrors1145': flutterErrors1145,
                });
              }
            } finally {
              FlutterError.onError = originalErrorHandler1145;
              // WidgetTester verifies active handles before addTearDown runs.
              semantics.dispose();
            }
          });
        }

      }
    }
  }
}

Finder _scrollFinder(Finder page) => find.descendant(
  of: page,
  matching: find.byElementPredicate((element) {
    if (element is! StatefulElement || element.state is! ScrollableState) {
      return false;
    }
    final state = element.state as ScrollableState;
    return state.position.axis == Axis.vertical &&
        state.position.physics.allowUserScrolling;
  }),
);

ScrollableState _scrollState(WidgetTester tester, Finder page) =>
    tester.state<ScrollableState>(_scrollFinder(page));

Finder _moreTitle(WidgetTester tester, Finder page) {
  final appBar = tester.widget<AppBar>(
    find.descendant(of: page, matching: find.byType(AppBar)),
  );
  return find.byWidget(appBar.title!);
}

Finder _reminderHeader(Finder page) => find.descendant(
  of: page,
  matching: find.text(TodayUiCopy.reminderHeaderTitle),
);

Map<String, Object?> _observe(
  WidgetTester tester,
  _Fixture fixture,
  Finder page, {
  required Finder title,
  bool reminder = false,
}) {
  final matches = _scrollFinder(page).evaluate().toList();
  final current = matches.length == 1
      ? tester.state<ScrollableState>(_scrollFinder(page))
      : null;
  final titleElements = title.evaluate().toList();
  final paragraphs = find
      .descendant(of: title, matching: find.byType(RichText))
      .evaluate()
      .toList();
  final paragraph = paragraphs.length == 1
      ? tester.renderObject<RenderParagraph>(
          find.descendant(of: title, matching: find.byType(RichText)),
        )
      : null;
  final pageMediaQuery = MediaQuery.of(tester.element(page));
  return {
    'brand': fixture.theme.brand.id,
    'locale': I18n.current.name,
    'width': fixture.size.width,
    'height': fixture.size.height,
    'scale': 2.0,
    'scrollCount': matches.length,
    'scrollStateIdentity': current == null ? null : identityHashCode(current),
    'pixels': current?.position.pixels,
    'minScrollExtent': current?.position.minScrollExtent,
    'maxScrollExtent': current?.position.maxScrollExtent,
    'viewportDimension': current?.position.viewportDimension,
    'pageElementIdentity': identityHashCode(tester.element(page)),
    'routeIdentity': identityHashCode(ModalRoute.of(tester.element(page))),
    'mutations': fixture.store.mutations,
    'preferences': fixture.preferenceSnapshot(),
    'titleCount': titleElements.length,
    'title': paragraph?.text.toPlainText(),
    'titleExceedsMaxLines': paragraph?.didExceedMaxLines,
    'titlePaintedWidth': paragraph?.textSize.width,
    'titleWidth': paragraph?.size.width,
    'titlePaintedHeight': paragraph?.textSize.height,
    'titleHeight': paragraph?.size.height,
    'titleTextScale': paragraph?.textScaler.scale(10),
    'accessibilityTypographyRequested': fixture.accessibilityTypography,
    'pageMediaQuery': {
      'boldText': pageMediaQuery.boldText,
      'letterSpacingOverride': pageMediaQuery.letterSpacingOverride,
      'wordSpacingOverride': pageMediaQuery.wordSpacingOverride,
      'scaled10': pageMediaQuery.textScaler.scale(10),
    },
    'titleTypography': _renderedTypography(paragraph),
    if (reminder)
      'titleAsciiWordBoxes': _reminderTitleAsciiWordBoxes(paragraph),
    if (fixture.accessibilityTypography)
      'renderedParagraphs': [
        for (final element
            in find
                .descendant(of: page, matching: find.byType(RichText))
                .evaluate())
          if (element.renderObject is RenderParagraph)
            {
              'text': (element.renderObject as RenderParagraph).text
                  .toPlainText(),
              'typography': _renderedTypography(
                element.renderObject as RenderParagraph,
              ),
              'didExceedMaxLines':
                  (element.renderObject as RenderParagraph).didExceedMaxLines,
              'paintedWidth':
                  (element.renderObject as RenderParagraph).textSize.width,
              'width': (element.renderObject as RenderParagraph).size.width,
              'paintedHeight':
                  (element.renderObject as RenderParagraph).textSize.height,
              'height': (element.renderObject as RenderParagraph).size.height,
            },
      ],
    if (reminder)
      'expandedReminder': find
          .descendant(
            of: page,
            matching: find.byKey(
              const ValueKey('today_reminder_todo_$_reminderId'),
            ),
          )
          .evaluate()
          .isNotEmpty,
  };
}

// Use the actual laid-out RenderParagraph, not a parallel width estimate.
// Max-height boxes normalize vertical bounds within each rendered line. A word
// can have several same-line boxes (e.g. font runs) without being fragmented.
List<Map<String, Object?>> _reminderTitleAsciiWordBoxes(
  RenderParagraph? paragraph,
) {
  if (paragraph == null) return <Map<String, Object?>>[];
  final text = paragraph.text.toPlainText();
  return [
    for (final word in RegExp(r'[A-Za-z]+').allMatches(text))
      _recordReminderTitleWord(paragraph, word),
  ];
}

Map<String, Object?> _recordReminderTitleWord(
  RenderParagraph paragraph,
  RegExpMatch word,
) {
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: word.start, extentOffset: word.end),
    boxHeightStyle: ui.BoxHeightStyle.max,
  );
  final lineTops = <double>[];
  for (final box in boxes) {
    if (!lineTops.any((top) => (top - box.top).abs() <= .1)) {
      lineTops.add(box.top);
    }
  }
  lineTops.sort();
  return {
    'word': word.group(0),
    'start': word.start,
    'end': word.end,
    'boxHeightStyle': 'max',
    'boxes': [
      for (final box in boxes)
        {
          'left': box.left,
          'top': box.top,
          'right': box.right,
          'bottom': box.bottom,
          'direction': box.direction.name,
        },
    ],
    'lineTops': lineTops,
    'lineCount': lineTops.length,
  };
}

void _expectReminderTitleWords(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  var englishStageCount = 0;
  for (final stage in [before, after]) {
    if (stage['locale'] != AppLocale.en.name) continue;
    englishStageCount++;
    expect(stage['titleCount'], 1);
    expect(stage['title'], 'Today Reminders');
    final words = (stage['titleAsciiWordBoxes'] as List)
        .cast<Map<String, Object?>>();
    expect(
      words.map((word) => word['word']).toList(),
      ['Today', 'Reminders'],
      reason: 'Check both fixed English reminder-header words',
    );
    for (final word in words) {
      final boxes = (word['boxes'] as List).cast<Map<String, Object?>>();
      expect(boxes, isNotEmpty);
      for (final box in boxes) {
        for (final coordinate in ['left', 'top', 'right', 'bottom']) {
          expect((box[coordinate] as double).isFinite, isTrue);
        }
      }
      expect(
        word['lineCount'],
        1,
        reason:
            'English reminder-header word spans multiple lines: ${word['word']}',
      );
    }
  }
  expect(
    englishStageCount,
    1,
    reason: 'Each retained Today case must check its English stage',
  );
}

// These are observed RenderParagraph styles after Flutter Text has resolved
// DefaultTextStyle, boldText, and the system spacing overrides.
Map<String, Object?>? _renderedTypography(RenderParagraph? paragraph) {
  if (paragraph == null) return null;
  final style = paragraph.text.style;
  return {
    'fontFamily': style?.fontFamily,
    'fontFamilyFallback': style?.fontFamilyFallback,
    'fontSize': style?.fontSize,
    'fontWeight': style?.fontWeight?.value,
    'letterSpacing': style?.letterSpacing,
    'wordSpacing': style?.wordSpacing,
    'height': style?.height,
    'scaled10': paragraph.textScaler.scale(10),
  };
}

void _expectAccessibilityTypography(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  for (final stage in [before, after]) {
    expect(stage['accessibilityTypographyRequested'], isTrue);
    final media = stage['pageMediaQuery'] as Map<String, Object?>;
    expect(media['boldText'], isTrue);
    expect(media['letterSpacingOverride'], 2.0);
    expect(media['wordSpacingOverride'], 3.0);
    expect(media['scaled10'], closeTo(20, .001));
    expect(stage['titleCount'], 1);
    expect(stage['titleTypography'], isNotNull);
    final typography = stage['titleTypography'] as Map<String, Object?>;
    expect(typography['fontWeight'], FontWeight.bold.value);
    expect(typography['letterSpacing'], 2.0);
    expect(typography['wordSpacing'], 3.0);
    expect(typography['scaled10'], closeTo(20, .001));
  }
}

void _expectRetained(
  WidgetTester tester,
  _Fixture fixture,
  Finder page,
  Element oldElement,
  ModalRoute<dynamic>? oldRoute,
  ScrollableState oldScroll,
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  expect(before['scrollCount'], 1);
  expect(after['scrollCount'], 1);
  final scroll = _scrollState(tester, page);
  expect(
    scroll,
    same(oldScroll),
    reason: 'Retain the real user ScrollableState',
  );
  expect(tester.element(page), same(oldElement));
  expect(oldRoute, isNotNull);
  expect(ModalRoute.of(tester.element(page)), same(oldRoute));
  final oldOffset = before['pixels'] as double;
  expect(oldOffset, greaterThan(0), reason: 'Baseline must really be scrolled');
  final expected = oldOffset
      .clamp(scroll.position.minScrollExtent, scroll.position.maxScrollExtent)
      .toDouble();
  expect(
    scroll.position.pixels,
    closeTo(expected, .1),
    reason:
        'Preserve offset, allowing only a changed real scroll range to clamp',
  );
  if (scroll.position.maxScrollExtent > 0) {
    expect(scroll.position.pixels, greaterThan(0));
  }
  expect(after['mutations'], before['mutations']);
  expect(after['preferences'], before['preferences']);
  expect(fixture.theme.brand.id, fixture.brand);
}

void _expectCompleteText(
  WidgetTester tester,
  Finder label,
  String expected, {
  double expectedTextScale = 2,
}) {
  expect(label, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: label, matching: find.byType(RichText)),
  );
  expect(paragraph.text.toPlainText(), expected);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
    paragraph.textSize.width,
    lessThanOrEqualTo(paragraph.size.width + .1),
  );
  expect(
    paragraph.textSize.height,
    lessThanOrEqualTo(paragraph.size.height + .1),
  );
  expect(paragraph.textScaler.scale(10), closeTo(10 * expectedTextScale, .001));
}

class _Fixture {
  _Fixture(
    this.brand,
    this.locale,
    this.size, {
    this.accessibilityTypography = false,
    TodoProvider? todosOverride,
    this.shareOverride,
  }) : todos = todosOverride ?? TodoProvider();
  final ShareProvider? shareOverride;
  final String brand;
  final AppLocale locale;
  final Size size;
  final bool accessibilityTypography;
  final boundary = GlobalKey();
  final theme = ThemeProvider();
  final preferences = PreferencesProvider();
  final TodoProvider todos;
  final auth = AuthProvider();
  final owned = <ChangeNotifier>[];
  late _TrackingStore store;
  late SharedPreferences prefs;
  SharedPreferencesStorePlatform? previousStore;
  bool installed = false;

  Future<void> mount(
    WidgetTester tester, {
    bool withReminder = false,
    TodoItem? reminderOverride,
  }) async {
    previousStore = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final item = reminderOverride ?? TodoItem(
      id: _reminderId,
      title: _reminderTitle,
      date: now.subtract(const Duration(days: 1)),
      dueDate: now.subtract(const Duration(hours: 1)),
    );
    store = _TrackingStore({
      'flutter.active_brand': brand,
      if (withReminder) 'flutter.todos': jsonEncode([item.toJson()]),
    });
    SharedPreferencesStorePlatform.instance = store;
    installed = true;
    await tester.runAsync(() async {
      await theme.loadFromStorage();
      if (withReminder) await todos.loadFromStorage();
      prefs = await SharedPreferences.getInstance();
      await loadWeeklyReviewScreenshotFonts();
      await AccountPreferenceWrites.drain();
    });
    I18n.setLocale(locale);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final habit = HabitProvider();
    final pomodoro = PomodoroProvider();
    final diary = DiaryProvider();
    final anniversary = AnniversaryProvider();
    final course = CourseProvider();
    final goal = GoalProvider();
    final user = UserProvider();
    final timeAudit = TimeAuditProvider();
    final share = shareOverride ?? ShareProvider();
    owned.addAll([
      habit,
      pomodoro,
      diary,
      anniversary,
      course,
      goal,
      user,
      timeAudit,
      share,
    ]);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
          ChangeNotifierProvider<TodoProvider>.value(value: todos),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<HabitProvider>.value(value: habit),
          ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
          ChangeNotifierProvider<DiaryProvider>.value(value: diary),
          ChangeNotifierProvider<AnniversaryProvider>.value(value: anniversary),
          ChangeNotifierProvider<CourseProvider>.value(value: course),
          ChangeNotifierProvider<GoalProvider>.value(value: goal),
          ChangeNotifierProvider<UserProvider>.value(value: user),
          ChangeNotifierProvider<TimeAuditProvider>.value(value: timeAudit),
          ChangeNotifierProvider<ShareProvider>.value(value: share),
        ],
        child: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, current, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.brand.theme,
            locale: Locale(current == AppLocale.zh ? 'zh' : 'en'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(
                    textScaler: const TextScaler.linear(2),
                    // Root accessibility data follows the production Text path;
                    // do not alter ThemeData, TextStyle, or the page implementation.
                    boldText: accessibilityTypography ? true : null,
                  )
                  .applyTextStyleOverrides(
                    lineHeightScaleFactorOverride: MediaQuery.of(
                      context,
                    ).lineHeightScaleFactorOverride,
                    letterSpacingOverride: accessibilityTypography
                        ? 2
                        : MediaQuery.of(context).letterSpacingOverride,
                    wordSpacingOverride: accessibilityTypography
                        ? 3
                        : MediaQuery.of(context).wordSpacingOverride,
                    paragraphSpacingOverride: MediaQuery.of(
                      context,
                    ).paragraphSpacingOverride,
                  ),
              child: RepaintBoundary(key: boundary, child: child!),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    key: _openKey,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        // Same constructor wrapper as Mine. Preserve its default flags.
                        builder: (_) => const BrandRouteSurface(
                          child: MoreApplicationsScreen(
                            visibleBottomNavTabs: [6],
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open real hidden features'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(_openKey));
    await tester.pumpAndSettle();
    await tester.runAsync(AccountPreferenceWrites.drain);
    await tester.pumpAndSettle();
  }

  Map<String, Object?> preferenceSnapshot() => {
    for (final key in prefs.getKeys().toList()..sort())
      key: prefs.get(key) is List
          ? List<String>.of(prefs.getStringList(key)!)
          : prefs.get(key),
  };

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(AccountPreferenceWrites.drain);
    for (final notifier in owned.reversed) {
      notifier.dispose();
    }
    theme.dispose();
    preferences.dispose();
    todos.dispose();
    auth.dispose();
    if (installed) {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previousStore!;
    }
    tester.view.reset();
    I18n.setLocale(AppLocale.zh);
  }
}


const _touchWorkspace1099 = 'touch-workspace1099';
const _touchSuggestion1099 = 'touch-add1099';

class _TouchShareProvider1099 extends ShareProvider {
  bool editable = true;

  @override
  bool canEdit(String? workspaceId) {
    if (workspaceId == _touchWorkspace1099) return editable;
    return super.canEdit(workspaceId);
  }

  void setEditable(bool value) {
    editable = value;
    notifyListeners();
  }
}

// Instrument calls but forward the actual mutations and all supplied arguments.
// Permission/origin checks must prevent invocation; the fixture does not fake
// success or replace production scheduling/deletion with counter increments.
class _TouchTodoProvider1099 extends TodoProvider {
  final deleteRequests = <String>[];
  final scheduleRequests = <Map<String, Object?>>[];
  final _settlements = <Future<void>>[];

  @override
  Future<void> deleteTodo(String id) async {
    deleteRequests.add(id);
    final operation = super.deleteTodo(id);
    _settlements.add(operation);
    await operation;
  }

  @override
  Future<bool> scheduleTodoForToday(
    String id, {
    DateTime? now,
    bool waitForReminderSync = true,
    int? expectedAccountDataGeneration,
  }) async {
    scheduleRequests.add({
      'id': id,
      'now': now?.toIso8601String(),
      'waitForReminderSync': waitForReminderSync,
      'expectedAccountDataGeneration': expectedAccountDataGeneration,
    });
    final operation = super.scheduleTodoForToday(
      id,
      now: now,
      waitForReminderSync: waitForReminderSync,
      expectedAccountDataGeneration: expectedAccountDataGeneration,
    );
    _settlements.add(operation.then<void>((_) {}));
    return await operation;
  }

  Future<void> settleCalls() async {
    await Future.wait(_settlements);
  }
}

Map<String, Object?> _touchState1099(
  WidgetTester tester,
  _Fixture fixture,
  _TouchTodoProvider1099 todos,
) => {
  'brand': fixture.theme.brand.id,
  'locale': I18n.current.name,
  'width': fixture.size.width,
  'height': fixture.size.height,
  'accessibilityTypography': fixture.accessibilityTypography,
  'activeTodayCount': find.byType(TodayScreen).evaluate().length,
  'allTodayCount': find.byType(TodayScreen, skipOffstage: false)
      .evaluate().length,
  'activeTodoCount': find.byType(TodoScreen).evaluate().length,
  'allTodoCount': find.byType(TodoScreen, skipOffstage: false)
      .evaluate().length,
  'accountGeneration': AccountLocalDataCleaner.accountDataGeneration,
  'todos': [for (final item in todos.todos) item.toJson()],
  'deleteRequests': List<String>.of(todos.deleteRequests),
  'scheduleRequests': [
    for (final request in todos.scheduleRequests)
      Map<String, Object?>.of(request),
  ],
  'mutations': fixture.store.mutations,
  'preferences': fixture.preferenceSnapshot(),
};

// Materialize diagnostic closures while their render objects still exist.
// This is a snapshot only: the onError hook forwards the original details.
Map<String, Object?> _touchErrorDetails1145(
  FlutterErrorDetails details,
  Map<String, Object?> history,
) {
  final information = details.informationCollector?.call().toList() ??
      <DiagnosticsNode>[];
  final frozen = details.copyWith(informationCollector: () => information);
  return {
    'phase': history['phase'],
    'exceptionType': details.exception.runtimeType.toString(),
    'exception': details.exceptionAsString(),
    'stack': details.stack?.toString(),
    'library': details.library,
    'context': details.context?.toStringDeep(minLevel: DiagnosticLevel.hidden),
    'silent': details.silent,
    'fullDetails': frozen.toString(minLevel: DiagnosticLevel.hidden),
    'information': [
      for (final node in information)
        {
          'type': node.runtimeType.toString(),
          'name': node.name,
          'valueType': node.value?.runtimeType.toString(),
          'details': node.toStringDeep(minLevel: DiagnosticLevel.hidden),
          if (node.value is DebugCreator)
            'creator': (node.value as DebugCreator).toString(),
          if (node.value is RenderObject)
            'renderCreator':
                (node.value as RenderObject).debugCreator?.toString(),
        },
    ],
  };
}

// Mock storage mutations and the tracking futures belong to the fake-async
// test zone. Pump that zone while waiting; runAsync would suspend its progress.
// Preserve the real operation and surface both errors and unfinished calls.
Future<void> _touchAwait1127(
  WidgetTester tester,
  String phase,
  Future<void> Function() operation,
) async {
  var finished = false;
  Object? failure;
  StackTrace? failureStack;
  operation().then<void>(
    (_) { finished = true; },
    onError: (Object error, StackTrace stack) {
      failure = error;
      failureStack = stack;
      finished = true;
    },
  );
  // The production reminder-sync deadline is five seconds. Keep thirty
  // seconds of fake time for completion without a ten-minute wall-clock hang.
  for (var pumps = 0; !finished && pumps < 1500; pumps++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!finished) {
    throw StateError('Touch $phase operation unfinished after 30s of pumping');
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStack!);
  }
}

Future<void> _touchReveal1099(
  WidgetTester tester, Finder page, Finder target,
) async {
  await tester.scrollUntilVisible(
    target, 120, scrollable: _scrollFinder(page), maxScrolls: 80,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
}

Map<String, Object?> _touchProbe1099(
  WidgetTester tester,
  Finder target, {
  String edge = 'top',
  Finder? visual,
}) {
  final record = <String, Object?>{
    'count': target.evaluate().length,
    'hitTestableCount': target.hitTestable().evaluate().length,
    'edge': edge,
  };
  if (record['count'] != 1) return record;
  final rect = tester.getRect(target);
  final point = edge == 'right'
      ? rect.centerRight - const Offset(1, 0)
      : edge == 'left'
          ? rect.centerLeft + const Offset(1, 0)
          : rect.topCenter + const Offset(0, 1);
  record.addAll({
    'width': rect.width, 'height': rect.height,
    'left': rect.left, 'top': rect.top,
    'edgeX': point.dx, 'edgeY': point.dy,
  });
  try {
    final node = tester.getSemantics(target);
    record.addAll({
      'semanticsWidth': node.rect.width,
      'semanticsHeight': node.rect.height,
      'semanticsLabel': node.getSemanticsData().label,
      'semanticsHasTap': node.getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
    });
  } catch (error) {
    record['semanticsError'] = error.toString();
  }
  if (visual != null) {
    record['visualCount'] = visual.evaluate().length;
    if (record['visualCount'] == 1) {
      final visualRect = tester.getRect(visual);
      record['visualWidth'] = visualRect.width;
      record['visualHeight'] = visualRect.height;
      record['edgeOutsideVisual'] = !visualRect.contains(point);
    }
  }
  return record;
}

void _expectTouch1099(Map<String, Object?> probe) {
  expect(probe['count'], 1);
  expect(probe['hitTestableCount'], 1);
  expect(probe['width'], greaterThanOrEqualTo(44));
  expect(probe['height'], greaterThanOrEqualTo(44));
  expect(probe['semanticsError'], isNull);
  expect(probe['semanticsWidth'], greaterThanOrEqualTo(44));
  expect(probe['semanticsHeight'], greaterThanOrEqualTo(44));
  expect(probe['semanticsHasTap'], isTrue);
}

Future<void> _tapTouchEdge1099(
  WidgetTester tester, Map<String, Object?> probe,
) => tester.tapAt(Offset(
  probe['edgeX'] as double,
  probe['edgeY'] as double,
));

Future<Finder> _openTouchSwipe1099(
  WidgetTester tester, Finder page,
) async {
  final tile = find.byKey(
    const ValueKey('today_reminder_todo_$_reminderId'),
  );
  await _touchReveal1099(tester, page, tile);
  await tester.drag(tile, const Offset(-180, 0));
  await tester.pumpAndSettle();
  final root = find.descendant(
    of: tile,
    matching: find.byKey(
      const ValueKey('today_todo_swipe_delete_button'),
    ),
  );
  return find.descendant(of: root, matching: find.byType(InkWell));
}

Future<void> _touchCancelDelete1099(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, I18n.tr('action.cancel')));
  await tester.pumpAndSettle();
}

Future<void> _exerciseTouch1099(
  WidgetTester tester,
  _Fixture fixture,
  _TouchTodoProvider1099 todos,
  _TouchShareProvider1099 share,
  String prefix,
  Map<String, Object?> history,
) async {
  history['phase'] = 'header';
  // Open Today through the actual production MoreApps entry, as in the24 cases.
  final todayButton = find.descendant(
    of: find.byType(MoreApplicationsScreen),
    matching: find.byWidgetPredicate(
      (widget) => widget is MoreApplicationButton && widget.app.tab == 0,
    ),
  );
  await Scrollable.ensureVisible(tester.element(todayButton), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(
    of: todayButton,
    matching: find.byKey(
      const ValueKey('more_application_button_tap_region'),
    ),
  ));
  await tester.pumpAndSettle();
  final page = find.byType(TodayScreen);
  final toggle = find.descendant(
    of: page,
    matching: find.byKey(const ValueKey('today_reminder_header_toggle')),
  );
  await _touchReveal1099(tester, page, toggle);
  final headerProbe = _touchProbe1099(tester, toggle, edge: 'left');
  await _save(tester, fixture, '$prefix-header', {
    ..._touchState1099(tester, fixture, todos),
    'header': headerProbe,
  });
  _expectTouch1099(headerProbe);
  await _tapTouchEdge1099(tester, headerProbe);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey(
    'today_reminder_todo_$_reminderId',
  )), findsOneWidget);
  expect(find.byType(TodoScreen, skipOffstage: false), findsNothing);
  history['headerExpandedWithoutNavigation'] = true;

  history['phase'] = 'view';
  // The View button is outside the toggle in narrow natural-reflow layouts.
  final section = find.byKey(
    const ValueKey('today_reminder_section_collapsed_by_default'),
  );
  final view = find.descendant(
    of: section,
    matching: find.widgetWithText(TextButton, I18n.tr('today.view')),
  );
  await _touchReveal1099(tester, page, view);
  final viewProbe = _touchProbe1099(tester, view);
  await _save(tester, fixture, '$prefix-view', {
    ..._touchState1099(tester, fixture, todos),
    'view': viewProbe, 'history': history,
  });
  _expectTouch1099(viewProbe);
  expect(viewProbe['semanticsLabel'], contains(I18n.tr('today.view')));
  final oldElement = tester.element(page);
  final oldRoute = ModalRoute.of(oldElement);
  final oldScroll = _scrollState(tester, page);
  final oldOffset = oldScroll.position.pixels;
  await _tapTouchEdge1099(tester, viewProbe);
  await tester.pumpAndSettle();
  expect(find.byType(TodoScreen), findsOneWidget);
  expect(find.byType(TodoScreen, skipOffstage: false), findsOneWidget);
  Navigator.of(tester.element(find.byType(TodoScreen))).pop();
  await tester.pumpAndSettle();
  expect(tester.element(page), same(oldElement));
  expect(ModalRoute.of(tester.element(page)), same(oldRoute));
  expect(_scrollState(tester, page), same(oldScroll));
  expect(oldScroll.position.pixels, closeTo(oldOffset, .1));
  expect(find.byKey(const ValueKey(
    'today_reminder_todo_$_reminderId',
  )), findsOneWidget);
  expect(todos.deleteRequests, isEmpty);
  expect(todos.scheduleRequests, isEmpty);
  history['viewPushedExactlyOneTodoAndReturnedRetained'] = true;

  history['phase'] = 'swipe';
  var deleteInk = await _openTouchSwipe1099(tester, page);
  final deleteRoot = find.byKey(
    const ValueKey('today_todo_swipe_delete_button'),
  );
  final visual = find.descendant(
    of: deleteRoot,
    matching: find.byWidgetPredicate((widget) =>
      widget is Container &&
      widget.constraints?.minWidth == 38 &&
      widget.constraints?.maxWidth == 38 &&
      widget.constraints?.minHeight == 38 &&
      widget.constraints?.maxHeight == 38),
  );
  final swipeProbe = _touchProbe1099(
    tester, deleteInk, edge: 'right', visual: visual,
  );
  await _save(tester, fixture, '$prefix-swipe', {
    ..._touchState1099(tester, fixture, todos),
    'swipe': swipeProbe, 'history': history,
  });
  _expectTouch1099(swipeProbe);
  expect(swipeProbe['semanticsLabel'], contains(I18n.tr('action.delete')));
  expect(swipeProbe['visualCount'], 1);
  expect(swipeProbe['visualWidth'], 38);
  expect(swipeProbe['visualHeight'], 38);
  expect(swipeProbe['edgeOutsideVisual'], isTrue);
  await _tapTouchEdge1099(tester, swipeProbe);
  await tester.pumpAndSettle();
  expect(find.text(TodayUiCopy.deleteTaskTitle()), findsOneWidget);
  await _touchCancelDelete1099(tester);
  expect(todos.deleteRequests, isEmpty);
  history['outside38VisualEdgeOpenedConfirmationCancelPreservedTodo'] = true;

  history['phase'] = 'stale-origin';
  // Reuse the existing origin-test technique: retain the real production
  // opener, invalidate authority, and verify it never invokes the provider.
  deleteInk = await _openTouchSwipe1099(tester, page);
  final staleOpener = tester.widget<InkWell>(deleteInk).onTap!;
  AccountLocalDataCleaner.invalidateInFlightAccountWrites();
  staleOpener();
  await tester.pumpAndSettle();
  expect(find.text(TodayUiCopy.deleteTaskTitle()), findsNothing);
  expect(todos.deleteRequests, isEmpty);
  history['staleAccountOpenerBlockedBeforeProvider'] = true;

  history['phase'] = 'read-only';
  share.setEditable(false);
  await tester.pumpAndSettle();
  deleteInk = await _openTouchSwipe1099(tester, page);
  final readOnlyProbe = _touchProbe1099(tester, deleteInk, edge: 'right');
  history['readOnlyProbe'] = readOnlyProbe;
  _expectTouch1099(readOnlyProbe);
  await _tapTouchEdge1099(tester, readOnlyProbe);
  await tester.pumpAndSettle();
  expect(find.text(TodayUiCopy.readOnlyActionMessage(
    '删除任务', fixture.locale,
  )), findsOneWidget);
  expect(find.text(TodayUiCopy.deleteTaskTitle()), findsNothing);
  expect(todos.deleteRequests, isEmpty);
  history['readOnlyEdgeDidNotOpenDeleteOrMutate'] = true;
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();

  share.setEditable(true);
  await tester.pumpAndSettle();
  deleteInk = await _openTouchSwipe1099(tester, page);
  await _tapTouchEdge1099(
    tester, _touchProbe1099(tester, deleteInk, edge: 'right'),
  );
  await tester.pumpAndSettle();
  history['phase'] = 'permission-revocation';
  final retainedConfirm = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, I18n.tr('action.delete')),
  ).onPressed!;
  share.setEditable(false);
  await tester.pumpAndSettle();
  retainedConfirm();
  await tester.pumpAndSettle();
  expect(find.text(TodayUiCopy.deleteTaskTitle()), findsOneWidget);
  expect(todos.deleteRequests, isEmpty);
  expect(todos.todos.any((item) => item.id == _reminderId), isTrue);
  await _touchCancelDelete1099(tester);
  history['permissionRevokedConfirmationBlockedBeforeProvider'] = true;
  history['phase'] = 'fresh-delete';

  share.setEditable(true);
  await tester.pumpAndSettle();
  deleteInk = await _openTouchSwipe1099(tester, page);
  await _tapTouchEdge1099(
    tester, _touchProbe1099(tester, deleteInk, edge: 'right'),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(FilledButton, I18n.tr('action.delete')),
  );
  await tester.pumpAndSettle();
  await _touchAwait1127(tester, history['phase'] as String, todos.settleCalls);
  await tester.pumpAndSettle();
  expect(todos.deleteRequests, [_reminderId]);
  expect(todos.todos.any((item) => item.id == _reminderId), isFalse);
  history['freshDeletionCalledRealProviderExactlyOnce'] = true;

  history['phase'] = 'add';
  // Open the real suggestions group through its visible title, then hit the
  // real AddToday button's edge. Do not synthesize a suggestion or invoke
  // the scheduling callback directly.
  final suggestions = find.byKey(
    const ValueKey('today_suggestion_section'),
  );
  await _touchReveal1099(tester, page, suggestions);
  await tester.tap(find.descendant(
    of: suggestions, matching: find.text(I18n.tr('today.suggestions')),
  ));
  await tester.pumpAndSettle();
  final add = find.byKey(
    const ValueKey('today_suggestion_add_$_touchSuggestion1099'),
  );
  await _touchReveal1099(tester, page, add);
  final addProbe = _touchProbe1099(tester, add);
  await _save(tester, fixture, '$prefix-add', {
    ..._touchState1099(tester, fixture, todos),
    'addToday': addProbe, 'history': history,
  });
  _expectTouch1099(addProbe);
  expect(addProbe['semanticsLabel'], contains(I18n.tr('today.add_to_today')));
  expect(addProbe['height'], greaterThanOrEqualTo(44));
  expect(todos.scheduleRequests, isEmpty);
  await _tapTouchEdge1099(tester, addProbe);
  await tester.pumpAndSettle();
  await _touchAwait1127(tester, history['phase'] as String, todos.settleCalls);
  await tester.pumpAndSettle();
  expect(todos.scheduleRequests, hasLength(1));
  expect(todos.scheduleRequests.single['id'], _touchSuggestion1099);
  expect(
    todos.scheduleRequests.single['expectedAccountDataGeneration'],
    AccountLocalDataCleaner.accountDataGeneration,
  );
  expect(todos.scheduleRequests.single['waitForReminderSync'], isTrue);
  final changed = todos.todos.singleWhere(
    (item) => item.id == _touchSuggestion1099,
  );
  final actionNow = DateTime.parse(
    todos.scheduleRequests.single['now'] as String,
  );
  expect(changed.date.year, actionNow.year);
  expect(changed.date.month, actionNow.month);
  expect(changed.date.day, actionNow.day);
  expect(changed.dueDate, isNotNull);
  expect(changed.dueDate!.year, actionNow.year);
  expect(changed.dueDate!.month, actionNow.month);
  expect(changed.dueDate!.day, actionNow.day);
  expect(changed.title, 'Touch add1099');
  expect(changed.workspaceId, _touchWorkspace1099);
  expect(changed.priority, TodoPriority.urgent);
  expect(todos.deleteRequests, [_reminderId]);
  history['addTodayEdgeCalledRealSchedulingOnceAndMovedTodoToToday'] = true;
  history['phase'] = 'complete';
}

class _TrackingStore extends InMemorySharedPreferencesStore {
  _TrackingStore(super.data) : super.withData();
  int mutations = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) {
    mutations++;
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) {
    mutations++;
    return super.remove(key);
  }

  @override
  Future<bool> clear() {
    mutations++;
    return super.clear();
  }
}

Future<void> _save(
  WidgetTester tester,
  _Fixture fixture,
  String name,
  Map<String, Object?> observations,
) async {
  final output = Platform.environment[_outputEnv];
  final repo = Platform.environment[_repoRootEnv1247];
  if ((output == null || output.isEmpty) && (repo == null || repo.isEmpty)) {
    return;
  }
  final directory = _resolveEvidenceDirectory1247(output, name);
  await tester.runAsync(() async {
    final png = File('$directory/$name.png');
    final record = File('$directory/$name.json');
    if (png.existsSync() || record.existsSync()) {
      throw StateError('Refusing to overwrite retained route evidence: $name');
    }
    _assertFreshCaptureFile1247(png.path);
    _assertFreshCaptureFile1247(record.path);
    png.parent.createSync(recursive: true);
    _assertDirectoryPath1247(directory);
    final boundary =
        fixture.boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await picture.toByteData(format: ui.ImageByteFormat.png))!;
      _assertFreshCaptureFile1247(png.path);
      png.writeAsBytesSync(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      picture.dispose();
    }
    _assertFreshCaptureFile1247(record.path);
    record.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(observations)}\n',
    );
  });
}


// Eight added1236 cases. Original1158 tests/helpers are preserved except the
// main-authorized AddToday height oracle: >=44 replaces an exact44 ceiling.
void _registerSuggestionReadability1236() {
  const variants = [
    (name: 'narrow200-standard', size: Size(200, 844), system: false),
    (name: 'narrow320-system', size: Size(320, 568), system: true),
  ];
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in [AppLocale.zh, AppLocale.en]) {
      for (final variant in variants) {
        final prefix = 'today-suggestion-readability-1236-$brand-'
            '${locale.name}-${variant.name}-scale2.0';
        testWidgets(prefix, (tester) async {
          final semantics = tester.ensureSemantics();
          final todos = _TouchTodoProvider1099();
          final share = _TouchShareProvider1099();
          final fixture = _Fixture(
            brand, locale, variant.size,
            accessibilityTypography: variant.system,
            todosOverride: todos, shareOverride: share,
          );
          final history = <String, Object?>{'phase': 'mount'};
          var mounted = false;
          addTearDown(() => fixture.dispose(tester));
          try {
            final now = DateTime.now();
            await fixture.mount(
              tester, withReminder: true,
              reminderOverride: TodoItem(
                id: _reminderId, title: _reminderTitle,
                workspaceId: _touchWorkspace1099,
                date: now.subtract(const Duration(days: 1)),
                dueDate: now.subtract(const Duration(hours: 1)),
              ),
            );
            mounted = true;
            final tomorrow = DateTime(now.year, now.month, now.day + 1);
            history['phase'] = 'seed-real-provider';
            await _touchAwait1127(tester, '1236-seed', () => todos.addTodo(
              TodoItem(
                id: _touchSuggestion1099,
                title: 'Readability suggestion 1236',
                workspaceId: _touchWorkspace1099, date: tomorrow,
                dueDate: tomorrow.add(const Duration(hours: 12)),
                priority: TodoPriority.urgent,
              ),
              // Fixture seeding only. Production AddToday must request sync.
              waitForReminderSync: false,
            ));
            await tester.pumpAndSettle();
            final entry = find.descendant(
              of: find.byType(MoreApplicationsScreen),
              matching: find.byWidgetPredicate((widget) =>
                  widget is MoreApplicationButton && widget.app.tab == 0),
            );
            await Scrollable.ensureVisible(
              tester.element(entry), alignment: .5,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.descendant(
              of: entry,
              matching: find.byKey(
                const ValueKey('more_application_button_tap_region'),
              ),
            ));
            await tester.pumpAndSettle();
            final page = find.byType(TodayScreen);
            final toggle = find.descendant(
              of: page,
              matching: find.byKey(
                const ValueKey('today_reminder_header_toggle'),
              ),
            );
            await _touchReveal1099(tester, page, toggle);
            final chevron = find.descendant(
              of: toggle, matching: find.byIcon(Icons.keyboard_arrow_down),
            );
            expect(chevron, findsOneWidget);
            await tester.tap(chevron);
            await tester.pumpAndSettle();
            expect(find.byKey(
              const ValueKey('today_reminder_todo_$_reminderId'),
            ), findsOneWidget);
            history['phase'] = 'collapsed-header';
            await _suggestionHeaderCapture1236(
              tester, fixture, page, '$prefix-collapsed-header',
              expanded: false,
            );
            await tester.tap(find.descendant(
              of: _suggestionGroup1236(page),
              matching: find.text(I18n.tr('today.suggestions')),
            ));
            await tester.pumpAndSettle();
            history['phase'] = 'expanded-initial';
            await _suggestionHeaderCapture1236(
              tester, fixture, page, '$prefix-initial-header',
              expanded: true,
            );
            await _suggestionActionCapture1236(
              tester, fixture, page, '$prefix-initial-action',
            );
            final oldElement = tester.element(page);
            final oldRoute = ModalRoute.of(oldElement);
            final oldScroll = _scrollState(tester, page);
            final before = _observe(
              tester, fixture, page,
              title: _reminderHeader(page), reminder: true,
            );
            expect(before['pixels'] as double, greaterThan(0));
            final initialGeneration =
                AccountLocalDataCleaner.accountDataGeneration;
            final seededItems = jsonEncode(
              todos.todos.map((todo) => todo.toJson()).toList(),
            );
            history['phase'] = 'mounted-opposite-locale';
            I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
            await tester.pumpAndSettle();
            final switched = _observe(
              tester, fixture, page,
              title: _reminderHeader(page), reminder: true,
            );
            history['oppositeRetention'] = switched;
            _expectRetained(
              tester, fixture, page, oldElement, oldRoute, oldScroll,
              before, switched,
            );
            _expectSuggestionRetained1236(
              page, todos, seededItems, initialGeneration,
            );
            await _suggestionHeaderCapture1236(
              tester, fixture, page, '$prefix-opposite-header',
              expanded: true,
            );
            await _suggestionActionCapture1236(
              tester, fixture, page, '$prefix-opposite-action',
            );
            // Explicit reveals may scroll. Rebase before the locale operation.
            final beforeReturn = _observe(
              tester, fixture, page,
              title: _reminderHeader(page), reminder: true,
            );
            history['phase'] = 'mounted-roundtrip';
            I18n.setLocale(locale);
            await tester.pumpAndSettle();
            final returned = _observe(
              tester, fixture, page,
              title: _reminderHeader(page), reminder: true,
            );
            history['roundtripRetention'] = returned;
            _expectRetained(
              tester, fixture, page, oldElement, oldRoute, oldScroll,
              beforeReturn, returned,
            );
            _expectSuggestionRetained1236(
              page, todos, seededItems, initialGeneration,
            );
            await _suggestionHeaderCapture1236(
              tester, fixture, page, '$prefix-roundtrip-header',
              expanded: true,
            );
            await _suggestionActionCapture1236(
              tester, fixture, page, '$prefix-roundtrip-action',
            );
            history['phase'] = 'stale-account-callback';
            final stale = tester.widget<TextButton>(
              _suggestionAction1236(page),
            ).onPressed!;
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
            stale();
            await tester.pumpAndSettle();
            await _touchAwait1127(
              tester, '1236-stale-settlements', todos.settleCalls,
            );
            expect(todos.scheduleRequests, isEmpty);
            expect(jsonEncode(
              todos.todos.map((todo) => todo.toJson()).toList(),
            ), seededItems);
            history['staleSchedulingBlocked'] = true;
            history['phase'] = 'fresh-edge-scheduling';
            final action = _suggestionAction1236(page);
            await _touchReveal1099(tester, page, action);
            final probe = _touchProbe1099(tester, action, edge: 'right');
            history['freshActionTarget'] = probe;
            _expectTouch1099(probe);
            expect(probe['semanticsLabel'],
                contains(_suggestionCopy1236()['action']));
            final freshGeneration =
                AccountLocalDataCleaner.accountDataGeneration;
            await _tapTouchEdge1099(tester, probe);
            await tester.pumpAndSettle();
            await _touchAwait1127(
              tester, '1236-fresh-scheduling', todos.settleCalls,
            );
            await tester.pumpAndSettle();
            expect(todos.scheduleRequests, hasLength(1));
            final request = todos.scheduleRequests.single;
            expect(request['id'], _touchSuggestion1099);
            expect(request['expectedAccountDataGeneration'], freshGeneration);
            expect(request['waitForReminderSync'], isTrue);
            final actionNow = DateTime.parse(request['now'] as String);
            final changed = todos.todos.singleWhere(
              (todo) => todo.id == _touchSuggestion1099,
            );
            expect(changed.title, 'Readability suggestion 1236');
            expect(changed.workspaceId, _touchWorkspace1099);
            expect(changed.priority, TodoPriority.urgent);
            expect(changed.date.year, actionNow.year);
            expect(changed.date.month, actionNow.month);
            expect(changed.date.day, actionNow.day);
            expect(changed.dueDate, isNotNull);
            expect(changed.dueDate!.year, actionNow.year);
            expect(changed.dueDate!.month, actionNow.month);
            expect(changed.dueDate!.day, actionNow.day);
            expect(todos.deleteRequests, isEmpty);
            expect(tester.element(page), same(oldElement));
            expect(ModalRoute.of(tester.element(page)), same(oldRoute));
            expect(_scrollState(tester, page), same(oldScroll));
            history['realSchedulingMovedTaskExactlyOnce'] = true;
            history['phase'] = 'complete';
            expect(tester.takeException(), isNull);
          } finally {
            try {
              if (mounted) {
                // Preserve actual route/partial history on assertion failures.
                await _save(tester, fixture, '$prefix-terminal', {
                  ..._touchState1099(tester, fixture, todos),
                  'history': history,
                });
              }
            } finally {
              semantics.dispose();
            }
          }
        });
      }
    }
  }
}

Finder _suggestionGroup1236(Finder page) => find.descendant(
  of: page, matching: find.byKey(
    const ValueKey('today_suggestion_section'),
  ),
);

Finder _suggestionAction1236(Finder page) => find.descendant(
  of: _suggestionGroup1236(page), matching: find.byKey(
    const ValueKey('today_suggestion_add_$_touchSuggestion1099'),
  ),
);

// Independent full copy: shortened production resources cannot pass.
Map<String, String> _suggestionCopy1236() => I18n.current == AppLocale.en
    ? {
        'title': 'Today suggestions',
        'subtitle': 'Recommended by due time, priority, and Eisenhower quadrant',
        'collapsed': 'Collapsed by default', 'action': 'Add to today',
        'reason': 'Due tomorrow · Scheduled for tomorrow · Urgent priority',
      }
    : {
        'title': '今日建议', 'subtitle': '根据截止时间、优先级和四象限自动推荐',
        'collapsed': '默认收起', 'action': '加入今日',
        'reason': '明天到期 · 明天计划 · 紧急优先级',
      };

void _expectSuggestionRetained1236(
  Finder page, _TouchTodoProvider1099 todos,
  String seededItems, int generation,
) {
  expect(find.descendant(
    of: page, matching: find.byKey(
      const ValueKey('today_reminder_todo_$_reminderId'),
    ),
  ), findsOneWidget);
  expect(_suggestionAction1236(page), findsOneWidget);
  expect(AccountLocalDataCleaner.accountDataGeneration, generation);
  expect(jsonEncode(todos.todos.map((todo) => todo.toJson()).toList()),
      seededItems);
  expect(todos.deleteRequests, isEmpty);
  expect(todos.scheduleRequests, isEmpty);
}

Future<void> _suggestionHeaderCapture1236(
  WidgetTester tester, _Fixture fixture, Finder page, String name, {
  required bool expanded,
}) async {
  final group = _suggestionGroup1236(page);
  final title = find.descendant(
    of: group, matching: find.text(I18n.tr('today.suggestions')),
  );
  await _touchReveal1099(tester, page, title);
  final actualSubtitle = expanded
      ? I18n.tr('today.suggestions.subtitle')
      : '${I18n.tr('today.suggestions.subtitle')} · '
          '${TodayUiCopy.collapsedByDefault}';
  final subtitle = find.descendant(
    of: group, matching: find.text(actualSubtitle),
  );
  if (subtitle.evaluate().length == 1) {
    await Scrollable.ensureVisible(tester.element(subtitle), alignment: .3);
    await tester.pumpAndSettle();
  }
  final copy = _suggestionCopy1236();
  final theme = Theme.of(tester.element(page));
  final expectedSubtitle = expanded
      ? copy['subtitle']!
      : '${copy['subtitle']} · ${copy['collapsed']}';
  final titleMetrics = _suggestionTextMetrics1236(
    tester, fixture, title, copy['title']!,
    theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14, fontWeight: FontWeight.normal,
    ),
  );
  final subtitleMetrics = _suggestionTextMetrics1236(
    tester, fixture, subtitle, expectedSubtitle, theme.textTheme.bodySmall!,
  );
  await _save(tester, fixture, name, {
    'protocol': 'today-suggestion-readability-1236/v1',
    'role': 'header', 'expanded': expanded,
    ..._observe(tester, fixture, page, title: _reminderHeader(page),
        reminder: true),
    'suggestionTitle': titleMetrics,
    'suggestionSubtitle': subtitleMetrics,
  });
  _expectSuggestionText1236(titleMetrics);
  _expectSuggestionText1236(subtitleMetrics);
  expect(_suggestionAction1236(page).evaluate().length, expanded ? 1 : 0);
  expect(tester.takeException(), isNull);
}

Future<void> _suggestionActionCapture1236(
  WidgetTester tester, _Fixture fixture, Finder page, String name,
) async {
  final action = _suggestionAction1236(page);
  await _touchReveal1099(tester, page, action);
  final label = find.descendant(of: action, matching: find.byType(Text));
  final theme = Theme.of(tester.element(action));
  final expectedStyle = theme.textButtonTheme.style?.textStyle
          ?.resolve(const <WidgetState>{}) ??
      theme.textTheme.labelLarge!;
  final metrics = _suggestionTextMetrics1236(
    tester, fixture, label, _suggestionCopy1236()['action']!,
    expectedStyle, action: action,
  );
  final row = find.descendant(
    of: _suggestionGroup1236(page),
    matching: find.byKey(
      const ValueKey('today_suggestion_todo_$_touchSuggestion1099'),
    ),
  );
  final reason = find.descendant(
    of: row,
    matching: find.text(TodayUiCopy.formatSuggestionReason(
      '明天到期 · 明天计划 · 紧急优先级',
    )),
  );
  final reasonMetrics = _suggestionTextMetrics1236(
    tester, fixture, reason, _suggestionCopy1236()['reason']!,
    const TextStyle(fontSize: 11),
  );
  final probe = _touchProbe1099(tester, action, edge: 'right');
  await _save(tester, fixture, name, {
    'protocol': 'today-suggestion-readability-1236/v1', 'role': 'action',
    ..._observe(tester, fixture, page, title: _reminderHeader(page),
        reminder: true),
    'actionText': metrics, 'actionTarget': probe,
    'suggestionReason': reasonMetrics,
  });
  _expectSuggestionText1236(metrics);
  _expectSuggestionText1236(reasonMetrics);
  _expectTouch1099(probe);
  expect(probe['semanticsLabel'], contains(_suggestionCopy1236()['action']));
  expect(tester.takeException(), isNull);
}

Map<String, double> _suggestionRect1236(Rect rect) => {
  'left': rect.left, 'top': rect.top,
  'right': rect.right, 'bottom': rect.bottom,
};

Map<String, Object?> _suggestionTextMetrics1236(
  WidgetTester tester, _Fixture fixture, Finder label,
  String expected, TextStyle expectedStyle, {
  Finder? action,
}) {
  final record = <String, Object?>{
    'count': label.evaluate().length, 'expected': expected,
    'systemTypography': fixture.accessibilityTypography,
  };
  if (record['count'] != 1) return record;
  final rich = find.descendant(of: label, matching: find.byType(RichText));
  record['paragraphCount'] = rich.evaluate().length;
  if (record['paragraphCount'] != 1) return record;
  final paragraph = tester.renderObject<RenderParagraph>(rich);
  final plain = paragraph.text.toPlainText();
  final media = MediaQuery.of(tester.element(label));
  final referenceStyle = DefaultTextStyle.of(tester.element(label)).style
      .merge(expectedStyle);
  final origin = paragraph.localToGlobal(Offset.zero);
  final xScale = (paragraph.localToGlobal(const Offset(1, 0)) - origin).distance;
  final yScale = (paragraph.localToGlobal(const Offset(0, 1)) - origin).distance;
  final globalRect = MatrixUtils.transformRect(
    paragraph.getTransformTo(null), Offset.zero & paragraph.size,
  );
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: plain.length),
    boxHeightStyle: ui.BoxHeightStyle.tight,
  );
  // Selection boxes include glyph/spacing outsets beyond paragraph line boxes.
  // Only actual paint clips constrain those outsets; a layout rect is not a clip.
  final ancestorClips = <Map<String, Object?>>[];
  RenderObject child = paragraph;
  for (RenderObject? ancestor = child.parent;
      ancestor != null;
      child = ancestor, ancestor = ancestor.parent) {
    final clip = ancestor.describeApproximatePaintClip(child);
    if (clip == null) continue;
    ancestorClips.add({
      'renderType': ancestor.runtimeType.toString(),
      'local': _suggestionRect1236(clip),
      'global': _suggestionRect1236(MatrixUtils.transformRect(
        ancestor.getTransformTo(null), clip,
      )),
    });
  }
  record.addAll({
    'text': plain, 'didExceedMaxLines': paragraph.didExceedMaxLines,
    'paintedWidth': paragraph.textSize.width, 'width': paragraph.size.width,
    'paintedHeight': paragraph.textSize.height, 'height': paragraph.size.height,
    'typography': _renderedTypography(paragraph),
    'expectedBaseFontSize': referenceStyle.fontSize,
    'expectedWeight': fixture.accessibilityTypography
        ? FontWeight.bold.value
        : (referenceStyle.fontWeight ?? FontWeight.normal).value,
    'expectedLetterSpacing': fixture.accessibilityTypography
        ? 2.0 : (referenceStyle.letterSpacing ?? 0.0),
    'expectedWordSpacing': fixture.accessibilityTypography
        ? 3.0 : (referenceStyle.wordSpacing ?? 0.0),
    'media': {
      'boldText': media.boldText,
      'letterSpacingOverride': media.letterSpacingOverride,
      'wordSpacingOverride': media.wordSpacingOverride,
      'scaled10': media.textScaler.scale(10),
    },
    'globalScaleX': xScale, 'globalScaleY': yScale,
    'globalTextRect': _suggestionRect1236(globalRect),
    'ancestorApproximatePaintClips': ancestorClips,
    'viewport': _suggestionRect1236(Offset.zero & fixture.size),
    'contentViewport': _suggestionRect1236(tester.getRect(
      _scrollFinder(find.byType(TodayScreen)),
    )),
    if (action != null)
      'actionRect': _suggestionRect1236(tester.getRect(action)),
    'glyphBoxes': [
      for (final box in boxes) {
        'local': _suggestionRect1236(box.toRect()),
        'global': _suggestionRect1236(MatrixUtils.transformRect(
          paragraph.getTransformTo(null), box.toRect(),
        )),
      },
    ],
    'asciiWords': [
      for (final word in RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)?").allMatches(plain))
        _recordReminderTitleWord(paragraph, word),
    ],
  });
  return record;
}

Rect _suggestionRecordedRect1236(Object? value) {
  final map = value as Map<String, double>;
  return Rect.fromLTRB(
    map['left']!, map['top']!, map['right']!, map['bottom']!,
  );
}

void _expectSuggestionText1236(Map<String, Object?> record) {
  final expected = record['expected'] as String;
  expect(record['count'], 1, reason: 'Missing actual label: $expected');
  expect(record['paragraphCount'], 1);
  expect(record['text'], expected, reason: 'Preserve complete fixed UI copy');
  expect(record['didExceedMaxLines'], isFalse);
  expect(record['paintedWidth'] as double,
      lessThanOrEqualTo((record['width'] as double) + .1));
  expect(record['paintedHeight'] as double,
      lessThanOrEqualTo((record['height'] as double) + .1));
  final typography = record['typography'] as Map<String, Object?>;
  final baseSize = record['expectedBaseFontSize'] as double;
  expect(typography['fontSize'], closeTo(baseSize, .001));
  expect(typography['fontWeight'], record['expectedWeight']);
  // Default nullable spacing and explicit zero have the same rendered meaning.
  // Keep system overrides literal/strict; retain raw nullable evidence above.
  expect(
    record['systemTypography'] == true
        ? typography['letterSpacing']
        : (typography['letterSpacing'] ?? 0.0),
    record['expectedLetterSpacing'],
  );
  expect(
    record['systemTypography'] == true
        ? typography['wordSpacing']
        : (typography['wordSpacing'] ?? 0.0),
    record['expectedWordSpacing'],
  );
  expect(typography['scaled10'], closeTo(20, .001));
  final media = record['media'] as Map<String, Object?>;
  expect(media['scaled10'], closeTo(20, .001));
  if (record['systemTypography'] == true) {
    expect(media['boldText'], isTrue);
    expect(media['letterSpacingOverride'], 2.0);
    expect(media['wordSpacingOverride'], 3.0);
  }
  // A2x TextScaler cannot hide an ancestor FittedBox shrinking actual glyphs.
  expect(record['globalScaleX'], closeTo(1, .001));
  expect(record['globalScaleY'], closeTo(1, .001));
  final ancestorClips =
      (record['ancestorApproximatePaintClips'] as List)
          .cast<Map<String, Object?>>();
  final viewport = _suggestionRecordedRect1236(record['viewport']);
  final contentViewport =
      _suggestionRecordedRect1236(record['contentViewport']);
  final actionRect = record['actionRect'] == null
      ? null : _suggestionRecordedRect1236(record['actionRect']);
  if (actionRect != null) {
    expect(viewport.inflate(.1).contains(actionRect.topLeft), isTrue);
    expect(viewport.inflate(.1).contains(actionRect.bottomRight), isTrue);
    expect(contentViewport.inflate(.1).contains(actionRect.topLeft), isTrue);
    expect(contentViewport.inflate(.1).contains(actionRect.bottomRight), isTrue);
  }
  final glyphs = (record['glyphBoxes'] as List).cast<Map<String, Object?>>();
  expect(glyphs, isNotEmpty, reason: 'Visible glyph boxes required');
  for (final glyph in glyphs) {
    final rect = _suggestionRecordedRect1236(glyph['global']);
    for (final coordinate in [rect.left, rect.top, rect.right, rect.bottom]) {
      expect(coordinate.isFinite, isTrue);
    }
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
    for (final ancestorClip in ancestorClips) {
      final clip = _suggestionRecordedRect1236(ancestorClip['global']);
      expect(clip.inflate(.1).contains(rect.topLeft), isTrue,
          reason: 'Glyph selection starts outside ${ancestorClip['renderType']} clip');
      expect(clip.inflate(.1).contains(rect.bottomRight), isTrue,
          reason: 'Glyph selection ends outside ${ancestorClip['renderType']} clip');
    }
    expect(viewport.inflate(.1).contains(rect.topLeft), isTrue);
    expect(viewport.inflate(.1).contains(rect.bottomRight), isTrue);
    expect(contentViewport.inflate(.1).contains(rect.topLeft), isTrue);
    expect(contentViewport.inflate(.1).contains(rect.bottomRight), isTrue);
    if (actionRect != null) {
      expect(actionRect.inflate(.1).contains(rect.topLeft), isTrue);
      expect(actionRect.inflate(.1).contains(rect.bottomRight), isTrue);
    }
  }
  final words = (record['asciiWords'] as List).cast<Map<String, Object?>>();
  expect(
    words.map((word) => word['word']).toList(),
    RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)?").allMatches(expected)
        .map((word) => word.group(0)).toList(),
  );
  for (final word in words) {
    expect(word['boxes'] as List, isNotEmpty);
    expect(word['lineCount'], 1,
        reason: 'Do not split complete English word: ${word['word']}');
  }
}


// 1247 output authority only; all48 cases and every1236 oracle are unchanged.
const _repoRootEnv1247 = 'DUOYI_MORE_APPS_RETAINED_ROUTE_REPO_ROOT';
const _canonicalRepo1247 = '/home/ubuntu/duoyi';
const _runtimeRelative1247 =
    '.dart_tool/native-busy-acceptance-20261024-v177';
String? _admittedEvidenceDirectory1247;

void _assertDirectoryPath1247(String absolute) {
  if (!absolute.startsWith('/') ||
      absolute.substring(1).split('/').any(
        (part) => part.isEmpty || part == '.' || part == '..',
      )) {
    throw StateError('Noncanonical absolute evidence authority path');
  }
  var current = '';
  for (final part in absolute.substring(1).split('/')) {
    current += '/$part';
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type != FileSystemEntityType.directory &&
        type != FileSystemEntityType.notFound) {
      throw StateError('Symlink or nondirectory evidence authority: $current');
    }
  }
}

String _resolveEvidenceDirectory1247(String? output, String name) {
  final repo = Platform.environment[_repoRootEnv1247];
  if (repo != _canonicalRepo1247) {
    throw StateError(
      '$_repoRootEnv1247 must bind the exact canonical repository root',
    );
  }
  _assertDirectoryPath1247(_canonicalRepo1247);
  if (!Directory(_canonicalRepo1247).existsSync()) {
    throw StateError('Canonical repository root is missing');
  }
  final cwd = Directory.current.path;
  _assertDirectoryPath1247(cwd);
  final actualCwd = Directory.current.resolveSymbolicLinksSync();
  const runtime = '$_canonicalRepo1247/$_runtimeRelative1247';
  if (cwd != actualCwd ||
      (actualCwd != _canonicalRepo1247 && actualCwd != runtime)) {
    throw StateError('Only canonical REPO or exact reused v177 cwd is admitted');
  }
  if (output == null || output.isEmpty ||
      name.isEmpty || name == '.' || name == '..' || name.contains('/')) {
    throw StateError('Empty or noncanonical capture path/stem');
  }

  late String relative;
  late String absolute;
  if (actualCwd == _canonicalRepo1247) {
    // Preserve the original main-root relative evidence contract.
    if (!output.startsWith('evidence/')) {
      throw StateError('REPO cwd requires a relative evidence/ batch path');
    }
    relative = output;
    absolute = '$_canonicalRepo1247/$relative';
  } else {
    // An absolute REPO path is mandatory from v177; never alias its evidence.
    const prefix = '$_canonicalRepo1247/';
    if (!output.startsWith('$_canonicalRepo1247/evidence/')) {
      throw StateError('v177 cwd requires absolute canonical REPO/evidence/');
    }
    relative = output.substring(prefix.length);
    absolute = output;
  }
  final parts = relative.split('/');
  if (parts.length < 3 || parts.first != 'evidence' ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw StateError('Fresh named evidence batch requires canonical segments');
  }
  _assertDirectoryPath1247(absolute);
  final type = FileSystemEntity.typeSync(absolute, followLinks: false);
  if (_admittedEvidenceDirectory1247 == null) {
    if (type != FileSystemEntityType.notFound) {
      throw StateError('Refusing an existing capture batch: $absolute');
    }
    _admittedEvidenceDirectory1247 = absolute;
  } else if (_admittedEvidenceDirectory1247 != absolute ||
      (type != FileSystemEntityType.directory &&
       type != FileSystemEntityType.notFound)) {
    throw StateError('Capture authority changed after fresh-batch admission');
  }
  return absolute;
}

void _assertFreshCaptureFile1247(String absolute) {
  final file = File(absolute);
  _assertDirectoryPath1247(file.parent.path);
  // followLinks:false also refuses a dangling symlink that existsSync misses.
  if (FileSystemEntity.typeSync(absolute, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError('Refusing existing or symlinked capture target: $absolute');
  }
}
