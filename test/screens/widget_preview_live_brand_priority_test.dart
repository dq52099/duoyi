import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

ValueKey<String> _cardKey(WidgetPreviewKind kind, WidgetDisplayMode mode) =>
    ValueKey('preview_${kind.name}_${mode.name}');

Widget _buildCard(WidgetPreviewKind kind, WidgetDisplayMode mode) {
  final key = _cardKey(kind, mode);
  return switch (kind) {
    WidgetPreviewKind.todo => WidgetPreviewCard.todo(
      key: key,
      displayMode: mode,
      platformOverride: TargetPlatform.iOS,
    ),
    WidgetPreviewKind.calendar => WidgetPreviewCard.calendar(
      key: key,
      displayMode: mode,
      platformOverride: TargetPlatform.iOS,
    ),
    _ => throw UnsupportedError('Unsupported preview kind: $kind'),
  };
}

double _calculateContrastRatio(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

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
      'evidence/screenshots/widget-live-parallel-20261023/preview-brand';

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Missing screenshot boundary for $name');
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Screenshot PNG encoding failed for $name');
      }
      final file = File('$baseDir/$name.png');
      if (file.existsSync()) {
        throw StateError('Preserve existing screenshot: ${file.path}');
      }
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _expectReadableRenderedParagraph(
  WidgetTester tester, {
  required Finder finder,
  required Finder surfaceFinder,
  required GlobalKey boundaryKey,
  required String role,
  double minimumContrast = 4.5,
}) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await _pumpBoundedFrames(tester);

  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
  final style = paragraph.text.style!;
  final foreground = style.foreground?.color ?? style.color!;

  final renderBoundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final surfaceBox = tester.renderObject<RenderBox>(surfaceFinder);

  final surfaceRect = MatrixUtils.transformRect(
    surfaceBox.getTransformTo(renderBoundary),
    Offset.zero & surfaceBox.size,
  );
  final textBounds = MatrixUtils.transformRect(
    paragraph.getTransformTo(renderBoundary),
    Offset.zero & paragraph.size,
  );

  expect(
    surfaceRect.inflate(0.1).contains(textBounds.topLeft),
    isTrue,
    reason: '$role text top-left must be contained within surface',
  );
  expect(
    surfaceRect.inflate(0.1).contains(textBounds.bottomRight),
    isTrue,
    reason: '$role text bottom-right must be contained within surface',
  );

  // Blank interior strip: inside the card surface, past the border, before padding.
  final samplePoint = Offset(surfaceRect.left + 8, textBounds.center.dy);
  expect(
    (Offset.zero & renderBoundary.size).contains(samplePoint),
    isTrue,
    reason:
        '$role sample point $samplePoint must be within rendered viewport boundary',
  );

  final renderedBackground = await tester.runAsync(() async {
    final image = await renderBoundary.toImage(pixelRatio: 1);
    try {
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final x = samplePoint.dx.floor().clamp(0, image.width - 1);
      final y = samplePoint.dy.floor().clamp(0, image.height - 1);
      final offset = (y * image.width + x) * 4;
      return Color.fromARGB(
        255,
        raw.getUint8(offset),
        raw.getUint8(offset + 1),
        raw.getUint8(offset + 2),
      );
    } finally {
      image.dispose();
    }
  });

  expect(
    renderedBackground,
    isNotNull,
    reason: '$role must capture rendered background pixel',
  );

  final ratio = _calculateContrastRatio(foreground, renderedBackground!);
  expect(
    ratio,
    greaterThanOrEqualTo(minimumContrast),
    reason:
        '$role rendered contrast ratio $ratio is below required $minimumContrast:1 (foreground=$foreground, background=$renderedBackground)',
  );
}

