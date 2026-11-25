// Real pushed calendar route; all data is synthetic and read-only.
import 'package:duoyi/core/calendar_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/calendar_month_grid.dart';
import 'package:duoyi/widgets/calendar_week_strip.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

final _selected = DateTime(2026, 6, 29);
final _todo = TodoItem(
  id: 'calendar-theme-task',
  title: 'Synthetic task',
  date: _selected,
  // A date-only deadline bounds this fixture to one calendar day.
  dueDate: _selected,
  createdAt: DateTime(2026, 6, 29, 9),
);

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'calendar-navigation-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient((_) async {
                fail(
                  'The calendar visual fixture must not issue HTTP requests',
                );
              }),
            ),
          );
          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<TodoProvider>(
                  create: (_) => _SyntheticTodos(),
                ),
                ChangeNotifierProvider(create: (_) => HabitProvider()),
                ChangeNotifierProvider(create: (_) => PomodoroProvider()),
                ChangeNotifierProvider(create: (_) => CalendarProvider()),
                ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
                ChangeNotifierProvider(create: (_) => CountdownProvider()),
                ChangeNotifierProvider(create: (_) => CourseProvider()),
                ChangeNotifierProvider(create: (_) => DiaryProvider()),
                ChangeNotifierProvider(create: (_) => GoalProvider()),
                ChangeNotifierProvider(create: (_) => ShareProvider()),
                ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
                ChangeNotifierProvider(create: (_) => PreferencesProvider()),
              ],
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        key: const ValueKey('open_calendar_theme'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BrandRouteSurface(
                              child: CalendarScreen(initialDate: _selected),
                            ),
                          ),
                        ),
                        child: const Text('Open synthetic calendar'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final prefs = await SharedPreferences.getInstance();
          final beforePrefs = {
            for (final key in prefs.getKeys()) key: prefs.get(key),
          };
          await tester.tap(find.byKey(const ValueKey('open_calendar_theme')));
          await tester.pumpAndSettle();
          final route = tester.state(find.byType(CalendarScreen));
          final controller = tester
              .widget<TabBar>(find.byType(TabBar))
              .controller!;
          final probe = RouteRenderProbe(tester, boundary, name);
          Finder tabs() => find.byType(TabBar);
          Future<void> choose(int index) async {
            final label =
                (tester.widget<TabBar>(tabs()).tabs[index] as Tab).text!;
            final tab = find.descendant(of: tabs(), matching: find.text(label));
            await Scrollable.ensureVisible(tester.element(tab), alignment: .5);
            await tester.pumpAndSettle();
            await tester.tap(tab);
            await tester.pumpAndSettle();
            expect(controller.index, index);
          }

          Future<void> header(String stage) async {
            final button = find.byKey(
              const ValueKey('calendar_navigation_date_button'),
            );
            final label = find.descendant(
              of: button,
              matching: find.byType(Text),
            );
            await probe.text(
              label,
              role: '$stage date navigation',
              minimumGeometricScale: .999,
            );
            final active =
                (tester.widget<TabBar>(tabs()).tabs[controller.index] as Tab)
                    .text!;
            await probe.text(
              find.descendant(of: tabs(), matching: find.text(active)),
              role: '$stage active view',
              minimumGeometricScale: .999,
            );
            await probe.capture(stage);
          }

          Future<void> calendarCells(String stage, int view) async {
            if (view == 0) {
              final grid = find.byType(CalendarMonthGrid);
              final labels = find.descendant(
                of: grid,
                matching: find.byType(Text),
              );
              // Weekday headings precede the civil day cells. Lunar previews
              // retain their existing separate one-line preview contract.
              final targets = <Finder>[
                for (var i = 0; i < 7; i++) labels.at(i),
                for (var day = 1; day <= 30; day++)
                  find.descendant(of: grid, matching: find.text('$day')),
              ];
              for (var i = 0; i < targets.length; i++) {
                await probe.text(
                  targets[i],
                  role: '$stage civil heading/day $i',
                  contrast: false,
                  minimumGeometricScale: .999,
                );
              }
            } else if (view == 1) {
              final card = find.descendant(
                of: find.byType(CalendarWeekStrip),
                matching: find.byKey(
                  const ValueKey('calendar_week_strip_skin_card'),
                ),
              );
              final labels = find.descendant(
                of: card,
                matching: find.byType(Text),
              );
              expect(labels, findsNWidgets(14));
              for (var i = 0; i < 14; i++) {
                final label = labels.at(i);
                await Scrollable.ensureVisible(
                  tester.element(label),
                  alignment: .5,
                );
                await tester.pumpAndSettle();
                await probe.text(
                  label,
                  role: '$stage week heading/day $i',
                  contrast: false,
                  minimumGeometricScale: .999,
                );
              }
            }
          }

          Future<void> yearCards(String stage) async {
            final year = find.byKey(const ValueKey('calendar_year_overview'));
            final grid = find.descendant(
              of: year,
              matching: find.byType(GridView),
            );
            for (var month = 1; month <= 12; month++) {
              final title = CalendarUiCopy.yearMonthTitle(month);
              final finder = find.descendant(
                of: year,
                matching: find.text(title),
              );
              if (finder.evaluate().isEmpty) {
                await tester.scrollUntilVisible(
                  finder,
                  160,
                  scrollable: find
                      .descendant(of: grid, matching: find.byType(Scrollable))
                      .first,
                  maxScrolls: 40,
                );
              }
              await probe.text(
                finder,
                role: '$stage month $month',
                minimumGeometricScale: .999,
              );
              final card = find.ancestor(
                of: finder,
                matching: find.byType(AppSurfaceCard),
              );
              final count = CalendarUiCopy.yearMonthEventCount(
                month == 6 ? 1 : 0,
              );
              await probe.text(
                find.descendant(of: card, matching: find.text(count)),
                role: '$stage month $month event count',
                minimumGeometricScale: .999,
              );
              if (month == 6) await probe.capture('$stage-selected-month');
            }
          }

          for (var view = 0; view < 5; view++) {
            await choose(view);
            await header('initial-view-$view');
            await calendarCells('initial-view-$view', view);
          }
          await yearCards('initial-year');
          final yearGrid = find.descendant(
            of: find.byKey(const ValueKey('calendar_year_overview')),
            matching: find.byType(Scrollable),
          );
          final yearScroll = tester.state<ScrollableState>(yearGrid);
          yearScroll.position.jumpTo(20);
          await tester.pumpAndSettle();
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(CalendarScreen)), same(route));
          expect(tester.widget<TabBar>(tabs()).controller, same(controller));
          expect(controller.index, 4);
          expect(tester.state<ScrollableState>(yearGrid), same(yearScroll));
          expect(yearScroll.position.pixels, closeTo(20, .1));
          yearScroll.position.jumpTo(0);
          await tester.pumpAndSettle();
          await yearCards('live-year');
          for (var view = 4; view >= 0; view--) {
            await choose(view);
            await header('live-view-$view');
            await calendarCells('live-view-$view', view);
          }
          expect(
            tester
                .widget<CalendarMonthGrid>(find.byType(CalendarMonthGrid))
                .selectedDay,
            _selected,
          );
          expect({
            for (final key in prefs.getKeys()) key: prefs.get(key),
          }, beforePrefs);
          expect(_todo.title, 'Synthetic task');
          await probe.finish();
        });
      }
    }
  }
}

class _SyntheticTodos extends TodoProvider {
  @override
  List<TodoItem> get todos => [_todo];
}
