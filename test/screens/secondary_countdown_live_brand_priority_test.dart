// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart'
    show AppSurfaceStyle, DesignTokens;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/widgets/app_date_format.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart'
    show AppModalSheet, appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

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
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  if (scrollableFinder != null && scrollToOffset != null) {
    tester
        .state<ScrollableState>(scrollableFinder)
        .position
        .jumpTo(scrollToOffset);
    await tester.pumpAndSettle();
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
      final file = File('$explicitDir/countdown-$name.png');
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
    await tester.pumpAndSettle();
  }
}

enum _CountdownContractOutcome { cancel, save }

class _CountdownLiveBrandScenario {
  final String name;
  final AppLocale locale;
  final Size size;
  final double scale;
  final String initialBrand;
  final String targetBrand;
  final _CountdownContractOutcome outcome;

  const _CountdownLiveBrandScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.scale,
    required this.initialBrand,
    required this.targetBrand,
    required this.outcome,
  });
}

const _scenarios = <_CountdownLiveBrandScenario>[
  _CountdownLiveBrandScenario(
    name: 'zh-portrait-320x844-cancel',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    outcome: _CountdownContractOutcome.cancel,
  ),
  _CountdownLiveBrandScenario(
    name: 'en-portrait-320x844-save',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    outcome: _CountdownContractOutcome.save,
  ),
  _CountdownLiveBrandScenario(
    name: 'zh-landscape-844x390-save',
    locale: AppLocale.zh,
    size: Size(844, 390),
    scale: 1.6,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    outcome: _CountdownContractOutcome.save,
  ),
  _CountdownLiveBrandScenario(
    name: 'en-landscape-844x390-cancel',
    locale: AppLocale.en,
    size: Size(844, 390),
    scale: 1.6,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    outcome: _CountdownContractOutcome.cancel,
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'countdown live brand priority defaultBrand <-> liquidGlass ${scenario.name}',
      (tester) async {
        final originalLocale = I18n.current;
        final originalShadows = debugDisableShadows;
        final originalTimeZoneReader =
            LocalTimezoneResolver.debugSystemTimeZoneReader;
        final originalNativeTimeZoneReader =
            LocalTimezoneResolver.debugNativeSystemTimeZoneReader;
        final previousStore = SharedPreferencesStorePlatform.instance;

        final initialPrefs = <String, Object>{
          'pref_app_timezone_mode': 'fixed',
          'pref_app_timezone_iana': 'Asia/Shanghai',
          'active_brand': scenario.initialBrand,
          'theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'flutter.pref_app_timezone_mode': 'fixed',
          'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
          'flutter.active_brand': scenario.initialBrand,
          'flutter.theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
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
          I18n.setLocale(scenario.locale);
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

          final baselineCountdownWrites = store.countdownWrites;
          void assertZeroCountdownPersistence(String stage) {
            expect(
              store.countdownWrites,
              baselineCountdownWrites,
              reason:
                  '$stage: expected zero duoyi_countdowns writes '
                  '(actual=${store.countdownWrites}, baseline=$baselineCountdownWrites)',
            );
            expect(
              countdownProvider.items,
              isEmpty,
              reason:
                  '$stage: expected countdownProvider.items to remain empty',
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
                            textScaler: TextScaler.linear(scenario.scale),
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

          // 1. Verify main screen mounted and add button is available
          expect(find.byType(CountdownScreen), findsOneWidget);
          expect(find.byType(BrandRouteSurface), findsOneWidget);
          final addButton = find.byKey(const ValueKey('countdown_add_button'));
          expect(addButton, findsOneWidget);

          assertZeroCountdownPersistence('1. initial screen load');
          await _capture(tester, boundary, '${scenario.name}-01-initial');

          // 2. Open editor sheet via real CountdownScreen add entry
          await tester.ensureVisible(addButton);
          await _boundedPumpAndSettle(tester);
          await tester.tap(addButton);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(find.byType(AppModalSheet), findsOneWidget);
          assertZeroCountdownPersistence('2. after editor open');

          // 3. Locate inputs by stable controller identity
          final textFields = find.descendant(
            of: find.byType(AppModalSheet),
            matching: find.byType(TextField),
          );
          expect(textFields, findsNWidgets(2));
          final initialTitleField = textFields.first;
          final initialCategoryField = textFields.last;

          final titleController = tester
              .widget<TextField>(initialTitleField)
              .controller!;
          final categoryController = tester
              .widget<TextField>(initialCategoryField)
              .controller!;

          Finder findTitleField() => find.byWidgetPredicate(
            (w) => w is TextField && identical(w.controller, titleController),
          );
          Finder findCategoryField() => find.byWidgetPredicate(
            (w) =>
                w is TextField && identical(w.controller, categoryController),
          );

          final initialEditorState = _countdownEditorState(
            tester,
            findTitleField(),
          );
          final initialModalRoute = ModalRoute.of(
            tester.element(findTitleField()),
          );
          expect(initialModalRoute, isNotNull);

          // 4. Enter draft into title and custom category
          final draftTitle = 'Launch Milestone ${scenario.name}';
          const draftTitleSelection = TextSelection(
            baseOffset: 2,
            extentOffset: 8,
          );

          await tester.ensureVisible(findTitleField());
          await _boundedPumpAndSettle(tester);
          await tester.tap(findTitleField());
          await tester.enterText(findTitleField(), draftTitle);
          titleController.selection = draftTitleSelection;
          await tester.pump();

          expect(titleController.text, draftTitle);
          expect(titleController.selection, draftTitleSelection);

          final draftCategory = 'ProjectAlpha';
          const draftCategorySelection = TextSelection(
            baseOffset: 1,
            extentOffset: 5,
          );

          await tester.ensureVisible(findCategoryField());
          await _boundedPumpAndSettle(tester);
          await tester.tap(findCategoryField());
          await tester.enterText(findCategoryField(), draftCategory);
          categoryController.selection = draftCategorySelection;
          await tester.pump();

          expect(categoryController.text, draftCategory);
          expect(categoryController.selection, draftCategorySelection);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();

          // 5. Open date picker and pick today's date via hit-testable buttons with pumped layout
          final targetDateTile = find.widgetWithIcon(
            ListTile,
            Icons.event_outlined,
          );
          expect(targetDateTile, findsOneWidget);
          await tester.ensureVisible(targetDateTile);
          await _boundedPumpAndSettle(tester);
          await tester.tap(targetDateTile);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);
          expect(find.byType(AppModalSheet), findsNWidgets(2));

          final datePickerSheet = find.byType(AppModalSheet).last;
          final todayButton = find.descendant(
            of: datePickerSheet,
            matching: find.widgetWithIcon(TextButton, Icons.today_outlined),
          );
          expect(todayButton, findsOneWidget);
          await tester.ensureVisible(todayButton);
          await _boundedPumpAndSettle(tester);
          expect(todayButton.hitTestable(), findsOneWidget);
          final todayAtTap = DateTime.now();
          final expectedToday = DateTime(
            todayAtTap.year,
            todayAtTap.month,
            todayAtTap.day,
          );
          await tester.tap(todayButton);
          await _boundedPumpAndSettle(tester);

          final confirmButton = find.descendant(
            of: datePickerSheet,
            matching: find.widgetWithText(
              FilledButton,
              I18n.tr('action.confirm'),
            ),
          );
          expect(confirmButton, findsOneWidget);
          await tester.ensureVisible(confirmButton);
          await _boundedPumpAndSettle(tester);
          await tester.tap(confirmButton);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);
          expect(find.byType(AppModalSheet), findsOneWidget);

          // The production Today action uses the device civil clock.
          // Assert its independently captured date, not a date parsed from output.
          final pickedTargetDate = expectedToday;
          final formattedPickedDate = I18nDateFormat.date(
            pickedTargetDate,
            pattern: AppDateFormat.readPattern(
              tester.element(findTitleField()),
            ),
          );
          expect(find.text(formattedPickedDate), findsOneWidget);

          // 6. Enable due reminder switch
          final reminderSwitch = find.byType(SwitchListTile);
          expect(reminderSwitch, findsOneWidget);
          expect(tester.widget<SwitchListTile>(reminderSwitch).value, isFalse);
          await tester.ensureVisible(reminderSwitch);
          await _boundedPumpAndSettle(tester);
          await tester.tap(reminderSwitch);
          await _boundedPumpAndSettle(tester);
          expect(tester.widget<SwitchListTile>(reminderSwitch).value, isTrue);

          final reminderKindFinder = find.byType(SegmentedButton<ReminderKind>);
          expect(reminderKindFinder, findsOneWidget);
          expect(
            tester
                .widget<SegmentedButton<ReminderKind>>(reminderKindFinder)
                .selected,
            {ReminderKind.push},
          );

          // 7. Establish meaningful nonzero scroll offset
          Finder findEditorScrollable() => find.descendant(
            of: find.byType(AppModalSheet).last,
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          );
          final editorScrollable = findEditorScrollable();
          expect(editorScrollable, findsOneWidget);

          final initialMaxExtent = tester
              .state<ScrollableState>(editorScrollable)
              .position
              .maxScrollExtent;
          if (scenario.size.width > scenario.size.height) {
            expect(initialMaxExtent, greaterThan(0.0));
          }
          // Portrait can fit the complete editor. Landscape provides the
          // nonzero scrolling case; both must retain their actual offsets.
          if (initialMaxExtent > 0) {
            final position = tester
                .state<ScrollableState>(editorScrollable)
                .position;
            position.jumpTo((initialMaxExtent * 0.3).clamp(0.0, 60.0));
          }
          await _boundedPumpAndSettle(tester);
          final initialScrollOffset = tester
              .state<ScrollableState>(editorScrollable)
              .position
              .pixels;
          expect(
            initialScrollOffset,
            initialMaxExtent > 0 ? greaterThan(0.0) : equals(0.0),
            reason:
                'Retain the real scroll offset for overflowing or fitting content',
          );

          assertZeroCountdownPersistence('3. after all draft inputs');
          await _capture(
            tester,
            boundary,
            '${scenario.name}-02-draft',
            scrollableFinder: editorScrollable,
            scrollToOffset: initialScrollOffset,
            restoreOffset: initialScrollOffset,
          );

          void assertEditorStateRetained(String stage) {
            final currentTitleField = findTitleField();
            final currentCategoryField = findCategoryField();
            expect(
              currentTitleField,
              findsOneWidget,
              reason:
                  '$stage: title field must be located by stable controller',
            );
            expect(
              currentCategoryField,
              findsOneWidget,
              reason:
                  '$stage: category field must be located by stable controller',
            );

            expect(
              identical(
                _countdownEditorState(tester, currentTitleField),
                initialEditorState,
              ),
              isTrue,
              reason: '$stage: editor State identity must be preserved',
            );
            expect(
              identical(
                ModalRoute.of(tester.element(currentTitleField)),
                initialModalRoute,
              ),
              isTrue,
              reason: '$stage: ModalRoute identity must be preserved',
            );
            expect(
              identical(
                tester.widget<TextField>(currentTitleField).controller,
                titleController,
              ),
              isTrue,
              reason: '$stage: title controller identity must be preserved',
            );
            expect(
              identical(
                tester.widget<TextField>(currentCategoryField).controller,
                categoryController,
              ),
              isTrue,
              reason: '$stage: category controller identity must be preserved',
            );

            expect(
              titleController.text,
              draftTitle,
              reason: '$stage: title draft text must be retained',
            );
            expect(
              titleController.selection,
              draftTitleSelection,
              reason: '$stage: title selection must be retained',
            );
            expect(
              categoryController.text,
              draftCategory,
              reason: '$stage: category draft text must be retained',
            );
            expect(
              categoryController.selection,
              draftCategorySelection,
              reason: '$stage: category selection must be retained',
            );

            final currentFormattedDate = I18nDateFormat.date(
              pickedTargetDate,
              pattern: AppDateFormat.readPattern(
                tester.element(currentTitleField),
              ),
            );
            expect(
              find.text(currentFormattedDate),
              findsOneWidget,
              reason: '$stage: picked date display must be retained',
            );

            final switchTile = tester.widget<SwitchListTile>(
              find.byType(SwitchListTile),
            );
            expect(
              switchTile.value,
              isTrue,
              reason: '$stage: reminder switch value must remain enabled',
            );
            expect(
              find.byType(SegmentedButton<ReminderKind>),
              findsOneWidget,
              reason:
                  '$stage: reminder kind segmented button must remain mounted',
            );

            final sheetElement = tester.element(
              find.byType(AppModalSheet).last,
            );
            expect(
              MediaQuery.textScalerOf(sheetElement),
              equals(TextScaler.linear(scenario.scale)),
              reason: '$stage: textScaler must not be downscaled',
            );
          }

          void assertThemeAndSurface(String brandId, String stage) {
            expect(
              theme.brand.id,
              brandId,
              reason: '$stage: ThemeProvider brand id',
            );
            final expectedBrand = AppBrands.byId(brandId);
            final sheetElement = tester.element(
              find.byType(AppModalSheet).last,
            );
            final titleElement = tester.element(findTitleField());

            final controlTheme = Theme.of(titleElement);
            expect(
              controlTheme.colorScheme.primary,
              equals(expectedBrand.theme.colorScheme.primary),
              reason:
                  '$stage: Theme.of at target control must match $brandId primary color',
            );

            final surfaceStyle = appSurfaceStyleOf(sheetElement);
            if (brandId == 'liquidGlass') {
              expect(
                surfaceStyle,
                equals(AppSurfaceStyle.liquidGlass),
                reason:
                    '$stage: appSurfaceStyleOf inside editor must equal liquidGlass style',
              );
              expect(
                surfaceStyle?.cardBorder,
                equals(AppSurfaceStyle.liquidGlass.cardBorder),
                reason: '$stage: cardBorder must match liquidGlass border',
              );
            } else {
              expect(
                surfaceStyle,
                isNot(equals(AppSurfaceStyle.liquidGlass)),
                reason:
                    '$stage: appSurfaceStyleOf must not equal liquidGlass for $brandId',
              );
              expect(
                surfaceStyle?.sheetTopRadius,
                equals(DesignTokens.sheetIosTopRadius),
                reason:
                    '$stage: sheetTopRadius must match iOS default brand token',
              );
            }
          }

          // 8. Live brand switch to targetBrand
          await tester.runAsync(() async {
            final switched = await theme.setBrand(scenario.targetBrand);
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          assertThemeAndSurface(
            scenario.targetBrand,
            '4. brand switch to ${scenario.targetBrand}',
          );
          assertEditorStateRetained(
            '4. brand switch to ${scenario.targetBrand}',
          );
          assertZeroCountdownPersistence(
            '4. brand switch to ${scenario.targetBrand}',
          );

          final offsetAfterBrandSwitch = tester
              .state<ScrollableState>(findEditorScrollable())
              .position
              .pixels;
          expect(
            offsetAfterBrandSwitch,
            equals(initialScrollOffset),
            reason:
                'Scroll offset must be exactly preserved across brand switch to ${scenario.targetBrand}',
          );
          await _capture(
            tester,
            boundary,
            '${scenario.name}-03-target-brand',
            scrollableFinder: findEditorScrollable(),
            scrollToOffset: initialScrollOffset,
            restoreOffset: initialScrollOffset,
          );

          // 9. Live brand roundtrip back to initialBrand
          await tester.runAsync(() async {
            final reverted = await theme.setBrand(scenario.initialBrand);
            expect(reverted, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          assertThemeAndSurface(
            scenario.initialBrand,
            '5. brand roundtrip back to ${scenario.initialBrand}',
          );
          assertEditorStateRetained(
            '5. brand roundtrip back to ${scenario.initialBrand}',
          );
          assertZeroCountdownPersistence(
            '5. brand roundtrip back to ${scenario.initialBrand}',
          );

          final offsetAfterBrandRevert = tester
              .state<ScrollableState>(findEditorScrollable())
              .position
              .pixels;
          expect(
            offsetAfterBrandRevert,
            equals(initialScrollOffset),
            reason:
                'Scroll offset must be exactly preserved across brand revert to ${scenario.initialBrand}',
          );
          await _capture(
            tester,
            boundary,
            '${scenario.name}-04-reverted-brand',
            scrollableFinder: findEditorScrollable(),
            scrollToOffset: initialScrollOffset,
            restoreOffset: initialScrollOffset,
          );

          // 10. Live locale switch to alternative locale
          final altLocale = scenario.locale == AppLocale.zh
              ? AppLocale.en
              : AppLocale.zh;
          I18n.setLocale(altLocale);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(find.text(I18n.tr('countdown.title')), findsWidgets);
          expect(find.text(I18n.tr('action.save')), findsOneWidget);
          expect(find.text(I18n.tr('action.cancel')), findsOneWidget);

          assertEditorStateRetained('6. locale switch to $altLocale');
          assertZeroCountdownPersistence('6. locale switch to $altLocale');

          final offsetOtherLocale = tester
              .state<ScrollableState>(findEditorScrollable())
              .position
              .pixels;
          final posOther = tester
              .state<ScrollableState>(findEditorScrollable())
              .position;
          expect(
            offsetOtherLocale,
            greaterThanOrEqualTo(posOther.minScrollExtent),
          );
          expect(
            offsetOtherLocale,
            lessThanOrEqualTo(posOther.maxScrollExtent),
          );
          expect(
            offsetOtherLocale,
            initialScrollOffset.clamp(
              posOther.minScrollExtent,
              posOther.maxScrollExtent,
            ),
            reason:
                'Locale reflow permits only ordinary scroll extent clamping',
          );
          await _capture(
            tester,
            boundary,
            '${scenario.name}-05-alt-locale',
            scrollableFinder: findEditorScrollable(),
            scrollToOffset: offsetOtherLocale,
            restoreOffset: offsetOtherLocale,
          );

          // 11. Live locale switch back to starting locale
          I18n.setLocale(scenario.locale);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(find.text(I18n.tr('countdown.title')), findsWidgets);
          expect(find.text(I18n.tr('action.save')), findsOneWidget);
          expect(find.text(I18n.tr('action.cancel')), findsOneWidget);

          assertEditorStateRetained(
            '7. locale roundtrip back to ${scenario.locale}',
          );
          assertZeroCountdownPersistence(
            '7. locale roundtrip back to ${scenario.locale}',
          );

          final offsetRestoredLocale = tester
              .state<ScrollableState>(findEditorScrollable())
              .position
              .pixels;
          expect(
            offsetRestoredLocale,
            offsetOtherLocale.clamp(
              tester
                  .state<ScrollableState>(findEditorScrollable())
                  .position
                  .minScrollExtent,
              tester
                  .state<ScrollableState>(findEditorScrollable())
                  .position
                  .maxScrollExtent,
            ),
            reason:
                'Locale roundtrip retains the prior offset within new extents',
          );
          await _capture(
            tester,
            boundary,
            '${scenario.name}-06-restored-locale',
            scrollableFinder: findEditorScrollable(),
            scrollToOffset: initialScrollOffset,
            restoreOffset: initialScrollOffset,
          );

          // 12. Contract outcome: Cancel vs Save
          if (scenario.outcome == _CountdownContractOutcome.cancel) {
            final cancelButton = find.descendant(
              of: find.byType(AppModalSheet).last,
              matching: find.widgetWithText(
                TextButton,
                I18n.tr('action.cancel'),
              ),
            );
            expect(cancelButton, findsOneWidget);
            await tester.ensureVisible(cancelButton);
            await _boundedPumpAndSettle(tester);
            await tester.tap(cancelButton);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(
              find.byType(AppModalSheet),
              findsNothing,
              reason: 'Cancel must dismiss the editor modal',
            );
            expect(
              countdownProvider.items,
              isEmpty,
              reason: 'Cancel must not persist any countdown item',
            );
            expect(
              store.countdownWrites,
              baselineCountdownWrites,
              reason: 'Cancel must perform zero storage writes',
            );

            final storedPrefs = await SharedPreferences.getInstance();
            expect(storedPrefs.getStringList('duoyi_countdowns'), isNull);

            await _capture(tester, boundary, '${scenario.name}-07-cancelled');
          } else {
            // Keep reminder-on state through all live transitions, then explicitly
            // disable it before saving this synthetic fixture.
            final reminder = find.byType(SwitchListTile);
            expect(tester.widget<SwitchListTile>(reminder).value, isTrue);
            await tester.ensureVisible(reminder);
            await _boundedPumpAndSettle(tester);
            expect(reminder.hitTestable(), findsOneWidget);
            await tester.tap(reminder);
            await _boundedPumpAndSettle(tester);
            expect(tester.widget<SwitchListTile>(reminder).value, isFalse);
            final saveButton = find.byKey(
              const ValueKey('countdown_editor_save_button'),
            );
            expect(saveButton, findsOneWidget);
            await tester.ensureVisible(saveButton);
            await _boundedPumpAndSettle(tester);
            await tester.tap(saveButton);
            await _drainAccountWrites(tester);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(
              find.byType(AppModalSheet),
              findsNothing,
              reason: 'Save must dismiss the editor modal upon success',
            );
            expect(
              countdownProvider.items.length,
              1,
              reason: 'Save must persist exactly one countdown item',
            );

            final savedItem = countdownProvider.items.single;
            expect(savedItem.title, draftTitle);
            expect(savedItem.category, draftCategory);
            expect(savedItem.targetDate, pickedTargetDate);
            expect(
              savedItem.remind,
              isFalse,
              reason:
                  'Explicitly disabled synthetic reminder must remain off on save',
            );
            expect(savedItem.reminderKind, ReminderKind.off);

            expect(
              store.countdownWrites,
              baselineCountdownWrites + 1,
              reason: 'Save must execute exactly one storage write',
            );

            final storedPrefs = await SharedPreferences.getInstance();
            final rawList = storedPrefs.getStringList('duoyi_countdowns');
            expect(rawList, isNotNull);
            expect(rawList!.length, 1);
            final decoded = jsonDecode(rawList.single) as Map<String, dynamic>;
            expect(decoded['title'], draftTitle);
            expect(decoded['category'], draftCategory);
            expect(decoded['remind'], isFalse);
            expect(decoded['reminderKind'], ReminderKind.off.index);

            expect(find.text(draftTitle), findsOneWidget);
            expect(find.text(draftCategory), findsOneWidget);

            await _capture(tester, boundary, '${scenario.name}-07-saved');
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
