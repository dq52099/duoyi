// Real pushed agenda with immutable synthetic local events and no HTTP.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
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

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'calendar-hour-axis-$brand-${locale.name}-${layout.name}';
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
          final probe = RouteRenderProbe(tester, boundary, name);
          final grid = find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_CalendarDayTimeGrid',
          );
          final stack = find
              .descendant(of: grid, matching: find.byType(Stack))
              .first;
          final stackRender = tester.renderObject<RenderBox>(stack);
          Rect rectInStack(RenderBox render) => MatrixUtils.transformRect(
            render.getTransformTo(stackRender),
            Offset.zero & render.size,
          );

          Future<void> measure(String stage) async {
            double gutter = 0;
            double? firstGutter;
            for (var hour = 0; hour < 24; hour++) {
              final label = '${hour.toString().padLeft(2, '0')}:00';
              final finder = find.descendant(
                of: find.descendant(
                  of: grid,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget.runtimeType.toString() == '_TimelineHourRow',
                  ),
                ),
                matching: find.text(label),
              );
              await probe.text(
                finder,
                role: '$stage hour $hour',
                contrast: false,
                minimumGeometricScale: .999,
              );
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: finder, matching: find.byType(RichText)),
              );
              final local = rectInStack(paragraph);
              gutter = math.max(gutter, local.right);
              firstGutter ??= local.right;
              expect(local.right, closeTo(firstGutter, .1));
              expect(local.top, closeTo(hour * 54 + 4, .1));
              final naturalWidth = paragraph.getMaxIntrinsicWidth(
                double.infinity,
              );
              final row = probe.rows.last;
              row['naturalSingleLineWidth'] = naturalWidth;
              row['allocatedWidth'] = paragraph.size.width;
              if (naturalWidth > paragraph.size.width + .1) {
                probe.errors.add(
                  '$stage $label wraps or clips at natural scaling',
                );
              }

              // Sample inside the grid's blank gutter gap, above the hour rule
              // and left of any event card (whose leading gap is at least 8px).
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final visible = MatrixUtils.transformRect(
                paragraph.getTransformTo(render),
                Offset.zero & paragraph.size,
              );
              final point = Offset(visible.right + 3, visible.top + 2);
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
              final style = paragraph.text.style!;
              final requestedScaler = layout.scale < 0
                  ? const RouteProbeNonlinearScaler()
                  : TextScaler.linear(layout.scale);
              expect(style.fontSize, 10);
              final expectedFontSize = requestedScaler.scale(10);
              final actualFontSize = paragraph.textScaler.scale(
                style.fontSize!,
              );
              expect(actualFontSize, closeTo(expectedFontSize, .001));
              row.addAll({
                'actualFontSize': actualFontSize,
                'expectedFontSize': expectedFontSize,
                'gutterRight': local.right,
              });
              final foreground = style.foreground?.color ?? style.color!;
              final a = Color.alphaBlend(
                foreground,
                background!,
              ).computeLuminance();
              final b = background.computeLuminance();
              final ratio = (math.max(a, b) + .05) / (math.min(a, b) + .05);
              final fontSize = MediaQuery.textScalerOf(
                tester.element(finder),
              ).scale(style.fontSize!);
              final required = fontSize >= 24 ? 3.0 : 4.5;
              row.addAll({
                'ratio': ratio,
                'required': required,
                'renderedFontSize': fontSize,
                'backgroundARGB': background.toARGB32(),
                'foregroundARGB': foreground.toARGB32(),
                'sampleX': point.dx.floor(),
                'sampleY': point.dy.floor(),
              });
              if (ratio < required) {
                probe.errors.add(
                  '$stage $label contrast $ratio below $required',
                );
              }
              if ([0, 12, 23].contains(hour)) {
                await probe.capture('$stage-hour-$hour');
              }
            }
            final geometry = <String, (double, double)>{
              'Alpha': (486, 54),
              'Beta': (513, 81),
              'Late': (1252, 44),
            };
            for (final entry in geometry.entries) {
              final card = find.ancestor(
                of: find.descendant(of: grid, matching: find.text(entry.key)),
                matching: find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_DraggableEventCard',
                ),
              );
              expect(card, findsOneWidget);
              final rect = rectInStack(tester.renderObject<RenderBox>(card));
              expect(rect.top, closeTo(entry.value.$1, .1));
              expect(rect.height, closeTo(entry.value.$2, .1));
              // The separate card fixture now proves non-occluding lanes.
              // Keep the axis gap and original vertical geometry here.
              expect(rect.left - gutter, greaterThanOrEqualTo(7.9));
              if (entry.key != 'Beta') {
                expect(rect.left - gutter, closeTo(8, .1));
              }
              expect(rect.width, greaterThan(0));
              probe.rows.add({
                'role': '$stage event ${entry.key}',
                'top': rect.top,
                'height': rect.height,
                'left': rect.left,
                'gutter': gutter,
                'width': rect.width,
              });
            }
          }

          await measure('initial');
          scrollState.position.jumpTo(300);
          await tester.pumpAndSettle();
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          expect(tester.element(agenda), same(element));
          expect(tester.state<ScrollableState>(scrolling), same(scrollState));
          expect(scrollState.position.pixels, closeTo(300, .1));
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
