// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/share_ui_copy.dart';
import 'package:duoyi/models/workspace.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/share_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart' show AppSurfaceCard;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';
import '../support/rendered_control_contrast.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int writeCount = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    writeCount++;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    writeCount++;
    return super.remove(key);
  }
}

Future<int> _boundedPumpAndSettle(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 50),
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  Duration timeout = const Duration(seconds: 3),
}) {
  return tester.pumpAndSettle(duration, phase, timeout);
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
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
      final file = File('$resolvedDir/share-route-readable-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _assertControl44(WidgetTester tester, Finder finder, String description) {
  expect(finder, findsOneWidget, reason: description);
  expectControlTouchTarget(tester, finder);
}

Future<void> _assertReadableParagraph(
  WidgetTester tester, {
  required Finder textFinder,
  required GlobalKey boundaryKey,
  required String role,
  Finder? surfaceFinder,
  Finder? scrollableFinder,
  Finder? clipContainerFinder,
  bool assertWordContinuity = false,
}) async {
  expect(textFinder, findsOneWidget, reason: '$role must exist');
  if (scrollableFinder != null) {
    await tester.scrollUntilVisible(textFinder, 80, scrollable: scrollableFinder);
    await Scrollable.ensureVisible(tester.element(textFinder), alignment: 0.5);
    await _boundedPumpAndSettle(tester);
  }
  final rich = find.descendant(of: textFinder, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(rich);
  expect(paragraph.didExceedMaxLines, isFalse, reason: '$role must not truncate');
  final text = paragraph.text.toPlainText();
  expect(text.trim(), isNotEmpty);
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  Rect bounds(Finder finder) {
    final box = tester.renderObject<RenderBox>(finder);
    return MatrixUtils.transformRect(box.getTransformTo(boundary), Offset.zero & box.size);
  }
  final screen = Offset.zero & boundary.size;
  final scroll = scrollableFinder == null ? null : tester.state<ScrollableState>(scrollableFinder);
  Rect visible() {
    var rect = screen;
    if (scrollableFinder != null) {
      final viewport = find.descendant(of: scrollableFinder, matching: find.byType(Viewport));
      expect(viewport, findsOneWidget);
      rect = rect.intersect(bounds(viewport));
    }
    if (clipContainerFinder != null) rect = rect.intersect(bounds(clipContainerFinder));
    if (surfaceFinder != null) rect = rect.intersect(bounds(surfaceFinder));
    return rect;
  }
  Rect transformed(ui.TextBox box) => MatrixUtils.transformRect(
    paragraph.getTransformTo(boundary), Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
  );
  var offset = 0;
  for (final rune in text.runes) {
    final glyph = String.fromCharCode(rune);
    final start = offset;
    offset += glyph.length;
    if (glyph.trim().isEmpty) continue;
    final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: offset));
    expect(boxes, isNotEmpty, reason: '$role $glyph missing layout box');
    for (final box in boxes) {
      if (scroll != null) {
        final viewport = find.descendant(of: scrollableFinder!, matching: find.byType(Viewport));
        final delta = transformed(box).center.dy - bounds(viewport).center.dy;
        final p = scroll.position;
        p.jumpTo((p.pixels + delta).clamp(p.minScrollExtent,p.maxScrollExtent));
        await tester.pump(const Duration(milliseconds: 20));
      }
      final rect = transformed(box);
      final clip = visible();
      expect(clip.inflate(0.5).contains(rect.topLeft), isTrue, reason: '$role $glyph top-left $rect outside clip $clip');
      expect(clip.inflate(0.5).contains(rect.bottomRight), isTrue, reason: '$role $glyph bottom-right $rect outside clip $clip');
    }
  }
  if (assertWordContinuity) {
    for (final word in RegExp(r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*").allMatches(text)) {
      final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: word.start, extentOffset: word.end));
      expect(boxes, isNotEmpty);
      expect(boxes.map((box) => box.top.round()).toSet(), hasLength(1),reason: '$role word ${word.group(0)} must remain intact');
    }
  }
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _ShareFixture {
  final ThemeProvider theme;
  final AuthProvider auth;
  final ShareProvider share;
  final _RecordingPreferencesStore prefsStore;
  final List<http.Request> requests;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey boundaryKey;

  _ShareFixture._({
    required this.theme,
    required this.auth,
    required this.share,
    required this.prefsStore,
    required this.requests,
    required this.navigatorKey,
    required this.boundaryKey,
  });

  static Future<_ShareFixture> create({
    required String initialBrand,
  }) async {
    final initialPrefs = <String, Object>{
      'active_brand': initialBrand,
      'theme_shop_state': jsonEncode({
        'activeBrand': initialBrand,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      'flutter.active_brand': initialBrand,
      'flutter.theme_shop_state': jsonEncode({
        'activeBrand': initialBrand,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
      'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    };
    SharedPreferences.setMockInitialValues(initialPrefs);

    final store = _RecordingPreferencesStore({
      for (final entry in initialPrefs.entries)
        if (!entry.key.startsWith('flutter.'))
          'flutter.${entry.key}': entry.value,
    });
    SharedPreferencesStorePlatform.instance = store;

    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-token-A',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' && request.url.path == '/api/workspaces') {
          return _json([
            {
              'id': 'space-synthetic',
              'name': 'Synthetic Core Space',
              'description': 'Collaborative project space for readability testing',
              'owner_user_id': 'user-A',
              'members': [
                {
                  'workspace_id': 'space-synthetic',
                  'user_id': 'user-A',
                  'username': 'synthetic-user',
                  'role': 'owner',
                },
                {
                  'workspace_id': 'space-synthetic',
                  'user_id': 'user-B',
                  'username': 'Synthetic Collaborator',
                  'role': 'editor',
                },
              ],
            },
          ]);
        }
        if (request.url.path == '/api/workspaces/mentions') {
          return _json([]);
        }
        return _json(request.method == 'GET' ? [] : {});
      }),
    );

    final auth = AuthProvider(
      client: client,
      initialState: const AuthState(
        userId: 'user-A',
        username: 'synthetic-user',
        token: 'synthetic-token-A',
      ),
    );

    final share = ShareProvider()
      ..apiClientGetter = (() => auth.client)
      ..userIdGetter = (() => auth.state.userId);

    final theme = ThemeProvider();
    await theme.loadFromStorage();

    return _ShareFixture._(
      theme: theme,
      auth: auth,
      share: share,
      prefsStore: store,
      requests: requests,
      navigatorKey: GlobalKey<NavigatorState>(),
      boundaryKey: GlobalKey(),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required double scale,
    required AppLocale locale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    I18n.setLocale(locale);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ShareProvider>.value(value: share),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, currentTheme, _) =>
              ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, currentLocale, _) => MaterialApp(
                  navigatorKey: navigatorKey,
                  debugShowCheckedModeBanner: false,
                  locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: currentTheme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: size,
                      textScaler: scale < 0
                          ? const RouteProbeNonlinearScaler()
                          : TextScaler.linear(scale),
                    ),
                    child: RepaintBoundary(key: boundaryKey, child: child!),
                  ),
                  home: const BrandRouteSurface(child: ShareScreen()),
                ),
              ),
        ),
      ),
    );

    await _boundedPumpAndSettle(tester);
    if (share.loading) {
      await tester.pump(const Duration(milliseconds: 50));
      await _boundedPumpAndSettle(tester);
    }
  }

  void dispose() {
    share.dispose();
    auth.dispose();
    theme.dispose();
  }
}

