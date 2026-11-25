// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_display_mode_store.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';

const _captureEnv = 'DUOYI_CAPTURE_WIDGET_LIVE_BRAND_SCREENSHOTS';
const _intentId = 'widget-recovery-live-brand-20261023-pending';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets(
    'pending mode-delivery intent survives live brand switch and page retry executes exactly one delivery',
    (tester) async {
      final fixture = _RecoveryFixture();
      addTearDown(() => fixture.dispose(tester));
      await fixture.mount(tester, viewport: const Size(390, 844));

      final prefs = await SharedPreferences.getInstance();
      final initialSelection = WidgetDisplayModeSelection.read(prefs);
      expect(initialSelection.intentId, _intentId);
      expect(initialSelection.pending, isTrue);
      expect(initialSelection.mode, 'detailed');
      expect(fixture.theme.brand.id, 'defaultBrand');
      expect(fixture.native.displayModeSaveValues, isEmpty);

      final pendingFinder = find.byKey(
        const ValueKey('widget_style_sync_pending'),
      );
      final retryFinder = find.byKey(const ValueKey('widget_style_sync_retry'));
      await Scrollable.ensureVisible(tester.element(retryFinder), alignment: 1);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(pendingFinder, findsOneWidget);
      expect(retryFinder.hitTestable(), findsOneWidget);

      // Live brand switch to liquidGlass on the same mounted screen
      await tester.runAsync(() async {
        final switched = await fixture.theme.setBrand('liquidGlass');
        expect(switched, isTrue);
      });
      await _settleAsyncWork(tester);

      expect(fixture.theme.brand.id, 'liquidGlass');
      expect(prefs.getString('active_brand'), 'liquidGlass');
      final activeTheme = Theme.of(tester.element(find.byType(WidgetScreen)));
      expect(
        activeTheme.colorScheme.primary,
        AppBrands.liquidGlass.theme.colorScheme.primary,
      );

      // Verify on the same mounted screen: intent identity unchanged, pending stays true
      final selectionInGlass = WidgetDisplayModeSelection.read(prefs);
      expect(selectionInGlass.intentId, _intentId);
      expect(selectionInGlass.pending, isTrue);
      expect(selectionInGlass.mode, 'detailed');
      expect(pendingFinder, findsOneWidget);
      expect(retryFinder.hitTestable(), findsOneWidget);
      expect(fixture.native.displayModeSaveValues, isEmpty);

      // Live brand switch back to defaultBrand
      await tester.runAsync(() async {
        final reverted = await fixture.theme.setBrand('defaultBrand');
        expect(reverted, isTrue);
      });
      await _settleAsyncWork(tester);

      expect(fixture.theme.brand.id, 'defaultBrand');
      expect(prefs.getString('active_brand'), 'defaultBrand');
      final selectionInDefault = WidgetDisplayModeSelection.read(prefs);
      expect(selectionInDefault.intentId, _intentId);
      expect(selectionInDefault.pending, isTrue);
      expect(selectionInDefault.mode, 'detailed');
      expect(pendingFinder, findsOneWidget);
      expect(retryFinder.hitTestable(), findsOneWidget);

      // Switch back to liquidGlass for retry delivery verification
      await tester.runAsync(() async {
        final switchedAgain = await fixture.theme.setBrand('liquidGlass');
        expect(switchedAgain, isTrue);
      });
      await _settleAsyncWork(tester);

      // Execute page retry
      final retryAttempt = fixture.native.watchNextDisplayModeSave();
      await tester.runAsync(() => tester.tap(retryFinder));
      await _waitForSaveAttempt(tester, retryAttempt);
      await _settleAsyncWork(tester);

      // Verify exactly one retry delivery sent to native host channel
      expect(fixture.native.displayModeSaveValues, ['detailed']);
      final confirmed = WidgetDisplayModeSelection.read(prefs);
      expect(confirmed.mode, 'detailed');
      expect(confirmed.pending, isFalse);
      expect(confirmed.intentId, _intentId);
      expect(
        find.byKey(const ValueKey('widget_style_sync_pending')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('widget_style_sync_retry')),
        findsNothing,
      );
      expect(fixture.dashboardRefreshCalls, 0);
      expect(tester.takeException(), isNull);
      await _captureScreenshot(
        tester,
        fixture,
        '01-retry-confirmed-liquidGlass',
      );
    },
  );

  testWidgets(
    'Add button remains disabled across live brand switch during queued recovery refresh',
    (tester) async {
      final fixture = _RecoveryFixture();
      addTearDown(() => fixture.dispose(tester));
      await fixture.mount(tester, viewport: const Size(390, 844));

      final row = find.byKey(const ValueKey(DuoyiWidgetKind.todo));
      await tester.scrollUntilVisible(
        row,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      final addButton = find.descendant(
        of: row,
        matching: find.byType(FilledButton),
      );
      expect(addButton, findsOneWidget);

      late Completer<void> gate;
      late Future<void> blocker;
      await tester.runAsync(() async {
        gate = Completer<void>();
        blocker = WidgetDisplayModeStore.runOperation(() => gate.future);
      });

      bool? addEnabledBeforeSwitch;
      bool? updatingLabelBeforeSwitch;
      bool? addEnabledAfterSwitch;
      bool? updatingLabelAfterSwitch;

      try {
        await tester.runAsync(
          () => tester.tap(find.byTooltip(WidgetUiCopy.refreshTooltip)),
        );
        await tester.pump();

        addEnabledBeforeSwitch =
            tester.widget<FilledButton>(addButton).onPressed != null;
        updatingLabelBeforeSwitch = find
            .descendant(
              of: addButton,
              matching: find.text(WidgetUiCopy.updatingStyle),
            )
            .evaluate()
            .isNotEmpty;

        // Live brand switch to liquidGlass while queued recovery operation is blocked
        await tester.runAsync(() async {
          final switched = await fixture.theme.setBrand('liquidGlass');
          expect(switched, isTrue);
        });
        await tester.pump();

        addEnabledAfterSwitch =
            tester.widget<FilledButton>(addButton).onPressed != null;
        updatingLabelAfterSwitch = find
            .descendant(
              of: addButton,
              matching: find.text(WidgetUiCopy.updatingStyle),
            )
            .evaluate()
            .isNotEmpty;

        expect(fixture.theme.brand.id, 'liquidGlass');
        expect(fixture.native.displayModeSaveValues, isEmpty);
        await _captureScreenshot(
          tester,
          fixture,
          '02-add-disabled-queued-liquidGlass',
        );
      } finally {
        await tester.runAsync(() async {
          gate.complete();
          await blocker.timeout(const Duration(seconds: 3));
        });
        await _settleAsyncWork(tester);
      }

      expect(addEnabledBeforeSwitch, isFalse);
      expect(updatingLabelBeforeSwitch, isTrue);
      expect(addEnabledAfterSwitch, isFalse);
      expect(updatingLabelAfterSwitch, isTrue);

      // After unblocking and completing recovery, Add button is enabled again
      expect(tester.widget<FilledButton>(addButton).onPressed, isNotNull);
      expect(fixture.native.displayModeSaveValues, ['detailed']);
      expect(fixture.dashboardRefreshCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failure snackbar retry survives live brand switch and executes exactly one retry delivery',
    (tester) async {
      final fixture = _RecoveryFixture();
      addTearDown(() => fixture.dispose(tester));
      final originalShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        await fixture.mount(tester, viewport: const Size(390, 844));

        final pageRetry = find.byKey(const ValueKey('widget_style_sync_retry'));
        await Scrollable.ensureVisible(tester.element(pageRetry), alignment: 1);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        expect(pageRetry.hitTestable(), findsOneWidget);

        fixture.native.failNextDisplayModeSave = true;
        final failedAttempt = fixture.native.watchNextDisplayModeSave();
        await tester.runAsync(() => tester.tap(pageRetry));
        await _waitForSaveAttempt(tester, failedAttempt);

        // Verify failure SnackBar appeared with retry action
        final snackbar = find.byType(SnackBar);
        final snackbarRetry = find.byKey(const ValueKey('widget_style_retry'));
        expect(snackbar, findsOneWidget);
        expect(snackbarRetry.hitTestable(), findsOneWidget);
        expect(fixture.native.displayModeSaveValues, ['detailed']);

        final prefs = await SharedPreferences.getInstance();
        final beforeSwitch = WidgetDisplayModeSelection.read(prefs);
        expect(beforeSwitch.pending, isTrue);
        expect(beforeSwitch.intentId, _intentId);

        // Live brand switch to liquidGlass while failure SnackBar is showing
        await tester.runAsync(() async {
          final switched = await fixture.theme.setBrand('liquidGlass');
          expect(switched, isTrue);
        });
        await _settleAsyncWork(tester);

        expect(fixture.theme.brand.id, 'liquidGlass');
        expect(snackbar, findsOneWidget);
        expect(snackbarRetry.hitTestable(), findsOneWidget);
        expect(find.text(WidgetUiCopy.styleSyncFailed), findsOneWidget);

        final inGlass = WidgetDisplayModeSelection.read(prefs);
        expect(inGlass.pending, isTrue);
        expect(inGlass.intentId, _intentId);
        expect(fixture.native.displayModeSaveValues, ['detailed']);
        await _captureScreenshot(
          tester,
          fixture,
          '03-snackbar-retry-survives-liquidGlass',
        );

        // Tap SnackBar retry
        final retryAttempt = fixture.native.watchNextDisplayModeSave();
        await tester.runAsync(() => tester.tap(snackbarRetry));
        await _waitForSaveAttempt(tester, retryAttempt);
        await _settleAsyncWork(tester);

        // Exactly one retry delivery sent to native
        expect(fixture.native.displayModeSaveValues, ['detailed', 'detailed']);
        final afterRetry = WidgetDisplayModeSelection.read(prefs);
        expect(afterRetry.mode, 'detailed');
        expect(afterRetry.pending, isFalse);
        expect(afterRetry.intentId, _intentId);
        expect(find.byKey(const ValueKey('widget_style_retry')), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        debugDisableShadows = originalShadows;
      }
    },
  );

  testWidgets(
    'retained pending retry cannot replace newer choice across live brand switch',
    (tester) async {
      final fixture = _RecoveryFixture();
      addTearDown(() => fixture.dispose(tester));
      await fixture.mount(tester, viewport: const Size(390, 844));

      final retryFinder = find.byKey(const ValueKey('widget_style_sync_retry'));
      await Scrollable.ensureVisible(tester.element(retryFinder), alignment: 1);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      final staleRetry = tester.widget<TextButton>(retryFinder).onPressed!;

      // Live brand switch to liquidGlass
      await tester.runAsync(() async {
        final switched = await fixture.theme.setBrand('liquidGlass');
        expect(switched, isTrue);
      });
      await _settleAsyncWork(tester);
      expect(fixture.theme.brand.id, 'liquidGlass');

      // Select a newer choice: compact
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

      // Live brand switch back to defaultBrand
      await tester.runAsync(() async {
        final reverted = await fixture.theme.setBrand('defaultBrand');
        expect(reverted, isTrue);
      });
      await _settleAsyncWork(tester);
      expect(fixture.theme.brand.id, 'defaultBrand');

      final writesBeforeStaleRetry = fixture.store.mutationCount;

      // Invoke stale retry callback
      staleRetry();
      await _settleAsyncWork(tester);

      // Stale retry must NOT revert or overwrite the newer compact choice
      final afterStaleRetry = WidgetDisplayModeSelection.read(prefs);
      expect(afterStaleRetry.mode, 'compact');
      expect(afterStaleRetry.pending, isFalse);
      expect(fixture.native.displayModeSaveValues, ['compact']);
      expect(fixture.store.mutationCount, writesBeforeStaleRetry);
      expect(tester.takeException(), isNull);
      await _captureScreenshot(
        tester,
        fixture,
        '04-stale-retry-blocked-defaultBrand',
      );
    },
  );

  // NEW2722: all four cases always execute every business/layout oracle.
  // Only explicitly requested pixels require a reserved NEW output directory.
  for (final initialBrand in ['defaultBrand', 'liquidGlass']) {
    for (final viewport in [const Size(320, 844), const Size(568, 320)]) {
      testWidgets(
        '[NEW2722 queued recovery layout] $initialBrand '
        '${viewport.width.toInt()}x${viewport.height.toInt()} scale2 '
        'preserves held recovery through mounted brand and locale transitions',
        (tester) => _runQueuedCaptureCase(tester, initialBrand, viewport),
      );
    }
  }
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
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

// NEW2722: explicit capture admission is separate from unconditional oracles.
const _queuedCaptureRequestEnv = 'DUOYI_CAPTURE_QUEUED_WIDGET_VISUAL_2722';
const _queuedEvidenceEnv = 'DUOYI_QUEUED_WIDGET_EVIDENCE_DIR_2722';
const _queuedExpectedTestEnv = 'DUOYI_QUEUED_WIDGET_TEST_SHA256_2722';
const _queuedBaselineSha =
    'd41a544c2d362c95b17a0522a7ceae10091c4f3de20fceba32c4977b8a6ce3a0';
const _queuedContractSha =
    '806b4e46c27b281ca2e2153d0c93a934fd0f81482a7b5bf5fcf73d9be1729d3a';
const _queuedProductInputs = <String, String>{
  'lib/screens/widget_screen.dart':
      'c1748bd64c1bb3a045a636677cf669748090505013f37a51e88885fd9d4ecc96',
  'lib/widgets/brand_background.dart':
      '5f8bc0d5d9b6b29c4f82a83b305c9de65fa57c0336880f256bc667cc6d214589',
  'lib/core/widget_ui_copy.dart':
      'aed5eabbae7adfc91d9c633fde4f080226e83723fc257878f80e167b099a0305',
  'lib/core/i18n.dart':
      '08b85a8387be66c57bf2f74a8a22daf828c1c38da2479c0f7b038b26d4f9762a',
  'lib/providers/theme_provider.dart':
      '124108b901f9e6a3ee85623be671e6b6ee34dfd520bf3ec02bddaefdd1cb3d2c',
  'lib/services/widget_display_mode_store.dart':
      'e0f2e7f95006655121fe89eef6b20c2bcfcd5ff7023205a7468793667a226e01',
  'lib/l10n/app_en.arb':
      '739ecbfd8974b9afd9c439bbd086cbd82c3f30f023e225b6c397a26641b1454e',
  'lib/l10n/app_zh.arb':
      '2554a5e16c7223902c9ba4616aca53900e6601efa65afdf4eced85783a35c1a5',
  'lib/l10n/generated/app_localizations.dart':
      '5ad6cd966f510a027184e9127f7ed784d2e4f48e5642ca9332c1220cffed2335',
  'lib/l10n/generated/app_localizations_en.dart':
      '2abb340c974cfa2b740b2390339a88fdad5f3abbc16e012a9b9f77d3e2797855',
  'lib/l10n/generated/app_localizations_zh.dart':
      '6ed22ceb3477bfe3fb6052a84ec1777958be641a3f4ce6a3715def8bd8e0a0a4',
};

// A font override or an external SHA alone is not a capture request. In
// particular, 2650 clears DUOYI_* then restores its packaged Latin font path.
bool get _queuedCaptureRequested =>
    Platform.environment[_queuedCaptureRequestEnv] == '1' ||
    Platform.environment[_queuedEvidenceEnv] != null ||
    Platform.environment[_captureEnv] == '1' ||
    Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] != null;

Future<void> _captureScreenshot(
  WidgetTester tester,
  _RecoveryFixture fixture,
  String name,
) async {
  final requested =
      Platform.environment[_captureEnv] == '1' ||
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] != null;
  if (!requested) return;
  final output = _QueuedEvidenceOutput.require();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  // Original bodies/oracles are untouched. Their optional pixels, if enabled,
  // also go into the newly reserved directory and cannot overwrite old PNGs.
  await _writeQueuedPixels(tester, fixture, output, 'original-$name', {
    'scope': 'original body capture; not a NEW2722 matrix frame',
    'brand': fixture.theme.brand.id,
    'locale': I18n.current.name,
    'nativeSaves': List<Object?>.of(fixture.native.displayModeSaveValues),
  });
}

Future<void> _runQueuedCaptureCase(
  WidgetTester tester,
  String initialBrand,
  Size viewport,
) async {
  final output = _queuedCaptureRequested
      ? _QueuedEvidenceOutput.require()
      : null;
  final caseId =
      '$initialBrand-${viewport.width.toInt()}x'
      '${viewport.height.toInt()}-scale2';
  final fixture = _RecoveryFixture(initialBrandId: initialBrand);
  addTearDown(() => fixture.dispose(tester));
  final semantics = tester.ensureSemantics();
  final oldShadows = debugDisableShadows;
  debugDisableShadows = false;

  try {
    await fixture.mount(
      tester,
      viewport: viewport,
      textScale: 2,
      locale: AppLocale.en,
      loadScreenshotFonts: true,
    );
    final prefs = await SharedPreferences.getInstance();
    final identity = _QueuedMountedIdentity.capture(tester, fixture);
    late Completer<void> gate;
    late Completer<void> entered;
    late Future<void> blocker;
    await tester.runAsync(() async {
      gate = Completer<void>();
      entered = Completer<void>();
      blocker = WidgetDisplayModeStore.runOperation(() {
        entered.complete();
        return gate.future;
      });
    });

    try {
      final laneEntered = await tester.runAsync<bool>(() async {
        await entered.future.timeout(const Duration(seconds: 3));
        return true;
      });
      expect(laneEntered, isTrue);
      // Actual user action on the production route, after the lane is held.
      await tester.runAsync(
        () => tester.tap(find.byTooltip(WidgetUiCopy.refreshTooltip)),
      );
      await tester.pump();
      final otherBrand = initialBrand == 'defaultBrand'
          ? 'liquidGlass'
          : 'defaultBrand';
      final phases = <(String, AppLocale, String)>[
        (initialBrand, AppLocale.en, '01-start-en'),
        (initialBrand, AppLocale.zh, '02-live-locale-zh'),
        (otherBrand, AppLocale.zh, '03-live-brand-zh'),
        (otherBrand, AppLocale.en, '04-live-locale-en'),
      ];
      for (final phase in phases) {
        if (fixture.theme.brand.id != phase.$1) {
          await tester.runAsync(() async {
            expect(await fixture.theme.setBrand(phase.$1), isTrue);
          });
        }
        if (I18n.current != phase.$2) I18n.setLocale(phase.$2);
        // Mount AnimatedTheme's new target before advancing its animation.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        await _captureHeldPhase(
          tester,
          fixture,
          output,
          prefs,
          identity,
          gate,
          viewport,
          phase.$1,
          phase.$2,
          '$caseId-${phase.$3}',
        );
      }
      // Return the real theme while still held. Do not repeat identical PNGs.
      await tester.runAsync(() async {
        expect(await fixture.theme.setBrand(initialBrand), isTrue);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      _assertQueuedState(
        tester,
        fixture,
        prefs,
        identity,
        viewport,
        initialBrand,
        AppLocale.en,
        held: true,
        gate: gate,
      );
    } finally {
      // The lane must always be released, even after a capture/oracle failure.
      await tester.runAsync(() async {
        if (!gate.isCompleted) gate.complete();
        await blocker.timeout(const Duration(seconds: 3));
      });
      await _settleAsyncWork(tester);
    }

    _assertQueuedState(
      tester,
      fixture,
      prefs,
      identity,
      viewport,
      initialBrand,
      AppLocale.en,
      held: false,
      gate: gate,
    );
    final row = find.byKey(const ValueKey(DuoyiWidgetKind.todo));
    await tester.scrollUntilVisible(
      row,
      180,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 80,
    );
    final button = find.descendant(
      of: row,
      matching: find.byType(FilledButton),
    );
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    final restoredLabel = WidgetUiCopy.addWidgetButtonLabel(
      modeLabel: WidgetDisplayMode.detailed.label,
      launcherRequestLabel: WidgetDisplayMode.detailed.launcherRequestLabel,
    );
    await _captureQueuedTarget(
      tester,
      fixture,
      output,
      prefs,
      identity,
      gate,
      viewport,
      initialBrand,
      AppLocale.en,
      '$caseId-05-release-add-enabled',
      find.descendant(of: button, matching: find.text(restoredLabel)),
      restoredLabel,
      held: false,
      addButton: button,
    );
    output?.checkInputs();
    expect(tester.takeException(), isNull);
  } catch (error, stack) {
    output?.writeFailure(caseId, error, stack, {
      'brand': fixture.theme.brand.id,
      'locale': I18n.current.name,
      'nativeSaves': List<Object?>.of(fixture.native.displayModeSaveValues),
      'dashboardRefreshCalls': fixture.dashboardRefreshCalls,
      'widgetTree': tester.binding.rootElement?.toStringDeep(),
    });
    rethrow;
  } finally {
    semantics.dispose();
    debugDisableShadows = oldShadows;
  }
}

Future<void> _captureHeldPhase(
  WidgetTester tester,
  _RecoveryFixture fixture,
  _QueuedEvidenceOutput? output,
  SharedPreferences prefs,
  _QueuedMountedIdentity identity,
  Completer<void> gate,
  Size viewport,
  String brand,
  AppLocale locale,
  String prefix,
) async {
  // The production ListView is lazy. Bring its first item back before finding
  // the style panel; never keep stale Add/paragraph Elements across scrolling.
  final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
  scroll.position.jumpTo(scroll.position.minScrollExtent);
  await tester.pump();
  _assertQueuedState(
    tester,
    fixture,
    prefs,
    identity,
    viewport,
    brand,
    locale,
    held: true,
    gate: gate,
  );
  final selectorFinder = find.byWidgetPredicate(
    (widget) => widget is SegmentedButton<WidgetDisplayMode>,
  );
  expect(selectorFinder, findsOneWidget);
  final selector = _styleSelector(tester);
  expect(selector.selected, {WidgetDisplayMode.detailed});
  expect(selector.onSelectionChanged, isNull);
  final selectedLabel =
      '${WidgetDisplayMode.detailed.label} '
      '${WidgetDisplayMode.detailed.launcherRequestLabel}';
  await _captureQueuedTarget(
    tester,
    fixture,
    output,
    prefs,
    identity,
    gate,
    viewport,
    brand,
    locale,
    '$prefix-selected-detailed',
    find.descendant(of: selectorFinder, matching: find.text(selectedLabel)),
    selectedLabel,
    held: true,
  );
  final description = WidgetUiCopy.hostStyleDescription(
    'detailed',
    WidgetHostPlatform.android,
  );
  await _captureQueuedTarget(
    tester,
    fixture,
    output,
    prefs,
    identity,
    gate,
    viewport,
    brand,
    locale,
    '$prefix-complete-style-description',
    find.text(description),
    description,
    held: true,
  );
  final pending = find.byKey(const ValueKey('widget_style_sync_pending'));
  await _captureQueuedTarget(
    tester,
    fixture,
    output,
    prefs,
    identity,
    gate,
    viewport,
    brand,
    locale,
    '$prefix-complete-queued-status',
    pending,
    WidgetUiCopy.updatingStyle,
    held: true,
  );
  final retry = find.byKey(const ValueKey('widget_style_sync_retry'));
  expect(retry, findsOneWidget);
  expect(tester.widget<TextButton>(retry).onPressed, isNull);

  final row = find.byKey(const ValueKey(DuoyiWidgetKind.todo));
  await tester.scrollUntilVisible(
    row,
    180,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 80,
  );
  final gallery = find.byKey(const ValueKey('widget_gallery_todo'));
  final subtitle = WidgetUiCopy.catalogSubtitle(DuoyiWidgetKind.todo);
  await _captureQueuedTarget(
    tester,
    fixture,
    output,
    prefs,
    identity,
    gate,
    viewport,
    brand,
    locale,
    '$prefix-complete-todo-description',
    find.descendant(of: gallery, matching: find.text(subtitle)),
    subtitle,
    held: true,
  );
  final button = find.descendant(of: row, matching: find.byType(FilledButton));
  expect(button, findsOneWidget);
  await _captureQueuedTarget(
    tester,
    fixture,
    output,
    prefs,
    identity,
    gate,
    viewport,
    brand,
    locale,
    '$prefix-add-disabled-updating',
    find.descendant(
      of: button,
      matching: find.text(WidgetUiCopy.updatingStyle),
    ),
    WidgetUiCopy.updatingStyle,
    held: true,
    addButton: button,
  );
}

class _QueuedMountedIdentity {
  _QueuedMountedIdentity(
    this.screen,
    this.state,
    this.surface,
    this.route,
    this.capture,
    this.scroll,
  );

  factory _QueuedMountedIdentity.capture(
    WidgetTester tester,
    _RecoveryFixture fixture,
  ) {
    final screen = tester.element(find.byType(WidgetScreen));
    final route = ModalRoute.of(screen);
    expect(route, isNotNull);
    return _QueuedMountedIdentity(
      screen,
      tester.state(find.byType(WidgetScreen)),
      tester.element(find.byType(BrandRouteSurface)),
      route!,
      fixture.captureKey.currentContext!,
      tester.state<ScrollableState>(find.byType(Scrollable).first),
    );
  }

  final Element screen;
  final State state;
  final Element surface;
  final ModalRoute<dynamic> route;
  final BuildContext capture;
  final ScrollableState scroll;

  void check(WidgetTester tester, _RecoveryFixture fixture) {
    expect(screen.mounted, isTrue);
    expect(state.mounted, isTrue);
    expect(
      identical(tester.element(find.byType(WidgetScreen)), screen),
      isTrue,
    );
    expect(identical(tester.state(find.byType(WidgetScreen)), state), isTrue);
    expect(
      identical(tester.element(find.byType(BrandRouteSurface)), surface),
      isTrue,
    );
    expect(identical(ModalRoute.of(screen), route), isTrue);
    expect(route.isActive, isTrue);
    expect(route.isCurrent, isTrue);
    expect(identical(fixture.captureKey.currentContext, capture), isTrue);
    expect(
      identical(
        tester.state<ScrollableState>(find.byType(Scrollable).first),
        scroll,
      ),
      isTrue,
    );
  }

  Map<String, Object?> record() => {
    'screenElement': identityHashCode(screen),
    'screenState': identityHashCode(state),
    'brandRouteSurfaceElement': identityHashCode(surface),
    'modalRoute': identityHashCode(route),
    'routeName': route.settings.name,
    'routeActive': route.isActive,
    'routeCurrent': route.isCurrent,
    'captureContext': identityHashCode(capture),
    'scrollableState': identityHashCode(scroll),
    'scrollPixels': scroll.position.pixels,
    'scope': 'process-local identity; compared with identical on every frame',
  };
}

void _assertQueuedState(
  WidgetTester tester,
  _RecoveryFixture fixture,
  SharedPreferences prefs,
  _QueuedMountedIdentity identity,
  Size viewport,
  String brand,
  AppLocale locale, {
  required bool held,
  required Completer<void> gate,
}) {
  identity.check(tester, fixture);
  expect(fixture.theme.brand.id, brand);
  expect(I18n.current, locale);
  final context = tester.element(find.byType(WidgetScreen));
  expect(
    Theme.of(context).colorScheme.primary,
    fixture.theme.brand.theme.colorScheme.primary,
  );
  expect(MediaQuery.sizeOf(context), viewport);
  expect(tester.view.physicalSize, viewport);
  expect(tester.view.devicePixelRatio, 1);
  final scaler = MediaQuery.textScalerOf(context);
  for (final size in [12.0, 14.0, 20.0]) {
    expect(scaler.scale(size), size * 2);
  }
  expect(gate.isCompleted, !held);
  final selection = WidgetDisplayModeSelection.read(prefs);
  expect(selection.intentId, _intentId);
  expect(selection.mode, 'detailed');
  expect(selection.pending, held);
  expect(prefs.getString(WidgetDisplayModeSelection.legacyKey), 'detailed');
  if (held) {
    expect(
      prefs.getString(WidgetDisplayModeSelection.storageKey),
      _RecoveryFixture._initialSelection.encode(),
    );
    expect(fixture.native.displayModeSaveValues, isEmpty);
    expect(fixture.dashboardRefreshCalls, 0);
    final refresh = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(WidgetUiCopy.refreshTooltip),
        matching: find.byType(IconButton),
      ),
    );
    expect(refresh.onPressed, isNull);
  } else {
    expect(fixture.native.displayModeSaveValues, ['detailed']);
    expect(fixture.dashboardRefreshCalls, 1);
  }
  final row = find.byKey(const ValueKey(DuoyiWidgetKind.todo));
  final add = find.descendant(of: row, matching: find.byType(FilledButton));
  if (add.evaluate().length == 1) {
    expect(tester.widget<FilledButton>(add).onPressed != null, !held);
  }
}

