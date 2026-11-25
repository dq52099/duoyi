// Synthetic in-memory statistics; no network, clipboard, export or saved mutations.
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/statistics_ui_copy.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/services/ai_service.dart';
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

Finder _rangeSegments() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString().startsWith('SegmentedButton<'),
);

// A chart may add a horizontal viewport inside the vertical page. Asking the
// vertical ScrollPosition to reveal a descendant of that viewport uses the
// wrong viewport offsets. Flutter's multi-scrollable API walks both axes.
class _TrendRenderProbe extends RouteRenderProbe {
  _TrendRenderProbe(super.tester, super.boundary, super.name);

  @override
  Future<void> reveal(Finder finder) async {
    expect(finder, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(finder));
    await tester.pumpAndSettle();
  }
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
        (name: 'transition', size: const Size(414, 844), scale: -1.0),
      ]) {
        final name = 'statistics-trend-$brand-${locale.name}-${layout.name}';
        testWidgets('statistics trend route readable and retained $name', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          I18n.setLocale(locale);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final todos = TodoProvider();
          final goals = GoalProvider();
          final habits = HabitProvider();
          final focus = PomodoroProvider();
          final diary = DiaryProvider();
          final time = TimeAuditProvider();
          final ai = AiService();
          final theme = ThemeProvider();
          await theme.loadFromStorage();
          final now = DateTime.now();
          todos.todos.add(
            TodoItem(
              id: 'done',
              title: 'Synthetic done task',
              isCompleted: true,
              completedAt: now,
              updatedAt: now,
            ),
          );
          focus.sessions.add(
            PomodoroSession(
              id: 'focus',
              startTime: now.subtract(const Duration(minutes: 75)),
              endTime: now,
              durationSeconds: 4500,
              type: PomodoroType.focus,
            ),
          );
          for (final daysAgo in [14, 45]) {
            final earlier = now.subtract(Duration(days: daysAgo));
            for (var n = 0; n < 4; n++) {
              todos.todos.add(
                TodoItem(
                  id: 'earlier-$daysAgo-$n',
                  title: 'Synthetic historical task',
                  isCompleted: true,
                  completedAt: earlier,
                  updatedAt: earlier,
                ),
              );
            }
            focus.sessions.add(
              PomodoroSession(
                id: 'earlier-focus-$daysAgo',
                startTime: earlier.subtract(const Duration(minutes: 150)),
                endTime: earlier,
                durationSeconds: 9000,
                type: PomodoroType.focus,
              ),
            );
          }
          final initialTodos = todos.todos.map((e) => e.toJson()).toList();
          final initialFocus = focus.sessions.map((e) => e.toJson()).toList();
          await tester.runAsync(loadWeeklyReviewScreenshotFonts);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            todos.dispose();
            goals.dispose();
            habits.dispose();
            focus.dispose();
            diary.dispose();
            time.dispose();
            ai.dispose();
            theme.dispose();
          });
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<TodoProvider>.value(value: todos),
                ChangeNotifierProvider<GoalProvider>.value(value: goals),
                ChangeNotifierProvider<HabitProvider>.value(value: habits),
                ChangeNotifierProvider<PomodoroProvider>.value(value: focus),
                ChangeNotifierProvider<DiaryProvider>.value(value: diary),
                ChangeNotifierProvider<TimeAuditProvider>.value(value: time),
                ChangeNotifierProvider<AiService>.value(value: ai),
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ],
              child: ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, selected, _) => MaterialApp(
                  locale: Locale(selected.name),
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
                          key: const ValueKey('open-statistics'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BrandRouteSurface(
                                child: StatisticsScreen(),
                              ),
                            ),
                          ),
                          child: const Text('Open synthetic statistics'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('open-statistics')));
          await tester.pumpAndSettle();
          expect(theme.brand.id, brand);
          final state = tester.state(find.byType(StatisticsScreen));
          final scroll = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView).first,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          final probe = _TrendRenderProbe(tester, boundary, name);
          Future<void> top() async {
            scroll.position.jumpTo(0);
            await tester.pumpAndSettle();
          }

          Future<void> measure(Finder scope, String role) async {
            final labels = find.descendant(
              of: scope,
              matching: find.byType(Text),
            );
            final count = labels.evaluate().length;
            expect(count, greaterThan(0), reason: role);
            for (var i = 0; i < count; i++) {
              final text = labels.at(i);
              if (tester.widget<Text>(text).data == null) continue;
              final diagnosticLabel = tester.widget<Text>(text).data!;
              final diagnosticOffset = scroll.position.pixels;
              final horizontal = Scrollable.maybeOf(
                tester.element(text),
                axis: Axis.horizontal,
              );
              if (horizontal != null) {
                await horizontal.position.ensureVisible(
                  tester.renderObject(text),
                );
                await tester.pumpAndSettle();
              }
              await probe.reveal(text);
              if (scope.evaluate().isEmpty) {
                fail(
                  '$role lost scope after revealing index $i ($diagnosticLabel): '
                  'page offset $diagnosticOffset -> ${scroll.position.pixels}',
                );
              }
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: text, matching: find.byType(RichText)),
              );
              final context = tester.element(text);
              final label = tester.widget<Text>(text).data!;
              var widest = 0.0;
              for (final token in RegExp(
                r'[A-Za-z0-9%+.,−-]+|[^\x00-\x7F]',
              ).allMatches(label).map((match) => match.group(0)!)) {
                final painter = TextPainter(
                  text: TextSpan(text: token, style: paragraph.text.style),
                  textScaler: MediaQuery.textScalerOf(context),
                  textDirection: Directionality.of(context),
                )..layout();
                if (painter.width > widest) widest = painter.width;
                painter.dispose();
              }
              if (widest > paragraph.size.width + 0.1) {
                probe.errors.add('$role $label: ordinary token cannot fit');
              }
              await probe.text(text, role: role);
              probe.rows.last.addAll({
                'widestToken': widest,
                'availableWidth': paragraph.size.width,
              });
            }
          }

          Future<Finder> revealTrend() async {
            final trend = _component('_ProductivityTrendCard');
            await tester.scrollUntilVisible(
              trend,
              200,
              scrollable: find
                  .descendant(
                    of: find.byType(ListView).first,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            return trend;
          }

          List<List<Object?>> identity(dynamic widget) => [
            for (final dynamic point in widget.points as List)
              [
                point.start.toIso8601String(),
                point.end.toIso8601String(),
                point.score,
                point.completedTodos,
                point.focusMinutes,
                point.habitCheckIns,
                point.timeEntryMinutes,
                point.isCurrentPeriod,
              ],
          ];

          Future<void> measureDetail(String role) async {
            final detail = _component('_ProductivityTrendDetailScreen');
            final detailScroll = find
                .descendant(of: detail, matching: find.byType(Scrollable))
                .first;
            tester.state<ScrollableState>(detailScroll).position.jumpTo(0);
            await tester.pumpAndSettle();
            await measure(
              find.descendant(of: detail, matching: find.byType(AppBar)),
              '$role-appbar',
            );
            final overview = find
                .descendant(of: detail, matching: _component('AppSurfaceCard'))
                .first;
            await measure(overview, '$role-overview');
            final dynamic widget = tester.widget(detail);
            final copy = StatisticsUiCopy.current();
            var checkedTiles = 0;
            for (final dynamic point in (widget.points as List).reversed) {
              final tile = find.descendant(
                of: detail,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget.runtimeType.toString() == '_TrendDetailTile' &&
                      identical((widget as dynamic).point, point),
                ),
              );
              await tester.scrollUntilVisible(
                tile,
                160,
                scrollable: detailScroll,
              );
              expect(tile, findsOneWidget);
              final content = tester
                  .widgetList<Text>(
                    find.descendant(of: tile, matching: find.byType(Text)),
                  )
                  .map((text) => text.data ?? text.textSpan!.toPlainText())
                  .join(' ');
              expect(content, contains(point.displayLabel(copy) as String));
              expect(content, contains(point.dateRangeLabel(copy) as String));
              expect(content, contains(copy.pointsCount(point.score as int)));
              expect(
                find.descendant(
                  of: tile,
                  matching: _component('_TrendDetailMetric'),
                ),
                findsNWidgets(4),
              );
              await measure(tile, '$role-tile-$checkedTiles');
              checkedTiles++;
            }
            expect(checkedTiles, 6);
            await probe.capture('$role-bottom');
          }

          Future<void> checkTrend(String role) async {
            final trend = await revealTrend();
            final chart = find.descendant(
              of: trend,
              matching: find.byType(LineChart),
            );
            expect(chart, findsOneWidget);
            final dynamic trendWidget = tester.widget(trend);
            final data = tester.widget<LineChart>(chart).data;
            final points = trendWidget.points as List;
            expect(data.minY, 0);
            expect(data.maxY, 100);
            expect(
              data.lineBarsData.single.spots
                  .map((spot) => [spot.x, spot.y])
                  .toList(),
              [
                for (var i = 0; i < points.length; i++)
                  [i.toDouble(), (points[i] as dynamic).score.toDouble()],
              ],
            );
            // All axis labels stay represented. Readability cannot be bought by
            // dropping dates or changing score/period identities.
            final copy = StatisticsUiCopy.current();
            final axisLabels = find.descendant(
              of: chart,
              matching: find.byType(Text),
            );
            for (final dynamic point in points) {
              expect(
                find.descendant(
                  of: chart,
                  matching: find.text(point.displayLabel(copy) as String),
                ),
                findsOneWidget,
              );
            }
            final rects = <Rect>[];
            for (var i = 0; i < axisLabels.evaluate().length; i++) {
              rects.add(tester.getRect(axisLabels.at(i)));
            }
            for (var i = 0; i < rects.length; i++) {
              for (var j = i + 1; j < rects.length; j++) {
                final overlap = rects[i].intersect(rects[j]);
                if (overlap.width > 0.5 && overlap.height > 0.5) {
                  probe.errors.add(
                    '$role chart axis labels overlap: $i and $j',
                  );
                }
              }
            }
            for (var i = 1; i < points.length; i++) {
              final dynamic leftPoint = points[i - 1];
              final dynamic rightPoint = points[i];
              final leftLabel = leftPoint.displayLabel(copy) as String;
              final rightLabel = rightPoint.displayLabel(copy) as String;
              final left = tester.getRect(
                find.descendant(of: chart, matching: find.text(leftLabel)),
              );
              final right = tester.getRect(
                find.descendant(of: chart, matching: find.text(rightLabel)),
              );
              final gap = right.left - left.right;
              probe.rows.add({
                'role': '$role bottom-axis-gap-$i',
                'leftLabel': leftLabel,
                'rightLabel': rightLabel,
                'gapPx': gap,
                'requiredGapPx': 4.0,
              });
              if (gap < 3.9) {
                probe.errors.add(
                  '$role adjacent bottom labels $leftLabel / $rightLabel: '
                  'gap $gap below 4',
                );
              }
            }
            await measure(trend, role);
            final title = find.descendant(
              of: trend,
              matching: find.text(copy.productivityTrend),
            );
            await probe.reveal(title);
            await probe.capture('$role-header');
            await probe.reveal(
              find.descendant(
                of: chart,
                matching: find.text(
                  (points.last as dynamic).displayLabel(copy) as String,
                ),
              ),
            );
            await probe.capture('$role-chart');
          }

          await measure(_rangeSegments(), 'week-selector');
          await checkTrend('week');
          final dynamic weekWidget = tester.widget(
            _component('_ProductivityTrendCard'),
          );
          final weekIdentity = identity(weekWidget);
          expect(weekIdentity, hasLength(6));
          final VoidCallback oldOpen = weekWidget.onOpenDetail as VoidCallback;
          final detailButton = find.descendant(
            of: _component('_ProductivityTrendCard'),
            matching: find.byTooltip(
              StatisticsUiCopy.current().viewTrendDetail,
            ),
          );
          await probe.reveal(detailButton);
          await tester.tap(detailButton);
          await tester.pumpAndSettle();
          final detail = _component('_ProductivityTrendDetailScreen');
          expect(detail, findsOneWidget);
          final detailState = tester.state(detail);
          expect(identity(tester.widget(detail)), weekIdentity);
          oldOpen(); // Retained callback from the covered parent is inert.
          await tester.pumpAndSettle();
          expect(detail, findsOneWidget);
          await measureDetail('week-detail');
          final opposite = locale == AppLocale.en ? AppLocale.zh : AppLocale.en;
          I18n.setLocale(opposite);
          await tester.pumpAndSettle();
          expect(identical(tester.state(detail), detailState), isTrue);
          expect(identity(tester.widget(detail)), weekIdentity);
          expect(
            find.text(StatisticsUiCopy.current().trendDetailTitle),
            findsOneWidget,
          );
          final detailScroll = tester.state<ScrollableState>(
            find
                .descendant(of: detail, matching: find.byType(Scrollable))
                .first,
          );
          detailScroll.position.jumpTo(0);
          await tester.pumpAndSettle();
          await probe.capture('detail-locale');
          await measureDetail('detail-locale');
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(detail, findsNothing);
          expect(
            identical(tester.state(find.byType(StatisticsScreen)), state),
            isTrue,
          );
          await top();
          await tester.tap(
            find.descendant(
              of: _rangeSegments(),
              matching: find.text(StatisticsUiCopy.current().rangeMonth),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            ((tester.widget(_rangeSegments()) as dynamic).selected as Set)
                .single
                .toString(),
            contains('month'),
          );
          await measure(_rangeSegments(), 'month-selector');
          await probe.capture('month-selector');
          await checkTrend('month');
          final dynamic monthWidget = tester.widget(
            _component('_ProductivityTrendCard'),
          );
          final monthIdentity = identity(monthWidget);
          expect(monthIdentity, hasLength(6));
          expect(monthIdentity, isNot(weekIdentity));
          final monthButton = find.descendant(
            of: _component('_ProductivityTrendCard'),
            matching: find.byTooltip(
              StatisticsUiCopy.current().viewTrendDetail,
            ),
          );
          await probe.reveal(monthButton);
          await tester.tap(monthButton);
          await tester.pumpAndSettle();
          expect(identity(tester.widget(detail)), monthIdentity);
          await measureDetail('month-detail');
          final monthDetailScroll = tester.state<ScrollableState>(
            find
                .descendant(of: detail, matching: find.byType(Scrollable))
                .first,
          );
          monthDetailScroll.position.jumpTo(0);
          await tester.pumpAndSettle();
          await probe.capture('month-detail');
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          await top();
          expect(
            ((tester.widget(_rangeSegments()) as dynamic).selected as Set)
                .single
                .toString(),
            contains('month'),
          );
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('open-statistics')), findsOneWidget);
          expect(todos.todos.map((e) => e.toJson()).toList(), initialTodos);
          expect(focus.sessions.map((e) => e.toJson()).toList(), initialFocus);
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getKeys(), {'active_brand'});
          expect(prefs.getString('active_brand'), brand);
          await probe.finish();
        });
      }
    }
  }
}
