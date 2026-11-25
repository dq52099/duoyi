// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart'
    show AppModalSheet, appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';
import '../support/rendered_control_contrast.dart' show expectControlTouchTarget;

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int countdownWrites = 0;

  static bool _isCountdownKey(String key) =>
      key == 'duoyi_countdowns' ||
      key == 'flutter.duoyi_countdowns' ||
      key.endsWith('.duoyi_countdowns');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isCountdownKey(key)) {
      countdownWrites++;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isCountdownKey(key)) {
      countdownWrites++;
    }
    return super.remove(key);
  }
}

Object _countdownEditorState(WidgetTester tester, Finder descendant) {
  Element? element = tester.element(descendant);
  while (element != null) {
    if (element is StatefulElement &&
        element.state.runtimeType.toString().contains(
          'CountdownEditSheetState',
        )) {
      return element.state;
    }
    Element? parent;
    element.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false;
    });
    element = parent;
  }
  throw StateError('Countdown editor State was not found above descendant.');
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
  await tester.pump(const Duration(milliseconds: 40));
}

Future<void> _waitForUiState(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  final deadline = Stopwatch()..start();
  while (!ready() && deadline.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(ready(), isTrue, reason: description);
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name, {
  Finder? scrollableFinder,
  double? scrollToOffset,
  double? restoreOffset,
}) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] ??
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  var resolvedDir = explicitDir.trim();
  if (resolvedDir.startsWith('/') || resolvedDir.startsWith(r'\')) {
    if (!resolvedDir.contains('evidence/screenshots')) {
      resolvedDir = 'evidence/screenshots/${resolvedDir.split('/').last}';
    }
  } else if (!resolvedDir.startsWith('evidence/screenshots')) {
    resolvedDir = 'evidence/screenshots/$resolvedDir';
  }

  if (scrollableFinder != null && scrollToOffset != null) {
    tester
        .state<ScrollableState>(scrollableFinder)
        .position
        .jumpTo(scrollToOffset);
    await _boundedPumpAndSettle(tester);
  }

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError(
        'Missing boundary: RepaintBoundary render object not found for boundaryKey $boundaryKey when capturing "$name"',
      );
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError(
          'Encoding error: image.toByteData returned null when capturing "$name"',
        );
      }
      final file = File('$resolvedDir/countdown-editor-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });

  if (scrollableFinder != null && restoreOffset != null) {
    tester
        .state<ScrollableState>(scrollableFinder)
        .position
        .jumpTo(restoreOffset);
    await _boundedPumpAndSettle(tester);
  }
}

void _assertControl44(WidgetTester tester, Finder control, String description) {
  expect(control, findsOneWidget, reason: description);
  expectControlTouchTarget(tester, control);
}

