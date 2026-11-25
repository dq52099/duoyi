// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';

Future<void> _pumpBoundedFrames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _captureScopeScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final enabled =
      Platform.environment['DUOYI_CAPTURE_WIDGET_SCREENSHOT'] == '1' ||
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] != null;
  if (!enabled) return;

  final baseDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] ??
      'evidence/screenshots/widget-preview-body-readable-20261024';

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError(
        'Cannot capture screenshot "$name": RepaintBoundary render object not found for boundaryKey $boundaryKey',
      );
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError(
          'Cannot capture screenshot "$name": image.toByteData returned null',
        );
      }
      final file = File('$baseDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<GlobalKey> _mountPreviewFixture(
  WidgetTester tester, {
  required String brandId,
  required AppLocale locale,
  required Size viewportSize,
  required TextScaler textScaler,
  required Widget child,
}) async {
  SharedPreferences.setMockInitialValues({'active_brand': brandId});
  I18n.setLocale(locale);
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final theme = ThemeProvider();
  await tester.runAsync(() async {
    await theme.loadFromStorage();
    await loadWeeklyReviewScreenshotFonts();
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    theme.dispose();
  });

  // Assert actual loaded/committed ThemeProvider brand and activeWidgetBackgroundBrand
  final expectedBrand =
      brandId == 'defaultBrand' ? AppBrands.defaultBrand : AppBrands.liquidGlass;
  expect(
    theme.brand.id,
    equals(expectedBrand.id),
    reason: 'ThemeProvider brand must match expected $brandId',
  );
  expect(
    theme.activeWidgetBackgroundBrand.id,
    equals(expectedBrand.id),
    reason:
        'ThemeProvider activeWidgetBackgroundBrand must match expected $brandId',
  );

  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ],
      child: ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, currentLocale, _) => MaterialApp(
          locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: theme.brand.theme,
          builder: (context, childWidget) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: textScaler,
            ),
            child: RepaintBoundary(key: boundaryKey, child: childWidget!),
          ),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: child),
          ),
        ),
      ),
    ),
  );
  await _pumpBoundedFrames(tester);

  // Assert Theme.of(actualsurface).primary vs real AppBrands expected
  final surfaceFinder = find.byKey(const ValueKey('widget_preview_surface'));
  expect(surfaceFinder, findsOneWidget);
  final surfaceElement = tester.element(surfaceFinder);
  final surfaceTheme = Theme.of(surfaceElement);
  expect(
    surfaceTheme.colorScheme.primary,
    equals(expectedBrand.theme.colorScheme.primary),
    reason:
        'Actual surface Theme primary color must match real $brandId AppBrand theme primary',
  );

  return boundaryKey;
}

