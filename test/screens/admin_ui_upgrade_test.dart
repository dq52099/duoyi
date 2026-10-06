import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/widget_polish_screenshot_font.dart';

const _modules = [
  (label: '概览', key: 'dashboard', endpoint: '/api/admin/stats'),
  (label: '全站设置', key: 'settings', endpoint: '/api/admin/settings'),
  (label: 'AI 配置', key: 'ai', endpoint: '/api/admin/settings?scope=ai'),
  (label: '云端备份', key: 'backup', endpoint: '/api/admin/settings?scope=backup'),
  (label: '用户', key: 'users', endpoint: '/api/admin/users'),
  (label: '用户组', key: 'groups', endpoint: '/api/admin/groups'),
  (label: '公告', key: 'announcements', endpoint: '/api/admin/announcements'),
  (label: '许愿与反馈', key: 'feedback', endpoint: '/api/admin/feedback'),
  (label: '邀请码', key: 'invites', endpoint: '/api/admin/invite-codes'),
  (label: '日志', key: 'audit', endpoint: '/api/admin/audit-log'),
];

const _layouts = [
  (
    width: 390.0,
    textScale: 1.0,
    brightness: Brightness.light,
    name: '390-light',
  ),
  (
    width: 320.0,
    textScale: 1.6,
    brightness: Brightness.dark,
    name: '320-dark-1.6',
  ),
];

