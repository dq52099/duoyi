import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/force_update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

bool _screenshotFontLoaded = false;

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('强制更新页桌面尺寸全屏覆盖', (tester) async {
    await _pumpForceUpdateGate(tester, size: const Size(1280, 820));
  });

  testWidgets('强制更新页手机尺寸全屏覆盖', (tester) async {
    await _pumpForceUpdateGate(tester, size: const Size(390, 844));
  });

  testWidgets('强制更新页 320px 下长安装包名可换行展示', (tester) async {
    await _pumpForceUpdateGate(tester, size: const Size(320, 700));
  });

  testWidgets('强制更新页挂载后 zh→en→zh 切换只更新界面文案', (tester) async {
    const size = Size(320, 700);
    const textScaler = TextScaler.linear(1.8);
    const releaseNotes =
        '发布说明：Keep *Markdown* and this exact text.\n- 第二行原样保留。  ';
    final originalLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(() => I18n.setLocale(originalLocale));

    final networkRequests = <http.Request>[];
    final fakeUpdater = _ForceUpdateGateUpdaterFixture(
      literalReleaseNotes: releaseNotes,
      observedRequests: networkRequests,
    );
    final themeProvider = ThemeProvider();
    addTearDown(fakeUpdater.dispose);
    final initialPolicyState = _policyState(fakeUpdater);
    final renderedUpdaters = <AppUpdateService>[];
    final renderedLocales = <AppLocale>[];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<AppUpdateService>.value(value: fakeUpdater),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: themeProvider.brand.theme,
          home: Builder(
            builder: (context) {
              final updater = context.watch<AppUpdateService>();
              renderedUpdaters.add(updater);
              renderedLocales.add(I18n.current);
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: const Stack(children: [ForceUpdateGate()]),
              );
            },
          ),
        ),
      ),
    );

    _expectForceUpdateLocale(tester, AppLocale.zh, releaseNotes);
    expect(fakeUpdater.mustUpdate, isTrue);
    expect(_policyState(fakeUpdater), initialPolicyState);

    I18n.setLocale(AppLocale.en);
    await tester.pump();
    _expectForceUpdateLocale(tester, AppLocale.en, releaseNotes);
    expect(fakeUpdater.mustUpdate, isTrue);
    expect(_policyState(fakeUpdater), initialPolicyState);

    I18n.setLocale(AppLocale.zh);
    await tester.pump();
    _expectForceUpdateLocale(tester, AppLocale.zh, releaseNotes);
    expect(fakeUpdater.mustUpdate, isTrue);
    expect(_policyState(fakeUpdater), initialPolicyState);
    expect(renderedLocales, containsAll([AppLocale.zh, AppLocale.en]));
    expect(renderedUpdaters, isNotEmpty);
    expect(
      renderedUpdaters.every((updater) => identical(updater, fakeUpdater)),
      isTrue,
    );
    expect(networkRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

void _expectForceUpdateLocale(
  WidgetTester tester,
  AppLocale locale,
  String releaseNotes,
) {
  final expected = switch (locale) {
    AppLocale.zh => (
      title: '需要更新后才能继续使用',
      description: '管理员已开启强制更新策略。更新完成前，应用功能会暂时锁定。',
      currentVersion: '当前版本',
      latestVersion: '最新版本',
      minimumVersion: '最低支持版本',
      notesHeading: '更新内容',
      unavailableTitle: '安装包暂不可用',
      unavailableMessage: '管理员未配置下载地址，或发布通道还没有提供可安装的新版本。请等待发布包同步完成。',
      installButton: '下载并安装',
    ),
    AppLocale.en => (
      title: 'Update required to continue',
      description:
          'An administrator requires this update. App features stay locked until it is installed.',
      currentVersion: 'Current version',
      latestVersion: 'Latest version',
      minimumVersion: 'Minimum supported version',
      notesHeading: 'What’s new',
      unavailableTitle: 'Installer unavailable',
      unavailableMessage:
          'No download URL is configured, or the release channel does not have an installable package yet. Wait for the package to sync.',
      installButton: 'Download and install',
    ),
  };

  expect(find.byType(ForceUpdateGate), findsOneWidget);
  expect(find.text(expected.title), findsOneWidget);
  expect(find.text(expected.description), findsOneWidget);
  expect(find.text(expected.currentVersion), findsOneWidget);
  expect(find.text(expected.latestVersion), findsOneWidget);
  expect(find.text(expected.minimumVersion), findsOneWidget);
  expect(find.text(expected.notesHeading), findsOneWidget);
  expect(find.text(expected.unavailableTitle), findsOneWidget);
  expect(find.text(expected.unavailableMessage), findsOneWidget);
  expect(find.text(expected.installButton), findsOneWidget);
  expect(find.text('1.1.34'), findsNWidgets(2));
  expect(find.text('1.1.37'), findsOneWidget);
  expect(
    tester.widget<SelectableText>(find.byType(SelectableText)).data,
    releaseNotes,
  );
  expect(
    find.byWidgetPredicate(
      (widget) => widget is FilledButton && widget.onPressed != null,
    ),
    findsNothing,
    reason: 'The fixture has no install URL and must not start installation.',
  );
}

List<Object?> _policyState(AppUpdateService updater) => [
  updater.currentVersion,
  updater.currentVersionCode,
  updater.latestVersion,
  updater.latestVersionCode,
  updater.minimumSupportedVersion,
  updater.minimumSupportedVersionCode,
  updater.forceUpdateRequired,
  updater.mustUpdate,
  updater.latestUrl,
  updater.latestAssetName,
  updater.latestNotesForDisplay,
];

/// Offline mounted-gate fixture: real policy fields use the existing test hook,
/// while supplied release notes stay literal and HTTP requests are captured.
class _ForceUpdateGateUpdaterFixture extends AppUpdateService {
  _ForceUpdateGateUpdaterFixture({
    required this.literalReleaseNotes,
    required this.observedRequests,
  }) : super(
         repo: 'dq52099/duoyi',
         currentVersion: '1.1.34',
         currentVersionCode: 140000,
         httpClient: MockClient((request) async {
           observedRequests.add(request);
           return http.Response('unexpected HTTP request', 500);
         }),
       ) {
    debugSetUpdatePolicyForTest(
      latestVersion: '1.1.37',
      latestVersionCode: 140003,
      minimumSupportedVersion: '1.1.34',
      minimumSupportedVersionCode: 140000,
      forceUpdateRequired: true,
    );
  }

  final String literalReleaseNotes;
  final List<http.Request> observedRequests;

  @override
  String? get latestNotes => literalReleaseNotes;

  @override
  String get latestNotesForDisplay => literalReleaseNotes;
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
        latestVersion: '1.1.37',
        latestVersionCode: 140003,
        minimumSupportedVersion: '1.1.34',
        minimumSupportedVersionCode: 140000,
        forceUpdateRequired: true,
        latestUrl:
            'https://example.test/releases/duoyi-v1.1.37-android-arm64-release-signed-official-channel.apk',
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
  expect(find.text('1.1.37'), findsOneWidget);
  expect(find.text('最低支持版本'), findsOneWidget);
  expect(find.text('安装包'), findsOneWidget);
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
