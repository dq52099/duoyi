import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/share_ui_copy.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/share_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final join in [false, true]) {
    testWidgets(
      'retained ${join ? 'join' : 'create'} form preserves draft and selection across locale',
      (tester) async {
        final f = _Fixture();
        await f.pump(tester);
        final screenState = tester.state(find.byType(ShareScreen));
        final listRequests = f.requests.where(_listRequest).length;
        await f.openForm(tester, join: join);
        final field = find.byType(TextField);
        await tester.enterText(field, '原始 synthetic draft');
        final controller = tester.widget<TextField>(field).controller!;
        controller.selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 7,
        );
        final before = controller.value;
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ShareScreen)), same(screenState));
        expect(f.requests.where(_listRequest).length, listRequests);
        expect(tester.widget<TextField>(field).controller, same(controller));
        expect(controller.value, before);
        expect(
          find.text(
            join
                ? ShareUiCopy.joinWorkspaceTitle()
                : ShareUiCopy.createWorkspaceTitle(),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('known service error is displayed once and changes locale live', (
    tester,
  ) async {
    final f = _Fixture(
      handler: (request) async {
        if (_listRequest(request)) {
          return _json({'detail': 'No workspace access'}, 403);
        }
        return null;
      },
    );
    await f.pump(tester);
    expect(find.text('没有共享空间访问权限'), findsOneWidget);
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text('No workspace access.'), findsOneWidget);
  });

  testWidgets(
    'pending create and visible error feedback follow current locale',
    (tester) async {
      final held = Completer<http.Response>();
      final f = _Fixture(
        handler: (request) async {
          if (request.method == 'POST') return held.future;
          return null;
        },
      );
      await f.pump(tester);
      await f.openForm(tester);
      await tester.enterText(find.byType(TextField), 'Synthetic name');
      await tester.tap(
        find.widgetWithText(FilledButton, ShareUiCopy.actionCreate()),
      );
      await tester.pump();
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      held.complete(_json({'detail': 'Workspace name required'}, 400));
      await tester.pumpAndSettle();
      expect(
        find.text(
          ShareUiCopy.createWorkspaceFailed('Workspace name is required.'),
        ),
        findsOneWidget,
      );
      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(
        find.text(ShareUiCopy.createWorkspaceFailed('空间名称不能为空')),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Synthetic name',
      );
    },
  );

  for (final editPending in [false, true]) {
    testWidgets(
      'comment success ${editPending ? 'preserves later editing value' : 'clears original submission'}',
      (tester) async {
        final held = Completer<http.Response>();
        final f = _Fixture(
          handler: (request) async {
            if (request.method == 'POST' &&
                request.url.path.endsWith('/comments')) {
              return held.future;
            }
            return null;
          },
        );
        await f.pump(tester);
        await f.openCollaboration(tester);
        final field = find.byType(TextField);
        await tester.enterText(field, '  submitted text  ');
        final controller = tester.widget<TextField>(field).controller!;
        await tester.tap(find.byTooltip(ShareUiCopy.actionSend()));
        await tester.pump();
        if (editPending) {
          expect(tester.widget<TextField>(field).enabled, isNot(false));
          await tester.enterText(field, '  submitted text  plus a new draft');
          controller.selection = const TextSelection(
            baseOffset: 4,
            extentOffset: 10,
          );
        }
        final pendingValue = controller.value;
        held.complete(
          _json({'id': 'comment-synthetic', 'body': 'submitted text'}),
        );
        await tester.pumpAndSettle();
        if (editPending) {
          expect(controller.value, pendingValue);
        } else {
          expect(controller.text, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('first legacy server ID keeps the retained create lease valid', (
    tester,
  ) async {
    final f = _Fixture(legacy: true);
    await f.pump(tester);
    await f.openForm(tester);
    await tester.enterText(find.byType(TextField), 'Legacy draft');
    await tester.runAsync(
      () => f.auth.applyServerAccountSnapshot({
        'id': 'A',
        'username': 'synthetic-A',
      }),
    );
    await tester.pumpAndSettle();
    expect(f.auth.state.userId, 'A');
    await tester.tap(
      find.widgetWithText(FilledButton, ShareUiCopy.actionCreate()),
    );
    await tester.pumpAndSettle();
    expect(
      f.requests.where(
        (r) => r.method == 'POST' && r.url.path == '/api/workspaces',
      ),
      hasLength(1),
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'retained mention callback cannot reauthorize into replacement provider',
    (tester) async {
      final f = _Fixture();
      await f.pump(tester);
      await tester.tap(find.byTooltip(ShareUiCopy.mentionInboxTooltip(1)));
      await tester.pumpAndSettle();
      final oldTap = tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Synthetic mention'))
          .onTap!;
      final replacement = f.makeAuth('B');
      f.auth = replacement;
      await f.pump(tester);
      final writesBefore = f.requests.where((r) => r.method != 'GET').length;
      oldTap();
      await tester.pumpAndSettle();
      expect(f.requests.where((r) => r.method != 'GET').length, writesBefore);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mention in [false, true]) {
    testWidgets(
      'covered ${mention ? 'mention' : 'collaboration'} load cannot open another sheet',
      (tester) async {
        final held = Completer<http.Response>();
        var hold = false;
        final f = _Fixture(
          handler: (request) async {
            if (hold && request.url.path.endsWith('/comments')) {
              return held.future;
            }
            return null;
          },
        );
        await f.pump(tester);
        if (mention) {
          await tester.tap(find.byTooltip(ShareUiCopy.mentionInboxTooltip(1)));
          await tester.pumpAndSettle();
          hold = true;
          await tester.tap(find.widgetWithText(ListTile, 'Synthetic mention'));
        } else {
          hold = true;
          await tester.tap(find.byTooltip(ShareUiCopy.collaborationTooltip()));
        }
        await tester.pump();
        final cover = MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Unrelated route')),
        );
        unawaited(f.navigator.currentState!.push(cover));
        await tester.pumpAndSettle();
        held.complete(_json([]));
        await tester.pumpAndSettle();
        expect(cover.isCurrent, isTrue);
        expect(find.text('Unrelated route'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('current mention opens its original collaboration context', (
    tester,
  ) async {
    final f = _Fixture();
    await f.pump(tester);
    await tester.tap(find.byTooltip(ShareUiCopy.mentionInboxTooltip(1)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Synthetic mention'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(ShareUiCopy.mentionContextTitle()), findsOneWidget);
    expect(find.text('synthetic-target'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final join in [false, true]) {
    testWidgets('covered ${join ? 'join' : 'create'} callback cannot submit', (
      tester,
    ) async {
      final f = _Fixture();
      await f.pump(tester);
      await f.openForm(tester, join: join);
      await tester.enterText(find.byType(TextField), 'Synthetic draft');
      final submit = tester
          .widget<FilledButton>(
            find.widgetWithText(
              FilledButton,
              join ? ShareUiCopy.actionJoin() : ShareUiCopy.actionCreate(),
            ),
          )
          .onPressed!;
      unawaited(
        f.navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Unrelated route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      submit();
      await tester.pumpAndSettle();
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets('covered comment callback cannot submit', (tester) async {
    final f = _Fixture();
    await f.pump(tester);
    await f.openCollaboration(tester);
    await tester.enterText(find.byType(TextField), 'Synthetic draft');
    final send = tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                widget.tooltip == ShareUiCopy.actionSend(),
          ),
        )
        .onPressed!;
    unawaited(
      f.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Unrelated route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    send();
    await tester.pumpAndSettle();
    expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final mention in [false, true]) {
    testWidgets(
      'covered ${mention ? 'mention' : 'comment'} error cannot announce on unrelated route',
      (tester) async {
        final held = Completer<http.Response>();
        final f = _Fixture(
          handler: (request) async =>
              request.method == 'POST' ? held.future : null,
        );
        await f.pump(tester);
        if (mention) {
          await tester.tap(find.byTooltip(ShareUiCopy.mentionInboxTooltip(1)));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ListTile, 'Synthetic mention'));
        } else {
          await f.openCollaboration(tester);
          await tester.enterText(find.byType(TextField), 'Synthetic draft');
          await tester.tap(find.byTooltip(ShareUiCopy.actionSend()));
        }
        await tester.pump();
        unawaited(
          f.navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Unrelated route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        held.complete(_json({'detail': 'private-diagnostic'}, 503));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text('Unrelated route'), findsOneWidget);
      },
    );
  }

  for (final flow in ['create', 'join', 'invite']) {
    testWidgets(
      'covered successful $flow can finish without duplicate request',
      (tester) async {
        final held = Completer<http.Response>();
        final f = _Fixture(
          handler: (request) async =>
              request.method == 'POST' ? held.future : null,
        );
        await f.pump(tester);
        if (flow == 'invite') {
          await tester.tap(find.byTooltip(ShareUiCopy.createInviteTooltip()));
          await tester.pumpAndSettle();
        } else {
          await f.openForm(tester, join: flow == 'join');
          await tester.enterText(find.byType(TextField), 'Synthetic accepted');
        }
        final submitLabel = switch (flow) {
          'invite' => ShareUiCopy.actionGenerate(),
          'join' => ShareUiCopy.actionJoin(),
          _ => ShareUiCopy.actionCreate(),
        };
        final submit = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, submitLabel),
            )
            .onPressed!;
        submit();
        await tester.pump();
        unawaited(
          f.navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Unrelated route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        held.complete(
          _json({
            'id': 'synthetic-accepted',
            'workspace_id': 'space',
            'code': 'synthetic-invite',
            'role': 'viewer',
          }),
        );
        await tester.pumpAndSettle();
        expect(find.text('Unrelated route'), findsOneWidget);
        f.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        // A retained callback from the initial form cannot repeat a successful
        // remote write after its completion state has become visible.
        submit();
        await tester.pumpAndSettle();
        expect(f.requests.where((r) => r.method == 'POST'), hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(768, 600),
  ]) {
    testWidgets(
      'long members and empty collaboration fit $size at 1.6 text scale',
      (tester) async {
        I18n.setLocale(AppLocale.en);
        final f = _Fixture(longMember: true, textScale: 1.6);
        await f.pump(tester, size: size);
        expect(tester.takeException(), isNull);
        await f.openCollaboration(tester);
        expect(find.text(ShareUiCopy.memberLeaderboardEmpty()), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  if (Platform.environment['DUOYI_SHARE_SCREENSHOTS'] == '1') {
    for (final sample in [
      (size: const Size(320, 640), locale: AppLocale.zh),
      (size: const Size(390, 844), locale: AppLocale.en),
      (size: const Size(768, 600), locale: AppLocale.en),
    ]) {
      testWidgets('share surfaces evidence ${sample.size} ${sample.locale}', (
        tester,
      ) async {
        await tester.runAsync(loadWidgetPolishScreenshotFonts);
        I18n.setLocale(sample.locale);
        final f = _Fixture(
          longMember: true,
          textScale: 1.6,
          evidenceFonts: true,
        );
        await f.pump(tester, size: sample.size);
        expect(tester.takeException(), isNull);
        await _captureShare(
          tester,
          f,
          'spaces-${sample.size.width.toInt()}-${sample.locale.name}',
        );
        await f.openCollaboration(tester);
        expect(tester.takeException(), isNull);
        await _captureShare(
          tester,
          f,
          'collaboration-${sample.size.width.toInt()}-${sample.locale.name}',
        );
      });
    }
  }
}

Future<void> _captureShare(
  WidgetTester tester,
  _Fixture fixture,
  String name,
) async {
  await tester.runAsync(() async {
    final boundary =
        fixture.captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    try {
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final directory =
          Platform.environment['DUOYI_SHARE_SCREENSHOT_DIR'] ??
          'evidence/screenshots/share-space-20261012';
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}

bool _listRequest(http.Request r) =>
    r.method == 'GET' && r.url.path == '/api/workspaces';
http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Fixture {
  final Future<http.Response?> Function(http.Request)? handler;
  final bool longMember;
  final double textScale;
  final bool evidenceFonts;
  final requests = <http.Request>[];
  final navigator = GlobalKey<NavigatorState>();
  final captureKey = GlobalKey();
  final theme = ThemeProvider();
  late AuthProvider auth;
  late final ShareProvider share;
  final auths = <AuthProvider>[];
  bool registered = false;

  _Fixture({
    this.handler,
    this.longMember = false,
    this.textScale = 1,
    this.evidenceFonts = false,
    bool legacy = false,
  }) {
    auth = makeAuth(legacy ? null : 'A');
    share = ShareProvider()
      ..apiClientGetter = (() => auth.client)
      ..userIdGetter = (() => auth.state.userId);
  }

  AuthProvider makeAuth(String? id) {
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-${id ?? 'legacy'}',
      httpClient: MockClient((request) async {
        requests.add(request);
        final override = await handler?.call(request);
        if (override != null) return override;
        if (_listRequest(request)) {
          return _json([
            {
              'id': 'space',
              'name': 'Synthetic Space',
              'owner_user_id': id ?? 'A',
              'members': [
                {
                  'workspace_id': 'space',
                  'user_id': id ?? 'A',
                  'username': longMember
                      ? 'Very long synthetic member name ' * 8
                      : 'Synthetic member',
                  'role': 'owner',
                },
              ],
            },
          ]);
        }
        if (request.url.path == '/api/workspaces/mentions') {
          return _json([
            {
              'id': 1,
              'workspace_id': 'space',
              'workspace_name': 'Synthetic Space',
              'target_id': 'synthetic-target',
              'body': 'Synthetic mention',
              'author_name': 'Synthetic author',
            },
          ]);
        }
        return _json(request.method == 'GET' ? [] : {});
      }),
    );
    final next = AuthProvider(
      client: client,
      initialState: AuthState(
        userId: id,
        username: 'synthetic-${id ?? 'legacy'}',
        token: client.token,
      ),
    );
    auths.add(next);
    return next;
  }

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(390, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    if (!registered) {
      registered = true;
      addTearDown(() {
        tester.view.reset();
        share.dispose();
        theme.dispose();
        for (final auth in auths) {
          auth.dispose();
        }
      });
    }
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ShareProvider>.value(value: share),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          theme: evidenceFonts
              ? theme.brand.theme.copyWith(
                  textTheme: theme.brand.theme.textTheme.apply(
                    fontFamily: 'DuoyiScreenshotLatin',
                    fontFamilyFallback: const ['DuoyiScreenshot'],
                  ),
                  primaryTextTheme: theme.brand.theme.primaryTextTheme.apply(
                    fontFamily: 'DuoyiScreenshotLatin',
                    fontFamilyFallback: const ['DuoyiScreenshot'],
                  ),
                )
              : theme.brand.theme,
          builder: (context, child) => RepaintBoundary(
            key: captureKey,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
          home: const BrandRouteSurface(child: ShareScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openForm(WidgetTester tester, {bool join = false}) async {
    await tester.tap(
      join
          ? find.byTooltip(ShareUiCopy.actionJoinTooltip())
          : find.widgetWithText(FilledButton, ShareUiCopy.actionNew()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCollaboration(WidgetTester tester) async {
    final control = find.byTooltip(ShareUiCopy.collaborationTooltip());
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    expect(control.hitTestable(), findsOneWidget);
    await tester.tap(control);
    await tester.pumpAndSettle();
  }
}
