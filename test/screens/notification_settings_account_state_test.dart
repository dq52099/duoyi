import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/notification_history_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/alarm_service.dart';
import 'package:duoyi/services/local_notifications.dart';
import 'package:duoyi/services/reminder_issue_copy.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
    final oldTimezone = LocalTimezoneResolver.debugSystemTimeZoneReader;
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
      LocalTimezoneResolver.debugSystemTimeZoneReader = oldTimezone;
      if (oldPlugin != null) {
        FlutterLocalNotificationsPlatform.instance = oldPlugin;
      }
      I18n.setLocale(AppLocale.zh);
    });
  });

  for (final transition in [
    'overlap',
    'same account',
    'new account',
    'cleanup',
  ]) {
    testWidgets('status refresh discards an old snapshot after $transition', (
      tester,
    ) async {
      final fixture = await _pump(tester, gateSnapshot: true);
      await tester.pump(const Duration(milliseconds: 50));
      expect(fixture.scheduler.loads, 1);
      if (transition == 'overlap') {
        unawaited(
          tester
              .widget<RefreshIndicator>(find.byType(RefreshIndicator))
              .onRefresh(),
        );
      } else if (transition == 'cleanup') {
        fixture.auth.beginTransition();
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        fixture.auth.settle('A');
      } else {
        fixture.auth.beginTransition();
        fixture.auth.settle(transition == 'new account' ? 'B' : 'A');
      }
      await tester.pumpAndSettle();
      expect(fixture.scheduler.loads, 2);
      await _show(
        tester,
        find.byKey(const ValueKey('notification_registered_reminders_tile')),
      );
      expect(find.textContaining('2 条登记'), findsOneWidget);
      fixture.scheduler.oldSnapshot.complete(_entries(1));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 条登记'), findsOneWidget);
      expect(find.textContaining('1 条登记'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('local cleanup refreshes status without an auth notification', (
    tester,
  ) async {
    final fixture = await _pump(tester, gateSnapshot: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(fixture.scheduler.loads, 1);
    // The platform probes use the real event loop; keep cleanup in that loop
    // instead of awaiting a fake-async completer after the last rendered frame.
    await tester.runAsync(() async {
      await AccountPreferenceWrites.boundary(() async {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(fixture.scheduler.loads, 1);
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(fixture.scheduler.loads, 2);
    await _show(
      tester,
      find.byKey(const ValueKey('notification_registered_reminders_tile')),
    );
    expect(find.textContaining('2 条登记'), findsOneWidget);
    fixture.scheduler.oldSnapshot.complete(_entries(1));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 条登记'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'account switch frees a new daily toggle during old permissions',
    (tester) async {
      final fixture = await _pump(tester, gateReadiness: true);
      await tester.pumpAndSettle();
      final toggle = find.byKey(
        const ValueKey('daily_reminder_slot_0_enabled_switch'),
      );
      await _show(tester, toggle);
      final oldTile = tester.element(toggle);
      final nativeSwitch = find.descendant(
        of: toggle,
        matching: find.byType(Switch),
      );
      await tester.tap(toggle);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<Switch>(nativeSwitch).onChanged, isNull);
      fixture.auth.beginTransition();
      fixture.auth.settle('B');
      await tester.pumpAndSettle();
      await _show(tester, toggle);
      expect(oldTile.mounted, isFalse);
      expect(tester.widget<Switch>(nativeSwitch).onChanged, isNotNull);
      fixture.notifications.readiness.complete(true);
      await tester.pumpAndSettle();
      expect(fixture.preferences.dailyReminderSlots[0].enabled, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('brand route keeps an in-flight status refresh across locales', (
    tester,
  ) async {
    final fixture = await _pump(tester, gateSnapshot: true);
    await tester.pump(const Duration(milliseconds: 50));
    final screenState = tester.state(find.byType(NotificationSettingsScreen));
    expect(fixture.scheduler.loads, 1);
    for (final locale in [AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(locale);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester.state(find.byType(NotificationSettingsScreen)),
        same(screenState),
      );
      expect(fixture.scheduler.loads, 1);
    }
    fixture.scheduler.oldSnapshot.complete(_entries(1));
    await tester.pumpAndSettle();
    await _show(
      tester,
      find.byKey(const ValueKey('notification_registered_reminders_tile')),
    );
    expect(find.textContaining('1 条登记'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposed settings ignores a late snapshot failure', (
    tester,
  ) async {
    final fixture = await _pump(tester, gateSnapshot: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(fixture.scheduler.loads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.scheduler.oldSnapshot.completeError(
      StateError('synthetic late snapshot failure'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final kind in ['daily', 'monthly']) {
    testWidgets('$kind picker cannot save after an account transition', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      await tester.pumpAndSettle();
      final timeKey = kind == 'daily'
          ? 'daily_reminder_slot_0_time_button'
          : 'report_reminder_time_button_monthly';
      if (kind == 'monthly') {
        final title = find.byKey(
          const ValueKey('report_reminder_monthly_header_title'),
        );
        await _show(tester, title);
        await tester.tap(title);
        await tester.pumpAndSettle();
      }
      await _show(tester, find.byKey(ValueKey(timeKey)));
      await tester.tap(find.byKey(ValueKey(timeKey)));
      await tester.pumpAndSettle();
      final wheels = tester
          .widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
          .toList();
      (wheels.first.controller! as FixedExtentScrollController).jumpToItem(22);
      await tester.pumpAndSettle();
      fixture.auth.beginTransition();
      fixture.auth.settle('B');
      if (kind == 'daily') {
        await fixture.preferences.setDailyReminderSlot(
          0,
          fixture.preferences.dailyReminderSlots[0].copyWith(
            hour: 6,
            minute: 15,
          ),
        );
      } else {
        await fixture.preferences.setMonthlyReportReminderConfig(
          fixture.preferences.monthlyReportReminderConfig.copyWith(
            hour: 6,
            minute: 15,
          ),
        );
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(I18n.tr('action.confirm')));
      await tester.tap(find.text(I18n.tr('action.confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(ListWheelScrollView), findsNothing);
      final hour = kind == 'daily'
          ? fixture.preferences.dailyReminderSlots[0].hour
          : fixture.preferences.monthlyReportReminderConfig.hour;
      final minute = kind == 'daily'
          ? fixture.preferences.dailyReminderSlots[0].minute
          : fixture.preferences.monthlyReportReminderConfig.minute;
      expect(hour, 6);
      expect(minute, 15);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'daily permission result cannot enable a reminder after returning to the same account',
    (tester) async {
      final fixture = await _pump(tester, gateReadiness: true);
      await tester.pumpAndSettle();
      final toggle = find.byKey(
        const ValueKey('daily_reminder_slot_0_enabled_switch'),
      );
      await _show(tester, toggle);
      await tester.tap(toggle);
      await tester.pump(const Duration(milliseconds: 50));
      expect(fixture.notifications.readinessRequests, 1);
      fixture.auth.beginTransition();
      fixture.auth.settle('A');
      fixture.notifications.readiness.complete(true);
      await tester.pumpAndSettle();
      expect(fixture.preferences.dailyReminderSlots[0].enabled, isFalse);
      expect(find.text(NotificationUiCopy.dailySaveFailed), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<_Fixture> _pump(
  WidgetTester tester, {
  bool gateSnapshot = false,
  bool gateReadiness = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await LocalNotifications.instance.init();
      await AlarmService.instance.init();
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });
  final fixture = _Fixture(gateSnapshot, gateReadiness);
  addTearDown(fixture.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: fixture.auth),
        ChangeNotifierProvider<NotificationService>.value(
          value: fixture.notifications,
        ),
        ChangeNotifierProvider<PreferencesProvider>.value(
          value: fixture.preferences,
        ),
        Provider<ReminderScheduler>.value(value: fixture.scheduler),
      ],
      child: const MaterialApp(
        home: BrandRouteSurface(child: NotificationSettingsScreen()),
      ),
    ),
  );
  return fixture;
}

Future<void> _show(WidgetTester tester, Finder item) async {
  if (item.evaluate().isNotEmpty) {
    await Scrollable.ensureVisible(tester.element(item), alignment: 0.25);
    await tester.pumpAndSettle();
    return;
  }
  final scrollable = find
      .descendant(
        of: find.byKey(const ValueKey('notification_settings_scroll_view')),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    item,
    300,
    scrollable: scrollable,
    maxScrolls: 40,
  );
  await Scrollable.ensureVisible(tester.element(item), alignment: 0.25);
  await tester.pumpAndSettle();
}

class _Fixture {
  final auth = _BoundaryAuth();
  final preferences = PreferencesProvider();
  late final _ReadyNotifications notifications;
  late final _SnapshotScheduler scheduler;
  _Fixture(bool gateSnapshot, bool gateReadiness) {
    notifications = _ReadyNotifications(gateReadiness);
    scheduler = _SnapshotScheduler(notifications, gateSnapshot);
  }
  void dispose() {
    auth.dispose();
    preferences.dispose();
    notifications.dispose();
  }
}

class _BoundaryAuth extends AuthProvider {
  AuthState _fixtureState = const AuthState(userId: 'A', token: 'synthetic-A');
  bool _transitioning = false;
  @override
  AuthState get state => _fixtureState;
  @override
  bool get isAccountTransitionInProgress => _transitioning;
  void beginTransition() {
    _transitioning = true;
    notifyListeners();
  }

  void settle(String user) {
    _fixtureState = AuthState(userId: user, token: 'synthetic-$user');
    _transitioning = false;
    notifyListeners();
  }
}

class _ReadyNotifications extends NotificationService {
  final bool gateReadiness;
  final readiness = Completer<bool>();
  int readinessRequests = 0;
  _ReadyNotifications(this.gateReadiness);
  @override
  Future<bool> refreshPermission() async => true;
  @override
  Future<bool> ensureReadyForReminder({
    DateTime? scheduledTime,
    String? issueTitle,
    NotificationIssueTitle? issueTitleCode,
    String? relatedId,
    bool Function()? canContinue,
  }) {
    readinessRequests++;
    return gateReadiness ? readiness.future : Future.value(true);
  }
}

class _SnapshotScheduler extends ReminderScheduler {
  final bool gateSnapshot;
  final oldSnapshot = Completer<List<ReminderScheduleSnapshotEntry>>();
  int loads = 0;
  _SnapshotScheduler(super.notifications, this.gateSnapshot);
  @override
  Future<List<ReminderScheduleSnapshotEntry>> registeredRemindersSnapshot() {
    loads++;
    return gateSnapshot && loads == 1
        ? oldSnapshot.future
        : Future.value(_entries(2));
  }
}

List<ReminderScheduleSnapshotEntry> _entries(int count) => [
  for (var i = 0; i < count; i++)
    ReminderScheduleSnapshotEntry(
      objectType: 'todo',
      objectId: 'synthetic-$i',
      ids: [9950 + i],
      title: 'Synthetic task $i',
      subtitle: '',
    ),
];
