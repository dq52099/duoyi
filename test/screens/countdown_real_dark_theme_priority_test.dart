// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/date_item_feedback.dart'
    show DateItemMutationStatus;
import 'package:duoyi/widgets/surface_components.dart'
    show
        AppDialog,
        AppModalSheet,
        AppSurfaceCard,
        appContrastRatio,
        appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/retained_dialog_text_probe.dart';
import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int countdownWrites = 0;

  static bool _isCountdownKey(String key) =>
      key == 'duoyi_countdowns' ||
      key == 'flutter.duoyi_countdowns' ||
      key.endsWith('.duoyi_countdowns');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isCountdownKey(key)) {
      countdownWrites++;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isCountdownKey(key)) {
      countdownWrites++;
    }
    return super.remove(key);
  }
}

Object _countdownEditorState(WidgetTester tester, Finder descendant) {
  Element? element = tester.element(descendant);
  while (element != null) {
    if (element is StatefulElement &&
        element.state.runtimeType.toString().contains(
          'CountdownEditSheetState',
        )) {
      return element.state;
    }
    Element? parent;
    element.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false;
    });
    element = parent;
  }
  throw StateError('Countdown editor State was not found above descendant.');
}

Future<int> _boundedPumpAndSettle(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 50),
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  Duration timeout = const Duration(seconds: 5),
}) {
  return tester.pumpAndSettle(duration, phase, timeout);
}

Future<void> _drainAccountWrites(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(() => AccountPreferenceWrites.drain().timeout(timeout));
  await tester.pump(const Duration(milliseconds: 40));
}

void _assertCanHit(WidgetTester tester, Finder finder, String description) {
  expect(finder, findsOneWidget, reason: '$description must exist to hit');
  final center = tester.getCenter(finder);
  final targetRender = tester.renderObject(finder);
  final hitResult = tester.hitTestOnBinding(center);

  bool matchesTarget(Object? target) {
    if (target is! RenderObject) return false;
    RenderObject? current = target;
    while (current != null) {
      if (identical(current, targetRender)) return true;
      current = current.parent;
    }
    return false;
  }

  final hit = hitResult.path.any((entry) => matchesTarget(entry.target));
  expect(
    hit,
    isTrue,
    reason:
        '$description at $center must be hit-testable and not obscured or absorbed by AbsorbPointer',
  );
}

Future<void> _waitForDateItemIdle(
  WidgetTester tester, {
  Finder? scopeFinder,
  Finder? textFieldFinder,
  bool requireNoDialog = true,
  bool requireNoModalSheet = false,
  Duration timeout = const Duration(seconds: 10),
  String role = 'DateItem idle',
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    // 1. Advance route reverse/entrance animations in fakeAsync zone
    await tester.pump(const Duration(milliseconds: 50));

    final dialogActive =
        requireNoDialog && find.byType(AppDialog).evaluate().isNotEmpty;

    // 2. Advance microtasks and async event loop in real IO zone every round.
    // Do not block on drain while dialog exit animation / route continuation is mid-flight.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!dialogActive) {
        await AccountPreferenceWrites.drain().timeout(
          const Duration(seconds: 2),
        );
      }
    });

    // 3. Pump frame for setState() / widget rebuild
    await tester.pump(const Duration(milliseconds: 50));

    // Route exit checks: routes must complete exit animations before idle resolution
    if (dialogActive) {
      continue;
    }
    if (requireNoModalSheet &&
        find.byType(AppModalSheet).evaluate().isNotEmpty) {
      continue;
    }

    // Check scope DateItemMutationStatus busy
    if (scopeFinder != null) {
      final scopeElements = scopeFinder.evaluate();
      if (scopeElements.isEmpty) {
        if (requireNoModalSheet || requireNoDialog) {
          await _boundedPumpAndSettle(tester);
          return;
        }
      } else {
        final descendantStatus = find.descendant(
          of: scopeFinder,
          matching: find.byType(DateItemMutationStatus),
        );
        final ancestorStatus = find.ancestor(
          of: scopeFinder,
          matching: find.byType(DateItemMutationStatus),
        );
        final statusElements = [
          ...descendantStatus.evaluate(),
          ...ancestorStatus.evaluate(),
        ];
        if (statusElements.isNotEmpty) {
          final statuses = statusElements.map(
            (e) => (e.widget as DateItemMutationStatus),
          );
          if (statuses.any((s) => s.busy)) {
            continue;
          }
        }
      }
    } else {
      final allStatuses = tester
          .widgetList<DateItemMutationStatus>(
            find.byType(DateItemMutationStatus),
          )
          .toList();
      if (allStatuses.any((s) => s.busy)) {
        continue;
      }
    }

    // Check textField enabled
    if (textFieldFinder != null) {
      final tfElements = textFieldFinder.evaluate();
      if (tfElements.isNotEmpty) {
        final tf = tester.widget<TextField>(textFieldFinder);
        if (tf.enabled == false) {
          continue;
        }
      }
    }

    // All checked conditions met! Bounded pump and settle to ensure clean final state.
    await _boundedPumpAndSettle(tester);
    return;
  }

  throw StateError(
    'Timeout waiting for $role after ${stopwatch.elapsed.inMilliseconds}ms. '
    'Dialogs: ${find.byType(AppDialog).evaluate().length}, '
    'ModalSheets: ${find.byType(AppModalSheet).evaluate().length}, '
    'DateItemMutationStatus busy count: ${tester.widgetList<DateItemMutationStatus>(find.byType(DateItemMutationStatus)).where((s) => s.busy).length}',
  );
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name, {
  Finder? scrollableFinder,
  double? scrollToOffset,
  double? restoreOffset,
}) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] ??
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  var resolvedDir = explicitDir.trim();
  if (resolvedDir.startsWith('/') || resolvedDir.startsWith(r'\')) {
    if (!resolvedDir.contains('evidence/screenshots')) {
      resolvedDir = 'evidence/screenshots/${resolvedDir.split('/').last}';
    }
  } else if (!resolvedDir.startsWith('evidence/screenshots')) {
    resolvedDir = 'evidence/screenshots/$resolvedDir';
  }

  if (scrollableFinder != null && scrollToOffset != null) {
    tester
        .state<ScrollableState>(scrollableFinder)
        .position
        .jumpTo(scrollToOffset);
    await _boundedPumpAndSettle(tester);
  }

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError(
        'Missing boundary: RepaintBoundary render object not found for boundaryKey $boundaryKey when capturing "$name"',
      );
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError(
          'Encoding error: image.toByteData returned null when capturing "$name"',
        );
      }
      final file = File('$resolvedDir/countdown-real-dark-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });

  if (scrollableFinder != null && restoreOffset != null) {
    tester
        .state<ScrollableState>(scrollableFinder)
        .position
        .jumpTo(restoreOffset);
    await _boundedPumpAndSettle(tester);
  }
}

