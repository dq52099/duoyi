import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:duoyi/core/achievements.dart';
import 'package:duoyi/core/achievement_engine.dart';
import 'package:duoyi/core/growth_levels.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/core/achievement_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/achievements_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/weekly_review_screenshot_font.dart';

class _ProgressProvider extends AchievementProvider {
  final bool unlocked;
  _ProgressProvider(this.unlocked);
  @override
  int get coinBalance => 234;
  @override
  int get lifetimeCoins => unlocked ? 12650 : 800;
  @override
  GrowthLevel get growthLevel => GrowthLevels.fromLifetimeCoins(lifetimeCoins);
  @override
  int get unlockedCount => unlocked ? Achievements.all.length : 0;
  @override
  AchievementSnapshot snapshotFor(String id) {
    final badge = Achievements.all.firstWhere((badge) => badge.id == id);
    return AchievementSnapshot(
      id: id,
      unlocked: unlocked,
      current: unlocked ? (badge.target ?? 1) : (badge.target ?? 0) ~/ 2,
      target: badge.target,
      unlockedAt: unlocked ? DateTime(2026, 1, 1) : null,
    );
  }
}

final _evidenceFolder =
    Platform.environment['DUOYI_ACHIEVEMENT_EVIDENCE_DIRECTORY'];
