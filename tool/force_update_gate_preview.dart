// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/force_update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeProvider = ThemeProvider();
  await _loadPreviewFont();
  await themeProvider.applyShopStateFromServer({
    'activeBrand': 're0',
    'unlockedBrandIds': ['re0'],
  }, trusted: true);
  final updateService =
      AppUpdateService(
        repo: 'dq52099/duoyi',
        currentVersion: '1.1.34',
        currentVersionCode: 140000,
      )..debugSetUpdatePolicyForTest(
        latestVersion: '1.1.35',
        latestVersionCode: 140001,
        minimumSupportedVersion: '1.1.34',
        minimumSupportedVersionCode: 140000,
        forceUpdateRequired: true,
        latestUrl: 'https://example.test/releases/duoyi-v1.1.35.apk',
      );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<AppUpdateService>.value(value: updateService),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _withPreviewFont(themeProvider.brand.theme),
        home: const Stack(children: [ForceUpdateGate()]),
      ),
    ),
  );
}

Future<void> _loadPreviewFont() async {
  try {
    final response = await http.get(Uri.parse('force_update_subset.ttf'));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) return;
    final data = ByteData.sublistView(Uint8List.fromList(response.bodyBytes));
    await (FontLoader('DuoyiScreenshot')..addFont(Future.value(data))).load();
  } catch (_) {}
}

ThemeData _withPreviewFont(ThemeData theme) {
  const family = 'DuoyiScreenshot';
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: family),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: family),
  );
}
