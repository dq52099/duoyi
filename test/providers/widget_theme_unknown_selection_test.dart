import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(AccountPreferenceWrites.drain);

  for (final source in ['local', 'server']) {
    for (final brand in ['defaultBrand', 'liquidGlass']) {
      test(
        'unknown widget IDs follow $brand after $source hydration',
        () async {
          final state = <String, dynamic>{
            'activeBrand': brand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
            'activeCardSkinId': 'paper_card',
            'unlockedCardSkinIds': ['plain_card', 'paper_card'],
            'activeWidgetBackgroundId': 'future_widget_brand',
            'activeWidgetCardSkinId': 'retired_widget_skin',
            'updatedAt': '2099-01-01T00:00:00Z',
          };
          final theme = ThemeProvider();
          addTearDown(theme.dispose);
          if (source == 'local') {
            SharedPreferences.setMockInitialValues({
              'theme_shop_state': jsonEncode(state),
            });
            await theme.loadFromStorage();
          } else {
            await theme.applyShopStateFromServer(state, trusted: true);
          }
          expect(theme.brand.id, brand);
          expect(
            theme.activeWidgetBackgroundId,
            ThemeProvider.widgetFollowThemeId,
          );
          expect(
            theme.activeWidgetCardSkinId,
            ThemeProvider.widgetFollowCardSkinId,
          );
          expect(theme.activeWidgetBackgroundBrand.id, brand);
          expect(theme.activeWidgetCardSkin.id, 'paper_card');
          final payload = HomeWidgetThemePayload.fromThemeProvider(theme);
          expect(payload.brandId, brand);
          expect(payload.cardSkinId, 'paper_card');

          // A later app selection must still propagate to both widget choices.
          final otherBrand = brand == 'liquidGlass'
              ? 'defaultBrand'
              : 'liquidGlass';
          expect(await theme.setBrand(otherBrand), isTrue);
          expect(await theme.setCardSkin('plain_card'), isTrue);
          expect(theme.activeWidgetBackgroundBrand.id, otherBrand);
          expect(theme.activeWidgetCardSkin.id, 'plain_card');
          final reloaded = ThemeProvider();
          addTearDown(reloaded.dispose);
          await reloaded.loadFromStorage();
          expect(
            reloaded.activeWidgetBackgroundId,
            ThemeProvider.widgetFollowThemeId,
          );
          expect(
            reloaded.activeWidgetCardSkinId,
            ThemeProvider.widgetFollowCardSkinId,
          );
          expect(reloaded.activeWidgetBackgroundBrand.id, otherBrand);
          expect(reloaded.activeWidgetCardSkin.id, 'plain_card');
        },
      );
    }
  }

  test('explicit known default widget choices remain independent', () async {
    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    await theme.applyShopStateFromServer({
      'activeBrand': 'liquidGlass',
      'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      'activeCardSkinId': 'paper_card',
      'unlockedCardSkinIds': ['plain_card', 'paper_card'],
      'activeWidgetBackgroundId': 'defaultBrand',
      'activeWidgetCardSkinId': 'plain_card',
      'updatedAt': '2099-01-01T00:00:00Z',
    }, trusted: true);
    expect(theme.activeWidgetBackgroundId, 'defaultBrand');
    expect(theme.activeWidgetCardSkinId, 'plain_card');
    expect(theme.activeWidgetBackgroundBrand.id, 'defaultBrand');
    expect(theme.activeWidgetCardSkin.id, 'plain_card');
    final reloaded = ThemeProvider();
    addTearDown(reloaded.dispose);
    await reloaded.loadFromStorage();
    expect(reloaded.brand.id, 'liquidGlass');
    expect(reloaded.activeWidgetBackgroundId, 'defaultBrand');
    expect(reloaded.activeWidgetCardSkinId, 'plain_card');
  });
}
