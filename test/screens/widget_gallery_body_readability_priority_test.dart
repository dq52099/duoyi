// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';

const _widgetChannel = MethodChannel('duoyi/widgets');

Future<Object?> _handleWidgetMethodCall(MethodCall call) async {
  switch (call.method) {
    case 'canRequestPinWidget':
      return true;
    case 'canOpenWidgetSettings':
      return true;
    case 'openWidgetSettings':
      return true;
    case 'applyWidgetDisplayMode':
    case 'refreshAllWidgets':
      return 0;
    default:
      return null;
  }
}

Future<void> _captureGalleryScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final screenshotDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (screenshotDir == null || screenshotDir.isEmpty) return;

  await tester.runAsync(() async {
    final context = boundaryKey.currentContext;
    if (context == null) {
      throw StateError(
        'missingboundary: BuildContext not found for screenshot "$name"',
      );
    }
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError(
        'missingboundary: RenderRepaintBoundary not found for "$name"',
      );
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError(
          'encoding: failed to encode PNG for screenshot "$name"',
        );
      }
      final file = File('$screenshotDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _assertReadableParagraph(
  WidgetTester tester, {
  required Finder textFinder,
  required Finder surfaceFinder,
  required GlobalKey boundaryKey,
  required String role,
}) {
  expect(
    textFinder,
    findsOneWidget,
    reason: '$role text must exist (no vacuity)',
  );
  final richTextFinder = find.descendant(
    of: textFinder,
    matching: find.byType(RichText),
  );
  final paragraph = tester.renderObject<RenderParagraph>(
    richTextFinder.evaluate().isNotEmpty ? richTextFinder : textFinder,
  );

  // 1. RenderParagraph.didExceedMaxLines must be false (no line truncation)
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role didExceedMaxLines must be false (no line truncation)',
  );

  final text = paragraph.text.toPlainText();
  expect(text.trim(), isNotEmpty, reason: '$role text must not be empty');

  final renderBoundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final surfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
  final surfaceRect = MatrixUtils.transformRect(
    surfaceBox.getTransformTo(renderBoundary),
    Offset.zero & surfaceBox.size,
  );

  // Check non-blank graphemes individually to avoid whitespace padding being treated as overflow
  var nonBlankGlyphCount = 0;
  int i = 0;
  while (i < text.length) {
    final codeUnit = text.codeUnitAt(i);
    int end = i + 1;
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && end < text.length) {
      end = i + 2;
    }
    final cluster = text.substring(i, end);
    if (cluster.trim().isNotEmpty) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: end),
      );
      for (final box in boxes) {
        nonBlankGlyphCount++;
        // Check within paragraph bounds (top, bottom, left, right)
        expect(
          box.top,
          greaterThanOrEqualTo(-0.5),
          reason: '$role glyph ($cluster) top ${box.top} must be >= -0.5',
        );
        expect(
          box.bottom,
          lessThanOrEqualTo(paragraph.size.height + 0.5),
          reason:
              '$role glyph ($cluster) bottom ${box.bottom} must be <= ${paragraph.size.height + 0.5}',
        );
        expect(
          box.left,
          greaterThanOrEqualTo(-0.5),
          reason: '$role glyph ($cluster) left ${box.left} must be >= -0.5',
        );
        expect(
          box.right,
          lessThanOrEqualTo(paragraph.size.width + 0.5),
          reason:
              '$role glyph ($cluster) right ${box.right} must be <= ${paragraph.size.width + 0.5}',
        );

        // Check within surface bounds
        final glyphRect = MatrixUtils.transformRect(
          paragraph.getTransformTo(renderBoundary),
          Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
        );
        final visibleRect = Offset.zero & renderBoundary.size;
        expect(visibleRect.inflate(0.5).contains(glyphRect.topLeft), isTrue, reason: '$role visible glyph ($cluster) top-left must be in real mobile viewport');
        expect(visibleRect.inflate(0.5).contains(glyphRect.bottomRight), isTrue, reason: '$role visible glyph ($cluster) bottom-right must be in real mobile viewport');
        expect(
          surfaceRect.inflate(0.5).contains(glyphRect.topLeft),
          isTrue,
          reason:
              '$role glyph ($cluster) top-left $glyphRect must be within surface $surfaceRect',
        );
        expect(
          surfaceRect.inflate(0.5).contains(glyphRect.bottomRight),
          isTrue,
          reason:
              '$role glyph ($cluster) bottom-right $glyphRect must be within surface $surfaceRect',
        );
      }
    }
    i = end;
  }

  expect(
    nonBlankGlyphCount,
    greaterThan(0),
    reason: '$role must have at least one non-blank glyph box',
  );
}

