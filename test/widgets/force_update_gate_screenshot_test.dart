import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/force_update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

bool _screenshotFontLoaded = false;

void main() {
  testWidgets('强制更新页桌面尺寸全屏覆盖', (tester) async {
    await _pumpForceUpdateGate(tester, size: const Size(1280, 820));
  });

  testWidgets('强制更新页手机尺寸全屏覆盖', (tester) async {
    await _pumpForceUpdateGate(tester, size: const Size(390, 844));
  });
}

Future<void> _pumpForceUpdateGate(
  WidgetTester tester, {
  required Size size,
}) async {
  final captureTarget =
      Platform.environment['DUOYI_FORCE_UPDATE_SCREENSHOT_TARGET'];
  final shouldCapture =
      Platform.environment['DUOYI_CAPTURE_FORCE_UPDATE_SCREENSHOT'] == '1' &&
      (captureTarget == null || captureTarget == _screenshotNameForSize(size));
  if (shouldCapture) {
    await _loadScreenshotFont();
  }
  final screenshotKey = GlobalKey();
  final themeProvider = ThemeProvider();
  final updateService =
      AppUpdateService(
        repo: 'dq52099/duoyi',
        currentVersion: '1.1.34',
        currentVersionCode: 140000,
      )..debugSetUpdatePolicyForTest(
        latestVersion: '1.1.36',
        latestVersionCode: 140002,
        minimumSupportedVersion: '1.1.34',
        minimumSupportedVersionCode: 140000,
        forceUpdateRequired: true,
        latestUrl: 'https://example.test/releases/duoyi-v1.1.36.apk',
      );

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<AppUpdateService>.value(value: updateService),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shouldCapture
            ? _withScreenshotFont(themeProvider.brand.theme)
            : themeProvider.brand.theme,
        home: shouldCapture
            ? RepaintBoundary(
                key: screenshotKey,
                child: const Stack(children: [ForceUpdateGate()]),
              )
            : const Stack(children: [ForceUpdateGate()]),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  expect(tester.takeException(), isNull);
  expect(find.byType(ForceUpdateGate), findsOneWidget);
  expect(find.byType(PopScope), findsOneWidget);
  expect(find.text('需要更新后才能继续使用'), findsOneWidget);
  expect(find.text('管理员已开启强制更新策略。更新完成前，应用功能会暂时锁定。'), findsOneWidget);
  expect(find.text('当前版本'), findsOneWidget);
  expect(find.text('1.1.34'), findsWidgets);
  expect(find.text('最新版本'), findsOneWidget);
  expect(find.text('1.1.36'), findsOneWidget);
  expect(find.text('最低支持版本'), findsOneWidget);
  expect(find.text('当前平台不支持应用内安装'), findsOneWidget);
  expect(find.text('下载并安装'), findsOneWidget);

  if (shouldCapture) {
    final boundary =
        screenshotKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    image.dispose();
    final file = File(
      '.playwright-mcp/ui-regression/force_update_gate_${_screenshotNameForSize(size)}.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }
}

String _screenshotNameForSize(Size size) =>
    size.width < 600 ? 'mobile' : 'desktop';

Future<void> _loadScreenshotFont() async {
  if (_screenshotFontLoaded) return;
  final fontPath =
      Platform.environment['DUOYI_FORCE_UPDATE_SCREENSHOT_FONT'] ??
      '.playwright-mcp/ui-regression/force_update_subset.ttf';
  final fontFile = File(fontPath);
  if (!fontFile.existsSync()) return;
  final bytes = await fontFile.readAsBytes();
  final fontData = ByteData.sublistView(bytes);
  await (FontLoader('DuoyiScreenshot')..addFont(Future.value(fontData))).load();
  _screenshotFontLoaded = true;
}

ThemeData _withScreenshotFont(ThemeData theme) {
  const family = 'DuoyiScreenshot';
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: family),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: family),
  );
}
