import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/screens/note_screen.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/screens/course_schedule_screen.dart';
import 'package:duoyi/screens/goal_edit_screen.dart';
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
  diary,
  diaryEdit,
  note,
  noteEdit,
  anniversary,
  countdown,
  course,
  goalEdit,
}

Widget _screen(_Page page) => switch (page) {
  _Page.diary => const DiaryScreen(),
  _Page.diaryEdit => const DiaryEditScreen(),
  _Page.note => const NoteScreen(),
  _Page.noteEdit => const NoteEditScreen(),
  _Page.anniversary => const AnniversaryScreen(),
  _Page.countdown => const CountdownScreen(),
  _Page.course => const CourseScheduleScreen(),
  _Page.goalEdit => const GoalEditScreen(),
};

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand
      in (Platform.environment['DUOYI_LIBRARY_SMOKE'] == '1'
          ? ['defaultBrand', 'liquidGlass']
          : ['defaultBrand', 'liquidGlass', 're0', 'starRail'])) {
    for (final page in _Page.values) {
      for (final pushed
          in (Platform.environment['DUOYI_LIBRARY_SMOKE'] == '1'
              ? [true]
              : [false, true])) {
        for (final layout
            in Platform.environment['DUOYI_LIBRARY_SMOKE'] == '1'
                ? [priorityLayouts[0]]
                : brand == 're0' || brand == 'starRail'
                ? [priorityLayouts[1]]
                : priorityLayouts) {
          final name =
              '$brand-${page.name}-${pushed ? "pushed" : "standalone"}-${layout.name}';
          testWidgets('library backdrop $name', (tester) async {
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
            final notes = NoteProvider();
            final sounds = CustomFocusSoundProvider();
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
                notes,
                sounds,
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
                  ChangeNotifierProvider<NoteProvider>.value(value: notes),
                  ChangeNotifierProvider<CustomFocusSoundProvider>.value(
                    value: sounds,
                  ),
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
                                  // Main and pushed consumers provide the shared branded surface.
                                  builder: (_) =>
                                      BrandRouteSurface(child: screen),
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
            final state = screen is StatefulWidget
                ? tester.state(finder)
                : null;
            final controllers = await _editorControllers(
              tester,
              finder,
              lazyDiary: page == _Page.diaryEdit,
            );
            final values = [for (final c in controllers) c?.value];
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
              if (state != null) expect(tester.state(finder), same(state));
              final mountedControllers = await _editorControllers(
                tester,
                finder,
                lazyDiary: page == _Page.diaryEdit,
              );
              expect(mountedControllers, orderedEquals(controllers));
              expect([for (final c in mountedControllers) c?.value], values);
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
            final routeBackground =
                [
                  _Page.diaryEdit,
                  _Page.anniversary,
                  _Page.countdown,
                ].contains(page)
                ? t.brightness == Brightness.dark
                      ? t.colorScheme.surface
                      : t.colorScheme.surfaceContainerLowest
                : t.scaffoldBackgroundColor;
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
            final expectedLayers = brand == 'liquidGlass' || pushed ? 1 : 0;
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

// Translated mood/weather labels change the height of the lazy diary list.
// Visit its full extent so offscreen editors are included in the identity/value
// check, then restore the viewport before background and screenshot probes.
Future<List<TextEditingController?>> _editorControllers(
  WidgetTester tester,
  Finder route, {
  required bool lazyDiary,
}) async {
  List<TextEditingController?> mounted() => [
    for (final e
        in find
            .descendant(of: route, matching: find.byType(TextField))
            .evaluate())
      (e.widget as TextField).controller,
  ];
  if (!lazyDiary) return mounted();
  final list = find.descendant(of: route, matching: find.byType(ListView));
  expect(list, findsOneWidget);
  final scrollable = tester.state<ScrollableState>(
    find.descendant(of: list, matching: find.byType(Scrollable)).first,
  );
  final position = scrollable.position;
  final originalOffset = position.pixels;
  final controllers = <TextEditingController?>[];
  try {
    position.jumpTo(0);
    await tester.pumpAndSettle();
    for (var step = 0; step < 50; step++) {
      for (final controller in mounted()) {
        expect(controller, isNotNull);
        if (!controllers.contains(controller)) controllers.add(controller);
      }
      if (position.pixels >= position.maxScrollExtent) break;
      expect(
        step,
        lessThan(49),
        reason: 'Visit the complete diary editor list.',
      );
      position.jumpTo(
        (position.pixels + position.viewportDimension * .8).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
    }
  } finally {
    position.jumpTo(originalOffset.clamp(0.0, position.maxScrollExtent));
    await tester.pumpAndSettle();
  }
  expect(
    controllers,
    hasLength(2),
    reason: 'Retain both tag and body editors.',
  );
  return controllers;
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
