import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/widgets/calendar_event_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.en);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final start in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
    for (final editing in [false, true]) {
      testWidgets(
        '${editing ? 'edited' : 'new'} all-day event retains local midnight across ${start.month} DST boundary',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1100);
          tester.view.devicePixelRatio = 1;
          final end = DateTime(start.year, start.month, start.day + 1);
          if (Platform.environment['DUOYI_REQUIRE_DST'] == '1') {
            expect(start.timeZoneOffset, isNot(end.timeZoneOffset));
          }
          final provider = CalendarProvider();
          final original = CalendarEvent(
            id: 'dst-event',
            title: 'Synthetic all-day event',
            date: start,
            endDate: end,
            type: CalendarEventType.event,
            color: Colors.blue,
          );
          if (editing) await provider.addLocalEvent(original);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            provider.dispose();
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          await tester.pumpWidget(
            ChangeNotifierProvider<CalendarProvider>.value(
              value: provider,
              child: MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder: (context) => FilledButton(
                      onPressed: () => showLocalCalendarEventEditor(
                        context,
                        initialDate: start,
                        event: editing ? original : null,
                      ),
                      child: const Text('Open editor'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open editor'));
          await tester.pumpAndSettle();
          expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
          final endTile = tester.widget<ListTile>(
            find.widgetWithText(ListTile, 'End date'),
          );
          expect((endTile.subtitle! as Text).data, I18nDateFormat.date(start));
          await tester.enterText(
            find.widgetWithText(TextField, 'Event title'),
            'Saved all-day event',
          );
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
          await tester.pumpAndSettle();
          final saved = provider.localEvents.single;
          expect(saved.date, start);
          expect(saved.endDate, end);
          expect(saved.endDate!.hour, 0);
          expect(saved.time, isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
