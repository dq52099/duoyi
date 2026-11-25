import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:duoyi/widgets/surface_components.dart' show AppDialog;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

final _continuousBatches178 = <String, Directory>{};
final _continuousNames178 = <String>{};
const _overlap178 = 0.70;
const _epsilon178 = 0.0001;

/// Optional full-content evidence from the real, current backup dialog.
///
/// DUOYI_BACKUP_CONTINUOUS_DIR must name a nonsymlinked repo evidence directory.
/// The caller owns disk admission, the serial lock and the live resource guard;
/// this helper requires its inherited run marker and acquires no lock. Images
/// use pixelRatio 1. Each step advances 30% of the visible vertical viewport,
/// leaving 70% overlap. Nested scroll positions are swept in tree order, with
/// each child's complete sweep repeated at each visible parent offset.
///
/// Portrait chooser/result already have complete modal captures and are skipped.
/// Sidecars are sealed after finally restores every captured position. A manifest
/// binds both PNG and sidecar hashes, coverage and restoration; retain failures.
Future<void> captureBackupDialogContinuously(
  WidgetTester tester,
  GlobalKey captureKey,
  String caseName,
  String phase,
  Map<String, Object?> state,
) async {
  final supplied = Platform.environment['DUOYI_BACKUP_CONTINUOUS_DIR'];
  if (supplied == null || supplied.trim().isEmpty) return;
  final selected = Platform.environment['DUOYI_BACKUP_CONTINUOUS_ONLY'];
  if (selected != null && selected.isNotEmpty) {
    final names = selected.split(',');
    if (names.any(
      (name) => !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(name),
    )) {
      throw StateError('Invalid continuous capture state filter');
    }
    if (!names.contains('$caseName-$phase')) return;
  }
  final marker = Platform.environment['DUOYI_RESOURCE_GUARD_RUN_ID'];
  if (marker == null || marker.trim().isEmpty) {
    throw StateError('Continuous backup capture requires the resource guard');
  }
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(caseName) ||
      !const {
        'chooser-default',
        'chooser-glass',
        'mapping-default',
        'mapping-glass',
        'preview-default',
        'preview-glass',
        'result-default',
        'result-glass',
      }.contains(phase)) {
    throw StateError('Invalid continuous backup case/phase: $caseName/$phase');
  }
  final evidence = path.join(_repoRoot178(), 'evidence');
  final output = path.normalize(path.absolute(supplied));
  if (!path.isWithin(evidence, output)) {
    throw StateError(
      'Continuous output must be a named repo evidence directory',
    );
  }
  _directories178(output, allowMissing: true);
  await tester.pump();
  final context = captureKey.currentContext;
  final boundary = context?.findRenderObject();
  if (context == null ||
      boundary is! RenderRepaintBoundary ||
      !boundary.attached ||
      !boundary.hasSize) {
    throw StateError('Continuous capture requires the real viewport boundary');
  }
  final media = MediaQuery.of(context);
  if (media.size.height > media.size.width &&
      (phase.startsWith('chooser-') || phase.startsWith('result-'))) {
    return;
  }
  final name = '$caseName-$phase';
  if (!_continuousNames178.add('$output/$name')) {
    throw StateError('Duplicate continuous capture state: $name');
  }
  final frozenState = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
  final dialogs = find
      .descendant(of: find.byKey(captureKey), matching: find.byType(AppDialog))
      .evaluate()
      .where((element) {
        final route = ModalRoute.of(element);
        return route != null && route.isActive && route.isCurrent;
      })
      .toList();
  if (dialogs.length != 1) {
    throw StateError(
      'Require exactly one current AppDialog inside the boundary',
    );
  }
  final dialog = dialogs.single;
  final route = ModalRoute.of(dialog)!;
  final owner = find.byElementPredicate(
    (element) => identical(element, dialog),
  );
  final scrolls = <_ContinuousScroll178>[];
  for (final element
      in find
          .descendant(of: owner, matching: find.byType(Scrollable))
          .evaluate()) {
    if (element is StatefulElement && element.state is ScrollableState) {
      final scrollable = element.state as ScrollableState;
      if (axisDirectionToAxis(scrollable.widget.axisDirection) ==
          Axis.vertical) {
        scrolls.add(_ContinuousScroll178(scrolls.length, element, scrollable));
      }
    }
  }
  final batch = await tester.runAsync<Directory>(() async {
    _directories178(output, createMissing: true);
    final directory = _continuousBatches178.putIfAbsent(
      output,
      () => Directory(output).createTempSync('backup-continuous-178-'),
    );
    if (!path.isWithin(output, directory.path)) {
      throw StateError('Continuous batch escaped its admitted output');
    }
    _directories178(directory.path);
    return directory;
  });
  if (batch == null) {
    throw StateError('Continuous batch creation did not finish');
  }
  final frames = <Map<String, Object?>>[];
  final seenFrames = <String>{};
  final restoration = <Map<String, Object?>>[];
  final restorationErrors = <String>[];
  final publicationErrors = <String>[];
  final flutterErrors = <String>[];
  Object? failure;
  StackTrace? failureStack;
  var covered = false;

  void checkTarget() {
    Object? error;
    while ((error = tester.takeException()) != null) {
      flutterErrors.add(error.toString());
    }
    if (flutterErrors.isNotEmpty) {
      throw StateError(
        'Continuous capture observed Flutter errors: $flutterErrors',
      );
    }
    if (!dialog.mounted ||
        !route.isActive ||
        !route.isCurrent ||
        !identical(ModalRoute.of(dialog), route) ||
        !boundary.attached ||
        !identical(captureKey.currentContext?.findRenderObject(), boundary)) {
      throw StateError('Continuous capture dialog/boundary identity changed');
    }
    for (final scroll in scrolls) {
      scroll.check();
    }
  }

  Future<void> takePage() async {
    checkTarget();
    final offsets = scrolls.map((scroll) => scroll.position.pixels).toList();
    if (!seenFrames.add(jsonEncode(offsets))) return;
    final positions = <Map<String, Object?>>[];
    for (final scroll in scrolls) {
      final visible = _visible178(scroll.element, dialog, boundary);
      positions.add({
        ...scroll.snapshot(),
        'visibleRect': _rectData178(visible),
        'visibleContentInterval': scroll.contentInterval(visible),
      });
    }
    final index = frames.length;
    final file = File(
      path.join(batch.path, '$name-${index.toString().padLeft(4, '0')}.png'),
    );
    final record = <String, Object?>{
      'index': index,
      'png': file.path,
      'pngWritten': false,
      'scrollables': positions,
    };
    frames.add(record);
    final written = await tester.runAsync<bool>(() async {
      final picture = await boundary.toImage(pixelRatio: 1);
      try {
        if (picture.width != boundary.size.width.ceil() ||
            picture.height != boundary.size.height.ceil()) {
          throw StateError('Continuous PNG is not the real 1:1 boundary');
        }
        final data = await picture.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw StateError('Continuous PNG encoding returned null');
        }
        checkTarget();
        for (var i = 0; i < scrolls.length; i++) {
          if ((scrolls[i].position.pixels - offsets[i]).abs() > _epsilon178) {
            throw StateError(
              'Continuous scroll offset changed during rendering',
            );
          }
        }
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        record.addAll({
          'expectedPngSha256': sha256.convert(bytes).toString(),
          'pngSize': [picture.width, picture.height],
        });
        await _newBytes178(file, bytes, batch);
        record['pngWritten'] = true;
      } finally {
        picture.dispose();
      }
      return true;
    });
    if (written != true) {
      throw StateError('Continuous PNG capture did not finish: ${file.path}');
    }
    checkTarget();
    for (var i = 0; i < scrolls.length; i++) {
      final interval = positions[i]['visibleContentInterval'] as List<double>?;
      if (interval != null) {
        scrolls[i].visited.add(offsets[i]);
        scrolls[i].samples.add({
          'frameIndex': index,
          'start': interval[0],
          'end': interval[1],
          'ancestorAndOwnOffsets': offsets,
        });
      }
    }
  }

  Future<void> sweep(int level) async {
    checkTarget();
    if (level == scrolls.length) {
      await takePage();
      return;
    }
    final scroll = scrolls[level];
    final reversed = scroll.direction == AxisDirection.up;
    final start = reversed ? scroll.max : scroll.min;
    final end = reversed ? scroll.min : scroll.max;
    var offset = start;
    while (true) {
      scroll.position.jumpTo(offset);
      await tester.pump();
      checkTarget();
      await sweep(level + 1);
      if ((offset - end).abs() <= _epsilon178) break;
      final visible = _visible178(scroll.element, dialog, boundary);
      // A nested viewport outside its parent's current view will be swept when
      // the parent exposes it. Do not invent coverage for hidden child offsets.
      if (visible.isEmpty || visible.height < 1) break;
      final viewport = math.min(scroll.viewport, visible.height);
      final step = viewport * (1 - _overlap178);
      final distance = math.min(step, (end - offset).abs());
      final next = offset + (reversed ? -distance : distance);
      if (!next.isFinite || next == offset) {
        throw StateError('Continuous scroll sweep cannot advance');
      }
      offset = (next - end).abs() <= _epsilon178 ? end : next;
    }
  }

  try {
    await sweep(0);
    covered =
        frames.isNotEmpty &&
        scrolls.every((scroll) => scroll.coverage()['accepted'] == true);
    if (!covered) {
      throw StateError(
        'Continuous sweep has a content gap or insufficient overlap',
      );
    }
  } catch (error, stack) {
    failure = error;
    failureStack = stack;
  } finally {
    // Attempt every original position even if another restore/pump fails.
    for (final scroll in scrolls.reversed) {
      try {
        scroll.check();
        scroll.position.jumpTo(scroll.original);
        await tester.pump();
        checkTarget();
      } catch (error) {
        restorationErrors.add('scroll ${scroll.index}: $error');
      }
    }
    try {
      await tester.pump();
      checkTarget();
    } catch (error) {
      restorationErrors.add('final restoration frame: $error');
    }
    for (final scroll in scrolls) {
      final restored = <String, Object?>{
        'index': scroll.index,
        'scrollableElementIdentity': identityHashCode(scroll.element),
        'scrollableStateIdentity': identityHashCode(scroll.scrollable),
        'positionIdentity': identityHashCode(scroll.position),
        'originalOffset': scroll.original,
        'restored': false,
      };
      try {
        scroll.check();
        restored['actualOffset'] = scroll.position.pixels;
        restored['restored'] =
            (scroll.position.pixels - scroll.original).abs() <= _epsilon178;
        if (restored['restored'] != true) {
          restorationErrors.add(
            'scroll ${scroll.index}: original offset not restored',
          );
        }
      } catch (error) {
        restored['error'] = error.toString();
        restorationErrors.add(
          'scroll ${scroll.index} identity/metrics: $error',
        );
      }
      restoration.add(restored);
    }
    try {
      final published = await tester.runAsync<bool>(() async {
        for (final frame in frames) {
          try {
            _directories178(batch.path);
            final png = File(frame['png'] as String);
            if (FileSystemEntity.typeSync(png.path, followLinks: false) !=
                FileSystemEntityType.file) {
              throw StateError(
                'Missing/nonregular continuous PNG: ${png.path}',
              );
            }
            final checksum = sha256.convert(await png.readAsBytes()).toString();
            frame['pngSha256'] = checksum;
            if (frame['pngWritten'] != true ||
                checksum != frame['expectedPngSha256']) {
              throw StateError(
                'Continuous PNG write/hash did not complete: ${png.path}',
              );
            }
            final sidecar = File(path.setExtension(png.path, '.json'));
            final bytes = utf8.encode(
              '${const JsonEncoder.withIndent('  ').convert({
                ...frozenState,
                'schema': 'duoyi.backup-continuous.frame.v178',
                'case': caseName,
                'phase': phase,
                'guardRunId': marker,
                'viewport': [media.size.width, media.size.height],
                'textScale': media.textScaler.scale(12) / 12,
                'capturePixelRatio': 1,
                'dialogElementIdentity': identityHashCode(dialog),
                'dialogRouteIdentity': identityHashCode(route),
                ...frame,
                'overlapFraction': _overlap178,
                'restoration': restoration,
                'restorationErrors': restorationErrors,
                'captureError': failure?.toString(),
                'flutterErrors': flutterErrors,
                'coversAllScrollExtents': covered,
                'coverage': [for (final scroll in scrolls) scroll.coverage()],
              })}\n',
            );
            await _newBytes178(sidecar, bytes, batch);
            frame['sidecar'] = sidecar.path;
            frame['sidecarSha256'] = sha256.convert(bytes).toString();
          } catch (error) {
            publicationErrors.add('frame ${frame['index']}: $error');
          }
        }
        final manifest = utf8.encode(
          '${const JsonEncoder.withIndent('  ').convert({
            'schema': 'duoyi.backup-continuous.manifest.v178',
            'case': caseName,
            'phase': phase,
            'guardRunId': marker,
            'state': frozenState,
            'capturePixelRatio': 1,
            'overlapFraction': _overlap178,
            'offsetStepFraction': 1 - _overlap178,
            'dialogElementIdentity': identityHashCode(dialog),
            'dialogRouteIdentity': identityHashCode(route),
            'scrollables': [for (final scroll in scrolls) scroll.plan()],
            'frames': frames,
            'actualCount': frames.length,
            'coversAllScrollExtents': covered,
            'restoration': restoration,
            'restorationErrors': restorationErrors,
            'captureError': failure?.toString(),
            'flutterErrors': flutterErrors,
            'publicationErrors': publicationErrors,
            'accepted': covered && failure == null && flutterErrors.isEmpty && restorationErrors.isEmpty && publicationErrors.isEmpty,
          })}\n',
        );
        await _newBytes178(
          File(path.join(batch.path, '$name-manifest.json')),
          manifest,
          batch,
        );
        return true;
      });
      if (published != true) {
        throw StateError('Continuous manifest publication did not finish');
      }
    } catch (error) {
      publicationErrors.add('manifest publication: $error');
    }
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  if (restorationErrors.isNotEmpty || publicationErrors.isNotEmpty) {
    throw StateError(
      'Continuous capture failed: ${[...restorationErrors, ...publicationErrors].join('; ')}',
    );
  }
}

