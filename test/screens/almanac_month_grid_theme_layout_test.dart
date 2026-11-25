import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/almanac_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/almanac_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

class _GridProbe extends RouteRenderProbe {
  _GridProbe(super.tester, super.boundary, super.name);

  @override
  Future<void> reveal(Finder finder) async {
    expect(finder, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await tester.pumpAndSettle();
  }

  void frameworkErrors(String stage) {
    Object? error;
    while ((error = tester.takeException()) != null) {
      errors.add('$stage: $error');
    }
  }

  Future<void> measure(
    Finder group,
    String role, {
    bool singleText = false,
    bool calendarCell = false,
  }) async {
    await reveal(group);
    final repaint =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    Rect imageRect(RenderBox box) => MatrixUtils.transformRect(
      box.getTransformTo(repaint),
      Offset.zero & box.size,
    );
    final cellRect = imageRect(tester.renderObject<RenderBox>(group));
    final texts =
        (singleText
                ? group
                : find.descendant(of: group, matching: find.byType(Text)))
            .evaluate()
            .map((element) => element.widget as Text)
            .toList();
    expect(texts, isNotEmpty);
    if (calendarCell) {
      final civilDay = role.split(' ').last;
      int roleOrder(Text text) {
        if (text.data == civilDay) return 0;
        if (text.data == AlmanacUiCopy.holidayTag ||
            text.data == AlmanacUiCopy.makeupWorkdayTag) {
          return 2;
        }
        if (RegExp(r'^\+\d+$').hasMatch(text.data!)) return 3;
        return 1;
      }

      expect(texts.where((text) => roleOrder(text) == 0), hasLength(1));
      expect(texts.where((text) => roleOrder(text) == 1), hasLength(1));
      texts.sort((a, b) => roleOrder(a).compareTo(roleOrder(b)));
    }
    final paragraphs = <RenderParagraph>[];
    final originals = <InlineSpan>[];
    final pending = <Map<String, Object?>>[];
    final foregrounds = <Color>[];
    final rectangles = <Rect>[];
    final originalSizes = <Size>[];
    final originalTextSizes = <Size>[];
    final sourceIndices = <int>[];
    final label = calendarCell
        ? (tester.widget<Semantics>(group)).properties.label!
        : null;
    for (var index = 0; index < texts.length; index++) {
      final text = texts[index];
      if (text.data!.isEmpty) {
        expect(calendarCell && index == 1, isTrue);
        rows.add({
          'role': '$role $index',
          'text': '',
          'emptyPreview': true,
          'semanticLabel': label,
        });
        continue;
      }
      final finder = singleText
          ? group
          : find.descendant(
              of: group,
              matching: find.byWidgetPredicate(
                (widget) => identical(widget, text),
              ),
            );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: finder, matching: find.byType(RichText)),
      );
      final span = paragraph.text as TextSpan;
      expect(span.children, isNull);
      final style = span.style!;
      expect(style.foreground, isNull);
      final rect = imageRect(paragraph);
      final preview = calendarCell && index == 1;
      final verticalClip =
          paragraph.textSize.height > paragraph.size.height + .1;
      final incomplete =
          verticalClip ||
          (!preview &&
              (paragraph.didExceedMaxLines ||
                  paragraph.textSize.width > paragraph.size.width + .1));
      final scale = math.min(
        rect.width / paragraph.size.width,
        rect.height / paragraph.size.height,
      );
      final insideCell =
          !calendarCell ||
          (cellRect.inflate(.1).contains(rect.topLeft) &&
              cellRect.inflate(.1).contains(rect.bottomRight));
      if (incomplete) errors.add('$role $index: incomplete');
      if (!scale.isFinite || scale < .999) {
        errors.add('$role $index: invalid or reduced geometry $scale');
      }
      if (!insideCell) errors.add('$role $index: text outside its date cell');
      if (preview) {
        expect(label, contains(text.data!));
      }
      final renderedSize = MediaQuery.textScalerOf(
        tester.element(finder),
      ).scale(style.fontSize!);
      pending.add({
        'role': '$role $index',
        'text': text.data,
        'previewEllipsisAllowed': preview,
        'previewActuallyEllipsized': preview && paragraph.didExceedMaxLines,
        'semanticLabel': label,
        'incomplete': incomplete,
        'insideCell': insideCell,
        'geometricScale': scale.isFinite ? scale : 0.0,
        'nonFiniteGeometry': !scale.isFinite,
        'paragraphSize': [paragraph.size.width, paragraph.size.height],
        'minimumGeometricScale': .999,
        'renderedFontSize': renderedSize,
        'required': renderedSize >= 24 ? 3.0 : 4.5,
        'foregroundARGB': style.color!.toARGB32(),
        'textRect': [rect.left, rect.top, rect.right, rect.bottom],
        'cellRect': [
          cellRect.left,
          cellRect.top,
          cellRect.right,
          cellRect.bottom,
        ],
      });
      paragraphs.add(paragraph);
      originals.add(span);
      foregrounds.add(style.color!);
      rectangles.add(rect);
      originalSizes.add(paragraph.size);
      originalTextSizes.add(paragraph.textSize);
      sourceIndices.add(index);
    }
    if (calendarCell) {
      for (var i = 1; i < paragraphs.length; i++) {
        if (sourceIndices[i] < 2) continue;
        final overlapsDay = rectangles.first
            .deflate(.25)
            .overlaps(rectangles[i].deflate(.25));
        pending[i]['overlapsDayNumber'] = overlapsDay;
        if (overlapsDay) errors.add('$role: badge/counter overlaps day number');
      }
    }

