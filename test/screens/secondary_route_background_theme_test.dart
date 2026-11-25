import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/ai_history_screen.dart';
import 'package:duoyi/screens/announcements_screen.dart';
import 'package:duoyi/screens/backup_screen.dart';
import 'package:duoyi/screens/export_screen.dart';
import 'package:duoyi/screens/feedback_screen.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart' show priorityLayouts;
import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';

enum _Page {
  backup,
  restore,
  integrations,
  feedback,
  submit,
  announcements,
  ai,
  export,
}

Widget _screen(_Page page) => switch (page) {
  _Page.backup => const BackupScreen(),
  _Page.restore => const BackupScreen(initialMode: BackupEntryMode.restore),
  _Page.integrations => const IntegrationsScreen(),
  _Page.feedback => const FeedbackScreen(),
  _Page.submit => const FeedbackSubmitScreen(),
  _Page.announcements => const AnnouncementsScreen(),
  _Page.ai => const AiHistoryScreen(),
  _Page.export => const ExportScreen(),
};

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass', 're0', 'starRail']) {
    for (final page in _Page.values) {
      for (final pushed in [false, true]) {
        for (final layout
            in brand == 're0' || brand == 'starRail'
                ? [priorityLayouts[1]]
                : priorityLayouts) {
          final name =
              '$brand-${page.name}-${pushed ? "pushed" : "standalone"}-${layout.name}';
          testWidgets('secondary backdrop $name', (tester) async {
            SharedPreferences.setMockInitialValues({'active_brand': brand});
            I18n.setLocale(AppLocale.zh);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final theme = ThemeProvider();
            final transport = MockClient((request) async {
              expect(request.method, 'GET');
              expect(request.url.path, '/api/announcements');
              return http.Response(
                '[]',
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            });
            final auth = AuthProvider(
              client: ApiClient(
                baseUrl: 'https://synthetic.example.test',
                httpClient: transport,
              ),
            );
            final ai = AiService();
            final locale = LocaleProvider();
            final prefs = PreferencesProvider();
            final rewards = AchievementProvider();
            final location = LocationReminderProvider();
            final notifications = NotificationService();
            final sync = CalendarSyncProvider();
            final ann = AnniversaryProvider();
            final calendar = CalendarProvider();
            final countdown = CountdownProvider();
            final course = CourseProvider();
            final diary = DiaryProvider();
            final goal = GoalProvider();
            final habit = HabitProvider();
            final focus = PomodoroProvider();
            final todo = TodoProvider();
            await tester.runAsync(() async {
              await theme.loadFromStorage();
              await loadWeeklyReviewScreenshotFonts();
            });
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              for (final provider in <ChangeNotifier>[
                theme,
                auth,
                ai,
                locale,
                prefs,
                rewards,
                location,
                notifications,
                sync,
                ann,
                calendar,
                countdown,
                course,
                diary,
                goal,
                habit,
                focus,
                todo,
              ]) {
                provider.dispose();
              }
              transport.close();
            });
            final capture = GlobalKey();
            final screen = _screen(page);
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<AuthProvider>.value(value: auth),
                  ChangeNotifierProvider<AiService>.value(value: ai),
                  ChangeNotifierProvider<LocaleProvider>.value(value: locale),
                  ChangeNotifierProvider<PreferencesProvider>.value(
                    value: prefs,
                  ),
                  ChangeNotifierProvider<AchievementProvider>.value(
                    value: rewards,
                  ),
                  ChangeNotifierProvider<LocationReminderProvider>.value(
                    value: location,
                  ),
                  ChangeNotifierProvider<NotificationService>.value(
                    value: notifications,
                  ),
                  ChangeNotifierProvider<CalendarSyncProvider>.value(
                    value: sync,
                  ),
                  ChangeNotifierProvider<AnniversaryProvider>.value(value: ann),
                  ChangeNotifierProvider<CalendarProvider>.value(
                    value: calendar,
                  ),
                  ChangeNotifierProvider<CountdownProvider>.value(
                    value: countdown,
                  ),
                  ChangeNotifierProvider<CourseProvider>.value(value: course),
                  ChangeNotifierProvider<DiaryProvider>.value(value: diary),
                  ChangeNotifierProvider<GoalProvider>.value(value: goal),
                  ChangeNotifierProvider<HabitProvider>.value(value: habit),
                  ChangeNotifierProvider<PomodoroProvider>.value(value: focus),
                  ChangeNotifierProvider<TodoProvider>.value(value: todo),
                ],
                child: MaterialApp(
                  theme: theme.brand.theme,
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: layout.scale < 0
                          ? const RouteProbeNonlinearScaler()
                          : TextScaler.linear(layout.scale),
                    ),
                    child: RepaintBoundary(key: capture, child: child!),
                  ),
                  home: pushed
                      ? Builder(
                          builder: (context) => Scaffold(
                            body: TextButton(
                              key: const ValueKey('open_secondary_backdrop'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  // Feedback submission is a plain route in production.
                                  builder: (_) => page == _Page.submit
                                      ? screen
                                      : BrandRouteSurface(child: screen),
                                ),
                              ),
                              child: const Text('Open synthetic route'),
                            ),
                          ),
                        )
                      : screen,
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (pushed) {
              await tester.tap(
                find.byKey(const ValueKey('open_secondary_backdrop')),
              );
              await tester.pumpAndSettle();
            }
            expect(theme.brand.id, brand);
            final finder = find.byWidget(screen);
            final element = tester.element(finder);
            // Integrations owns its retained tab selection below its StatelessWidget.
            final stateFinder = page == _Page.integrations
                ? find.byType(DefaultTabController)
                : finder;
            final state = tester.state(stateFinder);
            final points = [
              for (final f in [.35, .65, .9]) Offset(2, layout.size.height * f),
            ];
            final actual = <String, List<int>>{};
            final backgroundLayers = <String, int>{};
            final errors = <Object>[];
            for (final selected in [AppLocale.zh, AppLocale.en]) {
              I18n.setLocale(selected);
              await tester.pumpAndSettle();
              expect(tester.element(finder), same(element));
              expect(tester.state(stateFinder), same(state));
              actual[selected.name] = await _pixels(tester, capture, points);
              backgroundLayers[selected.name] = find
                  .byType(BrandBackground)
                  .evaluate()
                  .length;
              await _screenshot(tester, capture, '$name-${selected.name}');
              final error = tester.takeException();
              if (error != null) errors.add(error);
            }
            if (pushed) {
              Navigator.of(element).pop();
              await tester.pumpAndSettle();
              expect(
                find.byKey(const ValueKey('open_secondary_backdrop')),
                findsOneWidget,
              );
            }
            final reference = GlobalKey();
            final t = theme.brand.theme;
            final routeBackground = page == _Page.ai
                ? t.scaffoldBackgroundColor
                : t.brightness == Brightness.dark
                ? t.colorScheme.surface
                : t.colorScheme.surfaceContainerLowest;
            // Independent reference is rendered only AFTER removing the page.
            await tester.pumpWidget(
              ChangeNotifierProvider<ThemeProvider>.value(
                value: theme,
                child: MaterialApp(
                  theme: t,
                  home: RepaintBoundary(
                    key: reference,
                    child: Material(
                      color: routeBackground,
                      child: brand == 'liquidGlass'
                          ? const BrandBackground(child: SizedBox.expand())
                          : const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final expected = await _pixels(tester, reference, points);
            final output =
                Platform.environment['DUOYI_ROUTE_BACKDROP_EVIDENCE'];
            if (output != null) {
              await tester.runAsync(() async {
                final file = File('$output/$name.json');
                file.parent.createSync(recursive: true);
                file.writeAsStringSync(
                  jsonEncode({
                    'name': name,
                    'brand': brand,
                    'page': page.name,
                    'actual': actual,
                    'backgroundLayers': backgroundLayers,
                    'reference': expected,
                    'renderErrors': [for (final error in errors) '$error'],
                    'stateRetained': true,
                    'pushed': pushed,
                  }),
                );
              });
            }
            for (final entry in actual.entries) {
              expect(
                entry.value,
                expected,
                reason: '$name ${entry.key}: preserve route background policy',
              );
            }
            expect(errors, isEmpty, reason: '$name: no rendering errors');
            final expectedLayers =
                brand == 'liquidGlass' || (pushed && page != _Page.submit)
                ? 1
                : 0;
            for (final count in backgroundLayers.values) {
              expect(
                count,
                expectedLayers,
                reason: '$name: background is owned once',
              );
            }
          });
        }
      }
    }
  }
}

Future<List<int>> _pixels(
  WidgetTester tester,
  GlobalKey key,
  List<Offset> points,
) async => (await tester.runAsync(() async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return [
      for (final point in points)
        data.getUint32((point.dy.floor() * image.width + point.dx.floor()) * 4),
    ];
  } finally {
    image.dispose();
  }
}))!;

Future<void> _screenshot(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final output = Platform.environment['DUOYI_ROUTE_BACKDROP_SCREENSHOTS'];
  if (output == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('$output/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
