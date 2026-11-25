import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/calendar_day_agenda.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/priority_theme_fixture.dart';

final _day = DateTime(2030, 6, 29);

class _RecordingTimeAudit extends TimeAuditProvider {
  final item = TimeEntry(
    id: 'timed-entry',
    title: 'Work',
    startAt: DateTime(2030, 6, 29, 9),
    endAt: DateTime(2030, 6, 29, 10),
    category: TimeEntryCategory.work,
    source: TimeEntrySource.manual,
    note: 'Preserve note',
  );
  final updates = <TimeEntry>[];

  @override
  List<TimeEntry> get entries => [item];

  @override
  Future<void> update(TimeEntry entry) async => updates.add(entry);
}

class _TimedCalendar extends CalendarProvider {
  @override
  List<CalendarEvent> getEventsForDate(
    DateTime date, {
    Set<CalendarEventType>? activeTypes,
    String? projectKey,
    String? workspaceId,
  }) => [
    CalendarEvent(
      id: 'timed-calendar-entry',
      sourceId: 'timed-entry',
      title: 'Work',
      date: _day,
      time: const TimeOfDay(hour: 9, minute: 0),
      endDate: DateTime(2030, 6, 29, 10),
      type: CalendarEventType.timeEntry,
      color: Colors.orange,
    ),
  ];
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      testWidgets(
        'timed TimeEntry drag remains admitted $brand ${locale.name}',
        (tester) async {
          final audit = _RecordingTimeAudit();
          final originalEntry = jsonEncode(audit.item.toJson());
          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient(
                (_) async => fail('No fixture HTTP allowed'),
              ),
            ),
          );
          await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: const Size(390, 844),
            scale: 2,
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
                ChangeNotifierProvider(create: (_) => CourseProvider()),
                ChangeNotifierProvider(create: (_) => DiaryProvider()),
                ChangeNotifierProvider(create: (_) => TodoProvider()),
                ChangeNotifierProvider<TimeAuditProvider>(create: (_) => audit),
                ChangeNotifierProvider<CalendarProvider>(
                  create: (_) => _TimedCalendar(),
                ),
              ],
              child: BrandRouteSurface(
                remountOnLocaleChange: false,
                child: Scaffold(
                  body: Builder(
                    builder: (context) => CalendarDayAgenda(
                      date: _day,
                      calendarProvider: context.read<CalendarProvider>(),
                    ),
                  ),
                ),
              ),
            ),
          );
          final title = find.byKey(
            const ValueKey('calendar-compact-title-timed-calendar-entry'),
          );
          await tester.ensureVisible(title);
          await tester.pumpAndSettle();
          final gesture = await tester.startGesture(tester.getCenter(title));
          await gesture.moveBy(const Offset(0, 24));
          await tester.pump();
          await gesture.moveBy(const Offset(0, 48));
          await gesture.up();
          await tester.pumpAndSettle();

          expect(audit.updates, hasLength(1));
          final updated = audit.updates.single;
          expect(updated.startAt, DateTime(2030, 6, 29, 9, 30));
          expect(updated.endAt, DateTime(2030, 6, 29, 10, 30));
          expect(updated.durationSeconds, audit.item.durationSeconds);
          expect(updated.id, audit.item.id);
          expect(updated.title, audit.item.title);
          expect(updated.note, audit.item.note);
          expect(updated.category, audit.item.category);
          expect(updated.source, audit.item.source);
          expect(jsonEncode(audit.item.toJson()), originalEntry);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
