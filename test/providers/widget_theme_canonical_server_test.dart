import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Fresh providers share the fixture's backing preferences. This exercises
// production serialization/hydration, not a real process or OS restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async => AccountPreferenceWrites.drain());

  for (final brandId in ['defaultBrand', 'liquidGlass']) {
    final otherBrandId = brandId == 'defaultBrand'
        ? 'liquidGlass'
        : 'defaultBrand';

    test(
      'WTC763 revoked missing-field server snapshot is canonical for $brandId',
      () async {
        final warm = _provider();
        await warm.applyShopStateFromServer(
          _fullSnapshot(
            brandId,
            widgetBrandId: 're0',
            widgetCardSkinId: 'starlight_card',
          ),
        );
        expect(warm.activeWidgetBackgroundId, 're0');
        expect(warm.activeWidgetCardSkinId, 'starlight_card');

        final incoming = _fullSnapshot(brandId, updatedAt: _newerTimestamp)
          ..['unlockedBrandIds'] = ['defaultBrand', 'liquidGlass']
          ..['unlockedCardSkinIds'] = ['plain_card']
          ..remove('activeWidgetBackgroundId')
          ..remove('activeWidgetCardSkinId');
        await warm.applyShopStateFromServer(incoming);

        expect(warm.isBrandUnlocked('re0'), isFalse);
        expect(warm.isCardSkinUnlocked('starlight_card'), isFalse);
        expect(warm.activeWidgetBackgroundId, ThemeProvider.widgetFollowThemeId);
        expect(
          warm.activeWidgetCardSkinId,
          ThemeProvider.widgetFollowCardSkinId,
        );
        expect(warm.activeWidgetBackgroundBrand.id, brandId);
        expect(warm.activeWidgetCardSkin.id, ThemeProvider.defaultCardSkinId);
        await _expectCanonicalRoundTrip(warm);
      },
    );

    test(
      'WTC763 unlocked missing-field server snapshot retains overrides for $brandId',
      () async {
        final warm = _provider();
        await warm.applyShopStateFromServer(
          _fullSnapshot(
            brandId,
            widgetBrandId: otherBrandId,
            widgetCardSkinId: 'starlight_card',
          ),
        );
        final incoming = _fullSnapshot(brandId, updatedAt: _newerTimestamp)
          ..remove('activeWidgetBackgroundId')
          ..remove('activeWidgetCardSkinId');
        await warm.applyShopStateFromServer(incoming);

        expect(warm.activeWidgetBackgroundId, otherBrandId);
        expect(warm.activeWidgetCardSkinId, 'starlight_card');
        expect(warm.activeWidgetBackgroundBrand.id, otherBrandId);
        expect(warm.activeWidgetCardSkin.id, 'starlight_card');
        await _expectCanonicalRoundTrip(warm);
      },
    );

    test(
      'WTC763 snake-case server snapshot round-trips canonical fields for $brandId',
      () async {
        final warm = _provider();
        await warm.applyShopStateFromServer({
          'active_brand': brandId,
          'switch_count': 7,
          'unlocked_brand_ids': ['defaultBrand', 'liquidGlass'],
          'active_focus_backdrop_id': 'forest_focus',
          'unlocked_focus_backdrop_ids': ['classic_focus', 'forest_focus'],
          'active_avatar_frame_id': 'golden_frame',
          'unlocked_avatar_frame_ids': ['simple_frame', 'golden_frame'],
          'active_card_skin_id': 'paper_card',
          'unlocked_card_skin_ids': [
            'plain_card',
            'paper_card',
            'starlight_card',
          ],
          'active_widget_background_id': otherBrandId,
          'active_widget_card_skin_id': 'starlight_card',
          'updated_at': _newerTimestamp,
        });

        expect(warm.brand.id, brandId);
        expect(warm.themeSwitchCount, 7);
        expect(warm.activeFocusBackdrop.id, 'forest_focus');
        expect(warm.activeAvatarFrame.id, 'golden_frame');
        expect(warm.activeCardSkin.id, 'paper_card');
        expect(warm.activeWidgetBackgroundId, otherBrandId);
        expect(warm.activeWidgetCardSkinId, 'starlight_card');
        expect(warm.shopStateUpdatedAt, _newerTimestamp);
        final stored = await _storedSnapshot();
        expect(stored['activeWidgetBackgroundId'], otherBrandId);
        expect(stored['activeWidgetCardSkinId'], 'starlight_card');
        expect(stored.containsKey('active_widget_background_id'), isFalse);
        expect(stored.containsKey('active_widget_card_skin_id'), isFalse);
        await _expectCanonicalRoundTrip(warm);
      },
    );

    for (final legacyOnly in [false, true]) {
      test(
        'WTC763 stored legacy missing fields follow $brandId legacyOnly=$legacyOnly',
        () async {
          final warm = _provider();
          await warm.applyShopStateFromServer(
            _fullSnapshot(
              brandId,
              widgetBrandId: otherBrandId,
              widgetCardSkinId: 'starlight_card',
            ),
          );
          expect(warm.activeWidgetBackgroundId, otherBrandId);
          expect(warm.activeWidgetCardSkinId, 'starlight_card');

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('active_brand', brandId);
          await prefs.setStringList('theme_unlocked_brands', [
            'defaultBrand',
            'liquidGlass',
          ]);
          await prefs.setInt('theme_switch_count', 3);
          String? legacyRaw;
          if (legacyOnly) {
            await prefs.remove('theme_shop_state');
          } else {
            final legacy = _fullSnapshot(
              brandId,
              updatedAt: _newerTimestamp,
            )
              ..remove('activeWidgetBackgroundId')
              ..remove('activeWidgetCardSkinId');
            legacyRaw = jsonEncode(legacy);
            await prefs.setString('theme_shop_state', legacyRaw);
          }

          await warm.loadFromStorage();
          final fresh = _provider();
          await fresh.loadFromStorage();
          for (final provider in [warm, fresh]) {
            expect(provider.brand.id, brandId);
            expect(
              provider.activeWidgetBackgroundId,
              ThemeProvider.widgetFollowThemeId,
            );
            expect(
              provider.activeWidgetCardSkinId,
              ThemeProvider.widgetFollowCardSkinId,
            );
            expect(provider.activeWidgetBackgroundBrand.id, brandId);
            expect(provider.activeWidgetCardSkin.id, 'plain_card');
          }
          expect(_widgetSelection(fresh), _widgetSelection(warm));
          expect(
            HomeWidgetThemePayload.fromThemeProvider(fresh).payloadValues,
            HomeWidgetThemePayload.fromThemeProvider(warm).payloadValues,
          );
          // Read-only hydration retains old storage rather than inventing a
          // canonical migration or durable delivery receipt.
          expect(prefs.getString('theme_shop_state'), legacyRaw);
        },
      );
    }

    test(
      'WTC763 explicit valid widget theme positive control for $brandId',
      () async {
        final warm = _provider();
        await warm.applyShopStateFromServer(
          _fullSnapshot(
            brandId,
            widgetBrandId: brandId,
            widgetCardSkinId: ThemeProvider.defaultCardSkinId,
          ),
        );
        expect(warm.activeWidgetBackgroundId, brandId);
        expect(warm.activeWidgetCardSkinId, ThemeProvider.defaultCardSkinId);
        final payload = HomeWidgetThemePayload.fromThemeProvider(warm);
        expect(payload.brandId, brandId);
        expect(payload.cardSkinId, ThemeProvider.defaultCardSkinId);
        expect(payload.payloadValues['widget_theme_brand_id'], brandId);
        await _expectCanonicalRoundTrip(warm);
      },
    );
  }
}

