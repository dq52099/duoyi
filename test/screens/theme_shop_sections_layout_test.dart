import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/theme_picker_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final layout in priorityLayouts) {
      testWidgets('shop section copy $brand ${layout.name}', (tester) async {
        final rewards = AchievementProvider();
        addTearDown(rewards.dispose);
        final boundary = await mountPriorityFixture(
          tester,
          auth: AuthProvider(),
          brand: brand,
          locale: AppLocale.zh,
          size: layout.size,
          scale: layout.scale,
          home: ChangeNotifierProvider<AchievementProvider>.value(
            value: rewards,
            child: const BrandRouteSurface(child: ThemePickerScreen()),
          ),
        );
        final retained = tester.state(find.byType(ThemePickerScreen));
        final prefs = await SharedPreferences.getInstance();
        final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
        final probe = RouteRenderProbe(
          tester,
          boundary,
          'shop-sections-$brand-${layout.name}',
        );
        for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
          final scrollable = find.byType(Scrollable).first;
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();
          expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
          final sections = [
            (
              I18n.tr('theme.section.styles'),
              I18n.tr('theme.section.styles.subtitle'),
            ),
            (
              DataSettingsUiCopy.focusBackdropSectionTitle,
              DataSettingsUiCopy.focusBackdropSectionSubtitle,
            ),
            (
              DataSettingsUiCopy.avatarFrameSectionTitle,
              DataSettingsUiCopy.avatarFrameSectionSubtitle,
            ),
            (
              DataSettingsUiCopy.cardSkinSectionTitle,
              DataSettingsUiCopy.cardSkinSectionSubtitle,
            ),
          ];
          for (var index = 0; index < sections.length; index++) {
            final section = sections[index];
            final header = find.byWidgetPredicate(
              (widget) =>
                  widget is AppSectionHeader && widget.title == section.$1,
            );
            final title = find.descendant(
              of: header,
              matching: find.text(section.$1),
            );
            if (title.evaluate().isEmpty) {
              try {
                for (
                  var step = 0;
                  step < 400 && title.evaluate().isEmpty;
                  step++
                ) {
                  final position = tester
                      .state<ScrollableState>(scrollable)
                      .position;
                  position.jumpTo(
                    (position.pixels + 150).clamp(0, position.maxScrollExtent),
                  );
                  await tester.pumpAndSettle();
                }
                expect(title, findsOneWidget);
              } catch (error) {
                final position = tester
                    .state<ScrollableState>(scrollable)
                    .position;
                fail(
                  'Cannot reveal ${locale.name} section $index: ${section.$1}; '
                  'offset=${position.pixels}, max=${position.maxScrollExtent}; '
                  'locale=${I18n.current}; headers=${tester.widgetList<AppSectionHeader>(find.byType(AppSectionHeader)).map((header) => header.title).toList()}; $error',
                );
              }
            }
            await probe.text(
              title,
              role: '${locale.name} section $index title',
              minimumGeometricScale: .999,
            );
            await probe.text(
              find.descendant(of: header, matching: find.text(section.$2)),
              role: '${locale.name} section $index subtitle',
              minimumGeometricScale: .999,
            );
            await probe.reveal(header);
            await probe.capture('${probe.rows.length}-${locale.name}-$index');
          }
          expect(tester.state(find.byType(ThemePickerScreen)), same(retained));
          expect({
            for (final key in prefs.getKeys()) key: prefs.get(key),
          }, before);
        }
        await probe.finish();
      });
    }
  }
}
