import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/almanac_locale_format.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/calendar_day_agenda.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

final _diaryDate = DateTime(2023, 3, 22);
final _agendaDate = DateTime(2026, 2, 17);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final surface in _DisplaySurface.values) {
    for (final locale in AppLocale.values) {
      for (final layout in _layouts) {
        testWidgets(
          'lunar display ${surface.name} ${locale.name} ${layout.name}',
          (tester) async {
            SharedPreferences.setMockInitialValues(<String, Object>{});
            I18n.setLocale(locale);
            await tester.runAsync(_loadFonts);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;

            final providers = _Providers();
            final boundary = GlobalKey();
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              providers.dispose();
              tester.view.reset();
              I18n.setLocale(AppLocale.zh);
              SharedPreferences.setMockInitialValues(<String, Object>{});
            });

            expect(providers.theme.brand.id, AppBrands.defaultBrand.id);
            final lunar = LunarCalendar.fromSolar(_diaryDate);
            expect(lunar.year, 2023);
            expect(lunar.month, 2);
            expect(lunar.day, 1);
            expect(lunar.isLeapMonth, isTrue);

            final listItem = Anniversary.create(
              id: 'lunar-layout-list',
              title: '闰月纪念日',
              solarDate: _diaryDate,
              type: AnniversaryType.normal,
              calendarType: AnniversaryCalendarType.lunar,
            );
            if (surface == _DisplaySurface.anniversaryList) {
              await providers.anniversaries.add(listItem);
            }

            final home = switch (surface) {
              _DisplaySurface.diary => DiaryEditScreen(initialDate: _diaryDate),
              _DisplaySurface.anniversaryList => const AnniversaryScreen(),
              _DisplaySurface.anniversary => _AnniversaryEditorLauncher(
                item: Anniversary.create(
                  id: 'lunar-layout-anniversary',
                  title: '闰月纪念日',
                  solarDate: _diaryDate,
                  type: AnniversaryType.memorial,
                  calendarType: AnniversaryCalendarType.lunar,
                ),
              ),
              _DisplaySurface.agenda => Scaffold(
                body: CalendarDayAgenda(
                  date: _agendaDate,
                  calendarProvider: providers.calendar,
                ),
              ),
            };

            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(
                    value: providers.theme,
                  ),
                  ChangeNotifierProvider<AnniversaryProvider>.value(
                    value: providers.anniversaries,
                  ),
                  ChangeNotifierProvider<CourseProvider>.value(
                    value: providers.courses,
                  ),
                  ChangeNotifierProvider<DiaryProvider>.value(
                    value: providers.diary,
                  ),
                  ChangeNotifierProvider<TodoProvider>.value(
                    value: providers.todos,
                  ),
                ],
                child: MaterialApp(
                  theme: providers.theme.brand.theme.copyWith(
                    platform: TargetPlatform.iOS,
                  ),
                  builder: (context, child) => RepaintBoundary(
                    key: boundary,
                    child: MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                      child: child!,
                    ),
                  ),
                  home: BrandRouteSurface(child: home),
                ),
              ),
            );
            await tester.pumpAndSettle();

            switch (surface) {
              case _DisplaySurface.diary:
                _expectDiaryLunarDate(tester, locale, lunar);
                break;
              case _DisplaySurface.anniversary:
                await tester.tap(
                  find.byKey(const ValueKey('open_lunar_anniversary_editor')),
                );
                await tester.pumpAndSettle();
                await _revealAnniversaryDateTile(tester);
                final editorDate = LunarCalendar.fromSolar(_diaryDate);
                final editorLunarText = AlmanacLocaleFormat.formatFullLunarDate(
                  editorDate,
                  includeGanzhi: true,
                );
                expect(find.textContaining(editorLunarText), findsOneWidget);
                expect(tester.takeException(), isNull);
                break;
              case _DisplaySurface.anniversaryList:
                // The summary is intentionally disposed when it scrolls outside
                // the viewport/cache; check it before revealing the final card.
                expect(
                  find.text(I18n.tr('countdown.nearest.empty')),
                  findsWidgets,
                );
                expect(find.text(I18n.tr('anniversary.empty')), findsNothing);
                final listScrollable = find
                    .descendant(
                      of: find.byKey(const ValueKey('anniversary_fixed_all')),
                      matching: find.byType(Scrollable),
                    )
                    .first;
                if (locale == AppLocale.en) {
                  await tester.scrollUntilVisible(
                    find.text('Anniversary list'),
                    100,
                    scrollable: listScrollable,
                  );
                  expect(find.text('Anniversary list'), findsOneWidget);
                }
                final card = find.byKey(
                  ValueKey('anniversary_card_${listItem.id}'),
                );
                await tester.scrollUntilVisible(
                  card,
                  100,
                  scrollable: listScrollable,
                );
                await tester.pumpAndSettle();
                // Exercise the trailing space with normal scrolling. A tall
                // card aligned to the top has not yet used that space.
                await tester.drag(listScrollable, const Offset(0, -500));
                await tester.pumpAndSettle();
                final list = tester.widget<ListView>(
                  find.byKey(const ValueKey('anniversary_fixed_all')),
                );
                expect((list.padding! as EdgeInsets).bottom, 88);
                final cardRect = tester.getRect(card);
                final fabRect = tester.getRect(
                  find.byType(FloatingActionButton),
                );
                expect(
                  cardRect.overlaps(fabRect),
                  isFalse,
                  reason:
                      'card=$cardRect fab=$fabRect scroll=${tester.state<ScrollableState>(listScrollable).position}',
                );
                expect(
                  find.descendant(
                    of: card,
                    matching: find.textContaining(
                      AlmanacLocaleFormat.formatLunarDate(lunar),
                    ),
                  ),
                  findsOneWidget,
                );
                final dateText = find.descendant(
                  of: card,
                  matching: find.textContaining(
                    AlmanacLocaleFormat.formatLunarDate(lunar),
                  ),
                );
                // First verify bottom padding using a normal end-of-list drag,
                // then explicitly reveal the date paragraph before measuring it.
                await Scrollable.ensureVisible(
                  tester.element(dateText),
                  alignment: .1,
                );
                await tester.pumpAndSettle();
                final dateRect = tester.getRect(dateText);
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(
                    of: dateText,
                    matching: find.byType(RichText),
                  ),
                );
                expect(paragraph.didExceedMaxLines, isFalse);
                expect(
                  paragraph.textSize.width,
                  lessThanOrEqualTo(paragraph.size.width + .1),
                );
                expect(
                  paragraph.textSize.height,
                  lessThanOrEqualTo(paragraph.size.height + .1),
                );
                expect(
                  dateRect.top,
                  greaterThanOrEqualTo(tester.getRect(listScrollable).top),
                );
                expect(dateRect.bottom, lessThan(fabRect.top));
                break;
              case _DisplaySurface.agenda:
                _expectAgendaLunarHeader(tester, locale);
                break;
            }

            expect(tester.takeException(), isNull);
            await _capture(
              tester,
              boundary,
              '${surface.name}-${locale.name}-${layout.name}',
            );
          },
        );
      }
    }
  }
}

