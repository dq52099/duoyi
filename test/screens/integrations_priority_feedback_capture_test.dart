import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

// Uses the same platform fixtures as integrations_retained_feedback_test.
// ignore_for_file: depend_on_referenced_packages
import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/ics_subscription_storage.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../support/retained_feedback_visual.dart'
    show loadRetainedFeedbackFonts;

const _captureKey = ValueKey('integrations-priority-feedback-capture-262');
const _literalName = 'Fixture 用户日历 262';
const _clientId = 'fixture-client-262';
const _code = 'fixture-code-262';
const _icsId = 'fixture-ics-262';
const _icsName = 'Fixture 原文 ICS 262';
const _permissionChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);
const _geofenceChannel = MethodChannel('duoyi/location_geofence');
final _strict = Platform.environment['DUOYI_INTEGRATIONS_STRICT'] == '1';

enum _Case { oauthCopy, oauthOpenFailure, locationSettings, oauthMenu, icsMenu }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final start in [AppLocale.zh, AppLocale.en]) {
      for (final viewport in [
        (name: '390x844-100', size: const Size(390, 844), scale: 1.0),
        (name: '320x844-200', size: const Size(320, 844), scale: 2.0),
      ]) {
        for (final kind in _Case.values) {
          testWidgets(
            '262 ${kind.name} $brand ${start.name} ${viewport.name} retained capture',
            (tester) async {
              final fixture = _Fixture(
                brand: brand,
                start: start,
                kind: kind,
                size: viewport.size,
                scale: viewport.scale,
                id: '${kind.name}-$brand-${start.name}-${viewport.name}',
              );
              final semantics = tester.ensureSemantics();
              try {
                await fixture.mount(tester);
                await fixture.openState(tester);
                final overlay = fixture.overlay;
                expect(overlay, findsOneWidget);
                final retainedElement = tester.element(overlay);
                final route = ModalRoute.of(retainedElement);
                final openingLabels = fixture.labels();
                final scrollPositions = fixture.scrollPositions(tester);
                final openingOps = fixture.operations();
                final draft = fixture.drafts(tester);
                final authority = fixture.authority();
                fixture.bindNativeAction(tester);
                final originalAction = fixture.nativeActionCallback;

                Future<void> capture(String phase) async {
                  expect(tester.element(overlay), same(retainedElement));
                  expect(ModalRoute.of(tester.element(overlay)), same(route));
                  expect(
                    tester.element(find.byType(IntegrationsScreen)),
                    same(fixture.screenElement),
                  );
                  expect(fixture.operations(), openingOps);
                  expect(fixture.drafts(tester), draft);
                  expect(fixture.authority(), authority);
                  final record = await fixture.capture(
                    tester,
                    phase,
                    openingLabels: openingLabels,
                    expectedLabels: fixture.labels(),
                    openingAuthority: authority,
                    openingScrollPositions: scrollPositions,
                  );
                  // Capture precedes strict assertions so failed states survive.
                  final shown = (record['shownText'] as List).cast<String>();
                  for (
                    var index = 0;
                    index < fixture.labels().length;
                    index++
                  ) {
                    final current = fixture.labels()[index];
                    final opening = openingLabels[index];
                    expect(shown, anyOf(contains(current), contains(opening)));
                    if (_strict) expect(shown, contains(current));
                  }
                  if (_strict) {
                    for (final raw in record['paragraphs'] as List) {
                      final paragraph = raw as Map<String, Object?>;
                      expect(
                        paragraph['complete'],
                        isTrue,
                        reason: '${fixture.id}/$phase ${paragraph['text']}',
                      );
                    }
                  }
                  expect(tester.takeException(), isNull);
                }

                await capture('opened');
                await fixture.setBrand(tester, fixture.otherBrand);
                await capture('theme-changed');
                await fixture.setLocale(
                  tester,
                  start == AppLocale.zh ? AppLocale.en : AppLocale.zh,
                );
                await capture('locale-changed');
                await fixture.setBrand(tester, brand);
                await fixture.setLocale(tester, start);
                await capture('restored');

                if (kind == _Case.locationSettings) {
                  final snack = tester.widget<SnackBar>(overlay);
                  expect(snack.persist, isTrue);
                  expect(fixture.nativeActionFinder, findsOneWidget);
                  expect(tester.widget<SnackBarAction>(fixture.nativeActionFinder)
                      .onPressed, same(originalAction));
                  await tester.pump(
                    snack.duration + const Duration(seconds: 1),
                  );
                  await capture('action-lifetime');
                  final settings = find.descendant(
                    of: overlay,
                    matching: find.text(NotificationUiCopy.toSettingsAction),
                  );
                  expect(settings, findsOneWidget);
                  await tester.tap(settings);
                  await _frames(tester);
                  expect(fixture.settingsOpens, 1);
                  expect(fixture.permissionRequests, openingOps['permissions']);
                  expect(fixture.geofenceSyncs, 0);
                } else if (kind == _Case.icsMenu || kind == _Case.oauthMenu) {
                  // Tap the actual retained opening item; no direct callback replay.
                  final pause = find.byWidgetPredicate(
                    (widget) =>
                        widget is PopupMenuItem<String> &&
                        widget.value ==
                            (kind == _Case.icsMenu ? 'pause' : 'toggle'),
                  );
                  expect(pause, findsOneWidget);
                  await tester.tap(pause);
                  await _frames(tester);
                  fixture.observeNativeMenu(tester, 'selected', false);
                  await tester.runAsync(() async {
                    await AccountPreferenceWrites.drain().timeout(
                      const Duration(seconds: 10),
                    );
                  });
                  await _frames(tester);
                  if (kind == _Case.icsMenu) {
                    expect(
                      fixture.calendar.subscriptions.single.enabled,
                      isFalse,
                    );
                    expect(fixture.calendar.icsActions, [
                      {'id': _icsId, 'enabled': false, 'authorityAtCall': true},
                    ]);
                    final stored = await fixture.store.getAll();
                    final rows =
                        jsonDecode(
                              stored['flutter.${IcsSubscriptionStorage.subscriptionsKey}']
                                  as String,
                            )
                            as List;
                    expect((rows.single as Map)['enabled'], isFalse);
                  } else {
                    expect(fixture.calendar.oauthActions, [
                      {'id': 'fixture-oauth-262', 'enabled': false},
                    ]);
                  }
                }
                await fixture.capture(
                  tester,
                  'action-completed',
                  openingLabels: openingLabels,
                  expectedLabels: const [],
                  openingAuthority: authority,
                  openingScrollPositions: scrollPositions,
                );
                expect(tester.takeException(), isNull);
              } finally {
                try {
                  await fixture.close(tester);
                } finally {
                  semantics.dispose();
                }
              }
            },
          );
        }
      }
    }
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 100));
}

