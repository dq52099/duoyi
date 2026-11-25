import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _selections = [
  (
    appBrand: 'defaultBrand',
    appCard: 'mint_card',
    widgetBrand: 're0',
    widgetCard: 'paper_card',
    assetKey: 're0',
  ),
  (
    appBrand: 'liquidGlass',
    appCard: 'paper_card',
    widgetBrand: 'genshin',
    widgetCard: 'mint_card',
    assetKey: 'genshin',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_widget');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() async {
    await AccountPreferenceWrites.drain();
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveWidgetData');
      calls.add(call);
      return true;
    });
  });

  tearDown(() async {
    await AccountPreferenceWrites.drain();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<Map<String, Object>> savePayload(HomeWidgetThemePayload payload) async {
    calls.clear();
    final results = await Future.wait(payload.saveOperations());
    expect(results, everyElement(isTrue));
    expect(calls, hasLength(payload.payloadValues.length));
    final saved = <String, Object>{};
    for (final call in calls) {
      final args = call.arguments as Map;
      final key = args['id'] as String;
      expect(saved.containsKey(key), isFalse, reason: 'duplicate save of $key');
      saved[key] = args['data'] as Object;
    }
    expect(saved, payload.payloadValues);
    return saved;
  }

  test(
    'server-selected widget palettes save the same canonical payload after warm and fresh-provider reloads',
    () async {
      for (final selection in _selections) {
        // The reference also uses a real provider and the production factory.
        // It follows an app palette equal to the independent widget selection.
        final reference = await _followPayload(
          selection.widgetBrand,
          selection.widgetCard,
        );
        SharedPreferences.setMockInitialValues({});
        final theme = ThemeProvider();
        addTearDown(theme.dispose);
        await theme.loadFromStorage();
        await theme.applyShopStateFromServer(
          _state(
            appBrand: selection.appBrand,
            appCard: selection.appCard,
            widgetBrand: selection.widgetBrand,
            widgetCard: selection.widgetCard,
          ),
          trusted: true,
        );

        expect(theme.brand.id, selection.appBrand);
        expect(theme.activeCardSkin.id, selection.appCard);
        expect(theme.activeWidgetBackgroundId, selection.widgetBrand);
        expect(theme.activeWidgetCardSkinId, selection.widgetCard);
        final payload = HomeWidgetThemePayload.fromThemeProvider(theme);
        _expectPalette(payload, selection.widgetBrand, selection.widgetCard);
        expect(payload.backgroundAssetKey, selection.assetKey);
        expect(payload.payloadValues, reference.payloadValues);
        final saved = await savePayload(payload);

        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('theme_shop_state')!;
        final canonical = jsonDecode(raw) as Map<String, dynamic>;
        expect(canonical, theme.shopStateSnapshot);
        expect(canonical['activeBrand'], selection.appBrand);
        expect(canonical['activeCardSkinId'], selection.appCard);
        expect(canonical['activeWidgetBackgroundId'], selection.widgetBrand);
        expect(canonical['activeWidgetCardSkinId'], selection.widgetCard);

        // Warm reload uses the current provider; fresh reload creates only a
        // new provider on the same SharedPreferences fixture, not a process.
        await theme.loadFromStorage();
        final warm = HomeWidgetThemePayload.fromThemeProvider(theme);
        expect(warm.payloadValues, saved);
        expect(warm.signature, payload.signature);
        expect(await savePayload(warm), saved);

        final fresh = ThemeProvider();
        addTearDown(fresh.dispose);
        await fresh.loadFromStorage();
        expect(fresh.brand.id, selection.appBrand);
        expect(fresh.activeCardSkin.id, selection.appCard);
        expect(fresh.activeWidgetBackgroundId, selection.widgetBrand);
        expect(fresh.activeWidgetCardSkinId, selection.widgetCard);
        final restored = HomeWidgetThemePayload.fromThemeProvider(fresh);
        _expectPalette(restored, selection.widgetBrand, selection.widgetCard);
        expect(restored.backgroundAssetKey, selection.assetKey);
        expect(restored.payloadValues, reference.payloadValues);
        expect(restored.signature, payload.signature);
        expect(await savePayload(restored), saved);
        expect(fresh.shopStateSnapshot, canonical);
        expect(prefs.getString('theme_shop_state'), raw);
      }
    },
  );

  test(
    'server revocation cannot persist locked widget overrides over the current app palette',
    () async {
      for (final selection in _selections) {
        final reference = await _followPayload(
          selection.appBrand,
          selection.appCard,
        );
        SharedPreferences.setMockInitialValues({});
        final theme = ThemeProvider();
        addTearDown(theme.dispose);
        await theme.loadFromStorage();
        await theme.applyShopStateFromServer(
          _state(
            appBrand: selection.widgetBrand,
            appCard: selection.widgetCard,
            widgetBrand: selection.widgetBrand,
            widgetCard: selection.widgetCard,
          ),
          trusted: true,
        );
        final old = HomeWidgetThemePayload.fromThemeProvider(theme);
        _expectPalette(old, selection.widgetBrand, selection.widgetCard);
        expect(old.backgroundAssetKey, selection.assetKey);
        final oldSaved = await savePayload(old);

        // Omitted widget fields must not keep an override whose entitlement
        // has just disappeared. Move the app off the old premium brand too,
        // since an active app brand is automatically included in its unlocks.
        await theme.applyShopStateFromServer({
          'activeBrand': selection.appBrand,
          'unlockedBrandIds': ['defaultBrand', selection.appBrand],
          'activeCardSkinId': selection.appCard,
          'unlockedCardSkinIds': ['plain_card', selection.appCard],
          'updatedAt': '2099-01-02T00:00:00Z',
        }, trusted: true);

        expect(theme.brand.id, selection.appBrand);
        expect(theme.isBrandUnlocked(selection.widgetBrand), isFalse);
        expect(theme.isCardSkinUnlocked(selection.widgetCard), isFalse);
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('theme_shop_state')!;
        final canonical = jsonDecode(raw) as Map<String, dynamic>;
        // Check persisted canonical IDs before either hydration path can hide
        // a bad server save by normalizing a locked ID only in memory.
        expect(
          canonical['activeWidgetBackgroundId'],
          ThemeProvider.widgetFollowThemeId,
        );
        expect(
          canonical['activeWidgetCardSkinId'],
          ThemeProvider.widgetFollowCardSkinId,
        );
        expect(canonical, theme.shopStateSnapshot);
        expect(
          theme.activeWidgetBackgroundId,
          ThemeProvider.widgetFollowThemeId,
        );
        expect(
          theme.activeWidgetCardSkinId,
          ThemeProvider.widgetFollowCardSkinId,
        );

        final payload = HomeWidgetThemePayload.fromThemeProvider(theme);
        _expectPalette(payload, selection.appBrand, selection.appCard);
        expect(payload.backgroundAssetKey, isEmpty);
        expect(payload.payloadValues, reference.payloadValues);
        expect(payload.payloadValues, isNot(oldSaved));
        final saved = await savePayload(payload);

        await theme.loadFromStorage();
        final warm = HomeWidgetThemePayload.fromThemeProvider(theme);
        expect(warm.payloadValues, saved);
        expect(await savePayload(warm), saved);
        expect(theme.shopStateSnapshot, canonical);

        final fresh = ThemeProvider();
        addTearDown(fresh.dispose);
        await fresh.loadFromStorage();
        expect(
          fresh.activeWidgetBackgroundId,
          ThemeProvider.widgetFollowThemeId,
        );
        expect(
          fresh.activeWidgetCardSkinId,
          ThemeProvider.widgetFollowCardSkinId,
        );
        final restored = HomeWidgetThemePayload.fromThemeProvider(fresh);
        _expectPalette(restored, selection.appBrand, selection.appCard);
        expect(restored.payloadValues, reference.payloadValues);
        expect(restored.signature, payload.signature);
        expect(await savePayload(restored), saved);
        expect(fresh.shopStateSnapshot, canonical);
        expect(prefs.getString('theme_shop_state'), raw);
      }
    },
  );
}

Map<String, dynamic> _state({
  required String appBrand,
  required String appCard,
  required String widgetBrand,
  required String widgetCard,
}) => {
  'activeBrand': appBrand,
  'unlockedBrandIds': {'defaultBrand', appBrand, widgetBrand}.toList(),
  'activeCardSkinId': appCard,
  'unlockedCardSkinIds': {'plain_card', appCard, widgetCard}.toList(),
  'activeWidgetBackgroundId': widgetBrand,
  'activeWidgetCardSkinId': widgetCard,
  'updatedAt': '2099-01-01T00:00:00Z',
};

Future<HomeWidgetThemePayload> _followPayload(
  String brand,
  String card,
) async {
  SharedPreferences.setMockInitialValues({
    'theme_shop_state': jsonEncode({
      'activeBrand': brand,
      'unlockedBrandIds': ['defaultBrand', brand],
      'activeCardSkinId': card,
      'unlockedCardSkinIds': ['plain_card', card],
      'activeWidgetBackgroundId': ThemeProvider.widgetFollowThemeId,
      'activeWidgetCardSkinId': ThemeProvider.widgetFollowCardSkinId,
      'updatedAt': '2099-01-01T00:00:00Z',
    }),
  });
  final reference = ThemeProvider();
  try {
    await reference.loadFromStorage();
    expect(reference.activeWidgetBackgroundBrand.id, brand);
    expect(reference.activeWidgetCardSkin.id, card);
    return HomeWidgetThemePayload.fromThemeProvider(reference);
  } finally {
    reference.dispose();
  }
}

void _expectPalette(
  HomeWidgetThemePayload payload,
  String brandId,
  String cardId,
) {
  final brand = AppBrands.byId(brandId);
  final card = ThemeProvider.cardSkinRewards.singleWhere(
    (skin) => skin.id == cardId,
  );
  final colors = brand.theme.colorScheme;
  expect(payload.brandId, brandId);
  expect(payload.cardSkinId, cardId);
  expect(payload.dark, brand.theme.brightness == Brightness.dark);
  expect(payload.primary, colors.primary);
  expect(payload.text, colors.onSurface);
  expect(payload.mutedText, colors.onSurfaceVariant);
  expect(payload.onPrimary, colors.onPrimary);
  expect(payload.accentStart, card.colors.first);
  expect(payload.accentEnd, card.colors.last);
}
