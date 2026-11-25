// Actual HabitScreen creation sheet with synthetic providers and no save.
import 'package:duoyi/core/habit_templates.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';
import '../support/habit_create_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';
import '../test_support/recording_reminder_scheduler.dart';

class _HabitCreationProbe extends RouteRenderProbe {
  _HabitCreationProbe(super.tester, super.boundary, super.name);

  @override
  Future<void> reveal(Finder finder) async {
    expect(finder, findsOneWidget);
    // Recommendation labels are inside a horizontal list inside the sheet's
    // vertical scroll. Reveal through both viewports before sampling pixels.
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0);
    await tester.pumpAndSettle();
  }
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'habit-create-$brand-${locale.name}-${layout.name}';
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
            locale: locale,
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
          expect(form, findsOneWidget);
          final sheetElement = tester.element(form);
          final probe = _HabitCreationProbe(tester, boundary, name);
          Finder text(String label) =>
              find.descendant(of: form, matching: find.text(label));
          Finder field(String label) => find.descendant(
            of: form,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is TextField && widget.decoration?.labelText == label,
            ),
          );

          Future<void> inspect(String stage, {bool negative = false}) async {
            final english = I18n.current == AppLocale.en;
            await probe.text(
              text(english ? 'Recommended Goals' : '推荐目标'),
              role: '$stage recommendations heading',
              minimumGeometricScale: .999,
            );
            await probe.capture('$stage-recommendations');
            for (final category in HabitTemplates.byCategory.entries) {
              await probe.text(
                text(category.key),
                role: '$stage category',
                minimumGeometricScale: .999,
              );
              // The first recommendation in each horizontal list must retain
              // its complete generated name/frequency at inherited scaling.
              final sample = category.value.first;
              final chip = find.descendant(
                of: form,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is ActionChip &&
                      widget.label is Text &&
                      ((widget.label as Text).data ?? '').startsWith(
                        sample.localizedName,
                      ),
                ),
              );
              expect(chip, findsOneWidget);
              await probe.text(
                find.descendant(of: chip, matching: find.byType(Text)),
                role: '$stage first recommendation',
                minimumGeometricScale: .999,
              );
            }
            for (final label in [
              english ? 'Build habit' : '正向养成',
              english ? 'Avoid habit' : '反向戒除',
            ]) {
              await probe.text(
                text(label),
                role: '$stage habit type',
                minimumGeometricScale: .999,
              );
            }
            await probe.text(
              text(
                english
                    ? 'In-app popups at scheduled times, multiple times supported'
                    : '到点应用内弹出打卡提醒，可添加多个时间（例如每天 8 杯水）',
              ),
              role: '$stage reminder guidance',
              minimumGeometricScale: .999,
            );
            await probe.capture('$stage-reminders');
            await probe.text(
              text(
                negative
                    ? (english
                          ? 'Avoid habits track zero occurrences'
                          : '反向戒除按每日不发生统计')
                    : (english ? 'Off tracks daily streaks' : '关闭时按每日目标连续统计'),
              ),
              role: '$stage daily rule guidance',
              minimumGeometricScale: .999,
            );
          }

          await inspect('initial');
          final initialName = locale == AppLocale.en ? 'Habit name' : '习惯名称';
          final nameField = field(initialName);
          await tester.ensureVisible(nameField);
          await tester.enterText(nameField, 'My authored habit 自定义');
          final controller = tester.widget<TextField>(nameField).controller!;
          final draftValue = controller.value;
          final preferences = await SharedPreferences.getInstance();
          final preferencesBefore = {
            for (final key in preferences.getKeys()) key: preferences.get(key),
          };
          Finder negativeChoice() => find.ancestor(
            of: text(I18n.current == AppLocale.en ? 'Avoid habit' : '反向戒除'),
            matching: find.byType(ChoiceChip),
          );
          await tester.ensureVisible(negativeChoice());
          await tester.tap(negativeChoice());
          await tester.pumpAndSettle();
          expect(tester.widget<ChoiceChip>(negativeChoice()).selected, isTrue);
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          expect(tester.element(form), same(sheetElement));
          final switchedName = field(
            I18n.current == AppLocale.en ? 'Habit name' : '习惯名称',
          );
          expect(
            tester.widget<TextField>(switchedName).controller,
            same(controller),
          );
          expect(controller.value, draftValue);
          expect(tester.widget<ChoiceChip>(negativeChoice()).selected, isTrue);
          await inspect('switched', negative: true);
          expect(habits.habits, isEmpty);
          expect(scheduler.habitSyncs, isEmpty);
          expect({
            for (final key in preferences.getKeys()) key: preferences.get(key),
          }, preferencesBefore);
          Navigator.of(tester.element(switchedName)).pop();
          await tester.pumpAndSettle();
          expect(form, findsNothing);
          expect(habits.habits, isEmpty);
          expect(tester.takeException(), isNull);
          await probe.finish();
        });
      }
    }
  }
}
