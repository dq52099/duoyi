import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart' show AppSurfaceCard;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

const _layouts = [
  (name: 'ordinary', size: Size(390, 844), scale: 1.0),
  (name: '320px200percent', size: Size(320, 844), scale: 2.0),
];

const _priorityBrands = ['defaultBrand', 'liquidGlass'];

const _locales = [AppLocale.zh, AppLocale.en];

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  group('Priority admin mail Resend Base URL endpoint layout matrix', () {
    for (final brand in _priorityBrands) {
      for (final locale in _locales) {
        for (final layout in _layouts) {
          testWidgets(
            'Resend Base URL field readable with complete glyphs, target44, and semantics $brand ${locale.name} ${layout.name}',
            (tester) async {
              final semanticsHandle = tester.ensureSemantics();
              try {
                final fixture = await _mountAdminFixture(
                  tester,
                  brand: brand,
                  locale: locale,
                  size: layout.size,
                  scale: layout.scale,
                  initialTabIndex: 3, // Backup & email settings tab
                  permissions: const ['backup', 'settings', 'ai'],
                );

                final backupScrollable =
                    _moduleVerticalScrollable(modulePrefix: 'admin-backup-').first;

                final fieldFinder = _findResendBaseUrlField();
                await tester.scrollUntilVisible(
                  fieldFinder,
                  300,
                  scrollable: backupScrollable,
                );
                await tester.ensureVisible(fieldFinder);
                await tester.pumpAndSettle();
                expect(fieldFinder, findsOneWidget);

                // Verify minimum 44x44 tap target on the field
                _verifyTapTarget(
                  tester,
                  targetFinder: fieldFinder,
                  role:
                      'Resend Base URL field ($brand, ${locale.name}, ${layout.name})',
                );

                // Verify complete expected label
                final expectedLabel = locale == AppLocale.zh
                    ? 'Resend 服务地址'
                    : 'Resend Base URL';
                final labelFinder = find.text(expectedLabel);
                expect(
                  labelFinder,
                  findsOneWidget,
                  reason:
                      'Expected label "$expectedLabel" for locale ${locale.name} must exist on Resend Base URL field',
                );
                await tester.ensureVisible(labelFinder);
                await tester.pumpAndSettle();

                final surfaceFinder = find
                    .ancestor(
                      of: fieldFinder,
                      matching: find.byType(AppSurfaceCard),
                    )
                    .first;

                // Verify RenderParagraph no ellipsis, complete glyphs, and line bounds
                await _assertReadableLabelWithGlyphs(
                  tester,
                  textFinder: labelFinder,
                  surfaceFinder: surfaceFinder,
                  boundaryKey: fixture.captureKey,
                  role:
                      'Resend Base URL label ($brand, ${locale.name}, ${layout.name})',
                );

                // Verify semantics: isTextField, single label association, no redundant static duplicate
                _verifyMailEndpointFieldSemantics(
                  tester,
                  fieldFinder: fieldFinder,
                  expectedLabel: expectedLabel,
                  scopeFinder: surfaceFinder,
                );

                // Verify TextField is editable with synthetic draft endpoint
                const syntheticDraft =
                    'https://synthetic-resend-proxy.internal/v1';
                await tester.enterText(fieldFinder, syntheticDraft);
                await tester.pumpAndSettle();

                final fieldWidget = tester.widget<TextField>(fieldFinder);
                expect(
                  fieldWidget.controller?.text,
                  syntheticDraft,
                  reason:
                      'Editing Resend Base URL field must update controller text',
                );

                final fieldBox = tester.renderObject<RenderBox>(fieldFinder);
                final labelBox = tester.renderObject<RenderBox>(labelFinder);

                final observation = {
                  'scenario':
                      'admin-mail-resend-endpoint-$brand-${locale.name}-${layout.name}',
                  'brand': brand,
                  'locale': locale.name,
                  'layout': layout.name,
                  'viewport': {
                    'width': layout.size.width,
                    'height': layout.size.height,
                    'scale': layout.scale,
                  },
                  'field': {
                    'width': fieldBox.size.width,
                    'height': fieldBox.size.height,
                  },
                  'label': {
                    'text': expectedLabel,
                    'width': labelBox.size.width,
                    'height': labelBox.size.height,
                  },
                  'tapTargetPass':
                      fieldBox.size.width >= 43.99 &&
                      fieldBox.size.height >= 43.99,
                };

                // Export layout measurements JSON if requested
                await _exportLayoutMeasurementsIfRequested(
                  tester,
                  'admin-mail-resend-endpoint-$brand-${locale.name}-${layout.name}',
                  observation,
                );

                // Export PNG screenshot if requested
                await _captureRetainedScreenshotIfRequested(
                  tester,
                  fixture.captureKey,
                  'admin-mail-resend-endpoint-$brand-${locale.name}-${layout.name}',
                );

                // Verify no unsaved mutation writes sent to backend
                final mutations =
                    fixture.requests.where((r) => r.method != 'GET');
                expect(
                  mutations,
                  isEmpty,
                  reason:
                      'Editing synthetic draft endpoint must not send mutation requests to backend',
                );

                expect(tester.takeException(), isNull);
              } finally {
                semanticsHandle.dispose();
              }
            },
          );
        }
      }
    }
  });

  group('Priority admin mail Resend Base URL mounted transitions', () {
    testWidgets(
      'preserves Resend Base URL controller instance, selection, focus, and synthetic draft across mounted brand transitions defaultBrand <-> liquidGlass',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final fixture = await _mountAdminFixture(
            tester,
            brand: 'defaultBrand',
            locale: AppLocale.zh,
            size: const Size(320, 844),
            scale: 2.0,
            initialTabIndex: 3,
            permissions: const ['backup', 'settings', 'ai'],
          );

          final backupScrollable =
              _moduleVerticalScrollable(modulePrefix: 'admin-backup-').first;
          final fieldFinder = _findResendBaseUrlField();
          await tester.scrollUntilVisible(
            fieldFinder,
            300,
            scrollable: backupScrollable,
          );
          await tester.ensureVisible(fieldFinder);
          await tester.pumpAndSettle();

          const syntheticDraft =
              'https://synthetic-resend-proxy.internal/v1';
          await tester.enterText(fieldFinder, syntheticDraft);
          final controller =
              tester.widget<TextField>(fieldFinder).controller!;

          final editableFinder = find.descendant(
            of: fieldFinder,
            matching: find.byType(EditableText),
          );
          expect(editableFinder, findsOneWidget);
          final focusNode =
              tester.widget<EditableText>(editableFinder).focusNode;
          focusNode.requestFocus();
          await tester.pumpAndSettle();

          const selection = TextSelection(baseOffset: 8, extentOffset: 24);
          controller.selection = selection;
          await tester.pumpAndSettle();

          final initialField = tester.widget<TextField>(fieldFinder);
          expect(initialField.controller, same(controller));
          expect(controller.text, syntheticDraft);
          expect(controller.selection, selection);
          expect(focusNode.hasFocus, isTrue);

          final screenState = tester.state(find.byType(AdminScreen));

          // Live mounted brand transition: defaultBrand -> liquidGlass
          await tester.runAsync(() async {
            await fixture.theme.setBrand('liquidGlass');
          });
          await tester.pumpAndSettle();

          expect(tester.state(find.byType(AdminScreen)), same(screenState));
          final lgField = tester.widget<TextField>(fieldFinder);
          expect(lgField.controller, same(controller));
          expect(controller.text, syntheticDraft);
          expect(controller.selection, selection);
          final lgEditable = tester.widget<EditableText>(editableFinder);
          expect(lgEditable.focusNode, same(focusNode));
          expect(focusNode.hasFocus, isTrue);

          _verifyTapTarget(
            tester,
            targetFinder: fieldFinder,
            role: 'Resend Base URL field (liquidGlass brand transition)',
          );

          // Live mounted brand transition back: liquidGlass -> defaultBrand
          await tester.runAsync(() async {
            await fixture.theme.setBrand('defaultBrand');
          });
          await tester.pumpAndSettle();

          expect(tester.state(find.byType(AdminScreen)), same(screenState));
          final dfField = tester.widget<TextField>(fieldFinder);
          expect(dfField.controller, same(controller));
          expect(controller.text, syntheticDraft);
          expect(controller.selection, selection);
          final dfEditable = tester.widget<EditableText>(editableFinder);
          expect(dfEditable.focusNode, same(focusNode));
          expect(focusNode.hasFocus, isTrue);

          _verifyTapTarget(
            tester,
            targetFinder: fieldFinder,
            role: 'Resend Base URL field (defaultBrand restored)',
          );

          final mutations = fixture.requests.where((r) => r.method != 'GET');
          expect(
            mutations,
            isEmpty,
            reason: 'Zero mutation writes across brand switches',
          );
          expect(tester.takeException(), isNull);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      'preserves Resend Base URL controller instance, selection, focus, and synthetic draft across mounted locale transitions zh <-> en',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final fixture = await _mountAdminFixture(
            tester,
            brand: 'liquidGlass',
            locale: AppLocale.zh,
            size: const Size(320, 844),
            scale: 2.0,
            initialTabIndex: 3,
            permissions: const ['backup', 'settings', 'ai'],
          );

          final backupScrollable =
              _moduleVerticalScrollable(modulePrefix: 'admin-backup-').first;
          final fieldFinder = _findResendBaseUrlField();
          await tester.scrollUntilVisible(
            fieldFinder,
            300,
            scrollable: backupScrollable,
          );
          await tester.ensureVisible(fieldFinder);
          await tester.pumpAndSettle();

          const syntheticDraft =
              'https://synthetic-resend-proxy.internal/v1';
          await tester.enterText(fieldFinder, syntheticDraft);
          final controller =
              tester.widget<TextField>(fieldFinder).controller!;

          final editableFinder = find.descendant(
            of: fieldFinder,
            matching: find.byType(EditableText),
          );
          expect(editableFinder, findsOneWidget);
          final focusNode =
              tester.widget<EditableText>(editableFinder).focusNode;
          focusNode.requestFocus();
          await tester.pumpAndSettle();

          const selection = TextSelection(baseOffset: 8, extentOffset: 24);
          controller.selection = selection;
          await tester.pumpAndSettle();

          final screenState = tester.state(find.byType(AdminScreen));
          final initialField = tester.widget<TextField>(fieldFinder);
          expect(initialField.controller, same(controller));
          expect(controller.text, syntheticDraft);
          expect(controller.selection, selection);
          expect(focusNode.hasFocus, isTrue);

          // Initial Chinese label
          const zhLabel = 'Resend 服务地址';
          final zhLabelFinder = find.text(zhLabel);
          expect(zhLabelFinder, findsOneWidget);
          final surfaceFinder = find
              .ancestor(
                of: fieldFinder,
                matching: find.byType(AppSurfaceCard),
              )
              .first;
          _verifyMailEndpointFieldSemantics(
            tester,
            fieldFinder: fieldFinder,
            expectedLabel: zhLabel,
            scopeFinder: surfaceFinder,
          );

          // Live mounted locale transition: zh -> en
          I18n.setLocale(AppLocale.en);
          await tester.pumpAndSettle();

          expect(tester.state(find.byType(AdminScreen)), same(screenState));
          final enField = tester.widget<TextField>(fieldFinder);
          expect(enField.controller, same(controller));
          expect(controller.text, syntheticDraft);
          expect(controller.selection, selection);
          final enEditable = tester.widget<EditableText>(editableFinder);
          expect(enEditable.focusNode, same(focusNode));
          expect(focusNode.hasFocus, isTrue);

          // Dynamic English label rendered completely
          const enLabel = 'Resend Base URL';
          final enLabelFinder = find.text(enLabel);
          expect(enLabelFinder, findsOneWidget);
          _verifyMailEndpointFieldSemantics(
            tester,
            fieldFinder: fieldFinder,
            expectedLabel: enLabel,
            scopeFinder: surfaceFinder,
          );

          // Live mounted locale transition back: en -> zh
          I18n.setLocale(AppLocale.zh);
          await tester.pumpAndSettle();

          expect(tester.state(find.byType(AdminScreen)), same(screenState));
          final zhFieldBack = tester.widget<TextField>(fieldFinder);
          expect(zhFieldBack.controller, same(controller));
          expect(controller.text, syntheticDraft);
          expect(controller.selection, selection);
          final zhEditable = tester.widget<EditableText>(editableFinder);
          expect(zhEditable.focusNode, same(focusNode));
          expect(focusNode.hasFocus, isTrue);

          final zhLabelBack = find.text(zhLabel);
          expect(zhLabelBack, findsOneWidget);
          _verifyMailEndpointFieldSemantics(
            tester,
            fieldFinder: fieldFinder,
            expectedLabel: zhLabel,
            scopeFinder: surfaceFinder,
          );

          final mutations = fixture.requests.where((r) => r.method != 'GET');
          expect(
            mutations,
            isEmpty,
            reason: 'Zero mutation writes across locale switches',
          );
          expect(tester.takeException(), isNull);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      'preserves Resend Base URL controller instance, selection, focus, and synthetic draft across ordinary <-> compact layout transitions',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final fixture = await _mountAdminFixture(
            tester,
            brand: 'defaultBrand',
            locale: AppLocale.zh,
            size: const Size(390, 844),
            scale: 1.0,
            initialTabIndex: 3,
            permissions: const ['backup', 'settings', 'ai'],
          );

          final backupScrollable =
              _moduleVerticalScrollable(modulePrefix: 'admin-backup-').first;
          final fieldFinder = _findResendBaseUrlField();
          await tester.scrollUntilVisible(
            fieldFinder,
            300,
            scrollable: backupScrollable,
          );
          await tester.ensureVisible(fieldFinder);
          await tester.pumpAndSettle();

          const syntheticDraft =
              'https://synthetic-resend-proxy.internal/v1';
          await tester.enterText(fieldFinder, syntheticDraft);
          final controller =
              tester.widget<TextField>(fieldFinder).controller!;

          final editableFinder = find.descendant(
            of: fieldFinder,
            matching: find.byType(EditableText),
          );
          expect(editableFinder, findsOneWidget);
          final focusNode =
              tester.widget<EditableText>(editableFinder).focusNode;
          focusNode.requestFocus();
          await tester.pumpAndSettle();

          const selection = TextSelection(baseOffset: 8, extentOffset: 24);
          controller.selection = selection;
          await tester.pumpAndSettle();

          final screenState = tester.state(find.byType(AdminScreen));
          final initialField = tester.widget<TextField>(fieldFinder);
          expect(initialField.controller, same(controller));
          expect(controller.text, syntheticDraft);
          expect(controller.selection, selection);
          expect(focusNode.hasFocus, isTrue);

          // Live mounted layout transition: ordinary -> 320px200percent
          await fixture.updateLayout(
            tester,
            size: const Size(320, 844),
            scale: 2.0,
          );

          expect(tester.state(find.byType(AdminScreen)), same(screenState));
          final compactField = tester.widget<TextField>(fieldFinder);
          expect(compactField.controller, same(controller));
          expect(controller.text, syntheticDraft);
          expect(controller.selection, selection);
          final compactEditable = tester.widget<EditableText>(editableFinder);
          expect(compactEditable.focusNode, same(focusNode));
          expect(focusNode.hasFocus, isTrue);

          // Live mounted layout transition back: 320px200percent -> ordinary
          await fixture.updateLayout(
            tester,
            size: const Size(390, 844),
            scale: 1.0,
          );

          expect(tester.state(find.byType(AdminScreen)), same(screenState));
          final restoredField = tester.widget<TextField>(fieldFinder);
          expect(restoredField.controller, same(controller));
          expect(controller.text, syntheticDraft);
          expect(controller.selection, selection);
          final restoredEditable = tester.widget<EditableText>(editableFinder);
          expect(restoredEditable.focusNode, same(focusNode));
          expect(focusNode.hasFocus, isTrue);

          final mutations = fixture.requests.where((r) => r.method != 'GET');
          expect(
            mutations,
            isEmpty,
            reason: 'Zero mutation writes across layout transitions',
          );
          expect(tester.takeException(), isNull);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      'cancelling or exiting admin screen preserves backend state with zero mutation requests',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final fixture = await _mountAdminFixture(
            tester,
            brand: 'defaultBrand',
            locale: AppLocale.zh,
            size: const Size(320, 844),
            scale: 2.0,
            initialTabIndex: 3,
            permissions: const ['backup', 'settings', 'ai'],
          );

          final backupScrollable =
              _moduleVerticalScrollable(modulePrefix: 'admin-backup-').first;
          final fieldFinder = _findResendBaseUrlField();
          await tester.scrollUntilVisible(
            fieldFinder,
            300,
            scrollable: backupScrollable,
          );
          await tester.ensureVisible(fieldFinder);
          await tester.pumpAndSettle();

          await tester.enterText(
            fieldFinder,
            'https://unsaved-temporary-endpoint.example.org',
          );
          await tester.pumpAndSettle();

          // Exit / pop route by unmounting screen
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();

          // Zero mutations
          final mutations = fixture.requests.where((r) => r.method != 'GET');
          expect(
            mutations,
            isEmpty,
            reason:
                'Leaving screen must never write unsaved draft synthetic endpoint to backend API',
          );

          expect(tester.takeException(), isNull);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );
  });
}

