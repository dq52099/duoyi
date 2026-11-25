import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart' show appContrastRatio;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../test_support/recording_reminder_scheduler.dart';

// Timers are created in runAsync's real zone, where they can actually fire.
// A timeout in the widget test's fake zone cannot bound a stalled real await.
void _stage(String label) {
  // ignore: avoid_print
  print('habit-capture247 $label');
}

Future<void> _hostStage(
  WidgetTester tester,
  String label,
  Future<void> Function() operation,
) async {
  _stage('$label start');
  final completed = await tester.runAsync(() async {
    try {
      await operation().timeout(const Duration(seconds: 20));
      return true;
    } catch (error) {
      _stage('$label failed: $error');
      rethrow;
    }
  });
  expect(completed, isTrue, reason: 'Host stage failed: $label');
  _stage('$label done');
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

// Only finite, bounded RenderFlex layout overflows belong in baseline evidence.
// Other Flutter errors remain owned by the original test error handler.
class _BaselineOverflows {
  final List<Map<String, Object?>> records = [];
  final Set<String> _signatures = {};
  final void Function(FlutterErrorDetails)? _previous = FlutterError.onError;
  String phase = 'setup';
  String? capture;
  final ThemeProvider Function() theme;

  _BaselineOverflows(this.theme) {
    FlutterError.onError = _handle;
  }

  void restore() => FlutterError.onError = _previous;

  void _handle(FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    final match = RegExp(
      r'^A RenderFlex overflowed by ([0-9]+(?:\.[0-9]+)?) pixels on the (left|right|top|bottom)\.$',
    ).firstMatch(message);
    final amount = match == null ? null : double.tryParse(match.group(1)!);
    final context = details.context?.toDescription();
    if (details.exception is! FlutterError ||
        details.library != 'rendering library' ||
        context != 'during layout' ||
        amount == null || !amount.isFinite || amount <= 0 || amount > 16) {
      _forward(details);
      return;
    }
    final diagnostic = details.toString();
    // Limit both event volume and distinct faults; repeats can still carry
    // actual new state identity without flooding the diagnostic files.
    final signature = message;
    if (records.length >= 64 || (_signatures.length >= 8 && !_signatures.contains(signature))) {
      _forward(details);
      return;
    }
    _signatures.add(signature);
    final record = <String, Object?>{
      'index': records.length, 'phase': phase, 'capture': capture,
      'brand': theme().brand.id, 'locale': I18n.current.storageValue,
      'message': message, 'pixels': amount, 'edge': match!.group(2),
      'library': details.library, 'context': context,
      'stack': details.stack?.toString(), 'diagnostic': diagnostic,
    };
    records.add(record);
    _stage('baseline overflow ${record['index']} ${record['brand']}/${record['locale']}: $message');
    // Emit original diagnostics as a print, preserving source/constraints and
    // the real yellow/black overflow indicator in the subsequent PNG.
    // ignore: avoid_print
    print(diagnostic);
  }

  void _forward(FlutterErrorDetails details) {
    if (_previous != null) {
      _previous(details);
    } else {
      Error.throwWithStackTrace(details.exception, details.stack ?? StackTrace.current);
    }
  }

  List<Map<String, Object?>> snapshot() => [
    for (final record in records) Map<String, Object?>.from(record),
  ];
}

List<Map<String, Object?>> _renderFlexOverflows(
  WidgetTester tester,
  RenderRepaintBoundary boundary,
) {
  final found = <Map<String, Object?>>[];
  for (final element in find.descendant(
    of: find.byType(HabitScreen),
    matching: find.byWidgetPredicate((widget) => widget is Flex),
  ).evaluate()) {
    final object = element.renderObject;
    if (object is! RenderFlex || !object.hasSize || !object.toStringShort().contains('OVERFLOWING')) continue;
    Rect? children;
    object.visitChildren((child) {
      if (child is RenderBox && child.hasSize) {
        final data = child.parentData! as FlexParentData;
        final rect = data.offset & child.size;
        children = children == null ? rect : children!.expandToInclude(rect);
      }
    });
    final rect = MatrixUtils.transformRect(object.getTransformTo(boundary), Offset.zero & object.size);
    final childRect = children;
    final overflow = childRect == null ? const <String, double>{} : <String, double>{
      'left': childRect.left < 0 ? -childRect.left : 0,
      'top': childRect.top < 0 ? -childRect.top : 0,
      'right': childRect.right > object.size.width ? childRect.right - object.size.width : 0,
      'bottom': childRect.bottom > object.size.height ? childRect.bottom - object.size.height : 0,
    };
    if (overflow.values.any((amount) => !amount.isFinite || amount > 16)) {
      throw StateError('Baseline RenderFlex exceeds 16px evidence bound: $overflow');
    }
    found.add({
      'renderObject': object.toStringShort(), 'creator': object.debugCreator?.toString(),
      'direction': object.direction.name, 'rect': _rect(rect),
      'childrenRect': childRect == null ? null : _rect(childRect),
      'childBoundsOverflow': overflow,
      'visibleInRootViewport': rect.overlaps(Offset.zero & boundary.size),
      'constraints': object.constraints.toString(),
      'diagnostic': object.toStringDeep(),
    });
  }
  return found;
}

Finder _kind(String type) => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == type,
);
Finder _card(String id) => find.byKey(ValueKey('habit_checkin_card_$id'));
Finder _feedback(String id, String key) => find.descendant(
  of: _card(id), matching: find.byKey(ValueKey(key)),
);
Finder _streak(String id) => find.descendant(
  of: _card(id), matching: _kind('_HabitStreakBadge'),
);
Finder _todayScrollable() => find.descendant(
  of: find.byKey(const ValueKey('habit_today_scroll_view')),
  matching: find.byType(Scrollable),
).first;

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final scroll = tester.state<ScrollableState>(_todayScrollable());
  scroll.position.jumpTo(scroll.position.minScrollExtent);
  await _settle(tester);
  await tester.scrollUntilVisible(target, 250, scrollable: _todayScrollable());
  await tester.ensureVisible(target);
  await _settle(tester);
}

