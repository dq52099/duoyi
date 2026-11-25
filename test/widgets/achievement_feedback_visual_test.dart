import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/achievements.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/widgets/achievement_feedback_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

const _captureKey = ValueKey('feedback-capture');
void main() {
  for (final locale in AppLocale.values) {
    for (final inset in [0.0, 300.0]) {
      testWidgets('feedback visual ${locale.name} inset $inset at 320 and 1.6x', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        I18n.setLocale(locale);
        final capture =
            Platform.environment['DUOYI_CAPTURE_ACHIEVEMENTS'] == '1';
        if (capture) await loadWeeklyReviewScreenshotFonts();
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        final provider = AchievementProvider();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          provider.dispose();
          tester.view.reset();
          I18n.setLocale(AppLocale.zh);
        });
        await provider.loadFromStorage();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: MaterialApp(
              theme: AppBrands.defaultBrand.theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(1.6),
                  accessibleNavigation: true,
                  viewInsets: EdgeInsets.only(bottom: inset),
                ),
                child: RepaintBoundary(
                  key: _captureKey,
                  child: AchievementFeedbackHost(child: child!),
                ),
              ),
              home: Scaffold(
                appBar: AppBar(
                  title: Text(locale == AppLocale.en ? 'Achievements' : '成就'),
                ),
                body: Center(
                  child: Text(
                    locale == AppLocale.en
                        ? 'Keep making progress'
                        : '持续积累，点滴进步',
                  ),
                ),
              ),
            ),
          ),
        );
        await provider.updateContext(
          const AchievementContext(
            totalTodos: 1,
            completedTodos: 1,
            longestHabitStreak: 0,
            habitCount: 0,
            focusMinutes: 0,
            focusSessions: 0,
            diaryStreak: 0,
            diaryCount: 0,
            goalsTotal: 0,
            goalsAchieved: 0,
            anniversaries: 0,
            courses: 0,
            notes: 0,
          ),
        );
        await tester.pumpAndSettle();
        final banner = find.byKey(const ValueKey('achievement-feedback'));
        expect(banner.hitTestable(), findsOneWidget);
        expect(tester.getRect(banner).bottom, lessThanOrEqualTo(844 - inset));
        expect(tester.takeException(), isNull);
        if (capture) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(_captureKey),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'evidence/screenshots/achievements-locale-20261015/feedback-${locale.name}-${inset.toInt()}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
      });
    }
  }
}
