import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/calendar_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CalendarProvider rebuilds habit events when only unit changes', () {
    final provider = CalendarProvider();
    final colorScheme = const ColorScheme.light();
    final habit = Habit(
      id: 'drink-water',
      name: '喝水',
      targetCount: 2,
      unit: '次',
      completions: const {'2026-05-12': 1},
    );

    provider.rebuild(const [], [habit], const [], colorScheme);
    expect(
      provider.events
          .singleWhere((e) => e.type == CalendarEventType.habit)
          .subtitle,
      '1 次 / 2 次',
    );

    provider.rebuild(
      const [],
      [habit.copyWith(unit: '杯')],
      const [],
      colorScheme,
    );

    expect(
      provider.events
          .singleWhere((e) => e.type == CalendarEventType.habit)
          .subtitle,
      '1 杯 / 2 杯',
    );
  });
}
