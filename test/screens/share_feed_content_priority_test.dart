// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/share_ui_copy.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/share_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart'
    show AppModalSheet, AppSurfaceCard;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/rendered_control_contrast.dart';
import '../support/weekly_review_screenshot_font.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int writeCount = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    writeCount++;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    writeCount++;
    return super.remove(key);
  }
}

Future<int> _boundedPumpAndSettle(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 50),
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  Duration timeout = const Duration(seconds: 3),
}) {
  return tester.pumpAndSettle(duration, phase, timeout);
}

Future<void> _drainAccountWrites(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 3),
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

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
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
      final file = File('$resolvedDir/share-feed-readable-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _assertControl44(WidgetTester tester, Finder finder, String description) {
  expect(finder, findsOneWidget, reason: description);
  expectControlTouchTarget(tester, finder);
}

Future<void> _assertReadableParagraph(
  WidgetTester tester, {
  required Finder textFinder,
  required GlobalKey boundaryKey,
  required String role,
  Finder? surfaceFinder,
  Finder? scrollableFinder,
  Finder? clipContainerFinder,
  bool assertWordContinuity = false,
}) async {
  expect(textFinder, findsOneWidget, reason: '$role must exist');
  final element = tester.element(textFinder);
  final rich = find.descendant(of: textFinder, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(rich);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role must not truncate',
  );
  final text = paragraph.text.toPlainText();
  expect(text.trim(), isNotEmpty);

  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  Rect boundsOf(RenderBox box) => MatrixUtils.transformRect(
    box.getTransformTo(boundary),
    Offset.zero & box.size,
  );

  // 1. Locate the true vertical ScrollableState in the element's ancestor chain.
  // Avoid finding un-scoped sibling/child scrollables (e.g. TextField's internal scrollable).
  ScrollableState? scrollable;
  if (scrollableFinder != null) {
    final scopedScrollable = find.ancestor(
      of: textFinder,
      matching: scrollableFinder,
    );
    for (final elem in scopedScrollable.evaluate()) {
      if (elem is StatefulElement && elem.state is ScrollableState) {
        final state = elem.state as ScrollableState;
        if (state.position.axis == Axis.vertical) {
          scrollable = state;
          break;
        }
      }
    }
  }
  if (scrollable == null) {
    ScrollableState? firstVertical;
    element.visitAncestorElements((ancestor) {
      if (ancestor is StatefulElement && ancestor.state is ScrollableState) {
        final state = ancestor.state as ScrollableState;
        if (state.position.axis == Axis.vertical) {
          firstVertical ??= state;
          if (state.position.maxScrollExtent > state.position.minScrollExtent) {
            scrollable = state;
            return false;
          }
        }
      }
      return true;
    });
    scrollable ??= firstVertical;
  }

  // Ensure text is initially visible within the true vertical scrollable
  if (scrollable != null) {
    await Scrollable.ensureVisible(
      element,
      alignment: 0.5,
    );
    await _boundedPumpAndSettle(tester);
  }

  // 2. Compute the FIXED visible clip: screen ∩ surface ∩ viewport.
  // Viewport/surface geometries are fixed in boundary coordinates.
  final screen = Offset.zero & boundary.size;
  var clip = screen;

  // Locate the true ancestor surface box (e.g. AppModalSheet / AppSurfaceCard / Dialog).
  RenderBox? surfaceBox;
  if (surfaceFinder != null) {
    final scopedSurface = find.ancestor(
      of: textFinder,
      matching: surfaceFinder,
    );
    if (scopedSurface.evaluate().isNotEmpty) {
      final ro = tester.renderObject(scopedSurface);
      if (ro is RenderBox) {
        surfaceBox = ro;
      }
    }
  }
  if (surfaceBox == null) {
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is AppModalSheet ||
          ancestor.widget is AppSurfaceCard ||
          ancestor.widget is Dialog) {
        final ro = ancestor.findRenderObject();
        if (ro is RenderBox) {
          surfaceBox = ro;
          return false;
        }
      }
      return true;
    });
  }
  if (surfaceBox != null) {
    clip = clip.intersect(boundsOf(surfaceBox!));
  }

  // Intersect with all ancestor RenderAbstractViewports in paragraph's render chain.
  // Both RenderViewport (ListView) and _RenderSingleChildViewport (SingleChildScrollView)
  // implement RenderAbstractViewport.
  RenderObject? ro = paragraph.parent;
  while (ro != null) {
    if (ro is RenderAbstractViewport && ro is RenderBox) {
      clip = clip.intersect(boundsOf(ro as RenderBox));
    }
    ro = ro.parent;
  }

  if (clipContainerFinder != null) {
    final scopedContainer = find.ancestor(
      of: textFinder,
      matching: clipContainerFinder,
    );
    if (scopedContainer.evaluate().isNotEmpty) {
      final box = tester.renderObject<RenderBox>(scopedContainer);
      clip = clip.intersect(boundsOf(box));
    }
  }

  // 5. Per-rune glyph layout and visibility inspection.
  // When a glyph box is vertically outside clip, scroll the true vertical scrollable,
  // query updated geometry, and assert inside clip with 0.5 subpixel margin.
  final paragraphScrollable = scrollable;
  var offset = 0;
  for (final rune in text.runes) {
    final glyph = String.fromCharCode(rune);
    final start = offset;
    offset += glyph.length;
    if (glyph.trim().isEmpty) continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: offset),
    );
    expect(boxes, isNotEmpty, reason: '$role $glyph missing layout box');
    for (final box in boxes) {
      if (paragraphScrollable != null) {
        final glyphRect = MatrixUtils.transformRect(
          paragraph.getTransformTo(boundary),
          Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
        );
        if (glyphRect.top < clip.top || glyphRect.bottom > clip.bottom) {
          final delta = glyphRect.center.dy - clip.center.dy;
          final p = paragraphScrollable.position;
          final target = (p.pixels + delta).clamp(
            p.minScrollExtent,
            p.maxScrollExtent,
          );
          if ((target - p.pixels).abs() > 0.01) {
            p.jumpTo(target);
            await tester.pump(const Duration(milliseconds: 20));
          }
        }
      }

      final glyphRect = MatrixUtils.transformRect(
        paragraph.getTransformTo(boundary),
        Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
      );
      expect(
        clip.inflate(0.5).contains(glyphRect.topLeft),
        isTrue,
        reason: '$role $glyph top-left $glyphRect outside clip $clip',
      );
      expect(
        clip.inflate(0.5).contains(glyphRect.bottomRight),
        isTrue,
        reason: '$role $glyph bottom-right $glyphRect outside clip $clip',
      );
    }
  }

  if (assertWordContinuity) {
    for (final word in RegExp(
      r"[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)*",
    ).allMatches(text)) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: word.start, extentOffset: word.end),
      );
      expect(boxes, isNotEmpty);
      expect(
        boxes.map((box) => box.top.round()).toSet(),
        hasLength(1),
        reason: '$role word ${word.group(0)} must remain intact',
      );
    }
  }
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _enWorkspaceName =
    'Infrastructure Architecture and Cross-Region Cluster Operations Taskforce';
