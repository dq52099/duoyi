import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/today_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart' show priorityLayouts;
import '../support/rendered_control_contrast.dart';
import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final initialLocale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name =
            'detail-fallback-$brand-${initialLocale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          I18n.setLocale(initialLocale);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final theme = ThemeProvider();
          final auth = AuthProvider();
          final todos = _RecoverableTodos();
          final courses = CourseProvider();
          final anniversaries = AnniversaryProvider();
          final goals = GoalProvider();
          final habits = HabitProvider();
          final notes = NoteProvider();
          final diary = DiaryProvider();
          final share = ShareProvider();
          final shadows = debugDisableShadows;
          try {
            debugDisableShadows = false;
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              for (final provider in <ChangeNotifier>[
                theme,
                auth,
                todos,
                courses,
                anniversaries,
                goals,
                habits,
                notes,
                diary,
                share,
              ]) {
                provider.dispose();
              }
            });
            await theme.loadFromStorage();
            await tester.runAsync(loadWeeklyReviewScreenshotFonts);
            final prefs = await SharedPreferences.getInstance();
            Map<String, Object?> stored() => {
              for (final key in prefs.getKeys()) key: prefs.get(key),
            };
            final before = stored();
            final boundary = GlobalKey();
            var kind = TodaySectionKind.todos;
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<AuthProvider>.value(value: auth),
                  ChangeNotifierProvider<TodoProvider>.value(value: todos),
                  ChangeNotifierProvider<CourseProvider>.value(value: courses),
                  ChangeNotifierProvider<AnniversaryProvider>.value(
                    value: anniversaries,
                  ),
                  ChangeNotifierProvider<GoalProvider>.value(value: goals),
                  ChangeNotifierProvider<HabitProvider>.value(value: habits),
                  ChangeNotifierProvider<NoteProvider>.value(value: notes),
                  ChangeNotifierProvider<DiaryProvider>.value(value: diary),
                  ChangeNotifierProvider<ShareProvider>.value(value: share),
                ],
                child: ValueListenableBuilder<AppLocale>(
                  valueListenable: I18n.localeListenable,
                  builder: (context, locale, _) => MaterialApp(
                    theme: theme.brand.theme,
                    locale: Locale(locale == AppLocale.en ? 'en' : 'zh'),
                    supportedLocales: const [Locale('en'), Locale('zh')],
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: layout.scale < 0
                            ? const RouteProbeNonlinearScaler()
                            : TextScaler.linear(layout.scale),
                      ),
                      child: RepaintBoundary(key: boundary, child: child!),
                    ),
                    home: Builder(
                      builder: (context) => Scaffold(
                        body: Center(
                          child: TextButton(
                            key: const ValueKey('open-detail'),
                            onPressed: () => TodayDetailRouter.open(
                              context,
                              kind,
                              id: 'deleted/object',
                            ),
                            child: const Text('Open'),
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
            final alternate = initialLocale == AppLocale.zh
                ? AppLocale.en
                : AppLocale.zh;

            Future<void> open() async {
              await tester.tap(find.byKey(const ValueKey('open-detail')));
              await tester.pumpAndSettle();
              expect(find.byType(BrandRouteSurface), findsOneWidget);
            }

            Future<void> measure(
              String stage,
              String body, {
              bool current = true,
              bool failed = false,
            }) async {
              final appBar = find.byType(AppBar);
              final title = find.descendant(
                of: appBar,
                matching: find.text(TodayUiCopy.detailTitle(kind.name)),
              );
              await probe.text(
                title,
                role: '$stage title',
                minimumGeometricScale: .999,
              );
              final bar = tester.getRect(appBar);
              final titleRect = tester.getRect(title);
              for (final control
                  in find
                      .descendant(of: appBar, matching: find.byType(IconButton))
                      .evaluate()) {
                final finder = find.byElementPredicate(
                  (e) => identical(e, control),
                );
                expect(finder.hitTestable(), findsOneWidget);
                if (titleRect.overlaps(tester.getRect(finder))) {
                  probe.errors.add('$stage title overlaps navigation');
                }
              }
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: title, matching: find.byType(RichText)),
              );
              for (final box in paragraph.getBoxesForSelection(
                TextSelection(
                  baseOffset: 0,
                  extentOffset: TodayUiCopy.detailTitle(kind.name).length,
                ),
              )) {
                final top = paragraph.localToGlobal(Offset(box.left, box.top));
                final bottom = paragraph.localToGlobal(
                  Offset(box.right, box.bottom),
                );
                if (top.dy < bar.top - .1 ||
                    bottom.dy > bar.bottom + .1 ||
                    top.dx < -.1 ||
                    bottom.dx > layout.size.width + .1) {
                  probe.errors.add('$stage title outside toolbar');
                }
              }
              if (kind == TodaySectionKind.anniversaries ||
                  failed ||
                  !current) {
                await probe.capture('$stage-title');
              }
              await probe.text(
                find.text(body),
                role: '$stage body',
                minimumGeometricScale: .999,
              );
              for (final label in [
                if (current)
                  failed ? I18n.tr('action.retry') : TodayUiCopy.detailOpenList,
                I18n.tr('action.back'),
              ]) {
                final button = find.widgetWithText(FilledButton, label);
                await probe.reveal(button);
                expectControlTouchTarget(tester, button);
                await probe.text(
                  find.descendant(of: button, matching: find.text(label)),
                  role: '$stage action',
                  minimumGeometricScale: .999,
                );
              }
              if (kind == TodaySectionKind.anniversaries ||
                  failed ||
                  !current) {
                await probe.capture('$stage-actions');
              }
              expect(
                find.textContaining('synthetic-private-error'),
                findsNothing,
              );
              expect(stored(), before);
              expect(tester.takeException(), isNull);
            }

            Future<void> back() async {
              final button = find.widgetWithText(
                FilledButton,
                I18n.tr('action.back'),
              );
              await probe.reveal(button);
              await tester.tap(button);
              await tester.pumpAndSettle();
              expect(find.byKey(const ValueKey('open-detail')), findsOneWidget);
              expect(find.byType(BrandRouteSurface), findsNothing);
            }

            for (final missingKind in TodaySectionKind.values) {
              kind = missingKind;
              I18n.setLocale(initialLocale);
              await tester.pumpAndSettle();
              await open();
              final retained = tester.element(find.byType(Scaffold).last);
              for (final locale in [initialLocale, alternate]) {
                I18n.setLocale(locale);
                await tester.pumpAndSettle();
                expect(
                  tester.element(find.byType(Scaffold).last),
                  same(retained),
                );
                await measure(
                  '${kind.name}-${locale.name}-missing',
                  TodayUiCopy.detailMissing(kind.name),
                );
              }
              await back();
            }

            kind = TodaySectionKind.todos;
            I18n.setLocale(initialLocale);
            todos.failReads = true;
            await open();
            final retained = tester.element(find.byType(Scaffold).last);
            for (final locale in [initialLocale, alternate, initialLocale]) {
              I18n.setLocale(locale);
              await tester.pumpAndSettle();
              expect(
                tester.element(find.byType(Scaffold).last),
                same(retained),
              );
              await measure(
                'error-${probe.rows.length}-${locale.name}',
                TodayUiCopy.detailOpenFailed,
                failed: true,
              );
            }
            await tester.tap(
              find.widgetWithText(FilledButton, I18n.tr('action.retry')),
            );
            await tester.pumpAndSettle();
            expect(find.text(TodayUiCopy.detailOpenFailed), findsOneWidget);
            todos.failReads = false;
            await tester.tap(
              find.widgetWithText(FilledButton, I18n.tr('action.retry')),
            );
            await tester.pumpAndSettle();
            await measure('recovered', TodayUiCopy.detailMissing(kind.name));
            final retry = tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, TodayUiCopy.detailOpenList),
                )
                .onPressed!;
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
            await tester.pumpAndSettle();
            final reads = todos.reads;
            retry();
            await tester.pumpAndSettle();
            expect(todos.reads, reads);
            expect(find.text(TodayUiCopy.detailOpenList), findsNothing);
            for (final locale in [initialLocale, alternate]) {
              I18n.setLocale(locale);
              await tester.pumpAndSettle();
              await measure(
                'changed-${locale.name}',
                TodayUiCopy.detailSourceChanged,
                current: false,
              );
            }

            // The reference is rendered only after the real route has been
            // removed. It cannot accidentally provide its backdrop to that route.
            final points = [
              for (final y in [.45, .7, .9]) Offset(4, layout.size.height * y),
            ];
            final actual = await _pixels(tester, boundary, points);
            await back();
            // Exercise the actual view-list replacement and return stack once.
            await open();
            final list = find.widgetWithText(
              FilledButton,
              TodayUiCopy.detailOpenList,
            );
            await probe.reveal(list);
            await tester.tap(list);
            await tester.pumpAndSettle();
            expect(find.byType(TodoScreen), findsOneWidget);
            Navigator.of(tester.element(find.byType(TodoScreen))).pop();
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('open-detail')), findsOneWidget);
            final reference = GlobalKey();
            await tester.pumpWidget(
              ChangeNotifierProvider<ThemeProvider>.value(
                value: theme,
                child: MaterialApp(
                  theme: theme.brand.theme,
                  home: RepaintBoundary(
                    key: reference,
                    child: Material(
                      color: theme.brand.theme.brightness == Brightness.dark
                          ? theme.brand.theme.colorScheme.surface
                          : theme
                                .brand
                                .theme
                                .colorScheme
                                .surfaceContainerLowest,
                      child: const BrandBackground(child: SizedBox.expand()),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final expected = await _pixels(tester, reference, points);
            for (var i = 0; i < points.length; i++) {
              probe.rows.add({
                'role': 'route backdrop $i',
                'actualRGBA': actual[i],
                'referenceRGBA': expected[i],
              });
              if (brand == 'liquidGlass' && actual[i] != expected[i]) {
                probe.errors.add('Glass backdrop hidden at margin $i');
              }
            }
            expect(stored(), before);
            await probe.finish();
          } finally {
            debugDisableShadows = shadows;
          }
        });
      }
    }
  }
}

class _RecoverableTodos extends TodoProvider {
  bool failReads = false;
  int reads = 0;
  @override
  List<TodoItem> get todos {
    reads++;
    if (failReads) throw StateError('synthetic-private-error');
    return super.todos;
  }
}

Future<List<int>> _pixels(
  WidgetTester tester,
  GlobalKey key,
  List<Offset> points,
) async => (await tester.runAsync(() async {
  final render =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await render.toImage(pixelRatio: 1);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return [
      for (final point in points)
        data.getUint32((point.dy.floor() * image.width + point.dx.floor()) * 4),
    ];
  } finally {
    image.dispose();
  }
}))!;
