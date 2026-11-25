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

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  group('Priority admin Base URL label readability layout matrix', () {
    for (final brand in _priorityBrands) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        for (final layout in _layouts) {
          testWidgets(
            'Base URL label readable with complete glyphs, surface bounds, and semantics $brand ${locale.name} ${layout.name}',
            (tester) async {
              final semanticsHandle = tester.ensureSemantics();
              try {
                final fixture = await _mountAdminFixture(
                  tester,
                  brand: brand,
                  locale: locale,
                  size: layout.size,
                  scale: layout.scale,
                  initialTabIndex: 2, // AI settings tab
                );

                final aiScrollable =
                    _moduleVerticalScrollable(modulePrefix: 'admin-ai-').first;

                final expectedLabel = AdminUiCopy.aiBaseUrlLabelFor(locale);
                final labelFinder = find.text(expectedLabel);

                await tester.scrollUntilVisible(
                  labelFinder,
                  300,
                  scrollable: aiScrollable,
                );
                await tester.ensureVisible(labelFinder);
                await tester.pumpAndSettle();

                final surfaceFinder = find
                    .ancestor(
                      of: labelFinder,
                      matching: find.byType(AppSurfaceCard),
                    )
                    .first;

                await _assertReadableLabelWithGlyphs(
                  tester,
                  textFinder: labelFinder,
                  surfaceFinder: surfaceFinder,
                  boundaryKey: fixture.captureKey,
                  role:
                      'Base URL label ($brand, ${locale.name}, ${layout.name})',
                );

                final baseFieldFinder = find.byKey(
                  const ValueKey('admin_ai_base_url_field'),
                );
                expect(baseFieldFinder, findsOneWidget);

                // Verify real field semantics association (full label, no duplication, allowing hint merge)
                _verifyBaseUrlFieldSemantics(
                  tester,
                  fieldFinder: baseFieldFinder,
                  expectedLabel: expectedLabel,
                );

                // Verify TextField is editable with draft text
                await tester.enterText(
                  baseFieldFinder,
                  'https://custom-proxy.internal/v1',
                );
                await tester.pumpAndSettle();

                final fieldWidget = tester.widget<TextField>(baseFieldFinder);
                expect(
                  fieldWidget.controller?.text,
                  'https://custom-proxy.internal/v1',
                );

                // Capture screenshot if DUOYI_PRIORITY_THEME_SCREENSHOT_DIR is set
                await _captureRetainedScreenshotIfRequested(
                  tester,
                  fixture.captureKey,
                  'admin-baseurl-$brand-${locale.name}-${layout.name}',
                );

                // No unsaved mutations sent to backend
                final mutations =
                    fixture.requests.where((r) => r.method != 'GET');
                expect(
                  mutations,
                  isEmpty,
                  reason: 'Editing draft must not send mutation requests',
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

  group('Priority admin live mounted transitions preserving controller, selection and focus', () {
    testWidgets(
      'preserves Base URL controller instance, selection, focus, and semantics across live mounted brand transitions defaultBrand <-> liquidGlass',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final fixture = await _mountAdminFixture(
            tester,
            brand: 'defaultBrand',
            locale: AppLocale.zh,
            size: const Size(320, 844),
            scale: 2.0,
            initialTabIndex: 2,
          );

          final aiScrollable =
              _moduleVerticalScrollable(modulePrefix: 'admin-ai-').first;
          final expectedZh = AdminUiCopy.aiBaseUrlLabelFor(AppLocale.zh);
          final labelFinder = find.text(expectedZh);

          await tester.scrollUntilVisible(
            labelFinder,
            300,
            scrollable: aiScrollable,
          );
          await tester.ensureVisible(labelFinder);
          await tester.pumpAndSettle();

          final baseFieldFinder = find.byKey(
            const ValueKey('admin_ai_base_url_field'),
          );
          expect(baseFieldFinder, findsOneWidget);

          const draftText = 'https://api.my-domain.org/v1';
          await tester.enterText(baseFieldFinder, draftText);
          final controller =
              tester.widget<TextField>(baseFieldFinder).controller!;

          // First focus the text field via tap
          await tester.tap(baseFieldFinder);
          await tester.pumpAndSettle();

          // Then set selection on the focused controller
          const selection = TextSelection(baseOffset: 8, extentOffset: 21);
          controller.selection = selection;
          await tester.pumpAndSettle();

          final initialField = tester.widget<TextField>(baseFieldFinder);
          expect(initialField.controller, same(controller));
          expect(controller.text, draftText);
          expect(controller.selection, selection);
          expect(initialField.focusNode?.hasFocus ?? false, isTrue);

          _verifyBaseUrlFieldSemantics(
            tester,
            fieldFinder: baseFieldFinder,
            expectedLabel: expectedZh,
          );

          final screenState = tester.state(find.byType(AdminScreen));

          // Live mounted brand transition: defaultBrand -> liquidGlass
          await tester.runAsync(() async {
            await fixture.theme.setBrand('liquidGlass');
          });
          await tester.pumpAndSettle();

          expect(tester.state(find.byType(AdminScreen)), same(screenState));
          final lgField = tester.widget<TextField>(baseFieldFinder);
          expect(lgField.controller, same(controller));
          expect(controller.text, draftText);
          expect(controller.selection, selection);
          expect(lgField.focusNode?.hasFocus ?? false, isTrue);

          _verifyBaseUrlFieldSemantics(
            tester,
            fieldFinder: baseFieldFinder,
            expectedLabel: expectedZh,
          );

          final surfaceFinder = find
              .ancestor(
                of: labelFinder,
                matching: find.byType(AppSurfaceCard),
              )
              .first;
          await _assertReadableLabelWithGlyphs(
            tester,
            textFinder: labelFinder,
            surfaceFinder: surfaceFinder,
            boundaryKey: fixture.captureKey,
            role: 'Base URL label (liquidGlass transition)',
          );

          // Live mounted brand transition back: liquidGlass -> defaultBrand
          await tester.runAsync(() async {
            await fixture.theme.setBrand('defaultBrand');
          });
          await tester.pumpAndSettle();

          expect(tester.state(find.byType(AdminScreen)), same(screenState));
          final dfField = tester.widget<TextField>(baseFieldFinder);
          expect(dfField.controller, same(controller));
          expect(controller.text, draftText);
          expect(controller.selection, selection);
          expect(dfField.focusNode?.hasFocus ?? false, isTrue);

          _verifyBaseUrlFieldSemantics(
            tester,
            fieldFinder: baseFieldFinder,
            expectedLabel: expectedZh,
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
      'preserves Base URL controller instance, selection, focus, and semantics across live mounted locale transitions zh <-> en',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final fixture = await _mountAdminFixture(
            tester,
            brand: 'liquidGlass',
            locale: AppLocale.zh,
            size: const Size(320, 844),
            scale: 2.0,
            initialTabIndex: 2,
          );

          final aiScrollable =
              _moduleVerticalScrollable(modulePrefix: 'admin-ai-').first;
          final expectedZh = AdminUiCopy.aiBaseUrlLabelFor(AppLocale.zh);
          final zhLabelFinder = find.text(expectedZh);

          await tester.scrollUntilVisible(
            zhLabelFinder,
            300,
            scrollable: aiScrollable,
          );
          await tester.ensureVisible(zhLabelFinder);
          await tester.pumpAndSettle();

          final baseFieldFinder = find.byKey(
            const ValueKey('admin_ai_base_url_field'),
          );
          const draftText = 'https://api.my-domain.org/v1';
          await tester.enterText(baseFieldFinder, draftText);
          final controller =
              tester.widget<TextField>(baseFieldFinder).controller!;

          // First focus the text field via tap
          await tester.tap(baseFieldFinder);
          await tester.pumpAndSettle();

          // Then set selection on the focused controller
          const selection = TextSelection(baseOffset: 8, extentOffset: 21);
          controller.selection = selection;
          await tester.pumpAndSettle();

          final screenState = tester.state(find.byType(AdminScreen));
          final initialField = tester.widget<TextField>(baseFieldFinder);
          expect(initialField.controller, same(controller));
          expect(controller.text, draftText);
          expect(controller.selection, selection);
          expect(initialField.focusNode?.hasFocus ?? false, isTrue);

          _verifyBaseUrlFieldSemantics(
            tester,
            fieldFinder: baseFieldFinder,
            expectedLabel: expectedZh,
          );

          // Live mounted locale transition: zh -> en
          I18n.setLocale(AppLocale.en);
          await tester.pumpAndSettle();

          expect(tester.state(find.byType(AdminScreen)), same(screenState));
          final enField = tester.widget<TextField>(baseFieldFinder);
          expect(enField.controller, same(controller));
          expect(controller.text, draftText);
          expect(controller.selection, selection);
          expect(enField.focusNode?.hasFocus ?? false, isTrue);

          final expectedEn = AdminUiCopy.aiBaseUrlLabelFor(AppLocale.en);
          final enLabelFinder = find.text(expectedEn);
          expect(enLabelFinder, findsOneWidget);

          _verifyBaseUrlFieldSemantics(
            tester,
            fieldFinder: baseFieldFinder,
            expectedLabel: expectedEn,
          );

          final enSurfaceFinder = find
              .ancestor(
                of: enLabelFinder,
                matching: find.byType(AppSurfaceCard),
              )
              .first;
          await _assertReadableLabelWithGlyphs(
            tester,
            textFinder: enLabelFinder,
            surfaceFinder: enSurfaceFinder,
            boundaryKey: fixture.captureKey,
            role: 'Base URL label (English locale transition)',
          );

          // Live mounted locale transition back: en -> zh
          I18n.setLocale(AppLocale.zh);
          await tester.pumpAndSettle();

          expect(tester.state(find.byType(AdminScreen)), same(screenState));
          final zhField = tester.widget<TextField>(baseFieldFinder);
          expect(zhField.controller, same(controller));
          expect(controller.text, draftText);
          expect(controller.selection, selection);
          expect(zhField.focusNode?.hasFocus ?? false, isTrue);

          _verifyBaseUrlFieldSemantics(
            tester,
            fieldFinder: baseFieldFinder,
            expectedLabel: expectedZh,
          );

          final zhSurfaceFinder = find
              .ancestor(
                of: find.text(expectedZh),
                matching: find.byType(AppSurfaceCard),
              )
              .first;
          await _assertReadableLabelWithGlyphs(
            tester,
            textFinder: find.text(expectedZh),
            surfaceFinder: zhSurfaceFinder,
            boundaryKey: fixture.captureKey,
            role: 'Base URL label (Chinese locale return)',
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
      'preserves Base URL controller instance, selection, focus, and semantics across ordinary <-> compact layout transitions',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final fixture = await _mountAdminFixture(
            tester,
            brand: 'defaultBrand',
            locale: AppLocale.zh,
            size: const Size(390, 844),
            scale: 1.0,
            initialTabIndex: 2,
          );

          final aiScrollable =
              _moduleVerticalScrollable(modulePrefix: 'admin-ai-').first;
          final expectedZh = AdminUiCopy.aiBaseUrlLabelFor(AppLocale.zh);
          final labelFinder = find.text(expectedZh);

          await tester.scrollUntilVisible(
            labelFinder,
            300,
            scrollable: aiScrollable,
          );
          await tester.ensureVisible(labelFinder);
          await tester.pumpAndSettle();

          final baseFieldFinder = find.byKey(
            const ValueKey('admin_ai_base_url_field'),
          );
          expect(baseFieldFinder, findsOneWidget);

          const draftText = 'https://api.my-domain.org/v1';
          await tester.enterText(baseFieldFinder, draftText);
          final controller =
              tester.widget<TextField>(baseFieldFinder).controller!;

          // First focus the text field via tap
          await tester.tap(baseFieldFinder);
          await tester.pumpAndSettle();

          // Then set selection on the focused controller
          const selection = TextSelection(baseOffset: 8, extentOffset: 21);
          controller.selection = selection;
          await tester.pumpAndSettle();

          final initialField = tester.widget<TextField>(baseFieldFinder);
          expect(initialField.controller, same(controller));
          expect(controller.text, draftText);
          expect(controller.selection, selection);
          expect(initialField.focusNode?.hasFocus ?? false, isTrue);

          _verifyBaseUrlFieldSemantics(
            tester,
            fieldFinder: baseFieldFinder,
            expectedLabel: expectedZh,
          );
          // Ordinary layout uses internal labelText
          expect(initialField.decoration?.labelText, expectedZh);

          final screenState = tester.state(find.byType(AdminScreen));

          // Live mounted layout transition: ordinary -> 320px200percent
          await fixture.updateLayout(
            tester,
            size: const Size(320, 844),
            scale: 2.0,
          );

          expect(tester.state(find.byType(AdminScreen)), same(screenState));
          final compactField = tester.widget<TextField>(baseFieldFinder);
          expect(compactField.controller, same(controller));
          expect(controller.text, draftText);
          expect(controller.selection, selection);
          expect(compactField.focusNode?.hasFocus ?? false, isTrue);
          // Compact layout moves label to external Text with ExcludeSemantics, labelText becomes null
          expect(compactField.decoration?.labelText, isNull);

          _verifyBaseUrlFieldSemantics(
            tester,
            fieldFinder: baseFieldFinder,
            expectedLabel: expectedZh,
          );

          final compactSurface = find
              .ancestor(
                of: find.text(expectedZh),
                matching: find.byType(AppSurfaceCard),
              )
              .first;
          await _assertReadableLabelWithGlyphs(
            tester,
            textFinder: find.text(expectedZh),
            surfaceFinder: compactSurface,
            boundaryKey: fixture.captureKey,
            role: 'Base URL label (compact layout switch)',
          );

          // Live mounted layout transition back: 320px200percent -> ordinary
          await fixture.updateLayout(
            tester,
            size: const Size(390, 844),
            scale: 1.0,
          );

          expect(tester.state(find.byType(AdminScreen)), same(screenState));
          final restoredField = tester.widget<TextField>(baseFieldFinder);
          expect(restoredField.controller, same(controller));
          expect(controller.text, draftText);
          expect(controller.selection, selection);
          expect(restoredField.focusNode?.hasFocus ?? false, isTrue);
          expect(restoredField.decoration?.labelText, expectedZh);

          _verifyBaseUrlFieldSemantics(
            tester,
            fieldFinder: baseFieldFinder,
            expectedLabel: expectedZh,
          );

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
  });

  group('Priority admin unsaved draft and page exit zero mutation invariant', () {
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
            initialTabIndex: 2,
          );

          final baseFieldFinder = find.byKey(
            const ValueKey('admin_ai_base_url_field'),
          );
          await tester.enterText(
            baseFieldFinder,
            'https://unsaved-temporary.example.org',
          );
          await tester.pumpAndSettle();

          // Exit / pop the route by replacing with blank widget
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();

          // Verify no mutation request (POST/PUT/DELETE) was ever sent
          final mutations = fixture.requests.where((r) => r.method != 'GET');
          expect(
            mutations,
            isEmpty,
            reason:
                'Leaving screen must never write unsaved draft to backend API',
          );

          expect(tester.takeException(), isNull);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );
  });
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

        // Scroll ancestor viewport line by line so glyph is in view, matching retained_dialog_text_probe.dart
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
        // Verify against real ancestor viewport
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

        // Also verify horizontal containment within surface card
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

void _verifyBaseUrlFieldSemantics(
  WidgetTester tester, {
  required Finder fieldFinder,
  required String expectedLabel,
}) {
  expect(fieldFinder, findsOneWidget);

  // 1. Query the real text input semantics node
  Finder inputFinder = find.descendant(
    of: fieldFinder,
    matching: find.byType(EditableText),
  );
  if (inputFinder.evaluate().isEmpty) {
    inputFinder = fieldFinder;
  }
  final semantics = tester.getSemantics(inputFinder);

  // 2. Strict requirement: isTextField flag must be set on the accessible input node
  expect(
    semantics.flagsCollection.isTextField,
    isTrue,
    reason:
        'Base URL target must have SemanticsFlag.isTextField set on its semantics node',
  );

  // 3. Query real field semantics label/value/hint; full label must be present (allowing merged hintText)
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

  // 4. Complete label must not be repeated redundantly on the field
  final countInField = expectedLabel.allMatches(label).length;
  expect(
    countInField,
    lessThanOrEqualTo(1),
    reason:
        'Label "$expectedLabel" must not be repeated multiple times in field semantics: "$label"',
  );

  // 5. Must not duplicate independent static label node in the semantics traversal tree
  final traversalNodes = tester.semantics.simulatedAccessibilityTraversal();
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

  final rootDir = Directory('evidence/screenshots');
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
      'DUOYI_PRIORITY_THEME_SCREENSHOT_DIR must stay under evidence/screenshots/, got: $explicitDir (target: $canonicalTarget, root: $canonicalRoot)',
    );
  }

  await tester.runAsync(() async {
    final context = boundaryKey.currentContext;
    if (context == null) {
      throw StateError(
        'missingboundary: BuildContext not found for screenshot "$name"',
      );
    }
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError(
        'missingboundary: RenderRepaintBoundary not found for "$name"',
      );
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError(
          'encoding: failed to encode PNG for screenshot "$name"',
        );
      }
      final file = File('$canonicalTarget${Platform.pathSeparator}$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes.buffer.asUint8List());
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
    if (scope == 'ai') {
      return json({
        'ai_enabled': true,
        'ai_base_url': '',
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
