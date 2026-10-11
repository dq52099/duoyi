// ignore_for_file: depend_on_referenced_packages

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
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/settings_picker_tile.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';

enum _Page { preferences, display, navigation, lock }

void main() {
  setUp(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
  });
  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('sliders show drafts and persist only when released', (
    tester,
  ) async {
    final store = _SliderPreferencesStore();
    final fixture = await _pump(tester, _Page.display, preferencesStore: store);
    final slider = find.byWidgetPredicate(
      (widget) => widget is Slider && widget.min == 5,
    );
    await tester.scrollUntilVisible(
      slider,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    final control = tester.widget<Slider>(slider);
    control.onChangeStart!(25);
    control.onChanged!(45);
    await tester.pump();
    expect(fixture.preferences.defaultPomodoroMinutes, 25);
    expect(store.writes, isEmpty);
    expect(tester.widget<Slider>(slider).value, 45);
    expect(find.text('45 分'), findsOneWidget);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    expect(find.text('45 min'), findsOneWidget);
    tester.widget<Slider>(slider).onChangeEnd!(45);
    await tester.pumpAndSettle();
    expect(fixture.preferences.defaultPomodoroMinutes, 45);
    expect(store.writes, [45]);
    final increase = find.byTooltip(SettingsUiCopy.increaseValue).first;
    await tester.ensureVisible(increase);
    await tester.tap(increase);
    await tester.pumpAndSettle();
    expect(fixture.preferences.defaultPomodoroMinutes, 50);
    expect(store.writes, [45, 50]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rejected slider save restores value and allows retry', (
    tester,
  ) async {
    final store = _SliderPreferencesStore()..rejectNext = true;
    final fixture = await _pump(tester, _Page.display, preferencesStore: store);
    final slider = find.byWidgetPredicate(
      (widget) => widget is Slider && widget.min == 5,
    );
    await tester.scrollUntilVisible(
      slider,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<Slider>(slider).onChanged!(60);
    await tester.pump();
    tester.widget<Slider>(slider).onChangeEnd!(60);
    await tester.pumpAndSettle();
    expect(fixture.preferences.defaultPomodoroMinutes, 25);
    expect(tester.widget<Slider>(slider).value, 25);
    expect(find.text(SettingsUiCopy.saveFailed), findsOneWidget);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    expect(find.text(SettingsUiCopy.saveFailed), findsOneWidget);
    tester.widget<Slider>(slider).onChanged!(60);
    tester.widget<Slider>(slider).onChangeEnd!(60);
    await tester.pumpAndSettle();
    expect(fixture.preferences.defaultPomodoroMinutes, 60);
    expect(store.writes, [60, 60]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('account invalidation discards a pending slider gesture', (
    tester,
  ) async {
    final store = _SliderPreferencesStore();
    final fixture = await _pump(tester, _Page.display, preferencesStore: store);
    final slider = find.byWidgetPredicate(
      (widget) => widget is Slider && widget.min == 5,
    );
    await tester.scrollUntilVisible(
      slider,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    final control = tester.widget<Slider>(slider);
    control.onChangeStart!(25);
    control.onChanged!(75);
    await tester.pump();
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    fixture.preferences.resetLocalState();
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    tester.widget<Slider>(slider).onChangeEnd!(75);
    await tester.pumpAndSettle();
    expect(store.writes, isEmpty);
    expect(fixture.preferences.defaultPomodoroMinutes, 25);
    expect(tester.widget<Slider>(slider).value, 25);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final page in _Page.values) {
        final name = '${page.name}-${locale.name}-${dark ? 'dark' : 'light'}';
        testWidgets('settings fit 320 / 1.6: $name', (tester) async {
          final fixture = await _pump(tester, page, locale: locale, dark: dark);
          if (page == _Page.preferences) {
            final title = find.text(SettingsUiCopy.displayAndBehaviorTitle);
            final paragraph = tester.renderObject<RenderParagraph>(title);
            expect(paragraph.didExceedMaxLines, isFalse);
          }
          if (page == _Page.navigation) {
            final title = find.text(I18n.tr('nav.calendar'));
            expect(
              tester.renderObject<RenderParagraph>(title).constraints.maxWidth,
              greaterThan(140),
            );
          }
          await _capture(tester, fixture.key, name);
          await _scrollAudit(tester, locale);
          await _capture(tester, fixture.key, '$name-bottom');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('open picker changes language and saves the stable option id', (
    tester,
  ) async {
    final fixture = await _pump(tester, _Page.display);
    final title = find.text(I18n.tr('preferences.first_day.title'));
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsOneWidget);
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text(SettingsUiCopy.selectFirstDay), findsOneWidget);
    _expectEnglish(tester);
    final option = find.descendant(
      of: find.byType(AppModalSheet),
      matching: find.text(I18n.tr('weekday.sun')),
    );
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(fixture.preferences.firstDayOfWeek, DateTime.sunday);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('date and timezone pickers preserve stored identifiers', (
    tester,
  ) async {
    final fixture = await _pump(tester, _Page.display, locale: AppLocale.en);
    Future<void> choose(String key, String value) async {
      final title = find.text(I18n.tr(key));
      await tester.ensureVisible(title);
      await tester.tap(title);
      await tester.pumpAndSettle();
      final option = find.descendant(
        of: find.byType(AppModalSheet),
        matching: find.text(value),
      );
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
    }

    await choose(
      'preferences.date_format.title',
      SettingsUiCopy.dateFormatLabel('yyyy年M月d日'),
    );
    expect(fixture.preferences.dateFormat, 'yyyy年M月d日');
    await choose(
      'preferences.timezone.title',
      SettingsUiCopy.timeZoneDisplayName('Europe/London'),
    );
    expect(fixture.preferences.appTimeZoneSelection, 'Europe/London');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'navigation preserves pinned Me, tab limit and reorder controls',
    (tester) async {
      final fixture = await _pump(
        tester,
        _Page.navigation,
        locale: AppLocale.en,
      );
      Finder actions(int tab) =>
          find.byKey(ValueKey('bottom_nav_actions_$tab'));
      Finder toggle(int tab) =>
          find.descendant(of: actions(tab), matching: find.byType(Switch));
      await tester.ensureVisible(actions(3));
      expect(tester.widget<Switch>(toggle(3)).onChanged, isNull);
      await tester.ensureVisible(actions(6));
      expect(tester.widget<Switch>(toggle(6)).onChanged, isNull);
      expect(fixture.preferences.bottomNavVisible.length, 5);

      await tester.ensureVisible(actions(2));
      await tester.tap(toggle(2));
      await tester.pumpAndSettle();
      expect(fixture.preferences.bottomNavVisible.contains(2), isFalse);
      await tester.ensureVisible(actions(3));
      await tester.tap(toggle(3));
      await tester.pumpAndSettle();
      expect(fixture.preferences.bottomNavVisible.contains(3), isTrue);
      expect(fixture.preferences.bottomNavVisible.length, 5);

      final moveUp = find.descendant(
        of: actions(3),
        matching: find.byTooltip(I18n.tr('action.move_up')),
      );
      await tester.tap(moveUp);
      await tester.pumpAndSettle();
      expect(fixture.preferences.bottomNavOrder.indexOf(3), 2);
      expect(fixture.preferences.bottomNavVisible.contains(6), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('settings categories open their corresponding routes', (
    tester,
  ) async {
    await _pump(tester, _Page.preferences, locale: AppLocale.en);
    await tester.tap(find.text(SettingsUiCopy.displayAndBehaviorTitle));
    await tester.pumpAndSettle();
    expect(find.byType(PersonalizationSettingsScreen), findsOneWidget);
    expect(find.text(SettingsUiCopy.jumpToDate), findsOneWidget);
    expect(find.text(SettingsUiCopy.jumpToDefaults), findsOneWidget);
    expect(find.text(SettingsUiCopy.jumpToInteraction), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text(SettingsUiCopy.navigationSectionTitle));
    await tester.pumpAndSettle();
    expect(find.byType(BottomNavSettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('PIN setup can cancel, retry and disable with verification', (
    tester,
  ) async {
    final fixture = await _pump(tester, _Page.lock, pinEnabled: false);
    Future<void> toggle() async {
      await tester.ensureVisible(find.byType(Switch).first);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
    }

    Future<void> enter(String value) async {
      await tester.enterText(find.byType(TextField).last, value);
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.confirm')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await toggle();
    await tester.enterText(find.byType(TextField).last, '2468');
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    _expectEnglish(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      '2468',
    );
    await tester.tap(find.widgetWithText(TextButton, I18n.tr('action.cancel')));
    await tester.pumpAndSettle();
    expect(fixture.lock.enabled, isFalse);
    expect(tester.takeException(), isNull);

    await toggle();
    await enter('2468');
    await enter('2468');
    expect(fixture.lock.enabled, isTrue);
    await toggle();
    await enter('1357');
    expect(fixture.lock.enabled, isTrue);
    await toggle();
    await enter('2468');
    expect(fixture.lock.enabled, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('lock timeout picker changes language without changing value', (
    tester,
  ) async {
    final fixture = await _pump(tester, _Page.lock);
    final title = find.text(I18n.tr('app_lock.auto_lock'));
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pumpAndSettle();
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    _expectEnglish(tester);
    final hour = find.descendant(
      of: find.byType(AppModalSheet),
      matching: find.text(SettingsUiCopy.autoLockOptionLabel(60)),
    );
    await tester.ensureVisible(hour);
    await tester.tap(hour);
    await tester.pumpAndSettle();
    expect(fixture.lock.autoLockMinutes, 60);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('picker ignores a result after its origin is removed', (
    tester,
  ) async {
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) => visible
                ? SettingsPickerTile<int>(
                    icon: Icons.tune,
                    color: Colors.blue,
                    titleBuilder: () => 'Select',
                    pickerTitleBuilder: () => 'Options',
                    currentValue: 1,
                    displayLabelBuilder: () => 'One',
                    optionsBuilder: () => const [
                      SettingsPickerOption(value: 2, title: 'Two'),
                    ],
                    onSelected: (_) => selected = true,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    show.value = false;
    await tester.pump();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(selected, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Fixture {
  final PreferencesProvider preferences;
  final AppLockProvider lock;
  final GlobalKey key;
  _Fixture(this.preferences, this.lock, this.key);
}

Future<_Fixture> _pump(
  WidgetTester tester,
  _Page page, {
  AppLocale locale = AppLocale.zh,
  bool dark = false,
  bool pinEnabled = true,
  SharedPreferencesStorePlatform? preferencesStore,
}) async {
  SharedPreferences.setMockInitialValues({
    'active_brand': dark ? 'starRail' : 'defaultBrand',
  });
  if (preferencesStore != null) {
    SharedPreferencesStorePlatform.instance = preferencesStore;
  }
  I18n.setLocale(locale);
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final themeProvider = ThemeProvider();
  await themeProvider.loadFromStorage();
  final preferences = PreferencesProvider();
  await preferences.loadFromStorage();
  final lock = AppLockProvider();
  if (pinEnabled) await lock.setPin('2468');
  addTearDown(themeProvider.dispose);
  addTearDown(preferences.dispose);
  addTearDown(lock.dispose);
  final key = GlobalKey();
  final theme = themeProvider.brand.theme;
  final fonts = theme.textTheme.apply(
    fontFamily: 'DuoyiScreenshotLatin',
    fontFamilyFallback: const ['DuoyiScreenshot'],
  );
  final screen = switch (page) {
    _Page.preferences => const PreferencesScreen(),
    _Page.display => const PersonalizationSettingsScreen(),
    _Page.navigation => const BottomNavSettingsScreen(),
    _Page.lock => const LockSettingsScreen(),
  };
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: preferences),
        ChangeNotifierProvider.value(value: lock),
      ],
      child: MaterialApp(
        theme: theme.copyWith(textTheme: fonts, primaryTextTheme: fonts),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: RepaintBoundary(key: key, child: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return _Fixture(preferences, lock, key);
}

Future<void> _scrollAudit(WidgetTester tester, AppLocale locale) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 20; i++) {
    if (locale == AppLocale.en) _expectEnglish(tester);
    final state = tester.state<ScrollableState>(list);
    if (state.position.extentAfter < 1) break;
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
}

void _expectEnglish(WidgetTester tester) {
  final chinese = RegExp(r'[\u3400-\u9fff]');
  final values = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '');
  expect(
    values.where(
      (value) =>
          chinese.hasMatch(value) &&
          !value.contains('yyyy年M月d日') &&
          !value.contains('2026年5月7日'),
    ),
    isEmpty,
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['DUOYI_CAPTURE_SETTINGS_SCREENSHOTS'] != '1') return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(
      '${Platform.environment['DUOYI_SETTINGS_SCREENSHOT_DIR'] ?? 'evidence/screenshots/settings-locale-20261006'}/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

class _SliderPreferencesStore extends InMemorySharedPreferencesStore {
  _SliderPreferencesStore() : super.withData({});

  bool rejectNext = false;
  final writes = <int>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.pref_default_pomodoro_minutes') {
      writes.add(value as int);
      if (rejectNext) {
        rejectNext = false;
        return false;
      }
    }
    return super.setValue(valueType, key, value);
  }
}
