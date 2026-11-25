// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/share_ui_copy.dart';
import 'package:duoyi/models/workspace.dart';
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

import '../support/rendered_control_contrast.dart' show expectControlTouchTarget;
import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart'
    show loadWeeklyReviewScreenshotFonts;

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
      final file = File('$resolvedDir/share-mention-rank-$name.png');
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
    reason: '$role must not truncate (didExceedMaxLines must be false)',
  );
  expect(
    paragraph.maxLines,
    isNull,
    reason: '$role must not restrict maxLines',
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
  final screen = Offset.zero & boundary.size;
  var clip = screen;

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

  // 3. Per-rune glyph layout and visibility inspection.
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
        reason: '$role word ${word.group(0)} must remain intact on a single line',
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
    'Infrastructure Architecture and Distributed Systems Workspace';
const _enAuthorName = 'Auditor Benjamin Harrison';
const _enLongMentionBody =
    'Reviewing the high-concurrency cross-replica synchronization protocols for distributed transactions under partition constraints. Please verify that all invariants hold across multi-datacenter failover scenarios before signing off on the production release.';
const _enLongMentionBody2 =
    'All consensus state machines must be re-evaluated under asymmetric network partitions and packet drop scenarios before final cluster staging certification.';
const _enLeaderboardUsername1 =
    'Dr. Alexander Bartholomew Montgomery-Sterling III';
const _enLeaderboardUsername2 =
    'Lead Systems Architect Elizabeth Alexandra Harrington';

const _zhWorkspaceName =
    '跨地域多集群高可用分布式任务协同工作区';
const _zhAuthorName = '审计专员张华';
const _zhLongMentionBody =
    '针对高并发分布式多副本同步协议进行全面基准压力测试与合规审查，请确认在跨地域网络分区隔离与异地多活容灾节点漂移场景下，所有分布式事务一致性与状态机顺序不变量均严格满足并完成联合签名发布。';
const _zhLongMentionBody2 =
    '请全量校验多集群动态负载均衡与高可用切流策略，在网络不可靠场景下严格保证跨节点状态机单调递增并达成法定多数共识。';
const _zhLeaderboardUsername1 =
    '跨地域分布式系统核心架构与高可用集群高级技术专家';
const _zhLeaderboardUsername2 =
    '多集群调度编排与容灾切流体系首席合规审计工程师';

class _ShareMentionsLeaderboardFixture {
  final ThemeProvider theme;
  final AuthProvider auth;
  final ShareProvider share;
  final _RecordingPreferencesStore prefsStore;
  final List<http.Request> requests;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey boundaryKey;

  _ShareMentionsLeaderboardFixture._({
    required this.theme,
    required this.auth,
    required this.share,
    required this.prefsStore,
    required this.requests,
    required this.navigatorKey,
    required this.boundaryKey,
  });

  static Future<_ShareMentionsLeaderboardFixture> create({
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
    final longMentionBody = isEn ? _enLongMentionBody : _zhLongMentionBody;
    final readMentionBody = isEn ? _enLongMentionBody2 : _zhLongMentionBody2;
    final leaderboardUsername1 =
        isEn ? _enLeaderboardUsername1 : _zhLeaderboardUsername1;
    final leaderboardUsername2 =
        isEn ? _enLeaderboardUsername2 : _zhLeaderboardUsername2;

    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-token-mentions-leaderboard',
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;

        if (request.method == 'GET' && path == '/api/workspaces') {
          return _json([
            {
              'id': 'space-mention-rank-fulltext',
              'name': workspaceName,
              'description': 'Fulltext mention and leaderboard priority workspace',
              'owner_user_id': 'user-owner',
              'members': [
                {
                  'workspace_id': 'space-mention-rank-fulltext',
                  'user_id': 'user-owner',
                  'username': leaderboardUsername1,
                  'role': 'owner',
                },
                {
                  'workspace_id': 'space-mention-rank-fulltext',
                  'user_id': 'user-leader-2',
                  'username': leaderboardUsername2,
                  'role': 'editor',
                },
              ],
            },
          ]);
        }

        if (request.method == 'GET' && path == '/api/workspaces/mentions') {
          return _json([
            {
              'id': 101,
              'workspace_id': 'space-mention-rank-fulltext',
              'workspace_name': workspaceName,
              'comment_id': 'comment-shared-1',
              'target_id': 'target-consensus-1',
              'author_user_id': 'user-author-1',
              'author_name': authorName,
              'body': longMentionBody,
              'read_at': null,
              'created_at': DateTime(2026, 10, 24, 9, 30).toIso8601String(),
            },
            {
              'id': 102,
              'workspace_id': 'space-mention-rank-fulltext',
              'workspace_name': workspaceName,
              'comment_id': 'comment-shared-2',
              'target_id': 'target-consensus-2',
              'author_user_id': 'user-author-2',
              'author_name': leaderboardUsername2,
              'body': readMentionBody,
              'read_at': DateTime(2026, 10, 24, 9, 0).toIso8601String(),
              'created_at': DateTime(2026, 10, 24, 9, 0).toIso8601String(),
            },
          ]);
        }

        if (request.method == 'POST' &&
            path.startsWith('/api/workspaces/mentions/') &&
            path.endsWith('/read')) {
          return _json({'status': 'ok'});
        }

        if (request.method == 'GET' &&
            path == '/api/workspaces/space-mention-rank-fulltext/comments') {
          return _json([
            {
              'id': 'comment-shared-1',
              'workspace_id': 'space-mention-rank-fulltext',
              'target_id': 'target-consensus-1',
              'author_user_id': 'user-author-1',
              'author_name': authorName,
              'body': longMentionBody,
              'created_at': DateTime(2026, 10, 24, 9, 30).toIso8601String(),
            },
            {
              'id': 'comment-shared-2',
              'workspace_id': 'space-mention-rank-fulltext',
              'target_id': 'target-consensus-2',
              'author_user_id': 'user-author-2',
              'author_name': leaderboardUsername2,
              'body': readMentionBody,
              'created_at': DateTime(2026, 10, 24, 9, 0).toIso8601String(),
            },
          ]);
        }

        if (request.method == 'GET' &&
            path == '/api/workspaces/space-mention-rank-fulltext/activities') {
          return _json([
            {
              'id': 201,
              'workspace_id': 'space-mention-rank-fulltext',
              'actor_user_id': 'user-owner',
              'actor_name': leaderboardUsername1,
              'action': 'workspace.create',
              'detail': 'Workspace initialization',
              'created_at': DateTime(2026, 10, 24, 8, 45).toIso8601String(),
            },
          ]);
        }

        if (request.method == 'GET' &&
            path == '/api/workspaces/space-mention-rank-fulltext/leaderboard') {
          return _json([
            {
              'workspace_id': 'space-mention-rank-fulltext',
              'user_id': 'user-owner',
              'username': leaderboardUsername1,
              'role': 'owner',
              'assigned': 12,
              'completed': 12,
              'completion_rate': 1.0,
            },
            {
              'workspace_id': 'space-mention-rank-fulltext',
              'user_id': 'user-leader-2',
              'username': leaderboardUsername2,
              'role': 'editor',
              'assigned': 8,
              'completed': 6,
              'completion_rate': 0.75,
            },
          ]);
        }

        return _json(request.method == 'GET' ? [] : {});
      }),
    );

    final auth = AuthProvider(
      client: client,
      initialState: const AuthState(
        userId: 'user-owner',
        username: 'synthetic-user',
        token: 'synthetic-token-mentions-leaderboard',
      ),
    );

    final share =
        ShareProvider()
          ..apiClientGetter = (() => auth.client)
          ..userIdGetter = (() => auth.state.userId);

    final theme = ThemeProvider();
    await theme.loadFromStorage();

    return _ShareMentionsLeaderboardFixture._(
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
    required TextScaler textScaler,
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
                              textScaler: textScaler,
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

class _SharePriorityScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final String targetBrand;
  final Size size;
  final TextScaler textScaler;

  const _SharePriorityScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.size,
    required this.textScaler,
  });
}

