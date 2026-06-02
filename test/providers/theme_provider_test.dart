import 'dart:convert';

import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('server theme shop state updates provider and local cache', () async {
    final provider = ThemeProvider();

    await provider.applyShopStateFromServer({
      'activeBrand': 're0',
      'switchCount': 1,
      'unlockedBrandIds': ['defaultBrand', 're0'],
      'activeFocusBackdropId': 'forest_focus',
      'unlockedFocusBackdropIds': ['classic_focus', 'forest_focus'],
      'updatedAt': '2026-06-01T00:00:00Z',
    });
    final prefs = await SharedPreferences.getInstance();
    final persisted =
        json.decode(prefs.getString('theme_shop_state')!)
            as Map<String, dynamic>;

    expect(provider.brand.id, 're0');
    expect(provider.activeFocusBackdrop.id, 'forest_focus');
    expect(provider.shopStateUpdatedAt, '2026-06-01T00:00:00Z');
    expect(persisted['activeBrand'], 're0');
    expect(persisted['activeFocusBackdropId'], 'forest_focus');
    expect(persisted['updatedAt'], '2026-06-01T00:00:00Z');
  });

  test(
    'local theme shop changes include updatedAt for sync ordering',
    () async {
      final provider = ThemeProvider();

      await provider.loadFromStorage();
      await provider.unlockBrand('re0');
      await provider.setBrand('re0');
      final prefs = await SharedPreferences.getInstance();
      final persisted =
          json.decode(prefs.getString('theme_shop_state')!)
              as Map<String, dynamic>;

      expect(provider.brand.id, 're0');
      expect(provider.shopStateUpdatedAt, isNotEmpty);
      expect(persisted['activeBrand'], 're0');
      expect(persisted['updatedAt'], isNotEmpty);
    },
  );

  test('older server theme shop state cannot roll back active theme', () async {
    final provider = ThemeProvider();

    await provider.applyShopStateFromServer({
      'activeBrand': 're0',
      'unlockedBrandIds': ['defaultBrand', 're0'],
      'updatedAt': '2026-06-01T00:00:02Z',
    });
    await provider.applyShopStateFromServer({
      'activeBrand': 'defaultBrand',
      'unlockedBrandIds': ['defaultBrand'],
      'updatedAt': '2026-06-01T00:00:01Z',
    });
    final prefs = await SharedPreferences.getInstance();
    final persisted =
        json.decode(prefs.getString('theme_shop_state')!)
            as Map<String, dynamic>;

    expect(provider.brand.id, 're0');
    expect(provider.shopStateUpdatedAt, '2026-06-01T00:00:02Z');
    expect(persisted['activeBrand'], 're0');
  });

  test('older server reward snapshot cannot roll back coin balance', () async {
    final provider = AchievementProvider();

    await provider.applyRewardsSnapshot({
      'balance': 60,
      'lifetime': 200,
      'updatedAt': '2026-06-01T00:00:02Z',
    });
    await provider.applyRewardsSnapshot({
      'balance': 120,
      'lifetime': 200,
      'updatedAt': '2026-06-01T00:00:01Z',
    });
    final prefs = await SharedPreferences.getInstance();
    final persisted =
        json.decode(prefs.getString('duoyi_virtual_rewards')!)
            as Map<String, dynamic>;

    expect(provider.coinBalance, 60);
    expect(provider.lifetimeCoins, 200);
    expect(persisted['balance'], 60);
  });
}
