// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
// BEGIN NEW2298 imports
import 'dart:convert';
import 'package:crypto/crypto.dart';
// END NEW2298 imports
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/settings_ui_copy.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/lock_settings_screen.dart';
import 'package:duoyi/screens/preferences_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/brand_background.dart';
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

  for (final brand in [AppBrands.defaultBrand, AppBrands.liquidGlass]) {
    for (final locale in AppLocale.values) {
      for (final page in _Page.values) {
        final name = '${brand.id}-${locale.name}-${page.name}';
        testWidgets('priority paired settings routes and modals: $name', (
          tester,
        ) async {
          final previousShadows = debugDisableShadows;
          debugDisableShadows = false;
          try {
            final fixture = await _pump(
              tester,
              page,
              locale: locale,
              brandId: brand.id,
              captureOverlays: true,
              pushRoute: true,
            );
            expect(find.byType(BackButton), findsOneWidget);
            await _capture(tester, fixture.key, '$name-top');
            await _scrollAudit(tester, locale);
            expect(
              tester
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position
                  .extentAfter,
              lessThan(1),
            );
            await _capture(tester, fixture.key, '$name-bottom');
            // BEGIN NEW2298 paired English display hook
            if (locale == AppLocale.en && page == _Page.display) {
              await _captureCompleteFocus2298(tester, fixture, name);
            }
            // END NEW2298 paired English display hook

            if (page == _Page.display) {
              final pageElement = tester.element(
                find.byType(PersonalizationSettingsScreen),
              );
              final before = fixture.preferences.firstDayOfWeek;
              final title = find.text(I18n.tr('preferences.first_day.title'));
              await tester.ensureVisible(title);
              await tester.pumpAndSettle();
              await tester.tap(title);
              await tester.pumpAndSettle();
              expect(find.byType(AppModalSheet), findsOneWidget);
              await _capture(tester, fixture.key, '$name-picker');
              final sheet = tester.element(find.byType(AppModalSheet));
              I18n.setLocale(
                locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
              );
              await tester.pumpAndSettle();
              expect(tester.element(find.byType(AppModalSheet)), same(sheet));
              expect(
                tester.element(find.byType(PersonalizationSettingsScreen)),
                same(pageElement),
              );
              expect(find.text(SettingsUiCopy.selectFirstDay), findsOneWidget);
              if (I18n.current == AppLocale.en) _expectEnglish(tester);
              await _capture(tester, fixture.key, '$name-picker-switched');
              await tester.tapAt(const Offset(8, 8));
              await tester.pumpAndSettle();
              expect(find.byType(AppModalSheet), findsNothing);
              expect(fixture.preferences.firstDayOfWeek, before);
              if (locale == AppLocale.en) {
                I18n.setLocale(AppLocale.en);
                await tester.pumpAndSettle();
                final beforeZone = fixture.preferences.appTimeZoneSelection;
                final zone = find.text(I18n.tr('preferences.timezone.title'));
                await tester.ensureVisible(zone);
                await tester.pumpAndSettle();
                await tester.tap(zone);
                await tester.pumpAndSettle();
                expect(find.byType(AppModalSheet), findsOneWidget);
                _expectEnglish(tester);
                await _capture(tester, fixture.key, '$name-timezone-picker');
                await tester.tapAt(const Offset(8, 8));
                await tester.pumpAndSettle();
                expect(find.byType(AppModalSheet), findsNothing);
                expect(fixture.preferences.appTimeZoneSelection, beforeZone);
              }
            }

            if (page == _Page.lock) {
              final pageElement = tester.element(
                find.byType(LockSettingsScreen),
              );
              final change = find.text(I18n.tr('app_lock.change_pin'));
              await tester.ensureVisible(change);
              await tester.pumpAndSettle();
              await tester.tap(change);
              await tester.pumpAndSettle();
              expect(find.byType(AppDialog), findsOneWidget);
              await tester.enterText(find.byType(TextField), '1357');
              await tester.pumpAndSettle();
              await _capture(tester, fixture.key, '$name-pin');
              final dialog = tester.element(find.byType(AppDialog));
              I18n.setLocale(
                locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
              );
              await tester.pumpAndSettle();
              expect(tester.element(find.byType(AppDialog)), same(dialog));
              expect(
                tester.element(find.byType(LockSettingsScreen)),
                same(pageElement),
              );
              expect(
                tester
                    .widget<TextField>(find.byType(TextField))
                    .controller!
                    .text,
                '1357',
              );
              if (I18n.current == AppLocale.en) _expectEnglish(tester);
              await _capture(tester, fixture.key, '$name-pin-switched');
              tester.view.viewInsets = const FakeViewPadding(bottom: 300);
              await tester.pumpAndSettle();
              await _capture(tester, fixture.key, '$name-pin-inset');
              final cancel = find.widgetWithText(
                TextButton,
                I18n.tr('action.cancel'),
              );
              expect(cancel.hitTestable(), findsOneWidget);
              expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(544));
              await tester.tap(cancel);
              await tester.pumpAndSettle();
              expect(find.byType(AppDialog), findsNothing);
              expect(fixture.lock.enabled, isTrue);
              expect(await fixture.lock.verify('2468'), isTrue);
              expect(await fixture.lock.verify('1357'), isFalse);
              tester.view.resetViewInsets();
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            debugDisableShadows = previousShadows;
          }
        });
      }
    }
  }

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
    final increase = find.byTooltip(
      SettingsUiCopy.increaseSetting(
        I18n.tr('preferences.pomodoro_length.title'),
      ),
    );
    await tester.ensureVisible(increase);
    await tester.pumpAndSettle();
    await tester.tap(increase);
    await tester.pumpAndSettle();
    expect(fixture.preferences.defaultPomodoroMinutes, 50);
    expect(store.writes, [45, 50]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final locale in AppLocale.values) {
    testWidgets(
      'slider semantics keep units and native actions: ${locale.name}',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          final fixture = await _pump(tester, _Page.display, locale: locale);
          final focus = find.byWidgetPredicate(
            (widget) => widget is Slider && widget.min == 5,
          );
          final archive = find.byWidgetPredicate(
            (widget) => widget is Slider && widget.min == 0,
          );
          String minutes(int value) => '$value ${I18n.tr('unit.min')}';
          String days(int value) => switch (I18n.current) {
            AppLocale.zh => '$value 天',
            AppLocale.en => value == 1 ? '1 day' : '$value days',
          };
          Future<SemanticsData> data(Finder finder) async {
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
            return tester.getSemantics(finder).getSemanticsData();
          }

          Future<void> adjust(Finder finder, ui.SemanticsAction action) async {
            await data(finder);
            final node = tester.getSemantics(finder);
            node.owner!.performAction(node.id, action);
            await tester.pumpAndSettle();
          }

          final initial = await data(focus);
          expect(
            initial.label,
            contains(I18n.tr('preferences.pomodoro_length.title')),
          );
          expect(initial.label, contains(minutes(25)));
          expect(initial.value, minutes(25));
          expect(initial.increasedValue, minutes(30));
          expect(initial.decreasedValue, minutes(20));
          expect(initial.hasAction(ui.SemanticsAction.increase), isTrue);
          expect(initial.hasAction(ui.SemanticsAction.decrease), isTrue);
          final sliderMerge = find.ancestor(
            of: focus,
            matching: find.byType(MergeSemantics),
          );
          expect(sliderMerge, findsOneWidget);
          expect(
            find.descendant(of: sliderMerge, matching: find.byType(Slider)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: sliderMerge, matching: find.byType(IconButton)),
            findsNothing,
          );
          await _capture(tester, fixture.key, 'slider-focus-${locale.name}');
          // BEGIN NEW2298 native English focus hook
          if (locale == AppLocale.en) {
            await _captureCompleteFocus2298(tester, fixture, 'slider-semantics-en');
          }
          // END NEW2298 native English focus hook
          await adjust(focus, ui.SemanticsAction.increase);
          expect(fixture.preferences.defaultPomodoroMinutes, 30);
          expect((await data(focus)).value, minutes(30));
          await adjust(focus, ui.SemanticsAction.decrease);
          expect(fixture.preferences.defaultPomodoroMinutes, 25);
          for (final tooltip in [
            SettingsUiCopy.increaseSetting(
              I18n.tr('preferences.pomodoro_length.title'),
            ),
            SettingsUiCopy.decreaseSetting(
              I18n.tr('preferences.pomodoro_length.title'),
            ),
          ]) {
            final button = find.byTooltip(tooltip);
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
            expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
            final semantics = tester.getSemantics(button).getSemanticsData();
            expect(semantics.tooltip, tooltip);
            expect(semantics.hasAction(ui.SemanticsAction.tap), isTrue);
            expect(
              tester.getSemantics(button).rect.height,
              greaterThanOrEqualTo(44),
            );
          }
          final off = await data(archive);
          expect(
            off.label,
            contains(I18n.tr('preferences.auto_archive.title')),
          );
          expect(off.value, I18n.tr('action.off'));
          expect(off.increasedValue, days(1));
          await adjust(archive, ui.SemanticsAction.increase);
          expect(fixture.preferences.autoArchiveCompletedDays, 1);
          expect((await data(archive)).value, days(1));
          await _capture(tester, fixture.key, 'slider-archive-${locale.name}');

          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          final translated = await data(archive);
          expect(
            translated.label,
            contains(I18n.tr('preferences.auto_archive.title')),
          );
          expect(translated.value, days(1));
          expect(fixture.preferences.autoArchiveCompletedDays, 1);
          expect(
            find.byTooltip(
              SettingsUiCopy.increaseSetting(
                I18n.tr('preferences.auto_archive.title'),
              ),
            ),
            findsOneWidget,
          );
          expect((await data(focus)).value, minutes(25));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          handle.dispose();
        }
      },
    );
  }

  testWidgets(
    'rejected native slider action restores spoken value and retries',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        final store = _SliderPreferencesStore()..rejectNext = true;
        final fixture = await _pump(
          tester,
          _Page.display,
          preferencesStore: store,
        );
        final slider = find.byWidgetPredicate(
          (widget) => widget is Slider && widget.min == 5,
        );
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        Future<void> increase() async {
          final node = tester.getSemantics(slider);
          node.owner!.performAction(node.id, ui.SemanticsAction.increase);
          await tester.pumpAndSettle();
        }

        await increase();
        expect(fixture.preferences.defaultPomodoroMinutes, 25);
        expect(tester.getSemantics(slider).getSemanticsData().value, '25 分');
        expect(find.text(SettingsUiCopy.saveFailed), findsOneWidget);
        await increase();
        expect(fixture.preferences.defaultPomodoroMinutes, 30);
        expect(tester.getSemantics(slider).getSemanticsData().value, '30 分');
        expect(store.writes, [30, 30]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        handle.dispose();
      }
    },
  );

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
        matching: find.byTooltip(
          SettingsUiCopy.navigationMoveUp(I18n.tr('nav.calendar')),
        ),
      );
      await tester.tap(moveUp);
      await tester.pumpAndSettle();
      expect(fixture.preferences.bottomNavOrder.indexOf(3), 2);
      expect(fixture.preferences.bottomNavVisible.contains(6), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final locale in AppLocale.values) {
    testWidgets(
      'navigation feedback and independent semantics: ${locale.name}',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final fixture = await _pump(tester, _Page.navigation, locale: locale);
          Finder actions(int tab) =>
              find.byKey(ValueKey('bottom_nav_actions_$tab'));
          Finder toggle(int tab) =>
              find.descendant(of: actions(tab), matching: find.byType(Switch));

          Future<SemanticsData> switchData(int tab) async {
            await tester.ensureVisible(actions(tab));
            await tester.pumpAndSettle();
            return tester.getSemantics(toggle(tab)).getSemanticsData();
          }

          final blocked = await switchData(3);
          expect(blocked.label, I18n.tr('nav.calendar'));
          expect(blocked.flagsCollection.isToggled.toBoolOrNull(), isFalse);
          expect(blocked.flagsCollection.isEnabled.toBoolOrNull(), isFalse);
          expect(blocked.hasAction(ui.SemanticsAction.tap), isFalse);
          expect(blocked.hint, SettingsUiCopy.navigationHiddenAtLimit);
          expect(
            find.text(SettingsUiCopy.navigationHiddenAtLimit),
            findsWidgets,
          );
          final up = find.descendant(
            of: actions(3),
            matching: find.byTooltip(
              SettingsUiCopy.navigationMoveUp(I18n.tr('nav.calendar')),
            ),
          );
          final down = find.descendant(
            of: actions(3),
            matching: find.byTooltip(
              SettingsUiCopy.navigationMoveDown(I18n.tr('nav.calendar')),
            ),
          );
          expect(up, findsOneWidget);
          expect(down, findsOneWidget);
          for (final button in [up, down]) {
            expect(tester.getSize(button), const Size(44, 44));
            expect(
              tester
                  .getSemantics(button)
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isTrue,
            );
          }
          await tester.ensureVisible(find.text(I18n.tr('nav.calendar')));
          await tester.pumpAndSettle();
          await _capture(
            tester,
            fixture.key,
            'navigation-feedback-${locale.name}-full',
          );

          final oldLocale = locale;
          final orderBeforeLocale = List<int>.of(
            fixture.preferences.bottomNavOrder,
          );
          final visibleBeforeLocale = Set<int>.of(
            fixture.preferences.bottomNavVisible,
          );
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          final translated = await switchData(3);
          expect(translated.label, I18n.tr('nav.calendar'));
          expect(translated.label, isNot(blocked.label));
          expect(translated.hint, SettingsUiCopy.navigationHiddenAtLimit);
          expect(translated.hint, isNot(blocked.hint));
          expect(
            find.descendant(
              of: actions(3),
              matching: find.byTooltip(
                SettingsUiCopy.navigationMoveUp(I18n.tr('nav.calendar')),
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: actions(3),
              matching: find.byTooltip(
                SettingsUiCopy.navigationMoveDown(I18n.tr('nav.calendar')),
              ),
            ),
            findsOneWidget,
          );
          expect(find.text(I18n.tr('nav.calendar')), findsOneWidget);
          expect(
            fixture.preferences.bottomNavOrder,
            orderedEquals(orderBeforeLocale),
          );
          expect(fixture.preferences.bottomNavVisible, visibleBeforeLocale);
          I18n.setLocale(oldLocale);
          await tester.pumpAndSettle();

          await switchData(2);
          await tester.tap(toggle(2));
          await tester.pumpAndSettle();
          final available = await switchData(3);
          expect(available.label, I18n.tr('nav.calendar'));
          expect(available.flagsCollection.isEnabled.toBoolOrNull(), isTrue);
          expect(available.hasAction(ui.SemanticsAction.tap), isTrue);
          expect(available.hint, isEmpty);
          expect(
            find.text(SettingsUiCopy.navigationHiddenAtLimit),
            findsNothing,
          );
          expect(find.text(I18n.tr('preferences.nav.hidden')), findsWidgets);
          await tester.ensureVisible(find.text(I18n.tr('nav.calendar')));
          await tester.pumpAndSettle();
          await _capture(
            tester,
            fixture.key,
            'navigation-feedback-${locale.name}-available',
          );

          await tester.tap(toggle(3));
          await tester.pumpAndSettle();
          final enabled = await switchData(3);
          expect(enabled.flagsCollection.isToggled.toBoolOrNull(), isTrue);
          expect(fixture.preferences.bottomNavVisible, contains(3));
          expect(fixture.preferences.bottomNavVisible.length, 5);

          final pinned = await switchData(6);
          expect(pinned.label, I18n.tr('nav.mine'));
          expect(pinned.flagsCollection.isToggled.toBoolOrNull(), isTrue);
          expect(pinned.flagsCollection.isEnabled.toBoolOrNull(), isFalse);
          expect(pinned.hasAction(ui.SemanticsAction.tap), isFalse);
          expect(pinned.hint, I18n.tr('preferences.nav.fixed'));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semanticsHandle.dispose();
        }
      },
    );
  }

  testWidgets('settings categories open their corresponding routes', (
    tester,
  ) async {
    await _pump(tester, _Page.preferences, locale: AppLocale.en);
    await tester.tap(find.text(SettingsUiCopy.displayAndBehaviorTitle));
    await tester.pumpAndSettle();
    expect(find.byType(PersonalizationSettingsScreen), findsOneWidget);
    for (final label in [
      SettingsUiCopy.jumpToDate,
      SettingsUiCopy.jumpToDefaults,
      SettingsUiCopy.jumpToInteraction,
    ]) {
      final chip = find.widgetWithText(ActionChip, label);
      expect(chip, findsOneWidget);
      expect(tester.getSize(chip).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
    }
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
  String? brandId,
  bool captureOverlays = false,
  bool pushRoute = false,
  bool pinEnabled = true,
  SharedPreferencesStorePlatform? preferencesStore,
}) async {
  SharedPreferences.setMockInitialValues({
    'active_brand': brandId ?? (dark ? 'starRail' : 'defaultBrand'),
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
  if (brandId != null) expect(themeProvider.brand.id, brandId);
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
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(textTheme: fonts, primaryTextTheme: fonts),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: captureOverlays
              ? RepaintBoundary(key: key, child: child!)
              : child!,
        ),
        home: pushRoute
            ? const Scaffold(body: SizedBox.shrink())
            : captureOverlays
            ? screen
            : RepaintBoundary(key: key, child: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (pushRoute) {
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    if (page == _Page.display || page == _Page.navigation) {
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const BrandRouteSurface(child: PreferencesScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => page == _Page.preferences || page == _Page.lock
              ? BrandRouteSurface(child: screen)
              : screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
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

// BEGIN NEW2298 common evidence helpers
// Opt-in evidence is separate from the original capture writers. PNG+JSON
// precede added assertions. Visual review and parent guard closure stay external.
bool get _visualEndpointsEnabled =>
    Platform.environment['DUOYI_CAPTURE_VISUAL_ENDPOINTS'] == '1';

String _endpointId(Object? value) =>
    value == null ? 'null' : identityHashCode(value).toString();

Map<String, Object?> _endpointRect(Rect rect) => {
  'left': rect.left, 'top': rect.top, 'right': rect.right,
  'bottom': rect.bottom, 'width': rect.width, 'height': rect.height,
};
Rect _endpointBox(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;
bool _endpointContains(Rect outer, Rect inner) =>
    inner.width > 0 && inner.height > 0 &&
    inner.left >= outer.left - .1 && inner.right <= outer.right + .1 &&
    inner.top >= outer.top - .1 && inner.bottom <= outer.bottom + .1;

Map<String, Object?> _endpointScroll(ScrollableState state) => {
  'state': _endpointId(state), 'element': _endpointId(state.context),
  'position': _endpointId(state.position),
  'widgetController': _endpointId(state.widget.controller),
  'ambientPrimaryController': _endpointId(PrimaryScrollController.maybeOf(state.context)),
  'controllerBinding': state.widget.controller != null
      ? 'explicit Scrollable.widget.controller'
      : 'no explicit controller; bind public ScrollableState/ScrollPosition identities',
  'axisDirection': state.position.axisDirection.name,
  'pixels': state.position.pixels,
  'minScrollExtent': state.position.minScrollExtent,
  'maxScrollExtent': state.position.maxScrollExtent,
  'extentBefore': state.position.extentBefore,
  'extentAfter': state.position.extentAfter,
  'viewportDimension': state.position.viewportDimension,
};
Map<String, Object?> _endpointStableState(Map<String, Object?> state) {
  final result = Map<String, Object?>.from(state);
  for (final key in ['scroll', 'vertical', 'horizontal']) {
    final scroll = result[key];
    if (scroll is Map<String, Object?>) {
      result[key] = Map<String, Object?>.from(scroll)
        ..remove('pixels')..remove('extentBefore')..remove('extentAfter');
    }
  }
  return result;
}

Rect _endpointBodyViewport(WidgetTester tester, Finder screen, RenderObject child) {
  final viewport = RenderAbstractViewport.maybeOf(child);
  if (viewport is! RenderBox) throw StateError('Expected a box scroll viewport');
  var rect = _endpointBox(viewport as RenderBox).intersect(tester.getRect(screen));
  final bars = find.descendant(of: screen, matching: find.byType(AppBar));
  if (bars.evaluate().length != 1) throw StateError('Active AppBar is ambiguous');
  final bottom = tester.getRect(bars).bottom;
  return Rect.fromLTRB(rect.left, rect.top > bottom ? rect.top : bottom,
      rect.right, rect.bottom);
}

Map<String, Object?> _endpointParagraph(WidgetTester tester, Finder text) {
  final rich = find.descendant(of: text, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(rich);
  final style = paragraph.text.style;
  final fontSize = style?.fontSize ?? DefaultTextStyle.of(tester.element(text)).style.fontSize;
  final painter = TextPainter(
    text: paragraph.text, textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.size.width);
  try {
    return {
      'element': _endpointId(tester.element(text)),
      'renderObject': _endpointId(paragraph),
      'text': paragraph.text.toPlainText(),
      'rect': _endpointRect(_endpointBox(paragraph)),
      'fontFamily': style?.fontFamily,
      'fontFamilyFallback': style?.fontFamilyFallback,
      'fontWeight': style?.fontWeight?.value, 'fontStyle': style?.fontStyle?.name,
      'letterSpacing': style?.letterSpacing, 'lineHeight': style?.height,
      'textDirection': paragraph.textDirection.name,
      'fontSize': fontSize,
      'scaledFontSize': fontSize == null ? null : paragraph.textScaler.scale(fontSize),
      'scalerType': paragraph.textScaler.runtimeType.toString(),
      'maxLines': paragraph.maxLines, 'overflow': paragraph.overflow.name,
      'didExceedMaxLines': paragraph.didExceedMaxLines,
      'naturalWidth': painter.width, 'naturalHeight': painter.height,
      'complete': !paragraph.didExceedMaxLines &&
          paragraph.overflow != TextOverflow.ellipsis &&
          painter.width <= paragraph.size.width + .1 &&
          painter.height <= paragraph.size.height + .1,
    };
  } finally { painter.dispose(); }
}

Map<String, Object?> _endpointView(WidgetTester tester, BuildContext context) {
  final media = MediaQuery.of(context);
  final route = ModalRoute.of(context);
  return {
    'view': _endpointId(tester.view),
    'physicalWidth': tester.view.physicalSize.width,
    'physicalHeight': tester.view.physicalSize.height,
    'devicePixelRatio': tester.view.devicePixelRatio,
    'mediaWidth': media.size.width, 'mediaHeight': media.size.height,
    'padding': media.padding.toString(), 'viewInsets': media.viewInsets.toString(),
    'scalerType': media.textScaler.runtimeType.toString(),
    'scaledSamples': {for (final size in [11.0, 12.0, 14.0, 16.0])
      size.toString(): media.textScaler.scale(size)},
    'locale': I18n.current.name,
    'route': _endpointId(route), 'routeType': route.runtimeType.toString(),
    'routeCurrent': route?.isCurrent,
    'navigator': _endpointId(Navigator.of(context)),
    'screenElement': _endpointId(context),
    'themeProvider': _endpointId(context.read<ThemeProvider>()),
    'brand': context.read<ThemeProvider>().brand.id,
  };
}

List<Map<String, Object?>> _endpointInputs() {
  const latinHash = '690243adfefe0ce154b547db6205794bd30ac4277275179517a90994f4980648';
  const cjkHash = 'acb6440a713d880a13a21b468ba7cd43f5a2b2934972e51be791c880730777b8';
  final paths = <String, String?>{
    'test/screens/settings_locale_layout_test.dart': null,
    'test/screens/integrations_caldav_card_fit_test.dart': null,
    'lib/screens/preferences_screen.dart': '86a88c61ca9ca443c23f481b55bab24ff504bca9545639d0ecd549bf172e7213',
    'lib/screens/integrations_screen.dart': 'b816eba128425a50dec4d024afeb8a8f478b907d3403af3c7ca60be38faca09f',
    'test/support/widget_polish_screenshot_font.dart': 'db0e33e767d0cf88d6fb8f5eeb6391a88bed09ca2d630c913cf0a307a8c8d5ef',
    'test/support/weekly_review_screenshot_font.dart': '6300137dd8bd749f970d34430f3e2f8ae539d4ec2229040257c18c507cd9d1c0',
    'assets/fonts/DroidSansFallbackFull.ttf': cjkHash,
    'assets/fonts/DejaVuSans.ttf': latinHash,
    Platform.environment['DUOYI_WIDGET_SCREENSHOT_LATIN_FONT'] ??
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf': latinHash,
    'build/unit_test_assets/fonts/MaterialIcons-Regular.otf': 'd9865b671a09d683d13a863089d8825e0f61a37696ce5d7d448bc8023aa62453',
  };
  return [for (final entry in paths.entries) (() {
    final row = <String, Object?>{'requestedPath': entry.key, 'expectedSha256': entry.value};
    try {
      final file = File(entry.key);
      final before = file.statSync();
      final bytes = file.readAsBytesSync();
      final after = file.statSync();
      row.addAll({
        'resolvedPath': file.resolveSymbolicLinksSync(),
        'bytes': bytes.length.toString(), 'sha256': sha256.convert(bytes).toString(),
        'modifiedMicroseconds': after.modified.microsecondsSinceEpoch.toString(),
        'changedMicroseconds': after.changed.microsecondsSinceEpoch.toString(),
        'mode': after.mode.toString(),
        'stableRead': before.size == after.size && before.modified == after.modified &&
            before.changed == after.changed && before.mode == after.mode,
      });
    } catch (error) { row['error'] = error.toString(); }
    return row;
  })()];
}

// Preserve IO failures outside runAsync, whose binding otherwise reports them
// asynchronously and returns null. Each caller can retain diagnostic evidence.
Future<T> _endpointIO<T>(WidgetTester tester, Future<T> Function() operation) async {
  Object? failure;
  StackTrace? failureStack;
  final result = await tester.runAsync<T?>(() async {
    try { return await operation(); }
    catch (error, stack) { failure = error; failureStack = stack; return null; }
  });
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  if (result == null) throw StateError('Endpoint IO returned no result');
  return result;
}

class _EndpointEvidence {
  _EndpointEvidence(this.tester, this.key, this.name, this.metadata)
      : inputsBefore = _endpointInputs(),
        boundaryElementBefore = _endpointId(key.currentContext),
        boundaryRenderBefore = _endpointId(key.currentContext?.findRenderObject());
  final WidgetTester tester;
  final GlobalKey key;
  final String name;
  final Map<String, Object?> metadata;
  final List<Map<String, Object?>> inputsBefore;
  final String boundaryElementBefore;
  final String boundaryRenderBefore;
  final errors = <String>[];
  final checks = <String, bool>{};
  final frames = <Map<String, Object?>>[];
  final sidecars = <File>[];
  final sidecarHashes = <String>[];

  File _output(String phase, String extension) {
    final raw = Platform.environment['DUOYI_VISUAL_ENDPOINT_DIR'];
    const prefix = '/home/ubuntu/duoyi/evidence/screenshots/';
    if (raw == null || !raw.startsWith(prefix) || raw.length <= prefix.length ||
        Uri.directory(raw).normalizePath().toFilePath() != '$raw/') {
      throw StateError('DUOYI_VISUAL_ENDPOINT_DIR must name an absolute fresh batch under $prefix (no trailing slash)');
    }
    var ancestor = Directory(raw);
    while (ancestor.path != ancestor.parent.path) {
      if (FileSystemEntity.typeSync(ancestor.path, followLinks: false) == FileSystemEntityType.link) {
        throw StateError('Refusing a symlink output ancestor: ${ancestor.path}');
      }
      ancestor = ancestor.parent;
    }
    return File('$raw/$name-$phase.$extension');
  }

  Future<void> capture(String phase, Map<String, Object?> observed) async {
    final frame = <String, Object?>{'phase': phase, ...observed};
    final png = _output(phase, 'png');
    final json = _output(phase, 'json');
    for (final file in [png, json]) {
      if (FileSystemEntity.typeSync(file.path, followLinks: false) != FileSystemEntityType.notFound) {
        throw StateError('Refusing to overwrite endpoint evidence: ${file.path}');
      }
    }
    await _endpointIO(tester, () async {
      final stageBefore = _endpointInputs();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      checks['$phase-boundaryStable'] = _endpointId(key.currentContext) == boundaryElementBefore &&
          _endpointId(boundary) == boundaryRenderBefore;
      final picture = await boundary.toImage(pixelRatio: 1);
      try {
        final data = await picture.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('PNG encoding returned no bytes');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await png.parent.create(recursive: true);
        await png.writeAsBytes(bytes, flush: true);
        final stageAfter = _endpointInputs();
        checks['$phase-inputsStableDuringCapture'] = jsonEncode(stageBefore) == jsonEncode(stageAfter) &&
            jsonEncode(stageBefore) == jsonEncode(inputsBefore);
        frame.addAll({
          'inputsAtCaptureBefore': stageBefore, 'inputsAtCaptureAfter': stageAfter,
          'pngPath': png.path, 'pngSha256': sha256.convert(bytes).toString(),
          'pngBytes': bytes.length.toString(), 'pngWidth': picture.width,
          'pngHeight': picture.height, 'capturePixelRatio': 1,
          'boundaryElement': _endpointId(key.currentContext),
          'boundaryRenderObject': _endpointId(boundary),
          'capturedUtc': DateTime.now().toUtc().toIso8601String(),
        });
        frames.add(frame);
        sidecars.add(json);
        final encoded = _encode(frame, false);
        await json.writeAsString(encoded, flush: true);
        sidecarHashes.add(sha256.convert(utf8.encode(encoded)).toString());
      } finally { picture.dispose(); }
      return true;
    });
  }

  String _encode(Map<String, Object?> frame, bool assertionsPassed) => jsonEncode({
    'schema': 'visual-endpoints-2298-v1', 'case': name, 'accepted': false,
    'supplementalAssertionsPassed': assertionsPassed,
    'originalBodyComplete': 'pending; original test result and parent closure required',
    'boundaryElementBefore': boundaryElementBefore,
    'boundaryRenderBefore': boundaryRenderBefore,
    'acceptanceBoundary': 'visual review and parent guard/PID/input closure required',
    ...metadata, 'inputsBefore': inputsBefore, 'frame': frame,
    'errors': errors, 'checks': checks,
  });

  Future<void> _update(bool passed) async {
    await _endpointIO(tester, () async {
      for (var i = 0; i < sidecars.length; i++) {
        final file = sidecars[i];
        if (FileSystemEntity.typeSync(file.path, followLinks: false) != FileSystemEntityType.file ||
            sha256.convert(await file.readAsBytes()).toString() != sidecarHashes[i]) {
          throw StateError('Owned sidecar changed; refusing finalization: ${file.path}');
        }
        final encoded = _encode(frames[i], passed);
        await file.writeAsString(encoded, flush: true);
        sidecarHashes[i] = sha256.convert(utf8.encode(encoded)).toString();
      }
      return true;
    });
  }

  Future<void> finish(int expectedFrames) async {
    final after = await _endpointIO(tester, () async => _endpointInputs());
    metadata['inputsAfter'] = after;
    checks['inputsStable'] = jsonEncode(inputsBefore) == jsonEncode(after);
    checks['inputsReadableAndBound'] = inputsBefore.every((row) =>
        row['error'] == null && row['stableRead'] == true &&
        (row['expectedSha256'] == null || row['expectedSha256'] == row['sha256']));
    checks['frameCount'] = frames.length == expectedFrames;
    checks['boundaryStableAfterRestore'] = _endpointId(key.currentContext) == boundaryElementBefore &&
        _endpointId(key.currentContext?.findRenderObject()) == boundaryRenderBefore;
    await _update(false);
    // All added expectations follow PNG+JSON collection and restoration.
    expect(errors, isEmpty, reason: 'Endpoint capture diagnostics retained: $name');
    expect(checks.values.every((value) => value), isTrue,
        reason: 'Endpoint observations (ordinary scroll clipping is not a defect): $name $checks');
    await _update(true);
  }
}
// END NEW2298 common evidence helpers

// BEGIN NEW2298 complete focus helper
Future<void> _captureCompleteFocus2298(
  WidgetTester tester, _Fixture fixture, String name,
) async {
  if (!_visualEndpointsEnabled) return;
  final evidence = await _endpointIO(tester, () async => _EndpointEvidence(
    tester, fixture.key, name, {'kind': 'settings', 'supplementalPhase': 'focus-complete-25',
      'testBody': name == 'slider-semantics-en'
          ? 'slider semantics keep units and native actions: en'
          : 'priority paired settings routes and modals: $name',
      'fontRegistration': 'loadWidgetPolishScreenshotFonts (existing engine registration)',
      'widgetLatinPath': Platform.environment['DUOYI_WIDGET_SCREENSHOT_LATIN_FONT'] ??
          '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      'cjkPath': 'assets/fonts/DroidSansFallbackFull.ttf'},
  ));
  ScrollableState? vertical;
  ScrollPosition? savedPosition;
  double? savedPixels;
  RenderBox? item;
  final targets = <String, Finder>{};
  Map<String, Object?>? before;
  final screen = find.byType(PersonalizationSettingsScreen);
  Map<String, Object?> state() {
    final context = tester.element(screen);
    final prefs = context.read<PreferencesProvider>();
    return {..._endpointView(tester, context),
      'preferencesProvider': _endpointId(prefs),
      'lockProvider': _endpointId(context.read<AppLockProvider>()),
      'fixturePreferences': _endpointId(fixture.preferences),
      'fixtureLock': _endpointId(fixture.lock),
      'focusMinutes': prefs.defaultPomodoroMinutes,
      'archiveDays': prefs.autoArchiveCompletedDays,
      'scroll': vertical == null ? null : _endpointScroll(vertical),
      'targetIdentities': {for (final entry in targets.entries) entry.key: {
        'element': _endpointId(tester.element(entry.value)),
        'renderObject': _endpointId(tester.renderObject(entry.value)),
      }},
      'itemRenderObject': _endpointId(item),
    };
  }
  try {
    Finder scoped(Finder finder) => find.descendant(of: screen, matching: finder);
    final title = I18n.tr('preferences.pomodoro_length.title');
    targets.addAll({
      'title': scoped(find.text(title)),
      'subtitle': scoped(find.text('25 ${I18n.tr('unit.minute')} · ${I18n.tr('preferences.pomodoro_length.subtitle')}')),
      'badge': scoped(find.text('25 ${I18n.tr('unit.min')}')),
      'slider': scoped(find.byWidgetPredicate((widget) => widget is Slider && widget.min == 5)),
      'decrease': scoped(find.byWidgetPredicate((widget) => widget is IconButton &&
          widget.tooltip == SettingsUiCopy.decreaseSetting(title))),
      'increase': scoped(find.byWidgetPredicate((widget) => widget is IconButton &&
          widget.tooltip == SettingsUiCopy.increaseSetting(title))),
    });
    final objects = targets.values.map((finder) => tester.renderObject<RenderBox>(finder)).toList();
    bool containsObject(RenderObject ancestor, RenderObject object) {
      RenderObject? cursor = object;
      while (cursor != null) {
        if (identical(cursor, ancestor)) return true;
        cursor = cursor.parent;
      }
      return false;
    }
    RenderObject? cursor = objects.first;
    while (cursor != null) {
      final ancestor = cursor;
      if (ancestor is RenderBox && objects.every((object) => containsObject(ancestor, object))) {
        item = ancestor;
        break;
      }
      cursor = cursor.parent;
    }
    if (item == null) throw StateError('No common public RenderBox for complete focus item');
    vertical = tester.state<ScrollableState>(scoped(find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )));
    savedPosition = vertical.position;
    savedPixels = savedPosition.pixels;
    before = state();
    evidence.metadata['before'] = before;
    final viewport = _endpointBodyViewport(tester, screen, item);
    final delta = _endpointBox(item).top - viewport.top - 8;
    savedPosition.jumpTo((savedPixels + delta)
        .clamp(savedPosition.minScrollExtent, savedPosition.maxScrollExtent).toDouble());
    await tester.pumpAndSettle();
    final visible = _endpointBodyViewport(tester, screen, item);
    final paragraphs = {for (final part in ['title', 'subtitle', 'badge'])
      part: _endpointParagraph(tester, targets[part]!)};
    final rects = {for (final entry in targets.entries) entry.key: tester.getRect(entry.value)};
    final slider = tester.widget<Slider>(targets['slider']!);
    final atCapture = state();
    evidence.checks.addAll({
      'routeProvidersTargetsAndScrollStableAtCapture': jsonEncode(_endpointStableState(before)) == jsonEncode(_endpointStableState(atCapture)),
      'english25': I18n.current == AppLocale.en && fixture.preferences.defaultPomodoroMinutes == 25 && slider.value == 25,
      'viewport320x844dpr1': tester.view.physicalSize == const Size(320, 844) && tester.view.devicePixelRatio == 1,
      'actualScaler1.6': MediaQuery.of(tester.element(screen)).textScaler.scale(16) == 25.6,
      'wholeItemVisible': _endpointContains(visible, _endpointBox(item)),
      'allTargetRectsVisible': rects.values.every((rect) => _endpointContains(visible, rect)),
      'completeTitleSubtitleBadge': paragraphs.values.every((row) => row['complete'] == true),
      'minimum44pxButtons': ['decrease', 'increase'].every((part) =>
          rects[part]!.width >= 44 && rects[part]!.height >= 44),
      'buttonsHitTestable': ['decrease', 'increase'].every((part) => targets[part]!.hitTestable().evaluate().length == 1),
      'sliderHitTestable': targets['slider']!.hitTestable().evaluate().length == 1,
    });
    await evidence.capture('focus-complete-25', {
      'atCapture': atCapture, 'bodyViewport': _endpointRect(visible),
      'itemRect': _endpointRect(_endpointBox(item)),
      'targetRects': {for (final entry in rects.entries) entry.key: _endpointRect(entry.value)},
      'paragraphs': paragraphs, 'sliderValue': slider.value,
    });
  } catch (error) {
    evidence.errors.add(error.toString());
    if (evidence.frames.isEmpty) {
      await evidence.capture('focus-complete-25', {'diagnostic': error.toString()});
    }
  } finally {
    try {
      if (savedPosition != null && savedPixels != null) {
        savedPosition.jumpTo(savedPixels.clamp(
            savedPosition.minScrollExtent, savedPosition.maxScrollExtent).toDouble());
        await tester.pumpAndSettle();
        evidence.checks['originalPositionAndPixelsRestored'] =
            identical(vertical!.position, savedPosition) &&
            (savedPosition.pixels - savedPixels).abs() < .1;
      }
      final after = state();
      evidence.metadata['afterRestore'] = after;
      evidence.checks['routeProvidersTargetsAndScrollStable'] = before != null && jsonEncode(before) == jsonEncode(after);
    } catch (error) { evidence.errors.add('restore: $error'); }
  }
  await evidence.finish(1);
}
// END NEW2298 complete focus helper