class _ContinuousScroll178 {
  _ContinuousScroll178(this.index, this.element, this.scrollable)
    : position = scrollable.position,
      direction = scrollable.widget.axisDirection {
    if (!position.hasPixels ||
        !position.hasContentDimensions ||
        !position.hasViewportDimension) {
      throw StateError('Continuous scroll $index has no laid-out metrics');
    }
    original = position.pixels;
    min = position.minScrollExtent;
    max = position.maxScrollExtent;
    viewport = position.viewportDimension;
    if (![original, min, max, viewport].every((value) => value.isFinite) ||
        viewport <= 0 ||
        max < min ||
        original < min - _epsilon178 ||
        original > max + _epsilon178) {
      throw StateError('Continuous scroll $index has invalid/unstable metrics');
    }
  }
  final int index;
  final StatefulElement element;
  final ScrollableState scrollable;
  final ScrollPosition position;
  final AxisDirection direction;
  late final double original;
  late final double min;
  late final double max;
  late final double viewport;
  final visited = <double>{};
  final samples = <Map<String, Object?>>[];

  List<double>? contentInterval(Rect visible) {
    if (visible.isEmpty || visible.height < 1) return null;
    final box = element.findRenderObject()! as RenderBox;
    final local = Rect.fromPoints(
      box.globalToLocal(visible.topLeft),
      box.globalToLocal(visible.bottomRight),
    ).intersect(Offset.zero & box.size);
    if (local.isEmpty || local.height < 1) return null;
    if ((box.size.height - viewport).abs() > _epsilon178 ||
        local.left > _epsilon178 ||
        local.right < box.size.width - _epsilon178) {
      throw StateError(
        'Continuous scroll $index cannot prove full-width viewport coverage',
      );
    }
    return direction == AxisDirection.up
        ? [
            position.pixels + viewport - local.bottom,
            position.pixels + viewport - local.top,
          ]
        : [position.pixels + local.top, position.pixels + local.bottom];
  }

