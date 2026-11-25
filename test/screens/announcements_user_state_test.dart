import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/announcements_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/widget_polish_screenshot_font.dart';

const _loadFailedZh = '公告加载失败，请重试';
const _loadFailedEn = 'Could not load announcements. Try again.';
const _refreshFailedZh = '刷新未完成，仍显示上次加载的公告。';
const _refreshFailedEn =
    'Could not refresh. Showing the previously loaded announcements.';
const _serverDetail = 'PRIVATE SERVER DETAIL must not be displayed';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'guest list survives live locale changes without another request',
    (tester) async {
      final account = _AccountFixture(token: null);
      final initial = account.holdNext();
      final harness = _Harness([account]);
      await harness.mount(tester);

      try {
        await tester.pump();
        await _waitForStart(tester, initial);
        initial.complete(_listResponse(_longAnnouncementList()));
        await tester.pumpAndSettle();

        final title = 'Literal server title 标题 A';
        final body = 'Literal server body 原文 A';
        expect(find.text(title), findsOneWidget);
        expect(find.text(body), findsOneWidget);
        expect(account.requests, hasLength(1));
        expect(account.requests.single.method, 'GET');
        expect(account.requests.single.url.path, '/api/announcements');
        expect(
          account.requests.single.headers.keys.any(
            (key) => key.toLowerCase() == 'authorization',
          ),
          isFalse,
        );

        final scrollable = find
            .descendant(
              of: find.byType(RefreshIndicator),
              matching: find.byType(Scrollable),
            )
            .first;
        final scrollState = tester.state<ScrollableState>(scrollable);
        final retainedTitle = find.text('Announcement 8 标题');
        await tester.scrollUntilVisible(
          retainedTitle,
          240,
          scrollable: scrollable,
          maxScrolls: 20,
        );
        await tester.pumpAndSettle();
        final retainedBody = 'Server body 8 原始内容保留。这是一段用于检查滚动位置的公告正文。';
        expect(retainedTitle, findsOneWidget);
        expect(find.text(retainedBody), findsOneWidget);
        final offset = scrollState.position.pixels;

        for (final locale in [AppLocale.en, AppLocale.zh, AppLocale.en]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(
            identical(tester.state<ScrollableState>(scrollable), scrollState),
            isTrue,
          );
          expect(scrollState.position.pixels, closeTo(offset, 0.01));
          expect(retainedTitle, findsOneWidget);
          expect(find.text(retainedBody), findsOneWidget);
          expect(account.requests, hasLength(1));
        }
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'initial error copy updates with locale and hides server detail',
    (tester) async {
      final account = _AccountFixture(token: null);
      final initial = account.respondNext(_errorResponse());
      final harness = _Harness([account]);
      await harness.mount(tester);

      try {
        await tester.pump();
        await _waitForStart(tester, initial);
        await tester.pumpAndSettle();
        expect(find.text(_loadFailedZh), findsOneWidget);
        expect(find.textContaining(_serverDetail), findsNothing);

        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expect(find.text(_loadFailedEn), findsOneWidget);
        expect(find.textContaining(_serverDetail), findsNothing);
        expect(account.requests, hasLength(1));
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets('refresh error keeps cached rows and Retry replaces them', (
    tester,
  ) async {
    final account = _AccountFixture(token: null);
    final initial = account.respondNext(_listResponse(_rows('Cached A')));
    final refreshFailure = account.holdNext();
    final retrySuccess = account.holdNext();
    final harness = _Harness([account]);
    await harness.mount(tester);

    try {
      await tester.pump();
      await _waitForStart(tester, initial);
      await tester.pumpAndSettle();
      expect(find.text('Cached A title'), findsOneWidget);

      final refresh = _refresh(tester);
      await tester.pump();
      await _waitForStart(tester, refreshFailure);
      refreshFailure.complete(_errorResponse());
      await tester.pumpAndSettle();
      await refresh;

      expect(find.text('Cached A title'), findsOneWidget);
      expect(find.text(_refreshFailedZh), findsOneWidget);
      expect(find.textContaining(_serverDetail), findsNothing);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pump();
      await _waitForStart(tester, retrySuccess);
      retrySuccess.complete(_listResponse(_rows('Fresh B')));
      await tester.pumpAndSettle();

      expect(find.text('Fresh B title'), findsOneWidget);
      expect(find.text('Cached A title'), findsNothing);
      expect(find.text(_refreshFailedZh), findsNothing);
      expect(account.requests, hasLength(3));
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('newer refresh success is not replaced by older failure', (
    tester,
  ) async {
    final account = _AccountFixture(token: null);
    final initial = account.respondNext(_listResponse(_rows('Initial')));
    final olderFailure = account.holdNext();
    final newerSuccess = account.holdNext();
    final harness = _Harness([account]);
    await harness.mount(tester);

    try {
      await tester.pump();
      await _waitForStart(tester, initial);
      await tester.pumpAndSettle();

      final firstRefresh = _refresh(tester);
      await tester.pump();
      await _waitForStart(tester, olderFailure);
      final secondRefresh = _refresh(tester);
      await tester.pump();
      await _waitForStart(tester, newerSuccess);

      newerSuccess.complete(_listResponse(_rows('Newest')));
      await tester.pumpAndSettle();
      await secondRefresh;
      expect(find.text('Newest title'), findsOneWidget);

      olderFailure.complete(_errorResponse());
      await tester.pumpAndSettle();
      await firstRefresh;
      expect(find.text('Newest title'), findsOneWidget);
      expect(find.text(_refreshFailedZh), findsNothing);
      expect(find.textContaining(_serverDetail), findsNothing);
      expect(account.requests, hasLength(3));
    } finally {
      await harness.dispose(tester);
    }
  });

  for (final cached in [false, true]) {
    for (final fails in [false, true]) {
      testWidgets(
        'locale change retains ${cached ? 'refresh' : 'initial load'} with ${fails ? 'failure' : 'success'}',
        (tester) async {
          final account = _AccountFixture(token: null);
          if (cached) account.respondNext(_listResponse(_rows('Cached')));
          final held = account.holdNext();
          final harness = _Harness([account]);
          await harness.mount(tester);
          try {
            await tester.pump();
            if (cached) {
              await tester.pumpAndSettle();
              expect(find.text('Cached title'), findsOneWidget);
              unawaited(_refresh(tester));
              await tester.pump();
            }
            await _waitForStart(tester, held);
            final state = tester.state(find.byType(AnnouncementsScreen));
            final requests = account.requests.length;
            I18n.setLocale(AppLocale.en);
            // A progress indicator is intentionally still animating.
            await tester.pump();
            expect(tester.state(find.byType(AnnouncementsScreen)), same(state));
            expect(account.requests, hasLength(requests));
            expect(
              find.text(
                cached ? 'Updating announcements…' : 'Loading announcements…',
              ),
              findsOneWidget,
            );
            held.complete(
              fails ? _errorResponse() : _listResponse(_rows('Current')),
            );
            await tester.pumpAndSettle();
            expect(account.requests, hasLength(requests));
            expect(
              find.byKey(const ValueKey('announcements_loading')),
              findsNothing,
            );
            if (fails) {
              expect(
                find.text(cached ? _refreshFailedEn : _loadFailedEn),
                findsOneWidget,
              );
              expect(find.text('Retry'), findsOneWidget);
              if (cached) expect(find.text('Cached title'), findsOneWidget);
            } else {
              expect(find.text('Current title'), findsOneWidget);
              expect(find.text('Cached title'), findsNothing);
            }
            expect(tester.takeException(), isNull);
          } finally {
            held.complete(_listResponse(const []));
            await harness.dispose(tester);
          }
        },
      );
    }
  }

  for (final lateFailure in [false, true]) {
    testWidgets(
      'provider replacement discards delayed account A ${lateFailure ? 'failure' : 'success'}',
      (tester) async {
        final accountA = _AccountFixture(token: 'session-A');
        final heldA = accountA.holdNext();
        final accountB = _AccountFixture(token: 'session-B');
        final responseB = accountB.respondNext(
          _listResponse(_rows('Account B')),
        );
        final harness = _Harness([accountA]);
        await harness.mount(tester);

        try {
          await tester.pump();
          await _waitForStart(tester, heldA);

          harness.replaceAuth(accountB);
          await tester.pump();
          await _waitForStart(tester, responseB);
          await tester.pumpAndSettle();
          expect(find.text('Account B title'), findsOneWidget);
          expect(accountB.requests, hasLength(1));
          expect(
            accountB.requests.single.headers['authorization'],
            'Bearer session-B',
          );

          heldA.complete(
            lateFailure
                ? _errorResponse()
                : _listResponse(_rows('Stale account A')),
          );
          await tester.pumpAndSettle();

          expect(find.text('Account B title'), findsOneWidget);
          expect(find.text('Stale account A title'), findsNothing);
          expect(find.text(_loadFailedZh), findsNothing);
          expect(find.text(_refreshFailedZh), findsNothing);
          expect(find.textContaining(_serverDetail), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await harness.dispose(tester);
          accountB.dispose();
        }
      },
    );
  }

  testWidgets('account boundary delays loading and resolves against new auth', (
    tester,
  ) async {
    late Completer<void> boundaryStarted;
    late Completer<void> boundaryRelease;
    late Future<void> boundary;
    await tester.runAsync(() async {
      boundaryStarted = Completer<void>();
      boundaryRelease = Completer<void>();
      boundary = AccountLocalDataCleaner.runPreferenceBoundary(() async {
        boundaryStarted.complete();
        await boundaryRelease.future;
      });
      await boundaryStarted.future;
    });

    final accountA = _AccountFixture(token: 'session-A');
    final accountB = _AccountFixture(token: 'session-B');
    final responseB = accountB.respondNext(
      _listResponse(_rows('After boundary')),
    );
    final harness = _Harness([accountA, accountB]);
    await harness.mount(tester);

    try {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(accountA.requests, isEmpty);
      expect(accountB.requests, isEmpty);

      harness.replaceAuth(accountB);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(accountA.requests, isEmpty);
      expect(accountB.requests, isEmpty);

      await tester.runAsync(() async {
        boundaryRelease.complete();
        await boundary;
      });
      await tester.pump();
      await _waitForStart(tester, responseB);
      await tester.pumpAndSettle();

      expect(accountA.requests, isEmpty);
      expect(accountB.requests, hasLength(1));
      expect(find.text('After boundary title'), findsOneWidget);
      expect(find.text('Account A title'), findsNothing);
    } finally {
      await tester.runAsync(() async {
        if (!boundaryRelease.isCompleted) boundaryRelease.complete();
        await boundary;
      });
      await harness.dispose(tester);
    }
  });

  for (final lateFailure in [false, true]) {
    testWidgets(
      'late ${lateFailure ? 'failure' : 'success'} after disposal is ignored',
      (tester) async {
        final account = _AccountFixture(token: null);
        final held = account.holdNext();
        final harness = _Harness([account]);
        await harness.mount(tester);

        await tester.pump();
        await _waitForStart(tester, held);
        await tester.pumpWidget(const SizedBox.shrink());
        held.complete(
          lateFailure
              ? _errorResponse()
              : _listResponse(_rows('Disposed page')),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(AnnouncementsScreen), findsNothing);
        await harness.dispose(tester, alreadyUnmounted: true);
      },
    );
  }

  testWidgets('cached error layout fits compact screens at large text scale', (
    tester,
  ) async {
    final capture =
        Platform.environment['DUOYI_CAPTURE_USER_ANNOUNCEMENT_SCREENSHOTS'] ==
        '1';
    if (capture) await tester.runAsync(loadWidgetPolishScreenshotFonts);

    for (final size in [const Size(320, 844), const Size(568, 320)]) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final account = _AccountFixture(token: null);
        final initial = account.respondNext(_listResponse(_rows('Cached')));
        final refreshFailure = account.respondNext(_errorResponse());
        final harness = _Harness(
          [account],
          textScale: 1.6,
          screenshotTheme: capture,
        );
        await harness.mount(tester, size: size);

        try {
          await tester.pump();
          await _waitForStart(tester, initial);
          await tester.pumpAndSettle();
          final refresh = _refresh(tester);
          await tester.pump();
          await _waitForStart(tester, refreshFailure);
          await tester.pumpAndSettle();
          await refresh;

          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          final scrollable = find
              .descendant(
                of: find.byType(RefreshIndicator),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            find.text('Cached title'),
            180,
            scrollable: scrollable,
          );
          expect(find.text('Cached title'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('announcements_retry')),
            -180,
            scrollable: scrollable,
          );
          await Scrollable.ensureVisible(
            tester.element(find.byKey(const ValueKey('announcements_retry'))),
            alignment: 1,
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              locale == AppLocale.en ? _refreshFailedEn : _refreshFailedZh,
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          if (capture) {
            final label =
                '${size.width.toInt()}x${size.height.toInt()}-1_6-${locale.name}';
            await _captureScreenshot(tester, harness.captureKey, label);
          }
        } finally {
          await harness.dispose(tester);
        }
      }
    }
  });
}

Future<void> _waitForStart(WidgetTester tester, _Reply reply) async {
  await tester.runAsync(
    () => reply.started.future.timeout(const Duration(seconds: 3)),
  );
}

Future<void> _refresh(WidgetTester tester) =>
    tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();

Future<void> _captureScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'evidence/screenshots/announcements-user-20261016/$name.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

http.Response _listResponse(List<Map<String, dynamic>> rows) => http.Response(
  jsonEncode(rows),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

http.Response _errorResponse() => http.Response(
  jsonEncode({'detail': _serverDetail}),
  503,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

List<Map<String, dynamic>> _rows(String prefix) => [
  {
    'id': 1,
    'title': '$prefix title',
    'body': '$prefix body',
    'level': 'info',
    'created_at': '2026-10-15T12:00:00Z',
  },
];

List<Map<String, dynamic>> _longAnnouncementList() => List.generate(
  18,
  (index) => {
    'id': index + 1,
    'title': index == 0
        ? 'Literal server title 标题 A'
        : 'Announcement $index 标题',
    'body': index == 0
        ? 'Literal server body 原文 A'
        : 'Server body $index 原始内容保留。这是一段用于检查滚动位置的公告正文。',
    'level': 'info',
    'created_at': '2026-10-15T12:00:00Z',
  },
);

class _Reply {
  _Reply();

  final Completer<void> started = Completer<void>();
  final Completer<http.Response> _response = Completer<http.Response>();

  factory _Reply.ready(http.Response response) => _Reply()..complete(response);

  Future<http.Response> receive() {
    if (!started.isCompleted) started.complete();
    return _response.future;
  }

  void complete(http.Response response) {
    if (!_response.isCompleted) _response.complete(response);
  }
}

class _AccountFixture {
  _AccountFixture({required this.token}) {
    transport = MockClient(_handle);
    client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: token,
      httpClient: transport,
    );
    auth = AuthProvider(
      client: client,
      initialState: AuthState(
        userId: token == null ? null : 'user-$token',
        username: token == null ? null : 'account-$token',
        token: token,
      ),
    );
  }

  final String? token;
  final Queue<_Reply> _replies = Queue<_Reply>();
  final List<http.Request> requests = [];
  late final MockClient transport;
  late final ApiClient client;
  late final AuthProvider auth;
  bool _disposed = false;

  _Reply holdNext() {
    final reply = _Reply();
    _replies.add(reply);
    return reply;
  }

  _Reply respondNext(http.Response response) {
    final reply = _Reply.ready(response);
    _replies.add(reply);
    return reply;
  }

  Future<http.Response> _handle(http.Request request) {
    requests.add(request);
    final reply = _replies.isEmpty
        ? _Reply.ready(_listResponse(const []))
        : _replies.removeFirst();
    return reply.receive();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    auth.dispose();
    transport.close();
  }
}

class _Harness {
  _Harness(this.accounts, {this.textScale = 1, this.screenshotTheme = false})
    : theme = ThemeProvider();

  final List<_AccountFixture> accounts;
  final double textScale;
  final bool screenshotTheme;
  final ThemeProvider theme;
  final GlobalKey<_AnnouncementHostState> hostKey =
      GlobalKey<_AnnouncementHostState>();
  final GlobalKey captureKey = GlobalKey();
  bool _mounted = false;

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    _mounted = true;
    await tester.pumpWidget(
      _AnnouncementHost(
        key: hostKey,
        auth: accounts.first.auth,
        theme: theme,
        textScale: textScale,
        screenshotTheme: screenshotTheme,
        captureKey: captureKey,
      ),
    );
  }

  void replaceAuth(_AccountFixture account) {
    if (!accounts.contains(account)) accounts.add(account);
    hostKey.currentState!.replaceAuth(account.auth);
  }

  Future<void> dispose(
    WidgetTester tester, {
    bool alreadyUnmounted = false,
  }) async {
    if (_mounted && !alreadyUnmounted) {
      await tester.pumpWidget(const SizedBox.shrink());
    }
    _mounted = false;
    for (final account in accounts) {
      account.dispose();
    }
    theme.dispose();
    tester.view.reset();
  }
}

class _AnnouncementHost extends StatefulWidget {
  const _AnnouncementHost({
    super.key,
    required this.auth,
    required this.theme,
    required this.textScale,
    required this.screenshotTheme,
    required this.captureKey,
  });

  final AuthProvider auth;
  final ThemeProvider theme;
  final double textScale;
  final bool screenshotTheme;
  final GlobalKey captureKey;

  @override
  State<_AnnouncementHost> createState() => _AnnouncementHostState();
}

class _AnnouncementHostState extends State<_AnnouncementHost> {
  late AuthProvider _auth = widget.auth;

  void replaceAuth(AuthProvider auth) => setState(() => _auth = auth);

  ThemeData get _appTheme {
    final brandTheme = widget.theme.brand.theme;
    if (!widget.screenshotTheme) return brandTheme;
    return brandTheme.copyWith(
      textTheme: _withScreenshotFonts(brandTheme.textTheme),
      primaryTextTheme: _withScreenshotFonts(brandTheme.primaryTextTheme),
    );
  }

  TextTheme _withScreenshotFonts(TextTheme text) {
    TextStyle? font(TextStyle? style) => style?.copyWith(
      fontFamily: 'DuoyiScreenshotLatin',
      fontFamilyFallback: const ['DuoyiScreenshot'],
    );
    return text.copyWith(
      displayLarge: font(text.displayLarge),
      displayMedium: font(text.displayMedium),
      displaySmall: font(text.displaySmall),
      headlineLarge: font(text.headlineLarge),
      headlineMedium: font(text.headlineMedium),
      headlineSmall: font(text.headlineSmall),
      titleLarge: font(text.titleLarge),
      titleMedium: font(text.titleMedium),
      titleSmall: font(text.titleSmall),
      bodyLarge: font(text.bodyLarge),
      bodyMedium: font(text.bodyMedium),
      bodySmall: font(text.bodySmall),
      labelLarge: font(text.labelLarge),
      labelMedium: font(text.labelMedium),
      labelSmall: font(text.labelSmall),
    );
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: _auth),
      ChangeNotifierProvider<ThemeProvider>.value(value: widget.theme),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _appTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(widget.textScale)),
        child: RepaintBoundary(key: widget.captureKey, child: child!),
      ),
      home: const BrandRouteSurface(child: AnnouncementsScreen()),
    ),
  );
}
