import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/account_status_chip.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/rendered_control_contrast.dart'
    show withControlEvidenceShadows;
import '../support/rendered_information_chip_contrast.dart';
import '../support/widget_polish_screenshot_font.dart';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final status in AccountDisplayStatus.values) {
        testWidgets(
          'account status contrast $brand ${locale.name} ${status.name}',
          (tester) => withControlEvidenceShadows(() async {
            final boundary = await _mountStatusCard(
              tester,
              brand: brand,
              locale: locale,
            );
            expect(find.byType(AccountStatusChip), findsNWidgets(5));
            // Capture before the contrast assertion so the red run can retain
            // the same five-state card without producing twenty duplicate PNGs.
            if (status == AccountDisplayStatus.loggedIn) {
              await _captureIfRequested(
                tester,
                boundary,
                '$brand-${locale.name}',
              );
            }
            await expectInformationChipContrast(tester, boundary, [
              _statusLabel(status),
            ]);
            expect(tester.takeException(), isNull);
          }),
        );
      }
    }
  }

  testWidgets('account status optional onTap invokes callback', (tester) async {
    var taps = 0;
    await _mountStatusCard(
      tester,
      brand: 'defaultBrand',
      locale: AppLocale.en,
      onLoggedInTap: () => taps++,
    );
    final loggedIn = find.byWidgetPredicate(
      (widget) =>
          widget is AccountStatusChip &&
          widget.status == AccountDisplayStatus.loggedIn,
    );
    expect(loggedIn, findsOneWidget);
    expect(taps, 0);
    await tester.tap(loggedIn);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}

String _statusLabel(AccountDisplayStatus status) => switch (status) {
  AccountDisplayStatus.notLoggedIn => AccountUiCopy.statusNotLoggedIn,
  AccountDisplayStatus.loggedIn => AccountUiCopy.statusLoggedIn,
  AccountDisplayStatus.syncing => AccountUiCopy.statusSyncing,
  AccountDisplayStatus.syncFailed => AccountUiCopy.statusSyncFailed,
  AccountDisplayStatus.localOnly => AccountUiCopy.statusLocalMode,
};

Future<GlobalKey> _mountStatusCard(
  WidgetTester tester, {
  required String brand,
  required AppLocale locale,
  VoidCallback? onLoggedInTap,
}) async {
  SharedPreferences.setMockInitialValues({'active_brand': brand});
  I18n.setLocale(locale);
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final theme = ThemeProvider();
  await theme.loadFromStorage();
  expect(theme.brand.id, brand);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 844);
  final boundary = GlobalKey();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    theme.dispose();
    tester.view.reset();
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });
  final baseTheme = theme.brand.theme;
  TextTheme withScreenshotFonts(TextTheme text) => text.apply(
    fontFamily: 'DuoyiScreenshotLatin',
    fontFamilyFallback: const ['DuoyiScreenshot'],
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: theme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: baseTheme.copyWith(
          platform: TargetPlatform.iOS,
          textTheme: withScreenshotFonts(baseTheme.textTheme),
          primaryTextTheme: withScreenshotFonts(baseTheme.primaryTextTheme),
        ),
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
        ),
        home: BrandRouteSurface(
          remountOnLocaleChange: false,
          child: BrandScaffold(
            paintBackground: false,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: AppSurfaceCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final status in AccountDisplayStatus.values)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: AccountStatusChip(
                              status: status,
                              wrapLabel: true,
                              onTap: status == AccountDisplayStatus.loggedIn
                                  ? onLoggedInTap
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return boundary;
}

Future<void> _captureIfRequested(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (Platform.environment['DUOYI_CAPTURE_ACCOUNT_STATUS'] != '1') return;
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'evidence/screenshots/account-status-contrast-20261019/'
        'account-status-$name.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
