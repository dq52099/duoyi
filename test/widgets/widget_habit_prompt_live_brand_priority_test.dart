import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/widget_launch_access.dart';
import 'package:duoyi/services/widget_navigation_request.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/widget_habit_check_in_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../support/retained_dialog_text_probe.dart';

/// Presentation-only launch fixture modeling widget receipt retention.
///
/// This fixture verifies only dialog presentation, reachability, and submission fencing.
/// It makes NO claim of native platform launch, deep-link dispatch, MainShell routing,
/// or actual HabitProvider mutation.
class _WidgetLaunchAccessFixture {
  int generation = 1;
  bool blocked = false;
  bool available = true;
  final uri = Uri.parse(
    'duoyi://action/checkin_habit?id=habit-fixture&confirm=1&widget_delivery=retained-fixture',
  );
  late final requests = WidgetNavigationRequests(
    accountGeneration: () => generation,
  );
  final queued = <(Uri, WidgetNavigationRequest)>[];
  final acknowledged = <Uri>[];

  WidgetLaunchAccess delivery(
    WidgetNavigationRequest request, {
    bool latest = false,
    Uri? uri,
  }) => WidgetLaunchAccess(
    uri: uri ?? this.uri,
    request: request,
    isBlocked: () => blocked,
    isCallerAvailable: () => available,
    requiresLatest: latest,
    requeue: (uri, request) => queued.add((uri, request)),
    acknowledge: (uri) async => acknowledged.add(uri),
  );
}

class _HabitPromptScenario {
  final String name;
  final String initialBrand;
  final String targetBrand;
  final AppLocale initialLocale;
  final AppLocale targetLocale;
  final Size size;
  final double scale;
  final bool testConfirm;

  const _HabitPromptScenario({
    required this.name,
    required this.initialBrand,
    required this.targetBrand,
    required this.initialLocale,
    required this.targetLocale,
    required this.size,
    required this.scale,
    required this.testConfirm,
  });
}

const _scenarios = <_HabitPromptScenario>[
  _HabitPromptScenario(
    name: 'defaultBrand-zh-320x844x2-cancel',
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    initialLocale: AppLocale.zh,
    targetLocale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    testConfirm: false,
  ),
  _HabitPromptScenario(
    name: 'liquidGlass-en-844x390x1-confirm',
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    initialLocale: AppLocale.en,
    targetLocale: AppLocale.zh,
    size: Size(844, 390),
    scale: 1.0,
    testConfirm: true,
  ),
  _HabitPromptScenario(
    name: 'defaultBrand-en-844x390x1-cancel',
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    initialLocale: AppLocale.en,
    targetLocale: AppLocale.zh,
    size: Size(844, 390),
    scale: 1.0,
    testConfirm: false,
  ),
  _HabitPromptScenario(
    name: 'liquidGlass-zh-320x844x2-confirm',
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    initialLocale: AppLocale.zh,
    targetLocale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    testConfirm: true,
  ),
];

ThemeData _injectScreenshotFonts(ThemeData baseTheme) {
  const fallback = [
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'Microsoft YaHei',
    'WenQuanYi Micro Hei',
    'DroidSansFallbackFull',
    'DejaVu Sans',
    'DuoyiScreenshot',
    'DuoyiScreenshotLatin',
  ];
  return baseTheme.copyWith(
    textTheme: baseTheme.textTheme.apply(
      fontFamily: 'sans-serif',
      fontFamilyFallback: fallback,
    ),
    primaryTextTheme: baseTheme.primaryTextTheme.apply(
      fontFamily: 'sans-serif',
      fontFamilyFallback: fallback,
    ),
  );
}

Future<void> _settleOrPumpFrames(
  WidgetTester tester, {
  Duration step = const Duration(milliseconds: 50),
}) async {
  try {
    await tester.pumpAndSettle(
      step,
      EnginePhase.sendSemanticsUpdate,
      const Duration(milliseconds: 600),
    );
  } on FlutterError catch (e) {
    if (e.message.contains('pumpAndSettle timed out')) {
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(step);
      }
    } else {
      rethrow;
    }
  }
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
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(timeout, onTimeout: () {}),
  );
}

