import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/theme_picker_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('priority widget theme choice paired screenshots', (
    tester,
  ) async {
    final directory =
        Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
    if (directory == null || directory.isEmpty) return;
    addTearDown(tester.view.reset);
    final previousDisableShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await tester.runAsync(loadWidgetPolishScreenshotFonts);
      for (final brand in [AppBrands.defaultBrand, AppBrands.liquidGlass]) {
        for (final locale in AppLocale.values) {
          I18n.setLocale(locale);
          SharedPreferences.setMockInitialValues({'active_brand': brand.id});
          final theme = ThemeProvider();
          await theme.loadFromStorage();
          expect(theme.brand.id, brand.id);
          final auth = _ShopAuth(loggedIn: false);
          final rewards = _ShopRewards();
          final base = brand.theme;
          final visualTheme = base.copyWith(
            textTheme: base.textTheme.apply(
              fontFamily: 'DuoyiScreenshotLatin',
              fontFamilyFallback: const ['DuoyiScreenshot'],
            ),
            appBarTheme: base.appBarTheme.copyWith(
              titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
                fontFamily: 'DuoyiScreenshotLatin',
                fontFamilyFallback: const ['DuoyiScreenshot'],
              ),
            ),
          );
          for (final width in [320.0, 1024.0]) {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            final key = GlobalKey();
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<AuthProvider>.value(value: auth),
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<AchievementProvider>.value(
                    value: rewards,
                  ),
                ],
                child: MaterialApp(
                  theme: visualTheme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(width == 320 ? 1.6 : 1),
                    ),
                    child: RepaintBoundary(key: key, child: child!),
                  ),
                  home: const BrandRouteSurface(child: ThemePickerScreen()),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final option = find.text(
              DataSettingsUiCopy.widgetFollowCurrentTheme,
            );
            await tester.scrollUntilVisible(
              option,
              500,
              scrollable: find.byType(Scrollable).first,
            );
            await Scrollable.ensureVisible(
              tester.element(option),
              alignment: 0.2,
            );
            await tester.pumpAndSettle();
            final selected = tester
                .widgetList<ChoiceChip>(find.byType(ChoiceChip))
                .where((chip) => chip.selected);
            expect(selected, isNotEmpty);
            for (final chip in selected) {
              expect(
                appContrastRatio(chip.selectedColor!, chip.labelStyle!.color!),
                greaterThanOrEqualTo(4.5),
              );
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '${brand.id}/${locale.name}/$width',
            );
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
                '$directory/${brand.id}-widget-theme-choices-${locale.name}-${width.toInt()}.png',
              );
              file.parent.createSync(recursive: true);
              file.writeAsBytesSync(bytes!.buffer.asUint8List());
            });
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
          auth.dispose();
          rewards.dispose();
          theme.dispose();
        }
      }
    } finally {
      debugDisableShadows = previousDisableShadows;
    }
  });

  for (final choice in [
    (
      background: true,
      id: 'follow_theme',
      zh: '跟随当前主题',
      en: 'Follow Current Theme',
    ),
    (background: true, id: 'defaultBrand', zh: '多仪', en: 'Duoyi'),
    (background: true, id: 'liquidGlass', zh: '液态玻璃', en: 'Liquid Glass'),
    (
      background: false,
      id: 'follow_card_skin',
      zh: '跟随卡片皮肤',
      en: 'Follow Card Skin',
    ),
    (background: false, id: 'plain_card', zh: '素净卡片', en: 'Plain Card'),
    (
      background: false,
      id: 'starlight_card',
      zh: '星光玻璃卡',
      en: 'Starlight Glass Card',
    ),
  ]) {
    testWidgets(
      'widget ${choice.id} feedback follows pending and mounted locale',
      (tester) async {
        final auth = _ShopAuth(loggedIn: false);
        final theme = _ShopTheme()..widgetSaveGate = Completer<void>();
        theme.extraUnlockedBrands.add('liquidGlass');
        theme.extraUnlockedSkins.add('starlight_card');
        final rewards = _ShopRewards();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          auth.dispose();
          theme.dispose();
          rewards.dispose();
        });
        await _mount(tester, auth, theme, rewards);
        final element = tester.element(find.byType(ThemePickerScreen));
        final option = find.widgetWithText(ChoiceChip, choice.zh);
        await tester.scrollUntilVisible(
          option,
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(option);
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(theme.savedWidgetChoices, [choice.id]);
        expect(find.byType(SnackBar), findsNothing);

        I18n.setLocale(AppLocale.en);
        await tester.pump();
        theme.widgetSaveGate!.complete();
        await tester.pumpAndSettle();
        final english = choice.background
            ? 'Widget background switched to ${choice.en}'
            : 'Widget card skin switched to ${choice.en}';
        final chinese = choice.background
            ? '小组件背景已切换为 ${choice.zh}'
            : '小组件卡片皮肤已切换为 ${choice.zh}';
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(english),
          ),
          findsOneWidget,
        );
        final snackbar = tester.element(find.byType(SnackBar));

        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(chinese),
          ),
          findsOneWidget,
        );
        expect(find.text(english), findsNothing);
        expect(tester.element(find.byType(SnackBar)), same(snackbar));
        expect(tester.element(find.byType(ThemePickerScreen)), same(element));
        expect(theme.widgetSaveCalls, 1);
        expect(theme.widgetBackgroundSaveCalls, choice.background ? 1 : 0);
        expect(theme.widgetSkinSaveCalls, choice.background ? 0 : 1);
        expect(theme.savedWidgetChoices, [choice.id]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final background in [true, false]) {
    for (final failed in [true, false]) {
      testWidgets(
        'widget ${background ? 'background' : 'skin'} ${failed ? 'error' : 'locked'} feedback follows mounted locale',
        (tester) async {
          final auth = _ShopAuth(loggedIn: false);
          final theme = _ShopTheme()
            ..widgetSaveGate = Completer<void>()
            ..failWidgetSave = failed
            ..widgetSaveResult = false;
          final rewards = _ShopRewards();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            auth.dispose();
            theme.dispose();
            rewards.dispose();
          });
          await _mount(tester, auth, theme, rewards);
          final element = tester.element(find.byType(ThemePickerScreen));
          final option = find.widgetWithText(
            ChoiceChip,
            background ? '跟随当前主题' : '跟随卡片皮肤',
          );
          await tester.scrollUntilVisible(
            option,
            500,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(option);
          await tester.pump();
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          I18n.setLocale(AppLocale.en);
          await tester.pump();
          theme.widgetSaveGate!.complete();
          await tester.pumpAndSettle();
          final english = failed
              ? DataSettingsUiCopy.themeSaveFailed
              : background
              ? DataSettingsUiCopy.unlockThemeFirst
              : DataSettingsUiCopy.unlockCardSkinFirst;
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.text(english),
            ),
            findsOneWidget,
          );
          final snackbar = tester.element(find.byType(SnackBar));
          I18n.setLocale(AppLocale.zh);
          await tester.pumpAndSettle();
          final chinese = failed
              ? DataSettingsUiCopy.themeSaveFailed
              : background
              ? DataSettingsUiCopy.unlockThemeFirst
              : DataSettingsUiCopy.unlockCardSkinFirst;
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.text(chinese),
            ),
            findsOneWidget,
          );
          expect(find.text(english), findsNothing);
          expect(tester.element(find.byType(SnackBar)), same(snackbar));
          expect(tester.element(find.byType(ThemePickerScreen)), same(element));
          expect(theme.widgetSaveCalls, 1);
          expect(theme.widgetBackgroundSaveCalls, background ? 1 : 0);
          expect(theme.widgetSkinSaveCalls, background ? 0 : 1);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'old widget ${background ? 'background' : 'skin'} success stays silent after account switch',
      (tester) async {
        final auth = _ShopAuth(loggedIn: false);
        final theme = _ShopTheme()..widgetSaveGate = Completer<void>();
        final rewards = _ShopRewards();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          auth.dispose();
          theme.dispose();
          rewards.dispose();
        });
        await _mount(tester, auth, theme, rewards);
        final option = find.widgetWithText(
          ChoiceChip,
          background ? '跟随当前主题' : '跟随卡片皮肤',
        );
        await tester.scrollUntilVisible(
          option,
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(option);
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        auth.switchAccount();
        I18n.setLocale(AppLocale.en);
        theme.widgetSaveGate!.complete();
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        expect(theme.widgetSaveCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );

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
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
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
    'guest transaction completion cannot enable a theme for the next account',
    (tester) async {
      final auth = _ShopAuth(loggedIn: false);
      final store = _HeldShopStore();
      SharedPreferencesStorePlatform.instance = store;
      final theme = ThemeProvider();
      final rewards = AchievementProvider();
      await rewards.applyRewardsSnapshot({'balance': 1000, 'lifetime': 1000});
      await _mount(tester, auth, theme, rewards);
      await tester.tap(find.text('从零开始'));
      await _waitForShopWrite(tester, store);
      expect(rewards.coinBalance, 860);

      auth.switchAccount();
      theme.resetLocalState();
      rewards.resetLocalState();
      store.release.complete();
      await tester.pumpAndSettle();
      expect(theme.isBrandUnlocked('re0'), isFalse);
      expect(rewards.coinBalance, 0);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      theme.dispose();
      rewards.dispose();
    },
  );

  for (final failure in [false, true]) {
    testWidgets('guest transaction survives locale switch, failure=$failure', (
      tester,
    ) async {
      final store = _HeldShopStore()..rejectHeldWrite = failure;
      SharedPreferencesStorePlatform.instance = store;
      final auth = _ShopAuth(loggedIn: false);
      final theme = ThemeProvider();
      final rewards = AchievementProvider();
      await rewards.applyRewardsSnapshot({'balance': 1000, 'lifetime': 1000});
      await _mount(tester, auth, theme, rewards);
      final element = tester.element(find.byType(ThemePickerScreen));
      final card = find
          .ancestor(
            of: find.text('从零开始'),
            matching: find.byType(AppSurfaceCard),
          )
          .first;
      final tap = tester.widget<AppSurfaceCard>(card).onTap!;
      tap();
      tap();
      await _waitForShopWrite(tester, store);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(tester.element(find.byType(ThemePickerScreen)), same(element));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        rewards.rewardLedger.where((entry) => entry.coins < 0),
        hasLength(1),
      );
      tap();
      store.release.complete();
      await tester.pumpAndSettle();
      expect(rewards.coinBalance, failure ? 1000 : 860);
      expect(theme.isBrandUnlocked('re0'), !failure);
      expect(theme.brand.id, failure ? 'defaultBrand' : 're0');
      expect(
        rewards.rewardLedger.where((entry) => entry.coins < 0),
        hasLength(failure ? 0 : 1),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        (jsonDecode(prefs.getString('duoyi_virtual_rewards')!)
            as Map)['balance'],
        rewards.coinBalance,
      );
      if (failure) {
        expect(find.text(DataSettingsUiCopy.themeSaveFailed), findsOneWidget);
      }
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      theme.dispose();
      rewards.dispose();
    });
  }

  testWidgets('guest transaction completes after its view is dismissed', (
    tester,
  ) async {
    final store = _HeldShopStore();
    SharedPreferencesStorePlatform.instance = store;
    final auth = _ShopAuth(loggedIn: false);
    final theme = ThemeProvider();
    final rewards = AchievementProvider();
    await rewards.applyRewardsSnapshot({'balance': 1000, 'lifetime': 1000});
    await _mount(tester, auth, theme, rewards);
    await tester.tap(find.text('从零开始'));
    await _waitForShopWrite(tester, store);
    await tester.pumpWidget(const SizedBox.shrink());
    store.release.complete();
    await tester.pumpAndSettle();
    expect(rewards.coinBalance, 860);
    expect(theme.brand.id, 're0');
    expect(theme.isBrandUnlocked('re0'), isTrue);
    expect(tester.takeException(), isNull);
    auth.dispose();
    theme.dispose();
    rewards.dispose();
  });

  testWidgets(
    'covered theme view completes purchase without misplaced feedback',
    (tester) async {
      final store = _HeldShopStore();
      SharedPreferencesStorePlatform.instance = store;
      final auth = _ShopAuth(loggedIn: false);
      final theme = ThemeProvider();
      final rewards = AchievementProvider();
      await rewards.applyRewardsSnapshot({'balance': 1000, 'lifetime': 1000});
      await _mount(tester, auth, theme, rewards);
      await tester.tap(find.text('从零开始'));
      await _waitForShopWrite(tester, store);
      final navigator = Navigator.of(
        tester.element(find.byType(ThemePickerScreen)),
      );
      navigator.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Cover'))),
      );
      await tester.pump(const Duration(milliseconds: 400));
      store.release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Cover'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(theme.brand.id, 're0');
      expect(rewards.coinBalance, 860);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      theme.dispose();
      rewards.dispose();
    },
  );
  _registerThemeFeedbackTests();
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
      child: const MaterialApp(
        home: BrandRouteSurface(child: ThemePickerScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _waitForShopWrite(
  WidgetTester tester,
  _HeldShopStore store,
) async {
  for (var i = 0; i < 30 && !store.started.isCompleted; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(store.started.isCompleted, isTrue);
}

class _HeldShopStore extends InMemorySharedPreferencesStore {
  _HeldShopStore() : super.withData({});
  final started = Completer<void>();
  final release = Completer<void>();
  bool rejectHeldWrite = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.theme_shop_state' && !started.isCompleted) {
      started.complete();
      await release.future;
      if (rejectHeldWrite) return false;
    }
    return super.setValue(valueType, key, value);
  }
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
  bool widgetSaveResult = true;
  int widgetSaveCalls = 0;
  int widgetBackgroundSaveCalls = 0;
  int widgetSkinSaveCalls = 0;
  final savedWidgetChoices = <String>[];
  final extraUnlockedBrands = <String>{};
  final extraUnlockedSkins = <String>{};

  @override
  bool isBrandUnlocked(String id) =>
      extraUnlockedBrands.contains(id) || super.isBrandUnlocked(id);

  @override
  bool isCardSkinUnlocked(String id) =>
      extraUnlockedSkins.contains(id) || super.isCardSkinUnlocked(id);

  Future<bool> _saveWidgetChoice(String id) async {
    widgetSaveCalls++;
    savedWidgetChoices.add(id);
    if (widgetSaveGate != null) await widgetSaveGate!.future;
    if (failWidgetSave) throw StateError('Controlled persistence failure');
    return widgetSaveResult;
  }

  @override
  Future<bool> setWidgetBackgroundBrand(String id) {
    widgetBackgroundSaveCalls++;
    return _saveWidgetChoice(id);
  }

  @override
  Future<bool> setWidgetCardSkin(String id) {
    widgetSkinSaveCalls++;
    return _saveWidgetChoice(id);
  }

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

void _registerThemeFeedbackTests() {
  for (final itemType in [
    'brand',
    'focus_backdrop',
    'avatar_frame',
    'card_skin',
  ]) {
    for (final unlocked in [false, true]) {
      testWidgets(
        'theme shop feedback $itemType unlocked=$unlocked follows visible locale',
        (tester) async {
          final auth = _FeedbackAuth();
          final theme = _FeedbackTheme(unlocked: unlocked);
          final rewards = _ShopRewards();
          await _mount(tester, auth, theme, rewards);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            auth.dispose();
            theme.dispose();
            rewards.dispose();
          });
          final route = tester.state(find.byType(ThemePickerScreen));
          final prefs = await SharedPreferences.getInstance();
          final before = _feedbackPreferences(prefs);
          await _tapFeedbackItem(tester, _feedbackItemName(itemType));
          String message() => unlocked
              ? DataSettingsUiCopy.themeApplied(_feedbackItemName(itemType))
              : DataSettingsUiCopy.themeRedeemedAndApplied(
                  _feedbackItemName(itemType),
                );
          final snack = tester.element(find.byType(SnackBar));
          final originalMessage = message();
          expect(_feedbackText(originalMessage), findsOneWidget);
          for (final locale in [AppLocale.en, AppLocale.zh]) {
            I18n.setLocale(locale);
            await tester.pumpAndSettle();
            expect(_feedbackText(message()), findsOneWidget);
            expect(tester.element(find.byType(SnackBar)), same(snack));
            expect(tester.state(find.byType(ThemePickerScreen)), same(route));
            expect(auth.calls, 1);
            expect(theme.snapshotCalls, 1);
            expect(rewards.snapshotCalls, 1);
            expect(_feedbackPreferences(prefs), before);
            if (locale == AppLocale.en) {
              expect(_feedbackText(originalMessage), findsNothing);
            }
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final literalServerMessage in [false, true]) {
    testWidgets(
      'theme shop feedback error literal=$literalServerMessage follows visible locale',
      (tester) async {
        const serverMessage = 'Please choose another theme. 原始服务器文案';
        final auth = _FeedbackAuth(
          error: literalServerMessage
              ? const ApiException(serverMessage)
              : StateError('Controlled internal save failure'),
        );
        final theme = _FeedbackTheme(unlocked: false);
        final rewards = _ShopRewards();
        await _mount(tester, auth, theme, rewards);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          auth.dispose();
          theme.dispose();
          rewards.dispose();
        });
        final route = tester.state(find.byType(ThemePickerScreen));
        final prefs = await SharedPreferences.getInstance();
        final before = _feedbackPreferences(prefs);
        await _tapFeedbackItem(tester, _feedbackItemName('brand'));
        String message() => literalServerMessage
            ? serverMessage
            : DataSettingsUiCopy.themeSaveFailed;
        final snack = tester.element(find.byType(SnackBar));
        expect(_feedbackText(message()), findsOneWidget);
        for (final locale in [AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(_feedbackText(message()), findsOneWidget);
          expect(tester.element(find.byType(SnackBar)), same(snack));
          expect(tester.state(find.byType(ThemePickerScreen)), same(route));
          expect(auth.calls, 1);
          expect(theme.snapshotCalls, 0);
          expect(rewards.snapshotCalls, 0);
          expect(_feedbackPreferences(prefs), before);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  _registerGuestThemeFeedbackTests();
}

Finder _feedbackText(String text) =>
    find.descendant(of: find.byType(SnackBar), matching: find.text(text));

Map<String, Object?> _feedbackPreferences(SharedPreferences prefs) => {
  for (final key in prefs.getKeys()) key: prefs.get(key),
};

Future<void> _tapFeedbackItem(WidgetTester tester, String name) async {
  final card = find.ancestor(
    of: find.text(name),
    matching: find.byWidgetPredicate(
      (widget) => widget is AppSurfaceCard && widget.onTap != null,
    ),
  );
  await tester.scrollUntilVisible(
    card,
    400,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 100,
  );
  expect(card, findsOneWidget);
  await tester.ensureVisible(card);
  await tester.tap(card);
  await tester.pumpAndSettle();
}

String _feedbackItemName(String itemType) => switch (itemType) {
  'brand' => AppBrands.byId('re0').localizedName,
  'focus_backdrop' => DataSettingsUiCopy.focusBackdropName(
    'morning_focus',
    ThemeProvider.focusBackdropRewards
        .firstWhere((item) => item.id == 'morning_focus')
        .name,
  ),
  'avatar_frame' => DataSettingsUiCopy.avatarFrameName(
    'golden_frame',
    ThemeProvider.avatarFrameRewards
        .firstWhere((item) => item.id == 'golden_frame')
        .name,
  ),
  'card_skin' => DataSettingsUiCopy.cardSkinName(
    'paper_card',
    ThemeProvider.cardSkinRewards
        .firstWhere((item) => item.id == 'paper_card')
        .name,
  ),
  _ => throw StateError('Unknown feedback fixture item'),
};

class _FeedbackAuth extends _ShopAuth {
  _FeedbackAuth({this.error}) : super(loggedIn: true);
  final Object? error;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> applyThemeShopItem({
    required String itemType,
    required String itemId,
    required String title,
  }) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return super.applyThemeShopItem(
      itemType: itemType,
      itemId: itemId,
      title: title,
    );
  }
}

class _FeedbackTheme extends _ShopTheme {
  _FeedbackTheme({required this.unlocked});
  final bool unlocked;

  @override
  bool isBrandUnlocked(String id) => unlocked || super.isBrandUnlocked(id);

  @override
  bool isFocusBackdropUnlocked(String id) =>
      unlocked || super.isFocusBackdropUnlocked(id);

  @override
  bool isAvatarFrameUnlocked(String id) =>
      unlocked || super.isAvatarFrameUnlocked(id);

  @override
  bool isCardSkinUnlocked(String id) =>
      unlocked || super.isCardSkinUnlocked(id);
}

void _registerGuestThemeFeedbackTests() {
  for (final failure in ['insufficient', 'declined', 'thrown']) {
    testWidgets(
      'theme shop feedback guest $failure follows locale and retains failure facts',
      (tester) async {
        final auth = _ShopAuth(loggedIn: false);
        final theme = _GuestFeedbackTheme(throwOnSave: failure == 'thrown');
        final rewards = _GuestFeedbackRewards(
          balance: failure == 'insufficient' ? 0 : 1000,
        );
        await _mount(tester, auth, theme, rewards);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          auth.dispose();
          theme.dispose();
          rewards.dispose();
        });
        final route = tester.state(find.byType(ThemePickerScreen));
        final prefs = await SharedPreferences.getInstance();
        final before = _feedbackPreferences(prefs);
        final deficit = theme.brandCost('re0') - rewards.coinBalance;
        await _tapFeedbackItem(tester, _feedbackItemName('brand'));
        String message() => failure == 'insufficient'
            ? DataSettingsUiCopy.insufficientCoins(deficit)
            : DataSettingsUiCopy.themeSaveFailed;
        final snack = tester.element(find.byType(SnackBar));
        expect(_feedbackText(message()), findsOneWidget);
        // A subsequent award/balance update must not rewrite the failed event.
        rewards.replaceBalance(failure == 'insufficient' ? 2000 : 0);
        await tester.pumpAndSettle();
        for (final locale in [AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(_feedbackText(message()), findsOneWidget);
          expect(tester.element(find.byType(SnackBar)), same(snack));
          expect(tester.state(find.byType(ThemePickerScreen)), same(route));
          expect(theme.redeemCalls, 1);
          expect(rewards.spendCalls, 0);
          expect(theme.brand.id, 'defaultBrand');
          expect(theme.isBrandUnlocked('re0'), isFalse);
          expect(_feedbackPreferences(prefs), before);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _GuestFeedbackTheme extends ThemeProvider {
  _GuestFeedbackTheme({required this.throwOnSave});
  final bool throwOnSave;
  int redeemCalls = 0;

  @override
  Future<bool> redeemGuestItem({
    required AchievementProvider rewards,
    required String itemType,
    required String itemId,
    required String title,
    required String reason,
    required bool Function() isAuthorized,
  }) async {
    redeemCalls++;
    if (!isAuthorized()) return false;
    if (throwOnSave) throw StateError('Controlled guest save failure');
    return false;
  }
}

class _GuestFeedbackRewards extends _ShopRewards {
  _GuestFeedbackRewards({required this.balance});
  int balance;

  @override
  int get coinBalance => balance;

  void replaceBalance(int value) {
    balance = value;
    notifyListeners();
  }
}