Finder _findResendBaseUrlField() {
  return find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.decoration?.hintText == 'https://api.resend.com' ||
            (w.controller != null &&
                (w.controller!.text == 'https://api.resend.com' ||
                    w.controller!.text.contains('resend')))),
  );
}

void _verifyTapTarget(
  WidgetTester tester, {
  required Finder targetFinder,
  required String role,
}) {
  expect(targetFinder, findsOneWidget);
  final size = tester.getSize(targetFinder);
  expect(
    size.width,
    greaterThanOrEqualTo(44.0 - 0.01),
    reason: '$role width ${size.width} should be at least 44px',
  );
  expect(
    size.height,
    greaterThanOrEqualTo(44.0 - 0.01),
    reason: '$role height ${size.height} should be at least 44px',
  );
}

Future<void> _assertReadableLabelWithGlyphs(
  WidgetTester tester, {
  required Finder textFinder,
  required Finder surfaceFinder,
  required GlobalKey boundaryKey,
  required String role,
}) async {
  expect(
    textFinder,
    findsOneWidget,
    reason: '$role text must exist (no vacuity)',
  );
  final richTextFinder = find.descendant(
    of: textFinder,
    matching: find.byType(RichText),
  );
  final target =
      richTextFinder.evaluate().isNotEmpty ? richTextFinder : textFinder;
  final element = tester.element(target);
  final paragraph = tester.renderObject<RenderParagraph>(target);

  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role didExceedMaxLines must be false (no line truncation)',
  );

  final text = paragraph.text.toPlainText();
  expect(text.trim(), isNotEmpty, reason: '$role text must not be empty');
  expect(
    text.contains('…'),
    isFalse,
    reason: '$role must not contain ellipsis character …',
  );

  // Verify full content produces non-empty layout selection boxes
  final totalBoxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(totalBoxes, isNotEmpty, reason: '$role must produce layout boxes');

  // Words should stay on their respective line
  for (final word in RegExp(
    r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*",
  ).allMatches(text)) {
    final wordBoxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: word.start, extentOffset: word.end),
    );
    expect(wordBoxes, isNotEmpty);
    expect(
      wordBoxes.map((box) => box.top.round()).toSet(),
      hasLength(1),
      reason: 'Word ${word.group(0)} must remain on one line',
    );
  }

  // Determine actual ancestor scrollable viewport and surface bounds
  final scroll = Scrollable.maybeOf(element);
  final surfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
  final surfaceRect = Rect.fromPoints(
    surfaceBox.localToGlobal(Offset.zero),
    surfaceBox.localToGlobal(
      Offset(surfaceBox.size.width, surfaceBox.size.height),
    ),
  );
  final viewport = scroll == null
      ? surfaceRect
      : tester.getRect(find.byWidget(scroll.widget));

  // Check every non-blank character: each non-blank character must have at least one box
  var nonBlankGlyphCount = 0;
  int i = 0;
  while (i < text.length) {
    final codeUnit = text.codeUnitAt(i);
    int end = i + 1;
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && end < text.length) {
      end = i + 2;
    }
    final cluster = text.substring(i, end);
    if (cluster.trim().isNotEmpty) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: end),
      );
      expect(
        boxes,
        isNotEmpty,
        reason: '$role non-blank character ($cluster) must have a glyph box',
      );
      for (final box in boxes) {
        nonBlankGlyphCount++;
        expect(
          box.right - box.left,
          greaterThan(0),
          reason: '$role glyph ($cluster) must have positive width',
        );
        expect(
          box.bottom - box.top,
          greaterThan(0),
          reason: '$role glyph ($cluster) must have positive height',
        );

        Rect global(ui.TextBox current) => Rect.fromPoints(
          paragraph.localToGlobal(Offset(current.left, current.top)),
          paragraph.localToGlobal(Offset(current.right, current.bottom)),
        );

        if (scroll != null) {
          final delta = global(box).center.dy - viewport.center.dy;
          final position = scroll.position;
          position.jumpTo(
            (position.pixels + delta).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }

        final actual = global(box);
        expect(
          actual.left,
          greaterThanOrEqualTo(viewport.left - 0.5),
          reason:
              '$role glyph ($cluster) left ${actual.left} must be >= viewport left ${viewport.left}',
        );
        expect(
          actual.right,
          lessThanOrEqualTo(viewport.right + 0.5),
          reason:
              '$role glyph ($cluster) right ${actual.right} must be <= viewport right ${viewport.right}',
        );
        expect(
          actual.top,
          greaterThanOrEqualTo(viewport.top - 0.5),
          reason:
              '$role glyph ($cluster) top ${actual.top} must be >= viewport top ${viewport.top}',
        );
        expect(
          actual.bottom,
          lessThanOrEqualTo(viewport.bottom + 0.5),
          reason:
              '$role glyph ($cluster) bottom ${actual.bottom} must be <= viewport bottom ${viewport.bottom}',
        );

        expect(
          actual.left,
          greaterThanOrEqualTo(surfaceRect.left - 0.5),
          reason:
              '$role glyph ($cluster) left ${actual.left} must be >= surface left ${surfaceRect.left}',
        );
        expect(
          actual.right,
          lessThanOrEqualTo(surfaceRect.right + 0.5),
          reason:
              '$role glyph ($cluster) right ${actual.right} must be <= surface right ${surfaceRect.right}',
        );
      }
    }
    i = end;
  }

  expect(
    nonBlankGlyphCount,
    greaterThan(0),
    reason: '$role must have at least one non-blank glyph box',
  );
}