Future<void> _verifyNavigationFooter(
  WidgetTester tester, {
  required Finder navFinder,
  required WidgetPreviewKind kind,
  required GlobalKey boundaryKey,
  required String role,
}) async {
  await tester.ensureVisible(navFinder);
  await _pumpBoundedFrames(tester);
  final labels = WidgetUiCopy.previewNavLabels;
  final selectedIndex = switch (kind) {
    WidgetPreviewKind.todo => 0,
    WidgetPreviewKind.focus => 3,
    WidgetPreviewKind.habit => 1,
    _ => 2,
  };

  final renderBoundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final navBox = tester.renderObject<RenderBox>(navFinder);
  final navRect = MatrixUtils.transformRect(
    navBox.getTransformTo(renderBoundary),
    Offset.zero & navBox.size,
  );

  expect(navRect.left, greaterThanOrEqualTo(-0.01), reason: role);
  expect(navRect.top, greaterThanOrEqualTo(-0.01), reason: role);
  expect(
    navRect.right,
    lessThanOrEqualTo(renderBoundary.size.width + 0.01),
    reason: role,
  );
  expect(
    navRect.bottom,
    lessThanOrEqualTo(renderBoundary.size.height + 0.01),
    reason: role,
  );

  // Sample blank strip inside navigation footer padding
  final samplePoint = Offset(navRect.left + 8, navRect.top + 3);
  expect(
    (Offset.zero & renderBoundary.size).contains(samplePoint),
    isTrue,
    reason: '$role footer sample point $samplePoint must be within boundary',
  );

  final renderedNavBackground = await tester.runAsync(() async {
    final image = await renderBoundary.toImage(pixelRatio: 1);
    try {
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final x = samplePoint.dx.floor().clamp(0, image.width - 1);
      final y = samplePoint.dy.floor().clamp(0, image.height - 1);
      final offset = (y * image.width + x) * 4;
      return Color.fromARGB(
        255,
        raw.getUint8(offset),
        raw.getUint8(offset + 1),
        raw.getUint8(offset + 2),
      );
    } finally {
      image.dispose();
    }
  });

  expect(
    renderedNavBackground,
    isNotNull,
    reason: '$role must capture rendered navigation background pixel',
  );

  Color? selectedColor;
  final unselectedColors = <int, Color>{};

  for (var i = 0; i < labels.length; i++) {
    final labelFinder = find.descendant(
      of: navFinder,
      matching: find.text(labels[i]),
    );
    expect(
      labelFinder,
      findsOneWidget,
      reason: '$role: footer label "${labels[i]}" must be rendered',
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: labelFinder, matching: find.byType(RichText)),
    );
    final style = paragraph.text.style!;
    final foreground = style.foreground?.color ?? style.color!;

    final ratio = _calculateContrastRatio(foreground, renderedNavBackground!);
    expect(
      ratio,
      greaterThanOrEqualTo(4.5),
      reason:
          '$role: footer label "${labels[i]}" contrast ratio $ratio is below required 4.5:1 (fg=$foreground, bg=$renderedNavBackground)',
    );

    final semantics = tester.getSemantics(labelFinder);
    if (i == selectedIndex) {
      selectedColor = foreground;
      expect(
        semantics.flagsCollection.isSelected == ui.Tristate.isTrue,
        isTrue,
        reason:
            '$role: selected footer label "${labels[i]}" must have isSelected semantic flag',
      );
    } else {
      unselectedColors[i] = foreground;
      expect(
        semantics.flagsCollection.isSelected == ui.Tristate.isTrue,
        isFalse,
        reason:
            '$role: unselected footer label "${labels[i]}" must not have isSelected semantic flag',
      );
    }
  }

  expect(selectedColor, isNotNull);
  for (final entry in unselectedColors.entries) {
    expect(
      selectedColor,
      isNot(equals(entry.value)),
      reason:
          '$role: selected label "${labels[selectedIndex]}" color ($selectedColor) must visibly differ from unselected label "${labels[entry.key]}" color (${entry.value})',
    );
  }
}

