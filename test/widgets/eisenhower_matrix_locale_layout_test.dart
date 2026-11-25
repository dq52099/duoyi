import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/eisenhower_matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('full quadrant headings at $width / $scale across locales', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.runAsync(loadWidgetPolishScreenshotFonts);
        final theme = ThemeProvider();
        final taps = <EisenhowerQuadrant>[];
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>.value(
            value: theme,
            child: MaterialApp(
              theme: widgetPolishScreenshotTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: EisenhowerMatrix(
                      quadrantGroups: {
                        EisenhowerQuadrant.notUrgentImportant: [
                          for (var i = 0; i < 4; i++)
                            TodoItem(title: '任务 Raw $i'),
                        ],
                      },
                      onQuadrantTap: taps.add,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final state = tester.element(find.byType(EisenhowerMatrix));
        for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          final copy = theme.brand.strings;
          final titles = [
            copy.quadrantQ1Label,
            copy.quadrantQ2Label,
            copy.quadrantQ3Label,
            copy.quadrantQ4Label,
          ];
          for (final title in titles) {
            final text = find.text(title);
            expect(text, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(text);
            expect(paragraph.didExceedMaxLines, isFalse, reason: title);
            if (locale == AppLocale.en) {
              expect(
                paragraph.getMinIntrinsicWidth(double.infinity),
                lessThanOrEqualTo(paragraph.size.width + 0.01),
                reason: '$title retains whole words',
              );
            }
            expect(
              tester.widget<Text>(text).overflow,
              isNot(TextOverflow.ellipsis),
            );
          }
          final cards = find.descendant(
            of: find.byType(EisenhowerMatrix),
            matching: find.byType(GestureDetector),
          );
          expect(cards, findsNWidgets(4));
          final heights = [
            for (var i = 0; i < 4; i++) tester.getSize(cards.at(i)).height,
          ];
          expect(heights.toSet(), hasLength(1));
          if (locale == AppLocale.zh) {
            expect(
              tester.getRect(find.text(copy.quadrantQ1Label)).top,
              tester.getRect(find.text(copy.quadrantQ2Label)).top,
              reason: 'CJK headings retain the two-column grid',
            );
          }
          expect(tester.element(find.byType(EisenhowerMatrix)), same(state));
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(copy.quadrantQ1Label));
          await tester.pump();
          expect(taps.last, EisenhowerQuadrant.urgentImportant);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        theme.dispose();
      });
    }
  }
}
