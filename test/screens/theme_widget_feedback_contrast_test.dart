// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/theme_picker_screen.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_display_mode_store.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

// The caller must admit resources and select a fresh named evidence batch.
const _evidenceEnv = 'DUOYI_THEME_WIDGET_CONTRAST_SCREENSHOT_DIR';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in [AppLocale.zh, AppLocale.en]) {
      for (final scale in [1.6, 2.0]) {
        final suffix = '$brand-${locale.name}-320-${scale.toStringAsFixed(1)}';
        testWidgets('theme-feedback-$suffix', (tester) async {
          final fixture = _Fixture(brand, locale, scale);
          addTearDown(() => fixture.dispose(tester));
          await fixture.install(tester, widgetRoute: false);
          final retained = tester.state(find.byType(ThemePickerScreen));
          final account = fixture.auth.state;
          final generation = AccountLocalDataCleaner.accountDataGeneration;
          final prefs = await SharedPreferences.getInstance();
          final savedShop = prefs.getString('theme_shop_state');
          final writes = fixture.store.mutations;

          // Two real cards in every section: unlocked/inactive and locked.
          // The persisted fixture explicitly unlocks the first two rewards.
          final theme = fixture.theme;
          final options = <({String role, String label, bool locked})>[
            (role: 'brand-inactive', label: AppBrands.byId(
              brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand',
            ).localizedName, locked: false),
            (role: 'brand-locked', label: AppBrands.byId('re0').localizedName,
              locked: true),
            for (final locked in [false, true])
              (role: 'backdrop-${locked ? 'locked' : 'inactive'}',
                label: (() {
                  final item = theme.focusBackdrops.firstWhere((item) =>
                    locked ? !theme.isFocusBackdropUnlocked(item.id) :
                    theme.isFocusBackdropUnlocked(item.id) &&
                      item.id != theme.activeFocusBackdrop.id);
                  return DataSettingsUiCopy.focusBackdropName(item.id, item.name);
                })(), locked: locked),
            for (final locked in [false, true])
              (role: 'frame-${locked ? 'locked' : 'inactive'}',
                label: (() {
                  final item = theme.avatarFrames.firstWhere((item) =>
                    locked ? !theme.isAvatarFrameUnlocked(item.id) :
                    theme.isAvatarFrameUnlocked(item.id) &&
                      item.id != theme.activeAvatarFrame.id);
                  return DataSettingsUiCopy.avatarFrameName(item.id, item.name);
                })(), locked: locked),
            for (final locked in [false, true])
              (role: 'skin-${locked ? 'locked' : 'inactive'}',
                label: (() {
                  final item = theme.cardSkins.firstWhere((item) =>
                    locked ? !theme.isCardSkinUnlocked(item.id) :
                    theme.isCardSkinUnlocked(item.id) &&
                      item.id != theme.activeCardSkin.id);
                  return DataSettingsUiCopy.cardSkinName(item.id, item.name);
                })(), locked: locked),
          ];
          for (final option in options) {
            final card = await _revealThemeOption(tester,
              label: option.label,
              brandId: option.role == 'brand-locked' ? 're0' :
                option.role == 'brand-inactive' ?
                  (brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand') : null,
            );
            final icon = find.descendant(of: card, matching: find.byIcon(
              option.locked ? Icons.lock_outline : Icons.radio_button_unchecked,
            ));
            expect(icon, findsOneWidget, reason: option.role);
            final probe = await _Raster.capture(tester, fixture.boundary,
              '$suffix-${option.role}',
              saveImage: option.role.startsWith('brand-'));
            final paragraph = _paragraph(tester, icon);
            final cardRect = probe.rect(tester.renderObject<RenderBox>(card));
            final glyph = probe.rect(paragraph);
            expect(cardRect.contains(glyph.topLeft), isTrue);
            expect(cardRect.contains(glyph.bottomRight - const Offset(.1, .1)),
              isTrue);
            final points = [
              Offset(glyph.left + glyph.width * .25, cardRect.top + 6),
              Offset(glyph.left + glyph.width * .75, cardRect.top + 9),
            ];
            await probe.check(tester, paragraph, card, points, 3,
              '$suffix-${option.role}');
            if (brand == 'defaultBrand' && option.role == 'brand-inactive') {
              final scaffold = tester.widget<Scaffold>(find.descendant(
                of: find.byType(ThemePickerScreen),
                matching: find.byType(Scaffold),
              ));
              final designated = theme.brand.theme.scaffoldBackgroundColor;
              final routePixel = probe.pixel(Offset(4, cardRect.center.dy));
              final cardPixel = probe.pixel(points.first);
              await _record('$suffix-hierarchy', {
                'scaffold': _hex(scaffold.backgroundColor!),
                'designated': _hex(designated),
                'routePixel': _hex(routePixel), 'cardPixel': _hex(cardPixel),
                'separationRatio': _ratio(cardPixel, routePixel),
              });
              expect(scaffold.backgroundColor, designated);
              _expectNearColor(routePixel, designated);
              expect(_ratio(cardPixel, routePixel), greaterThan(1.01),
                reason: 'Default-brand card remains distinct from scaffold');
            }
          }
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(ThemePickerScreen)), same(retained));
          expect(find.text(I18n.tr('theme.title')), findsOneWidget);
          expect(theme.brand.id, brand);
          expect(fixture.auth.state, same(account));
          expect(AccountLocalDataCleaner.accountDataGeneration, generation);
          expect(fixture.store.mutations, writes);
          expect(prefs.getString('theme_shop_state'), savedShop);
          expect(tester.takeException(), isNull);
        });

        testWidgets('widget-feedback-$suffix', (tester) async {
          final fixture = _Fixture(brand, locale, scale);
          addTearDown(() => fixture.dispose(tester));
          await fixture.install(tester, widgetRoute: true);
          final retained = tester.state(find.byType(WidgetScreen));
          final account = fixture.auth.state;
          fixture.native.failNext = true;
          final failed = fixture.native.watchSave();
          await tester.runAsync(() async {
            _selector(tester).onSelectionChanged!({WidgetDisplayMode.detailed});
          });
          await _waitSave(tester, failed);
          final prefs = await SharedPreferences.getInstance();
          final pending = WidgetDisplayModeSelection.read(prefs);
          expect(pending.mode, 'detailed');
          expect(pending.pending, isTrue);
          expect(pending.intentId, isNotEmpty);
          expect(fixture.native.values['widget_display_mode'], 'standard');
          expect(fixture.native.saves, ['detailed']);
          final snack = find.byType(SnackBar);
          final retry = find.byKey(const ValueKey('widget_style_retry'));
          expect(snack, findsOneWidget);
          expect(retry.hitTestable(), findsOneWidget);
          final probe = await _Raster.capture(tester, fixture.boundary,
            '$suffix-snackbar-failure');
          final retryParagraph = _paragraph(tester, retry);
          final retryRect = probe.rect(tester.renderObject<RenderBox>(retry));
          await probe.check(tester, retryParagraph, retry, [
            Offset(retryRect.center.dx, retryRect.top + 3),
            Offset(retryRect.center.dx, retryRect.bottom - 3),
          ], 4.5, '$suffix-snackbar-retry');
          for (final paragraph in tester.renderObjectList<RenderParagraph>(
            find.descendant(of: snack, matching: find.byType(RichText)),
          )) {
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(paragraph.textSize.width,
              lessThanOrEqualTo(paragraph.size.width + .1));
            expect(paragraph.textSize.height,
              lessThanOrEqualTo(paragraph.size.height + .1));
          }

          // A live locale switch keeps the pending intent and native writes.
          final encoded = prefs.getString(WidgetDisplayModeSelection.storageKey);
          final writes = fixture.store.mutations;
          final generation = AccountLocalDataCleaner.accountDataGeneration;
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.state(find.byType(WidgetScreen)), same(retained));
          expect(find.descendant(of: snack,
            matching: find.text(WidgetUiCopy.styleSyncFailed)), findsOneWidget);
          expect(find.descendant(of: retry,
            matching: find.text(WidgetUiCopy.actionRetry)), findsOneWidget);
          expect(fixture.auth.state, same(account));
          expect(AccountLocalDataCleaner.accountDataGeneration, generation);
          expect(fixture.store.mutations, writes);
          expect(prefs.getString(WidgetDisplayModeSelection.storageKey), encoded);
          expect(fixture.native.saves, ['detailed']);
          I18n.setLocale(locale);
          await tester.pump(const Duration(milliseconds: 100));

          // Tap the actual Snackbar control, then independently fail again and
          // exercise the persistent page control for the newer compact intent.
          final succeeded = fixture.native.watchSave();
          await tester.runAsync(() => tester.tap(retry));
          await _waitSave(tester, succeeded);
          final delivered = WidgetDisplayModeSelection.read(prefs);
          expect(delivered.pending, isFalse);
          expect(delivered.intentId, pending.intentId);
          expect(delivered.mode, 'detailed');
          expect(fixture.native.values['widget_display_mode'], 'detailed');
          fixture.native.failNext = true;
          final failedAgain = fixture.native.watchSave();
          await tester.runAsync(() async {
            _selector(tester).onSelectionChanged!({WidgetDisplayMode.compact});
          });
          await _waitSave(tester, failedAgain);
          final compact = WidgetDisplayModeSelection.read(prefs);
          expect(compact.pending, isTrue);
          expect(compact.intentId, isNot(pending.intentId));
          final context = tester.element(find.byType(WidgetScreen));
          ScaffoldMessenger.of(context).clearSnackBars();
          await tester.pump(const Duration(milliseconds: 400));
          final pageRetry = find.byKey(const ValueKey('widget_style_sync_retry'));
          await _reveal(tester, pageRetry);
          expect(pageRetry.hitTestable(), findsOneWidget);
          final card = find.ancestor(of: pageRetry,
            matching: find.byType(AppSurfaceCard)).first;
          final pageProbe = await _Raster.capture(tester, fixture.boundary,
            '$suffix-page-retry');
          final pageRect = pageProbe.rect(tester.renderObject<RenderBox>(pageRetry));
          await pageProbe.check(tester, _paragraph(tester,
            find.descendant(of: pageRetry,
              matching: find.text(WidgetUiCopy.actionRetry))), card, [
            Offset(pageRect.center.dx, pageRect.top + 3),
            Offset(pageRect.center.dx, pageRect.bottom - 3),
          ], 4.5, '$suffix-page-retry');
          final pageSucceeded = fixture.native.watchSave();
          await tester.runAsync(() => tester.tap(pageRetry));
          await _waitSave(tester, pageSucceeded);
          final finalSelection = WidgetDisplayModeSelection.read(prefs);
          expect(finalSelection.mode, 'compact');
          expect(finalSelection.pending, isFalse);
          expect(finalSelection.intentId, compact.intentId);
          expect(fixture.native.saves,
            ['detailed', 'detailed', 'compact', 'compact']);
          expect(fixture.native.values['widget_display_mode'], 'compact');

          // Use a currently valid pending retry so account invalidation is the
          // reason it loses authority, independently of older intent guards.
          fixture.native.failNext = true;
          final boundaryFailure = fixture.native.watchSave();
          await tester.runAsync(() async {
            _selector(tester).onSelectionChanged!({WidgetDisplayMode.detailed});
          });
          await _waitSave(tester, boundaryFailure);
          final boundaryPending = WidgetDisplayModeSelection.read(prefs);
          expect(boundaryPending.pending, isTrue);
          expect(boundaryPending.mode, 'detailed');
          final boundaryRetry = tester.widget<TextButton>(
            find.byKey(const ValueKey('widget_style_retry'))).onPressed!;
          final beforeStale = fixture.store.mutations;
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          boundaryRetry();
          await _settle(tester);
          expect(fixture.store.mutations, beforeStale);
          expect(fixture.native.saves,
            ['detailed', 'detailed', 'compact', 'compact', 'detailed']);
          expect(prefs.getString(WidgetDisplayModeSelection.storageKey),
            boundaryPending.encode());
          expect(fixture.native.values['widget_display_mode'], 'compact');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

SegmentedButton<WidgetDisplayMode> _selector(WidgetTester tester) =>
  tester.widget<SegmentedButton<WidgetDisplayMode>>(find.byWidgetPredicate(
    (widget) => widget is SegmentedButton<WidgetDisplayMode>));

RenderParagraph _paragraph(WidgetTester tester, Finder root) =>
  tester.renderObject<RenderParagraph>(find.descendant(of: root,
    matching: find.byType(RichText)).first);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(
      const Duration(milliseconds: 10)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _waitSave(WidgetTester tester, Future<void> save) async {
  await _settle(tester);
  await tester.runAsync(() => save.timeout(const Duration(seconds: 3)));
  await _settle(tester);
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 350,
      scrollable: find.byType(Scrollable).first, maxScrolls: 100);
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
}

Future<Finder> _revealThemeOption(WidgetTester tester, {
  required String label,
  String? brandId,
}) async {
  // A lazy ListView may not have mounted this option yet. Keep an unfiltered
  // finder until scrolling materializes it: Finder.first throws on zero hits.
  // Brand previews have unique production keys; the other section labels are
  // scoped to actionable AppSurfaceCards to exclude summary/choice panels.
  final anchor = brandId == null ? find.text(label) :
    find.byKey(ValueKey('theme_card_bg_$brandId'));
  final cards = find.ancestor(of: anchor, matching: find.byWidgetPredicate(
    (widget) => widget is AppSurfaceCard && widget.onTap != null,
  ));
  if (cards.evaluate().isEmpty) {
    // An earlier brand (for example re0 after liquidGlass) may have been
    // disposed above the viewport. Search from the actual list's beginning.
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.minScrollExtent);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(cards, 350,
      scrollable: scrollable, maxScrolls: 100);
  }
  expect(cards, findsOneWidget, reason: 'Real mounted option card: $label');
  expect(find.descendant(of: cards, matching: find.text(label)), findsOneWidget);
  await Scrollable.ensureVisible(tester.element(cards), alignment: .5);
  await tester.pumpAndSettle();
  return cards;
}

class _Fixture {
  _Fixture(this.brand, this.locale, this.scale);
  final String brand;
  final AppLocale locale;
  final double scale;
  final theme = ThemeProvider();
  final auth = AuthProvider();
  final achievements = AchievementProvider();
  final boundary = GlobalKey();
  final native = _NativeStore();
  late _Preferences store;
  SharedPreferencesStorePlatform? previousStore;
  Future<bool> Function()? previousRefresher;
  bool? previousSupport;
  bool? previousAndroid;
  bool installed = false;

  Future<void> install(WidgetTester tester, {required bool widgetRoute}) async {
    previousStore = SharedPreferencesStorePlatform.instance;
    previousRefresher = HomeWidgetService.dashboardDataRefresher;
    previousSupport = HomeWidgetService.supportedForTesting;
    previousAndroid = AndroidWidgetManager.debugIsAndroidOverride;
    SharedPreferences.setMockInitialValues({});
    store = _Preferences({
      'flutter.theme_shop_state': jsonEncode({
        'activeBrand': brand,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
        'unlockedFocusBackdropIds': theme.focusBackdrops.take(2)
          .map((item) => item.id).toList(),
        'unlockedAvatarFrameIds': theme.avatarFrames.take(2)
          .map((item) => item.id).toList(),
        'unlockedCardSkinIds': theme.cardSkins.take(2)
          .map((item) => item.id).toList(),
      }),
      'flutter.${WidgetDisplayModeSelection.legacyKey}': 'standard',
    });
    SharedPreferencesStorePlatform.instance = store;
    installed = true;
    HomeWidgetService.supportedForTesting = true;
    AndroidWidgetManager.debugIsAndroidOverride = true;
    HomeWidgetService.dashboardDataRefresher = () async => true;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), native.handle);
    messenger.setMockMethodCallHandler(const MethodChannel('duoyi/widgets'),
      (call) async => switch (call.method) {
        'canRequestPinWidget' || 'canOpenWidgetSettings' => true,
        'applyWidgetDisplayMode' || 'refreshAllWidgets' => 0,
        _ => null,
      });
    await tester.runAsync(theme.loadFromStorage);
    await tester.runAsync(loadWeeklyReviewScreenshotFonts);
    I18n.setLocale(locale);
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AchievementProvider>.value(value: achievements),
      ],
      child: Consumer<ThemeProvider>(builder: (context, selected, _) =>
        ValueListenableBuilder<AppLocale>(valueListenable: I18n.localeListenable,
          builder: (context, current, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: selected.brand.theme,
            locale: Locale(current == AppLocale.zh ? 'zh' : 'en'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: boundary, child: child!),
            ),
            home: BrandRouteSurface(remountOnLocaleChange: false,
              child: widgetRoute
                ? const WidgetScreen(hostPlatform: WidgetHostPlatform.android)
                : const ThemePickerScreen()),
          )),
      ),
    ));
    await _settle(tester);
    expect(theme.brand.id, brand);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(AccountPreferenceWrites.drain);
    if (installed) {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('duoyi/widgets'), null);
      HomeWidgetService.dashboardDataRefresher = previousRefresher;
      HomeWidgetService.supportedForTesting = previousSupport;
      AndroidWidgetManager.debugIsAndroidOverride = previousAndroid;
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previousStore!;
    }
    tester.view.reset();
    I18n.setLocale(AppLocale.zh);
    theme.dispose();
    auth.dispose();
    achievements.dispose();
  }
}

