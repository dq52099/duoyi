// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart' show appSurfaceStyleOf;

import '../support/weekly_review_screenshot_font.dart';

/// Non-linear text scaler for narrow-screen readability validation.
class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize <= 14 ? fontSize * 1.9 : 26.6 + (fontSize - 14) * 1.4;

  @override
  double get textScaleFactor => 1.9;
}

/// In-memory SharedPreferences store recording write counts.
class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int diaryWrites = 0;

  static bool _isDiaryKey(String key) =>
      key == 'duoyi_diary' ||
      key == 'flutter.duoyi_diary' ||
      key.endsWith('.duoyi_diary');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isDiaryKey(key)) {
      diaryWrites++;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isDiaryKey(key)) {
      diaryWrites++;
    }
    return super.remove(key);
  }
}

/// DiaryProvider tracking calls to addOrUpdate.
class _RecordingDiaryProvider extends DiaryProvider {
  int saves = 0;

  @override
  Future<void> addOrUpdate(DiaryEntry entry) async {
    saves++;
    await super.addOrUpdate(entry);
  }
}

Future<int> _boundedPumpAndSettle(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 50),
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  Duration timeout = const Duration(seconds: 5),
}) {
  return tester.pumpAndSettle(duration, phase, timeout);
}

Future<void> _drainAccountWrites(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(() => AccountPreferenceWrites.drain().timeout(timeout));
}

Future<void> _scrollTo(
  WidgetTester tester,
  Finder target, {
  Finder? scrollable,
  double delta = 200,
  int maxSteps = 25,
}) async {
  final scroll =
      scrollable ??
      find
          .descendant(
            of: find.byType(DiaryEditScreen),
            matching: find.byType(Scrollable),
          )
          .first;

  if (target.evaluate().isNotEmpty) {
    await Scrollable.ensureVisible(
      tester.element(target.first),
      alignment: 0.5,
    );
    await _boundedPumpAndSettle(tester);
    return;
  }

  for (var i = 0; i < maxSteps; i++) {
    if (target.evaluate().isNotEmpty) break;
    final posBefore = tester.state<ScrollableState>(scroll).position.pixels;
    await tester.drag(scroll, Offset(0, -delta.abs()));
    await _boundedPumpAndSettle(tester);
    final posAfter = tester.state<ScrollableState>(scroll).position.pixels;
    if ((posAfter - posBefore).abs() < 0.5) break;
  }

  if (target.evaluate().isEmpty) {
    for (var i = 0; i < maxSteps * 2; i++) {
      if (target.evaluate().isNotEmpty) break;
      final posBefore = tester.state<ScrollableState>(scroll).position.pixels;
      await tester.drag(scroll, Offset(0, delta.abs()));
      await _boundedPumpAndSettle(tester);
      final posAfter = tester.state<ScrollableState>(scroll).position.pixels;
      if ((posAfter - posBefore).abs() < 0.5) break;
    }
  }

  expect(
    target,
    findsWidgets,
    reason: 'Target widget should be visible after scrolling through lazy ListView',
  );
  await Scrollable.ensureVisible(tester.element(target.first), alignment: 0.5);
  await _boundedPumpAndSettle(tester);
}

