import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/notification_history_policy.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/notification_history_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/alarm_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/local_notifications.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/foundation.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';
import '../support/weekly_review_screenshot_font.dart';

const _historyKey = 'duoyi_notif_history';
const _limitKey = NotificationHistoryPolicy.preferenceKey;
const _platformHistoryKey = 'flutter.$_historyKey';
const _platformLimitKey = 'flutter.$_limitKey';
final _captureRetentionScreenshots =
    Platform.environment['DUOYI_CAPTURE_NOTIFICATION_RETENTION_SCREENSHOTS'] ==
    '1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';

    FlutterLocalNotificationsPlatform? oldPlugin;
    try {
      oldPlugin = FlutterLocalNotificationsPlatform.instance;
    } on Error {
      oldPlugin = null;
    }
    IOSFlutterLocalNotificationsPlugin.registerWith();
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
      LocalTimezoneResolver.debugSystemTimeZoneReader = null;
      LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
      if (oldPlugin != null) {
        FlutterLocalNotificationsPlatform.instance = oldPlugin;
      }
      I18n.setLocale(AppLocale.zh);
    });
  });

  testWidgets(
    'brand history route retains search filters selection and page across locales',
    (tester) async {
      await _pump(
        tester,
        historyItems: [
          for (final id in _initialIds)
            _item(id).copyWith(isRead: id == 'history-199'),
          NotificationItem(
            id: 'other-type-match',
            title: 'history-199 todo match',
            body: 'Must be excluded by the general type filter',
            scheduledTime: DateTime.utc(2026, 10, 2),
            type: NotificationType.todo,
          ),
        ],
      );
      unawaited(
        Navigator.of(
          tester.element(find.byType(NotificationSettingsScreen)),
        ).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                const BrandRouteSurface(child: NotificationHistoryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final screenState = tester.state(find.byType(NotificationHistoryScreen));
      final search = find.byType(TextField);
      await tester.enterText(search, 'history-1');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final general = find.widgetWithText(
        ChoiceChip,
        NotificationUiCopy.notificationTypeLabel(NotificationType.general),
      );
      await tester.ensureVisible(general);
      await tester.tap(general);
      await tester.pumpAndSettle();
      final readControl = find.byWidgetPredicate(
        (widget) => widget is SegmentedButton,
      );
      await tester.tap(
        find.descendant(
          of: readControl,
          matching: find.text(NotificationUiCopy.filterUnread),
        ),
      );
      await tester.pumpAndSettle();
      final unreadSelection =
          (tester.widget(readControl) as SegmentedButton).selected.single;
      await tester.tap(find.byTooltip(NotificationUiCopy.pagerNextTooltip));
      await tester.pumpAndSettle();
      expect(find.text('51-100 / 110'), findsOneWidget);
      final controller = tester.widget<TextField>(search).controller!;
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 6,
      );
      final editingValue = controller.value;
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(NotificationHistoryScreen)),
          same(screenState),
        );
        expect(tester.widget<TextField>(search).controller, same(controller));
        expect(controller.value, editingValue);
        expect(find.text('51-100 / 110'), findsOneWidget);
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(
                  ChoiceChip,
                  NotificationUiCopy.notificationTypeLabel(
                    NotificationType.general,
                  ),
                ),
              )
              .selected,
          isTrue,
        );
        expect(
          (tester.widget(readControl) as SegmentedButton).selected.single,
          unreadSelection,
        );
        expect(
          find.byKey(const ValueKey('notification_record_history-148')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'clear history confirmation follows brand without losing its route',
    (tester) async {
      if (_captureRetentionScreenshots) {
        await tester.runAsync(loadWeeklyReviewScreenshotFonts);
        I18n.setLocale(AppLocale.en);
      }
      final fixture = await _pump(
        tester,
        liveBrand: true,
        historyItems: [_item('theme-confirmation-history')],
      );
      final theme = Provider.of<ThemeProvider>(
        tester.element(find.byType(NotificationSettingsScreen)),
        listen: false,
      );
      unawaited(
        Navigator.of(
          tester.element(find.byType(NotificationSettingsScreen)),
        ).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                const BrandRouteSurface(child: NotificationHistoryScreen()),
          ),
        ),
      );
      await _settle(tester);
      final history = fixture.notifications.history.single;
      final historyState = tester.state(find.byType(NotificationHistoryScreen));
      final search = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      search.text = 'theme-confirmation';
      await _settle(tester);
      await tester.tap(find.byTooltip(NotificationUiCopy.clearHistoryTooltip));
      await _settle(tester);

      final dialog = find.byType(AppDialog);
      final dialogElement = tester.element(dialog);
      final dialogRoute = ModalRoute.of(dialogElement);
      expect(
        Theme.of(dialogElement).colorScheme.primary,
        AppBrands.defaultBrand.theme.colorScheme.primary,
      );
      await _captureRetentionScreenshot(
        tester,
        fixture.overlayBoundary,
        'clear-history-default-initial',
      );
      for (final brand in ['liquidGlass', 'defaultBrand']) {
        await tester.runAsync(() async {
          if (brand == 'liquidGlass') await theme.unlockBrand(brand);
          expect(await theme.setBrand(brand), isTrue);
        });
        await _settle(tester);
        expect(tester.element(dialog), same(dialogElement));
        expect(ModalRoute.of(tester.element(dialog)), same(dialogRoute));
        expect(
          Theme.of(tester.element(dialog)).colorScheme.primary,
          AppBrands.byId(brand).theme.colorScheme.primary,
        );
        expect(
          tester.state(find.byType(NotificationHistoryScreen)),
          same(historyState),
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller,
          same(search),
        );
        expect(fixture.notifications.history.single.id, history.id);
        expect(search.text, 'theme-confirmation');
        await _captureRetentionScreenshot(
          tester,
          fixture.overlayBoundary,
          'clear-history-$brand-return',
        );
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.text(I18n.tr('action.cancel')));
      await _settle(tester);
      expect(find.byType(AppDialog), findsNothing);
      expect(fixture.notifications.history.single.id, history.id);
    },
  );

  for (final throws in [false, true]) {
    testWidgets(
      'preference failure $throws preserves history and retries after a locale change',
      (tester) async {
        final fixture = await _pump(tester);
        final screenState = tester.state(
          find.byType(NotificationSettingsScreen),
        );
        final onChanged = _historyLimitCallback(tester);
        fixture.store.failNext(_platformLimitKey, throws: throws);

        onChanged(100);
        await _settle(tester);

        expect(fixture.preferences.notificationHistoryLimit, 500);
        expect(fixture.notifications.historyLimit, 500);
        expect(fixture.notifications.history, hasLength(200));
        expect(fixture.store.historyWriteCount, 0);
        expect(await fixture.diskLimit(), 500);
        expect(await fixture.diskHistoryIds(), _initialIds.toSet());
        expect(
          find.text(NotificationUiCopy.historyRetentionSaveFailed),
          findsOneWidget,
          reason:
              'preference writes=${fixture.store.limitWriteCount}, '
              'boundary=${AccountPreferenceWrites.isBoundaryActive}, '
              'busy=${tester.widget<AppCompactDropdown<int>>(find.byKey(const ValueKey('notification_history_limit_dropdown'))).onChanged == null}',
        );

        I18n.setLocale(AppLocale.en);
        await tester.pump();
        expect(
          tester.state(find.byType(NotificationSettingsScreen)),
          same(screenState),
        );
        expect(
          find.text(NotificationUiCopy.historyRetentionSaveFailed),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('notification_history_limit_retry')),
        );
        await _settle(tester);

        expect(fixture.preferences.notificationHistoryLimit, 100);
        expect(fixture.notifications.historyLimit, 100);
        expect(fixture.notifications.history, hasLength(100));
        expect(fixture.store.historyWriteCount, greaterThan(0));
        expect(await fixture.diskLimit(), 100);
        expect(await fixture.diskHistoryIds(), _initialIds.take(100).toSet());
        expect(
          find.text(NotificationUiCopy.historyRetentionSaved(100)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final throws in [false, true]) {
    testWidgets(
      'trim failure $throws preserves records and retries the saved limit',
      (tester) async {
        final fixture = await _pump(tester);
        final screenState = tester.state(
          find.byType(NotificationSettingsScreen),
        );
        final onChanged = _historyLimitCallback(tester);
        fixture.store.failNext(_platformHistoryKey, throws: throws);

        onChanged(100);
        await _settle(tester);

        expect(fixture.preferences.notificationHistoryLimit, 100);
        expect(fixture.notifications.historyLimit, 500);
        expect(fixture.notifications.history, hasLength(200));
        expect(fixture.store.historyWriteCount, greaterThan(0));
        expect(await fixture.diskLimit(), 100);
        expect(await fixture.diskHistoryIds(), _initialIds.toSet());
        expect(
          find.text(NotificationUiCopy.historyRetentionTrimFailed),
          findsOneWidget,
        );

        I18n.setLocale(AppLocale.en);
        await tester.pump();
        expect(
          tester.state(find.byType(NotificationSettingsScreen)),
          same(screenState),
        );
        expect(
          find.text(NotificationUiCopy.historyRetentionTrimFailed),
          findsOneWidget,
        );
        expect(
          find.text(
            'Limit saved, but old records could not be cleaned up. Retry to finish.',
          ),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('notification_history_limit_retry')),
        );
        await _settle(tester);

        expect(fixture.preferences.notificationHistoryLimit, 100);
        expect(fixture.notifications.historyLimit, 100);
        expect(fixture.notifications.history, hasLength(100));
        expect(await fixture.diskLimit(), 100);
        expect(await fixture.diskHistoryIds(), _initialIds.take(100).toSet());
        expect(
          find.text(NotificationUiCopy.historyRetentionSaved(100)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final boundary in [
    'session',
    'lock',
    'update',
    'preference reset',
    'notification reset',
    'account epoch',
    'covered route',
  ]) {
    testWidgets('retained dropdown callback does not write after $boundary', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      final onChanged = _historyLimitCallback(tester);

      switch (boundary) {
        case 'session':
          fixture.auth.advanceSession();
          break;
        case 'lock':
          fixture.lock.setLocked(true);
          break;
        case 'update':
          fixture.update.setMustUpdate(true);
          break;
        case 'preference reset':
          fixture.preferences.resetLocalState();
          break;
        case 'notification reset':
          fixture.notifications.resetLocalState();
          break;
        case 'account epoch':
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          break;
        case 'covered route':
          await _coverRoute(tester);
          break;
      }

      onChanged(100);
      await _settle(tester);

      expect(fixture.store.limitWriteCount, 0);
      expect(fixture.store.historyWriteCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final boundary in ['covered route', 'lock']) {
    testWidgets('held preference write cannot trim after $boundary', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      fixture.store.holdNextWrite(_platformLimitKey);

      _historyLimitCallback(tester)(100);
      await tester.pump();
      await fixture.store.writeStarted.future;
      expect(
        tester
            .widget<AppCompactDropdown<int>>(
              find.byKey(const ValueKey('notification_history_limit_dropdown')),
            )
            .onChanged,
        isNull,
      );

      if (boundary == 'covered route') {
        await _coverRoute(tester);
      } else {
        fixture.lock.setLocked(true);
      }
      fixture.store.releaseHeldWrite();
      await _settle(tester);

      expect(fixture.store.historyWriteCount, 0);
      expect(fixture.notifications.historyLimit, 500);
      expect(fixture.notifications.history, hasLength(200));
      expect(fixture.preferences.notificationHistoryLimit, 500);
      expect(await fixture.diskLimit(), 500);
      expect(await fixture.diskHistoryIds(), _initialIds.toSet());
      expect(tester.takeException(), isNull);
    });
  }

  for (final boundary in ['covered route', 'account epoch']) {
    testWidgets('failed-save retry does not write after $boundary', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      fixture.store.failNext(_platformLimitKey, throws: false);
      _historyLimitCallback(tester)(100);
      await _settle(tester);

      final retry = tester.widget<TextButton>(
        find.byKey(const ValueKey('notification_history_limit_retry')),
      );
      final retryCallback = retry.onPressed!;
      final limitWritesBeforeRetry = fixture.store.limitWriteCount;
      if (boundary == 'covered route') {
        await _coverRoute(tester);
      } else {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      }

      retryCallback();
      await _settle(tester);

      expect(fixture.store.limitWriteCount, limitWritesBeforeRetry);
      expect(fixture.store.historyWriteCount, 0);
      expect(fixture.notifications.history, hasLength(200));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('retained callback rejects replaced providers', (tester) async {
    final fixture = await _pump(tester);
    final onChanged = _historyLimitCallback(tester);
    final replacementPreferences = PreferencesProvider();
    final replacementNotifications = _ReadyNotifications();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      replacementPreferences.dispose();
      replacementNotifications.dispose();
    });

    await tester.pumpWidget(
      _settingsApp(
        fixture,
        preferences: replacementPreferences,
        notifications: replacementNotifications,
      ),
    );
    await _settle(tester);
    onChanged(100);
    await _settle(tester);

    expect(fixture.store.limitWriteCount, 0);
    expect(fixture.store.historyWriteCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retention dropdown keeps its count across locales at 320px and 1.6x text',
    (tester) async {
      final fixture = await _pump(
        tester,
        width: 320,
        textScale: 1.6,
        captureScreenshotFonts: true,
      );
      final dropdownFinder = find.byKey(
        const ValueKey('notification_history_limit_dropdown'),
      );
      await _show(tester, dropdownFinder);

      _historyLimitCallback(tester)(100);
      await _settle(tester);
      expect(fixture.preferences.notificationHistoryLimit, 100);
      expect(tester.widget<AppCompactDropdown<int>>(dropdownFinder).value, 100);
      expect(find.text('100 条'), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await _settle(tester);

      expect(tester.widget<AppCompactDropdown<int>>(dropdownFinder).value, 100);
      expect(find.text('100 items'), findsOneWidget);
      expect(find.text('500 items'), findsNothing);
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.descendant(
                of: dropdownFinder,
                matching: find.text('100 items'),
              ),
            )
            .didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final boundary in ['session', 'lock', 'update', 'covered route']) {
    testWidgets('retained picker opener is blocked after $boundary', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      final dropdown = find.byKey(
        const ValueKey('notification_history_limit_dropdown'),
      );
      final opener = tester
          .widget<InkWell>(
            find.descendant(of: dropdown, matching: find.byType(InkWell)),
          )
          .onTap!;
      await _invalidatePicker(tester, fixture, boundary);

      opener();
      await _settle(tester);

      expect(_menuItems(), findsNothing);
      expect(fixture.store.limitWriteCount, 0);
      expect(fixture.store.historyWriteCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picker awaiting keyboard hide is blocked after $boundary', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      await tester.tap(
        find.byKey(const ValueKey('notification_history_limit_dropdown')),
      );
      await tester.pump();
      expect(_menuItems(), findsNothing);
      await _invalidatePicker(tester, fixture, boundary);
      await tester.pump(const Duration(milliseconds: 500));
      await _settle(tester);

      expect(_menuItems(), findsNothing);
      expect(fixture.store.limitWriteCount, 0);
      expect(fixture.store.historyWriteCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final boundary in ['session', 'lock', 'update', 'covered route']) {
    testWidgets('retained menu item cannot pop or save after $boundary', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      await tester.tap(
        find.byKey(const ValueKey('notification_history_limit_dropdown')),
      );
      await _settle(tester);
      final itemTap = tester
          .widget<InkWell>(
            find
                .ancestor(
                  of: find.text('100 条'),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .onTap!;
      await _invalidatePicker(tester, fixture, boundary);

      itemTap();
      await _settle(tester);

      if (boundary == 'covered route') {
        expect(find.text('Covered route'), findsOneWidget);
      } else {
        expect(_menuItems(), findsWidgets);
        expect(find.text('100 条'), findsOneWidget);
      }
      expect(fixture.store.limitWriteCount, 0);
      expect(fixture.store.historyWriteCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('open dropdown options update with the live locale', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    final dropdown = find.byKey(
      const ValueKey('notification_history_limit_dropdown'),
    );
    final openingWidget = tester.widget<AppCompactDropdown<int>>(dropdown);
    await tester.tap(dropdown);
    await _settle(tester);
    expect(find.text('100 条'), findsOneWidget);

    I18n.setLocale(AppLocale.en);
    await _settle(tester);
    expect(find.text('100 items'), findsOneWidget);
    expect(
      openingWidget.isSelectionAllowed!(),
      isTrue,
      reason: 'the opening origin must remain valid across locale changes',
    );
    final menuRoute = ModalRoute.of(tester.element(find.text('100 items')))!;
    expect(menuRoute.isCurrent, isTrue);

    await tester.tap(find.text('100 items'));
    await _settle(tester);
    expect(
      fixture.preferences.notificationHistoryLimit,
      100,
      reason:
          'menu=${_menuItems().evaluate().length}, '
          'writeCount=${fixture.store.limitWriteCount}, '
          'opening origin=${openingWidget.isInteractionAllowed!()}',
    );
    expect(fixture.notifications.historyLimit, 100);
    expect(fixture.notifications.history, hasLength(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('open dropdown ignores a selection from an old session', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('notification_history_limit_dropdown')),
    );
    await _settle(tester);
    expect(find.text('100 条'), findsOneWidget);

    fixture.auth.advanceSession();
    await _settle(tester);
    await tester.tap(find.text('100 条'));
    await _settle(tester);

    expect(fixture.store.limitWriteCount, 0);
    expect(fixture.store.historyWriteCount, 0);
    expect(fixture.notifications.historyLimit, 500);
    expect(fixture.notifications.history, hasLength(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('optional partial trim feedback screenshot', (tester) async {
    if (!_captureRetentionScreenshots) return;
    final fixture = await _pump(
      tester,
      width: 320,
      textScale: 1.6,
      captureScreenshotFonts: true,
    );
    fixture.store.failNext(_platformHistoryKey, throws: false);
    _historyLimitCallback(tester)(100);
    await _settle(tester);
    I18n.setLocale(AppLocale.en);
    await _settle(tester);

    await _captureRetentionScreenshot(
      tester,
      fixture.screenshotBoundary,
      'partial-trim-error-en',
    );
  });

  testWidgets('optional normal dropdown screenshot at 320px and 1.6x text', (
    tester,
  ) async {
    if (!_captureRetentionScreenshots) return;
    final fixture = await _pump(
      tester,
      width: 320,
      textScale: 1.6,
      captureScreenshotFonts: true,
    );
    I18n.setLocale(AppLocale.en);
    await _settle(tester);

    await _captureRetentionScreenshot(
      tester,
      fixture.screenshotBoundary,
      'normal-dropdown-320-scale-1_6-en',
    );
  });
}

Future<_Fixture> _pump(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
  double textScale = 1,
  bool captureScreenshotFonts = false,
  bool liveBrand = false,
  List<NotificationItem>? historyItems,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // Notification hydration runs in real async; its queue must be created
  // there too. Preference reads and UI writes keep their queue in fake async.
  final notifications = (await tester.runAsync(
    () async => _ReadyNotifications(),
  ))!;
  final fixture = _Fixture(notifications, historyItems: historyItems);
  SharedPreferencesStorePlatform.instance = fixture.store;
  addTearDown(() async {
    fixture.store.releaseHeldWrite();
    await _settle(tester);
    await AccountPreferenceWrites.drain();
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  await tester.runAsync(() async {
    if (captureScreenshotFonts) await loadWidgetPolishScreenshotFonts();
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await fixture.load();
      await LocalNotifications.instance.init();
      await AlarmService.instance.init();
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });
  // loadFromStorage chains onto the provider's fake-zone write tail. Awaiting
  // it inside runAsync stalls that zone, even when the tail has completed.
  final preferencesLoaded = fixture.preferences.loadFromStorage();
  await _settle(tester);
  expect(
    fixture.preferences.isStorageLoaded,
    isTrue,
    reason: 'preference hydration completes before mounting the settings',
  );
  await preferencesLoaded;
  await tester.pumpWidget(
    _settingsApp(
      fixture,
      textScale: textScale,
      screenshotFonts: captureScreenshotFonts,
      liveBrand: liveBrand,
    ),
  );
  await _settle(tester);
  await _show(
    tester,
    find.byKey(const ValueKey('notification_history_limit_dropdown')),
  );
  return fixture;
}

Widget _settingsApp(
  _Fixture fixture, {
  PreferencesProvider? preferences,
  NotificationService? notifications,
  double textScale = 1,
  bool screenshotFonts = false,
  bool liveBrand = false,
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ChangeNotifierProvider<AuthProvider>.value(value: fixture.auth),
    ChangeNotifierProvider<NotificationService>.value(
      value: notifications ?? fixture.notifications,
    ),
    ChangeNotifierProvider<PreferencesProvider>.value(
      value: preferences ?? fixture.preferences,
    ),
    ChangeNotifierProvider<AppLockProvider>.value(value: fixture.lock),
    ChangeNotifierProvider<AppUpdateService>.value(value: fixture.update),
  ],
  child: Consumer<ThemeProvider>(
    builder: (_, theme, _) => MaterialApp(
      theme: screenshotFonts
          ? widgetPolishScreenshotTheme()
          : (liveBrand ? theme.brand.theme : null),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(key: fixture.overlayBoundary, child: child!),
      ),
      home: RepaintBoundary(
        key: fixture.screenshotBoundary,
        child: const BrandRouteSurface(child: NotificationSettingsScreen()),
      ),
    ),
  ),
);

ValueChanged<int?> _historyLimitCallback(WidgetTester tester) {
  final dropdown = tester.widget<AppCompactDropdown<int>>(
    find.byKey(const ValueKey('notification_history_limit_dropdown')),
  );
  expect(dropdown.onChanged, isNotNull);
  return dropdown.onChanged!;
}

Finder _menuItems() =>
    find.byWidgetPredicate((widget) => widget is PopupMenuItem<int>);

Future<void> _settle(WidgetTester tester) async {
  // Hydration uses real async; UI writes use fake async. Flush both event
  // queues before asserting a completed storage effect or draining teardown.
  for (var i = 0; i < 4; i++) {
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  await tester.pumpAndSettle();
}

Future<void> _coverRoute(WidgetTester tester) async {
  final screen = find.byType(NotificationSettingsScreen);
  unawaited(
    Navigator.of(tester.element(screen))
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covered route')),
          ),
        )
        .then<void>((_) {}),
  );
  await _settle(tester);
}

Future<void> _invalidatePicker(
  WidgetTester tester,
  _Fixture fixture,
  String boundary,
) async {
  switch (boundary) {
    case 'session':
      fixture.auth.advanceSession();
    case 'lock':
      fixture.lock.setLocked(true);
    case 'update':
      fixture.update.setMustUpdate(true);
    case 'covered route':
      await _coverRoute(tester);
  }
  await _settle(tester);
}

Future<void> _show(WidgetTester tester, Finder item) async {
  if (item.evaluate().isNotEmpty) {
    await Scrollable.ensureVisible(tester.element(item), alignment: 0.25);
    await _settle(tester);
    return;
  }
  final scrollable = find
      .descendant(
        of: find.byKey(const ValueKey('notification_settings_scroll_view')),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await _settle(tester);
  await tester.scrollUntilVisible(
    item,
    300,
    scrollable: scrollable,
    maxScrolls: 40,
  );
  await Scrollable.ensureVisible(tester.element(item), alignment: 0.25);
  await _settle(tester);
}

Future<void> _captureRetentionScreenshot(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  if (!_captureRetentionScreenshots) return;
  await _settle(tester);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory =
        Platform.environment['DUOYI_NOTIFICATION_RETENTION_SCREENSHOT_DIR'] ??
        'evidence/screenshots/notification-retention-20261013/v65';
    final file = File('$directory/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

final List<String> _initialIds = List<String>.generate(
  200,
  (index) => 'history-${200 - index}',
  growable: false,
);

class _Fixture {
  _Fixture(this.notifications, {List<NotificationItem>? historyItems})
    : store = _HistoryStore(_seededStorage(historyItems));

  final _HistoryStore store;
  final screenshotBoundary = GlobalKey();
  final overlayBoundary = GlobalKey();
  final auth = _FixtureAuth();
  final preferences = PreferencesProvider();
  final _ReadyNotifications notifications;
  final lock = _FixtureLock();
  final update = _FixtureUpdate();
  late SharedPreferences prefs;

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    await notifications.loadHistoryForTest();
  }

  Future<int?> diskLimit() async {
    await prefs.reload();
    return prefs.getInt(_limitKey);
  }

  Future<Set<String>> diskHistoryIds() async {
    await prefs.reload();
    return (prefs.getStringList(_historyKey) ?? const <String>[])
        .map(
          (raw) => (jsonDecode(raw) as Map<String, dynamic>)['id']! as String,
        )
        .toSet();
  }

  void dispose() {
    auth.dispose();
    preferences.dispose();
    notifications.dispose();
    lock.dispose();
    update.dispose();
  }
}

class _FixtureAuth extends AuthProvider {
  int _fixtureSessionGeneration = 0;

  _FixtureAuth() : super(initialState: const AuthState());

  @override
  int get sessionGeneration => _fixtureSessionGeneration;

  void advanceSession() {
    _fixtureSessionGeneration++;
    notifyListeners();
  }
}

class _ReadyNotifications extends NotificationService {
  @override
  Future<bool> refreshPermission() async => true;
}

class _FixtureLock extends AppLockProvider {
  bool _locked = false;

  @override
  bool get isLocked => _locked;

  void setLocked(bool value) {
    _locked = value;
    notifyListeners();
  }
}

class _FixtureUpdate extends AppUpdateService {
  bool _mustUpdate = false;

  _FixtureUpdate() : super(repo: 'synthetic/test', currentVersion: '1.0.0');

  @override
  bool get mustUpdate => _mustUpdate;

  void setMustUpdate(bool value) {
    _mustUpdate = value;
    notifyListeners();
  }
}

class _HistoryStore extends InMemorySharedPreferencesStore {
  _HistoryStore(super.data) : super.withData();

  String? _failKey;
  bool _throwOnFailure = false;
  String? _heldKey;
  Completer<void>? _writeStarted;
  Completer<void>? _release;
  int historyWriteCount = 0;
  int limitWriteCount = 0;

  Completer<void> get writeStarted => _writeStarted!;

  void failNext(String key, {required bool throws}) {
    _failKey = key;
    _throwOnFailure = throws;
  }

  void holdNextWrite(String key) {
    _heldKey = key;
    _writeStarted = Completer<void>();
    _release = Completer<void>();
  }

  void releaseHeldWrite() {
    final release = _release;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == _platformHistoryKey) historyWriteCount++;
    if (key == _platformLimitKey) limitWriteCount++;
    if (key == _heldKey) {
      _heldKey = null;
      _writeStarted!.complete();
      await _release!.future;
    }

    final saved = await super.setValue(valueType, key, value);
    if (key == _failKey) {
      _failKey = null;
      if (_throwOnFailure) {
        throw StateError('injected notification history write failure');
      }
      return false;
    }
    return saved;
  }
}

Map<String, Object> _seededStorage([List<NotificationItem>? historyItems]) =>
    <String, Object>{
      _platformLimitKey: 500,
      _platformHistoryKey: (historyItems ?? _initialIds.map(_item))
          .map((item) => jsonEncode(item.toJson()))
          .toList(growable: false),
    };

NotificationItem _item(String id) {
  final sequence = int.tryParse(id.split('-').last) ?? 1000;
  return NotificationItem(
    id: id,
    title: id,
    body: 'Synthetic notification $id',
    scheduledTime: DateTime.utc(2026, 10, 1).add(Duration(minutes: sequence)),
    type: NotificationType.general,
  );
}
