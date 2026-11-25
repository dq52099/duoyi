import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/share_ui_copy.dart';
import 'package:duoyi/models/workspace.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final mutation in _Mutation.values) {
    test('$mutation refreshes despite a fresh cached workspace list', () async {
      var reads = 0;
      final f = _Fixture((request) async {
        if (_isWorkspaceRead(request)) return _workspace(++reads);
        return _defaultResponse(request);
      });
      addTearDown(f.dispose);
      await f.provider.load();
      await f.provider.load();
      expect(reads, 1);
      await _mutate(f.provider, mutation);
      expect(reads, 2);
      expect(f.provider.workspaces.single.name, 'Workspace 2');
    });
  }

  test(
    'mutations waiting for an earlier GET share one fresh followup',
    () async {
      final first = Completer<http.Response>();
      var reads = 0;
      var writes = 0;
      final f = _Fixture((request) async {
        if (_isWorkspaceRead(request)) {
          reads++;
          return reads == 1 ? first.future : _workspace(reads);
        }
        if (request.method != 'GET') writes++;
        return _defaultResponse(request);
      });
      addTearDown(f.dispose);
      final oldLoad = f.provider.load();
      final a = f.provider.createWorkspace('A');
      final b = f.provider.acceptInvite('synthetic-code');
      await _until(() => writes == 2);
      expect(reads, 1);
      first.complete(_workspace(1));
      await Future.wait([oldLoad, a, b]);
      expect(reads, 2);
      expect(f.provider.workspaces.single.name, 'Workspace 2');
    },
  );

  test(
    'a mutation after followup starts schedules another fresh GET',
    () async {
      final held = <int, Completer<http.Response>>{
        1: Completer<http.Response>(),
        2: Completer<http.Response>(),
        3: Completer<http.Response>(),
      };
      var reads = 0;
      var writes = 0;
      final f = _Fixture((request) async {
        if (_isWorkspaceRead(request)) return held[++reads]!.future;
        if (request.method != 'GET') writes++;
        return _defaultResponse(request);
      });
      addTearDown(f.dispose);
      final oldLoad = f.provider.load();
      final a = f.provider.createWorkspace('A');
      await _until(() => writes == 1);
      held[1]!.complete(_workspace(1));
      await _until(() => reads == 2);
      final b = f.provider.createWorkspace('B');
      await _until(() => writes == 2);
      held[2]!.complete(_workspace(2));
      await _until(() => reads == 3);
      held[3]!.complete(_workspace(3));
      await Future.wait([oldLoad, a, b]);
      expect(reads, 3);
      expect(f.provider.workspaces.single.name, 'Workspace 3');
    },
  );

  for (final oldFails in [false, true]) {
    test(
      'old account completion cannot release new loading: error=$oldFails',
      () async {
        final old = Completer<http.Response>();
        final next = Completer<http.Response>();
        var reads = 0;
        final f = _Fixture((request) async {
          if (_isWorkspaceRead(request)) {
            reads++;
            return request.headers['Authorization'] == 'Bearer synthetic-A'
                ? old.future
                : next.future;
          }
          return _defaultResponse(request);
        });
        addTearDown(f.dispose);
        final before = f.provider.load();
        await _until(() => reads == 1);
        f.provider.resetLocalState();
        f.account = 'B';
        f.client.token = 'synthetic-B';
        final after = f.provider.load();
        await _until(() => reads == 2);
        old.complete(oldFails ? _errorResponse() : _workspace(1));
        await before;
        expect(f.provider.loading, isTrue);
        expect(f.provider.lastError, isNull);
        expect(f.provider.workspaces, isEmpty);
        expect(f.provider.load(), same(after));
        next.complete(_workspace(2));
        await after;
        expect(f.provider.loading, isFalse);
        expect(f.provider.workspaces.single.name, 'Workspace 2');
      },
    );
  }

  for (final interruption in ['reset', 'dispose', 'token']) {
    test(
      '$interruption cancels a queued mutation refresh without another GET',
      () async {
        final read = Completer<http.Response>();
        var reads = 0;
        var writes = 0;
        final f = _Fixture((request) async {
          if (_isWorkspaceRead(request)) {
            reads++;
            return read.future;
          }
          if (request.method != 'GET') writes++;
          return _defaultResponse(request);
        });
        var notices = 0;
        f.provider.addListener(() => notices++);
        final before = f.provider.load();
        final change = f.provider.createWorkspace('A');
        await _until(() => writes == 1);
        if (interruption == 'dispose') {
          f.dispose();
        } else if (interruption == 'reset') {
          f.provider.resetLocalState();
          f.account = 'B';
          f.client.token = 'synthetic-B';
        } else {
          f.client.token = 'synthetic-B';
        }
        final baseline = notices;
        read.complete(_workspace(1));
        await Future.wait([before, change]);
        expect(reads, 1);
        expect(notices, baseline);
        expect(f.provider.workspaces, isEmpty);
        if (interruption != 'dispose') f.dispose();
      },
    );
  }

  test('dispose during a POST suppresses refresh and notifications', () async {
    final posted = Completer<http.Response>();
    var reads = 0;
    var writes = 0;
    final f = _Fixture((request) async {
      if (_isWorkspaceRead(request)) reads++;
      if (request.method == 'POST') {
        writes++;
        return posted.future;
      }
      return _defaultResponse(request);
    });
    var notices = 0;
    f.provider.addListener(() => notices++);
    final change = f.provider.createWorkspace('A');
    await _until(() => writes == 1);
    f.dispose();
    posted.complete(http.Response('{}', 200));
    await change;
    await f.provider.load(force: true);
    expect(reads, 0);
    expect(notices, 0);
  });

  test('reentrant loading listener joins the published Future', () async {
    final read = Completer<http.Response>();
    var reads = 0;
    final f = _Fixture((request) async {
      if (_isWorkspaceRead(request)) {
        reads++;
        return read.future;
      }
      return _defaultResponse(request);
    });
    addTearDown(f.dispose);
    Future<void>? joined;
    f.provider.addListener(() {
      if (f.provider.loading) joined = f.provider.load();
    });
    final original = f.provider.load();
    expect(joined, same(original));
    read.complete(_workspace(1));
    await original;
    expect(reads, 1);
  });

  test('first server ID preserves a legacy session load', () async {
    final read = Completer<http.Response>();
    var reads = 0;
    final f = _Fixture((request) async {
      if (_isWorkspaceRead(request)) {
        reads++;
        return read.future;
      }
      return _defaultResponse(request);
    });
    addTearDown(f.dispose);
    f.account = '';
    final pending = f.provider.load();
    await _until(() => reads == 1);
    f.account = 'A';
    read.complete(_workspace(1));
    await pending;
    expect(f.provider.workspaces.single.name, 'Workspace 1');
    expect(f.provider.loading, isFalse);
  });

  test('stored service errors localize without another HTTP request', () async {
    var reads = 0;
    final f = _Fixture((request) async {
      if (_isWorkspaceRead(request)) {
        reads++;
        return _errorResponse();
      }
      return _defaultResponse(request);
    });
    addTearDown(f.dispose);
    I18n.setLocale(AppLocale.zh);
    await f.provider.load();
    final chinese = f.provider.lastError;
    expect(chinese, contains('共享空间'));
    expect(chinese, isNot(contains('private-diagnostic')));
    I18n.setLocale(AppLocale.en);
    expect(f.provider.lastError, ShareUiCopy.serviceUnavailable(AppLocale.en));
    expect(f.provider.lastError, isNot(chinese));
    expect(reads, 1);
  });
}

