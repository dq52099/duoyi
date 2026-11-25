import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/settings_ui_copy.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/preferences_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

enum _Destination {
  date,
  defaults,
  interaction;

  String get label => switch (this) {
    date => SettingsUiCopy.jumpToDate,
    defaults => SettingsUiCopy.jumpToDefaults,
    interaction => SettingsUiCopy.jumpToInteraction,
  };

  String get heading => I18n.tr(switch (this) {
    date => 'preferences.section.date',
    defaults => 'preferences.section.defaults',
    interaction => 'preferences.section.interaction',
  });
}

void main() {
  setUp(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });

  for (final locale in AppLocale.values) {
    for (final destination in _Destination.values) {
      testWidgets(
        'initial shortcut reaches ${destination.name} at 320x540 / 2x ${locale.name}',
        (tester) async {
          final fixture = await _Fixture.create(tester, locale: locale);
          final chip = find.widgetWithText(ActionChip, destination.label);
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          await fixture.capture(
            tester,
            '${locale.name}-${destination.name}-menu',
          );
          await tester.tap(chip);
          await tester.pumpAndSettle();
          expect(find.text(destination.heading).hitTestable(), findsOneWidget);
          expect(fixture.position.pixels, greaterThan(0));
          expect(tester.takeException(), isNull);
          await fixture.capture(
            tester,
            '${locale.name}-${destination.name}-target',
          );
        },
      );
    }
  }

  testWidgets('covered route rejects a retained shortcut and returns usable', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    final callback = fixture.callback(_Destination.date);
    final position = fixture.position;
    final before = position.pixels;
    fixture.navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Covering route')),
      ),
    );
    await tester.pumpAndSettle();
    callback();
    await tester.pumpAndSettle();
    expect(position.pixels, before);
    fixture.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(ActionChip, _Destination.date.label),
    );
    await tester.pumpAndSettle();
    fixture.callback(_Destination.date)();
    await tester.pumpAndSettle();
    expect(find.text(_Destination.date.heading).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final invalidation in [
    'account',
    'preferences reset',
    'lock',
    'update',
  ]) {
    testWidgets('retained shortcut rejects $invalidation', (tester) async {
      final fixture = await _Fixture.create(tester);
      final callback = fixture.callback(_Destination.date);
      final position = fixture.position;
      final before = position.pixels;
      switch (invalidation) {
        case 'account':
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          break;
        case 'preferences reset':
          fixture.preferences.resetLocalState();
          break;
        case 'lock':
          await tester.runAsync(() => fixture.lock.setPin('2468'));
          fixture.lock.lock();
          break;
        case 'update':
          fixture.update.requireUpdate();
          break;
      }
      await tester.pump();
      callback();
      await tester.pumpAndSettle();
      expect(position.pixels, before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'last shortcut cancels an animation even at its current position',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      final date = fixture.callback(_Destination.date);
      final interaction = fixture.callback(_Destination.interaction);
      date();
      await tester.pumpAndSettle();
      final before = fixture.position.pixels;
      interaction();
      date();
      await tester.pumpAndSettle();
      expect(fixture.position.pixels, closeTo(before, 0.01));
      expect(
        find.text(_Destination.date.heading).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manual scrolling cancels a shortcut without a delayed return', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    fixture.callback(_Destination.interaction)();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.drag(find.byType(Scrollable), const Offset(0, 120));
    await tester.pumpAndSettle();
    final stopped = fixture.position.pixels;
    await tester.pump(const Duration(milliseconds: 500));
    expect(fixture.position.pixels, closeTo(stopped, 0.01));
    expect(
      find.text(_Destination.interaction.heading).hitTestable(),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion reaches a shortcut in the next frame', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester, disableAnimations: true);
    fixture.callback(_Destination.interaction)();
    await tester.pump();
    expect(fixture.position.isScrollingNotifier.value, isFalse);
    expect(
      find.text(_Destination.interaction.heading).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing language preserves position and fresh shortcuts work', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    fixture.callback(_Destination.defaults)();
    await tester.pumpAndSettle();
    final before = fixture.position.pixels;
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(fixture.position.pixels, closeTo(before, 0.01));
    fixture.callback(_Destination.interaction)();
    await tester.pumpAndSettle();
    expect(
      find.text(_Destination.interaction.heading).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a disposed page ignores its retained shortcut', (tester) async {
    final fixture = await _Fixture.create(tester);
    final callback = fixture.callback(_Destination.date);
    await tester.pumpWidget(const SizedBox.shrink());
    callback();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS primary scroll position supports status bar tap to top', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester, platform: TargetPlatform.iOS);
    fixture.callback(_Destination.interaction)();
    await tester.pumpAndSettle();
    expect(fixture.position.pixels, greaterThan(0));
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
    final primary = PrimaryScrollController.of(scaffold.context);
    expect(primary.positions, contains(fixture.position));
    scaffold.handleStatusBarTap();
    await tester.pumpAndSettle();
    expect(fixture.position.pixels, closeTo(0, 0.01));
    expect(tester.takeException(), isNull);
  });
}

class _Fixture {
  final preferences = PreferencesProvider();
  final theme = ThemeProvider();
  final auth = AuthProvider(
    initialState: const AuthState(
      userId: 'shortcut-user',
      token: 'fixture-token',
    ),
  );
  final lock = AppLockProvider();
  final update = _TestUpdateService();
  final navigatorKey = GlobalKey<NavigatorState>();
  final captureKey = GlobalKey();

  VoidCallback callback(_Destination destination) =>
      testerChip(destination).onPressed!;

  ActionChip testerChip(_Destination destination) =>
      find
              .widgetWithText(ActionChip, destination.label)
              .evaluate()
              .single
              .widget
          as ActionChip;

  ScrollPosition get position =>
      ((find.byType(Scrollable).evaluate().first as StatefulElement).state
              as ScrollableState)
          .position;

  static Future<_Fixture> create(
    WidgetTester tester, {
    AppLocale locale = AppLocale.zh,
    bool disableAnimations = false,
    TargetPlatform? platform,
  }) async {
    I18n.setLocale(locale);
    tester.view.physicalSize = const Size(320, 540);
    tester.view.devicePixelRatio = 1;
    if (platform == TargetPlatform.iOS) {
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24);
    }
    addTearDown(tester.view.reset);
    await tester.runAsync(loadWidgetPolishScreenshotFonts);
    final fixture = _Fixture();
    await fixture.theme.loadFromStorage();
    await fixture.preferences.loadFromStorage();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.preferences.dispose();
      fixture.theme.dispose();
      fixture.auth.dispose();
      fixture.lock.dispose();
      fixture.update.dispose();
    });
    final theme = fixture.theme.brand.theme;
    final fonts = theme.textTheme.apply(
      fontFamily: 'DuoyiScreenshotLatin',
      fontFamilyFallback: const ['DuoyiScreenshot'],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: fixture.preferences),
          ChangeNotifierProvider.value(value: fixture.theme),
          ChangeNotifierProvider.value(value: fixture.auth),
          ChangeNotifierProvider.value(value: fixture.lock),
          ChangeNotifierProvider<AppUpdateService>.value(value: fixture.update),
        ],
        child: MaterialApp(
          navigatorKey: fixture.navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: fonts,
            primaryTextTheme: fonts,
            platform: platform,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: disableAnimations,
            ),
            child: RepaintBoundary(key: fixture.captureKey, child: child!),
          ),
          home: const PersonalizationSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return fixture;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory =
        Platform.environment['DUOYI_SETTINGS_SHORTCUT_SCREENSHOT_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('$directory/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
}

class _TestUpdateService extends AppUpdateService {
  _TestUpdateService() : super(repo: 'dq52099/duoyi', currentVersion: '1.0.0');

  void requireUpdate() {
    debugSetUpdatePolicyForTest(
      latestVersion: '2.0.0',
      minimumSupportedVersion: '2.0.0',
      forceUpdateRequired: true,
    );
    notifyListeners();
  }
}