Future<void> _captureQueuedTarget(
  WidgetTester tester,
  _RecoveryFixture fixture,
  _QueuedEvidenceOutput? output,
  SharedPreferences prefs,
  _QueuedMountedIdentity identity,
  Completer<void> gate,
  Size viewport,
  String brand,
  AppLocale locale,
  String name,
  Finder target,
  String completeText, {
  required bool held,
  Finder? addButton,
}) async {
  expect(target, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  final paragraph = tester.renderObject<RenderParagraph>(target);
  final data = tester.getSemantics(target).getSemanticsData();
  final rect = tester.getRect(target);
  final visible = _queuedPaintViewport(tester, paragraph);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: completeText.length),
  );
  // Selection boxes include trailing soft-wrap spaces and typographic leading.
  // Check visible text runs against the real paint viewport, retaining the full
  // selection measurements below for diagnosis.
  final visibleTextBoxes = [
    for (final run in RegExp(r'\S+').allMatches(completeText))
      ...paragraph.getBoxesForSelection(
        TextSelection(baseOffset: run.start, extentOffset: run.end),
      ),
  ];
  if (output != null) {
    final context = tester.element(target);
    final selection = WidgetDisplayModeSelection.read(prefs);
    final snapshot = <String, Object?>{
      'scope':
          'Flutter host production WidgetScreen; controlled native channels',
      'frame': name,
      'held': held,
      'gateCompleted': gate.isCompleted,
      'gateIdentity': identityHashCode(gate),
      'brand': fixture.theme.brand.id,
      'expectedBrand': brand,
      'locale': I18n.current.name,
      'expectedLocale': locale.name,
      'materialLocalizationsLocale': Localizations.localeOf(context).toString(),
      'mounted': identity.record(),
      'intentId': selection.intentId,
      'originalIntentId': _intentId,
      'mode': selection.mode,
      'pending': selection.pending,
      'encodedSelection': prefs.getString(
        WidgetDisplayModeSelection.storageKey,
      ),
      'nativeSaves': List<Object?>.of(fixture.native.displayModeSaveValues),
      'nativeModeValue': fixture.native.values['widget_display_mode'],
      'dashboardRefreshCalls': fixture.dashboardRefreshCalls,
      'requestedViewport': [viewport.width, viewport.height],
      'physicalSize': [
        tester.view.physicalSize.width,
        tester.view.physicalSize.height,
      ],
      'mediaQuerySize': [
        MediaQuery.sizeOf(context).width,
        MediaQuery.sizeOf(context).height,
      ],
      'dpr': tester.view.devicePixelRatio,
      'requestedLinearScale': 2,
      'effectiveScaler': MediaQuery.textScalerOf(
        context,
      ).runtimeType.toString(),
      'effectiveFontSizes': {
        for (final size in [12.0, 14.0, 20.0])
          '$size': MediaQuery.textScalerOf(context).scale(size),
      },
      'target': {
        'requiredCompleteText': completeText,
        'actualText': paragraph.text.toPlainText(),
        'rect': _queuedRect(rect),
        'visiblePaintViewport': _queuedRect(visible),
        'didExceedMaxLines': paragraph.didExceedMaxLines,
        'maxLines': paragraph.maxLines,
        'overflow': paragraph.overflow.name,
        'textBoxes': [for (final box in boxes) _queuedRect(box.toRect())],
        'nonWhitespaceTextBoxes': [
          for (final box in visibleTextBoxes) _queuedRect(box.toRect()),
        ],
        'textBoxMeasurement':
            'selection metrics; non-whitespace runs checked against actual paint clips',
        'semanticsLabel': data.label,
        'semanticsTree': tester.getSemantics(target).toStringDeep(),
        'resolvedRootTextStyle': paragraph.text.style?.toString(),
        'defaultFontFamily': DefaultTextStyle.of(context).style.fontFamily,
        'defaultFontFallback': DefaultTextStyle.of(
          context,
        ).style.fontFamilyFallback,
        'colorSchemePrimary': Theme.of(context).colorScheme.primary.toARGB32(),
      },
      'fontInventory': output.fonts,
    };
    final liveSelector = find.byWidgetPredicate(
      (widget) => widget is SegmentedButton<WidgetDisplayMode>,
    );
    snapshot['styleSelector'] = liveSelector.evaluate().length == 1
        ? {
            'mounted': true,
            'selected': [
              for (final mode in _styleSelector(tester).selected) mode.id,
            ],
            'enabledCallback':
                _styleSelector(tester).onSelectionChanged != null,
          }
        : {
            'mounted': false,
            'reason':
                'outside lazy ListView cache; selected frame recorded separately',
          };
    snapshot['screenshotFontsLoaded'] = fixture._screenshotFontsLoaded;
    final liveAdd = find.descendant(
      of: find.byKey(const ValueKey(DuoyiWidgetKind.todo)),
      matching: find.byType(FilledButton),
    );
    snapshot['liveAdd'] = liveAdd.evaluate().length == 1
        ? {
            'mounted': true,
            'enabledCallback':
                tester.widget<FilledButton>(liveAdd).onPressed != null,
          }
        : {
            'mounted': false,
            'reason':
                'outside lazy ListView cache; Add frame recorded separately',
          };
    if (addButton != null) {
      final buttonData = tester.getSemantics(addButton).getSemanticsData();
      snapshot['add'] = {
        'enabledCallback':
            tester.widget<FilledButton>(addButton).onPressed != null,
        'rect': _queuedRect(tester.getRect(addButton)),
        'semanticsLabel': buttonData.label,
        'isButton': buttonData.flagsCollection.isButton,
        'hasEnabledState':
            buttonData.flagsCollection.isEnabled != ui.Tristate.none,
        'isEnabled': buttonData.flagsCollection.isEnabled == ui.Tristate.isTrue,
        'semanticsTree': tester.getSemantics(addButton).toStringDeep(),
      };
    }
    // Explicit capture retains pixels/measurements before common completeness
    // assertions. No-capture runs still reach every oracle below.
    await _writeQueuedPixels(tester, fixture, output, name, snapshot);
    output.checkInputs();
  }
  _assertQueuedState(
    tester,
    fixture,
    prefs,
    identity,
    viewport,
    brand,
    locale,
    held: held,
    gate: gate,
  );
  expect(fixture._screenshotFontsLoaded, isTrue);
  expect(paragraph.text.toPlainText(), completeText);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(data.label, contains(completeText));
  expect(boxes, isNotEmpty);
  _assertQueuedRectInside(rect, visible);
  expect(visibleTextBoxes, isNotEmpty);
  for (final box in visibleTextBoxes) {
    final local = box.toRect();
    expect(local.left, greaterThanOrEqualTo(-0.5));
    expect(local.right, lessThanOrEqualTo(paragraph.size.width + 0.5));
    _assertQueuedRectInside(
      Rect.fromPoints(
        paragraph.localToGlobal(local.topLeft),
        paragraph.localToGlobal(local.bottomRight),
      ),
      visible,
    );
  }
  if (addButton != null) {
    final buttonData = tester.getSemantics(addButton).getSemanticsData();
    expect(tester.widget<FilledButton>(addButton).onPressed != null, !held);
    expect(buttonData.flagsCollection.isButton, isTrue);
    expect(buttonData.flagsCollection.isEnabled != ui.Tristate.none, isTrue);
    expect(buttonData.flagsCollection.isEnabled == ui.Tristate.isTrue, !held);
    expect(
      buttonData.label,
      contains(WidgetUiCopy.catalogTitle(DuoyiWidgetKind.todo)),
    );
    expect(buttonData.label, contains(completeText));
    final buttonRect = tester.getRect(addButton);
    expect(buttonRect.width, greaterThanOrEqualTo(44));
    expect(buttonRect.height, greaterThanOrEqualTo(44));
    _assertQueuedRectInside(buttonRect, visible);
  }
  expect(tester.takeException(), isNull);
}