// Compare divergent branches under their actual common render ancestor. This
// handles Navigator Overlay order and a foreground sibling in a dialog route;
// a dialog's own ancestor surface cannot cover its descendant feedback.
int? _relativePaintOrder(RenderObject text, RenderObject surface) {
  List<RenderObject> lineage(RenderObject node) {
    final result = <RenderObject>[node];
    while (node.parent != null) {
      node = node.parent!;
      result.add(node);
    }
    return result.reversed.toList();
  }

  final a = lineage(text);
  final b = lineage(surface);
  var shared = 0;
  while (shared < a.length &&
      shared < b.length &&
      identical(a[shared], b[shared])) {
    shared++;
  }
  if (shared == b.length) return -1; // Surface paints before its descendant.
  if (shared == a.length) return 1;
  if (shared == 0) return null;
  final common = a[shared - 1];
  // Only use child order where the framework paints forward. Unknown custom
  // multi-child renderers remain unresolved instead of certifying visibility.
  if (common.runtimeType != RenderStack &&
      common.runtimeType.toString() != '_RenderTheater') {
    return null;
  }
  final children = <RenderObject>[];
  common.visitChildren(children.add);
  final textIndex = children.indexWhere((node) => identical(node, a[shared]));
  final surfaceIndex = children.indexWhere(
    (node) => identical(node, b[shared]),
  );
  if (textIndex < 0 || surfaceIndex < 0) return null;
  return surfaceIndex.compareTo(textIndex);
}

class _DialogSurface329 {
  _DialogSurface329(this.element, this.render, this.path, this.color);
  final Element element;
  final RenderBox render;
  final Path path;
  final Color color;
}

List<_DialogSurface329> _opaqueDialogSurfaces329(WidgetTester tester) {
  final result = <_DialogSurface329>[];
  for (final dialog in find.byType(Dialog).evaluate()) {
    final materials = find
        .descendant(
          of: find.byElementPredicate((element) => identical(element, dialog)),
          matching: find.byType(Material),
        )
        .evaluate();
    if (materials.isEmpty) continue;
    // Flutter Dialog builds its surface Material before nested content controls.
    final element = materials.first;
    final material = element.widget as Material;
    final color = material.color;
    final render = element.findRenderObject();
    if (color == null ||
        color.a < .999 ||
        render is! RenderBox ||
        !render.hasSize) {
      continue;
    }
    var opaqueAncestors = true;
    RenderObject? ancestor = render;
    while (ancestor != null) {
      if (ancestor is RenderOpacity && ancestor.opacity < .999) {
        opaqueAncestors = false;
      }
      if (ancestor is RenderAnimatedOpacity && ancestor.opacity.value < .999) {
        opaqueAncestors = false;
      }
      ancestor = ancestor.parent;
    }
    if (!opaqueAncestors) continue;
    final bounds = Offset.zero & render.size;
    final Path local;
    if (render is RenderPhysicalShape) {
      local = render.clipper?.getClip(render.size) ?? (Path()..addRect(bounds));
    } else if (render is RenderPhysicalModel) {
      local = render.shape == BoxShape.circle
          ? (Path()..addOval(bounds))
          : (Path()..addRRect(
              (render.borderRadius ?? BorderRadius.zero).toRRect(bounds),
            ));
    } else {
      // An unknown surface cannot be measured from a target shape alone.
      throw StateError(
        'Unresolved actual Dialog physical surface: ${render.runtimeType}',
      );
    }
    result.add(
      _DialogSurface329(
        element,
        render,
        local.transform(render.getTransformTo(null).storage),
        color,
      ),
    );
  }
  return result;
}

Map<String, Object?> _paragraphPaint349(RenderParagraph paragraph) {
  final glyphs = paragraph
      .getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: paragraph.text.toPlainText().length,
        ),
      )
      .map(
        (box) => MatrixUtils.transformRect(
          paragraph.getTransformTo(null),
          box.toRect(),
        ),
      )
      .where((rect) => !rect.isEmpty)
      .toList();
  final clips = <Map<String, Object?>>[];
  var fullyPainted = true;
  RenderObject child = paragraph;
  RenderObject? ancestor = child.parent;
  while (ancestor != null) {
    if ((ancestor is RenderOpacity && ancestor.opacity < .999) ||
        (ancestor is RenderAnimatedOpacity && ancestor.opacity.value < .999) ||
        (ancestor is RenderOffstage && ancestor.offstage)) {
      fullyPainted = false;
    }
    final localClip = ancestor.describeApproximatePaintClip(child);
    if (localClip != null) {
      final globalClip = MatrixUtils.transformRect(
        ancestor.getTransformTo(null),
        localClip,
      );
      final covered = glyphs.every(
        (rect) =>
            globalClip.inflate(.1).contains(rect.topLeft) &&
            globalClip.inflate(.1).contains(rect.bottomRight),
      );
      fullyPainted = fullyPainted && covered;
      clips.add({
        'type': ancestor.runtimeType.toString(),
        'bounds': [
          globalClip.left,
          globalClip.top,
          globalClip.width,
          globalClip.height,
        ],
        'containsGlyphBounds': covered,
      });
    }
    child = ancestor;
    ancestor = ancestor.parent;
  }
  return {
    'fullyPainted': fullyPainted,
    'ancestorClipBounds': clips,
    'scope':
        'actual opacity/offstage and approximate ancestor clip bounds; rounded clip corners require original pixel review',
  };
}

