import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/widgets/calendar_day_agenda.dart';
import 'package:duoyi/widgets/calendar_week_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _date = DateTime(2026, 10, 11);

List<CalendarEvent> _events() => [
  CalendarEvent(
    id: 'regular-generated',
    title: '专注 25 分钟',
    date: _date,
    type: CalendarEventType.pomodoro,
    color: Colors.red,
    // No raw subtitle: the resolver must drive presence and row height too.
    displayMetadata: const PomodoroDisplayMetadata(minutes: 25),
  ),
  CalendarEvent(
    id: 'short-generated',
    title: '专注 15 分钟',
    subtitle: '15分钟',
    date: _date,
    endDate: DateTime(2026, 10, 11, 9, 15),
    time: const TimeOfDay(hour: 9, minute: 0),
    type: CalendarEventType.pomodoro,
    color: Colors.orange,
    displayMetadata: const PomodoroDisplayMetadata(minutes: 15),
  ),
  CalendarEvent(
    id: 'generated-diary',
    title: '10月11日的日记',
    subtitle: '开心',
    date: _date,
    type: CalendarEventType.diary,
    color: Colors.teal,
    displayMetadata: DiaryDisplayMetadata(
      fallbackTitleDate: _date,
      moodKey: 'diary.mood.good',
    ),
  ),
  CalendarEvent(
    id: 'authored',
    title: '专注 25 分钟',
    subtitle: '用户正文保持原样',
    date: _date,
    type: CalendarEventType.event,
    color: Colors.blue,
  ),
];

class _CachedCalendarProvider extends CalendarProvider {
  _CachedCalendarProvider(this.cached);
  final List<CalendarEvent> cached;

  @override
  List<CalendarEvent> getEventsForDate(
    DateTime date, {
    Set<CalendarEventType>? activeTypes,
    String? projectKey,
    String? workspaceId,
  }) =>
      date.year == _date.year &&
          date.month == _date.month &&
          date.day == _date.day
      ? List<CalendarEvent>.of(cached)
      : <CalendarEvent>[];
}

Widget _app(_CachedCalendarProvider provider, {required bool week}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
        ChangeNotifierProvider(create: (_) => CourseProvider()),
        ChangeNotifierProvider(create: (_) => DiaryProvider()),
        ChangeNotifierProvider(create: (_) => TodoProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (_, locale, _) => week
                ? CalendarWeekStrip(
                    selectedDay: _date,
                    dateEventTypes: const {},
                    calendarProvider: provider,
                    onDaySelected: (_) {},
                  )
                : SingleChildScrollView(
                    child: CalendarDayAgenda(
                      date: _date,
                      calendarProvider: provider,
                      scrollable: false,
                    ),
                  ),
          ),
        ),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final week in [false, true]) {
    testWidgets(
      'cached ${week ? 'week' : 'day'} rows repaint without replacing events',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final cached = _events();
        final snapshots = cached.map((e) => e.toJson()).toList();
        final provider = _CachedCalendarProvider(cached);
        addTearDown(provider.dispose);
        await tester.pumpWidget(_app(provider, week: week));
        await tester.pumpAndSettle();
        expect(find.text('专注 25 分钟'), findsNWidgets(2));
        expect(find.text('专注 15 分钟'), findsOneWidget);
        expect(find.text('10月11日的日记'), findsOneWidget);
        expect(find.text('用户正文保持原样'), findsOneWidget);
        if (!week) {
          expect(find.text('🕘 时间线'), findsOneWidget);
          expect(find.text('📝 全天/无时间'), findsOneWidget);
        }
        final tiles = find.byWidgetPredicate(
          (w) =>
              w.runtimeType.toString() ==
              (week ? '_WeekEventTile' : '_DraggableEventCard'),
        );
        List<String> ids() => tester.widgetList(tiles).map((w) {
          final dynamic tile = w;
          return (tile.event as CalendarEvent).id;
        }).toList();
        final oldOrder = ids();
        expect(oldOrder, hasLength(cached.length));

        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expect(find.text('Focus 25 min'), findsOneWidget);
        expect(find.text('Focus 15 min'), findsOneWidget);
        expect(find.text('Diary for 10/11'), findsOneWidget);
        expect(find.text('专注 25 分钟'), findsOneWidget); // authored
        expect(find.text('用户正文保持原样'), findsOneWidget);
        expect(find.text('25 min'), findsOneWidget); // raw subtitle was absent
        expect(find.text('Good'), findsOneWidget);
        if (!week) {
          expect(find.text('🕘 Timeline'), findsOneWidget);
          expect(find.text('📝 All-day / Untimed'), findsOneWidget);
          expect(find.text('🕘 时间线'), findsNothing);
          expect(find.text('📝 全天/无时间'), findsNothing);
        }
        if (week) {
          expect(find.text('9:00 AM · 15 min'), findsOneWidget);
        } else {
          expect(
            find.byKey(
              const ValueKey('calendar-compact-title-short-generated'),
            ),
            findsOneWidget,
          );
        }
        expect(ids(), oldOrder);
        expect(cached.map((e) => e.toJson()).toList(), snapshots);

        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
        expect(find.text('专注 25 分钟'), findsNWidgets(2));
        expect(find.text('专注 15 分钟'), findsOneWidget);
        expect(find.text('10月11日的日记'), findsOneWidget);
        expect(ids(), oldOrder);
        expect(cached.map((e) => e.toJson()).toList(), snapshots);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        I18n.setLocale(AppLocale.en);
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