  Map<String, Object?> coverage() {
    final ordered = List<Map<String, Object?>>.of(samples)
      ..sort((a, b) {
        final first = (a['start'] as double).compareTo(b['start'] as double);
        return first != 0
            ? first
            : (a['end'] as double).compareTo(b['end'] as double);
      });
    final targetEnd = max + viewport;
    final gaps = <List<double>>[];
    final chain = <Map<String, Object?>>[];
    var end = min;
    Map<String, Object?>? previous;
    var minimumOverlap = 1.0;
    for (final sample in ordered) {
      final start = sample['start'] as double;
      final nextEnd = sample['end'] as double;
      if (nextEnd <= end + _epsilon178) continue;
      if (start > end + _epsilon178) gaps.add([end, start]);
      if (previous != null) {
        final previousStart = previous['start'] as double;
        final previousEnd = previous['end'] as double;
        final intersection = math.max(
          0.0,
          math.min(previousEnd, nextEnd) - math.max(previousStart, start),
        );
        final denominator = math.min(
          previousEnd - previousStart,
          nextEnd - start,
        );
        final overlap = intersection / denominator;
        minimumOverlap = math.min(minimumOverlap, overlap);
        chain.add({...sample, 'observedOverlapFraction': overlap});
      } else {
        chain.add({...sample, 'observedOverlapFraction': null});
      }
      previous = sample;
      end = nextEnd;
    }
    if (end < targetEnd - _epsilon178) gaps.add([end, targetEnd]);
    return {
      'index': index,
      'targetContentInterval': [min, targetEnd],
      'samples': samples,
      'coverageChain': chain,
      'gaps': gaps,
      'minimumObservedOverlapFraction': minimumOverlap,
      'requiredOverlapFraction': _overlap178,
      'accepted':
          samples.isNotEmpty &&
          gaps.isEmpty &&
          minimumOverlap + _epsilon178 >= _overlap178,
    };
  }