Map<String, Object?> _occlusion329(
  Element element,
  RenderParagraph paragraph,
  List<_DialogSurface329> surfaces,
) {
  final textRoute = ModalRoute.of(element);
  final glyphRects = paragraph
      .getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: paragraph.text.toPlainText().length,
        ),
      )
      .map(
        (box) => MatrixUtils.transformRect(
          paragraph.getTransformTo(null),
          box.toRect(),
        ),
      )
      .where((rect) => !rect.isEmpty)
      .toList();
  final candidates = <Map<String, Object?>>[];
  var occluded = false;
  var unresolved = false;
  for (final surface in surfaces) {
    final route = ModalRoute.of(surface.element);
    if (route != null && !route.isActive) continue;
    final order = _relativePaintOrder(paragraph, surface.render);
    final intersections = <List<double>>[];
    for (final rect in glyphRects) {
      final overlap = Path.combine(
        PathOperation.intersect,
        surface.path,
        Path()..addRect(rect),
      ).getBounds();
      if (!overlap.isEmpty) {
        intersections.add([
          overlap.left,
          overlap.top,
          overlap.width,
          overlap.height,
        ]);
      }
    }
    final sameRoute = identical(textRoute, route);
    final blocks = intersections.isNotEmpty && order != null && order > 0;
    final unknown = intersections.isNotEmpty && order == null;
    occluded = occluded || blocks;
    unresolved = unresolved || unknown;
    final rect = surface.path.getBounds();
    candidates.add({
      'dialogRouteIdentity': route == null ? null : identityHashCode(route),
      'dialogRouteCurrent': route?.isCurrent,
      'sameRoute': sameRoute,
      'surfaceIdentity': identityHashCode(surface.render),
      'surfaceColor': surface.color.toARGB32(),
      'surfaceBounds': [rect.left, rect.top, rect.width, rect.height],
      'surfaceAfterParagraph': order == null ? null : order > 0,
      'orderMethod':
          'divergent render siblings in visitChildren paint order; ancestor surface precedes descendant',
      'glyphIntersections': intersections,
      'occludes': blocks,
      'orderingUnresolved': unknown,
    });
  }
  return {
    'paragraphRouteIdentity': textRoute == null
        ? null
        : identityHashCode(textRoute),
    'paragraphRouteCurrent': textRoute?.isCurrent,
    'glyphRects': glyphRects
        .map((rect) => [rect.left, rect.top, rect.width, rect.height])
        .toList(),
    'occluded': occluded,
    'orderingUnresolved': unresolved,
    'dialogSurfaces': candidates,
  };
}

class _Fixture {
  _Fixture({
    required this.brand,
    required this.start,
    required this.kind,
    required this.size,
    required this.scale,
    required this.id,
  });
  final String brand;
  final AppLocale start;
  final _Case kind;
  final Size size;
  final double scale;
  final String id;
  final theme = ThemeProvider();
  final locale = LocaleProvider();
  final calendar = _Calendar();
  final locations = LocationReminderProvider();
  final notifications = NotificationService();
  final navigator = GlobalKey<NavigatorState>();
  final observer = _Observer();
  final previousStore = SharedPreferencesStorePlatform.instance;
  final previousLauncher = UrlLauncherPlatform.instance;
  final launcher = _Launcher();
  late final _Store store;
  Element? screenElement;
  final clipboard = <String>[];
  int permissionChecks = 0;
  int permissionRequests = 0;
  int settingsOpens = 0;
  int geofenceSyncs = 0;
  Element? nativeActionElement;
  State<SnackBarAction>? nativeActionState;
  VoidCallback? nativeActionCallback;
  Element? nativeMenuElement;
  PopupMenuButtonState<String>? nativeMenuState;
  final nativeMenuObservations = <Map<String, Object?>>[];
  bool menuCancellationPreserved = true;

  Finder get nativeActionFinder => find.descendant(
    of: find.byType(SnackBar), matching: find.byType(SnackBarAction),
  );

  void bindNativeAction(WidgetTester tester) {
    if (kind != _Case.locationSettings) return;
    final members = nativeActionFinder.evaluate().toList();
    if (members.length != 1) return; // Capture records the failure before assertions.
    nativeActionElement = members.single;
    nativeActionState = tester.state<State<SnackBarAction>>(nativeActionFinder);
    nativeActionCallback = tester.widget<SnackBarAction>(nativeActionFinder).onPressed;
  }

  Map<String, Object?> nativeActionEvidence(WidgetTester tester) {
    final snacks = find.byType(SnackBar).evaluate().toList();
    final members = nativeActionFinder.evaluate().toList();
    if (snacks.length != 1 || members.length != 1) {
      return {'snackCount': snacks.length, 'nativeActionCount': members.length};
    }
    final action = tester.widget<SnackBarAction>(nativeActionFinder);
    final state = tester.state<State<SnackBarAction>>(nativeActionFinder);
    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    return {
      'snackCount': 1, 'nativeActionCount': 1,
      'exactNativeType': action.runtimeType == SnackBarAction,
      'label': action.label, 'callbackIdentity': identityHashCode(action.onPressed),
      'elementIdentity': identityHashCode(members.single),
      'stateIdentity': identityHashCode(state),
      'elementRetained': identical(members.single, nativeActionElement),
      'stateRetained': identical(state, nativeActionState),
      'callbackRetained': identical(action.onPressed, nativeActionCallback),
      'persistent': snack.persist, 'durationMs': snack.duration.inMilliseconds,
    };
  }

