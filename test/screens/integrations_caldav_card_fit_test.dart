import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
// BEGIN NEW2298 imports
import 'package:crypto/crypto.dart';
import 'package:duoyi/widgets/surface_components.dart';
// END NEW2298 imports

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

enum _Copy { guidance, summary, conflicts, error }

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final layout in const [
      (name: 'ordinary', size: Size(390, 844), scaler: TextScaler.noScaling),
      (name: 'narrow', size: Size(320, 844), scaler: TextScaler.linear(1.6)),
      (name: 'landscape', size: Size(568, 320), scaler: TextScaler.linear(2)),
      (name: 'nonlinear', size: Size(332, 844), scaler: _CardScaler()),
    ]) {
      for (final copy in _Copy.values) {
        final name = '$brand-${layout.name}-${copy.name}';
        testWidgets('CalDAV card complete generated copy $name', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          final sync = _Sync(copy);
          final theme = ThemeProvider();
          final locale = LocaleProvider();
          final locations = LocationReminderProvider();
          final notifications = NotificationService();
          final capture = GlobalKey();
          final originalShadows = debugDisableShadows;
          final measurements = <Map<String, Object>>[];
          try {
            I18n.setLocale(AppLocale.zh);
            await theme.loadFromStorage();
            expect(theme.brand.id, brand);
            await tester.runAsync(loadWeeklyReviewScreenshotFonts);
            debugDisableShadows = false;
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<CalendarSyncProvider>.value(
                    value: sync,
                  ),
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<LocaleProvider>.value(value: locale),
                  ChangeNotifierProvider<LocationReminderProvider>.value(
                    value: locations,
                  ),
                  ChangeNotifierProvider<NotificationService>.value(
                    value: notifications,
                  ),
                ],
                child: MaterialApp(
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: layout.scaler),
                    child: RepaintBoundary(key: capture, child: child!),
                  ),
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const BrandRouteSurface(
                              child: IntegrationsScreen(),
                            ),
                          ),
                        ),
                        child: const Text('Open synthetic integrations'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open synthetic integrations'));
            await tester.pumpAndSettle();
            final retainedRoute = tester.element(
              find.byType(IntegrationsScreen),
            );
            expect(find.byType(BackButton), findsOneWidget);
            final prefs = await SharedPreferences.getInstance();
            final initialPrefs = {
              for (final key in prefs.getKeys()) key: prefs.get(key),
            };
            for (final step in const [
              (phase: 'initial-zh', locale: AppLocale.zh),
              (phase: 'switched-en', locale: AppLocale.en),
              (phase: 'restored-zh', locale: AppLocale.zh),
            ]) {
              final next = step.locale;
              final phase = step.phase;
              I18n.setLocale(next);
              await tester.pumpAndSettle();
              tester.state<ScrollableState>(_vertical()).position.jumpTo(0);
              await tester.pumpAndSettle();
              final message = _message(sync, copy);
              final text = find.text(message);
              if (copy == _Copy.error) {
                final expectedError = next == AppLocale.en
                    ? 'Calendar access denied. Check your authorization and permissions.'
                    : '日历访问被拒绝，请检查授权信息和权限';
                expect(
                  message,
                  expectedError,
                  reason: 'The CalDAV error fixture must supply complete safe copy.',
                );
              }
              await tester.scrollUntilVisible(
                text,
                100,
                maxScrolls: 40,
                scrollable: _vertical(),
              );
              await tester.ensureVisible(text);
              await tester.pumpAndSettle();
              if (copy == _Copy.error) {
                expect(
                  text,
                  findsOneWidget,
                  reason:
                      'The dedicated CalDAV error must be mounted exactly once after revealing.',
                );
              }
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: text, matching: find.byType(RichText)),
              );
              final fontSize = paragraph.text.style!.fontSize!;
              final painter = TextPainter(
                text: paragraph.text,
                textDirection: paragraph.textDirection,
                textScaler: paragraph.textScaler,
              )..layout(maxWidth: paragraph.size.width);
              final complete =
                  !paragraph.didExceedMaxLines &&
                  painter.height <= paragraph.size.height + .1 &&
                  painter.width <= paragraph.size.width + .1;
              measurements.add({
                'phase': phase,
                'locale': next.name,
                'copy': copy.name,
                'availableWidth': paragraph.size.width,
                'renderedHeight': paragraph.size.height,
                'naturalHeight': painter.height,
                'maxLines': paragraph.maxLines ?? -1,
                'didExceedMaxLines': paragraph.didExceedMaxLines,
                'fontSize': fontSize,
                'scaledFontSize': paragraph.textScaler.scale(fontSize),
                'complete': complete,
              });
              expect(
                fontSize,
                copy == _Copy.conflicts || copy == _Copy.error ? 11 : 12,
              );
              expect(
                paragraph.textScaler.scale(fontSize),
                closeTo(layout.scaler.scale(fontSize), .01),
              );
              painter.dispose();
              expect(
                tester.element(find.byType(IntegrationsScreen)),
                same(retainedRoute),
              );
              expect(sync.calls, 0);
              expect({
                for (final key in prefs.getKeys()) key: prefs.get(key),
              }, initialPrefs);
              if (Platform.environment['DUOYI_CAPTURE_CALDAV_CARD'] == '1') {
                await tester.runAsync(() async {
                  final boundary =
                      capture.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary;
                  final picture = await boundary.toImage();
                  try {
                    final bytes = await picture.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    final run =
                        Platform.environment['DUOYI_CALDAV_CARD_RUN'] ??
                        'current';
                    final file = File(
                      'evidence/screenshots/caldav-card-fit-20261020/$run/$name-$phase-${next.name}.png',
                    );
                    if (FileSystemEntity.typeSync(
                          file.path,
                          followLinks: false,
                        ) !=
                        FileSystemEntityType.notFound) {
                      throw StateError(
                        'Refusing to overwrite CalDAV screenshot: ${file.path}',
                      );
                    }
                    await file.parent.create(recursive: true);
                    await file.writeAsBytes(bytes!.buffer.asUint8List());
                  } finally {
                    picture.dispose();
                  }
                });
              }
              // BEGIN NEW2298 two original CalDAV bodies hook
              await _captureCalDavEndpoints2298(
                tester, capture, name, phase, sync, copy, text, prefs,
              );
              // END NEW2298 two original CalDAV bodies hook
              expect(tester.takeException(), isNull);
            }
            expect(
              measurements.every((row) => row['complete'] == true),
              isTrue,
              reason:
                  'All natural text must be visible at its actual inherited font/scaler. $measurements',
            );
            final action = find.widgetWithText(
              OutlinedButton,
              copy == _Copy.guidance
                  ? NotificationUiCopy.calDavConfigure
                  : NotificationUiCopy.calDavEdit,
            );
            tester.state<ScrollableState>(_vertical()).position.jumpTo(0);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              action,
              100,
              maxScrolls: 40,
              scrollable: _vertical(),
            );
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(action.hitTestable(), findsOneWidget);
            await tester.tap(action);
            await tester.pumpAndSettle();
            final field = find.widgetWithText(
              TextField,
              NotificationUiCopy.collectionUrlLabel,
            );
            final controller = tester.widget<TextField>(field).controller!;
            expect(controller.text, sync.writeTarget?.collectionUrl ?? '');
            await tester.enterText(
              field,
              'https://draft.example.test/calendar/',
            );
            I18n.setLocale(AppLocale.en);
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<TextField>(
                    find.widgetWithText(
                      TextField,
                      NotificationUiCopy.collectionUrlLabel,
                    ),
                  )
                  .controller,
              same(controller),
            );
            expect(controller.text, 'https://draft.example.test/calendar/');
            final cancel = find.widgetWithText(
              TextButton,
              I18n.tr('action.cancel'),
            );
            await tester.ensureVisible(cancel);
            await tester.pumpAndSettle();
            await tester.tap(cancel);
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsNothing);
            expect(sync.calls, 0);
            expect(
              tester.element(find.byType(IntegrationsScreen)),
              same(retainedRoute),
            );
            expect({
              for (final key in prefs.getKeys()) key: prefs.get(key),
            }, initialPrefs);
            expect(tester.takeException(), isNull);
          } finally {
            try {
              final run = Platform.environment['DUOYI_CALDAV_CARD_RUN'];
              if (run != null) {
                await tester.runAsync(() async {
                  final file = File(
                    'evidence/caldav-card-fit-20261020/$run/$name.json',
                  );
                  if (FileSystemEntity.typeSync(
                        file.path,
                        followLinks: false,
                      ) !=
                      FileSystemEntityType.notFound) {
                    throw StateError(
                      'Refusing to overwrite CalDAV measurements: ${file.path}',
                    );
                  }
                  await file.parent.create(recursive: true);
                  await file.writeAsString(jsonEncode(measurements));
                });
              }
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              sync.dispose();
              theme.dispose();
              locale.dispose();
              locations.dispose();
              notifications.dispose();
              tester.view.reset();
              debugDisableShadows = originalShadows;
              I18n.setLocale(AppLocale.zh);
            }
          }
        });
      }
    }
  }
}