Future<void> _captureScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final file = File('$explicitDir/diary-tag-hint-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _saveMeasurements(
  WidgetTester tester,
  String name,
  Map<String, dynamic> data,
) async {
  final measurementsDir =
      Platform.environment['DUOYI_PRIORITY_THEME_MEASUREMENTS_DIR'];
  if (measurementsDir == null || measurementsDir.isEmpty) return;

  await tester.runAsync(() async {
    final file = File('$measurementsDir/diary-tag-hint-$name.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  });
}

List<LineMetrics> _computeTextLines(RenderParagraph paragraph) {
  final painter = TextPainter(
    text: paragraph.text,
    textAlign: paragraph.textAlign,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
    maxLines: paragraph.maxLines,
    strutStyle: paragraph.strutStyle,
    textWidthBasis: paragraph.textWidthBasis,
    textHeightBehavior: paragraph.textHeightBehavior,
  )..layout(
      maxWidth: paragraph.constraints.maxWidth.isFinite
          ? paragraph.constraints.maxWidth
          : paragraph.size.width,
    );
  try {
    return painter.computeLineMetrics();
  } finally {
    painter.dispose();
  }
}

Future<Map<String, dynamic>> _assertAndMeasureTagHintLayout(
  WidgetTester tester, {
  required GlobalKey boundaryKey,
  required String expectedHint,
  required String role,
  Finder? scrollableFinder,
}) async {
  final hintFinder = find.text(expectedHint);
  expect(
    hintFinder,
    findsWidgets,
    reason: '$role: tag hint "$expectedHint" must exist in widget tree',
  );

  final externalCandidates = find.byWidgetPredicate((w) {
    if (w is! Text || w.data != expectedHint) return false;
    return find
        .ancestor(of: find.byWidget(w), matching: find.byType(TextField))
        .evaluate()
        .isEmpty;
  });
  final targetHint = externalCandidates.evaluate().isNotEmpty
      ? externalCandidates.first
      : hintFinder.first;
  if (scrollableFinder != null) {
    await _scrollTo(tester, targetHint, scrollable: scrollableFinder);
  }

  final richFinder = find.descendant(
    of: targetHint,
    matching: find.byType(RichText),
  );
  final target =
      richFinder.evaluate().isNotEmpty ? richFinder.first : targetHint;
  final paragraph = tester.renderObject<RenderParagraph>(target);

  // 1. Readability assertions: no line truncation, full content, no ellipsis glyph
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role: tag hint didExceedMaxLines must be false (no line truncation)',
  );
  expect(
    paragraph.text.toPlainText(),
    contains(expectedHint),
    reason: '$role: tag hint text must match full localized string',
  );
  expect(
    paragraph.text.toPlainText(),
    isNot(contains('\u2026')),
    reason: '$role: tag hint must not be ellipsized',
  );

  // 2. Line metrics via TextPainter: natural line wrapping verification
  final lineMetrics = _computeTextLines(paragraph);
  expect(
    lineMetrics,
    isNotEmpty,
    reason: '$role: tag hint must produce at least one line',
  );
  for (final lm in lineMetrics) {
    expect(lm.width, greaterThan(0));
    expect(lm.height, greaterThan(0));
    expect(
      lm.width,
      lessThanOrEqualTo(paragraph.size.width + 1.0),
      reason: '$role: line width (${lm.width}) must not exceed paragraph allocated width (${paragraph.size.width})',
    );
  }

  // 3. RenderEditable assertion if hint is embedded in TextField (flexible hierarchy)
  final ancestorTextFields = find.ancestor(
    of: targetHint,
    matching: find.byType(TextField),
  );
  if (ancestorTextFields.evaluate().isNotEmpty) {
    final editableFinder = find.descendant(
      of: ancestorTextFields.first,
      matching: find.byType(EditableText),
    );
    if (editableFinder.evaluate().isNotEmpty) {
      final renderEditable =
          tester.state<EditableTextState>(editableFinder.first).renderEditable;
      expect(
        renderEditable.maxLines,
        anyOf(isNull, greaterThanOrEqualTo(1)),
        reason: '$role: RenderEditable maxLines must not truncate',
      );
    }
  }

  // 4. Character glyph bounding boxes and viewport verification (horizontal + vertical reachability)
  final renderBoundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final screenRect = Rect.fromLTWH(
    0,
    0,
    tester.view.physicalSize.width / tester.view.devicePixelRatio,
    tester.view.physicalSize.height / tester.view.devicePixelRatio,
  );

  final Rect visibleClipRect;
  if (scrollableFinder != null) {
    final scrollBox = tester.renderObject<RenderBox>(scrollableFinder);
    final viewportRect = MatrixUtils.transformRect(
      scrollBox.getTransformTo(renderBoundary),
      Offset.zero & scrollBox.size,
    );
    visibleClipRect = screenRect.intersect(viewportRect);
  } else {
    visibleClipRect = screenRect;
  }

  final text = paragraph.text.toPlainText();
  final glyphBoxes = <Map<String, dynamic>>[];
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char.trim().isEmpty) continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    expect(
      boxes,
      isNotEmpty,
      reason: '$role: character "$char" at index $i must have a laid out box',
    );
    for (final box in boxes) {
      expect(
        box.left,
        greaterThanOrEqualTo(-0.5),
        reason: '$role: character "$char" box left must be >= -0.5',
      );
      expect(
        box.right,
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason: '$role: character "$char" box right must be <= paragraph width',
      );

      // Verify and maintain vertical glyph reachability in the scrollable viewport
      final glyphCenterY = paragraph.localToGlobal(
        Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2),
      ).dy;
      if (scrollableFinder != null &&
          (glyphCenterY < visibleClipRect.top ||
              glyphCenterY > visibleClipRect.bottom)) {
        final scroll = Scrollable.maybeOf(tester.element(target));
        if (scroll != null) {
          final delta = glyphCenterY - visibleClipRect.center.dy;
          final targetPixels = (scroll.position.pixels + delta).clamp(
            scroll.position.minScrollExtent,
            scroll.position.maxScrollExtent,
          );
          if ((targetPixels - scroll.position.pixels).abs() > 0.5) {
            scroll.position.jumpTo(targetPixels);
            await tester.pump(const Duration(milliseconds: 20));
          }
        }
      }

      final glyphRect = MatrixUtils.transformRect(
        paragraph.getTransformTo(renderBoundary),
        Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
      );
      expect(
        glyphRect.left,
        greaterThanOrEqualTo(-0.5),
        reason: '$role: character "$char" glyph left must be within screen bounds',
      );
      expect(
        glyphRect.right,
        lessThanOrEqualTo(screenRect.width + 0.5),
        reason: '$role: character "$char" glyph right must be within screen width',
      );
      expect(
        glyphRect.top,
        greaterThanOrEqualTo(visibleClipRect.top - 1.0),
        reason: '$role: character "$char" glyph top must be reachable within viewport top',
      );
      expect(
        glyphRect.bottom,
        lessThanOrEqualTo(visibleClipRect.bottom + 1.0),
        reason: '$role: character "$char" glyph bottom must be reachable within viewport bottom',
      );

      glyphBoxes.add({
        'char': char,
        'index': i,
        'box': {
          'left': box.left,
          'top': box.top,
          'right': box.right,
          'bottom': box.bottom,
        },
      });
    }
  }

  return {
    'hintText': expectedHint,
    'paragraphSize': {
      'width': paragraph.size.width,
      'height': paragraph.size.height,
    },
    'didExceedMaxLines': paragraph.didExceedMaxLines,
    'lineCount': lineMetrics.length,
    'lines': [
      for (final lm in lineMetrics)
        {
          'width': lm.width,
          'height': lm.height,
          'baseline': lm.baseline,
          'lineNumber': lm.lineNumber,
        }
    ],
    'glyphCount': glyphBoxes.length,
  };
}

