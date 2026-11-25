// Real timetable route, synthetic immutable courses, no HTTP or persistence.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/course_schedule.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/screens/course_schedule_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

final _settings = ScheduleSettings(termStart: DateTime(2026, 6, 29));
final _courses = [
  CourseItem(
    id: 'course /?#&=% short',
    name: 'Art',
    weekday: 1,
    startSection: 1,
    sectionCount: 1,
    colorValue: 0xFF4CAF50,
    weeks: [1, 3],
  ),
  CourseItem(
    id: 'orange',
    name: 'Lab',
    teacher: 'Lin',
    location: 'R1',
    weekday: 3,
    startSection: 3,
    sectionCount: 2,
    colorValue: 0xFFFFA726,
    weeks: [1, 3],
  ),
  CourseItem(
    id: 'blue',
    name: 'Math',
    teacher: 'Lee',
    location: 'R2',
    weekday: 5,
    startSection: 6,
    sectionCount: 3,
    colorValue: 0xFF42A5F5,
    weeks: [1, 3],
  ),
  CourseItem(
    id: 'purple',
    name: 'Music',
    teacher: 'Wu',
    location: 'R3',
    weekday: 7,
    startSection: 9,
    sectionCount: 3,
    colorValue: 0xFF5C6BC0,
    weeks: [1, 3],
  ),
];

class _SyntheticCourses extends CourseProvider {
  _SyntheticCourses([List<CourseItem>? items]) : _items = items ?? _courses;

  final List<CourseItem> _items;

  @override
  ScheduleSettings get settings => _settings;
  @override
  List<CourseItem> get courses => List.unmodifiable(_items);
  @override
  int get currentWeek => 1;
  @override
  List<CourseItem> coursesOfWeek(int week) =>
      _items.where((course) => course.activeInWeek(week)).toList();
}

class _GridProbe extends RouteRenderProbe {
  _GridProbe(super.tester, super.boundary, super.name, this.requested);

  final TextScaler requested;

  Finder backgroundFor(Finder text) {
    Element? parent;
    tester.element(text).visitAncestorElements((element) {
      if (element.widget is Container) {
        parent = element;
        return false;
      }
      return true;
    });
    expect(parent, isNotNull);
    return find.byElementPredicate((element) => identical(element, parent));
  }