Finder _vertical() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;
String _message(_Sync sync, _Copy copy) => switch (copy) {
  _Copy.guidance => NotificationUiCopy.calDavConfigPrompt,
  _Copy.summary =>
    '${NotificationUiCopy.calDavVerified} · ${NotificationUiCopy.isEn ? 'Keep remote changes' : '远端变更不覆盖'} · ${sync.writeTarget!.collectionUrl}',
  _Copy.conflicts => NotificationUiCopy.calDavConflictsSkipped(
    sync.lastCalDavConflicts.length,
  ),
  _Copy.error => NotificationUiCopy.formatCalDavError(sync.lastCalDavError!),
};

class _Sync extends CalendarSyncProvider {
  _Sync(this.copy);
  final _Copy copy;
  int calls = 0;
  @override
  CalDavWriteTarget? get writeTarget => copy == _Copy.guidance
      ? null
      : const CalDavWriteTarget(
          collectionUrl:
              'https://synthetic.example.test/calendars/a-long-public-collection-identifier/',
          authorizationHeader: 'Basic synthetic-not-real',
          enabled: true,
        );
  @override
  String? get lastCalDavError =>
      copy == _Copy.error ? '401 synthetic-private diagnostic' : null;
  @override
  List<CalDavWriteConflict> get lastCalDavConflicts => copy == _Copy.conflicts
      ? const [
          CalDavWriteConflict(
            uid: 'synthetic-id',
            title: 'Synthetic 用户标题',
            reason: 'synthetic conflict',
          ),
        ]
      : const [];
  @override
  Future<void> saveWriteTarget(CalDavWriteTarget target) async {
    calls++;
  }

  @override
  Future<void> clearWriteTarget() async {
    calls++;
  }

  @override
  Future<void> testWriteTarget({bool Function()? isCurrent}) async {
    calls++;
  }
}

class _CardScaler extends TextScaler {
  const _CardScaler();
  @override
  double scale(double fontSize) => fontSize * (fontSize < 14 ? 1.9 : 1.6);
  @override
  double get textScaleFactor => 1;
}

// BEGIN NEW2298 common evidence helpers
// Opt-in evidence is separate from the original capture writers. PNG+JSON
// precede added assertions. Visual review and parent guard closure stay external.
bool get _visualEndpointsEnabled =>
    Platform.environment['DUOYI_CAPTURE_VISUAL_ENDPOINTS'] == '1';

String _endpointId(Object? value) =>
    value == null ? 'null' : identityHashCode(value).toString();

