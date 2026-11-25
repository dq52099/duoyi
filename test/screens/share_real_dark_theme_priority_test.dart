// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/share_ui_copy.dart';
import 'package:duoyi/models/workspace.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/share_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/empty_state.dart';
import 'package:duoyi/widgets/surface_components.dart'
    show
        AppDialog,
        AppSurfaceCard,
        appContrastRatio,
        appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/rendered_control_contrast.dart';
import '../support/weekly_review_screenshot_font.dart';

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

Future<void> _pumpThemeSwitchFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw TimeoutException(
        'AccountPreferenceWrites.drain() timed out while pumping theme switch frames',
        const Duration(seconds: 3),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
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
      final file = File('$resolvedDir/share-real-dark-$name.png');
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
        p.jumpTo((p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent));
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
      expect(boxes.map((box) => box.top.round()).toSet(), hasLength(1), reason: '$role word ${word.group(0)} must remain intact');
    }
  }
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  for (final editable in find.byType(EditableText).evaluate()) {
    tester
        .state<EditableTextState>(find.byWidget(editable.widget))
        .hideToolbar();
  }
  if (target.evaluate().isNotEmpty) {
    final element = tester.element(target.first);
    if (Scrollable.maybeOf(element) != null) {
      await Scrollable.ensureVisible(element, alignment: 0.5);
    }
    await _boundedPumpAndSettle(tester);
    return;
  }
  final scrollFinder = find.byType(Scrollable);
  if (scrollFinder.evaluate().isNotEmpty) {
    final scroll = scrollFinder.first;
    for (var step = 0; step < 20 && target.evaluate().isEmpty; step++) {
      await tester.drag(scroll, const Offset(0, -100));
      await tester.pump(const Duration(milliseconds: 30));
    }
  }
  if (target.evaluate().isNotEmpty) {
    final element = tester.element(target.first);
    if (Scrollable.maybeOf(element) != null) {
      await Scrollable.ensureVisible(element, alignment: 0.5);
    }
    await _boundedPumpAndSettle(tester);
  }
}

Future<void> _expectReadableAction(
  WidgetTester tester,
  Finder control,
) async {
  await _reveal(tester, control);
  expectReadableControl(tester, control);
}

