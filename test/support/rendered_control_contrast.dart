import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the built control's text and ancestor fills, including Ink card
/// decorations and button Materials. Gradient stops are checked separately.
void expectReadableControl(WidgetTester tester, Finder control) {
  final textFinder = find.descendant(of: control, matching: find.byType(Text));
  expect(textFinder, findsOneWidget);
  final element = tester.element(textFinder);
  final text = tester.widget<Text>(textFinder);
  final foreground = DefaultTextStyle.of(
    element,
  ).style.merge(text.style).color!;
  final layers = <List<Color>>[];
  void addDecoration(Decoration? decoration) {
    if (decoration is! BoxDecoration) return;
    final layer = <List<Color>>[];
    if (decoration.color case final color?) layer.add([color]);
    if (decoration.gradient case final gradient?) layer.add(gradient.colors);
    // Ancestors are visited inside out; decoration paints color before gradient.
    layers.addAll(layer.reversed);
  }

  element.visitAncestorElements((ancestor) {
    switch (ancestor.widget) {
      case Material(:final color):
        if (color != null) layers.add([color]);
      case Ink(:final decoration):
        addDecoration(decoration);
      case DecoratedBox(:final decoration):
        addDecoration(decoration);
    }
    return true;
  });
  var backgrounds = <Color>[Colors.white];
  for (final layer in layers.reversed) {
    backgrounds = [
      for (final background in backgrounds)
        for (final color in layer) Color.alphaBlend(color, background),
    ];
  }
  for (final background in backgrounds) {
    expect(
      appContrastRatio(Color.alphaBlend(foreground, background), background),
      greaterThanOrEqualTo(4.5),
      reason: '${text.data}: $foreground on $background',
    );
  }
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: textFinder, matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
    paragraph.textSize.width,
    lessThanOrEqualTo(paragraph.size.width + 0.1),
  );
  expect(
    paragraph.textSize.height,
    lessThanOrEqualTo(paragraph.size.height + 0.1),
  );
  final textRect = tester.getRect(textFinder);
  final controlRect = tester.getRect(control);
  expectControlTouchTarget(tester, control);
  expect(controlRect.inflate(0.1).contains(textRect.topLeft), isTrue);
  expect(controlRect.inflate(0.1).contains(textRect.bottomRight), isTrue);
}

Future<void> captureControlPage(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  if (Platform.environment['DUOYI_CAPTURE_PRIORITY_CONTROLS'] != '1') return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    try {
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'evidence/screenshots/widget-priority-followup-20261019/$name.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}

Future<void> withControlEvidenceShadows(Future<void> Function() body) async {
  final original = debugDisableShadows;
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = original;
  }
}

void expectControlTouchTarget(WidgetTester tester, Finder control) {
  final rect = tester.getRect(control);
  expect(
    rect.width,
    greaterThanOrEqualTo(44 - 1e-7),
    reason: 'secondary action width',
  );
  expect(
    rect.height,
    greaterThanOrEqualTo(44 - 1e-7),
    reason: 'secondary action height',
  );
  final semanticsHandle = tester.ensureSemantics();
  try {
    final node = tester.getSemantics(control);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    // These fixtures use translation only. Reject a larger merged ancestor
    // rather than mistaking the surrounding row's action for this button.
    expect(node.rect.width, closeTo(rect.width, 0.1));
    expect(node.rect.height, closeTo(rect.height, 0.1));
  } finally {
    semanticsHandle.dispose();
  }
  final controlRender = tester.renderObject(control);
  bool belongsToControl(Object target) {
    if (target is! RenderObject) return false;
    RenderObject? current = target;
    while (current != null) {
      if (identical(current, controlRender)) return true;
      current = current.parent;
    }
    return false;
  }

  // Sample just inside the 44dp square's edges. This is a hit-test sample,
  // not a proof of every continuous point or gesture-arena outcome.
  const edge = 22.0 - 0.01;
  for (final dx in [-edge, 0.0, edge]) {
    for (final dy in [-edge, 0.0, edge]) {
      final hit = tester.hitTestOnBinding(rect.center + Offset(dx, dy));
      expect(
        hit.path.any((entry) => belongsToControl(entry.target)),
        isTrue,
        reason: '44dp target must hit this control at ($dx, $dy)',
      );
    }
  }
  final viewport =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  expect(viewport.inflate(0.1).contains(rect.topLeft), isTrue);
  expect(viewport.inflate(0.1).contains(rect.bottomRight), isTrue);
}
