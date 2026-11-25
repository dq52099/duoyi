import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/theme_picker_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

class ThemePickerPriorityProbe extends RouteRenderProbe {
  ThemePickerPriorityProbe(super.tester, super.boundary, super.name);

  @override
  Future<void> capture(String stage) async {
    await super.capture(stage);
    final explicitDir =
        Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
    if (explicitDir != null &&
        explicitDir.isNotEmpty &&
        Platform.environment['DUOYI_SECONDARY_SCREENSHOTS'] == null) {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          final file = File('$explicitDir/$name-$stage.png');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(data.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
  }
}

String styleDescription(BrandStyle style) => switch (style) {
  BrandStyle.defaultBrand => I18n.tr('theme.style.default.description'),
  BrandStyle.re0 => I18n.tr('theme.style.re0.description'),
  BrandStyle.genshin => I18n.tr('theme.style.genshin.description'),
  BrandStyle.starRail => I18n.tr('theme.style.star_rail.description'),
  BrandStyle.wuthering => I18n.tr('theme.style.wuthering.description'),
  BrandStyle.zzz => I18n.tr('theme.style.zzz.description'),
  BrandStyle.yanyun => I18n.tr('theme.style.yanyun.description'),
  BrandStyle.botw => I18n.tr('theme.style.botw.description'),
  BrandStyle.liquidGlass => I18n.tr('theme.style.liquid_glass.description'),
};

Finder brandCardFinder(String brandId) {
  return find.ancestor(
    of: find.byKey(ValueKey('theme_card_bg_$brandId')),
    matching: find.byType(AppSurfaceCard),
  );
}

Finder summaryCardFinder() {
  return find.byWidgetPredicate(
    (widget) => widget is AppSurfaceCard && widget.gradient != null,
  );
}

Future<List<int>> _samplePoints(
  WidgetTester tester,
  GlobalKey boundaryKey,
  List<Offset> points,
) async {
  return (await tester.runAsync(() async {
    final render =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    try {
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      return [
        for (final point in points)
          raw.getUint32(
            (point.dy.floor() * image.width + point.dx.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

void _verifyScalerFidelity(
  WidgetTester tester,
  Finder titleFinder,
  Finder descFinder,
  RouteRenderProbe probe,
  String stage,
  TextScaler scenarioScaler,
  double scale,
  bool isNonlinear,
) {
  final titleParagraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: titleFinder, matching: find.byType(RichText)),
  );
  final descParagraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: descFinder, matching: find.byType(RichText)),
  );
  // AppSecondaryControlTheme in BrandRouteSurface overrides textTheme:
  // titleMedium -> controlText (fontSize: 12.0)
  // bodySmall   -> labelText   (fontSize: 11.0)
  const nominalTitle = 12.0;
  const nominalDesc = 11.0;

  expect(
    titleParagraph.text.style!.fontSize,
    equals(nominalTitle),
    reason:
        '$stage title nominal font size mismatch (expected AppSecondaryControlTheme titleMedium $nominalTitle)',
  );
  expect(
    descParagraph.text.style!.fontSize,
    equals(nominalDesc),
    reason:
        '$stage desc nominal font size mismatch (expected AppSecondaryControlTheme bodySmall $nominalDesc)',
  );

  final expectedTitleScale = scenarioScaler.scale(nominalTitle);
  final expectedDescScale = scenarioScaler.scale(nominalDesc);

  expect(
    titleParagraph.textScaler.scale(nominalTitle),
    equals(expectedTitleScale),
    reason:
        '$stage title textScaler does not match scenario scaler expectation',
  );
  expect(
    descParagraph.textScaler.scale(nominalDesc),
    equals(expectedDescScale),
    reason: '$stage desc textScaler does not match scenario scaler expectation',
  );

  probe.rows.add({
    'role': '$stage scaler fidelity',
    'nominalTitleFontSize': nominalTitle,
    'scaledTitleFontSize': expectedTitleScale,
    'nominalDescFontSize': nominalDesc,
    'scaledDescFontSize': expectedDescScale,
    'scalerType': isNonlinear ? 'nonlinear' : 'linear',
    'scaleFactor': scale,
  });
}

void _verifyIndicatorNotOverflow(
  WidgetTester tester,
  Finder cardFinder,
  IconData icon,
) {
  expect(cardFinder, findsOneWidget);
  final cardRect = tester.getRect(cardFinder);
  final iconFinder = find.descendant(
    of: cardFinder,
    matching: find.byIcon(icon),
  );
  expect(iconFinder, findsOneWidget);
  final iconRect = tester.getRect(iconFinder);
  expect(
    iconRect.right,
    lessThanOrEqualTo(cardRect.right + 0.1),
    reason: 'selection icon right bound exceeds card',
  );
  expect(
    iconRect.left,
    greaterThanOrEqualTo(cardRect.left - 0.1),
    reason: 'selection icon left bound exceeds card',
  );
  expect(
    iconRect.top,
    greaterThanOrEqualTo(cardRect.top - 0.1),
    reason: 'selection icon top bound exceeds card',
  );
  expect(
    iconRect.bottom,
    lessThanOrEqualTo(cardRect.bottom + 0.1),
    reason: 'selection icon bottom bound exceeds card',
  );
}

Future<void> _verifyLockedRe0Card(
  WidgetTester tester,
  ThemeProvider theme,
  RouteRenderProbe probe,
) async {
  final re0Card = brandCardFinder('re0');
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(re0Card, 200, scrollable: scrollable);
  await Scrollable.ensureVisible(tester.element(re0Card), alignment: 0.3);
  await tester.pumpAndSettle();

  expect(re0Card, findsOneWidget);
  final cardRect = tester.getRect(re0Card);

  final lockIcon = find.descendant(
    of: re0Card,
    matching: find.byIcon(Icons.lock_outline),
  );
  expect(lockIcon, findsOneWidget);
  final lockRect = tester.getRect(lockIcon);
  expect(lockRect.right, lessThanOrEqualTo(cardRect.right + 0.1));
  expect(lockRect.left, greaterThanOrEqualTo(cardRect.left - 0.1));
  expect(lockRect.top, greaterThanOrEqualTo(cardRect.top - 0.1));
  expect(lockRect.bottom, lessThanOrEqualTo(cardRect.bottom + 0.1));

  final expectedCost = theme.brandCost('re0');
  final priceFinder = find.descendant(
    of: re0Card,
    matching: find.text(DataSettingsUiCopy.coinCost(expectedCost)),
  );
  expect(priceFinder, findsOneWidget);
  final priceRect = tester.getRect(priceFinder);
  expect(priceRect.right, lessThanOrEqualTo(cardRect.right + 0.1));
  expect(priceRect.left, greaterThanOrEqualTo(cardRect.left - 0.1));
  expect(priceRect.top, greaterThanOrEqualTo(cardRect.top - 0.1));
  expect(priceRect.bottom, lessThanOrEqualTo(cardRect.bottom + 0.1));

  probe.rows.add({
    'role': 're0 locked price indicator',
    'cost': expectedCost,
    'lockRect': [lockRect.left, lockRect.top, lockRect.width, lockRect.height],
    'priceRect': [
      priceRect.left,
      priceRect.top,
      priceRect.width,
      priceRect.height,
    ],
  });
}

void _verifySnackbarVisual(
  WidgetTester tester,
  Finder snackbarFinder,
  Finder snackMsgFinder,
  RouteRenderProbe probe,
  String role,
) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: snackMsgFinder, matching: find.byType(RichText)),
  );
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role exceeded max lines',
  );
  expect(
    paragraph.textSize.width,
    lessThanOrEqualTo(paragraph.size.width + 0.1),
    reason: '$role text width overflow',
  );
  expect(
    paragraph.textSize.height,
    lessThanOrEqualTo(paragraph.size.height + 0.1),
    reason: '$role text height overflow',
  );

  final element = tester.element(snackMsgFinder);
  final foreground =
      paragraph.text.style?.color ??
      DefaultTextStyle.of(element).style.color ??
      Colors.white;
  final snackWidget = tester.widget<SnackBar>(snackbarFinder);
  final background =
      snackWidget.backgroundColor ??
      Theme.of(element).snackBarTheme.backgroundColor ??
      const Color(0xFF322F35);
  final contrast = appContrastRatio(
    Color.alphaBlend(foreground, background),
    background,
  );
  expect(
    contrast,
    greaterThanOrEqualTo(4.5),
    reason: '$role contrast ratio $contrast below 4.5',
  );

  probe.rows.add({
    'role': role,
    'text': (tester.widget(snackMsgFinder) as Text).data,
    'foregroundARGB': foreground.toARGB32(),
    'backgroundARGB': background.toARGB32(),
    'contrast': contrast,
  });
}

Future<void> _tapBrandOptionAndSettle(
  WidgetTester tester,
  Finder cardFinder,
  ThemeProvider theme,
  String expectedBrandId,
) async {
  await tester.tap(cardFinder);
  await tester.pump();

  var settled = false;
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    if (theme.brand.id == expectedBrandId &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      settled = true;
      break;
    }
  }

  expect(
    settled,
    isTrue,
    reason:
        'Theme brand switch to $expectedBrandId timed out or _shopBusy progress indicator remained mounted',
  );
  expect(
    theme.brand.id,
    equals(expectedBrandId),
    reason: 'Theme brand did not switch to $expectedBrandId after UI tap',
  );
  expect(
    find.byType(LinearProgressIndicator),
    findsNothing,
    reason: 'LinearProgressIndicator did not dismiss after UI tap',
  );

  await tester.runAsync(() async {
    await AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5));
  });

  await tester.pumpAndSettle();
}