Rect _queuedPaintViewport(WidgetTester tester, RenderParagraph paragraph) {
  var visible = tester.getRect(find.byType(ListView).first);
  RenderObject child = paragraph;
  while (child.parent is RenderObject) {
    final parent = child.parent!;
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null && parent is RenderBox) {
      visible = visible.intersect(
        Rect.fromPoints(
          parent.localToGlobal(clip.topLeft),
          parent.localToGlobal(clip.bottomRight),
        ),
      );
    }
    child = parent;
  }
  return visible;
}

List<double> _queuedRect(Rect rect) => [
  rect.left,
  rect.top,
  rect.right,
  rect.bottom,
];

void _assertQueuedRectInside(Rect target, Rect viewport) {
  expect(target.isEmpty, isFalse);
  expect(viewport.isEmpty, isFalse);
  expect(target.left, greaterThanOrEqualTo(viewport.left - 0.5));
  expect(target.top, greaterThanOrEqualTo(viewport.top - 0.5));
  expect(target.right, lessThanOrEqualTo(viewport.right + 0.5));
  expect(target.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
}

Future<void> _writeQueuedPixels(
  WidgetTester tester,
  _RecoveryFixture fixture,
  _QueuedEvidenceOutput output,
  String name,
  Map<String, Object?> snapshot,
) async {
  final frame = output.newFrame(name);
  final completed = await tester.runAsync<bool>(() async {
    try {
      final object = fixture.captureKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) {
        throw StateError('Mounted capture boundary missing for $name');
      }
      final image = await object.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null || bytes.lengthInBytes == 0) {
          throw StateError('PNG encoding failed for $name');
        }
        final png = File('${frame.path}/frame.png');
        output.writeNewBytes(
          png,
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        snapshot['png'] = _queuedFingerprint(png);
        snapshot['imageSize'] = [image.width, image.height];
        snapshot['inputs'] = output.inputs;
        output.writeNewJson(File('${frame.path}/frame.json'), snapshot);
        expect(image.width, tester.view.physicalSize.width.toInt());
        expect(image.height, tester.view.physicalSize.height.toInt());
      } finally {
        image.dispose();
      }
    } catch (error, stack) {
      output.writeNewJson(File('${frame.path}/capture-failure.json'), {
        'error': error.toString(),
        'stack': stack.toString(),
        'snapshot': snapshot,
      });
      rethrow;
    }
    return true;
  });
  if (completed != true) {
    throw StateError(
      'Capture did not complete for $name; retain frame diagnostics',
    );
  }
}