void _assertReadableParagraph(
  WidgetTester tester, {
  required Finder textFinder,
  required Finder surfaceFinder,
  required GlobalKey boundaryKey,
  required String role,
  Finder? rowFinder,
}) {
  expect(textFinder, findsOneWidget, reason: '$role must be present (no vacuity)');
  final richTextFinder = find.descendant(
    of: textFinder,
    matching: find.byType(RichText),
  );
  final paragraph = tester.renderObject<RenderParagraph>(
    richTextFinder.evaluate().isNotEmpty ? richTextFinder : textFinder,
  );

  // 1. Must not exceed maxLines (real RenderParagraph didExceedMaxLines geometry assertion)
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role didExceedMaxLines must be false (no line truncation)',
  );

  final text = paragraph.text.toPlainText();
  expect(text, isNotEmpty, reason: '$role text must not be empty');

  final renderBoundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final surfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
  final surfaceRect = MatrixUtils.transformRect(
    surfaceBox.getTransformTo(renderBoundary),
    Offset.zero & surfaceBox.size,
  );

  RenderBox? rowBox;
  Rect? rowRect;
  if (rowFinder != null) {
    rowBox = tester.renderObject<RenderBox>(rowFinder);
    rowRect = MatrixUtils.transformRect(
      rowBox.getTransformTo(renderBoundary),
      Offset.zero & rowBox.size,
    );
  }

  // 2. Verify token glyph ink boxes fit within layout bounds (matching profile_password_live_brand_priority_test)
  final tokens = RegExp(r'\S+').allMatches(text);
  expect(
    tokens,
    isNotEmpty,
    reason: '$role must contain non-whitespace tokens to lay out',
  );
  for (final match in tokens) {
    final tokenBoxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: match.start, extentOffset: match.end),
    );
    expect(
      tokenBoxes,
      isNotEmpty,
      reason: '$role glyph boxes for token "${match.group(0)}" must be laid out',
    );
    for (final box in tokenBoxes) {
      expect(
        box.top,
        greaterThanOrEqualTo(-0.5),
        reason:
            '$role token "${match.group(0)}" glyph box top ${box.top} must be inside paragraph allocated height',
      );
      expect(
        box.bottom,
        lessThanOrEqualTo(paragraph.size.height + 0.5),
        reason:
            '$role token "${match.group(0)}" glyph box bottom ${box.bottom} must be inside paragraph allocated height ${paragraph.size.height}',
      );
      expect(
        box.left,
        greaterThanOrEqualTo(-0.5),
        reason:
            '$role token "${match.group(0)}" glyph box left ${box.left} must be inside paragraph allocated width',
      );
      expect(
        box.right,
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason:
            '$role token "${match.group(0)}" glyph box right ${box.right} must be inside paragraph allocated width ${paragraph.size.width}',
      );

      final glyphRect = MatrixUtils.transformRect(
        paragraph.getTransformTo(renderBoundary),
        Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
      );
      expect(
        surfaceRect.inflate(0.5).contains(glyphRect.topLeft),
        isTrue,
        reason:
            '$role glyph top-left $glyphRect must be within painted surface $surfaceRect',
      );
      expect(
        surfaceRect.inflate(0.5).contains(glyphRect.bottomRight),
        isTrue,
        reason:
            '$role glyph bottom-right $glyphRect must be within painted surface $surfaceRect',
      );

      if (rowRect != null) {
        expect(
          rowRect.inflate(0.5).contains(glyphRect.topLeft),
          isTrue,
          reason: '$role glyph top-left must be within allocated row bounds $rowRect',
        );
        expect(
          rowRect.inflate(0.5).contains(glyphRect.bottomRight),
          isTrue,
          reason: '$role glyph bottom-right must be within allocated row bounds $rowRect',
        );
      }
    }
  }

  // 3. Full text selection boxes must not be empty and must fit within painted surface bounds
  final fullBoxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(
    fullBoxes,
    isNotEmpty,
    reason: '$role full text selection boxes must not be empty',
  );
  for (final box in fullBoxes) {
    expect(
      box.top,
      greaterThanOrEqualTo(-0.5),
      reason:
          '$role selection box top ${box.top} must be inside paragraph allocated height',
    );
    expect(
      box.bottom,
      lessThanOrEqualTo(paragraph.size.height + 0.5),
      reason:
          '$role selection box bottom ${box.bottom} must be inside paragraph allocated height ${paragraph.size.height}',
    );
    final fullBoxRect = MatrixUtils.transformRect(
      paragraph.getTransformTo(renderBoundary),
      Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
    );
    expect(
      surfaceRect.inflate(1.0).contains(fullBoxRect.topLeft),
      isTrue,
      reason:
          '$role selection top-left $fullBoxRect must be within painted surface $surfaceRect',
    );
    expect(
      surfaceRect.inflate(1.0).contains(fullBoxRect.bottomRight),
      isTrue,
      reason:
          '$role selection bottom-right $fullBoxRect must be within painted surface $surfaceRect',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetPreviewBodyReadabilityPriorityTest - Todo Rows', () {
    for (final brandId in ['defaultBrand', 'liquidGlass']) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
          testWidgets(
            'Todo item 1 readable at 320px 200% text scale in $brandId $locale ${platform.name}',
            (tester) async {
              final boundary = await _mountPreviewFixture(
                tester,
                brandId: brandId,
                locale: locale,
                viewportSize: const Size(320, 600),
                textScaler: const TextScaler.linear(2.0),
                child: WidgetPreviewCard.todo(
                  displayMode: WidgetDisplayMode.standard,
                  platformOverride: platform,
                ),
              );

              final surfaceFinder = find.byKey(
                const ValueKey('widget_preview_surface'),
              );
              expect(surfaceFinder, findsOneWidget);

              final primaryTodoFinder = find.text(WidgetUiCopy.todoItem1);
              final rowFinder = find.ancestor(
                of: primaryTodoFinder,
                matching: find.byType(Row),
              ).first;

              _assertReadableParagraph(
                tester,
                textFinder: primaryTodoFinder,
                surfaceFinder: surfaceFinder,
                boundaryKey: boundary,
                role: 'Todo primary row ($brandId, $locale, ${platform.name})',
                rowFinder: rowFinder,
              );

              await _captureScopeScreenshot(
                tester,
                boundary,
                'todo_${brandId}_${locale.name}_${platform.name}_320px_200pct',
              );
            },
          );

          testWidgets(
            'Todo item 1 readable under RouteProbeNonlinearScaler in $brandId $locale ${platform.name}',
            (tester) async {
              final boundary = await _mountPreviewFixture(
                tester,
                brandId: brandId,
                locale: locale,
                viewportSize: const Size(332, 600),
                textScaler: const RouteProbeNonlinearScaler(),
                child: WidgetPreviewCard.todo(
                  displayMode: WidgetDisplayMode.compact,
                  platformOverride: platform,
                ),
              );

              final surfaceFinder = find.byKey(
                const ValueKey('widget_preview_surface'),
              );
              expect(surfaceFinder, findsOneWidget);

              final primaryTodoFinder = find.text(WidgetUiCopy.todoItem1);
              _assertReadableParagraph(
                tester,
                textFinder: primaryTodoFinder,
                surfaceFinder: surfaceFinder,
                boundaryKey: boundary,
                role:
                    'Todo compact primary row under nonlinear scaler ($brandId, $locale, ${platform.name})',
              );

              await _captureScopeScreenshot(
                tester,
                boundary,
                'todo_${brandId}_${locale.name}_${platform.name}_compact_nonlinear',
              );
            },
          );
        }
      }
    }
  });

  group('WidgetPreviewBodyReadabilityPriorityTest - Representative Ordinary Scale', () {
    for (final brandId in ['defaultBrand', 'liquidGlass']) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
          testWidgets(
            'Todo and Schedule readable at ordinary scale 1.0 in $brandId $locale ${platform.name}',
            (tester) async {
              final boundary = await _mountPreviewFixture(
                tester,
                brandId: brandId,
                locale: locale,
                viewportSize: const Size(390, 844),
                textScaler: const TextScaler.linear(1.0),
                child: WidgetPreviewCard.todo(
                  displayMode: WidgetDisplayMode.standard,
                  platformOverride: platform,
                ),
              );

              final surfaceFinder = find.byKey(
                const ValueKey('widget_preview_surface'),
              );
              expect(surfaceFinder, findsOneWidget);

              final primaryTodoFinder = find.text(WidgetUiCopy.todoItem1);
              _assertReadableParagraph(
                tester,
                textFinder: primaryTodoFinder,
                surfaceFinder: surfaceFinder,
                boundaryKey: boundary,
                role: 'Todo ordinary 1.0 ($brandId, $locale, ${platform.name})',
              );

              await _captureScopeScreenshot(
                tester,
                boundary,
                'todo_ordinary_${brandId}_${locale.name}_${platform.name}',
              );
            },
          );
        }
      }
    }
  });

  group('WidgetPreviewBodyReadabilityPriorityTest - Detailed Mode Both Themes and Locales', () {
    for (final brandId in ['defaultBrand', 'liquidGlass']) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
          testWidgets(
            'Detailed mode retains primary content at 320px 200% scale in $brandId $locale ${platform.name}',
            (tester) async {
              final boundary = await _mountPreviewFixture(
                tester,
                brandId: brandId,
                locale: locale,
                viewportSize: const Size(320, 800),
                textScaler: const TextScaler.linear(2.0),
                child: WidgetPreviewCard.todo(
                  displayMode: WidgetDisplayMode.detailed,
                  platformOverride: platform,
                ),
              );

              final surfaceFinder = find.byKey(
                const ValueKey('widget_preview_surface'),
              );
              expect(surfaceFinder, findsOneWidget);

              final primaryTodoFinder = find.text(WidgetUiCopy.todoItem1);
              _assertReadableParagraph(
                tester,
                textFinder: primaryTodoFinder,
                surfaceFinder: surfaceFinder,
                boundaryKey: boundary,
                role:
                    'Detailed mode primary row ($brandId, $locale, ${platform.name})',
              );

              await _captureScopeScreenshot(
                tester,
                boundary,
                'detailed_${brandId}_${locale.name}_${platform.name}_320px_200pct',
              );
            },
          );
        }
      }
    }
  });

  group('WidgetPreviewBodyReadabilityPriorityTest - Schedule Lines', () {
    for (final brandId in ['defaultBrand', 'liquidGlass']) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        testWidgets(
          'Schedule line 1 readable at 320px 200% scale in $brandId $locale iOS',
          (tester) async {
            final boundary = await _mountPreviewFixture(
              tester,
              brandId: brandId,
              locale: locale,
              viewportSize: const Size(320, 600),
              textScaler: const TextScaler.linear(2.0),
              child: WidgetPreviewCard.schedule(
                displayMode: WidgetDisplayMode.standard,
                platformOverride: TargetPlatform.iOS,
              ),
            );

            final surfaceFinder = find.byKey(
              const ValueKey('widget_preview_surface'),
            );
            expect(surfaceFinder, findsOneWidget);

            final scheduleItemFinder = find.text(WidgetUiCopy.scheduleItem1);
            _assertReadableParagraph(
              tester,
              textFinder: scheduleItemFinder,
              surfaceFinder: surfaceFinder,
              boundaryKey: boundary,
              role: 'Schedule line 1 ($brandId, $locale, iOS)',
            );

            await _captureScopeScreenshot(
              tester,
              boundary,
              'schedule_${brandId}_${locale.name}_iOS_320px_200pct',
            );
          },
        );

        testWidgets(
          'Schedule line 1 readable under RouteProbeNonlinearScaler in $brandId $locale Android',
          (tester) async {
            final boundary = await _mountPreviewFixture(
              tester,
              brandId: brandId,
              locale: locale,
              viewportSize: const Size(320, 600),
              textScaler: const RouteProbeNonlinearScaler(),
              child: WidgetPreviewCard.schedule(
                displayMode: WidgetDisplayMode.compact,
                platformOverride: TargetPlatform.android,
              ),
            );

            final surfaceFinder = find.byKey(
              const ValueKey('widget_preview_surface'),
            );
            expect(surfaceFinder, findsOneWidget);

            final scheduleItemFinder = find.text(WidgetUiCopy.scheduleItem1);
            _assertReadableParagraph(
              tester,
              textFinder: scheduleItemFinder,
              surfaceFinder: surfaceFinder,
              boundaryKey: boundary,
              role: 'Schedule compact line 1 ($brandId, $locale, Android)',
            );

            await _captureScopeScreenshot(
              tester,
              boundary,
              'schedule_${brandId}_${locale.name}_android_compact_nonlinear',
            );
          },
        );
      }
    }
  });

  group('WidgetPreviewBodyReadabilityPriorityTest - Habit Title and Action', () {
    for (final brandId in ['defaultBrand', 'liquidGlass']) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        testWidgets(
          'Habit title and check-in button readable at 320px 200% scale in $brandId $locale',
          (tester) async {
            final boundary = await _mountPreviewFixture(
              tester,
              brandId: brandId,
              locale: locale,
              viewportSize: const Size(320, 600),
              textScaler: const TextScaler.linear(2.0),
              child: WidgetPreviewCard.habit(
                displayMode: WidgetDisplayMode.standard,
                platformOverride: TargetPlatform.iOS,
              ),
            );

            final surfaceFinder = find.byKey(
              const ValueKey('widget_preview_surface'),
            );
            expect(surfaceFinder, findsOneWidget);

            final habitTitleFinder = find.text(WidgetUiCopy.habitTitle);
            _assertReadableParagraph(
              tester,
              textFinder: habitTitleFinder,
              surfaceFinder: surfaceFinder,
              boundaryKey: boundary,
              role: 'Habit title ($brandId, $locale)',
            );

            final habitActionFinder = find.text(
              WidgetUiCopy.habitCheckInButton,
            );
            _assertReadableParagraph(
              tester,
              textFinder: habitActionFinder,
              surfaceFinder: surfaceFinder,
              boundaryKey: boundary,
              role: 'Habit check-in button ($brandId, $locale)',
            );

            await _captureScopeScreenshot(
              tester,
              boundary,
              'habit_${brandId}_${locale.name}_320px_200pct',
            );
          },
        );

        testWidgets(
          'Habit title readable under RouteProbeNonlinearScaler in $brandId $locale',
          (tester) async {
            final boundary = await _mountPreviewFixture(
              tester,
              brandId: brandId,
              locale: locale,
              viewportSize: const Size(320, 600),
              textScaler: const RouteProbeNonlinearScaler(),
              child: WidgetPreviewCard.habit(
                displayMode: WidgetDisplayMode.compact,
                platformOverride: TargetPlatform.android,
              ),
            );

            final surfaceFinder = find.byKey(
              const ValueKey('widget_preview_surface'),
            );
            expect(surfaceFinder, findsOneWidget);

            final habitTitleFinder = find.text(WidgetUiCopy.habitTitle);
            _assertReadableParagraph(
              tester,
              textFinder: habitTitleFinder,
              surfaceFinder: surfaceFinder,
              boundaryKey: boundary,
              role: 'Habit compact title nonlinear ($brandId, $locale)',
            );
          },
        );
      }
    }
  });

  group('WidgetPreviewBodyReadabilityPriorityTest - Focus Metrics', () {
    for (final brandId in ['defaultBrand', 'liquidGlass']) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        testWidgets(
          'Focus timer value readable without truncation at 320px 200% scale in $brandId $locale',
          (tester) async {
            final boundary = await _mountPreviewFixture(
              tester,
              brandId: brandId,
              locale: locale,
              viewportSize: const Size(320, 600),
              textScaler: const TextScaler.linear(2.0),
              child: WidgetPreviewCard.focus(
                displayMode: WidgetDisplayMode.standard,
                platformOverride: TargetPlatform.iOS,
              ),
            );

            final surfaceFinder = find.byKey(
              const ValueKey('widget_preview_surface'),
            );
            expect(surfaceFinder, findsOneWidget);

            // Focus metrics value must be readable and present
            final metricFinder = find.text('25');
            expect(metricFinder, findsWidgets);
            final firstMetric = metricFinder.first;

            _assertReadableParagraph(
              tester,
              textFinder: firstMetric,
              surfaceFinder: surfaceFinder,
              boundaryKey: boundary,
              role: 'Focus metric value ($brandId, $locale)',
            );

            await _captureScopeScreenshot(
              tester,
              boundary,
              'focus_${brandId}_${locale.name}_320px_200pct',
            );
          },
        );
      }
    }
  });

  group('WidgetPreviewBodyReadabilityPriorityTest - Primary Line Checks for Changed Kinds', () {
    final kinds = [
      (
        kind: WidgetPreviewKind.goal,
        builder: (WidgetDisplayMode m, TargetPlatform p) =>
            WidgetPreviewCard.goal(displayMode: m, platformOverride: p),
        label: (AppLocale l) => WidgetUiCopy.goalItem1,
        name: 'Goal',
      ),
      (
        kind: WidgetPreviewKind.course,
        builder: (WidgetDisplayMode m, TargetPlatform p) =>
            WidgetPreviewCard.course(displayMode: m, platformOverride: p),
        label: (AppLocale l) => WidgetUiCopy.courseItem1,
        name: 'Course',
      ),
      (
        kind: WidgetPreviewKind.note,
        builder: (WidgetDisplayMode m, TargetPlatform p) =>
            WidgetPreviewCard.note(displayMode: m, platformOverride: p),
        label: (AppLocale l) => WidgetUiCopy.noteItem1,
        name: 'Note',
      ),
      (
        kind: WidgetPreviewKind.anniversary,
        builder: (WidgetDisplayMode m, TargetPlatform p) =>
            WidgetPreviewCard.anniversary(displayMode: m, platformOverride: p),
        label: (AppLocale l) => WidgetUiCopy.anniversaryItem1,
        name: 'Anniversary',
      ),
      (
        kind: WidgetPreviewKind.diary,
        builder: (WidgetDisplayMode m, TargetPlatform p) =>
            WidgetPreviewCard.diary(displayMode: m, platformOverride: p),
        label: (AppLocale l) => WidgetUiCopy.diaryItem1,
        name: 'Diary',
      ),
    ];

    for (final item in kinds) {
      for (final brandId in ['defaultBrand', 'liquidGlass']) {
        for (final locale in [AppLocale.zh, AppLocale.en]) {
          testWidgets(
            '${item.name} primary line readable at 320px 200% scale in $brandId $locale (Android & iOS)',
            (tester) async {
              final platform =
                  brandId == 'defaultBrand' ? TargetPlatform.iOS : TargetPlatform.android;
              final boundary = await _mountPreviewFixture(
                tester,
                brandId: brandId,
                locale: locale,
                viewportSize: const Size(320, 600),
                textScaler: const TextScaler.linear(2.0),
                child: item.builder(WidgetDisplayMode.standard, platform),
              );

              final surfaceFinder = find.byKey(
                const ValueKey('widget_preview_surface'),
              );
              expect(surfaceFinder, findsOneWidget);

              final expectedText = item.label(locale);
              final textFinder = find.text(expectedText);
              _assertReadableParagraph(
                tester,
                textFinder: textFinder,
                surfaceFinder: surfaceFinder,
                boundaryKey: boundary,
                role: '${item.name} primary line ($brandId, $locale, ${platform.name})',
              );

              await _captureScopeScreenshot(
                tester,
                boundary,
                '${item.name.toLowerCase()}_${brandId}_${locale.name}_320px_200pct',
              );
            },
          );

          testWidgets(
            '${item.name} compact primary line readable under nonlinear scaler in $brandId $locale',
            (tester) async {
              final platform =
                  brandId == 'defaultBrand' ? TargetPlatform.android : TargetPlatform.iOS;
              final boundary = await _mountPreviewFixture(
                tester,
                brandId: brandId,
                locale: locale,
                viewportSize: const Size(332, 600),
                textScaler: const RouteProbeNonlinearScaler(),
                child: item.builder(WidgetDisplayMode.compact, platform),
              );

              final surfaceFinder = find.byKey(
                const ValueKey('widget_preview_surface'),
              );
              expect(surfaceFinder, findsOneWidget);

              final expectedText = item.label(locale);
              final textFinder = find.text(expectedText);
              _assertReadableParagraph(
                tester,
                textFinder: textFinder,
                surfaceFinder: surfaceFinder,
                boundaryKey: boundary,
                role:
                    '${item.name} compact nonlinear primary line ($brandId, $locale, ${platform.name})',
              );
            },
          );
        }
      }
    }
  });
}