class _Preferences extends InMemorySharedPreferencesStore {
  _Preferences(super.values) : super.withData();
  int mutations = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) {
    mutations++;
    return super.setValue(type, key, value);
  }
  @override
  Future<bool> remove(String key) {
    mutations++;
    return super.remove(key);
  }
}

class _NativeStore {
  final values = <String, Object?>{'widget_display_mode': 'standard'};
  final saves = <Object?>[];
  bool failNext = false;
  Completer<void>? waiter;
  Future<void> watchSave() {
    waiter = Completer<void>();
    return waiter!.future;
  }
  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments as Map?;
    switch (call.method) {
      case 'setAppGroupId': return true;
      case 'getWidgetData': return values[args?['id']];
      case 'saveWidgetData':
        final key = args!['id'] as String;
        final value = args['data'];
        if (key == 'widget_display_mode') {
          saves.add(value);
          waiter?.complete();
          waiter = null;
          if (failNext) { failNext = false; return false; }
        }
        values[key] = value;
        return true;
      case 'updateWidget': return true;
      default: return null;
    }
  }
}

class _Raster {
  _Raster(this.render, this.bytes, this.width, this.height);
  final RenderRepaintBoundary render;
  final ByteData bytes;
  final int width;
  final int height;

  static Future<_Raster> capture(WidgetTester tester, GlobalKey boundary,
    String name, {bool saveImage = true}) async {
    await tester.pump();
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final result = await tester.runAsync(() async {
      final picture = await render.toImage(pixelRatio: 1);
      try {
        final raw = (await picture.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final directory = _directory();
        if (directory != null && saveImage) {
          final png = (await picture.toByteData(format: ui.ImageByteFormat.png))!;
          final file = File('$directory/$name.png');
          _reserve(file);
          file.writeAsBytesSync(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
        }
        return _Raster(render, raw, picture.width, picture.height);
      } finally { picture.dispose(); }
    });
    return result!;
  }

  Rect rect(RenderBox box) => MatrixUtils.transformRect(
    box.getTransformTo(render), Offset.zero & box.size);

  Color pixel(Offset point) {
    final x = point.dx.floor();
    final y = point.dy.floor();
    expect(x, inInclusiveRange(0, width - 1));
    expect(y, inInclusiveRange(0, height - 1));
    final offset = (y * width + x) * 4;
    expect(bytes.getUint8(offset + 3), 255);
    return Color.fromARGB(255, bytes.getUint8(offset),
      bytes.getUint8(offset + 1), bytes.getUint8(offset + 2));
  }

  Future<void> check(WidgetTester tester, RenderParagraph paragraph,
    Finder surface, List<Offset> points, double minimum, String name) async {
    final foreground = paragraph.text.style?.foreground?.color ?? paragraph.text.style?.color;
    expect(foreground, isNotNull);
    final surfaceRect = rect(tester.renderObject<RenderBox>(surface));
    final content = tester.renderObjectList<RenderParagraph>(
      find.descendant(of: surface, matching: find.byType(RichText)),
    ).map(rect).toList();
    final observations = <Map<String, Object>>[];
    for (final point in points) {
      expect(surfaceRect.contains(point), isTrue);
      expect(content.any((glyph) => glyph.contains(point)), isFalse,
        reason: '$name must sample blank padding, not painted text');
      final background = pixel(point);
      // Independent source-over composition, independent WCAG luminance.
      final visible = _over(foreground!, background);
      observations.add({'x': point.dx, 'y': point.dy,
        'foreground': _hex(foreground), 'background': _hex(background),
        'visible': _hex(visible), 'ratio': _ratio(visible, background)});
    }
    await _record(name, {'minimum': minimum, 'samples': observations});
    for (final observation in observations) {
      expect(observation['ratio'] as double, greaterThanOrEqualTo(minimum),
        reason: '$name $observation');
    }
  }
}

Color _over(Color foreground, Color background) => Color.fromARGB(255,
  ((foreground.r * foreground.a + background.r * (1 - foreground.a)) * 255).round(),
  ((foreground.g * foreground.a + background.g * (1 - foreground.a)) * 255).round(),
  ((foreground.b * foreground.a + background.b * (1 - foreground.a)) * 255).round());

double _luminance(Color color) {
  double linear(double channel) => channel <= .04045 ? channel / 12.92 :
    math.pow((channel + .055) / 1.055, 2.4).toDouble();
  return .2126 * linear(color.r) + .7152 * linear(color.g) + .0722 * linear(color.b);
}

double _ratio(Color a, Color b) {
  final left = _luminance(a);
  final right = _luminance(b);
  return (math.max(left, right) + .05) / (math.min(left, right) + .05);
}

String _hex(Color color) => color.toARGB32().toRadixString(16).padLeft(8, '0');

void _expectNearColor(Color actual, Color expected) {
  for (final pair in [(actual.r, expected.r), (actual.g, expected.g),
    (actual.b, expected.b)]) {
    expect((pair.$1 - pair.$2).abs(), lessThanOrEqualTo(2 / 255));
  }
}

String? _directory() {
  final value = Platform.environment[_evidenceEnv];
  if (value == null) return null;
  final parts = value.split('/');
  if (!value.startsWith('evidence/') || parts.length < 3 ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw StateError('$_evidenceEnv requires a fresh named directory under evidence/');
  }
  return value;
}

void _reserve(File file) {
  file.parent.createSync(recursive: true);
  if (file.existsSync()) throw StateError('Refusing to overwrite ${file.path}');
}

Future<void> _record(String name, Map<String, Object?> data) async {
  final directory = _directory();
  if (directory == null) return;
  final file = File('$directory/$name.json');
  _reserve(file);
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(data)}\n');
}