/// UI contract checks for the administrator surface.
///
/// These tests use an in-memory HTTP client only. They deliberately never call
/// the configured backend, so they remain useful when the preview server is
/// offline or has no administrator account available.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final layout in _layouts) {
    for (var index = 0; index < _modules.length; index++) {
      final module = _modules[index];
      testWidgets('${module.label} renders and scrolls at ${layout.name}', (
        tester,
      ) async {
        final requests = <String>[];
        final client = ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'admin-token',
          httpClient: MockClient(_adminMockHandler(requests: requests)),
        );
        await _pumpAdmin(
          tester,
          client,
          initialTabIndex: index,
          width: layout.width,
          textScale: layout.textScale,
          brightness: layout.brightness,
        );

        expect(find.byKey(ValueKey('admin-${module.key}-0')), findsOneWidget);
        expect(
          requests.any((request) => request.startsWith(module.endpoint)),
          isTrue,
          reason: '${module.label} did not load its data source: $requests',
        );
        expect(find.text('重新加载'), findsNothing);
        final captureName = 'admin-${module.key}-${layout.name}';
        await _captureAdmin(tester, captureName);
        expect(tester.takeException(), isNull);
        await _scrollVerticalContent(tester, captureName: captureName);
        await _disposeAdmin(tester);
      });
    }
  }

  testWidgets('all ten admin modules keep their 0-9 menu mapping', (
    tester,
  ) async {
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient(_adminMockHandler()),
    );
    await _pumpAdmin(tester, client);

    final tabBar = find.byWidgetPredicate(
      (widget) => widget is TabBar && widget.tabs.length == _modules.length,
    );
    expect(tabBar, findsOneWidget);
    final controller = tester.widget<TabBar>(tabBar).controller;
    expect(controller, isNotNull);

    for (var index = 0; index < _modules.length; index++) {
      await tester.tap(find.byTooltip('选择管理模块'));
      await tester.pumpAndSettle();
      final item = find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<int> && widget.value == index,
      );
      expect(item, findsOneWidget);
      expect(
        find.descendant(of: item, matching: find.text(_modules[index].label)),
        findsOneWidget,
      );
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(
        controller!.index,
        index,
        reason: '管理模块 ${_modules[index].label} 映射错误',
      );
      expect(tester.takeException(), isNull);
    }
    await _disposeAdmin(tester);
  });

  testWidgets('overview shows retry after an error and preserves zero values', (
    tester,
  ) async {
    var statsCalls = 0;
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/admin/stats') {
          statsCalls++;
          if (statsCalls == 1) {
            return _jsonResponse({'detail': 'temporary failure'}, status: 503);
          }
          return _jsonResponse(_statsWithZerosAndMissingValues());
        }
        return _adminMockHandler()(request);
      }),
    );
    await _pumpAdmin(tester, client, initialTabIndex: 0);

    expect(find.textContaining('概览'), findsWidgets);
    expect(find.text('重新加载'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();

    expect(statsCalls, 2);
    expect(find.text('总用户'), findsOneWidget);
    expect(_kpiValueFinder('总用户', '0'), findsOneWidget);
    expect(_kpiValueFinder('管理员', '-'), findsOneWidget);
    expect(_kpiValueFinder('已禁用', '0'), findsOneWidget);
    await _scrollAdminListTo(tester, find.text('暂无注册'));
    expect(find.text('暂无注册'), findsOneWidget);
    expect(find.text('重新加载'), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeAdmin(tester);
  });

  testWidgets('users remain readable with long identity and no-result state', (
    tester,
  ) async {
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/admin/users') {
          final query = request.url.queryParameters['q'] ?? '';
          if (query == '无匹配用户') {
            return _pageResponse(const <Map<String, dynamic>>[], total: 0);
          }
          return _pageResponse([
            {
              'user_id': 'long-user-id',
              'username':
                  'a-very-long-administrator-user-name-for-mobile-layout',
              'display_name': '这是一个很长但仍应完整可读的管理员昵称',
              'email': 'admin-layout@example.com',
              'email_verified': true,
              'is_admin': true,
              'is_disabled': false,
              'online': true,
              'admin_permissions': ['users', 'feedback'],
              'group_id': 'group_default',
              'role_id': 'role_admin',
              'coin_balance': 0,
              'lifetime_coins': 0,
              'created_at': '2026-10-01 08:00:00',
              'last_login_at': '2026-10-06 08:00:00',
              'last_active_at': '2026-10-06 08:05:00',
            },
          ], total: 1);
        }
        return _adminMockHandler()(request);
      }),
    );
    await _pumpAdmin(
      tester,
      client,
      initialTabIndex: 4,
      width: 320,
      textScale: 1.6,
      brightness: Brightness.dark,
    );

    const username = 'a-very-long-administrator-user-name-for-mobile-layout';
    const displayName = '这是一个很长但仍应完整可读的管理员昵称';
    expect(find.text(username, skipOffstage: false), findsOneWidget);
    expect(find.text('管理员', skipOffstage: false), findsWidgets);
    expect(find.text('细分权限', skipOffstage: false), findsOneWidget);
    expect(find.text('在线', skipOffstage: false), findsWidgets);

    await tester.ensureVisible(find.text(username));
    await tester.tap(find.text(username));
    await tester.pumpAndSettle();
    expect(find.textContaining(displayName), findsOneWidget);
    expect(find.textContaining('管理权限: 用户、反馈'), findsOneWidget);
    await tester.tap(find.text('关闭').last);
    await tester.pumpAndSettle();

    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '搜索用户名、邮箱、昵称或用户 ID',
    );
    expect(search, findsOneWidget);
    await tester.enterText(search, '无匹配用户');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('没有匹配的用户。请调整搜索关键词或账号状态筛选。'), findsOneWidget);
    expect(find.text(username), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeAdmin(tester);
  });

  testWidgets('unfiltered users show an empty list rather than search advice', (
    tester,
  ) async {
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient(_adminMockHandler(users: const [])),
    );
    await _pumpAdmin(tester, client, initialTabIndex: 4);
    expect(find.text('暂无用户记录'), findsOneWidget);
    expect(find.textContaining('没有匹配的用户'), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeAdmin(tester);
  });

  testWidgets('one setting is submitted once until its request finishes', (
    tester,
  ) async {
    final firstSave = Completer<http.Response>();
    final submitted = <Map<String, dynamic>>[];
    final readOnlyHandler = _adminMockHandler();
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.method == 'PATCH' &&
            request.url.path == '/api/admin/settings') {
          submitted.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (submitted.length == 1) return firstSave.future;
          return _jsonResponse(submitted.last);
        }
        return readOnlyHandler(request);
      }),
    );
    await _pumpAdmin(tester, client, initialTabIndex: 1);
    final coinsField = _textFieldWithLabel('默认用户组时光币');
    await tester.ensureVisible(coinsField);
    await tester.enterText(coinsField, '250');

    // Both keyboard completions arrive before the next frame can disable the
    // field. A slow response must not create two writes for one setting.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, [
      {'default_registration_coins': 250},
    ]);

    firstSave.complete(_jsonResponse({'detail': 'please retry'}, status: 503));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // A failed save releases the setting so the administrator can correct it
    // and retry without leaving the page.
    await tester.enterText(coinsField, '300');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(submitted, [
      {'default_registration_coins': 250},
      {'default_registration_coins': 300},
    ]);
    expect(tester.widget<TextField>(coinsField).controller!.text, '300');
    expect(tester.takeException(), isNull);
    await _disposeAdmin(tester);
  });

  testWidgets('a failed group page remains retryable without skipping a page', (
    tester,
  ) async {
    final failingPage = Completer<http.Response>();
    final requestedOffsets = <int>[];
    final readOnlyHandler = _adminMockHandler();
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/admin/groups') {
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          requestedOffsets.add(offset);
          if (requestedOffsets.length == 2) return failingPage.future;
          return _pageResponse(
            offset == 0
                ? List.generate(
                    20,
                    (index) => _group('first-$index', '第一页用户组 ${index + 1}'),
                  )
                : [_group('second-0', '第二页用户组')],
            total: 21,
            offset: offset,
            hasMore: offset == 0,
          );
        }
        return readOnlyHandler(request);
      }),
    );
    await _pumpAdmin(tester, client, initialTabIndex: 5);
    final pagination = find.byKey(
      const ValueKey('admin_groups_pagination_bar'),
    );
    final nextPage = find.descendant(
      of: pagination,
      matching: find.byTooltip('下一页'),
    );
    expect(find.textContaining('第 1/2 页'), findsOneWidget);
    await tester.tap(nextPage);
    await tester.pump();
    expect(requestedOffsets, [0, 20]);

    failingPage.complete(
      _jsonResponse({'detail': 'group page unavailable'}, status: 503),
    );
    await tester.pumpAndSettle();
    expect(find.text('第一页用户组 1'), findsOneWidget);
    expect(find.textContaining('第 1/2 页'), findsOneWidget);
    expect(find.text('第二页用户组'), findsNothing);

    final retry = find.text('重试');
    final reload = find.text('重新加载');
    expect(
      retry.evaluate().isNotEmpty || reload.evaluate().isNotEmpty,
      isTrue,
      reason: '翻页失败应给出可操作的错误提示，不能静默保留旧页',
    );
    await tester.ensureVisible(retry.evaluate().isNotEmpty ? retry : reload);
    await tester.tap(retry.evaluate().isNotEmpty ? retry : reload);
    await tester.pumpAndSettle();

    expect(requestedOffsets, [0, 20, 20]);
    expect(find.text('第二页用户组'), findsOneWidget);
    expect(find.text('第一页用户组 1'), findsNothing);
    expect(find.textContaining('第 2/2 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeAdmin(tester);
  });

  for (final responseWasPending in [false, true]) {
    testWidgets('settings disappear after permission withdrawal '
        '(pending response: $responseWasPending)', (tester) async {
      final settingsResponse = Completer<http.Response>();
      var settingsRequests = 0;
      final readOnlyHandler = _adminMockHandler();
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'admin-token',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/admin/settings' &&
              !request.url.queryParameters.containsKey('scope')) {
            settingsRequests++;
            return settingsResponse.future;
          }
          return readOnlyHandler(request);
        }),
      );
      final auth = _AdminFakeAuthProvider(
        state: const AuthState(
          userId: 'admin',
          username: 'admin',
          token: 'admin-token',
          isAdmin: true,
          adminPermissions: ['settings', 'feedback'],
        ),
        client: client,
      );
      final response = _jsonResponse({
        'registration_enabled': true,
        'maintenance_message': '仅允许设置管理员查看的维护公告',
        'default_registration_coins': 275,
      });
      if (!responseWasPending) settingsResponse.complete(response);
      await _pumpAdmin(
        tester,
        client,
        initialTabIndex: 1,
        auth: auth,
        settle: !responseWasPending,
      );
      expect(settingsRequests, 1);
      if (!responseWasPending) {
        expect(_textFieldWithLabel('默认用户组时光币'), findsOneWidget);
      }

      auth.replaceState(auth.state.copyWith(adminPermissions: ['feedback']));
      await tester.pump();
      if (responseWasPending) settingsResponse.complete(response);
      await tester.pumpAndSettle();

      expect(
        _textFieldWithLabel('默认用户组时光币', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is AppSwitchTile && widget.title == '允许注册',
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(find.textContaining('仅允许设置管理员查看的维护公告'), findsNothing);
      expect(tester.takeException(), isNull);
      await _disposeAdmin(tester);
    });
  }

  testWidgets('a late backup search cannot replace the newer search result', (
    tester,
  ) async {
    final olderSettings = Completer<http.Response>();
    var settingsRequests = 0;
    final readOnlyHandler = _adminMockHandler();
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/admin/settings' &&
            request.url.queryParameters['scope'] == 'backup') {
          settingsRequests++;
          if (settingsRequests == 2) return olderSettings.future;
          return _jsonResponse({
            'backup_enabled': true,
            'backup_max_size_kb': settingsRequests == 1 ? 2048 : 9090,
            'email_service_enabled': false,
          });
        }
        if (request.url.path == '/api/admin/server-backups') {
          final query = request.url.queryParameters['q'] ?? '';
          return _pageResponse([
            {
              'filename': query.isEmpty ? 'initial-backup.zip' : '$query.zip',
              'status': 'uploaded',
              'created_at': '2026-10-06 08:00:00',
              'size_bytes': 2048,
            },
          ], total: 1);
        }
        return readOnlyHandler(request);
      }),
    );
    await _pumpAdmin(tester, client, initialTabIndex: 3);
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '搜索文件名、状态、路径或详情',
    );
    await _scrollAdminListTo(tester, search);
    // Deliver two submissions before the frame can rebuild the search field.
    // Using its public callback keeps this race independent of IME focus loss.
    final field = tester.widget<TextField>(search);
    field.controller!.text = 'older-query';
    field.onSubmitted!('older-query');
    field.controller!.text = 'newer-query';
    field.onSubmitted!('newer-query');
    await tester.pumpAndSettle();
    expect(settingsRequests, 3);
    await _scrollAdminListTo(tester, find.text('newer-query.zip'));
    expect(find.text('newer-query.zip'), findsOneWidget);

    olderSettings.complete(
      _jsonResponse({
        'backup_enabled': false,
        'backup_max_size_kb': 1111,
        'email_service_enabled': false,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('newer-query.zip'), findsOneWidget);
    expect(find.text('older-query.zip'), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeAdmin(tester);
  });
}

