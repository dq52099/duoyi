import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/main_ui_copy.dart';
import 'package:duoyi/models/calendar_event.dart';
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
import 'package:duoyi/widgets/calendar_event_sheet.dart';
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

class _LocalCalendar extends CalendarProvider {
  _LocalCalendar(this.event);
  final CalendarEvent event;
  @override
  List<CalendarEvent> getEventsForDate(
    DateTime date, {
    Set<CalendarEventType>? activeTypes,
    String? projectKey,
    String? workspaceId,
  }) => [event];
}

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
    for (final state in ['normal', 'completed', 'overdue']) {
      for (final layout in _layouts) {
        final name = 'calendar-untimed-$brand-$state-${layout.name}';
        testWidgets(name, (tester) async {
          final event = CalendarEvent(
            id: 'untimed-$state',
            title: 'Review / 复核',
            subtitle:
                'Review the plan and confirm each next step. 请核对最新安排、确认下一步，并保留这条备注全文。',
            date: DateTime(state == 'overdue' ? 2020 : 2030, 6, 29),
            endDate: state == 'overdue' ? DateTime(2020, 6, 29) : null,
            type: CalendarEventType.todo,
            isCompleted: state == 'completed',
            hasConflict: state == 'overdue',
            color: Colors.blue,
          );
          final originalEvent = event.toJson();
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
          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient(
                (_) async => fail('No fixture HTTP allowed'),
              ),
            ),
          );
          final boundary = GlobalKey();
          final agendaKey = GlobalKey();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            theme.dispose();
            anniversaries.dispose();
            courses.dispose();
            auth.dispose();
          });
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<AnniversaryProvider>.value(
                  value: anniversaries,
                ),
                ChangeNotifierProvider<CourseProvider>.value(value: courses),
                ChangeNotifierProvider(create: (_) => DiaryProvider()),
                ChangeNotifierProvider(create: (_) => TodoProvider()),
                ChangeNotifierProvider<CalendarProvider>(
                  create: (_) => _LocalCalendar(event),
                ),
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
                                      date: event.date,
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
          final scrolling = find
              .descendant(
                of: find.byType(CalendarDayAgenda),
                matching: find.byType(Scrollable),
              )
              .first;
          final scrollState = tester.state<ScrollableState>(scrolling);
          final probe = RouteRenderProbe(tester, boundary, name);
          final card = find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_DraggableEventCard',
          );
          Future<void> inspect(String stage) async {
            scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
            await tester.pumpAndSettle();
            expect(card, findsOneWidget);
            final surfaces = find.descendant(
              of: card,
              matching: find.byType(AppSurfaceCard),
            );
            if (surfaces.evaluate().length != 1) {
              probe.errors.add('$stage: missing shared untimed card surface');
            }
            probe.rows.add({
              'role': '$stage surface',
              'sharedSurface': surfaces.evaluate().length == 1,
              'brand': theme.brand.id,
              'completed': event.isCompleted,
              'conflict': event.hasConflict,
            });
            for (final (label, size) in [
              (event.title, 13.0),
              (event.subtitle!, 11.0),
              if (state != 'normal')
                (
                  state == 'completed'
                      ? MainUiCopy.calendarStatusCompleted
                      : MainUiCopy.calendarStatusOverdue,
                  10.0,
                ),
            ]) {
              final text = find.descendant(
                of: card,
                matching: find.text(label),
              );
              await probe.text(
                text,
                role: '$stage $size',
                minimumGeometricScale: .999,
              );
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: text, matching: find.byType(RichText)),
              );
              expect(paragraph.text.style!.fontSize, size);
              expect(paragraph.text.style!.fontWeight, FontWeight.normal);
              expect(
                paragraph.textScaler.scale(size),
                layout.scaler.scale(size),
              );
              for (final word in RegExp(r'[A-Za-z]+').allMatches(label)) {
                final boxes = paragraph.getBoxesForSelection(
                  TextSelection(baseOffset: word.start, extentOffset: word.end),
                );
                if (boxes.map((b) => (b.top * 10).round()).toSet().length > 1) {
                  probe.errors.add('$stage splits word ${word.group(0)}');
                }
              }
              if (label == event.title) {
                expect(
                  paragraph.text.style!.decoration ==
                      TextDecoration.lineThrough,
                  event.isCompleted,
                );
              }
            }
            await Scrollable.ensureVisible(tester.element(card), alignment: .5);
            await tester.pumpAndSettle();
            final rect = tester.getRect(card);
            probe.rows.add({
              'role': '$stage card',
              'left': rect.left,
              'top': rect.top,
              'right': rect.right,
              'bottom': rect.bottom,
            });
            await probe.capture(stage);
            final title = find.descendant(
              of: card,
              matching: find.text(event.title),
            );
            expect(title.hitTestable(), findsOneWidget);
            await tester.tap(title);
            await tester.pumpAndSettle();
            final sheet = find.byType(CalendarEventSheet);
            expect(sheet, findsOneWidget);
            expect(tester.widget<CalendarEventSheet>(sheet).event.id, event.id);
            final detailSubtitle = find.descendant(
              of: sheet,
              matching: find.text(event.subtitle!),
            );
            expect(detailSubtitle, findsOneWidget);
            await tester.ensureVisible(detailSubtitle);
            await tester.pumpAndSettle();
            Navigator.of(tester.element(sheet)).pop();
            await tester.pumpAndSettle();
            expect(agendaKey.currentContext, same(agenda));
            expect(tester.state<ScrollableState>(scrolling), same(scrollState));
            expect(event.toJson(), originalEvent);
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
          await inspect('live');
          expect(await tester.runAsync(() => theme.setBrand(brand)), isTrue);
          I18n.setLocale(AppLocale.zh);
          await tester.pumpAndSettle();
          await inspect('restored');
          await probe.finish();
        });
      }
    }
  }
}