const _olderTimestamp = '2026-11-14T00:00:00Z';
const _newerTimestamp = '2026-11-14T00:00:01Z';

ThemeProvider _provider() {
  final provider = ThemeProvider();
  addTearDown(provider.dispose);
  return provider;
}

Map<String, dynamic> _fullSnapshot(
  String brandId, {
  String widgetBrandId = ThemeProvider.widgetFollowThemeId,
  String widgetCardSkinId = ThemeProvider.widgetFollowCardSkinId,
  String updatedAt = _olderTimestamp,
}) => {
  'activeBrand': brandId,
  'switchCount': 3,
  'unlockedBrandIds': ['defaultBrand', 'liquidGlass', 're0'],
  'activeFocusBackdropId': 'classic_focus',
  'unlockedFocusBackdropIds': ['classic_focus'],
  'activeAvatarFrameId': 'simple_frame',
  'unlockedAvatarFrameIds': ['simple_frame'],
  'activeCardSkinId': 'plain_card',
  'unlockedCardSkinIds': ['plain_card', 'starlight_card'],
  'activeWidgetBackgroundId': widgetBrandId,
  'activeWidgetCardSkinId': widgetCardSkinId,
  'updatedAt': updatedAt,
};

Future<Map<String, dynamic>> _storedSnapshot() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('theme_shop_state');
  expect(raw, isNotNull);
  return jsonDecode(raw!) as Map<String, dynamic>;
}

Map<String, Object> _widgetSelection(ThemeProvider provider) => {
  'activeBrand': provider.brand.id,
  'activeWidgetBackgroundId': provider.activeWidgetBackgroundId,
  'activeWidgetCardSkinId': provider.activeWidgetCardSkinId,
};

Future<void> _expectCanonicalRoundTrip(ThemeProvider warm) async {
  final warmSnapshot = warm.shopStateSnapshot;
  final warmPayload = HomeWidgetThemePayload.fromThemeProvider(warm).payloadValues;
  final stored = await _storedSnapshot();
  final fresh = _provider();
  await fresh.loadFromStorage();
  // Collect the fresh provider even when canonical equality is the failing
  // regression, so the assertion distinguishes persistence from UI fallback.
  expect(fresh.shopStateSnapshot, warmSnapshot);
  expect(
    HomeWidgetThemePayload.fromThemeProvider(fresh).payloadValues,
    warmPayload,
  );
  expect(stored, warmSnapshot);
}
