import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/announcements_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final lateFailure in [false, true]) {
    testWidgets(
      'same AuthProvider A to B to A rejects delayed old A ${lateFailure ? 'failure' : 'success'}',
      (tester) async {
        final account = _AuthFixture(token: 'session-A');
        final oldA = account.holdNext();
        final b = account.respondNext(_listResponse(_rows('Account B')));
        final newA = account.respondNext(
          _listResponse(_rows('Account A fresh')),
        );
        final fixture = _Harness(account);
        await fixture.mount(tester);

        try {
          await tester.pump();
          await _waitForStart(tester, oldA);

          account.useAccount(userId: 'B', token: 'session-B');
          await tester.pump();
          await _waitForStart(tester, b);
          await tester.pumpAndSettle();
          expect(find.text('Account B title'), findsOneWidget);

          account.useAccount(userId: 'A', token: 'session-A-returned');
          await tester.pump();
          await _waitForStart(tester, newA);
          await tester.pumpAndSettle();
          expect(find.text('Account A fresh title'), findsOneWidget);

          oldA.complete(
            lateFailure
                ? _errorResponse()
                : _listResponse(_rows('Account A stale')),
          );
          await tester.pumpAndSettle();

          expect(find.text('Account A fresh title'), findsOneWidget);
          expect(find.text('Account A stale title'), findsNothing);
          expect(find.text('公告加载失败，请重试'), findsNothing);
          expect(account.requests, hasLength(3));
          expect(account.requests.map(_authorization), [
            'Bearer session-A',
            'Bearer session-B',
            'Bearer session-A-returned',
          ]);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
    );
  }

  testWidgets('ordinary profile notification does not repeat the GET', (
    tester,
  ) async {
    final account = _AuthFixture(token: 'session-A');
    final initial = account.respondNext(_listResponse(_rows('Stable account')));
    final fixture = _Harness(account);
    await fixture.mount(tester);

    try {
      await tester.pump();
      await _waitForStart(tester, initial);
      await tester.pumpAndSettle();
      expect(find.text('Stable account title'), findsOneWidget);
      expect(account.requests, hasLength(1));

      account.auth.notifyProfileChanged();
      await tester.pumpAndSettle();

      expect(account.requests, hasLength(1));
      expect(find.text('Stable account title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('cleaner generation clears rows and rejects retained refresh', (
    tester,
  ) async {
    final account = _AuthFixture(token: 'session-A');
    final initial = account.respondNext(_listResponse(_rows('Before cleanup')));
    final postCleanup = account.holdNext();
    final fixture = _Harness(account);
    await fixture.mount(tester);

    try {
      await tester.pump();
      await _waitForStart(tester, initial);
      await tester.pumpAndSettle();
      final retainedRefresh = _refresh(tester);
      expect(find.text('Before cleanup title'), findsOneWidget);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await retainedRefresh();
      await tester.pump();
      await _waitForStart(tester, postCleanup);

      expect(find.text('Before cleanup title'), findsNothing);
      expect(account.requests, hasLength(2));

      postCleanup.complete(_listResponse(_rows('After cleanup')));
      await tester.pumpAndSettle();
      expect(find.text('After cleanup title'), findsOneWidget);
      expect(account.requests, hasLength(2));
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final initialBoundary in ['transition', 'blocked']) {
    testWidgets(
      '$initialBoundary auth dispatches no GET until stable, then exactly one',
      (tester) async {
        final account = _AuthFixture(
          token: 'session-A',
          changing: initialBoundary == 'transition',
          blocked: initialBoundary == 'blocked',
        );
        final stableResponse = account.holdNext();
        final fixture = _Harness(account);
        await fixture.mount(tester);

        try {
          await tester.pump();
          await tester.pump();
          expect(account.requests, isEmpty);

          account.auth.setAvailability(changing: false, blocked: false);
          await tester.pump();
          await _waitForStart(tester, stableResponse);
          expect(account.requests, hasLength(1));
          stableResponse.complete(
            _listResponse(_rows('Stable after boundary')),
          );
          await tester.pumpAndSettle();

          expect(account.requests, hasLength(1));
          expect(find.text('Stable after boundary title'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
    );
  }

  for (final invalidation in ['covered route', 'app lock', 'forced update']) {
    testWidgets(
      'retained refresh after $invalidation cannot dispatch another GET',
      (tester) async {
        final account = _AuthFixture(token: 'session-A');
        final initial = account.respondNext(_listResponse(_rows('Visible')));
        final fixture = _Harness(account);
        await fixture.mount(tester);

        try {
          await tester.pump();
          await _waitForStart(tester, initial);
          await tester.pumpAndSettle();
          final retainedRefresh = _refresh(tester);

          switch (invalidation) {
            case 'covered route':
              fixture.navigatorKey.currentState!.push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('Covered announcements route')),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              break;
            case 'app lock':
              fixture.lock.setLocked(true);
              break;
            case 'forced update':
              fixture.updater.setMustUpdate(true);
              break;
          }

          await retainedRefresh();
          await tester.pumpAndSettle();
          expect(account.requests, hasLength(1));
          if (invalidation == 'covered route') {
            expect(find.text('Covered announcements route'), findsOneWidget);
            fixture.navigatorKey.currentState!.pop();
            await tester.pumpAndSettle();
          } else {
            expect(find.text('Visible title'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
    );
  }

  testWidgets(
    'covered held refresh does not commit, releases loading, and can refresh on return',
    (tester) async {
      final account = _AuthFixture(token: 'session-A');
      final initial = account.respondNext(_listResponse(_rows('Existing')));
      final heldRefresh = account.holdNext();
      final returnedRefresh = account.respondNext(
        _listResponse(_rows('Fresh after return')),
      );
      final fixture = _Harness(account);
      await fixture.mount(tester);

      try {
        await tester.pump();
        await _waitForStart(tester, initial);
        await tester.pumpAndSettle();

        final pendingRefresh = _refresh(tester)();
        await tester.pump();
        await _waitForStart(tester, heldRefresh);
        expect(
          find.byKey(const ValueKey('announcements_loading')),
          findsOneWidget,
        );

        fixture.navigatorKey.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Temporary cover')),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        heldRefresh.complete(_listResponse(_rows('Covered stale result')));
        await tester.pumpAndSettle();
        await pendingRefresh;

        expect(find.text('Temporary cover'), findsOneWidget);
        expect(find.text('Covered stale result title'), findsNothing);
        expect(account.requests, hasLength(2));
        expect(tester.takeException(), isNull);

        fixture.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text('Existing title'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('announcements_loading')),
          findsNothing,
        );

        final freshRequest = _refresh(tester)();
        await tester.pump();
        await _waitForStart(tester, returnedRefresh);
        await tester.pumpAndSettle();
        await freshRequest;

        expect(find.text('Fresh after return title'), findsOneWidget);
        expect(find.text('Existing title'), findsNothing);
        expect(account.requests, hasLength(3));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  for (final malformed in ['non-list response', 'malformed row']) {
    testWidgets('$malformed is reported as a localized load failure', (
      tester,
    ) async {
      final account = _AuthFixture(token: 'session-A');
      final response = account.respondNext(
        malformed == 'non-list response'
            ? _jsonResponse({'announcements': []})
            : _jsonResponse(['not an announcement object']),
      );
      final fixture = _Harness(account);
      await fixture.mount(tester);

      try {
        await tester.pump();
        await _waitForStart(tester, response);
        await tester.pumpAndSettle();
        expect(find.text('公告加载失败，请重试'), findsOneWidget);
        expect(find.text('暂无公告'), findsNothing);
        expect(account.requests, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets('successful empty response clears the old rows', (tester) async {
    final account = _AuthFixture(token: 'session-A');
    final initial = account.respondNext(_listResponse(_rows('Old row')));
    final empty = account.respondNext(_listResponse(const []));
    final fixture = _Harness(account);
    await fixture.mount(tester);

    try {
      await tester.pump();
      await _waitForStart(tester, initial);
      await tester.pumpAndSettle();
      expect(find.text('Old row title'), findsOneWidget);

      final refresh = _refresh(tester)();
      await tester.pump();
      await _waitForStart(tester, empty);
      await tester.pumpAndSettle();
      await refresh;

      expect(find.text('Old row title'), findsNothing);
      expect(find.text('暂无公告'), findsOneWidget);
      expect(account.requests, hasLength(2));
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('older finally cannot hide the newer refresh spinner', (
    tester,
  ) async {
    final account = _AuthFixture(token: 'session-A');
    final initial = account.respondNext(_listResponse(_rows('Initial')));
    final older = account.holdNext();
    final newer = account.holdNext();
    final fixture = _Harness(account);
    await fixture.mount(tester);

    try {
      await tester.pump();
      await _waitForStart(tester, initial);
      await tester.pumpAndSettle();

      final olderRefresh = _refresh(tester)();
      await tester.pump();
      await _waitForStart(tester, older);
      final newerRefresh = _refresh(tester)();
      await tester.pump();
      await _waitForStart(tester, newer);

      older.complete(_listResponse(_rows('Obsolete')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('announcements_loading')),
        findsOneWidget,
      );
      expect(find.text('Obsolete title'), findsNothing);

      newer.complete(_listResponse(_rows('Latest')));
      await tester.pumpAndSettle();
      await olderRefresh;
      await newerRefresh;

      expect(find.byKey(const ValueKey('announcements_loading')), findsNothing);
      expect(find.text('Latest title'), findsOneWidget);
      expect(find.text('Obsolete title'), findsNothing);
      expect(account.requests, hasLength(3));
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });
}

Future<void> _waitForStart(WidgetTester tester, _Reply reply) async {
  await tester.runAsync(
    () => reply.started.future.timeout(const Duration(seconds: 3)),
  );
}

Future<void> Function() _refresh(WidgetTester tester) =>
    tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;

String? _authorization(http.Request request) {
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == 'authorization') return entry.value;
  }
  return null;
}

http.Response _listResponse(List<Map<String, dynamic>> rows) =>
    _jsonResponse(rows);

http.Response _jsonResponse(Object? value) => http.Response(
  jsonEncode(value),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

http.Response _errorResponse() => http.Response(
  jsonEncode({'detail': 'synthetic account response detail'}),
  503,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

List<Map<String, dynamic>> _rows(String title) => [
  {
    'id': 1,
    'title': '$title title',
    'body': '$title body',
    'level': 'info',
    'created_at': '2026-10-16T12:00:00Z',
  },
];

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

class _AuthFixture {
  _AuthFixture({
    required String token,
    bool changing = false,
    bool blocked = false,
  }) {
    final client = _newClient(token);
    auth = _MutableAuth(
      client: client,
      initialState: _stateFor('A', token),
      changing: changing,
      blocked: blocked,
    );
  }

  final Queue<_Reply> _replies = Queue<_Reply>();
  final List<http.Request> requests = [];
  final List<MockClient> _transports = [];
  late final _MutableAuth auth;
  bool _disposed = false;

  ApiClient _newClient(String token) {
    final transport = MockClient(_handle);
    _transports.add(transport);
    return ApiClient(
      baseUrl: 'https://duoyi.test',
      token: token,
      httpClient: transport,
    );
  }

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

  void useAccount({required String userId, required String token}) {
    auth.useAccount(userId: userId, token: token, client: _newClient(token));
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
    for (final transport in _transports) {
      transport.close();
    }
  }
}

AuthState _stateFor(String userId, String token) =>
    AuthState(userId: userId, username: 'account-$userId', token: token);

class _MutableAuth extends AuthProvider {
  _MutableAuth({
    required ApiClient client,
    required super.initialState,
    required bool changing,
    required bool blocked,
  }) : _client = client,
       _fixtureState = initialState,
       _changing = changing,
       _blocked = blocked,
       super(client: client);

  ApiClient _client;
  AuthState _fixtureState;
  int _fixtureSession = 1;
  bool _changing;
  bool _blocked;

  @override
  ApiClient get client => _client;

  @override
  AuthState get state => _fixtureState;

  @override
  int get sessionGeneration => _fixtureSession;

  @override
  bool get isAccountTransitionInProgress => _changing;

  @override
  bool get isLocalAccountDataBlocked => _blocked;

  void useAccount({
    required String userId,
    required String token,
    required ApiClient client,
  }) {
    _fixtureState = _stateFor(userId, token);
    _client = client;
    _fixtureSession++;
    notifyListeners();
  }

  void notifyProfileChanged() => notifyListeners();

  void setAvailability({required bool changing, required bool blocked}) {
    _changing = changing;
    _blocked = blocked;
    _fixtureSession++;
    notifyListeners();
  }
}

class _Harness {
  _Harness(this.account)
    : theme = ThemeProvider(),
      lock = _TestLock(),
      updater = _TestUpdater();

  final _AuthFixture account;
  final ThemeProvider theme;
  final _TestLock lock;
  final _TestUpdater updater;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  bool _mounted = false;

  Future<void> mount(WidgetTester tester) async {
    _mounted = true;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: account.auth),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<AppLockProvider>.value(value: lock),
          ChangeNotifierProvider<AppUpdateService>.value(value: updater),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: theme.brand.theme,
          home: const BrandRouteSurface(child: AnnouncementsScreen()),
        ),
      ),
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_mounted) await tester.pumpWidget(const SizedBox.shrink());
    _mounted = false;
    account.dispose();
    theme.dispose();
    lock.dispose();
    updater.dispose();
    updater.transport.close();
  }
}

class _TestLock extends AppLockProvider {
  bool _locked = false;

  @override
  bool get isLocked => _locked;

  void setLocked(bool value) {
    _locked = value;
    notifyListeners();
  }
}

class _TestUpdater extends AppUpdateService {
  _TestUpdater() : this._(MockClient((_) async => http.Response('{}', 200)));

  _TestUpdater._(this.transport)
    : super(
        repo: 'duoyi/duoyi',
        currentVersion: '1.0.0',
        httpClient: transport,
      );

  final MockClient transport;
  bool _mustUpdate = false;

  @override
  bool get mustUpdate => _mustUpdate;

  void setMustUpdate(bool value) {
    _mustUpdate = value;
    notifyListeners();
  }
}