enum _Mutation { create, join, role, remove }

Future<void> _mutate(ShareProvider provider, _Mutation mutation) =>
    switch (mutation) {
      _Mutation.create => provider.createWorkspace('Synthetic'),
      _Mutation.join => provider.acceptInvite('synthetic-code'),
      _Mutation.role => provider.updateMemberRole(
        'space',
        'member',
        WorkspaceRole.editor,
      ),
      _Mutation.remove => provider.removeMember('space', 'member'),
    };

class _Fixture {
  String account = 'A';
  late final ApiClient client;
  late final ShareProvider provider;
  _Fixture(Future<http.Response> Function(http.Request) handler) {
    client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-A',
      httpClient: MockClient(handler),
    );
    provider = ShareProvider()
      ..apiClientGetter = (() => client)
      ..userIdGetter = (() => account);
  }
  void dispose() => provider.dispose();
}

bool _isWorkspaceRead(http.Request request) =>
    request.method == 'GET' && request.url.path == '/api/workspaces';

http.Response _workspace(int revision) => http.Response(
  jsonEncode([
    {
      'id': 'space',
      'name': 'Workspace $revision',
      'owner_user_id': 'A',
      'created_at': '2026-10-12T00:00:00Z',
      'updated_at': '2026-10-12T00:00:00Z',
    },
  ]),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _defaultResponse(http.Request request) => http.Response(
  request.method == 'GET' ? '[]' : '{}',
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _errorResponse() => http.Response(
  '{"detail":"private-diagnostic"}',
  503,
  headers: {'content-type': 'application/json'},
);

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: 'The expected request did not start.');
}