Finder _textFieldWithLabel(String label, {bool skipOffstage = true}) =>
    find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
      skipOffstage: skipOffstage,
    );

Map<String, dynamic> _group(String id, String name) => {
  'id': id,
  'name': name,
  'default_time_coins': 100,
  'is_active': true,
};

Future<void> _scrollAdminListTo(WidgetTester tester, Finder target) async {
  final outerList = find.byType(ListView).first;
  final scrollable = find
      .descendant(of: outerList, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(
    target,
    450,
    scrollable: scrollable,
    maxScrolls: 100,
  );
  await tester.pumpAndSettle();
}

Finder _kpiValueFinder(String title, String value) {
  final card = find.ancestor(
    of: find.text(title),
    matching: find.byType(AppSurfaceCard),
  );
  return find.descendant(of: card, matching: find.text(value));
}

Future<void> _pumpAdmin(
  WidgetTester tester,
  ApiClient client, {
  int initialTabIndex = 0,
  double width = 390,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  _AdminFakeAuthProvider? auth,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final previousErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    // Preserve the render object's source location even when takeException
    // below turns the layout error into a concise failed expectation.
    debugPrint(details.toString());
    previousErrorHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousErrorHandler);

  // Use identical, readable font metrics with and without evidence capture.
  await tester.runAsync(_loadAdminReadableFonts);
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.indigo,
    brightness: brightness,
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
          value:
              auth ??
              _AdminFakeAuthProvider(
                state: const AuthState(
                  userId: 'admin',
                  username: 'admin',
                  token: 'admin-token',
                  isAdmin: true,
                ),
                client: client,
              ),
        ),
        ChangeNotifierProvider<AiService>(
          create: (_) => AiService()..attachClient(client),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          fontFamily: 'DuoyiScreenshotLatin',
          fontFamilyFallback: const ['DuoyiScreenshot'],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(key: _adminCaptureKey, child: child!),
        ),
        home: AdminScreen(initialTabIndex: initialTabIndex),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final _adminCaptureKey = GlobalKey();
bool get _captureEnabled =>
    Platform.environment['DUOYI_CAPTURE_ADMIN_UI_SCREENSHOTS'] == '1';

bool _fontsReady = false;

Future<void> _loadAdminReadableFonts() async {
  if (_fontsReady) return;
  await loadWidgetPolishScreenshotFonts();
  // Material controls can retain an explicit family instead of inheriting the
  // route theme. Give those families CJK glyphs as well as Latin characters.
  final cjk = ByteData.sublistView(
    File('assets/fonts/DroidSansFallbackFull.ttf').readAsBytesSync(),
  );
  final latinFile = File(
    Platform.environment['DUOYI_WIDGET_SCREENSHOT_LATIN_FONT'] ??
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  );
  final latin = latinFile.existsSync()
      ? ByteData.sublistView(latinFile.readAsBytesSync())
      : null;
  for (final family in [
    'Ahem',
    'Roboto',
    'monospace',
    'sans-serif',
    'DuoyiScreenshotLatin',
    'DroidSansFallbackFull',
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(cjk));
    if (latin != null) loader.addFont(Future.value(latin));
    await loader.load();
  }
  _fontsReady = true;
}

Future<void> _scrollVerticalContent(
  WidgetTester tester, {
  required String captureName,
}) async {
  // Exercise the lower settings sections as well as the initial viewport.
  final scrollables = tester.stateList<ScrollableState>(
    find.byType(Scrollable),
  );
  var capturedScrollEnd = false;
  for (final state in scrollables.toList()) {
    if (!state.mounted ||
        axisDirectionToAxis(state.axisDirection) != Axis.vertical) {
      continue;
    }
    final position = state.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
      continue;
    }
    final step = position.viewportDimension * 0.8;
    if (step <= 0) continue;
    for (var offset = step; offset < position.maxScrollExtent; offset += step) {
      position.jumpTo(offset);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (!capturedScrollEnd) {
      await _captureAdmin(tester, '$captureName-scrolled');
      capturedScrollEnd = true;
    }
    position.jumpTo(0);
    await tester.pumpAndSettle();
  }
}

Future<void> _disposeAdmin(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Future<void> _captureAdmin(WidgetTester tester, String name) async {
  if (!_captureEnabled) return;
  await tester.runAsync(() async {
    final boundary =
        _adminCaptureKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      'evidence/screenshots/admin-ui-upgrade-20261006/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<http.Response> Function(http.Request) _adminMockHandler({
  List<String>? requests,
  List<Map<String, dynamic>>? users,
}) {
  return (request) async {
    requests?.add(
      '${request.url.path}${request.url.hasQuery ? '?${request.url.query}' : ''}',
    );
    if (request.method != 'GET') {
      throw StateError(
        'Unexpected mutation in rendering fixture: ${request.method} ${request.url}',
      );
    }
    final path = request.url.path;
    if (path == '/api/admin/stats') {
      return _jsonResponse(_statsWithZerosAndMissingValues());
    }
    if (path == '/api/admin/settings') {
      final scope = request.url.queryParameters['scope'];
      if (scope == 'ai') {
        return _jsonResponse({
          'ai_enabled': false,
          'ai_model': '',
          'ai_api_key_set': false,
          'ai_daily_quota': 0,
        });
      }
      if (scope == 'backup') {
        return _jsonResponse({
          'backup_enabled': false,
          'backup_max_size_kb': 2048,
          'backup_interval_minutes': 30,
          'backup_retain_days': 0,
          'server_backup_enabled': false,
          'local_backups': <dynamic>[],
          'reminder_email_enabled': false,
          'email_service_enabled': false,
        });
      }
      return _jsonResponse({
        'invite_code_required': false,
        'registration_enabled': true,
        'registration_email_required': false,
        'maintenance_mode': false,
        'force_update_required': false,
        'default_registration_coins': 100,
      });
    }
    if (path == '/api/admin/groups') {
      return _pageResponse([
        {
          'id': 'group_default',
          'name': '默认组',
          'description': '普通用户',
          'default_time_coins': 100,
          'is_active': true,
        },
      ], total: 1);
    }
    if (path == '/api/admin/roles') {
      return _jsonResponse([
        {
          'id': 'role_admin',
          'name': '管理员',
          'description': '后台管理员',
          'permissions': ['users', 'feedback'],
          'is_active': true,
        },
      ]);
    }
    if (path == '/api/admin/users') {
      final items =
          users ??
          [
            {
              'user_id': 'fixture-user',
              'username': 'fixture-admin',
              'display_name': '后台演示用户',
              'email': 'fixture@example.com',
              'email_verified': true,
              'is_admin': true,
              'is_disabled': false,
              'online': true,
              'admin_permissions': ['users'],
              'group_id': 'group_default',
              'role_id': 'role_admin',
              'coin_balance': 100,
              'lifetime_coins': 100,
              'created_at': '2026-10-01 08:00:00',
              'last_login_at': '2026-10-06 08:00:00',
              'last_active_at': '2026-10-06 08:05:00',
            },
          ];
      return _pageResponse(items, total: items.length);
    }
    if (path == '/api/admin/backups' || path == '/api/admin/server-backups') {
      return _pageResponse(const <Map<String, dynamic>>[], total: 0);
    }
    if (path == '/api/admin/announcements') {
      return _pageResponse(const <Map<String, dynamic>>[], total: 0);
    }
    if (path == '/api/admin/feedback') {
      return _pageResponse(const <Map<String, dynamic>>[], total: 0);
    }
    if (path == '/api/admin/invite-codes') {
      return _pageResponse(const <Map<String, dynamic>>[], total: 0);
    }
    if (path == '/api/admin/audit-log') {
      return _pageResponse(const <Map<String, dynamic>>[], total: 0);
    }
    throw StateError('Missing admin UI mock: ${request.method} ${request.url}');
  };
}

Map<String, dynamic> _statsWithZerosAndMissingValues() {
  return {
    'users': {
      'total': 0,
      'disabled': 0,
      'new_today': 0,
      'active_7d': 0,
      'online': 0,
      // Deliberately omit admin and unverified_email to distinguish missing
      // server data from a real zero.
    },
    'feedback': {'total': 0, 'open': 0, 'in_progress': 0},
    'announcements': {'total': 0, 'published': 0},
    'invites': {'total': 0, 'used': 0},
    'registration_series': <Map<String, dynamic>>[],
  };
}

http.Response _jsonResponse(Object body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

http.Response _pageResponse(
  List<Map<String, dynamic>> items, {
  required int total,
  int offset = 0,
  int limit = 20,
  bool hasMore = false,
}) {
  return _jsonResponse({
    'items': items,
    'total': total,
    'limit': limit,
    'offset': offset,
    'has_more': hasMore,
  });
}

class _AdminFakeAuthProvider extends AuthProvider {
  AuthState _fakeState;
  final ApiClient _fakeClient;

  _AdminFakeAuthProvider({required AuthState state, required ApiClient client})
    : _fakeState = state,
      _fakeClient = client;

  @override
  AuthState get state => _fakeState;

  @override
  ApiClient get client => _fakeClient;

  void replaceState(AuthState state) {
    _fakeState = state;
    notifyListeners();
  }
}