  Map<String, Object?> observeNativeMenu(
    WidgetTester tester, String phase, bool expectedExpanded,
  ) {
    final row = <String, Object?>{
      'phase': phase, 'expectedExpanded': expectedExpanded,
      'brand': theme.brand.id, 'locale': I18n.current.name,
    };
    try {
      final trigger = find.byElementPredicate(
        (element) => identical(element, nativeMenuElement),
      );
      final nodes = <Map<String, Object?>>[];
      void readNode(SemanticsNode node) {
        final data = node.getSemanticsData();
        if (data.flagsCollection.isExpanded != ui.Tristate.none) {
          nodes.add({'nodeId': node.id,
            'expanded': data.flagsCollection.isExpanded == ui.Tristate.isTrue});
        }
        node.visitChildren((child) { readNode(child); return true; });
      }
      readNode(tester.getSemantics(trigger));
      row.addAll({
        'triggerCount': trigger.evaluate().length,
        'elementRetained': identical(tester.element(trigger), nativeMenuElement),
        'stateRetained': identical(
          tester.state<PopupMenuButtonState<String>>(trigger), nativeMenuState),
        'nativeExpandedNodes': nodes,
        'expandedMatches': nodes.length == 1 && nodes.single['expanded'] == expectedExpanded,
      });
    } catch (error) {
      row['observationError'] = '$error';
      row['expandedMatches'] = false;
    }
    nativeMenuObservations.add(row);
    return row;
  }
  String get otherBrand =>
      brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand';
  bool get isMenu => kind == _Case.icsMenu || kind == _Case.oauthMenu;
  Finder get overlay =>
      isMenu ? find.byType(PopupMenuItem<String>).first : find.byType(SnackBar);

