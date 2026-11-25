import 'dart:io';

import 'package:duoyi/core/calendar_date_navigation.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
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
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Widget _calendarApp(DateTime initialDate) {
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
      ChangeNotifierProvider<CalendarProvider>(
        create: (_) => CalendarProvider(),
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
    child: MaterialApp(home: CalendarScreen(initialDate: initialDate)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocale originalLocale;

  setUp(() {
    originalLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    I18n.setLocale(originalLocale);
  });

  testWidgets(
    'UTC next-month navigation keeps November 30 as December 30',
    (tester) async {
      expect(Platform.environment['TZ'], 'UTC');

      final initialDate = DateTime(2011, 11, 30);
      expect(initialDate.day, 30);
      expect(
        CalendarDateNavigation.tryShiftMonths(initialDate, 1),
        DateTime(2011, 12, 30),
      );

      await tester.pumpWidget(_calendarApp(initialDate));
      await tester.pumpAndSettle();

      expect(
        find.text(I18nDateFormat.yearMonth(DateTime(2011, 11))),
        findsOneWidget,
      );
      _expectSelectedDay(tester, initialDate);

      final nextMonthButton = _nextMonthButton();
      expect(tester.widget<IconButton>(nextMonthButton).onPressed, isNotNull);
      await tester.tap(nextMonthButton);
      await tester.pumpAndSettle();

      final selectedDate = DateTime(2011, 12, 30);
      expect(
        find.text(I18nDateFormat.yearMonth(DateTime(2011, 12))),
        findsOneWidget,
      );
      _expectSelectedDay(tester, selectedDate);
      expect(tester.takeException(), isNull);
    },
    skip: _skipUnlessZone(zone: 'UTC', requireVariable: 'DUOYI_REQUIRE_UTC'),
  );

  testWidgets(
    'Apia next-month navigation stays disabled when November 30 has no December counterpart',
    (tester) async {
      expect(Platform.environment['TZ'], 'Pacific/Apia');

      final initialDate = DateTime(2011, 11, 30);
      expect(initialDate.day, 30);
      expect(CalendarDateNavigation.tryShiftMonths(initialDate, 1), isNull);

      await tester.pumpWidget(_calendarApp(initialDate));
      await tester.pumpAndSettle();

      expect(
        find.text(I18nDateFormat.yearMonth(DateTime(2011, 11))),
        findsOneWidget,
      );
      _expectSelectedDay(tester, initialDate);

      final nextMonthButton = _nextMonthButton();
      expect(tester.widget<IconButton>(nextMonthButton).onPressed, isNull);
      await tester.tap(nextMonthButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        find.text(I18nDateFormat.yearMonth(DateTime(2011, 11))),
        findsOneWidget,
      );
      expect(
        find.text(I18nDateFormat.date(DateTime(2011, 12, 31))),
        findsNothing,
      );
      _expectSelectedDay(tester, initialDate);
      expect(tester.takeException(), isNull);
    },
    skip: _skipUnlessZone(
      zone: 'Pacific/Apia',
      requireVariable: 'DUOYI_REQUIRE_APIA',
    ),
  );
}

Finder _nextMonthButton() => find
    .descendant(
      of: find.byKey(const ValueKey('calendar_navigation_header_bar')),
      matching: find.byType(IconButton),
    )
    .last;

void _expectSelectedDay(WidgetTester tester, DateTime date) {
  final dateLabel = I18nDateFormat.date(date);
  final selected = tester
      .widgetList<Semantics>(find.byType(Semantics))
      .where(
        (semantics) =>
            semantics.properties.selected == true &&
            (semantics.properties.label?.startsWith('$dateLabel，') ?? false),
      )
      .toList();
  expect(selected, hasLength(1));
}

bool _skipUnlessZone({required String zone, required String requireVariable}) {
  if (Platform.environment['TZ'] == zone ||
      Platform.environment[requireVariable] == '1') {
    return false;
  }
  return true;
}
