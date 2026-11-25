import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'readable foreground covers primary fills and alpha over real surfaces',
    () {
      for (final background in [
        const Color(0xFFC85656),
        const Color(0xFFF6F7F9),
        const Color(0xFFF1F3F6),
        const Color(0xFFEFF3F9),
        Colors.black,
      ]) {
        for (final preferred in [
          Colors.white,
          Colors.black,
          const Color(0x40111827),
          const Color(0xFFC85656),
        ]) {
          final foreground = appReadableForeground(background, preferred);
          expect(
            appContrastRatio(
              background,
              Color.alphaBlend(foreground, background),
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
      expect(appReadableForeground(Colors.white, Colors.black), Colors.black);
    },
  );

  for (final brand in [AppBrands.defaultBrand, AppBrands.liquidGlass]) {
    testWidgets('secondary iOS control shapes resolve in ${brand.id}', (
      tester,
    ) async {
      late ThemeData resolved;
      late ButtonStyle helper;
      await tester.pumpWidget(
        MaterialApp(
          theme: brand.theme,
          home: Scaffold(
            body: AppSecondaryControlTheme(
              child: Builder(
                builder: (context) {
                  resolved = Theme.of(context);
                  helper = appSecondaryFilledButtonStyle(context);
                  return const TextField();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        (resolved.inputDecorationTheme.enabledBorder! as OutlineInputBorder)
            .borderRadius,
        BorderRadius.circular(12),
      );
      for (final style in [
        resolved.textButtonTheme.style,
        resolved.elevatedButtonTheme.style,
        resolved.outlinedButtonTheme.style,
        resolved.filledButtonTheme.style,
        resolved.segmentedButtonTheme.style,
        helper,
      ]) {
        final shape = style!.shape!.resolve({})! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(12));
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('secondary targets $platform $brightness text $scale', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(320, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final semanticsHandle = tester.ensureSemantics();
          try {
            final calls = <String>[];
            var selected = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(
                  platform: platform,
                  brightness: brightness,
                  // Prove that the scoped policy also replaces desktop density.
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: AppSecondaryControlTheme(
                    child: Builder(
                      builder: (context) => StatefulBuilder(
                        builder: (context, setState) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextButton(
                              onPressed: () => calls.add('text'),
                              child: const Text('Edit'),
                            ),
                            OutlinedButton(
                              onPressed: () => calls.add('outlined'),
                              child: const Text('Export'),
                            ),
                            ElevatedButton(
                              onPressed: () => calls.add('elevated'),
                              child: const Text('Save'),
                            ),
                            FilledButton(
                              onPressed: () => calls.add('filled'),
                              child: const Text('Confirm'),
                            ),
                            FilledButton(
                              style: appSecondaryFilledButtonStyle(context),
                              onPressed: () => calls.add('helper'),
                              child: const Text('Continue'),
                            ),
                            SegmentedButton<int>(
                              segments: const [
                                ButtonSegment(value: 0, label: Text('Day')),
                                ButtonSegment(value: 1, label: Text('Week')),
                              ],
                              selected: {selected},
                              onSelectionChanged: (values) {
                                setState(() => selected = values.single);
                                calls.add('segment');
                              },
                            ),
                            ActionChip(
                              label: const Text('Date settings'),
                              onPressed: () => calls.add('chip'),
                            ),
                            AppSectionHeader(
                              title: 'Review',
                              actionLabel: 'More',
                              onAction: () => calls.add('header'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            Future<void> checkAndTap(Finder finder, String action) async {
              final size = tester.getSize(finder);
              expect(size.width, greaterThanOrEqualTo(44), reason: action);
              expect(size.height, greaterThanOrEqualTo(44), reason: action);
              final node = tester.getSemantics(finder);
              expect(node.rect.width, greaterThanOrEqualTo(44), reason: action);
              expect(
                node.rect.height,
                greaterThanOrEqualTo(44),
                reason: action,
              );
              expect(
                node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
                isTrue,
              );
              // This point is outside the short visual interior on ordinary buttons.
              final before = calls.length;
              await tester.tapAt(
                tester.getRect(finder).topCenter + const Offset(0, 1),
              );
              await tester.pumpAndSettle();
              expect(calls.length, before + 1, reason: '$action padded edge');
              expect(calls.last, action);
            }

            await checkAndTap(find.widgetWithText(TextButton, 'Edit'), 'text');
            await checkAndTap(
              find.widgetWithText(OutlinedButton, 'Export'),
              'outlined',
            );
            await checkAndTap(
              find.widgetWithText(ElevatedButton, 'Save'),
              'elevated',
            );
            await checkAndTap(
              find.widgetWithText(FilledButton, 'Confirm'),
              'filled',
            );
            await checkAndTap(
              find.widgetWithText(FilledButton, 'Continue'),
              'helper',
            );
            for (final label in ['Week', 'Day']) {
              final segment = find.descendant(
                of: find.byType(SegmentedButton<int>),
                matching: find.widgetWithText(TextButton, label),
              );
              await checkAndTap(segment, 'segment');
            }
            expect(selected, 0);
            await checkAndTap(find.byType(ActionChip), 'chip');
            await checkAndTap(
              find.widgetWithText(TextButton, 'More'),
              'header',
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            semanticsHandle.dispose();
          }
        });
      }
    }
  }
}