  Future<void> mount(WidgetTester tester) async {
    // Native layout and retention checks always need the evidence fonts.
    await tester.runAsync(loadRetainedFeedbackFonts);
    SharedPreferences.setMockInitialValues({});
    store = _Store(brand, start, kind == _Case.icsMenu);
    SharedPreferencesStorePlatform.instance = store;
    UrlLauncherPlatform.instance = launcher;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      } else if (call.method == 'Clipboard.getData') {
        return {'text': clipboard.isEmpty ? '' : clipboard.last};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_permissionChannel, (call) async {
      if (call.method == 'checkPermissionStatus') {
        permissionChecks++;
        return call.arguments == Permission.locationWhenInUse.value
            ? PermissionStatus.granted.index
            : PermissionStatus.permanentlyDenied.index;
      }
      if (call.method == 'requestPermissions') {
        permissionRequests++;
        return {
          for (final value in call.arguments as List)
            value: PermissionStatus.permanentlyDenied.index,
        };
      }
      throw StateError('Unexpected permission fixture method ${call.method}');
    });
    messenger.setMockMethodCallHandler(_geofenceChannel, (call) async {
      if (call.method == 'openLocationSettings') {
        settingsOpens++;
        return true;
      }
      if (call.method == 'syncReminders') {
        geofenceSyncs++;
        return {'available': true, 'scheduledCount': 0, 'status': 'fixture'};
      }
      if (call.method == 'clearReminders') {
        return {'available': true, 'scheduledCount': 0, 'status': 'fixture'};
      }
      throw StateError('Unexpected geofence fixture method ${call.method}');
    });
    await tester.runAsync(() async {
      await theme.loadFromStorage();
      await locale.loadFromStorage();
      await calendar.loadFromStorage();
    });
    I18n.setLocale(start);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
          ChangeNotifierProvider<CalendarSyncProvider>.value(value: calendar),
          ChangeNotifierProvider<LocationReminderProvider>.value(
            value: locations,
          ),
          ChangeNotifierProvider<NotificationService>.value(
            value: notifications,
          ),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, theme, _) => MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [observer],
            theme: theme.brand.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: _captureKey, child: child!),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const BrandRouteSurface(child: IntegrationsScreen()),
                    ),
                  ),
                  child: const Text('Open fixture extensions 262'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open fixture extensions 262'));
    await _frames(tester);
    screenElement = tester.element(find.byType(IntegrationsScreen));
    expect(theme.brand.id, brand);
    expect(tester.takeException(), isNull);
  }

  Future<void> openState(WidgetTester tester) async {
    final screen = find.byElementPredicate(
      (element) => identical(element, screenElement),
    );
    final tabBar = find.descendant(of: screen, matching: find.byType(TabBar));

    Finder activeList(int tabIndex) {
      expect(screen, findsOneWidget);
      expect(tabBar, findsOneWidget);
      expect(DefaultTabController.of(tester.element(tabBar)).index, tabIndex);
      final view = find.descendant(
        of: screen,
        matching: find.byType(TabBarView),
      );
      expect(view, findsOneWidget);
      // Adjacent cached pages can be mounted; only the current list is hit-testable.
      final list = find
          .descendant(of: view, matching: find.byType(ListView))
          .hitTestable();
      expect(
        list,
        findsOneWidget,
        reason: 'Exactly one active ListView must be hit-testable in tab $tabIndex.',
      );
      return list;
    }

    Future<void> findMounted(
      Finder list,
      Finder target,
      String description,
    ) async {
      final scroll = find.descendant(
        of: list,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      expect(scroll, findsOneWidget);
      final state = tester.state<ScrollableState>(scroll);
      expect(state.position.hasContentDimensions, isTrue);
      for (var step = 0; step <= 40; step++) {
        if (target.evaluate().isNotEmpty) {
          expect(
            target,
            findsOneWidget,
            reason: '$description must mount exactly once in the active list.',
          );
          return;
        }
        final position = state.position;
        final before = position.pixels;
        if (step == 40 || before >= position.maxScrollExtent) {
          fail(
            'Could not mount $description after $step vertical drags: '
            'pixels=$before max=${position.maxScrollExtent}.',
          );
        }
        await tester.drag(scroll, const Offset(0, -100));
        await _frames(tester);
        expect(tester.state<ScrollableState>(scroll), same(state));
        if (state.position.pixels <= before && target.evaluate().isEmpty) {
          fail('No forward scroll progress while searching for $description.');
        }
      }
    }

    if (kind == _Case.locationSettings) {
      expect(screen, findsOneWidget);
      expect(tabBar, findsOneWidget);
      final tab = find.descendant(
        of: tabBar,
        matching: find.text(NotificationUiCopy.tabLocation),
      );
      expect(tab, findsOneWidget);
      final horizontal = find.descendant(
        of: tabBar,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              (widget.axisDirection == AxisDirection.right ||
                  widget.axisDirection == AxisDirection.left),
        ),
      );
      expect(horizontal, findsOneWidget);
      expect(find.ancestor(of: tab, matching: horizontal), findsOneWidget);
      await tester.ensureVisible(tab);
      await _frames(tester);
      expect(tab.hitTestable(), findsOneWidget);
      await tester.tap(tab);
      await _frames(tester);
      final list = activeList(1);
      final grant = find.descendant(
        of: list,
        matching: find.widgetWithText(
          OutlinedButton,
          NotificationUiCopy.grantBackgroundLocationAction,
        ),
      );
      await findMounted(list, grant, 'location grant button');
      await _tap(tester, grant);
      expect(permissionRequests, 1);
      expect(geofenceSyncs, 0);
      // Native action census/identity is checked only after the opened capture.
      return;
    }
    if (isMenu) {
      final list = activeList(0);
      final title = find.descendant(
        of: list,
        matching: find.text(kind == _Case.icsMenu ? _icsName : _literalName),
      );
      await findMounted(list, title, 'calendar menu literal title');
      await tester.ensureVisible(title);
      await _frames(tester);
      final tile = find.ancestor(of: title, matching: find.byType(ListTile));
      expect(tile, findsOneWidget);
      final trigger = find.descendant(
        of: tile,
        matching: find.byWidgetPredicate((widget) => widget is PopupMenuButton<String>),
      );
      expect(trigger, findsOneWidget);
      nativeMenuElement = tester.element(trigger);
      nativeMenuState = tester.state<PopupMenuButtonState<String>>(trigger);
      final beforeCancelOps = operations();
      final beforeCancelAuthority = authority();
      observeNativeMenu(tester, 'closed', false);
      await _tap(tester, trigger);
      observeNativeMenu(tester, 'open-before-cancel', true);
      // Native route cancellation, without replaying callbacks or business actions.
      navigator.currentState!.pop();
      await _frames(tester);
      observeNativeMenu(tester, 'canceled', false);
      menuCancellationPreserved = jsonEncode(operations()) == jsonEncode(beforeCancelOps)
          && jsonEncode(authority()) == jsonEncode(beforeCancelAuthority);
      await _tap(tester, trigger);
      observeNativeMenu(tester, 'opened', true);
      return;
    }
    await _tap(
      tester,
      find.widgetWithText(FilledButton, NotificationUiCopy.addAccountAction),
    );
    await tester.enterText(
      find.widgetWithText(TextField, NotificationUiCopy.displayNameLabel),
      _literalName,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Client ID'),
      _clientId,
    );
    final code = find.widgetWithText(
      TextField,
      NotificationUiCopy.authCodeLabel,
    );
    await tester.ensureVisible(code);
    await tester.enterText(code, _code);
    final field = tester.widget<TextField>(code);
    field.controller!.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 5,
    );
    await _tap(
      tester,
      find.widgetWithText(
        kind == _Case.oauthCopy ? OutlinedButton : FilledButton,
        kind == _Case.oauthCopy
            ? NotificationUiCopy.copyAction
            : NotificationUiCopy.openAction,
      ),
    );
    expect(calendar.pending.length, 1);
    expect(clipboard.length, 1);
    expect(launcher.urls.length, kind == _Case.oauthCopy ? 0 : 1);
    final saved = calendar.pending.single;
    expect(saved['displayName'], _literalName);
    expect(saved['clientId'], _clientId);
    expect(saved['codeVerifier'], isNotEmpty);
    expect(saved['state'], isNotEmpty);
  }

  Future<void> _tap(WidgetTester tester, Finder target) async {
    expect(target, findsOneWidget);
    await tester.ensureVisible(target);
    await tester.pump();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await _frames(tester);
  }

  Future<void> setBrand(WidgetTester tester, String next) async {
    await tester.runAsync(() async {
      expect(
        await theme.setBrand(next).timeout(const Duration(seconds: 10)),
        isTrue,
      );
    });
    await tester.pump();
    // NEW2361: cross the 200 ms root and descendant theme transitions.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> setLocale(WidgetTester tester, AppLocale next) async {
    await tester.runAsync(
      () => locale.setLocale(next).timeout(const Duration(seconds: 10)),
    );
    await tester.pump();
  }

  List<String> labels() => switch (kind) {
    _Case.oauthCopy => [NotificationUiCopy.authUrlCopied],
    _Case.oauthOpenFailure => [NotificationUiCopy.openAuthFailed],
    _Case.locationSettings => [
      NotificationUiCopy.formatLocationPermissionMessage(
        '需要在系统设置中允许始终访问位置，后台地理围栏才能触发',
      ),
      NotificationUiCopy.toSettingsAction,
    ],
    _Case.oauthMenu => [
      NotificationUiCopy.isEn ? 'Pause' : '暂停',
      NotificationUiCopy.menuSync,
      NotificationUiCopy.menuDelete,
    ],
    _Case.icsMenu => [
      NotificationUiCopy.isEn ? 'Pause' : '暂停',
      NotificationUiCopy.isEn ? 'Refresh' : '刷新',
      NotificationUiCopy.menuDelete,
    ],
  };
  Map<String, Object?> operations() => {
    'pendingSaves': calendar.pending.length,
    'clipboardWrites': clipboard.length,
    'launcherCalls': launcher.urls.length,
    'permissions': permissionRequests,
    'permissionChecks': permissionChecks,
    'settingsOpens': settingsOpens,
    'geofenceSyncs': geofenceSyncs,
    'icsActions': calendar.icsActions.length,
    'oauthActions': calendar.oauthActions.length,
    'syncCalls': calendar.syncCalls,
  };
  Map<String, Object?> authority() => {
    'providerIdentity': identityHashCode(calendar),
    'lifetime': calendar.icsLifetimeGeneration,
    'sourceRevision': IcsSubscriptionStorage.sourceRevision(_icsId),
    'subscriptionRows': calendar.subscriptions
        .map((row) => row.toJson())
        .toList(),
    'oauthRows': calendar.oauthAccounts
        .map(
          (row) => {
            'id': row.id,
            'enabled': row.enabled,
            'displayName': row.displayName,
            'clientId': row.clientId,
            'calendarId': row.calendarId,
          },
        )
        .toList(),
    'pendingDrafts': calendar.pending.map(Map<String, String>.from).toList(),
    'clipboard': List<String>.from(clipboard),
    'launcherUris': List<String>.from(launcher.urls),
    'accountBoundaryActive': AccountPreferenceWrites.isBoundaryActive,
  };
  List<Map<String, Object?>> drafts(WidgetTester tester) => [
    for (final field in tester.widgetList<TextField>(find.byType(TextField)))
      {
        'controllerIdentity': identityHashCode(field.controller),
        'text': field.controller?.text,
        'base': field.controller?.selection.baseOffset,
        'extent': field.controller?.selection.extentOffset,
      },
  ];
  List<Map<String, Object?>> scrollPositions(WidgetTester tester) => [
    for (final state in tester.stateList<ScrollableState>(
      find.byType(Scrollable),
    ))
      {
        'identity': identityHashCode(state),
        'pixels': state.position.pixels,
        'min': state.position.minScrollExtent,
        'max': state.position.maxScrollExtent,
      },
  ];

  Map<String, Object?> _themeEvidence2361(WidgetTester tester) {
    final target = _themeSnapshot2361(theme.brand.theme);
    final errors = <String>[];
    Map<String, Object?> observe(String role, ThemeData Function() read) {
      try {
        return _themeSnapshot2361(read());
      } catch (error) {
        errors.add('$role: $error');
        return {'observationError': '$error'};
      }
    }
    final root = observe('root', () => Theme.of(
      tester.element(find.byKey(_captureKey)),
    ));
    final live = observe('live', () => Theme.of(screenElement!));
    final items = find.byType(PopupMenuItem<String>).evaluate().toList();
    final menu = isMenu && items.isNotEmpty
        ? observe('menu', () => Theme.of(items.first))
        : null;
    Element? materialElement;
    if (items.isNotEmpty) {
      items.first.visitAncestorElements((element) {
        if (element.widget is Material) { materialElement = element; return false; }
        return true;
      });
    }
    final material = materialElement?.widget as Material?;
    final materialTheme = materialElement == null ? null
        : observe('menuMaterial', () => Theme.of(materialElement!));
    final targetTheme = theme.brand.theme;
    final expectedMenuColor = targetTheme.popupMenuTheme.color ??
        (targetTheme.useMaterial3 ? targetTheme.colorScheme.surfaceContainer
            : targetTheme.colorScheme.surface);
    bool matches(Map<String, Object?> actual) =>
        jsonEncode(actual) == jsonEncode(target);
    return {
      'providerBrand': theme.brand.id,
      'targetBrandTheme': target,
      'root': root,
      'live': live,
      'menu': menu,
      'rootMatchesCurrentBrand': matches(root),
      'liveMatchesCurrentBrand': matches(live),
      'menuMatchesCurrentBrand': menu == null ? null : matches(menu),
      'menuMaterialTheme': materialTheme,
      'menuMaterialColor': material?.color?.toARGB32(),
      'expectedMenuMaterialColor': expectedMenuColor.toARGB32(),
      'menuMaterialThemeMatchesCurrentBrand': materialTheme == null ? null : matches(materialTheme),
      'menuMaterialColorMatchesCurrentBrand': material == null ? null
          : material.color == expectedMenuColor,
      'menuThemeAcceptance': false, // Raw evidence; assertions occur after persistence.
      'menuThemeContract': 'Current live brand Theme and actual menu Material; no captured-theme exception.',
      'observationErrors': errors,
      'comparisonScope': 'Selected Theme colors and AppSurfaceStyle only; '
          'local text/control copies are not whole-ThemeData equality.',
    };
  }

  Future<Map<String, Object?>> capture(
    WidgetTester tester,
    String phase, {
    required List<String> openingLabels,
    required List<String> expectedLabels,
    required Map<String, Object?> openingAuthority,
    required List<Map<String, Object?>> openingScrollPositions,
  }) async {
    final scope = isMenu
        ? find.byType(PopupMenuItem<String>)
        : find.byType(SnackBar);
    final paragraphs = <Map<String, Object?>>[];
    final viewport = Offset.zero & size;
    final dialogSurfaces = _opaqueDialogSurfaces329(tester);
    for (final element
        in find
            .descendant(of: scope, matching: find.byType(RichText))
            .evaluate()) {
      final render = element.findRenderObject();
      if (render is! RenderParagraph || !render.hasSize) continue;
      final rect = MatrixUtils.transformRect(
        render.getTransformTo(null),
        Offset.zero & render.size,
      );
      final paint = _paragraphPaint349(render);
      final occlusion = _occlusion329(element, render, dialogSurfaces);
      final layoutComplete =
          !render.didExceedMaxLines &&
          render.textSize.width <= render.size.width + .1 &&
          render.textSize.height <= render.size.height + .1 &&
          viewport.inflate(.1).contains(rect.topLeft) &&
          viewport.inflate(.1).contains(rect.bottomRight);
      final complete =
          layoutComplete &&
          paint['fullyPainted'] == true &&
          occlusion['occluded'] == false &&
          occlusion['orderingUnresolved'] == false;
      paragraphs.add({
        'text': render.text.toPlainText(),
        'rect': [rect.left, rect.top, rect.width, rect.height],
        'textSize': [render.textSize.width, render.textSize.height],
        'maxLines': render.maxLines,
        'didExceedMaxLines': render.didExceedMaxLines,
        'complete': complete,
        'layoutComplete': layoutComplete,
        'occlusion': occlusion,
        'effectivePaint': paint,
        'transform': render.getTransformTo(null).storage.toList(),
      });
    }
    final shown = paragraphs.map((row) => row['text'] as String).toList();
    if (isMenu && expectedLabels.isNotEmpty) {
      observeNativeMenu(tester, 'retained-$phase', true);
    }
    final record = <String, Object?>{
      'case': id,
      'phase': phase,
      'strict': _strict,
      'scope':
          'Flutter real IntegrationsScreen; synthetic platform/OAuth boundary',
      'brand': theme.brand.id,
      'themeEvidence2361': _themeEvidence2361(tester),
      'locale': I18n.current.name,
      'viewport': [size.width, size.height],
      'textScale': scale,
      'openingLabels': openingLabels,
      'expectedLabels': expectedLabels,
      'shownText': shown,
      'paragraphs': paragraphs,
      'visibilityOracle':
          '329 opaque Dialog Material surface / render order / glyph intersection',
      'visibleCompleteText': paragraphs
          .where((row) => row['complete'] == true)
          .map((row) => row['text'])
          .toList(),
      'staleExpectedLabels': expectedLabels
          .where((text) => !shown.contains(text))
          .toList(),
      'operations': operations(),
      'drafts': drafts(tester),
      'openingScrollPositions': openingScrollPositions,
      'scrollPositions': scrollPositions(tester),
      'openingAuthority': openingAuthority,
      'currentAuthority': authority(),
      'storeWriteKeys': List<String>.from(store.writeKeys),
      'overlayCount': scope.evaluate().length,
      'snackBarAction': kind == _Case.locationSettings
          ? nativeActionEvidence(tester) : null,
      'nativeMenuLifecycle': List<Map<String, Object?>>.from(nativeMenuObservations),
      'menuCancellationPreserved': menuCancellationPreserved,
      'icsActionCalls': calendar.icsActions
          .map(Map<String, Object?>.from)
          .toList(),
      'oauthActionCalls': calendar.oauthActions
          .map(Map<String, Object?>.from)
          .toList(),
      'routeIdentity': screenElement == null
          ? null
          : identityHashCode(ModalRoute.of(screenElement!)),
      'navigatorRoutes': observer.routes
          .map(
            (route) => {
              'identity': identityHashCode(route),
              'type': route.runtimeType.toString(),
              'active': route.isActive,
              'current': route.isCurrent,
            },
          )
          .toList(),
      'accepted': false,
    };
    final directory = _outputDirectory();
    if (directory != null) {
      await tester.runAsync(() async {
        final destination = Directory('${directory.path}/$id');
        await destination.create(recursive: true);
        final png = File('${destination.path}/$phase.png');
        final metadata = File('${destination.path}/$phase.json');
        if (await png.exists() || await metadata.exists()) {
          throw StateError('Refusing to overwrite evidence: ${png.path}');
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_captureKey),
        );
        final picture = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (bytes == null) throw StateError('No PNG data');
          await png.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
          record['screenshot'] = png.path;
          await metadata.writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(record)}\n',
            flush: true,
          );
        } finally {
          picture.dispose();
        }
      });
    }
    // NEW2361: original PNG and JSON are retained before these new checks.
    final themeEvidence = record['themeEvidence2361']! as Map<String, Object?>;
    expect(themeEvidence['rootMatchesCurrentBrand'], isTrue,
      reason: '$id/$phase settled root Theme must match the current brand');
    expect(themeEvidence['liveMatchesCurrentBrand'], isTrue,
      reason: '$id/$phase settled live Theme must match the current brand');
    if (isMenu) {
      expect(menuCancellationPreserved, isTrue,
        reason: '$id/$phase native cancellation preserves authority and all business counters');
      for (final observation in nativeMenuObservations) {
        expect(observation['expandedMatches'], isTrue,
          reason: '$id/$phase actual native expanded lifecycle: $observation');
        expect(observation['elementRetained'], isTrue);
        expect(observation['stateRetained'], isTrue);
      }
      if (expectedLabels.isNotEmpty) {
        expect(themeEvidence['menuMatchesCurrentBrand'], isTrue,
          reason: '$id/$phase retained menu Theme matches the current live brand');
        expect(themeEvidence['menuMaterialThemeMatchesCurrentBrand'], isTrue,
          reason: '$id/$phase actual menu Material Theme is live');
        expect(themeEvidence['menuMaterialColorMatchesCurrentBrand'], isTrue,
          reason: '$id/$phase actual menu Material color is current-brand color');
      }
    }
    if (kind == _Case.locationSettings && expectedLabels.isNotEmpty) {
      final action = record['snackBarAction']! as Map<String, Object?>;
      expect(action['snackCount'], 1);
      expect(action['nativeActionCount'], 1);
      expect(action['exactNativeType'], isTrue);
      expect(action['label'], NotificationUiCopy.toSettingsAction);
      expect(action['elementRetained'], isTrue);
      expect(action['stateRetained'], isTrue);
      expect(action['callbackRetained'], isTrue);
      expect(action['persistent'], isTrue);
    }
    if (kind == _Case.locationSettings && expectedLabels.isEmpty) {
      expect(find.byType(SnackBar), findsNothing,
        reason: '$id/$phase real native Settings tap hides the retained feedback');
    }
    return record;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(_permissionChannel, null);
    messenger.setMockMethodCallHandler(_geofenceChannel, null);
    UrlLauncherPlatform.instance = previousLauncher;
    theme.dispose();
    locale.dispose();
    calendar.dispose();
    locations.dispose();
    notifications.dispose();
    tester.view.reset();
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previousStore;
  }
}

