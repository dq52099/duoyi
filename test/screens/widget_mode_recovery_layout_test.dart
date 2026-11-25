// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_display_mode_store.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';
import '../support/rendered_control_contrast.dart';

const _captureEnv = 'DUOYI_CAPTURE_WIDGET_LOCALE_SCREENSHOTS';
const _captureDirectory = 'evidence/screenshots/widget-mode-recovery-20261015';
const _intentId = 'widget-mode-recovery-20261015-pending';
const _viewports = <_ViewportSpec>[
  _ViewportSpec('320x844', Size(320, 844)),
  _ViewportSpec('568x320', Size(568, 320)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets(
    'ordinary refresh keeps a failed pending delivery and page retry confirms it',
    (tester) async {
      final fixture = _RecoveryFixture();
      addTearDown(() => fixture.dispose(tester));
      await fixture.mount(tester, viewport: const Size(390, 844));

      fixture.native.failNextDisplayModeSave = true;
      final firstAttempt = fixture.native.watchNextDisplayModeSave();
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip(WidgetUiCopy.refreshTooltip));
      });
      await _waitForSaveAttempt(tester, firstAttempt);

      final prefs = await SharedPreferences.getInstance();
      final afterRefresh = WidgetDisplayModeSelection.read(prefs);
      expect(afterRefresh.pending, isTrue);
      expect(afterRefresh.intentId, _intentId);
      expect(fixture.dashboardRefreshCalls, 0);
      expect(find.text(WidgetUiCopy.refreshSuccess), findsNothing);
      expect(fixture.native.displayModeSaveValues, ['detailed']);

      final retry = find.byKey(const ValueKey('widget_style_sync_retry'));
      await tester.ensureVisible(retry);
      final retryAttempt = fixture.native.watchNextDisplayModeSave();
      await tester.runAsync(() async {
        await tester.tap(retry);
      });
      await _waitForSaveAttempt(tester, retryAttempt);
      await _settleAsyncWork(tester);

      final afterRetry = WidgetDisplayModeSelection.read(prefs);
      expect(afterRetry.mode, 'detailed');
      expect(afterRetry.pending, isFalse);
      expect(afterRetry.intentId, _intentId);
      expect(fixture.native.displayModeSaveValues, ['detailed', 'detailed']);
      expect(fixture.dashboardRefreshCalls, 0);
      expect(find.text(WidgetUiCopy.refreshSuccess), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retained pending retry cannot replace a newer compact choice', (
    tester,
  ) async {
    final fixture = _RecoveryFixture();
    addTearDown(() => fixture.dispose(tester));
    await fixture.mount(tester, viewport: const Size(390, 844));

    final retryFinder = find.byKey(const ValueKey('widget_style_sync_retry'));
    final staleRetry = tester.widget<TextButton>(retryFinder).onPressed!;
    final selector = _styleSelector(tester);
    final compactAttempt = fixture.native.watchNextDisplayModeSave();
    await tester.runAsync(() async {
      selector.onSelectionChanged!({WidgetDisplayMode.compact});
    });
    await _waitForSaveAttempt(tester, compactAttempt);
    await _settleAsyncWork(tester);

    final prefs = await SharedPreferences.getInstance();
    final compact = WidgetDisplayModeSelection.read(prefs);
    expect(compact.mode, 'compact');
    expect(compact.pending, isFalse);
    expect(fixture.native.displayModeSaveValues, ['compact']);
    final writesBeforeStaleRetry = fixture.store.mutationCount;

    staleRetry();
    await _settleAsyncWork(tester);

    final afterStaleRetry = WidgetDisplayModeSelection.read(prefs);
    expect(afterStaleRetry.mode, 'compact');
    expect(afterStaleRetry.pending, isFalse);
    expect(fixture.native.displayModeSaveValues, ['compact']);
    expect(fixture.store.mutationCount, writesBeforeStaleRetry);
    expect(tester.takeException(), isNull);
  });

  for (final brandId in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      testWidgets(
        'queued recovery refresh disables add in $brandId ${locale.name}',
        (tester) async {
          final fixture = _RecoveryFixture(brandId: brandId);
          addTearDown(() => fixture.dispose(tester));
          await fixture.mount(
            tester,
            viewport: const Size(390, 844),
            locale: locale,
            loadScreenshotFonts: true,
          );
          await _settleAsyncWork(tester);
          final row = find.byKey(const ValueKey(DuoyiWidgetKind.todo));
          await tester.scrollUntilVisible(
            row,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          final button = find.descendant(
            of: row,
            matching: find.byType(FilledButton),
          );
          late Completer<void> gate;
          late Future<void> blocker;
          await tester.runAsync(() async {
            gate = Completer<void>();
            blocker = WidgetDisplayModeStore.runOperation(() => gate.future);
          });
          bool? enabledWhileQueued;
          bool? updatingLabelWhileQueued;
          try {
            await tester.runAsync(
              () => tester.tap(find.byTooltip(WidgetUiCopy.refreshTooltip)),
            );
            await tester.pump();
            enabledWhileQueued =
                tester.widget<FilledButton>(button).onPressed != null;
            updatingLabelWhileQueued = find
                .descendant(
                  of: button,
                  matching: find.text(WidgetUiCopy.updatingStyle),
                )
                .evaluate()
                .isNotEmpty;
            await _recordRefreshEvidence(
              tester,
              fixture,
              'queued-$brandId-${locale.name}',
              {
                'addEnabled': enabledWhileQueued,
                'updatingLabel': updatingLabelWhileQueued,
                'nativeSavesBeforeRelease':
                    fixture.native.displayModeSaveValues.length,
              },
            );
          } finally {
            await tester.runAsync(() async {
              gate.complete();
              await blocker.timeout(const Duration(seconds: 3));
            });
            await _settleAsyncWork(tester);
          }
          expect(enabledWhileQueued, isFalse);
          expect(updatingLabelWhileQueued, isTrue);
          expect(fixture.native.displayModeSaveValues, ['detailed']);
          expect(fixture.dashboardRefreshCalls, 1);
          expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'successful recovery refresh replaces stale feedback in $brandId ${locale.name}',
        (tester) async {
          final fixture = _RecoveryFixture(brandId: brandId);
          addTearDown(() => fixture.dispose(tester));
          await fixture.mount(
            tester,
            viewport: const Size(390, 844),
            locale: locale,
            loadScreenshotFonts: true,
          );
          await _settleAsyncWork(tester);
          final retry = find.byKey(const ValueKey('widget_style_sync_retry'));
          await Scrollable.ensureVisible(tester.element(retry), alignment: 1);
          await tester.pumpAndSettle();
          expect(retry.hitTestable(), findsOneWidget);
          fixture.native.failNextDisplayModeSave = true;
          final failed = fixture.native.watchNextDisplayModeSave();
          await tester.runAsync(() => tester.tap(retry));
          await _waitForSaveAttempt(tester, failed);
          final oldRetry = tester
              .widget<TextButton>(
                find.byKey(const ValueKey('widget_style_retry')),
              )
              .onPressed!;
          final succeeded = fixture.native.watchNextDisplayModeSave();
          await tester.runAsync(
            () => tester.tap(find.byTooltip(WidgetUiCopy.refreshTooltip)),
          );
          await _waitForSaveAttempt(tester, succeeded);
          await tester.pump(const Duration(milliseconds: 300));
          final staleVisible = find
              .text(WidgetUiCopy.styleSyncFailed)
              .evaluate()
              .isNotEmpty;
          final successVisible = find
              .text(WidgetUiCopy.refreshSuccess)
              .evaluate()
              .isNotEmpty;
          await _recordRefreshEvidence(
            tester,
            fixture,
            'feedback-$brandId-${locale.name}',
            {
              'failureVisibleAfterSuccess': staleVisible,
              'successVisible': successVisible,
            },
          );
          final saves = fixture.native.displayModeSaveValues.length;
          oldRetry();
          await _settleAsyncWork(tester);
          expect(fixture.native.displayModeSaveValues.length, saves);
          expect(staleVisible, isFalse);
          expect(successVisible, isTrue);
          expect(fixture.dashboardRefreshCalls, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final brandId in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final viewport in _viewports) {
        testWidgets(
          'failure snackbar retry is readable and delivers in $brandId ${locale.name} ${viewport.name}',
          (tester) async {
            final fixture = _RecoveryFixture(brandId: brandId);
            addTearDown(() => fixture.dispose(tester));
            final originalShadows = debugDisableShadows;
            debugDisableShadows = false;
            try {
              await fixture.mount(
                tester,
                viewport: viewport.size,
                textScale: 1.6,
                locale: locale,
                loadScreenshotFonts:
                    Platform.environment['DUOYI_CAPTURE_WIDGET_RETRY'] == '1',
              );
              expect(fixture.theme.brand.id, brandId);
              final prefs = await SharedPreferences.getInstance();
              final originalSelection = prefs.getString(
                WidgetDisplayModeSelection.storageKey,
              );
              final pageRetry = find.byKey(
                const ValueKey('widget_style_sync_retry'),
              );
              await Scrollable.ensureVisible(
                tester.element(pageRetry),
                alignment: 1,
              );
              await tester.pumpAndSettle();
              expect(pageRetry.hitTestable(), findsOneWidget);
              fixture.native.failNextDisplayModeSave = true;
              final failedAttempt = fixture.native.watchNextDisplayModeSave();
              await tester.runAsync(() => tester.tap(pageRetry));
              await _waitForSaveAttempt(tester, failedAttempt);
              expect(fixture.native.displayModeSaveValues, ['detailed']);
              expect(
                prefs.getString(WidgetDisplayModeSelection.storageKey),
                originalSelection,
              );
              final snackbar = find.byType(SnackBar);
              final retry = find.byKey(const ValueKey('widget_style_retry'));
              expect(snackbar, findsOneWidget);
              expect(retry.hitTestable(), findsOneWidget);
              final snackbarElement = tester.element(snackbar);
              final name = '$brandId-${locale.name}-${viewport.name}';
              await _recordRetryFeedback(tester, fixture, '$name-initial');
              expectReadableControl(tester, retry);

              final writesBeforeLocaleChange = fixture.store.mutationCount;
              final oldFailure = WidgetUiCopy.styleSyncFailed;
              I18n.setLocale(
                locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
              );
              await tester.pumpAndSettle();
              expect(tester.element(snackbar), same(snackbarElement));
              expect(
                find.descendant(
                  of: snackbar,
                  matching: find.text(WidgetUiCopy.styleSyncFailed),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(of: snackbar, matching: find.text(oldFailure)),
                findsNothing,
              );
              expect(
                find.descendant(
                  of: retry,
                  matching: find.text(WidgetUiCopy.actionRetry),
                ),
                findsOneWidget,
              );
              expect(fixture.store.mutationCount, writesBeforeLocaleChange);
              expect(fixture.native.displayModeSaveValues, ['detailed']);
              expect(
                prefs.getString(WidgetDisplayModeSelection.storageKey),
                originalSelection,
              );
              await _recordRetryFeedback(tester, fixture, '$name-switched');
              expectReadableControl(tester, retry);
              final retryAttempt = fixture.native.watchNextDisplayModeSave();
              await tester.runAsync(() => tester.tap(retry));
              await _waitForSaveAttempt(tester, retryAttempt);
              final saved = WidgetDisplayModeSelection.read(prefs);
              expect(saved.mode, 'detailed');
              expect(saved.intentId, _intentId);
              expect(saved.pending, isFalse);
              expect(fixture.native.displayModeSaveValues, [
                'detailed',
                'detailed',
              ]);
              expect(fixture.dashboardRefreshCalls, 0);
              expect(
                find.byKey(const ValueKey('widget_style_retry')),
                findsNothing,
              );
              expect(tester.takeException(), isNull);
            } finally {
              debugDisableShadows = originalShadows;
            }
          },
        );
      }
    }
  }

  for (final locale in AppLocale.values) {
    for (final viewport in _viewports) {
      testWidgets(
        'pending recovery stays visible in ${locale.name} at ${viewport.name}',
        (tester) async {
          final fixture = _RecoveryFixture();
          addTearDown(() => fixture.dispose(tester));
          final capture = Platform.environment[_captureEnv] == '1';
          await fixture.mount(
            tester,
            viewport: viewport.size,
            textScale: 1.6,
            locale: locale,
            loadScreenshotFonts: capture,
          );

          final pending = find.byKey(
            const ValueKey('widget_style_sync_pending'),
          );
          final retry = find.byKey(const ValueKey('widget_style_sync_retry'));
          await Scrollable.ensureVisible(tester.element(retry), alignment: 1);
          await tester.pumpAndSettle();
          expect(pending, findsOneWidget);
          expect(retry.hitTestable(), findsOneWidget);
          expect(
            find.text(WidgetUiCopy.styleSyncPending).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.text(WidgetUiCopy.actionRetry).hitTestable(),
            findsOneWidget,
          );
          expect(tester.getSize(find.byKey(fixture.captureKey)), viewport.size);
          expect(tester.takeException(), isNull);
          await _capture(tester, fixture, viewport, locale);

          final prefs = await SharedPreferences.getInstance();
          final savedBeforeLocaleChange = prefs.getString(
            WidgetDisplayModeSelection.storageKey,
          );
          final legacyBeforeLocaleChange = prefs.getString(
            WidgetDisplayModeSelection.legacyKey,
          );
          final writesBeforeLocaleChange = fixture.store.mutationCount;
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();

          expect(fixture.store.mutationCount, writesBeforeLocaleChange);
          expect(
            prefs.getString(WidgetDisplayModeSelection.storageKey),
            savedBeforeLocaleChange,
          );
          expect(
            prefs.getString(WidgetDisplayModeSelection.legacyKey),
            legacyBeforeLocaleChange,
          );
          expect(find.text(WidgetUiCopy.styleSyncPending), findsOneWidget);
          expect(find.text(WidgetUiCopy.actionRetry), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> _recordRefreshEvidence(
  WidgetTester tester,
  _RecoveryFixture fixture,
  String name,
  Map<String, Object?> observation,
) async {
  final measurementDir = Platform.environment['DUOYI_SECONDARY_MEASUREMENTS'];
  if (measurementDir != null) {
    final file = File('$measurementDir/$name.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${jsonEncode(observation)}\n');
  }
  final screenshotDir = Platform.environment['DUOYI_RECOVERY_REFRESH_IMAGES'];
  if (screenshotDir == null) return;
  await tester.runAsync(() async {
    final boundary =
        fixture.captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    try {
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$screenshotDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}

Future<void> _recordRetryFeedback(
  WidgetTester tester,
  _RecoveryFixture fixture,
  String name,
) async {
  final retry = find.byKey(const ValueKey('widget_style_retry'));
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: retry, matching: find.byType(RichText)),
  );
  final foreground = paragraph.text.style!.color!;
  final materials = tester.widgetList<Material>(
    find.ancestor(of: retry, matching: find.byType(Material)),
  );
  final background = materials.firstWhere((m) => m.color != null).color!;
  expect(background.a, 1, reason: 'measured SnackBar fill is opaque');
  final rect = tester.getRect(retry);
  final record = <String, Object>{
    'name': name,
    'brandId': fixture.theme.brand.id,
    'locale': I18n.current.name,
    'foreground': foreground.toARGB32().toRadixString(16),
    'background': background.toARGB32().toRadixString(16),
    'contrastRatio': appContrastRatio(
      Color.alphaBlend(foreground, background),
      background,
    ),
    'width': rect.width,
    'height': rect.height,
  };
  // Keep resolved rendering evidence even when the subsequent assertion fails.
  final directory = Platform.environment['DUOYI_WIDGET_RETRY_EVIDENCE_DIR'];
  if (directory != null) {
    final file = File('$directory/$name.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${jsonEncode(record)}\n');
  }
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.descendant(of: find.byType(SnackBar), matching: find.byType(RichText)),
  )) {
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      paragraph.textSize.width,
      lessThanOrEqualTo(paragraph.size.width + 0.1),
    );
    expect(
      paragraph.textSize.height,
      lessThanOrEqualTo(paragraph.size.height + 0.1),
    );
  }
  if (Platform.environment['DUOYI_CAPTURE_WIDGET_RETRY'] != '1') return;
  await tester.runAsync(() async {
    final boundary =
        fixture.captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    try {
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      final batch =
          Platform.environment['DUOYI_WIDGET_RETRY_SCREENSHOT_BATCH'] ??
          'current';
      final file = File(
        'evidence/screenshots/widget-retry-theme-20261019/$batch/$name.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}

SegmentedButton<WidgetDisplayMode> _styleSelector(WidgetTester tester) =>
    tester.widget<SegmentedButton<WidgetDisplayMode>>(
      find.byWidgetPredicate(
        (widget) => widget is SegmentedButton<WidgetDisplayMode>,
      ),
    );

Future<void> _waitForSaveAttempt(
  WidgetTester tester,
  Future<void> attempted,
) async {
  // Let preference transactions and their platform messages leave FakeAsync
  // before waiting for the native save notification in the real async zone.
  await _settleAsyncWork(tester);
  await tester.runAsync(() => attempted.timeout(const Duration(seconds: 3)));
  await _settleAsyncWork(tester);
}

Future<void> _settleAsyncWork(WidgetTester tester) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _capture(
  WidgetTester tester,
  _RecoveryFixture fixture,
  _ViewportSpec viewport,
  AppLocale locale,
) async {
  if (Platform.environment[_captureEnv] != '1') return;
  await tester.pump(const Duration(milliseconds: 20));
  await tester.runAsync(() async {
    final boundary =
        fixture.captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$_captureDirectory/${locale.name}-${viewport.name}.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

class _ViewportSpec {
  const _ViewportSpec(this.name, this.size);

  final String name;
  final Size size;
}

class _RecoveryFixture {
  static const _initialSelection = WidgetDisplayModeSelection(
    mode: 'detailed',
    intentId: _intentId,
    pending: true,
  );

  _RecoveryFixture({this.brandId})
    : store = _MemoryPreferencesStore(
        initialValues: <String, Object>{
          'flutter.active_brand': ?brandId,
          'flutter.${WidgetDisplayModeSelection.storageKey}': _initialSelection
              .encode(),
          'flutter.${WidgetDisplayModeSelection.legacyKey}': 'detailed',
        },
      );

  final _MemoryPreferencesStore store;
  final String? brandId;
  final _FakeHomeWidget native = _FakeHomeWidget();
  final ThemeProvider theme = ThemeProvider();
  final GlobalKey captureKey = GlobalKey();
  int dashboardRefreshCalls = 0;

  SharedPreferencesStorePlatform? _previousStore;
  Future<bool> Function()? _previousDashboardRefresher;
  bool? _previousHomeWidgetSupport;
  bool? _previousAndroidOverride;
  bool _screenshotFontsLoaded = false;
  bool _installed = false;

  static const _homeWidgetChannel = MethodChannel('home_widget');
  static const _widgetChannel = MethodChannel('duoyi/widgets');

  Future<void> mount(
    WidgetTester tester, {
    required Size viewport,
    double textScale = 1,
    AppLocale locale = AppLocale.zh,
    bool loadScreenshotFonts = false,
  }) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    _previousStore = SharedPreferencesStorePlatform.instance;
    _previousDashboardRefresher = HomeWidgetService.dashboardDataRefresher;
    _previousHomeWidgetSupport = HomeWidgetService.supportedForTesting;
    _previousAndroidOverride = AndroidWidgetManager.debugIsAndroidOverride;

    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferencesStorePlatform.instance = store;
    if (brandId != null) await tester.runAsync(theme.loadFromStorage);
    I18n.setLocale(locale);
    HomeWidgetService.supportedForTesting = true;
    AndroidWidgetManager.debugIsAndroidOverride = true;
    HomeWidgetService.dashboardDataRefresher = () async {
      dashboardRefreshCalls++;
      return true;
    };
    messenger.setMockMethodCallHandler(_homeWidgetChannel, native.handle);
    messenger.setMockMethodCallHandler(_widgetChannel, _handleWidgetMethod);

    if (loadScreenshotFonts) {
      await tester.runAsync(loadWidgetPolishScreenshotFonts);
      _screenshotFontsLoaded = true;
    }
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _appTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: RepaintBoundary(key: captureKey, child: child!),
          ),
          home: const WidgetScreen(hostPlatform: WidgetHostPlatform.android),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _installed = true;
  }

  ThemeData get _appTheme {
    final brandTheme = theme.brand.theme;
    if (!_screenshotFontsLoaded) return brandTheme;
    return brandTheme.copyWith(
      textTheme: _withScreenshotFonts(brandTheme.textTheme),
      primaryTextTheme: _withScreenshotFonts(brandTheme.primaryTextTheme),
      snackBarTheme: brandTheme.snackBarTheme.copyWith(
        contentTextStyle: _screenshotStyle(
          brandTheme.snackBarTheme.contentTextStyle,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: brandTheme.textButtonTheme.style?.copyWith(
          textStyle: WidgetStateProperty.resolveWith(
            (states) => _screenshotStyle(
              brandTheme.textButtonTheme.style?.textStyle?.resolve(states),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle? _screenshotStyle(TextStyle? style) => style?.copyWith(
    fontFamily: 'DuoyiScreenshotLatin',
    fontFamilyFallback: const ['DuoyiScreenshot'],
  );

  TextTheme _withScreenshotFonts(TextTheme text) {
    TextStyle? font(TextStyle? style) => style?.copyWith(
      fontFamily: 'DuoyiScreenshotLatin',
      fontFamilyFallback: const ['DuoyiScreenshot'],
    );
    return text.copyWith(
      displayLarge: font(text.displayLarge),
      displayMedium: font(text.displayMedium),
      displaySmall: font(text.displaySmall),
      headlineLarge: font(text.headlineLarge),
      headlineMedium: font(text.headlineMedium),
      headlineSmall: font(text.headlineSmall),
      titleLarge: font(text.titleLarge),
      titleMedium: font(text.titleMedium),
      titleSmall: font(text.titleSmall),
      bodyLarge: font(text.bodyLarge),
      bodyMedium: font(text.bodyMedium),
      bodySmall: font(text.bodySmall),
      labelLarge: font(text.labelLarge),
      labelMedium: font(text.labelMedium),
      labelSmall: font(text.labelSmall),
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_installed) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_homeWidgetChannel, null);
    messenger.setMockMethodCallHandler(_widgetChannel, null);
    HomeWidgetService.dashboardDataRefresher = _previousDashboardRefresher;
    HomeWidgetService.supportedForTesting = _previousHomeWidgetSupport;
    AndroidWidgetManager.debugIsAndroidOverride = _previousAndroidOverride;
    SharedPreferences.resetStatic();
    final previousStore = _previousStore;
    if (previousStore != null) {
      SharedPreferencesStorePlatform.instance = previousStore;
    }
    tester.view.reset();
    I18n.setLocale(AppLocale.zh);
    theme.dispose();
  }
}

class _MemoryPreferencesStore extends InMemorySharedPreferencesStore {
  _MemoryPreferencesStore({required Map<String, Object> initialValues})
    : super.withData(initialValues);

  int mutationCount = 0;

  @override
  Future<bool> setValue(String type, String key, Object value) {
    mutationCount++;
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) {
    mutationCount++;
    return super.remove(key);
  }
}

class _FakeHomeWidget {
  final Map<String, Object?> values = <String, Object?>{
    'widget_display_mode': 'standard',
  };
  final List<Object?> displayModeSaveValues = <Object?>[];
  bool failNextDisplayModeSave = false;
  Completer<void>? _nextDisplayModeSave;

  Future<void> watchNextDisplayModeSave() {
    final next = Completer<void>();
    _nextDisplayModeSave = next;
    return next.future;
  }

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments as Map?;
    switch (call.method) {
      case 'setAppGroupId':
        return true;
      case 'getWidgetData':
        return values[args?['id']?.toString()];
      case 'saveWidgetData':
        final key = args?['id']?.toString();
        final value = args?['data'];
        if (key == 'widget_display_mode') {
          displayModeSaveValues.add(value);
          final waiter = _nextDisplayModeSave;
          _nextDisplayModeSave = null;
          if (waiter != null && !waiter.isCompleted) waiter.complete();
          if (failNextDisplayModeSave) {
            failNextDisplayModeSave = false;
            return false;
          }
        }
        if (key != null) values[key] = value;
        return true;
      case 'updateWidget':
        return null;
      default:
        return null;
    }
  }
}

Future<Object?> _handleWidgetMethod(MethodCall call) async =>
    switch (call.method) {
      'canRequestPinWidget' || 'canOpenWidgetSettings' => true,
      'applyWidgetDisplayMode' || 'refreshAllWidgets' => 0,
      _ => null,
    };
