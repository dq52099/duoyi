// Synthetic, in-memory rendering; no network, clipboard or submitted mutations.
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/time_audit_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

Finder _component(String type) =>
    find.byWidgetPredicate((widget) => widget.runtimeType.toString() == type);

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in [
        (name: 'common', size: const Size(390, 844), scale: 1.0),
        (name: 'narrow', size: const Size(320, 844), scale: 1.6),
        (name: 'large', size: const Size(320, 844), scale: 2.0),
        (name: 'landscape', size: const Size(568, 320), scale: 2.0),
        (name: 'desktop', size: const Size(1000, 720), scale: 1.1),
        (name: 'nonlinear', size: const Size(332, 844), scale: -1.0),
      ]) {
        final name = 'audit-$brand-${locale.name}-${layout.name}';
        testWidgets('time tracking readable and retained $name', (
          tester,
        ) async {
          final now = DateTime.now();
          final day = DateTime(now.year, now.month, now.day);
          final entries = [
            TimeEntry(
              id: 'work',
              title: 'Deep work',
              startAt: day.add(const Duration(hours: 9)),
              endAt: day.add(const Duration(hours: 10, minutes: 15)),
              category: TimeEntryCategory.work,
              source: TimeEntrySource.manual,
              createdAt: day,
              updatedAt: day,
            ),
            TimeEntry(
              id: 'read',
              title: 'Reading',
              startAt: day.add(const Duration(hours: 11)),
              endAt: day.add(const Duration(hours: 11, minutes: 45)),
              category: TimeEntryCategory.study,
              source: TimeEntrySource.todo,
              createdAt: day,
              updatedAt: day,
            ),
          ];
          final stored = entries.map((e) => jsonEncode(e.toJson())).toList();
          SharedPreferences.setMockInitialValues({
            'active_brand': brand,
            TimeAuditProvider.storageKey: stored,
          });
          I18n.setLocale(locale);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final provider = TimeAuditProvider();
          final theme = ThemeProvider();
          await provider.loadFromStorage();
          await theme.loadFromStorage();
          await tester.runAsync(loadWeeklyReviewScreenshotFonts);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            provider.dispose();
            theme.dispose();
          });
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<TimeAuditProvider>.value(
                  value: provider,
                ),
              ],
              child: ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, selected, _) => MaterialApp(
                  locale: Locale(selected == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
                      body: Center(
                        child: TextButton(
                          key: const ValueKey('open-audit'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BrandRouteSurface(
                                child: TimeAuditScreen(),
                              ),
                            ),
                          ),
                          child: const Text('Open synthetic route'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('open-audit')));
          await tester.pumpAndSettle();
          expect(theme.brand.id, brand);
          expect(provider.entries, hasLength(2));
          final initialEntries = provider.entries
              .map((e) => e.toJson())
              .toList();
          final state = tester.state(find.byType(TimeAuditScreen));
          final probe = RouteRenderProbe(tester, boundary, name);
          final rootScroll = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          Future<void> top() async {
            rootScroll.position.jumpTo(0);
            await tester.pumpAndSettle();
          }

          Future<void> measure(String type, String role) async {
            final components = _component(type);
            expect(components, findsWidgets);
            final count = components.evaluate().length;
            for (var n = 0; n < count; n++) {
              final texts = find.descendant(
                of: components.at(n),
                matching: find.byType(Text),
              );
              final textCount = texts.evaluate().length;
              for (var i = 0; i < textCount; i++) {
                final text = texts.at(i);
                await probe.reveal(text);
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(of: text, matching: find.byType(RichText)),
                );
                final label = tester.widget<Text>(text).data!;
                final fab = tester.getRect(find.byType(FloatingActionButton));
                final occluded = paragraph
                    .getBoxesForSelection(
                      TextSelection(baseOffset: 0, extentOffset: label.length),
                    )
                    .any(
                      (box) => MatrixUtils.transformRect(
                        paragraph.getTransformTo(null),
                        box.toRect(),
                      ).overlaps(fab),
                    );
                var widestToken = 0.0;
                final context = tester.element(text);
                for (final token in label.split(RegExp(r'\s+'))) {
                  final painter = TextPainter(
                    text: TextSpan(text: token, style: paragraph.text.style),
                    textScaler: MediaQuery.textScalerOf(context),
                    textDirection: Directionality.of(context),
                  )..layout();
                  if (painter.width > widestToken) widestToken = painter.width;
                  painter.dispose();
                }
                if (widestToken > paragraph.size.width + 0.1) {
                  probe.errors.add('$role $label: ordinary token cannot fit');
                }
                if (occluded) {
                  probe.errors.add('$role $label: hidden by add button');
                }
                // The actual blank padding precedes these scoped paragraphs.
                // Never sample FAB pixels as though they were card background.
                await probe.text(text, role: role, contrast: !occluded);
                probe.rows.last.addAll({
                  'widestToken': widestToken,
                  'availableWidth': paragraph.size.width,
                  'occludedByAddButton': occluded,
                });
              }
            }
          }

          Future<void> showSelector(String view) async {
            await top();
            final label = find.text(I18n.tr('time_audit.view.$view'));
            await tester.scrollUntilVisible(
              label,
              100,
              scrollable: find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            expect(label, findsOneWidget);
            await Scrollable.ensureVisible(tester.element(label));
            await tester.pumpAndSettle();
            expect(label.hitTestable(), findsOneWidget);
          }

          Future<void> choose(String view) async {
            await showSelector(view);
            await tester.tap(find.text(I18n.tr('time_audit.view.$view')));
            await tester.pumpAndSettle();
          }

          await probe.capture('top');
          await measure('_MetricBlock', 'summary metric');
          await measure('_CategoryShareRow', 'summary category');
          await measure('_TimeEntryCard', 'timeline entry');
          await probe.capture('timeline');
          await choose('category');
          await measure('_CategoryBreakdownTile', 'category breakdown');
          await measure('_SourceBreakdownRow', 'source breakdown');
          await probe.capture('category');
          await choose('calendar');
          await measure('_CompactEntryRow', 'calendar entry');
          await probe.capture('calendar');
          await choose('trend');
          await measure('_TrendDayRow', 'trend day');
          await probe.capture('trend');
          // Retain the selected view and unsaved form while locale changes.
          await choose('trend');
          final selectedBefore = tester
              .widgetList<SegmentedButton>(
                find.byWidgetPredicate((w) => w is SegmentedButton),
              )
              .map((w) => Set<Object?>.of(w.selected))
              .toList();
          await tester.tap(find.byType(FloatingActionButton));
          await tester.pumpAndSettle();
          final field = find.byType(TextField).first;
          await probe.reveal(field);
          await tester.enterText(field, 'Retained synthetic draft');
          final controller = tester.widget<TextField>(field).controller!;
          controller.selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 8,
          );
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(TimeAuditScreen)), same(state));
          expect(tester.widget<TextField>(field).controller, same(controller));
          expect(controller.text, 'Retained synthetic draft');
          expect(
            controller.selection,
            const TextSelection(baseOffset: 2, extentOffset: 8),
          );
          expect(
            find.text(I18n.tr('time_audit.sheet.add_title')),
            findsOneWidget,
          );
          await probe.reveal(field);
          await probe.capture('live-form');
          final cancel = find.widgetWithText(
            TextButton,
            I18n.tr('action.cancel'),
          );
          await probe.reveal(cancel);
          expect(cancel.hitTestable(), findsOneWidget);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(find.byType(TextField), findsNothing);
          await showSelector('trend');
          expect(
            tester
                .widgetList<SegmentedButton>(
                  find.byWidgetPredicate((w) => w is SegmentedButton),
                )
                .map((w) => Set<Object?>.of(w.selected))
                .toList(),
            selectedBefore,
          );
          expect(
            provider.entries.map((e) => e.toJson()).toList(),
            initialEntries,
          );
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getStringList(TimeAuditProvider.storageKey), stored);
          final back = find.byType(BackButton);
          expect(back.hitTestable(), findsOneWidget);
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('open-audit')), findsOneWidget);
          await probe.finish();
        });
      }
    }
  }
}