  void check() {
    if (!element.mounted ||
        !scrollable.mounted ||
        !identical(element.state, scrollable) ||
        !identical(scrollable.position, position) ||
        scrollable.widget.axisDirection != direction ||
        !position.hasPixels ||
        !position.hasContentDimensions ||
        !position.hasViewportDimension ||
        ![
          position.pixels,
          position.minScrollExtent,
          position.maxScrollExtent,
          position.viewportDimension,
        ].every((value) => value.isFinite) ||
        (position.minScrollExtent - min).abs() > _epsilon178 ||
        (position.maxScrollExtent - max).abs() > _epsilon178 ||
        (position.viewportDimension - viewport).abs() > _epsilon178) {
      throw StateError('Continuous scroll $index identity/metrics changed');
    }
  }

  bool saw(double offset) =>
      visited.any((value) => (value - offset).abs() <= _epsilon178);
  Map<String, Object?> snapshot() => {
    'index': index,
    'scrollableElementIdentity': identityHashCode(element),
    'scrollableStateIdentity': identityHashCode(scrollable),
    'positionIdentity': identityHashCode(position),
    'axisDirection': direction.name,
    'originalOffset': original,
    'minScrollExtent': min,
    'maxScrollExtent': max,
    'viewportDimension': viewport,
    'offset': position.pixels,
  };
  Map<String, Object?> plan() => {
    ...snapshot(),
    'visibleCapturedOffsets': visited.toList(),
    'topCaptured': saw(direction == AxisDirection.up ? max : min),
    'endCaptured': saw(direction == AxisDirection.up ? min : max),
    'coverage': coverage(),
  };
}

