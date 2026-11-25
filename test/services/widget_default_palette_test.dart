import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fresh widget palette agrees with the empty account defaults', () {
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    final payload = HomeWidgetThemePayload.fromThemeProvider(provider);
    final defaults = HomeWidgetService.accountPayloadDefaults;

    expect(provider.activeWidgetBackgroundBrand.id, 'defaultBrand');
    expect(provider.activeWidgetCardSkin.id, 'plain_card');
    expect(defaults['widget_theme_primary'], '#FF0066D6');
    expect(defaults['widget_theme_accent_start'], '#FF0066D6');
    expect(defaults['widget_theme_accent_end'], '#FF3898FF');
    expect(defaults['widget_theme_border'], '#000066D6');
    expect(defaults['widget_theme_background'], '#FFF6F7F9');
    for (final entry in payload.payloadValues.entries) {
      expect(entry.value, defaults[entry.key], reason: entry.key);
    }
    expect(payload.mutedText, DesignTokens.defaultTextMuted);
    expect(payload.mutedText, isNot(payload.text));
    for (final background in [payload.background, payload.surface]) {
      expect(
        (background.computeLuminance() + 0.05) /
            (payload.mutedText.computeLuminance() + 0.05),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test(
    'empty storage keeps the same default palette after hydration',
    () async {
      final provider = ThemeProvider();
      addTearDown(provider.dispose);
      final before = HomeWidgetThemePayload.fromThemeProvider(provider);
      await provider.loadFromStorage();
      final after = HomeWidgetThemePayload.fromThemeProvider(provider);

      expect(after.payloadValues, before.payloadValues);
      expect(after.mutedText, DesignTokens.defaultTextMuted);
    },
  );

  test(
    'plain glass widgets publish opaque composed surfaces and a static highlight',
    () {
      final provider = _PaletteProvider(
        AppBrands.liquidGlass,
        ThemeProvider.cardSkinRewards.singleWhere(
          (skin) => skin.id == ThemeProvider.defaultCardSkinId,
        ),
      );
      addTearDown(provider.dispose);
      final payload = HomeWidgetThemePayload.fromThemeProvider(provider);
      const base = Color(0xFFE9EEF6);
      expect(
        payload.background,
        Color.alphaBlend(Colors.white.withValues(alpha: 0.45), base),
      );
      expect(
        payload.surface,
        Color.alphaBlend(Colors.white.withValues(alpha: 0.72), base),
      );
      expect(
        payload.navBackground,
        Color.alphaBlend(Colors.white.withValues(alpha: 0.28), base),
      );
      for (final color in [
        payload.background,
        payload.surface,
        payload.navBackground,
      ]) {
        expect(color.a, 1);
      }
      expect(
        payload.surface.computeLuminance(),
        greaterThan(payload.background.computeLuminance()),
      );
      expect(
        payload.background.computeLuminance(),
        greaterThan(payload.navBackground.computeLuminance()),
      );
      expect(payload.border, Colors.white.withValues(alpha: 0.35));
      expect(payload.cornerRadiusDp, 16);
      expect(payload.controlRadiusDp, 12);
      expect(payload.borderWidthDp, 1);
      expect(payload.backgroundAssetKey, isEmpty);
    },
  );

  test('glass card skins retain their independent geometry', () {
    for (final entry in {
      'paper_card': 14,
      'mint_card': 15,
      'starlight_card': 16,
    }.entries) {
      final provider = _PaletteProvider(
        AppBrands.liquidGlass,
        ThemeProvider.cardSkinRewards.singleWhere(
          (skin) => skin.id == entry.key,
        ),
      );
      final payload = HomeWidgetThemePayload.fromThemeProvider(provider);
      provider.dispose();
      expect(payload.cornerRadiusDp, entry.value);
      expect(payload.controlRadiusDp, 8);
      expect(payload.borderWidthDp, 1);
      expect(payload.border, isNot(Colors.white.withValues(alpha: 0.35)));
    }
  });

  test(
    'nondefault themes and selected card skins keep their own text roles',
    () {
      for (final brand in AppBrands.all) {
        for (final skin in ThemeProvider.cardSkinRewards) {
          if (brand.id == AppBrands.defaultBrand.id &&
              skin.id == ThemeProvider.defaultCardSkinId) {
            continue;
          }
          final provider = _PaletteProvider(brand, skin);
          final payload = HomeWidgetThemePayload.fromThemeProvider(provider);
          expect(payload.brandId, brand.id);
          expect(payload.cardSkinId, skin.id);
          expect(payload.text, brand.theme.colorScheme.onSurface);
          expect(payload.mutedText, brand.theme.colorScheme.onSurfaceVariant);
          provider.dispose();
        }
      }
    },
  );
}

class _PaletteProvider extends ThemeProvider {
  _PaletteProvider(this.widgetBrand, this.widgetSkin);

  final AppBrand widgetBrand;
  final CardSkinReward widgetSkin;

  @override
  AppBrand get activeWidgetBackgroundBrand => widgetBrand;

  @override
  CardSkinReward get activeWidgetCardSkin => widgetSkin;
}
