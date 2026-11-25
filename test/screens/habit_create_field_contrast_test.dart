// Real creation-sheet input labels, including native floating transforms.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/habit_create_theme_fixture.dart';
import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';
import '../test_support/recording_reminder_scheduler.dart';

class _FieldLabelProbe extends RouteRenderProbe {
  _FieldLabelProbe(super.tester, super.boundary, super.name);

  Future<void> label(Finder finder, String role) async {
    await text(
      finder,
      role: role,
      contrast: false,
      minimumGeometricScale: .749,
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)),
    );
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final rect = MatrixUtils.transformRect(
      paragraph.getTransformTo(render),
      Offset.zero & paragraph.size,
    );
    final point = Offset(rect.left - 3, rect.center.dy);
    final background = await tester.runAsync(() async {
      final picture = await render.toImage(pixelRatio: 1);
      try {
        final bytes = (await picture.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final x = point.dx.floor(), y = point.dy.floor();
        expect(x, inInclusiveRange(0, picture.width - 1));
        expect(y, inInclusiveRange(0, picture.height - 1));
        final offset = (y * picture.width + x) * 4;
        return Color.fromARGB(
          255,
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      } finally {
        picture.dispose();
      }
    });
    final style = paragraph.text.style!;
    final foreground = style.foreground?.color ?? style.color!;
    final a = Color.alphaBlend(foreground, background!).computeLuminance();
    final b = background.computeLuminance();
    final ratio = (math.max(a, b) + .05) / (math.min(a, b) + .05);
    final geometricScale = rect.height / paragraph.size.height;
    final paintedFontSize =
        paragraph.textScaler.scale(style.fontSize!) * geometricScale;
    final required = paintedFontSize >= 24 ? 3.0 : 4.5;
    rows.last.addAll({
      'foregroundARGB': foreground.toARGB32(),
      'backgroundARGB': background.toARGB32(),
      'sampleX': point.dx.floor(),
      'sampleY': point.dy.floor(),
      'paintedFontSize': paintedFontSize,
      'ratio': ratio,
      'required': required,
    });
    if (ratio < required) {
      errors.add('$role: contrast $ratio below $required');
    }
  }
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final layout in priorityLayouts) {
      final name = 'habit-field-contrast-$brand-${layout.name}';
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
        final sheet = find.byType(BottomSheet);
        final element = tester.element(sheet);
        Finder field(String english, String chinese) => find.descendant(
          of: sheet,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText ==
                    (I18n.current == AppLocale.en ? english : chinese),
          ),
        );
        Finder label(String english, String chinese) => find.descendant(
          of: sheet,
          matching: find.text(I18n.current == AppLocale.en ? english : chinese),
        );
        final probe = _FieldLabelProbe(tester, boundary, name);
        for (final pair in [('Daily target', '每日目标'), ('Unit', '单位')]) {
          await probe.label(label(pair.$1, pair.$2), 'initial ${pair.$1}');
        }
        final retained = <TextEditingController, TextEditingValue>{};
        for (final entry in [
          ('Habit name', '习惯名称', 'Authored habit 自定义'),
          ('Group', '分组', 'Authored group 自定义'),
        ]) {
          final finder = field(entry.$1, entry.$2);
          await tester.ensureVisible(finder);
          await tester.enterText(finder, entry.$3);
          final controller = tester.widget<TextField>(finder).controller!;
          FocusScope.of(tester.element(finder)).unfocus();
          await tester.pumpAndSettle();
          retained[controller] = controller.value;
        }
        for (final stage in ['filled', 'chinese', 'english-again']) {
          I18n.setLocale(stage == 'chinese' ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          for (final pair in [
            ('Habit name', '习惯名称'),
            ('Group', '分组'),
            ('Daily target', '每日目标'),
            ('Unit', '单位'),
          ]) {
            await probe.label(label(pair.$1, pair.$2), '$stage ${pair.$1}');
          }
          await probe.capture(stage);
          expect(tester.element(sheet), same(element));
          for (final entry in retained.entries) {
            expect(entry.key.value, entry.value);
          }
        }
        final unit = field('Unit', '单位');
        final unitController = tester.widget<TextField>(unit).controller!;
        await tester.ensureVisible(unit);
        await tester.tap(unit);
        await tester.pumpAndSettle();
        await probe.label(label('Unit', '单位'), 'focused Unit');
        await probe.capture('focused');
        FocusScope.of(tester.element(unit)).unfocus();
        await tester.pumpAndSettle();
        await probe.label(label('Unit', '单位'), 'unfocused Unit');
        expect(unitController.text, isEmpty);
        expect(tester.widget<TextField>(unit).decoration!.hintText, 'time');
        Navigator.of(tester.element(unit)).pop();
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(habits.habits, isEmpty);
        expect(scheduler.habitSyncs, isEmpty);
        await probe.finish();
      });
    }
  }
}
