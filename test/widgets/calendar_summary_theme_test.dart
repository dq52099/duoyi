import 'dart:convert';

import 'package:duoyi/core/calendar_agenda_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/course_schedule.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/calendar_day_agenda.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

const _birthdayTitle =
    'Family celebration with friends at the riverside garden';
const _normalTitle = '家人团聚与共同学习的纪念日';
const _courseTitle =
    'Collaborative research and writing at the community library';
const _shortCourseTitle = '中文阅读与写作';
const _dataKeys = [
  'duoyi_anniversaries_v2',
  'duoyi_courses',
  'duoyi_course_settings',
];

class _Scenario {
  _Scenario(
    this.theme,
    this.anniversaries,
    this.courses,
    this.boundary,
    this.agendaKey,
  );
  final ThemeProvider theme;
  final AnniversaryProvider anniversaries;
  final CourseProvider courses;
  final GlobalKey boundary;
  final GlobalKey agendaKey;
}

Future<_Scenario> _mount(
  WidgetTester tester, {
  required String brand,
  required AppLocale locale,
  required DateTime day,
  required Size size,
  required double scale,
  int? originYear,
}) async {
  final anniversaries = [
    Anniversary(
      id: 'birthday',
      title: _birthdayTitle,
      originDate: DateTime(originYear ?? day.year - 4, day.month, day.day),
      type: AnniversaryType.birthday,
      colorValue: 0xFF2196F3,
    ),
    Anniversary(
      id: 'single',
      title: _normalTitle,
      originDate: day,
      colorValue: 0xFFFFA726,
    ),
  ];
  final courses = [
    CourseItem(
      id: 'full',
      name: _courseTitle,
      teacher: 'Dr. Morgan Reed',
      location: 'North library reading room',
      weekday: day.weekday,
      startSection: 11,
      sectionCount: 2,
      weeks: [1],
      colorValue: 0xFFFFCA28,
    ),
    CourseItem(
      id: 'short',
      name: _shortCourseTitle,
      weekday: day.weekday,
      startSection: 3,
      sectionCount: 1,
      weeks: [1],
      colorValue: 0xFF7E57C2,
    ),
  ];
  SharedPreferences.setMockInitialValues({
    'active_brand': brand,
    'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    'duoyi_anniversaries_v2': anniversaries
        .map((a) => jsonEncode(a.toJson()))
        .toList(),
    'duoyi_courses': courses.map((c) => jsonEncode(c.toJson())).toList(),
    'duoyi_course_settings': jsonEncode(
      ScheduleSettings(
        termStart: day.subtract(Duration(days: day.weekday - 1)),
      ).toJson(),
    ),
  });
  I18n.setLocale(locale);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late ThemeProvider theme;
  late AnniversaryProvider anniversaryProvider;
  late CourseProvider courseProvider;
  late AuthProvider auth;
  await tester.runAsync(() async {
    theme = ThemeProvider();
    anniversaryProvider = AnniversaryProvider();
    courseProvider = CourseProvider();
    auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((_) async => fail('No fixture HTTP')),
      ),
    );
    await theme.loadFromStorage();
    await anniversaryProvider.loadFromStorage();
    await courseProvider.loadFromStorage();
    await loadWeeklyReviewScreenshotFonts();
  });
  final boundary = GlobalKey();
  final agendaKey = GlobalKey();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    theme.dispose();
    anniversaryProvider.dispose();
    courseProvider.dispose();
    auth.dispose();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AnniversaryProvider>.value(
          value: anniversaryProvider,
        ),
        ChangeNotifierProvider<CourseProvider>.value(value: courseProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => DiaryProvider()),
        ChangeNotifierProvider(create: (_) => TodoProvider()),
        ChangeNotifierProvider(create: (_) => CalendarProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, selectedTheme, _) =>
            ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (context, selectedLocale, _) => MaterialApp(
                theme: selectedTheme.brand.theme,
                locale: Locale(selectedLocale.storageValue),
                supportedLocales: const [Locale('zh'), Locale('en')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
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
                              date: day,
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
  expect(courseProvider.coursesOfDate(day), hasLength(2));
  return _Scenario(
    theme,
    anniversaryProvider,
    courseProvider,
    boundary,
    agendaKey,
  );
}

Finder _cardFor(WidgetTester tester, Finder text) {
  Element? result;
  tester.element(text).visitAncestorElements((e) {
    if (e.widget is CalendarDayAgenda) return false;
    if (e.widget is AppSurfaceCard ||
        (e.widget is Container && (e.widget as Container).decoration != null)) {
      result = e;
      return false;
    }
    return true;
  });
  expect(result, isNotNull);
  return find.byElementPredicate((e) => identical(e, result));
}

class _SummaryProbe extends RouteRenderProbe {
  _SummaryProbe(super.tester, super.boundary, super.name);
  @override
  Future<void> reveal(Finder finder) async {
    expect(finder, findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(_cardFor(tester, finder)),
      alignment: .5,
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in [
        (name: 'ordinary', size: const Size(390, 844), scale: 1.0),
        (name: 'large', size: const Size(320, 844), scale: 2.0),
        (name: 'landscape', size: const Size(568, 320), scale: 2.0),
      ]) {
        final name = 'calendar-summary-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final now = DateTime.now();
          final day = DateTime(now.year, now.month, now.day);
          final scenario = await _mount(
            tester,
            brand: brand,
            locale: locale,
            day: day,
            size: layout.size,
            scale: layout.scale,
          );
          final prefs = await SharedPreferences.getInstance();
          final stored = {for (final key in _dataKeys) key: prefs.get(key)};
          final beforeCourses = scenario.courses.courses
              .map((c) => c.toJson())
              .toList();
          final beforeAnniversaries = scenario.anniversaries.items
              .map((a) => a.toJson())
              .toList();
          final agenda = scenario.agendaKey.currentContext;
          final scroll = tester.state(
            find
                .descendant(
                  of: find.byType(CalendarDayAgenda),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          final probe = _SummaryProbe(tester, scenario.boundary, name);
          Future<void> inspect(String stage) async {
            // The retained lazy list may have evicted its first card while
            // inspecting the last one. Revisit the top before each full pass.
            tester
                .state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byType(CalendarDayAgenda),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                )
                .position
                .jumpTo(0);
            await tester.pumpAndSettle();
            final headers = RouteRenderProbe(tester, scenario.boundary, name);
            for (final heading in [
              CalendarAgendaUiCopy.anniversarySectionTitle,
              CalendarAgendaUiCopy.courseSectionTitle,
            ]) {
              await headers.text(
                find.text(heading),
                role: '$stage section heading',
                minimumGeometricScale: .999,
              );
            }
            probe.rows.addAll(headers.rows);
            probe.errors.addAll(headers.errors);
            tester
                .state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byType(CalendarDayAgenda),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                )
                .position
                .jumpTo(0);
            await tester.pumpAndSettle();
            final labels = [
              (_birthdayTitle, CalendarAgendaUiCopy.anniversaryCount(5)),
              (_normalTitle, null),
              (
                _courseTitle,
                '${CalendarAgendaUiCopy.coursePeriod(11, 12)} · North library reading room · Dr. Morgan Reed',
              ),
              (_shortCourseTitle, CalendarAgendaUiCopy.coursePeriod(3, 3)),
            ];
            for (var i = 0; i < labels.length; i++) {
              final (title, subtitle) = labels[i];
              final titleFinder = find.text(title);
              final card = _cardFor(tester, titleFinder);
              if (tester.widget(card) is! AppSurfaceCard) {
                probe.errors.add(
                  '$stage $title bypasses shared themed surface',
                );
              } else {
                final ink = tester.widget<Ink>(
                  find.descendant(of: card, matching: find.byType(Ink)),
                );
                final decoration = ink.decoration! as BoxDecoration;
                final style = appSurfaceStyleOf(tester.element(card))!;
                expect(decoration.color, style.cardFillColor);
                expect(decoration.border, style.cardBorder);
                expect(
                  decoration.borderRadius,
                  BorderRadius.circular(style.cardRadius),
                );
              }
              for (final (label, font) in [
                (title, 13.0),
                if (subtitle != null) (subtitle, 11.0),
              ]) {
                final finder = find.descendant(
                  of: card,
                  matching: find.text(label),
                );
                await probe.text(
                  finder,
                  role: '$stage card $i',
                  minimumGeometricScale: .999,
                );
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(of: finder, matching: find.byType(RichText)),
                );
                expect(paragraph.text.style!.fontSize, font);
                expect(paragraph.textScaler.scale(font), font * layout.scale);
              }
              probe.rows.add({
                'stage': stage,
                'title': title,
                'sharedSurface': tester.widget(card) is AppSurfaceCard,
                'brand': scenario.theme.brand.id,
                'locale': I18n.current.name,
                'selectedDate': day.toIso8601String(),
              });
              await probe.capture('$stage-$i');
            }
          }

          await inspect('initial');
          final otherBrand = brand == 'defaultBrand'
              ? 'liquidGlass'
              : 'defaultBrand';
          expect(
            await tester.runAsync(() => scenario.theme.setBrand(otherBrand)),
            isTrue,
          );
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          expect(scenario.agendaKey.currentContext, same(agenda));
          expect(
            tester.state(
              find
                  .descendant(
                    of: find.byType(CalendarDayAgenda),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            ),
            same(scroll),
          );
          expect(scenario.theme.brand.id, otherBrand);
          await inspect('switched');
          expect(
            scenario.courses.courses.map((c) => c.toJson()).toList(),
            beforeCourses,
          );
          expect(
            scenario.anniversaries.items.map((a) => a.toJson()).toList(),
            beforeAnniversaries,
          );
          expect({for (final key in _dataKeys) key: prefs.get(key)}, stored);
          await probe.finish();
        });
      }
    }
    final anchorYear = DateTime.now().year;
    for (final year in [anchorYear - 2, anchorYear + 4]) {
      for (final locale in AppLocale.values) {
        testWidgets(
          'calendar summary uses selected year $brand $year ${locale.name}',
          (tester) async {
            final day = DateTime(year, 6, 29);
            await _mount(
              tester,
              brand: brand,
              locale: locale,
              day: day,
              size: const Size(390, 844),
              scale: 1,
              originYear: anchorYear - 6,
            );
            expect(find.text(_birthdayTitle), findsOneWidget);
            expect(
              find.text(
                CalendarAgendaUiCopy.anniversaryCount(year - anchorYear + 7),
              ),
              findsOneWidget,
            );
            expect(find.text(_normalTitle), findsOneWidget);
            expect(
              find.text(
                locale == AppLocale.en
                    ? '🎉 Anniversaries on this day'
                    : '🎉 当日纪念',
              ),
              findsOneWidget,
            );
            expect(
              find.text(
                locale == AppLocale.en ? '📚 Courses on this day' : '📚 当日课程',
              ),
              findsOneWidget,
            );
            expect(
              find.text(CalendarAgendaUiCopy.anniversarySectionTitle),
              findsNothing,
            );
            expect(
              find.text(CalendarAgendaUiCopy.courseSectionTitle),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
