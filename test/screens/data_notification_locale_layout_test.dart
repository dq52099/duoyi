import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/backup_screen.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/screens/notification_history_screen.dart';
import 'package:duoyi/screens/theme_picker_screen.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/services/alarm_service.dart';
import 'package:duoyi/services/local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';
import '../support/weekly_review_screenshot_font.dart';
import '../support/rendered_control_contrast.dart';
import '../support/priority_theme_fixture.dart' show priorityLayouts;
import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler, RouteRenderProbe;

enum _Page {
  backup,
  restore,
  themes,
  integrations,
  history,
  notifications,
  registeredReminders,
}

void main() {
  setUp(() {
    final originalTimezoneReader =
        LocalTimezoneResolver.debugSystemTimeZoneReader;
    FlutterLocalNotificationsPlatform? originalPlugin;
    try {
      originalPlugin = FlutterLocalNotificationsPlatform.instance;
    } on Error {
      originalPlugin = null;
    }
    IOSFlutterLocalNotificationsPlugin.registerWith();
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
        'initialize' => true,
        'pendingNotificationRequests' => <Map<String, Object>>[],
        _ => null,
      },
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      if (originalPlugin != null) {
        FlutterLocalNotificationsPlatform.instance = originalPlugin;
      }
      LocalTimezoneResolver.debugSystemTimeZoneReader = originalTimezoneReader;
    });
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final page in _Page.values) {
        final name = '${page.name}-${locale.name}-${dark ? 'dark' : 'light'}';
        testWidgets('data and notification settings fit 320 / 1.6: $name', (
          tester,
        ) async {
          final key = await _pump(tester, page, locale, dark);
          await _capture(tester, key, name);
          await _auditScroll(tester, locale);
          if (page == _Page.notifications) {
            await _auditReminderSections(tester, key, name, locale);
          }
          if (page == _Page.integrations) {
            for (final index in [1, 2]) {
              final tabs = find.descendant(
                of: find.byType(TabBar),
                matching: find.byType(Tab),
              );
              await tester.ensureVisible(tabs.at(index));
              await tester.tap(tabs.at(index));
              await tester.pumpAndSettle();
              await _capture(tester, key, '$name-tab$index');
              if (locale == AppLocale.en) _expectEnglish(tester);
              expect(tester.takeException(), isNull);
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  for (final page in _Page.values) {
    testWidgets('${page.name} follows locale while mounted', (tester) async {
      await _pump(tester, page, AppLocale.zh, false);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      await _auditScroll(tester, AppLocale.en);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final granted in [false, true]) {
        testWidgets(
          'priority notification controls are readable $brand ${locale.name} granted=$granted',
          (tester) => withControlEvidenceShadows(() async {
            final key = await _pump(
              tester,
              _Page.notifications,
              locale,
              false,
              brandId: brand,
              permissionGranted: granted,
            );
            final permission = find.descendant(
              of: find.byKey(const ValueKey('notification_permission_tile')),
              matching: find.byType(TextButton),
            );
            expect(tester.widget<TextButton>(permission).onPressed, isNotNull);
            expect(
              find.descendant(
                of: permission,
                matching: find.text(
                  granted
                      ? NotificationUiCopy.checkAgainAction
                      : NotificationUiCopy.enableAction,
                ),
              ),
              findsOneWidget,
            );
            expectReadableControl(tester, permission);
            final name = 'notification-$brand-${locale.name}-$granted';
            await captureControlPage(tester, key, '$name-permission');
            final view = find.byKey(
              const ValueKey('notification_registered_reminders_view_button'),
            );
            await _showSettingsItem(tester, view);
            expect(tester.widget<TextButton>(view).onPressed, isNotNull);
            expectReadableControl(tester, view);
            final refresh = find.byKey(
              const ValueKey(
                'notification_registered_reminders_refresh_button',
              ),
            );
            expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
            expectControlTouchTarget(tester, refresh);
            await captureControlPage(tester, key, '$name-registered');
            final historyView = find.byKey(
              const ValueKey('notification_history_entry_view_button'),
            );
            await _showSettingsItem(tester, historyView);
            expect(tester.widget<TextButton>(historyView).onPressed, isNotNull);
            expectReadableControl(tester, historyView);
            await captureControlPage(tester, key, '$name-history');
            await tester.tap(historyView);
            await tester.pumpAndSettle();
            expect(find.byType(NotificationHistoryScreen), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }),
        );
      }
    }
  }

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      testWidgets(
        'reminder selector full labels $brand ${locale.name}',
        (tester) => withControlEvidenceShadows(() async {
          final key = await _pump(
            tester,
            _Page.notifications,
            locale,
            false,
            brandId: brand,
            permissionGranted: true,
          );
          final selector = find.byKey(
            const ValueKey('daily_reminder_kind_selector_row'),
          );
          await _showSettingsItem(tester, selector);
          final buttons = [
            for (final kind in ['push', 'popup', 'alarm', 'off'])
              find.byKey(ValueKey('daily_reminder_kind_$kind')),
          ];
          for (var i = 0; i < buttons.length; i++) {
            final button = buttons[i];
            final kind = ['push', 'popup', 'alarm', 'off'][i];
            expect(
              find.descendant(
                of: button,
                matching: find.text(I18n.tr('reminder.kind.$kind')),
              ),
              findsOneWidget,
            );
            expectReadableControl(tester, button);
            for (final other in buttons.take(i)) {
              expect(
                tester.getRect(button).overlaps(tester.getRect(other)),
                isFalse,
              );
            }
          }
          if (locale == AppLocale.en) {
            // Require the adaptive branch when the full English labels
            // cannot all fit at this width and text scale.
            expect(
              buttons.map((b) => tester.getRect(b).top).toSet().length,
              greaterThan(1),
            );
          }
          await captureControlPage(
            tester,
            key,
            'selector-$brand-${locale.name}',
          );
          // Off avoids native scheduling: assert the live callback persists
          // this exact choice and updates the selected semantics.
          await tester.tap(buttons.last);
          await tester.pumpAndSettle();
          final preferences = Provider.of<PreferencesProvider>(
            tester.element(buttons.last),
            listen: false,
          );
          expect(preferences.dailyReminderSlots.first.kind.name, 'off');
          expect(preferences.dailyReminderSlots.first.enabled, isFalse);
          final handle = tester.ensureSemantics();
          try {
            expect(
              tester
                  .getSemantics(buttons.last)
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected
                  .toBoolOrNull(),
              isTrue,
            );
          } finally {
            handle.dispose();
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }),
      );
    }
  }

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final layout in ['ordinary', 'narrow', 'landscape']) {
      testWidgets('notification hero complete $brand $layout', (tester) async {
        final size = layout == 'ordinary'
            ? const Size(390, 844)
            : layout == 'narrow'
            ? const Size(320, 844)
            : const Size(568, 320);
        final key = await _pump(
          tester,
          _Page.notifications,
          AppLocale.zh,
          false,
          brandId: brand,
          permissionGranted: false,
          size: size,
          textScaler: TextScaler.linear(layout == 'ordinary' ? 1 : 1.6),
          branded: true,
        );
        final element = tester.element(find.byType(NotificationSettingsScreen));
        final state = tester.state(find.byType(NotificationSettingsScreen));
        final prefs = await SharedPreferences.getInstance();
        final initial = {for (final k in prefs.getKeys()) k: prefs.get(k)};
        final measurements = <Map<String, Object?>>[];
        var retained = true;
        for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          retained =
              retained &&
              identical(
                element,
                tester.element(find.byType(NotificationSettingsScreen)),
              ) &&
              identical(
                state,
                tester.state(find.byType(NotificationSettingsScreen)),
              );
          final content = find.byKey(
            const ValueKey('notification_settings_content'),
          );
          final scroll = find
              .descendant(of: content, matching: find.byType(Scrollable))
              .first;
          tester.state<ScrollableState>(scroll).position.jumpTo(0);
          await tester.pumpAndSettle();
          for (final entry in [
            ('title', NotificationUiCopy.settingsTitle),
            ('description', NotificationUiCopy.settingsHeroSubtitle),
          ]) {
            final label = find.descendant(
              of: content,
              matching: find.text(entry.$2),
            );
            expect(label, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(label);
            final natural = TextPainter(
              text: paragraph.text,
              textDirection: paragraph.textDirection,
              textScaler: paragraph.textScaler,
              locale: paragraph.locale,
              strutStyle: paragraph.strutStyle,
              textWidthBasis: paragraph.textWidthBasis,
              textHeightBehavior: paragraph.textHeightBehavior,
            )..layout(maxWidth: paragraph.size.width);
            final rect = tester.getRect(label);
            measurements.add({
              'locale': locale.name,
              'role': entry.$1,
              'text': entry.$2,
              'truncated': paragraph.didExceedMaxLines,
              'height': paragraph.size.height,
              'naturalHeight': natural.height,
              'width': paragraph.size.width,
              'naturalLines': natural.computeLineMetrics().length,
              'fontSize': paragraph.text.style?.fontSize,
              'fontWeight': paragraph.text.style?.fontWeight?.value,
              'textScaleAt12': paragraph.textScaler.scale(12),
              'foreground': paragraph.text.style?.color?.toARGB32(),
              'rect': [rect.left, rect.top, rect.right, rect.bottom],
            });
            natural.dispose();
          }
          final run = Platform.environment['DUOYI_NOTIFICATION_HERO_RUN'];
          if (run != null && measurements.length <= 4) {
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final picture = await boundary.toImage();
              try {
                final data = await picture.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  'evidence/screenshots/notification-hero-fit-20261020/$run/$brand-$layout-${locale.name}.png',
                );
                file.parent.createSync(recursive: true);
                file.writeAsBytesSync(data!.buffer.asUint8List());
              } finally {
                picture.dispose();
              }
            });
          }
        }
        expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, initial);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        final run = Platform.environment['DUOYI_NOTIFICATION_HERO_RUN'];
        if (run != null) {
          final file = File(
            'evidence/notification-hero-fit-20261020/$run/$brand-$layout.json',
          );
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert({
              'retained': retained,
              'preferencesUnchanged': true,
              'measurements': measurements,
            }),
          );
        }
        expect(retained, isTrue);
        expect(
          measurements.where(
            (m) =>
                m['truncated'] == true ||
                (m['height'] as num) + 0.1 < (m['naturalHeight'] as num),
          ),
          isEmpty,
          reason:
              'The real bilingual notification hero must show complete text at its natural scaled font.',
        );
      });
    }
  }

  testWidgets(
    'report reminder stays expanded and its picker keeps wheel state across locale changes',
    (tester) async {
      await _pump(tester, _Page.notifications, AppLocale.zh, false);
      final monthlyHeader = find.byKey(
        const ValueKey('report_reminder_monthly_header'),
      );
      await _showSettingsItem(tester, monthlyHeader);
      await tester.tap(monthlyHeader);
      await tester.pumpAndSettle();
      final timeButton = find.byKey(
        const ValueKey('report_reminder_time_button_monthly'),
      );
      await tester.ensureVisible(timeButton);
      await tester.tap(timeButton);
      await tester.pumpAndSettle();
      final wheels = tester
          .widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
          .toList();
      expect(wheels, hasLength(2));
      final hourController =
          wheels[0].controller! as FixedExtentScrollController;
      final minuteController =
          wheels[1].controller! as FixedExtentScrollController;
      hourController.jumpToItem((hourController.selectedItem + 3) % 24);
      minuteController.jumpToItem((minuteController.selectedItem + 7) % 60);
      await tester.pumpAndSettle();
      final hour = hourController.selectedItem;
      final minute = minuteController.selectedItem;
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text('Monthly report notification time'), findsOneWidget);
      _expectEnglish(tester);
      final localizedWheels = tester
          .widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
          .toList();
      expect(localizedWheels[0].controller, same(hourController));
      expect(localizedWheels[1].controller, same(minuteController));
      expect(hourController.selectedItem, hour);
      expect(minuteController.selectedItem, minute);
      await tester.tap(find.text(I18n.tr('action.cancel')));
      await tester.pumpAndSettle();
      expect(timeButton, findsOneWidget);
      _expectEnglish(tester);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brand in ['defaultBrand', 'liquidGlass', 're0', 'starRail']) {
    for (final page in [
      _Page.history,
      _Page.notifications,
      _Page.registeredReminders,
    ]) {
      for (final pushed in [false, true]) {
        for (final layout
            in brand == 're0' || brand == 'starRail'
                ? [priorityLayouts[1]]
                : priorityLayouts) {
          final name =
              'notification-backdrop-$brand-${page.name}-${pushed ? "pushed" : "standalone"}-${layout.name}';
          testWidgets(name, (tester) async {
            final capture = await _pump(
              tester,
              page,
              AppLocale.zh,
              false,
              brandId: brand,
              permissionGranted: false,
              size: layout.size,
              textScaler: layout.scale < 0
                  ? const RouteProbeNonlinearScaler()
                  : TextScaler.linear(layout.scale),
              // Mine wraps these two pages; the registered-reminders entry
              // pushes a plain MaterialPageRoute from notification settings.
              branded: pushed && page != _Page.registeredReminders,
              pushed: pushed,
            );
            final pageFinder = switch (page) {
              _Page.history => find.byType(NotificationHistoryScreen),
              _Page.notifications => find.byType(NotificationSettingsScreen),
              _ => find.byType(RegisteredRemindersScreen),
            };
            final retained = tester.element(pageFinder);
            final state = tester.state(pageFinder);
            final theme = Provider.of<ThemeProvider>(retained, listen: false);
            expect(theme.brand.id, brand);
            final points = [
              for (final fraction in [.35, .65, .9])
                Offset(2, layout.size.height * fraction),
            ];
            final observations = <String, List<int>>{};
            final renderErrors = <Object>[];
            for (final locale in [AppLocale.zh, AppLocale.en]) {
              I18n.setLocale(locale);
              await tester.pumpAndSettle();
              expect(tester.element(pageFinder), same(retained));
              expect(tester.state(pageFinder), same(state));
              observations[locale.name] = await _backdropPixels(
                tester,
                capture,
                points,
              );
              await _capture(tester, capture, '$name-${locale.name}');
              final renderError = tester.takeException();
              if (renderError != null) renderErrors.add(renderError);
              if (page == _Page.registeredReminders) {
                final probe = RouteRenderProbe(
                  tester,
                  capture,
                  '$name-${locale.name}',
                );
                final title = find.descendant(
                  of: find.byType(AppBar),
                  matching: find.text(
                    NotificationUiCopy.registeredRemindersTitle,
                  ),
                );
                await probe.text(title, role: 'full route title');
                final titleRect = tester.getRect(title);
                final appBarRect = tester.getRect(find.byType(AppBar));
                expect(
                  appBarRect.inflate(0.1).contains(titleRect.topLeft),
                  isTrue,
                );
                expect(
                  appBarRect.inflate(0.1).contains(titleRect.bottomRight),
                  isTrue,
                );
                await probe.text(
                  find.byKey(
                    const ValueKey('registered_reminders_status_hint'),
                  ),
                  role: 'registration status explanation',
                );
                final emptyMessage = find.text(
                  NotificationUiCopy.registeredEmptyMessage(
                    filterName: 'current',
                    missingCount: 0,
                  ),
                );
                // EmptyState has a non-scrolling inner viewport; reveal through
                // all ancestors so the real page viewport reaches its message.
                await tester.ensureVisible(emptyMessage);
                await tester.pumpAndSettle();
                await probe.text(
                  emptyMessage,
                  role: 'empty registration state',
                );
                await _capture(
                  tester,
                  capture,
                  '$name-${locale.name}-reading-end',
                );
                final scrolling = tester.state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byKey(
                          const ValueKey('registered_reminders_scroll_view'),
                        ),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                );
                expect(
                  tester
                      .stateList<ScrollableState>(find.byType(Scrollable))
                      .where((s) => s.position.maxScrollExtent > 0.1)
                      .length,
                  scrolling.position.maxScrollExtent > 0.1 ? 1 : 0,
                  reason: 'one continuous vertical reading flow',
                );
                final output = Platform
                    .environment['DUOYI_NOTIFICATION_BACKDROP_EVIDENCE'];
                if (output != null) {
                  await tester.runAsync(() async {
                    final file = File(
                      '$output/reading/$name-${locale.name}.json',
                    );
                    file.parent.createSync(recursive: true);
                    file.writeAsStringSync(
                      jsonEncode({
                        'name': '$name-${locale.name}',
                        'rows': probe.rows,
                        'errors': probe.errors,
                      }),
                    );
                  });
                }
                expect(probe.errors, isEmpty);
                scrolling.position.jumpTo(0);
                await tester.pumpAndSettle();
              }
            }
            if (pushed) {
              Navigator.of(retained).pop();
              await tester.pumpAndSettle();
              expect(
                find.byKey(const ValueKey('notification-backdrop-open')),
                findsOneWidget,
              );
            }
            // Unmount the real page before rendering the independent reference.
            final reference = GlobalKey();
            await tester.pumpWidget(
              ChangeNotifierProvider<ThemeProvider>.value(
                value: theme,
                child: MaterialApp(
                  theme: theme.brand.theme,
                  home: RepaintBoundary(
                    key: reference,
                    child: Material(
                      color: theme.brand.theme.brightness == Brightness.dark
                          ? theme.brand.theme.colorScheme.surface
                          : theme
                                .brand
                                .theme
                                .colorScheme
                                .surfaceContainerLowest,
                      child: brand == 'liquidGlass'
                          ? const BrandBackground(child: SizedBox.expand())
                          : const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final expected = await _backdropPixels(tester, reference, points);
            final output =
                Platform.environment['DUOYI_NOTIFICATION_BACKDROP_EVIDENCE'];
            if (output != null) {
              await tester.runAsync(() async {
                final file = File('$output/$name.json');
                file.parent.createSync(recursive: true);
                file.writeAsStringSync(
                  jsonEncode({
                    'name': name,
                    'backgroundPolicy': brand == 'liquidGlass'
                        ? 'production BrandBackground'
                        : 'original opaque routeBackground',
                    'actual': observations,
                    'reference': expected,
                    'renderErrors': [
                      for (final error in renderErrors) '$error',
                    ],
                  }),
                );
              });
            }
            for (final entry in observations.entries) {
              expect(
                entry.value,
                expected,
                reason:
                    '$name ${entry.key}: preserve the brand background policy',
              );
            }
            expect(renderErrors, isEmpty, reason: '$name: no layout errors');
            await tester.pumpWidget(const SizedBox.shrink());
          });
        }
      }
    }
  }
  for (final initialBrand in ['defaultBrand', 'liquidGlass']) {
    for (final page in [
      _Page.history,
      _Page.notifications,
      _Page.registeredReminders,
    ]) {
      for (final pushed in [false, true]) {
        final name =
            'notification-live-$initialBrand-${page.name}-${pushed ? "pushed" : "standalone"}';
        testWidgets(name, (tester) async {
          final capture = await _pump(
            tester,
            page,
            AppLocale.en,
            false,
            brandId: initialBrand,
            permissionGranted: false,
            size: const Size(568, 320),
            textScaler: const TextScaler.linear(2),
            branded: pushed && page != _Page.registeredReminders,
            pushed: pushed,
          );
          final route = switch (page) {
            _Page.history => find.byType(NotificationHistoryScreen),
            _Page.notifications => find.byType(NotificationSettingsScreen),
            _ => find.byType(RegisteredRemindersScreen),
          };
          final element = tester.element(route);
          final state = tester.state(route);
          final theme = Provider.of<ThemeProvider>(element, listen: false);
          ScrollableState? scrolling;
          Finder? scrollHost;
          if (page == _Page.notifications) {
            scrollHost = find.byKey(
              const ValueKey('notification_settings_scroll_view'),
            );
          } else if (page == _Page.registeredReminders) {
            final filter = find.byKey(
              const ValueKey('registered_reminders_filter_missing'),
            );
            await tester.ensureVisible(filter);
            await tester.tap(filter);
            await tester.pumpAndSettle();
            scrollHost = find.byKey(
              const ValueKey('registered_reminders_scroll_view'),
            );
          }
          if (scrollHost != null) {
            scrolling = tester.state<ScrollableState>(
              find
                  .descendant(of: scrollHost, matching: find.byType(Scrollable))
                  .first,
            );
            expect(scrolling.position.maxScrollExtent, greaterThan(0));
            scrolling.position.jumpTo(
              scrolling.position.maxScrollExtent.clamp(0, 20).toDouble(),
            );
            await tester.pumpAndSettle();
          }
          final initialOffset = scrolling?.position.pixels;
          final pixels = <List<int>>[];
          final alternateBrand = initialBrand == 'defaultBrand'
              ? 'liquidGlass'
              : 'defaultBrand';
          var phase = 0;
          for (final brand in [initialBrand, alternateBrand, initialBrand]) {
            if (theme.brand.id != brand) {
              expect(
                await tester.runAsync(() => theme.setBrand(brand)),
                isTrue,
              );
              await tester.pumpAndSettle();
            }
            expect(theme.brand.id, brand);
            expect(tester.element(route), same(element));
            expect(tester.state(route), same(state));
            if (scrollHost != null) {
              expect(
                tester.state<ScrollableState>(
                  find
                      .descendant(
                        of: scrollHost,
                        matching: find.byType(Scrollable),
                      )
                      .first,
                ),
                same(scrolling),
              );
              expect(scrolling!.position.pixels, closeTo(initialOffset!, 0.1));
            }
            if (page == _Page.registeredReminders) {
              expect(
                tester
                    .widget<ChoiceChip>(
                      find.byKey(
                        const ValueKey('registered_reminders_filter_missing'),
                      ),
                    )
                    .selected,
                isTrue,
              );
            }
            pixels.add(
              await _backdropPixels(tester, capture, const [
                Offset(2, 112),
                Offset(2, 208),
                Offset(2, 288),
              ]),
            );
            await _capture(tester, capture, '$name-phase$phase-$brand');
            expect(tester.takeException(), isNull);
            phase++;
          }
          expect(pixels[2], pixels[0]);
          expect(pixels[1], isNot(pixels[0]));
          for (final locale in [AppLocale.zh, AppLocale.en]) {
            I18n.setLocale(locale);
            await tester.pumpAndSettle();
            expect(tester.element(route), same(element));
            expect(tester.state(route), same(state));
            if (scrollHost != null) {
              expect(
                tester.state<ScrollableState>(
                  find
                      .descendant(
                        of: scrollHost,
                        matching: find.byType(Scrollable),
                      )
                      .first,
                ),
                same(scrolling),
              );
            }
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}

Future<GlobalKey> _pump(
  WidgetTester tester,
  _Page page,
  AppLocale locale,
  bool dark, {
  String? brandId,
  bool? permissionGranted,
  Size size = const Size(320, 844),
  TextScaler textScaler = const TextScaler.linear(1.6),
  bool branded = false,
  bool pushed = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'active_brand': brandId ?? (dark ? 'starRail' : 'defaultBrand'),
    'theme_unlocked_brands': ['defaultBrand', 'liquidGlass', 're0', 'starRail'],
  });
  I18n.setLocale(locale);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWeeklyReviewScreenshotFonts);
  if (page == _Page.notifications) {
    await tester.runAsync(() async {
      final originalPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await LocalNotifications.instance.init();
        await AlarmService.instance.init();
      } finally {
        debugDefaultTargetPlatformOverride = originalPlatform;
      }
    });
  }
  final theme = ThemeProvider();
  await theme.loadFromStorage();
  final localeProvider = LocaleProvider();
  await localeProvider.setLocale(locale);
  final auth = AuthProvider();
  final rewards = AchievementProvider();
  final preferences = PreferencesProvider();
  final notification = permissionGranted == null
      ? NotificationService()
      : _PermissionNotificationService(permissionGranted);
  final calendar = CalendarSyncProvider();
  final location = LocationReminderProvider();
  for (final provider in [
    theme,
    localeProvider,
    auth,
    rewards,
    preferences,
    notification,
    calendar,
    location,
  ]) {
    addTearDown(provider.dispose);
  }
  final key = GlobalKey();
  final screen = switch (page) {
    _Page.backup => const BackupScreen(),
    _Page.restore => const BackupScreen(initialMode: BackupEntryMode.restore),
    _Page.themes => const ThemePickerScreen(),
    _Page.integrations => const IntegrationsScreen(),
    _Page.history => const NotificationHistoryScreen(),
    _Page.notifications => const NotificationSettingsScreen(),
    _Page.registeredReminders => const RegisteredRemindersScreen(),
  };
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AchievementProvider>.value(value: rewards),
        ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
        ChangeNotifierProvider<NotificationService>.value(value: notification),
        ChangeNotifierProvider<CalendarSyncProvider>.value(value: calendar),
        ChangeNotifierProvider<LocationReminderProvider>.value(value: location),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, selected, _) {
          final baseTheme = selected.brand.theme;
          final fonts = baseTheme.textTheme.apply(
            fontFamily: 'DuoyiScreenshotLatin',
            fontFamilyFallback: const ['DuoyiScreenshot'],
          );
          return MaterialApp(
            theme: baseTheme.copyWith(
              textTheme: fonts,
              primaryTextTheme: fonts,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: pushed ? RepaintBoundary(key: key, child: child!) : child!,
            ),
            home: pushed
                ? Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        key: const ValueKey('notification-backdrop-open'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => branded
                                ? BrandRouteSurface(child: screen)
                                : screen,
                          ),
                        ),
                        child: const Text('Open'),
                      ),
                    ),
                  )
                : RepaintBoundary(
                    key: key,
                    child: branded ? BrandRouteSurface(child: screen) : screen,
                  ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (pushed) {
    await tester.tap(find.byKey(const ValueKey('notification-backdrop-open')));
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull);
  return key;
}

Future<List<int>> _backdropPixels(
  WidgetTester tester,
  GlobalKey key,
  List<Offset> points,
) async => (await tester.runAsync(() async {
  final render =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await render.toImage(pixelRatio: 1);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return [
      for (final point in points)
        data.getUint32((point.dy.floor() * image.width + point.dx.floor()) * 4),
    ];
  } finally {
    image.dispose();
  }
}))!;

Future<void> _auditScroll(WidgetTester tester, AppLocale locale) async {
  for (var i = 0; i < 30; i++) {
    if (locale == AppLocale.en) _expectEnglish(tester);
    final lists = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where((s) => s.widget.axisDirection == AxisDirection.down)
        .toList();
    if (lists.isEmpty || lists.first.position.extentAfter < 1) break;
    lists.first.position.jumpTo(
      (lists.first.position.pixels + 480).clamp(
        0,
        lists.first.position.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
}

Future<void> _auditReminderSections(
  WidgetTester tester,
  GlobalKey key,
  String name,
  AppLocale locale,
) async {
  for (final section in ['daily_reminder_slot_1', 'report_reminder_yearly']) {
    final header = find.byKey(ValueKey('${section}_header'));
    await _showSettingsItem(tester, header);
    await tester.tap(find.byKey(ValueKey('${section}_header_title')));
    await tester.pumpAndSettle();
    final timeButton = find.byKey(
      ValueKey(
        section.startsWith('daily')
            ? 'daily_reminder_slot_1_time_button'
            : 'report_reminder_time_button_yearly',
      ),
    );
    expect(timeButton, findsOneWidget);
    expect(tester.takeException(), isNull);
    if (locale == AppLocale.en) _expectEnglish(tester);
    await _capture(tester, key, '$name-$section');
    await _auditScroll(tester, locale);
  }
}

Future<void> _showSettingsItem(WidgetTester tester, Finder item) async {
  final scrollView = find.byKey(
    const ValueKey('notification_settings_scroll_view'),
  );
  final scrollable = find
      .descendant(of: scrollView, matching: find.byType(Scrollable))
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    item,
    300,
    scrollable: scrollable,
    maxScrolls: 60,
  );
  await Scrollable.ensureVisible(tester.element(item), alignment: 0.25);
  await tester.pumpAndSettle();
}

void _expectEnglish(WidgetTester tester) {
  final values = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');
  expect(
    values.where(
      (text) => RegExp(r'[\u3400-\u9fff]').hasMatch(text) && text != '简体中文',
    ),
    isEmpty,
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final filter = Platform.environment['DUOYI_DATA_SETTINGS_SCREENSHOT_FILTER'];
  if (filter != null && !RegExp(filter).hasMatch(name)) return;
  if (Platform.environment['DUOYI_CAPTURE_DATA_SETTINGS_SCREENSHOTS'] != '1') {
    return;
  }
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    try {
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '${Platform.environment['DUOYI_DATA_SETTINGS_SCREENSHOT_DIRECTORY'] ?? 'evidence/screenshots/notification-settings-locale-20261012'}/$name.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}

class _PermissionNotificationService extends NotificationService {
  _PermissionNotificationService(this.granted);
  final bool granted;
  @override
  bool get permissionGranted => granted;
  @override
  Future<bool> refreshPermission() async => granted;
}
