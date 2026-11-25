import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Optional evidence for a repaint boundary around the production route.
///
/// Set ICS_CAPTURE_DIR to a named directory under evidence/. The harness owns
/// disk admission, the serial lock and resource guard. This helper acquires no
/// locks, loads no fonts, and allocates no semantics handles.
class IcsVisualCapture {
  IcsVisualCapture({required this.caseName, required this.initialBrand});

  final key = GlobalKey(debugLabel: 'ics-visual-capture');
  final String caseName;
  final String initialBrand;

  static final _runName =
      'ics-visual-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';
  static int _sequence = 0;

  /// Always pumps one frame, including when capture output is disabled.
  ///
  /// Place [key] on the production route's RepaintBoundary inside its window
  /// MediaQuery. [metadata] supplies JSON-safe durable/origin/semantic snapshots
  /// under the sidecar's `state` key. Font loading remains with the harness.
  Future<void> take(
    WidgetTester tester,
    String phase, {
    required String actualBrand,
    required String locale,
    required Map<String, Object?> metadata,
  }) async {
    await tester.pump();
    final root = Platform.environment['ICS_CAPTURE_DIR'];
    if (root == null || root.trim().isEmpty) return;
    // Retain existing accepted evidence; emit only the changed states when an
    // acceptance batch supplies a phase filter. Pump behavior stays identical.
    final phases = Platform.environment['ICS_CAPTURE_PHASES'];
    if (phases != null && !RegExp(phases).hasMatch(phase)) return;

    final context = key.currentContext;
    final renderObject = context?.findRenderObject();
    if (context == null || renderObject is! RenderRepaintBoundary) {
      throw StateError('ICS capture requires a mounted repaint boundary');
    }
    final supplied = _evidenceDirectory(root);
    final index = _sequence++;
    final name =
        '${_segment(initialBrand)}-${_segment(caseName)}-'
        '$index-${_segment(phase)}';
    final media = MediaQuery.maybeOf(context);
    final physical = tester.view.physicalSize;
    final ratio = tester.view.devicePixelRatio;
    final logical = physical / ratio;
    final mediaSize = media?.size ?? logical;
    final insets = media?.viewInsets ?? EdgeInsets.zero;
    final scope = find.byKey(key);
    final fieldFinder = _scoped(scope, find.byType(TextField));
    final progressFinder = _scoped(
      scope,
      find.byWidgetPredicate((widget) => widget is ProgressIndicator),
    );
    final uiSnapshot = <String, Object?>{
      'run': _runName,
      'name': name,
      'case': caseName,
      'phase': phase,
      'sequence': index,
      'initialBrand': initialBrand,
      'actualBrand': actualBrand,
      'locale': locale,
      'physicalSize': [physical.width, physical.height],
      'devicePixelRatio': ratio,
      'logicalSize': [logical.width, logical.height],
      'mediaSize': [mediaSize.width, mediaSize.height],
      'textScale': media?.textScaler.scale(1.0) ?? 1.0,
      'keyboardInset': insets.bottom,
      'viewInsets': _insets(insets),
      'viewPadding': _insets(media?.viewPadding ?? EdgeInsets.zero),
      'padding': _insets(media?.padding ?? EdgeInsets.zero),
      'literalFields': _fieldSnapshots(fieldFinder),
      'progress': _progressSnapshots(progressFinder),
      'controls': _controlSnapshots(
        _scoped(
          scope,
          find.byWidgetPredicate(
            (widget) =>
                widget is ButtonStyleButton ||
                widget is IconButton ||
                widget is PopupMenuButton ||
                widget is PopupMenuItem ||
                widget is ChoiceChip,
          ),
        ),
      ),
    };

    await tester.runAsync(() async {
      // Validate and freeze caller state before creating either artifact.
      final state = jsonDecode(jsonEncode(metadata));
      final batch = Directory('$supplied/$_runName');
      await batch.create(recursive: true);
      final picture = await renderObject.toImage(pixelRatio: 1);
      try {
        final data = await picture.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('ICS PNG encoding returned no data');
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final checksum = sha256.convert(bytes).toString();
        final png = File('${batch.path}/$name.png');
        final json = File('${batch.path}/$name.json');
        await png.writeAsBytes(bytes);
        await json.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            ...uiSnapshot,
            'png': png.path,
            'pngSha256': checksum,
            'capturePixelRatio': 1,
            'pngSize': [picture.width, picture.height],
            'state': state,
          }),
        );
      } finally {
        picture.dispose();
      }
    });
  }
}

