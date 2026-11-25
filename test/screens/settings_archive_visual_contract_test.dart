import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/settings_ui_copy.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/preferences_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

const _archiveStorageKey = 'pref_auto_archive_completed_days';

bool get _before =>
    Platform.environment['DUOYI_ARCHIVE_COPY_PHASE'] == 'before';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    testWidgets(
      'archive real category and jump entry: $brand-320x844-scale160',
      (tester) async {
        final originalLocale = I18n.current;
        final originalReader = LocalTimezoneResolver.debugSystemTimeZoneReader;
        final originalShadows = debugDisableShadows;
        final semantics = tester.ensureSemantics();
        ThemeProvider? theme;
        PreferencesProvider? preferences;
        AppLockProvider? lock;
        try {
          debugDisableShadows = false;
          LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
              'Asia/Shanghai';
          SharedPreferences.setMockInitialValues({
            'active_brand': brand,
            _archiveStorageKey: 0,
          });
          I18n.setLocale(AppLocale.zh);
          tester.view.physicalSize = const Size(320, 844);
          tester.view.devicePixelRatio = 1;
          await tester.runAsync(loadWidgetPolishScreenshotFonts);
          theme = ThemeProvider();
          await theme.loadFromStorage();
          preferences = PreferencesProvider();
          await preferences.loadFromStorage();
          lock = AppLockProvider();
          expect(theme.brand.id, brand);
          expect(preferences.autoArchiveCompletedDays, 0);
          final captureKey = GlobalKey();
          final fonts = theme.brand.theme.textTheme.apply(
            fontFamily: 'DuoyiScreenshotLatin',
            fontFamilyFallback: const ['DuoyiScreenshot'],
          );
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: theme),
                ChangeNotifierProvider.value(value: preferences),
                ChangeNotifierProvider.value(value: lock),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.brand.theme.copyWith(
                  textTheme: fonts,
                  primaryTextTheme: fonts,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.6),
                  ),
                  child: RepaintBoundary(key: captureKey, child: child!),
                ),
                home: const BrandRouteSurface(child: PreferencesScreen()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final category = find.text(SettingsUiCopy.displayAndBehaviorTitle);
          await tester.ensureVisible(category);
          await tester.pumpAndSettle();
          await tester.tap(category);
          await tester.pumpAndSettle();
          final page = find.byType(PersonalizationSettingsScreen);
          expect(page, findsOneWidget);
          expect(find.byType(BackButton), findsOneWidget);
          final pageElement = tester.element(page);
          final pageState = tester.state(page);
          final route = ModalRoute.of(pageElement);
          expect(route!.isCurrent, isTrue);

          final jump = find.widgetWithText(
            ActionChip,
            SettingsUiCopy.jumpToInteraction,
          );
          await tester.ensureVisible(jump);
          await tester.pumpAndSettle();
          await tester.tap(jump);
          await tester.pumpAndSettle();
          final archive = find.byWidgetPredicate(
            (widget) => widget is Slider &&
                widget.min == 0 && widget.max == 365 &&
                widget.divisions == 365,
          );
          expect(archive, findsOneWidget);
          final setting = find.ancestor(
            of: archive,
            matching: find.byWidgetPredicate(
              (widget) => widget.runtimeType.toString() == '_SliderSetting',
            ),
          );
          expect(setting, findsOneWidget);
          await _frame(tester, setting);
          final settingElement = tester.element(setting);
          final settingState = tester.state(setting);
          final scrollableState = Scrollable.of(tester.element(archive));
          final scrollController = scrollableState.widget.controller;
          final primaryController =
              PrimaryScrollController.maybeOf(tester.element(archive));
          expect(scrollableState.position.pixels, greaterThan(0));

          Future<void> checkAndCapture(int days, AppLocale locale) async {
            I18n.setLocale(locale);
            await tester.pumpAndSettle();
            await _frame(tester, setting);
            final value = _renderedValue(days, locale);
            final subtitle = _renderedSubtitle(days, locale);
            expect(SettingsUiCopy.autoArchiveValueLabel(days),
                _valueLabel(days, locale));
            expect(SettingsUiCopy.autoArchiveSubtitle(days),
                _subtitle(days, locale));
            expect(find.descendant(of: setting, matching: find.text(value)),
                findsOneWidget);
            expect(find.descendant(of: setting, matching: find.text(subtitle)),
                findsOneWidget);
            for (final literal in [value, subtitle]) {
              final text = find.descendant(
                of: setting,
                matching: find.text(literal),
              );
              final paragraph = tester.renderObject<RenderParagraph>(text);
              expect(paragraph.didExceedMaxLines, isFalse);
            }
            final spoken = tester.getSemantics(archive).getSemanticsData();
            expect(spoken.value, value);
            expect(spoken.increasedValue, _renderedValue(days + 1, locale));
            if (days > 0) {
              expect(spoken.decreasedValue, _renderedValue(days - 1, locale));
              expect(spoken.hasAction(ui.SemanticsAction.decrease), isTrue);
            }
            expect(spoken.hasAction(ui.SemanticsAction.increase), isTrue);
            expect(tester.widget<Slider>(archive).label, value);
            expect(tester.widget<Slider>(archive).semanticFormatterCallback!(
                days.toDouble()), value);
            expect(preferences!.autoArchiveCompletedDays, days);
            final stored = await SharedPreferences.getInstance();
            expect(stored.getInt(_archiveStorageKey), days);
            expect(tester.element(page), same(pageElement));
            expect(tester.state(page), same(pageState));
            expect(ModalRoute.of(tester.element(page)), same(route));
            expect(route.isCurrent, isTrue);
            expect(tester.element(setting), same(settingElement));
            expect(tester.state(setting), same(settingState));
            final currentScrollable = Scrollable.of(tester.element(archive));
            expect(currentScrollable, same(scrollableState));
            expect(currentScrollable.widget.controller, same(scrollController));
            expect(PrimaryScrollController.maybeOf(tester.element(archive)),
                same(primaryController));
            expect(currentScrollable.position.pixels, greaterThan(0));
            expect(tester.takeException(), isNull);
            await _capture(tester, captureKey,
                '$brand-archive-days$days-${locale.name}', {
              'brand': brand,
              'locale': locale.name,
              'days': days,
              'value': value,
              'subtitle': subtitle,
              'kind': 'archive',
            });
          }

          for (final days in [0, 1, 2]) {
            if (days > 0) {
              I18n.setLocale(AppLocale.zh);
              await tester.pumpAndSettle();
              await _frame(tester, setting);
              final node = tester.getSemantics(archive);
              node.owner!.performAction(node.id, ui.SemanticsAction.increase);
              await tester.pumpAndSettle();
              expect(preferences.autoArchiveCompletedDays, days);
            }
            await checkAndCapture(days, AppLocale.zh);
            await checkAndCapture(days, AppLocale.en);
          }

          // Native decrease must persist too, without another screenshot batch.
          final node = tester.getSemantics(archive);
          node.owner!.performAction(node.id, ui.SemanticsAction.decrease);
          await tester.pumpAndSettle();
          expect(preferences.autoArchiveCompletedDays, 1);
          expect((await SharedPreferences.getInstance())
              .getInt(_archiveStorageKey), 1);
          expect(tester.getSemantics(archive).getSemanticsData().value,
              _before ? '1 days' : '1 day');

          await tester.ensureVisible(find.widgetWithText(
            ActionChip, SettingsUiCopy.jumpToDate,
          ));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(
            ActionChip, SettingsUiCopy.jumpToDate,
          ));
          await tester.pumpAndSettle();
          final zoneElement = tester.element(find.text(
            I18n.tr('preferences.timezone.title'),
          ));
          for (final locale in [AppLocale.zh, AppLocale.en]) {
            I18n.setLocale(locale);
            await tester.pumpAndSettle();
            final title = find.text(I18n.tr('preferences.timezone.title'));
            await tester.ensureVisible(title);
            await tester.pumpAndSettle();
            expect(preferences.followSystemTimeZone, isTrue);
            expect(preferences.appTimeZoneSelection, 'system');
            expect(preferences.appTimeZone, 'Asia/Shanghai');
            final literal = locale == AppLocale.zh
                ? '跟随手机：中国标准时间 (上海)'
                : _before ? 'Follow phone：China Standard Time (Shanghai)'
                    : 'Follow phone: China Standard Time (Shanghai)';
            expect(SettingsUiCopy.followSystemTimeZoneSubtitle(
                preferences.appTimeZone), locale == AppLocale.zh
                    ? '跟随手机：中国标准时间 (上海)'
                    : 'Follow phone: China Standard Time (Shanghai)');
            final caption = find.text(literal);
            expect(caption, findsOneWidget);
            await tester.ensureVisible(caption);
            await tester.pumpAndSettle();
            expect(tester.renderObject<RenderParagraph>(caption)
                .didExceedMaxLines, isFalse);
            expect(tester.element(title), same(zoneElement));
            expect(tester.element(page), same(pageElement));
            expect(tester.state(page), same(pageState));
            expect(preferences.autoArchiveCompletedDays, 1);
            expect((await SharedPreferences.getInstance())
                .getInt(_archiveStorageKey), 1);
            await _capture(tester, captureKey,
                '$brand-timezone-follow-system-${locale.name}', {
              'brand': brand,
              'locale': locale.name,
              'kind': 'timezone',
              'resolvedZone': preferences.appTimeZone,
              'subtitle': literal,
            });
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          semantics.dispose();
          lock?.dispose();
          preferences?.dispose();
          theme?.dispose();
          tester.view.reset();
          I18n.setLocale(originalLocale);
          LocalTimezoneResolver.debugSystemTimeZoneReader = originalReader;
          debugDisableShadows = originalShadows;
          SharedPreferences.setMockInitialValues({});
        }
      },
    );
  }
}

