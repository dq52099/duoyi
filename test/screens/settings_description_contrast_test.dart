import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/settings_ui_copy.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/lock_settings_screen.dart';
import 'package:duoyi/screens/preferences_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/settings_picker_tile.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

enum _Page { overview, display, navigation, lock }

typedef _Target = ({String id, String text, Finder? scope});

List<_Target> _targets(_Page page, PreferencesProvider preferences) {
  _Target target(String id, String text, [Finder? scope]) =>
      (id: id, text: text, scope: scope);
  Finder navRow(String key) => find.ancestor(
    of: find.text(I18n.tr(key)),
    matching: find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_NavConfigTile',
    ),
  );
  return switch (page) {
    _Page.overview => [
      target('hero', SettingsUiCopy.preferencesHeroExplanation),
      target('section', SettingsUiCopy.preferencesCategoriesSectionSubtitle),
      target('display-entry', SettingsUiCopy.displayAndBehaviorSubtitle),
      target('navigation-entry', SettingsUiCopy.navigationSectionSubtitle),
      target(
        'heading-control',
        SettingsUiCopy.preferencesCategoriesSectionTitle,
      ),
    ],
    _Page.display => [
      target('hero', SettingsUiCopy.displayAndBehaviorHeroSubtitle),
      target('section', I18n.tr('preferences.section.date.subtitle')),
      target(
        'picker-row',
        SettingsUiCopy.currentFirstWeekday(preferences.firstDayOfWeek),
      ),
      target('lunar-switch', I18n.tr('preferences.lunar.subtitle')),
      target(
        'defaults-section',
        I18n.tr('preferences.section.defaults.subtitle'),
      ),
      target(
        'focus-description',
        '${preferences.defaultPomodoroMinutes} ${I18n.tr('unit.minute')} · ${I18n.tr('preferences.pomodoro_length.subtitle')}',
      ),
      target(
        'focus-value',
        '${preferences.defaultPomodoroMinutes} ${I18n.tr('unit.min')}',
      ),
      target(
        'interaction-section',
        I18n.tr('preferences.section.interaction.subtitle'),
      ),
      target('haptic-switch', I18n.tr('preferences.haptic.subtitle')),
      target(
        'archive-section',
        I18n.tr('preferences.section.auto_archive.subtitle'),
      ),
      target(
        'archive-description',
        preferences.autoArchiveCompletedDays == 0
            ? I18n.tr('preferences.auto_archive.never')
            : '${preferences.autoArchiveCompletedDays} ${I18n.tr('preferences.auto_archive.after_days')}',
      ),
      target('heading-control', I18n.tr('preferences.section.date')),
    ],
    _Page.navigation => [
      target('banner-control', SettingsUiCopy.navigationBannerMessage),
      target('section', I18n.tr('preferences.section.bottom_nav.subtitle')),
      target(
        'visible',
        I18n.tr('preferences.nav.visible'),
        navRow('nav.today'),
      ),
      target(
        'limit',
        SettingsUiCopy.navigationHiddenAtLimit,
        navRow('nav.calendar'),
      ),
      target('fixed', I18n.tr('preferences.nav.fixed'), navRow('nav.mine')),
      target('heading-control', I18n.tr('nav.today'), navRow('nav.today')),
    ],
    _Page.lock => [
      target('hero-control', I18n.tr('app_lock.hero.subtitle')),
      target('section', I18n.tr('app_lock.section.status.subtitle')),
      target('enabled-switch', I18n.tr('app_lock.enabled')),
      target('change-pin', I18n.tr('app_lock.change_pin.subtitle')),
      target('picker-row', SettingsUiCopy.autoLockSubtitle(5)),
      target('lock-now', I18n.tr('app_lock.lock_now.subtitle')),
      target('tip-control', I18n.tr('app_lock.tip')),
    ],
  };
}

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final layout in ['ordinary', 'narrow', 'landscape']) {
      for (final page in _Page.values) {
        final name = '$brand-$layout-${page.name}';
        testWidgets('settings descriptions are readable $name', (tester) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
              'Asia/Shanghai';
          final theme = ThemeProvider();
          final preferences = PreferencesProvider();
          final lock = AppLockProvider();
          final capture = GlobalKey();
          final originalShadows = debugDisableShadows;
          final measurements = <Map<String, Object?>>[];
          var retainedPages = true;
          var retainedSheets = true;
          try {
            await theme.loadFromStorage();
            await preferences.loadFromStorage();
            expect(await lock.setPin('2468'), isTrue);
            expect(theme.brand.id, brand);
            expect(theme.activeCardSkin.id, ThemeProvider.defaultCardSkinId);
            final prefs = await SharedPreferences.getInstance();
            final initial = {for (final k in prefs.getKeys()) k: prefs.get(k)};
            await tester.runAsync(loadWeeklyReviewScreenshotFonts);
            debugDisableShadows = false;
            tester.view.physicalSize = layout == 'ordinary'
                ? const Size(390, 844)
                : layout == 'narrow'
                ? const Size(320, 844)
                : const Size(568, 320);
            tester.view.devicePixelRatio = 1;
            final scale = layout == 'ordinary' ? 1.0 : 1.6;
            final screen = switch (page) {
              _Page.overview => const PreferencesScreen(),
              _Page.display => const PersonalizationSettingsScreen(),
              _Page.navigation => const BottomNavSettingsScreen(),
              _Page.lock => const LockSettingsScreen(),
            };
            I18n.setLocale(AppLocale.zh);
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<PreferencesProvider>.value(
                    value: preferences,
                  ),
                  ChangeNotifierProvider<AppLockProvider>.value(value: lock),
                ],
                child: MaterialApp(
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: RepaintBoundary(key: capture, child: child!),
                  ),
                  home: BrandRouteSurface(
                    child: page == _Page.lock
                        ? screen
                        : const PreferencesScreen(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (page == _Page.display || page == _Page.navigation) {
              final entry = find.text(
                page == _Page.display
                    ? SettingsUiCopy.displayAndBehaviorTitle
                    : SettingsUiCopy.navigationSectionTitle,
              );
              await tester.ensureVisible(entry);
              await tester.pumpAndSettle();
              await tester.tap(entry);
              await tester.pumpAndSettle();
            }
            final retained = tester.element(find.byType(screen.runtimeType));
            for (final locale in [AppLocale.zh, AppLocale.en]) {
              tester
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position
                  .jumpTo(0);
              await tester.pumpAndSettle();
              I18n.setLocale(locale);
              await tester.pumpAndSettle();
              for (final target in _targets(page, preferences)) {
                final finder = target.scope == null
                    ? find.text(target.text)
                    : find.descendant(
                        of: target.scope!,
                        matching: find.text(target.text),
                      );
                await tester.scrollUntilVisible(
                  finder,
                  240,
                  scrollable: find.byType(Scrollable).first,
                );
                await _measure(
                  tester,
                  capture,
                  finder,
                  target.text,
                  target.id,
                  name,
                  locale,
                  measurements,
                  screenshot: const {
                    'hero',
                    'navigation-entry',
                    'section',
                    'focus-value',
                    'limit',
                    'enabled-switch',
                  }.contains(target.id),
                );
              }
              retainedPages =
                  retainedPages &&
                  identical(
                    tester.element(find.byType(screen.runtimeType)),
                    retained,
                  );
              expect({
                for (final k in prefs.getKeys()) k: prefs.get(k),
              }, initial);
            }
            if (page == _Page.display || page == _Page.lock) {
              final titleKey = page == _Page.display
                  ? 'preferences.first_day.title'
                  : 'app_lock.auto_lock';
              final title = find.text(I18n.tr(titleKey));
              await tester.scrollUntilVisible(
                title,
                -240,
                scrollable: find.byType(Scrollable).first,
              );
              final picker = find.ancestor(
                of: title,
                matching: find.byType(SettingsPickerTile<int>),
              );
              expect(picker, findsOneWidget);
              await Scrollable.ensureVisible(
                tester.element(picker),
                alignment: .5,
              );
              await tester.pumpAndSettle();
              final value = page == _Page.display
                  ? SettingsUiCopy.firstWeekdayLabel(preferences.firstDayOfWeek)
                  : SettingsUiCopy.autoLockOptionLabel(5);
              await tester.tap(
                find.descendant(of: picker, matching: find.text(value)),
              );
              await tester.pumpAndSettle();
              expect(find.byType(AppModalSheet), findsOneWidget);
              final sheet = tester.element(find.byType(AppModalSheet));
              for (final locale in [AppLocale.en, AppLocale.zh]) {
                I18n.setLocale(locale);
                await tester.pumpAndSettle();
                final modal = find.byType(AppModalSheet);
                final subtitle = page == _Page.display
                    ? SettingsUiCopy.currentFirstWeekday(
                        preferences.firstDayOfWeek,
                      )
                    : SettingsUiCopy.autoLockSubtitle(5);
                final options = page == _Page.display
                    ? [
                        I18n.tr('preferences.first_day.current_monday'),
                        I18n.tr('preferences.first_day.current_sunday'),
                      ]
                    : [
                        I18n.tr('app_lock.auto_lock.every_foreground'),
                        '${I18n.tr('app_lock.auto_lock.after_prefix')}5${I18n.tr('app_lock.auto_lock.after_suffix')}',
                      ];
                final descriptions = [subtitle, ...options];
                for (var index = 0; index < descriptions.length; index++) {
                  final text = descriptions[index];
                  final finder = index == 0
                      ? find.descendant(
                          of: find.descendant(
                            of: modal,
                            matching: find.byType(AppSectionHeader),
                          ),
                          matching: find.text(text),
                        )
                      : find
                            .descendant(of: modal, matching: find.text(text))
                            .last;
                  expect(finder, findsOneWidget);
                  await _measure(
                    tester,
                    capture,
                    finder,
                    text,
                    'modal-$index',
                    name,
                    locale,
                    measurements,
                    screenshot: index != 0,
                  );
                }
                retainedSheets =
                    retainedSheets && identical(tester.element(modal), sheet);
                retainedPages =
                    retainedPages &&
                    identical(
                      tester.element(find.byType(screen.runtimeType)),
                      retained,
                    );
                expect({
                  for (final k in prefs.getKeys()) k: prefs.get(k),
                }, initial);
              }
              tester.state<NavigatorState>(find.byType(Navigator).first).pop();
              await tester.pumpAndSettle();
              expect(find.byType(AppModalSheet), findsNothing);
            }
            expect(lock.enabled, isTrue);
            expect(lock.autoLockMinutes, 5);
            expect(await lock.verify('2468'), isTrue);
            expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, initial);
            final expected = switch (page) {
              _Page.overview => 10,
              _Page.display => 30,
              _Page.navigation => 12,
              _Page.lock => 20,
            };
            expect(measurements.length, expected);
            expect(
              retainedPages,
              isTrue,
              reason:
                  'The real route must retain its Element during locale changes',
            );
            expect(
              retainedSheets,
              isTrue,
              reason:
                  'The opened picker must retain its Element during locale changes',
            );
            expect(
              measurements.where((m) => m['readable'] != true).toList(),
              isEmpty,
              reason:
                  'Every active description must have actual contrast >=4.5:1',
            );
          } finally {
            final run = Platform.environment['DUOYI_SETTINGS_DESCRIPTION_RUN'];
            if (run != null) {
              await tester.runAsync(() async {
                final file = File(
                  'evidence/settings-description-contrast-20261020/$run/$name.json',
                );
                await file.parent.create(recursive: true);
                await file.writeAsString(
                  jsonEncode({
                    'pageRetained': retainedPages,
                    'sheetRetained': retainedSheets,
                    'measurements': measurements,
                  }),
                );
              });
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            theme.dispose();
            preferences.dispose();
            lock.dispose();
            tester.view.reset();
            debugDisableShadows = originalShadows;
            I18n.setLocale(AppLocale.zh);
            LocalTimezoneResolver.debugSystemTimeZoneReader = null;
            SharedPreferences.setMockInitialValues({});
          }
        });
      }
    }
  }
}

