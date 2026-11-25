// Synthetic delayed-response probe. Execute only with the shared Flutter lock.
import 'dart:async';
import 'dart:convert';

import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _roomId = FocusRoomProvider.defaultRoomId;
const _room = {
  'id': 'synthetic-remote-room',
  'name': 'Synthetic owner A room',
  'description': 'Synthetic test data',
  'weekly_target_seconds': 3600,
};
const _invite = {
  'id': 'synthetic-invite',
  'code': 'SYNTHETIC',
  'room': {'id': _roomId, 'name': 'Synthetic default room'},
};
const _friend = {
  'user_id': 'synthetic-friend-a',
  'username': 'synthetic-peer',
  'status': 'accepted',
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<void> _settle(Future<dynamic> future) async {
  try {
    await future;
  } on ApiException {
    // A stale operation may explicitly report account cancellation.
    // State, persistence, subsequent requests and loading ownership are tested.
  }
}

class _Harness {
  final entered = Completer<void>();
  final response = Completer<http.Response>();
  final requests = <String>[];
  final provider = FocusRoomProvider();
  late ApiClient client;
  late MockClient transport;
  int localChanges = 0;
  bool disposed = false;

  _Harness(String heldMethod, String heldPath, {bool emptyFriends = false}) {
    transport = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == heldMethod && request.url.path == heldPath) {
        if (!entered.isCompleted) entered.complete();
        return response.future;
      }
      if (request.url.path == '/api/focus-friends') {
        return _json(
          request.method == 'POST'
              ? _friend
              : {
                  'items': emptyFriends ? [] : [_friend],
                },
        );
      }
      if (request.method == 'POST' && request.url.path.endsWith('/invites')) {
        return _json(_invite);
      }
      if (request.url.path == '/api/focus-friends/requests') {
        return _json({'incoming': [], 'outgoing': []});
      }
      if (request.url.path == '/api/focus-leaderboard/friends') {
        return _json({'room_id': 'friends', 'entries': []});
      }
      return _json({});
    });
    client = _client('synthetic-owner-a');
    provider.apiClientGetter = () => client;
    provider.onLocalChanged = () => localChanges++;
    addTearDown(dispose);
  }

  ApiClient _client(String token) => ApiClient(
    baseUrl: 'https://synthetic.example.test',
    token: token,
    httpClient: transport,
  );

  void dispose() {
    if (!disposed) {
      disposed = true;
      provider.dispose();
    }
  }

  void switchOwner() {
    provider.resetLocalState();
    client = _client('synthetic-owner-b');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final switchOwner in [false, true]) {
    test('create invite account boundary reset=$switchOwner', () async {
      final h = _Harness('POST', '/api/focus-rooms/$_roomId/invites');
      final operation = _settle(h.provider.createInviteForRoom(_roomId));
      await h.entered.future;
      if (switchOwner) h.switchOwner();
      h.response.complete(_json(_invite));
      await operation;
      expect(h.provider.invitesForRoom(_roomId).length, switchOwner ? 0 : 1);
      expect(h.provider.lastRemoteError, isNull);
      expect(h.provider.remoteLoading, isFalse);
    });

    test('accept invite account persistence reset=$switchOwner', () async {
      final h = _Harness('POST', '/api/focus-room-invites/SYNTHETIC/accept');
      final operation = _settle(h.provider.acceptInviteCode('SYNTHETIC'));
      await h.entered.future;
      if (switchOwner) h.switchOwner();
      final prefs = await SharedPreferences.getInstance();
      if (switchOwner) {
        await prefs.setString(FocusRoomProvider.storageKey, 'owner-b-sentinel');
      }
      h.response.complete(
        _json({
          'code': 'SYNTHETIC',
          'room': _room,
          'ranking': {'room_id': _room['id'], 'entries': []},
        }),
      );
      await operation;
      expect(h.provider.roomById(_room['id'] as String) == null, switchOwner);
      expect(h.localChanges, switchOwner ? 0 : 1);
      if (switchOwner) {
        expect(h.provider.activeRoomId, _roomId);
        expect(
          prefs.getString(FocusRoomProvider.storageKey),
          'owner-b-sentinel',
        );
      } else {
        expect(h.provider.activeRoomId, _room['id']);
        expect(
          prefs.getString(FocusRoomProvider.storageKey),
          contains(_room['id']),
        );
      }
    });

    test('friend refresh account boundary reset=$switchOwner', () async {
      final h = _Harness('GET', '/api/focus-friends');
      final operation = h.provider.loadFocusFriendsAndRanking(force: true);
      await h.entered.future;
      if (switchOwner) h.switchOwner();
      h.response.complete(
        _json({
          'items': [_friend],
        }),
      );
      await operation;
      expect(h.provider.focusFriends.length, switchOwner ? 0 : 1);
      expect(h.provider.remoteFriendRankingActive, !switchOwner);
      if (switchOwner) {
        expect(h.requests, ['GET /api/focus-friends']);
        expect(h.provider.lastFriendSyncAt, isNull);
      }
      expect(h.provider.lastRemoteError, isNull);
    });

    test('friend mutation stops old followup reset=$switchOwner', () async {
      final h = _Harness('POST', '/api/focus-friends');
      final operation = _settle(h.provider.addFocusFriend('synthetic-peer'));
      await h.entered.future;
      if (switchOwner) h.switchOwner();
      h.response.complete(_json(_friend));
      await operation;
      expect(h.provider.focusFriends.length, switchOwner ? 0 : 1);
      if (switchOwner) expect(h.requests, ['POST /api/focus-friends']);
      expect(h.provider.lastRemoteError, isNull);
    });
  }

  for (final path in [
    '/api/focus-friends/requests',
    '/api/focus-leaderboard/friends',
  ]) {
    test('friend refresh discards later old response $path', () async {
      final h = _Harness('GET', path);
      final operation = h.provider.loadFocusFriendsAndRanking(force: true);
      await h.entered.future;
      h.switchOwner();
      h.response.complete(
        _json(
          path.endsWith('/requests')
              ? {'incoming': [], 'outgoing': []}
              : {'room_id': 'friends', 'entries': []},
        ),
      );
      await operation;
      expect(h.provider.focusFriends, isEmpty);
      expect(h.provider.remoteFriendRankingActive, isFalse);
      expect(h.provider.lastFriendSyncAt, isNull);
      expect(h.provider.lastRemoteError, isNull);
    });
  }

  test(
    'old invite error preserves new owner loading and diagnostics',
    () async {
      final oldEntered = Completer<void>();
      final newEntered = Completer<void>();
      final oldResponse = Completer<http.Response>();
      final newResponse = Completer<http.Response>();
      final provider = FocusRoomProvider();
      addTearDown(provider.dispose);
      final transport = MockClient((request) async {
        if (request.headers['authorization'] == 'Bearer synthetic-owner-a') {
          if (!oldEntered.isCompleted) oldEntered.complete();
          return oldResponse.future;
        }
        if (!newEntered.isCompleted) newEntered.complete();
        return newResponse.future;
      });
      ApiClient makeClient(String token) => ApiClient(
        baseUrl: 'https://synthetic.example.test',
        token: token,
        httpClient: transport,
      );
      var currentClient = makeClient('synthetic-owner-a');
      provider.apiClientGetter = () => currentClient;
      final oldOperation = _settle(provider.createInviteForRoom(_roomId));
      await oldEntered.future;
      provider.resetLocalState();
      currentClient = makeClient('synthetic-owner-b');
      final newOperation = _settle(provider.createInviteForRoom(_roomId));
      await newEntered.future;
      oldResponse.complete(_json({'detail': 'synthetic old owner error'}, 403));
      await oldOperation;
      final stillLoading = provider.remoteLoading;
      final oldError = provider.lastRemoteError;
      newResponse.complete(_json({..._invite, 'id': 'owner-b-invite'}));
      await newOperation;
      expect(stillLoading, isTrue);
      expect(oldError, isNull);
      expect(provider.invitesForRoom(_roomId).map((item) => item.id), [
        'owner-b-invite',
      ]);
    },
  );
  for (final action in ['accept', 'reject', 'cancel', 'remove']) {
    for (final reset in [false, true]) {
      test('friend $action boundary reset=$reset', () async {
        final method = action == 'cancel' || action == 'remove'
            ? 'DELETE'
            : 'POST';
        final path = switch (action) {
          'accept' => '/api/focus-friend-requests/synthetic-friend-a/accept',
          'reject' => '/api/focus-friend-requests/synthetic-other/reject',
          'cancel' => '/api/focus-friend-requests/synthetic-other',
          _ => '/api/focus-friends/synthetic-friend-a',
        };
        final h = _Harness(method, path, emptyFriends: action == 'remove');
        final operation = _settle(switch (action) {
          'accept' => h.provider.acceptFocusFriendRequest('synthetic-friend-a'),
          'reject' => h.provider.rejectFocusFriendRequest('synthetic-other'),
          'cancel' => h.provider.cancelFocusFriendRequest('synthetic-other'),
          _ => h.provider.removeFocusFriend('synthetic-friend-a'),
        });
        await h.entered.future;
        if (reset) h.switchOwner();
        h.response.complete(_json(_friend));
        await operation;
        expect(
          h.provider.focusFriends.length,
          reset || action == 'remove' ? 0 : 1,
        );
        expect(h.provider.remoteFriendRankingActive, !reset);
        expect(h.provider.lastFriendSyncAt == null, reset);
        expect(h.provider.lastRemoteError, isNull);
        if (reset) expect(h.requests, ['$method $path']);
      });
    }
  }

  for (final reset in [false, true]) {
    test('revoke invite boundary reset=$reset', () async {
      final h = _Harness('DELETE', '/api/focus-room-invites/synthetic-invite');
      await h.provider.createInviteForRoom(_roomId);
      expect(h.provider.invitesForRoom(_roomId).single.revoked, isFalse);
      final operation = _settle(
        h.provider.revokeInviteForRoom(_roomId, 'synthetic-invite'),
      );
      await h.entered.future;
      if (reset) h.switchOwner();
      h.response.complete(_json({}));
      await operation;
      if (reset) {
        expect(h.provider.invitesForRoom(_roomId), isEmpty);
      } else {
        expect(h.provider.invitesForRoom(_roomId).single.revoked, isTrue);
      }
      expect(h.provider.lastRemoteError, isNull);
    });

    test('load invites boundary reset=$reset', () async {
      final h = _Harness('GET', '/api/focus-rooms/$_roomId/invites');
      final operation = _settle(h.provider.loadInvitesForRoom(_roomId));
      await h.entered.future;
      if (reset) h.switchOwner();
      h.response.complete(
        _json({
          'items': [_invite],
        }),
      );
      await operation;
      expect(h.provider.invitesForRoom(_roomId).length, reset ? 0 : 1);
    });

    test('global ranking boundary reset=$reset', () async {
      final h = _Harness('GET', '/api/focus-leaderboard/global');
      final operation = h.provider.loadGlobalRanking(force: true);
      await h.entered.future;
      if (reset) h.switchOwner();
      h.response.complete(_json({'room_id': 'global', 'entries': []}));
      await operation;
      expect(h.provider.remoteGlobalRankingActive, !reset);
      expect(h.provider.lastGlobalSyncAt == null, reset);
      expect(h.provider.lastRemoteError, isNull);
    });

    test('room ranking boundary reset=$reset', () async {
      final h = _Harness('GET', '/api/focus-rooms/$_roomId/ranking');
      final operation = h.provider.loadRemoteRanking(
        _roomId,
        const [],
        force: true,
      );
      await h.entered.future;
      if (reset) h.switchOwner();
      h.response.complete(_json({'room_id': _roomId, 'entries': []}));
      await operation;
      expect(h.provider.effectiveRankingFor(_roomId, const []).remote, !reset);
      expect(h.provider.lastRemoteError, isNull);
    });

    test('heartbeat boundary reset=$reset', () async {
      final h = _Harness('POST', '/api/focus-rooms/$_roomId/heartbeat');
      final operation = h.provider.syncRemoteRankings(const [], force: true);
      await h.entered.future;
      if (reset) h.switchOwner();
      h.response.complete(_json({'room_id': _roomId, 'entries': []}));
      await operation;
      expect(h.provider.effectiveRankingFor(_roomId, const []).remote, !reset);
      expect(h.provider.remoteGlobalRankingActive, !reset);
      expect(h.provider.lastRemoteError, isNull);
      if (reset) {
        expect(h.requests, ['POST /api/focus-rooms/$_roomId/heartbeat']);
      }
    });

    for (final action in ['join', 'create', 'active', 'leave']) {
      test('local $action persistence boundary reset=$reset', () async {
        final h = _Harness('POST', '/api/focus-rooms/unused/heartbeat');
        final other = h.provider.rooms
            .firstWhere((room) => room.id != _roomId)
            .id;
        if (action == 'active' || action == 'leave') {
          await h.provider.joinRoom(other);
        }
        h.localChanges = 0;
        final prefs = await SharedPreferences.getInstance();
        final operation = _settle(switch (action) {
          'join' => h.provider.joinRoom(other),
          'create' => h.provider.createRoom(
            name: 'Synthetic local room',
            description: 'Synthetic',
            weeklyTargetMinutes: 30,
          ),
          'active' => h.provider.setActiveRoom(_roomId),
          _ => h.provider.leaveRoom(other),
        });
        if (reset) {
          h.switchOwner();
          await prefs.setString(
            FocusRoomProvider.storageKey,
            'owner-b-sentinel',
          );
        }
        await operation;
        expect(h.localChanges, reset ? 0 : 1);
        if (reset) {
          expect(h.provider.activeRoomId, _roomId);
          expect(
            prefs.getString(FocusRoomProvider.storageKey),
            'owner-b-sentinel',
          );
        } else {
          expect(
            prefs.getString(FocusRoomProvider.storageKey),
            isNot('owner-b-sentinel'),
          );
        }
      });
    }
  }

  for (final action in ['invites', 'room', 'friends', 'global']) {
    test(
      'old $action read failure leaves new account diagnostics clear',
      () async {
        final path = switch (action) {
          'invites' => '/api/focus-rooms/$_roomId/invites',
          'room' => '/api/focus-rooms/$_roomId/ranking',
          'friends' => '/api/focus-friends',
          _ => '/api/focus-leaderboard/global',
        };
        final h = _Harness('GET', path);
        final operation = _settle(switch (action) {
          'invites' => h.provider.loadInvitesForRoom(_roomId),
          'room' => h.provider.loadRemoteRanking(
            _roomId,
            const [],
            force: true,
          ),
          'friends' => h.provider.loadFocusFriendsAndRanking(force: true),
          _ => h.provider.loadGlobalRanking(force: true),
        });
        await h.entered.future;
        h.switchOwner();
        h.response.complete(
          _json({'detail': 'synthetic old owner error'}, 403),
        );
        await operation;
        expect(h.provider.lastRemoteError, isNull);
        expect(h.provider.fallbackToLocal, isFalse);
      },
    );
  }

  test(
    'late invite completion after disposal does not mutate caches',
    () async {
      final h = _Harness('POST', '/api/focus-rooms/$_roomId/invites');
      final operation = _settle(h.provider.createInviteForRoom(_roomId));
      await h.entered.future;
      h.dispose();
      h.response.complete(_json(_invite));
      await operation;
      expect(h.provider.invitesForRoom(_roomId), isEmpty);
    },
  );
}
