// Real pushed agenda with immutable synthetic local events and no HTTP.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/calendar_event_display_text.dart';
import 'package:duoyi/core/main_ui_copy.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/widgets/calendar_event_sheet.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/calendar_day_agenda.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

final _day = DateTime(2026, 6, 29);
final _events = [
  CalendarEvent(
    id: 'normal',
    title: 'Plan',
    subtitle: 'Room A',
    date: _day,
    time: const TimeOfDay(hour: 8, minute: 0),
    endDate: DateTime(2026, 6, 29, 12),
    type: CalendarEventType.event,
    color: Colors.blue,
  ),
  CalendarEvent(
    id: 'done',
    title: 'Done',
    subtitle: 'Task note',
    date: _day,
    time: const TimeOfDay(hour: 12, minute: 0),
    endDate: DateTime(2026, 6, 29, 16),
    type: CalendarEventType.todo,
    isCompleted: true,
    color: Colors.green,
  ),
  CalendarEvent(
    id: 'overdue',
    title: 'Late',
    subtitle: 'Task note',
    date: _day,
    time: const TimeOfDay(hour: 16, minute: 0),
    endDate: DateTime(2026, 6, 29, 20),
    type: CalendarEventType.todo,
    color: Colors.orange,
  ),
  CalendarEvent(
    id: 'short-done',
    title: 'Done short',
    date: _day,
    time: const TimeOfDay(hour: 21, minute: 0),
    endDate: DateTime(2026, 6, 29, 21, 30),
    type: CalendarEventType.todo,
    isCompleted: true,
    color: Colors.green,
  ),
  CalendarEvent(
    id: 'generated',
    title: '专注 25 分钟',
    date: _day,
    type: CalendarEventType.pomodoro,
    color: Colors.red,
    displayMetadata: const PomodoroDisplayMetadata(minutes: 25),
  ),
  CalendarEvent(
    id: 'authored',
    title: 'Note',
    subtitle: 'Room B',
    date: _day,
    type: CalendarEventType.event,
    color: Colors.teal,
  ),
];

class _SyntheticCalendar extends CalendarProvider {
  @override
  List<CalendarEvent> getEventsForDate(
    DateTime date, {
    Set<CalendarEventType>? activeTypes,
    String? projectKey,
    String? workspaceId,
  }) => [..._events];
}

class _CardRenderProbe extends RouteRenderProbe {
  _CardRenderProbe(super.tester, super.boundary, super.name);

