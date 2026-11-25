import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/main_ui_copy.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/pomodoro_session_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final width in [320.0, 332.0, 360.0, 390.0]) {
        final name = '$brand-${locale.name}-$width';
        testWidgets('focus history metadata and actions fit at 200% $name', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          final originalLocale = I18n.current;
          I18n.setLocale(locale);
          final theme = ThemeProvider();
          final boundary = GlobalKey();
          final session = PomodoroSession(
            id: 'local-layout-session',
            startTime: DateTime(2026, 10, 23, 10, 30),
            endTime: DateTime(2026, 10, 23, 10, 55),
            durationSeconds: 1500,
            type: PomodoroType.focus,
            taskName: locale == AppLocale.en ? 'Read' : '阅读',
            whiteNoiseSound: 'rain',
          );
          final originalSession = jsonEncode(session.toJson());
          var edits = 0;
          var deletes = 0;
          tester.view.physicalSize = Size(width, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            theme.dispose();
            tester.view.reset();
            I18n.setLocale(originalLocale);
          });
          await tester.runAsync(() async {
            await theme.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });
          await tester.pumpWidget(
            ChangeNotifierProvider<ThemeProvider>.value(
              value: theme,
              child: MaterialApp(
                theme: theme.brand.theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(2)),
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
                home: Scaffold(
                  body: BrandBackground(
                    child: ListView(
                      children: [
                        PomodoroSessionCard(
                          session: session,
                          onEdit: () => edits++,
                          onDelete: () => deletes++,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final layoutError = tester.takeException();
          final edit = find.widgetWithIcon(IconButton, Icons.edit_outlined);
          final delete = find.widgetWithIcon(IconButton, Icons.delete_outline);
          final sound = find.byIcon(Icons.water_drop);
          final actionRects = [tester.getRect(edit), tester.getRect(delete)];
          final soundCenter = tester.getCenter(sound);
          final paragraphs = tester.renderObjectList<RenderParagraph>(
            find.descendant(
              of: find.byType(PomodoroSessionCard),
              matching: find.byType(RichText),
            ),
          );
          final geometry = [
            for (final paragraph in paragraphs)
              {
                'text': paragraph.text.toPlainText(),
                'width': paragraph.size.width,
                'textWidth': paragraph.textSize.width,
                'height': paragraph.size.height,
                'textHeight': paragraph.textSize.height,
                'exceededMaxLines': paragraph.didExceedMaxLines,
              },
          ];
          final directory =
              Platform.environment['DUOYI_SECONDARY_MEASUREMENTS'];
          if (directory != null) {
            final file = File('$directory/focus-history-$name.json');
            file.parent.createSync(recursive: true);
            file.writeAsStringSync(
              jsonEncode({
                'layoutError': layoutError?.toString(),
                'paragraphs': geometry,
                'actions': [
                  for (final rect in actionRects)
                    {
                      'width': rect.width,
                      'height': rect.height,
                      'centerY': rect.center.dy,
                    },
                ],
                'soundCenterY': soundCenter.dy,
              }),
            );
          }
          final images = Platform.environment['DUOYI_FOCUS_HISTORY_IMAGES'];
          if (images != null) {
            await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final picture = await render.toImage();
              try {
                final bytes = await picture.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File('$images/$name.png');
                file.parent.createSync(recursive: true);
                file.writeAsBytesSync(bytes!.buffer.asUint8List());
              } finally {
                picture.dispose();
              }
            });
          }
          expect(layoutError, isNull);
          for (final rect in actionRects) {
            expect(rect.width, greaterThanOrEqualTo(44));
            expect(rect.height, greaterThanOrEqualTo(44));
          }
          // These original-source cases already fit inline. Keep the action
          // row aligned with the sound badge rather than needlessly reflowing.
          if (width == 390) {
            for (final rect in actionRects) {
              expect(rect.center.dy, closeTo(soundCenter.dy, 0.1));
            }
          }
          for (final label in [
            session.taskName!,
            I18nDateFormat.time(session.startTime),
            locale == AppLocale.en ? '25 min' : '25 分钟',
          ]) {
            final paragraph = paragraphs.singleWhere(
              (paragraph) => paragraph.text.toPlainText() == label,
            );
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(
              paragraph.textSize.width,
              lessThanOrEqualTo(paragraph.size.width + 0.1),
            );
            expect(
              paragraph.textSize.height,
              lessThanOrEqualTo(paragraph.size.height + 0.1),
            );
          }
          await tester.tap(find.byTooltip(MainUiCopy.pomodoroEditRecord));
          await tester.pump();
          expect(edits, 1);
          expect(deletes, 0);
          await tester.tap(find.byTooltip(MainUiCopy.pomodoroDeleteRecord));
          await tester.pump();
          expect(edits, 1);
          expect(deletes, 1);
          expect(jsonEncode(session.toJson()), originalSession);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