Future<void> _measure(
  WidgetTester tester,
  GlobalKey capture,
  Finder finder,
  String text,
  String role,
  String name,
  AppLocale locale,
  List<Map<String, Object?>> measurements, {
  bool screenshot = false,
}) async {
  expect(finder, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary =
      capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final rect = MatrixUtils.transformRect(
    paragraph.getTransformTo(boundary),
    Offset.zero & paragraph.size,
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.text.toPlainText(), text);
  expect(paragraph.text.style!.fontWeight, FontWeight.normal);
  final foreground = paragraph.text.style!.color!;
  final raster = (await tester.runAsync(() async {
    final picture = await boundary.toImage(pixelRatio: 1);
    try {
      final run = Platform.environment['DUOYI_SETTINGS_DESCRIPTION_RUN'];
      if (run != null && screenshot) {
        final png = await picture.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'evidence/screenshots/settings-description-contrast-20261020/$run/$name-${locale.name}-$role.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png!.buffer.asUint8List());
      }
      return (
        data: (await picture.toByteData(format: ui.ImageByteFormat.rawRgba))!,
        width: picture.width,
        height: picture.height,
      );
    } finally {
      picture.dispose();
    }
  }))!;
  final samples = <Map<String, Object>>[];
  for (final fraction in [.25, .75]) {
    for (final y in [rect.top - 1, rect.bottom + 1]) {
      final point = Offset(rect.left + rect.width * fraction, y);
      expect(rect.contains(point), isFalse);
      final x = point.dx.floor();
      final py = point.dy.floor();
      expect(x, inInclusiveRange(0, raster.width - 1));
      expect(py, inInclusiveRange(0, raster.height - 1));
      final offset = (py * raster.width + x) * 4;
      final data = raster.data;
      final background = Color.fromARGB(
        data.getUint8(offset + 3),
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      );
      expect(background.a, 1.0);
      samples.add({
        'x': x,
        'y': py,
        'background': background.toARGB32(),
        'contrast': appContrastRatio(
          background,
          Color.alphaBlend(foreground, background),
        ),
      });
    }
  }
  measurements.add({
    'role': role,
    'locale': locale.name,
    'text': text,
    'foreground': foreground.toARGB32(),
    'fontSize': paragraph.text.style!.fontSize,
    'scaledFontSize': paragraph.textScaler.scale(
      paragraph.text.style!.fontSize!,
    ),
    'fontWeight': '${paragraph.text.style!.fontWeight}',
    'rect': [rect.left, rect.top, rect.width, rect.height],
    'samples': samples,
    'readable': samples.every(
      (sample) => (sample['contrast']! as double) >= 4.5,
    ),
  });
}