Future<void> _verifyCard(
  WidgetTester tester, {
  required WidgetPreviewKind kind,
  required WidgetDisplayMode mode,
  required String brandId,
  required TextScaler scaler,
  required GlobalKey boundaryKey,
  required ThemeProvider theme,
  Map<String, Size>? recordedSizes,
}) async {
  final key = _cardKey(kind, mode);
  final cardFinder = find.byKey(key);
  expect(cardFinder, findsOneWidget);

  await tester.ensureVisible(cardFinder);
  await _pumpBoundedFrames(tester);

  final role = '$brandId ${kind.name} ${mode.name}';

  // 1. Semantics label contains iOS mode label (never Android grid cell label)
  final expectedSemanticsLabel =
      '${WidgetUiCopy.previewTitle(kind)} ${mode.label}';
  expect(
    find.descendant(
      of: cardFinder,
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == expectedSemanticsLabel,
      ),
    ),
    findsOneWidget,
    reason: '$role: iOS Semantics must use displayMode.label',
  );

  // 2. iOS Title Badge
  final expectedTitle = WidgetUiCopy.previewSampleBadge(
    WidgetUiCopy.previewTitle(kind),
  );
  final titleFinder = find.descendant(
    of: cardFinder,
    matching: find.text(expectedTitle),
  );
  expect(titleFinder, findsOneWidget);

  final titleParagraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: titleFinder, matching: find.byType(RichText)),
  );
  expect(titleParagraph.text.style?.fontSize, 12.0);
  expect(
    titleParagraph.textScaler.scale(12.0),
    closeTo(scaler.scale(12.0), 0.001),
  );

  // 3. iOS Date / Style Subtitle
  final expectedDateLabel = WidgetUiCopy.sampleHeaderDate(mode.label);
  final dateFinder = find.descendant(
    of: cardFinder,
    matching: find.text(expectedDateLabel),
  );
  expect(dateFinder, findsOneWidget);

  final dateParagraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: dateFinder, matching: find.byType(RichText)),
  );
  expect(dateParagraph.text.style?.fontSize, 10.0);
  expect(
    dateParagraph.textScaler.scale(10.0),
    closeTo(scaler.scale(10.0), 0.001),
  );

  // 4. Verify Android grid dimensions do NOT leak into iOS captions
  expect(
    find.descendant(
      of: cardFinder,
      matching: find.textContaining(mode.previewCellLabel),
    ),
    findsNothing,
    reason:
        '$role: iOS captions must name styles without Android grid dimensions (${mode.previewCellLabel})',
  );
  expect(
    find.descendant(
      of: cardFinder,
      matching: find.textContaining(mode.launcherRequestLabel),
    ),
    findsNothing,
    reason:
        '$role: iOS captions must name styles without Android launcher request dimensions (${mode.launcherRequestLabel})',
  );

  // 5. Refresh button
  final refreshFinder = find.descendant(
    of: cardFinder,
    matching: find.text('↻'),
  );
  expect(refreshFinder, findsOneWidget);

  final refreshParagraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: refreshFinder, matching: find.byType(RichText)),
  );
  expect(refreshParagraph.text.style?.fontSize, 11.0);
  expect(
    refreshParagraph.textScaler.scale(11.0),
    closeTo(scaler.scale(11.0), 0.001),
  );

  // 6. Geometry and sizing assertions
  // The outer LayoutBuilder fills the parent width. The painted preview
  // surface inside it owns the display-mode width constraint.
  final surfaceFinder = find.descendant(
    of: cardFinder,
    matching: find.byKey(const ValueKey('widget_preview_surface')),
  );
  expect(surfaceFinder, findsOneWidget);
  final cardSize = tester.getSize(surfaceFinder);
  expect(cardSize.width, greaterThan(0.0));
  expect(cardSize.height, greaterThan(0.0));
  expect(cardSize.width, lessThanOrEqualTo(mode.previewMaxWidth));

  // Navigation footer expectations on iOS:
  final navFinder = find.descendant(
    of: cardFinder,
    matching: find.byKey(const ValueKey('widget_preview_navigation')),
  );
  if (mode == WidgetDisplayMode.compact) {
    expect(
      navFinder,
      findsNothing,
      reason: '$role: iOS compact card has no footer',
    );
  } else if (mode == WidgetDisplayMode.standard &&
      kind == WidgetPreviewKind.todo) {
    expect(
      navFinder,
      findsOneWidget,
      reason: '$role: iOS standard todo card includes navigation footer',
    );
  } else if (mode == WidgetDisplayMode.detailed) {
    expect(navFinder.evaluate().length, lessThanOrEqualTo(1));
  }

  if (navFinder.evaluate().isNotEmpty) {
    await _verifyNavigationFooter(
      tester,
      navFinder: navFinder,
      kind: kind,
      boundaryKey: boundaryKey,
      role: role,
    );
  }

  // 7. Surface decoration and theme responsiveness
  final containerWidget = tester.widget<Container>(surfaceFinder);
  final decoration = containerWidget.decoration as BoxDecoration;

  if (brandId == 'defaultBrand') {
    // In defaultBrand without card skin, borderWidthDp is 0 -> border is null
    expect(
      decoration.border,
      isNull,
      reason: '$role: defaultBrand surface has no border',
    );
  } else if (brandId == 'liquidGlass') {
    // In liquidGlass, borderWidthDp is 1 -> border is Border.all with glass highlight
    expect(
      decoration.border,
      isNotNull,
      reason: '$role: liquidGlass surface has highlight border',
    );
    final border = decoration.border as Border;
    expect(border.top.width, closeTo(1.0, 0.001));
  }

  // 8. Contrast and readability verification (Mandatory, skip-free >= 4.5:1 against rendered adjacent blank surface)
  await _expectReadableRenderedParagraph(
    tester,
    finder: titleFinder,
    surfaceFinder: surfaceFinder,
    boundaryKey: boundaryKey,
    role: '$role title',
    minimumContrast: 4.5,
  );

  await _expectReadableRenderedParagraph(
    tester,
    finder: dateFinder,
    surfaceFinder: surfaceFinder,
    boundaryKey: boundaryKey,
    role: '$role subtitle',
    minimumContrast: 4.5,
  );

  // 9. Record or verify geometry stability across transitions
  final sizeKey = '${kind.name}_${mode.name}';
  if (recordedSizes != null) {
    if (recordedSizes.containsKey(sizeKey)) {
      final previousSize = recordedSizes[sizeKey]!;
      expect(
        cardSize.width,
        equals(previousSize.width),
        reason: '$role: Width must be preserved across brand switch',
      );
      expect(
        (cardSize.height - previousSize.height).abs(),
        lessThanOrEqualTo(4.0),
        reason:
            '$role: Height must remain stable across brand switch (within 4dp tolerance)',
      );
    } else {
      recordedSizes[sizeKey] = cardSize;
    }
  }
}

