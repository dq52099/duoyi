import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exporter uses the production Flutter palette factory. The normal run
/// verifies native resources against that factory, so palette changes cannot
/// silently leave old Android versions with stale or unreadable surfaces.
void main() {
  test('native surfaces match all published brand and card palettes', () {
    final palettes = <Map<String, Object>>[];
    for (final brand in AppBrands.all) {
      for (final skin in ThemeProvider.cardSkinRewards) {
        final provider = _PaletteProvider(brand, skin);
        final payload = HomeWidgetThemePayload.fromThemeProvider(provider);
        palettes.add(payload.payloadValues);
        provider.dispose();
      }
    }
    final export = Platform.environment['DUOYI_EXPORT_WIDGET_PALETTES'];
    if (export != null) {
      File(export).writeAsStringSync(jsonEncode(palettes));
      return;
    }
    final manifest =
        jsonDecode(
              File(
                'android/app/src/main/res/raw/widget_surface_palettes.json',
              ).readAsStringSync(),
            )
            as List;
    expect(manifest.length, palettes.length);
    final kotlin = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSurfaceResources.kt',
    ).readAsStringSync();
    for (final palette in palettes) {
      final key =
          '${palette['widget_theme_brand_id']}|${palette['widget_theme_card_skin_id']}';
      final entry = manifest.singleWhere((item) => item['key'] == key) as Map;
      expect(entry['palette'], palette, reason: key);
      expect(kotlin, contains('"$key" to'));
      for (final role in [
        'root',
        'nav',
        'primary',
        'secondary',
        'imageBorder',
      ]) {
        final shape = entry['surfaces'][role] as Map;
        final resource = shape['resource'] as String;
        final xml = File(
          'android/app/src/main/res/drawable/$resource.xml',
        ).readAsStringSync();
        expect(kotlin, contains('R.drawable.$resource'));
        expect(
          xml,
          contains('android:color="${shape['fill']}"'),
          reason: '$key $role',
        );
        expect(
          xml,
          contains('android:radius="${shape['radius']}dp"'),
          reason: '$key $role',
        );
        if (shape['strokeWidth'] > 0) {
          expect(xml, contains('android:color="${shape['stroke']}"'));
          expect(xml, contains('android:width="${shape['strokeWidth']}dp"'));
        }
        expect(
          shape['radius'],
          role == 'root' || role == 'imageBorder'
              ? palette['widget_theme_corner_radius_dp']
              : palette['widget_theme_control_radius_dp'],
        );
        if (role == 'primary') {
          expect(shape['fill'], palette['widget_theme_primary']);
          expect(shape['strokeWidth'], 0);
        } else if (role == 'root') {
          expect(shape['fill'], palette['widget_theme_background']);
        } else if (role == 'imageBorder') {
          expect(shape['fill'], '#00000000');
          expect(shape['strokeWidth'], palette['widget_theme_border_width_dp']);
          if (shape['strokeWidth'] > 0) {
            expect(shape['stroke'], palette['widget_theme_border']);
          }
        } else {
          expect(shape['fill'], palette['widget_theme_nav_background']);
        }
      }
    }
  });
}

class _PaletteProvider extends ThemeProvider {
  final AppBrand widgetBrand;
  final CardSkinReward widgetSkin;

  _PaletteProvider(this.widgetBrand, this.widgetSkin);

  @override
  AppBrand get activeWidgetBackgroundBrand => widgetBrand;

  @override
  CardSkinReward get activeWidgetCardSkin => widgetSkin;
}