void _verifyMailEndpointFieldSemantics(
  WidgetTester tester, {
  required Finder fieldFinder,
  required String expectedLabel,
  Finder? scopeFinder,
}) {
  expect(fieldFinder, findsOneWidget);

  // 1. Locate editable input semantics node
  Finder inputFinder = find.descendant(
    of: fieldFinder,
    matching: find.byType(EditableText),
  );
  if (inputFinder.evaluate().isEmpty) {
    inputFinder = fieldFinder;
  }
  final semantics = tester.getSemantics(inputFinder);

  // 2. SemanticsFlag.isTextField must be true
  expect(
    semantics.flagsCollection.isTextField,
    isTrue,
    reason:
        'Resend Base URL target must have SemanticsFlag.isTextField set on its semantics node',
  );

  // 3. Associates complete expected label
  final label = semantics.label;
  final value = semantics.value;
  final hint = semantics.hint;
  final tooltip = semantics.tooltip;
  final combined = '$label\n$value\n$hint\n$tooltip';
  expect(
    label.contains(expectedLabel) || combined.contains(expectedLabel),
    isTrue,
    reason:
        'Field semantics (label="$label", hint="$hint") must associate complete label "$expectedLabel"',
  );

  // 4. Label read only once on the field (no redundant repetition)
  final countInField = expectedLabel.allMatches(label).length;
  expect(
    countInField,
    lessThanOrEqualTo(1),
    reason:
        'Label "$expectedLabel" must not be repeated multiple times in field semantics: "$label"',
  );

  // 5. Scope-protected check: no duplicate independent static label node in traversal
  final traversalNodes = tester.semantics.simulatedAccessibilityTraversal();
  if (scopeFinder != null && scopeFinder.evaluate().isNotEmpty) {
    final scopeRect = tester.getRect(scopeFinder);
    final duplicateStaticNodes = traversalNodes.where(
      (s) =>
          !s.flagsCollection.isTextField &&
          s.label.trim() == expectedLabel.trim() &&
          scopeRect.contains(s.rect.center),
    );
    expect(
      duplicateStaticNodes,
      isEmpty,
      reason:
          'Static label "$expectedLabel" within scope must not produce duplicate independent semantics node in simulatedAccessibilityTraversal',
    );
  } else {
    final duplicateStaticNodes = traversalNodes.where(
      (s) =>
          !s.flagsCollection.isTextField &&
          s.label.trim() == expectedLabel.trim(),
    );
    expect(
      duplicateStaticNodes,
      isEmpty,
      reason:
          'Static label "$expectedLabel" must not produce duplicate independent semantics node in simulatedAccessibilityTraversal',
    );
  }
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

Future<void> _captureRetainedScreenshotIfRequested(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.trim().isEmpty) return;

  await tester.runAsync(() async {
    final context = boundaryKey.currentContext;
    if (context == null) return;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final file = File('${explicitDir.trim()}${Platform.pathSeparator}$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _exportLayoutMeasurementsIfRequested(
  WidgetTester tester,
  String name,
  Map<String, dynamic> data,
) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_MEASUREMENTS_DIR'];
  if (explicitDir == null || explicitDir.trim().isEmpty) return;

  await tester.runAsync(() async {
    final dir = Directory(explicitDir.trim());
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}${Platform.pathSeparator}$name.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data),
    );
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
  final ValueNotifier<({Size size, double scale})> layoutNotifier;

  _AdminFixture({
    required this.auth,
    required this.theme,
    required this.ai,
    required this.requests,
    required this.captureKey,
    required this.layoutNotifier,
  });

  Future<void> updateLayout(
    WidgetTester tester, {
    required Size size,
    required double scale,
  }) async {
    tester.view.physicalSize = size;
    layoutNotifier.value = (size: size, scale: scale);
    await tester.pumpAndSettle();
  }
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
    if (scope == 'backup') {
      return json({
        'backup_enabled': true,
        'backup_max_size_kb': 2048,
        'backup_interval_minutes': 30,
        'backup_retain_days': 7,
        'server_backup_enabled': false,
        'server_backup_interval_minutes': 720,
        'server_backup_retain_days': 14,
        'openlist_backup_enabled': false,
        'openlist_webdav_url': '',
        'openlist_public_url': '',
        'openlist_username': '',
        'openlist_password_set': false,
        'openlist_backup_path': '/duoyi-backups',
        'backup_email_enabled': false,
        'backup_email_to': '',
        'backup_email_from': '',
        'backup_email_smtp_host': '',
        'backup_email_smtp_port': 465,
        'backup_email_smtp_username': '',
        'backup_email_smtp_password_set': false,
        'reminder_email_enabled': false,
        'reminder_email_to': '',
        'reminder_email_from': '',
        'reminder_email_smtp_host': '',
        'reminder_email_smtp_port': 465,
        'reminder_email_smtp_username': '',
        'reminder_email_smtp_password_set': false,
        'email_service_enabled': false,
        'account_email_enabled': true,
        'email_auto_switch_enabled': false,
        'email_code_primary_provider': 'claw163',
        'email_code_backup_provider': 'resend',
        'email_code_active_slot': 'primary',
        'email_title': '多仪',
        'email_sender_name': '多仪',
        'openclaw_mail_user': '',
        'openclaw_mail_api_key_set': false,
        'resend_base_url': 'https://api.resend.com',
        'resend_api_key': '',
        'resend_api_key_set': false,
        'resend_from': '多仪 <noreply@mail.6688667.xyz>',
        'system_notice_email_to': '',
        'email_smtp_host': '',
        'email_smtp_port': 465,
        'email_smtp_username': '',
        'email_smtp_password_set': false,
        'email_smtp_use_ssl': true,
      });
    }
    if (scope == 'ai') {
      return json({
        'ai_enabled': true,
        'ai_base_url': '',
        'ai_model': 'gemini-1.5-pro',
        'ai_api_key_set': true,
        'ai_daily_quota': 1000,
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
  if (path == '/api/admin/backups' || path == '/api/admin/server-backups') {
    return json({
      'items': <dynamic>[],
      'total': 0,
      'limit': int.tryParse(query['limit'] ?? '') ?? 20,
      'offset': int.tryParse(query['offset'] ?? '') ?? 0,
      'has_more': false,
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
          'admin_permissions': ['users', 'settings', 'ai', 'backup'],
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
  return json({'ok': true});
}

Future<_AdminFixture> _mountAdminFixture(
  WidgetTester tester, {
  required String brand,
  required AppLocale locale,
  required Size size,
  required double scale,
  int initialTabIndex = 3,
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
    await loadWeeklyReviewScreenshotFonts();
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

  final layoutNotifier = ValueNotifier<({Size size, double scale})>(
    (size: size, scale: scale),
  );

  addTearDown(() async {
    layoutNotifier.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    ai.dispose();
    auth.dispose();
    theme.dispose();
  });

  final captureKey = GlobalKey();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AiService>.value(value: ai),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, currentTheme, _) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, currentLocale, _) {
            final baseTheme = currentTheme.brand.theme;
            return ValueListenableBuilder<({Size size, double scale})>(
              valueListenable: layoutNotifier,
              builder: (context, currentLayout, _) {
                return MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: baseTheme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: currentLayout.size,
                      textScaler: TextScaler.linear(currentLayout.scale),
                    ),
                    child: RepaintBoundary(key: captureKey, child: child!),
                  ),
                  home: BrandRouteSurface(
                    remountOnLocaleChange: false,
                    child: AdminScreen(initialTabIndex: initialTabIndex),
                  ),
                );
              },
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
    layoutNotifier: layoutNotifier,
  );
}