Directory? _outputDirectory() {
  final raw = Platform.environment['DUOYI_INTEGRATIONS_CAPTURE_DIR'];
  if (raw == null || raw.isEmpty) return null;
  final path = raw.startsWith('/') ? raw : '${Directory.current.path}/$raw';
  final roots = [
    '${Directory.current.path}/evidence/',
    '/home/ubuntu/duoyi/evidence/',
  ];
  if (!roots.any((root) => path.startsWith(root) && path != root) ||
      path.split('/').contains('..')) {
    throw StateError(
      'Capture directory must be a named child of workspace evidence/',
    );
  }
  return Directory(path);
}

class _Observer extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }
}

class _Store extends InMemorySharedPreferencesStore {
  _Store(String brand, AppLocale locale, bool seedIcs)
    : super.withData({
        'flutter.active_brand': brand,
        'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        'flutter.duoyi_locale_v1': locale.storageValue,
        if (seedIcs)
          'flutter.${IcsSubscriptionStorage.subscriptionsKey}': jsonEncode([
            const IcsSubscription(
              id: _icsId,
              name: _icsName,
              url: 'https://fixture.invalid/calendar-262.ics',
            ).toJson(),
          ]),
      });
  final writeKeys = <String>[];
  @override
  Future<bool> setValue(String type, String key, Object value) {
    writeKeys.add(key);
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) {
    writeKeys.add(key);
    return super.remove(key);
  }
}

