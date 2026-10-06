import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/habit_weekly_card.dart';
import 'package:duoyi/widgets/surface_components.dart';
import '../support/widget_polish_screenshot_font.dart';

final _captureKey = GlobalKey();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'today habit detail opens and shows provider data at width $width / 1.3x',
      (tester) async {
        final today = DateTime.now();
        final habit = Habit(
          id: 'weekly-card-reading',
          name: '阅读',
          targetCount: 4,
          completions: {
            Habit(id: 'date-key-helper', name: 'helper').dateKey(today): 2,
          },
          createdAt: today.subtract(const Duration(days: 30)),
        );
        final provider = HabitProvider();
        await provider.addHabit(habit);

        await _pumpWeeklyCard(tester, provider, width: width, textScale: 1.3);

        final todayIndex = DateTime.now().weekday - 1;
        final todayCell = find.byKey(
          ValueKey('habit_weekly_overview_day_$todayIndex'),
        );
        expect(todayCell, findsOneWidget);
        await tester.ensureVisible(todayCell);
        await tester.tap(todayCell);
        await tester.pumpAndSettle();

        expect(find.byType(AppModalSheet), findsOneWidget);
        expect(find.text('阅读'), findsOneWidget);
        expect(find.text('2 次 / 4 次'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, 'habit-day-detail-${width.toInt()}');
      },
    );
  }

  testWidgets('day detail updates live after a habit check-in', (tester) async {
    final provider = HabitProvider();
    await provider.addHabit(
      Habit(
        id: 'live-update',
        name: '实时更新',
        targetCount: 2,
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
      ),
    );

    await _pumpWeeklyCard(tester, provider);
    await tester.tap(_dayCell(DateTime.now()));
    await tester.pumpAndSettle();

    expect(find.text('0 次 / 2 次'), findsOneWidget);
    expect(find.text('未达标'), findsOneWidget);

    await provider.incrementHabitForDate('live-update', DateTime.now());
    await tester.pumpAndSettle();

    expect(find.text('1 次 / 2 次'), findsOneWidget);
    expect(find.text('未达标'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'future weekday cells are disabled',
    (tester) async {
      final provider = HabitProvider();
      await provider.addHabit(
        Habit(
          id: 'future-day',
          name: '未来日期',
          createdAt: DateTime.now().subtract(const Duration(days: 10)),
        ),
      );
      await _pumpWeeklyCard(tester, provider);

      final todayIndex = DateTime.now().weekday - 1;
      final futureIndex = (todayIndex + 1) % DateTime.daysPerWeek;
      final futureCell = find.byKey(
        ValueKey('habit_weekly_overview_day_$futureIndex'),
      );
      await tester.tap(futureCell);
      await tester.pumpAndSettle();

      expect(find.byType(AppModalSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
    skip: DateTime.now().weekday == DateTime.sunday,
  );

  testWidgets('past date detail filters habits created after that date', (
    tester,
  ) async {
    final today = _dateOnly(DateTime.now());
    final monday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    final afterMonday = DateTime(monday.year, monday.month, monday.day + 1);
    final oldHabit = Habit(
      id: 'already-created',
      name: '较早创建',
      targetCount: 1,
      completions: {
        Habit(id: 'past-key-helper', name: 'helper').dateKey(monday): 1,
      },
      createdAt: monday.subtract(const Duration(days: 14)),
    );
    final newHabit = Habit(
      id: 'created-later',
      name: '后来创建',
      createdAt: afterMonday,
    );
    final provider = HabitProvider();
    await provider.addHabit(oldHabit);
    await provider.addHabit(newHabit);

    await _pumpWeeklyCard(tester, provider);
    await tester.tap(_dayCell(monday));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('habit_day_detail_already-created')),
      findsOneWidget,
    );
    expect(find.text('较早创建'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('habit_day_detail_created-later')),
      findsNothing,
    );
    expect(find.text('后来创建'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'generation invalidation removes the detail sheet once below a dialog',
    (tester) async {
      final provider = HabitProvider();
      await provider.addHabit(
        Habit(
          id: 'invalidated-detail',
          name: '失效后关闭',
          createdAt: DateTime.now().subtract(const Duration(days: 10)),
        ),
      );
      final observer = _RecordingNavigatorObserver();
      await _pumpWeeklyCard(tester, provider, observer: observer);

      await tester.tap(_dayCell(DateTime.now()));
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsOneWidget);

      final sheetContext = tester.element(find.byType(AppModalSheet));
      unawaited(
        showDialog<void>(
          context: sheetContext,
          builder: (dialogContext) => AlertDialog(
            title: const Text('保留的对话框'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      final removedBeforeInvalidation = observer.removedRoutes.length;
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpAndSettle();

      expect(find.byType(AppModalSheet), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('保留的对话框'), findsOneWidget);
      expect(observer.removedRoutes.length - removedBeforeInvalidation, 1);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(observer.removedRoutes.length - removedBeforeInvalidation, 1);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('habit_weekly_overview_card')),
        findsOneWidget,
      );
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final textScale in [1.3, 1.6]) {
      testWidgets(
        'admin overview KPIs fit at $width px / ${textScale}x text scale',
        (tester) async {
          final requests = <String>[];
          final client = ApiClient(
            baseUrl: 'https://duoyi.test',
            token: 'admin-token',
            httpClient: MockClient((request) async {
              requests.add('${request.method} ${request.url.path}');
              if (request.method == 'GET' &&
                  request.url.path == '/api/admin/stats') {
                return http.Response(
                  json.encode({
                    'users': {
                      'total': 12345,
                      'admin': 6,
                      'disabled': 7,
                      'new_today': 8,
                      'active_7d': 9012,
                      'online': 10,
                      'unverified_email': 11,
                    },
                    'feedback': {'total': 12, 'open': 13, 'in_progress': 14},
                    'announcements': {'total': 15, 'published': 16},
                    'invites': {'total': 17, 'used': 18},
                    'registration_series': <Map<String, Object?>>[],
                  }),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              return http.Response('not found', 404);
            }),
          );

          await _pumpAdminDashboard(
            tester,
            client,
            width: width,
            textScale: textScale,
          );

          expect(find.text('总用户'), findsOneWidget);
          expect(find.text('12345'), findsOneWidget);
          expect(find.text('近 7 天注册'), findsOneWidget);
          expect(requests, contains('GET /api/admin/stats'));
          expect(tester.takeException(), isNull);
          await _capture(tester, 'admin-overview-${width.toInt()}-$textScale');
        },
      );
    }
  }
}

Future<void> _pumpAdminDashboard(
  WidgetTester tester,
  ApiClient client, {
  required double width,
  required double textScale,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 820));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  if (Platform.environment['DUOYI_CAPTURE_WIDGET_POLISH_SCREENSHOT'] == '1') {
    await tester.runAsync(loadWidgetPolishScreenshotFonts);
  }

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: _DashboardFakeAuthProvider(
        state: const AuthState(
          userId: 'admin',
          username: 'admin',
          token: 'admin-token',
          isAdmin: true,
        ),
        client: client,
      ),
      child: MaterialApp(
        theme: widgetPolishScreenshotTheme(),
        builder: (context, child) =>
            RepaintBoundary(key: _captureKey, child: child!),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: const AdminScreen(initialTabIndex: 0),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpWeeklyCard(
  WidgetTester tester,
  HabitProvider provider, {
  double width = 390,
  double textScale = 1,
  NavigatorObserver? observer,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 820));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  if (Platform.environment['DUOYI_CAPTURE_WIDGET_POLISH_SCREENSHOT'] == '1') {
    await tester.runAsync(loadWidgetPolishScreenshotFonts);
  }

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<HabitProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: widgetPolishScreenshotTheme(),
        builder: (context, child) =>
            RepaintBoundary(key: _captureKey, child: child!),
        navigatorObservers: observer == null ? [] : [observer],
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(width: width, child: const HabitWeeklyCard()),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _dayCell(DateTime date) =>
    find.byKey(ValueKey('habit_weekly_overview_day_${date.weekday - 1}'));

Future<void> _capture(WidgetTester tester, String name) async {
  if (Platform.environment['DUOYI_CAPTURE_WIDGET_POLISH_SCREENSHOT'] != '1') {
    return;
  }
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('evidence/screenshots/widget-polish-20261006/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

class _RecordingNavigatorObserver extends NavigatorObserver {
  final removedRoutes = <Route<dynamic>>[];

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    removedRoutes.add(route);
  }
}

class _DashboardFakeAuthProvider extends AuthProvider {
  final AuthState _fakeState;
  final ApiClient _fakeClient;

  _DashboardFakeAuthProvider({
    required AuthState state,
    required ApiClient client,
  }) : _fakeState = state,
       _fakeClient = client;

  @override
  AuthState get state => _fakeState;

  @override
  ApiClient get client => _fakeClient;
}
