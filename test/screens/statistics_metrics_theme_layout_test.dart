// Synthetic in-memory statistics; no network, clipboard, export or saved mutations.
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/statistics_ui_copy.dart';
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
        (name: 'transition', size: const Size(414, 844), scale: -1.0),
        (name: 'two-column-large', size: const Size(390, 844), scale: 2.0),
        (name: 'wide-phone-large', size: const Size(430, 844), scale: 2.0),
      ]) {
        final name = 'statistics-$brand-${locale.name}-${layout.name}';
        testWidgets('statistics metrics readable and retained $name', (
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
          final probe = RouteRenderProbe(tester, boundary, name);
          Future<void> top() async {
            scroll.position.jumpTo(0);
            await tester.pumpAndSettle();
          }

          Future<void> measureHeader(
            AppLocale visibleLocale,
            String stage,
          ) async {
            final copy = StatisticsUiCopy(visibleLocale);
            final appBar = find.byType(AppBar);
            final title = find.descendant(
              of: appBar,
              matching: find.text(copy.pageTitle),
            );
            await probe.text(
              title,
              role: '$stage-page-title',
              minimumGeometricScale: 0.99,
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: title, matching: find.byType(RichText)),
            );
            final expectedFontSize =
                theme.brand.theme.appBarTheme.titleTextStyle!.fontSize;
            expect(paragraph.text.style!.fontSize, expectedFontSize);
            final titleRect = tester.getRect(title);
            final barRect = tester.getRect(appBar);
            expect(titleRect.left, greaterThanOrEqualTo(0));
            expect(titleRect.right, lessThanOrEqualTo(layout.size.width));
            expect(titleRect.top, greaterThanOrEqualTo(barRect.top));
            final segments = tester.getRect(_rangeSegments());
            expect(titleRect.bottom, lessThanOrEqualTo(segments.top + 0.1));
            expect(segments.bottom, lessThanOrEqualTo(barRect.bottom + 0.1));
            final controls = <Map<String, double>>[];
            for (final button in [
              find.byType(BackButton),
              find.byTooltip(copy.copyReportTooltip),
              find.byTooltip(copy.reportShareImageTooltip),
            ]) {
              expect(button.hitTestable(), findsOneWidget);
              final rect = tester.getRect(button);
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(layout.size.width));
              expect(rect.top, greaterThanOrEqualTo(barRect.top));
              expect(rect.bottom, lessThanOrEqualTo(segments.top + 0.1));
              expect(titleRect.overlaps(rect), isFalse);
              controls.add({'width': rect.width, 'height': rect.height});
            }
            probe.rows.last['controls'] = controls;
            await probe.capture('$stage-header');
          }

          await measureHeader(locale, 'initial');

          Future<void> measure(String type, String role) async {
            final components = _component(type);
            if (components.evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                components,
                160,
                scrollable: find
                    .descendant(
                      of: find.byType(ListView).first,
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );
            }
            final count = components.evaluate().length;
            expect(count, type == '_Kpi' ? 5 : 1);
            for (var n = 0; n < count; n++) {
              final texts = find.descendant(
                of: components.at(n),
                matching: find.byType(Text),
              );
              final textCount = texts.evaluate().length;
              for (var i = 0; i < textCount; i++) {
                final text = texts.at(i);
                // KPI cards sit in a non-scrolling GridView. Reveal through
                // the enclosing page, rather than its inner Scrollable.
                await scroll.position.ensureVisible(tester.renderObject(text));
                await tester.pumpAndSettle();
                await probe.reveal(text);
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(of: text, matching: find.byType(RichText)),
                );
                final label = tester.widget<Text>(text).data!;
                var widestToken = 0.0;
                final context = tester.element(text);
                // CJK text can wrap between characters; Latin words/numbers
                // still need room without splitting ordinary tokens.
                final tokens = RegExp(
                  r'[A-Za-z0-9%+.,−-]+|[^\x00-\x7F]',
                ).allMatches(label).map((match) => match.group(0)!);
                for (final token in tokens) {
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
                await probe.text(text, role: role);
                probe.rows.last.addAll({
                  'widestToken': widestToken,
                  'availableWidth': paragraph.size.width,
                });
              }
            }
          }

          await probe.capture('root');
          await measure('_Kpi', 'week-kpi');
          await measure('_ProductivityComparisonCard', 'week-comparison');
          await scroll.position.ensureVisible(
            tester.renderObject(_component('_ProductivityComparisonCard')),
          );
          await tester.pumpAndSettle();
          await probe.capture('comparison');
          await scroll.position.ensureVisible(
            tester.renderObject(_component('_ProductivityComparisonCard')),
            alignment: 1,
          );
          await tester.pumpAndSettle();
          await probe.capture('comparison-bottom');
          await top();
          // The generic type is private; locate the actual segment label instead.
          final month = find.descendant(
            of: _rangeSegments(),
            matching: find.text(locale == AppLocale.en ? 'This month' : '本月'),
          );
          expect(month, findsOneWidget);
          await tester.tap(month);
          await tester.pumpAndSettle();
          expect(
            identical(tester.state(find.byType(StatisticsScreen)), state),
            isTrue,
          );
          await measure('_Kpi', 'month-kpi');
          await top();
          final opposite = locale == AppLocale.en ? AppLocale.zh : AppLocale.en;
          I18n.setLocale(opposite);
          await tester.pumpAndSettle();
          expect(
            identical(tester.state(find.byType(StatisticsScreen)), state),
            isTrue,
          );
          expect(
            find.descendant(
              of: _rangeSegments(),
              matching: find.text(
                opposite == AppLocale.en ? 'This month' : '本月',
              ),
            ),
            findsOneWidget,
          );
          await measureHeader(opposite, 'live-locale');
          // Verify selected range through the actual widget, retaining its State.
          final segment = tester.widget(_rangeSegments()) as dynamic;
          expect(
            (segment.selected as Set).single.toString(),
            contains('month'),
          );
          await probe.capture('locale-month');
          await top();
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('open-statistics')), findsOneWidget);
          expect(find.byType(StatisticsScreen), findsNothing);
          expect(todos.todos.map((e) => e.toJson()).toList(), initialTodos);
          expect(focus.sessions.map((e) => e.toJson()).toList(), initialFocus);
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getKeys(), {'active_brand'});
          expect(prefs.getString('active_brand'), brand);
          expect(probe.rows, hasLength(39));
          await probe.finish();
        });
      }
    }
  }
}