class _Calendar extends CalendarSyncProvider {
  final pending = <Map<String, String>>[];
  final oauthActions = <Map<String, Object?>>[];
  final icsActions = <Map<String, Object?>>[];
  int syncCalls = 0;
  final _account = OAuthCalendarAccount(
    id: 'fixture-oauth-262',
    provider: OAuthCalendarProvider.google,
    displayName: _literalName,
    clientId: _clientId,
    redirectUri: 'duoyi://oauth/calendar',
    accessToken: 'fixture-access',
    refreshToken: 'fixture-refresh',
    expiresAt: DateTime.utc(2030),
  );
  @override
  List<OAuthCalendarAccount> get oauthAccounts => [_account];
  @override
  Future<Map<String, String>> savePendingOAuthAuthorization({
    required OAuthCalendarProvider provider,
    required String displayName,
    required String clientId,
    required String clientSecret,
    required String redirectUri,
    required String calendarId,
    required String codeVerifier,
    required String state,
    bool Function()? isCurrent,
    String? expectedAttemptId,
    bool requireExpectedAttempt = false,
  }) async {
    pending.add({
      'provider': provider.name,
      'displayName': displayName,
      'clientId': clientId,
      'clientSecret': clientSecret,
      'redirectUri': redirectUri,
      'calendarId': calendarId,
      'codeVerifier': codeVerifier,
      'state': state,
    });
    return Map<String, String>.from(pending.last);
  }