Map<String, Object?> _endpointRect(Rect rect) => {
  'left': rect.left, 'top': rect.top, 'right': rect.right,
  'bottom': rect.bottom, 'width': rect.width, 'height': rect.height,
};
Rect _endpointBox(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;
bool _endpointContains(Rect outer, Rect inner) =>
    inner.width > 0 && inner.height > 0 &&
    inner.left >= outer.left - .1 && inner.right <= outer.right + .1 &&
    inner.top >= outer.top - .1 && inner.bottom <= outer.bottom + .1;

Map<String, Object?> _endpointScroll(ScrollableState state) => {
  'state': _endpointId(state), 'element': _endpointId(state.context),
  'position': _endpointId(state.position),
  'widgetController': _endpointId(state.widget.controller),
  'ambientPrimaryController': _endpointId(PrimaryScrollController.maybeOf(state.context)),
  'controllerBinding': state.widget.controller != null
      ? 'explicit Scrollable.widget.controller'
      : 'no explicit controller; bind public ScrollableState/ScrollPosition identities',
  'axisDirection': state.position.axisDirection.name,
  'pixels': state.position.pixels,
  'minScrollExtent': state.position.minScrollExtent,
  'maxScrollExtent': state.position.maxScrollExtent,
  'extentBefore': state.position.extentBefore,
  'extentAfter': state.position.extentAfter,
  'viewportDimension': state.position.viewportDimension,
};
Map<String, Object?> _endpointStableState(Map<String, Object?> state) {
  final result = Map<String, Object?>.from(state);
  for (final key in ['scroll', 'vertical', 'horizontal']) {
    final scroll = result[key];
    if (scroll is Map<String, Object?>) {
      result[key] = Map<String, Object?>.from(scroll)
        ..remove('pixels')..remove('extentBefore')..remove('extentAfter');
    }
  }
  return result;
}

Rect _endpointBodyViewport(WidgetTester tester, Finder screen, RenderObject child) {
  final viewport = RenderAbstractViewport.maybeOf(child);
  if (viewport is! RenderBox) throw StateError('Expected a box scroll viewport');
  var rect = _endpointBox(viewport as RenderBox).intersect(tester.getRect(screen));
  final bars = find.descendant(of: screen, matching: find.byType(AppBar));
  if (bars.evaluate().length != 1) throw StateError('Active AppBar is ambiguous');
  final bottom = tester.getRect(bars).bottom;
  return Rect.fromLTRB(rect.left, rect.top > bottom ? rect.top : bottom,
      rect.right, rect.bottom);
}

Map<String, Object?> _endpointParagraph(WidgetTester tester, Finder text) {
  final rich = find.descendant(of: text, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(rich);
  final style = paragraph.text.style;
  final fontSize = style?.fontSize ?? DefaultTextStyle.of(tester.element(text)).style.fontSize;
  final painter = TextPainter(
    text: paragraph.text, textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.size.width);
  try {
    return {
      'element': _endpointId(tester.element(text)),
      'renderObject': _endpointId(paragraph),
      'text': paragraph.text.toPlainText(),
      'rect': _endpointRect(_endpointBox(paragraph)),
      'fontFamily': style?.fontFamily,
      'fontFamilyFallback': style?.fontFamilyFallback,
      'fontWeight': style?.fontWeight?.value, 'fontStyle': style?.fontStyle?.name,
      'letterSpacing': style?.letterSpacing, 'lineHeight': style?.height,
      'textDirection': paragraph.textDirection.name,
      'fontSize': fontSize,
      'scaledFontSize': fontSize == null ? null : paragraph.textScaler.scale(fontSize),
      'scalerType': paragraph.textScaler.runtimeType.toString(),
      'maxLines': paragraph.maxLines, 'overflow': paragraph.overflow.name,
      'didExceedMaxLines': paragraph.didExceedMaxLines,
      'naturalWidth': painter.width, 'naturalHeight': painter.height,
      'complete': !paragraph.didExceedMaxLines &&
          paragraph.overflow != TextOverflow.ellipsis &&
          painter.width <= paragraph.size.width + .1 &&
          painter.height <= paragraph.size.height + .1,
    };
  } finally { painter.dispose(); }
}

Map<String, Object?> _endpointView(WidgetTester tester, BuildContext context) {
  final media = MediaQuery.of(context);
  final route = ModalRoute.of(context);
  return {
    'view': _endpointId(tester.view),
    'physicalWidth': tester.view.physicalSize.width,
    'physicalHeight': tester.view.physicalSize.height,
    'devicePixelRatio': tester.view.devicePixelRatio,
    'mediaWidth': media.size.width, 'mediaHeight': media.size.height,
    'padding': media.padding.toString(), 'viewInsets': media.viewInsets.toString(),
    'scalerType': media.textScaler.runtimeType.toString(),
    'scaledSamples': {for (final size in [11.0, 12.0, 14.0, 16.0])
      size.toString(): media.textScaler.scale(size)},
    'locale': I18n.current.name,
    'route': _endpointId(route), 'routeType': route.runtimeType.toString(),
    'routeCurrent': route?.isCurrent,
    'navigator': _endpointId(Navigator.of(context)),
    'screenElement': _endpointId(context),
    'themeProvider': _endpointId(context.read<ThemeProvider>()),
    'brand': context.read<ThemeProvider>().brand.id,
  };
}

List<Map<String, Object?>> _endpointInputs() {
  const latinHash = '690243adfefe0ce154b547db6205794bd30ac4277275179517a90994f4980648';
  const cjkHash = 'acb6440a713d880a13a21b468ba7cd43f5a2b2934972e51be791c880730777b8';
  final paths = <String, String?>{
    'test/screens/settings_locale_layout_test.dart': null,
    'test/screens/integrations_caldav_card_fit_test.dart': null,
    'lib/screens/preferences_screen.dart': '86a88c61ca9ca443c23f481b55bab24ff504bca9545639d0ecd549bf172e7213',
    'lib/screens/integrations_screen.dart': 'b816eba128425a50dec4d024afeb8a8f478b907d3403af3c7ca60be38faca09f',
    'test/support/widget_polish_screenshot_font.dart': 'db0e33e767d0cf88d6fb8f5eeb6391a88bed09ca2d630c913cf0a307a8c8d5ef',
    'test/support/weekly_review_screenshot_font.dart': '6300137dd8bd749f970d34430f3e2f8ae539d4ec2229040257c18c507cd9d1c0',
    'assets/fonts/DroidSansFallbackFull.ttf': cjkHash,
    'assets/fonts/DejaVuSans.ttf': latinHash,
    Platform.environment['DUOYI_WIDGET_SCREENSHOT_LATIN_FONT'] ??
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf': latinHash,
    'build/unit_test_assets/fonts/MaterialIcons-Regular.otf': 'd9865b671a09d683d13a863089d8825e0f61a37696ce5d7d448bc8023aa62453',
  };
  return [for (final entry in paths.entries) (() {
    final row = <String, Object?>{'requestedPath': entry.key, 'expectedSha256': entry.value};
    try {
      final file = File(entry.key);
      final before = file.statSync();
      final bytes = file.readAsBytesSync();
      final after = file.statSync();
      row.addAll({
        'resolvedPath': file.resolveSymbolicLinksSync(),
        'bytes': bytes.length.toString(), 'sha256': sha256.convert(bytes).toString(),
        'modifiedMicroseconds': after.modified.microsecondsSinceEpoch.toString(),
        'changedMicroseconds': after.changed.microsecondsSinceEpoch.toString(),
        'mode': after.mode.toString(),
        'stableRead': before.size == after.size && before.modified == after.modified &&
            before.changed == after.changed && before.mode == after.mode,
      });
    } catch (error) { row['error'] = error.toString(); }
    return row;
  })()];
}

// Preserve IO failures outside runAsync, whose binding otherwise reports them
// asynchronously and returns null. Each caller can retain diagnostic evidence.
Future<T> _endpointIO<T>(WidgetTester tester, Future<T> Function() operation) async {
  Object? failure;
  StackTrace? failureStack;
  final result = await tester.runAsync<T?>(() async {
    try { return await operation(); }
    catch (error, stack) { failure = error; failureStack = stack; return null; }
  });
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  if (result == null) throw StateError('Endpoint IO returned no result');
  return result;
}

class _EndpointEvidence {
  _EndpointEvidence(this.tester, this.key, this.name, this.metadata)
      : inputsBefore = _endpointInputs(),
        boundaryElementBefore = _endpointId(key.currentContext),
        boundaryRenderBefore = _endpointId(key.currentContext?.findRenderObject());
  final WidgetTester tester;
  final GlobalKey key;
  final String name;
  final Map<String, Object?> metadata;
  final List<Map<String, Object?>> inputsBefore;
  final String boundaryElementBefore;
  final String boundaryRenderBefore;
  final errors = <String>[];
  final checks = <String, bool>{};
  final frames = <Map<String, Object?>>[];
  final sidecars = <File>[];
  final sidecarHashes = <String>[];

  File _output(String phase, String extension) {
    final raw = Platform.environment['DUOYI_VISUAL_ENDPOINT_DIR'];
    const prefix = '/home/ubuntu/duoyi/evidence/screenshots/';
    if (raw == null || !raw.startsWith(prefix) || raw.length <= prefix.length ||
        Uri.directory(raw).normalizePath().toFilePath() != '$raw/') {
      throw StateError('DUOYI_VISUAL_ENDPOINT_DIR must name an absolute fresh batch under $prefix (no trailing slash)');
    }
    var ancestor = Directory(raw);
    while (ancestor.path != ancestor.parent.path) {
      if (FileSystemEntity.typeSync(ancestor.path, followLinks: false) == FileSystemEntityType.link) {
        throw StateError('Refusing a symlink output ancestor: ${ancestor.path}');
      }
      ancestor = ancestor.parent;
    }
    return File('$raw/$name-$phase.$extension');
  }

  Future<void> capture(String phase, Map<String, Object?> observed) async {
    final frame = <String, Object?>{'phase': phase, ...observed};
    final png = _output(phase, 'png');
    final json = _output(phase, 'json');
    for (final file in [png, json]) {
      if (FileSystemEntity.typeSync(file.path, followLinks: false) != FileSystemEntityType.notFound) {
        throw StateError('Refusing to overwrite endpoint evidence: ${file.path}');
      }
    }
    await _endpointIO(tester, () async {
      final stageBefore = _endpointInputs();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      checks['$phase-boundaryStable'] = _endpointId(key.currentContext) == boundaryElementBefore &&
          _endpointId(boundary) == boundaryRenderBefore;
      final picture = await boundary.toImage(pixelRatio: 1);
      try {
        final data = await picture.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('PNG encoding returned no bytes');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await png.parent.create(recursive: true);
        await png.writeAsBytes(bytes, flush: true);
        final stageAfter = _endpointInputs();
        checks['$phase-inputsStableDuringCapture'] = jsonEncode(stageBefore) == jsonEncode(stageAfter) &&
            jsonEncode(stageBefore) == jsonEncode(inputsBefore);
        frame.addAll({
          'inputsAtCaptureBefore': stageBefore, 'inputsAtCaptureAfter': stageAfter,
          'pngPath': png.path, 'pngSha256': sha256.convert(bytes).toString(),
          'pngBytes': bytes.length.toString(), 'pngWidth': picture.width,
          'pngHeight': picture.height, 'capturePixelRatio': 1,
          'boundaryElement': _endpointId(key.currentContext),
          'boundaryRenderObject': _endpointId(boundary),
          'capturedUtc': DateTime.now().toUtc().toIso8601String(),
        });
        frames.add(frame);
        sidecars.add(json);
        final encoded = _encode(frame, false);
        await json.writeAsString(encoded, flush: true);
        sidecarHashes.add(sha256.convert(utf8.encode(encoded)).toString());
      } finally { picture.dispose(); }
      return true;
    });
  }

  String _encode(Map<String, Object?> frame, bool assertionsPassed) => jsonEncode({
    'schema': 'visual-endpoints-2298-v1', 'case': name, 'accepted': false,
    'supplementalAssertionsPassed': assertionsPassed,
    'originalBodyComplete': 'pending; original test result and parent closure required',
    'boundaryElementBefore': boundaryElementBefore,
    'boundaryRenderBefore': boundaryRenderBefore,
    'acceptanceBoundary': 'visual review and parent guard/PID/input closure required',
    ...metadata, 'inputsBefore': inputsBefore, 'frame': frame,
    'errors': errors, 'checks': checks,
  });

  Future<void> _update(bool passed) async {
    await _endpointIO(tester, () async {
      for (var i = 0; i < sidecars.length; i++) {
        final file = sidecars[i];
        if (FileSystemEntity.typeSync(file.path, followLinks: false) != FileSystemEntityType.file ||
            sha256.convert(await file.readAsBytes()).toString() != sidecarHashes[i]) {
          throw StateError('Owned sidecar changed; refusing finalization: ${file.path}');
        }
        final encoded = _encode(frames[i], passed);
        await file.writeAsString(encoded, flush: true);
        sidecarHashes[i] = sha256.convert(utf8.encode(encoded)).toString();
      }
      return true;
    });
  }

  Future<void> finish(int expectedFrames) async {
    final after = await _endpointIO(tester, () async => _endpointInputs());
    metadata['inputsAfter'] = after;
    checks['inputsStable'] = jsonEncode(inputsBefore) == jsonEncode(after);
    checks['inputsReadableAndBound'] = inputsBefore.every((row) =>
        row['error'] == null && row['stableRead'] == true &&
        (row['expectedSha256'] == null || row['expectedSha256'] == row['sha256']));
    checks['frameCount'] = frames.length == expectedFrames;
    checks['boundaryStableAfterRestore'] = _endpointId(key.currentContext) == boundaryElementBefore &&
        _endpointId(key.currentContext?.findRenderObject()) == boundaryRenderBefore;
    await _update(false);
    // All added expectations follow PNG+JSON collection and restoration.
    expect(errors, isEmpty, reason: 'Endpoint capture diagnostics retained: $name');
    expect(checks.values.every((value) => value), isTrue,
        reason: 'Endpoint observations (ordinary scroll clipping is not a defect): $name $checks');
    await _update(true);
  }
}
// END NEW2298 common evidence helpers

// BEGIN NEW2298 CalDAV endpoint helper
Future<void> _captureCalDavEndpoints2298(
  WidgetTester tester, GlobalKey capture, String name, String phase,
  _Sync sync, _Copy copy, Finder message, SharedPreferences prefs,
) async {
  if (!_visualEndpointsEnabled || (name != 'defaultBrand-narrow-guidance' &&
      name != 'liquidGlass-narrow-error')) {
    return;
  }
  final evidence = await _endpointIO(tester, () async => _EndpointEvidence(
    tester, capture, name, {'kind': 'caldav', 'originalPhase': phase,
      'testBody': 'CalDAV card complete generated copy $name',
      'configured': sync.writeTarget != null,
      'copy': copy.name, 'fontRegistration': 'loadWeeklyReviewScreenshotFonts (existing engine registration)',
      'widgetLatinPath': Platform.environment['DUOYI_WIDGET_SCREENSHOT_LATIN_FONT'] ??
          '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      'productionLatinPath': 'assets/fonts/DejaVuSans.ttf',
      'cjkPath': 'assets/fonts/DroidSansFallbackFull.ttf'},
  ));
  final screen = find.byType(IntegrationsScreen);
  ScrollableState? vertical;
  ScrollableState? horizontal;
  ScrollPosition? verticalPosition;
  ScrollPosition? horizontalPosition;
  double? verticalPixels;
  double? horizontalPixels;
  Finder? card;
  Finder? strip;
  Map<String, Object?>? before;
  final buttons = <String, Finder>{};
  final labels = <String, Finder>{};
  final icons = <String, Finder>{};
  final covered = <String, bool>{};
  var intermediateFrameCount2359 = 0;
  Map<String, Object?> state() {
    final context = tester.element(screen);
    return {..._endpointView(tester, context),
      'syncProvider': _endpointId(context.read<CalendarSyncProvider>()),
      'fixtureSync': _endpointId(sync),
      'localeProvider': _endpointId(context.read<LocaleProvider>()),
      'locationsProvider': _endpointId(context.read<LocationReminderProvider>()),
      'notificationsProvider': _endpointId(context.read<NotificationService>()),
      'providerCalls': sync.calls,
      'sharedPreferences': {for (final key in prefs.getKeys().toList()..sort()) key: prefs.get(key)},
      'vertical': vertical == null ? null : _endpointScroll(vertical),
      'horizontal': horizontal == null ? null : _endpointScroll(horizontal),
      'cardElement': card == null ? null : _endpointId(tester.element(card)),
      'stripElement': strip == null ? null : _endpointId(tester.element(strip)),
      'messageElement': _endpointId(tester.element(message)),
      'buttonIdentities': {for (final entry in buttons.entries) entry.key: {
        'element': _endpointId(tester.element(entry.value)),
        'renderObject': _endpointId(tester.renderObject(entry.value)),
      }},
    };
  }
  try {
    card = find.ancestor(of: message, matching: find.byType(AppSurfaceCard));
    if (card.evaluate().length != 1) throw StateError('Message must identify one CalDAV card');
    strip = find.descendant(of: card, matching: find.byKey(const ValueKey('integration_action_strip')));
    vertical = tester.state<ScrollableState>(find.descendant(of: screen,
      matching: find.byWidgetPredicate((widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down)));
    horizontal = tester.state<ScrollableState>(find.descendant(of: strip,
      matching: find.byWidgetPredicate((widget) => widget is Scrollable &&
          (widget.axisDirection == AxisDirection.left || widget.axisDirection == AxisDirection.right))));
    verticalPosition = vertical.position;
    horizontalPosition = horizontal.position;
    verticalPixels = verticalPosition.pixels;
    horizontalPixels = horizontalPosition.pixels;
    final copies = <String, String>{
      'configureOrEdit': copy == _Copy.guidance ? NotificationUiCopy.calDavConfigure : NotificationUiCopy.calDavEdit,
      if (copy != _Copy.guidance) 'remove': NotificationUiCopy.calDavRemove,
      'icloud': 'iCloud', 'testWriteback': NotificationUiCopy.calDavTestWriteback,
    };
    for (final entry in copies.entries) {
      final label = find.descendant(of: strip, matching: find.text(entry.value));
      final button = find.ancestor(of: label, matching: find.byWidgetPredicate(
          (widget) => widget is OutlinedButton || widget is FilledButton));
      buttons[entry.key] = button;
      labels[entry.key] = label;
      icons[entry.key] = find.descendant(of: button, matching: find.byType(Icon));
      covered[entry.key] = false;
    }
    before = state();
    evidence.metadata['before'] = before;
    final body = _endpointBodyViewport(tester, screen, tester.renderObject<RenderBox>(strip));
    final stripRect = tester.getRect(strip);
    verticalPosition.jumpTo((verticalPixels + stripRect.top - body.top - 8)
        .clamp(verticalPosition.minScrollExtent, verticalPosition.maxScrollExtent).toDouble());
    await tester.pumpAndSettle();
    for (final endpoint in ['right', 'left']) {
      try {
        // reverse:true in LTR is AxisDirection.left: right=min, left=max.
        final direction = horizontalPosition.axisDirection;
        final useMin = (direction == AxisDirection.left) == (endpoint == 'right');
        final pixels = useMin ? horizontalPosition.minScrollExtent : horizontalPosition.maxScrollExtent;
        horizontalPosition.jumpTo(pixels);
        await tester.pumpAndSettle();
        final visibleBody = _endpointBodyViewport(tester, screen, tester.renderObject<RenderBox>(strip));
        final horizontalViewport = RenderAbstractViewport.maybeOf(tester.renderObject<RenderBox>(labels.values.first));
        if (horizontalViewport is! RenderBox) throw StateError('Expected box horizontal clip viewport');
        final clip = _endpointBox(horizontalViewport as RenderBox).intersect(tester.getRect(strip)).intersect(visibleBody);
        final actionRows = <String, Object?>{};
        for (final entry in buttons.entries) {
          final buttonRect = tester.getRect(entry.value);
          final labelRect = tester.getRect(labels[entry.key]!);
          final iconRect = tester.getRect(icons[entry.key]!);
          final paragraph = _endpointParagraph(tester, labels[entry.key]!);
          final complete = _endpointContains(clip, buttonRect) &&
              _endpointContains(clip, labelRect) && _endpointContains(clip, iconRect) &&
              paragraph['complete'] == true;
          covered[entry.key] = covered[entry.key]! || complete;
          final widget = tester.widget<ButtonStyleButton>(entry.value);
          actionRows[entry.key] = {
            'label': copies[entry.key], 'buttonRect': _endpointRect(buttonRect),
            'labelRect': _endpointRect(labelRect), 'iconRect': _endpointRect(iconRect),
            'paragraph': paragraph, 'completeAtEndpoint': complete,
            'enabled': widget.onPressed != null,
            'hitTestable': entry.value.hitTestable().evaluate().length == 1,
            'icon': tester.widget<Icon>(icons[entry.key]!).icon?.codePoint.toString(),
          };
          evidence.checks['$endpoint-${entry.key}-singleButtonFitsWidth'] = buttonRect.width <= clip.width + .1;
          if (complete && widget.onPressed != null) {
            evidence.checks['$endpoint-${entry.key}-visibleEnabledButtonHitTestable'] =
                entry.value.hitTestable().evaluate().length == 1;
          }
        }
        final atCapture = state();
        evidence.checks['$endpoint-routeProvidersTargetsAndScrollStable'] =
            jsonEncode(_endpointStableState(before)) == jsonEncode(_endpointStableState(atCapture));
        evidence.checks['$endpoint-position'] = (horizontalPosition.pixels - pixels).abs() < .1;
        evidence.checks['$endpoint-stripHeightVisible'] = _endpointContains(visibleBody, tester.getRect(strip));
        evidence.checks['$endpoint-originalProviderNoCalls'] = sync.calls == 0;
        await evidence.capture('$phase-actions-$endpoint', {
          'visualEndpoint': endpoint, 'expectedEndpointPixels': pixels,
          'atCapture': atCapture, 'bodyViewport': _endpointRect(visibleBody),
          'horizontalClipViewport': _endpointRect(clip),
          'message': _endpointParagraph(tester, message),
          'messageRect': _endpointRect(tester.getRect(message)),
          'cardRect': _endpointRect(tester.getRect(card)),
          'stripRect': _endpointRect(tester.getRect(strip)), 'actions': actionRows,
        });
      } catch (error) {
        evidence.errors.add('$endpoint: $error');
        if (!evidence.frames.any((row) => row['phase'] == '$phase-actions-$endpoint')) {
          await evidence.capture('$phase-actions-$endpoint', {'visualEndpoint': endpoint, 'diagnostic': error.toString()});
        }
      }
    }
    evidence.checks.addAll({
      'originalLocalePhasePreserved': I18n.current.name == (phase == 'switched-en' ? 'en' : 'zh'),
      'allIndividualActionsCompleteAcrossEndpointPair': covered.values.every((value) => value),
      'viewport320x844dpr1': tester.view.physicalSize == const Size(320, 844) && tester.view.devicePixelRatio == 1,
      'actualScaler1.6': MediaQuery.of(tester.element(screen)).textScaler.scale(16) == 25.6,
    });
    evidence.metadata['completeAcrossEndpoints'] = covered;
    // BEGIN NEW2359 measured intermediate coverage, preserving endpoint facts.
    final endpointPairComplete2359 = evidence.checks.remove(
      'allIndividualActionsCompleteAcrossEndpointPair',
    ) ?? false;
    evidence.metadata['allIndividualActionsCompleteAcrossEndpointPair'] =
        endpointPairComplete2359;
    evidence.metadata['endpointPairChecks2359'] = {
      'allIndividualActionsCompleteAcrossEndpointPair': endpointPairComplete2359,
    };
    // The original covered map remains the endpoint-only observation.
    final completeAcrossCaptureSet2359 = Map<String, bool>.from(covered);
    final missingAtEndpoints2359 = covered.entries
        .where((entry) => !entry.value)
        .map((entry) => entry.key)
        .toList();
    evidence.metadata['coverageScope2359'] =
        'original right/left endpoints plus actual intermediate frames for '
        'actions incomplete across the endpoint pair';
    evidence.metadata['intermediateTargets2359'] = missingAtEndpoints2359;
    for (final target2359 in missingAtEndpoints2359) {
      final capturePhase2359 = '$phase-actions-intermediate-$target2359';
      intermediateFrameCount2359++;
      final planning2359 = <String, Object?>{
        'target': target2359,
        'endpointPairCompleteBeforeSupplement': endpointPairComplete2359,
        'derivedFrom': 'actual button/label/icon bounds and horizontal clip',
      };
      try {
        final visibleBefore2359 = _endpointBodyViewport(
          tester, screen, tester.renderObject<RenderBox>(strip),
        );
        final viewportBefore2359 = RenderAbstractViewport.maybeOf(
          tester.renderObject<RenderBox>(labels[target2359]!),
        );
        if (viewportBefore2359 is! RenderBox) {
          throw StateError('Expected box horizontal viewport for intermediate');
        }
        final clipBefore2359 = _endpointBox(viewportBefore2359 as RenderBox)
            .intersect(tester.getRect(strip)).intersect(visibleBefore2359);
        final bounds2359 = tester.getRect(buttons[target2359]!)
            .expandToInclude(tester.getRect(labels[target2359]!))
            .expandToInclude(tester.getRect(icons[target2359]!));
        final direction2359 = horizontalPosition.axisDirection;
        if (direction2359 != AxisDirection.left &&
            direction2359 != AxisDirection.right) {
          throw StateError('Intermediate requires an actual horizontal axis');
        }
        // Increasing pixels moves the content right for AxisDirection.left,
        // and left for AxisDirection.right. Solve the complete-bounds interval.
        final current2359 = horizontalPosition.pixels;
        final shiftLow2359 = clipBefore2359.left - bounds2359.left;
        final shiftHigh2359 = clipBefore2359.right - bounds2359.right;
        final rawLow2359 = current2359 + (direction2359 == AxisDirection.left
            ? shiftLow2359 : -shiftHigh2359);
        final rawHigh2359 = current2359 + (direction2359 == AxisDirection.left
            ? shiftHigh2359 : -shiftLow2359);
        final low2359 = rawLow2359 > horizontalPosition.minScrollExtent
            ? rawLow2359 : horizontalPosition.minScrollExtent;
        final high2359 = rawHigh2359 < horizontalPosition.maxScrollExtent
            ? rawHigh2359 : horizontalPosition.maxScrollExtent;
        planning2359.addAll({
          'axisDirection': direction2359.name,
          'planningPixels': current2359,
          'planningClip': _endpointRect(clipBefore2359),
          'planningCompleteBounds': _endpointRect(bounds2359),
          'rawFeasibleMinPixels': rawLow2359,
          'rawFeasibleMaxPixels': rawHigh2359,
          'feasibleMinPixels': low2359, 'feasibleMaxPixels': high2359,
          'minScrollExtent': horizontalPosition.minScrollExtent,
          'maxScrollExtent': horizontalPosition.maxScrollExtent,
        });
        final feasible2359 = low2359.isFinite && high2359.isFinite &&
            low2359 <= high2359 && bounds2359.width <= clipBefore2359.width + .1;
        evidence.checks['intermediate-$target2359-feasibleCompleteBounds'] =
            feasible2359;
        if (!feasible2359) {
          throw StateError('No feasible complete intermediate for $target2359');
        }
        final pixels2359 = (low2359 + high2359) / 2;
        planning2359['requestedPixels'] = pixels2359;
        horizontalPosition.jumpTo(pixels2359);
        await tester.pumpAndSettle();
        final visibleBody2359 = _endpointBodyViewport(
          tester, screen, tester.renderObject<RenderBox>(strip),
        );
        final viewport2359 = RenderAbstractViewport.maybeOf(
          tester.renderObject<RenderBox>(labels[target2359]!),
        );
        if (viewport2359 is! RenderBox) {
          throw StateError('Expected box intermediate horizontal clip viewport');
        }
        final clip2359 = _endpointBox(viewport2359 as RenderBox)
            .intersect(tester.getRect(strip)).intersect(visibleBody2359);
        final actionRows2359 = <String, Object?>{};
        for (final entry in buttons.entries) {
          final buttonRect2359 = tester.getRect(entry.value);
          final labelRect2359 = tester.getRect(labels[entry.key]!);
          final iconRect2359 = tester.getRect(icons[entry.key]!);
          final paragraph2359 = _endpointParagraph(tester, labels[entry.key]!);
          final complete2359 = _endpointContains(clip2359, buttonRect2359) &&
              _endpointContains(clip2359, labelRect2359) &&
              _endpointContains(clip2359, iconRect2359) &&
              paragraph2359['complete'] == true;
          final widget2359 = tester.widget<ButtonStyleButton>(entry.value);
          final hit2359 = entry.value.hitTestable().evaluate().length == 1;
          actionRows2359[entry.key] = {
            'label': copies[entry.key],
            'buttonRect': _endpointRect(buttonRect2359),
            'labelRect': _endpointRect(labelRect2359),
            'iconRect': _endpointRect(iconRect2359),
            'paragraph': paragraph2359,
            'completeAtIntermediate': complete2359,
            'enabled': widget2359.onPressed != null, 'hitTestable': hit2359,
            'icon': tester.widget<Icon>(icons[entry.key]!).icon?.codePoint.toString(),
          };
          evidence.checks['intermediate-$target2359-${entry.key}-singleButtonFitsWidth'] =
              buttonRect2359.width <= clip2359.width + .1;
          if (complete2359 && widget2359.onPressed != null) {
            evidence.checks['intermediate-$target2359-${entry.key}-visibleEnabledButtonHitTestable'] =
                hit2359;
          }
        }
        final atCapture2359 = state();
        evidence.checks['intermediate-$target2359-routeProvidersTargetsAndScrollStable'] =
            jsonEncode(_endpointStableState(before)) ==
            jsonEncode(_endpointStableState(atCapture2359));
        evidence.checks['intermediate-$target2359-position'] =
            (horizontalPosition.pixels - pixels2359).abs() < .1;
        evidence.checks['intermediate-$target2359-actuallyBetweenEndpoints'] =
            pixels2359 > horizontalPosition.minScrollExtent + .1 &&
            pixels2359 < horizontalPosition.maxScrollExtent - .1;
        evidence.checks['intermediate-$target2359-targetComplete'] =
            (actionRows2359[target2359] as Map<String, Object?>)
                ['completeAtIntermediate'] == true;
        evidence.checks['intermediate-$target2359-stripHeightVisible'] =
            _endpointContains(visibleBody2359, tester.getRect(strip));
        evidence.checks['intermediate-$target2359-originalProviderNoCalls'] =
            sync.calls == 0;
        await evidence.capture(capturePhase2359, {
          'visualEndpoint': 'intermediate',
          'targetAction': target2359, 'intermediatePlan2359': planning2359,
          'expectedIntermediatePixels': pixels2359,
          'atCapture': atCapture2359,
          'bodyViewport': _endpointRect(visibleBody2359),
          'horizontalClipViewport': _endpointRect(clip2359),
          'message': _endpointParagraph(tester, message),
          'messageRect': _endpointRect(tester.getRect(message)),
          'cardRect': _endpointRect(tester.getRect(card)),
          'stripRect': _endpointRect(tester.getRect(strip)),
          'actions': actionRows2359,
        });
        for (final entry2359 in actionRows2359.entries) {
          final observed2359 = entry2359.value as Map<String, Object?>;
          completeAcrossCaptureSet2359[entry2359.key] =
              completeAcrossCaptureSet2359[entry2359.key]! ||
              observed2359['completeAtIntermediate'] == true;
        }
      } catch (error) {
        evidence.errors.add('intermediate-$target2359: $error');
        if (!evidence.frames.any((row) => row['phase'] == capturePhase2359)) {
          await evidence.capture(capturePhase2359, {
            'visualEndpoint': 'intermediate', 'targetAction': target2359,
            'intermediatePlan2359': planning2359,
            'diagnostic': error.toString(),
          });
        }
      }
    }
    evidence.metadata['completeAcrossCaptureSet2359'] =
        Map<String, bool>.from(completeAcrossCaptureSet2359);
    evidence.metadata['intermediateFrameCount2359'] = intermediateFrameCount2359;
    evidence.checks['allIndividualActionsCompleteAcrossCaptureSet2359'] =
        completeAcrossCaptureSet2359.values.every((value) => value);
    // END NEW2359 measured intermediate coverage.
  } catch (error) {
    evidence.errors.add(error.toString());
    for (final endpoint in ['right', 'left']) {
      if (!evidence.frames.any((row) => row['phase'] == '$phase-actions-$endpoint')) {
        await evidence.capture('$phase-actions-$endpoint', {'visualEndpoint': endpoint, 'diagnostic': error.toString()});
      }
    }
  } finally {
    try {
      if (horizontalPosition != null && horizontalPixels != null) {
        horizontalPosition.jumpTo(horizontalPixels.clamp(
            horizontalPosition.minScrollExtent, horizontalPosition.maxScrollExtent).toDouble());
      }
      if (verticalPosition != null && verticalPixels != null) {
        verticalPosition.jumpTo(verticalPixels.clamp(
            verticalPosition.minScrollExtent, verticalPosition.maxScrollExtent).toDouble());
      }
      await tester.pumpAndSettle();
      final after = state();
      evidence.metadata['afterRestore'] = after;
      evidence.checks['routeProvidersTargetsAndScrollStable'] = before != null && jsonEncode(before) == jsonEncode(after);
      evidence.checks['originalPositionAndPixelsRestored'] =
          identical(vertical!.position, verticalPosition) && identical(horizontal!.position, horizontalPosition) &&
          (verticalPosition!.pixels - verticalPixels!).abs() < .1 &&
          (horizontalPosition!.pixels - horizontalPixels!).abs() < .1;
    } catch (error) { evidence.errors.add('restore: $error'); }
  }
  await evidence.finish(2 + intermediateFrameCount2359);
}
// END NEW2298 CalDAV endpoint helper