class _ShareReadabilityScenario {
  final String name;
  final AppLocale initialLocale;
  final String brandId;
  final Size size;
  final double scale;

  const _ShareReadabilityScenario({
    required this.name,
    required this.initialLocale,
    required this.brandId,
    required this.size,
    required this.scale,
  });
}

const _scenarios = <_ShareReadabilityScenario>[
  _ShareReadabilityScenario(
    name: 'zh-portrait-320x844-scale2-defaultBrand',
    initialLocale: AppLocale.zh,
    brandId: 'defaultBrand',
    size: Size(320, 844),
    scale: 2.0,
  ),
  _ShareReadabilityScenario(
    name: 'en-portrait-320x844-scale2-liquidGlass',
    initialLocale: AppLocale.en,
    brandId: 'liquidGlass',
    size: Size(320, 844),
    scale: 2.0,
  ),
  _ShareReadabilityScenario(
    name: 'en-nonlinear-332x844-scaleNonlinear-defaultBrand',
    initialLocale: AppLocale.en,
    brandId: 'defaultBrand',
    size: Size(332, 844),
    scale: -1.0,
  ),
  _ShareReadabilityScenario(
    name: 'en-portrait-390x844-scale1-liquidGlass',
    initialLocale: AppLocale.en,
    brandId: 'liquidGlass',
    size: Size(390, 844),
    scale: 1.0,
  ),
  _ShareReadabilityScenario(
    name: 'zh-landscape-844x390-scale1-defaultBrand',
    initialLocale: AppLocale.zh,
    brandId: 'defaultBrand',
    size: Size(844, 390),
    scale: 1.0,
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;

  setUpAll(() async {
    await loadWeeklyReviewScreenshotFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'ShareScreen visible content readable with full heading, member chips, and 44px actions: ${scenario.name}',
      (tester) async {
        final fixture = await _ShareFixture.create(
          initialBrand: scenario.brandId,
        );
        addTearDown(fixture.dispose);

        await fixture.pump(
          tester,
          size: scenario.size,
          scale: scenario.scale,
          locale: scenario.initialLocale,
        );

        // 1. Core AppBar Heading Readability: didExceedMaxLines == false
        // Tested against actual toolbar ∩ screen bounds
        final appTitleFinder = find.descendant(
          of: find.byType(AppBar),
          matching: find.text(ShareUiCopy.screenTitle(scenario.initialLocale)),
        );
        await _assertReadableParagraph(
          tester,
          textFinder: appTitleFinder,
          clipContainerFinder: find.byType(AppBar),
          boundaryKey: fixture.boundaryKey,
          role: 'AppBar title (${scenario.name})',
          assertWordContinuity: true,
        );

        // 2. All 3 AppBar action buttons preserved and >= 44px touch target
        final mentionBtnFinder = find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.alternate_email_outlined),
        );
        final joinBtnFinder = find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.qr_code_2),
        );
        final refreshBtnFinder = find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.refresh),
        );

        _assertControl44(
          tester,
          find.ancestor(of: mentionBtnFinder, matching: find.byType(IconButton)),
          'Mentions inbox button (${scenario.name})',
        );
        _assertControl44(
          tester,
          find.ancestor(of: joinBtnFinder, matching: find.byType(IconButton)),
          'Join QR button (${scenario.name})',
        );
        _assertControl44(
          tester,
          find.ancestor(of: refreshBtnFinder, matching: find.byType(IconButton)),
          'Refresh button (${scenario.name})',
        );

        // 3. Hero Card Heading Readability
        final heroTitleFinder = find.descendant(
          of: find.byType(AppSurfaceCard),
          matching: find.text(ShareUiCopy.screenTitle(scenario.initialLocale)),
        );
        await _assertReadableParagraph(
          tester,
          textFinder: heroTitleFinder,
          surfaceFinder: find.byType(AppSurfaceCard).first,
          boundaryKey: fixture.boundaryKey,
          role: 'Hero card title (${scenario.name})',
          assertWordContinuity: true,
        );

        // 4. Workspace Member Chips Readability: didExceedMaxLines == false
        // Tested against actual scroll viewport ∩ screen bounds
        final scrollableFinder = find.byType(Scrollable).first;
        final memberNameFinder = find.text('synthetic-user');

        await _assertReadableParagraph(
          tester,
          textFinder: memberNameFinder,
          scrollableFinder: scrollableFinder,
          surfaceFinder: find.ancestor(of: memberNameFinder, matching: find.byType(Container)).first,
          boundaryKey: fixture.boundaryKey,
          role: 'Member chip username (${scenario.name})',
          assertWordContinuity: true,
        );

        final ownerBadgeFinder = find.text(
          WorkspaceRole.owner.labelFor(scenario.initialLocale),
        );
        await _assertReadableParagraph(
          tester,
          textFinder: ownerBadgeFinder,
          scrollableFinder: scrollableFinder,
          boundaryKey: fixture.boundaryKey,
          role: 'Member chip role badge (${scenario.name})',
        );

        // 5. Screenshot capture if DUOYI_PRIORITY_THEME_SCREENSHOT_DIR is configured
        await _capture(tester, fixture.boundaryKey, scenario.name);

        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'ShareScreen visible content readable on pushed route with real leading return button: en-pushed-320x844-scale2-defaultBrand',
    (tester) async {
      final fixture = await _ShareFixture.create(
        initialBrand: 'defaultBrand',
      );
      addTearDown(fixture.dispose);

      // 1. Initial root mount
      await fixture.pump(
        tester,
        size: const Size(320, 844),
        scale: 2.0,
        locale: AppLocale.en,
      );

      // 2. Push ShareScreen onto the navigator so it has a real leading back button
      await tester.runAsync(() async {
        fixture.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const BrandRouteSurface(child: ShareScreen()),
          ),
        );
      });
      await _boundedPumpAndSettle(tester);

      // 3. Verify real leading return button exists and is >= 44px
      final backButtonFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackButton),
      );
      _assertControl44(tester, backButtonFinder, 'Leading back button on pushed route');

      // 4. Verify all 3 action buttons exist and are >= 44px
      final mentionBtnFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.alternate_email_outlined),
      );
      final joinBtnFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.qr_code_2),
      );
      final refreshBtnFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.refresh),
      );

      _assertControl44(
        tester,
        find.ancestor(of: mentionBtnFinder, matching: find.byType(IconButton)),
        'Mentions inbox button (pushed route)',
      );
      _assertControl44(
        tester,
        find.ancestor(of: joinBtnFinder, matching: find.byType(IconButton)),
        'Join QR button (pushed route)',
      );
      _assertControl44(
        tester,
        find.ancestor(of: refreshBtnFinder, matching: find.byType(IconButton)),
        'Refresh button (pushed route)',
      );

      // 5. Verify AppBar title is readable, didExceedMaxLines == false, words unbroken,
      // and glyphs strictly within actual toolbar ∩ screen
      final appTitleFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.text(ShareUiCopy.screenTitle(AppLocale.en)),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: appTitleFinder,
        clipContainerFinder: find.byType(AppBar),
        boundaryKey: fixture.boundaryKey,
        role: 'AppBar title (pushed route)',
        assertWordContinuity: true,
      );

      // 6. Verify workspace member chips readable and inside actual scroll viewport ∩ screen
      final scrollableFinder = find.byType(Scrollable).first;
      final memberNameFinder = find.text('synthetic-user');

      await _assertReadableParagraph(
        tester,
        textFinder: memberNameFinder,
        scrollableFinder: scrollableFinder,
        surfaceFinder: find.ancestor(of: memberNameFinder, matching: find.byType(Container)).first,
        boundaryKey: fixture.boundaryKey,
        role: 'Member chip username (pushed route)',
        assertWordContinuity: true,
      );

      final ownerBadgeFinder = find.text(
        WorkspaceRole.owner.labelFor(AppLocale.en),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: ownerBadgeFinder,
        scrollableFinder: scrollableFinder,
        boundaryKey: fixture.boundaryKey,
        role: 'Member chip role badge (pushed route)',
      );

      // 7. Capture screenshot for the pushed route scenario
      await _capture(tester, fixture.boundaryKey, 'en-pushed-320x844-scale2-defaultBrand');

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ShareScreen preserves readability, 0 mutation writes, and provider identity across live mounted brand switch: defaultBrand <-> liquidGlass',
    (tester) async {
      final fixture = await _ShareFixture.create(
        initialBrand: 'defaultBrand',
      );
      addTearDown(fixture.dispose);

      await fixture.pump(
        tester,
        size: const Size(320, 844),
        scale: 2.0,
        locale: AppLocale.en,
      );

      final initialScreenState = tester.state(find.byType(ShareScreen));
      final initialAuth = fixture.auth;
      final initialShare = fixture.share;

      final appTitleFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.text(ShareUiCopy.screenTitle(AppLocale.en)),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: appTitleFinder,
        clipContainerFinder: find.byType(AppBar),
        boundaryKey: fixture.boundaryKey,
        role: 'AppBar title (defaultBrand initial)',
        assertWordContinuity: true,
      );

      // Live switch to liquidGlass
      await tester.runAsync(() async {
        await fixture.theme.setBrand('liquidGlass');
      });
      await _boundedPumpAndSettle(tester);

      expect(tester.state(find.byType(ShareScreen)), same(initialScreenState));
      expect(fixture.auth, same(initialAuth));
      expect(fixture.share, same(initialShare));

      await _assertReadableParagraph(
        tester,
        textFinder: appTitleFinder,
        clipContainerFinder: find.byType(AppBar),
        boundaryKey: fixture.boundaryKey,
        role: 'AppBar title (liquidGlass switched)',
        assertWordContinuity: true,
      );

      // Live switch back to defaultBrand
      await tester.runAsync(() async {
        await fixture.theme.setBrand('defaultBrand');
      });
      await _boundedPumpAndSettle(tester);

      expect(tester.state(find.byType(ShareScreen)), same(initialScreenState));
      expect(fixture.auth, same(initialAuth));
      expect(fixture.share, same(initialShare));

      await _assertReadableParagraph(
        tester,
        textFinder: appTitleFinder,
        clipContainerFinder: find.byType(AppBar),
        boundaryKey: fixture.boundaryKey,
        role: 'AppBar title (defaultBrand restored)',
        assertWordContinuity: true,
      );

      // Verify zero mutation writes to backend
      final mutations = fixture.requests.where((r) => r.method != 'GET');
      expect(mutations, isEmpty, reason: 'Zero mutation writes across live brand switches');

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ShareScreen preserves readability, 0 mutation writes, and provider identity across live mounted locale switch: zh <-> en',
    (tester) async {
      final fixture = await _ShareFixture.create(
        initialBrand: 'liquidGlass',
      );
      addTearDown(fixture.dispose);

      await fixture.pump(
        tester,
        size: const Size(320, 844),
        scale: 2.0,
        locale: AppLocale.zh,
      );

      final initialScreenState = tester.state(find.byType(ShareScreen));
      final initialAuth = fixture.auth;
      final initialShare = fixture.share;

      // In zh: verify "共享空间" and "拥有者"
      final zhTitleFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.text(ShareUiCopy.screenTitle(AppLocale.zh)),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: zhTitleFinder,
        clipContainerFinder: find.byType(AppBar),
        boundaryKey: fixture.boundaryKey,
        role: 'AppBar title (zh initial)',
      );

      final scrollableFinder = find.byType(Scrollable).first;
      final zhRoleFinder = find.text(
        WorkspaceRole.owner.labelFor(AppLocale.zh),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: zhRoleFinder,
        scrollableFinder: scrollableFinder,
        boundaryKey: fixture.boundaryKey,
        role: 'Role badge (zh initial)',
      );

      // Live switch to en
      I18n.setLocale(AppLocale.en);
      await _boundedPumpAndSettle(tester);

      expect(tester.state(find.byType(ShareScreen)), same(initialScreenState));
      expect(fixture.auth, same(initialAuth));
      expect(fixture.share, same(initialShare));

      // In en: verify "Shared Spaces" and "Owner"
      final enTitleFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.text(ShareUiCopy.screenTitle(AppLocale.en)),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: enTitleFinder,
        clipContainerFinder: find.byType(AppBar),
        boundaryKey: fixture.boundaryKey,
        role: 'AppBar title (en switched)',
        assertWordContinuity: true,
      );

      final enRoleFinder = find.text(
        WorkspaceRole.owner.labelFor(AppLocale.en),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: enRoleFinder,
        scrollableFinder: scrollableFinder,
        boundaryKey: fixture.boundaryKey,
        role: 'Role badge (en switched)',
      );

      // Verify zero mutation writes to backend
      final mutations = fixture.requests.where((r) => r.method != 'GET');
      expect(mutations, isEmpty, reason: 'Zero mutation writes across live locale switches');

      expect(tester.takeException(), isNull);
    },
  );
}
