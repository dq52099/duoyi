// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart'
    show AppModalSheet, AppSurfaceCard;
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
      final file = File('$resolvedDir/countdown-list-readable-$name.png');
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

void _assertControl44(WidgetTester tester, Finder finder, String description) {
  expect(finder, findsOneWidget, reason: '$description must exist');
  final size = tester.getSize(finder);
  expect(
    size.width,
    greaterThanOrEqualTo(44.0 - 0.01),
    reason: '$description width (${size.width}) must be >= 44px',
  );
  expect(
    size.height,
    greaterThanOrEqualTo(44.0 - 0.01),
    reason: '$description height (${size.height}) must be >= 44px',
  );
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

  if (scrollableFinder != null) {
    await tester.scrollUntilVisible(
      textFinder,
      80,
      scrollable: scrollableFinder,
    );
    final element = tester.element(textFinder);
    await Scrollable.ensureVisible(element, alignment: 0.5);
    await _boundedPumpAndSettle(tester);
  }

  final rich = find.descendant(of: textFinder, matching: find.byType(RichText));
  final target = rich.evaluate().isNotEmpty ? rich : textFinder;
  final paragraph = tester.renderObject<RenderParagraph>(target);

  // 1. Core readability assertion: didExceedMaxLines must be false (no truncation/ellipsis)
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

  // Determine real visible clip: screen ∩ viewport for scrollable, screen ∩ surface for non-scroll header
  final Rect visibleClipRect;
  if (scrollableFinder != null) {
    final viewportFinder = find.descendant(
      of: scrollableFinder,
      matching: find.byType(Viewport),
    );
    expect(viewportFinder, findsOneWidget);
    final viewportBox = tester.renderObject<RenderBox>(viewportFinder);
    final viewportRect = MatrixUtils.transformRect(
      viewportBox.getTransformTo(renderBoundary),
      Offset.zero & viewportBox.size,
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
  // Must verify that every non-whitespace character has a laid out glyph box.
  // Paragraph-local vertical box.top/bottom assertions are removed as RenderParagraph
  // does not clip font leading; physical containment is enforced via real surface and visibleClipRect.
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
      // Horizontal bounds within paragraph allocated width:
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

      // If content is taller than viewport and character is outside current visibleClipRect,
      // scroll line-by-line so that the character is brought into the viewport center.
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

      // Re-read transformed positions
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

  // 3. Natural word line breaking (words do not break across lines when avoidable)
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

  // 4. Full text selection boxes: check non-empty and horizontal paragraph width
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
      box.left,
      greaterThanOrEqualTo(-0.5),
      reason:
          '$role selection box left ${box.left} must be inside paragraph allocated width',
    );
    expect(
      box.right,
      lessThanOrEqualTo(paragraph.size.width + 0.5),
      reason:
          '$role selection box right ${box.right} must be inside paragraph allocated width ${paragraph.size.width}',
    );
  }
}

class _CountdownReadabilityScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String brandId;
  final Size size;
  final double scale;

  const _CountdownReadabilityScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.brandId,
    required this.size,
    required this.scale,
  });
}