    // Hide only glyph ink while retaining the exact inherited text metrics.
    // This samples the real gradient/cell/badge background directly behind
    // each paragraph, including translucent layers and neighboring shadows.
    try {
      for (var i = 0; i < paragraphs.length; i++) {
        final span = originals[i] as TextSpan;
        paragraphs[i].text = TextSpan(
          text: span.text,
          locale: span.locale,
          style: span.style!.copyWith(color: Colors.transparent),
        );
      }
      await tester.pump();
      final pixels = await tester.runAsync(() async {
        final image = await repaint.toImage(pixelRatio: 1);
        try {
          return (
            data: (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
            width: image.width,
            height: image.height,
          );
        } finally {
          image.dispose();
        }
      });
      expect(pixels, isNotNull);
      for (var i = 0; i < paragraphs.length; i++) {
        expect(paragraphs[i].size, originalSizes[i]);
        expect(paragraphs[i].textSize, originalTextSizes[i]);
        final backgrounds = <int>[];
        final ratios = <double>[];
        final rect = rectangles[i];
        for (final fraction in [.2, .5, .8]) {
          final x = (rect.left + rect.width * fraction).floor();
          final y = rect.center.dy.floor();
          expect(x, inInclusiveRange(0, pixels!.width - 1));
          expect(y, inInclusiveRange(0, pixels.height - 1));
          final offset = (y * pixels.width + x) * 4;
          final data = pixels.data;
          expect(data.getUint8(offset + 3), 255);
          final background = Color.fromARGB(
            255,
            data.getUint8(offset),
            data.getUint8(offset + 1),
            data.getUint8(offset + 2),
          );
          final a = Color.alphaBlend(
            foregrounds[i],
            background,
          ).computeLuminance();
          final b = background.computeLuminance();
          backgrounds.add(background.toARGB32());
          ratios.add((math.max(a, b) + .05) / (math.min(a, b) + .05));
        }
        final ratio = ratios.reduce(math.min);
        pending[i].addAll({
          'ratio': ratio,
          'backgroundSamplesARGB': backgrounds,
          'hiddenInkGeometryUnchanged': true,
        });
        if (ratio < (pending[i]['required']! as double)) {
          errors.add(
            '$role $i: contrast $ratio below ${pending[i]['required']}',
          );
        }
      }
    } finally {
      for (var i = 0; i < paragraphs.length; i++) {
        paragraphs[i].text = originals[i];
      }
      await tester.pump();
    }
    rows.addAll(pending);
    frameworkErrors(role);
  }
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'almanac-grid-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final shadows = debugDisableShadows;
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = shadows);
          try {
            final boundary = await mountPriorityFixture(
              tester,
              auth: AuthProvider(),
              brand: brand,
              locale: locale,
              size: layout.size,
              scale: layout.scale,
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    key: const ValueKey('open_almanac_grid'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BrandRouteSurface(
                          child: AlmanacScreen(
                            initialDate: DateTime(2026, 6, 28),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open synthetic month calendar'),
                  ),
                ),
              ),
            );
            await tester.tap(find.byKey(const ValueKey('open_almanac_grid')));
            await tester.pumpAndSettle();
            final state = tester.state(find.byType(AlmanacScreen));
            final grid = find.byWidgetPredicate(
              (widget) => widget.runtimeType.toString() == '_MonthCalendar',
            );
            final element = tester.element(grid);
            final probe = _GridProbe(tester, boundary, name);
            probe.frameworkErrors('initial calendar');
            Finder cell(int day) {
              final numeric = find.descendant(
                of: grid,
                matching: find.text('$day'),
              );
              expect(numeric, findsOneWidget);
              return find
                  .ancestor(
                    of: numeric,
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Semantics &&
                          widget.properties.button == true &&
                          widget.properties.selected != null,
                    ),
                  )
                  .first;
            }

            Future<void> header(String stage) async {
              final texts = find
                  .descendant(of: grid, matching: find.byType(Text))
                  .evaluate()
                  .take(9)
                  .map((e) => e.widget as Text)
                  .toList();
              expect(texts.length, 9);
              expect(texts[0].data, AlmanacUiCopy.monthHeader(6));
              expect(texts[1].data, AlmanacUiCopy.yearHeader(2026));
              expect(
                texts.skip(2).map((text) => text.data),
                AlmanacUiCopy.weekdayInitials,
              );
              for (var i = 0; i < texts.length; i++) {
                final text = texts[i];
                await probe.measure(
                  find.descendant(
                    of: grid,
                    matching: find.byWidgetPredicate(
                      (widget) => identical(widget, text),
                    ),
                  ),
                  '$stage header $i',
                  singleText: true,
                );
              }
              await probe.reveal(
                find.descendant(
                  of: grid,
                  matching: find.text(AlmanacUiCopy.monthHeader(6)),
                ),
              );
              await probe.capture('$stage-header');
            }

            Future<void> month(String stage, int selected) async {
              expect(
                find.descendant(of: grid, matching: find.text('31')),
                findsNothing,
              );
              for (var day = 1; day <= 30; day++) {
                final finder = cell(day);
                expect(
                  tester.widget<Semantics>(finder).properties.selected,
                  day == selected,
                );
                await probe.measure(
                  finder,
                  '$stage day $day',
                  calendarCell: true,
                );
              }
              await probe.capture('$stage-month-bottom');
            }

            await header('initial');
            await month('initial', 28);
            await probe.reveal(cell(29));
            await tester.tap(
              find.descendant(of: cell(29), matching: find.text('29')),
            );
            await tester.pumpAndSettle();
            probe.frameworkErrors('selected June29');
            for (final day in [28, 29]) {
              final finder = cell(day);
              expect(
                tester.widget<Semantics>(finder).properties.selected,
                day == 29,
              );
              await probe.measure(
                finder,
                'changed day $day',
                calendarCell: true,
              );
            }
            await probe.capture('changed-selection');
            I18n.setLocale(
              locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
            );
            await tester.pumpAndSettle();
            probe.frameworkErrors('live locale');
            expect(tester.state(find.byType(AlmanacScreen)), same(state));
            expect(tester.element(grid), same(element));
            probe.rows.add({
              'role': 'mounted calendar retention',
              'sameMainState': true,
              'sameCalendarElement': true,
              'selectedCivilDay': '2026-06-29',
              'monthCellCount': 30,
            });
            await header('live');
            await month('live', 29);
            await probe.finish();
          } finally {
            debugDisableShadows = shadows;
          }
        });
      }
    }
  }
}
