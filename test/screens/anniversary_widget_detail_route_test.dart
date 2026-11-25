import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final type in [
        AnniversaryType.normal,
        AnniversaryType.birthday,
        AnniversaryType.memorial,
      ]) {
        testWidgets('published anniversary $type $brand ${locale.name}', (
          tester,
        ) async {
          final item = Anniversary(
            id: 'anniversary /?#&=% 测试🌙',
            title: 'Selected user title',
            description: 'Selected user description',
            originDate: DateTime(2023, 3, 22),
            type: type,
          );
          final other = Anniversary(
            id: 'other-object',
            title: 'Different object',
            originDate: DateTime(2024, 5, 6),
            type: type,
          );
          final stored = [
            other,
            item,
          ].map((entry) => jsonEncode(entry.toJson())).toList();
          SharedPreferences.setMockInitialValues({
            'active_brand': brand,
            'duoyi_anniversaries_v2': stored,
          });
          I18n.setLocale(locale);
          final anniversaries = AnniversaryProvider();
          final theme = ThemeProvider();
          try {
            await anniversaries.loadFromStorage();
            await theme.loadFromStorage();
            expect(theme.brand.id, brand);
            // Start at the decoded-ID receiver contract, without simulating
            // native URL delivery or snapshot validation in main.
            final uri = Uri.parse(
              'duoyi://anniversary/${Uri.encodeComponent(item.id)}',
            );
            expect(uri.pathSegments, [item.id]);
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<AnniversaryProvider>.value(
                    value: anniversaries,
                  ),
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ],
                child: MaterialApp(
                  theme: theme.brand.theme,
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => TodayDetailRouter.open(
                          context,
                          TodaySectionKind.anniversaries,
                          id: uri.pathSegments.first,
                        ),
                        child: const Text('Open published anniversary'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open published anniversary'));
            await tester.pumpAndSettle();
            expect(find.byType(BrandRouteSurface), findsOneWidget);
            final route = tester.widget<AnniversaryScreen>(
              find.byType(AnniversaryScreen),
            );
            expect(route.initialAnniversaryId, item.id);
            expect(route.fixedType, type);
            final fields = tester.widgetList<TextField>(find.byType(TextField));
            expect(fields.map((field) => field.controller?.text), [
              item.title,
              item.description,
            ]);
            final cancel = find.text(I18n.tr('action.cancel'));
            await tester.ensureVisible(cancel);
            await tester.pumpAndSettle();
            expect(cancel.hitTestable(), findsOneWidget);
            await tester.tap(cancel);
            await tester.pumpAndSettle();
            expect(find.byType(TextField), findsNothing);
            await tester.pageBack();
            await tester.pumpAndSettle();
            expect(find.text('Open published anniversary'), findsOneWidget);
            expect(
              (await SharedPreferences.getInstance()).getStringList(
                'duoyi_anniversaries_v2',
              ),
              stored,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            anniversaries.dispose();
            theme.dispose();
            I18n.setLocale(AppLocale.zh);
          }
        });
      }
    }
  }
}
