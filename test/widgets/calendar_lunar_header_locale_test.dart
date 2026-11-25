import 'package:duoyi/core/almanac_locale_format.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/widgets/calendar_day_agenda.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final date in [
    DateTime(2026, 1, 1),
    DateTime(2026, 2, 17),
    DateTime(2026, 3, 20),
  ]) {
    testWidgets('day lunar header follows mounted locale for $date', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      I18n.setLocale(AppLocale.zh);
      final calendar = CalendarProvider();
      addTearDown(calendar.dispose);
      addTearDown(() => I18n.setLocale(AppLocale.zh));
      final lunar = LunarCalendar.fromSolar(date);
      final term = LunarCalendar.solarTerm(date);
      final solarFestival = LunarCalendar.solarFestival(date);
      final lunarFestival = LunarCalendar.lunarFestival(lunar);
      await tester.pumpWidget(
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
              body: CalendarDayAgenda(date: date, calendarProvider: calendar),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(CalendarDayAgenda));
      for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(CalendarDayAgenda)), same(element));
        expect(
          find.text(
            '${I18n.tr('calendar.chinese_lunar_calendar')} ${AlmanacLocaleFormat.formatLunarDate(lunar)}',
          ),
          findsOneWidget,
        );
        if (term != null) {
          expect(
            find.text(AlmanacLocaleFormat.formatSolarTerm(term)!),
            findsOneWidget,
          );
        }
        if (solarFestival != null) {
          expect(
            find.text(AlmanacLocaleFormat.formatFestival(solarFestival)!),
            findsOneWidget,
          );
        }
        if (lunarFestival != null) {
          expect(
            find.text(AlmanacLocaleFormat.formatFestival(lunarFestival)!),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
