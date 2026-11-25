import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secondary_route_render_probe.dart';
import 'weekly_review_screenshot_font.dart';

Future<GlobalKey> mountHabitCreateFixture(
  WidgetTester tester, {
  required HabitProvider habits,
  required TimeAuditProvider audit,
  required String brand,
  required AppLocale locale,
  required Size size,
  required double scale,
}) async {
  SharedPreferences.setMockInitialValues({'active_brand': brand});
  I18n.setLocale(locale);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = ThemeProvider();
  final auth = AuthProvider();
  await tester.runAsync(() async {
    await theme.loadFromStorage();
    await loadWeeklyReviewScreenshotFonts();
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    auth.dispose();
    theme.dispose();
  });
  final boundary = GlobalKey();
  await tester.pumpWidget(
    // The Navigator overlay must inherit the same providers as HabitScreen so
    // actual sheet action-origin checks see the captured provider identities.
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<HabitProvider>.value(value: habits),
        ChangeNotifierProvider<TimeAuditProvider>.value(value: audit),
      ],
      child: ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, selected, _) => MaterialApp(
          locale: Locale(selected == AppLocale.en ? 'en' : 'zh'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: theme.brand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: scale < 0
                  ? const RouteProbeNonlinearScaler()
                  : TextScaler.linear(scale),
            ),
            child: RepaintBoundary(key: boundary, child: child!),
          ),
          home: const BrandBackground(child: HabitScreen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return boundary;
}