  @override
  Future<void> reveal(Finder finder) async {
    expect(finder, findsOneWidget);
    final card = find.ancestor(
      of: finder,
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_DraggableEventCard',
      ),
    );
    expect(card, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(card), alignment: .5);
    await tester.pumpAndSettle();
    final horizontal = Scrollable.maybeOf(
      tester.element(finder),
      axis: Axis.horizontal,
    );
    if (horizontal != null) {
      await horizontal.position.ensureVisible(
        tester.renderObject(finder),
        alignment: .5,
      );
      await tester.pumpAndSettle();
    }
  }
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name =
            'calendar-agenda-state-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient(
                (_) async => fail('No fixture HTTP allowed'),
              ),
            ),
          );
          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
                ChangeNotifierProvider(create: (_) => CourseProvider()),
                ChangeNotifierProvider(create: (_) => DiaryProvider()),
                ChangeNotifierProvider(create: (_) => TodoProvider()),
                ChangeNotifierProvider<CalendarProvider>(
                  create: (_) => _SyntheticCalendar(),
                ),
              ],
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        key: const ValueKey('open_axis'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => BrandRouteSurface(
                              // Match CalendarScreen's state-preserving
                              // route contract around this leaf fixture.
                              remountOnLocaleChange: false,
                              child: Scaffold(
                                appBar: AppBar(
                                  title: const Text('Synthetic calendar'),
                                ),
                                body: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: AppSurfaceCard(
                                    padding: EdgeInsets.zero,
                                    child: CalendarDayAgenda(
                                      date: _day,
                                      calendarProvider: context
                                          .read<CalendarProvider>(),
                                      horizontalPadding: 8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        child: const Text('Open synthetic agenda'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final prefs = await SharedPreferences.getInstance();
          final beforePrefs = {
            for (final key in prefs.getKeys()) key: prefs.get(key),
          };
          final beforeEvents = _events.map((event) => event.toJson()).toList();
          await tester.tap(find.byKey(const ValueKey('open_axis')));
          await tester.pumpAndSettle();
          final agenda = find.byType(CalendarDayAgenda);
          final element = tester.element(agenda);
          final scrolling = find
              .descendant(of: agenda, matching: find.byType(Scrollable))
              .first;
          final scrollState = tester.state<ScrollableState>(scrolling);
          final probe = _CardRenderProbe(tester, boundary, name);
          final grid = find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_CalendarDayTimeGrid',
          );
          Rect rectInGrid(RenderBox render) => MatrixUtils.transformRect(
            // The lazy list can dispose/recreate the grid after visiting all
            // untimed rows; use the currently mounted render object.
            render.getTransformTo(tester.renderObject<RenderBox>(grid)),
            Offset.zero & render.size,
          );
          Finder cardFor(CalendarEvent event) =>
              find.byWidgetPredicate((widget) {
                if (widget.runtimeType.toString() != '_DraggableEventCard') {
                  return false;
                }
                final dynamic card = widget;
                return (card.event as CalendarEvent).id == event.id;
              });
          Future<void> measure(String stage) async {
            final rowOrigin = rectInGrid(
              tester.renderObject<RenderBox>(
                find
                    .byWidgetPredicate(
                      (widget) =>
                          widget.runtimeType.toString() == '_TimelineHourRow',
                    )
                    .first,
              ),
            ).top;
            for (final event in _events) {
              if (event.time == null) {
                // ListView constructs the untimed children lazily in short
                // landscape windows; enter that section before locating them.
                scrollState.position.jumpTo(
                  scrollState.position.maxScrollExtent,
                );
                await tester.pumpAndSettle();
              }
              final card = cardFor(event);
              expect(card, findsOneWidget);
              if (event.time != null) {
                final rect = rectInGrid(tester.renderObject<RenderBox>(card));
                final top = event.time!.hour * 54.0;
                final height = event.id == 'short-done' ? 44.0 : 216.0;
                expect(rect.top - rowOrigin, closeTo(top, .1));
                expect(rect.height, closeTo(height, .1));
                probe.rows.add({
                  'role': '$stage geometry ${event.id}',
                  'top': rect.top - rowOrigin,
                  'height': rect.height,
                });
              }
              final titleText = CalendarEventDisplayText.resolveTitle(event);
              final title = find.descendant(
                of: card,
                matching: find.text(titleText),
              );
              final compact = event.id == 'short-done';
              final entries = <(String, Finder, double)>[
                ('title', title, compact ? 12 : 13),
                if (CalendarEventDisplayText.resolveSubtitle(event)
                    case final String subtitle)
                  (
                    'subtitle',
                    find.descendant(of: card, matching: find.text(subtitle)),
                    11,
                  ),
                if (event.time != null)
                  (
                    'time',
                    find.descendant(
                      of: card,
                      matching: find.text(
                        I18nDateFormat.timeOfDay(
                          hour: event.time!.hour,
                          minute: event.time!.minute,
                        ),
                      ),
                    ),
                    compact ? 10 : 11,
                  ),
                if (event.id == 'done' || event.id == 'overdue')
                  (
                    'status',
                    find.descendant(
                      of: card,
                      matching: find.text(
                        event.id == 'done'
                            ? MainUiCopy.calendarStatusCompleted
                            : MainUiCopy.calendarStatusOverdue,
                      ),
                    ),
                    10,
                  ),
              ];
              for (final (role, finder, nominal) in entries) {
                await probe.text(
                  finder,
                  role: '$stage ${event.id} $role',
                  contrast: false,
                  minimumGeometricScale: .999,
                );
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(of: finder, matching: find.byType(RichText)),
                );
                final style = paragraph.text.style!;
                final requested = layout.scale < 0
                    ? const RouteProbeNonlinearScaler()
                    : TextScaler.linear(layout.scale);
                expect(style.fontSize, nominal);
                expect(
                  paragraph.textScaler.scale(nominal),
                  closeTo(requested.scale(nominal), .001),
                );
                if (role == 'title') {
                  expect(
                    style.decoration == TextDecoration.lineThrough,
                    event.isCompleted,
                  );
                }
                if (role == 'title' || role == 'status') {
                  // Short authored/generated English words must wrap at word
                  // boundaries instead of breaking beside a state badge.
                  final splitWords = <String>[];
                  for (final word in RegExp(
                    r'[A-Za-z]+',
                  ).allMatches(paragraph.text.toPlainText())) {
                    final boxes = paragraph.getBoxesForSelection(
                      TextSelection(
                        baseOffset: word.start,
                        extentOffset: word.end,
                      ),
                    );
                    if (boxes
                            .map((box) => (box.top * 10).round())
                            .toSet()
                            .length >
                        1) {
                      splitWords.add(word.group(0)!);
                    }
                  }
                  probe.rows.last['splitWords'] = splitWords;
                  if (splitWords.isNotEmpty) {
                    probe.errors.add(
                      '$stage ${event.id} $role splits words $splitWords',
                    );
                  }
                }
                final render =
                    boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final paragraphRect = MatrixUtils.transformRect(
                  paragraph.getTransformTo(render),
                  Offset.zero & paragraph.size,
                );
                // Blank spacing above each paragraph is inside the card;
                // status pills supply their own6px leading padding sample.
                final point = role == 'status'
                    ? Offset(paragraphRect.left - 3, paragraphRect.center.dy)
                    : Offset(paragraphRect.center.dx, paragraphRect.top - 2);
                final background = await tester.runAsync(() async {
                  final img = await render.toImage(pixelRatio: 1);
                  try {
                    final bytes = (await img.toByteData(
                      format: ui.ImageByteFormat.rawRgba,
                    ))!;
                    final x = point.dx.floor(), y = point.dy.floor();
                    expect(x, inInclusiveRange(0, img.width - 1));
                    expect(y, inInclusiveRange(0, img.height - 1));
                    final offset = (y * img.width + x) * 4;
                    return Color.fromARGB(
                      255,
                      bytes.getUint8(offset),
                      bytes.getUint8(offset + 1),
                      bytes.getUint8(offset + 2),
                    );
                  } finally {
                    img.dispose();
                  }
                });
                final foreground = style.foreground?.color ?? style.color!;
                final a = Color.alphaBlend(
                  foreground,
                  background!,
                ).computeLuminance();
                final b = background.computeLuminance();
                final ratio = (math.max(a, b) + .05) / (math.min(a, b) + .05);
                final required = requested.scale(nominal) >= 24 ? 3.0 : 4.5;
                probe.rows.last.addAll({
                  'ratio': ratio,
                  'required': required,
                  'foregroundARGB': foreground.toARGB32(),
                  'backgroundARGB': background.toARGB32(),
                  'sampleX': point.dx.floor(),
                  'sampleY': point.dy.floor(),
                  'nominalFontSize': nominal,
                  'actualFontSize': paragraph.textScaler.scale(nominal),
                });
                if (ratio < required) {
                  probe.errors.add(
                    '$stage ${event.id} $role contrast $ratio below $required',
                  );
                }
              }
              await probe.reveal(title);
              await probe.capture('$stage-${event.id}');
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: title, matching: find.byType(RichText)),
              );
              final boxes = paragraph.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: titleText.length),
              );
              expect(boxes, isNotEmpty);
              final point = paragraph.localToGlobal(
                boxes.first.toRect().center,
              );
              expect(
                tester
                    .hitTestOnBinding(point)
                    .path
                    .any((entry) => identical(entry.target, paragraph)),
                isTrue,
              );
              await tester.tapAt(point);
              await tester.pumpAndSettle();
              final sheet = find.byType(CalendarEventSheet);
              expect(sheet, findsOneWidget);
              expect(
                tester.widget<CalendarEventSheet>(sheet).event.id,
                event.id,
              );
              await probe.capture('$stage-${event.id}-detail');
              expect(tester.takeException(), isNull);
              final actions = find.descendant(
                of: sheet,
                matching: find.byType(FilledButton),
              );
              expect(actions, findsWidgets);
              for (var i = 0; i < actions.evaluate().length; i++) {
                await Scrollable.ensureVisible(tester.element(actions.at(i)));
                await tester.pumpAndSettle();
                expect(actions.at(i).hitTestable(), findsOneWidget);
              }
              probe.rows.add({
                'role': '$stage tap ${event.id}',
                'eventId': event.id,
                'reachableActionCount': actions.evaluate().length,
              });
              Navigator.of(tester.element(sheet)).pop();
              await tester.pumpAndSettle();
            }
          }

          await measure('initial');
          scrollState.position.jumpTo(300);
          await tester.pumpAndSettle();
          final gridScrolls = find
              .descendant(of: grid, matching: find.byType(Scrollable))
              .evaluate()
              .map(
                (element) =>
                    (element as StatefulElement).state as ScrollableState,
              )
              .toList();
          for (final state in gridScrolls) {
            if (state.position.maxScrollExtent > 0) {
              state.position.jumpTo(
                math.min(20, state.position.maxScrollExtent),
              );
            }
          }
          await tester.pumpAndSettle();
          final gridOffsets = [
            for (final state in gridScrolls) state.position.pixels,
          ];
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          expect(tester.element(agenda), same(element));
          expect(tester.state<ScrollableState>(scrolling), same(scrollState));
          expect(scrollState.position.pixels, closeTo(300, .1));
          final liveScrolls = find
              .descendant(of: grid, matching: find.byType(Scrollable))
              .evaluate()
              .map(
                (element) =>
                    (element as StatefulElement).state as ScrollableState,
              )
              .toList();
          expect(liveScrolls.length, gridScrolls.length);
          for (var i = 0; i < gridScrolls.length; i++) {
            expect(liveScrolls[i], same(gridScrolls[i]));
            final expectedOffset = gridOffsets[i].clamp(
              liveScrolls[i].position.minScrollExtent,
              liveScrolls[i].position.maxScrollExtent,
            );
            expect(liveScrolls[i].position.pixels, closeTo(expectedOffset, .1));
          }
          await measure('live');
          expect(_events.map((event) => event.toJson()).toList(), beforeEvents);
          expect({
            for (final key in prefs.getKeys()) key: prefs.get(key),
          }, beforePrefs);
          await probe.finish();
        });
      }
    }
  }
}