// Linux-host native fingerprinting/reservation only; no new Dart dependency.
Map<String, Object?> _queuedFingerprint(File file) {
  if (!file.existsSync()) {
    throw StateError('Required input missing: ${file.path}');
  }
  final stat = file.statSync();
  final result = Process.runSync('sha256sum', ['--', file.path]);
  if (result.exitCode != 0) {
    throw StateError('Cannot hash ${file.path}: ${result.stderr}');
  }
  final match = RegExp(
    r'^([a-f0-9]{64})\s',
  ).firstMatch(result.stdout.toString());
  if (match == null) throw StateError('Invalid SHA output: ${file.path}');
  return {
    'path': file.path,
    'canonicalPath': file.resolveSymbolicLinksSync(),
    'sha256': match.group(1),
    'bytes': stat.size,
    'mtimeUtc': stat.modified.toUtc().toIso8601String(),
  };
}

class _QueuedEvidenceOutput {
  _QueuedEvidenceOutput(this.root, this.inputs, this.fonts);
  static _QueuedEvidenceOutput? _current;
  final Directory root;
  final Map<String, Object?> inputs;
  final Map<String, Object?> fonts;

  static _QueuedEvidenceOutput require() {
    final current = _current;
    if (current != null) {
      current.checkInputs();
      return current;
    }
    final raw = Platform.environment[_queuedEvidenceEnv];
    if (raw == null ||
        raw.isEmpty ||
        raw != raw.trim() ||
        !raw.startsWith('/')) {
      throw StateError(
        '$_queuedEvidenceEnv must name an absolute NEW evidence '
        'directory. Legacy flags/paths never authorize fallback output.',
      );
    }
    final normalized = Directory(raw).absolute.uri.normalizePath().toFilePath();
    final path = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    const evidenceRoot = '/home/ubuntu/duoyi/evidence';
    if (!path.startsWith('$evidenceRoot/') ||
        !RegExp(
          r'^queued-widget-2722-[A-Za-z0-9][A-Za-z0-9_.-]*$',
        ).hasMatch(path.split('/').last)) {
      throw StateError(
        'Output must be a NEW queued-widget-2722-<run-id> batch '
        'under $evidenceRoot (prefer evidence/screenshots).',
      );
    }
    var ancestor = Directory(path).parent;
    if (!ancestor.existsSync()) throw StateError('Output parent must exist');
    while (true) {
      if (FileSystemEntity.typeSync(ancestor.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw StateError(
          'Non-directory/symlink output ancestor: ${ancestor.path}',
        );
      }
      if (ancestor.parent.path == ancestor.path) break;
      ancestor = ancestor.parent;
    }
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Refusing existing output path: $path');
    }
    final expectedTest = Platform.environment[_queuedExpectedTestEnv];
    if (expectedTest == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedTest)) {
      throw StateError(
        '$_queuedExpectedTestEnv must bind the reviewed candidate SHA',
      );
    }
    final actualTest = _queuedFingerprint(
      File('test/screens/widget_recovery_live_brand_priority_test.dart'),
    );
    if (actualTest['sha256'] != expectedTest) {
      throw StateError('Staged test SHA differs from reviewed candidate SHA');
    }
    final products = <String, Object?>{};
    for (final input in _queuedProductInputs.entries) {
      final fingerprint = _queuedFingerprint(File(input.key));
      if (fingerprint['sha256'] != input.value) {
        throw StateError('Reviewed 2722 product input changed: ${input.key}');
      }
      products[input.key] = fingerprint;
    }
    final fonts = <String, Object?>{
      for (final path in [
        'assets/fonts/DroidSansFallbackFull.ttf',
        'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
        Platform.environment['DUOYI_WIDGET_SCREENSHOT_LATIN_FONT'] ??
            '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      ])
        path: _queuedFingerprint(File(path)),
    };
    final inputs = <String, Object?>{
      'baselineTestSha256': _queuedBaselineSha,
      'contract2703Sha256': _queuedContractSha,
      'predecessor2709TestSha256':
          'b01bb4b5012709cfcec6623f994f776f86b812c4dbabd9a9ff5b3e4e0c14d370',
      'captureRequested': true,
      'stagedTest': actualTest,
      'products': products,
      'fontLoader': _queuedFingerprint(
        File('test/support/widget_polish_screenshot_font.dart'),
      ),
      'fontInventory': fonts,
      'runtimeCwd': Directory.current.resolveSymbolicLinksSync(),
      'scope':
          'unaccepted source candidate; host capture only; no device/Launcher credit',
      'matrix':
          'both starting brands; en->zh, brand switch, zh->en, brand return; '
          '320x844 and 568x320; DPR1; linear2; one held recovery per case',
    };
    _mkdirExclusive(path);
    final output = _QueuedEvidenceOutput(Directory(path), inputs, fonts);
    output.writeNewJson(File('$path/inputs.json'), inputs);
    _current = output;
    return output;
  }

  void checkInputs() {
    final test = inputs['stagedTest']! as Map<String, Object?>;
    if (jsonEncode(_queuedFingerprint(File(test['path']! as String))) !=
        jsonEncode(test)) {
      throw StateError('Staged test fingerprint changed');
    }
    final products = inputs['products']! as Map<String, Object?>;
    for (final input in products.entries) {
      if (jsonEncode(_queuedFingerprint(File(input.key))) !=
          jsonEncode(input.value)) {
        throw StateError('Product fingerprint changed: ${input.key}');
      }
    }
    final loader = inputs['fontLoader']! as Map<String, Object?>;
    if (jsonEncode(_queuedFingerprint(File(loader['path']! as String))) !=
        jsonEncode(loader)) {
      throw StateError('Font loader fingerprint changed');
    }
    for (final font in fonts.entries) {
      if (jsonEncode(_queuedFingerprint(File(font.key))) !=
          jsonEncode(font.value)) {
        throw StateError('Registered-font input changed: ${font.key}');
      }
    }
  }

  Directory newFrame(String name) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(name)) {
      throw StateError('Invalid frame name: $name');
    }
    if (FileSystemEntity.typeSync(root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        root.resolveSymbolicLinksSync() != root.path) {
      throw StateError('Reserved output root changed');
    }
    final directory = Directory('${root.path}/$name');
    _mkdirExclusive(directory.path);
    return directory;
  }