const _enAuthorName = 'Dr. Alexander Bartholomew Montgomery-Sterling III';
const _enSharedFullBody =
    'Reviewing the high-concurrency cross-replica synchronization protocols for distributed transactions under partition constraints. Please verify that all invariants hold across multi-datacenter failover scenarios before signing off on the production release.';
const _enActorName =
    'Lead System Architect and Distributed Consensus Taskforce Director Elizabeth Alexandra Harrington';

const _zhWorkspaceName =
    '跨地域多集群高可用分布式任务协同与统一调度工作区';
const _zhAuthorName = '分布式协作系统高级架构审计专家';
const _zhSharedFullBody =
    '针对高并发分布式多副本同步协议进行全面基准压力测试与合规审查，请确认在跨地域网络分区隔离与异地多活容灾节点漂移场景下，所有分布式事务一致性与状态机顺序不变量均严格满足，并在最终版本归档前由核心架构决策委员会与各协同节点负责人共同完成全量联合数字签名与封版发布确认。';
const _zhActorName =
    '核心架构决策委员会与跨地域集群高可用调度系统首席协调员';

class _ShareFixture {
  final ThemeProvider theme;
  final AuthProvider auth;
  final ShareProvider share;
  final _RecordingPreferencesStore prefsStore;
  final List<http.Request> requests;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey boundaryKey;

