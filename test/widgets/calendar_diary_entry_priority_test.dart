import 'package:duoyi/core/calendar_agenda_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/calendar_day_agenda.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

final _date = DateTime(2026, 6, 29);
const _title =
    'A day of learning and reflection with friends and family at the library';

class _DiaryFixture extends DiaryProvider {
  _DiaryFixture(this.entry);
  final DiaryEntry? entry;

  @override
  DiaryEntry? entryForDate(DateTime date) => date == _date ? entry : null;
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
        for (final populated in [false, true]) {
          final name =
              'calendar-diary-$brand-${locale.name}-${layout.name}-$populated';
          testWidgets(name, (tester) async {
            SharedPreferences.setMockInitialValues({
              'active_brand': brand,
              'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
            });
            I18n.setLocale(locale);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final semantics = tester.ensureSemantics();
            try {
              final theme = ThemeProvider();
              final auth = AuthProvider(
                client: ApiClient(
                  baseUrl: 'https://duoyi.test',
                  httpClient: MockClient((_) async => fail('No fixture HTTP')),
                ),
              );
              final entry = populated
                  ? DiaryEntry(
                      id: 'synthetic-diary',
                      date: _date,
                      content:
                          '$_title\nA second paragraph remains in the editor.',
                      mood: Mood.good,
                    )
                  : null;
              final beforeEntry = entry?.toJson();
              await tester.runAsync(() async {
                await theme.loadFromStorage();
                await loadWeeklyReviewScreenshotFonts();
              });
              final boundary = GlobalKey();
              final nav = GlobalKey<NavigatorState>();
              final agendaKey = GlobalKey();
              final diary = _DiaryFixture(entry);
              addTearDown(() async {
                await tester.pumpWidget(const SizedBox.shrink());
                await tester.pumpAndSettle();
                diary.dispose();
                auth.dispose();
                theme.dispose();
              });
              await tester.pumpWidget(
                MultiProvider(
                  providers: [
                    ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                    ChangeNotifierProvider<AuthProvider>.value(value: auth),
                    ChangeNotifierProvider<DiaryProvider>.value(value: diary),
                    ChangeNotifierProvider(
                      create: (_) => AnniversaryProvider(),
                    ),
                    ChangeNotifierProvider(create: (_) => CourseProvider()),
                    ChangeNotifierProvider(create: (_) => TodoProvider()),
                    ChangeNotifierProvider(create: (_) => CalendarProvider()),
                  ],
                  child: Consumer<ThemeProvider>(
                    builder: (context, selectedTheme, _) =>
                        ValueListenableBuilder<AppLocale>(
                          valueListenable: I18n.localeListenable,
                          builder: (context, selectedLocale, _) => MaterialApp(
                            navigatorKey: nav,
                            theme: selectedTheme.brand.theme,
                            locale: Locale(selectedLocale.storageValue),
                            supportedLocales: const [
                              Locale('zh'),
                              Locale('en'),
                            ],
                            localizationsDelegates:
                                GlobalMaterialLocalizations.delegates,
                            builder: (context, child) => MediaQuery(
                              data: MediaQuery.of(context).copyWith(
                                textScaler: TextScaler.linear(layout.scale),
                              ),
                              child: RepaintBoundary(
                                key: boundary,
                                child: child!,
                              ),
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
                                          date: _date,
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
              final probe = RouteRenderProbe(tester, boundary, name);
              final agendaElement = agendaKey.currentContext;
              final quick = find.descendant(
                of: find.byType(CalendarDayAgenda),
                matching: find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_DiaryQuickEntry',
                ),
              );
              final scrollState = tester.state(
                find
                    .descendant(
                      of: find.byType(CalendarDayAgenda),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );

              Future<void> inspect(String stage) async {
                final label = populated
                    ? _title
                    : CalendarAgendaUiCopy.emptyDiaryPrompt;
                final text = find.descendant(
                  of: quick,
                  matching: find.text(label),
                );
                await probe.text(
                  text,
                  role: '$stage diary action',
                  minimumGeometricScale: .999,
                );
                final entryContext = tester.element(quick);
                expect(
                  Theme.of(entryContext).colorScheme.primary,
                  theme.brand.theme.colorScheme.primary,
                );
                final cards = find.descendant(
                  of: quick,
                  matching: find.byType(AppSurfaceCard),
                );
                if (cards.evaluate().length != 1) {
                  probe.errors.add(
                    '$stage diary bypasses shared themed surface',
                  );
                } else {
                  final ink = tester.widget<Ink>(
                    find.descendant(of: cards, matching: find.byType(Ink)),
                  );
                  final decoration = ink.decoration! as BoxDecoration;
                  final style = appSurfaceStyleOf(entryContext)!;
                  expect(decoration.color, style.cardFillColor);
                  expect(decoration.border, style.cardBorder);
                  expect(
                    decoration.borderRadius,
                    BorderRadius.circular(style.cardRadius),
                  );
                }
                final rect = tester.getRect(quick);
                probe.rows.add({
                  'stage': stage,
                  'brand': theme.brand.id,
                  'locale': I18n.current.name,
                  'buttonHeight': rect.height,
                  'sharedSurface': cards.evaluate().length == 1,
                });
                if (rect.height < 44) {
                  probe.errors.add(
                    '$stage diary hit height ${rect.height} < 44',
                  );
                }
                final node = tester.getSemantics(quick);
                if (!node.flagsCollection.isButton ||
                    !node.getSemanticsData().hasAction(SemanticsAction.tap)) {
                  probe.errors.add('$stage diary lacks button/tap semantics');
                }
                await probe.capture(stage);
              }

              await inspect('initial');
              final otherBrand = brand == 'defaultBrand'
                  ? 'liquidGlass'
                  : 'defaultBrand';
              expect(
                await tester.runAsync(() => theme.setBrand(otherBrand)),
                isTrue,
              );
              I18n.setLocale(
                locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
              );
              await tester.pumpAndSettle();
              expect(
                identical(agendaKey.currentContext, agendaElement),
                isTrue,
              );
              expect(
                tester.state(
                  find
                      .descendant(
                        of: find.byType(CalendarDayAgenda),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                ),
                same(scrollState),
              );
              expect(theme.brand.id, otherBrand);
              await inspect('switched');

              // Hit the bottom edge, then inspect the actual production editor.
              final rect = tester.getRect(quick);
              await tester.tapAt(Offset(rect.center.dx, rect.bottom - 1));
              await tester.pumpAndSettle();
              expect(find.byType(DiaryEditScreen), findsOneWidget);
              final editor = tester.widget<DiaryEditScreen>(
                find.byType(DiaryEditScreen),
              );
              expect(editor.entry, same(entry));
              expect(editor.initialDate, _date);
              nav.currentState!.pop();
              await tester.pumpAndSettle();
              expect(find.byType(CalendarDayAgenda), findsOneWidget);
              expect(entry?.toJson(), beforeEntry);
              expect(diary.entries, isEmpty);
              final prefs = await SharedPreferences.getInstance();
              expect(prefs.containsKey('duoyi_diary'), isFalse);
              await probe.finish();
            } finally {
              semantics.dispose();
            }
          });
        }
      }
    }
  }
}
