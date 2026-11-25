// Synthetic saved-conflict fallback theme regression; no live sync actions.
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/sync_conflict_log_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../support/secondary_route_render_probe.dart';
import '../support/secondary_route_header_probe.dart';

final _decision = SyncMergeDecision(
  workspaceId: 'synthetic-workspace',
  itemType: 'todo',
  itemId: 'synthetic-item',
  winner: 'remote',
  reason: 'Literal reason 原始内容 stays unchanged.',
  changedFields: const ['title'],
  localUpdatedAt: '2026-10-14T09:34:00Z',
  remoteUpdatedAt: '2026-10-14T09:35:00Z',
  decidedAt: DateTime(2026, 10, 14, 9, 35),
);

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final winner in ['remote', 'local']) {
        for (final layout in [
          (name: 'common', size: const Size(390, 844), scale: 1.0),
          (name: 'narrow', size: const Size(320, 844), scale: 1.6),
          (name: 'large', size: const Size(320, 844), scale: 2.0),
          (name: 'landscape', size: const Size(568, 320), scale: 2.0),
          (name: 'desktop', size: const Size(1000, 720), scale: 1.1),
          (name: 'nonlinear', size: const Size(332, 844), scale: -1.0),
        ]) {
          final name = 'conflict-$winner-$brand-${locale.name}-${layout.name}';
          testWidgets('saved conflict theme and retained locale $name', (
            tester,
          ) async {
            final saved = [
              jsonEncode({..._decision.toJson(), 'winner': winner}),
            ];
            SharedPreferences.setMockInitialValues({
              'active_brand': brand,
              'sync_merge_decisions': saved,
            });
            I18n.setLocale(locale);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final theme = ThemeProvider();
            await tester.runAsync(() async {
              await theme.loadFromStorage();
              await loadWeeklyReviewScreenshotFonts();
            });
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              theme.dispose();
            });
            final boundary = GlobalKey();
            await tester.pumpWidget(
              ChangeNotifierProvider<ThemeProvider>.value(
                value: theme,
                child: ValueListenableBuilder<AppLocale>(
                  valueListenable: I18n.localeListenable,
                  builder: (context, selected, _) => MaterialApp(
                    locale: Locale(selected == AppLocale.en ? 'en' : 'zh'),
                    supportedLocales: const [Locale('en'), Locale('zh')],
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    theme: theme.brand.theme,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: layout.scale < 0
                            ? const RouteProbeNonlinearScaler()
                            : TextScaler.linear(layout.scale),
                      ),
                      child: RepaintBoundary(key: boundary, child: child!),
                    ),
                    home: Builder(
                      builder: (context) => Scaffold(
                        body: TextButton(
                          key: const ValueKey('open_conflict'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BrandRouteSurface(
                                child: SyncConflictLogScreen(),
                              ),
                            ),
                          ),
                          child: const Text('Open synthetic conflicts'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.byKey(const ValueKey('open_conflict')));
            await tester.pumpAndSettle();
            final state = tester.state(find.byType(SyncConflictLogScreen));
            final probe = RouteRenderProbe(tester, boundary, name);
            await checkSecondaryRouteHeader(
              probe,
              'sync_conflict.title',
              stage: 'initial',
            );
            await probe.capture('top');
            for (final text in [
              I18n.current == AppLocale.en
                  ? 'Sync status unavailable'
                  : '同步状态未接入',
              I18n.current == AppLocale.en
                  ? 'Only saved conflicts are available; live sync status could not be read.'
                  : '当前页面只能显示已记录的冲突，未读取到云同步运行状态。',
              I18n.tr('sync_conflict.keep_$winner'),
              I18nDateFormat.shortDateTime(_decision.decidedAt),
              _decision.reason,
              '${I18n.current == AppLocale.en ? 'Field' : '字段'}: title',
            ]) {
              await probe.text(find.text(text), role: 'saved conflict');
            }
            await _checkWinnerSpacing(tester, probe, winner);
            await probe.capture('decision');
            I18n.setLocale(
              locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
            );
            await tester.pumpAndSettle();
            expect(
              tester.state(find.byType(SyncConflictLogScreen)),
              same(state),
            );
            expect(find.text(_decision.reason), findsOneWidget);
            await probe.text(
              find.text(I18n.tr('sync_conflict.keep_$winner')),
              role: 'live winner',
            );
            await probe.text(
              find.text(I18nDateFormat.shortDateTime(_decision.decidedAt)),
              role: 'live time',
            );
            await _checkWinnerSpacing(tester, probe, winner);
            final prefs = await SharedPreferences.getInstance();
            expect(prefs.getStringList('sync_merge_decisions'), saved);
            await checkSecondaryRouteHeader(
              probe,
              'sync_conflict.title',
              stage: 'live',
            );
            await probe.capture('live-header');
            await probe.finish();
            await tester.tap(find.byType(BackButton));
            await tester.pumpAndSettle();
            expect(find.byType(SyncConflictLogScreen), findsNothing);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
}

Future<void> _checkWinnerSpacing(
  WidgetTester tester,
  RouteRenderProbe probe,
  String winner,
) async {
  final title = find.text(I18n.tr('sync_conflict.keep_$winner'));
  final time = find.text(I18nDateFormat.shortDateTime(_decision.decidedAt));
  await probe.reveal(title);
  RenderParagraph paragraph(Finder finder) =>
      tester.renderObject<RenderParagraph>(
        find.descendant(of: finder, matching: find.byType(RichText)),
      );
  final heading = paragraph(title), timestamp = paragraph(time);
  List<Rect> glyphBounds(RenderParagraph text) => text
      .getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: text.text.toPlainText().length,
        ),
      )
      .map((box) => box.toRect().shift(text.localToGlobal(Offset.zero)))
      .toList();
  double? minimumGap;
  for (final a in glyphBounds(heading)) {
    for (final b in glyphBounds(timestamp)) {
      if (a.top < b.bottom && a.bottom > b.top) {
        final gap = b.left - a.right;
        minimumGap = minimumGap == null || gap < minimumGap ? gap : minimumGap;
      }
    }
  }
  if (minimumGap != null && minimumGap < 7.99) {
    probe.errors.add('winner/time visible glyph gap $minimumGap below8');
  }
  double widestWord = 0;
  if (I18n.current == AppLocale.en) {
    for (final word in I18n.tr('sync_conflict.keep_$winner').split(' ')) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: heading.text.style),
        textDirection: heading.textDirection,
        textScaler: MediaQuery.textScalerOf(tester.element(title)),
      )..layout();
      if (painter.width > widestWord) widestWord = painter.width;
      painter.dispose();
    }
    if (heading.size.width + 0.1 < widestWord) {
      probe.errors.add(
        'winner splits English word: width ${heading.size.width}, needs $widestWord',
      );
    }
  }
  probe.rows.add({
    'role': 'winner/time spacing',
    'minimumGlyphGap': minimumGap,
    'headingWidth': heading.size.width,
    'widestEnglishWord': widestWord,
  });
}
