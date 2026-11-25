// Synthetic paired-theme route regression; optional evidence uses DUOYI_SECONDARY_* env vars.
import 'package:duoyi/core/export_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/export_screen.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../support/secondary_route_render_probe.dart';
import '../support/secondary_route_header_probe.dart';

Future<void> _checkSwitchWords(RouteRenderProbe probe, String stage) async {
  final tester = probe.tester;
  final labels = find.descendant(
    of: find.byType(AppSwitchTile),
    matching: find.byType(Text),
  );
  for (final element in labels.evaluate().toList()) {
    final label = find.byWidget(element.widget);
    await probe.text(label, role: '$stage switch label');
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: label, matching: find.byType(RichText)),
    );
    final text = (element.widget as Text).data!;
    for (final word in RegExp(r'[A-Za-z]+').allMatches(text)) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: word.start, extentOffset: word.end),
      );
      final lines = boxes.map((box) => box.top).toSet().length;
      probe.rows.add({
        'role': '$stage switch word',
        'word': word.group(0),
        'lines': lines,
      });
      if (lines > 1) probe.errors.add('$stage splits ${word.group(0)}');
    }
  }
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in [
        (name: 'common', size: const Size(390, 844), scale: 1.0),
        (name: 'narrow', size: const Size(320, 844), scale: 1.6),
        (name: 'landscape', size: const Size(568, 320), scale: 2.0),
        (name: 'desktop', size: const Size(1000, 720), scale: 1.1),
        (name: 'large', size: const Size(320, 844), scale: 2.0),
        (name: 'nonlinear', size: const Size(332, 844), scale: -1.0),
      ]) {
        final name = 'export-$brand-${locale.name}-${layout.name}';
        testWidgets('export generated guidance layout and contrast $name', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          I18n.setLocale(locale);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final theme = ThemeProvider();
          final auth = AuthProvider();
          final anniversaries = AnniversaryProvider();
          final calendar = CalendarProvider();
          final countdown = CountdownProvider();
          final course = CourseProvider();
          final diary = DiaryProvider();
          final goal = GoalProvider();
          final habit = HabitProvider();
          final pomodoro = PomodoroProvider();
          final todo = TodoProvider();
          final sync = CalendarSyncProvider();
          await tester.runAsync(() async {
            await theme.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            for (final provider in <ChangeNotifier>[
              theme,
              auth,
              anniversaries,
              calendar,
              countdown,
              course,
              diary,
              goal,
              habit,
              pomodoro,
              todo,
              sync,
            ]) {
              provider.dispose();
            }
          });
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<AnniversaryProvider>.value(
                  value: anniversaries,
                ),
                ChangeNotifierProvider<CalendarProvider>.value(value: calendar),
                ChangeNotifierProvider<CountdownProvider>.value(
                  value: countdown,
                ),
                ChangeNotifierProvider<CourseProvider>.value(value: course),
                ChangeNotifierProvider<DiaryProvider>.value(value: diary),
                ChangeNotifierProvider<GoalProvider>.value(value: goal),
                ChangeNotifierProvider<HabitProvider>.value(value: habit),
                ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
                ChangeNotifierProvider<TodoProvider>.value(value: todo),
                ChangeNotifierProvider<CalendarSyncProvider>.value(value: sync),
              ],
              child: ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, selected, _) => MaterialApp(
                  locale: Locale(selected == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme.brand.theme,
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
                          key: const ValueKey('probe_open_route'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BrandRouteSurface(
                                child: ExportScreen(),
                              ),
                            ),
                          ),
                          child: const Text('Open synthetic route'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('probe_open_route')));
          await tester.pumpAndSettle();
          expect(theme.brand.id, brand);
          final state = tester.state(find.byType(ExportScreen));
          final probe = RouteRenderProbe(tester, boundary, name);
          await checkSecondaryRouteHeader(
            probe,
            'export.title',
            stage: 'initial',
          );
          await probe.capture('top');
          for (final key in [
            'export.hero.title',
            'export.hero.subtitle',
            'export.range.title',
            'export.range.subtitle',
            'export.include_anniversaries',
            'export.include_calendar',
            'export.include_calendar.subtitle',
          ]) {
            await probe.text(find.text(I18n.tr(key)), role: key);
          }
          await probe.text(
            find.text(ExportUiCopy.current().anniversaryRangeHint),
            role: 'anniversary range hint',
          );
          await _checkSwitchWords(probe, 'initial');
          await probe.capture('range');
          await probe.text(
            find.text(ExportUiCopy.current().calDavScope),
            role: 'CalDAV scope',
          );
          final generate = find.byKey(const ValueKey('export_generate'));
          await probe.reveal(generate);
          expect(generate.hitTestable(), findsOneWidget);
          await tester.tap(generate);
          await tester.pumpAndSettle();
          final preview = find.byType(SelectableText);
          expect(preview, findsOneWidget);
          final bytes = tester.widget<SelectableText>(preview).data!;
          expect(bytes, contains('BEGIN:VCALENDAR'));
          for (final text in [
            I18n.tr('export.content.title'),
            I18n.tr('export.copy'),
            ExportUiCopy.current().snapshotHint,
          ]) {
            await probe.text(find.text(text), role: 'preview guidance');
          }
          await probe.capture('preview');
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(ExportScreen)), same(state));
          expect(tester.widget<SelectableText>(preview).data, bytes);
          final list = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const PageStorageKey('export_list')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          list.position.jumpTo(0);
          await tester.pumpAndSettle();
          await probe.text(
            find.text(I18n.tr('export.hero.subtitle')),
            role: 'live hero subtitle',
          );
          await _checkSwitchWords(probe, 'live');
          await probe.capture('live-range');
          list.position.jumpTo(list.position.maxScrollExtent);
          await tester.pumpAndSettle();
          await probe.text(
            find.text(ExportUiCopy.current().snapshotHint),
            role: 'live snapshot hint',
          );
          await probe.capture('live');
          await checkSecondaryRouteHeader(probe, 'export.title', stage: 'live');
          await probe.finish();
          final back = find.byType(BackButton);
          expect(back.hitTestable(), findsOneWidget);
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(find.byType(ExportScreen), findsNothing);
          expect(
            find.byKey(const ValueKey('probe_open_route')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