void _assertTagSemantics(
  WidgetTester tester, {
  required Finder tagFieldFinder,
  required String expectedHint,
  required String role,
  bool requireHintOccurrence = true,
}) {
  final editableFinder = find.descendant(
    of: tagFieldFinder,
    matching: find.byType(EditableText),
  );
  expect(
    editableFinder,
    findsOneWidget,
    reason: '$role: Tag field EditableText must exist for semantics inspection',
  );
  final semantics = tester.getSemantics(editableFinder);
  expect(
    semantics.flagsCollection.isTextField,
    isTrue,
    reason: '$role: Tag field EditableText must have isTextField semantics flag',
  );

  final traversalNodes = tester.semantics.simulatedAccessibilityTraversal();
  int hintOccurrences = 0;
  for (final node in traversalNodes) {
    final d = node.getSemanticsData();
    if (d.label == expectedHint ||
        d.hint == expectedHint ||
        d.tooltip == expectedHint ||
        d.value == expectedHint) {
      hintOccurrences++;
    }
  }

  if (requireHintOccurrence) {
    expect(
      hintOccurrences,
      equals(1),
      reason:
          '$role: Localized hint/label "$expectedHint" must appear in accessibility semantics exactly once without redundant duplicate static nodes',
    );
  } else {
    expect(
      hintOccurrences,
      lessThanOrEqualTo(1),
      reason:
          '$role: Localized hint/label "$expectedHint" must not have redundant duplicate static nodes',
    );
  }
}

enum _Outcome { discard, save }

class _DiaryTagHintScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final String targetBrand;
  final Size size;
  final TextScaler textScaler;
  final _Outcome outcome;

  const _DiaryTagHintScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.size,
    required this.textScaler,
    required this.outcome,
  });
}

