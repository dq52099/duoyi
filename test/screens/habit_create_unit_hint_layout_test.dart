// Generated unit hints must remain readable at the user's natural text scale.
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/widgets/habit_unit_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/priority_theme_fixture.dart';
import '../support/habit_create_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';
import '../test_support/recording_reminder_scheduler.dart';

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final layout in priorityLayouts) {
      final name = 'habit-create-unit-$brand-${layout.name}';
      testWidgets(name, (tester) async {
        final scheduler = RecordingReminderScheduler();
        final audit = TimeAuditProvider();
        final habits = HabitProvider()
          ..timeAudit = audit
          ..scheduler = scheduler;
        final boundary = await mountHabitCreateFixture(
          tester,
          habits: habits,
          audit: audit,
          brand: brand,
          locale: AppLocale.en,
          size: layout.size,
          scale: layout.scale,
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          habits.dispose();
          audit.dispose();
        });
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        final form = find.byType(BottomSheet);
        final sheet = tester.element(form);
        final unitHost = find.descendant(
          of: form,
          matching: find.byType(HabitUnitField),
        );
        final unitField = find.descendant(
          of: unitHost,
          matching: find.byType(TextField),
        );
        final controller = tester.widget<TextField>(unitField).controller!;
        final probe = RouteRenderProbe(tester, boundary, name);

        Future<void> hint(String expected, String stage) async {
          expect(
            tester.widget<TextField>(unitField).decoration!.hintText,
            expected,
          );
          expect(
            tester.widget<TextField>(unitField).controller,
            same(controller),
          );
          expect(controller.text, isEmpty);
          await probe.text(
            find.descendant(of: unitHost, matching: find.text(expected)),
            role: stage,
            minimumGeometricScale: .999,
          );
          await probe.capture(stage);
        }

        Future<void> target(String value) async {
          final field = find.descendant(
            of: form,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText ==
                      (I18n.current == AppLocale.en ? 'Daily target' : '每日目标'),
            ),
          );
          await tester.ensureVisible(field);
          await tester.enterText(field, value);
          FocusScope.of(tester.element(field)).unfocus();
          await tester.pumpAndSettle();
        }

        await hint('time', 'default-singular');
        await target('2');
        await hint('times', 'default-plural');
        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
        expect(tester.element(form), same(sheet));
        await hint('次', 'default-chinese');

        final water = find.descendant(
          of: form,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ActionChip &&
                widget.label is Text &&
                ((widget.label as Text).data ?? '').startsWith('每日喝水'),
          ),
        );
        await Scrollable.ensureVisible(tester.element(water), alignment: 0);
        await tester.pumpAndSettle();
        await tester.tap(water);
        await tester.pumpAndSettle();
        await hint('杯', 'water-chinese');
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        await hint('cups', 'water-plural');
        await target('1');
        await hint('cup', 'water-singular');
        expect(tester.element(form), same(sheet));
        Navigator.of(tester.element(unitField)).pop();
        await tester.pumpAndSettle();
        expect(form, findsNothing);
        expect(habits.habits, isEmpty);
        expect(scheduler.habitSyncs, isEmpty);
        await probe.finish();
      });
    }
  }
}