Future<void> _verifyDialogReachabilityAndReadability(
  WidgetTester tester, {
  required Finder presenterFinder,
  required String expectedTitle,
  required String expectedContent,
  required String expectedCancelLabel,
  required String expectedConfirmLabel,
  required String habitName,
}) async {
  expect(expectedTitle, contains(habitName));
  for (final label in [
    expectedTitle,
    expectedContent,
    expectedCancelLabel,
    expectedConfirmLabel,
  ]) {
    final text = find.descendant(
      of: presenterFinder,
      matching: find.text(label),
    );
    await verifyRetainedDialogText(tester, text, expected: label);
  }
  for (final actionType in [TextButton, FilledButton]) {
    final action = find.descendant(
      of: presenterFinder,
      matching: find.byType(actionType),
    );
    await tester.ensureVisible(action);
    await _settleOrPumpFrames(tester);
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(34));
  }
  await tester.ensureVisible(find.text(expectedTitle));
  await _settleOrPumpFrames(tester);
}

void _assertTargetBrandColors(
  WidgetTester tester, {
  required Finder presenterFinder,
  required String targetBrandId,
}) {
  final targetBrand = AppBrands.byId(targetBrandId);
  final targetRefTheme = _injectScreenshotFonts(targetBrand.theme);

  // 1. Theme.of(element) colors from dialog context
  final appDialogFinder = find.byType(AppDialog);
  final dialogTheme = Theme.of(tester.element(appDialogFinder));
  expect(
    dialogTheme.colorScheme.primary,
    targetRefTheme.colorScheme.primary,
    reason:
        'Dialog theme primary must match independent target-brand reference',
  );
  expect(
    dialogTheme.colorScheme.surface,
    targetRefTheme.colorScheme.surface,
    reason:
        'Dialog theme surface must match independent target-brand reference',
  );

  // 2. Rendered dialog surface Material color
  final dialogMaterialFinder = find
      .descendant(of: find.byType(AlertDialog), matching: find.byType(Material))
      .first;
  final dialogMaterial = tester.widget<Material>(dialogMaterialFinder);
  final expectedSurfaceColor =
      targetRefTheme.dialogTheme.backgroundColor ??
      targetRefTheme.colorScheme.surface;
  expect(
    dialogMaterial.color,
    expectedSurfaceColor,
    reason:
        'Rendered dialog surface color must match target-brand reference surface',
  );

  // 3. Rendered FilledButton (Confirm) background & shape compared to independent AppSecondaryControlTheme reference
  final actualFilledBtn = find.descendant(
    of: presenterFinder,
    matching: find.byType(FilledButton),
  );
  final actualFilledMaterial = tester.widget<Material>(
    find.descendant(of: actualFilledBtn, matching: find.byType(Material)),
  );
  final refFilledFinder = find.byKey(
    ValueKey('ref-filled-$targetBrandId'),
    skipOffstage: false,
  );
  final refElement = tester.element(refFilledFinder);
  final referenceStyle = FilledButtonTheme.of(refElement).style!;
  expect(
    actualFilledMaterial.color,
    referenceStyle.backgroundColor!.resolve({}),
    reason:
        'Rendered confirm surface follows the independent target secondary theme',
  );
  expect(
    actualFilledMaterial.shape,
    referenceStyle.shape!.resolve({})!.copyWith(
      side: referenceStyle.side?.resolve({}) ?? BorderSide.none,
    ),
  );

  // 4. Rendered TextButton (Cancel) text color compared to independent AppSecondaryControlTheme reference
  final actualTextBtn = find.descendant(
    of: presenterFinder,
    matching: find.byType(TextButton),
  );
  final actualTextRichText = find.descendant(
    of: actualTextBtn,
    matching: find.byType(RichText),
  );
  final actualTextParagraph = tester.renderObject<RenderParagraph>(
    actualTextRichText,
  );
  final expectedTextColor =
      TextButtonTheme.of(refElement).style?.foregroundColor?.resolve({}) ??
      Theme.of(refElement).colorScheme.primary;
  expect(
    actualTextParagraph.text.style?.color,
    expectedTextColor,
    reason: 'Rendered cancel label follows independent target secondary theme',
  );
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  await tester.pump();
  await tester.runAsync(() async {
    final context = boundaryKey.currentContext;
    if (context == null) return;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final file = File('$explicitDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  for (final scenario in _scenarios) {
    testWidgets('Widget habit check-in dialog live brand priority ${scenario.name}', (
      tester,
    ) async {
      final previousShadows = debugDisableShadows;
      final originalLocale = I18n.current;
      ThemeProvider? theme;

      try {
        debugDisableShadows = false;
        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;

        SharedPreferences.setMockInitialValues({
          'active_brand': scenario.initialBrand,
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
        });

        I18n.setLocale(scenario.initialLocale);

        // Construct ThemeProvider inside tester.runAsync before awaiting load
        await tester.runAsync(() async {
          theme = ThemeProvider();
          await theme!.loadFromStorage().timeout(const Duration(seconds: 5));
          await loadWeeklyReviewScreenshotFonts().timeout(
            const Duration(seconds: 5),
          );
        });

        expect(theme!.brand.id, scenario.initialBrand);
        expect(theme!.isBrandUnlocked(scenario.targetBrand), isTrue);

        final fixture = _WidgetLaunchAccessFixture();
        final access = fixture.delivery(fixture.requests.capture());

        final habit = Habit(
          id: 'habit/retained-fixture-${scenario.name}',
          name: scenario.initialLocale == AppLocale.zh
              ? '每日深度专注工程实践与系统架构演进 Retained Long Habit Fixture'
              : 'Daily Deep Focused Engineering Practice Retained Long Habit Fixture',
          targetCount: 5,
          completions: {
            Habit(id: 'probe', name: 'probe', targetCount: 1).todayKey(): 2,
          },
          startDate: DateTime(2026, 1, 1),
        );

        final boundary = GlobalKey();
        bool? dialogResult;
        var popCount = 0;
        ModalRoute<bool>? dialogRoute;

        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>.value(
            value: theme!,
            child: AnimatedBuilder(
              animation: Listenable.merge([theme!, I18n.localeListenable]),
              builder: (context, _) => MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: _injectScreenshotFonts(theme!.brand.theme),
                locale: Locale(I18n.current == AppLocale.en ? 'en' : 'zh'),
                supportedLocales: const [Locale('en'), Locale('zh')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (appContext, child) => MediaQuery(
                  data: MediaQuery.of(appContext).copyWith(
                    size: scenario.size,
                    textScaler: TextScaler.linear(scenario.scale),
                  ),
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
                home: Builder(
                  builder: (scaffoldContext) => Scaffold(
                    body: Stack(
                      children: [
                        Center(
                          child: TextButton(
                            onPressed: () async {
                              access.markInteractionPresented();
                              dialogResult = await showDialog<bool>(
                                context: scaffoldContext,
                                builder: (dialogContext) {
                                  dialogRoute = ModalRoute.of<bool>(
                                    dialogContext,
                                  );
                                  bool canSubmit() =>
                                      dialogContext.mounted &&
                                      dialogRoute?.isCurrent == true &&
                                      access.canProceed;
                                  return WidgetHabitCheckInDialog(
                                    habit: habit,
                                    canSubmit: canSubmit,
                                  );
                                },
                              );
                              popCount++;
                            },
                            child: const Text('Open Habit Dialog'),
                          ),
                        ),
                        Offstage(
                          offstage: true,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final brandId in [
                                scenario.initialBrand,
                                scenario.targetBrand,
                              ])
                                Theme(
                                  data: _injectScreenshotFonts(
                                    AppBrands.byId(brandId).theme,
                                  ),
                                  child: AppSecondaryControlTheme(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        FilledButton(
                                          key: ValueKey('ref-filled-$brandId'),
                                          onPressed: () {},
                                          child: Text('Confirm-$brandId'),
                                        ),
                                        TextButton(
                                          key: ValueKey('ref-text-$brandId'),
                                          onPressed: () {},
                                          child: Text('Cancel-$brandId'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _settleOrPumpFrames(tester);

        await tester.tap(find.text('Open Habit Dialog'));
        await _settleOrPumpFrames(tester);

        // 1. Exact presenter mounted in real DialogRoute
        final presenterFinder = find.byType(WidgetHabitCheckInDialog);
        expect(presenterFinder, findsOneWidget);
        final dialogElement = tester.element(presenterFinder);
        expect(dialogRoute, isNotNull);
        expect(dialogRoute!.isActive, isTrue);
        expect(ModalRoute.of(dialogElement), same(dialogRoute));

        // 2. Reachability, readability, complete words and hitTestable actions in initial state
        final isInitialEnglish = scenario.initialLocale == AppLocale.en;
        final initialTitle = isInitialEnglish
            ? 'Check in: ${habit.name}'
            : '打卡：${habit.name}';
        final initialContent = isInitialEnglish
            ? '2 / 5 check-ins today. Check in again?'
            : '今天已打卡 2 / 5 次，继续打卡吗？';
        final initialCancel = isInitialEnglish ? 'Cancel' : '取消';
        final initialConfirm = isInitialEnglish ? 'Check in' : '完成打卡';

        await _verifyDialogReachabilityAndReadability(
          tester,
          presenterFinder: presenterFinder,
          expectedTitle: initialTitle,
          expectedContent: initialContent,
          expectedCancelLabel: initialCancel,
          expectedConfirmLabel: initialConfirm,
          habitName: habit.name,
        );

        // 3. Overall containing RenderBox bounds check
        expect(tester.takeException(), isNull);
        final appDialogFinder = find.byType(AppDialog);
        final initialBox = tester.renderObject(appDialogFinder) as RenderBox;
        expect(initialBox.hasSize, isTrue);
        expect(initialBox.size.width, lessThanOrEqualTo(scenario.size.width));
        expect(initialBox.size.height, lessThanOrEqualTo(scenario.size.height));

        // 4. Initial brand surface and button color check against independent reference
        _assertTargetBrandColors(
          tester,
          presenterFinder: presenterFinder,
          targetBrandId: scenario.initialBrand,
        );

        await _capture(tester, boundary, '${scenario.name}-01-initial');

        // 5. Test invalid canSubmit cannot pop or mutate
        fixture.blocked = true;
        expect(access.canProceed, isFalse);

        final actionButton = scenario.testConfirm
            ? find.descendant(
                of: presenterFinder,
                matching: find.widgetWithText(FilledButton, initialConfirm),
              )
            : find.descendant(
                of: presenterFinder,
                matching: find.widgetWithText(TextButton, initialCancel),
              );
        await tester.tap(actionButton);
        await _settleOrPumpFrames(tester);

        expect(presenterFinder, findsOneWidget);
        expect(dialogRoute!.isActive, isTrue);
        expect(dialogResult, isNull);
        expect(popCount, 0);
        expect(habit.todayCount(), 2);

        fixture.blocked = false;
        expect(access.canProceed, isTrue);

        // 6. Live brand switch 1: scenario.initialBrand -> scenario.targetBrand & target locale
        await tester.runAsync(() async {
          final switched = await theme!
              .setBrand(scenario.targetBrand)
              .timeout(const Duration(seconds: 5));
          expect(switched, isTrue);
        });
        await _drainAccountWrites(tester);
        I18n.setLocale(scenario.targetLocale);
        await _settleOrPumpFrames(tester);
        expect(tester.takeException(), isNull);

        // Assert same dialog Element and Route across brand/locale roundtrip
        expect(tester.element(presenterFinder), same(dialogElement));
        expect(
          ModalRoute.of(tester.element(presenterFinder)),
          same(dialogRoute),
        );

        // Assert updated locale presentation reachability and readability
        final isTargetEnglish = scenario.targetLocale == AppLocale.en;
        final targetTitle = isTargetEnglish
            ? 'Check in: ${habit.name}'
            : '打卡：${habit.name}';
        final targetContent = isTargetEnglish
            ? '2 / 5 check-ins today. Check in again?'
            : '今天已打卡 2 / 5 次，继续打卡吗？';
        final targetCancel = isTargetEnglish ? 'Cancel' : '取消';
        final targetConfirm = isTargetEnglish ? 'Check in' : '完成打卡';

        await _verifyDialogReachabilityAndReadability(
          tester,
          presenterFinder: presenterFinder,
          expectedTitle: targetTitle,
          expectedContent: targetContent,
          expectedCancelLabel: targetCancel,
          expectedConfirmLabel: targetConfirm,
          habitName: habit.name,
        );

        // Assert bounds on switched presentation
        final switchedBox = tester.renderObject(appDialogFinder) as RenderBox;
        expect(switchedBox.hasSize, isTrue);
        expect(switchedBox.size.width, lessThanOrEqualTo(scenario.size.width));
        expect(
          switchedBox.size.height,
          lessThanOrEqualTo(scenario.size.height),
        );

        // Assert target-brand surface and button colors against independent reference
        _assertTargetBrandColors(
          tester,
          presenterFinder: presenterFinder,
          targetBrandId: scenario.targetBrand,
        );

        await _capture(tester, boundary, '${scenario.name}-02-switched');

        // 7. Live brand switch 2: scenario.targetBrand -> scenario.initialBrand (revert) & initial locale
        await tester.runAsync(() async {
          final reverted = await theme!
              .setBrand(scenario.initialBrand)
              .timeout(const Duration(seconds: 5));
          expect(reverted, isTrue);
        });
        await _drainAccountWrites(tester);
        I18n.setLocale(scenario.initialLocale);
        await _settleOrPumpFrames(tester);
        expect(tester.takeException(), isNull);

        // Assert same dialog Element and Route after roundtrip revert
        expect(tester.element(presenterFinder), same(dialogElement));
        expect(
          ModalRoute.of(tester.element(presenterFinder)),
          same(dialogRoute),
        );

        // Assert reverted locale reachability and readability
        await _verifyDialogReachabilityAndReadability(
          tester,
          presenterFinder: presenterFinder,
          expectedTitle: initialTitle,
          expectedContent: initialContent,
          expectedCancelLabel: initialCancel,
          expectedConfirmLabel: initialConfirm,
          habitName: habit.name,
        );

        // Assert reverted brand colors against independent reference
        _assertTargetBrandColors(
          tester,
          presenterFinder: presenterFinder,
          targetBrandId: scenario.initialBrand,
        );

        await _capture(tester, boundary, '${scenario.name}-03-reverted');

        // 8. Final action pop verification (Confirm true vs Cancel false at most once)
        final finalActionButton = scenario.testConfirm
            ? find.descendant(
                of: presenterFinder,
                matching: find.widgetWithText(FilledButton, initialConfirm),
              )
            : find.descendant(
                of: presenterFinder,
                matching: find.widgetWithText(TextButton, initialCancel),
              );
        await tester.tap(finalActionButton);
        await _settleOrPumpFrames(tester);
        expect(tester.takeException(), isNull);

        if (scenario.testConfirm) {
          expect(dialogResult, isTrue);
        } else {
          expect(dialogResult, isFalse);
        }
        expect(popCount, 1);
        expect(presenterFinder, findsNothing);
      } finally {
        // Robust finally restoration
        debugDisableShadows = previousShadows;
        I18n.setLocale(originalLocale);
        tester.view.reset();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 5),
            onTimeout: () {},
          );
        });
        theme?.dispose();
      }
    });
  }
}
