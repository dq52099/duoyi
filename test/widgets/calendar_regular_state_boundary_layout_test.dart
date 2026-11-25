import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/main_ui_copy.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:provider/provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/calendar_day_agenda.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

class _BoundaryCalendar extends CalendarProvider {
  _BoundaryCalendar(this.event);
  final CalendarEvent event;

  @override
  List<CalendarEvent> getEventsForDate(
    DateTime date, {
    Set<CalendarEventType>? activeTypes,
    String? projectKey,
    String? workspaceId,
  }) => [event];
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final scale in [1.0, 2.0]) {
      final name = 'calendar-regular-state-boundary-$brand-$scale';
      testWidgets(name, (tester) async {
        final day = DateTime(2026, 6, 29);
        final event = CalendarEvent(
          id: 'boundary',
          title: List.filled(50, 'Long completed event title').join(' '),
          subtitle: 'Task note',
          date: day,
          time: const TimeOfDay(hour: 12, minute: 0),
          endDate: DateTime(2026, 6, 29, scale == 1 ? 14 : 15),
          type: CalendarEventType.todo,
          isCompleted: true,
          color: Colors.green,
        );
        final calendar = _BoundaryCalendar(event);
        addTearDown(calendar.dispose);
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
          locale: AppLocale.en,
          size: const Size(320, 844),
          scale: scale,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
              ChangeNotifierProvider(create: (_) => CourseProvider()),
              ChangeNotifierProvider(create: (_) => DiaryProvider()),
              ChangeNotifierProvider(create: (_) => TodoProvider()),
            ],
            child: BrandRouteSurface(
              remountOnLocaleChange: false,
              child: Scaffold(
                body: AppSurfaceCard(
                  padding: EdgeInsets.zero,
                  child: CalendarDayAgenda(
                    date: day,
                    calendarProvider: calendar,
                  ),
                ),
              ),
            ),
          ),
        );
        final status = find.text(MainUiCopy.calendarStatusCompleted);
        expect(status, findsOneWidget);
        expect(
          find.byKey(const ValueKey('calendar-compact-title-boundary')),
          findsNothing,
        );
        await Scrollable.ensureVisible(tester.element(status), alignment: .5);
        await tester.pumpAndSettle();
        final card = find.ancestor(
          of: status,
          matching: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_DraggableEventCard',
          ),
        );
        expect(
          tester.getSize(card).height,
          closeTo(scale == 1 ? 108 : 162, .1),
        );
        final probe = RouteRenderProbe(tester, boundary, name);
        await probe.capture('long-title-minimum-regular-height');
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(card).contains(tester.getRect(status).center),
          isTrue,
        );
      });
    }
  }
}
