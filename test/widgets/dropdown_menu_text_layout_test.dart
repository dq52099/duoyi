import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final compact in [false, true]) {
      testWidgets(
        'opened $brand compact=$compact menu keeps complete choices',
        (tester) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          final theme = ThemeProvider();
          final selections = <String?>[];
          const labels = [
            'A selected option with a long readable label',
            'Another option with a long readable label',
            'A disabled option with a long readable label',
          ];
          try {
            await theme.loadFromStorage();
            await tester.runAsync(loadWeeklyReviewScreenshotFonts);
            tester.view.physicalSize = const Size(320, 640);
            tester.view.devicePixelRatio = 1;
            final items = [
              for (var i = 0; i < labels.length; i++)
                DropdownMenuItem<String>(
                  value: '$i',
                  enabled: i != 2,
                  child: AppSecondaryMenuText(labels[i]),
                ),
            ];
            await tester.pumpWidget(
              MaterialApp(
                theme: theme.brand.theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: 220,
                        child: compact
                            ? AppCompactDropdown<String>(
                                value: '0',
                                items: items,
                                onChanged: selections.add,
                              )
                            : AppDropdownField<String>(
                                initialValue: '0',
                                items: items,
                                onChanged: selections.add,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final anchor = compact
                ? find.byType(AppCompactDropdown<String>)
                : find.byType(AppDropdownField<String>);
            final menu = find.byWidgetPredicate(
              (widget) => widget is PopupMenuItem<String>,
            );
            await tester.tap(anchor);
            await tester.pumpAndSettle();
            expect(menu, findsNWidgets(3));
            for (final label in labels) {
              final option = find.descendant(
                of: menu,
                matching: find.text(label),
              );
              await tester.ensureVisible(option);
              await tester.pumpAndSettle();
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: option, matching: find.byType(RichText)),
              );
              final painter = TextPainter(
                text: paragraph.text,
                textDirection: paragraph.textDirection,
                textScaler: paragraph.textScaler,
                maxLines: paragraph.maxLines,
                ellipsis: paragraph.overflow == TextOverflow.ellipsis
                    ? '\u2026'
                    : null,
              )..layout(maxWidth: paragraph.size.width);
              expect(painter.didExceedMaxLines, isFalse, reason: label);
              expect(
                painter.height,
                lessThanOrEqualTo(paragraph.size.height + 0.5),
              );
              expect(paragraph.textScaler.scale(14), closeTo(28, 0.01));
              painter.dispose();
            }
            final disabled = tester
                .widgetList<PopupMenuItem<String>>(menu)
                .last;
            expect(disabled.enabled, isFalse);
            Navigator.of(tester.element(menu.first)).pop();
            await tester.pumpAndSettle();
            expect(selections, isEmpty);
            await tester.tap(anchor);
            await tester.pumpAndSettle();
            final alternate = find.descendant(
              of: menu,
              matching: find.text(labels[1]),
            );
            await tester.ensureVisible(alternate);
            await tester.pumpAndSettle();
            await tester.tap(alternate);
            await tester.pumpAndSettle();
            expect(selections, ['1']);
            expect(menu, findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            theme.dispose();
            tester.view.reset();
          }
        },
      );
    }
  }
}