String _evidenceDirectory(String root) {
  final evidence = Directory(
    'evidence',
  ).absolute.uri.normalizePath().toFilePath();
  final supplied = Directory(root).absolute.uri.normalizePath().toFilePath();
  final prefix = evidence.endsWith(Platform.pathSeparator)
      ? evidence
      : '$evidence${Platform.pathSeparator}';
  if (supplied != evidence && !supplied.startsWith(prefix)) {
    throw StateError('ICS_CAPTURE_DIR must be under evidence/');
  }
  return supplied;
}

String _segment(String value) =>
    value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');

Finder _scoped(Finder? scope, Finder finder) =>
    scope == null ? finder : find.descendant(of: scope, matching: finder);

Map<String, double> _insets(EdgeInsets value) => {
  'left': value.left,
  'top': value.top,
  'right': value.right,
  'bottom': value.bottom,
};

Map<String, double>? _rect(Element element) {
  final box = element.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  final topLeft = box.localToGlobal(Offset.zero);
  final bottomRight = box.localToGlobal(
    Offset(box.size.width, box.size.height),
  );
  return {
    'left': topLeft.dx,
    'top': topLeft.dy,
    'right': bottomRight.dx,
    'bottom': bottomRight.dy,
  };
}

List<Map<String, Object?>> _fieldSnapshots(Finder finder) => [
  for (final element in finder.evaluate())
    if (element.widget is TextField)
      _fieldSnapshot(element, element.widget as TextField),
];

Map<String, Object?> _fieldSnapshot(Element element, TextField field) {
  final value = field.controller?.value;
  return {
    'label': field.decoration?.labelText,
    'text': value?.text,
    'selectionBase': value?.selection.baseOffset,
    'selectionExtent': value?.selection.extentOffset,
    'selectionAffinity': value?.selection.affinity.name,
    'selectionDirectional': value?.selection.isDirectional,
    'composingStart': value?.composing.start,
    'composingEnd': value?.composing.end,
    'error': field.decoration?.errorText,
    'enabled': field.enabled ?? field.decoration?.enabled ?? true,
    'readOnly': field.readOnly,
    'rect': _rect(element),
  };
}

List<Map<String, Object?>> _progressSnapshots(Finder finder) {
  final hitTestable = finder.hitTestable().evaluate().toSet();
  return [
    for (final element in finder.evaluate())
      if (element.widget is ProgressIndicator)
        {
          'type': element.widget.runtimeType.toString(),
          'value': (element.widget as ProgressIndicator).value,
          'semanticsLabel':
              (element.widget as ProgressIndicator).semanticsLabel,
          'semanticsValue':
              (element.widget as ProgressIndicator).semanticsValue,
          'hitTestable': hitTestable.contains(element),
          'rect': _rect(element),
        },
  ];
}

List<Map<String, Object?>> _controlSnapshots(Finder finder) {
  final hitTestable = finder.hitTestable().evaluate().toSet();
  return [
    for (final element in finder.evaluate())
      {
        'type': element.widget.runtimeType.toString(),
        'captions': _captions(element),
        'enabled': _enabled(element.widget),
        'hitTestable': hitTestable.contains(element),
        'rect': _rect(element),
      },
  ];
}

List<String> _captions(Element element) {
  final owner = find.byElementPredicate(
    (candidate) => identical(candidate, element),
    skipOffstage: false,
  );
  return [
    for (final child
        in find
            .descendant(
              of: owner,
              matching: find.byType(Text, skipOffstage: false),
            )
            .evaluate())
      ((child.widget as Text).data ??
          (child.widget as Text).textSpan?.toPlainText() ??
          ''),
  ];
}

bool? _enabled(Widget widget) {
  if (widget is ButtonStyleButton) {
    return widget.onPressed != null || widget.onLongPress != null;
  }
  if (widget is IconButton) return widget.onPressed != null;
  if (widget is PopupMenuButton) return widget.enabled;
  if (widget is PopupMenuItem) return widget.enabled;
  if (widget is ChoiceChip) return widget.onSelected != null;
  return null;
}
