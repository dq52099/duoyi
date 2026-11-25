// Real pushed agenda with immutable synthetic local events and no HTTP.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
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
    id: 'axis-alpha',
    title: 'Alpha',
    date: _day,
    time: const TimeOfDay(hour: 9, minute: 0),
    endDate: DateTime(2026, 6, 29, 10),
    type: CalendarEventType.event,
    color: Colors.blue,
  ),
  CalendarEvent(
    id: 'axis-beta',
    title: 'Beta',
    date: _day,
    time: const TimeOfDay(hour: 9, minute: 30),
    endDate: DateTime(2026, 6, 29, 11),
    type: CalendarEventType.event,
    color: Colors.green,
  ),
  for (final name in ['Gamma', 'Delta'])
    CalendarEvent(
      id: 'cards-$name',
      title: name,
      date: _day,
      time: const TimeOfDay(hour: 9, minute: 45),
      endDate: DateTime(2026, 6, 29, 10, 15),
      type: CalendarEventType.event,
      color: Colors.orange,
    ),
  CalendarEvent(
    id: 'cards-short',
    title: 'Short',
    date: _day,
    time: const TimeOfDay(hour: 10, minute: 16),
    endDate: DateTime(2026, 6, 29, 10, 30),
    type: CalendarEventType.event,
    color: Colors.brown,
  ),
  CalendarEvent(
    id: 'cards-touch',
    title: 'Touch',
    date: _day,
    time: const TimeOfDay(hour: 11, minute: 0),
    endDate: DateTime(2026, 6, 29, 11, 30),
    type: CalendarEventType.event,
    color: Colors.teal,
  ),
  CalendarEvent(
    id: 'axis-late',
    title: 'Late',
    date: _day,
    time: const TimeOfDay(hour: 23, minute: 30),
    endDate: DateTime(2026, 6, 30, 0, 15),
    type: CalendarEventType.event,
    color: Colors.purple,
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
    await Scrollable.ensureVisible(tester.element(finder));
    await tester.pumpAndSettle();
  }
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name =
            'calendar-event-cards-$brand-${locale.name}-${layout.name}';
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
          final gridRender = tester.renderObject<RenderBox>(grid);
          Rect rectInGrid(RenderBox render) => MatrixUtils.transformRect(
            render.getTransformTo(gridRender),
            Offset.zero & render.size,
          );
          Finder cardFor(CalendarEvent event) => find.ancestor(
            of: find.byKey(ValueKey('calendar-compact-title-${event.id}')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget.runtimeType.toString() == '_DraggableEventCard',
            ),
          );
          Future<void> reveal(Finder finder) async {
            await Scrollable.ensureVisible(tester.element(finder));
            await tester.pumpAndSettle();
          }

          Future<void> measure(String stage) async {
            final axisTop = rectInGrid(
              tester.renderObject<RenderBox>(
                find
                    .byWidgetPredicate(
                      (widget) =>
                          widget.runtimeType.toString() == '_TimelineHourRow',
                    )
                    .first,
              ),
            ).top;
            final rectangles = <String, Rect>{};
            final geometry = <String, (double, double)>{
              'Alpha': (486, 54),
              'Beta': (513, 81),
              'Gamma': (526.5, 44),
              'Delta': (526.5, 44),
              'Short': (554.4, 44),
              'Touch': (594, 44),
              'Late': (1252, 44),
            };
            // Measure all rectangles at one horizontal scroll position.
            for (final event in _events) {
              final card = cardFor(event);
              expect(card, findsOneWidget);
              final rect = rectInGrid(tester.renderObject<RenderBox>(card));
              rectangles[event.title] = rect;
              final expected = geometry[event.title]!;
              expect(rect.top - axisTop, closeTo(expected.$1, .1));
              expect(rect.height, closeTo(expected.$2, .1));
              expect(rect.width, greaterThan(0));
              probe.rows.add({
                'role': '$stage geometry ${event.title}',
                'top': rect.top - axisTop,
                'height': rect.height,
                'left': rect.left,
                'right': rect.right,
                'width': rect.width,
              });
            }
            for (var i = 0; i < _events.length; i++) {
              for (var j = i + 1; j < _events.length; j++) {
                final a = _events[i].title, b = _events[j].title;
                final intersection = rectangles[a]!.intersect(rectangles[b]!);
                final occluded =
                    intersection.width > .1 && intersection.height > .1;
                probe.rows.add({
                  'role': '$stage pair $a/$b',
                  'occluded': occluded,
                  'intersectionWidth': intersection.width,
                  'intersectionHeight': intersection.height,
                });
                if (occluded) {
                  probe.errors.add('$stage $a/$b cards obscure each other');
                }
              }
            }
            for (final event in _events) {
              final card = cardFor(event);
              final title = find.byKey(
                ValueKey('calendar-compact-title-${event.id}'),
              );
              final time = find.descendant(
                of: card,
                matching: find.text(
                  I18nDateFormat.timeOfDay(
                    hour: event.time!.hour,
                    minute: event.time!.minute,
                  ),
                ),
              );
              for (final entry in [
                ('title', title, 12.0),
                ('time', time, 10.0),
              ]) {
                await reveal(entry.$2);
                await probe.text(
                  entry.$2,
                  role: '$stage ${event.title} ${entry.$1}',
                  contrast: false,
                  minimumGeometricScale: .999,
                );
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(
                    of: entry.$2,
                    matching: find.byType(RichText),
                  ),
                );
                final style = paragraph.text.style!;
                expect(style.fontSize, entry.$3);
                final requested = layout.scale < 0
                    ? const RouteProbeNonlinearScaler()
                    : TextScaler.linear(layout.scale);
                expect(
                  paragraph.textScaler.scale(style.fontSize!),
                  closeTo(requested.scale(entry.$3), .001),
                );
                final render =
                    boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final cardBox = tester.renderObject<RenderBox>(card);
                final cardRect = MatrixUtils.transformRect(
                  cardBox.getTransformTo(render),
                  Offset.zero & cardBox.size,
                );
                final textRect = MatrixUtils.transformRect(
                  paragraph.getTransformTo(render),
                  Offset.zero & paragraph.size,
                );
                final visibleText = textRect.intersect(
                  Offset.zero & render.size,
                );
                final point = Offset(visibleText.center.dx, cardRect.top + 3);
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
                final required = requested.scale(entry.$3) >= 24 ? 3.0 : 4.5;
                probe.rows.last.addAll({
                  'ratio': ratio,
                  'required': required,
                  'foregroundARGB': foreground.toARGB32(),
                  'backgroundARGB': background.toARGB32(),
                  'sampleX': point.dx.floor(),
                  'sampleY': point.dy.floor(),
                });
                if (ratio < required) {
                  probe.errors.add(
                    '$stage ${event.title} ${entry.$1} contrast $ratio below $required',
                  );
                }
              }
              await reveal(title);
              await probe.capture('$stage-${event.title}');
              final titleParagraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: title, matching: find.byType(RichText)),
              );
              final boxes = titleParagraph.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: event.title.length),
              );
              expect(boxes, isNotEmpty);
              final glyphCenter = titleParagraph.localToGlobal(
                boxes.first.toRect().center,
              );
              final receivesTap = tester
                  .hitTestOnBinding(glyphCenter)
                  .path
                  .any((entry) => identical(entry.target, titleParagraph));
              final tapRow = <String, Object?>{
                'role': '$stage tap ${event.title}',
                'hitTestable': receivesTap,
                'expectedEventId': event.id,
              };
              probe.rows.add(tapRow);
              if (!receivesTap) {
                probe.errors.add(
                  '$stage ${event.title} title cannot receive a tap',
                );
              } else {
                await tester.tapAt(glyphCenter);
                await tester.pumpAndSettle();
                final sheet = find.byType(CalendarEventSheet);
                expect(sheet, findsOneWidget);
                expect(
                  tester.widget<CalendarEventSheet>(sheet).event.id,
                  event.id,
                );
                tapRow['openedEventId'] = tester
                    .widget<CalendarEventSheet>(sheet)
                    .event
                    .id;
                Navigator.of(tester.element(sheet)).pop();
                await tester.pumpAndSettle();
              }
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
            expect(liveScrolls[i].position.pixels, closeTo(gridOffsets[i], .1));
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
