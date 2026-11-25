import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/widgets/calendar_month_grid.dart';
import 'package:duoyi/widgets/calendar_week_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

class _EmptyTodoProvider extends TodoProvider {
  @override
  List<TodoItem> get todos => const <TodoItem>[];
}

class _EmptyHabitProvider extends HabitProvider {
  @override
  List<Habit> get habits => const <Habit>[];
}

class _EmptyPomodoroProvider extends PomodoroProvider {
  @override
  List<PomodoroSession> get sessions => const <PomodoroSession>[];
}

Widget _calendarApp({
  required DateTime initialDate,
  required PreferencesProvider preferencesProvider,
  required CalendarProvider calendarProvider,
  required GlobalKey screenshotKey,
}) {
  final palette = ThemeProvider();
  final theme = palette.brand.theme;
  palette.dispose();
  final fonts = theme.textTheme.apply(
    fontFamily: 'DuoyiScreenshotLatin',
    fontFamilyFallback: const ['DuoyiScreenshot'],
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TodoProvider>(create: (_) => _EmptyTodoProvider()),
      ChangeNotifierProvider<HabitProvider>(
        create: (_) => _EmptyHabitProvider(),
      ),
      ChangeNotifierProvider<PomodoroProvider>(
        create: (_) => _EmptyPomodoroProvider(),
      ),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<CalendarProvider>.value(value: calendarProvider),
      ChangeNotifierProvider<PreferencesProvider>.value(
        value: preferencesProvider,
      ),
      ChangeNotifierProvider<AnniversaryProvider>(
        create: (_) => AnniversaryProvider(),
      ),
      ChangeNotifierProvider<CountdownProvider>(
        create: (_) => CountdownProvider(),
      ),
      ChangeNotifierProvider<CourseProvider>(create: (_) => CourseProvider()),
      ChangeNotifierProvider<DiaryProvider>(create: (_) => DiaryProvider()),
      ChangeNotifierProvider<GoalProvider>(create: (_) => GoalProvider()),
      ChangeNotifierProvider<ShareProvider>(create: (_) => ShareProvider()),
      ChangeNotifierProvider<TimeAuditProvider>(
        create: (_) => TimeAuditProvider(),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(textTheme: fonts, primaryTextTheme: fonts),
      home: RepaintBoundary(
        key: screenshotKey,
        child: CalendarScreen(initialDate: initialDate),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocale originalLocale;

  setUp(() {
    originalLocale = I18n.current;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    I18n.setLocale(originalLocale);
  });

  testWidgets(
    'Chinese calendar month and week views follow the Sunday week-start preference',
    (tester) => _expectSundayWeekStartBehavior(tester, AppLocale.zh),
    skip: _skipUnlessUtc(),
  );

  testWidgets(
    'English calendar month and week views follow the Sunday week-start preference',
    (tester) => _expectSundayWeekStartBehavior(tester, AppLocale.en),
    skip: _skipUnlessUtc(),
  );
}

Future<void> _expectSundayWeekStartBehavior(
  WidgetTester tester,
  AppLocale locale,
) async {
  expect(Platform.environment['TZ'], 'UTC');
  I18n.setLocale(locale);
  final screenshotKey = GlobalKey();
  final capture =
      Platform.environment['DUOYI_CAPTURE_WIDGET_LOCALE_SCREENSHOTS'] == '1';
  if (capture) {
    await tester.runAsync(loadWidgetPolishScreenshotFonts);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  final initialDate = DateTime(2024, 9, 4);
  final firstSunday = DateTime(2024, 9, 1);
  final sentinel = CalendarEvent(
    id: 'calendar-week-start-sentinel',
    title: 'Week start sentinel',
    date: DateTime(2024, 9, 4, 14),
    endDate: DateTime(2024, 9, 4, 15),
    time: const TimeOfDay(hour: 14, minute: 0),
    type: CalendarEventType.event,
    color: const Color(0xFF4169E1),
    sourceId: 'calendar-week-start-sentinel',
    note: 'Event data must remain unchanged while the preference changes.',
  );
  final calendarProvider = CalendarProvider()
    ..setExternalEvents(<CalendarEvent>[sentinel]);
  late PreferencesProvider preferencesProvider;
  await tester.runAsync(() async {
    preferencesProvider = PreferencesProvider();
    await preferencesProvider.loadFromStorage();
  });

  try {
    expect(preferencesProvider.firstDayOfWeek, 1);

    await tester.pumpWidget(
      _calendarApp(
        initialDate: initialDate,
        preferencesProvider: preferencesProvider,
        calendarProvider: calendarProvider,
        screenshotKey: screenshotKey,
      ),
    );
    await tester.pumpAndSettle();

    _expectMonthStartsOn(
      tester,
      firstDay: DateTime(2024, 9, 2),
      expectedWeekdayHeaders: locale == AppLocale.en
          ? const <String>['M', 'T', 'W', 'T', 'F', 'S', 'S']
          : const <String>['一', '二', '三', '四', '五', '六', '日'],
    );
    _expectSelectedMonthDay(tester, initialDate);
    if (capture) {
      await _capture(tester, screenshotKey, '${locale.name}-month-1');
    }

    final initialEvents = List<CalendarEvent>.of(calendarProvider.events);
    expect(initialEvents, hasLength(1));
    expect(identical(initialEvents.single, sentinel), isTrue);
    final initialEventData = initialEvents
        .map((event) => event.toJson())
        .toList(growable: false);

    await tester.runAsync(() => preferencesProvider.setFirstDayOfWeek(7));
    await tester.pumpAndSettle();
    expect(preferencesProvider.firstDayOfWeek, 7);
    _expectMonthStartsOn(
      tester,
      firstDay: firstSunday,
      expectedWeekdayHeaders: locale == AppLocale.en
          ? const <String>['S', 'M', 'T', 'W', 'T', 'F', 'S']
          : const <String>['日', '一', '二', '三', '四', '五', '六'],
    );
    _expectSelectedMonthDay(tester, initialDate);
    if (capture) {
      await _capture(tester, screenshotKey, '${locale.name}-month-7');
    }
    _expectCalendarEventsUnchanged(
      calendarProvider,
      initialEvents,
      initialEventData,
      sentinel,
    );

    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    _expectWeekStartsOn(tester, firstDay: firstSunday);
    _expectSelectedWeekDay(tester, initialDate);
    if (capture) await _capture(tester, screenshotKey, '${locale.name}-week-7');
    _expectCalendarEventsUnchanged(
      calendarProvider,
      initialEvents,
      initialEventData,
      sentinel,
    );

    for (final firstDayOfWeek in <int>[1, 7]) {
      await tester.runAsync(
        () => preferencesProvider.setFirstDayOfWeek(firstDayOfWeek),
      );
      await tester.pumpAndSettle();

      expect(preferencesProvider.firstDayOfWeek, firstDayOfWeek);
      _expectWeekStartsOn(
        tester,
        firstDay: firstDayOfWeek == 7 ? firstSunday : DateTime(2024, 9, 2),
      );
      _expectSelectedWeekDay(tester, initialDate);
      if (capture && firstDayOfWeek == 1) {
        await _capture(tester, screenshotKey, '${locale.name}-week-1');
      }
      _expectCalendarEventsUnchanged(
        calendarProvider,
        initialEvents,
        initialEventData,
        sentinel,
      );
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    preferencesProvider.dispose();
    calendarProvider.dispose();
  }
}

void _expectMonthStartsOn(
  WidgetTester tester, {
  required DateTime firstDay,
  required List<String> expectedWeekdayHeaders,
}) {
  final grid = find.byType(CalendarMonthGrid);
  final day = _monthDaySemantics(firstDay);
  expect(day, findsOneWidget);

  final gridRect = tester.getRect(
    find.byKey(const ValueKey('calendar_fixed_month_grid')),
  );
  expect(
    tester.getCenter(day).dx,
    lessThan(gridRect.left + gridRect.width / 7),
    reason: '${_fixtureDate(firstDay)} should occupy the first column.',
  );

  final headerLabels = tester
      .widgetList<Text>(find.descendant(of: grid, matching: find.byType(Text)))
      .take(7)
      .map((text) => text.data)
      .toList(growable: false);
  expect(headerLabels, expectedWeekdayHeaders);
}

void _expectSelectedMonthDay(WidgetTester tester, DateTime date) {
  final selectedDays = tester
      .widgetList<Semantics>(
        find.descendant(
          of: find.byType(CalendarMonthGrid),
          matching: find.byType(Semantics),
        ),
      )
      .where(
        (semantics) =>
            semantics.properties.selected == true &&
            (semantics.properties.label?.startsWith(_fixtureDate(date)) ??
                false),
      )
      .toList(growable: false);
  expect(selectedDays, hasLength(1));
}

void _expectWeekStartsOn(WidgetTester tester, {required DateTime firstDay}) {
  final lastDay = firstDay.add(const Duration(days: 6));
  final expectedRange =
      '${I18nDateFormat.monthDay(firstDay)} - ${I18nDateFormat.monthDay(lastDay)}';
  expect(find.text(expectedRange), findsOneWidget);

  final dayCenters = <double>[];
  for (var offset = 0; offset < 7; offset++) {
    final date = firstDay.add(Duration(days: offset));
    final day = _weekDaySemantics(date);
    expect(day, findsOneWidget);
    dayCenters.add(tester.getCenter(day).dx);
  }
  for (var index = 1; index < dayCenters.length; index++) {
    expect(dayCenters[index - 1], lessThan(dayCenters[index]));
  }
}

void _expectSelectedWeekDay(WidgetTester tester, DateTime date) {
  final selectedDays = tester
      .widgetList<Semantics>(
        find.descendant(
          of: find.byType(CalendarWeekStrip),
          matching: find.byType(Semantics),
        ),
      )
      .where((semantics) => semantics.properties.selected == true)
      .toList(growable: false);
  expect(selectedDays, hasLength(1));
  expect(
    selectedDays.single.properties.label?.startsWith(_fixtureDate(date)),
    isTrue,
  );
}

String _fixtureDate(DateTime date) =>
    I18nDateFormat.date(date, pattern: I18nDateFormat.defaultPattern);

Finder _monthDaySemantics(DateTime date) => find.descendant(
  of: find.byType(CalendarMonthGrid),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        (widget.properties.label?.startsWith(_fixtureDate(date)) ?? false),
  ),
);

Finder _weekDaySemantics(DateTime date) => find.descendant(
  of: find.byType(CalendarWeekStrip),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        (widget.properties.label?.startsWith(_fixtureDate(date)) ?? false),
  ),
);

void _expectCalendarEventsUnchanged(
  CalendarProvider calendarProvider,
  List<CalendarEvent> initialEvents,
  List<Map<String, dynamic>> initialEventData,
  CalendarEvent sentinel,
) {
  expect(calendarProvider.events, hasLength(initialEvents.length));
  expect(
    calendarProvider.events.map((event) => event.toJson()).toList(),
    initialEventData,
  );
  for (var index = 0; index < initialEvents.length; index++) {
    expect(
      identical(calendarProvider.events[index], initialEvents[index]),
      isTrue,
    );
  }
  expect(
    identical(
      calendarProvider.events.singleWhere((event) => event.id == sentinel.id),
      sentinel,
    ),
    isTrue,
  );
}

bool _skipUnlessUtc() =>
    Platform.environment['TZ'] == 'UTC' ||
        Platform.environment['DUOYI_REQUIRE_UTC'] == '1'
    ? false
    : true;

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final base = Platform.environment['DUOYI_WIDGET_SCREENSHOT_DIR']!;
      final file = File('$base/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
