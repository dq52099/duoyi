import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/backup_screen.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'backup import keeps pasted text on locale change and cancels safely',
    (tester) async {
      await _pump(
        tester,
        const BackupScreen(initialMode: BackupEntryMode.restore),
      );

      final mergeButton = find.text(DataSettingsUiCopy.mergeImportButton);
      await _scrollUntilVisible(tester, mergeButton);
      await tester.tap(mergeButton);
      await tester.pumpAndSettle();
      expect(
        _dialogText(DataSettingsUiCopy.importDialogTitle(true)),
        findsOneWidget,
      );

      const pasted = '{"regression":"keep this text"}';
      final input = find.byType(TextField);
      await tester.enterText(input, pasted);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(_dialogText('Merge Import'), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, pasted);

      await _cancelAndInspectExit(tester);
      await _scrollUntilVisible(
        tester,
        find.text(DataSettingsUiCopy.mergeImportButton),
      );
      await tester.tap(find.text(DataSettingsUiCopy.mergeImportButton));
      await tester.pumpAndSettle();
      expect(_dialogText('Merge Import'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      await _cancelAndInspectExit(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'WebDAV configuration keeps fields on locale change and cancels safely',
    (tester) async {
      await _pump(
        tester,
        const BackupScreen(initialMode: BackupEntryMode.restore),
      );

      final configureButton = find.text(
        DataSettingsUiCopy.webDavConfigureButton(false),
      );
      await _scrollUntilVisible(tester, configureButton);
      await tester.tap(configureButton);
      await tester.pumpAndSettle();
      expect(_dialogText(DataSettingsUiCopy.webDavDialogTitle), findsOneWidget);

      final fields = find.byType(TextField);
      const url = 'https://dav.example.test/user/files';
      const username = 'fixture-user';
      await tester.enterText(fields.at(0), url);
      await tester.enterText(fields.at(1), username);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(_dialogText('WebDAV Cloud Backup'), findsOneWidget);
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, url);
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, username);
      expect(
        tester.widget<TextField>(fields.at(1)).decoration!.labelText,
        DataSettingsUiCopy.webDavUsername,
      );

      await _cancelAndInspectExit(tester);
      await _scrollUntilVisible(
        tester,
        find.text(DataSettingsUiCopy.webDavConfigureButton(false)),
      );
      await tester.tap(
        find.text(DataSettingsUiCopy.webDavConfigureButton(false)),
      );
      await tester.pumpAndSettle();
      expect(_dialogText('WebDAV Cloud Backup'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(5));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '',
      );
      await _cancelAndInspectExit(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ICS add keeps name and URL on locale change and cancels safely',
    (tester) async {
      final fixture = await _pump(tester, const IntegrationsScreen());

      await tester.tap(find.byTooltip(NotificationUiCopy.addIcsTooltip));
      await tester.pumpAndSettle();
      expect(
        _dialogText(NotificationUiCopy.addSubscriptionDialogTitle),
        findsOneWidget,
      );

      final fields = find.byType(TextField);
      const name = 'Team calendar';
      const url = 'https://calendar.example.test/team.ics';
      await tester.enterText(fields.at(0), name);
      await tester.enterText(fields.at(1), url);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(_dialogText('Add Calendar Subscription'), findsOneWidget);
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, name);
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, url);
      expect(
        tester.widget<TextField>(fields.at(0)).decoration!.labelText,
        NotificationUiCopy.subscriptionNameLabel,
      );

      await _cancelAndInspectExit(tester);
      expect(fixture.calendar.subscriptions, isEmpty);
      await tester.tap(find.byTooltip(NotificationUiCopy.addIcsTooltip));
      await tester.pumpAndSettle();
      expect(_dialogText('Add Calendar Subscription'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        '',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        '',
      );
      await _cancelAndInspectExit(tester);
      expect(fixture.calendar.subscriptions, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_Fixture> _pump(WidgetTester tester, Widget screen) async {
  SharedPreferences.setMockInitialValues({});
  I18n.setLocale(AppLocale.zh);
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final theme = ThemeProvider();
  await theme.loadFromStorage();
  final locale = LocaleProvider();
  await locale.setLocale(AppLocale.zh);
  final auth = AuthProvider();
  final achievements = AchievementProvider();
  final preferences = PreferencesProvider();
  final notifications = NotificationService();
  final calendar = CalendarSyncProvider();
  final locations = LocationReminderProvider();
  for (final provider in [
    theme,
    locale,
    auth,
    achievements,
    preferences,
    notifications,
    calendar,
    locations,
  ]) {
    addTearDown(provider.dispose);
  }

  final baseTheme = theme.brand.theme;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AchievementProvider>.value(value: achievements),
        ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
        ChangeNotifierProvider<NotificationService>.value(value: notifications),
        ChangeNotifierProvider<CalendarSyncProvider>.value(value: calendar),
        ChangeNotifierProvider<LocationReminderProvider>.value(
          value: locations,
        ),
      ],
      child: MaterialApp(
        theme: baseTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return _Fixture(calendar);
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(target, 300, scrollable: scrollable);
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

Finder _dialogText(String value) =>
    find.descendant(of: find.byType(AppDialog), matching: find.text(value));

Future<void> _cancelAndInspectExit(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppDialog),
      matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
    ),
  );
  // Check each portion of the route transition while its dialog fields may
  // still be mounted, since the showDialog future completes at the start of
  // the reverse animation.
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  }
  await tester.pumpAndSettle();
  expect(find.byType(AppDialog), findsNothing);
  expect(tester.takeException(), isNull);
}

class _Fixture {
  final CalendarSyncProvider calendar;

  const _Fixture(this.calendar);
}