  static void _mkdirExclusive(String path) {
    // mkdir without -p atomically rejects existing paths and concurrent runs.
    final result = Process.runSync('mkdir', ['--', path]);
    if (result.exitCode != 0) {
      throw StateError('Cannot reserve NEW directory $path: ${result.stderr}');
    }
  }

  void _checkNewFile(File file) {
    if (!file.path.startsWith('${root.path}/') ||
        FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        file.parent.resolveSymbolicLinksSync() != file.parent.path) {
      throw StateError(
        'Refusing existing, escaped or symlink output: ${file.path}',
      );
    }
  }

  void writeNewBytes(File file, List<int> bytes) {
    _checkNewFile(file);
    file.writeAsBytesSync(bytes, flush: true);
  }

  void writeNewJson(File file, Object value) {
    _checkNewFile(file);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(value)}\n',
      flush: true,
    );
  }

  void writeFailure(
    String caseId,
    Object error,
    StackTrace stack,
    Map<String, Object?> observations,
  ) {
    final frame = newFrame('$caseId-failure');
    writeNewJson(File('${frame.path}/failure.json'), {
      'error': error.toString(),
      'stack': stack.toString(),
      'observations': observations,
      'inputs': inputs,
      'scope': 'failure diagnostics; no acceptance',
    });
  }
}