List<double> _rect(Rect rect) => [rect.left, rect.top, rect.width, rect.height];

// Final PNG is encoded before any readability assertion. Strict mode checks
// only after every affected baseline view has been captured.
Future<Map<String, Object?>> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Finder scope,
  List<Finder> statusScopes,
  String name,
  Map<String, Object?> state,
  _BaselineOverflows overflows,
) async {
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  Rect inImage(RenderBox box) => MatrixUtils.transformRect(
    box.getTransformTo(boundary), Offset.zero & box.size,
  );
  final viewport = Offset.zero & boundary.size;
  final scopeRect = inImage(tester.renderObject<RenderBox>(scope));
  overflows.capture = name;
  _stage('capture $name start');
  final captured = await tester.runAsync(() async {
    return await (() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final directory = Platform.environment['DUOYI_HABIT_PRIORITY_SCREENSHOTS'];
      if (directory != null && directory.isNotEmpty) {
        final file = File('$directory/$name.png');
        if (file.existsSync()) throw StateError('Refusing to overwrite $file');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(png.buffer.asUint8List());
      }
      return (rgba: rgba, width: image.width, height: image.height);
    } finally {
      image.dispose();
    }
    })().timeout(const Duration(seconds: 20));
  });
  expect(captured, isNotNull);
  final raster = captured!;
  final probes = <Map<String, Object?>>[];
  for (final status in statusScopes) {
    expect(status, findsOneWidget);
    final statusRect = inImage(tester.renderObject<RenderBox>(status));
    expect(viewport.contains(statusRect.topLeft), isTrue);
    expect(viewport.contains(statusRect.bottomRight - const Offset(.01, .01)), isTrue);
    // Text widgets exclude the adjacent Icon's separate RichText paragraph.
    final texts = find.descendant(of: status, matching: find.byType(Text));
    final textFinders = texts.evaluate().isEmpty && tester.widget(status) is Text
        ? [status]
        : [for (final element in texts.evaluate()) find.byElementPredicate((candidate) => identical(candidate, element))];
    expect(textFinders, isNotEmpty);
    for (final text in textFinders) {
      final richText = find.descendant(of: text, matching: find.byType(RichText));
      final paragraph = tester.renderObject<RenderParagraph>(richText);
      final textRect = inImage(paragraph);
      final transform = paragraph.getTransformTo(boundary);
      final origin = MatrixUtils.transformPoint(transform, Offset.zero);
      final xScale = (MatrixUtils.transformPoint(transform, const Offset(1, 0)) - origin).distance;
      final yScale = (MatrixUtils.transformPoint(transform, const Offset(0, 1)) - origin).distance;
      final foreground = paragraph.text.style?.foreground?.color ?? paragraph.text.style?.color;
      expect(foreground, isNotNull);
      final isSummaryPercent = paragraph.text.toPlainText() == '100%';
      late Rect fillRect;
      Rect? ringRect;
      double? innerRadius;
      late String paintedSurface;
      RenderBox? surfaceBox;
      BoxDecoration? surfaceDecoration;
      RRect? surfaceSafeFill;
      Offset Function(Offset)? surfaceLocalPoint;
      RenderBox? ringCanvas;
      Rect? ringPaintExclusion;
      Map<String, Object?>? ringParagraphGeometry;
      final paintExclusions = <Rect>[];
      final paintExclusionReports = <Map<String, Object?>>[];
      if (isSummaryPercent) {
        // Resolve the nearest actually filled ancestor of THIS paragraph.
        // AppSurfaceCard uses Ink; a relocated label can have a closer fill.
        tester.element(text).visitAncestorElements((element) {
          final widget = element.widget;
          final decoration = widget is Ink ? widget.decoration
              : widget is DecoratedBox && widget.position == DecorationPosition.background
              ? widget.decoration : null;
          if (decoration is! BoxDecoration ||
              (decoration.gradient == null && (decoration.color?.a ?? 0) == 0)) {
            return true;
          }
          expect(decoration.image, isNull,
            reason: '100% probe requires a known blank color/gradient fill.');
          final object = element.renderObject;
          expect(object, isA<RenderBox>());
          surfaceBox = object! as RenderBox;
          surfaceDecoration = decoration;
          paintedSurface = 'nearest filled ${widget.runtimeType} ancestor of 100%';
          return false;
        });
        expect(surfaceBox, isNotNull,
          reason: '100% must have an actual Ink/DecoratedBox painted background.');
        final box = surfaceBox!;
        final decoration = surfaceDecoration!;
        fillRect = inImage(box);
        final direction = Directionality.of(tester.element(text));
        final border = decoration.border?.dimensions.resolve(direction) ?? EdgeInsets.zero;
        final inset = math.max(math.max(border.left, border.right),
          math.max(border.top, border.bottom)) + 2;
        final localFill = Offset.zero & box.size;
        surfaceSafeFill = decoration.shape == BoxShape.circle
            ? RRect.fromRectAndRadius(
                Rect.fromCircle(center: localFill.center, radius: localFill.shortestSide / 2),
                Radius.circular(localFill.shortestSide / 2)).deflate(inset)
            : (decoration.borderRadius?.resolve(direction).toRRect(localFill)
                ?? RRect.fromRectAndRadius(localFill, Radius.zero)).deflate(inset);
        surfaceLocalPoint = (point) => box.globalToLocal(
          boundary.localToGlobal(point));
        final indicator = find.descendant(of: scope, matching: find.byType(CircularProgressIndicator));
        expect(indicator, findsOneWidget);
        final widget = tester.widget<CircularProgressIndicator>(indicator);
        expect(widget.value, 1);
        // The CustomPaint bounds describe the actual ring canvas, including
        // any theme padding applied outside it by CircularProgressIndicator.
        final paint = find.descendant(of: indicator, matching: find.byType(CustomPaint));
        expect(paint, findsOneWidget);
        final canvas = tester.renderObject<RenderBox>(paint);
        ringCanvas = canvas;
        ringRect = inImage(canvas);
        final matrix = canvas.getTransformTo(boundary);
        final zero = MatrixUtils.transformPoint(matrix, Offset.zero);
        final sx = (MatrixUtils.transformPoint(matrix, const Offset(1, 0)) - zero).distance;
        final sy = (MatrixUtils.transformPoint(matrix, const Offset(0, 1)) - zero).distance;
        final stroke = widget.strokeWidth ?? ProgressIndicatorTheme.of(tester.element(indicator)).strokeWidth;
        expect(stroke, isNotNull);
        // Reserve a full stroke plus 2px AA margin: safely inside both
        // center- and inside-aligned ring paint, without sampling its arc.
        final strokeMargin = stroke! * math.max(sx, sy) + 2;
        innerRadius = math.min(ringRect.width, ringRect.height) / 2 - strokeMargin;
        ringPaintExclusion = ringRect.inflate(strokeMargin);
        expect(innerRadius, greaterThan(0));
        // Readability must also keep the WHOLE paragraph off the ring stroke.
        // Bound the actual transformed canvas conservatively: the inner
        // circle uses the shorter axis, the outer circle the longer axis,
        // both with the real scaled stroke plus the existing 2px AA margin.
        // Baseline records this fault; strict rejects it after all 20 views.
        final center = ringRect.center;
        final canvasRadius = math.min(ringRect.width, ringRect.height) / 2;
        final safeOuterRadius = math.max(ringRect.width, ringRect.height) / 2 + strokeMargin;
        final corners = [textRect.topLeft, textRect.topRight,
          textRect.bottomRight, textRect.bottomLeft];
        final cornerDistances = [for (final corner in corners) (corner - center).distance];
        final maxCornerDistance = cornerDistances.reduce(math.max);
        final nearestParagraphPoint = Offset(
          center.dx.clamp(textRect.left, textRect.right).toDouble(),
          center.dy.clamp(textRect.top, textRect.bottom).toDouble(),
        );
        final nearestParagraphDistance = (nearestParagraphPoint - center).distance;
        final paragraphCenterDistance = (textRect.center - center).distance;
        final centerInsideRing = paragraphCenterDistance <= canvasRadius;
        final whollyInsideSafeCircle = cornerDistances.every((distance) => distance <= innerRadius!);
        final whollyOutsideStroke = nearestParagraphDistance > safeOuterRadius;
        ringParagraphGeometry = {
          'coordinateSpace': 'root screenshot pixels',
          'ringCenter': [center.dx, center.dy],
          'canvasInscribedRadius': canvasRadius,
          'safeInnerRadius': innerRadius,
          'safeOuterRadius': safeOuterRadius,
          'scaledStrokeWidth': strokeMargin - 2,
          'antialiasMargin': 2,
          'paragraphCenter': [textRect.center.dx, textRect.center.dy],
          'paragraphCenterDistance': paragraphCenterDistance,
          'centerInsideRing': centerInsideRing,
          'placement': centerInsideRing ? 'inside-ring' : 'outside-ring',
          'paragraphCorners': [for (var i = 0; i < corners.length; i++) {
            'point': [corners[i].dx, corners[i].dy], 'distanceToRingCenter': cornerDistances[i],
            'insideSafeCircle': cornerDistances[i] <= innerRadius,
          }],
          'maxCornerDistance': maxCornerDistance,
          'innerClearance': innerRadius - maxCornerDistance,
          'nearestParagraphPoint': [nearestParagraphPoint.dx, nearestParagraphPoint.dy],
          'nearestParagraphDistance': nearestParagraphDistance,
          'outerClearance': nearestParagraphDistance - safeOuterRadius,
          'whollyInsideSafeCircle': whollyInsideSafeCircle,
          'whollyOutsideStroke': whollyOutsideStroke,
          'intersectsGuardedStroke': !whollyInsideSafeCircle && !whollyOutsideStroke,
          'placementAccepted': centerInsideRing ? whollyInsideSafeCircle : whollyOutsideStroke,
        };
        bool containsParagraph(RenderObject object) {
          RenderObject? ancestor = paragraph;
          while (ancestor != null) {
            if (identical(ancestor, object)) return true;
            ancestor = ancestor.parent;
          }
          return false;
        }
        void collectPaintExclusions(RenderObject object) {
          // Paragraphs also cover Icon RichText. Unknown custom paint and
          // neighboring decorated/image/physical surfaces are excluded whole.
          // The actual progress canvas has its own stroke-aware mask below.
          if (object is RenderBox && object.hasSize &&
              !identical(object, ringCanvas) && !containsParagraph(object) &&
              (object is RenderParagraph || object is RenderImage ||
               object is RenderCustomPaint || object is RenderDecoratedBox ||
               object is RenderPhysicalModel || object is RenderPhysicalShape)) {
            final rect = inImage(object).inflate(2);
            paintExclusions.add(rect);
            paintExclusionReports.add({
              'renderObject': object.runtimeType.toString(), 'rectWithMargin': _rect(rect),
            });
          }
          object.visitChildren(collectPaintExclusions);
        }
        box.visitChildren(collectPaintExclusions);
      } else {
        final decorations = find.ancestor(of: text, matching: find.byType(DecoratedBox));
        expect(decorations, findsWidgets);
        fillRect = inImage(tester.renderObject<RenderBox>(decorations.first));
        paintedSurface = 'feedback or streak DecoratedBox';
      }
      final painter = TextPainter(
        text: paragraph.text, textDirection: paragraph.textDirection,
        textAlign: paragraph.textAlign, textScaler: paragraph.textScaler,
        maxLines: paragraph.maxLines,
        ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null,
        strutStyle: paragraph.strutStyle, textWidthBasis: paragraph.textWidthBasis,
      )..layout(maxWidth: paragraph.size.width);
      final exceeded = painter.didExceedMaxLines;
      painter.dispose();
      final samples = <Map<String, Object?>>[];
      final samplePoints = <Offset>[];
      if (isSummaryPercent) {
        final ring = ringRect!;
        final radius = innerRadius!;
        // Keep all candidates within 8 root pixels of the actual paragraph.
        // An old centered label can use LOCAL inner-ring blank paint; when
        // the label moves beside/below the ring, exclude the entire canvas.
        const maxDistance = 8.0;
        double distanceToText(Offset point) {
          final dx = math.max(math.max(textRect.left - point.dx, 0.0), point.dx - textRect.right);
          final dy = math.max(math.max(textRect.top - point.dy, 0.0), point.dy - textRect.bottom);
          return math.sqrt(dx * dx + dy * dy);
        }
        final allowInnerRing = ring.contains(textRect.topLeft) &&
            ring.contains(textRect.bottomRight - const Offset(.01, .01));
        final search = textRect.inflate(maxDistance).intersect(fillRect).intersect(viewport);
        final candidates = <Offset>[];
        for (var y = search.top.ceil(); y < search.bottom.floor(); y++) {
          for (var x = search.left.ceil(); x < search.right.floor(); x++) {
            final point = Offset(x + .5, y + .5);
            if (distanceToText(point) > maxDistance ||
                textRect.inflate(1).contains(point) ||
                !surfaceSafeFill!.contains(surfaceLocalPoint!(point)) ||
                paintExclusions.any((rect) => rect.contains(point))) {
              continue;
            }
            if (ringPaintExclusion!.contains(point) &&
                (!allowInnerRing || (point - ring.center).distance > radius)) {
              continue;
            }
            candidates.add(point);
          }
        }
        expect(candidates.length, greaterThanOrEqualTo(3),
          reason: '100% needs three blank pixels within 8px of its actual paragraph on its actual fill.');
        // Pick nearest points to three paragraph-edge anchors, using ONLY
        // geometry before reading RGBA. Require separation to avoid repeats.
        final anchors = [
          Offset(textRect.left + textRect.width * .25, textRect.top - 2),
          Offset(textRect.left + textRect.width * .75, textRect.bottom + 2),
          Offset(textRect.left - 2, textRect.center.dy),
        ];
        for (final anchor in anchors) {
          final eligible = candidates.where((point) => samplePoints.every(
            (chosen) => (chosen - point).distance >= 2)).toList();
          expect(eligible, isNotEmpty,
            reason: '100% local background samples must be geometrically distinct.');
          final selected = eligible.reduce((a, b) =>
            (a - anchor).distance <= (b - anchor).distance ? a : b);
          samplePoints.add(selected);
        }
      } else {
        final y = ((fillRect.top + textRect.top) / 2).floor();
        for (final fraction in [.35, .5, .65]) {
          final x = (textRect.left + textRect.width * fraction).floor();
          samplePoints.add(Offset(x + .5, y + .5));
        }
      }
      for (final point in samplePoints) {
        final x = point.dx.floor();
        final y = point.dy.floor();
        expect(x, inInclusiveRange(0, raster.width - 1));
        expect(y, inInclusiveRange(0, raster.height - 1));
        expect(fillRect.contains(point), isTrue);
        expect(textRect.contains(point), isFalse);
        final data = raster.rgba;
        final offset = (y * raster.width + x) * 4;
        final background = Color.fromARGB(
          data.getUint8(offset + 3), data.getUint8(offset),
          data.getUint8(offset + 1), data.getUint8(offset + 2),
        );
        expect(background.a, 1);
        samples.add({
          'x': x, 'y': y, 'backgroundArgb': background.toARGB32(),
          if (isSummaryPercent) 'distanceToParagraph': math.sqrt(
            math.pow(math.max(math.max(textRect.left - point.dx, 0.0), point.dx - textRect.right), 2) +
            math.pow(math.max(math.max(textRect.top - point.dy, 0.0), point.dy - textRect.bottom), 2)),
          'ratio': appContrastRatio(Color.alphaBlend(foreground!, background), background),
        });
      }
      probes.add({
        'text': paragraph.text.toPlainText(), 'rect': _rect(textRect),
        'statusRect': _rect(statusRect), 'fillRect': _rect(fillRect),
        'paintedSurface': paintedSurface,
        if (ringRect != null) 'ringCanvasRect': _rect(ringRect),
        'ringSafeInnerRadius': ?innerRadius,
        if (ringPaintExclusion != null) 'ringPaintExclusionRect': _rect(ringPaintExclusion),
        'ringParagraphGeometry': ?ringParagraphGeometry,
        'sampleSelection': isSummaryPercent
            ? 'geometry-only paragraph-edge anchors; blank actual fill within 8px; paragraph/stroke/neighbor masks'
            : 'blank top padding fractions',
        if (isSummaryPercent) 'sampleMaxDistanceToParagraph': 8,
        if (isSummaryPercent) 'surfaceSafeFillLocal': {
          'rect': _rect(surfaceSafeFill!.outerRect),
          'radii': [surfaceSafeFill.tlRadiusX, surfaceSafeFill.tlRadiusY,
            surfaceSafeFill.trRadiusX, surfaceSafeFill.trRadiusY,
            surfaceSafeFill.brRadiusX, surfaceSafeFill.brRadiusY,
            surfaceSafeFill.blRadiusX, surfaceSafeFill.blRadiusY],
        },
        if (isSummaryPercent) 'paintExclusions': paintExclusionReports,
        if (isSummaryPercent) 'ringInteriorEligible': ringRect!.contains(textRect.topLeft) &&
            ringRect.contains(textRect.bottomRight - const Offset(.01, .01)),
        'didExceedMaxLines': exceeded,
        'scaled10px': paragraph.textScaler.scale(10),
        'transformScaleX': xScale, 'transformScaleY': yScale,
        'foregroundArgb': foreground!.toARGB32(),
        'fontWeight': (paragraph.text.style?.fontWeight ?? FontWeight.normal).value,
        'samples': samples,
      });
    }
  }
  final report = <String, Object?>{
    'schema': 'duoyi.habit-priority.capture.v272',
    'name': name, 'state': state, 'viewport': [raster.width, raster.height],
    'textScale': 2, 'capturePixelRatio': 1,
    'scopeRect': _rect(scopeRect), 'paragraphs': probes,
    'baselineRenderFlexDiagnostics': overflows.snapshot(),
    'renderFlexOverflowsAtCapture': _renderFlexOverflows(tester, boundary),
    'baselineReadabilityAccepted': false,
  };
  final directory = Platform.environment['DUOYI_HABIT_PRIORITY_SCREENSHOTS'];
  if (directory != null && directory.isNotEmpty) {
    await tester.runAsync(() async {
      final file = File('$directory/$name.json');
      if (file.existsSync()) throw StateError('Refusing to overwrite $file');
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    });
  }
  _stage('capture $name done');
  return report;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Habit root completed flex recorded streak and 100 percent capture', (tester) async {
    final initialLocale = I18n.current;
    addTearDown(() => I18n.setLocale(initialLocale));
    SharedPreferences.setMockInitialValues({
      'active_brand': 'defaultBrand',
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    });
    I18n.setLocale(AppLocale.zh);
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late TimeAuditProvider audit;
    late HabitProvider habits;
    late ThemeProvider theme;
    late AuthProvider auth;
    final scheduler = RecordingReminderScheduler();
    // Same real root/providers/fonts as mountHabitCreateFixture. Construct
    // queue-owning providers in the real zone before awaiting their queues.
    await _hostStage(tester, 'providers and storage', () async {
      audit = TimeAuditProvider();
      habits = HabitProvider()
        ..timeAudit = audit
        ..scheduler = scheduler;
      theme = ThemeProvider();
      auth = AuthProvider();
      addTearDown(() {
        habits.dispose();
        audit.dispose();
        theme.dispose();
        auth.dispose();
      });
      await theme.loadFromStorage();
      await habits.loadFromStorage();
      await audit.loadFromStorage();
    });
    addTearDown(() async {
      _stage('teardown unmount start');
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      _stage('teardown unmount done');
    });
    await _hostStage(tester, 'fonts', loadWeeklyReviewScreenshotFonts);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final overflows = _BaselineOverflows(() => theme);
    addTearDown(overflows.restore);
    final boundary = GlobalKey();
    _stage('root mount start');
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<HabitProvider>.value(value: habits),
        ChangeNotifierProvider<TimeAuditProvider>.value(value: audit),
      ],
      child: AnimatedBuilder(
        animation: Listenable.merge([theme, I18n.localeListenable]),
        builder: (context, _) => MaterialApp(
          locale: I18n.current.flutterLocale,
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: theme.brand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
            child: RepaintBoundary(key: boundary, child: child!),
          ),
          home: const BrandBackground(child: HabitScreen()),
        ),
      ),
    ));
    await _settle(tester);
    _stage('root mount done');
    final retainedScreen = tester.state(find.byType(HabitScreen));
    final retainedRoute = ModalRoute.of(tester.element(find.byType(HabitScreen)));
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final daily = Habit(
      id: 'priority-daily-220', name: 'Daily fixture', targetCount: 1,
      currentStreak: 7, bestStreak: 7, startDate: day.subtract(const Duration(days: 14)),
    );
    for (var i = 1; i < 7; i++) {
      daily.completions[daily.dateKey(day.subtract(Duration(days: i)))] = 1;
    }
    final flex = Habit(
      id: 'priority-flex-220', name: 'Flex fixture', targetCount: 1,
      flexPeriod: HabitFlexPeriod.week, flexTarget: 1,
      currentStreak: 3, bestStreak: 3, startDate: day.subtract(const Duration(days: 28)),
    );
    var previousWeek = flex.previousPeriodBounds(flex.periodBoundsForDate(day));
    for (var i = 0; i < 2; i++) {
      flex.completions[flex.dateKey(previousWeek.start)] = 1;
      previousWeek = flex.previousPeriodBounds(previousWeek);
    }
    final negative = Habit(
      id: 'priority-negative-220', name: 'Avoid fixture', kind: HabitKind.negative,
      startDate: day.subtract(const Duration(days: 14)),
    );

    await _hostStage(tester, 'seed habits', () async {
      await habits.addHabit(daily);
      await habits.addHabit(flex);
      await habits.addHabit(negative);
    });
    expect(scheduler.habitSyncs, hasLength(3));
    expect(scheduler.habitSyncs.last, [daily.id, flex.id, negative.id]);
    expect(habits.lastReminderSyncIssue, isNull);
    await _settle(tester);
    for (final habit in [daily, flex, negative]) {
      overflows.phase = 'check-in-${habit.id}';
      _stage('check in ${habit.id} reveal');
      await _reveal(tester, _card(habit.id));
      final button = find.descendant(of: _card(habit.id), matching: find.byType(FilledButton));
      expect(button, findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await _hostStage(tester, 'check in ${habit.id}', () async {
        await tester.tap(button);
        await AccountPreferenceWrites.drain();
        await Future<void>.delayed(Duration.zero);
      });
      await _settle(tester);
      expect(habits.habits.singleWhere((item) => item.id == habit.id).todayCount(), 1);
      // The real check-in feedback stays visible for its normal duration; let
      // it close so badge captures contain the root rather than a SnackBar.
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(tester.state(find.byType(HabitScreen)), same(retainedScreen));
      expect(ModalRoute.of(tester.element(find.byType(HabitScreen))), same(retainedRoute));
    }
    expect(habits.habits.singleWhere((item) => item.id == daily.id).currentStreak, 7);
    expect(habits.habits.singleWhere((item) => item.id == flex.id).currentStreak, 3);
    final screen = tester.state(find.byType(HabitScreen));
    final route = ModalRoute.of(tester.element(find.byType(HabitScreen)));
    final reports = <Map<String, Object?>>[];
    Habit current(String id) => habits.habits.singleWhere((habit) => habit.id == id);
    Future<void> change(String brand, AppLocale locale) async {
      await _hostStage(tester, 'theme $brand', () async {
        expect(await theme.setBrand(brand), isTrue);
      });
      I18n.setLocale(locale);
      await _settle(tester);
      expect(theme.brand.id, brand);
      expect(Theme.of(tester.element(find.byType(HabitScreen))).colorScheme,
        theme.brand.theme.colorScheme);
      expect(tester.state(find.byType(HabitScreen)), same(screen));
      expect(ModalRoute.of(tester.element(find.byType(HabitScreen))), same(route));
      expect(tester.takeException(), isNull);
    }
    try {
      for (final phase in ['badges', 'summary100']) {
        overflows.phase = phase;
        overflows.capture = null;
        if (phase == 'summary100') {
          await _hostStage(tester, 'negative undo for 100 percent',
            () => habits.decrementHabitForDate(negative.id, day));
          await _settle(tester);
          expect(current(negative.id).todayCount(), 0);
          expect(habits.todayOverallProgress, 1);
        } else {
          expect(current(negative.id).todayCount(), 1);
          expect(habits.todayOverallProgress, closeTo(2 / 3, .00001));
        }
        final frozen = jsonEncode(habits.habits.map((habit) => habit.toJson()).toList());
        var index = 0;
        for (final state in <(String, AppLocale)>[
          ('defaultBrand', AppLocale.zh), ('liquidGlass', AppLocale.zh),
          ('liquidGlass', AppLocale.en), ('defaultBrand', AppLocale.en),
          ('defaultBrand', AppLocale.zh),
        ]) {
          overflows.phase = '$phase-${state.$1}-${state.$2.name}';
          overflows.capture = null;
          _stage('$phase ${state.$1} ${state.$2.name} start');
          await change(state.$1, state.$2);
          expect(jsonEncode(habits.habits.map((habit) => habit.toJson()).toList()), frozen);
          expect(current(daily.id).isCompletedToday(), isTrue);
          expect(current(flex.id).flexProgressForDate(day)!.isCompleted, isTrue);
          final details = <String, Object?>{
            'phase': phase, 'brand': theme.brand.id,
            'locale': I18n.current.storageValue, 'day': daily.dateKey(day),
            'overallProgress': habits.todayOverallProgress,
            'habits': habits.habits.map((habit) => habit.toJson()).toList(),
          };
          final stem = '$phase-${index++}-${state.$1}-${state.$2.storageValue}-320x844-scale200';
          if (phase == 'badges') {
            for (final habit in [daily, flex, negative]) {
              await _reveal(tester, _card(habit.id));
              final feedback = _feedback(habit.id, habit.kind == HabitKind.negative
                  ? 'habit-warning-feedback' : 'habit-completed-feedback');
              final english = state.$2 == AppLocale.en;
              final label = habit.kind == HabitKind.negative
                  ? (english ? 'Recorded' : '已记录')
                  : habit.hasFlexRule
                  ? (english
                      ? '${current(habit.id).flexProgressForDate(day)!.labelPrefix} reached'
                      : '${current(habit.id).flexProgressForDate(day)!.labelPrefix}达标')
                  : (english ? 'Completed' : '已达标');
              expect(find.descendant(of: feedback, matching: find.text(label)), findsOneWidget);
              reports.add(await _capture(tester, boundary, _card(habit.id),
                [feedback, if (habit.currentStreak > 0) _streak(habit.id)],
                '$stem-${habit.id}', details, overflows));
            }
          } else {
            final summary = _kind('_HabitTodaySummaryCard');
            await _reveal(tester, summary);
            final percent = find.descendant(of: summary, matching: find.text('100%'));
            expect(percent, findsOneWidget);
            reports.add(await _capture(tester, boundary, summary, [percent], '$stem-ring', details, overflows));
          }
          expect(tester.takeException(), isNull);
        }
      }
      overflows.restore();
      expect(reports, hasLength(20));
      _stage('matrix complete: ${reports.length} captures, ${overflows.records.length} bounded overflow events');
      expect(tester.takeException(), isNull);
      if (Platform.environment['DUOYI_HABIT_PRIORITY_REQUIRE_READABLE'] == '1') {
        expect(overflows.records, isEmpty,
          reason: 'Strict mode rejects every baseline RenderFlex exception after the complete matrix.');
        for (final report in reports) {
          expect(report['renderFlexOverflowsAtCapture'], isEmpty,
            reason: '${report['name']}: current RenderFlex geometry overflows');
        }
        for (final report in reports) {
          for (final probe in report['paragraphs']! as List<Map<String, Object?>>) {
            final reason = '${report['name']}: ${probe['text']}';
            expect(probe['didExceedMaxLines'], isFalse, reason: reason);
            expect(probe['scaled10px'], 20, reason: reason);
            expect(probe['transformScaleX'], closeTo(1, .001), reason: reason);
            expect(probe['transformScaleY'], closeTo(1, .001), reason: reason);
            expect(probe['fontWeight'], 400, reason: reason);
            if (probe['text'] == '100%') {
              final geometry = probe['ringParagraphGeometry']! as Map<String, Object?>;
              expect(geometry['placementAccepted'], isTrue,
                reason: '$reason: whole paragraph must fit the safe inner circle or clear the ring stroke: $geometry');
            }
            for (final sample in probe['samples']! as List<Map<String, Object?>>) {
              expect(sample['ratio']! as double, greaterThanOrEqualTo(4.5), reason: reason);
            }
          }
        }
      }
    } finally {
      overflows.restore();
      _stage('unmount start');
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      _stage('unmount done');
    }
  });
}
