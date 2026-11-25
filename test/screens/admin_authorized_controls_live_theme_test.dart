import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/admin_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

const _layouts = [
  (name: 'ordinary', size: Size(390, 844), scale: 1.0),
  (name: '320px200percent', size: Size(320, 844), scale: 2.0),
];

const _priorityBrands = ['defaultBrand', 'liquidGlass'];

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  group('Priority admin authorized controls live theme layout', () {
    for (final brand in _priorityBrands) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        for (final layout in _layouts) {
          testWidgets(
            'authorized controls target44, complete label and radius12 $brand ${locale.name} ${layout.name}',
            (tester) async {
              final fixture = await _mountAdminFixture(
                tester,
                brand: brand,
                locale: locale,
                size: layout.size,
                scale: layout.scale,
                initialTabIndex:
                    2, // AI settings: has both FilledButton and OutlinedButton
              );

              // 1. Verify backend calls received for the authorized module
              expect(
                fixture.requests.any(
                  (r) =>
                      r.url.path == '/api/admin/settings' &&
                      r.url.queryParameters['scope'] == 'ai',
                ),
                isTrue,
                reason: 'AI settings should be fetched on initial load',
              );

              final aiScrollable = _moduleVerticalScrollable(
                modulePrefix: 'admin-ai-',
              ).first;

              // 2. Verify FilledButton (Save)
              final saveLabel = AdminUiCopy.saveBtnFor(locale);
              final saveButtonFinder = find.widgetWithText(
                FilledButton,
                saveLabel,
              );
              await tester.scrollUntilVisible(
                saveButtonFinder,
                300,
                scrollable: aiScrollable,
              );
              await tester.ensureVisible(saveButtonFinder);
              await tester.pumpAndSettle();
              expect(saveButtonFinder, findsOneWidget);
              _verifyButtonCharacteristics(
                tester,
                saveButtonFinder,
                brand: brand,
              );

              // 3. Verify OutlinedButton (Test AI Form)
              final testLabel = AdminUiCopy.aiTestCurrentFormFor(locale);
              final testButtonFinder = find.widgetWithText(
                OutlinedButton,
                testLabel,
              );
              await tester.scrollUntilVisible(
                testButtonFinder,
                300,
                scrollable: aiScrollable,
              );
              await tester.ensureVisible(testButtonFinder);
              await tester.pumpAndSettle();
              expect(testButtonFinder, findsOneWidget);
              _verifyButtonCharacteristics(
                tester,
                testButtonFinder,
                brand: brand,
              );

              // 4. Capture screenshot if environment variable requests it
              await _captureRetainedDialogIfRequested(
                tester,
                fixture.captureKey,
                'admin-authorized-$brand-${locale.name}-${layout.name}',
              );

              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('Denied admin submodule mounted presentation', () {
    for (final initialBrand in _priorityBrands) {
      for (final size in [const Size(320, 844), const Size(568, 320)]) {
        testWidgets(
          'denied backup retains account, route and complete copy $initialBrand ${size.width.toInt()}x${size.height.toInt()} scale2',
          (tester) async {
            final semantics = tester.ensureSemantics();
            try {
              final fixture = await _mountAdminFixture(
                tester,
                brand: initialBrand,
                locale: AppLocale.en,
                size: size,
                scale: 2,
                permissions: const ['ai'],
              );
              final screenState = tester.state(find.byType(AdminScreen));
              final controller = tester
                  .widget<TabBar>(find.byType(TabBar))
                  .controller!;
              controller.animateTo(3);
              await tester.pumpAndSettle();
              final otherBrand = initialBrand == 'defaultBrand'
                  ? 'liquidGlass'
                  : 'defaultBrand';
              final phases = [
                (brand: initialBrand, locale: AppLocale.en),
                (brand: initialBrand, locale: AppLocale.zh),
                (brand: otherBrand, locale: AppLocale.zh),
                (brand: otherBrand, locale: AppLocale.en),
              ];
              for (var index = 0; index < phases.length; index++) {
                final phase = phases[index];
                await tester.runAsync(
                  () => fixture.theme.setBrand(phase.brand),
                );
                I18n.setLocale(phase.locale);
                await tester.pumpAndSettle();
                expect(
                  tester.state(find.byType(AdminScreen)),
                  same(screenState),
                );
                expect(fixture.theme.brand.id, phase.brand);
                expect(I18n.current, phase.locale);
                expect(controller.index, 3);
                expect(fixture.auth.state.adminPermissions, ['ai']);
                expect(find.byIcon(Icons.lock_outline), findsOneWidget);
                final message = AdminUiCopy.noModulePermissionFor(phase.locale);
                final label = find.text(message);
                expect(label, findsOneWidget);
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(of: label, matching: find.byType(RichText)),
                );
                expect(paragraph.didExceedMaxLines, isFalse);
                final rect = tester.getRect(label);
                expect(rect.left, greaterThanOrEqualTo(0));
                expect(rect.top, greaterThanOrEqualTo(0));
                expect(rect.right, lessThanOrEqualTo(size.width));
                expect(rect.bottom, lessThanOrEqualTo(size.height));
                expect(
                  tester.getSemantics(label).getSemanticsData().label,
                  contains(message),
                );
                expect(find.byType(FilledButton), findsNothing);
                expect(find.byType(OutlinedButton), findsNothing);
                expect(
                  fixture.requests.where(
                    (r) => !['GET', 'HEAD'].contains(r.method),
                  ),
                  isEmpty,
                );
                await _captureRetainedDialogIfRequested(
                  tester,
                  fixture.captureKey,
                  'admin-denied-$initialBrand-${size.width.toInt()}x${size.height.toInt()}-$index-${phase.brand}-${phase.locale.name}',
                  metadata: {
                    'brand': fixture.theme.brand.id,
                    'locale': I18n.current.name,
                    'viewport': [size.width, size.height],
                    'requestedTextScale': 2,
                    'tabIndex': controller.index,
                    'screenStateIdentity': identityHashCode(screenState),
                    'message': message,
                    'messageRect': [
                      rect.left,
                      rect.top,
                      rect.right,
                      rect.bottom,
                    ],
                    'permissions': fixture.auth.state.adminPermissions,
                    'mutationRequests': 0,
                    'scope':
                        'Flutter host fixture; UI denial does not prove server authorization',
                  },
                );
                expect(tester.takeException(), isNull);
              }
              await tester.runAsync(() => fixture.theme.setBrand(initialBrand));
              I18n.setLocale(AppLocale.en);
              controller.animateTo(2);
              await tester.pumpAndSettle();
              expect(tester.state(find.byType(AdminScreen)), same(screenState));
              final save = find.widgetWithText(
                FilledButton,
                AdminUiCopy.saveBtnFor(AppLocale.en),
              );
              await tester.scrollUntilVisible(
                save,
                300,
                scrollable: _moduleVerticalScrollable(
                  modulePrefix: 'admin-ai-',
                ).first,
              );
              await tester.ensureVisible(save);
              await tester.pumpAndSettle();
              _verifyButtonCharacteristics(tester, save, brand: initialBrand);
              expect(
                fixture.requests.where(
                  (r) => !['GET', 'HEAD'].contains(r.method),
                ),
                isEmpty,
              );
              expect(tester.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  });

  group('Priority admin authorized controls mounted transitions', () {
    testWidgets(
      'preserves button 12px radius across mounted brand transition defaultBrand <-> liquidGlass',
      (tester) async {
        final fixture = await _mountAdminFixture(
          tester,
          brand: 'defaultBrand',
          locale: AppLocale.zh,
          size: const Size(320, 844),
          scale: 2.0,
          initialTabIndex: 2,
        );

        final aiScrollable = _moduleVerticalScrollable(
          modulePrefix: 'admin-ai-',
        ).first;
        final filledButton = find.widgetWithText(
          FilledButton,
          AdminUiCopy.saveBtnFor(AppLocale.zh),
        );
        final outlinedButton = find.widgetWithText(
          OutlinedButton,
          AdminUiCopy.aiTestCurrentFormFor(AppLocale.zh),
        );

        await tester.scrollUntilVisible(
          filledButton,
          300,
          scrollable: aiScrollable,
        );
        await tester.ensureVisible(filledButton);
        await tester.pumpAndSettle();
        _verifyButtonCharacteristics(
          tester,
          filledButton,
          brand: 'defaultBrand',
        );

        await tester.scrollUntilVisible(
          outlinedButton,
          300,
          scrollable: aiScrollable,
        );
        await tester.ensureVisible(outlinedButton);
        await tester.pumpAndSettle();
        _verifyButtonCharacteristics(
          tester,
          outlinedButton,
          brand: 'defaultBrand',
        );

        final screenState = tester.state(find.byType(AdminScreen));

        // Live mounted brand transition: defaultBrand -> liquidGlass
        await tester.runAsync(() async {
          await fixture.theme.setBrand('liquidGlass');
        });
        await tester.pumpAndSettle();

        // Screen remains mounted with intact state
        expect(tester.state(find.byType(AdminScreen)), same(screenState));

        // Buttons retain 12px radius and 44px targets in liquidGlass
        await tester.scrollUntilVisible(
          filledButton,
          300,
          scrollable: aiScrollable,
        );
        await tester.ensureVisible(filledButton);
        await tester.pumpAndSettle();
        _verifyButtonCharacteristics(
          tester,
          filledButton,
          brand: 'liquidGlass',
        );

        await tester.scrollUntilVisible(
          outlinedButton,
          300,
          scrollable: aiScrollable,
        );
        await tester.ensureVisible(outlinedButton);
        await tester.pumpAndSettle();
        _verifyButtonCharacteristics(
          tester,
          outlinedButton,
          brand: 'liquidGlass',
        );

        // Live mounted brand transition back: liquidGlass -> defaultBrand
        await tester.runAsync(() async {
          await fixture.theme.setBrand('defaultBrand');
        });
        await tester.pumpAndSettle();

        expect(tester.state(find.byType(AdminScreen)), same(screenState));
        await tester.scrollUntilVisible(
          filledButton,
          300,
          scrollable: aiScrollable,
        );
        await tester.ensureVisible(filledButton);
        await tester.pumpAndSettle();
        _verifyButtonCharacteristics(
          tester,
          filledButton,
          brand: 'defaultBrand',
        );

        await tester.scrollUntilVisible(
          outlinedButton,
          300,
          scrollable: aiScrollable,
        );
        await tester.ensureVisible(outlinedButton);
        await tester.pumpAndSettle();
        _verifyButtonCharacteristics(
          tester,
          outlinedButton,
          brand: 'defaultBrand',
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'preserves complete labels and button radius across mounted locale transition zh <-> en',
      (tester) async {
        await _mountAdminFixture(
          tester,
          brand: 'liquidGlass',
          locale: AppLocale.zh,
          size: const Size(320, 844),
          scale: 2.0,
          initialTabIndex: 2,
        );

        final screenState = tester.state(find.byType(AdminScreen));
        final aiScrollable = _moduleVerticalScrollable(
          modulePrefix: 'admin-ai-',
        ).first;

        final zhFilled = find.widgetWithText(
          FilledButton,
          AdminUiCopy.saveBtnFor(AppLocale.zh),
        );
        final zhOutlined = find.widgetWithText(
          OutlinedButton,
          AdminUiCopy.aiTestCurrentFormFor(AppLocale.zh),
        );

        // Initial Chinese labels
        await tester.scrollUntilVisible(
          zhFilled,
          300,
          scrollable: aiScrollable,
        );
        await tester.ensureVisible(zhFilled);
        await tester.pumpAndSettle();
        expect(zhFilled, findsOneWidget);
        _verifyButtonCharacteristics(tester, zhFilled, brand: 'liquidGlass');

        await tester.scrollUntilVisible(
          zhOutlined,
          300,
          scrollable: aiScrollable,
        );
        await tester.ensureVisible(zhOutlined);
        await tester.pumpAndSettle();
        expect(zhOutlined, findsOneWidget);
        _verifyButtonCharacteristics(tester, zhOutlined, brand: 'liquidGlass');

        // Live mounted locale transition: zh -> en
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();

        expect(tester.state(find.byType(AdminScreen)), same(screenState));

        // English labels rendered completely without truncation
        final enFilled = find.widgetWithText(
          FilledButton,
          AdminUiCopy.saveBtnFor(AppLocale.en),
        );
        final enOutlined = find.widgetWithText(
          OutlinedButton,
          AdminUiCopy.aiTestCurrentFormFor(AppLocale.en),
        );

        await tester.scrollUntilVisible(
          enFilled,
          300,
          scrollable: aiScrollable,
        );
        await tester.ensureVisible(enFilled);
        await tester.pumpAndSettle();
        expect(enFilled, findsOneWidget);
        _verifyButtonCharacteristics(tester, enFilled, brand: 'liquidGlass');

        await tester.scrollUntilVisible(
          enOutlined,
          300,
          scrollable: aiScrollable,
        );
        await tester.ensureVisible(enOutlined);
        await tester.pumpAndSettle();
        expect(enOutlined, findsOneWidget);
        _verifyButtonCharacteristics(tester, enOutlined, brand: 'liquidGlass');

        // Live mounted locale transition back: en -> zh
        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();

        expect(tester.state(find.byType(AdminScreen)), same(screenState));
        final zhFilledBack = find.widgetWithText(
          FilledButton,
          AdminUiCopy.saveBtnFor(AppLocale.zh),
        );
        await tester.scrollUntilVisible(
          zhFilledBack,
          300,
          scrollable: aiScrollable,
        );
        await tester.ensureVisible(zhFilledBack);
        await tester.pumpAndSettle();
        expect(zhFilledBack, findsOneWidget);
        _verifyButtonCharacteristics(
          tester,
          zhFilledBack,
          brand: 'liquidGlass',
        );

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Priority admin authorized route contracts and boundaries', () {
    testWidgets(
      'authorizes permitted tab and blocks denied submodules with lock presentation',
      (tester) async {
        await _mountAdminFixture(
          tester,
          brand: 'defaultBrand',
          locale: AppLocale.zh,
          size: const Size(390, 844),
          scale: 1.0,
          initialTabIndex: 2,
          permissions: const ['ai'], // Only 'ai' permitted, 'backup' denied
        );

        // Authorized tab 2 (AI): renders controls
        final saveFinder = find.widgetWithText(
          FilledButton,
          AdminUiCopy.saveBtnFor(AppLocale.zh),
        );
        final aiScrollable = _moduleVerticalScrollable(
          modulePrefix: 'admin-ai-',
        ).first;
        await tester.scrollUntilVisible(
          saveFinder,
          300,
          scrollable: aiScrollable,
        );
        await tester.ensureVisible(saveFinder);
        await tester.pumpAndSettle();
        expect(saveFinder, findsOneWidget);
        _verifyButtonCharacteristics(tester, saveFinder, brand: 'defaultBrand');

        // Animate to denied tab 3 (Cloud backup)
        final tabController = tester
            .widget<TabBar>(find.byType(TabBar))
            .controller!;
        tabController.animateTo(3);
        await tester.pumpAndSettle();

        // Denied tab presents lock icon and no-permission message
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        expect(
          find.text(AdminUiCopy.noModulePermissionFor(AppLocale.zh)),
          findsOneWidget,
        );

        // No mutation action buttons in the denied tab
        expect(
          find.text(AdminUiCopy.saveConfigBtnFor(AppLocale.zh)),
          findsNothing,
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'preserves pagination parameters and backend call contract on authorized submodules',
      (tester) async {
        final fixture = await _mountAdminFixture(
          tester,
          brand: 'liquidGlass',
          locale: AppLocale.zh,
          size: const Size(390, 844),
          scale: 1.0,
          initialTabIndex: 4, // Users tab
          permissions: const ['users', 'roles', 'groups'],
        );

        // Verify users tab made paginated request
        final userRequests = fixture.requests.where(
          (r) => r.url.path == '/api/admin/users',
        );
        expect(userRequests, isNotEmpty);
        final initialUserRequest = userRequests.first;
        expect(initialUserRequest.method, 'GET');
        expect(
          initialUserRequest.url.queryParameters['limit'] ?? '20',
          '20',
          reason: 'Default page limit should be preserved',
        );
        expect(
          initialUserRequest.url.queryParameters['offset'] ?? '0',
          '0',
          reason: 'Initial page offset should be 0',
        );

        // Next page navigation via pagination bar
        final nextButton = find.byTooltip(
          AdminUiCopy.nextPageFor(AppLocale.zh),
        );
        expect(nextButton, findsOneWidget);
        await tester.tap(nextButton);
        await tester.pumpAndSettle();
        final paginatedRequests = fixture.requests.where(
          (r) => r.url.path == '/api/admin/users',
        );
        expect(paginatedRequests.length, greaterThan(1));
        expect(
          paginatedRequests.last.url.queryParameters['offset'],
          '20',
          reason: 'Pagination offset should advance to 20',
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'preserves draft and cancel state in authorized submodule action dialog without mutation',
      (tester) async {
        final fixture = await _mountAdminFixture(
          tester,
          brand: 'defaultBrand',
          locale: AppLocale.zh,
          size: const Size(390, 844),
          scale: 1.0,
          initialTabIndex: 5, // Groups tab
          permissions: const ['groups', 'roles'],
        );

        // Tap Add Group button
        final addGroupBtn = find.text(AdminUiCopy.addGroupTitle);
        await tester.ensureVisible(addGroupBtn);
        await tester.tap(addGroupBtn);
        await tester.pumpAndSettle();

        // Verify dialog is visible
        expect(find.byType(Dialog), findsOneWidget);

        // Enter text into draft group name
        final textField = find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(TextField),
            )
            .first;
        await tester.enterText(textField, 'Draft Group / 原文保留');
        await tester.pumpAndSettle();

        // Tap Cancel
        final cancelBtn = find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(
            TextButton,
            AdminUiCopy.cancelFor(AppLocale.zh),
          ),
        );
        expect(cancelBtn, findsOneWidget);
        await tester.tap(cancelBtn);
        await tester.pumpAndSettle();

        // Dialog dismissed
        expect(find.byType(Dialog), findsNothing);

        // Verify NO POST/mutation was sent to the synthetic backend
        final mutations = fixture.requests.where((r) => r.method != 'GET');
        expect(
          mutations,
          isEmpty,
          reason:
              'Cancelling a draft must not send mutation requests to the backend',
        );

        expect(tester.takeException(), isNull);
      },
    );

    for (final brand in _priorityBrands) {
      testWidgets(
        'authorized submodule TextButton inherits effective 44px target and 12px radius $brand',
        (tester) async {
          await _mountAdminFixture(
            tester,
            brand: brand,
            locale: AppLocale.zh,
            size: const Size(390, 844),
            scale: 1.0,
            initialTabIndex: 1, // Settings tab with TextButton.icon
            permissions: const ['settings', 'groups', 'roles'],
          );

          final groupBtnFinder = find.widgetWithText(
            TextButton,
            AdminUiCopy.addGroupBtnFor(AppLocale.zh),
          );
          final settingsScrollable = _moduleVerticalScrollable(
            modulePrefix: 'admin-settings-',
          ).first;
          await tester.scrollUntilVisible(
            groupBtnFinder,
            400,
            scrollable: settingsScrollable,
          );
          await tester.ensureVisible(groupBtnFinder);
          await tester.pumpAndSettle();
          expect(groupBtnFinder, findsOneWidget);
          _verifyButtonCharacteristics(tester, groupBtnFinder, brand: brand);

          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}

Finder _moduleVerticalScrollable({String? modulePrefix}) {
  final parent = modulePrefix != null
      ? find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey &&
              '${(w.key! as ValueKey).value}'.startsWith(modulePrefix),
        )
      : find.byType(TabBarView);

  return find.descendant(
    of: parent,
    matching: find.byWidgetPredicate(
      (w) =>
          w is Scrollable &&
          (w.axisDirection == AxisDirection.down ||
              w.axisDirection == AxisDirection.up),
    ),
  );
}

void _verifyButtonCharacteristics(
  WidgetTester tester,
  Finder buttonFinder, {
  required String brand,
}) {
  expect(buttonFinder, findsOneWidget);
  final size = tester.getSize(buttonFinder);
  expect(
    size.width,
    greaterThanOrEqualTo(44.0 - 0.01),
    reason: 'Button width ${size.width} should be at least 44px',
  );
  expect(
    size.height,
    greaterThanOrEqualTo(44.0 - 0.01),
    reason: 'Button height ${size.height} should be at least 44px',
  );

  final textFinder = find.descendant(
    of: buttonFinder,
    matching: find.byType(Text),
  );
  if (textFinder.evaluate().isNotEmpty) {
    final textWidget = tester.widget<Text>(textFinder.first);
    final text = textWidget.data ?? textWidget.textSpan?.toPlainText() ?? '';
    expect(text, isNotEmpty, reason: 'Button label should not be empty');

    final richFinder = find.descendant(
      of: textFinder.first,
      matching: find.byType(RichText),
    );
    if (richFinder.evaluate().isNotEmpty) {
      final paragraph = tester.renderObject<RenderParagraph>(richFinder.first);
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: 'Button text "$text" should not overflow its line constraints',
      );
    }
  }

  final materialFinder = find.descendant(
    of: buttonFinder,
    matching: find.byType(Material),
  );
  expect(materialFinder, findsWidgets);
  final material = tester.widget<Material>(materialFinder.first);
  expect(
    material.shape,
    isNot(isA<StadiumBorder>()),
    reason: 'Button shape in brand $brand must not regress to StadiumBorder',
  );
  expect(
    material.shape,
    isA<RoundedRectangleBorder>(),
    reason: 'Button shape in brand $brand must be RoundedRectangleBorder',
  );
  final border = material.shape! as RoundedRectangleBorder;
  final radius = border.borderRadius.resolve(TextDirection.ltr);
  expect(
    radius,
    BorderRadius.circular(12),
    reason: 'Button corner radius in brand $brand must be shared 12 radius',
  );
}

Future<void> _captureRetainedDialogIfRequested(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name, {
  Map<String, Object?>? metadata,
}) async {
  final explicitDir =
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.trim().isEmpty) return;
  if (metadata == null &&
      Platform.environment['DUOYI_ADMIN_DENIED_ONLY_CAPTURE'] == '1') {
    return;
  }

  final repoRoot = Platform.environment['DUOYI_RETAINED_DIALOG_REPO_ROOT'];
  final rootDir = Directory(
    repoRoot == null
        ? 'evidence/screenshots'
        : '$repoRoot/evidence/screenshots',
  );
  if (!rootDir.existsSync()) {
    rootDir.createSync(recursive: true);
  }
  final canonicalRoot = rootDir.resolveSymbolicLinksSync();

  final targetDir = Directory(explicitDir.trim());
  if (!targetDir.existsSync()) {
    targetDir.createSync(recursive: true);
  }
  final canonicalTarget = targetDir.resolveSymbolicLinksSync();

  if (canonicalTarget != canonicalRoot &&
      !canonicalTarget.startsWith('$canonicalRoot${Platform.pathSeparator}')) {
    throw StateError(
      'DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR must stay under evidence/screenshots/, got: $explicitDir (target: $canonicalTarget, root: $canonicalRoot)',
    );
  }

  await tester.runAsync(() async {
    final context = boundaryKey.currentContext;
    if (context == null) {
      throw StateError('Capture boundary context missing for: $name');
    }
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('RenderRepaintBoundary missing for: $name');
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('ByteData encoding failed for screenshot: $name');
      }
      final file = File('$canonicalTarget${Platform.pathSeparator}$name.png');
      if (file.existsSync()) {
        throw StateError('Preserve existing screenshot: ${file.path}');
      }
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes.buffer.asUint8List());
      if (metadata != null) {
        final dataFile = File(
          '$canonicalTarget${Platform.pathSeparator}$name.json',
        );
        if (dataFile.existsSync()) {
          throw StateError('Preserve existing metadata: ${dataFile.path}');
        }
        dataFile.writeAsStringSync('${jsonEncode(metadata)}\n');
      }
    } finally {
      image.dispose();
    }
  });
}

class _TestAuthProvider extends AuthProvider {
  final ApiClient _client;
  final List<String>? permissions;
  final bool isAdminUser;

  _TestAuthProvider({
    required ApiClient client,
    this.permissions,
    this.isAdminUser = true,
  }) : _client = client;

  @override
  ApiClient get client => _client;

  @override
  AuthState get state => AuthState(
    userId: 'admin-authorized-user',
    username: 'admin',
    token: 'synthetic-admin-token',
    isAdmin: isAdminUser,
    adminPermissions: permissions,
  );
}

class _AdminFixture {
  final _TestAuthProvider auth;
  final ThemeProvider theme;
  final AiService ai;
  final List<http.Request> requests;
  final GlobalKey captureKey;

  _AdminFixture({
    required this.auth,
    required this.theme,
    required this.ai,
    required this.requests,
    required this.captureKey,
  });
}

Future<void> _setupPreferences(String brand) async {
  final initialPrefs = <String, Object>{
    'pref_app_timezone_mode': 'fixed',
    'pref_app_timezone_iana': 'Asia/Shanghai',
    'active_brand': brand,
    'theme_shop_state': jsonEncode({
      'activeBrand': brand,
      'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
    }),
    'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    'flutter.pref_app_timezone_mode': 'fixed',
    'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
    'flutter.active_brand': brand,
    'flutter.theme_shop_state': jsonEncode({
      'activeBrand': brand,
      'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
    }),
    'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
  };
  SharedPreferences.setMockInitialValues(initialPrefs);
}

http.Response _mockHandler(http.Request request) {
  final path = request.url.path;
  final query = request.url.queryParameters;

  http.Response json(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: const {'content-type': 'application/json'},
  );

  if (path == '/api/admin/stats') {
    return json({
      'users': {
        'total': 12,
        'disabled': 0,
        'new_today': 1,
        'active_7d': 6,
        'online': 3,
      },
      'feedback': {'total': 2, 'open': 1, 'in_progress': 1},
      'announcements': {'total': 1, 'published': 1},
    });
  }
  if (path == '/api/admin/settings') {
    final scope = query['scope'];
    if (scope == 'ai') {
      return json({
        'ai_enabled': true,
        'ai_model': 'gemini-1.5-pro',
        'ai_api_key_set': true,
        'ai_daily_quota': 1000,
      });
    }
    if (scope == 'backup') {
      return json({
        'backup_enabled': true,
        'backup_max_size_kb': 2048,
        'backup_interval_minutes': 30,
        'backup_retain_days': 7,
        'server_backup_enabled': false,
        'local_backups': <dynamic>[],
        'reminder_email_enabled': false,
        'email_service_enabled': false,
      });
    }
    return json({
      'invite_code_required': false,
      'registration_enabled': true,
      'registration_email_required': false,
      'maintenance_mode': false,
      'force_update_required': false,
      'default_registration_coins': 100,
    });
  }
  if (path == '/api/admin/groups') {
    return json({
      'items': [
        {
          'id': 'group_default',
          'name': '默认用户组',
          'description': '系统默认普通用户组',
          'default_time_coins': 100,
          'is_active': true,
          'user_count': 5,
          'created_at': '2026-10-01 08:00:00',
          'updated_at': '2026-10-01 08:00:00',
        },
      ],
      'total': 1,
      'limit': int.tryParse(query['limit'] ?? '') ?? 20,
      'offset': int.tryParse(query['offset'] ?? '') ?? 0,
      'has_more': false,
    });
  }
  if (path == '/api/admin/roles') {
    return json([
      {
        'id': 'role_admin',
        'name': '系统管理员',
        'description': '全局管理权限角色',
        'permissions': [
          'users',
          'settings',
          'ai',
          'backup',
          'groups',
          'announcements',
          'feedback',
          'invites',
          'audit',
        ],
        'is_active': true,
      },
    ]);
  }
  if (path == '/api/admin/users') {
    final limit = int.tryParse(query['limit'] ?? '') ?? 20;
    final offset = int.tryParse(query['offset'] ?? '') ?? 0;
    const total = 45;
    return json({
      'items': [
        {
          'user_id': 'user-$offset',
          'username': 'admin-test-user-$offset',
          'display_name': '测试管理员',
          'email': 'admin@duoyi.test',
          'email_verified': true,
          'is_admin': true,
          'is_disabled': false,
          'online': true,
          'admin_permissions': ['users', 'settings', 'ai'],
          'group_id': 'group_default',
          'role_id': 'role_admin',
          'coin_balance': 200,
          'lifetime_coins': 500,
          'created_at': '2026-10-01 08:00:00',
          'last_login_at': '2026-10-24 06:00:00',
          'last_active_at': '2026-10-24 06:50:00',
        },
      ],
      'total': total,
      'limit': limit,
      'offset': offset,
      'has_more': offset + limit < total,
    });
  }
  if (path == '/api/admin/announcements') {
    return json({
      'items': [
        {
          'id': 'anno-1',
          'title': '测试公告标题',
          'content': '测试公告内容',
          'level': 'info',
          'is_published': true,
          'created_at': '2026-10-01 08:00:00',
        },
      ],
      'total': 1,
      'limit': int.tryParse(query['limit'] ?? '') ?? 20,
      'offset': int.tryParse(query['offset'] ?? '') ?? 0,
      'has_more': false,
    });
  }
  if (path == '/api/admin/feedback') {
    return json({
      'items': [
        {
          'id': 'feedback-1',
          'user_id': 'user-1',
          'username': 'feedback-author',
          'type': 'feature',
          'content': '反馈内容示例',
          'status': 'open',
          'created_at': '2026-10-01 08:00:00',
        },
      ],
      'total': 1,
      'limit': int.tryParse(query['limit'] ?? '') ?? 20,
      'offset': int.tryParse(query['offset'] ?? '') ?? 0,
      'has_more': false,
    });
  }
  if (path == '/api/admin/invite-codes') {
    return json({
      'items': [
        {
          'code': 'INVITE2026TEST',
          'created_by': 'admin',
          'used_by': null,
          'is_used': false,
          'created_at': '2026-10-01 08:00:00',
          'expires_at': null,
        },
      ],
      'total': 1,
      'limit': int.tryParse(query['limit'] ?? '') ?? 20,
      'offset': int.tryParse(query['offset'] ?? '') ?? 0,
      'has_more': false,
    });
  }
  if (path == '/api/admin/audit-log') {
    return json({
      'items': [
        {
          'id': 'audit-1',
          'user_id': 'user-1',
          'action': 'admin.login',
          'details': {'ip': '127.0.0.1'},
          'created_at': '2026-10-24 06:00:00',
        },
      ],
      'total': 1,
      'limit': int.tryParse(query['limit'] ?? '') ?? 20,
      'offset': int.tryParse(query['offset'] ?? '') ?? 0,
      'has_more': false,
    });
  }
  if (path == '/api/admin/backups' || path == '/api/admin/server-backups') {
    return json({
      'items': <dynamic>[],
      'total': 0,
      'limit': int.tryParse(query['limit'] ?? '') ?? 20,
      'offset': int.tryParse(query['offset'] ?? '') ?? 0,
      'has_more': false,
    });
  }
  return json({'ok': true});
}

Future<_AdminFixture> _mountAdminFixture(
  WidgetTester tester, {
  required String brand,
  required AppLocale locale,
  required Size size,
  required double scale,
  int initialTabIndex = 2,
  List<String>? permissions,
  bool isAdminUser = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await _setupPreferences(brand);
  I18n.setLocale(locale);

  final theme = ThemeProvider();
  await tester.runAsync(() async {
    await theme.loadFromStorage();
    await loadWidgetPolishScreenshotFonts();
  });

  final requests = <http.Request>[];
  final mockClient = MockClient((request) async {
    requests.add(request);
    return _mockHandler(request);
  });
  final apiClient = ApiClient(
    baseUrl: 'https://duoyi.test',
    token: 'synthetic-admin-token',
    httpClient: mockClient,
  );
  final auth = _TestAuthProvider(
    client: apiClient,
    permissions: permissions,
    isAdminUser: isAdminUser,
  );
  final ai = AiService()..attachClient(apiClient);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    ai.dispose();
    auth.dispose();
    theme.dispose();
  });

  final captureKey = GlobalKey();
  final fonts = widgetPolishScreenshotTheme();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AiService>.value(value: ai),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, currentTheme, _) =>
            ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (context, currentLocale, _) {
                final baseTheme = currentTheme.brand.theme;
                final themed = baseTheme.copyWith(
                  textTheme: fonts.textTheme,
                  primaryTextTheme: fonts.primaryTextTheme,
                );
                return MaterialApp(
                  locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: themed,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: RepaintBoundary(key: captureKey, child: child!),
                  ),
                  home: BrandRouteSurface(
                    child: AdminScreen(initialTabIndex: initialTabIndex),
                  ),
                );
              },
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _AdminFixture(
    auth: auth,
    theme: theme,
    ai: ai,
    requests: requests,
    captureKey: captureKey,
  );
}
