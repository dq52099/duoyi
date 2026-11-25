// Input labels must keep their complete copy beside responsive unit fields.
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/habit_create_theme_fixture.dart';
import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';
import '../test_support/recording_reminder_scheduler.dart';

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final layout in priorityLayouts) {
      final name = 'habit-create-target-$brand-${layout.name}';
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
        Finder target() => find.descendant(
          of: form,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText ==
                    (I18n.current == AppLocale.en ? 'Daily target' : '每日目标'),
          ),
        );
        final controller = tester.widget<TextField>(target()).controller!;
        final originalValue = controller.value;
        final probe = RouteRenderProbe(tester, boundary, name);
        for (final stage in ['english', 'chinese', 'english-again']) {
          I18n.setLocale(stage == 'chinese' ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          expect(tester.element(form), same(sheet));
          expect(
            tester.widget<TextField>(target()).controller,
            same(controller),
          );
          expect(controller.value, originalValue);
          for (final label in [
            I18n.current == AppLocale.en ? 'Daily target' : '每日目标',
            I18n.current == AppLocale.en ? 'Unit' : '单位',
          ]) {
            await probe.text(
              find.descendant(of: form, matching: find.text(label)),
              role: '$stage input label',
              contrast: false,
              // Material's built-in floating label transform is 0.75.
              // Preserve that behavior; forbid additional fitting shrink.
              minimumGeometricScale: .749,
            );
          }
          await probe.capture(stage);
        }
        Navigator.of(tester.element(target())).pop();
        await tester.pumpAndSettle();
        expect(form, findsNothing);
        expect(habits.habits, isEmpty);
        expect(scheduler.habitSyncs, isEmpty);
        await probe.finish();
      });
    }
  }
}