  _ShareFixture._({
    required this.theme,
    required this.auth,
    required this.share,
    required this.prefsStore,
    required this.requests,
    required this.navigatorKey,
    required this.boundaryKey,
  });

  static Future<_ShareFixture> create({
    required String initialBrand,
    required AppLocale locale,
  }) async {
    final initialPrefs = <String, Object>{
      'active_brand': initialBrand,
      'theme_shop_state': jsonEncode({
        'activeBrand': initialBrand,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      'flutter.active_brand': initialBrand,
      'flutter.theme_shop_state': jsonEncode({
        'activeBrand': initialBrand,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
      'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    };
    SharedPreferences.setMockInitialValues(initialPrefs);

    final store = _RecordingPreferencesStore({
      for (final entry in initialPrefs.entries)
        if (!entry.key.startsWith('flutter.'))
          'flutter.${entry.key}': entry.value,
    });
    SharedPreferencesStorePlatform.instance = store;

    final isEn = locale == AppLocale.en;
    final workspaceName = isEn ? _enWorkspaceName : _zhWorkspaceName;
    final authorName = isEn ? _enAuthorName : _zhAuthorName;
    final sharedFullBody = isEn ? _enSharedFullBody : _zhSharedFullBody;
    final actorName = isEn ? _enActorName : _zhActorName;

    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-token-feed',
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;

        if (request.method == 'GET' && path == '/api/workspaces') {
          return _json([
            {
              'id': 'space-feed-readable',
              'name': workspaceName,
              'description': 'Feed readable contract test workspace',
              'owner_user_id': 'user-owner',
              'members': [
                {
                  'workspace_id': 'space-feed-readable',
                  'user_id': 'user-owner',
                  'username': 'synthetic-user',
                  'role': 'owner',
                },
                {
                  'workspace_id': 'space-feed-readable',
                  'user_id': 'user-author',
                  'username': authorName,
                  'role': 'editor',
                },
              ],
            },
          ]);
        }

        // Mention contract per backend/main.py _workspace_mention_to_dict:
        // m.comment_id points to wc.id, and body is identical to wc.body.
        if (request.method == 'GET' && path == '/api/workspaces/mentions') {
          return _json([
            {
              'id': 101,
              'workspace_id': 'space-feed-readable',
              'workspace_name': workspaceName,
              'comment_id': 'comment-shared-1',
              'target_id': 'target-consensus-1',
              'author_user_id': 'user-author',
              'author_name': authorName,
              'body': sharedFullBody,
              'read_at': null,
              'created_at': DateTime(2026, 10, 24, 9, 30).toIso8601String(),
            },
          ]);
        }

        if (request.method == 'POST' &&
            path.startsWith('/api/workspaces/mentions/') &&
            path.endsWith('/read')) {
          return _json({'status': 'ok'});
        }

        // Collaboration comments return the exact same comment_id & sharedFullBody
        if (request.method == 'GET' &&
            path == '/api/workspaces/space-feed-readable/comments') {
          return _json([
            {
              'id': 'comment-shared-1',
              'workspace_id': 'space-feed-readable',
              'target_id': 'target-consensus-1',
              'author_user_id': 'user-author',
              'author_name': authorName,
              'body': sharedFullBody,
              'created_at': DateTime(2026, 10, 24, 9, 30).toIso8601String(),
            },
          ]);
        }

        if (request.method == 'GET' &&
            path == '/api/workspaces/space-feed-readable/activities') {
          return _json([
            {
              'id': 201,
              'workspace_id': 'space-feed-readable',
              'actor_user_id': 'user-author',
              'actor_name': actorName,
              'action': 'workspace.create',
              'detail': 'Workspace initialization',
              'created_at': DateTime(2026, 10, 24, 9, 15).toIso8601String(),
            },
          ]);
        }

        if (request.method == 'GET' &&
            path == '/api/workspaces/space-feed-readable/leaderboard') {
          return _json([]);
        }

        return _json(request.method == 'GET' ? [] : {});
      }),
    );

    final auth = AuthProvider(
      client: client,
      initialState: const AuthState(
        userId: 'user-owner',
        username: 'synthetic-user',
        token: 'synthetic-token-feed',
      ),
    );

    final share =
        ShareProvider()
          ..apiClientGetter = (() => auth.client)
          ..userIdGetter = (() => auth.state.userId);

    final theme = ThemeProvider();
    await theme.loadFromStorage();

    return _ShareFixture._(
      theme: theme,
      auth: auth,
      share: share,
      prefsStore: store,
      requests: requests,
      navigatorKey: GlobalKey<NavigatorState>(),
      boundaryKey: GlobalKey(),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required double scale,
    required AppLocale locale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    I18n.setLocale(locale);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ShareProvider>.value(value: share),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: Consumer<ThemeProvider>(
          builder:
              (context, currentTheme, _) => ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder:
                    (context, currentLocale, _) => MaterialApp(
                      navigatorKey: navigatorKey,
                      debugShowCheckedModeBanner: false,
                      locale: Locale(
                        currentLocale == AppLocale.en ? 'en' : 'zh',
                      ),
                      supportedLocales: const [Locale('en'), Locale('zh')],
                      localizationsDelegates:
                          GlobalMaterialLocalizations.delegates,
                      theme: currentTheme.brand.theme,
                      builder:
                          (context, child) => MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              size: size,
                              textScaler: TextScaler.linear(scale),
                            ),
                            child: RepaintBoundary(
                              key: boundaryKey,
                              child: child!,
                            ),
                          ),
                      home: const BrandRouteSurface(child: ShareScreen()),
                    ),
              ),
        ),
      ),
    );

    await _boundedPumpAndSettle(tester);
    if (share.loading) {
      await tester.pump(const Duration(milliseconds: 50));
      await _boundedPumpAndSettle(tester);
    }
  }

  void dispose() {
    share.dispose();
    auth.dispose();
    theme.dispose();
  }
}

