// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart'
    show AppSurfaceStyle, DesignTokens;
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
    show AppDialog, AppModalSheet, appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/retained_dialog_text_probe.dart';
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

/// Waits for the actual observable mutation outcome across the fake-frame and
/// real-I/O zones. A completed account drain alone does not mean that a dialog's
/// real-zone continuation has started its write or restored enabled controls.
Future<void> _waitForUiState(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  final deadline = Stopwatch()..start();
  while (!ready() && deadline.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(() => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5)));
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
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'] ??
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
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
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final file = File('$resolvedDir/countdown-retained-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
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

enum _CountdownOutcome {
  deleteDeniedThenSave,
  editorCancel,
  deleteConfirmedFromEditor,
  swipeDeleteDeniedThenConfirmed,
}

class _CountdownRetainedScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final String targetBrand;
  final Size size;
  final double scale;
  final _CountdownOutcome outcome;

  const _CountdownRetainedScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.size,
    required this.scale,
    required this.outcome,
  });
}

const _scenarios = <_CountdownRetainedScenario>[
  _CountdownRetainedScenario(
    name: 'zh-portrait-320x844-scale2-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    scale: 2.0,
    outcome: _CountdownOutcome.deleteDeniedThenSave,
  ),
  _CountdownRetainedScenario(
    name: 'en-portrait-390x844-scale1-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(390, 844),
    scale: 1.0,
    outcome: _CountdownOutcome.editorCancel,
  ),
  _CountdownRetainedScenario(
    name: 'zh-landscape-844x390-scale1-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(844, 390),
    scale: 1.0,
    outcome: _CountdownOutcome.deleteConfirmedFromEditor,
  ),
  _CountdownRetainedScenario(
    name: 'en-nonlinear-332x844-scaleNonlinear-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(332, 844),
    scale: -1.0,
    outcome: _CountdownOutcome.swipeDeleteDeniedThenConfirmed,
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'countdown retained theme priority defaultBrand <-> liquidGlass ${scenario.name}',
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
          fail(
            'Unexpected network call during countdown fixture: '
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

          expect(theme.brand.id, scenario.initialBrand);
          expect(theme.isBrandUnlocked(scenario.targetBrand), isTrue);
          expect(countdownProvider.items.length, 4);

          final baselineCountdownWrites = store.countdownWrites;

          void assertZeroCountdownPersistence(String stage) {
            expect(
              store.countdownWrites,
              baselineCountdownWrites,
              reason:
                  '$stage: expected zero duoyi_countdowns writes '
                  '(actual=${store.countdownWrites}, baseline=$baselineCountdownWrites)',
            );
          }

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

          // 1. Verify main screen elements mounted and controls44px on FAB
          expect(find.byType(CountdownScreen), findsOneWidget);
          expect(find.byType(BrandRouteSurface), findsOneWidget);
          final addButton = find.byKey(const ValueKey('countdown_add_button'));
          _assertControl44(tester, addButton, 'Countdown add FAB');

          // Verify list scrollable exists and establish nonzero scroll on list
          final mainListScrollable = find.descendant(
            of: find.byType(CountdownScreen),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          ).first;
          expect(mainListScrollable, findsOneWidget);

          final mainScrollPos =
              tester.state<ScrollableState>(mainListScrollable).position;
          if (mainScrollPos.maxScrollExtent > 0) {
            mainScrollPos.jumpTo(
              (mainScrollPos.maxScrollExtent * 0.4).clamp(10.0, 120.0),
            );
            await _boundedPumpAndSettle(tester);
          }
          final listOffset =
              tester.state<ScrollableState>(mainListScrollable).position.pixels;
          if (mainScrollPos.maxScrollExtent > 0) {
            expect(listOffset, greaterThan(0.0));
          }

          assertZeroCountdownPersistence('1. initial screen load with nonzero list scroll');
          await _capture(tester, boundary, '${scenario.name}-01-initial-list');

          // Check category display on cards:
          // Generated default item:
          final generatedCard =
              find.byKey(const ValueKey('countdown_card_item-generated-default'));
          expect(generatedCard, findsOneWidget);
          final expectedGeneratedLabel = scenario.initialLocale == AppLocale.en
              ? 'Default'
              : '默认';
          expect(
            find.descendant(
              of: generatedCard,
              matching: find.text(expectedGeneratedLabel),
            ),
            findsOneWidget,
            reason: 'Generated category label follows initial locale',
          );

          // User-authored literal '默认':
          final authoredDefaultCard = find.byKey(
            const ValueKey('countdown_card_item-authored-default-literal'),
          );
          expect(authoredDefaultCard, findsOneWidget);
          expect(
            find.descendant(
              of: authoredDefaultCard,
              matching: find.text('默认'),
            ),
            findsOneWidget,
            reason: 'Authored category literal "默认" preserved in card',
          );

          // User-authored custom 'ProjectAlpha':
          final authoredAlphaCard = find.byKey(
            const ValueKey('countdown_card_item-authored-custom-alpha'),
          );
          expect(authoredAlphaCard, findsOneWidget);
          expect(
            find.descendant(
              of: authoredAlphaCard,
              matching: find.text('ProjectAlpha'),
            ),
            findsOneWidget,
            reason: 'Authored custom category literal preserved in card',
          );

          void assertBrandSurface(String expectedBrandId, String stage) {
            expect(
              theme.brand.id,
              expectedBrandId,
              reason: '$stage: ThemeProvider brand id',
            );
            final expectedBrand = AppBrands.byId(expectedBrandId);
            final screenElement = tester.element(find.byType(CountdownScreen));
            final controlTheme = Theme.of(screenElement);
            expect(
              controlTheme.colorScheme.primary,
              equals(expectedBrand.theme.colorScheme.primary),
              reason: '$stage: primary color match',
            );

            final modalSheet = find.byType(AppModalSheet);
            if (modalSheet.evaluate().isNotEmpty) {
              final sheetElement = tester.element(modalSheet.last);
              final surfaceStyle = appSurfaceStyleOf(sheetElement);
              if (expectedBrandId == 'liquidGlass') {
                expect(
                  surfaceStyle,
                  equals(AppSurfaceStyle.liquidGlass),
                  reason: '$stage: sheet liquidGlass style',
                );
              } else {
                expect(
                  surfaceStyle,
                  isNot(equals(AppSurfaceStyle.liquidGlass)),
                  reason: '$stage: sheet non-liquidGlass style',
                );
                expect(
                  surfaceStyle?.sheetTopRadius,
                  equals(DesignTokens.sheetIosTopRadius),
                  reason: '$stage: sheetTopRadius default brand token',
                );
              }
            }

            final dialogFinder = find.byType(AppDialog);
            if (dialogFinder.evaluate().isNotEmpty) {
              final dialogElement = tester.element(dialogFinder.last);
              final surfaceStyle = appSurfaceStyleOf(dialogElement);
              if (expectedBrandId == 'liquidGlass') {
                expect(
                  surfaceStyle,
                  equals(AppSurfaceStyle.liquidGlass),
                  reason: '$stage: dialog liquidGlass style',
                );
              } else {
                expect(
                  surfaceStyle,
                  isNot(equals(AppSurfaceStyle.liquidGlass)),
                  reason: '$stage: dialog non-liquidGlass style',
                );
              }
            }
          }

          if (scenario.outcome ==
              _CountdownOutcome.swipeDeleteDeniedThenConfirmed) {
            // Flow 4: Swipe actions and direct delete confirmation from list with nonzero scroll
            await tester.ensureVisible(authoredAlphaCard);
            await _boundedPumpAndSettle(tester);

            // Drag card horizontally to reveal swipe actions
            await tester.drag(authoredAlphaCard, const Offset(-120, 0));
            await _boundedPumpAndSettle(tester);

            final swipeDeleteButton = find.byKey(
              const ValueKey('countdown_swipe_delete_button'),
            );
            expect(swipeDeleteButton, findsOneWidget);
            _assertControl44(
              tester,
              swipeDeleteButton,
              'Swipe inline delete button',
            );

            // Tap swipe delete -> opens delete confirmation AppDialog
            await tester.runAsync(() => tester.tap(swipeDeleteButton));
            await _boundedPumpAndSettle(tester);
            expect(find.byType(AppDialog), findsOneWidget);
            assertZeroCountdownPersistence('Swipe delete dialog opened');

            final initialDialogElement = tester.element(find.byType(AppDialog));
            final initialDialogRoute = ModalRoute.of(initialDialogElement);

            // Live brand switch while delete confirmation is open
            await tester.runAsync(() async {
              final switched = await theme.setBrand(scenario.targetBrand);
              expect(switched, isTrue);
              await AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              );
            });
            await _boundedPumpAndSettle(tester);
            assertBrandSurface(
              scenario.targetBrand,
              'Swipe delete dialog targetBrand',
            );
            expect(
              tester.element(find.byType(AppDialog)),
              same(initialDialogElement),
              reason: 'Dialog element preserved across brand switch',
            );
            expect(
              ModalRoute.of(tester.element(find.byType(AppDialog))),
              same(initialDialogRoute),
              reason: 'Dialog route preserved across brand switch',
            );
            assertZeroCountdownPersistence('After brand switch with dialog open');

            // Live brand roundtrip back
            await tester.runAsync(() async {
              final reverted = await theme.setBrand(scenario.initialBrand);
              expect(reverted, isTrue);
              await AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              );
            });
            await _boundedPumpAndSettle(tester);
            assertBrandSurface(
              scenario.initialBrand,
              'Swipe delete dialog revertedBrand',
            );
            assertZeroCountdownPersistence('After brand revert with dialog open');

            // Live locale switch while dialog open
            I18n.setLocale(scenario.alternateLocale);
            await _boundedPumpAndSettle(tester);
            expect(find.byType(AppDialog), findsOneWidget);

            // Full generated labels check with verifyRetainedDialogText
            final altDeleteTitle = I18n.tr('anniversary.delete.title');
            final altDeleteContent =
                '"Project Alpha Target" ${I18n.tr('anniversary.delete.content_suffix')}';
            final altCancelText = I18n.tr('action.cancel');
            final altDeleteText = I18n.tr('action.delete');

            await verifyRetainedDialogText(
              tester,
              find.descendant(
                of: find.byType(AppDialog),
                matching: find.text(altDeleteTitle),
              ),
              expected: altDeleteTitle,
            );
            await verifyRetainedDialogText(
              tester,
              find.descendant(
                of: find.byType(AppDialog),
                matching: find.text(altDeleteContent),
              ),
              expected: altDeleteContent,
            );

            // Controls44px on dialog buttons
            final dialogCancelBtn = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(TextButton, altCancelText),
            );
            final dialogDeleteBtn = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(FilledButton, altDeleteText),
            );
            _assertControl44(
              tester,
              dialogCancelBtn,
              'Delete dialog cancel button',
            );
            _assertControl44(
              tester,
              dialogDeleteBtn,
              'Delete dialog confirm button',
            );

            // Live locale roundtrip back to initialLocale
            I18n.setLocale(scenario.initialLocale);
            await _boundedPumpAndSettle(tester);
            expect(find.byType(AppDialog), findsOneWidget);

            await _capture(
              tester,
              boundary,
              '${scenario.name}-02-swipe-delete-dialog-open',
            );

            // 1. Denied / Cancel the deletion dialog
            final cancelBtnCurrent = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(
                TextButton,
                I18n.tr('action.cancel'),
              ),
            );
            await tester.tap(cancelBtnCurrent);
            await _boundedPumpAndSettle(tester);
            await _waitForUiState(tester, () =>
              find.byType(AppDialog).evaluate().isEmpty &&
              authoredAlphaCard.evaluate().isNotEmpty &&
              find.ancestor(of: authoredAlphaCard, matching: find.byWidgetPredicate(
                (widget) => widget is AbsorbPointer && widget.absorbing,
              )).evaluate().isEmpty,
              'Cancelled swipe deletion restores an interactive card without writes');

            expect(find.byType(AppDialog), findsNothing);
            expect(
              countdownProvider.items.any(
                (item) => item.id == 'item-authored-custom-alpha',
              ),
              isTrue,
              reason: 'Item must remain after cancel',
            );
            assertZeroCountdownPersistence('After cancel in swipe delete dialog');

            // 2. Open delete confirmation again and confirm deletion
            await tester.ensureVisible(authoredAlphaCard);
            await _boundedPumpAndSettle(tester);
            await tester.drag(authoredAlphaCard, const Offset(-120, 0));
            await _boundedPumpAndSettle(tester);
            await tester.runAsync(
              () => tester.tap(
                find.byKey(const ValueKey('countdown_swipe_delete_button')),
              ),
            );
            await _boundedPumpAndSettle(tester);
            expect(find.byType(AppDialog), findsOneWidget);

            final confirmDeleteBtn = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(
                FilledButton,
                I18n.tr('action.delete'),
              ),
            );
            await tester.ensureVisible(confirmDeleteBtn);
            await tester.runAsync(() => tester.tap(confirmDeleteBtn));
            await _drainAccountWrites(tester);
            await _boundedPumpAndSettle(tester);
            await _waitForUiState(tester, () =>
              !countdownProvider.items.any((item) => item.id == 'item-authored-custom-alpha') &&
              store.countdownWrites == baselineCountdownWrites + 1,
              'Confirmed swipe deletion commits exactly once before checking resolution');

            expect(find.byType(AppDialog), findsNothing);
            expect(
              countdownProvider.items.any(
                (item) => item.id == 'item-authored-custom-alpha',
              ),
              isFalse,
              reason: 'Item must be deleted after confirm',
            );
            expect(
              store.countdownWrites,
              baselineCountdownWrites + 1,
              reason: 'Exactly 1 write must occur upon confirmed deletion',
            );
            await _capture(
              tester,
              boundary,
              '${scenario.name}-03-swipe-deleted-resolved',
            );
          } else {
            // Flows 1, 2, 3: Editor workflows (editing an existing item with category)
            final targetCardId = scenario.outcome == _CountdownOutcome.editorCancel
                ? 'item-authored-custom-alpha'
                : (scenario.outcome ==
                        _CountdownOutcome.deleteConfirmedFromEditor
                    ? 'item-authored-work'
                    : 'item-authored-default-literal');

            final cardToOpen = find.byKey(ValueKey('countdown_card_$targetCardId'));
            await tester.scrollUntilVisible(
              cardToOpen,
              120,
              scrollable: mainListScrollable,
            );
            expect(cardToOpen, findsOneWidget);
            await tester.ensureVisible(cardToOpen);
            await _boundedPumpAndSettle(tester);
            await tester.tap(cardToOpen);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(find.byType(AppModalSheet), findsOneWidget);
            assertZeroCountdownPersistence('Editor sheet opened');

            final textFields = find.descendant(
              of: find.byType(AppModalSheet),
              matching: find.byType(TextField),
            );
            expect(textFields, findsNWidgets(2));
            final titleField = textFields.first;
            final categoryField = textFields.last;

            final titleController =
                tester.widget<TextField>(titleField).controller!;
            final categoryController =
                tester.widget<TextField>(categoryField).controller!;

            Finder findTitleField() => find.byWidgetPredicate(
              (w) => w is TextField && identical(w.controller, titleController),
            );

            final initialEditorState = _countdownEditorState(
              tester,
              findTitleField(),
            );
            final initialModalRoute = ModalRoute.of(
              tester.element(findTitleField()),
            );

            // Verify user-authored category literal is preserved in text field
            if (targetCardId == 'item-authored-default-literal') {
              expect(
                categoryController.text,
                '默认',
                reason: 'Authored literal "默认" preserved in editor',
              );
            } else if (targetCardId == 'item-authored-custom-alpha') {
              expect(
                categoryController.text,
                'ProjectAlpha',
                reason: 'Authored category "ProjectAlpha" preserved in editor',
              );
            } else if (targetCardId == 'item-authored-work') {
              expect(
                categoryController.text,
                '工作',
                reason: 'Authored category "工作" preserved in editor',
              );
            }

            // Set active category text and text selection ("while category selected")
            const draftCategorySelection = TextSelection(
              baseOffset: 0,
              extentOffset: 2,
            );
            categoryController.selection = draftCategorySelection;
            await tester.pump();
            expect(categoryController.selection, draftCategorySelection);

            // Establish nonzero scroll in editor modal sheet
            Finder findEditorScrollable() => find.descendant(
              of: find.byType(AppModalSheet).last,
              matching: find.byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              ),
            );
            final editorScrollable = findEditorScrollable();
            expect(editorScrollable, findsOneWidget);

            final initialEditorMaxExtent = tester
                .state<ScrollableState>(editorScrollable)
                .position
                .maxScrollExtent;
            if (initialEditorMaxExtent > 0) {
              tester
                  .state<ScrollableState>(editorScrollable)
                  .position
                  .jumpTo((initialEditorMaxExtent * 0.4).clamp(10.0, 80.0));
              await _boundedPumpAndSettle(tester);
            }
            final initialEditorScrollOffset = tester
                .state<ScrollableState>(editorScrollable)
                .position
                .pixels;

            // Verify controls44px on editor action buttons
            final editorCancelBtn = find.descendant(
              of: find.byType(AppModalSheet).last,
              matching: find.widgetWithText(
                TextButton,
                I18n.tr('action.cancel'),
              ),
            );
            final editorSaveBtn = find.byKey(
              const ValueKey('countdown_editor_save_button'),
            );
            final editorDeleteBtn = find.descendant(
              of: find.byType(AppModalSheet).last,
              matching: find.widgetWithText(
                TextButton,
                I18n.tr('action.delete'),
              ),
            );

            _assertControl44(tester, editorCancelBtn, 'Editor Cancel button');
            _assertControl44(tester, editorSaveBtn, 'Editor Save button');
            _assertControl44(tester, editorDeleteBtn, 'Editor Delete button');

            assertZeroCountdownPersistence('Draft state established in editor');
            await _capture(
              tester,
              boundary,
              '${scenario.name}-02-editor-draft-open',
              scrollableFinder: editorScrollable,
              scrollToOffset: initialEditorScrollOffset,
              restoreOffset: initialEditorScrollOffset,
            );

            // Live brand switch while editor is open
            await tester.runAsync(() async {
              final switched = await theme.setBrand(scenario.targetBrand);
              expect(switched, isTrue);
              await AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              );
            });
            await _boundedPumpAndSettle(tester);
            assertBrandSurface(
              scenario.targetBrand,
              'Editor open targetBrand switch',
            );

            // Verify editor state retained across brand switch
            expect(
              identical(
                _countdownEditorState(tester, findTitleField()),
                initialEditorState,
              ),
              isTrue,
              reason: 'Editor state identity retained across brand switch',
            );
            expect(
              identical(
                ModalRoute.of(tester.element(findTitleField())),
                initialModalRoute,
              ),
              isTrue,
              reason: 'Editor route identity retained across brand switch',
            );
            expect(categoryController.selection, draftCategorySelection);
            final offsetAfterBrand = tester
                .state<ScrollableState>(findEditorScrollable())
                .position
                .pixels;
            expect(offsetAfterBrand, equals(initialEditorScrollOffset));
            assertZeroCountdownPersistence('After brand switch in editor');

            // Live brand roundtrip back
            await tester.runAsync(() async {
              final reverted = await theme.setBrand(scenario.initialBrand);
              expect(reverted, isTrue);
              await AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              );
            });
            await _boundedPumpAndSettle(tester);
            assertBrandSurface(
              scenario.initialBrand,
              'Editor open revertedBrand switch',
            );
            expect(
              identical(
                _countdownEditorState(tester, findTitleField()),
                initialEditorState,
              ),
              isTrue,
            );
            expect(categoryController.selection, draftCategorySelection);
            assertZeroCountdownPersistence('After brand roundtrip in editor');

            // Live locale switch while editor is open
            I18n.setLocale(scenario.alternateLocale);
            await _boundedPumpAndSettle(tester);
            expect(find.text(I18n.tr('countdown.editor.edit_title')), findsOneWidget);
            expect(find.text(I18n.tr('action.save')), findsOneWidget);
            expect(find.text(I18n.tr('action.cancel')), findsOneWidget);
            expect(find.text(I18n.tr('action.delete')), findsOneWidget);

            // Verify user-authored category literals are NOT corrupted by locale change
            if (targetCardId == 'item-authored-default-literal') {
              expect(
                categoryController.text,
                '默认',
                reason: 'Authored literal "默认" remains authored after locale switch',
              );
            }
            expect(categoryController.selection, draftCategorySelection);
            assertZeroCountdownPersistence('After locale switch in editor');

            // Live locale roundtrip back
            I18n.setLocale(scenario.initialLocale);
            await _boundedPumpAndSettle(tester);
            expect(find.text(I18n.tr('countdown.editor.edit_title')), findsOneWidget);
            expect(categoryController.selection, draftCategorySelection);
            assertZeroCountdownPersistence('After locale roundtrip in editor');

            if (scenario.outcome == _CountdownOutcome.editorCancel) {
              // Outcome: Cancel editor
              final cancelBtn = find.descendant(
                of: find.byType(AppModalSheet).last,
                matching: find.widgetWithText(
                  TextButton,
                  I18n.tr('action.cancel'),
                ),
              );
              await tester.ensureVisible(cancelBtn);
              await _boundedPumpAndSettle(tester);
              await tester.tap(cancelBtn);
              await _boundedPumpAndSettle(tester);

              expect(find.byType(AppModalSheet), findsNothing);
              assertZeroCountdownPersistence('After editor cancel');
              expect(countdownProvider.items.length, 4);
              await _capture(
                tester,
                boundary,
                '${scenario.name}-03-editor-cancelled',
              );
            } else {
              // Delete confirmation flow from inside editor
              final deleteBtn = find.descendant(
                of: find.byType(AppModalSheet).last,
                matching: find.widgetWithText(
                  TextButton,
                  I18n.tr('action.delete'),
                ),
              );
              await tester.ensureVisible(deleteBtn);
              await _boundedPumpAndSettle(tester);
              await tester.runAsync(() => tester.tap(deleteBtn));
              await _boundedPumpAndSettle(tester);
              expect(find.byType(AppDialog), findsOneWidget);
              assertZeroCountdownPersistence('Delete confirmation dialog opened from editor');

              final dialogElement = tester.element(find.byType(AppDialog));
              final dialogRoute = ModalRoute.of(dialogElement);

              // Live brand switch while delete confirmation is open
              await tester.runAsync(() async {
                final switched = await theme.setBrand(scenario.targetBrand);
                expect(switched, isTrue);
                await AccountPreferenceWrites.drain().timeout(
                  const Duration(seconds: 5),
                );
              });
              await _boundedPumpAndSettle(tester);
              assertBrandSurface(
                scenario.targetBrand,
                'Delete confirmation open targetBrand',
              );
              expect(
                tester.element(find.byType(AppDialog)),
                same(dialogElement),
                reason: 'Delete dialog element retained across brand switch',
              );
              expect(
                ModalRoute.of(tester.element(find.byType(AppDialog))),
                same(dialogRoute),
                reason: 'Delete dialog route retained across brand switch',
              );
              assertZeroCountdownPersistence('After brand switch with dialog open');

              // Live brand roundtrip back
              await tester.runAsync(() async {
                final reverted = await theme.setBrand(scenario.initialBrand);
                expect(reverted, isTrue);
                await AccountPreferenceWrites.drain().timeout(
                  const Duration(seconds: 5),
                );
              });
              await _boundedPumpAndSettle(tester);
              assertBrandSurface(
                scenario.initialBrand,
                'Delete confirmation open revertedBrand',
              );
              assertZeroCountdownPersistence('After brand roundtrip with dialog open');

              // Live locale switch while delete confirmation is open
              I18n.setLocale(scenario.alternateLocale);
              await _boundedPumpAndSettle(tester);
              expect(find.byType(AppDialog), findsOneWidget);

              final itemTitle = targetCardId == 'item-authored-work'
                  ? 'Work Sprint Review'
                  : 'Authored Literal Default';

              final expectedDialogTitle = I18n.tr('anniversary.delete.title');
              final expectedDialogContent =
                  '"$itemTitle" ${I18n.tr('anniversary.delete.content_suffix')}';
              final expectedCancelLabel = I18n.tr('action.cancel');
              final expectedDeleteLabel = I18n.tr('action.delete');

              // Verify full generated labels with verifyRetainedDialogText
              await verifyRetainedDialogText(
                tester,
                find.descendant(
                  of: find.byType(AppDialog),
                  matching: find.text(expectedDialogTitle),
                ),
                expected: expectedDialogTitle,
              );
              await verifyRetainedDialogText(
                tester,
                find.descendant(
                  of: find.byType(AppDialog),
                  matching: find.text(expectedDialogContent),
                ),
                expected: expectedDialogContent,
              );

              final dCancel = find.descendant(
                of: find.byType(AppDialog),
                matching: find.widgetWithText(TextButton, expectedCancelLabel),
              );
              final dDelete = find.descendant(
                of: find.byType(AppDialog),
                matching: find.widgetWithText(FilledButton, expectedDeleteLabel),
              );
              _assertControl44(tester, dCancel, 'Dialog Cancel button');
              _assertControl44(tester, dDelete, 'Dialog Delete button');

              // Live locale roundtrip back
              I18n.setLocale(scenario.initialLocale);
              await _boundedPumpAndSettle(tester);
              expect(find.byType(AppDialog), findsOneWidget);

              await _capture(
                tester,
                boundary,
                '${scenario.name}-03-delete-confirmation-open',
              );

              if (scenario.outcome ==
                  _CountdownOutcome.deleteConfirmedFromEditor) {
                // Confirm delete
                final confirmBtn = find.descendant(
                  of: find.byType(AppDialog),
                  matching: find.widgetWithText(
                    FilledButton,
                    I18n.tr('action.delete'),
                  ),
                );
                await tester.ensureVisible(confirmBtn);
                await tester.runAsync(() => tester.tap(confirmBtn));
                await _drainAccountWrites(tester);
                await _boundedPumpAndSettle(tester);
                await _waitForUiState(tester, () =>
                  find.byType(AppModalSheet).evaluate().isEmpty &&
                  store.countdownWrites == baselineCountdownWrites + 1,
                  'Confirmed editor deletion commits and closes the original sheet');

                expect(find.byType(AppDialog), findsNothing);
                expect(find.byType(AppModalSheet), findsNothing);
                expect(
                  countdownProvider.items.any((item) => item.id == targetCardId),
                  isFalse,
                  reason: 'Item must be removed from provider',
                );
                expect(
                  store.countdownWrites,
                  baselineCountdownWrites + 1,
                  reason: 'Confirmed deletion must execute exactly 1 storage write',
                );
                await _capture(
                  tester,
                  boundary,
                  '${scenario.name}-04-editor-deleted-resolved',
                );
              } else if (scenario.outcome ==
                  _CountdownOutcome.deleteDeniedThenSave) {
                // Cancel dialog (denied deletion)
                final cancelDialogBtn = find.descendant(
                  of: find.byType(AppDialog),
                  matching: find.widgetWithText(
                    TextButton,
                    I18n.tr('action.cancel'),
                  ),
                );
                await tester.tap(cancelDialogBtn);
                await _boundedPumpAndSettle(tester);
                await _waitForUiState(tester, () =>
                  find.byType(AppDialog).evaluate().isEmpty &&
                  tester.widget<TextField>(findTitleField()).enabled != false,
                  'Denied editor deletion restores the editable draft before the next tap');

                expect(find.byType(AppDialog), findsNothing);
                expect(find.byType(AppModalSheet), findsOneWidget);
                assertZeroCountdownPersistence('After delete denial, editor remains open');
                expect(
                  countdownProvider.items.any((item) => item.id == targetCardId),
                  isTrue,
                );

                // Now modify title draft slightly and save
                final currentTitleField = findTitleField();
                await tester.ensureVisible(currentTitleField);
                await _boundedPumpAndSettle(tester);
                await tester.tap(currentTitleField);
                await tester.enterText(
                  currentTitleField,
                  'Authored Literal Default Updated',
                );
                await tester.pump();

                final saveBtn = find.byKey(
                  const ValueKey('countdown_editor_save_button'),
                );
                await tester.ensureVisible(saveBtn);
                await _boundedPumpAndSettle(tester);
                await tester.runAsync(() => tester.tap(saveBtn));
                await _drainAccountWrites(tester);
                await _boundedPumpAndSettle(tester);
                await _waitForUiState(tester, () =>
                  find.byType(AppModalSheet).evaluate().isEmpty &&
                  store.countdownWrites == baselineCountdownWrites + 1,
                  'Saved draft commits exactly once and closes its sheet');

                expect(find.byType(AppModalSheet), findsNothing);
                expect(
                  store.countdownWrites,
                  baselineCountdownWrites + 1,
                  reason: 'Save must execute exactly 1 storage write',
                );

                final updatedItem = countdownProvider.items.firstWhere(
                  (item) => item.id == targetCardId,
                );
                expect(updatedItem.title, 'Authored Literal Default Updated');
                expect(
                  updatedItem.category,
                  '默认',
                  reason: 'User-authored literal "默认" preserved across save',
                );
                expect(
                  updatedItem.categoryIsDefault,
                  isFalse,
                  reason: 'User-authored literal remains non-default categoryIsDefault flag',
                );

                await _capture(
                  tester,
                  boundary,
                  '${scenario.name}-04-editor-saved-resolved',
                );
              }
            }
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
