import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final width in [54.0, 220.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final above in [false, true]) {
          final name = '$brand-width$width-scale$scale-above$above';
          testWidgets('numeric compact menu $name', (tester) async {
            SharedPreferences.setMockInitialValues({'active_brand': brand});
            final theme = ThemeProvider();
            final selections = <int?>[];
            final boundary = GlobalKey();
            try {
              await tester.runAsync(() async {
                await theme.loadFromStorage();
                await loadWeeklyReviewScreenshotFonts();
              });
              tester.view.physicalSize = const Size(390, 640);
              tester.view.devicePixelRatio = 1;
              await tester.pumpWidget(
                MaterialApp(
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: Scaffold(
                    body: Align(
                      alignment: above
                          ? Alignment.bottomLeft
                          : Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: AppCompactDropdown<int>(
                          width: width,
                          value: 10,
                          items: [
                            for (final value in [10, 20, 50, 100])
                              DropdownMenuItem(
                                value: value,
                                child: Text('$value'),
                              ),
                          ],
                          onChanged: selections.add,
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final anchor = find.byType(AppCompactDropdown<int>);
              final anchorBefore = tester.getRect(anchor);
              await tester.tap(anchor);
              await tester.pumpAndSettle();
              final menus = find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem<int>,
              );
              expect(menus, findsNWidgets(4));
              final observations = <Map<String, Object?>>[];
              for (final value in [10, 20, 50, 100]) {
                final label = find.descendant(
                  of: menus,
                  matching: find.text('$value'),
                );
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(of: label, matching: find.byType(RichText)),
                );
                final painter = TextPainter(
                  text: paragraph.text,
                  textDirection: paragraph.textDirection,
                  textScaler: paragraph.textScaler,
                )..layout();
                observations.add({
                  'value': value,
                  'paintedWidth': paragraph.size.width,
                  'naturalWidth': painter.width,
                  'height': paragraph.size.height,
                  'singleLineHeight': painter.height,
                  'exceededMaxLines': paragraph.didExceedMaxLines,
                });
                painter.dispose();
              }
              final first = tester.getRect(menus.first);
              final last = tester.getRect(menus.last);
              final aboveGap = anchorBefore.top - last.bottom;
              final layoutError = tester.takeException();
              final screenshotDir = Platform.environment['DUOYI_MENU_IMAGES'];
              if (screenshotDir != null) {
                await tester.runAsync(() async {
                  final render =
                      boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary;
                  final picture = await render.toImage();
                  try {
                    final bytes = await picture.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    final file = File('$screenshotDir/$name.png');
                    file.parent.createSync(recursive: true);
                    file.writeAsBytesSync(bytes!.buffer.asUint8List());
                  } finally {
                    picture.dispose();
                  }
                });
              }
              final measurementDir =
                  Platform.environment['DUOYI_SECONDARY_MEASUREMENTS'];
              if (measurementDir != null) {
                final file = File('$measurementDir/$name.json');
                file.parent.createSync(recursive: true);
                file.writeAsStringSync(
                  jsonEncode({
                    'name': name,
                    'anchor': anchorBefore.toString(),
                    'menuFirst': first.toString(),
                    'menuLast': last.toString(),
                    'aboveGap': aboveGap,
                    'layoutError': layoutError?.toString(),
                    'labels': observations,
                  }),
                );
              }
              expect(layoutError, isNull);
              expect(tester.getRect(anchor), anchorBefore);
              for (final observation in observations) {
                expect(
                  observation['paintedWidth']! as double,
                  greaterThanOrEqualTo(
                    (observation['naturalWidth']! as double) - 0.1,
                  ),
                  reason: '${observation['value']} must remain a whole number',
                );
                expect(observation['exceededMaxLines'], isFalse);
              }
              if (above) {
                expect(last.bottom, lessThanOrEqualTo(anchorBefore.top));
                expect(aboveGap, inInclusiveRange(0, 22));
              } else {
                expect(first.top, greaterThanOrEqualTo(anchorBefore.bottom));
                expect(first.top - anchorBefore.bottom, lessThanOrEqualTo(22));
              }
              await tester.tap(
                find.descendant(of: menus, matching: find.text('20')),
              );
              await tester.pumpAndSettle();
              expect(selections, [20]);
              expect(menus, findsNothing);
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              theme.dispose();
              tester.view.reset();
            }
          });
        }
      }
    }
  }
}
