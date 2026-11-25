import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/calendar_event_sheet_ui_copy.dart';
import 'package:duoyi/core/calendar_aggregator.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/today_ui_copy.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_schedule_detail_route.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/widget_launch_access.dart';
import 'package:duoyi/services/widget_navigation_request.dart';
import 'package:duoyi/services/widget_schedule_projection.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/calendar_event_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

const _id = '  record /?#&=% 测试  ';
final _day = DateTime(2023, 3, 22, 9, 15);
const _layouts = [
  (name: 'narrow', size: Size(320, 844), scale: 1.6),
  (name: 'landscape', size: Size(568, 320), scale: 2.0),
];

class _Sessions extends PomodoroProvider {
  int generation = 0;
  List<PomodoroSession> items = [
    PomodoroSession(
      id: _id,
      startTime: _day,
      endTime: _day.add(const Duration(minutes: 25)),
      durationSeconds: 1500,
      type: PomodoroType.focus,
      taskName: 'Published focus',
      tag: 'User tag',
    ),
  ];
  @override
  List<PomodoroSession> get sessions => items;
  @override
  int get storageGeneration => generation;

  @override
  void resetLocalState() {
    generation++;
    items = [];
    notifyListeners();
  }

  void clearRecords() {
    items = [];
    notifyListeners();
  }
}

class _Fixture {
  final CalendarProvider originalCalendar = CalendarProvider();
  late CalendarProvider calendar = originalCalendar;
  final _Sessions originalSessions = _Sessions();
  late _Sessions sessions = originalSessions;
  final ThemeProvider theme = ThemeProvider();
  final FocusRoomProvider rooms = FocusRoomProvider();
  final boundary = GlobalKey();
  final String host;
  bool blocked = false;
  int acknowledgements = 0;
  int requeues = 0;
  late WidgetLaunchAccess access;

  _Fixture(this.host);
  Uri get uri {
    final event = host == 'event'
        ? calendar.localEvents.single
        : CalendarAggregator.buildEvents(
            todos: const [],
            habits: const [],
            pomodoroSessions: sessions.sessions,
            colorScheme: theme.brand.theme.colorScheme,
          ).single;
    return Uri.parse(homeWidgetScheduleEventDeepLink(event));
  }

  Future<void> initialize(String brand) async {
    SharedPreferences.setMockInitialValues({'active_brand': brand});
    await theme.loadFromStorage();
    await calendar.loadFromStorage();
    await calendar.addLocalEvent(
      CalendarEvent(
        id: _id,
        title: 'Published local event',
        date: _day,
        type: CalendarEventType.event,
        color: Colors.blue,
        sourceId: 'different-source-alias',
        note: 'User note',
      ),
    );
  }

