import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secondary_route_render_probe.dart';
import 'weekly_review_screenshot_font.dart';

const priorityLayouts = [
  (name: 'common', size: Size(390, 844), scale: 1.0),
  (name: 'narrow', size: Size(320, 844), scale: 1.6),
  (name: 'large', size: Size(320, 844), scale: 2.0),
  (name: 'landscape', size: Size(568, 320), scale: 2.0),
  (name: 'desktop', size: Size(1000, 720), scale: 1.1),
  (name: 'nonlinear', size: Size(332, 844), scale: -1.0),
];

Future<GlobalKey> mountPriorityFixture(
  WidgetTester tester, {
  required AuthProvider auth,
  required String brand,
  required AppLocale locale,
  required Size size,
  required double scale,
  required Widget home,
}) async {
  SharedPreferences.setMockInitialValues({'active_brand': brand});
  I18n.setLocale(locale);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = ThemeProvider();
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
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
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
          home: home,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return boundary;
}