const _scenarios = <_CountdownReadabilityScenario>[
  _CountdownReadabilityScenario(
    name: 'zh-portrait-320x844-scale2-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    brandId: 'defaultBrand',
    size: Size(320, 844),
    scale: 2.0,
  ),
  _CountdownReadabilityScenario(
    name: 'en-nonlinear-332x844-scaleNonlinear-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    brandId: 'liquidGlass',
    size: Size(332, 844),
    scale: -1.0,
  ),
  _CountdownReadabilityScenario(
    name: 'en-portrait-390x844-scale1-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    brandId: 'liquidGlass',
    size: Size(390, 844),
    scale: 1.0,
  ),
  _CountdownReadabilityScenario(
    name: 'zh-landscape-844x390-scale1-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    brandId: 'defaultBrand',
    size: Size(844, 390),
    scale: 1.0,
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'countdown list readability priority across two themes and locales: ${scenario.name}',
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
            id: 'item-generated-default',
            title: 'Generated Milestone',
            targetDate: DateTime(2030, 6, 15),
            categoryIsDefault: true,
            isPinned: true,
            remind: false,
            reminderKind: ReminderKind.off,
          ),
          CountdownItem(
            id: 'item-authored-default-literal',
            title: 'Authored Literal Default',
            targetDate: DateTime(2030, 9, 20),
            category: '默认',
            categoryIsDefault: false,
            isPinned: false,
            remind: false,
            reminderKind: ReminderKind.off,
          ),
          CountdownItem(
            id: 'item-authored-custom-alpha',
            title: 'Project Alpha Target',
            targetDate: DateTime(2030, 11, 1),
            category: 'ProjectAlpha',
            categoryIsDefault: false,
            isPinned: false,
            remind: false,
            reminderKind: ReminderKind.off,
          ),
          CountdownItem(
            id: 'item-authored-work',
            title: 'Work Sprint Review',
            targetDate: DateTime(2031, 1, 10),
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
          'active_brand': scenario.brandId,
          'theme_shop_state': jsonEncode({
            'activeBrand': scenario.brandId,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'duoyi_countdowns': initialEncodedCountdowns,
          'flutter.pref_app_timezone_mode': 'fixed',
          'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
          'flutter.active_brand': scenario.brandId,
          'flutter.theme_shop_state': jsonEncode({
            'activeBrand': scenario.brandId,
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
          fail(
            'Unexpected network call during countdown readability fixture: '
            '${request.method} ${request.url}',
          );
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

          // Assert ThemeProvider and loaded items
          expect(theme.brand.id, scenario.brandId);
          expect(theme.isBrandUnlocked('defaultBrand'), isTrue);
          expect(theme.isBrandUnlocked('liquidGlass'), isTrue);
          expect(countdownProvider.items.length, 4);

          final baselineCountdownWrites = store.countdownWrites;

          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1;

          final boundary = GlobalKey();

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
                          child: RepaintBoundary(key: boundary, child: child!),
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

          // Assert primary theme color applied to actual screen
          final expectedBrand = scenario.brandId == 'defaultBrand'
              ? AppBrands.defaultBrand
              : AppBrands.liquidGlass;
          final screenTheme = Theme.of(tester.element(find.byType(CountdownScreen)));
          expect(
            screenTheme.colorScheme.primary,
            equals(expectedBrand.theme.colorScheme.primary),
            reason: 'Screen Theme primary color must match real ${scenario.brandId} brand theme primary',
          );
          expect(I18n.current, equals(scenario.initialLocale));

          // 1. Verify main screen elements mounted and 44px on FAB
          expect(find.byType(CountdownScreen), findsOneWidget);
          expect(find.byType(BrandRouteSurface), findsOneWidget);
          final addButton = find.byKey(const ValueKey('countdown_add_button'));
          _assertControl44(tester, addButton, 'Countdown add FAB');

          // Verify list scrollable exists
          final mainListScrollable = find.descendant(
            of: find.byType(CountdownScreen),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          ).first;
          expect(mainListScrollable, findsOneWidget);

          // Capture initial header screenshot
          await _capture(tester, boundary, '${scenario.name}-01-initial-header');

          // 2. Readability assertion: nearest countdown description in header card
          final nearestDescPrefix = I18n.tr('countdown.nearest.prefix');
          final nearestDescFinder = find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data != null &&
                widget.data!.startsWith(nearestDescPrefix),
          );
          final headerSurfaceFinder = find.descendant(
            of: find.byType(CountdownScreen),
            matching: find.byType(AppSurfaceCard),
          ).first;
          await _assertReadableParagraph(
            tester,
            textFinder: nearestDescFinder,
            boundaryKey: boundary,
            surfaceFinder: headerSurfaceFinder,
            role: 'Header nearest countdown description (${scenario.name})',
          );

          // 3. Readability assertions on all 4 cards in real ListView viewport
          for (final item in syntheticItems) {
            final cardFinder = find.byKey(ValueKey('countdown_card_${item.id}'));

            // 3a. Card title readability (didExceedMaxLines=false, non-empty glyphs, word continuity)
            final titleFinder = find.descendant(
              of: cardFinder,
              matching: find.text(item.title),
            );
            await _assertReadableParagraph(
              tester,
              textFinder: titleFinder,
              boundaryKey: boundary,
              surfaceFinder: find.descendant(
                of: cardFinder,
                matching: find.byType(AppSurfaceCard),
              ).first,
              scrollableFinder: mainListScrollable,
              role: 'Card ${item.id} title (${scenario.name})',
              assertWordContinuity: true,
            );

            // 3b. Card target date readability (didExceedMaxLines=false, non-empty glyphs)
            final expectedTargetDate =
                '${I18n.tr('countdown.target.prefix')}'
                '${I18nDateFormat.date(item.targetDate, pattern: preferences.dateFormat, locale: I18n.current)}';
            final targetDateFinder = find.descendant(
              of: cardFinder,
              matching: find.text(expectedTargetDate),
            );
            await _assertReadableParagraph(
              tester,
              textFinder: targetDateFinder,
              boundaryKey: boundary,
              surfaceFinder: find.descendant(
                of: cardFinder,
                matching: find.byType(AppSurfaceCard),
              ).first,
              scrollableFinder: mainListScrollable,
              role: 'Card ${item.id} targetDate (${scenario.name})',
            );

            // 3c. Card days remaining label readability
            final expectedDaysLabel = item.daysRemaining < 0
                ? I18n.tr('countdown.days.elapsed')
                : I18n.tr('countdown.days.remaining');
            final daysLabelFinder = find.descendant(
              of: cardFinder,
              matching: find.text(expectedDaysLabel),
            );
            await _assertReadableParagraph(
              tester,
              textFinder: daysLabelFinder,
              boundaryKey: boundary,
              surfaceFinder: find.descendant(
                of: cardFinder,
                matching: find.byType(AppSurfaceCard),
              ).first,
              scrollableFinder: mainListScrollable,
              role: 'Card ${item.id} daysLabel (${scenario.name})',
            );
          }

          // Capture representative readable card screenshot with first card scrolled to center
          // Scroll up (negative delta) from the bottom of the list back to top pinned item
          final firstCardFinder = find.byKey(
            const ValueKey('countdown_card_item-generated-default'),
          );
          await tester.scrollUntilVisible(
            firstCardFinder,
            -80,
            scrollable: mainListScrollable,
          );
          await Scrollable.ensureVisible(
            tester.element(firstCardFinder),
            alignment: 0.5,
          );
          await _boundedPumpAndSettle(tester);
          await _capture(tester, boundary, '${scenario.name}-02-first-card-readable');

          // 4. Retain language switch contract: switch to alternate locale and back
          I18n.setLocale(scenario.alternateLocale);
          await _boundedPumpAndSettle(tester);
          expect(I18n.current, equals(scenario.alternateLocale));

          // Verify generated category reflects alternate locale
          final generatedCard = find.byKey(
            const ValueKey('countdown_card_item-generated-default'),
          );
          await tester.scrollUntilVisible(
            generatedCard,
            -80,
            scrollable: mainListScrollable,
          );
          await Scrollable.ensureVisible(
            tester.element(generatedCard),
            alignment: 0.5,
          );
          await _boundedPumpAndSettle(tester);

          final expectedGeneratedAlt = scenario.alternateLocale == AppLocale.en
              ? 'Default'
              : '默认';
          expect(
            find.descendant(
              of: generatedCard,
              matching: find.text(expectedGeneratedAlt),
            ),
            findsOneWidget,
            reason: 'Generated category follows alternate locale dynamically',
          );

          // Restore initial locale
          I18n.setLocale(scenario.initialLocale);
          await _boundedPumpAndSettle(tester);
          expect(I18n.current, equals(scenario.initialLocale));

          // 5. Retain card tap to editor draft and cancel without writes:
          // Scroll until customAlpha title is visible and hit-testable, tap to open editor
          final customAlphaCard = find.byKey(
            const ValueKey('countdown_card_item-authored-custom-alpha'),
          );
          final customAlphaTitleFinder = find.descendant(
            of: customAlphaCard,
            matching: find.text('Project Alpha Target'),
          );
          await tester.scrollUntilVisible(
            customAlphaTitleFinder,
            100,
            scrollable: mainListScrollable,
          );
          await Scrollable.ensureVisible(
            tester.element(customAlphaTitleFinder),
            alignment: 0.5,
          );
          await _boundedPumpAndSettle(tester);

          expect(
            customAlphaTitleFinder.hitTestable(),
            findsOneWidget,
            reason: 'Custom alpha title must be hit-testable before tap',
          );
          await tester.tap(customAlphaTitleFinder);
          await _boundedPumpAndSettle(tester);

          expect(
            find.byType(AppModalSheet),
            findsOneWidget,
            reason: 'Tapping countdown card opens editor draft sheet',
          );

          // Modify draft text in editor
          final editorTextFields = find.descendant(
            of: find.byType(AppModalSheet).last,
            matching: find.byType(TextField),
          );
          expect(editorTextFields, findsAtLeastNWidgets(1));
          final editorTitleField = editorTextFields.first;
          await tester.ensureVisible(editorTitleField);
          await _boundedPumpAndSettle(tester);
          await tester.enterText(
            editorTitleField,
            'Project Alpha Unsaved Draft Title',
          );
          await tester.pump();

          // Cancel draft via visible cancel action button from retained theme test
          final editorCancelBtn = find.descendant(
            of: find.byType(AppModalSheet).last,
            matching: find.widgetWithText(
              TextButton,
              I18n.tr('action.cancel'),
            ),
          );
          expect(
            editorCancelBtn,
            findsOneWidget,
            reason: 'Editor Cancel action button must exist',
          );
          await tester.ensureVisible(editorCancelBtn);
          await _boundedPumpAndSettle(tester);
          await tester.tap(editorCancelBtn);
          await _boundedPumpAndSettle(tester);

          expect(
            find.byType(AppModalSheet),
            findsNothing,
            reason: 'Cancelling editor sheet closes it without saving',
          );

          // Verify provider item and store retain original title and zero writes
          final customAlphaItem = countdownProvider.items.firstWhere(
            (item) => item.id == 'item-authored-custom-alpha',
          );
          expect(
            customAlphaItem.title,
            equals('Project Alpha Target'),
            reason: 'Cancelled draft preserves original title in provider',
          );
          expect(
            store.countdownWrites,
            equals(baselineCountdownWrites),
            reason: 'Opening, modifying, and cancelling draft produces zero storage writes',
          );

          // 6. Pinned status presentation check (deep mutation contracts covered in retained suite)
          // Scroll up (negative delta) from customAlphaCard back to top pinned item
          await tester.scrollUntilVisible(
            generatedCard,
            -80,
            scrollable: mainListScrollable,
          );
          await Scrollable.ensureVisible(
            tester.element(generatedCard),
            alignment: 0.5,
          );
          await _boundedPumpAndSettle(tester);

          final pinnedIconFinder = find.descendant(
            of: generatedCard,
            matching: find.byIcon(Icons.push_pin),
          );
          expect(
            pinnedIconFinder,
            findsOneWidget,
            reason: 'Pinned item displays pin icon in readable card',
          );
          expect(
            store.countdownWrites,
            equals(baselineCountdownWrites),
            reason: 'Reading countdown cards maintains zero persistence mutations',
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