void _expectReadableDialogTitle(WidgetTester tester, Finder titleFinder) {
  expect(titleFinder, findsOneWidget);
  final textFinder = find.descendant(
    of: titleFinder,
    matching: find.byType(Text),
  );
  final target = textFinder.evaluate().isNotEmpty ? textFinder : titleFinder;
  final element = tester.element(target);
  final text = tester.widget<Text>(target);
  final foreground = DefaultTextStyle.of(
    element,
  ).style.merge(text.style).color ?? Theme.of(element).colorScheme.onSurface;

  final layers = <List<Color>>[];
  void addDecoration(Decoration? decoration) {
    if (decoration is! BoxDecoration) return;
    final layer = <List<Color>>[];
    if (decoration.color case final color?) layer.add([color]);
    if (decoration.gradient case final gradient?) layer.add(gradient.colors);
    layers.addAll(layer.reversed);
  }

  element.visitAncestorElements((ancestor) {
    switch (ancestor.widget) {
      case Material(:final color):
        if (color != null) layers.add([color]);
      case Ink(:final decoration):
        addDecoration(decoration);
      case DecoratedBox(:final decoration):
        addDecoration(decoration);
    }
    return true;
  });
  final dialogTheme = Theme.of(element);
  final defaultBg = dialogTheme.dialogTheme.backgroundColor ??
      dialogTheme.colorScheme.surface;
  var backgrounds = <Color>[defaultBg];
  for (final layer in layers.reversed) {
    backgrounds = [
      for (final background in backgrounds)
        for (final color in layer) Color.alphaBlend(color, background),
    ];
  }
  for (final background in backgrounds) {
    expect(
      appContrastRatio(Color.alphaBlend(foreground, background), background),
      greaterThanOrEqualTo(4.5),
      reason: 'Title "${text.data}": $foreground on $background',
    );
  }
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _ShareRealDarkFixture {
  final ThemeProvider theme;
  final AuthProvider auth;
  final ShareProvider share;
  final _RecordingPreferencesStore prefsStore;
  final List<http.Request> requests;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey boundaryKey;

  _ShareRealDarkFixture._({
    required this.theme,
    required this.auth,
    required this.share,
    required this.prefsStore,
    required this.requests,
    required this.navigatorKey,
    required this.boundaryKey,
  });

  static Future<_ShareRealDarkFixture> create({
    required String initialBrand,
    bool isLoggedIn = true,
  }) async {
    final initialPrefs = <String, Object>{
      'active_brand': initialBrand,
      'theme_shop_state': jsonEncode({
        'activeBrand': initialBrand,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass', 'starRail', 'zzz'],
      }),
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass', 'starRail', 'zzz'],
      'flutter.active_brand': initialBrand,
      'flutter.theme_shop_state': jsonEncode({
        'activeBrand': initialBrand,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass', 'starRail', 'zzz'],
      }),
      'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass', 'starRail', 'zzz'],
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
      token: isLoggedIn ? 'synthetic-token-A' : null,
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
        if (request.method == 'POST' && request.url.path == '/api/workspaces') {
          return _json({
            'id': 'space-new',
            'name': 'Created Workspace',
            'owner_user_id': 'user-A',
            'members': [],
          });
        }
        return _json(request.method == 'GET' ? [] : {});
      }),
    );

    final auth = AuthProvider(
      client: client,
      initialState: isLoggedIn
          ? const AuthState(
              userId: 'user-A',
              username: 'synthetic-user',
              token: 'synthetic-token-A',
            )
          : const AuthState(),
    );

    final share = ShareProvider()
      ..apiClientGetter = (() => auth.client)
      ..userIdGetter = (() => auth.state.userId);

    final theme = ThemeProvider();
    await theme.loadFromStorage();

    return _ShareRealDarkFixture._(
      theme: theme,
      auth: auth,
      share: share,
      prefsStore: store,
      requests: requests,
      navigatorKey: GlobalKey<NavigatorState>(),
      boundaryKey: GlobalKey(),
    );
  }

  Future<void> pumpPushed(
    WidgetTester tester, {
    required Size size,
    required double scale,
    required AppLocale locale,
  }) async {
    tester.view.physicalSize = Size(size.width, size.height);
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
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: RepaintBoundary(key: boundaryKey, child: child!),
                  ),
                  home: const Scaffold(
                    body: Center(child: Text('Synthetic Root Launcher')),
                  ),
                ),
              ),
        ),
      ),
    );

    await _boundedPumpAndSettle(tester);

    await tester.runAsync(() async {
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const BrandRouteSurface(child: ShareScreen()),
        ),
      );
    });

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