String _valueLabel(int days, AppLocale locale) => locale == AppLocale.zh
    ? days == 0 ? '关' : '$days 天'
    : days == 0 ? 'Off'
        : days == 1 ? '1 day' : '$days days';

String _subtitle(int days, AppLocale locale) => locale == AppLocale.zh
    ? days == 0 ? '从不归档' : '$days 天后自动隐藏'
    : days == 0 ? 'Never archive'
        : days == 1 ? 'Auto-hide after 1 day' : 'Auto-hide after $days days';

String _renderedValue(int days, AppLocale locale) =>
    _before && locale == AppLocale.en && days != 0
        ? '$days days' : _valueLabel(days, locale);

String _renderedSubtitle(int days, AppLocale locale) =>
    _before && locale == AppLocale.en && days != 0
        ? '$days days before auto hide' : _subtitle(days, locale);

Future<void> _frame(WidgetTester tester, Finder setting) async {
  await Scrollable.ensureVisible(tester.element(setting), alignment: 0.5);
  await tester.pumpAndSettle();
  final rect = tester.getRect(setting);
  final appBarBottom = tester.getRect(find.byType(AppBar).last).bottom;
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(320));
  expect(rect.top, greaterThanOrEqualTo(appBarBottom));
  expect(rect.bottom, lessThanOrEqualTo(844));
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name,
    Map<String, Object> state) async {
  if (Platform.environment['DUOYI_CAPTURE_SETTINGS_SCREENSHOTS'] != '1') return;
  final directory = Platform.environment['DUOYI_SETTINGS_SCREENSHOT_DIR'];
  if (directory == null || directory.isEmpty) {
    throw StateError('An explicit unique settings screenshot directory is required');
  }
  await tester.runAsync(() async {
    final file = File('$directory/$name.png');
    final metadata = File('$directory/$name.json');
    if (file.existsSync() || metadata.existsSync()) {
      throw StateError('Refusing to overwrite screenshot evidence: $name');
    }
    final boundary = key.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      metadata.writeAsStringSync('${jsonEncode({
        ...state,
        'phase': _before ? 'before' : 'after',
        'size': [image.width, image.height],
        'dpr': 1,
        'linearTextScale': 1.6,
        'latinFontPath': Platform.environment['DUOYI_WIDGET_SCREENSHOT_LATIN_FONT'],
        'pngPath': file.path,
      })}\n');
    } finally {
      image.dispose();
    }
  });
}
