import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/lunar_calendar.dart';
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
import 'package:duoyi/widgets/app_date_picker.dart';
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

Widget _datePickerHost({
  required DateTime initialDate,
  required ValueChanged<Future<AppDatePickerResult?>> onOpened,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            key: const ValueKey('open_date_picker'),
            onPressed: () => onOpened(
              AppDatePicker.show(
                context,
                initialDate: initialDate,
                firstDate: firstDate,
                lastDate: lastDate,
              ),
            ),
            child: const Text('Open date picker'),
          ),
        ),
      ),
    ),
  );
}

class _OpenedDatePicker {
  const _OpenedDatePicker(this.result);

  final Future<AppDatePickerResult?> result;
}

Future<_OpenedDatePicker> _openDatePicker(
  WidgetTester tester, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  Future<AppDatePickerResult?>? result;
  await tester.pumpWidget(
    _datePickerHost(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      onOpened: (opened) => result = opened,
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open_date_picker')));
  await tester.pumpAndSettle();
  return _OpenedDatePicker(result!);
}

DateTime get _wideFirstDate => DateTime(1, 1, 1);
DateTime get _wideLastDate => DateTime(9999, 12, 31);

String _lunarPreviewText(DateTime solarDate, LunarDate lunar) =>
    '${LunarCalendar.ganzhiOf(lunar.year)}年（${solarDate.year}）'
    '${LunarCalendar.monthName(lunar.month, isLeap: lunar.isLeapMonth)} '
    '${LunarCalendar.dayName(lunar.day)}';

Finder _calendarDateLabel(String text) => find.descendant(
  of: find.byKey(const ValueKey('calendar_navigation_date_button')),
  matching: find.text(text),
);

Future<void> _confirmPicker(WidgetTester tester) async {
  final confirm = find.text(I18n.tr('action.confirm'));
  await tester.ensureVisible(confirm);
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}

Future<void> _tapLunarModeIfAvailable(WidgetTester tester) async {
  final lunarSegment = find.descendant(
    of: find.byType(SegmentedButton<AppDatePickerMode>),
    matching: find.text(I18n.tr('calendar.lunar')),
  );
  if (lunarSegment.evaluate().isEmpty) return;
  await tester.ensureVisible(lunarSegment);
  await tester.tap(lunarSegment);
  await tester.pumpAndSettle();
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

  testWidgets('Calendar picker preserves Solar date at year 0001 start', (
    tester,
  ) async {
    final initialDate = DateTime(1, 1, 1);
    await tester.pumpWidget(_calendarApp(initialDate));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('calendar_navigation_date_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text(I18nDateFormat.date(initialDate)), findsOneWidget);

    await _confirmPicker(tester);
    final dayTab = find.widgetWithText(Tab, I18n.tr('calendar.day'));
    await tester.ensureVisible(dayTab);
    await tester.tap(dayTab);
    await tester.pumpAndSettle();

    expect(
      _calendarDateLabel(I18nDateFormat.date(initialDate)),
      findsOneWidget,
    );
  });

  testWidgets('Calendar picker preserves Solar date at year 9999 end', (
    tester,
  ) async {
    final initialDate = DateTime(9999, 12, 31);
    await tester.pumpWidget(_calendarApp(initialDate));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('calendar_navigation_date_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text(I18nDateFormat.date(initialDate)), findsOneWidget);

    await _confirmPicker(tester);
    final dayTab = find.widgetWithText(Tab, I18n.tr('calendar.day'));
    await tester.ensureVisible(dayTab);
    await tester.tap(dayTab);
    await tester.pumpAndSettle();

    expect(
      _calendarDateLabel(I18nDateFormat.date(initialDate)),
      findsOneWidget,
    );
  });

  testWidgets('wide Solar picker keeps draft, month, and mode across locales', (
    tester,
  ) async {
    final initialDate = DateTime(2026, 5, 17);
    final selectedDate = DateTime(2026, 5, 19);
    final picker = await _openDatePicker(
      tester,
      initialDate: initialDate,
      firstDate: _wideFirstDate,
      lastDate: _wideLastDate,
    );

    final selectedCell = find.byKey(const ValueKey('solar-day-2026-05-19'));
    await tester.ensureVisible(selectedCell);
    await tester.tap(selectedCell);
    await tester.pumpAndSettle();
    expect(find.text(I18nDateFormat.date(selectedDate)), findsOneWidget);

    for (final locale in [AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(locale);
      await tester.pumpAndSettle();
      expect(find.text(I18nDateFormat.date(selectedDate)), findsOneWidget);
      expect(
        find.text(I18nDateFormat.yearMonth(DateTime(2026, 5))),
        findsOneWidget,
      );
      final modeButton = tester.widget<SegmentedButton<AppDatePickerMode>>(
        find.byType(SegmentedButton<AppDatePickerMode>),
      );
      expect(modeButton.selected, {AppDatePickerMode.solar});
    }

    await _confirmPicker(tester);
    final result = await picker.result;
    expect(result, isNotNull);
    expect(result!.date, selectedDate);
    expect(result.mode, AppDatePickerMode.solar);
  });

  testWidgets('1900 Solar date stays distinct from lunar year 1900 wheel', (
    tester,
  ) async {
    final solarDate = DateTime(1900, 1, 1);
    final lunar = LunarCalendar.tryFromSolar(solarDate);
    expect(lunar, isNotNull);
    expect(lunar!.year, 1899);

    final picker = await _openDatePicker(
      tester,
      initialDate: solarDate,
      firstDate: _wideFirstDate,
      lastDate: _wideLastDate,
    );
    expect(find.text(_lunarPreviewText(solarDate, lunar)), findsOneWidget);

    await _tapLunarModeIfAvailable(tester);
    expect(find.text(I18nDateFormat.date(solarDate)), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsNothing);

    await _confirmPicker(tester);
    final result = await picker.result;
    expect(result, isNotNull);
    expect(result!.date, solarDate);
  });

  testWidgets('2100 policy hides lunar metadata and retains Solar draft', (
    tester,
  ) async {
    final solarDate = DateTime(2100, 1, 1);
    expect(LunarCalendar.isWithinDocumentedSolarRange(solarDate), isFalse);
    final converted = LunarCalendar.tryFromSolar(solarDate);
    final forbiddenMetadata = <String>{
      _lunarPreviewText(solarDate, LunarCalendar.fromSolar(solarDate)),
      if (converted != null) _lunarPreviewText(solarDate, converted),
    };
    final publicResultMetadata = AppDatePickerResult(
      date: solarDate,
      mode: AppDatePickerMode.solar,
    ).lunarText;
    expect(forbiddenMetadata.contains(publicResultMetadata), isFalse);

    final picker = await _openDatePicker(
      tester,
      initialDate: solarDate,
      firstDate: _wideFirstDate,
      lastDate: _wideLastDate,
    );
    expect(find.text(I18nDateFormat.date(solarDate)), findsOneWidget);
    for (final metadata in forbiddenMetadata) {
      expect(find.text(metadata), findsNothing);
    }

    await _tapLunarModeIfAvailable(tester);
    if (find.byType(ListWheelScrollView).evaluate().isNotEmpty) {
      expect(converted, isNotNull);
      final alternateDay = _alternateLunarDayIn2100(converted!);
      expect(alternateDay, isNotNull);
      final wheels = tester
          .widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
          .toList();
      final dayController =
          wheels[2].controller! as FixedExtentScrollController;
      dayController.jumpToItem(alternateDay! - 1);
      await tester.pumpAndSettle();
    }

    expect(find.text(I18nDateFormat.date(solarDate)), findsOneWidget);
    for (final metadata in forbiddenMetadata) {
      expect(find.text(metadata), findsNothing);
    }

    await _confirmPicker(tester);
    final result = await picker.result;
    expect(result, isNotNull);
    expect(result!.date, solarDate);
  });
}

int? _alternateLunarDayIn2100(LunarDate lunar) {
  final dayCount = LunarCalendar.daysInMonth(
    lunar.year,
    lunar.month,
    isLeap: lunar.isLeapMonth,
  );
  for (var day = 1; day <= dayCount; day++) {
    if (day == lunar.day) continue;
    final solar = LunarCalendar.toSolar(
      lunar.year,
      lunar.month,
      day,
      isLeap: lunar.isLeapMonth,
    );
    if (solar.year == 2100) return day;
  }
  return null;
}