class _ShareFeedPriorityScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final String targetBrand;
  final Size size;
  final double scale;

  const _ShareFeedPriorityScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.size,
    required this.scale,
  });
}

const _scenarios = <_ShareFeedPriorityScenario>[
  _ShareFeedPriorityScenario(
    name: 'zh-portrait-320x844-scale2-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    scale: 2.0,
  ),
  _ShareFeedPriorityScenario(
    name: 'en-portrait-320x844-scale2-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(320, 844),
    scale: 2.0,
  ),
  _ShareFeedPriorityScenario(
    name: 'zh-landscape-844x390-scale1-liquidGlass',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(844, 390),
    scale: 1.0,
  ),
  _ShareFeedPriorityScenario(
    name: 'en-landscape-844x390-scale1-defaultBrand',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(844, 390),
    scale: 1.0,
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;

  setUpAll(() async {
    await loadWeeklyReviewScreenshotFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'ShareScreen mention inbox preserves summary, satisfies 44dp View action, and navigates to full comment and activity: ${scenario.name}',
      (tester) async {
        final fixture = await _ShareFixture.create(
          initialBrand: scenario.initialBrand,
          locale: scenario.initialLocale,
        );
        addTearDown(fixture.dispose);

        await fixture.pump(
          tester,
          size: scenario.size,
          scale: scenario.scale,
          locale: scenario.initialLocale,
        );

        final baselineWrites = fixture.prefsStore.writeCount;
        final isEn = scenario.initialLocale == AppLocale.en;
        final workspaceName = isEn ? _enWorkspaceName : _zhWorkspaceName;
        final sharedFullBody = isEn ? _enSharedFullBody : _zhSharedFullBody;
        final actorName = isEn ? _enActorName : _zhActorName;

        // 1. Open mention inbox sheet via AppBar button with correct tooltip signature:
        // ShareUiCopy.mentionInboxTooltip(int unreadCount, [AppLocale? locale])
        final unreadCount = fixture.share.unreadMentionCount;
        expect(unreadCount, 1, reason: 'Initial unread mention count must be 1');
        final inboxTooltip = ShareUiCopy.mentionInboxTooltip(
          unreadCount,
          scenario.initialLocale,
        );
        final inboxButtonFinder = find.byTooltip(inboxTooltip);
        expect(inboxButtonFinder, findsOneWidget);
        await tester.tap(inboxButtonFinder);
        await _boundedPumpAndSettle(tester);

        final expectedInboxTitle =
            isEn ? ShareUiCopy.mentionInboxTitle(scenario.initialLocale) : '@ 提及';
        expect(find.text(expectedInboxTitle), findsOneWidget);

        // 2. Mention Tile View Button: verify real 44dp touch target
        final viewButtonFinder = find.widgetWithText(
          FilledButton,
          ShareUiCopy.actionView(scenario.initialLocale),
        );
        _assertControl44(
          tester,
          viewButtonFinder,
          'Mention View button must meet 44dp touch target',
        );

        // 3. Mention Tile Title (Body): verify full body readability without truncation
        // using the exact shared full body text
        final mentionBodyFinder = find.text(sharedFullBody);
        expect(mentionBodyFinder, findsOneWidget);
        await _assertReadableParagraph(
          tester,
          textFinder: mentionBodyFinder,
          boundaryKey: fixture.boundaryKey,
          role: 'Mention full body',
        );

        // 4. Mention Tile Subtitle (Metadata): verify natural wrapping without truncation
        // Limit search strictly to the specific mention tile owning the View action
        // to avoid ambiguity with the background workspace card title
        final mentionTileFinder = find.ancestor(
          of: viewButtonFinder,
          matching: find.byType(ListTile),
        );
        expect(mentionTileFinder, findsOneWidget);
        final subtitleFinder = find.descendant(
          of: mentionTileFinder,
          matching: find.textContaining(workspaceName),
        );
        expect(subtitleFinder, findsOneWidget);
        await _assertReadableParagraph(
          tester,
          textFinder: subtitleFinder,
          boundaryKey: fixture.boundaryKey,
          role: 'Mention metadata subtitle',
        );

        // Verify zero writes occurred during inbox viewing
        expect(
          fixture.prefsStore.writeCount,
          equals(baselineWrites),
          reason: 'Viewing mention inbox must cause 0 preference writes',
        );

        // 5. Tap View button: unread -> open with server guards
        await tester.ensureVisible(viewButtonFinder);
        await _boundedPumpAndSettle(tester);
        expect(viewButtonFinder.hitTestable(), findsOneWidget);
        await tester.tap(viewButtonFinder);
        await _boundedPumpAndSettle(tester);

        // Verify single mutating network request occurred (markMentionRead)
        final mutations = fixture.requests
            .where((r) => r.method != 'GET')
            .toList();
        expect(
          mutations,
          hasLength(1),
          reason: 'Only markMentionRead POST mutation is permitted',
        );
        expect(
          mutations.single.url.path,
          '/api/workspaces/mentions/101/read',
          reason: 'Only markMentionRead POST mutation is permitted',
        );

        final expectedCollabTitle = ShareUiCopy.collaborationSheetTitle(
          workspaceName,
          scenario.initialLocale,
        );
        expect(find.text(expectedCollabTitle), findsOneWidget);

        // 6. Comment Tile: comment全文 for the EXACT SAME comment_id and sharedFullBody
        // Confirm every non-whitespace rune is fully visible in surface ∩ viewport
        final collabSheetFinder = find.byType(AppModalSheet).last;
        final commentBodyFinder = find.descendant(
          of: collabSheetFinder,
          matching: find.text(sharedFullBody),
        );
        await _assertReadableParagraph(
          tester,
          textFinder: commentBodyFinder.first,
          boundaryKey: fixture.boundaryKey,
          role: 'Same comment_id full body in collaboration sheet',
          assertWordContinuity: isEn,
        );

        // 7. Activity Tile: activity长标题 (long title without truncation)
        final activityTitleFinder = find.descendant(
          of: collabSheetFinder,
          matching: find.textContaining(actorName),
        );
        await _assertReadableParagraph(
          tester,
          textFinder: activityTitleFinder,
          boundaryKey: fixture.boundaryKey,
          role: 'Activity long title',
          assertWordContinuity: isEn,
        );

        // 8. Theme / Locale Roundtrip:
        // Assert same route / element / provider and untranslated content preservation
        final initialSheetElement = tester.element(collabSheetFinder);
        final initialSheetRoute = ModalRoute.of(initialSheetElement);
        final initialProvider = fixture.share;

        // Phase 8.1: Switch to alternateLocale and targetBrand via setBrand (returning Future<bool>)
        I18n.setLocale(scenario.alternateLocale);
        await _boundedPumpAndSettle(tester);

        final altIsEn = scenario.alternateLocale == AppLocale.en;
        final altCollabTitle = ShareUiCopy.collaborationSheetTitle(
          workspaceName,
          scenario.alternateLocale,
        );
        expect(find.text(altCollabTitle), findsOneWidget);

        final writesBeforeBrand1 = fixture.prefsStore.writeCount;
        await tester.runAsync(() async {
          final switched = await fixture.theme.setBrand(scenario.targetBrand);
          expect(switched, isTrue, reason: 'setBrand must return true on success');
        });
        await _boundedPumpAndSettle(tester);
        final writesDelta1 = fixture.prefsStore.writeCount - writesBeforeBrand1;
        expect(writesDelta1, greaterThan(0), reason: 'setBrand must record intentional writes');

        // Verify route, element, provider, and untranslated full body preserved
        expect(
          tester.element(find.byType(AppModalSheet).last),
          same(initialSheetElement),
          reason: 'Collaboration sheet element must be retained across theme switch',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppModalSheet).last)),
          same(initialSheetRoute),
          reason: 'Collaboration sheet route must remain current across theme switch',
        );
        expect(
          fixture.share,
          same(initialProvider),
          reason: 'ShareProvider instance must be retained',
        );
        expect(
          find.text(sharedFullBody),
          findsAtLeastNWidgets(1),
          reason: 'User comment body must not be translated by locale changes',
        );

        await _assertReadableParagraph(
          tester,
          textFinder: find.descendant(
            of: find.byType(AppModalSheet).last,
            matching: find.text(sharedFullBody),
          ).first,
          boundaryKey: fixture.boundaryKey,
          role: 'Comment full text after theme switch',
          assertWordContinuity: altIsEn,
        );
        await _assertReadableParagraph(
          tester,
          textFinder: find.descendant(
            of: find.byType(AppModalSheet).last,
            matching: find.textContaining(actorName),
          ),
          boundaryKey: fixture.boundaryKey,
          role: 'Activity long title after theme switch',
          assertWordContinuity: altIsEn,
        );

        // Phase 8.2: Roundtrip back to initialBrand and initialLocale
        final writesBeforeBrand2 = fixture.prefsStore.writeCount;
        await tester.runAsync(() async {
          final reverted = await fixture.theme.setBrand(scenario.initialBrand);
          expect(reverted, isTrue, reason: 'setBrand must return true on revert');
        });
        await _boundedPumpAndSettle(tester);
        final writesDelta2 = fixture.prefsStore.writeCount - writesBeforeBrand2;
        expect(writesDelta2, greaterThan(0), reason: 'setBrand revert must record intentional writes');

        I18n.setLocale(scenario.initialLocale);
        await _boundedPumpAndSettle(tester);

        expect(
          tester.element(find.byType(AppModalSheet).last),
          same(initialSheetElement),
          reason: 'Collaboration sheet element must be retained across theme/locale roundtrip',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppModalSheet).last)),
          same(initialSheetRoute),
          reason: 'Collaboration sheet route must remain current across roundtrip',
        );
        expect(
          fixture.share,
          same(initialProvider),
          reason: 'ShareProvider instance must be retained across roundtrip',
        );
        expect(
          find.text(sharedFullBody),
          findsAtLeastNWidgets(1),
          reason: 'User comment body must remain intact after roundtrip',
        );

        await _assertReadableParagraph(
          tester,
          textFinder: find.descendant(
            of: find.byType(AppModalSheet).last,
            matching: find.text(sharedFullBody),
          ).first,
          boundaryKey: fixture.boundaryKey,
          role: 'Comment full text after roundtrip',
          assertWordContinuity: isEn,
        );
        await _assertReadableParagraph(
          tester,
          textFinder: find.descendant(
            of: find.byType(AppModalSheet).last,
            matching: find.textContaining(actorName),
          ),
          boundaryKey: fixture.boundaryKey,
          role: 'Activity long title after roundtrip',
          assertWordContinuity: isEn,
        );

        await _capture(tester, fixture.boundaryKey, scenario.name);

        // 9. Strict zero unexpected writes check:
        // Excluding the exact intentional writes from setBrand, delta must be precisely zero!
        await _drainAccountWrites(tester);
        final totalExpectedWrites = baselineWrites + writesDelta1 + writesDelta2;
        expect(
          fixture.prefsStore.writeCount,
          equals(totalExpectedWrites),
          reason:
              'Excluding intentional setBrand writes, exactly 0 unexpected preference writes must occur',
        );

        // Strict mutation check: only the single markMentionRead POST throughout
        final totalMutations = fixture.requests
            .where((r) => r.method != 'GET')
            .toList();
        expect(
          totalMutations,
          hasLength(1),
          reason: 'Only markMentionRead POST mutation is permitted across the entire test',
        );
      },
    );

    testWidgets(
      'ShareScreen direct workspace collaboration displays comment全文 and activity长标题: ${scenario.name}',
      (tester) async {
        final fixture = await _ShareFixture.create(
          initialBrand: scenario.initialBrand,
          locale: scenario.initialLocale,
        );
        addTearDown(fixture.dispose);

        await fixture.pump(
          tester,
          size: scenario.size,
          scale: scenario.scale,
          locale: scenario.initialLocale,
        );

        final baselineWrites = fixture.prefsStore.writeCount;
        final isEn = scenario.initialLocale == AppLocale.en;
        final workspaceName = isEn ? _enWorkspaceName : _zhWorkspaceName;
        final sharedFullBody = isEn ? _enSharedFullBody : _zhSharedFullBody;
        final actorName = isEn ? _enActorName : _zhActorName;

        final collabIconFinder = find.byIcon(Icons.forum_outlined);
        expect(collabIconFinder, findsAtLeastNWidgets(1));
        await tester.tap(collabIconFinder.first);
        await _boundedPumpAndSettle(tester);

        final expectedCollabTitle = ShareUiCopy.collaborationSheetTitle(
          workspaceName,
          scenario.initialLocale,
        );
        expect(find.text(expectedCollabTitle), findsOneWidget);

        final collabSheetFinder = find.byType(AppModalSheet).last;
        await _assertReadableParagraph(
          tester,
          textFinder: find.descendant(
            of: collabSheetFinder,
            matching: find.text(sharedFullBody),
          ).first,
          boundaryKey: fixture.boundaryKey,
          role: 'Direct comment full text',
          assertWordContinuity: isEn,
        );

        await _assertReadableParagraph(
          tester,
          textFinder: find.descendant(
            of: collabSheetFinder,
            matching: find.textContaining(actorName),
          ),
          boundaryKey: fixture.boundaryKey,
          role: 'Direct activity long title',
          assertWordContinuity: isEn,
        );

        await _drainAccountWrites(tester);
        expect(
          fixture.prefsStore.writeCount,
          equals(baselineWrites),
          reason: 'Opening collaboration sheet directly must cause 0 preference writes',
        );
        expect(
          fixture.requests.where((r) => r.method != 'GET'),
          isEmpty,
          reason: 'Direct collaboration inspection must perform 0 mutating requests',
        );
      },
    );
  }
}