class _GalleryFixture {
  _GalleryFixture._({
    required this.theme,
    required this.auth,
    required this.rewards,
    required this.boundaryKey,
    required this.viewportSize,
  });

  final ThemeProvider theme;
  final AuthProvider auth;
  final AchievementProvider rewards;
  final GlobalKey boundaryKey;
  final Size viewportSize;

  static Future<_GalleryFixture> mount(
    WidgetTester tester, {
    required String brandId,
    required AppLocale locale,
    required Size viewportSize,
    required TextScaler textScaler,
    required WidgetHostPlatform hostPlatform,
  }) async {
    SharedPreferences.setMockInitialValues({
      'active_brand': brandId,
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      'theme_shop_state': jsonEncode({
        'activeBrand': brandId,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
    });
    I18n.setLocale(locale);
    AndroidWidgetManager.debugIsAndroidOverride =
        hostPlatform == WidgetHostPlatform.android;

    tester.view.physicalSize = viewportSize;
    tester.view.devicePixelRatio = 1;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      _widgetChannel,
      _handleWidgetMethodCall,
    );

    final theme = ThemeProvider();
    final auth = AuthProvider();
    final rewards = AchievementProvider();

    await tester.runAsync(() async {
      await theme.loadFromStorage();
      await loadWeeklyReviewScreenshotFonts();
    });

    final boundaryKey = GlobalKey();

    addTearDown(() async {
      await tester.runAsync(AccountPreferenceWrites.drain);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      messenger.setMockMethodCallHandler(_widgetChannel, null);
      AndroidWidgetManager.debugIsAndroidOverride = null;
      tester.view.reset();
      theme.dispose();
      auth.dispose();
      rewards.dispose();
    });

    Widget buildApp() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<AchievementProvider>.value(value: rewards),
        ],
        child: AnimatedBuilder(
          animation: Listenable.merge([theme, I18n.localeListenable]),
          builder: (context, _) {
            final baseTheme = theme.brand.theme;
            final visualTheme = baseTheme;
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: Locale(I18n.current == AppLocale.en ? 'en' : 'zh'),
              supportedLocales: const [Locale('en'), Locale('zh')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: visualTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: viewportSize,
                  textScaler: textScaler,
                ),
                child: RepaintBoundary(key: boundaryKey, child: child!),
              ),
              home: BrandRouteSurface(
                child: WidgetScreen(
                  hostPlatform: hostPlatform,
                ),
              ),
            );
          },
        ),
      );
    }

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    return _GalleryFixture._(
      theme: theme,
      auth: auth,
      rewards: rewards,
      boundaryKey: boundaryKey,
      viewportSize: viewportSize,
    );
  }
}

Future<void> _revealCard(WidgetTester tester, Finder cardFinder) async {
  final scrollableFinder = find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  if (cardFinder.evaluate().isEmpty) {
    try {
      await tester.scrollUntilVisible(
        cardFinder,
        250.0,
        scrollable: scrollableFinder,
        maxScrolls: 50,
      );
    } catch (_) {
      final scrollable = tester.state<ScrollableState>(scrollableFinder);
      scrollable.position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        cardFinder,
        250.0,
        scrollable: scrollableFinder,
        maxScrolls: 50,
      );
    }
    await tester.pumpAndSettle();
  }
  final previewCardFinder = find.descendant(
    of: cardFinder,
    matching: find.byType(WidgetPreviewCard),
  );
  if (previewCardFinder.evaluate().isNotEmpty) {
    await tester.ensureVisible(previewCardFinder);
  } else {
    await tester.ensureVisible(cardFinder);
  }
  await tester.pumpAndSettle();
}