Future<void> _assertReadableParagraph(
  WidgetTester tester, {
  required Finder textFinder,
  required GlobalKey boundaryKey,
  required String role,
  Finder? surfaceFinder,
  Finder? scrollableFinder,
  bool assertWordContinuity = false,
}) async {
  expect(textFinder, findsOneWidget, reason: '$role must be present');

  final rich = find.descendant(of: textFinder, matching: find.byType(RichText));
  final target = rich.evaluate().isNotEmpty ? rich : textFinder;
  final initialParagraph = tester.renderObject<RenderParagraph>(target);

  // Only a scrollable in the paragraph's actual ancestor chain may clip it.
  final RenderAbstractViewport? enclosingViewport =
      RenderAbstractViewport.maybeOf(initialParagraph);
  final isInsideScrollable = scrollableFinder != null &&
      enclosingViewport != null &&
      find.descendant(of: scrollableFinder, matching: textFinder).evaluate().isNotEmpty;

  if (!isInsideScrollable) {
    scrollableFinder = null;
    surfaceFinder ??= find.byType(AppModalSheet).last;
  }

  if (scrollableFinder != null) {
    await tester.scrollUntilVisible(
      textFinder,
      80,
      scrollable: scrollableFinder,
    );
    final element = tester.element(target);
    await Scrollable.ensureVisible(element, alignment: 0.5);
    await _boundedPumpAndSettle(tester);
  }

  final paragraph = tester.renderObject<RenderParagraph>(target);

  // 1. Core readability assertion: didExceedMaxLines must be false (no line truncation or ellipsis)
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role didExceedMaxLines must be false (no line truncation)',
  );

  final text = paragraph.text.toPlainText();
  expect(text, isNotEmpty, reason: '$role text must not be empty');

  final renderBoundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  final screenRect = Rect.fromLTWH(
    0,
    0,
    tester.view.physicalSize.width / tester.view.devicePixelRatio,
    tester.view.physicalSize.height / tester.view.devicePixelRatio,
  );

  Rect? surfaceRect;
  if (surfaceFinder != null) {
    final surfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
    surfaceRect = MatrixUtils.transformRect(
      surfaceBox.getTransformTo(renderBoundary),
      Offset.zero & surfaceBox.size,
    );
  }

  final Rect visibleClipRect;
  if (scrollableFinder != null) {
    RenderBox? foundViewportBox;
    final currentViewport = RenderAbstractViewport.maybeOf(paragraph);
    if (currentViewport is RenderBox) {
      foundViewportBox = currentViewport as RenderBox;
    } else {
      final scrollableElement = tester.element(scrollableFinder);
      void visitor(Element element) {
        if (foundViewportBox != null) return;
        final ro = element.renderObject;
        if (ro is RenderAbstractViewport && ro is RenderBox) {
          foundViewportBox = ro as RenderBox;
          return;
        }
        element.visitChildren(visitor);
      }
      scrollableElement.visitChildren(visitor);
      foundViewportBox ??= tester.renderObject<RenderBox>(scrollableFinder);
    }
    expect(
      foundViewportBox,
      isNotNull,
      reason: 'Scrollable $role must have an enclosing viewport RenderBox',
    );
    final RenderBox resolvedViewportBox = foundViewportBox!;
    final viewportRect = MatrixUtils.transformRect(
      resolvedViewportBox.getTransformTo(renderBoundary),
      Offset.zero & resolvedViewportBox.size,
    );
    visibleClipRect = screenRect.intersect(viewportRect);
  } else {
    expect(
      surfaceRect,
      isNotNull,
      reason: 'Non-scrollable $role requires a painted surface to intersect with screen',
    );
    visibleClipRect = screenRect.intersect(surfaceRect!);
  }

  // 2. Character-by-character readability verification:
  final nonWhitespaceOffsets = <int>[];
  for (var i = 0; i < text.length; i++) {
    if (text[i].trim().isNotEmpty) {
      nonWhitespaceOffsets.add(i);
    }
  }
  expect(
    nonWhitespaceOffsets,
    isNotEmpty,
    reason: '$role must contain non-whitespace characters to lay out',
  );

  for (final offset in nonWhitespaceOffsets) {
    final char = text[offset];
    final charBoxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + 1),
    );
    expect(
      charBoxes,
      isNotEmpty,
      reason: '$role character "$char" at index $offset must have a laid out box',
    );

    for (final box in charBoxes) {
      expect(
        box.left,
        greaterThanOrEqualTo(-0.5),
        reason:
            '$role character "$char" box left ${box.left} must be inside paragraph allocated width',
      );
      expect(
        box.right,
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason:
            '$role character "$char" box right ${box.right} must be inside paragraph allocated width ${paragraph.size.width}',
      );

      if (scrollableFinder != null) {
        final initialGlyphY = paragraph.localToGlobal(
          Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2),
        ).dy;
        if (initialGlyphY < visibleClipRect.top || initialGlyphY > visibleClipRect.bottom) {
          final scroll = Scrollable.maybeOf(tester.element(target));
          if (scroll != null) {
            final delta = initialGlyphY - visibleClipRect.center.dy;
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
      }

      final glyphRect = MatrixUtils.transformRect(
        paragraph.getTransformTo(renderBoundary),
        Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
      );

      Rect? currentSurfaceRect;
      if (surfaceFinder != null) {
        final sBox = tester.renderObject<RenderBox>(surfaceFinder);
        currentSurfaceRect = MatrixUtils.transformRect(
          sBox.getTransformTo(renderBoundary),
          Offset.zero & sBox.size,
        );
      }

      if (currentSurfaceRect != null) {
        expect(
          glyphRect.left,
          greaterThanOrEqualTo(currentSurfaceRect.left - 0.5),
          reason:
              '$role character "$char" glyph left ${glyphRect.left} must be within painted surface left ${currentSurfaceRect.left}',
        );
        expect(
          glyphRect.right,
          lessThanOrEqualTo(currentSurfaceRect.right + 0.5),
          reason:
              '$role character "$char" glyph right ${glyphRect.right} must be within painted surface right ${currentSurfaceRect.right}',
        );
        expect(
          glyphRect.top,
          greaterThanOrEqualTo(currentSurfaceRect.top - 0.5),
          reason:
              '$role character "$char" glyph top ${glyphRect.top} must be within painted surface top ${currentSurfaceRect.top}',
        );
        expect(
          glyphRect.bottom,
          lessThanOrEqualTo(currentSurfaceRect.bottom + 0.5),
          reason:
              '$role character "$char" glyph bottom ${glyphRect.bottom} must be within painted surface bottom ${currentSurfaceRect.bottom}',
        );
      }

      expect(
        glyphRect.left,
        greaterThanOrEqualTo(visibleClipRect.left - 0.5),
        reason:
            '$role character "$char" glyph left ${glyphRect.left} must be within visible viewport left ${visibleClipRect.left}',
      );
      expect(
        glyphRect.right,
        lessThanOrEqualTo(visibleClipRect.right + 0.5),
        reason:
            '$role character "$char" glyph right ${glyphRect.right} must be within visible viewport right ${visibleClipRect.right}',
      );
      expect(
        glyphRect.top,
        greaterThanOrEqualTo(visibleClipRect.top - 0.5),
        reason:
            '$role character "$char" glyph top ${glyphRect.top} must be within visible viewport top ${visibleClipRect.top}',
      );
      expect(
        glyphRect.bottom,
        lessThanOrEqualTo(visibleClipRect.bottom + 0.5),
        reason:
            '$role character "$char" glyph bottom ${glyphRect.bottom} must be within visible viewport bottom ${visibleClipRect.bottom}',
      );
    }
  }

  // 3. Natural word line breaking
  if (assertWordContinuity) {
    for (final wordMatch in RegExp(
      r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*",
    ).allMatches(text)) {
      final word = wordMatch.group(0)!;
      final wordBoxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: wordMatch.start, extentOffset: wordMatch.end),
      );
      expect(wordBoxes, isNotEmpty, reason: '$role: word "$word" must have boxes');
      final lineTops = wordBoxes.map((b) => b.top.round()).toSet();
      expect(
        lineTops.length,
        equals(1),
        reason:
            '$role: word "$word" must remain on one line without character-by-character column breakage',
      );
    }
  }

  // 4. Full text selection boxes
  final fullBoxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(
    fullBoxes,
    isNotEmpty,
    reason: '$role full text selection boxes must not be empty',
  );
}