void main() {
  final initialGlobalLocale = I18n.current;

  setUpAll(() async {
    await loadWeeklyReviewScreenshotFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.en);
  });

  tearDown(() => I18n.setLocale(initialGlobalLocale));

  testWidgets(
    'Pushed ShareScreen visible content readable in production dark theme (starRail): en-pushed-320x844-scale2-starRail',
    (tester) async {
      final fixture = await _ShareRealDarkFixture.create(
        initialBrand: 'starRail',
      );
      addTearDown(fixture.dispose);

      await fixture.pumpPushed(
        tester,
        size: const Size(320, 844),
        scale: 2.0,
        locale: AppLocale.en,
      );

      // Verify production dark theme brightness directly from brand.theme
      final shareScreenFinder = find.byType(ShareScreen);
      expect(shareScreenFinder, findsOneWidget);
      final theme = Theme.of(tester.element(shareScreenFinder));
      expect(theme.brightness, equals(Brightness.dark));
      expect(
        theme.colorScheme.primary,
        equals(AppBrands.starRail.theme.colorScheme.primary),
      );

      // 1. Verify leading return BackButton exists and has >= 44dp touch target
      final backButtonFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackButton),
      );
      _assertControl44(
        tester,
        backButtonFinder,
        'Leading back button on pushed dark route (starRail)',
      );

      // 2. Verify all 3 action buttons exist and have >= 44dp touch target
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
        'Mentions inbox button (starRail dark)',
      );
      _assertControl44(
        tester,
        find.ancestor(of: joinBtnFinder, matching: find.byType(IconButton)),
        'Join QR button (starRail dark)',
      );
      _assertControl44(
        tester,
        find.ancestor(of: refreshBtnFinder, matching: find.byType(IconButton)),
        'Refresh button (starRail dark)',
      );

      // 3. Verify AppBar title is readable, didExceedMaxLines == false, words unbroken,
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
        role: 'AppBar title (en starRail dark)',
        assertWordContinuity: true,
      );

      // 4. Hero Card Heading Readability
      final heroTitleFinder = find.descendant(
        of: find.byType(AppSurfaceCard),
        matching: find.text(ShareUiCopy.screenTitle(AppLocale.en)),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: heroTitleFinder,
        surfaceFinder: find.byType(AppSurfaceCard).first,
        boundaryKey: fixture.boundaryKey,
        role: 'Hero card title (en starRail dark)',
        assertWordContinuity: true,
      );

      // 5. Workspace member chips readable inside actual scroll viewport ∩ screen
      final scrollableFinder = find.byType(Scrollable).first;
      final memberNameFinder = find.text('synthetic-user');

      await _assertReadableParagraph(
        tester,
        textFinder: memberNameFinder,
        scrollableFinder: scrollableFinder,
        surfaceFinder: find.ancestor(of: memberNameFinder, matching: find.byType(Container)).first,
        boundaryKey: fixture.boundaryKey,
        role: 'Member chip username (en starRail dark)',
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
        role: 'Member chip role badge (en starRail dark)',
      );

      // 6. Screenshot capture if env var configured (validates boundary non-null)
      await _capture(tester, fixture.boundaryKey, 'en-pushed-320x844-scale2-starRail');

      // 7. Verify zero mutation writes to backend
      expect(
        fixture.requests.where((r) => r.method != 'GET'),
        isEmpty,
        reason: 'Zero mutation writes for pushed dark route',
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Pushed ShareScreen visible content readable in production dark theme (starRail): zh-pushed-320x844-scale2-starRail',
    (tester) async {
      final fixture = await _ShareRealDarkFixture.create(
        initialBrand: 'starRail',
      );
      addTearDown(fixture.dispose);

      await fixture.pumpPushed(
        tester,
        size: const Size(320, 844),
        scale: 2.0,
        locale: AppLocale.zh,
      );

      final shareScreenFinder = find.byType(ShareScreen);
      expect(shareScreenFinder, findsOneWidget);
      final theme = Theme.of(tester.element(shareScreenFinder));
      expect(theme.brightness, equals(Brightness.dark));

      // 1. BackButton and action buttons >= 44dp
      final backButtonFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackButton),
      );
      _assertControl44(tester, backButtonFinder, 'Leading back button (zh starRail)');

      final refreshBtnFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.refresh),
      );
      _assertControl44(
        tester,
        find.ancestor(of: refreshBtnFinder, matching: find.byType(IconButton)),
        'Refresh button (zh starRail)',
      );

      // 2. Chinese AppBar title "共享空间"
      final appTitleFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.text(ShareUiCopy.screenTitle(AppLocale.zh)),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: appTitleFinder,
        clipContainerFinder: find.byType(AppBar),
        boundaryKey: fixture.boundaryKey,
        role: 'AppBar title (zh starRail dark)',
      );

      // 3. Chinese workspace member chips "synthetic-user" & "拥有者"
      final scrollableFinder = find.byType(Scrollable).first;
      final memberNameFinder = find.text('synthetic-user');
      await _assertReadableParagraph(
        tester,
        textFinder: memberNameFinder,
        scrollableFinder: scrollableFinder,
        surfaceFinder: find.ancestor(of: memberNameFinder, matching: find.byType(Container)).first,
        boundaryKey: fixture.boundaryKey,
        role: 'Member chip username (zh starRail dark)',
      );

      final ownerBadgeFinder = find.text(
        WorkspaceRole.owner.labelFor(AppLocale.zh),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: ownerBadgeFinder,
        scrollableFinder: scrollableFinder,
        boundaryKey: fixture.boundaryKey,
        role: 'Member chip role badge (zh starRail dark)',
      );

      await _capture(tester, fixture.boundaryKey, 'zh-pushed-320x844-scale2-starRail');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Pushed ShareScreen visible content readable in ordinary landscape dark mode: landscape-844x390-scale1-starRail',
    (tester) async {
      final fixture = await _ShareRealDarkFixture.create(
        initialBrand: 'starRail',
      );
      addTearDown(fixture.dispose);

      await fixture.pumpPushed(
        tester,
        size: const Size(844, 390),
        scale: 1.0,
        locale: AppLocale.en,
      );

      final shareScreenFinder = find.byType(ShareScreen);
      expect(shareScreenFinder, findsOneWidget);
      expect(
        Theme.of(tester.element(shareScreenFinder)).brightness,
        equals(Brightness.dark),
      );

      final backButtonFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackButton),
      );
      _assertControl44(tester, backButtonFinder, 'Leading back button (landscape dark)');

      final appTitleFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.text(ShareUiCopy.screenTitle(AppLocale.en)),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: appTitleFinder,
        clipContainerFinder: find.byType(AppBar),
        boundaryKey: fixture.boundaryKey,
        role: 'AppBar title (landscape starRail dark)',
        assertWordContinuity: true,
      );

      await _capture(tester, fixture.boundaryKey, 'landscape-844x390-scale1-starRail');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Representative second production dark theme (zzz): en-pushed-320x844-scale2-zzz',
    (tester) async {
      final fixture = await _ShareRealDarkFixture.create(
        initialBrand: 'zzz',
      );
      addTearDown(fixture.dispose);

      await fixture.pumpPushed(
        tester,
        size: const Size(320, 844),
        scale: 2.0,
        locale: AppLocale.en,
      );

      final shareScreenFinder = find.byType(ShareScreen);
      expect(shareScreenFinder, findsOneWidget);
      final theme = Theme.of(tester.element(shareScreenFinder));
      expect(theme.brightness, equals(Brightness.dark));
      expect(
        theme.colorScheme.primary,
        equals(AppBrands.zzz.theme.colorScheme.primary),
      );

      final backButtonFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackButton),
      );
      _assertControl44(tester, backButtonFinder, 'Leading back button (zzz dark)');

      final appTitleFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.text(ShareUiCopy.screenTitle(AppLocale.en)),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: appTitleFinder,
        clipContainerFinder: find.byType(AppBar),
        boundaryKey: fixture.boundaryKey,
        role: 'AppBar title (en zzz dark)',
        assertWordContinuity: true,
      );

      await _capture(tester, fixture.boundaryKey, 'en-pushed-320x844-scale2-zzz');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Logged-out pushed ShareScreen in production dark mode with surface/viewport constraints: loggedout-320x844-scale2-starRail',
    (tester) async {
      final fixture = await _ShareRealDarkFixture.create(
        initialBrand: 'starRail',
        isLoggedIn: false,
      );
      addTearDown(fixture.dispose);

      await fixture.pumpPushed(
        tester,
        size: const Size(320, 844),
        scale: 2.0,
        locale: AppLocale.en,
      );

      final shareScreenFinder = find.byType(ShareScreen);
      expect(shareScreenFinder, findsOneWidget);
      final theme = Theme.of(tester.element(shareScreenFinder));
      expect(theme.brightness, equals(Brightness.dark));

      // 1. Back button present on pushed route
      final backButtonFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackButton),
      );
      _assertControl44(tester, backButtonFinder, 'Leading back button (logged out)');

      // 2. AppBar title readable
      final appTitleFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.text(ShareUiCopy.screenTitle(AppLocale.en)),
      );
      await _assertReadableParagraph(
        tester,
        textFinder: appTitleFinder,
        clipContainerFinder: find.byType(AppBar),
        boundaryKey: fixture.boundaryKey,
        role: 'AppBar title (logged out starRail dark)',
        assertWordContinuity: true,
      );

      // 3. EmptyState message and Login action button
      final emptyMessageFinder = find.text(ShareUiCopy.loggedOutMessage(AppLocale.en));
      expect(emptyMessageFinder, findsOneWidget);

      final loginBtnFinder = find.widgetWithText(
        FilledButton,
        ShareUiCopy.actionLogin(AppLocale.en),
      );
      expect(loginBtnFinder, findsOneWidget);
      _assertControl44(tester, loginBtnFinder, 'Login action button (logged out)');

      // 4. Viewport constraint: EmptyState fits within screen boundary without overflow
      final boundary = fixture.boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final screenRect = Offset.zero & boundary.size;
      final emptyBox = tester.renderObject<RenderBox>(find.byType(EmptyState));
      final emptyRect = MatrixUtils.transformRect(
        emptyBox.getTransformTo(boundary),
        Offset.zero & emptyBox.size,
      );
      expect(
        screenRect.inflate(0.5).contains(emptyRect.topLeft),
        isTrue,
        reason: 'EmptyState top-left within viewport',
      );
      expect(
        screenRect.inflate(0.5).contains(emptyRect.bottomRight),
        isTrue,
        reason: 'EmptyState bottom-right within viewport',
      );

      await _capture(tester, fixture.boundaryKey, 'loggedout-320x844-scale2-starRail');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Retained controller dialog across production theme switches: starRail (dark) -> defaultBrand (light) -> liquidGlass (light) -> starRail (dark) with en <-> zh locale switching',
    (tester) async {
      final fixture = await _ShareRealDarkFixture.create(
        initialBrand: 'starRail',
      );
      addTearDown(fixture.dispose);

      await fixture.pumpPushed(
        tester,
        size: const Size(320, 844),
        scale: 2.0,
        locale: AppLocale.en,
      );

      // 1. Initial pushed route in dark theme
      expect(
        Theme.of(tester.element(find.byType(ShareScreen))).brightness,
        equals(Brightness.dark),
      );

      // 2. Open Create Workspace Controller Dialog
      final newBtn = find.widgetWithText(
        FilledButton,
        ShareUiCopy.actionNew(AppLocale.en),
      );
      await _reveal(tester, newBtn);
      await tester.tap(newBtn);
      await _boundedPumpAndSettle(tester);

      final dialogFinder = find.byType(AppDialog);
      expect(dialogFinder, findsOneWidget);
      final initialDialogElement = tester.element(dialogFinder);
      final initialDialogRoute = ModalRoute.of(initialDialogElement)!;

      // Assert dark brightness on initial dialog
      expect(
        Theme.of(initialDialogElement).brightness,
        equals(Brightness.dark),
        reason: 'Initial dialog must inherit starRail dark brightness',
      );

      // Assert title contrast & action controls
      final createTitleFinder = find.descendant(
        of: dialogFinder,
        matching: find.text(ShareUiCopy.createWorkspaceTitle(AppLocale.en)),
      );
      _expectReadableDialogTitle(tester, createTitleFinder);

      final cancelBtn = find.descendant(
        of: dialogFinder,
        matching: find.widgetWithText(TextButton, ShareUiCopy.actionCancel(AppLocale.en)),
      );
      final createSubmitBtn = find.descendant(
        of: dialogFinder,
        matching: find.widgetWithText(FilledButton, ShareUiCopy.actionCreate(AppLocale.en)),
      );
      await _expectReadableAction(tester, cancelBtn);
      await _expectReadableAction(tester, createSubmitBtn);

      // Enter draft text, selection, and verify focus in TextField
      final createFieldFinder = find.descendant(
        of: dialogFinder,
        matching: find.byType(TextField),
      );
      expect(createFieldFinder, findsOneWidget);
      const draftName = 'Synthetic Dark-to-Light Workspace';
      await tester.enterText(createFieldFinder, draftName);
      final createController =
          tester.widget<TextField>(createFieldFinder).controller!;
      const draftSelection = TextSelection(baseOffset: 2, extentOffset: 11);
      createController.selection = draftSelection;
      await tester.pump();

      expect(createController.text, equals(draftName));
      expect(createController.selection, equals(draftSelection));

      final editableFinder = find.descendant(
        of: createFieldFinder,
        matching: find.byType(EditableText),
      );
      final focusNode = tester.widget<EditableText>(editableFinder).focusNode;
      expect(focusNode.hasFocus, isTrue);

      await _capture(tester, fixture.boundaryKey, 'dialog-01-starRail-dark');

      // ===================================================================
      // SWITCH 1: starRail (dark) -> defaultBrand (light)
      // ===================================================================
      await tester.runAsync(() async {
        final switched = await fixture.theme.setBrand('defaultBrand');
        expect(switched, isTrue);
      });
      await _pumpThemeSwitchFrames(tester);

      expect(fixture.theme.brand.id, equals('defaultBrand'));
      final defaultDialogElement = tester.element(find.byType(AppDialog));

      // Explicit assertion: theme brightness switches from dark to light
      expect(
        Theme.of(defaultDialogElement).brightness,
        equals(Brightness.light),
        reason: 'Theme brightness must change to light for defaultBrand',
      );
      expect(
        appSurfaceStyleOf(defaultDialogElement),
        equals(AppSurfaceStyle.ios),
        reason: 'SurfaceStyle must match defaultBrand iOS',
      );

      // Preserve same route and element identity
      expect(defaultDialogElement, same(initialDialogElement));
      expect(ModalRoute.of(defaultDialogElement), same(initialDialogRoute));

      // Retain draft text, selection, and focus
      expect(createController.text, equals(draftName));
      expect(createController.selection, equals(draftSelection));
      expect(focusNode.hasFocus, isTrue);

      _expectReadableDialogTitle(tester, createTitleFinder);
      await _capture(tester, fixture.boundaryKey, 'dialog-02-defaultBrand-light');

      // ===================================================================
      // SWITCH 2: defaultBrand (light) -> liquidGlass (light)
      // ===================================================================
      await tester.runAsync(() async {
        final switched = await fixture.theme.setBrand('liquidGlass');
        expect(switched, isTrue);
      });
      await _pumpThemeSwitchFrames(tester);

      expect(fixture.theme.brand.id, equals('liquidGlass'));
      final glassDialogElement = tester.element(find.byType(AppDialog));

      // Explicit assertion: liquidGlass preserves light brightness with liquidGlass surfaceStyle
      expect(
        Theme.of(glassDialogElement).brightness,
        equals(Brightness.light),
        reason: 'liquidGlass must remain light brightness',
      );
      expect(
        appSurfaceStyleOf(glassDialogElement),
        equals(AppSurfaceStyle.liquidGlass),
        reason: 'SurfaceStyle must switch to liquidGlass',
      );

      expect(glassDialogElement, same(initialDialogElement));
      expect(ModalRoute.of(glassDialogElement), same(initialDialogRoute));

      expect(createController.text, equals(draftName));
      expect(createController.selection, equals(draftSelection));
      expect(focusNode.hasFocus, isTrue);

      _expectReadableDialogTitle(tester, createTitleFinder);
      await _capture(tester, fixture.boundaryKey, 'dialog-03-liquidGlass-light');

      // ===================================================================
      // SWITCH 3: liquidGlass (light) -> starRail (dark)
      // ===================================================================
      await tester.runAsync(() async {
        final switched = await fixture.theme.setBrand('starRail');
        expect(switched, isTrue);
      });
      await _pumpThemeSwitchFrames(tester);

      expect(fixture.theme.brand.id, equals('starRail'));
      final restoredDarkElement = tester.element(find.byType(AppDialog));

      // Explicit assertion: theme brightness switches back to dark
      expect(
        Theme.of(restoredDarkElement).brightness,
        equals(Brightness.dark),
        reason: 'Theme brightness must restore to dark for starRail',
      );

      expect(restoredDarkElement, same(initialDialogElement));
      expect(ModalRoute.of(restoredDarkElement), same(initialDialogRoute));

      expect(createController.text, equals(draftName));
      expect(createController.selection, equals(draftSelection));
      expect(focusNode.hasFocus, isTrue);

      _expectReadableDialogTitle(tester, createTitleFinder);
      await _capture(tester, fixture.boundaryKey, 'dialog-04-starRail-restored-dark');

      // ===================================================================
      // LOCALE SWITCH: en -> zh while dialog remains open
      // ===================================================================
      I18n.setLocale(AppLocale.zh);
      await _boundedPumpAndSettle(tester);

      final zhTitleFinder = find.descendant(
        of: find.byType(AppDialog),
        matching: find.text(ShareUiCopy.createWorkspaceTitle(AppLocale.zh)),
      );
      expect(zhTitleFinder, findsOneWidget);
      _expectReadableDialogTitle(tester, zhTitleFinder);

      // Verify route identity and draft retained across locale switch
      final zhDialogElement = tester.element(find.byType(AppDialog));
      expect(zhDialogElement, same(initialDialogElement));
      expect(ModalRoute.of(zhDialogElement), same(initialDialogRoute));
      expect(createController.text, equals(draftName));
      expect(createController.selection, equals(draftSelection));
      expect(focusNode.hasFocus, isTrue);

      await _capture(tester, fixture.boundaryKey, 'dialog-05-zh-starRail-dark');

      // ===================================================================
      // DISMISS DIALOG & VERIFY ZERO MUTATION WRITES
      // ===================================================================
      final zhCancelBtn = find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(TextButton, ShareUiCopy.actionCancel(AppLocale.zh)),
      );
      await tester.tap(zhCancelBtn);
      await _boundedPumpAndSettle(tester);

      expect(find.byType(AppDialog), findsNothing);

      // Confirm zero mutation writes to backend
      final mutations = fixture.requests.where((r) => r.method != 'GET');
      expect(
        mutations,
        isEmpty,
        reason: 'Zero mutation writes across theme switches, locale switches, and dialog cancel',
      );

      // ===================================================================
      // POP PUSHED ROUTE WITH LEADING BACK BUTTON
      // ===================================================================
      final leadingBackFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackButton),
      );
      expect(leadingBackFinder, findsOneWidget);
      await tester.tap(leadingBackFinder);
      await _boundedPumpAndSettle(tester);

      // Returned to root launcher
      expect(find.text('Synthetic Root Launcher'), findsOneWidget);
      expect(find.byType(ShareScreen), findsNothing);

      expect(tester.takeException(), isNull);
    },
  );
}