void main() {
  final initialLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialLocale));

  const samplePoints = [
    Offset(2, 844 * 0.4),
    Offset(320 - 3, 844 * 0.65),
    Offset(2, 844 - 24),
  ];

  const scenarios = [
    (
      locale: AppLocale.zh,
      scaleName: 'linear20',
      scale: 2.0,
      isNonlinear: false,
      label: 'zh narrow 320 linear 2.0',
    ),
    (
      locale: AppLocale.zh,
      scaleName: 'nonlinear',
      scale: -1.0,
      isNonlinear: true,
      label: 'zh narrow 320 nonlinear',
    ),
    (
      locale: AppLocale.en,
      scaleName: 'linear20',
      scale: 2.0,
      isNonlinear: false,
      label: 'en narrow 320 linear 2.0',
    ),
    (
      locale: AppLocale.en,
      scaleName: 'nonlinear',
      scale: -1.0,
      isNonlinear: true,
      label: 'en narrow 320 nonlinear',
    ),
  ];

  for (final scenario in scenarios) {
    testWidgets(
      'priority live brand switch defaultBrand <-> liquidGlass ${scenario.label}',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'theme_shop_state': jsonEncode({
            'activeBrand': 'defaultBrand',
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'active_brand': 'defaultBrand',
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        });
        I18n.setLocale(scenario.locale);
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final originalShadows = debugDisableShadows;
        try {
          debugDisableShadows = false;

          final theme = ThemeProvider();
          final auth = AuthProvider();
          final rewards = AchievementProvider();

          await tester.runAsync(() async {
            await theme.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });

          addTearDown(() async {
            await tester.runAsync(() async {
              await AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              );
              await Future<void>.delayed(const Duration(milliseconds: 20));
            });
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            auth.dispose();
            rewards.dispose();
            theme.dispose();
          });

          expect(theme.brand.id, 'defaultBrand');
          expect(theme.isBrandUnlocked('liquidGlass'), isTrue);

          final TextScaler scenarioScaler = scenario.isNonlinear
              ? const RouteProbeNonlinearScaler()
              : TextScaler.linear(scenario.scale);

          final boundary = GlobalKey();

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<AchievementProvider>.value(
                  value: rewards,
                ),
              ],
              child: AnimatedBuilder(
                animation: Listenable.merge([theme, I18n.localeListenable]),
                builder: (context, _) => MaterialApp(
                  locale: Locale(I18n.current == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: scenarioScaler),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: const BrandRouteSurface(child: ThemePickerScreen()),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final pickerFinder = find.byType(ThemePickerScreen);
          expect(pickerFinder, findsOneWidget);
          final retainedState = tester.state<State<ThemePickerScreen>>(
            pickerFinder,
          );
          final retainedRoute = ModalRoute.of(tester.element(pickerFinder));
          expect(retainedRoute, isNotNull);

          final scrollable = find.byType(Scrollable).first;
          expect(scrollable, findsOneWidget);
          final retainedScrollState = tester.state<ScrollableState>(scrollable);
          final retainedScrollController =
              retainedScrollState.widget.controller;
          expect(retainedScrollController, isNotNull);
          expect(
            retainedScrollController!.positions,
            contains(same(retainedScrollState.position)),
          );

          final probe = ThemePickerPriorityProbe(
            tester,
            boundary,
            'live-priority-${scenario.locale.name}-narrow320-${scenario.scaleName}',
          );

          // 1. Initial State: defaultBrand
          expect(theme.brand.id, 'defaultBrand');
          final initialScaffold = tester.widget<Scaffold>(
            find.byType(Scaffold),
          );
          expect(
            initialScaffold.backgroundColor,
            isNot(equals(Colors.transparent)),
            reason: 'defaultBrand scaffold background should be opaque',
          );

          final actualDefaultInitialPixels = await _samplePoints(
            tester,
            boundary,
            samplePoints,
          );
          for (var i = 0; i < samplePoints.length; i++) {
            probe.rows.add({
              'role': 'initial defaultBrand margin $i sample',
              'rgba': actualDefaultInitialPixels[i],
            });
          }

          // Summary card completeness for initial defaultBrand
          final summaryInitialCard = summaryCardFinder();
          expect(summaryInitialCard, findsOneWidget);
          final summaryInitialTitle = find.descendant(
            of: summaryInitialCard,
            matching: find.text(AppBrands.defaultBrand.localizedName),
          );
          final summaryInitialDesc = find.descendant(
            of: summaryInitialCard,
            matching: find.text(styleDescription(BrandStyle.defaultBrand)),
          );
          await probe.text(
            summaryInitialTitle,
            role: 'initial summary defaultBrand title',
          );
          await probe.text(
            summaryInitialDesc,
            role: 'initial summary defaultBrand description',
          );

          // Visible brand names & descriptions check on defaultBrand card
          final defaultCard = brandCardFinder('defaultBrand');
          await probe.reveal(defaultCard);
          expect(
            find.descendant(
              of: defaultCard,
              matching: find.byIcon(Icons.check_circle),
            ),
            findsOneWidget,
          );

          final defaultTitle = find.descendant(
            of: defaultCard,
            matching: find.text(AppBrands.defaultBrand.localizedName),
          );
          final defaultDesc = find.descendant(
            of: defaultCard,
            matching: find.text(styleDescription(BrandStyle.defaultBrand)),
          );
          await probe.text(defaultTitle, role: 'initial defaultBrand title');
          await probe.text(
            defaultDesc,
            role: 'initial defaultBrand description',
          );
          _verifyScalerFidelity(
            tester,
            defaultTitle,
            defaultDesc,
            probe,
            'initial defaultBrand',
            scenarioScaler,
            scenario.scale,
            scenario.isNonlinear,
          );
          _verifyIndicatorNotOverflow(tester, defaultCard, Icons.check_circle);

          // Explicit reachability & assertion on locked re0 card (Defect 2)
          await _verifyLockedRe0Card(tester, theme, probe);

          // Return to liquidGlass card location and assert state
          final glassCard = brandCardFinder('liquidGlass');
          await tester.scrollUntilVisible(
            glassCard,
            300,
            scrollable: scrollable,
          );
          await Scrollable.ensureVisible(
            tester.element(glassCard),
            alignment: 0.3,
          );
          await tester.pumpAndSettle();
          expect(glassCard, findsOneWidget);

          expect(
            find.descendant(
              of: glassCard,
              matching: find.byIcon(Icons.radio_button_unchecked),
            ),
            findsOneWidget,
          );

          final glassTitle = find.descendant(
            of: glassCard,
            matching: find.text(AppBrands.liquidGlass.localizedName),
          );
          final glassDesc = find.descendant(
            of: glassCard,
            matching: find.text(styleDescription(BrandStyle.liquidGlass)),
          );
          await probe.text(glassTitle, role: 'initial liquidGlass title');
          await probe.text(glassDesc, role: 'initial liquidGlass description');
          _verifyScalerFidelity(
            tester,
            glassTitle,
            glassDesc,
            probe,
            'initial liquidGlass',
            scenarioScaler,
            scenario.scale,
            scenario.isNonlinear,
          );
          _verifyIndicatorNotOverflow(
            tester,
            glassCard,
            Icons.radio_button_unchecked,
          );

          await probe.capture('01-initial-defaultBrand');

          // 2. User clicks liquidGlass card
          final glassRect = tester.getRect(glassCard);
          expect(
            glassRect.width,
            greaterThanOrEqualTo(44.0 - 1e-7),
            reason: 'liquidGlass card target width',
          );
          expect(
            glassRect.height,
            greaterThanOrEqualTo(44.0 - 1e-7),
            reason: 'liquidGlass card target height',
          );
          expect(glassCard.hitTestable(), findsOneWidget);

          await _tapBrandOptionAndSettle(
            tester,
            glassCard,
            theme,
            'liquidGlass',
          );

          // Check SnackBar immediately while freshly displayed (before scroll/time elapse)
          final expectedGlassFeedback = DataSettingsUiCopy.themeApplied(
            AppBrands.liquidGlass.localizedName,
          );
          final snackbar = find.byType(SnackBar);
          expect(snackbar, findsOneWidget);
          final snackMsg = find.descendant(
            of: snackbar,
            matching: find.text(expectedGlassFeedback),
          );
          expect(snackMsg, findsOneWidget);
          _verifySnackbarVisual(
            tester,
            snackbar,
            snackMsg,
            probe,
            'liquidGlass feedback',
          );

          // Confirm ThemeProvider changed to liquidGlass
          expect(theme.brand.id, 'liquidGlass');

          // Confirm MaterialApp theme updated to liquidGlass theme
          final activeCs = Theme.of(tester.element(pickerFinder)).colorScheme;
          expect(
            activeCs.primary,
            equals(AppBrands.liquidGlass.theme.colorScheme.primary),
            reason: 'MaterialApp theme did not update on notifyListeners',
          );

          // Confirm real persistence in SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs.getString('active_brand'),
            'liquidGlass',
            reason: 'real persistence active_brand key mismatch',
          );
          final savedState =
              jsonDecode(prefs.getString('theme_shop_state')!)
                  as Map<String, dynamic>;
          expect(
            savedState['activeBrand'],
            'liquidGlass',
            reason: 'real persistence theme_shop_state activeBrand mismatch',
          );
          expect(
            (savedState['unlockedBrandIds'] as List).cast<String>(),
            contains('liquidGlass'),
          );

          // Confirm state and route retained across notify and rebuild
          expect(
            tester.state<State<ThemePickerScreen>>(pickerFinder),
            same(retainedState),
            reason: 'ThemePickerScreen state was remounted or lost',
          );
          expect(
            ModalRoute.of(tester.element(pickerFinder)),
            same(retainedRoute),
            reason: 'ThemePickerScreen route changed unexpectedly',
          );

          // Confirm glass backdrop transparency
          final glassScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
          expect(
            glassScaffold.backgroundColor,
            equals(Colors.transparent),
            reason:
                'liquidGlass scaffold must be transparent for glass backdrop',
          );

          ScaffoldMessenger.of(tester.element(pickerFinder)).clearSnackBars();
          await tester.pumpAndSettle();

          final actualGlassPixels = await _samplePoints(
            tester,
            boundary,
            samplePoints,
          );
          for (var i = 0; i < samplePoints.length; i++) {
            probe.rows.add({
              'role': 'applied liquidGlass margin $i sample',
              'rgba': actualGlassPixels[i],
            });
          }

          // Selection indicators updated
          expect(
            find.descendant(
              of: glassCard,
              matching: find.byIcon(Icons.check_circle),
            ),
            findsOneWidget,
          );
          _verifyIndicatorNotOverflow(tester, glassCard, Icons.check_circle);

          // Summary card completeness for applied liquidGlass (Defect 3)
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();
          final summaryGlassCard = summaryCardFinder();
          expect(summaryGlassCard, findsOneWidget);
          final summaryGlassTitle = find.descendant(
            of: summaryGlassCard,
            matching: find.text(AppBrands.liquidGlass.localizedName),
          );
          final summaryGlassDesc = find.descendant(
            of: summaryGlassCard,
            matching: find.text(styleDescription(BrandStyle.liquidGlass)),
          );
          await probe.text(
            summaryGlassTitle,
            role: 'liquidGlass summary title',
          );
          await probe.text(
            summaryGlassDesc,
            role: 'liquidGlass summary description',
          );

          await probe.capture('02-applied-liquidGlass');

          // 3. User clicks defaultBrand card to switch back
          await probe.reveal(defaultCard);
          final defaultRect = tester.getRect(defaultCard);
          expect(
            defaultRect.width,
            greaterThanOrEqualTo(44.0 - 1e-7),
            reason: 'defaultBrand card target width',
          );
          expect(
            defaultRect.height,
            greaterThanOrEqualTo(44.0 - 1e-7),
            reason: 'defaultBrand card target height',
          );
          expect(defaultCard.hitTestable(), findsOneWidget);

          await _tapBrandOptionAndSettle(
            tester,
            defaultCard,
            theme,
            'defaultBrand',
          );

          // Check SnackBar immediately while freshly displayed (before scroll/time elapse)
          final expectedDefaultFeedback = DataSettingsUiCopy.themeApplied(
            AppBrands.defaultBrand.localizedName,
          );
          final revertedSnackbar = find.byType(SnackBar);
          expect(revertedSnackbar, findsOneWidget);
          final revertedSnackMsg = find.descendant(
            of: revertedSnackbar,
            matching: find.text(expectedDefaultFeedback),
          );
          expect(revertedSnackMsg, findsOneWidget);
          _verifySnackbarVisual(
            tester,
            revertedSnackbar,
            revertedSnackMsg,
            probe,
            'defaultBrand feedback',
          );

          // Confirm ThemeProvider reverted to defaultBrand
          expect(theme.brand.id, 'defaultBrand');

          // Confirm MaterialApp theme updated back to defaultBrand
          final revertedCs = Theme.of(tester.element(pickerFinder)).colorScheme;
          expect(
            revertedCs.primary,
            equals(AppBrands.defaultBrand.theme.colorScheme.primary),
            reason: 'MaterialApp theme did not revert to defaultBrand',
          );

          // Confirm real persistence reverted in SharedPreferences
          expect(
            prefs.getString('active_brand'),
            'defaultBrand',
            reason: 'active_brand did not revert to defaultBrand',
          );
          final revertedState =
              jsonDecode(prefs.getString('theme_shop_state')!)
                  as Map<String, dynamic>;
          expect(
            revertedState['activeBrand'],
            'defaultBrand',
            reason:
                'theme_shop_state activeBrand did not revert to defaultBrand',
          );

          // Confirm state and route retained across second switch
          expect(
            tester.state<State<ThemePickerScreen>>(pickerFinder),
            same(retainedState),
            reason: 'ThemePickerScreen state was remounted during revert',
          );
          expect(
            ModalRoute.of(tester.element(pickerFinder)),
            same(retainedRoute),
            reason: 'ThemePickerScreen route changed during revert',
          );

          // Confirm Scaffold background restored to opaque
          final revertedScaffold = tester.widget<Scaffold>(
            find.byType(Scaffold),
          );
          expect(
            revertedScaffold.backgroundColor,
            isNot(equals(Colors.transparent)),
            reason: 'defaultBrand scaffold background should be opaque again',
          );

          ScaffoldMessenger.of(tester.element(pickerFinder)).clearSnackBars();
          await tester.pumpAndSettle();

          final actualDefaultRevertedPixels = await _samplePoints(
            tester,
            boundary,
            samplePoints,
          );

          // Selection indicators restored
          expect(
            find.descendant(
              of: defaultCard,
              matching: find.byIcon(Icons.check_circle),
            ),
            findsOneWidget,
          );
          _verifyIndicatorNotOverflow(tester, defaultCard, Icons.check_circle);

          // Summary card completeness for reverted defaultBrand (Defect 3)
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();

          // Verify scroll recovery behavior and controller identity immediately after jumpTo(0)
          expect(
            tester.state<ScrollableState>(scrollable),
            same(retainedScrollState),
            reason:
                'ScrollableState identity must be preserved across switches',
          );
          expect(
            tester.state<ScrollableState>(scrollable).widget.controller,
            same(retainedScrollController),
            reason:
                'ScrollController identity must be preserved across switches',
          );
          expect(
            retainedScrollController.positions,
            contains(same(tester.state<ScrollableState>(scrollable).position)),
            reason: 'Retained controller must own the current scroll position',
          );
          expect(
            tester.state<ScrollableState>(scrollable).position.pixels,
            equals(0.0),
            reason:
                'Scroll position must recover to 0.0 immediately after jumpTo(0)',
          );

          final summaryRevertedCard = summaryCardFinder();
          expect(summaryRevertedCard, findsOneWidget);
          final summaryRevertedTitle = find.descendant(
            of: summaryRevertedCard,
            matching: find.text(AppBrands.defaultBrand.localizedName),
          );
          final summaryRevertedDesc = find.descendant(
            of: summaryRevertedCard,
            matching: find.text(styleDescription(BrandStyle.defaultBrand)),
          );
          await probe.text(
            summaryRevertedTitle,
            role: 'reverted summary defaultBrand title',
          );
          await probe.text(
            summaryRevertedDesc,
            role: 'reverted summary defaultBrand description',
          );

          // Explicitly restore to top for final screenshot capture and assert scroll recovery
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();
          expect(
            tester.state<ScrollableState>(scrollable).position.pixels,
            equals(0.0),
            reason:
                'Scroll position must be restored to top at 0.0 for final capture',
          );

          await probe.capture('03-reverted-defaultBrand');

          // 4. Multi-edge background validation & independent BrandBackground reference (Defect 1)
          for (var i = 0; i < samplePoints.length; i++) {
            expect(
              actualDefaultRevertedPixels[i],
              equals(actualDefaultInitialPixels[i]),
              reason:
                  'Reverting to defaultBrand did not restore solid background at margin point $i',
            );
            expect(
              actualGlassPixels[i],
              isNot(equals(actualDefaultInitialPixels[i])),
              reason:
                  'liquidGlass margin pixel at point $i should not equal defaultBrand solid background',
            );
            expect(
              actualGlassPixels[i] & 0xFF,
              equals(255),
              reason:
                  'liquidGlass route margin point $i must remain opaque (no alpha fallthrough)',
            );
            expect(
              actualGlassPixels[i] >> 8,
              isNot(equals(0)),
              reason: 'liquidGlass route margin point $i must not turn black',
            );
          }

          // Mount independent BrandBackground reference alone (widget_style_loading pattern)
          await tester.runAsync(() async {
            await theme.setBrand('liquidGlass');
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          final referenceKey = GlobalKey();
          await tester.pumpWidget(
            ChangeNotifierProvider<ThemeProvider>.value(
              value: theme,
              child: MaterialApp(
                theme: theme.brand.theme,
                home: RepaintBoundary(
                  key: referenceKey,
                  child: Material(
                    color: theme.brand.theme.scaffoldBackgroundColor,
                    child: const BrandBackground(child: SizedBox.expand()),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final referenceGlassPixels = await _samplePoints(
            tester,
            referenceKey,
            samplePoints,
          );

          for (var i = 0; i < samplePoints.length; i++) {
            final equal = actualGlassPixels[i] == referenceGlassPixels[i];
            probe.rows.add({
              'role': 'liquidGlass route margin $i vs reference',
              'actualRGBA': actualGlassPixels[i],
              'referenceRGBA': referenceGlassPixels[i],
              'matchesRealBrandBackground': equal,
            });
            expect(
              actualGlassPixels[i],
              equals(referenceGlassPixels[i]),
              reason:
                  'Glass backdrop at route margin point $i does not match independent BrandBackground reference',
            );
          }

          await probe.finish();
        } finally {
          debugDisableShadows = originalShadows;
        }
      },
    );
  }
}