Future<void> _assertGalleryCardReadability(
  WidgetTester tester, {
  required _GalleryFixture fixture,
  required DuoyiWidgetKind kind,
  required String expectedBrandId,
  required double viewportWidth,
  required List<(Finder Function(Finder cardFinder), String role)> textChecks,
}) async {
  // 1. Assert real ThemeProvider.brand FIRST
  expect(
    fixture.theme.brand.id,
    equals(expectedBrandId),
    reason: 'ThemeProvider.brand must be $expectedBrandId before card assertion',
  );

  // 2. Assert activeWidgetBackgroundBrand
  expect(
    fixture.theme.activeWidgetBackgroundBrand.id,
    equals(expectedBrandId),
    reason:
        'ThemeProvider.activeWidgetBackgroundBrand must be $expectedBrandId before card assertion',
  );

  final cardFinder = find.byKey(ValueKey('widget_gallery_${kind.name}'));

  // 3. Scroll until card is visible in gallery
  await _revealCard(tester, cardFinder);

  // 4. Find preview surface within this gallery card
  final surfaceFinder = find.descendant(
    of: cardFinder,
    matching: find.byKey(const ValueKey('widget_preview_surface')),
  );
  expect(
    surfaceFinder,
    findsOneWidget,
    reason: 'Card ${kind.name} must contain widget_preview_surface',
  );

  // 5. Assert actual surface primary color vs real AppBrand theme primary
  final surfaceElement = tester.element(surfaceFinder);
  final surfaceTheme = Theme.of(surfaceElement);
  final expectedBrand = expectedBrandId == 'defaultBrand'
      ? AppBrands.defaultBrand
      : AppBrands.liquidGlass;
  expect(
    surfaceTheme.colorScheme.primary,
    equals(expectedBrand.theme.colorScheme.primary),
    reason:
        'Actual surface Theme primary color must match real $expectedBrandId AppBrand theme primary',
  );

  // 6. Verify real gallery -> WidgetPreviewCard width and content area (272 for 320, 312 for 360)
  final previewCardFinder = find.descendant(
    of: cardFinder,
    matching: find.byType(WidgetPreviewCard),
  );
  expect(previewCardFinder, findsOneWidget);
  final previewCardWidth = tester.getSize(previewCardFinder).width;
  // Ink includes BoxDecoration.border padding; glass outer gallery card has0.55dp on each side.
  final outerBorderInset = expectedBrandId == 'liquidGlass' ? 1.1 : 0.0;
  final expectedCardWidth = viewportWidth - 48.0 - outerBorderInset;
  expect(
    previewCardWidth,
    closeTo(expectedCardWidth, 1e-7),
    reason:
        'Real gallery WidgetPreviewCard rendered width ($previewCardWidth) must match expected $expectedCardWidth on ${viewportWidth}px viewport',
  );

  final surfaceWidth = tester.getSize(surfaceFinder).width;
  expect(
    surfaceWidth,
    closeTo(expectedCardWidth, 1e-7),
    reason:
        'Real gallery surface rendered width ($surfaceWidth) must match expected card width $expectedCardWidth',
  );

  final contentFrameFinder = find.descendant(
    of: previewCardFinder,
    matching: find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_WidgetPreviewContentFrame',
    ),
  );
  expect(contentFrameFinder, findsOneWidget, reason: 'Actual content frame must exist; do not skip width verification');
  {
    final expectedBodyWidth = expectedCardWidth - 24.0 - (expectedBrandId == 'liquidGlass' ? 2.0 : 0.0);
    final contentWidth = tester.getSize(contentFrameFinder).width;
    expect(
      contentWidth,
      closeTo(expectedBodyWidth, 1e-7),
      reason:
          'Content area bodyWidth ($contentWidth) must match expected $expectedBodyWidth for $expectedBrandId on ${viewportWidth}px viewport',
    );
  }

  // 7. Assert text paragraphs: exist, non-empty, didExceedMaxLines == false, glyph geometries
  for (final check in textChecks) {
    final targetFinder = check.$1(cardFinder);
    expect(targetFinder, findsOneWidget);
    await tester.ensureVisible(targetFinder);
    await tester.pumpAndSettle();
    _assertReadableParagraph(
      tester,
      textFinder: targetFinder,
      surfaceFinder: surfaceFinder,
      boundaryKey: fixture.boundaryKey,
      role: '${kind.name} - ${check.$2}',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetGalleryBodyReadabilityPriorityTest - 320px 200% Scale Across Brands & Locales', () {
    testWidgets(
      'Gallery Todo/Schedule/Habit/Focus at 320px 200% text scale in defaultBrand zh Android',
      (tester) async {
        final fixture = await _GalleryFixture.mount(
          tester,
          brandId: 'defaultBrand',
          locale: AppLocale.zh,
          viewportSize: const Size(320, 844),
          textScaler: const TextScaler.linear(2.0),
          hostPlatform: WidgetHostPlatform.android,
        );

        // Priority Todo
        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.todo,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.todoItem1),
              ),
              'Todo item 1',
            ),
          ],
        );

        // Representative Focus
        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.focus,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text('25'),
              ).first,
              'Focus metric value',
            ),
          ],
        );

        // Representative Habit
        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.habit,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitTitle),
              ),
              'Habit title',
            ),
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitCheckInButton),
              ),
              'Habit check-in button',
            ),
          ],
        );

        // Priority Schedule
        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.schedule,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.scheduleItem1),
              ),
              'Schedule line 1',
            ),
          ],
        );

        await _captureGalleryScreenshot(
          tester,
          fixture.boundaryKey,
          'gallery_320px_200pct_defaultBrand_zh_android',
        );
      },
    );

    testWidgets(
      'Gallery Todo/Schedule/Habit/Focus at 320px 200% text scale in defaultBrand en iOS',
      (tester) async {
        final fixture = await _GalleryFixture.mount(
          tester,
          brandId: 'defaultBrand',
          locale: AppLocale.en,
          viewportSize: const Size(320, 844),
          textScaler: const TextScaler.linear(2.0),
          hostPlatform: WidgetHostPlatform.ios,
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.todo,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.todoItem1),
              ),
              'Todo item 1',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.focus,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text('25'),
              ).first,
              'Focus metric value',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.habit,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitTitle),
              ),
              'Habit title',
            ),
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitCheckInButton),
              ),
              'Habit check-in button',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.schedule,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.scheduleItem1),
              ),
              'Schedule line 1',
            ),
          ],
        );

        await _captureGalleryScreenshot(
          tester,
          fixture.boundaryKey,
          'gallery_320px_200pct_defaultBrand_en_ios',
        );
      },
    );

    testWidgets(
      'Gallery Todo/Schedule/Habit/Focus at 320px 200% text scale in liquidGlass zh iOS',
      (tester) async {
        final fixture = await _GalleryFixture.mount(
          tester,
          brandId: 'liquidGlass',
          locale: AppLocale.zh,
          viewportSize: const Size(320, 844),
          textScaler: const TextScaler.linear(2.0),
          hostPlatform: WidgetHostPlatform.ios,
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.todo,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.todoItem1),
              ),
              'Todo item 1',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.focus,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text('25'),
              ).first,
              'Focus metric value',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.habit,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitTitle),
              ),
              'Habit title',
            ),
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitCheckInButton),
              ),
              'Habit check-in button',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.schedule,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.scheduleItem1),
              ),
              'Schedule line 1',
            ),
          ],
        );

        await _captureGalleryScreenshot(
          tester,
          fixture.boundaryKey,
          'gallery_320px_200pct_liquidGlass_zh_ios',
        );
      },
    );

    testWidgets(
      'Gallery Todo/Schedule/Habit/Focus at 320px 200% text scale in liquidGlass en Android',
      (tester) async {
        final fixture = await _GalleryFixture.mount(
          tester,
          brandId: 'liquidGlass',
          locale: AppLocale.en,
          viewportSize: const Size(320, 844),
          textScaler: const TextScaler.linear(2.0),
          hostPlatform: WidgetHostPlatform.android,
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.todo,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.todoItem1),
              ),
              'Todo item 1',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.focus,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text('25'),
              ).first,
              'Focus metric value',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.habit,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitTitle),
              ),
              'Habit title',
            ),
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitCheckInButton),
              ),
              'Habit check-in button',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.schedule,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.scheduleItem1),
              ),
              'Schedule line 1',
            ),
          ],
        );

        await _captureGalleryScreenshot(
          tester,
          fixture.boundaryKey,
          'gallery_320px_200pct_liquidGlass_en_android',
        );
      },
    );
  });

  group('WidgetGalleryBodyReadabilityPriorityTest - 360px Representative Ordinary & Nonlinear Scales', () {
    testWidgets(
      'Gallery at 360px ordinary scale 1.0 in defaultBrand zh Android',
      (tester) async {
        final fixture = await _GalleryFixture.mount(
          tester,
          brandId: 'defaultBrand',
          locale: AppLocale.zh,
          viewportSize: const Size(360, 800),
          textScaler: const TextScaler.linear(1.0),
          hostPlatform: WidgetHostPlatform.android,
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.todo,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.todoItem1),
              ),
              'Todo item 1',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.focus,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text('25'),
              ).first,
              'Focus metric value',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.habit,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitTitle),
              ),
              'Habit title',
            ),
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitCheckInButton),
              ),
              'Habit check-in button',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.schedule,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.scheduleItem1),
              ),
              'Schedule line 1',
            ),
          ],
        );

        await _captureGalleryScreenshot(
          tester,
          fixture.boundaryKey,
          'gallery_360px_ordinary_defaultBrand_zh_android',
        );
      },
    );

    testWidgets(
      'Gallery at 360px ordinary scale 1.0 in liquidGlass en iOS',
      (tester) async {
        final fixture = await _GalleryFixture.mount(
          tester,
          brandId: 'liquidGlass',
          locale: AppLocale.en,
          viewportSize: const Size(360, 800),
          textScaler: const TextScaler.linear(1.0),
          hostPlatform: WidgetHostPlatform.ios,
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.todo,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.todoItem1),
              ),
              'Todo item 1',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.focus,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text('25'),
              ).first,
              'Focus metric value',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.habit,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitTitle),
              ),
              'Habit title',
            ),
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitCheckInButton),
              ),
              'Habit check-in button',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.schedule,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.scheduleItem1),
              ),
              'Schedule line 1',
            ),
          ],
        );

        await _captureGalleryScreenshot(
          tester,
          fixture.boundaryKey,
          'gallery_360px_ordinary_liquidGlass_en_ios',
        );
      },
    );

    testWidgets(
      'Gallery at 360px RouteProbeNonlinearScaler in defaultBrand en iOS',
      (tester) async {
        final fixture = await _GalleryFixture.mount(
          tester,
          brandId: 'defaultBrand',
          locale: AppLocale.en,
          viewportSize: const Size(360, 800),
          textScaler: const RouteProbeNonlinearScaler(),
          hostPlatform: WidgetHostPlatform.ios,
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.todo,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.todoItem1),
              ),
              'Todo item 1',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.focus,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text('25'),
              ).first,
              'Focus metric value',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.habit,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitTitle),
              ),
              'Habit title',
            ),
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitCheckInButton),
              ),
              'Habit check-in button',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.schedule,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.scheduleItem1),
              ),
              'Schedule line 1',
            ),
          ],
        );

        await _captureGalleryScreenshot(
          tester,
          fixture.boundaryKey,
          'gallery_360px_nonlinear_defaultBrand_en_ios',
        );
      },
    );

    testWidgets(
      'Gallery at 360px RouteProbeNonlinearScaler in liquidGlass zh Android',
      (tester) async {
        final fixture = await _GalleryFixture.mount(
          tester,
          brandId: 'liquidGlass',
          locale: AppLocale.zh,
          viewportSize: const Size(360, 800),
          textScaler: const RouteProbeNonlinearScaler(),
          hostPlatform: WidgetHostPlatform.android,
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.todo,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.todoItem1),
              ),
              'Todo item 1',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.focus,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text('25'),
              ).first,
              'Focus metric value',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.habit,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitTitle),
              ),
              'Habit title',
            ),
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.habitCheckInButton),
              ),
              'Habit check-in button',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.schedule,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.scheduleItem1),
              ),
              'Schedule line 1',
            ),
          ],
        );

        await _captureGalleryScreenshot(
          tester,
          fixture.boundaryKey,
          'gallery_360px_nonlinear_liquidGlass_zh_android',
        );
      },
    );
  });

  group('WidgetGalleryBodyReadabilityPriorityTest - Retained Elements Across Dynamic Brand & Locale Switch', () {
    testWidgets(
      'Retained gallery state and readability across dynamic brand switch defaultBrand -> liquidGlass at 320px 200%',
      (tester) async {
        final fixture = await _GalleryFixture.mount(
          tester,
          brandId: 'defaultBrand',
          locale: AppLocale.zh,
          viewportSize: const Size(320, 844),
          textScaler: const TextScaler.linear(2.0),
          hostPlatform: WidgetHostPlatform.ios,
        );

        final screenFinder = find.byType(WidgetScreen);
        expect(screenFinder, findsOneWidget);
        final initialScreenState = tester.state(screenFinder);
        final initialRoute = ModalRoute.of(tester.element(screenFinder));
        expect(initialRoute, isNotNull);

        // Verify initial state under defaultBrand
        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.todo,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.todoItem1),
              ),
              'Initial Todo item 1',
            ),
          ],
        );

        // Dynamic brand switch to liquidGlass via real ThemeProvider.setBrand
        await tester.runAsync(() async {
          final switched = await fixture.theme.setBrand('liquidGlass');
          expect(switched, isTrue, reason: 'setBrand(liquidGlass) must return true');
        });
        await tester.runAsync(AccountPreferenceWrites.drain);
        await tester.pumpAndSettle();

        // Invariants after switching brand:
        expect(
          tester.state(screenFinder),
          same(initialScreenState),
          reason: 'WidgetScreen state must be retained across brand switch',
        );
        expect(
          ModalRoute.of(tester.element(screenFinder)),
          same(initialRoute),
          reason: 'ModalRoute must be retained across brand switch',
        );

        // Verify updated state under liquidGlass
        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.todo,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.todoItem1),
              ),
              'Switched Todo item 1',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.schedule,
          expectedBrandId: 'liquidGlass',
          viewportWidth: 320.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text(WidgetUiCopy.scheduleItem1),
              ),
              'Switched Schedule line 1',
            ),
          ],
        );

        await _captureGalleryScreenshot(
          tester,
          fixture.boundaryKey,
          'gallery_retained_brand_switch_320px_200pct',
        );
      },
    );

    testWidgets(
      'Retained gallery state and readability across dynamic locale switch zh -> en at 360px nonlinear',
      (tester) async {
        final fixture = await _GalleryFixture.mount(
          tester,
          brandId: 'defaultBrand',
          locale: AppLocale.zh,
          viewportSize: const Size(360, 800),
          textScaler: const RouteProbeNonlinearScaler(),
          hostPlatform: WidgetHostPlatform.android,
        );

        final screenFinder = find.byType(WidgetScreen);
        expect(screenFinder, findsOneWidget);
        final initialScreenState = tester.state(screenFinder);

        // Verify initial Chinese texts
        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.todo,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text('整理今日计划'),
              ),
              'Initial zh Todo item 1',
            ),
          ],
        );

        // Dynamic locale switch to English
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();

        // Invariants after switching locale
        expect(
          tester.state(screenFinder),
          same(initialScreenState),
          reason: 'WidgetScreen state must be retained across locale switch',
        );

        // Verify updated English texts
        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.todo,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text('Organize daily plan'),
              ),
              'Updated en Todo item 1',
            ),
          ],
        );

        await _assertGalleryCardReadability(
          tester,
          fixture: fixture,
          kind: DuoyiWidgetKind.schedule,
          expectedBrandId: 'defaultBrand',
          viewportWidth: 360.0,
          textChecks: [
            (
              (card) => find.descendant(
                of: card,
                matching: find.text('09:00 Daily planning · Reminder'),
              ),
              'Updated en Schedule line 1',
            ),
          ],
        );

        await _captureGalleryScreenshot(
          tester,
          fixture.boundaryKey,
          'gallery_retained_locale_switch_360px_nonlinear',
        );
      },
    );
  });
}
