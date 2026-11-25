import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/theme_picker_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      testWidgets('widget section header $brand ${locale.name} large', (
        tester,
      ) async {
        final rewards = AchievementProvider();
        addTearDown(rewards.dispose);
        final key = await mountPriorityFixture(
          tester,
          auth: AuthProvider(),
          brand: brand,
          locale: locale,
          size: const Size(320, 844),
          scale: 2,
          home: ChangeNotifierProvider<AchievementProvider>.value(
            value: rewards,
            child: const BrandRouteSurface(child: ThemePickerScreen()),
          ),
        );
        final retained = tester.state(find.byType(ThemePickerScreen));
        final prefs = await SharedPreferences.getInstance();
        final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
        final probe = RouteRenderProbe(
          tester,
          key,
          'widget-section-header-$brand-${locale.name}',
        );
        Future<void> measure(String stage) async {
          final title = find.text(DataSettingsUiCopy.widgetSyncNoticeTitle);
          if (title.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              title,
              600,
              maxScrolls: 100,
              scrollable: find.byType(Scrollable).first,
            );
          }
          await probe.text(
            title,
            role: '$stage title',
            minimumGeometricScale: .999,
          );
          await probe.text(
            find.text(DataSettingsUiCopy.widgetSyncNoticeSubtitle),
            role: '$stage subtitle',
            minimumGeometricScale: .999,
          );
          await probe.capture(stage);
        }

        await measure('initial');
        I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ThemePickerScreen)), same(retained));
        expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, before);
        await measure('locale');
        await probe.finish();
      });
    }
  }
}