  @override
  Future<void> reveal(Finder finder) async {
    expect(finder, findsOneWidget);
    final element = tester.element(finder);
    for (final axis in [Axis.horizontal, Axis.vertical]) {
      final scroll = Scrollable.maybeOf(element, axis: axis);
      if (scroll == null) continue;
      // ScrollPosition.ensureVisible chooses the nearest render viewport,
      // which is horizontal even when called on this grid's outer vertical
      // position. Use the selected scrollable's own viewport geometry instead.
      final viewport = scroll.context.findRenderObject()! as RenderBox;
      final target = tester.renderObject<RenderBox>(
        axis == Axis.horizontal ? backgroundFor(finder) : finder,
      );
      final rect = MatrixUtils.transformRect(
        target.getTransformTo(viewport),
        Offset.zero & target.size,
      );
      final delta = axis == Axis.horizontal
          ? rect.center.dx - viewport.size.width / 2
          : rect.center.dy - viewport.size.height / 2;
      scroll.position.jumpTo(
        (scroll.position.pixels + delta).clamp(
          scroll.position.minScrollExtent,
          scroll.position.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> measure(Finder finder, String role, double nominal) async {
    await text(
      finder,
      role: role,
      contrast: false,
      minimumGeometricScale: .999,
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)),
    );
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    Rect inBoundary(RenderBox object) => MatrixUtils.transformRect(
      object.getTransformTo(render),
      Offset.zero & object.size,
    );
    final paragraphRect = inBoundary(paragraph);
    final containerRect = inBoundary(
      tester.renderObject<RenderBox>(backgroundFor(finder)),
    );
    final inside =
        paragraphRect.left >= containerRect.left - .1 &&
        paragraphRect.right <= containerRect.right + .1 &&
        paragraphRect.top >= containerRect.top - .1 &&
        paragraphRect.bottom <= containerRect.bottom + .1;
    if (!inside) {
      errors.add('$role paragraph outside its painted container');
    }
    final point = Offset(containerRect.left + 1, paragraphRect.center.dy);
    expect(
      (Offset.zero & render.size).contains(point),
      isTrue,
      reason: '$role background sample must actually be on screen: $point',
    );
    for (final axis in [Axis.horizontal, Axis.vertical]) {
      final scroll = Scrollable.maybeOf(tester.element(finder), axis: axis);
      if (scroll == null) continue;
      final viewport = scroll.context.findRenderObject()! as RenderBox;
      final viewportRect = inBoundary(viewport);
      expect(
        viewportRect.contains(point),
        isTrue,
        reason: '$role background sample must be inside its $axis viewport',
      );
      expect(
        paragraphRect.intersect(viewportRect).size,
        paragraphRect.size,
        reason: '$role paragraph must be fully revealed before measurement',
      );
    }
    final background = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 1);
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final x = point.dx.floor(), y = point.dy.floor();
        expect(x, inInclusiveRange(0, image.width - 1));
        expect(y, inInclusiveRange(0, image.height - 1));
        final index = (y * image.width + x) * 4;
        return Color.fromARGB(
          255,
          bytes.getUint8(index),
          bytes.getUint8(index + 1),
          bytes.getUint8(index + 2),
        );
      } finally {
        image.dispose();
      }
    });
    final style = paragraph.text.style!;
    expect(style.fontSize, nominal);
    expect(style.fontWeight ?? FontWeight.normal, FontWeight.normal);
    expect(
      paragraph.textScaler.scale(nominal),
      closeTo(requested.scale(nominal), .001),
    );
    final foreground = style.foreground?.color ?? style.color!;
    final a = Color.alphaBlend(foreground, background!).computeLuminance();
    final b = background.computeLuminance();
    final ratio = (math.max(a, b) + .05) / (math.min(a, b) + .05);
    final size = paragraph.textScaler.scale(nominal);
    final required = size >= 24 ? 3.0 : 4.5;
    rows.last.addAll({
      'ratio': ratio,
      'required': required,
      'nominalFontSize': nominal,
      'actualFontSize': size,
      'foregroundARGB': foreground.toARGB32(),
      'backgroundARGB': background.toARGB32(),
      'insideContainer': inside,
      'sampleX': point.dx.floor(),
      'sampleY': point.dy.floor(),
    });
    if (ratio < required) {
      errors.add('$role contrast $ratio below $required');
    }
  }
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    testWidgets('course-content-boundary-$brand', (tester) async {
      final short = CourseItem(
        id: 'short-cjk',
        name: '美术',
        weekday: 1,
        startSection: 1,
        sectionCount: 1,
        weeks: [1],
      );
      final long = CourseItem(
        id: 'long-cjk',
        name: List.filled(200, '超长课程名称').join(),
        weekday: 3,
        startSection: 3,
        sectionCount: 1,
        weeks: [1],
      );
      final courses = _SyntheticCourses([short, long]);
      addTearDown(courses.dispose);
      final auth = AuthProvider(
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          httpClient: MockClient((_) async => fail('No fixture HTTP allowed')),
        ),
      );
      final boundary = await mountPriorityFixture(
        tester,
        auth: auth,
        brand: brand,
        locale: AppLocale.zh,
        size: const Size(320, 844),
        scale: 2,
        home: ChangeNotifierProvider<CourseProvider>.value(
          value: courses,
          child: const BrandRouteSurface(child: CourseScheduleScreen()),
        ),
      );
      expect(tester.takeException(), isNull);
      final size = tester.getSize(
        find.byKey(const ValueKey('course_schedule_adaptive_grid')),
      );
      // Arbitrarily long authored names must keep a bounded preview canvas.
      expect(size.width, lessThan(4096));
      final probe = _GridProbe(
        tester,
        boundary,
        'course-content-boundary-$brand',
        const TextScaler.linear(2),
      );
      await probe.measure(find.text(short.name), 'short CJK title', 12);
      await probe.text(
        find.text(long.name),
        role: 'long authored preview',
        contrast: false,
        allowPreviewEllipsis: true,
        minimumGeometricScale: .999,
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text(long.name),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraph.didExceedMaxLines, isTrue);
      probe.rows.add({'role': 'bounded canvas', 'gridWidth': size.width});
      await probe.finish();
    });
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'course-grid-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final courses = _SyntheticCourses();
          addTearDown(courses.dispose);
          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient(
                (_) async => fail('No fixture HTTP allowed'),
              ),
            ),
          );
          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: ChangeNotifierProvider<CourseProvider>.value(
              value: courses,
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      key: const ValueKey('open_course_grid'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BrandRouteSurface(
                            child: CourseScheduleScreen(),
                          ),
                        ),
                      ),
                      child: const Text('Open synthetic timetable'),
                    ),
                  ),
                ),
              ),
            ),
          );
          final prefs = await SharedPreferences.getInstance();
          final beforePrefs = {
            for (final key in prefs.getKeys()) key: prefs.get(key),
          };
          final beforeCourses = _courses
              .map((course) => course.toJson())
              .toList();
          final beforeSettings = _settings.toJson();
          await tester.tap(find.byKey(const ValueKey('open_course_grid')));
          await tester.pumpAndSettle();
          final screen = find.byType(CourseScheduleScreen);
          final screenElement = tester.element(screen);
          final grid = find.byKey(
            const ValueKey('course_schedule_adaptive_grid'),
          );
          final probe = _GridProbe(
            tester,
            boundary,
            name,
            layout.scale < 0
                ? const RouteProbeNonlinearScaler()
                : TextScaler.linear(layout.scale),
          );
          final initialFrameworkError = tester.takeException();
          if (initialFrameworkError != null) {
            probe.errors.add('initial framework: $initialFrameworkError');
          }

          Future<void> measure(String stage) async {
            final gridBox = tester.renderObject<RenderBox>(grid);
            Rect inGrid(RenderBox object) => MatrixUtils.transformRect(
              object.getTransformTo(gridBox),
              Offset.zero & object.size,
            );
            for (var day = 1; day <= 7; day++) {
              final weekday = find.descendant(
                of: grid,
                matching: find.text(
                  I18n.tr(
                    'weekday.${['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'][day - 1]}',
                  ),
                ),
              );
              await probe.measure(weekday, '$stage weekday $day', 12);
              final date = _settings.termStart.add(Duration(days: day - 1));
              await probe.measure(
                find.descendant(
                  of: grid,
                  matching: find.text('${date.month}/${date.day}'),
                ),
                '$stage date $day',
                11,
              );
            }
            for (
              var session = 1;
              session <= _settings.sessionsPerDay;
              session++
            ) {
              await probe.measure(
                find.descendant(of: grid, matching: find.text('$session')),
                '$stage period $session',
                11,
              );
            }
            for (final course in _courses) {
              final card = find.byWidgetPredicate((widget) {
                if (widget.runtimeType.toString() != '_CourseBlock') {
                  return false;
                }
                final dynamic block = widget;
                return (block.course as CourseItem).id == course.id;
              });
              expect(card, findsOneWidget);
              final title = find.descendant(
                of: card,
                matching: find.text(course.name),
              );
              final time = find.descendant(
                of: card,
                matching: find.text(
                  _settings.sectionTimeRangeLabel(
                    course.startSection,
                    course.sectionCount,
                  ),
                ),
              );
              await probe.measure(time, '$stage ${course.id} time', 9);
              await probe.measure(title, '$stage ${course.id} title', 12);
              if (layout.name == 'desktop' && course.sectionCount >= 2) {
                expect(
                  find.descendant(
                    of: card,
                    matching: find.text('@${course.location}'),
                  ),
                  findsOneWidget,
                );
                if (course.sectionCount >= 3) {
                  expect(
                    find.descendant(
                      of: card,
                      matching: find.text(course.teacher),
                    ),
                    findsOneWidget,
                  );
                  expect(
                    find.descendant(
                      of: card,
                      matching: find.text(
                        '2${I18n.tr('course.week.count_suffix')}',
                      ),
                    ),
                    findsOneWidget,
                  );
                }
              }
              for (final text
                  in find
                      .descendant(of: card, matching: find.byType(Text))
                      .evaluate()) {
                final widget = text.widget as Text;
                if (widget.data == course.name ||
                    widget.data == tester.widget<Text>(time).data) {
                  continue;
                }
                final nominal =
                    widget.data!.startsWith('@') ||
                        widget.data == course.teacher
                    ? 10.0
                    : 9.0;
                await probe.measure(
                  find.byWidget(widget),
                  '$stage ${course.id} metadata ${widget.data}',
                  nominal,
                );
              }
              final rect = inGrid(tester.renderObject<RenderBox>(card));
              final firstPeriod = find.descendant(
                of: grid,
                matching: find.text('1'),
              );
              final periodRect = inGrid(
                tester.renderObject<RenderBox>(
                  probe.backgroundFor(firstPeriod),
                ),
              );
              final rowHeight = periodRect.height;
              final dayWidth = (gridBox.size.width - periodRect.width) / 7;
              expect(rowHeight, greaterThanOrEqualTo(56));
              expect(
                rect.left,
                closeTo(
                  periodRect.width + (course.weekday - 1) * dayWidth + 2,
                  .1,
                ),
              );
              expect(
                rect.top,
                closeTo(
                  periodRect.top + (course.startSection - 1) * rowHeight + 2,
                  .1,
                ),
              );
              expect(rect.width, closeTo(dayWidth - 4, .1));
              expect(
                rect.height,
                closeTo(rowHeight * course.sectionCount - 4, .1),
              );
              probe.rows.add({
                'rowHeight': rowHeight,
                'dayWidth': dayWidth,
                'role': '$stage ${course.id} geometry',
                'left': rect.left,
                'top': rect.top,
                'width': rect.width,
                'height': rect.height,
                'weekday': course.weekday,
                'startSection': course.startSection,
                'sectionCount': course.sectionCount,
              });
              await probe.reveal(title);
              await probe.capture(
                '$stage-${course.id == _courses.first.id ? 'short' : course.id}',
              );
              await tester.tap(title);
              await tester.pumpAndSettle();
              final sheet = find.byType(AppModalSheet);
              expect(sheet, findsOneWidget);
              final fields = find.descendant(
                of: sheet,
                matching: find.byType(TextField),
              );
              expect(
                tester
                    .widgetList<TextField>(fields)
                    .map((field) => field.controller!.text),
                [course.name, course.teacher, course.location],
              );
              probe.rows.add({
                'role': '$stage ${course.id} tap',
                'courseId': course.id,
              });
              final cancel = find.descendant(
                of: sheet,
                matching: find.text(I18n.tr('action.cancel')),
              );
              await Scrollable.ensureVisible(tester.element(cancel));
              await tester.pumpAndSettle();
              await tester.tap(cancel);
              await tester.pumpAndSettle();
              expect(find.byType(AppModalSheet), findsNothing);
              final error = tester.takeException();
              if (error != null) {
                probe.errors.add('$stage ${course.id} framework: $error');
              }
            }
          }

          await measure('initial');
          final scrolls = find
              .ancestor(of: grid, matching: find.byType(Scrollable))
              .evaluate()
              .map(
                (element) =>
                    (element as StatefulElement).state as ScrollableState,
              )
              .toList();
          expect(scrolls, hasLength(2));
          for (final scroll in scrolls) {
            scroll.position.jumpTo(
              math.min(20, scroll.position.maxScrollExtent),
            );
          }
          await tester.pumpAndSettle();
          final offsets = scrolls
              .map((scroll) => scroll.position.pixels)
              .toList();
          final oldWeek = courses.viewingWeek;
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          expect(tester.element(screen), same(screenElement));
          expect(courses.viewingWeek, oldWeek);
          final liveScrolls = find
              .ancestor(of: grid, matching: find.byType(Scrollable))
              .evaluate()
              .map(
                (element) =>
                    (element as StatefulElement).state as ScrollableState,
              )
              .toList();
          expect(liveScrolls.length, scrolls.length);
          for (var i = 0; i < scrolls.length; i++) {
            expect(liveScrolls[i], same(scrolls[i]));
            expect(
              liveScrolls[i].position.pixels,
              closeTo(
                offsets[i].clamp(
                  liveScrolls[i].position.minScrollExtent,
                  liveScrolls[i].position.maxScrollExtent,
                ),
                .1,
              ),
            );
          }
          await measure('live');
          expect(
            _courses.map((course) => course.toJson()).toList(),
            beforeCourses,
          );
          expect(_settings.toJson(), beforeSettings);
          expect({
            for (final key in prefs.getKeys()) key: prefs.get(key),
          }, beforePrefs);
          await probe.finish();
        });
      }
    }
  }
}
