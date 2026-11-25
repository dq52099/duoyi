import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/backup_screen.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('priority shared import dialog screenshots', (tester) async {
    final directory =
        Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
    if (directory == null || directory.isEmpty) return;
    final previousDisableShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await tester.runAsync(loadWidgetPolishScreenshotFonts);
      for (final brand in [AppBrands.defaultBrand, AppBrands.liquidGlass]) {
        for (final locale in AppLocale.values) {
          for (final size in [const Size(320, 844), const Size(568, 320)]) {
            final key = GlobalKey();
            await _pump(
              tester,
              const BackupScreen(initialMode: BackupEntryMode.restore),
              brand: brand,
              appLocale: locale,
              captureKey: key,
              size: size,
            );
            final merge = find.text(DataSettingsUiCopy.mergeImportButton);
            await _scrollUntilVisible(tester, merge);
            await tester.tap(merge);
            await tester.pumpAndSettle();
            final input = find.byType(TextField);
            await tester.enterText(
              input,
              '{"visual":"synthetic text; cancel only"}',
            );
            await tester.pumpAndSettle();
            expect(
              tester.widget<TextField>(input).focusNode?.hasFocus ??
                  tester
                      .widget<EditableText>(find.byType(EditableText))
                      .focusNode
                      .hasFocus,
              isTrue,
            );
            final fieldTheme = Theme.of(tester.element(input));
            expect(
              (fieldTheme.inputDecorationTheme.focusedBorder!
                      as OutlineInputBorder)
                  .borderRadius,
              BorderRadius.circular(12),
            );
            final confirm = find.widgetWithText(
              FilledButton,
              DataSettingsUiCopy.confirmImport,
            );
            await tester.ensureVisible(confirm);
            await tester.pumpAndSettle();
            expect(confirm.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              image.dispose();
              final file = File(
                '$directory/${brand.id}-import-dialog-${locale.name}-${size.width.toInt()}.png',
              );
              file.parent.createSync(recursive: true);
              file.writeAsBytesSync(bytes!.buffer.asUint8List());
            });
            await _cancelAndInspectExit(tester);
            final prefs = await SharedPreferences.getInstance();
            expect(prefs.getString('user_profile'), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
        }
      }
    } finally {
      debugDisableShadows = previousDisableShadows;
    }
  });

  testWidgets('old import confirmation cannot write to the next account', (
    tester,
  ) async {
    await _pump(
      tester,
      const BackupScreen(initialMode: BackupEntryMode.restore),
    );
    final merge = find.text(DataSettingsUiCopy.mergeImportButton);
    await _scrollUntilVisible(tester, merge);
    await tester.tap(merge);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '{"app":"duoyi","schema":1,"data":{"user_profile":{"type":"string","value":"stale import"}}}',
    );
    expect(
      find.widgetWithText(FilledButton, DataSettingsUiCopy.confirmImport),
      findsOneWidget,
    );
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile', 'new account profile');
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(
      FilledButton,
      DataSettingsUiCopy.confirmImport,
    );
    if (confirm.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(confirm).onPressed != null) {
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
    }
    expect(prefs.getString('user_profile'), 'new account profile');
    expect(find.text(DataSettingsUiCopy.importSuccess(true, 1)), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('old WebDAV configuration cannot save after account switch', (
    tester,
  ) async {
    await _pump(
      tester,
      const BackupScreen(initialMode: BackupEntryMode.restore),
    );
    final configure = find.text(
      DataSettingsUiCopy.webDavConfigureButton(false),
    );
    await _scrollUntilVisible(tester, configure);
    await tester.tap(configure);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(
      fields.at(0),
      'https://dav.example.test/old-account',
    );
    await tester.enterText(fields.at(1), 'synthetic-old-user');
    await tester.enterText(fields.at(2), 'synthetic-old-password');
    expect(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(FilledButton, I18n.tr('action.save')),
      ),
      findsOneWidget,
    );
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    await tester.pumpAndSettle();
    final save = find.descendant(
      of: find.byType(AppDialog),
      matching: find.widgetWithText(FilledButton, I18n.tr('action.save')),
    );
    if (save.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(save).onPressed != null) {
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('webdav_backup_base_url'), isNull);
    expect(prefs.getString('webdav_backup_username'), isNull);
    expect(prefs.getString('webdav_backup_password'), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

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

      final screenState = tester.state(find.byType(BackupScreen));
      const pasted = '{"regression":"keep this text"}';
      final input = find.byType(TextField);
      await tester.enterText(input, pasted);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(BackupScreen)), same(screenState));
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

Future<_Fixture> _pump(
  WidgetTester tester,
  Widget screen, {
  AppBrand? brand,
  AppLocale appLocale = AppLocale.zh,
  GlobalKey? captureKey,
  Size size = const Size(320, 844),
}) async {
  SharedPreferences.setMockInitialValues({
    if (brand != null) 'active_brand': brand.id,
  });
  I18n.setLocale(appLocale);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final theme = ThemeProvider();
  final todos = TodoProvider();
  await theme.loadFromStorage();
  final locale = LocaleProvider();
  await locale.setLocale(appLocale);
  final auth = AuthProvider();
  final achievements = AchievementProvider();
  final preferences = PreferencesProvider();
  final notifications = NotificationService();
  final calendar = CalendarSyncProvider();
  final locations = LocationReminderProvider();
  for (final provider in [
    theme,
    todos,
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

  final originalTheme = theme.brand.theme;
  final baseTheme = captureKey == null
      ? originalTheme
      : originalTheme.copyWith(
          textTheme: originalTheme.textTheme.apply(
            fontFamily: 'DuoyiScreenshotLatin',
            fontFamilyFallback: const ['DuoyiScreenshot'],
          ),
          appBarTheme: originalTheme.appBarTheme.copyWith(
            titleTextStyle: originalTheme.appBarTheme.titleTextStyle?.copyWith(
              fontFamily: 'DuoyiScreenshotLatin',
              fontFamilyFallback: const ['DuoyiScreenshot'],
            ),
          ),
        );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<TodoProvider>.value(value: todos),
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
          child: captureKey == null
              ? child!
              : RepaintBoundary(key: captureKey, child: child!),
        ),
        home: BrandRouteSurface(child: screen),
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