class _RecoveryFixture {
  static const _initialSelection = WidgetDisplayModeSelection(
    mode: 'detailed',
    intentId: _intentId,
    pending: true,
  );

  _RecoveryFixture({this.initialBrandId = 'defaultBrand'})
    : store = _MemoryPreferencesStore(
        initialValues: <String, Object>{
          'flutter.active_brand': initialBrandId,
          'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'flutter.theme_shop_state': jsonEncode({
            'activeBrand': initialBrandId,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'flutter.${WidgetDisplayModeSelection.storageKey}': _initialSelection
              .encode(),
          'flutter.${WidgetDisplayModeSelection.legacyKey}': 'detailed',
        },
      );

  final String initialBrandId;
  final _MemoryPreferencesStore store;
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

    SharedPreferences.setMockInitialValues(<String, Object>{
      'active_brand': initialBrandId,
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      'theme_shop_state': jsonEncode({
        'activeBrand': initialBrandId,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
      WidgetDisplayModeSelection.storageKey: _initialSelection.encode(),
      WidgetDisplayModeSelection.legacyKey: 'detailed',
    });
    SharedPreferencesStorePlatform.instance = store;
    await tester.runAsync(theme.loadFromStorage);
    I18n.setLocale(locale);
    HomeWidgetService.supportedForTesting = true;
    AndroidWidgetManager.debugIsAndroidOverride = true;
    HomeWidgetService.dashboardDataRefresher = () async {
      dashboardRefreshCalls++;
      return true;
    };
    messenger.setMockMethodCallHandler(_homeWidgetChannel, native.handle);
    messenger.setMockMethodCallHandler(_widgetChannel, _handleWidgetMethod);

    if (loadScreenshotFonts ||
        Platform.environment[_captureEnv] == '1' ||
        Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] != null) {
      await tester.runAsync(loadWidgetPolishScreenshotFonts);
      _screenshotFontsLoaded = true;
    }
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: AnimatedBuilder(
          animation: theme,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _appTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: RepaintBoundary(key: captureKey, child: child!),
            ),
            home: const BrandRouteSurface(
              child: WidgetScreen(hostPlatform: WidgetHostPlatform.android),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
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
    await _settleAsyncWork(tester);
    await tester.runAsync(
      () => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5)),
    );
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
        return true;
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
