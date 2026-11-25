import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/course_schedule.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/course_schedule_screen.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      testWidgets('published course detail $brand ${locale.name}', (
        tester,
      ) async {
        final selected = CourseItem(
          id: 'course /?#&=% 测试🌙',
          name: 'Selected user course',
          teacher: 'Selected teacher',
          location: 'Selected classroom',
          weekday: 2,
          startSection: 3,
          sectionCount: 2,
          weeks: [3, 5],
        );
        final other = CourseItem(
          id: 'other-course',
          name: 'Different user course',
          teacher: 'Other teacher',
          location: 'Other classroom',
          weekday: 4,
          startSection: 6,
          weeks: [1],
        );
        final stored = [
          other,
          selected,
        ].map((course) => jsonEncode(course.toJson())).toList();
        final settings = jsonEncode(
          ScheduleSettings(termStart: DateTime(2020, 1, 6)).toJson(),
        );
        SharedPreferences.setMockInitialValues({
          'active_brand': brand,
          'duoyi_courses': stored,
          'duoyi_course_settings': settings,
        });
        I18n.setLocale(locale);
        final courses = CourseProvider();
        final theme = ThemeProvider();
        try {
          await courses.loadFromStorage();
          await theme.loadFromStorage();
          expect(theme.brand.id, brand);
          expect(courses.viewingWeek, 1);
          // Begin at the decoded-ID Flutter receiver, not native URL delivery.
          final uri = Uri.parse(
            'duoyi://course/${Uri.encodeComponent(selected.id)}',
          );
          expect(uri.pathSegments, [selected.id]);
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<CourseProvider>.value(value: courses),
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ],
              child: MaterialApp(
                theme: theme.brand.theme,
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => TodayDetailRouter.open(
                        context,
                        TodaySectionKind.courses,
                        id: uri.pathSegments.first,
                      ),
                      child: const Text('Open published course'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open published course'));
          await tester.pumpAndSettle();
          expect(find.byType(BrandRouteSurface), findsOneWidget);
          expect(
            tester
                .widget<CourseScheduleScreen>(find.byType(CourseScheduleScreen))
                .initialCourseId,
            selected.id,
          );
          expect(courses.viewingWeek, 3);
          expect(find.byType(AppModalSheet), findsOneWidget);
          final fields = find.byType(TextField);
          expect(
            tester.widgetList<TextField>(fields).map((f) => f.controller?.text),
            [selected.name, selected.teacher, selected.location],
          );
          await tester.enterText(fields.first, 'Unsaved course draft');
          // Finish the focused editor's pending caret scroll before locating
          // the sheet's footer; it otherwise races ensureVisible.
          await tester.pumpAndSettle();
          final cancel = find.text(I18n.tr('action.cancel'));
          final scrollable = find
              .descendant(
                of: find.byType(AppModalSheet),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            cancel,
            200,
            scrollable: scrollable,
            maxScrolls: 30,
          );
          await tester.pumpAndSettle();
          expect(cancel.hitTestable(), findsOneWidget);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(find.byType(AppModalSheet), findsNothing);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Open published course'), findsOneWidget);
          expect(
            courses.courses.map((course) => jsonEncode(course.toJson())),
            stored,
          );
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getStringList('duoyi_courses'), stored);
          expect(prefs.getString('duoyi_course_settings'), settings);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          courses.dispose();
          theme.dispose();
          I18n.setLocale(AppLocale.zh);
        }
      });
    }
  }
}