final _screenshotFolder =
    Platform.environment['DUOYI_ACHIEVEMENT_SCREENSHOT_DIRECTORY'];

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in [
        (name: 'common', size: const Size(390, 844), scale: 1.0),
        (name: 'narrow', size: const Size(320, 844), scale: 1.6),
      ]) {
        for (final unlocked in [false, true]) {
          final name =
              '$brand-${locale.name}-${layout.name}-${unlocked ? 'unlocked' : 'progress'}';
          testWidgets('achievement active information contrast $name', (
            tester,
          ) async {
            SharedPreferences.setMockInitialValues({'active_brand': brand});
            I18n.setLocale(locale);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final provider = _ProgressProvider(unlocked);
            final theme = ThemeProvider();
            final boundary = GlobalKey();
            await tester.runAsync(() async {
              await theme.loadFromStorage();
              await loadWeeklyReviewScreenshotFonts();
            });
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              provider.dispose();
              theme.dispose();
            });
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<AchievementProvider>.value(
                    value: provider,
                  ),
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ],
                child: MaterialApp(
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: const BrandRouteSurface(child: AchievementsScreen()),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(theme.brand.id, brand);
            final level = provider.growthLevel;
            final values = <({String text, Finder finder})>[];
            void add(String text, [Finder? within]) {
              values.add((
                text: text,
                finder: within == null
                    ? find.text(text).first
                    : find.descendant(of: within, matching: find.text(text)),
              ));
            }

            add(AchievementUiCopy.text('你的成就', 'Your achievements'));
            add('${provider.unlockedCount} / ${Achievements.all.length}');
            add('Lv.${level.level}');
            add(AchievementUiCopy.levelTitle(level));
            add(
              level.coinsForNextLevel <= 0
                  ? AchievementUiCopy.text('最高等级', 'Maximum level')
                  : AchievementUiCopy.text(
                      '还差 ${level.coinsRemaining}',
                      '${level.coinsRemaining} coins to next level',
                    ),
            );
            add(
              AchievementUiCopy.text(
                '时光币 ${provider.coinBalance}',
                'Time coins ${provider.coinBalance}',
              ),
            );
            add(
              AchievementUiCopy.text(
                '累计 ${provider.lifetimeCoins}',
                'Lifetime ${provider.lifetimeCoins}',
              ),
            );
            for (final badge in Achievements.all) {
              final title = AchievementUiCopy.badgeTitle(badge);
              final card = find
                  .ancestor(
                    of: find.text(title),
                    matching: find.byType(AppSurfaceCard),
                  )
                  .first;
              add(title, card);
              add(AchievementUiCopy.badgeDescription(badge), card);
              add(
                unlocked
                    ? AchievementUiCopy.text('已解锁', 'Unlocked')
                    : AchievementUiCopy.text('进行中', 'In progress'),
                card,
              );
              final snapshot = provider.snapshotFor(badge.id);
              if (badge.current != null && snapshot.target != null) {
                add('${snapshot.current} / ${snapshot.target}', card);
              }
            }
            final rows = <Map<String, Object?>>[];
            final errors = <String>[];
            for (final (index, value) in values.indexed) {
              final text = value.text;
              final finder = value.finder;
              expect(finder, findsOneWidget, reason: text);
              await tester.ensureVisible(finder);
              await tester.pumpAndSettle();
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: finder, matching: find.byType(RichText)),
              );
              final rect = MatrixUtils.transformRect(
                paragraph.getTransformTo(null),
                Offset.zero & paragraph.size,
              );
              final point = Offset(rect.left - 3, rect.center.dy);
              final foreground = paragraph.text.style!.color!;
              final renderedFontSize = MediaQuery.textScalerOf(
                tester.element(finder),
              ).scale(paragraph.text.style!.fontSize!);
              final requiredContrast = renderedFontSize >= 24 ? 3.0 : 4.5;
              await tester.runAsync(() async {
                final render =
                    boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final picture = await render.toImage(pixelRatio: 1);
                try {
                  final raw = (await picture.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))!;
                  final x = point.dx.round(), y = point.dy.round();
                  expect(
                    x,
                    inInclusiveRange(0, picture.width - 1),
                    reason: text,
                  );
                  expect(
                    y,
                    inInclusiveRange(0, picture.height - 1),
                    reason: text,
                  );
                  final offset = (y * picture.width + x) * 4;
                  final background = Color.fromARGB(
                    255,
                    raw.getUint8(offset),
                    raw.getUint8(offset + 1),
                    raw.getUint8(offset + 2),
                  );
                  final a = Color.alphaBlend(
                    foreground,
                    background,
                  ).computeLuminance();
                  final b = background.computeLuminance();
                  final ratio =
                      (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
                  rows.add({
                    'text': text,
                    'ratio': ratio,
                    'requiredContrast': requiredContrast,
                    'renderedFontSize': renderedFontSize,
                    'foregroundARGB': foreground.toARGB32(),
                    'backgroundARGB': background.toARGB32(),
                    'sampleX': x,
                    'sampleY': y,
                    'truncated': paragraph.didExceedMaxLines,
                  });
                  if (ratio < requiredContrast) {
                    errors.add(
                      '$text: contrast $ratio below $requiredContrast',
                    );
                  }
                  if (paragraph.didExceedMaxLines) {
                    errors.add('$text: incomplete');
                  }
                  if (_screenshotFolder != null &&
                      (index < 10 || index == values.length - 1)) {
                    final png = (await picture.toByteData(
                      format: ui.ImageByteFormat.png,
                    ))!;
                    final image = File('$_screenshotFolder/$name-$index.png');
                    image.parent.createSync(recursive: true);
                    image.writeAsBytesSync(png.buffer.asUint8List());
                  }
                } finally {
                  picture.dispose();
                }
              });
            }
            if (_evidenceFolder != null) {
              await tester.runAsync(() async {
                final file = File('$_evidenceFolder/$name.measurements.json');
                file.parent.createSync(recursive: true);
                file.writeAsStringSync(
                  const JsonEncoder.withIndent('  ').convert({
                    'name': name,
                    'measurements': rows,
                    'errors': errors,
                  }),
                );
              });
            }
            final page = tester.element(find.byType(AchievementsScreen));
            final scroll = tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position;
            final offset = scroll.pixels;
            I18n.setLocale(
              locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
            );
            await tester.pumpAndSettle();
            expect(tester.element(find.byType(AchievementsScreen)), same(page));
            final retained = tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position;
            // Locale may shorten content while scrolled at its end. A retained
            // viewport clamps to the new extent rather than resetting to zero.
            expect(
              retained.pixels,
              closeTo(math.min(offset, retained.maxScrollExtent), 0.01),
            );
            expect(tester.takeException(), isNull);
            expect(errors, isEmpty);
          });
        }
      }
    }
  }
}