  @override
  Future<void> updateOAuthAccount(
    OAuthCalendarAccount account, {
    bool Function()? isCurrent,
  }) async {
    oauthActions.add({'id': account.id, 'enabled': account.enabled});
  }

  @override
  Future<void> updateSubscription(
    IcsSubscription sub, {
    bool Function()? isCurrent,
  }) async {
    icsActions.add({
      'id': sub.id,
      'enabled': sub.enabled,
      'authorityAtCall': isCurrent?.call(),
    });
    await super.updateSubscription(sub, isCurrent: isCurrent);
  }

  @override
  Future<void> syncAll({bool Function()? isCurrent}) async {
    syncCalls++;
  }
}

class _Launcher extends UrlLauncherPlatform {
  final urls = <String>[];
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    return false;
  }
}

Map<String, Object?> _themeSnapshot2361(ThemeData data) {
  final colors = data.colorScheme;
  final surface = data.extension<AppSurfaceStyle>();
  Map<String, Object?> side(BorderSide value) => {
    'colorARGB': value.color.toARGB32(),
    'width': value.width,
    'style': value.style.name,
    'strokeAlign': value.strokeAlign,
  };
  return {
    'brightness': data.brightness.name,
    'colorScheme': {
      'brightness': colors.brightness.name,
      'primaryARGB': colors.primary.toARGB32(),
      'onPrimaryARGB': colors.onPrimary.toARGB32(),
      'secondaryARGB': colors.secondary.toARGB32(),
      'onSecondaryARGB': colors.onSecondary.toARGB32(),
      'surfaceARGB': colors.surface.toARGB32(),
      'onSurfaceARGB': colors.onSurface.toARGB32(),
      'onSurfaceVariantARGB': colors.onSurfaceVariant.toARGB32(),
      'outlineARGB': colors.outline.toARGB32(),
      'errorARGB': colors.error.toARGB32(),
      'onErrorARGB': colors.onError.toARGB32(),
      'shadowARGB': colors.shadow.toARGB32(),
      'scrimARGB': colors.scrim.toARGB32(),
    },
    'scaffoldBackgroundARGB': data.scaffoldBackgroundColor.toARGB32(),
    'canvasARGB': data.canvasColor.toARGB32(),
    'cardARGB': data.cardColor.toARGB32(),
    'dividerARGB': data.dividerColor.toARGB32(),
    'AppSurfaceStyle': surface == null ? null : {
      'cardRadius': surface.cardRadius,
      'smallTileRadius': surface.smallTileRadius,
      'cardFillARGB': surface.cardFillColor?.toARGB32(),
      'cardBorder': surface.cardBorder == null ? null : {
        'top': side(surface.cardBorder!.top),
        'right': side(surface.cardBorder!.right),
        'bottom': side(surface.cardBorder!.bottom),
        'left': side(surface.cardBorder!.left),
      },
      'cardShadow': [
        for (final shadow in surface.cardShadow) {
          'colorARGB': shadow.color.toARGB32(),
          'offset': [shadow.offset.dx, shadow.offset.dy],
          'blurRadius': shadow.blurRadius,
          'spreadRadius': shadow.spreadRadius,
          'blurStyle': shadow.blurStyle.name,
        },
      ],
      'sheetTopRadius': surface.sheetTopRadius,
      'navBarBlurSigma': surface.navBarBlurSigma,
    },
  };
}

