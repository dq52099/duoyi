import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

enum _Page { backup, restore, themes, integrations, history }

void main() {
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
}

Future<GlobalKey> _pump(
  WidgetTester tester,
  _Page page,
  AppLocale locale,
  bool dark,
) async {
  SharedPreferences.setMockInitialValues({
    'active_brand': dark ? 'starRail' : 'defaultBrand',
  });
  I18n.setLocale(locale);
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final theme = ThemeProvider();
  await theme.loadFromStorage();
  final localeProvider = LocaleProvider();
  await localeProvider.setLocale(locale);
  final auth = AuthProvider();
  final rewards = AchievementProvider();
  final preferences = PreferencesProvider();
  final notification = NotificationService();
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
  final baseTheme = theme.brand.theme;
  final fonts = baseTheme.textTheme.apply(
    fontFamily: 'DuoyiScreenshotLatin',
    fontFamilyFallback: const ['DuoyiScreenshot'],
  );
  final key = GlobalKey();
  final screen = switch (page) {
    _Page.backup => const BackupScreen(),
    _Page.restore => const BackupScreen(initialMode: BackupEntryMode.restore),
    _Page.themes => const ThemePickerScreen(),
    _Page.integrations => const IntegrationsScreen(),
    _Page.history => const NotificationHistoryScreen(),
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
      child: MaterialApp(
        theme: baseTheme.copyWith(textTheme: fonts, primaryTextTheme: fonts),
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
  return key;
}

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
  if (Platform.environment['DUOYI_CAPTURE_DATA_SETTINGS_SCREENSHOTS'] != '1') {
    return;
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    try {
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'evidence/screenshots/data-settings-locale-20261007/$name.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}
