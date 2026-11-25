// Synthetic route rendering; no account, network, or persistent data operations.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/search_screen.dart';
import 'package:duoyi/screens/time_audit_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

const _title = 'review planning session';
const _subtitle = 'review notes';
final _entry = TimeEntry(
  id: 'synthetic-search-time',
  title: _title,
  note: _subtitle,
  startAt: DateTime(2026, 10, 20, 9),
  endAt: DateTime(2026, 10, 20, 10),
);

class _Anniversaries extends AnniversaryProvider {
  @override
  List<Anniversary> get items => [
    Anniversary(
      id: 'synthetic-search-anniversary',
      title: 'review anniversary',
      originDate: DateTime(2026, 10, 21),
    ),
  ];
}

class _Time extends TimeAuditProvider {
  int reads = 0;
  @override
  List<TimeEntry> get entries {
    reads++;
    return [_entry];
  }
}

Future<void> _highlight(
  WidgetTester tester,
  RouteRenderProbe probe,
  String label,
  double fontSize,
) async {
  final finder = find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText() == label,
  );
  await probe.reveal(finder);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final expected = MediaQuery.textScalerOf(
    tester.element(finder),
  ).scale(fontSize);
  final actual = paragraph.textScaler.scale(fontSize);
  final incomplete = paragraph.didExceedMaxLines;
  if (incomplete) probe.errors.add('$label incomplete');
  if ((actual - expected).abs() > 0.01) {
    probe.errors.add('$label scaler $actual expected $expected');
  }
  probe.rows.add({
    'role': 'highlight',
    'text': label,
    'incomplete': incomplete,
    'actualFontSize': actual,
    'expectedFontSize': expected,
  });
  final boundary =
      probe.boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  final rect = MatrixUtils.transformRect(
    paragraph.getTransformTo(boundary),
    Offset.zero & paragraph.size,
  );
  final background = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final x = (rect.left - 3).floor();
      final y = rect.center.dy.floor();
      expect(x, inInclusiveRange(0, image.width - 1));
      expect(y, inInclusiveRange(0, image.height - 1));
      final offset = (y * image.width + x) * 4;
      return Color.fromARGB(
        255,
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    } finally {
      image.dispose();
    }
  });
  void measure(InlineSpan span, TextStyle inherited) {
    final style = inherited.merge(span.style);
    if (span is! TextSpan) return;
    if (span.text?.isNotEmpty ?? false) {
      final foreground = style.foreground?.color ?? style.color!;
      final a = Color.alphaBlend(foreground, background!).computeLuminance();
      final b = background.computeLuminance();
      final ratio = (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
      final required = paragraph.textScaler.scale(style.fontSize!) >= 24
          ? 3.0
          : 4.5;
      probe.rows.add({
        'role': 'highlight span',
        'text': span.text,
        'foregroundARGB': foreground.toARGB32(),
        'backgroundARGB': background.toARGB32(),
        'ratio': ratio,
        'required': required,
      });
      if (ratio < required) {
        probe.errors.add(
          '$label span ${span.text} contrast $ratio below $required',
        );
      }
    }
    for (final child in span.children ?? <InlineSpan>[]) {
      measure(child, style);
    }
  }

  measure(paragraph.text, const TextStyle());
}

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
        final name = 'search-$brand-${locale.name}-${layout.name}';
        testWidgets('search complete copy and natural scaling $name', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          I18n.setLocale(locale);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final theme = ThemeProvider();
          final time = _Time();
          await tester.runAsync(() async {
            await theme.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            theme.dispose();
            time.dispose();
          });
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<TimeAuditProvider>.value(value: time),
                ChangeNotifierProvider<TodoProvider>(
                  create: (_) => TodoProvider(),
                ),
                ChangeNotifierProvider<HabitProvider>(
                  create: (_) => HabitProvider(),
                ),
                ChangeNotifierProvider<NoteProvider>(
                  create: (_) => NoteProvider(),
                ),
                ChangeNotifierProvider<DiaryProvider>(
                  create: (_) => DiaryProvider(),
                ),
                ChangeNotifierProvider<AnniversaryProvider>(
                  create: (_) => _Anniversaries(),
                ),
                ChangeNotifierProvider<CountdownProvider>(
                  create: (_) => CountdownProvider(),
                ),
                ChangeNotifierProvider<GoalProvider>(
                  create: (_) => GoalProvider(),
                ),
                ChangeNotifierProvider<CourseProvider>(
                  create: (_) => CourseProvider(),
                ),
                ChangeNotifierProvider<CalendarProvider>(
                  create: (_) => CalendarProvider(),
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
                          key: const ValueKey('open_search'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BrandRouteSurface(
                                child: SearchScreen(),
                              ),
                            ),
                          ),
                          child: const Text('Open synthetic search'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('open_search')));
          await tester.pumpAndSettle();
          final probe = RouteRenderProbe(tester, boundary, name);
          await probe.capture('empty');
          await tester.enterText(find.byType(TextField), 'review');
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          expect(time.reads, 1);
          final state = tester.state(find.byType(SearchScreen));
          final controller = tester
              .widget<TextField>(find.byType(TextField))
              .controller!;
          controller.selection = const TextSelection(
            baseOffset: 1,
            extentOffset: 4,
          );
          final value = controller.value;
          for (final stage in ['results', 'live']) {
            if (stage == 'live') {
              I18n.setLocale(
                locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
              );
              await tester.pumpAndSettle();
            }
            // Return to the top before measuring the header of a lazy list.
            final scroll = tester.state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(SearchScreen),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Scrollable &&
                          widget.axisDirection == AxisDirection.down,
                    ),
                  )
                  .first,
            );
            scroll.position.jumpTo(0);
            await tester.pumpAndSettle();
            final summary =
                '${I18n.tr('search.results.summary_prefix')}review${I18n.tr('search.results.summary_middle')}2${I18n.tr('search.results.summary_suffix')}';
            await probe.text(find.text(summary), role: '$stage summary');
            await probe.capture('$stage-summary');
            await probe.text(
              find.text(I18n.tr('search.kind.anniversary')),
              role: '$stage long category',
            );
            await probe.text(
              find.text(I18n.tr('search.kind.time_entry')),
              role: '$stage kind',
            );
            await probe.text(find.text('10/20'), role: '$stage date');
            await _highlight(tester, probe, _title, 13);
            await _highlight(
              tester,
              probe,
              _subtitle,
              theme.brand.theme.textTheme.bodySmall!.fontSize!,
            );
            await probe.capture('$stage-hit');
            expect(tester.state(find.byType(SearchScreen)), same(state));
            expect(controller.value, value);
            expect(time.reads, 1);
            expect(_entry.title, _title);
            expect(_entry.note, _subtitle);
          }
          await probe.reveal(
            find.byWidgetPredicate(
              (widget) =>
                  widget is RichText && widget.text.toPlainText() == _title,
            ),
          );
          await tester.tap(
            find
                .ancestor(
                  of: find.byWidgetPredicate(
                    (widget) =>
                        widget is RichText &&
                        widget.text.toPlainText() == _title,
                  ),
                  matching: find.byType(AppSurfaceCard),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(find.byType(TimeAuditScreen), findsOneWidget);
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(SearchScreen)), same(state));
          expect(controller.value, value);
          final readsAfterReturn = time.reads;
          await tester.enterText(find.byType(TextField), 'absent');
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          expect(time.reads, readsAfterReturn + 1);
          final noResults =
              '${I18n.tr('search.no_results.prefix')}"absent"${I18n.tr('search.no_results.suffix')}';
          await probe.text(find.text(noResults), role: 'no results');
          await probe.capture('no-results');
          await tester.tap(find.byTooltip(I18n.tr('search.clear')).first);
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          expect(controller.text, isEmpty);
          expect(find.text(I18n.tr('search.empty')), findsOneWidget);
          expect(time.reads, readsAfterReturn + 1);
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(find.byType(SearchScreen), findsNothing);
          await probe.finish();
        });
      }
    }
  }
}
