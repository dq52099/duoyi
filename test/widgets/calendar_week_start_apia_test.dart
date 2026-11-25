import 'dart:io';

import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/widgets/calendar_week_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Apia Sunday week keeps Friday empty and Saturday selectable',
    (tester) async {
      expect(Platform.environment['TZ'], 'Pacific/Apia');
      expect(DateTime(2011, 12, 30).day, 31);
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      final selections = <DateTime>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarWeekStrip(
              selectedDay: DateTime(2011, 12, 28),
              dateEventTypes: const {},
              calendarProvider: provider,
              firstDayOfWeek: 7,
              onDaySelected: selections.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final absent = find.byKey(const ValueKey('calendar_week_unavailable_5'));
      expect(absent, findsOneWidget);
      expect(tester.widget<Semantics>(absent).properties.enabled, isFalse);
      final saturday = find.descendant(
        of: find.byType(CalendarWeekStrip),
        matching: find.text('31'),
      );
      expect(saturday, findsOneWidget);
      expect(
        tester.getCenter(saturday).dx,
        greaterThan(tester.getCenter(absent).dx),
      );
      await tester.tap(saturday);
      await tester.pump();
      expect(selections, [DateTime(2011, 12, 31)]);
      expect(find.text('30'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: Platform.environment['DUOYI_REQUIRE_APIA'] != '1',
  );
}