const _scenarios = <_DiaryTagHintScenario>[
  _DiaryTagHintScenario(
    name: 'zh-320px-200pct-defaultBrand-save',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    textScaler: TextScaler.linear(2.0),
    outcome: _Outcome.save,
  ),
  _DiaryTagHintScenario(
    name: 'en-320px-200pct-liquidGlass-discard',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(320, 844),
    textScaler: TextScaler.linear(2.0),
    outcome: _Outcome.discard,
  ),
  _DiaryTagHintScenario(
    name: 'zh-332px-nonlinear-liquidGlass-save',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(332, 800),
    textScaler: _NonlinearTextScaler(),
    outcome: _Outcome.save,
  ),
  _DiaryTagHintScenario(
    name: 'en-332px-nonlinear-defaultBrand-discard',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(332, 800),
    textScaler: _NonlinearTextScaler(),
    outcome: _Outcome.discard,
  ),
  _DiaryTagHintScenario(
    name: 'zh-390px-ordinary-control-defaultBrand-save',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(390, 844),
    textScaler: TextScaler.linear(1.0),
    outcome: _Outcome.save,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final initialGlobalLocale = I18n.current;
  final initialTimezoneReader =
      LocalTimezoneResolver.debugSystemTimeZoneReader;

  setUp(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader =
        () async => 'Asia/Shanghai';
  });

  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = initialTimezoneReader;
    I18n.setLocale(initialGlobalLocale);
  });

  for (final scenario in _scenarios) {
    testWidgets('DiaryEditScreen tag hint layout & behavior ${scenario.name}', (
      tester,
    ) async {
      final recordedRequests = <String>[];
      await HttpOverrides.runZoned(
        () async {
          final originalLocale = I18n.current;
          final originalShadows = debugDisableShadows;
          final originalTimeZoneReader =
              LocalTimezoneResolver.debugSystemTimeZoneReader;
          final previousStore = SharedPreferencesStorePlatform.instance;

          final baselineDate = DateTime(2026, 10, 24);

          final initialPrefs = <String, Object>{
            'pref_app_timezone_mode': 'fixed',
            'pref_app_timezone_iana': 'Asia/Shanghai',
            'active_brand': scenario.initialBrand,
            'theme_shop_state': jsonEncode({
              'activeBrand': scenario.initialBrand,
              'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
            }),
            'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
            'duoyi_diary': <String>[],
            'flutter.pref_app_timezone_mode': 'fixed',
            'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
            'flutter.active_brand': scenario.initialBrand,
            'flutter.theme_shop_state': jsonEncode({
              'activeBrand': scenario.initialBrand,
              'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
            }),
            'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
            'flutter.duoyi_diary': <String>[],
          };

          SharedPreferences.setMockInitialValues(initialPrefs);
          final store = _RecordingPreferencesStore({
            for (final entry in initialPrefs.entries)
              if (!entry.key.startsWith('flutter.'))
                'flutter.${entry.key}': entry.value,
          });
          SharedPreferencesStorePlatform.instance = store;
          LocalTimezoneResolver.debugSystemTimeZoneReader =
              () async => 'Asia/Shanghai';

          final diaries = _RecordingDiaryProvider();
          final theme = ThemeProvider();
          late final PreferencesProvider preferences;

          try {
            I18n.setLocale(scenario.initialLocale);
            debugDisableShadows = false;

            await tester.runAsync(() async {
              preferences = PreferencesProvider();
              await theme.loadFromStorage().timeout(const Duration(seconds: 5));
              await preferences.loadFromStorage().timeout(
                const Duration(seconds: 5),
              );
              await diaries.loadFromStorage().timeout(
                const Duration(seconds: 5),
              );
              await loadWeeklyReviewScreenshotFonts().timeout(
                const Duration(seconds: 5),
              );
            });

            await _drainAccountWrites(tester);

            expect(theme.brand.id, scenario.initialBrand);
            expect(theme.isBrandUnlocked(scenario.targetBrand), isTrue);
            expect(diaries.entries, isEmpty);

            final baselineDiaryWrites = store.diaryWrites;

            tester.view.physicalSize = scenario.size;
            tester.view.devicePixelRatio = 1.0;

            final boundary = GlobalKey();
            final navigatorKey = GlobalKey<NavigatorState>();

            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<DiaryProvider>.value(value: diaries),
                  ChangeNotifierProvider<PreferencesProvider>.value(
                    value: preferences,
                  ),
                ],
                child: Consumer<ThemeProvider>(
                  builder: (context, currentTheme, _) {
                    return ValueListenableBuilder<AppLocale>(
                      valueListenable: I18n.localeListenable,
                      builder: (context, currentLocale, _) {
                        return MaterialApp(
                          navigatorKey: navigatorKey,
                          locale: currentLocale.flutterLocale,
                          supportedLocales: const [Locale('en'), Locale('zh')],
                          localizationsDelegates:
                              GlobalMaterialLocalizations.delegates,
                          theme: currentTheme.brand.theme,
                          builder: (context, child) => MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              textScaler: scenario.textScaler,
                            ),
                            child: RepaintBoundary(
                              key: boundary,
                              child: child!,
                            ),
                          ),
                          home: Scaffold(
                            body: Center(
                              child: TextButton(
                                onPressed: () => navigatorKey.currentState!.push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => BrandRouteSurface(
                                      remountOnLocaleChange: false,
                                      child: DiaryEditScreen(
                                        initialDate: baselineDate,
                                      ),
                                    ),
                                  ),
                                ),
                                child: const Text('Open diary editor'),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            );

            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            // 1. Open DiaryEditScreen
            await tester.tap(find.text('Open diary editor'));
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            final editorFinder = find.byType(DiaryEditScreen);
            expect(editorFinder, findsOneWidget);
            final initialEditorState = tester.state(editorFinder);
            final initialModalRoute =
                ModalRoute.of(tester.element(editorFinder));
            expect(initialModalRoute, isNotNull);

            final scrollableFinder = find
                .descendant(of: editorFinder, matching: find.byType(Scrollable))
                .first;

            // 2. Locate tag field by prefixIcon Icons.tag
            final tagFieldFinder = find.byWidgetPredicate(
              (w) =>
                  w is TextField &&
                  w.decoration?.prefixIcon is Icon &&
                  (w.decoration!.prefixIcon as Icon).icon == Icons.tag,
            );
            await _scrollTo(
              tester,
              tagFieldFinder,
              scrollable: scrollableFinder,
            );
            expect(tagFieldFinder, findsOneWidget);

            // Cache controller to avoid relying on off-screen widget instances
            final tagController =
                tester.widget<TextField>(tagFieldFinder).controller!;
            expect(tagController.text, isEmpty);

            // 3. Verify initial tag hint layout & natural line wrapping
            final expectedInitialHint = I18n.tr('diary.editor.tag_hint');
            final hintMeasurements = await _assertAndMeasureTagHintLayout(
              tester,
              boundaryKey: boundary,
              expectedHint: expectedInitialHint,
              role: '${scenario.name}-initial-hint',
              scrollableFinder: scrollableFinder,
            );

            // Verify initial tag semantics (textField flag, hint/label present exactly once)
            _assertTagSemantics(
              tester,
              tagFieldFinder: tagFieldFinder,
              expectedHint: expectedInitialHint,
              role: '${scenario.name}-initial-semantics',
              requireHintOccurrence: true,
            );

            await _captureScreenshot(
              tester,
              boundary,
              '${scenario.name}-01-initial',
            );
            await _saveMeasurements(
              tester,
              '${scenario.name}-01-initial',
              {
                'scenario': scenario.name,
                'stage': 'initial-hint',
                'brand': scenario.initialBrand,
                'locale': scenario.initialLocale.name,
                'size': {
                  'width': scenario.size.width,
                  'height': scenario.size.height,
                },
                'measurements': hintMeasurements,
              },
            );

            // 4. Enter uncommitted draft: content, uncommitted tag, mood, weather
            final draftContentText = 'Draft content for ${scenario.name}';
            final draftTagText = 'study-tag';
            const expectedMood = Mood.awesome;
            const expectedWeather = Weather.rain;

            // Content field: cache controller
            final contentFieldFinder = find.byWidgetPredicate(
              (w) =>
                  w is TextField &&
                  (w.maxLines == 12 ||
                      w.decoration?.hintText ==
                          I18n.tr('diary.editor.content_hint')),
            );
            await _scrollTo(
              tester,
              contentFieldFinder,
              scrollable: scrollableFinder,
            );
            final contentController =
                tester.widget<TextField>(contentFieldFinder).controller!;
            await tester.tap(contentFieldFinder);
            await tester.enterText(contentFieldFinder, draftContentText);
            await tester.pump();

            // Tag field: enter uncommitted tag WITHOUT submitting done
            await _scrollTo(
              tester,
              tagFieldFinder,
              scrollable: scrollableFinder,
            );
            await tester.tap(tagFieldFinder);
            await tester.enterText(tagFieldFinder, draftTagText);
            await tester.pump();

            // Verify uncommitted state: text in controller, no Chip yet
            expect(tagController.text, equals(draftTagText));
            expect(
              find.ancestor(
                of: find.text(draftTagText),
                matching: find.byType(Chip),
              ),
              findsNothing,
              reason: 'Uncommitted tag must not create Chip before submit',
            );

            // Select mood (Mood.awesome 😄)
            await _scrollTo(
              tester,
              find.text(expectedMood.emoji),
              scrollable: scrollableFinder,
            );
            await tester.tap(find.text(expectedMood.emoji));
            await _boundedPumpAndSettle(tester);

            // Select weather (Weather.rain 🌧️)
            final weatherChipFinder = find.byWidgetPredicate(
              (w) =>
                  w is FilterChip &&
                  w.label is Text &&
                  (w.label as Text).data!.contains(expectedWeather.emoji),
            );
            await _scrollTo(
              tester,
              weatherChipFinder,
              scrollable: scrollableFinder,
            );
            await tester.tap(weatherChipFinder);
            await _boundedPumpAndSettle(tester);
            expect(
              tester.widget<FilterChip>(weatherChipFinder).selected,
              isTrue,
            );

            // Selecting mood/weather alters focus: re-focus tag field before switch
            await _scrollTo(
              tester,
              tagFieldFinder,
              scrollable: scrollableFinder,
            );
            final tagEditable = tester.widget<EditableText>(
              find.descendant(
                of: tagFieldFinder,
                matching: find.byType(EditableText),
              ),
            );
            final tagFocusNode = tagEditable.focusNode;
            tagFocusNode.requestFocus();
            await tester.pump();
            final hadFocusBeforeBrandSwitch = tagFocusNode.hasFocus;
            expect(
              hadFocusBeforeBrandSwitch,
              isTrue,
              reason: 'Tag field must be focused before live brand switch',
            );

            // Scroll to establish a meaningful scroll offset when scrollable
            await tester.drag(scrollableFinder, const Offset(0, -60));
            await _boundedPumpAndSettle(tester);
            final scrollPosition =
                tester.state<ScrollableState>(scrollableFinder).position;
            final savedScrollOffset = scrollPosition.pixels;
            if (scrollPosition.maxScrollExtent > 0) {
              expect(
                savedScrollOffset,
                greaterThan(0),
                reason:
                    'Scrollable scenarios must establish nonzero scroll offset',
              );
            } else {
              expect(
                savedScrollOffset,
                equals(0),
                reason:
                    'Non-overflowing scenarios must maintain zero offset within valid extent',
              );
              expect(
                savedScrollOffset,
                inInclusiveRange(
                  scrollPosition.minScrollExtent,
                  scrollPosition.maxScrollExtent,
                ),
                reason: 'Offset must stay within valid extent',
              );
            }

            // 5. Live Brand Switch: initialBrand -> targetBrand
            await tester.runAsync(() async {
              final switched = await theme.setBrand(scenario.targetBrand);
              expect(switched, isTrue);
              await AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              );
            });
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            // Assert State identity and surface style preserved
            expect(
              identical(tester.state(editorFinder), initialEditorState),
              isTrue,
              reason: 'State identity preserved across live brand switch',
            );
            expect(
              identical(
                ModalRoute.of(tester.element(editorFinder)),
                initialModalRoute,
              ),
              isTrue,
              reason: 'ModalRoute identity preserved across live brand switch',
            );
            expect(
              appSurfaceStyleOf(tester.element(editorFinder)),
              equals(
                scenario.targetBrand == 'liquidGlass'
                    ? AppSurfaceStyle.liquidGlass
                    : AppSurfaceStyle.ios,
              ),
            );

            // Assert uncommitted draft fields preserved via cached controllers
            expect(
              tagController.text,
              equals(draftTagText),
              reason: 'Uncommitted tag text preserved on brand switch',
            );
            expect(
              contentController.text,
              equals(draftContentText),
              reason: 'Draft content preserved on brand switch',
            );
            expect(
              tagFocusNode.hasFocus,
              equals(hadFocusBeforeBrandSwitch),
              reason: 'Focus state preserved on brand switch',
            );

            // Verify weather selection after scrolling back to it
            await _scrollTo(
              tester,
              weatherChipFinder,
              scrollable: scrollableFinder,
            );
            expect(
              tester.widget<FilterChip>(weatherChipFinder).selected,
              isTrue,
              reason: 'Weather selection preserved on brand switch',
            );

            await _captureScreenshot(
              tester,
              boundary,
              '${scenario.name}-02-switchedBrand',
            );

            // Re-focus tag field before locale switch
            await _scrollTo(
              tester,
              tagFieldFinder,
              scrollable: scrollableFinder,
            );
            tagFocusNode.requestFocus();
            await tester.pump();
            final hadFocusBeforeLocaleSwitch = tagFocusNode.hasFocus;
            expect(
              hadFocusBeforeLocaleSwitch,
              isTrue,
              reason: 'Tag field must be focused before live locale switch',
            );

            // 6. Live Locale Switch: initialLocale -> alternateLocale -> initialLocale
            I18n.setLocale(scenario.alternateLocale);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(
              identical(tester.state(editorFinder), initialEditorState),
              isTrue,
              reason: 'State identity preserved across locale switch',
            );
            expect(
              tagController.text,
              equals(draftTagText),
              reason: 'Uncommitted tag text preserved on locale switch',
            );
            expect(
              contentController.text,
              equals(draftContentText),
              reason: 'Draft content preserved on locale switch',
            );
            expect(
              tagFocusNode.hasFocus,
              equals(hadFocusBeforeLocaleSwitch),
              reason: 'Focus state preserved on locale switch',
            );

            // Verify translated hint layout in alternate locale without clearing draft
            final altExpectedHint = I18n.tr('diary.editor.tag_hint');
            final altHintFinder = find.text(altExpectedHint);
            final isEmbeddedInTextField = altHintFinder.evaluate().isNotEmpty &&
                find
                    .ancestor(
                      of: altHintFinder,
                      matching: find.byType(TextField),
                    )
                    .evaluate()
                    .isNotEmpty;
            final isExternalHint =
                altHintFinder.evaluate().isNotEmpty && !isEmbeddedInTextField;
            if (isExternalHint) {
              await _assertAndMeasureTagHintLayout(
                tester,
                boundaryKey: boundary,
                expectedHint: altExpectedHint,
                role: '${scenario.name}-alt-locale-hint',
                scrollableFinder: scrollableFinder,
              );
            } else {
              await _scrollTo(
                tester,
                tagFieldFinder,
                scrollable: scrollableFinder,
              );
              final tf = tester.widget<TextField>(tagFieldFinder);
              expect(
                tf.decoration?.hintText,
                equals(altExpectedHint),
                reason: 'Translated hintText updated in alternate locale',
              );
            }

            // Real tag semantics check on alternate locale
            await _scrollTo(
              tester,
              tagFieldFinder,
              scrollable: scrollableFinder,
            );
            _assertTagSemantics(
              tester,
              tagFieldFinder: tagFieldFinder,
              expectedHint: altExpectedHint,
              role: '${scenario.name}-alt-locale-semantics',
              requireHintOccurrence: isExternalHint,
            );

            // Switch locale back to initial
            I18n.setLocale(scenario.initialLocale);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(
              identical(tester.state(editorFinder), initialEditorState),
              isTrue,
              reason: 'State identity preserved after reverting locale',
            );
            expect(
              tagController.text,
              equals(draftTagText),
              reason: 'Uncommitted tag text preserved after reverting locale',
            );
            expect(
              tagFocusNode.hasFocus,
              equals(hadFocusBeforeLocaleSwitch),
              reason: 'Focus preserved after reverting locale',
            );

            // Verify initial hint if external hint widget is rendered
            final restoredHintFinder = find.text(expectedInitialHint);
            final isRestoredExternalHint =
                restoredHintFinder.evaluate().isNotEmpty &&
                    find
                        .ancestor(
                          of: restoredHintFinder,
                          matching: find.byType(TextField),
                        )
                        .evaluate()
                        .isEmpty;
            if (isRestoredExternalHint) {
              await _assertAndMeasureTagHintLayout(
                tester,
                boundaryKey: boundary,
                expectedHint: expectedInitialHint,
                role: '${scenario.name}-restored-locale-hint',
                scrollableFinder: scrollableFinder,
              );
            }

            // 7. Explicitly submit tag via TextInputAction.done
            await _scrollTo(
              tester,
              tagFieldFinder,
              scrollable: scrollableFinder,
            );
            await tester.showKeyboard(tagFieldFinder);
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await _boundedPumpAndSettle(tester);

            // Controller text cleared upon submit; Tag Chip rendered
            expect(
              tagController.text,
              isEmpty,
              reason: 'Tag input controller must clear after pressing done',
            );
            final tagChipFinder = find.ancestor(
              of: find.text(draftTagText),
              matching: find.byType(Chip),
            );
            expect(
              tagChipFinder,
              findsOneWidget,
              reason: 'Submitted tag must render as a Chip',
            );

            // Now that input is empty, verify tag hint layout post-submission
            await _assertAndMeasureTagHintLayout(
              tester,
              boundaryKey: boundary,
              expectedHint: expectedInitialHint,
              role: '${scenario.name}-post-submit-hint',
              scrollableFinder: scrollableFinder,
            );

            // Post-submission semantics check with empty input
            _assertTagSemantics(
              tester,
              tagFieldFinder: tagFieldFinder,
              expectedHint: expectedInitialHint,
              role: '${scenario.name}-post-submit-semantics',
              requireHintOccurrence: true,
            );

            await _captureScreenshot(
              tester,
              boundary,
              '${scenario.name}-03-tagCommitted',
            );

            // 8. Outcome: Discard vs Save contracts
            if (scenario.outcome == _Outcome.discard) {
              // Discard contract: tap BackButton
              final backButton = find.byType(BackButton);
              expect(backButton, findsOneWidget);
              await _scrollTo(tester, backButton, scrollable: scrollableFinder);
              await tester.tap(backButton);
              await _drainAccountWrites(tester);
              await _boundedPumpAndSettle(tester);
              expect(tester.takeException(), isNull);

              // Route popped
              expect(find.byType(DiaryEditScreen), findsNothing);
              expect(find.text('Open diary editor'), findsOneWidget);

              // Zero writes to storage and zero provider calls
              expect(recordedRequests, isEmpty);
              expect(store.diaryWrites, equals(baselineDiaryWrites));
              expect(diaries.saves, equals(0));
              expect(diaries.entries, isEmpty);

              final prefs = await SharedPreferences.getInstance();
              final storedDiaries = prefs.getStringList('duoyi_diary') ?? [];
              expect(storedDiaries, isEmpty);

              await _saveMeasurements(
                tester,
                '${scenario.name}-04-discarded',
                {
                  'scenario': scenario.name,
                  'outcome': 'discard',
                  'writes': store.diaryWrites - baselineDiaryWrites,
                  'saves': diaries.saves,
                  'persisted': false,
                },
              );
            } else {
              // Save contract: tap Save check button
              final saveButton = find.widgetWithIcon(IconButton, Icons.check);
              expect(saveButton, findsOneWidget);
              await tester.tap(saveButton);
              await _drainAccountWrites(tester);
              await _boundedPumpAndSettle(tester);
              expect(tester.takeException(), isNull);

              // Route popped
              expect(find.byType(DiaryEditScreen), findsNothing);
              expect(find.text('Open diary editor'), findsOneWidget);

              // Verified: exactly one write to local store and provider
              expect(recordedRequests, isEmpty);
              expect(
                store.diaryWrites,
                equals(baselineDiaryWrites + 1),
                reason: 'Save must trigger exactly 1 write to SharedPreferences',
              );
              expect(diaries.saves, equals(1));
              expect(diaries.entries.length, equals(1));

              final savedEntry = diaries.entries.first;
              expect(savedEntry.content, equals(draftContentText));
              expect(savedEntry.tags, equals([draftTagText]));
              expect(savedEntry.mood, equals(expectedMood));
              expect(savedEntry.weather, equals(expectedWeather));
              expect(savedEntry.date, equals(baselineDate));

              // Verified: persisted JSON in SharedPreferences
              final prefs = await SharedPreferences.getInstance();
              final storedDiaries = prefs.getStringList('duoyi_diary');
              expect(storedDiaries, isNotNull);
              expect(storedDiaries!.length, equals(1));

              final storedJson =
                  jsonDecode(storedDiaries.first) as Map<String, dynamic>;
              expect(storedJson['content'], equals(draftContentText));
              expect(storedJson['tags'], equals([draftTagText]));
              expect(storedJson['mood'], equals(expectedMood.index));
              expect(storedJson['weather'], equals(expectedWeather.index));

              await _saveMeasurements(
                tester,
                '${scenario.name}-04-saved',
                {
                  'scenario': scenario.name,
                  'outcome': 'save',
                  'writes': store.diaryWrites - baselineDiaryWrites,
                  'saves': diaries.saves,
                  'persisted': true,
                  'entry': storedJson,
                },
              );
            }

            await _captureScreenshot(
              tester,
              boundary,
              '${scenario.name}-05-final',
            );
          } finally {
            try {
              await _drainAccountWrites(tester);
              await tester.pumpWidget(const SizedBox.shrink());
              await _boundedPumpAndSettle(tester);
            } finally {
              SharedPreferences.resetStatic();
              SharedPreferencesStorePlatform.instance = previousStore;
              LocalTimezoneResolver.debugSystemTimeZoneReader =
                  originalTimeZoneReader;
              diaries.dispose();
              theme.dispose();
              preferences.dispose();
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
              debugDisableShadows = originalShadows;
              I18n.setLocale(originalLocale);
            }
          }
        },
        createHttpClient: (_) {
          recordedRequests.add('HTTP client creation');
          throw StateError(
            'Unexpected network client during diary fixture: offline contract violated',
          );
        },
      );
    });
  }
}
