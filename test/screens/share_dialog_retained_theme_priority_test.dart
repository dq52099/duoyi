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
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/share_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/rendered_control_contrast.dart';
import '../support/retained_dialog_text_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

class _ShareDialogPriorityScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final String targetBrand;
  final Size size;
  final double scale;
  final double devicePixelRatio;

  const _ShareDialogPriorityScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.size,
    required this.scale,
    required this.devicePixelRatio,
  });
}

const _scenarios = <_ShareDialogPriorityScenario>[
  _ShareDialogPriorityScenario(
    name: 'zh-portrait-320x844-scale2-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
  ),
  _ShareDialogPriorityScenario(
    name: 'en-portrait-320x844-scale2-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
  ),
  _ShareDialogPriorityScenario(
    name: 'zh-landscape-844x390-scale1-liquidGlass',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
  ),
  _ShareDialogPriorityScenario(
    name: 'en-landscape-844x390-scale1-defaultBrand',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
  ),
];

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
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  final normalized = explicitDir.replaceAll('\\', '/');
  if (!normalized.startsWith('evidence/screenshots/') &&
      !normalized.contains('/evidence/screenshots/')) {
    return;
  }

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('Missing share screenshot boundary: $name');
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Share screenshot encoding failed: $name');
      final file = File('$explicitDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
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

void _assertBrandStyle(
  WidgetTester tester,
  String expectedBrandId, {
  required String stage,
}) {
  final dialogFinder = find.byType(AppDialog);
  expect(
    dialogFinder,
    findsOneWidget,
    reason: '$stage: AppDialog must be visible',
  );
  final dialogElement = tester.element(dialogFinder);
  final currentTheme = Theme.of(dialogElement);
  final refElement = tester.element(
    find.byKey(ValueKey('ref_theme_$expectedBrandId'), skipOffstage: false),
  );
  final refTheme = Theme.of(refElement);
  final expectedSurfaceStyle = appSurfaceStyleOf(refElement);
  final expectedButtonStyle = appSecondaryFilledButtonStyle(refElement);

  // 1. ColorScheme.primary
  expect(
    currentTheme.colorScheme.primary,
    equals(refTheme.colorScheme.primary),
    reason: '$stage: ColorScheme.primary must match reference $expectedBrandId',
  );

  // 2. Surface style
  final surfaceStyle = appSurfaceStyleOf(dialogElement);
  if (expectedBrandId == 'liquidGlass') {
    expect(
      surfaceStyle,
      equals(AppSurfaceStyle.liquidGlass),
      reason: '$stage: SurfaceStyle must be liquidGlass',
    );
  } else {
    expect(
      surfaceStyle,
      isNot(equals(AppSurfaceStyle.liquidGlass)),
      reason:
          '$stage: SurfaceStyle must not be liquidGlass for $expectedBrandId',
    );
  }
  expect(
    surfaceStyle,
    equals(expectedSurfaceStyle),
    reason: '$stage: SurfaceStyle must match reference $expectedBrandId',
  );

  // 3. Dialog surface Material color token matching brand reference
  final alertDialogFinder = find.descendant(
    of: dialogFinder,
    matching: find.byType(AlertDialog),
  );
  expect(alertDialogFinder, findsOneWidget);
  final dialogMaterial = tester.widget<Material>(
    find
        .descendant(of: alertDialogFinder, matching: find.byType(Material))
        .first,
  );
  final expectedDialogBg =
      refTheme.dialogTheme.backgroundColor ?? refTheme.colorScheme.surface;
  expect(
    dialogMaterial.color,
    equals(expectedDialogBg),
    reason:
        '$stage: Dialog background Material color token must match $expectedBrandId reference',
  );

  // 4. Filled button styling
  final filledFinder = find.descendant(
    of: dialogFinder,
    matching: find.byType(FilledButton),
  );
  if (filledFinder.evaluate().isNotEmpty) {
    final filledBtn = tester.widget<FilledButton>(filledFinder);
    final btnElement = tester.element(filledFinder);
    final effectiveStyle =
        filledBtn.style ?? Theme.of(btnElement).filledButtonTheme.style;
    final effectiveBg = effectiveStyle?.backgroundColor?.resolve({});
    final expectedBg = expectedButtonStyle.backgroundColor?.resolve({});
    expect(
      effectiveBg,
      equals(expectedBg),
      reason:
          '$stage: FilledButton background must match reference $expectedBrandId',
    );
  }
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
  ).style.merge(text.style).color!;

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
  var backgrounds = <Color>[Colors.white];
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

class _ShareDialogFixture {
  final ThemeProvider theme;
  final AuthProvider auth;
  final ShareProvider share;
  final List<http.Request> requests;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey boundaryKey;
  final Future<http.Response?> Function(http.Request)? handler;

  _ShareDialogFixture._({
    required this.theme,
    required this.auth,
    required this.share,
    required this.requests,
    required this.navigatorKey,
    required this.boundaryKey,
    this.handler,
  });

  static Future<_ShareDialogFixture> create({
    required String initialBrand,
    Future<http.Response?> Function(http.Request)? handler,
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

    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-token-A',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (handler != null) {
          final override = await handler(request);
          if (override != null) return override;
        }
        if (request.method == 'GET' && request.url.path == '/api/workspaces') {
          return _json([
            {
              'id': 'space',
              'name': 'Synthetic Space',
              'owner_user_id': 'user-A',
              'members': [
                {
                  'workspace_id': 'space',
                  'user_id': 'user-A',
                  'username': 'Synthetic Member',
                  'role': 'owner',
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
        if (request.method == 'POST' &&
            request.url.path.startsWith('/api/invites/') &&
            request.url.path.endsWith('/accept')) {
          return _json({'id': 'space-joined', 'name': 'Joined Workspace'});
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/workspaces/space/invites') {
          return _json({
            'id': 'invite-1',
            'workspace_id': 'space',
            'code': 'SYNTHETIC-INVITE-CODE',
            'role': 'viewer',
          });
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

    return _ShareDialogFixture._(
      theme: theme,
      auth: auth,
      share: share,
      requests: requests,
      navigatorKey: GlobalKey<NavigatorState>(),
      boundaryKey: GlobalKey(),
      handler: handler,
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required _ShareDialogPriorityScenario scenario,
  }) async {
    tester.view.physicalSize = Size(
      scenario.size.width * scenario.devicePixelRatio,
      scenario.size.height * scenario.devicePixelRatio,
    );
    tester.view.devicePixelRatio = scenario.devicePixelRatio;
    addTearDown(tester.view.reset);

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
                      size: scenario.size,
                      textScaler: TextScaler.linear(scenario.scale),
                    ),
                    child: RepaintBoundary(key: boundaryKey, child: child!),
                  ),
                  home: Stack(
                    children: [
                      const BrandRouteSurface(child: ShareScreen()),
                      for (final brand in [
                        AppBrands.defaultBrand,
                        AppBrands.liquidGlass,
                      ])
                        Offstage(
                          offstage: true,
                          child: Theme(
                            data: brand.theme,
                            child: Material(
                              color:
                                  brand.theme.dialogTheme.backgroundColor ??
                                  brand.theme.colorScheme.surface,
                              child: DefaultTextStyle(
                                style:
                                    brand.theme.textTheme.bodyMedium ??
                                    const TextStyle(),
                                child: AppSecondaryControlTheme(
                                  child: Builder(
                                    key: ValueKey('ref_theme_${brand.id}'),
                                    builder: (refContext) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        ),
      ),
    );
    await _boundedPumpAndSettle(tester);
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
    if (File('assets/fonts/DroidSansFallbackFull.ttf').existsSync() &&
        File('assets/fonts/DejaVuSans.ttf').existsSync()) {
      await loadWeeklyReviewScreenshotFonts();
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    I18n.setLocale(initialGlobalLocale);
  });

  for (final scenario in _scenarios) {
    testWidgets(
      'retained create, join, invite controller dialogs live brand priority ${scenario.name}',
      (tester) async {
        final originalShadows = debugDisableShadows;
        try {
          debugDisableShadows = false;
          I18n.setLocale(scenario.initialLocale);

          http.Response? dynamicResponse;
        final fixture = (await tester.runAsync(
          () => _ShareDialogFixture.create(
            initialBrand: scenario.initialBrand,
            handler: (r) async => dynamicResponse,
          ),
        ))!;
        addTearDown(fixture.dispose);

        await fixture.pump(tester, scenario: scenario);
        expect(tester.takeException(), isNull);
        expect(fixture.theme.brand.id, scenario.initialBrand);

        // ===================================================================
        // FLOW 1: Create Workspace Controller Dialog
        // ===================================================================
        final newBtn = find.widgetWithText(
          FilledButton,
          ShareUiCopy.actionNew(scenario.initialLocale),
        );
        await _reveal(tester, newBtn);
        await tester.tap(newBtn);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        final createDialogFinder = find.byType(AppDialog);
        expect(createDialogFinder, findsOneWidget);
        final initialCreateElement = tester.element(createDialogFinder);
        final initialCreateRoute = ModalRoute.of(initialCreateElement)!;

        // 1.1 Initial style & reachability
        _assertBrandStyle(
          tester,
          scenario.initialBrand,
          stage: 'Create 1. initial brand',
        );
        final expectedCreateTitle = ShareUiCopy.createWorkspaceTitle(
          scenario.initialLocale,
        );
        final expectedCreateCancel = ShareUiCopy.actionCancel(
          scenario.initialLocale,
        );
        final expectedCreateSubmit = ShareUiCopy.actionCreate(
          scenario.initialLocale,
        );

        final createTitleFinder = find.descendant(
          of: createDialogFinder,
          matching: find.text(expectedCreateTitle),
        );
        await verifyRetainedDialogText(
          tester,
          createTitleFinder,
          expected: expectedCreateTitle,
        );
        _expectReadableDialogTitle(tester, createTitleFinder);

        final createCancelBtn = find.descendant(
          of: createDialogFinder,
          matching: find.widgetWithText(TextButton, expectedCreateCancel),
        );
        final createSubmitBtn = find.descendant(
          of: createDialogFinder,
          matching: find.widgetWithText(FilledButton, expectedCreateSubmit),
        );
        await _expectReadableAction(tester, createCancelBtn);
        await _expectReadableAction(tester, createSubmitBtn);

        // Backdrop & surface readability
        expect(
          initialCreateRoute.barrierColor,
          equals(Colors.black.withValues(alpha: 0.36)),
        );
        expect(initialCreateRoute.barrierDismissible, isTrue);

        // Enter realistic draft, focus & selection in TextField
        final createFieldFinder = find.descendant(
          of: createDialogFinder,
          matching: find.byType(TextField),
        );
        expect(createFieldFinder, findsOneWidget);
        const draftWorkspaceName = 'Synthetic Core Project Space';
        await tester.enterText(createFieldFinder, draftWorkspaceName);
        final createController =
            tester.widget<TextField>(createFieldFinder).controller!;
        const createSelection = TextSelection(baseOffset: 2, extentOffset: 12);
        createController.selection = createSelection;
        await tester.pump();
        expect(createController.text, draftWorkspaceName);
        expect(createController.selection, createSelection);

        final createEditableFinder = find.descendant(
          of: createFieldFinder,
          matching: find.byType(EditableText),
        );
        expect(createEditableFinder, findsOneWidget);
        final createFocusNode =
            tester.widget<EditableText>(createEditableFinder).focusNode;
        expect(createFocusNode.hasFocus, isTrue);

        final baselinePostRequests =
            fixture.requests.where((r) => r.method == 'POST').length;

        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-create-01-initial',
        );

        // 1.2 Live brand switch to targetBrand
        await tester.runAsync(() async {
          final switched = await fixture.theme.setBrand(scenario.targetBrand);
          expect(switched, isTrue);
        });
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);
        expect(fixture.theme.brand.id, scenario.targetBrand);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialCreateElement),
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialCreateRoute),
        );
        _assertBrandStyle(
          tester,
          scenario.targetBrand,
          stage: 'Create 2. after targetBrand switch',
        );
        expect(
          tester.widget<TextField>(createFieldFinder).controller,
          same(createController),
        );
        expect(
          tester.widget<EditableText>(createEditableFinder).focusNode,
          same(createFocusNode),
        );
        expect(createFocusNode.hasFocus, isTrue);
        expect(createController.text, draftWorkspaceName);
        expect(createController.selection, createSelection);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          baselinePostRequests,
        );
        await verifyRetainedDialogText(
          tester,
          createTitleFinder,
          expected: expectedCreateTitle,
        );
        _expectReadableDialogTitle(tester, createTitleFinder);

        // Hide selection handles via public API before measuring button geometry
        tester.state<EditableTextState>(createEditableFinder).hideToolbar();
        await tester.pump();
        expect(
          tester.widget<TextField>(createFieldFinder).controller,
          same(createController),
        );
        expect(
          tester.widget<EditableText>(createEditableFinder).focusNode,
          same(createFocusNode),
        );
        expect(createFocusNode.hasFocus, isTrue);
        expect(createController.text, draftWorkspaceName);
        expect(createController.selection, createSelection);

        await _expectReadableAction(tester, createCancelBtn);
        await _expectReadableAction(tester, createSubmitBtn);
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-create-02-switched',
        );

        // 1.3 Live brand roundtrip back to initialBrand
        await tester.runAsync(() async {
          final reverted = await fixture.theme.setBrand(scenario.initialBrand);
          expect(reverted, isTrue);
        });
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);
        expect(fixture.theme.brand.id, scenario.initialBrand);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialCreateElement),
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialCreateRoute),
        );
        _assertBrandStyle(
          tester,
          scenario.initialBrand,
          stage: 'Create 3. after brand roundtrip',
        );
        expect(
          tester.widget<TextField>(createFieldFinder).controller,
          same(createController),
        );
        expect(
          tester.widget<EditableText>(createEditableFinder).focusNode,
          same(createFocusNode),
        );
        expect(createFocusNode.hasFocus, isTrue);
        expect(createController.text, draftWorkspaceName);
        expect(createController.selection, createSelection);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          baselinePostRequests,
        );
        await verifyRetainedDialogText(
          tester,
          createTitleFinder,
          expected: expectedCreateTitle,
        );
        _expectReadableDialogTitle(tester, createTitleFinder);

        // Hide selection handles via public API before measuring button geometry
        tester.state<EditableTextState>(createEditableFinder).hideToolbar();
        await tester.pump();
        expect(
          tester.widget<TextField>(createFieldFinder).controller,
          same(createController),
        );
        expect(
          tester.widget<EditableText>(createEditableFinder).focusNode,
          same(createFocusNode),
        );
        expect(createFocusNode.hasFocus, isTrue);
        expect(createController.text, draftWorkspaceName);
        expect(createController.selection, createSelection);

        await _expectReadableAction(tester, createCancelBtn);
        await _expectReadableAction(tester, createSubmitBtn);

        // 1.4 Live locale switch to alternateLocale
        I18n.setLocale(scenario.alternateLocale);
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialCreateElement),
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialCreateRoute),
        );
        final altCreateTitle = ShareUiCopy.createWorkspaceTitle(
          scenario.alternateLocale,
        );
        final altCreateCancel = ShareUiCopy.actionCancel(
          scenario.alternateLocale,
        );
        final altCreateSubmit = ShareUiCopy.actionCreate(
          scenario.alternateLocale,
        );
        final altCreateTitleFinder = find.descendant(
          of: find.byType(AppDialog),
          matching: find.text(altCreateTitle),
        );
        await verifyRetainedDialogText(
          tester,
          altCreateTitleFinder,
          expected: altCreateTitle,
        );
        _expectReadableDialogTitle(tester, altCreateTitleFinder);
        expect(
          tester.widget<TextField>(createFieldFinder).controller,
          same(createController),
        );
        expect(
          tester.widget<EditableText>(createEditableFinder).focusNode,
          same(createFocusNode),
        );
        expect(createFocusNode.hasFocus, isTrue);
        expect(createController.text, draftWorkspaceName);
        expect(createController.selection, createSelection);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          baselinePostRequests,
        );

        final altCreateCancelBtn = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(TextButton, altCreateCancel),
        );
        final altCreateSubmitBtn = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(FilledButton, altCreateSubmit),
        );

        // Hide selection handles via public API before measuring button geometry
        tester.state<EditableTextState>(createEditableFinder).hideToolbar();
        await tester.pump();
        expect(
          tester.widget<TextField>(createFieldFinder).controller,
          same(createController),
        );
        expect(
          tester.widget<EditableText>(createEditableFinder).focusNode,
          same(createFocusNode),
        );
        expect(createFocusNode.hasFocus, isTrue);
        expect(createController.text, draftWorkspaceName);
        expect(createController.selection, createSelection);

        await _expectReadableAction(tester, altCreateCancelBtn);
        await _expectReadableAction(tester, altCreateSubmitBtn);
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-create-04-locale',
        );

        // 1.5 Live locale roundtrip back to initialLocale
        I18n.setLocale(scenario.initialLocale);
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialCreateElement),
        );
        await verifyRetainedDialogText(
          tester,
          createTitleFinder,
          expected: expectedCreateTitle,
        );
        _expectReadableDialogTitle(tester, createTitleFinder);
        expect(
          tester.widget<TextField>(createFieldFinder).controller,
          same(createController),
        );
        expect(
          tester.widget<EditableText>(createEditableFinder).focusNode,
          same(createFocusNode),
        );
        expect(createFocusNode.hasFocus, isTrue);
        expect(createController.text, draftWorkspaceName);
        expect(createController.selection, createSelection);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          baselinePostRequests,
        );

        // Hide selection handles via public API before measuring button geometry
        tester.state<EditableTextState>(createEditableFinder).hideToolbar();
        await tester.pump();
        expect(
          tester.widget<TextField>(createFieldFinder).controller,
          same(createController),
        );
        expect(
          tester.widget<EditableText>(createEditableFinder).focusNode,
          same(createFocusNode),
        );
        expect(createFocusNode.hasFocus, isTrue);
        expect(createController.text, draftWorkspaceName);
        expect(createController.selection, createSelection);

        await _expectReadableAction(tester, createCancelBtn);
        await _expectReadableAction(tester, createSubmitBtn);

        // 1.6 Current failed request feedback
        dynamicResponse = _json(
          {'detail': 'Workspace name required'},
          400,
        );
        await tester.tap(createSubmitBtn);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          baselinePostRequests + 1,
        );
        expect(find.byType(AppDialog), findsOneWidget);
        expect(createController.text, draftWorkspaceName);

        final expectedCreateError = ShareUiCopy.createWorkspaceFailed(
          ShareUiCopy.error(
            const ApiException('400: Workspace name required'),
            scenario.initialLocale,
          ),
          scenario.initialLocale,
        );
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(expectedCreateError), findsOneWidget);

        // Dismiss SnackBar and cancel dialog
        ScaffoldMessenger.of(
          tester.element(find.byType(ShareScreen)),
        ).clearSnackBars();
        await _boundedPumpAndSettle(tester);
        await tester.tap(createCancelBtn);
        await _boundedPumpAndSettle(tester);
        expect(find.byType(AppDialog), findsNothing);
        expect(find.byType(ShareScreen), findsOneWidget);
        dynamicResponse = null;

        // ===================================================================
        // FLOW 2: Join Workspace Controller Dialog
        // ===================================================================
        final joinBtn = find.byTooltip(
          ShareUiCopy.actionJoinTooltip(scenario.initialLocale),
        );
        await _reveal(tester, joinBtn);
        await tester.tap(joinBtn);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        final joinDialogFinder = find.byType(AppDialog);
        expect(joinDialogFinder, findsOneWidget);
        final initialJoinElement = tester.element(joinDialogFinder);
        final initialJoinRoute = ModalRoute.of(initialJoinElement)!;

        // 2.1 Initial style & reachability
        _assertBrandStyle(
          tester,
          scenario.initialBrand,
          stage: 'Join 1. initial brand',
        );
        final expectedJoinTitle = ShareUiCopy.joinWorkspaceTitle(
          scenario.initialLocale,
        );
        final expectedJoinCancel = ShareUiCopy.actionCancel(
          scenario.initialLocale,
        );
        final expectedJoinSubmit = ShareUiCopy.actionJoin(
          scenario.initialLocale,
        );

        final joinTitleFinder = find.descendant(
          of: joinDialogFinder,
          matching: find.text(expectedJoinTitle),
        );
        await verifyRetainedDialogText(
          tester,
          joinTitleFinder,
          expected: expectedJoinTitle,
        );
        _expectReadableDialogTitle(tester, joinTitleFinder);
        final joinCancelBtn = find.descendant(
          of: joinDialogFinder,
          matching: find.widgetWithText(TextButton, expectedJoinCancel),
        );
        final joinSubmitBtn = find.descendant(
          of: joinDialogFinder,
          matching: find.widgetWithText(FilledButton, expectedJoinSubmit),
        );
        await _expectReadableAction(tester, joinCancelBtn);
        await _expectReadableAction(tester, joinSubmitBtn);

        // Backdrop & surface readability
        expect(
          initialJoinRoute.barrierColor,
          equals(Colors.black.withValues(alpha: 0.36)),
        );
        expect(initialJoinRoute.barrierDismissible, isTrue);

        // Enter code, focus & selection in TextField
        final joinFieldFinder = find.descendant(
          of: joinDialogFinder,
          matching: find.byType(TextField),
        );
        expect(joinFieldFinder, findsOneWidget);
        const draftInviteCode = 'SYNTHETIC-JOIN-CODE-2026';
        await tester.enterText(joinFieldFinder, draftInviteCode);
        final joinController =
            tester.widget<TextField>(joinFieldFinder).controller!;
        const joinSelection = TextSelection(baseOffset: 2, extentOffset: 12);
        joinController.selection = joinSelection;
        await tester.pump();
        expect(joinController.text, draftInviteCode);
        expect(joinController.selection, joinSelection);

        final joinEditableFinder = find.descendant(
          of: joinFieldFinder,
          matching: find.byType(EditableText),
        );
        expect(joinEditableFinder, findsOneWidget);
        final joinFocusNode =
            tester.widget<EditableText>(joinEditableFinder).focusNode;
        expect(joinFocusNode.hasFocus, isTrue);

        final postCountBeforeJoin =
            fixture.requests.where((r) => r.method == 'POST').length;
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-join-01-initial',
        );

        // 2.2 Live brand switch to targetBrand
        await tester.runAsync(() async {
          final switched = await fixture.theme.setBrand(scenario.targetBrand);
          expect(switched, isTrue);
        });
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);
        expect(fixture.theme.brand.id, scenario.targetBrand);

        expect(tester.element(find.byType(AppDialog)), same(initialJoinElement));
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialJoinRoute),
        );
        _assertBrandStyle(
          tester,
          scenario.targetBrand,
          stage: 'Join 2. after targetBrand switch',
        );
        expect(
          tester.widget<TextField>(joinFieldFinder).controller,
          same(joinController),
        );
        expect(
          tester.widget<EditableText>(joinEditableFinder).focusNode,
          same(joinFocusNode),
        );
        expect(joinFocusNode.hasFocus, isTrue);
        expect(joinController.text, draftInviteCode);
        expect(joinController.selection, joinSelection);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          postCountBeforeJoin,
        );
        await verifyRetainedDialogText(
          tester,
          joinTitleFinder,
          expected: expectedJoinTitle,
        );
        _expectReadableDialogTitle(tester, joinTitleFinder);

        // Hide selection handles via public API before measuring button geometry
        tester.state<EditableTextState>(joinEditableFinder).hideToolbar();
        await tester.pump();
        expect(
          tester.widget<TextField>(joinFieldFinder).controller,
          same(joinController),
        );
        expect(
          tester.widget<EditableText>(joinEditableFinder).focusNode,
          same(joinFocusNode),
        );
        expect(joinFocusNode.hasFocus, isTrue);
        expect(joinController.text, draftInviteCode);
        expect(joinController.selection, joinSelection);

        await _expectReadableAction(tester, joinCancelBtn);
        await _expectReadableAction(tester, joinSubmitBtn);
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-join-02-switched',
        );

        // 2.3 Live brand roundtrip back to initialBrand
        await tester.runAsync(() async {
          final reverted = await fixture.theme.setBrand(scenario.initialBrand);
          expect(reverted, isTrue);
        });
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);
        expect(fixture.theme.brand.id, scenario.initialBrand);

        expect(tester.element(find.byType(AppDialog)), same(initialJoinElement));
        _assertBrandStyle(
          tester,
          scenario.initialBrand,
          stage: 'Join 3. after brand roundtrip',
        );
        expect(
          tester.widget<TextField>(joinFieldFinder).controller,
          same(joinController),
        );
        expect(
          tester.widget<EditableText>(joinEditableFinder).focusNode,
          same(joinFocusNode),
        );
        expect(joinFocusNode.hasFocus, isTrue);
        expect(joinController.text, draftInviteCode);
        expect(joinController.selection, joinSelection);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          postCountBeforeJoin,
        );
        await verifyRetainedDialogText(
          tester,
          joinTitleFinder,
          expected: expectedJoinTitle,
        );
        _expectReadableDialogTitle(tester, joinTitleFinder);

        // Hide selection handles via public API before measuring button geometry
        tester.state<EditableTextState>(joinEditableFinder).hideToolbar();
        await tester.pump();
        expect(
          tester.widget<TextField>(joinFieldFinder).controller,
          same(joinController),
        );
        expect(
          tester.widget<EditableText>(joinEditableFinder).focusNode,
          same(joinFocusNode),
        );
        expect(joinFocusNode.hasFocus, isTrue);
        expect(joinController.text, draftInviteCode);
        expect(joinController.selection, joinSelection);

        await _expectReadableAction(tester, joinCancelBtn);
        await _expectReadableAction(tester, joinSubmitBtn);

        // 2.4 Live locale switch to alternateLocale
        I18n.setLocale(scenario.alternateLocale);
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(tester.element(find.byType(AppDialog)), same(initialJoinElement));
        final altJoinTitle = ShareUiCopy.joinWorkspaceTitle(
          scenario.alternateLocale,
        );
        final altJoinCancel = ShareUiCopy.actionCancel(
          scenario.alternateLocale,
        );
        final altJoinSubmit = ShareUiCopy.actionJoin(scenario.alternateLocale);
        final altJoinTitleFinder = find.descendant(
          of: find.byType(AppDialog),
          matching: find.text(altJoinTitle),
        );
        await verifyRetainedDialogText(
          tester,
          altJoinTitleFinder,
          expected: altJoinTitle,
        );
        _expectReadableDialogTitle(tester, altJoinTitleFinder);
        expect(
          tester.widget<TextField>(joinFieldFinder).controller,
          same(joinController),
        );
        expect(
          tester.widget<EditableText>(joinEditableFinder).focusNode,
          same(joinFocusNode),
        );
        expect(joinFocusNode.hasFocus, isTrue);
        expect(joinController.text, draftInviteCode);
        expect(joinController.selection, joinSelection);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          postCountBeforeJoin,
        );

        final altJoinCancelBtn = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(TextButton, altJoinCancel),
        );
        final altJoinSubmitBtn = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(FilledButton, altJoinSubmit),
        );

        // Hide selection handles via public API before measuring button geometry
        tester.state<EditableTextState>(joinEditableFinder).hideToolbar();
        await tester.pump();
        expect(
          tester.widget<TextField>(joinFieldFinder).controller,
          same(joinController),
        );
        expect(
          tester.widget<EditableText>(joinEditableFinder).focusNode,
          same(joinFocusNode),
        );
        expect(joinFocusNode.hasFocus, isTrue);
        expect(joinController.text, draftInviteCode);
        expect(joinController.selection, joinSelection);

        await _expectReadableAction(tester, altJoinCancelBtn);
        await _expectReadableAction(tester, altJoinSubmitBtn);

        // 2.5 Live locale roundtrip back to initialLocale
        I18n.setLocale(scenario.initialLocale);
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(tester.element(find.byType(AppDialog)), same(initialJoinElement));
        await verifyRetainedDialogText(
          tester,
          joinTitleFinder,
          expected: expectedJoinTitle,
        );
        _expectReadableDialogTitle(tester, joinTitleFinder);
        expect(
          tester.widget<TextField>(joinFieldFinder).controller,
          same(joinController),
        );
        expect(
          tester.widget<EditableText>(joinEditableFinder).focusNode,
          same(joinFocusNode),
        );
        expect(joinFocusNode.hasFocus, isTrue);
        expect(joinController.text, draftInviteCode);
        expect(joinController.selection, joinSelection);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          postCountBeforeJoin,
        );

        // Hide selection handles via public API before measuring button geometry
        tester.state<EditableTextState>(joinEditableFinder).hideToolbar();
        await tester.pump();
        expect(
          tester.widget<TextField>(joinFieldFinder).controller,
          same(joinController),
        );
        expect(
          tester.widget<EditableText>(joinEditableFinder).focusNode,
          same(joinFocusNode),
        );
        expect(joinFocusNode.hasFocus, isTrue);
        expect(joinController.text, draftInviteCode);
        expect(joinController.selection, joinSelection);

        await _expectReadableAction(tester, joinCancelBtn);
        await _expectReadableAction(tester, joinSubmitBtn);

        // 2.6 Current failed request feedback
        dynamicResponse = _json({'detail': 'Invite expired or invalid'}, 404);
        await tester.tap(joinSubmitBtn);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          postCountBeforeJoin + 1,
        );
        expect(find.byType(AppDialog), findsOneWidget);
        expect(joinController.text, draftInviteCode);

        final expectedJoinError = ShareUiCopy.joinWorkspaceFailed(
          ShareUiCopy.error(
            const ApiException('404: Invite expired or invalid'),
            scenario.initialLocale,
          ),
          scenario.initialLocale,
        );
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(expectedJoinError), findsOneWidget);

        // Dismiss SnackBar and cancel dialog
        ScaffoldMessenger.of(
          tester.element(find.byType(ShareScreen)),
        ).clearSnackBars();
        await _boundedPumpAndSettle(tester);
        await tester.tap(joinCancelBtn);
        await _boundedPumpAndSettle(tester);
        expect(find.byType(AppDialog), findsNothing);
        dynamicResponse = null;

        // ===================================================================
        // FLOW 3: Invite Controller Dialog
        // ===================================================================
        final inviteBtn = find.byTooltip(
          ShareUiCopy.createInviteTooltip(scenario.initialLocale),
        );
        await _reveal(tester, inviteBtn);
        await tester.tap(inviteBtn);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        final inviteDialogFinder = find.byType(AppDialog);
        expect(inviteDialogFinder, findsOneWidget);
        final initialInviteElement = tester.element(inviteDialogFinder);
        final initialInviteRoute = ModalRoute.of(initialInviteElement)!;

        // 3.1 Initial style & reachability
        _assertBrandStyle(
          tester,
          scenario.initialBrand,
          stage: 'Invite 1. initial brand',
        );
        final expectedInviteTitle = ShareUiCopy.createInviteTitle(
          scenario.initialLocale,
        );
        final expectedRoleViewer = ShareUiCopy.roleReadOnlyTitle(
          scenario.initialLocale,
        );
        final expectedRoleEditor = ShareUiCopy.roleCanEditTitle(
          scenario.initialLocale,
        );
        final expectedInviteCancel = ShareUiCopy.actionCancel(
          scenario.initialLocale,
        );
        final expectedInviteSubmit = ShareUiCopy.actionGenerate(
          scenario.initialLocale,
        );

        final inviteTitleFinder = find.descendant(
          of: inviteDialogFinder,
          matching: find.text(expectedInviteTitle),
        );
        await verifyRetainedDialogText(
          tester,
          inviteTitleFinder,
          expected: expectedInviteTitle,
        );
        _expectReadableDialogTitle(tester, inviteTitleFinder);
        await verifyRetainedDialogText(
          tester,
          find.descendant(
            of: inviteDialogFinder,
            matching: find.text(expectedRoleViewer),
          ),
          expected: expectedRoleViewer,
        );
        await verifyRetainedDialogText(
          tester,
          find.descendant(
            of: inviteDialogFinder,
            matching: find.text(expectedRoleEditor),
          ),
          expected: expectedRoleEditor,
        );

        final inviteCancelBtn = find.descendant(
          of: inviteDialogFinder,
          matching: find.widgetWithText(TextButton, expectedInviteCancel),
        );
        final inviteSubmitBtn = find.descendant(
          of: inviteDialogFinder,
          matching: find.widgetWithText(FilledButton, expectedInviteSubmit),
        );
        await _expectReadableAction(tester, inviteCancelBtn);
        await _expectReadableAction(tester, inviteSubmitBtn);

        // Backdrop & surface readability
        expect(
          initialInviteRoute.barrierColor,
          equals(Colors.black.withValues(alpha: 0.36)),
        );
        expect(initialInviteRoute.barrierDismissible, isTrue);

        // Select Editor role and verify checkmark moves
        final editorTile = find.widgetWithText(ListTile, expectedRoleEditor);
        await tester.tap(editorTile);
        await tester.pump();
        final editorCheckFinder = find.descendant(
          of: editorTile,
          matching: find.byIcon(Icons.check),
        );
        expect(editorCheckFinder, findsOneWidget);
        final refInitialElement = tester.element(
          find.byKey(
            ValueKey('ref_theme_${scenario.initialBrand}'),
            skipOffstage: false,
          ),
        );
        expect(
          tester.widget<Icon>(editorCheckFinder).color,
          equals(Theme.of(refInitialElement).colorScheme.primary),
        );

        final postCountBeforeInvite =
            fixture.requests.where((r) => r.method == 'POST').length;
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-invite-01-initial',
        );

        // 3.2 Live brand switch to targetBrand: verifies mounted actual theme propagation on invite controller dialog
        await tester.runAsync(() async {
          final switched = await fixture.theme.setBrand(scenario.targetBrand);
          expect(switched, isTrue);
        });
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);
        expect(fixture.theme.brand.id, scenario.targetBrand);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialInviteElement),
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialInviteRoute),
        );
        _assertBrandStyle(
          tester,
          scenario.targetBrand,
          stage: 'Invite 2. after targetBrand switch',
        );
        // Checkmark on Editor tile propagates actual targetBrand primary color
        final refTargetElement = tester.element(
          find.byKey(
            ValueKey('ref_theme_${scenario.targetBrand}'),
            skipOffstage: false,
          ),
        );
        expect(
          tester.widget<Icon>(editorCheckFinder).color,
          equals(Theme.of(refTargetElement).colorScheme.primary),
        );
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          postCountBeforeInvite,
        );
        await verifyRetainedDialogText(
          tester,
          inviteTitleFinder,
          expected: expectedInviteTitle,
        );
        _expectReadableDialogTitle(tester, inviteTitleFinder);
        await _expectReadableAction(tester, inviteCancelBtn);
        await _expectReadableAction(tester, inviteSubmitBtn);
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-invite-02-switched',
        );

        // 3.3 Live brand roundtrip back to initialBrand
        await tester.runAsync(() async {
          final reverted = await fixture.theme.setBrand(scenario.initialBrand);
          expect(reverted, isTrue);
        });
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);
        expect(fixture.theme.brand.id, scenario.initialBrand);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialInviteElement),
        );
        _assertBrandStyle(
          tester,
          scenario.initialBrand,
          stage: 'Invite 3. after brand roundtrip',
        );
        expect(
          tester.widget<Icon>(editorCheckFinder).color,
          equals(Theme.of(refInitialElement).colorScheme.primary),
        );
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          postCountBeforeInvite,
        );
        await verifyRetainedDialogText(
          tester,
          inviteTitleFinder,
          expected: expectedInviteTitle,
        );
        _expectReadableDialogTitle(tester, inviteTitleFinder);
        await _expectReadableAction(tester, inviteCancelBtn);
        await _expectReadableAction(tester, inviteSubmitBtn);

        // 3.4 Live locale switch to alternateLocale
        I18n.setLocale(scenario.alternateLocale);
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialInviteElement),
        );
        final altInviteTitle = ShareUiCopy.createInviteTitle(
          scenario.alternateLocale,
        );
        final altRoleViewer = ShareUiCopy.roleReadOnlyTitle(
          scenario.alternateLocale,
        );
        final altRoleEditor = ShareUiCopy.roleCanEditTitle(
          scenario.alternateLocale,
        );
        final altInviteCancel = ShareUiCopy.actionCancel(
          scenario.alternateLocale,
        );
        final altInviteSubmit = ShareUiCopy.actionGenerate(
          scenario.alternateLocale,
        );

        final altInviteTitleFinder = find.descendant(
          of: find.byType(AppDialog),
          matching: find.text(altInviteTitle),
        );
        await verifyRetainedDialogText(
          tester,
          altInviteTitleFinder,
          expected: altInviteTitle,
        );
        _expectReadableDialogTitle(tester, altInviteTitleFinder);
        await verifyRetainedDialogText(
          tester,
          find.descendant(
            of: find.byType(AppDialog),
            matching: find.text(altRoleViewer),
          ),
          expected: altRoleViewer,
        );
        await verifyRetainedDialogText(
          tester,
          find.descendant(
            of: find.byType(AppDialog),
            matching: find.text(altRoleEditor),
          ),
          expected: altRoleEditor,
        );

        final altEditorTile = find.widgetWithText(ListTile, altRoleEditor);
        final altEditorCheckFinder = find.descendant(
          of: altEditorTile,
          matching: find.byIcon(Icons.check),
        );
        expect(altEditorCheckFinder, findsOneWidget);
        expect(
          tester.widget<Icon>(altEditorCheckFinder).color,
          equals(Theme.of(refInitialElement).colorScheme.primary),
        );

        final altInviteCancelBtn = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(TextButton, altInviteCancel),
        );
        final altInviteSubmitBtn = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(FilledButton, altInviteSubmit),
        );
        await _expectReadableAction(tester, altInviteCancelBtn);
        await _expectReadableAction(tester, altInviteSubmitBtn);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          postCountBeforeInvite,
        );

        // 3.5 Live locale roundtrip back to initialLocale
        I18n.setLocale(scenario.initialLocale);
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialInviteElement),
        );
        await verifyRetainedDialogText(
          tester,
          inviteTitleFinder,
          expected: expectedInviteTitle,
        );
        _expectReadableDialogTitle(tester, inviteTitleFinder);
        await verifyRetainedDialogText(
          tester,
          find.descendant(
            of: find.byType(AppDialog),
            matching: find.text(expectedRoleViewer),
          ),
          expected: expectedRoleViewer,
        );
        await verifyRetainedDialogText(
          tester,
          find.descendant(
            of: find.byType(AppDialog),
            matching: find.text(expectedRoleEditor),
          ),
          expected: expectedRoleEditor,
        );

        final restoredEditorTile =
            find.widgetWithText(ListTile, expectedRoleEditor);
        final restoredEditorCheckFinder = find.descendant(
          of: restoredEditorTile,
          matching: find.byIcon(Icons.check),
        );
        expect(restoredEditorCheckFinder, findsOneWidget);
        expect(
          tester.widget<Icon>(restoredEditorCheckFinder).color,
          equals(Theme.of(refInitialElement).colorScheme.primary),
        );

        await _expectReadableAction(tester, inviteCancelBtn);
        await _expectReadableAction(tester, inviteSubmitBtn);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          postCountBeforeInvite,
        );

        // 3.6 Current failed request feedback
        dynamicResponse = _json(
          {'detail': 'Private workspace cannot invite'},
          400,
        );
        await tester.tap(inviteSubmitBtn);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          postCountBeforeInvite + 1,
        );
        expect(find.byType(AppDialog), findsOneWidget);
        // Editor role is still selected
        expect(
          find.descendant(
            of: find.widgetWithText(ListTile, expectedRoleEditor),
            matching: find.byIcon(Icons.check),
          ),
          findsOneWidget,
        );

        final expectedInviteError = ShareUiCopy.createInviteFailed(
          ShareUiCopy.error(
            const ApiException('400: Private workspace cannot invite'),
            scenario.initialLocale,
          ),
          scenario.initialLocale,
        );
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(expectedInviteError), findsOneWidget);

        // Dismiss SnackBar and cancel dialog
        ScaffoldMessenger.of(
          tester.element(find.byType(ShareScreen)),
        ).clearSnackBars();
        await _boundedPumpAndSettle(tester);
        await tester.tap(inviteCancelBtn);
        await _boundedPumpAndSettle(tester);
        expect(find.byType(AppDialog), findsNothing);
      } finally {
        debugDisableShadows = originalShadows;
      }
    },
    );
  }

  // =========================================================================
  // GROUP 2: In-flight Failed Request Feedback vs Superseded Account
  // =========================================================================
  for (final flow in ['create', 'join', 'invite']) {
    testWidgets(
      'current failed $flow request displays feedback while superseded account suppresses feedback',
      (tester) async {
        I18n.setLocale(AppLocale.zh);
        var shouldHold = false;
        final held = Completer<http.Response>();
        final fixture = (await tester.runAsync(
          () => _ShareDialogFixture.create(
            initialBrand: 'defaultBrand',
            handler: (request) async {
              if (request.method == 'POST') {
                if (shouldHold) return held.future;
                return _json(
                  {'detail': 'Immediate failure for active account'},
                  400,
                );
              }
              return null;
            },
          ),
        ))!;
        addTearDown(fixture.dispose);

        await fixture.pump(
          tester,
          scenario: const _ShareDialogPriorityScenario(
            name: 'verification',
            initialLocale: AppLocale.zh,
            alternateLocale: AppLocale.en,
            initialBrand: 'defaultBrand',
            targetBrand: 'liquidGlass',
            size: Size(390, 844),
            scale: 1.0,
            devicePixelRatio: 2.0,
          ),
        );

        // Open respective dialog
        switch (flow) {
          case 'create':
            final btn = find.widgetWithText(
              FilledButton,
              ShareUiCopy.actionNew(),
            );
            await _reveal(tester, btn);
            await tester.tap(btn);
            await _boundedPumpAndSettle(tester);
            await tester.enterText(
              find.descendant(
                of: find.byType(AppDialog),
                matching: find.byType(TextField),
              ),
              'Valid Draft Name',
            );
          case 'join':
            final btn = find.byTooltip(ShareUiCopy.actionJoinTooltip());
            await _reveal(tester, btn);
            await tester.tap(btn);
            await _boundedPumpAndSettle(tester);
            await tester.enterText(
              find.descendant(
                of: find.byType(AppDialog),
                matching: find.byType(TextField),
              ),
              'VALID-CODE-1234',
            );
          case 'invite':
            final btn = find.byTooltip(ShareUiCopy.createInviteTooltip());
            await _reveal(tester, btn);
            await tester.tap(btn);
            await _boundedPumpAndSettle(tester);
        }

        expect(find.byType(AppDialog), findsOneWidget);
        final submitLabel = switch (flow) {
          'create' => ShareUiCopy.actionCreate(),
          'join' => ShareUiCopy.actionJoin(),
          _ => ShareUiCopy.actionGenerate(),
        };

        final submitBtn = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(FilledButton, submitLabel),
        );

        // Phase 1: Current active account receives failed request feedback
        await tester.tap(submitBtn);
        await _boundedPumpAndSettle(tester);
        expect(
          find.byType(SnackBar),
          findsOneWidget,
          reason: 'Active account must display error feedback for failed request',
        );

        ScaffoldMessenger.of(
          tester.element(find.byType(ShareScreen)),
        ).clearSnackBars();
        await _boundedPumpAndSettle(tester);
        expect(find.byType(SnackBar), findsNothing);

        // Phase 2: In-flight request superseded by account invalidation suppresses feedback
        shouldHold = true;
        final postCountBeforeHeld =
            fixture.requests.where((r) => r.method == 'POST').length;
        // Capture the actual UI button's async handler so this stale-account
        // assertion runs only after its catch/guard continuation has finished.
        // Phase1 and the retained-flow matrix exercise the real tap path.
        final heldAction = tester.widget<FilledButton>(submitBtn).onPressed;
        expect(heldAction, isNotNull);
        late Future<void> heldSubmission;
        await tester.runAsync(() async {
          final result = Function.apply(heldAction!, const []);
          expect(result, isA<Future<void>>());
          heldSubmission = result as Future<void>;
        });
        await tester.pump();
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          equals(postCountBeforeHeld + 1),
        );

        // Supersede the active account while request is in flight
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();

        // Complete the held request with an API error
        await tester.runAsync(() async {
          held.complete(_json({'detail': 'Private diagnostic failure'}, 400));
          await heldSubmission.timeout(const Duration(seconds: 5));
        });
        // Stale-origin guards intentionally leave the obsolete form busy;
        // pumpAndSettle would spin on its indeterminate progress indicator.
        await tester.pump();

        // Feedback MUST be suppressed for superseded account
        expect(
          find.byType(SnackBar),
          findsNothing,
          reason:
              'Superseded account must never display feedback from former requests',
        );
        expect(
          fixture.requests.where((r) => r.method == 'POST').length,
          equals(postCountBeforeHeld + 1),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