  Widget app({double scale = 1.6}) => MultiProvider(
    providers: [
      ChangeNotifierProvider<CalendarProvider>.value(value: calendar),
      ChangeNotifierProvider<PomodoroProvider>.value(value: sessions),
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ChangeNotifierProvider<FocusRoomProvider>.value(value: rooms),
    ],
    child: MaterialApp(
      theme: theme.brand.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: boundary, child: child!),
      ),
      home: BrandRouteSurface(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                key: const ValueKey('open-object'),
                onPressed: () {
                  final published = uri;
                  access = WidgetLaunchAccess(
                    uri: published,
                    request: WidgetNavigationRequests(
                      accountGeneration: () =>
                          AccountLocalDataCleaner.accountDataGeneration,
                    ).capture(),
                    isBlocked: () => blocked,
                    requeue: (_, _) => requeues++,
                    acknowledge: (_) async {
                      acknowledgements++;
                    },
                  );
                  access.afterFrame(() {
                    unawaited(
                      access.run(
                        () => openWidgetScheduleDetail(
                          context,
                          published,
                          access,
                        ),
                      ),
                    );
                  });
                  access.finishDispatch();
                },
                child: const Text('Open object'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, {double scale = 1.6}) async {
    await tester.pumpWidget(app(scale: scale));
    await tester.tap(find.byKey(const ValueKey('open-object')));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('DUOYI_SCHEDULE_SCREENSHOTS')) return;
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rendered = await render.toImage(pixelRatio: 1);
      try {
        final bytes = (await rendered.toByteData(
          format: ui.ImageByteFormat.png,
        ))!;
        final file = File(
          'evidence/screenshots/widget-schedule-object-routes-20261020/$name.png',
        );
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      } finally {
        rendered.dispose();
      }
    });
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    originalCalendar.dispose();
    if (!identical(calendar, originalCalendar)) calendar.dispose();
    originalSessions.dispose();
    if (!identical(sessions, originalSessions)) sessions.dispose();
    theme.dispose();
    rooms.dispose();
    I18n.setLocale(AppLocale.zh);
  }
}

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final host in ['event', 'pomodoro']) {
        for (final layout in _layouts) {
          final name = '$brand-${locale.name}-$host-${layout.name}';
          testWidgets(
            'opens exact schedule object and retains editor draft $name',
            (tester) async {
              final fixture = _Fixture(host);
              tester.view.physicalSize = layout.size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              await tester.runAsync(loadWeeklyReviewScreenshotFonts);
              I18n.setLocale(locale);
              await fixture.initialize(brand);
              try {
                await fixture.open(tester, scale: layout.scale);
                final sheet = tester.widget<CalendarEventSheet>(
                  find.byType(CalendarEventSheet),
                );
                expect(
                  host == 'event' ? sheet.event.id : sheet.event.sourceId,
                  _id,
                );
                expect(sheet.event.date, _day);
                expect(fixture.acknowledgements, 0);
                await fixture.capture(tester, '$name-detail');
                final retained = tester.element(
                  find.byType(CalendarEventSheet),
                );
                I18n.setLocale(
                  locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
                );
                await tester.pumpAndSettle();
                expect(
                  identical(
                    tester.element(find.byType(CalendarEventSheet)),
                    retained,
                  ),
                  isTrue,
                );
                final edit = find.text(CalendarEventSheetUiCopy.actionEdit);
                await tester.ensureVisible(edit);
                await tester.tap(edit);
                await tester.pumpAndSettle();
                final field = find.byType(TextField).first;
                await tester.enterText(field, 'Retained user draft');
                final controller = tester.widget<TextField>(field).controller!;
                I18n.setLocale(locale);
                await tester.pumpAndSettle();
                expect(
                  tester.widget<TextField>(field).controller,
                  same(controller),
                );
                expect(controller.text, 'Retained user draft');
                await fixture.capture(tester, '$name-editor');
                Navigator.of(tester.element(field)).pop();
                await tester.pumpAndSettle();
                expect(
                  fixture.calendar.localEvents.single.title,
                  'Published local event',
                );
                expect(
                  fixture.sessions.sessions.single.taskName,
                  'Published focus',
                );
                expect(fixture.acknowledgements, 1);
                expect(fixture.requeues, 0);
                expect(tester.takeException(), isNull);
              } finally {
                await fixture.dispose(tester);
              }
            },
          );
        }
      }
    }
  }

  for (final host in ['event', 'pomodoro']) {
    for (final change in ['delete', 'account', 'replace-provider', 'reset']) {
      testWidgets(
        '$host open detail rejects $change without selecting another object',
        (tester) async {
          final fixture = _Fixture(host);
          await fixture.initialize('defaultBrand');
          try {
            await fixture.open(tester);
            expect(find.byType(CalendarEventSheet), findsOneWidget);
            if (change == 'delete') {
              if (host == 'event') {
                await fixture.calendar.deleteLocalEvent(_id);
              } else {
                fixture.sessions.clearRecords();
              }
            } else if (change == 'account') {
              AccountLocalDataCleaner.invalidateInFlightAccountWrites();
            } else if (change == 'replace-provider') {
              if (host == 'event') {
                fixture.calendar = CalendarProvider();
                await fixture.calendar.loadFromStorage();
                await tester.pumpWidget(fixture.app());
              } else {
                fixture.sessions = _Sessions();
                await tester.pumpWidget(fixture.app());
              }
            } else {
              if (host == 'event') {
                fixture.calendar.resetLocalState();
              } else {
                fixture.sessions.resetLocalState();
              }
            }
            await tester.pumpAndSettle();
            expect(find.byType(CalendarEventSheet), findsNothing);
            expect(
              find.text(
                change == 'delete' || (change == 'reset' && host == 'event')
                    ? TodayUiCopy.detailMissing('events')
                    : TodayUiCopy.detailSourceChanged,
              ),
              findsOneWidget,
            );
            expect(
              find.text(CalendarEventSheetUiCopy.actionEdit),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await fixture.dispose(tester);
          }
        },
      );
    }
    testWidgets('$host blocked receipt requeues without presenting a detail', (
      tester,
    ) async {
      final fixture = _Fixture(host);
      await fixture.initialize('defaultBrand');
      fixture.blocked = true;
      try {
        await fixture.open(tester);
        expect(find.byType(CalendarEventSheet), findsNothing);
        expect(fixture.requeues, 1);
        expect(fixture.acknowledgements, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
    testWidgets(
      '$host lock after presentation retains one detail without requeue',
      (tester) async {
        final fixture = _Fixture(host);
        await fixture.initialize('defaultBrand');
        try {
          await fixture.open(tester);
          final retained = tester.element(find.byType(CalendarEventSheet));
          fixture.blocked = true;
          expect(fixture.access.canProceed, isFalse);
          expect(fixture.requeues, 0);
          fixture.blocked = false;
          await tester.pumpAndSettle();
          expect(
            tester.element(find.byType(CalendarEventSheet)),
            same(retained),
          );
          Navigator.of(tester.element(find.byType(CalendarEventSheet))).pop();
          await tester.pumpAndSettle();
          expect(fixture.acknowledgements, 1);
          expect(fixture.requeues, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
    );
  }
}