const _scenarios = <_SharePriorityScenario>[
  _SharePriorityScenario(
    name: 'zh-portrait-320x844-scale2-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    textScaler: TextScaler.linear(2.0),
  ),
  _SharePriorityScenario(
    name: 'zh-portrait-320x844-scale2-liquidGlass',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(320, 844),
    textScaler: TextScaler.linear(2.0),
  ),
  _SharePriorityScenario(
    name: 'en-portrait-320x844-scale2-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(320, 844),
    textScaler: TextScaler.linear(2.0),
  ),
  _SharePriorityScenario(
    name: 'en-portrait-320x844-scale2-defaultBrand',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    textScaler: TextScaler.linear(2.0),
  ),
  _SharePriorityScenario(
    name: 'en-landscape-844x390-scale1-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(844, 390),
    textScaler: TextScaler.linear(1.0),
  ),
  _SharePriorityScenario(
    name: 'zh-portrait-320x844-nonlinear-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    textScaler: RouteProbeNonlinearScaler(),
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
      'ShareScreen mentions fulltext and leaderboard reflow without truncation: ${scenario.name}',
      (tester) async {
        final fixture = await _ShareMentionsLeaderboardFixture.create(
          initialBrand: scenario.initialBrand,
          locale: scenario.initialLocale,
        );
        addTearDown(fixture.dispose);

        await fixture.pump(
          tester,
          size: scenario.size,
          textScaler: scenario.textScaler,
          locale: scenario.initialLocale,
        );

        final baselineWrites = fixture.prefsStore.writeCount;
        final isEn = scenario.initialLocale == AppLocale.en;
        final workspaceName = isEn ? _enWorkspaceName : _zhWorkspaceName;
        final longMentionBody = isEn ? _enLongMentionBody : _zhLongMentionBody;
        final readMentionBody = isEn ? _enLongMentionBody2 : _zhLongMentionBody2;
        final leaderboardUsername1 =
            isEn ? _enLeaderboardUsername1 : _zhLeaderboardUsername1;
        final leaderboardUsername2 =
            isEn ? _enLeaderboardUsername2 : _zhLeaderboardUsername2;

        // 1. Open mention inbox sheet via AppBar button
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

        final inboxSheetFinder = find.byType(AppModalSheet).last;
        final expectedInboxTitle =
            isEn ? ShareUiCopy.mentionInboxTitle(scenario.initialLocale) : '@ 提及';
        expect(find.text(expectedInboxTitle), findsOneWidget);

        // Zero preference writes during inbox viewing
        expect(
          fixture.prefsStore.writeCount,
          equals(baselineWrites),
          reason: 'Viewing mention inbox must cause 0 preference writes',
        );

        // 2. Mention 1 (Unread): verify full body reflow without truncation
        final unreadTileFinder = find.ancestor(
          of: find.text(longMentionBody),
          matching: find.byType(ListTile),
        );
        expect(unreadTileFinder, findsOneWidget);
        final unreadBodyFinder = find.descendant(
          of: unreadTileFinder,
          matching: find.text(longMentionBody),
        );
        await Scrollable.ensureVisible(
          tester.element(unreadBodyFinder),
          alignment: 0.5,
        );
        await _boundedPumpAndSettle(tester);

        await _assertReadableParagraph(
          tester,
          textFinder: unreadBodyFinder,
          boundaryKey: fixture.boundaryKey,
          surfaceFinder: inboxSheetFinder,
          role: 'Unread mention body in inbox',
          assertWordContinuity: isEn,
        );

        // Unread mention View Button: verify real 44dp touch target
        final viewButtonFinder = find.descendant(
          of: unreadTileFinder,
          matching: find.widgetWithText(
            FilledButton,
            ShareUiCopy.actionView(scenario.initialLocale),
          ),
        );
        _assertControl44(
          tester,
          viewButtonFinder,
          'Unread mention View button must meet 44dp touch target',
        );

        // 3. Mention 2 (Read): verify full body reflow without truncation
        final readTileFinder = find.ancestor(
          of: find.text(readMentionBody),
          matching: find.byType(ListTile),
        );
        expect(readTileFinder, findsOneWidget);
        final readBodyFinder = find.descendant(
          of: readTileFinder,
          matching: find.text(readMentionBody),
        );
        await Scrollable.ensureVisible(
          tester.element(readBodyFinder),
          alignment: 0.5,
        );
        await _boundedPumpAndSettle(tester);

        await _assertReadableParagraph(
          tester,
          textFinder: readBodyFinder,
          boundaryKey: fixture.boundaryKey,
          surfaceFinder: inboxSheetFinder,
          role: 'Read mention body in inbox',
          assertWordContinuity: isEn,
        );

        // Read mention has chevron icon instead of View button
        final chevronFinder = find.descendant(
          of: readTileFinder,
          matching: find.byIcon(Icons.chevron_right),
        );
        expect(chevronFinder, findsOneWidget);

        // Capture mention inbox screenshot
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-mention-inbox',
        );

        // 4. Open collaboration sheet via View button or Read tile
        final isReadPathOnly = scenario.name.contains('landscape');
        if (isReadPathOnly) {
          // Scroll read tile into visible viewport, ensure hitTestable before tap
          await Scrollable.ensureVisible(
            tester.element(readTileFinder),
            alignment: 0.5,
          );
          await _boundedPumpAndSettle(tester);
          expect(readTileFinder.hitTestable(), findsOneWidget);
          await tester.tap(readTileFinder.hitTestable());
          await _boundedPumpAndSettle(tester);

          // Verify NO markMentionRead POST was sent for already-read mention
          final readMutations = fixture.requests
              .where((r) => r.method != 'GET')
              .toList();
          expect(
            readMutations,
            isEmpty,
            reason: 'Tapping read mention must not trigger mark-as-read POST mutation',
          );
        } else {
          // Scroll View button into visible viewport, ensure hitTestable before tap
          await Scrollable.ensureVisible(
            tester.element(viewButtonFinder),
            alignment: 0.5,
          );
          await _boundedPumpAndSettle(tester);
          expect(viewButtonFinder.hitTestable(), findsOneWidget);
          await tester.tap(viewButtonFinder.hitTestable());
          await _boundedPumpAndSettle(tester);

          // Verify exact markMentionRead POST was sent for unread mention 101
          final mutations = fixture.requests
              .where((r) => r.method != 'GET')
              .toList();
          expect(
            mutations,
            hasLength(1),
            reason: 'Only markMentionRead POST mutation is permitted for unread mention',
          );
          expect(
            mutations.single.url.path,
            '/api/workspaces/mentions/101/read',
            reason: 'markMentionRead must target mention id 101',
          );
        }

        final collabSheetFinder = find.byType(AppModalSheet).last;
        final expectedCollabTitle = ShareUiCopy.collaborationSheetTitle(
          workspaceName,
          scenario.initialLocale,
        );
        expect(find.text(expectedCollabTitle), findsOneWidget);

        // 5. Leaderboard Section: verify title and full reflow of entry usernames
        final expectedLeaderboardTitle = isEn
            ? ShareUiCopy.memberLeaderboardTitle(scenario.initialLocale)
            : '成员排行榜';
        expect(find.text(expectedLeaderboardTitle), findsOneWidget);

        // Scope Leaderboard Entry 1 (100% completion rate):
        final rank1TileFinder = find.ancestor(
          of: find.descendant(of: collabSheetFinder, matching: find.text('100%')),
          matching: find.byType(ListTile),
        );
        expect(rank1TileFinder, findsOneWidget);
        final user1Finder = find.descendant(
          of: rank1TileFinder,
          matching: find.text(leaderboardUsername1),
        );
        expect(user1Finder, findsOneWidget);
        await Scrollable.ensureVisible(
          tester.element(user1Finder),
          alignment: 0.5,
        );
        await _boundedPumpAndSettle(tester);

        await _assertReadableParagraph(
          tester,
          textFinder: user1Finder,
          boundaryKey: fixture.boundaryKey,
          surfaceFinder: collabSheetFinder,
          role: 'Leaderboard rank 1 username',
          assertWordContinuity: isEn,
        );

        // Leaderboard Entry 1: verify rank badge, completion rate, role subtitle
        expect(
          find.descendant(of: rank1TileFinder, matching: find.text('1')),
          findsOneWidget,
          reason: 'Rank 1 badge must be visible',
        );
        final user1Subtitle = ShareUiCopy.leaderboardSubtitle(
          WorkspaceRole.owner.labelFor(scenario.initialLocale),
          12,
          12,
          scenario.initialLocale,
        );
        expect(
          find.descendant(of: rank1TileFinder, matching: find.text(user1Subtitle)),
          findsOneWidget,
          reason: 'Owner completion stats subtitle must be visible',
        );

        // Scope Leaderboard Entry 2 (75% completion rate):
        final rank2TileFinder = find.ancestor(
          of: find.descendant(of: collabSheetFinder, matching: find.text('75%')),
          matching: find.byType(ListTile),
        );
        expect(rank2TileFinder, findsOneWidget);
        final user2Finder = find.descendant(
          of: rank2TileFinder,
          matching: find.text(leaderboardUsername2),
        );
        expect(user2Finder, findsOneWidget);
        await Scrollable.ensureVisible(
          tester.element(user2Finder),
          alignment: 0.5,
        );
        await _boundedPumpAndSettle(tester);

        await _assertReadableParagraph(
          tester,
          textFinder: user2Finder,
          boundaryKey: fixture.boundaryKey,
          surfaceFinder: collabSheetFinder,
          role: 'Leaderboard rank 2 username',
          assertWordContinuity: isEn,
        );

        expect(
          find.descendant(of: rank2TileFinder, matching: find.text('2')),
          findsOneWidget,
          reason: 'Rank 2 badge must be visible',
        );
        final user2Subtitle = ShareUiCopy.leaderboardSubtitle(
          WorkspaceRole.editor.labelFor(scenario.initialLocale),
          8,
          6,
          scenario.initialLocale,
        );
        expect(
          find.descendant(of: rank2TileFinder, matching: find.text(user2Subtitle)),
          findsOneWidget,
          reason: 'Editor completion stats subtitle must be visible',
        );

        // Capture collaboration sheet screenshot
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-collaboration',
        );

        // 6. Theme and Locale Roundtrip: state retention and preference write isolation
        final initialSheetElement = tester.element(collabSheetFinder);
        final initialSheetRoute = ModalRoute.of(initialSheetElement);
        final initialProvider = fixture.share;

        // Switch to alternateLocale
        I18n.setLocale(scenario.alternateLocale);
        await _boundedPumpAndSettle(tester);

        final altCollabTitle = ShareUiCopy.collaborationSheetTitle(
          workspaceName,
          scenario.alternateLocale,
        );
        expect(find.text(altCollabTitle), findsOneWidget);

        // Switch brand
        final writesBeforeFirstBrand = fixture.prefsStore.writeCount;
        await tester.runAsync(() async {
          final switched = await fixture.theme.setBrand(scenario.targetBrand);
          expect(switched, isTrue, reason: 'First setBrand must succeed');
        });
        await _boundedPumpAndSettle(tester);
        final firstBrandDelta =
            fixture.prefsStore.writeCount - writesBeforeFirstBrand;
        expect(
          firstBrandDelta,
          greaterThan(0),
          reason: 'First setBrand records intentional write',
        );

        // Verify sheet route and provider retention across alternate switch
        expect(
          tester.element(find.byType(AppModalSheet).last),
          same(initialSheetElement),
          reason:
              'Collaboration sheet element must be retained across alternate switch',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppModalSheet).last)),
          same(initialSheetRoute),
          reason:
              'Collaboration sheet route must remain current across alternate switch',
        );
        expect(
          fixture.share,
          same(initialProvider),
          reason:
              'ShareProvider instance must be retained across alternate switch',
        );

        // Usernames in scoped tiles preserved and readable after alternate switch
        expect(
          find.descendant(
            of: rank1TileFinder,
            matching: find.text(leaderboardUsername1),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: rank2TileFinder,
            matching: find.text(leaderboardUsername2),
          ),
          findsOneWidget,
        );

        await _assertReadableParagraph(
          tester,
          textFinder: user1Finder,
          boundaryKey: fixture.boundaryKey,
          surfaceFinder: collabSheetFinder,
          role: 'Leaderboard rank 1 username after alternate switch',
          assertWordContinuity: isEn,
        );
        await _assertReadableParagraph(
          tester,
          textFinder: user2Finder,
          boundaryKey: fixture.boundaryKey,
          surfaceFinder: collabSheetFinder,
          role: 'Leaderboard rank 2 username after alternate switch',
          assertWordContinuity: isEn,
        );

        // Revert switch to initialLocale
        I18n.setLocale(scenario.initialLocale);
        await _boundedPumpAndSettle(tester);

        expect(
          find.text(expectedCollabTitle),
          findsOneWidget,
          reason: 'Collaboration sheet title must revert to initial locale',
        );

        // Revert switch to initialBrand
        final writesBeforeRevertBrand = fixture.prefsStore.writeCount;
        await tester.runAsync(() async {
          final reverted = await fixture.theme.setBrand(scenario.initialBrand);
          expect(reverted, isTrue, reason: 'Revert setBrand must succeed');
        });
        await _boundedPumpAndSettle(tester);
        final revertBrandDelta =
            fixture.prefsStore.writeCount - writesBeforeRevertBrand;
        expect(
          revertBrandDelta,
          greaterThan(0),
          reason: 'Revert setBrand records intentional write',
        );

        // Drain writes and assert exact writes count equality
        await _drainAccountWrites(tester);
        expect(
          fixture.prefsStore.writeCount,
          equals(baselineWrites + firstBrandDelta + revertBrandDelta),
          reason:
              'Only intentional first and revert setBrand preference writes must be recorded',
        );

        // Verify sheet route and provider retention across full roundtrip
        expect(
          tester.element(find.byType(AppModalSheet).last),
          same(initialSheetElement),
          reason:
              'Collaboration sheet element must be retained across full roundtrip',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppModalSheet).last)),
          same(initialSheetRoute),
          reason:
              'Collaboration sheet route must remain current across full roundtrip',
        );
        expect(
          fixture.share,
          same(initialProvider),
          reason:
              'ShareProvider instance must be retained across full roundtrip',
        );

        // Usernames in scoped tiles preserved and readable after full roundtrip
        expect(
          find.descendant(
            of: rank1TileFinder,
            matching: find.text(leaderboardUsername1),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: rank2TileFinder,
            matching: find.text(leaderboardUsername2),
          ),
          findsOneWidget,
        );

        await _assertReadableParagraph(
          tester,
          textFinder: user1Finder,
          boundaryKey: fixture.boundaryKey,
          surfaceFinder: collabSheetFinder,
          role: 'Leaderboard rank 1 username after full roundtrip',
          assertWordContinuity: isEn,
        );
        await _assertReadableParagraph(
          tester,
          textFinder: user2Finder,
          boundaryKey: fixture.boundaryKey,
          surfaceFinder: collabSheetFinder,
          role: 'Leaderboard rank 2 username after full roundtrip',
          assertWordContinuity: isEn,
        );

        // Final mutations list check: zero for read path, exactly 1 for unread path
        final finalMutations = fixture.requests
            .where((r) => r.method != 'GET')
            .toList();
        if (isReadPathOnly) {
          expect(
            finalMutations,
            isEmpty,
            reason: 'Read path must produce zero POST mutations across full run',
          );
        } else {
          expect(
            finalMutations,
            hasLength(1),
            reason:
                'Only markMentionRead POST mutation is permitted across full run',
          );
          expect(
            finalMutations.single.url.path,
            '/api/workspaces/mentions/101/read',
            reason: 'markMentionRead must target mention id 101',
          );
        }
      },
    );
  }

  // 7. Independent Direct-Collaboration Leaderboard Tests (standalone baseline failure proof)
  testWidgets(
    'ShareScreen direct collaboration leaderboard reflows without truncation: zh-portrait-320x844-scale2-defaultBrand',
    (tester) async {
      final fixture = await _ShareMentionsLeaderboardFixture.create(
        initialBrand: 'defaultBrand',
        locale: AppLocale.zh,
      );
      addTearDown(fixture.dispose);

      await fixture.pump(
        tester,
        size: const Size(320, 844),
        textScaler: const TextScaler.linear(2.0),
        locale: AppLocale.zh,
      );

      // Directly open collaboration from WorkspaceCard without entering mention inbox
      final collabButton = find.byTooltip(ShareUiCopy.collaborationTooltip(AppLocale.zh));
      expect(collabButton, findsOneWidget);
      await tester.tap(collabButton);
      await _boundedPumpAndSettle(tester);

      final collabSheetFinder = find.byType(AppModalSheet).last;
      expect(collabSheetFinder, findsOneWidget);

      final rank1TileFinder = find.ancestor(
        of: find.descendant(of: collabSheetFinder, matching: find.text('100%')),
        matching: find.byType(ListTile),
      );
      expect(rank1TileFinder, findsOneWidget);
      final user1Finder = find.descendant(
        of: rank1TileFinder,
        matching: find.text(_zhLeaderboardUsername1),
      );
      expect(user1Finder, findsOneWidget);

      await Scrollable.ensureVisible(tester.element(user1Finder), alignment: 0.5);
      await _boundedPumpAndSettle(tester);

      // In baseline product, _LeaderboardTile has maxLines: 1 and TextOverflow.ellipsis,
      // so didExceedMaxLines is true and this assertion genuinely fails.
      await _assertReadableParagraph(
        tester,
        textFinder: user1Finder,
        boundaryKey: fixture.boundaryKey,
        surfaceFinder: collabSheetFinder,
        role: 'Direct collaboration rank 1 username zh',
      );
    },
  );

  testWidgets(
    'ShareScreen direct collaboration leaderboard reflows without truncation: en-portrait-320x844-scale2-liquidGlass',
    (tester) async {
      final fixture = await _ShareMentionsLeaderboardFixture.create(
        initialBrand: 'liquidGlass',
        locale: AppLocale.en,
      );
      addTearDown(fixture.dispose);

      await fixture.pump(
        tester,
        size: const Size(320, 844),
        textScaler: const TextScaler.linear(2.0),
        locale: AppLocale.en,
      );

      // Directly open collaboration from WorkspaceCard without entering mention inbox
      final collabButton = find.byTooltip(ShareUiCopy.collaborationTooltip(AppLocale.en));
      expect(collabButton, findsOneWidget);
      await tester.tap(collabButton);
      await _boundedPumpAndSettle(tester);

      final collabSheetFinder = find.byType(AppModalSheet).last;
      expect(collabSheetFinder, findsOneWidget);

      final rank1TileFinder = find.ancestor(
        of: find.descendant(of: collabSheetFinder, matching: find.text('100%')),
        matching: find.byType(ListTile),
      );
      expect(rank1TileFinder, findsOneWidget);
      final user1Finder = find.descendant(
        of: rank1TileFinder,
        matching: find.text(_enLeaderboardUsername1),
      );
      expect(user1Finder, findsOneWidget);

      await Scrollable.ensureVisible(tester.element(user1Finder), alignment: 0.5);
      await _boundedPumpAndSettle(tester);

      // In baseline product, _LeaderboardTile has maxLines: 1 and TextOverflow.ellipsis,
      // so didExceedMaxLines is true and this assertion genuinely fails.
      await _assertReadableParagraph(
        tester,
        textFinder: user1Finder,
        boundaryKey: fixture.boundaryKey,
        surfaceFinder: collabSheetFinder,
        role: 'Direct collaboration rank 1 username en',
        assertWordContinuity: true,
      );
    },
  );

  // 8. Preference & Mutation Isolation with Raw Stored User Content Preservation
  testWidgets(
    'ShareScreen unread and read mention paths preserve exact callback counts and avoid incidental preference writes during locale transitions',
    (tester) async {
      final fixture = await _ShareMentionsLeaderboardFixture.create(
        initialBrand: 'defaultBrand',
        locale: AppLocale.zh,
      );
      addTearDown(fixture.dispose);

      await fixture.pump(
        tester,
        size: const Size(320, 844),
        textScaler: const TextScaler.linear(2.0),
        locale: AppLocale.zh,
      );

      final baselineWrites = fixture.prefsStore.writeCount;
      expect(fixture.share.unreadMentionCount, 1);

      // Open mention inbox
      final inboxButtonFinder = find.byTooltip(
        ShareUiCopy.mentionInboxTooltip(1, AppLocale.zh),
      );
      await tester.tap(inboxButtonFinder);
      await _boundedPumpAndSettle(tester);

      expect(
        fixture.prefsStore.writeCount,
        equals(baselineWrites),
        reason: 'Opening inbox must cause 0 preference writes',
      );

      // Tap unread mention View button -> exactly 1 POST mutation
      final viewButtonFinder = find.widgetWithText(
        FilledButton,
        ShareUiCopy.actionView(AppLocale.zh),
      );
      await Scrollable.ensureVisible(
        tester.element(viewButtonFinder),
        alignment: 0.5,
      );
      await _boundedPumpAndSettle(tester);
      expect(viewButtonFinder.hitTestable(), findsOneWidget);
      await tester.tap(viewButtonFinder.hitTestable());
      await _boundedPumpAndSettle(tester);

      final mutations = fixture.requests
          .where((r) => r.method != 'GET')
          .toList();
      expect(mutations, hasLength(1));
      expect(mutations.single.url.path, '/api/workspaces/mentions/101/read');

      // Drain and verify zero incidental preference writes during view and transition
      await _drainAccountWrites(tester);
      expect(
        fixture.prefsStore.writeCount,
        equals(baselineWrites),
        reason: 'Viewing mention and navigating must not perform incidental preference writes',
      );

      // Dismiss collaboration sheet
      Navigator.pop(fixture.navigatorKey.currentContext!);
      await _boundedPumpAndSettle(tester);

      // Change locale while on ShareScreen: 0 preference writes
      final writesBeforeLocale = fixture.prefsStore.writeCount;
      I18n.setLocale(AppLocale.en);
      await _boundedPumpAndSettle(tester);
      await _drainAccountWrites(tester);
      expect(
        fixture.prefsStore.writeCount,
        equals(writesBeforeLocale),
        reason: 'Locale transition must not trigger incidental preference writes',
      );

      // Open inbox again: unread count is now 0
      expect(fixture.share.unreadMentionCount, 0);
      final enInboxFinder = find.byTooltip(
        ShareUiCopy.mentionInboxTooltip(0, AppLocale.en),
      );
      await tester.tap(enInboxFinder);
      await _boundedPumpAndSettle(tester);

      // Raw stored mention body of mention 102 was created in Chinese (_zhLongMentionBody2),
      // and must remain raw Chinese even after switching UI locale to English.
      final readTileFinder = find.ancestor(
        of: find.text(_zhLongMentionBody2),
        matching: find.byType(ListTile),
      );
      expect(
        readTileFinder,
        findsOneWidget,
        reason: 'Raw stored mention body must remain unchanged in Chinese despite locale switch to English',
      );

      // Scroll read tile into view, ensure hitTestable, and tap directly
      await Scrollable.ensureVisible(
        tester.element(readTileFinder),
        alignment: 0.5,
      );
      await _boundedPumpAndSettle(tester);
      expect(readTileFinder.hitTestable(), findsOneWidget);
      await tester.tap(readTileFinder.hitTestable());
      await _boundedPumpAndSettle(tester);

      // Drain writes and verify zero incidental preference writes after read tap & navigation
      await _drainAccountWrites(tester);
      expect(
        fixture.prefsStore.writeCount,
        equals(baselineWrites),
        reason:
            'Reading already-read mention and viewing collaboration must not perform incidental preference writes',
      );

      // Total mutations remain 1 (no additional POST for already-read mention)
      final totalMutations = fixture.requests
          .where((r) => r.method != 'GET')
          .toList();
      expect(
        totalMutations,
        hasLength(1),
        reason: 'Read mention tap must not produce additional POST mutations',
      );
      expect(
        totalMutations.single.url.path,
        '/api/workspaces/mentions/101/read',
        reason: 'Only markMentionRead for mention 101 was recorded',
      );

      // Collaboration sheet opened successfully with localized title
      final collabSheetFinder = find.byType(AppModalSheet).last;
      expect(collabSheetFinder, findsOneWidget);
      final expectedTitle = ShareUiCopy.collaborationSheetTitle(
        _zhWorkspaceName,
        AppLocale.en,
      );
      expect(
        find.descendant(of: collabSheetFinder, matching: find.text(expectedTitle)),
        findsOneWidget,
      );
    },
  );
}