void main() {
  final initialLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialLocale));

  const scenarios = [
    (
      name: 'zh-portrait-200',
      locale: AppLocale.zh,
      size: Size(390, 844),
      scaler: TextScaler.linear(2.0),
    ),
    (
      name: 'zh-landscape-200',
      locale: AppLocale.zh,
      size: Size(844, 390),
      scaler: TextScaler.linear(2.0),
    ),
    (
      name: 'en-portrait-200',
      locale: AppLocale.en,
      size: Size(390, 844),
      scaler: TextScaler.linear(2.0),
    ),
    (
      name: 'en-landscape-200',
      locale: AppLocale.en,
      size: Size(844, 390),
      scaler: TextScaler.linear(2.0),
    ),
  ];

  for (final scenario in scenarios) {
    testWidgets('preview live brand switch defaultBrand <-> liquidGlass ${scenario.name}', (
      tester,
    ) async {
      final originalShadows = debugDisableShadows;
      try {
        debugDisableShadows = false;

        SharedPreferences.setMockInitialValues({
          // Calendar previews use the default Monday week start. Fix the
          // synthetic app timezone so hydration never calls a device plugin.
          'pref_app_timezone_mode': 'fixed',
          'pref_app_timezone_iana': 'Asia/Shanghai',
          'theme_shop_state': jsonEncode({
            'activeBrand': 'defaultBrand',
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
            'activeWidgetBackgroundId': ThemeProvider.widgetFollowThemeId,
          }),
          'active_brand': 'defaultBrand',
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        });

        final originalLocale = I18n.current;
        I18n.setLocale(scenario.locale);

        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        addTearDown(() {
          I18n.setLocale(originalLocale);
        });

        final theme = ThemeProvider();
        late final PreferencesProvider preferences;
        await tester.runAsync(() async {
          // Its write-tail Future must be created in the same real async
          // zone that awaits hydration, rather than the fake test zone.
          preferences = PreferencesProvider();
          await theme.loadFromStorage().timeout(const Duration(seconds: 5));
          await preferences.loadFromStorage().timeout(
            const Duration(seconds: 5),
          );
          await loadWeeklyReviewScreenshotFonts().timeout(
            const Duration(seconds: 5),
          );
        });
        expect(tester.takeException(), isNull);

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          theme.dispose();
          preferences.dispose();
        });

        final boundaryKey = GlobalKey();
        final recordedSizes = <String, Size>{};

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<PreferencesProvider>.value(
                value: preferences,
              ),
            ],
            child: Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                return ValueListenableBuilder<AppLocale>(
                  valueListenable: I18n.localeListenable,
                  builder: (context, locale, _) {
                    return MaterialApp(
                      locale: Locale(locale == AppLocale.en ? 'en' : 'zh'),
                      supportedLocales: const [Locale('en'), Locale('zh')],
                      localizationsDelegates:
                          GlobalMaterialLocalizations.delegates,
                      theme: themeProvider.brand.theme,
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: scenario.scaler),
                        child: RepaintBoundary(key: boundaryKey, child: child!),
                      ),
                      home: BrandRouteSurface(
                        remountOnLocaleChange: false,
                        child: Scaffold(
                          backgroundColor: Colors.transparent,
                          body: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final kind in [
                                  WidgetPreviewKind.todo,
                                  WidgetPreviewKind.calendar,
                                ])
                                  for (final mode
                                      in WidgetDisplayMode.values) ...[
                                    _buildCard(kind, mode),
                                    const SizedBox(height: 12),
                                  ],
                              ],
                            ),
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

        await _pumpBoundedFrames(tester);
        expect(tester.takeException(), isNull);

        // --- Retained Element & Route Identity Setup ---
        final initialElements = <String, Element>{};
        for (final kind in [
          WidgetPreviewKind.todo,
          WidgetPreviewKind.calendar,
        ]) {
          for (final mode in WidgetDisplayMode.values) {
            final key = _cardKey(kind, mode);
            final cardFinder = find.byKey(key);
            expect(cardFinder, findsOneWidget);
            initialElements['${kind.name}_${mode.name}'] = tester.element(
              cardFinder,
            );
          }
        }
        final anchorKey = _cardKey(
          WidgetPreviewKind.todo,
          WidgetDisplayMode.compact,
        );
        final initialRoute = ModalRoute.of(
          tester.element(find.byKey(anchorKey)),
        );
        expect(initialRoute, isNotNull, reason: 'Mounted route must exist');

        // --- PHASE 1: Initial defaultBrand ---
        expect(theme.brand.id, 'defaultBrand');
        expect(theme.activeWidgetBackgroundBrand.id, 'defaultBrand');

        for (final kind in [
          WidgetPreviewKind.todo,
          WidgetPreviewKind.calendar,
        ]) {
          for (final mode in WidgetDisplayMode.values) {
            await _verifyCard(
              tester,
              kind: kind,
              mode: mode,
              brandId: 'defaultBrand',
              scaler: scenario.scaler,
              boundaryKey: boundaryKey,
              theme: theme,
              recordedSizes: recordedSizes,
            );
          }
        }

        // Capture affected card (todo standard) footer before final scrolled calendar
        await tester.ensureVisible(
          find.descendant(
            of: find.byKey(
              _cardKey(WidgetPreviewKind.todo, WidgetDisplayMode.standard),
            ),
            matching: find.byKey(const ValueKey('widget_preview_navigation')),
          ),
        );
        await _pumpBoundedFrames(tester);
        await _captureScopeScreenshot(
          tester,
          boundaryKey,
          'widget-preview-live-brand-${scenario.name}-01-defaultBrand-todo',
        );
        await tester.ensureVisible(
          find.descendant(
            of: find.byKey(
              _cardKey(WidgetPreviewKind.calendar, WidgetDisplayMode.detailed),
            ),
            matching: find.byKey(const ValueKey('widget_preview_navigation')),
          ),
        );
        await _pumpBoundedFrames(tester);
        await _captureScopeScreenshot(
          tester,
          boundaryKey,
          'widget-preview-live-brand-${scenario.name}-01-defaultBrand',
        );

        // --- PHASE 2: Live switch to liquidGlass ---
        await tester.runAsync(() async {
          final switched = await theme.setBrand('liquidGlass');
          expect(switched, isTrue);
        });
        await _pumpBoundedFrames(tester);
        expect(tester.takeException(), isNull);

        expect(theme.brand.id, 'liquidGlass');
        expect(theme.activeWidgetBackgroundBrand.id, 'liquidGlass');
        final prefsAfterSwitch = await SharedPreferences.getInstance();
        expect(prefsAfterSwitch.getString('active_brand'), 'liquidGlass');

        // Assert retained Element identity and mounted route identity
        for (final kind in [
          WidgetPreviewKind.todo,
          WidgetPreviewKind.calendar,
        ]) {
          for (final mode in WidgetDisplayMode.values) {
            final key = _cardKey(kind, mode);
            final currentElement = tester.element(find.byKey(key));
            expect(
              currentElement,
              same(initialElements['${kind.name}_${mode.name}']),
              reason:
                  'WidgetPreviewCard ${kind.name} ${mode.name} Element must be retained after liquidGlass switch',
            );
          }
        }
        final routeAfterSwitch = ModalRoute.of(
          tester.element(find.byKey(anchorKey)),
        );
        expect(
          routeAfterSwitch,
          same(initialRoute),
          reason:
              'Mounted route identity must be retained after liquidGlass switch',
        );

        for (final kind in [
          WidgetPreviewKind.todo,
          WidgetPreviewKind.calendar,
        ]) {
          for (final mode in WidgetDisplayMode.values) {
            await _verifyCard(
              tester,
              kind: kind,
              mode: mode,
              brandId: 'liquidGlass',
              scaler: scenario.scaler,
              boundaryKey: boundaryKey,
              theme: theme,
              recordedSizes: recordedSizes,
            );
          }
        }

        // Capture affected card (todo standard) footer before final scrolled calendar
        await tester.ensureVisible(
          find.descendant(
            of: find.byKey(
              _cardKey(WidgetPreviewKind.todo, WidgetDisplayMode.standard),
            ),
            matching: find.byKey(const ValueKey('widget_preview_navigation')),
          ),
        );
        await _pumpBoundedFrames(tester);
        await _captureScopeScreenshot(
          tester,
          boundaryKey,
          'widget-preview-live-brand-${scenario.name}-02-liquidGlass-todo',
        );
        await tester.ensureVisible(
          find.descendant(
            of: find.byKey(
              _cardKey(WidgetPreviewKind.calendar, WidgetDisplayMode.detailed),
            ),
            matching: find.byKey(const ValueKey('widget_preview_navigation')),
          ),
        );
        await _pumpBoundedFrames(tester);
        await _captureScopeScreenshot(
          tester,
          boundaryKey,
          'widget-preview-live-brand-${scenario.name}-02-liquidGlass',
        );

        // --- PHASE 3: Live revert to defaultBrand ---
        await tester.runAsync(() async {
          final reverted = await theme.setBrand('defaultBrand');
          expect(reverted, isTrue);
        });
        await _pumpBoundedFrames(tester);
        expect(tester.takeException(), isNull);

        expect(theme.brand.id, 'defaultBrand');
        expect(theme.activeWidgetBackgroundBrand.id, 'defaultBrand');
        final prefsAfterRevert = await SharedPreferences.getInstance();
        expect(prefsAfterRevert.getString('active_brand'), 'defaultBrand');

        // Assert retained Element identity and mounted route identity
        for (final kind in [
          WidgetPreviewKind.todo,
          WidgetPreviewKind.calendar,
        ]) {
          for (final mode in WidgetDisplayMode.values) {
            final key = _cardKey(kind, mode);
            final currentElement = tester.element(find.byKey(key));
            expect(
              currentElement,
              same(initialElements['${kind.name}_${mode.name}']),
              reason:
                  'WidgetPreviewCard ${kind.name} ${mode.name} Element must be retained after reverting to defaultBrand',
            );
          }
        }
        final routeAfterRevert = ModalRoute.of(
          tester.element(find.byKey(anchorKey)),
        );
        expect(
          routeAfterRevert,
          same(initialRoute),
          reason:
              'Mounted route identity must be retained after reverting to defaultBrand',
        );

        for (final kind in [
          WidgetPreviewKind.todo,
          WidgetPreviewKind.calendar,
        ]) {
          for (final mode in WidgetDisplayMode.values) {
            await _verifyCard(
              tester,
              kind: kind,
              mode: mode,
              brandId: 'defaultBrand',
              scaler: scenario.scaler,
              boundaryKey: boundaryKey,
              theme: theme,
              recordedSizes: recordedSizes,
            );
          }
        }

        // Capture affected card (todo standard) footer before final scrolled calendar
        await tester.ensureVisible(
          find.descendant(
            of: find.byKey(
              _cardKey(WidgetPreviewKind.todo, WidgetDisplayMode.standard),
            ),
            matching: find.byKey(const ValueKey('widget_preview_navigation')),
          ),
        );
        await _pumpBoundedFrames(tester);
        await _captureScopeScreenshot(
          tester,
          boundaryKey,
          'widget-preview-live-brand-${scenario.name}-03-reverted-defaultBrand-todo',
        );
        await tester.ensureVisible(
          find.descendant(
            of: find.byKey(
              _cardKey(WidgetPreviewKind.calendar, WidgetDisplayMode.detailed),
            ),
            matching: find.byKey(const ValueKey('widget_preview_navigation')),
          ),
        );
        await _pumpBoundedFrames(tester);
        await _captureScopeScreenshot(
          tester,
          boundaryKey,
          'widget-preview-live-brand-${scenario.name}-03-reverted-defaultBrand',
        );

        expect(tester.takeException(), isNull);
      } finally {
        debugDisableShadows = originalShadows;
      }
    });
  }
}
