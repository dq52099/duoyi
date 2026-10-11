import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/theme_picker_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final background in [true, false]) {
    testWidgets(
      'widget ${background ? 'background' : 'skin'} save failure shows localized feedback',
      (tester) async {
        final auth = _ShopAuth(loggedIn: false);
        final theme = _ShopTheme()..failWidgetSave = true;
        final rewards = _ShopRewards();
        await _mount(tester, auth, theme, rewards);
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        final option = find.text(
          background
              ? DataSettingsUiCopy.widgetFollowCurrentTheme
              : DataSettingsUiCopy.widgetFollowCardSkin,
        );
        await tester.scrollUntilVisible(
          option,
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(find.text(DataSettingsUiCopy.themeSaveFailed), findsOneWidget);
        expect(find.text(DataSettingsUiCopy.unlockThemeFirst), findsNothing);
        expect(find.text(DataSettingsUiCopy.unlockCardSkinFirst), findsNothing);
        expect(theme.widgetSaveCalls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
        theme.dispose();
        rewards.dispose();
      },
    );
  }

  testWidgets(
    'old widget save failure does not show feedback for the next account',
    (tester) async {
      final auth = _ShopAuth(loggedIn: false);
      final theme = _ShopTheme()
        ..failWidgetSave = true
        ..widgetSaveGate = Completer<void>();
      final rewards = _ShopRewards();
      await _mount(tester, auth, theme, rewards);
      final option = find.text(DataSettingsUiCopy.widgetFollowCurrentTheme);
      await tester.scrollUntilVisible(
        option,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(theme.widgetSaveCalls, 1);
      auth.switchAccount();
      theme.widgetSaveGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      theme.dispose();
      rewards.dispose();
    },
  );

  testWidgets(
    'account switch during theme snapshot skips old rewards and feedback',
    (tester) async {
      final auth = _ShopAuth(loggedIn: true);
      final theme = _ShopTheme()..snapshotGate = Completer<void>();
      final rewards = _ShopRewards();
      await _mount(tester, auth, theme, rewards);
      await tester.tap(find.text('从零开始'));
      await tester.pumpAndSettle();
      expect(theme.snapshotCalls, 1);

      auth.switchAccount();
      theme.snapshotGate!.complete();
      await tester.pumpAndSettle();
      expect(rewards.snapshotCalls, 0);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      theme.dispose();
      rewards.dispose();
    },
  );

  testWidgets(
    'guest unlock completion cannot enable a theme for the next account',
    (tester) async {
      final auth = _ShopAuth(loggedIn: false);
      final theme = _ShopTheme()..unlockGate = Completer<void>();
      final rewards = _ShopRewards();
      await _mount(tester, auth, theme, rewards);
      await tester.tap(find.text('从零开始'));
      await tester.pumpAndSettle();
      expect(rewards.spendCalls, 1);
      expect(theme.unlockCalls, 1);

      auth.switchAccount();
      theme.unlockGate!.complete();
      await tester.pumpAndSettle();
      expect(theme.setBrandCalls, 0);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      theme.dispose();
      rewards.dispose();
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  AuthProvider auth,
  ThemeProvider theme,
  AchievementProvider rewards,
) async {
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AchievementProvider>.value(value: rewards),
      ],
      child: const MaterialApp(home: ThemePickerScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _ShopAuth extends AuthProvider {
  _ShopAuth({required bool loggedIn})
    : _fixtureState = loggedIn
          ? const AuthState(userId: 'A', token: 'token-A', coinBalance: 1000)
          : const AuthState();
  AuthState _fixtureState;
  @override
  AuthState get state => _fixtureState;
  @override
  Future<Map<String, dynamic>> applyThemeShopItem({
    required String itemType,
    required String itemId,
    required String title,
  }) async => {
    'theme_shop_state': <String, dynamic>{},
    'virtual_rewards': <String, dynamic>{'coin_balance': 1000},
  };
  void switchAccount() {
    _fixtureState = const AuthState(userId: 'B', token: 'token-B');
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    notifyListeners();
  }
}

class _ShopTheme extends ThemeProvider {
  int snapshotCalls = 0;
  int unlockCalls = 0;
  int setBrandCalls = 0;
  Completer<void>? snapshotGate;
  Completer<void>? unlockGate;
  Completer<void>? widgetSaveGate;
  bool failWidgetSave = false;
  int widgetSaveCalls = 0;

  Future<bool> _saveWidgetChoice() async {
    widgetSaveCalls++;
    if (widgetSaveGate != null) await widgetSaveGate!.future;
    if (failWidgetSave) throw StateError('Controlled persistence failure');
    return true;
  }

  @override
  Future<bool> setWidgetBackgroundBrand(String id) => _saveWidgetChoice();
  @override
  Future<bool> setWidgetCardSkin(String id) => _saveWidgetChoice();
  @override
  Future<void> applyShopStateFromServer(
    Map<dynamic, dynamic> state, {
    bool trusted = false,
  }) async {
    snapshotCalls++;
    if (snapshotGate != null) await snapshotGate!.future;
  }

  @override
  Future<void> unlockBrand(String id) async {
    unlockCalls++;
    if (unlockGate != null) await unlockGate!.future;
  }

  @override
  Future<bool> setBrand(String id) async {
    setBrandCalls++;
    return true;
  }
}

class _ShopRewards extends AchievementProvider {
  int snapshotCalls = 0;
  int spendCalls = 0;
  @override
  int get coinBalance => 1000;
  @override
  Future<void> applyRewardsSnapshot(Map<dynamic, dynamic> rewards) async {
    snapshotCalls++;
  }

  @override
  Future<bool> spendCoins({
    required int coins,
    required String title,
    required String reason,
  }) async {
    spendCalls++;
    return true;
  }
}
