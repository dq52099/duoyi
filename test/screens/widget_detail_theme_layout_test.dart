import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

enum _Detail { diary, memorial }

const _layouts = [
  (name: 'narrow', size: Size(320, 844), scale: 1.6, inset: 240.0),
  (name: 'landscape', size: Size(568, 320), scale: 2.0, inset: 100.0),
];

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final detail in _Detail.values) {
        for (final layout in _layouts) {
          final name = '$brand-${locale.name}-${detail.name}-${layout.name}';
          testWidgets('paired widget detail route layout $name', (
            tester,
          ) async {
            final previousShadows = debugDisableShadows;
            final diary = DiaryEntry(
              id: 'historical/diary',
              date: DateTime(2023, 3, 22),
              content: 'User diary text stays unchanged\n用户日记原文',
              mood: Mood.good,
              weather: Weather.sunny,
              tags: ['User tag 用户标签'],
            );
            final memorial = Anniversary(
              id: 'memorial/object',
              title: 'User memorial title 用户纪念日',
              description: 'User description stays unchanged 用户备注',
              originDate: DateTime(2023, 3, 22),
              type: AnniversaryType.memorial,
            );
            final storedDiary = [jsonEncode(diary.toJson())];
            final storedMemorial = [jsonEncode(memorial.toJson())];
            SharedPreferences.setMockInitialValues({
              'active_brand': brand,
              'duoyi_diary': storedDiary,
              'duoyi_anniversaries_v2': storedMemorial,
            });
            final diaries = DiaryProvider();
            final anniversaries = AnniversaryProvider();
            final theme = ThemeProvider();
            final boundary = GlobalKey();
            try {
              I18n.setLocale(locale);
              debugDisableShadows = false;
              await diaries.loadFromStorage();
              await anniversaries.loadFromStorage();
              await theme.loadFromStorage();
              expect(theme.brand.id, brand);
              await tester.runAsync(
                () => loadWeeklyReviewScreenshotFonts(
                  emojiFontPath:
                      'evidence/widget-detail-theme-20261020/fonts/NotoColorEmoji.ttf',
                ),
              );
              tester.view.physicalSize = layout.size;
              tester.view.devicePixelRatio = 1;
              await tester.pumpWidget(
                MultiProvider(
                  providers: [
                    ChangeNotifierProvider<DiaryProvider>.value(value: diaries),
                    ChangeNotifierProvider<AnniversaryProvider>.value(
                      value: anniversaries,
                    ),
                    ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ],
                  child: MaterialApp(
                    theme: theme.brand.theme,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                      // Include the Navigator and its real modal overlays.
                      child: RepaintBoundary(key: boundary, child: child!),
                    ),
                    home: Builder(
                      builder: (context) => Scaffold(
                        body: Center(
                          child: TextButton(
                            onPressed: () => TodayDetailRouter.open(
                              context,
                              detail == _Detail.diary
                                  ? TodaySectionKind.diary
                                  : TodaySectionKind.anniversaries,
                              id: detail == _Detail.diary
                                  ? diary.id
                                  : memorial.id,
                            ),
                            child: const Text('Open detail'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.tap(find.text('Open detail'));
              await tester.pumpAndSettle();
              expect(find.byType(BrandRouteSurface), findsOneWidget);
              final route = detail == _Detail.diary
                  ? find.byType(DiaryEditScreen)
                  : find.byType(AnniversaryScreen);
              final routeElement = tester.element(route);
              final sheetElement = detail == _Detail.memorial
                  ? tester.element(find.byType(AppModalSheet))
                  : null;
              expect(tester.takeException(), isNull);
              await _capture(tester, boundary, '$name-top');

              final scrollable = _scrollable(detail);
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              for (var attempt = 0; attempt < 30; attempt++) {
                position.jumpTo(position.maxScrollExtent);
                await tester.pumpAndSettle();
                if (position.extentAfter < 1) break;
              }
              expect(position.extentAfter, lessThan(1));
              expect(tester.takeException(), isNull);
              await _capture(tester, boundary, '$name-bottom');

              final field = detail == _Detail.diary
                  ? find.byWidgetPredicate(
                      (widget) =>
                          widget is TextField &&
                          widget.decoration?.hintText ==
                              I18n.tr('diary.editor.content_hint'),
                    )
                  : find.byType(TextField).first;
              await tester.ensureVisible(field);
              await tester.pumpAndSettle();
              await tester.enterText(field, 'Unsaved draft 未保存草稿');
              final controller = tester.widget<TextField>(field).controller!;
              final fieldElement = tester.element(field);
              for (final next in [
                locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
                locale,
              ]) {
                I18n.setLocale(next);
                await tester.pumpAndSettle();
                expect(tester.element(route), same(routeElement));
                expect(tester.element(field), same(fieldElement));
                expect(
                  tester.widget<TextField>(field).controller,
                  same(controller),
                );
                expect(controller.text, 'Unsaved draft 未保存草稿');
                if (sheetElement != null) {
                  expect(
                    tester.element(find.byType(AppModalSheet)),
                    same(sheetElement),
                  );
                }
                expect(tester.takeException(), isNull);
                if (next != locale) {
                  await _capture(tester, boundary, '$name-switched');
                }
              }

              // Simulated view insets exercise layout only, not a physical IME.
              tester.view.viewInsets = FakeViewPadding(bottom: layout.inset);
              await tester.pumpAndSettle();
              final close = detail == _Detail.memorial
                  ? find.text(I18n.tr('action.cancel'))
                  : find.byType(BackButton);
              if (detail == _Detail.memorial) {
                await tester.scrollUntilVisible(
                  close,
                  120,
                  scrollable: _scrollable(detail),
                  maxScrolls: 60,
                );
              } else {
                await tester.ensureVisible(close);
              }
              await tester.pumpAndSettle();
              expect(close.hitTestable(), findsOneWidget);
              final closeRect = tester.getRect(close);
              expect(closeRect.top, greaterThanOrEqualTo(0));
              expect(
                closeRect.bottom,
                lessThanOrEqualTo(layout.size.height - layout.inset + 1),
              );
              expect(closeRect.right, lessThanOrEqualTo(layout.size.width));
              expect(tester.takeException(), isNull);
              await _capture(tester, boundary, '$name-inset-close');
              await tester.tap(close);
              await tester.pumpAndSettle();
              tester.view.viewInsets = const FakeViewPadding();
              await tester.pumpAndSettle();
              if (detail == _Detail.memorial) {
                expect(find.byType(AppModalSheet), findsNothing);
                await tester.pageBack();
                await tester.pumpAndSettle();
              }
              expect(find.text('Open detail'), findsOneWidget);
              final prefs = await SharedPreferences.getInstance();
              expect(prefs.getStringList('duoyi_diary'), storedDiary);
              expect(
                prefs.getStringList('duoyi_anniversaries_v2'),
                storedMemorial,
              );
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              diaries.dispose();
              anniversaries.dispose();
              theme.dispose();
              tester.view.reset();
              I18n.setLocale(AppLocale.zh);
              debugDisableShadows = previousShadows;
            }
          });
        }
      }
    }
  }
}

Finder _scrollable(_Detail detail) => find
    .descendant(
      of: detail == _Detail.diary
          ? find.byType(DiaryEditScreen)
          : find.byType(AppModalSheet),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['DUOYI_CAPTURE_WIDGET_DETAIL_THEME_SCREENSHOTS'] !=
      '1') {
    return;
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    final run =
        Platform.environment['DUOYI_WIDGET_DETAIL_SCREENSHOT_RUN'] ?? 'current';
    final file = File(
      'evidence/screenshots/widget-detail-theme-20261020/$run/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
