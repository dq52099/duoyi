import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/widgets/calendar_month_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppLocale originalLocale;

  setUp(() {
    originalLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    I18n.setLocale(originalLocale);
  });

  testWidgets(
    'UTC month grid keeps December 30 and 31 as separate selectable days',
    (tester) async {
      expect(Platform.environment['TZ'], 'UTC');
      expect(DateTime(2011, 12, 30).day, 30);

      final selectedDays = <DateTime>[];
      await _pumpMonthGrid(
        tester,
        focusedMonth: DateTime(2011, 12),
        selectedDay: DateTime(2011, 12, 29),
        dateEventCounts: const <String, int>{'2011-12-30': 2, '2011-12-31': 3},
        onDaySelected: selectedDays.add,
      );

      expect(find.text('30'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
      expect(_dayLabels(tester, '2011年12月30日'), hasLength(1));
      expect(_dayLabels(tester, '2011年12月31日'), hasLength(1));

      await tester.tap(find.text('30'));
      await tester.pump();
      expect(selectedDays, hasLength(1));
      expect(_sameCivilDay(selectedDays.single, 2011, 12, 30), isTrue);

      await tester.tap(find.text('31'));
      await tester.pump();
      expect(selectedDays, hasLength(2));
      expect(_sameCivilDay(selectedDays.last, 2011, 12, 31), isTrue);
    },
    skip: _skipUnlessZone(zone: 'UTC', requireVariable: 'DUOYI_REQUIRE_UTC'),
  );

  testWidgets(
    'Apia skipped December 30 keeps its slot empty and does not borrow December 31',
    (tester) async {
      expect(Platform.environment['TZ'], 'Pacific/Apia');
      expect(DateTime(2011, 12, 29).day, 29);
      expect(
        DateTime(2011, 12, 30).day,
        isNot(30),
        reason: 'Pacific/Apia skipped this local civil day.',
      );
      expect(DateTime(2011, 12, 31).day, 31);

      final selectedDays = <DateTime>[];
      await _pumpMonthGrid(
        tester,
        focusedMonth: DateTime(2011, 12),
        selectedDay: DateTime(2011, 12, 29),
        dateEventCounts: const <String, int>{'2011-12-31': 2},
        onDaySelected: selectedDays.add,
      );

      // A missing date may be drawn as an inert placeholder or left blank.
      // If the numeral is drawn, tapping it must not select the normalized
      // December 31 neighbor.
      final gridRect = tester.getRect(find.byType(CalendarMonthGrid));
      const horizontalPadding = 12.0;
      final contentLeft = gridRect.left + horizontalPadding;
      final contentWidth = gridRect.width - horizontalPadding * 2;
      final skippedDayText = find.text('30');
      if (skippedDayText.evaluate().isNotEmpty) {
        final fridayCenter = contentLeft + contentWidth * (4.5 / 7);
        expect(
          tester.getRect(skippedDayText.first).center.dx,
          closeTo(fridayCenter, 2),
        );
        await tester.tap(skippedDayText.first);
        await tester.pump();
      }
      expect(selectedDays, isEmpty);

      // The real December 31 stays in Saturday's column and is the only cell
      // carrying December 31's event metadata.
      expect(find.text('31'), findsOneWidget);
      final day31Labels = _dayLabels(tester, '2011年12月31日');
      expect(day31Labels, hasLength(1));
      expect(day31Labels.single, contains('2 个事项'));

      final day31Rect = tester.getRect(find.text('31'));
      final saturdayCenter = contentLeft + contentWidth * (5.5 / 7);
      expect(day31Rect.center.dx, closeTo(saturdayCenter, 2));

      await tester.tap(find.text('31'));
      await tester.pump();
      expect(selectedDays, hasLength(1));
      expect(_sameCivilDay(selectedDays.single, 2011, 12, 31), isTrue);
      expect(selectedDays.single.isUtc, isFalse);
    },
    skip: _skipUnlessZone(
      zone: 'Pacific/Apia',
      requireVariable: 'DUOYI_REQUIRE_APIA',
    ),
  );
}

bool _skipUnlessZone({required String zone, required String requireVariable}) {
  if (Platform.environment['TZ'] == zone ||
      Platform.environment[requireVariable] == '1') {
    return false;
  }
  return true;
}

Future<void> _pumpMonthGrid(
  WidgetTester tester, {
  required DateTime focusedMonth,
  required DateTime selectedDay,
  required Map<String, int> dateEventCounts,
  required ValueChanged<DateTime> onDaySelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 700,
            height: 480,
            child: CalendarMonthGrid(
              focusedMonth: focusedMonth,
              selectedDay: selectedDay,
              dateEventTypes: const <String, List<CalendarEventType>>{},
              dateEventCounts: dateEventCounts,
              onDaySelected: onDaySelected,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _dayLabels(WidgetTester tester, String dateText) {
  return tester
      .widgetList<Semantics>(find.byType(Semantics))
      .map((semantics) => semantics.properties.label)
      .whereType<String>()
      .where((label) => label.contains(dateText))
      .toList();
}

bool _sameCivilDay(DateTime value, int year, int month, int day) =>
    value.year == year && value.month == month && value.day == day;
