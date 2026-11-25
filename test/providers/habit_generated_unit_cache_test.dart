import 'package:duoyi/core/calendar_event_display_text.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  final createdAt = DateTime.utc(2026, 10, 1, 8);
  final updatedAt = DateTime.utc(2026, 10, 10, 9);

  Habit source() => Habit(
    id: 'generated-unit-cache',
    name: 'Water habit',
    targetCount: 2,
    completions: const {'2026-10-11': 1},
    completionUpdatedAt: {'2026-10-11': DateTime.utc(2026, 10, 11, 10)},
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  void rebuild(CalendarProvider provider, Habit habit) =>
      provider.rebuild(const [], [habit], const [], const ColorScheme.light());

  test(
    'generated unit key transitions refresh cached habit display metadata',
    () {
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      final original = source();
      rebuild(provider, original);
      I18n.setLocale(AppLocale.en);

      var event = provider.events.single;
      expect(event.subtitle, '1 次 / 2 次');
      expect(
        CalendarEventDisplayText.resolveSubtitle(event),
        '1 time / 2 times',
      );
      expect(_habitMetadata(event).generatedUnitKey, isNull);

      var notifications = 0;
      var expectedNotifications = 0;
      provider.addListener(() => notifications++);
      var previousRawSubtitle = event.subtitle;

      for (final key in const <String?>['cup', 'future-unit', null]) {
        final updated = original.copyWith(
          generatedUnitKey: key,
          clearGeneratedUnitKey: key == null,
          updatedAt: original.updatedAt,
        );

        // The generated key is the only persisted habit field that changes.
        expect(
          _payloadWithoutGeneratedUnit(updated),
          _payloadWithoutGeneratedUnit(original),
        );
        expect(updated.name, original.name);
        expect(updated.updatedAt, original.updatedAt);
        expect(updated.completions, original.completions);
        expect(updated.completionUpdatedAt, original.completionUpdatedAt);

        rebuild(provider, updated);
        expectedNotifications++;
        expect(notifications, expectedNotifications);

        event = provider.events.single;
        final metadata = _habitMetadata(event);
        expect(metadata.generatedUnitKey, key);
        expect(metadata.count, 1);
        expect(metadata.targetCount, 2);
        expect(metadata.unit, isNull);

        final expectedRawSubtitle = key == 'cup' ? '1 杯 / 2 杯' : '1 次 / 2 次';
        final expectedEnglishSubtitle = key == 'cup'
            ? '1 cup / 2 cups'
            : '1 time / 2 times';
        expect(event.subtitle, expectedRawSubtitle);
        expect(
          CalendarEventDisplayText.resolveSubtitle(event),
          expectedEnglishSubtitle,
        );
        if (key == null) {
          // Unknown and absent keys have the same Chinese fallback text, while
          // the cache must still replace the unknown key in display metadata.
          expect(event.subtitle, previousRawSubtitle);
        }
        previousRawSubtitle = event.subtitle;
      }
    },
  );

  test(
    'locale-only subtitle resolution does not notify or change event JSON',
    () {
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      final habit = source().copyWith(
        generatedUnitKey: 'cup',
        updatedAt: updatedAt,
      );
      rebuild(provider, habit);
      final event = provider.events.single;
      final beforeJson = event.toJson();
      var notifications = 0;
      provider.addListener(() => notifications++);

      I18n.setLocale(AppLocale.en);
      expect(CalendarEventDisplayText.resolveSubtitle(event), '1 cup / 2 cups');
      expect(event.toJson(), beforeJson);
      expect(notifications, 0);

      I18n.setLocale(AppLocale.zh);
      expect(CalendarEventDisplayText.resolveSubtitle(event), '1 杯 / 2 杯');
      expect(event.toJson(), beforeJson);
      expect(notifications, 0);
    },
  );
}

HabitDisplayMetadata _habitMetadata(CalendarEvent event) {
  expect(event.displayMetadata, isA<HabitDisplayMetadata>());
  return event.displayMetadata! as HabitDisplayMetadata;
}

Map<String, dynamic> _payloadWithoutGeneratedUnit(Habit habit) {
  return Map<String, dynamic>.from(habit.toJson())..remove('generatedUnitKey');
}