enum _EditorOutcome {
  saveDraft,
  cancelDraft,
}

class _CountdownEditorScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final String targetBrand;
  final Size size;
  final double scale;
  final _EditorOutcome outcome;
  final Axis expectedReminderDirection;

  const _CountdownEditorScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.size,
    required this.scale,
    required this.outcome,
    required this.expectedReminderDirection,
  });
}

const _scenarios = <_CountdownEditorScenario>[
  _CountdownEditorScenario(
    name: 'en-portrait-320x844-scale2-defaultBrand',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    scale: 2.0,
    outcome: _EditorOutcome.saveDraft,
    expectedReminderDirection: Axis.vertical,
  ),
  _CountdownEditorScenario(
    name: 'zh-portrait-320x844-scale2-liquidGlass',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(320, 844),
    scale: 2.0,
    outcome: _EditorOutcome.cancelDraft,
    expectedReminderDirection: Axis.vertical,
  ),
  _CountdownEditorScenario(
    name: 'en-landscape-844x390-scale1-defaultBrand',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(844, 390),
    scale: 1.0,
    outcome: _EditorOutcome.cancelDraft,
    expectedReminderDirection: Axis.horizontal,
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'countdown editor responsive title subtitle and reminder layout ${scenario.name}',
      (tester) async {
        final originalLocale = I18n.current;
        final originalShadows = debugDisableShadows;
        final originalTimeZoneReader =
            LocalTimezoneResolver.debugSystemTimeZoneReader;
        final originalNativeTimeZoneReader =
            LocalTimezoneResolver.debugNativeSystemTimeZoneReader;
        final previousStore = SharedPreferencesStorePlatform.instance;

        final syntheticItems = [
          CountdownItem(
            id: 'item-sync-milestone',
            title: 'Milestone Alpha Sync',
            targetDate: DateTime(2030, 8, 15),
            category: 'ProjectAlpha',
            categoryIsDefault: false,
            isPinned: true,
            remind: true,
            remindDaysBefore: 3,
            remindHour: 9,
            remindMinute: 30,
            reminderKind: ReminderKind.push,
          ),
          CountdownItem(
            id: 'item-author-review',
            title: 'Annual Team Review',
            targetDate: DateTime(2030, 10, 20),
            category: '工作',
            categoryIsDefault: false,
            isPinned: false,
            remind: false,
            reminderKind: ReminderKind.off,
          ),
        ];

        final initialEncodedCountdowns =
            syntheticItems.map((e) => jsonEncode(e.toJson())).toList();

        final initialPrefs = <String, Object>{
          'pref_app_timezone_mode': 'fixed',
          'pref_app_timezone_iana': 'Asia/Shanghai',
          'active_brand': scenario.initialBrand,
          'theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'duoyi_countdowns': initialEncodedCountdowns,
          'flutter.pref_app_timezone_mode': 'fixed',
          'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
          'flutter.active_brand': scenario.initialBrand,
          'flutter.theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'flutter.duoyi_countdowns': initialEncodedCountdowns,
        };

        SharedPreferences.setMockInitialValues(initialPrefs);
        final store = _RecordingPreferencesStore({
          for (final entry in initialPrefs.entries)
            if (!entry.key.startsWith('flutter.'))
              'flutter.${entry.key}': entry.value,
        });
        SharedPreferencesStorePlatform.instance = store;

        LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
            'Asia/Shanghai';
        LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async =>
            'Asia/Shanghai';

        final transport = MockClient((request) async {
          fail('Unexpected network call during test: ${request.method} ${request.url}');
        });

        late final ThemeProvider theme;
        late final CountdownProvider countdownProvider;
        late final PreferencesProvider preferences;

        try {
          I18n.setLocale(scenario.initialLocale);
          debugDisableShadows = false;

          await tester.runAsync(() async {
            await LocalTimezoneResolver.init().timeout(
              const Duration(seconds: 5),
            );
            preferences = PreferencesProvider();
            theme = ThemeProvider();
            countdownProvider = CountdownProvider();
            await theme.loadFromStorage().timeout(const Duration(seconds: 5));
            await preferences.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await countdownProvider.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await loadWeeklyReviewScreenshotFonts().timeout(
              const Duration(seconds: 5),
            );
          });

          await _drainAccountWrites(tester);

          expect(theme.brand.id, scenario.initialBrand);
          expect(countdownProvider.items.length, 2);

          final baselineWrites = store.countdownWrites;
          void assertZeroCountdownWrites(String stage) {
            expect(
              store.countdownWrites,
              baselineWrites,
              reason: '$stage: expected zero writes (actual=${store.countdownWrites}, baseline=$baselineWrites)',
            );
          }

          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1;

          final boundaryKey = GlobalKey();

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<CountdownProvider>.value(
                  value: countdownProvider,
                ),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences,
                ),
              ],
              child: Consumer<ThemeProvider>(
                builder: (context, currentTheme, _) =>
                    ValueListenableBuilder<AppLocale>(
                      valueListenable: I18n.localeListenable,
                      builder: (context, currentLocale, _) => MaterialApp(
                        locale: Locale(
                          currentLocale == AppLocale.en ? 'en' : 'zh',
                        ),
                        supportedLocales: const [Locale('en'), Locale('zh')],
                        localizationsDelegates:
                            GlobalMaterialLocalizations.delegates,
                        theme: currentTheme.brand.theme,
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: scenario.scale < 0
                                ? const RouteProbeNonlinearScaler()
                                : TextScaler.linear(scenario.scale),
                          ),
                          child: RepaintBoundary(key: boundaryKey, child: child!),
                        ),
                        home: const BrandRouteSurface(
                          remountOnLocaleChange: false,
                          child: CountdownScreen(),
                        ),
                      ),
                    ),
              ),
            ),
          );

          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);
          assertZeroCountdownWrites('Initial main screen mount');

          // 1. Open the editor sheet for the item with remind: true
          final cardToTap = find.byKey(
            const ValueKey('countdown_card_item-sync-milestone'),
          );
          expect(cardToTap, findsOneWidget);
          await tester.tap(cardToTap);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(find.byType(AppModalSheet), findsOneWidget);
          assertZeroCountdownWrites('Editor sheet opened');

          final modalSheetFinder = find.byType(AppModalSheet).last;
          final editorScrollable = find.descendant(
            of: modalSheetFinder,
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          ).first;
          expect(editorScrollable, findsOneWidget);

          final initialScrollExtent = tester
              .state<ScrollableState>(editorScrollable)
              .position
              .maxScrollExtent;
          if (initialScrollExtent > 0) {
            tester
                .state<ScrollableState>(editorScrollable)
                .position
                .jumpTo((initialScrollExtent * 0.2).clamp(5.0, 50.0));
            await _boundedPumpAndSettle(tester);
          }
          final initialScrollOffset = tester
              .state<ScrollableState>(editorScrollable)
              .position
              .pixels;

          // 2. Readability verification on Editor Title
          final expectedTitle = I18n.tr('countdown.editor.edit_title');
          final editorTitleFinder = find.descendant(
            of: modalSheetFinder,
            matching: find.text(expectedTitle),
          );
          await _assertReadableParagraph(
            tester,
            textFinder: editorTitleFinder,
            boundaryKey: boundaryKey,
            role: 'Editor Title',
            scrollableFinder: editorScrollable,
            assertWordContinuity: true,
          );

          // 3. Readability verification on Editor Subtitle (defect regression)
          final expectedSubtitle = I18n.tr('countdown.editor.subtitle');
          final editorSubtitleFinder = find.descendant(
            of: modalSheetFinder,
            matching: find.text(expectedSubtitle),
          );
          await _assertReadableParagraph(
            tester,
            textFinder: editorSubtitleFinder,
            boundaryKey: boundaryKey,
            role: 'Editor Subtitle',
            scrollableFinder: editorScrollable,
            assertWordContinuity: true,
          );

          // 4. Verify reminder selector layout and responsive direction
          final reminderKeyedSubtree = find.byKey(
            const ValueKey('countdown_reminder_kind_scroll'),
          );
          expect(reminderKeyedSubtree, findsOneWidget);

          final segmentedButtonFinder = find.descendant(
            of: reminderKeyedSubtree,
            matching: find.byType(SegmentedButton<ReminderKind>),
          );
          expect(segmentedButtonFinder, findsOneWidget);

          final segmentedWidget = tester.widget<SegmentedButton<ReminderKind>>(
            segmentedButtonFinder,
          );
          expect(
            segmentedWidget.direction,
            equals(scenario.expectedReminderDirection),
            reason:
                'SegmentedButton direction for ${scenario.name} must be ${scenario.expectedReminderDirection}',
          );

          // 5. Verify all 4 reminder kind option segments have >=44dp hit area and readable labels
          for (final kind in const [
            ReminderKind.push,
            ReminderKind.popup,
            ReminderKind.alarm,
            ReminderKind.off,
          ]) {
            final label = switch (kind) {
              ReminderKind.push => I18n.tr('reminder.kind.push'),
              ReminderKind.popup => I18n.tr('reminder.kind.popup'),
              ReminderKind.alarm => I18n.tr('reminder.kind.alarm'),
              ReminderKind.off => I18n.tr('reminder.kind.off'),
              ReminderKind.email => throw UnsupportedError(
                'ReminderKind.email is not supported in countdown editor',
              ),
            };
            final optionFinder = find.descendant(
              of: segmentedButtonFinder,
              matching: find.text(label),
            );
            final segmentButtonFinder = find.ancestor(
              of: optionFinder,
              matching: find.byType(TextButton),
            ).first;

            await tester.ensureVisible(segmentButtonFinder);
            await _boundedPumpAndSettle(tester);

            // True 44dp hit test and touch target on each reminder segment
            _assertControl44(
              tester,
              segmentButtonFinder,
              'Reminder segment "$label"',
            );

            // Readability and glyph containment inside viewport & surface
            await _assertReadableParagraph(
              tester,
              textFinder: optionFinder,
              boundaryKey: boundaryKey,
              role: 'Reminder option "$label"',
              scrollableFinder: editorScrollable,
              assertWordContinuity: true,
            );
          }

          // 6. Verify 44dp hit area on action buttons (revealed in viewport before testing)
          final cancelBtn = find.descendant(
            of: modalSheetFinder,
            matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
          );
          final saveBtn = find.byKey(
            const ValueKey('countdown_editor_save_button'),
          );
          await tester.ensureVisible(cancelBtn);
          await _boundedPumpAndSettle(tester);
          _assertControl44(tester, cancelBtn, 'Editor Cancel button');

          await tester.ensureVisible(saveBtn);
          await _boundedPumpAndSettle(tester);
          _assertControl44(tester, saveBtn, 'Editor Save button');

          // 7. Verify all modes can be selected by real tap inside selector right edge (right - 2)
          Future<void> tapSegmentRightEdge(ReminderKind kind) async {
            final label = switch (kind) {
              ReminderKind.push => I18n.tr('reminder.kind.push'),
              ReminderKind.popup => I18n.tr('reminder.kind.popup'),
              ReminderKind.alarm => I18n.tr('reminder.kind.alarm'),
              ReminderKind.off => I18n.tr('reminder.kind.off'),
              ReminderKind.email => throw UnsupportedError(
                'ReminderKind.email is not supported in countdown editor',
              ),
            };
            final optionFinder = find.descendant(
              of: segmentedButtonFinder,
              matching: find.text(label),
            );
            final segmentButtonFinder = find.ancestor(
              of: optionFinder,
              matching: find.byType(TextButton),
            ).first;

            await tester.ensureVisible(segmentButtonFinder);
            await _boundedPumpAndSettle(tester);

            final segmentRect = tester.getRect(segmentButtonFinder);
            final selectorRect = tester.getRect(segmentedButtonFinder);
            final vertical = tester
                .widget<SegmentedButton<ReminderKind>>(segmentedButtonFinder)
                .direction == Axis.vertical;
            if (vertical) {
              expect(
                segmentRect.right,
                closeTo(selectorRect.right, 0.5),
                reason: 'Every vertical segment must reach the drawn selector edge',
              );
            }
            final tapPoint = Offset(
              (vertical ? selectorRect.right : segmentRect.right) - 2.0,
              segmentRect.center.dy,
            );
            await tester.tapAt(tapPoint);
            await _boundedPumpAndSettle(tester);
          }

          // Switch to popup
          await tapSegmentRightEdge(ReminderKind.popup);
          expect(
            tester
                .widget<SegmentedButton<ReminderKind>>(segmentedButtonFinder)
                .selected,
            contains(ReminderKind.popup),
            reason: 'Tapping right edge of Popup segment must select ReminderKind.popup',
          );
          assertZeroCountdownWrites('Mode selection updated in-memory for popup');

          // Switch to alarm
          await tapSegmentRightEdge(ReminderKind.alarm);
          expect(
            tester
                .widget<SegmentedButton<ReminderKind>>(segmentedButtonFinder)
                .selected,
            contains(ReminderKind.alarm),
            reason: 'Tapping right edge of Alarm segment must select ReminderKind.alarm',
          );
          assertZeroCountdownWrites('Mode selection updated in-memory for alarm');

          // Switch to off (selects off, reminder switch toggles off per product logic)
          await tapSegmentRightEdge(ReminderKind.off);
          final reminderSwitchFinder = find.descendant(
            of: modalSheetFinder,
            matching: find.byType(SwitchListTile),
          );
          expect(
            tester.widget<SwitchListTile>(reminderSwitchFinder).value,
            isFalse,
            reason: 'Selecting Off mode must toggle reminder switch off',
          );
          assertZeroCountdownWrites('Mode selection updated in-memory for off');

          // Re-enable reminder switch so selector reappears
          await tester.ensureVisible(reminderSwitchFinder);
          await _boundedPumpAndSettle(tester);
          await tester.tap(reminderSwitchFinder);
          await _boundedPumpAndSettle(tester);
          expect(
            tester.widget<SwitchListTile>(reminderSwitchFinder).value,
            isTrue,
            reason: 'Re-enabling reminder switch restores reminder selector',
          );
          expect(
            tester
                .widget<SegmentedButton<ReminderKind>>(segmentedButtonFinder)
                .selected,
            contains(ReminderKind.off),
            reason: 'Restored selector retains ReminderKind.off selection',
          );
          assertZeroCountdownWrites('Reminder re-enabled in-memory');

          // Switch back to push to preserve original save contract
          await tapSegmentRightEdge(ReminderKind.push);
          expect(
            tester
                .widget<SegmentedButton<ReminderKind>>(segmentedButtonFinder)
                .selected,
            contains(ReminderKind.push),
            reason: 'Tapping right edge of Push segment must select ReminderKind.push',
          );
          assertZeroCountdownWrites('Mode selection updated in-memory for push');

          // 8. Capture draft screenshot if enabled
          await _capture(
            tester,
            boundaryKey,
            '${scenario.name}-01-editor-readable',
            scrollableFinder: editorScrollable,
            scrollToOffset: initialScrollOffset,
            restoreOffset: initialScrollOffset,
          );

          // 9. Live brand switch while editor is open (retained form state)
          final titleTextField = find.descendant(
            of: modalSheetFinder,
            matching: find.byType(TextField),
          ).first;
          final titleCtrl = tester.widget<TextField>(titleTextField).controller!;
          final initialEditorState = _countdownEditorState(
            tester,
            titleTextField,
          );
          final initialRoute = ModalRoute.of(tester.element(titleTextField));

          await tester.runAsync(() async {
            final switched = await theme.setBrand(scenario.targetBrand);
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _boundedPumpAndSettle(tester);

          final currentSheet = find.byType(AppModalSheet).last;
          final sheetStyle = appSurfaceStyleOf(tester.element(currentSheet));
          if (scenario.targetBrand == 'liquidGlass') {
            expect(sheetStyle, equals(AppSurfaceStyle.liquidGlass));
          } else {
            expect(sheetStyle, isNot(equals(AppSurfaceStyle.liquidGlass)));
          }

          expect(
            identical(_countdownEditorState(tester, titleTextField), initialEditorState),
            isTrue,
            reason: 'Editor state identity retained across brand switch',
          );
          expect(
            identical(ModalRoute.of(tester.element(titleTextField)), initialRoute),
            isTrue,
            reason: 'Editor route identity retained across brand switch',
          );
          expect(
            identical(
              tester.widget<TextField>(titleTextField).controller,
              titleCtrl,
            ),
            isTrue,
            reason: 'Editor controller identity retained across brand switch',
          );
          assertZeroCountdownWrites('After targetBrand switch');

          // Roundtrip brand back
          await tester.runAsync(() async {
            final reverted = await theme.setBrand(scenario.initialBrand);
            expect(reverted, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _boundedPumpAndSettle(tester);
          assertZeroCountdownWrites('After brand revert');

          // 10. Live locale switch while editor is open
          I18n.setLocale(scenario.alternateLocale);
          await _boundedPumpAndSettle(tester);
          expect(find.text(I18n.tr('countdown.editor.edit_title')), findsOneWidget);
          expect(find.text(I18n.tr('countdown.editor.subtitle')), findsOneWidget);
          expect(find.text(I18n.tr('action.save')), findsOneWidget);
          expect(find.text(I18n.tr('action.cancel')), findsOneWidget);
          assertZeroCountdownWrites('After alternate locale switch');

          // Roundtrip locale back
          I18n.setLocale(scenario.initialLocale);
          await _boundedPumpAndSettle(tester);
          expect(find.text(I18n.tr('countdown.editor.edit_title')), findsOneWidget);
          assertZeroCountdownWrites('After locale restore');

          // 11. Final outcome: Save (single write) or Cancel (zero writes)
          if (scenario.outcome == _EditorOutcome.saveDraft) {
            final saveButton = find.byKey(
              const ValueKey('countdown_editor_save_button'),
            );
            await tester.ensureVisible(saveButton);
            await _boundedPumpAndSettle(tester);
            await tester.runAsync(() => tester.tap(saveButton));
            await _drainAccountWrites(tester);
            await _boundedPumpAndSettle(tester);
            await _waitForUiState(
              tester,
              () =>
                  find.byType(AppModalSheet).evaluate().isEmpty &&
                  store.countdownWrites == baselineWrites + 1,
              'Saved draft commits exactly once and dismisses modal sheet',
            );

            expect(find.byType(AppModalSheet), findsNothing);
            expect(
              store.countdownWrites,
              baselineWrites + 1,
              reason: 'Save must execute exactly 1 storage write',
            );
          } else {
            final currentCancel = find.descendant(
              of: find.byType(AppModalSheet).last,
              matching: find.widgetWithText(
                TextButton,
                I18n.tr('action.cancel'),
              ),
            );
            await tester.ensureVisible(currentCancel);
            await _boundedPumpAndSettle(tester);
            await tester.tap(currentCancel);
            await _boundedPumpAndSettle(tester);

            expect(find.byType(AppModalSheet), findsNothing);
            assertZeroCountdownWrites('After editor cancel: strictly 0 writes');
          }

          expect(tester.takeException(), isNull);
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
            LocalTimezoneResolver.debugNativeSystemTimeZoneReader =
                originalNativeTimeZoneReader;
            countdownProvider.dispose();
            theme.dispose();
            preferences.dispose();
            transport.close();
            tester.view.reset();
            debugDisableShadows = originalShadows;
            I18n.setLocale(originalLocale);
          }
        }
      },
    );
  }
}