void _assertControl44(WidgetTester tester, Finder finder, String description) {
  expect(finder, findsOneWidget, reason: '$description must exist');
  final rect = tester.getRect(finder);
  expect(
    rect.width,
    greaterThanOrEqualTo(44.0 - 0.01),
    reason: '$description width (${rect.width}) must be >= 44px',
  );
  expect(
    rect.height,
    greaterThanOrEqualTo(44.0 - 0.01),
    reason: '$description height (${rect.height}) must be >= 44px',
  );

  final controlRender = tester.renderObject(finder);
  bool belongsToControl(Object target) {
    if (target is! RenderObject) return false;
    RenderObject? current = target;
    while (current != null) {
      if (identical(current, controlRender)) return true;
      current = current.parent;
    }
    return false;
  }

  const edge = 22.0 - 0.5;
  for (final dx in [-edge, 0.0, edge]) {
    for (final dy in [-edge, 0.0, edge]) {
      final samplePoint = rect.center + Offset(dx, dy);
      final hit = tester.hitTestOnBinding(samplePoint);
      expect(
        hit.path.any((entry) => belongsToControl(entry.target)),
        isTrue,
        reason: '$description 44dp hit test at ($dx, $dy) must target control',
      );
    }
  }
}

double _assertCompositeContrast(
  WidgetTester tester,
  Finder textFinder, {
  required String role,
  double minContrast = 4.5,
}) {
  final rich = find.descendant(of: textFinder, matching: find.byType(RichText));
  final target = rich.evaluate().isNotEmpty ? rich : textFinder;
  final element = tester.element(target);
  final paragraph = tester.renderObject<RenderParagraph>(target);
  final text = paragraph.text.toPlainText();
  final theme = Theme.of(element);

  final foreground = paragraph.text.style?.color ??
      DefaultTextStyle.of(element).style.color ??
      theme.colorScheme.onSurface;

  final layers = <Color>[];
  element.visitAncestorElements((ancestor) {
    final w = ancestor.widget;
    if (w is Material && w.color != null && w.color != Colors.transparent) {
      layers.add(w.color!);
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      final d = w.decoration as BoxDecoration;
      if (d.color != null && d.color != Colors.transparent) {
        layers.add(d.color!);
      }
    } else if (w is Card && w.color != null && w.color != Colors.transparent) {
      layers.add(w.color!);
    }
    return true;
  });

  Color composite = theme.brightness == Brightness.dark
      ? (theme.scaffoldBackgroundColor != Colors.transparent
          ? theme.scaffoldBackgroundColor
          : theme.colorScheme.surface)
      : theme.scaffoldBackgroundColor;

  for (final color in layers.reversed) {
    composite = Color.alphaBlend(color, composite);
  }

  final effectiveFg = Color.alphaBlend(foreground, composite);
  final ratio = appContrastRatio(effectiveFg, composite);
  expect(
    ratio,
    greaterThanOrEqualTo(minContrast - 0.05),
    reason:
        '$role: contrast ratio $ratio for "$text" ($foreground on composite $composite) must be >= $minContrast',
  );
  return ratio;
}

Future<void> _assertReadableParagraph(
  WidgetTester tester, {
  required Finder textFinder,
  required GlobalKey boundaryKey,
  required String role,
  Finder? surfaceFinder,
  Finder? scrollableFinder,
  bool assertWordContinuity = false,
}) async {
  expect(textFinder, findsOneWidget, reason: '$role must be present');

  if (scrollableFinder != null) {
    await tester.scrollUntilVisible(
      textFinder,
      80,
      scrollable: scrollableFinder,
    );
    final element = tester.element(textFinder);
    await Scrollable.ensureVisible(element, alignment: 0.5);
    await _boundedPumpAndSettle(tester);
  }

  final rich = find.descendant(of: textFinder, matching: find.byType(RichText));
  final target = rich.evaluate().isNotEmpty ? rich : textFinder;
  final paragraph = tester.renderObject<RenderParagraph>(target);

  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role didExceedMaxLines must be false (no line truncation)',
  );

  final text = paragraph.text.toPlainText();
  expect(text, isNotEmpty, reason: '$role text must not be empty');

  final renderBoundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (renderBoundary == null) {
    throw StateError(
      'Missing boundary: RepaintBoundary render object not found for boundaryKey $boundaryKey when verifying $role',
    );
  }

  final screenRect = Rect.fromLTWH(
    0,
    0,
    tester.view.physicalSize.width / tester.view.devicePixelRatio,
    tester.view.physicalSize.height / tester.view.devicePixelRatio,
  );

  Rect? surfaceRect;
  if (surfaceFinder != null) {
    final surfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
    surfaceRect = MatrixUtils.transformRect(
      surfaceBox.getTransformTo(renderBoundary),
      Offset.zero & surfaceBox.size,
    );
  }

  final Rect visibleClipRect;
  if (scrollableFinder != null) {
    final viewportFinder = find.descendant(
      of: scrollableFinder,
      matching: find.byType(Viewport),
    );
    expect(viewportFinder, findsOneWidget);
    final viewportBox = tester.renderObject<RenderBox>(viewportFinder);
    final viewportRect = MatrixUtils.transformRect(
      viewportBox.getTransformTo(renderBoundary),
      Offset.zero & viewportBox.size,
    );
    visibleClipRect = screenRect.intersect(viewportRect);
  } else {
    expect(
      surfaceRect,
      isNotNull,
      reason:
          'Non-scrollable $role requires a painted surface to intersect with screen',
    );
    visibleClipRect = screenRect.intersect(surfaceRect!);
  }

  final nonWhitespaceOffsets = <int>[];
  for (var i = 0; i < text.length; i++) {
    if (text[i].trim().isNotEmpty) {
      nonWhitespaceOffsets.add(i);
    }
  }

  expect(
    nonWhitespaceOffsets,
    isNotEmpty,
    reason: '$role must contain non-whitespace characters to lay out',
  );

  for (final offset in nonWhitespaceOffsets) {
    final char = text[offset];
    final charBoxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + 1),
    );
    expect(
      charBoxes,
      isNotEmpty,
      reason:
          '$role character "$char" at index $offset must have a laid out box',
    );

    for (final box in charBoxes) {
      expect(
        box.left,
        greaterThanOrEqualTo(-0.5),
        reason:
            '$role character "$char" box left ${box.left} must be inside paragraph allocated width',
      );
      expect(
        box.right,
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason:
            '$role character "$char" box right ${box.right} must be inside paragraph allocated width ${paragraph.size.width}',
      );

      if (scrollableFinder != null) {
        final initialGlyphY = paragraph.localToGlobal(
          Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2),
        ).dy;
        if (initialGlyphY < visibleClipRect.top ||
            initialGlyphY > visibleClipRect.bottom) {
          final scroll = Scrollable.maybeOf(tester.element(target));
          if (scroll != null) {
            final delta = initialGlyphY - visibleClipRect.center.dy;
            final targetPixels = (scroll.position.pixels + delta).clamp(
              scroll.position.minScrollExtent,
              scroll.position.maxScrollExtent,
            );
            if ((targetPixels - scroll.position.pixels).abs() > 0.5) {
              scroll.position.jumpTo(targetPixels);
              await tester.pump(const Duration(milliseconds: 20));
            }
          }
        }
      }

      final glyphRect = MatrixUtils.transformRect(
        paragraph.getTransformTo(renderBoundary),
        Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
      );

      Rect? currentSurfaceRect;
      if (surfaceFinder != null) {
        final sBox = tester.renderObject<RenderBox>(surfaceFinder);
        currentSurfaceRect = MatrixUtils.transformRect(
          sBox.getTransformTo(renderBoundary),
          Offset.zero & sBox.size,
        );
      }

      if (currentSurfaceRect != null) {
        expect(
          glyphRect.left,
          greaterThanOrEqualTo(currentSurfaceRect.left - 0.5),
          reason:
              '$role character "$char" glyph left ${glyphRect.left} must be within painted surface left ${currentSurfaceRect.left}',
        );
        expect(
          glyphRect.right,
          lessThanOrEqualTo(currentSurfaceRect.right + 0.5),
          reason:
              '$role character "$char" glyph right ${glyphRect.right} must be within painted surface right ${currentSurfaceRect.right}',
        );
        expect(
          glyphRect.top,
          greaterThanOrEqualTo(currentSurfaceRect.top - 0.5),
          reason:
              '$role character "$char" glyph top ${glyphRect.top} must be within painted surface top ${currentSurfaceRect.top}',
        );
        expect(
          glyphRect.bottom,
          lessThanOrEqualTo(currentSurfaceRect.bottom + 0.5),
          reason:
              '$role character "$char" glyph bottom ${glyphRect.bottom} must be within painted surface bottom ${currentSurfaceRect.bottom}',
        );
      }

      expect(
        glyphRect.left,
        greaterThanOrEqualTo(visibleClipRect.left - 0.5),
        reason:
            '$role character "$char" glyph left ${glyphRect.left} must be within visible viewport left ${visibleClipRect.left}',
      );
      expect(
        glyphRect.right,
        lessThanOrEqualTo(visibleClipRect.right + 0.5),
        reason:
            '$role character "$char" glyph right ${glyphRect.right} must be within visible viewport right ${visibleClipRect.right}',
      );
      expect(
        glyphRect.top,
        greaterThanOrEqualTo(visibleClipRect.top - 0.5),
        reason:
            '$role character "$char" glyph top ${glyphRect.top} must be within visible viewport top ${visibleClipRect.top}',
      );
      expect(
        glyphRect.bottom,
        lessThanOrEqualTo(visibleClipRect.bottom + 0.5),
        reason:
            '$role character "$char" glyph bottom ${glyphRect.bottom} must be within visible viewport bottom ${visibleClipRect.bottom}',
      );
    }
  }

  if (assertWordContinuity) {
    for (final wordMatch in RegExp(
      r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*",
    ).allMatches(text)) {
      final word = wordMatch.group(0)!;
      final wordBoxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: wordMatch.start, extentOffset: wordMatch.end),
      );
      expect(
        wordBoxes,
        isNotEmpty,
        reason: '$role: word "$word" must have boxes',
      );
      final lineTops = wordBoxes.map((b) => b.top.round()).toSet();
      expect(
        lineTops.length,
        equals(1),
        reason:
            '$role: word "$word" must remain on one line without character-by-character column breakage',
      );
    }
  }
}