Rect _visible178(
  Element element,
  Element dialog,
  RenderRepaintBoundary boundary,
) {
  var visible = _boxRect178(element)
      .intersect(boundary.localToGlobal(Offset.zero) & boundary.size)
      .intersect(_boxRect178(dialog));
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is Scrollable) {
      visible = visible.intersect(_boxRect178(ancestor));
    }
    return !identical(ancestor, dialog);
  });
  RenderObject child = element.findRenderObject()!;
  while (child.parent != null) {
    final parent = child.parent!;
    if ((parent is RenderOffstage && parent.offstage) ||
        (parent is RenderOpacity && parent.opacity == 0)) {
      return Rect.zero;
    }
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null) {
      visible = visible.intersect(
        MatrixUtils.transformRect(parent.getTransformTo(null), clip),
      );
    }
    if (identical(parent, boundary)) break;
    child = parent;
  }
  return visible;
}

Rect _boxRect178(Element element) {
  final object = element.findRenderObject();
  if (object is! RenderBox || !object.attached || !object.hasSize) {
    throw StateError('Continuous capture requires a mounted scroll/dialog box');
  }
  return object.localToGlobal(Offset.zero) & object.size;
}

Map<String, Object?> _rectData178(Rect rect) => {
  'left': rect.left,
  'top': rect.top,
  'right': rect.right,
  'bottom': rect.bottom,
  'empty': rect.isEmpty,
};

String _repoRoot178() {
  var directory = Directory.current.absolute;
  while (true) {
    if (FileSystemEntity.typeSync(
          path.join(directory.path, '.git'),
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      return path.normalize(directory.path);
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Cannot locate repo evidence root for continuous capture',
      );
    }
    directory = parent;
  }
}

void _directories178(
  String target, {
  bool createMissing = false,
  bool allowMissing = false,
}) {
  final absolute = path.normalize(path.absolute(target));
  var current = path.rootPrefix(absolute);
  for (final part in path.split(absolute).skip(1)) {
    current = path.join(current, part);
    var type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.notFound && createMissing) {
      Directory(current).createSync();
      type = FileSystemEntity.typeSync(current, followLinks: false);
    }
    if (type == FileSystemEntityType.notFound && allowMissing) continue;
    if (type != FileSystemEntityType.directory) {
      throw StateError(
        'Continuous capture refuses symlink/non-directory: $current',
      );
    }
  }
}

Future<void> _newBytes178(File file, List<int> bytes, Directory batch) async {
  _directories178(batch.path);
  if (!path.isWithin(batch.path, file.path)) {
    throw StateError('Continuous artifact escaped its owned batch');
  }
  await file.create(exclusive: true);
  _directories178(batch.path);
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError(
      'Continuous artifact changed after creation: ${file.path}',
    );
  }
  await file.writeAsBytes(bytes, flush: true);
}