void _expectDiaryLunarDate(
  WidgetTester tester,
  AppLocale locale,
  LunarDate lunar,
) {
  final expectedMonthAndDay = AlmanacLocaleFormat.formatLunarDate(lunar);
  expect(find.textContaining(expectedMonthAndDay), findsOneWidget);
  if (locale == AppLocale.en) {
    expect(find.textContaining('Leap Month 2, Day 1'), findsOneWidget);
    expect(find.text('Chinese Lunar Calendar'), findsNothing);
  } else {
    expect(find.textContaining(lunar.chineseText), findsOneWidget);
  }
}

void _expectAgendaLunarHeader(WidgetTester tester, AppLocale locale) {
  final lunar = LunarCalendar.fromSolar(_agendaDate);
  final festival = LunarCalendar.lunarFestival(lunar);
  expect(lunar.month, 1);
  expect(lunar.day, 1);
  expect(festival, isNotNull);
  final expectedHeader =
      '${I18n.tr('calendar.chinese_lunar_calendar')} '
      '${AlmanacLocaleFormat.formatLunarDate(lunar, locale)}';
  expect(find.text(expectedHeader), findsOneWidget);
  expect(
    find.text(AlmanacLocaleFormat.formatFestival(festival, locale)!),
    findsOneWidget,
  );
}

Future<void> _revealAnniversaryDateTile(WidgetTester tester) async {
  final modal = find.byType(AppModalSheet).last;
  final scrollable = find
      .descendant(of: modal, matching: find.byType(Scrollable))
      .first;
  final dateTile = find.byKey(const ValueKey('anniversary_editor_date_tile'));
  await tester.scrollUntilVisible(
    dateTile,
    100,
    scrollable: scrollable,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
  expect(dateTile, findsOneWidget);
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (Platform.environment['DUOYI_CAPTURE_DATE_SETTINGS_SCREENSHOTS'] != '1') {
    return;
  }
  await tester.pump();
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('evidence/screenshots/lunar-display-20261015/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _loadFonts() async {
  await loadWidgetPolishScreenshotFonts();
  final latin = ByteData.sublistView(
    File('assets/fonts/DejaVuSans.ttf').readAsBytesSync(),
  );
  for (final family in ['sans-serif', 'DejaVu Sans', 'Roboto']) {
    await (FontLoader(family)..addFont(Future.value(latin))).load();
  }
  final chinese = ByteData.sublistView(
    File('assets/fonts/DroidSansFallbackFull.ttf').readAsBytesSync(),
  );
  for (final family in [
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'Microsoft YaHei',
    'WenQuanYi Micro Hei',
    'DroidSansFallbackFull',
  ]) {
    await (FontLoader(family)..addFont(Future.value(chinese))).load();
  }
  await PaintingBinding.instance.handleSystemMessage(<String, dynamic>{
    'type': 'fontsChange',
  });
}

class _AnniversaryEditorLauncher extends StatelessWidget {
  const _AnniversaryEditorLauncher({required this.item});

  final Anniversary item;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: const ValueKey('open_lunar_anniversary_editor'),
        onPressed: () =>
            showAnniversaryEditor(context, item: item, fixedType: item.type),
        child: const Text('Open anniversary editor'),
      ),
    ),
  );
}

class _Providers {
  final ThemeProvider theme = ThemeProvider();
  final AnniversaryProvider anniversaries = AnniversaryProvider();
  final CalendarProvider calendar = CalendarProvider();
  final CourseProvider courses = CourseProvider();
  final DiaryProvider diary = DiaryProvider();
  final TodoProvider todos = TodoProvider();

  void dispose() {
    theme.dispose();
    anniversaries.dispose();
    calendar.dispose();
    courses.dispose();
    diary.dispose();
    todos.dispose();
  }
}

enum _DisplaySurface { diary, anniversary, anniversaryList, agenda }

const _layouts = <({String name, Size size, double scale})>[
  (name: 'narrow', size: Size(320, 844), scale: 1.3),
  (name: 'landscape', size: Size(568, 320), scale: 1.6),
];