enum _CountdownOutcome {
  deleteDeniedThenSave,
  editorCancel,
  deleteConfirmedFromEditor,
  swipeDeleteDeniedThenConfirmed,
}

class _CountdownRealDarkScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final List<String> cycleBrands;
  final Size size;
  final double scale;
  final _CountdownOutcome outcome;

  const _CountdownRealDarkScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.cycleBrands,
    required this.size,
    required this.scale,
    required this.outcome,
  });
}

const _scenarios = <_CountdownRealDarkScenario>[
  _CountdownRealDarkScenario(
    name: 'en-portrait-320x844-scale2-starRail-cycle',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'starRail',
    cycleBrands: ['defaultBrand', 'liquidGlass', 'starRail'],
    size: Size(320, 844),
    scale: 2.0,
    outcome: _CountdownOutcome.deleteDeniedThenSave,
  ),
  _CountdownRealDarkScenario(
    name: 'zh-portrait-320x844-scale2-starRail-cycle',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'starRail',
    cycleBrands: ['defaultBrand', 'liquidGlass', 'starRail'],
    size: Size(320, 844),
    scale: 2.0,
    outcome: _CountdownOutcome.editorCancel,
  ),
  _CountdownRealDarkScenario(
    name: 'zh-landscape-844x390-scale1-starRail-cycle',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'starRail',
    cycleBrands: ['liquidGlass', 'defaultBrand', 'starRail'],
    size: Size(844, 390),
    scale: 1.0,
    outcome: _CountdownOutcome.deleteConfirmedFromEditor,
  ),
  _CountdownRealDarkScenario(
    name: 'en-portrait-390x844-scale1-zzz-representative',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'zzz',
    cycleBrands: ['liquidGlass', 'defaultBrand', 'zzz'],
    size: Size(390, 844),
    scale: 1.0,
    outcome: _CountdownOutcome.swipeDeleteDeniedThenConfirmed,
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'countdown real dark theme priority ${scenario.initialBrand} <-> light <-> dark ${scenario.name}',
      (tester) async {
        final originalLocale = I18n.current;
        final originalShadows = debugDisableShadows;
        final originalTimeZoneReader =
            LocalTimezoneResolver.debugSystemTimeZoneReader;
        final originalNativeTimeZoneReader =
            LocalTimezoneResolver.debugNativeSystemTimeZoneReader;
        final previousStore = SharedPreferencesStorePlatform.instance;
        final originalHitTestFatal =
            WidgetController.hitTestWarningShouldBeFatal;
        WidgetController.hitTestWarningShouldBeFatal = true;

        final syntheticItems = [
          CountdownItem(
            id: 'item-generated-default',
            title: 'Generated Milestone',
            targetDate: DateTime(2030, 6, 15),
            categoryIsDefault: true,
            isPinned: true,
            remind: false,
            reminderKind: ReminderKind.off,
          ),
          CountdownItem(
            id: 'item-authored-default-literal',
            title: 'Authored Literal Default',
            targetDate: DateTime(2030, 9, 20),
            category: '默认',
            categoryIsDefault: false,
            isPinned: false,
            remind: false,
            reminderKind: ReminderKind.off,
          ),
          CountdownItem(
            id: 'item-authored-custom-alpha',
            title: 'Project Alpha Target',
            targetDate: DateTime(2030, 11, 1),
            category: 'ProjectAlpha',
            categoryIsDefault: false,
            isPinned: false,
            remind: false,
            reminderKind: ReminderKind.off,
          ),
          CountdownItem(
            id: 'item-authored-work',
            title: 'Work Sprint Review',
            targetDate: DateTime(2031, 1, 10),
            category: '工作',
            categoryIsDefault: false,
            isPinned: false,
            remind: false,
            reminderKind: ReminderKind.off,
          ),
        ];

        final initialEncodedCountdowns =
            syntheticItems.map((e) => jsonEncode(e.toJson())).toList();

        final allUnlocked = ['starRail', 'zzz', 'defaultBrand', 'liquidGlass'];

        final initialPrefs = <String, Object>{
          'pref_app_timezone_mode': 'fixed',
          'pref_app_timezone_iana': 'Asia/Shanghai',
          'active_brand': scenario.initialBrand,
          'theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
            'unlockedBrandIds': allUnlocked,
          }),
          'theme_unlocked_brands': allUnlocked,
          'duoyi_countdowns': initialEncodedCountdowns,
          'flutter.pref_app_timezone_mode': 'fixed',
          'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
          'flutter.active_brand': scenario.initialBrand,
          'flutter.theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
            'unlockedBrandIds': allUnlocked,
          }),
          'flutter.theme_unlocked_brands': allUnlocked,
          'flutter.duoyi_countdowns': initialEncodedCountdowns,
        };

        SharedPreferences.setMockInitialValues(initialPrefs);
        final store = _RecordingPreferencesStore({
          for (final entry in initialPrefs.entries)
            if (!entry.key.startsWith('flutter.'))
              'flutter.${entry.key}': entry.value,
        });
        SharedPreferencesStorePlatform.instance = store;

        LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
            'Asia/Shanghai';
        LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async =>
            'Asia/Shanghai';

        final transport = MockClient((request) async {
          fail(
            'Unexpected network call during countdown real dark fixture: '
            '${request.method} ${request.url}',
          );
        });

        late final ThemeProvider theme;
        late final CountdownProvider countdownProvider;
        late final PreferencesProvider preferences;

        try {
          I18n.setLocale(scenario.initialLocale);
          debugDisableShadows = false;

          await tester.runAsync(() async {
            await LocalTimezoneResolver.init().timeout(
              const Duration(seconds: 5),
            );
            preferences = PreferencesProvider();
            theme = ThemeProvider();
            countdownProvider = CountdownProvider();
            await theme.loadFromStorage().timeout(const Duration(seconds: 5));
            await preferences.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await countdownProvider.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await loadWeeklyReviewScreenshotFonts().timeout(
              const Duration(seconds: 5),
            );
          });

          await _drainAccountWrites(tester);

          expect(theme.brand.id, scenario.initialBrand);
          for (final b in allUnlocked) {
            expect(
              theme.isBrandUnlocked(b),
              isTrue,
              reason: 'Brand $b must be unlocked in fixture',
            );
          }
          expect(countdownProvider.items.length, 4);

          final baselineCountdownWrites = store.countdownWrites;

          void assertZeroCountdownPersistence(String stage) {
            expect(
              store.countdownWrites,
              baselineCountdownWrites,
              reason:
                  '$stage: expected zero duoyi_countdowns writes '
                  '(actual=${store.countdownWrites}, baseline=$baselineCountdownWrites)',
            );
          }

          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1;

          final boundary = GlobalKey();

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<CountdownProvider>.value(
                  value: countdownProvider,
                ),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences,
                ),
              ],
              child: Consumer<ThemeProvider>(
                builder: (context, currentTheme, _) =>
                    ValueListenableBuilder<AppLocale>(
                      valueListenable: I18n.localeListenable,
                      builder: (context, currentLocale, _) => MaterialApp(
                        locale: Locale(
                          currentLocale == AppLocale.en ? 'en' : 'zh',
                        ),
                        supportedLocales: const [Locale('en'), Locale('zh')],
                        localizationsDelegates:
                            GlobalMaterialLocalizations.delegates,
                        theme: currentTheme.brand.theme,
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: scenario.scale < 0
                                ? const RouteProbeNonlinearScaler()
                                : TextScaler.linear(scenario.scale),
                          ),
                          child: RepaintBoundary(key: boundary, child: child!),
                        ),
                        home: const BrandRouteSurface(
                          remountOnLocaleChange: false,
                          child: CountdownScreen(),
                        ),
                      ),
                    ),
              ),
            ),
          );

          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          void assertThemeAndBrightness(
            String expectedBrandId,
            String stage,
          ) {
            expect(
              theme.brand.id,
              expectedBrandId,
              reason: '$stage: ThemeProvider brand id',
            );
            final expectedBrand = AppBrands.byId(expectedBrandId);
            final expectedBrightness = expectedBrand.theme.brightness;

            final screenElement = tester.element(find.byType(CountdownScreen));
            final controlTheme = Theme.of(screenElement);
            expect(
              controlTheme.brightness,
              equals(expectedBrightness),
              reason:
                  '$stage: screen real brightness (${controlTheme.brightness}) '
                  'must match brand theme brightness ($expectedBrightness)',
            );
            expect(
              controlTheme.colorScheme.primary,
              equals(expectedBrand.theme.colorScheme.primary),
              reason: '$stage: primary color match',
            );

            final modalSheet = find.byType(AppModalSheet);
            if (modalSheet.evaluate().isNotEmpty) {
              final sheetElement = tester.element(modalSheet.last);
              final sheetTheme = Theme.of(sheetElement);
              expect(
                sheetTheme.brightness,
                equals(expectedBrightness),
                reason:
                    '$stage: sheet real brightness must match brand brightness ($expectedBrightness)',
              );
              final surfaceStyle = appSurfaceStyleOf(sheetElement);
              if (expectedBrandId == 'liquidGlass') {
                expect(
                  surfaceStyle,
                  equals(AppSurfaceStyle.liquidGlass),
                  reason: '$stage: sheet liquidGlass style',
                );
              } else {
                expect(
                  surfaceStyle,
                  isNot(equals(AppSurfaceStyle.liquidGlass)),
                  reason: '$stage: sheet non-liquidGlass style',
                );
              }
            }

            final dialogFinder = find.byType(AppDialog);
            if (dialogFinder.evaluate().isNotEmpty) {
              final dialogElement = tester.element(dialogFinder.last);
              final dialogTheme = Theme.of(dialogElement);
              expect(
                dialogTheme.brightness,
                equals(expectedBrightness),
                reason:
                    '$stage: dialog real brightness must match brand brightness ($expectedBrightness)',
              );
              final surfaceStyle = appSurfaceStyleOf(dialogElement);
              if (expectedBrandId == 'liquidGlass') {
                expect(
                  surfaceStyle,
                  equals(AppSurfaceStyle.liquidGlass),
                  reason: '$stage: dialog liquidGlass style',
                );
              } else {
                expect(
                  surfaceStyle,
                  isNot(equals(AppSurfaceStyle.liquidGlass)),
                  reason: '$stage: dialog non-liquidGlass style',
                );
              }
            }
          }

          assertThemeAndBrightness(
            scenario.initialBrand,
            'Initial mount with real dark theme',
          );

          expect(find.byType(CountdownScreen), findsOneWidget);
          expect(find.byType(BrandRouteSurface), findsOneWidget);
          final addButton = find.byKey(const ValueKey('countdown_add_button'));
          _assertControl44(tester, addButton, 'Countdown add FAB');
          _assertCompositeContrast(
            tester,
            find.descendant(
              of: addButton,
              matching: find.text(I18n.tr('action.add')),
            ),
            role: 'FAB label contrast against composite surface',
          );

          final mainListScrollable = find.descendant(
            of: find.byType(CountdownScreen),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          ).first;
          expect(mainListScrollable, findsOneWidget);

          final mainScrollPos =
              tester.state<ScrollableState>(mainListScrollable).position;
          if (mainScrollPos.maxScrollExtent > 0) {
            mainScrollPos.jumpTo(
              (mainScrollPos.maxScrollExtent * 0.4).clamp(10.0, 120.0),
            );
            await _boundedPumpAndSettle(tester);
          }
          final listOffset =
              tester.state<ScrollableState>(mainListScrollable).position.pixels;
          if (mainScrollPos.maxScrollExtent > 0) {
            expect(listOffset, greaterThan(0.0));
          }

          assertZeroCountdownPersistence(
            '1. initial screen load with nonzero list scroll',
          );
          await _capture(tester, boundary, '${scenario.name}-01-initial-list');

          // Restore scroll position to top (0.0) so header card and nearest description
          // are fully within the viewport
          if (mainScrollPos.pixels > 0) {
            mainScrollPos.jumpTo(0.0);
            await _boundedPumpAndSettle(tester);
          }

          // Readability & contrast on header card
          final nearestDescPrefix = I18n.tr('countdown.nearest.prefix');
          final nearestDescFinder = find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data != null &&
                widget.data!.startsWith(nearestDescPrefix),
          );
          final headerSurfaceFinder = find.descendant(
            of: find.byType(CountdownScreen),
            matching: find.byType(AppSurfaceCard),
          ).first;
          await _assertReadableParagraph(
            tester,
            textFinder: nearestDescFinder,
            boundaryKey: boundary,
            surfaceFinder: headerSurfaceFinder,
            scrollableFinder: mainListScrollable,
            role: 'Header nearest countdown description (${scenario.name})',
          );
          _assertCompositeContrast(
            tester,
            nearestDescFinder,
            role: 'Header nearest countdown contrast against composite surface',
          );

          // Card readability, contrast, and category checks
          final generatedCard = find.byKey(
            const ValueKey('countdown_card_item-generated-default'),
          );
          await tester.scrollUntilVisible(
            generatedCard,
            80,
            scrollable: mainListScrollable,
          );
          await Scrollable.ensureVisible(
            tester.element(generatedCard),
            alignment: 0.5,
          );
          await _boundedPumpAndSettle(tester);
          expect(generatedCard, findsOneWidget);

          final expectedGeneratedLabel = scenario.initialLocale == AppLocale.en
              ? 'Default'
              : '默认';
          expect(
            find.descendant(
              of: generatedCard,
              matching: find.text(expectedGeneratedLabel),
            ),
            findsOneWidget,
            reason: 'Generated category label follows initial locale',
          );

          final authoredDefaultCard = find.byKey(
            const ValueKey('countdown_card_item-authored-default-literal'),
          );
          await tester.scrollUntilVisible(
            authoredDefaultCard,
            80,
            scrollable: mainListScrollable,
          );
          await Scrollable.ensureVisible(
            tester.element(authoredDefaultCard),
            alignment: 0.5,
          );
          await _boundedPumpAndSettle(tester);
          expect(authoredDefaultCard, findsOneWidget);
          expect(
            find.descendant(
              of: authoredDefaultCard,
              matching: find.text('默认'),
            ),
            findsOneWidget,
            reason: 'Authored category literal "默认" preserved in card',
          );

          final authoredAlphaCard = find.byKey(
            const ValueKey('countdown_card_item-authored-custom-alpha'),
          );
          await tester.scrollUntilVisible(
            authoredAlphaCard,
            80,
            scrollable: mainListScrollable,
          );
          await Scrollable.ensureVisible(
            tester.element(authoredAlphaCard),
            alignment: 0.5,
          );
          await _boundedPumpAndSettle(tester);
          expect(authoredAlphaCard, findsOneWidget);
          expect(
            find.descendant(
              of: authoredAlphaCard,
              matching: find.text('ProjectAlpha'),
            ),
            findsOneWidget,
            reason: 'Authored custom category literal preserved in card',
          );

          for (final item in syntheticItems) {
            final cardFinder = find.byKey(
              ValueKey('countdown_card_${item.id}'),
            );
            await tester.scrollUntilVisible(
              cardFinder,
              80,
              scrollable: mainListScrollable,
            );
            await Scrollable.ensureVisible(
              tester.element(cardFinder),
              alignment: 0.5,
            );
            await _boundedPumpAndSettle(tester);

            final cardSurface = find.descendant(
              of: cardFinder,
              matching: find.byType(AppSurfaceCard),
            ).first;

            final titleFinder = find.descendant(
              of: cardFinder,
              matching: find.text(item.title),
            );
            await _assertReadableParagraph(
              tester,
              textFinder: titleFinder,
              boundaryKey: boundary,
              surfaceFinder: cardSurface,
              scrollableFinder: mainListScrollable,
              role: 'Card ${item.id} title (${scenario.name})',
              assertWordContinuity: true,
            );
            _assertCompositeContrast(
              tester,
              titleFinder,
              role: 'Card ${item.id} title contrast against composite surface',
            );

            final expectedTargetDate =
                '${I18n.tr('countdown.target.prefix')}'
                '${I18nDateFormat.date(item.targetDate, pattern: preferences.dateFormat, locale: I18n.current)}';
            final targetDateFinder = find.descendant(
              of: cardFinder,
              matching: find.text(expectedTargetDate),
            );
            await _assertReadableParagraph(
              tester,
              textFinder: targetDateFinder,
              boundaryKey: boundary,
              surfaceFinder: cardSurface,
              scrollableFinder: mainListScrollable,
              role: 'Card ${item.id} targetDate (${scenario.name})',
            );
            _assertCompositeContrast(
              tester,
              targetDateFinder,
              role:
                  'Card ${item.id} targetDate contrast against composite surface',
            );

            final expectedDaysLabel = item.daysRemaining < 0
                ? I18n.tr('countdown.days.elapsed')
                : I18n.tr('countdown.days.remaining');
            final daysLabelFinder = find.descendant(
              of: cardFinder,
              matching: find.text(expectedDaysLabel),
            );
            await _assertReadableParagraph(
              tester,
              textFinder: daysLabelFinder,
              boundaryKey: boundary,
              surfaceFinder: cardSurface,
              scrollableFinder: mainListScrollable,
              role: 'Card ${item.id} daysLabel (${scenario.name})',
            );
          }

          if (scenario.outcome ==
              _CountdownOutcome.swipeDeleteDeniedThenConfirmed) {
            await tester.scrollUntilVisible(
              authoredAlphaCard,
              80,
              scrollable: mainListScrollable,
            );
            await Scrollable.ensureVisible(
              tester.element(authoredAlphaCard),
              alignment: 0.5,
            );
            await _boundedPumpAndSettle(tester);

            _assertCanHit(
              tester,
              authoredAlphaCard,
              'Card alpha before first swipe drag',
            );
            await tester.drag(authoredAlphaCard, const Offset(-120, 0));
            await _boundedPumpAndSettle(tester);

            final swipeDeleteButton = find.byKey(
              const ValueKey('countdown_swipe_delete_button'),
            );
            expect(swipeDeleteButton, findsOneWidget);
            await tester.ensureVisible(swipeDeleteButton);
            await _boundedPumpAndSettle(tester);
            _assertControl44(
              tester,
              swipeDeleteButton,
              'Swipe inline delete button',
            );
            _assertCanHit(
              tester,
              swipeDeleteButton,
              'Swipe inline delete button',
            );

            await tester.runAsync(() => tester.tap(swipeDeleteButton));
            await _boundedPumpAndSettle(tester);
            expect(find.byType(AppDialog), findsOneWidget);
            assertZeroCountdownPersistence('Swipe delete dialog opened');

            final initialDialogElement = tester.element(find.byType(AppDialog));
            final initialDialogRoute = ModalRoute.of(initialDialogElement);

            for (final targetBrand in scenario.cycleBrands) {
              await tester.runAsync(() async {
                final switched = await theme.setBrand(targetBrand);
                expect(switched, isTrue);
                await AccountPreferenceWrites.drain().timeout(
                  const Duration(seconds: 5),
                );
              });
              await _boundedPumpAndSettle(tester);
              assertThemeAndBrightness(
                targetBrand,
                'Swipe delete dialog brand cycle -> $targetBrand',
              );
              expect(
                tester.element(find.byType(AppDialog)),
                same(initialDialogElement),
                reason:
                    'Dialog element preserved across brand switch to $targetBrand',
              );
              expect(
                ModalRoute.of(tester.element(find.byType(AppDialog))),
                same(initialDialogRoute),
                reason:
                    'Dialog route preserved across brand switch to $targetBrand',
              );
              assertZeroCountdownPersistence(
                'After brand switch to $targetBrand with dialog open',
              );
            }

            I18n.setLocale(scenario.alternateLocale);
            await _boundedPumpAndSettle(tester);
            expect(find.byType(AppDialog), findsOneWidget);

            final altDeleteTitle = I18n.tr('anniversary.delete.title');
            final altDeleteContent =
                '"Project Alpha Target" ${I18n.tr('anniversary.delete.content_suffix')}';
            final altCancelText = I18n.tr('action.cancel');
            final altDeleteText = I18n.tr('action.delete');

            await verifyRetainedDialogText(
              tester,
              find.descendant(
                of: find.byType(AppDialog),
                matching: find.text(altDeleteTitle),
              ),
              expected: altDeleteTitle,
            );
            await verifyRetainedDialogText(
              tester,
              find.descendant(
                of: find.byType(AppDialog),
                matching: find.text(altDeleteContent),
              ),
              expected: altDeleteContent,
            );

            final dialogCancelBtn = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(TextButton, altCancelText),
            );
            final dialogDeleteBtn = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(FilledButton, altDeleteText),
            );
            _assertControl44(
              tester,
              dialogCancelBtn,
              'Delete dialog cancel button',
            );
            _assertControl44(
              tester,
              dialogDeleteBtn,
              'Delete dialog confirm button',
            );
            _assertCompositeContrast(
              tester,
              find.descendant(
                of: dialogDeleteBtn,
                matching: find.byType(Text),
              ),
              role: 'Dialog confirm delete button text contrast',
            );

            I18n.setLocale(scenario.initialLocale);
            await _boundedPumpAndSettle(tester);
            expect(find.byType(AppDialog), findsOneWidget);

            await _capture(
              tester,
              boundary,
              '${scenario.name}-02-swipe-delete-dialog-open',
            );

            // 1. Cancel the deletion dialog
            final cancelBtnCurrent = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(
                TextButton,
                I18n.tr('action.cancel'),
              ),
            );
            await tester.ensureVisible(cancelBtnCurrent);
            await _boundedPumpAndSettle(tester);
            _assertCanHit(
              tester,
              cancelBtnCurrent,
              'Swipe delete dialog cancel button',
            );
            await tester.tap(cancelBtnCurrent);
            await _boundedPumpAndSettle(tester);
            await _waitForDateItemIdle(
              tester,
              scopeFinder: authoredAlphaCard,
              requireNoDialog: true,
              role: 'Card alpha after swipe delete dialog cancel',
            );

            expect(find.byType(AppDialog), findsNothing);
            expect(
              countdownProvider.items.any(
                (item) => item.id == 'item-authored-custom-alpha',
              ),
              isTrue,
              reason: 'Item must remain after cancel',
            );
            assertZeroCountdownPersistence(
              'After cancel in swipe delete dialog',
            );

            // 2. Open delete confirmation again and confirm deletion
            await tester.scrollUntilVisible(
              authoredAlphaCard,
              80,
              scrollable: mainListScrollable,
            );
            await Scrollable.ensureVisible(
              tester.element(authoredAlphaCard),
              alignment: 0.5,
            );
            await _boundedPumpAndSettle(tester);

            _assertCanHit(
              tester,
              authoredAlphaCard,
              'Card alpha before second swipe drag',
            );
            await tester.drag(authoredAlphaCard, const Offset(-120, 0));
            await _boundedPumpAndSettle(tester);

            final secondSwipeDeleteButton = find.byKey(
              const ValueKey('countdown_swipe_delete_button'),
            );
            expect(secondSwipeDeleteButton, findsOneWidget);
            await tester.ensureVisible(secondSwipeDeleteButton);
            await _boundedPumpAndSettle(tester);
            _assertControl44(
              tester,
              secondSwipeDeleteButton,
              'Second swipe inline delete button',
            );
            _assertCanHit(
              tester,
              secondSwipeDeleteButton,
              'Second swipe inline delete button',
            );

            await tester.runAsync(() => tester.tap(secondSwipeDeleteButton));
            await _boundedPumpAndSettle(tester);
            expect(find.byType(AppDialog), findsOneWidget);

            final confirmDeleteBtn = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(
                FilledButton,
                I18n.tr('action.delete'),
              ),
            );
            await tester.ensureVisible(confirmDeleteBtn);
            await _boundedPumpAndSettle(tester);
            _assertCanHit(
              tester,
              confirmDeleteBtn,
              'Dialog confirm delete button',
            );
            await tester.runAsync(() => tester.tap(confirmDeleteBtn));
            await _drainAccountWrites(tester);
            await _boundedPumpAndSettle(tester);
            await _waitForDateItemIdle(
              tester,
              requireNoDialog: true,
              role: 'Card swipe confirmed delete',
            );

            expect(find.byType(AppDialog), findsNothing);
            expect(
              countdownProvider.items.any(
                (item) => item.id == 'item-authored-custom-alpha',
              ),
              isFalse,
              reason: 'Item must be deleted after confirm',
            );
            expect(
              store.countdownWrites,
              baselineCountdownWrites + 1,
              reason: 'Exactly 1 write must occur upon confirmed deletion',
            );
            await _capture(
              tester,
              boundary,
              '${scenario.name}-03-swipe-deleted-resolved',
            );
          } else {
            final targetCardId =
                scenario.outcome == _CountdownOutcome.editorCancel
                ? 'item-authored-custom-alpha'
                : (scenario.outcome ==
                        _CountdownOutcome.deleteConfirmedFromEditor
                    ? 'item-authored-work'
                    : 'item-authored-default-literal');

            final cardToOpen = find.byKey(
              ValueKey('countdown_card_$targetCardId'),
            );
            await tester.scrollUntilVisible(
              cardToOpen,
              120,
              scrollable: mainListScrollable,
            );
            expect(cardToOpen, findsOneWidget);
            await tester.ensureVisible(cardToOpen);
            await _boundedPumpAndSettle(tester);
            _assertCanHit(tester, cardToOpen, 'Card to open in editor');
            await tester.tap(cardToOpen);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(find.byType(AppModalSheet), findsOneWidget);
            assertZeroCountdownPersistence('Editor sheet opened');

            final textFields = find.descendant(
              of: find.byType(AppModalSheet),
              matching: find.byType(TextField),
            );
            expect(textFields, findsNWidgets(2));
            final titleField = textFields.first;
            final categoryField = textFields.last;

            final titleController =
                tester.widget<TextField>(titleField).controller!;
            final categoryController =
                tester.widget<TextField>(categoryField).controller!;

            Finder findTitleField() => find.byWidgetPredicate(
              (w) => w is TextField && identical(w.controller, titleController),
            );

            final initialEditorState = _countdownEditorState(
              tester,
              findTitleField(),
            );
            final initialModalRoute = ModalRoute.of(
              tester.element(findTitleField()),
            );

            if (targetCardId == 'item-authored-default-literal') {
              expect(
                categoryController.text,
                '默认',
                reason: 'Authored literal "默认" preserved in editor',
              );
            } else if (targetCardId == 'item-authored-custom-alpha') {
              expect(
                categoryController.text,
                'ProjectAlpha',
                reason: 'Authored category "ProjectAlpha" preserved in editor',
              );
            } else if (targetCardId == 'item-authored-work') {
              expect(
                categoryController.text,
                '工作',
                reason: 'Authored category "工作" preserved in editor',
              );
            }

            const draftCategorySelection = TextSelection(
              baseOffset: 0,
              extentOffset: 2,
            );
            categoryController.selection = draftCategorySelection;
            await tester.pump();
            expect(categoryController.selection, draftCategorySelection);

            Finder findEditorScrollable() => find.descendant(
              of: find.byType(AppModalSheet).last,
              matching: find.byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              ),
            );
            final editorScrollable = findEditorScrollable();
            expect(editorScrollable, findsOneWidget);

            final initialEditorMaxExtent = tester
                .state<ScrollableState>(editorScrollable)
                .position
                .maxScrollExtent;
            if (initialEditorMaxExtent > 0) {
              tester
                  .state<ScrollableState>(editorScrollable)
                  .position
                  .jumpTo((initialEditorMaxExtent * 0.4).clamp(10.0, 80.0));
              await _boundedPumpAndSettle(tester);
            }
            final initialEditorScrollOffset = tester
                .state<ScrollableState>(editorScrollable)
                .position
                .pixels;

            final editorCancelBtn = find.descendant(
              of: find.byType(AppModalSheet).last,
              matching: find.widgetWithText(
                TextButton,
                I18n.tr('action.cancel'),
              ),
            );
            final editorSaveBtn = find.byKey(
              const ValueKey('countdown_editor_save_button'),
            );
            final editorDeleteBtn = find.descendant(
              of: find.byType(AppModalSheet).last,
              matching: find.widgetWithText(
                TextButton,
                I18n.tr('action.delete'),
              ),
            );

            _assertControl44(tester, editorCancelBtn, 'Editor Cancel button');
            _assertControl44(tester, editorSaveBtn, 'Editor Save button');
            _assertControl44(tester, editorDeleteBtn, 'Editor Delete button');

            _assertCompositeContrast(
              tester,
              find.descendant(
                of: editorSaveBtn,
                matching: find.byType(Text),
              ),
              role: 'Editor save button text contrast',
            );

            assertZeroCountdownPersistence('Draft state established in editor');
            await _capture(
              tester,
              boundary,
              '${scenario.name}-02-editor-draft-open',
              scrollableFinder: editorScrollable,
              scrollToOffset: initialEditorScrollOffset,
              restoreOffset: initialEditorScrollOffset,
            );

            for (final targetBrand in scenario.cycleBrands) {
              await tester.runAsync(() async {
                final switched = await theme.setBrand(targetBrand);
                expect(switched, isTrue);
                await AccountPreferenceWrites.drain().timeout(
                  const Duration(seconds: 5),
                );
              });
              await _boundedPumpAndSettle(tester);
              assertThemeAndBrightness(
                targetBrand,
                'Editor open brand cycle -> $targetBrand',
              );

              expect(
                identical(
                  _countdownEditorState(tester, findTitleField()),
                  initialEditorState,
                ),
                isTrue,
                reason:
                    'Editor state identity retained across brand switch to $targetBrand',
              );
              expect(
                identical(
                  ModalRoute.of(tester.element(findTitleField())),
                  initialModalRoute,
                ),
                isTrue,
                reason:
                    'Editor route identity retained across brand switch to $targetBrand',
              );
              expect(categoryController.selection, draftCategorySelection);
              final offsetAfterBrand = tester
                  .state<ScrollableState>(findEditorScrollable())
                  .position
                  .pixels;
              expect(offsetAfterBrand, equals(initialEditorScrollOffset));
              assertZeroCountdownPersistence(
                'After brand switch to $targetBrand in editor',
              );
            }

            I18n.setLocale(scenario.alternateLocale);
            await _boundedPumpAndSettle(tester);
            expect(
              find.text(I18n.tr('countdown.editor.edit_title')),
              findsOneWidget,
            );
            expect(find.text(I18n.tr('action.save')), findsOneWidget);
            expect(find.text(I18n.tr('action.cancel')), findsOneWidget);
            expect(find.text(I18n.tr('action.delete')), findsOneWidget);

            if (targetCardId == 'item-authored-default-literal') {
              expect(
                categoryController.text,
                '默认',
                reason:
                    'Authored literal "默认" remains authored after locale switch',
              );
            }
            expect(categoryController.selection, draftCategorySelection);
            assertZeroCountdownPersistence('After locale switch in editor');

            I18n.setLocale(scenario.initialLocale);
            await _boundedPumpAndSettle(tester);
            expect(
              find.text(I18n.tr('countdown.editor.edit_title')),
              findsOneWidget,
            );
            expect(categoryController.selection, draftCategorySelection);
            assertZeroCountdownPersistence('After locale roundtrip in editor');

            if (scenario.outcome == _CountdownOutcome.editorCancel) {
              final cancelBtn = find.descendant(
                of: find.byType(AppModalSheet).last,
                matching: find.widgetWithText(
                  TextButton,
                  I18n.tr('action.cancel'),
                ),
              );
              await tester.ensureVisible(cancelBtn);
              await _boundedPumpAndSettle(tester);
              _assertCanHit(tester, cancelBtn, 'Editor cancel button');
              await tester.tap(cancelBtn);
              await _boundedPumpAndSettle(tester);

              await _waitForDateItemIdle(
                tester,
                requireNoModalSheet: true,
                role: 'Editor cancel dismissed sheet',
              );

              expect(find.byType(AppModalSheet), findsNothing);
              assertZeroCountdownPersistence('After editor cancel');
              expect(countdownProvider.items.length, 4);
              await _capture(
                tester,
                boundary,
                '${scenario.name}-03-editor-cancelled',
              );
            } else {
              final deleteBtn = find.descendant(
                of: find.byType(AppModalSheet).last,
                matching: find.widgetWithText(
                  TextButton,
                  I18n.tr('action.delete'),
                ),
              );
              await tester.ensureVisible(deleteBtn);
              await _boundedPumpAndSettle(tester);
              _assertCanHit(tester, deleteBtn, 'Editor delete button');
              await tester.runAsync(() => tester.tap(deleteBtn));
              await _boundedPumpAndSettle(tester);
              expect(find.byType(AppDialog), findsOneWidget);
              assertZeroCountdownPersistence(
                'Delete confirmation dialog opened from editor',
              );

              final dialogElement = tester.element(find.byType(AppDialog));
              final dialogRoute = ModalRoute.of(dialogElement);

              for (final targetBrand in scenario.cycleBrands) {
                await tester.runAsync(() async {
                  final switched = await theme.setBrand(targetBrand);
                  expect(switched, isTrue);
                  await AccountPreferenceWrites.drain().timeout(
                    const Duration(seconds: 5),
                  );
                });
                await _boundedPumpAndSettle(tester);
                assertThemeAndBrightness(
                  targetBrand,
                  'Delete confirmation open brand cycle -> $targetBrand',
                );
                expect(
                  tester.element(find.byType(AppDialog)),
                  same(dialogElement),
                  reason:
                      'Delete dialog element retained across brand switch to $targetBrand',
                );
                expect(
                  ModalRoute.of(tester.element(find.byType(AppDialog))),
                  same(dialogRoute),
                  reason:
                      'Delete dialog route retained across brand switch to $targetBrand',
                );
                assertZeroCountdownPersistence(
                  'After brand switch to $targetBrand with dialog open',
                );
              }

              I18n.setLocale(scenario.alternateLocale);
              await _boundedPumpAndSettle(tester);
              expect(find.byType(AppDialog), findsOneWidget);

              final itemTitle = targetCardId == 'item-authored-work'
                  ? 'Work Sprint Review'
                  : 'Authored Literal Default';

              final expectedDialogTitle = I18n.tr('anniversary.delete.title');
              final expectedDialogContent =
                  '"$itemTitle" ${I18n.tr('anniversary.delete.content_suffix')}';
              final expectedCancelLabel = I18n.tr('action.cancel');
              final expectedDeleteLabel = I18n.tr('action.delete');

              await verifyRetainedDialogText(
                tester,
                find.descendant(
                  of: find.byType(AppDialog),
                  matching: find.text(expectedDialogTitle),
                ),
                expected: expectedDialogTitle,
              );
              await verifyRetainedDialogText(
                tester,
                find.descendant(
                  of: find.byType(AppDialog),
                  matching: find.text(expectedDialogContent),
                ),
                expected: expectedDialogContent,
              );

              final dCancel = find.descendant(
                of: find.byType(AppDialog),
                matching: find.widgetWithText(TextButton, expectedCancelLabel),
              );
              final dDelete = find.descendant(
                of: find.byType(AppDialog),
                matching: find.widgetWithText(
                  FilledButton,
                  expectedDeleteLabel,
                ),
              );
              _assertControl44(tester, dCancel, 'Dialog Cancel button');
              _assertControl44(tester, dDelete, 'Dialog Delete button');
              _assertCompositeContrast(
                tester,
                find.descendant(
                  of: dDelete,
                  matching: find.byType(Text),
                ),
                role: 'Dialog confirm delete button contrast',
              );

              I18n.setLocale(scenario.initialLocale);
              await _boundedPumpAndSettle(tester);
              expect(find.byType(AppDialog), findsOneWidget);

              await _capture(
                tester,
                boundary,
                '${scenario.name}-03-delete-confirmation-open',
              );

              if (scenario.outcome ==
                  _CountdownOutcome.deleteConfirmedFromEditor) {
                final confirmBtn = find.descendant(
                  of: find.byType(AppDialog),
                  matching: find.widgetWithText(
                    FilledButton,
                    I18n.tr('action.delete'),
                  ),
                );
                await tester.ensureVisible(confirmBtn);
                await _boundedPumpAndSettle(tester);
                _assertCanHit(tester, confirmBtn, 'Delete dialog confirm button');
                await tester.runAsync(() => tester.tap(confirmBtn));
                await _drainAccountWrites(tester);
                await _boundedPumpAndSettle(tester);

                await _waitForDateItemIdle(
                  tester,
                  requireNoDialog: true,
                  requireNoModalSheet: true,
                  role: 'Editor delete confirmed and sheet dismissed',
                );

                expect(find.byType(AppDialog), findsNothing);
                expect(find.byType(AppModalSheet), findsNothing);
                expect(
                  countdownProvider.items.any(
                    (item) => item.id == targetCardId,
                  ),
                  isFalse,
                  reason: 'Item must be removed from provider',
                );
                expect(
                  store.countdownWrites,
                  baselineCountdownWrites + 1,
                  reason:
                      'Confirmed deletion must execute exactly 1 storage write',
                );
                await _capture(
                  tester,
                  boundary,
                  '${scenario.name}-04-editor-deleted-resolved',
                );
              } else if (scenario.outcome ==
                  _CountdownOutcome.deleteDeniedThenSave) {
                final cancelDialogBtn = find.descendant(
                  of: find.byType(AppDialog),
                  matching: find.widgetWithText(
                    TextButton,
                    I18n.tr('action.cancel'),
                  ),
                );
                await tester.ensureVisible(cancelDialogBtn);
                await _boundedPumpAndSettle(tester);
                _assertCanHit(
                  tester,
                  cancelDialogBtn,
                  'Delete confirmation cancel button',
                );
                await tester.tap(cancelDialogBtn);
                await _boundedPumpAndSettle(tester);

                final currentTitleField = findTitleField();
                await _waitForDateItemIdle(
                  tester,
                  scopeFinder: find.byType(AppModalSheet).last,
                  textFieldFinder: currentTitleField,
                  requireNoDialog: true,
                  role: 'Editor after delete confirmation denial',
                );

                expect(find.byType(AppDialog), findsNothing);
                expect(find.byType(AppModalSheet), findsOneWidget);
                assertZeroCountdownPersistence(
                  'After delete denial, editor remains open',
                );
                expect(
                  countdownProvider.items.any(
                    (item) => item.id == targetCardId,
                  ),
                  isTrue,
                );

                await tester.ensureVisible(currentTitleField);
                await _boundedPumpAndSettle(tester);
                _assertCanHit(tester, currentTitleField, 'Editor title field');
                await tester.tap(currentTitleField);
                await tester.enterText(
                  currentTitleField,
                  'Authored Literal Default Updated',
                );
                await _boundedPumpAndSettle(tester);

                final saveBtn = find.byKey(
                  const ValueKey('countdown_editor_save_button'),
                );
                await tester.ensureVisible(saveBtn);
                await _boundedPumpAndSettle(tester);
                _assertCanHit(tester, saveBtn, 'Editor save button');
                await tester.runAsync(() => tester.tap(saveBtn));
                await _drainAccountWrites(tester);
                await _boundedPumpAndSettle(tester);

                await _waitForDateItemIdle(
                  tester,
                  requireNoDialog: true,
                  requireNoModalSheet: true,
                  role: 'Editor save committed and sheet dismissed',
                );

                expect(find.byType(AppModalSheet), findsNothing);
                expect(
                  store.countdownWrites,
                  baselineCountdownWrites + 1,
                  reason: 'Save must execute exactly 1 storage write',
                );

                final updatedItem = countdownProvider.items.firstWhere(
                  (item) => item.id == targetCardId,
                );
                expect(updatedItem.title, 'Authored Literal Default Updated');
                expect(
                  updatedItem.category,
                  '默认',
                  reason: 'User-authored literal "默认" preserved across save',
                );
                expect(
                  updatedItem.categoryIsDefault,
                  isFalse,
                  reason:
                      'User-authored literal remains non-default categoryIsDefault flag',
                );

                await _capture(
                  tester,
                  boundary,
                  '${scenario.name}-04-editor-saved-resolved',
                );
              }
            }
          }

          expect(tester.takeException(), isNull);
        } finally {
          try {
            await _drainAccountWrites(tester);
            await tester.pumpWidget(const SizedBox.shrink());
            await _boundedPumpAndSettle(tester);
          } finally {
            WidgetController.hitTestWarningShouldBeFatal = originalHitTestFatal;
            SharedPreferences.resetStatic();
            SharedPreferencesStorePlatform.instance = previousStore;
            LocalTimezoneResolver.debugSystemTimeZoneReader =
                originalTimeZoneReader;
            LocalTimezoneResolver.debugNativeSystemTimeZoneReader =
                originalNativeTimeZoneReader;
            countdownProvider.dispose();
            theme.dispose();
            preferences.dispose();
            transport.close();
            tester.view.reset();
            debugDisableShadows = originalShadows;
            I18n.setLocale(originalLocale);
          }
        }
      },
    );
  }
}
