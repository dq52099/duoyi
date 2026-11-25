import 'package:duoyi/core/almanac_locale_format.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/calendar_day_agenda.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

final _days = [
  (
    name: 'ordinary',
    date: DateTime(2026, 10, 24),
    term: null,
    solar: null,
    lunar: null,
  ),
  (
    name: 'solar',
    date: DateTime(2026, 1, 1),
    term: null,
    solar: '元旦',
    lunar: null,
  ),
  (
    name: 'lunar',
    date: DateTime(2026, 2, 17),
    term: null,
    solar: null,
    lunar: '春节',
  ),
  (
    name: 'term',
    date: DateTime(2026, 3, 20),
    term: '春分',
    solar: null,
    lunar: '龙抬头',
  ),
  (
    name: 'combined',
    date: DateTime(2020, 10, 1),
    term: null,
    solar: '国庆节',
    lunar: '中秋',
  ),
];
const _layouts = [
  (name: 'ordinary', size: Size(390, 844), scaler: TextScaler.linear(1)),
  (name: 'large', size: Size(320, 844), scaler: TextScaler.linear(2)),
  (name: 'landscape', size: Size(568, 320), scaler: TextScaler.linear(2)),
  (
    name: 'nonlinear',
    size: Size(332, 844),
    scaler: RouteProbeNonlinearScaler(),
  ),
];

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final day in _days) {
      for (final layout in _layouts) {
        final name = 'calendar-lunar-$brand-${day.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final lunar = LunarCalendar.fromSolar(day.date);
          expect(LunarCalendar.solarTerm(day.date), day.term);
          expect(LunarCalendar.solarFestival(day.date), day.solar);
          expect(LunarCalendar.lunarFestival(lunar), day.lunar);
          SharedPreferences.setMockInitialValues({
            'active_brand': brand,
            'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
            'duoyi_anniversaries_v2': <String>[],
            'duoyi_courses': <String>[],
          });
          I18n.setLocale(AppLocale.zh);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          late ThemeProvider theme;
          late AnniversaryProvider anniversaries;
          late CourseProvider courses;
          await tester.runAsync(() async {
            theme = ThemeProvider();
            anniversaries = AnniversaryProvider();
            courses = CourseProvider();
            await theme.loadFromStorage();
            await anniversaries.loadFromStorage();
            await courses.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });
          final boundary = GlobalKey();
          final agendaKey = GlobalKey();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            theme.dispose();
            anniversaries.dispose();
            courses.dispose();
          });
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AnniversaryProvider>.value(
                  value: anniversaries,
                ),
                ChangeNotifierProvider<CourseProvider>.value(value: courses),
                ChangeNotifierProvider(create: (_) => DiaryProvider()),
                ChangeNotifierProvider(create: (_) => TodoProvider()),
                ChangeNotifierProvider(create: (_) => CalendarProvider()),
              ],
              child: Consumer<ThemeProvider>(
                builder: (context, selected, _) =>
                    ValueListenableBuilder<AppLocale>(
                      valueListenable: I18n.localeListenable,
                      builder: (context, locale, _) => MaterialApp(
                        theme: selected.brand.theme,
                        locale: Locale(locale.storageValue),
                        supportedLocales: const [Locale('zh'), Locale('en')],
                        localizationsDelegates:
                            GlobalMaterialLocalizations.delegates,
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(
                            context,
                          ).copyWith(textScaler: layout.scaler),
                          child: RepaintBoundary(key: boundary, child: child!),
                        ),
                        home: BrandRouteSurface(
                          remountOnLocaleChange: false,
                          child: Scaffold(
                            backgroundColor: Colors.transparent,
                            body: SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: AppSurfaceCard(
                                  padding: EdgeInsets.zero,
                                  child: Builder(
                                    builder: (context) => CalendarDayAgenda(
                                      key: agendaKey,
                                      date: day.date,
                                      calendarProvider: context
                                          .read<CalendarProvider>(),
                                      horizontalPadding: 8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final agenda = agendaKey.currentContext;
          final scroll = tester.state(
            find.descendant(
              of: find.byType(CalendarDayAgenda),
              matching: find.byType(Scrollable),
            ),
          );
          final probe = RouteRenderProbe(tester, boundary, name);
          Future<void> inspect(String stage) async {
            final labels = [
              (
                '${I18n.tr('calendar.chinese_lunar_calendar')} ${AlmanacLocaleFormat.formatLunarDate(lunar)}',
                13.0,
              ),
              if (day.term != null)
                (AlmanacLocaleFormat.formatSolarTerm(day.term)!, 11.0),
              if (day.solar != null)
                (AlmanacLocaleFormat.formatFestival(day.solar)!, 11.0),
              if (day.lunar != null)
                (AlmanacLocaleFormat.formatFestival(day.lunar)!, 11.0),
            ];
            for (final (label, fontSize) in labels) {
              final finder = find.text(label);
              await probe.text(
                finder,
                role: stage,
                minimumGeometricScale: .999,
              );
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: finder, matching: find.byType(RichText)),
              );
              expect(paragraph.text.style!.fontSize, fontSize);
              expect(
                paragraph.textScaler.scale(fontSize),
                layout.scaler.scale(fontSize),
              );
              expect(paragraph.text.style!.fontWeight, FontWeight.normal);
            }
            final position = tester
                .state<ScrollableState>(
                  find.descendant(
                    of: find.byType(CalendarDayAgenda),
                    matching: find.byType(Scrollable),
                  ),
                )
                .position;
            position.jumpTo(0);
            await tester.pumpAndSettle();
            await probe.capture(stage);
          }

          await inspect('initial');
          expect(
            await tester.runAsync(
              () => theme.setBrand(
                brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand',
              ),
            ),
            isTrue,
          );
          I18n.setLocale(AppLocale.en);
          await tester.pumpAndSettle();
          expect(agendaKey.currentContext, same(agenda));
          expect(
            tester.state(
              find.descendant(
                of: find.byType(CalendarDayAgenda),
                matching: find.byType(Scrollable),
              ),
            ),
            same(scroll),
          );
          await inspect('switched');
          expect(await tester.runAsync(() => theme.setBrand(brand)), isTrue);
          I18n.setLocale(AppLocale.zh);
          await tester.pumpAndSettle();
          expect(agendaKey.currentContext, same(agenda));
          await inspect('restored');
          final prefs = await tester.runAsync(SharedPreferences.getInstance);
          expect(prefs!.getStringList('duoyi_anniversaries_v2'), isEmpty);
          expect(prefs.getStringList('duoyi_courses'), isEmpty);
          expect(anniversaries.items, isEmpty);
          expect(courses.courses, isEmpty);
          await probe.finish();
        });
      }
    }
  }
}
