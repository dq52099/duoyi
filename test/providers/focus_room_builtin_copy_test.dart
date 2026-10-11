import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/focus_room.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/focus_room_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _copyKey = 'builtinRoomCopy';

Map<String, dynamic> _envelope(List<FocusRoom> rooms, {Object? metadata}) => {
  'rooms': rooms.map((room) => room.toJson()).toList(),
  'joinedRoomIds': [FocusRoomProvider.defaultRoomId],
  'activeRoomId': FocusRoomProvider.defaultRoomId,
  _copyKey: ?metadata,
};

Map<String, dynamic> _metadata(Map<String, Object?> rooms) => {
  'version': 1,
  'rooms': rooms,
};

FocusRoom _roomWithRaw(FocusRoom room, {String? name, String? description}) =>
    FocusRoom.fromJson({
      ...room.toJson(),
      'name': ?name,
      'description': ?description,
    });

Future<FocusRoomProvider> _load(Map<String, dynamic> envelope) async {
  SharedPreferences.setMockInitialValues({
    FocusRoomProvider.storageKey: jsonEncode(envelope),
  });
  final provider = FocusRoomProvider();
  addTearDown(provider.dispose);
  await provider.loadFromStorage();
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocale savedLocale;
  late List<FocusRoom> defaults;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    savedLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
    final provider = FocusRoomProvider();
    defaults = provider.rooms;
    provider.dispose();
  });
  tearDown(() => I18n.setLocale(savedLocale));

  for (final kind in FocusRoomBuiltinKind.values) {
    test(
      'explicit ${kind.name} display preserves raw room and member JSON',
      () {
        final room = defaults.singleWhere((room) => room.id == kind.roomId);
        final raw = jsonEncode(room.toJson());
        expect(room.builtinKind, kind);
        expect(room.nameFor(AppLocale.zh), room.name);
        expect(room.descriptionFor(AppLocale.zh), room.description);
        expect(room.nameFor(AppLocale.en), kind.nameFor(AppLocale.en));
        expect(
          room.descriptionFor(AppLocale.en),
          kind.descriptionFor(AppLocale.en),
        );
        expect(room.nameFor(AppLocale.en), isNot(room.name));
        expect(I18n.current, AppLocale.zh);
        expect(jsonEncode(room.toJson()), raw);
        expect(room.toJson().keys, isNot(contains(_copyKey)));

        final decoded = FocusRoom.fromJson({
          ...room.toJson(),
          'builtinKind': kind.storageCode,
          _copyKey: _metadata({room.id: kind.storageCode}),
        });
        expect(decoded.builtinKind, isNull);
        expect(decoded.nameFor(AppLocale.en), room.name);
        expect(decoded.descriptionFor(AppLocale.en), room.description);
        expect(jsonEncode(decoded.toJson()), raw);
      },
    );
  }

  test('mismatching raw identity invalidates explicit provenance', () {
    final source = defaults.first;
    for (final json in [
      {...source.toJson(), 'id': 'authored-room'},
      {...source.toJson(), 'name': '用户修改名称'},
      {...source.toJson(), 'description': '用户修改说明'},
    ]) {
      final room = FocusRoom.fromJson(
        json,
      ).withBuiltinKind(FocusRoomBuiltinKind.deepWork);
      expect(room.builtinKind, isNull);
      expect(room.nameFor(AppLocale.en), room.name);
      expect(room.descriptionFor(AppLocale.en), room.description);
    }
  });

  test(
    'real save and reload retain generated copy without locale side effects',
    () async {
      final provider = FocusRoomProvider();
      addTearDown(provider.dispose);
      var localChanges = 0;
      var notifications = 0;
      provider.onLocalChanged = () => localChanges++;
      provider.addListener(() => notifications++);
      await provider.joinRoom('reading_room');
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(FocusRoomProvider.storageKey)!;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      expect(saved['rooms'], defaults.map((room) => room.toJson()).toList());
      expect(
        saved[_copyKey],
        _metadata({
          for (final kind in FocusRoomBuiltinKind.values)
            kind.roomId: kind.storageCode,
        }),
      );
      final currentLocalChanges = localChanges;
      final currentNotifications = notifications;
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        for (final room in provider.rooms) {
          expect(room.nameFor(locale), room.builtinKind!.nameFor(locale));
        }
        expect(prefs.getString(FocusRoomProvider.storageKey), raw);
        expect(localChanges, currentLocalChanges);
        expect(notifications, currentNotifications);
      }
      final reloaded = FocusRoomProvider();
      addTearDown(reloaded.dispose);
      await reloaded.loadFromStorage();
      expect(reloaded.activeRoomId, 'reading_room');
      expect(reloaded.joinedRoomIds, provider.joinedRoomIds);
      for (final room in reloaded.rooms) {
        final original = provider.roomById(room.id)!;
        expect(room.builtinKind, original.builtinKind);
        expect(room.nameFor(AppLocale.en), original.nameFor(AppLocale.en));
        expect(
          room.descriptionFor(AppLocale.en),
          original.descriptionFor(AppLocale.en),
        );
        expect(room.toJson(), original.toJson());
      }
      expect(prefs.getString(FocusRoomProvider.storageKey), raw);
    },
  );

  test('legacy canonical rooms remain literal after a real save', () async {
    final provider = await _load(_envelope(defaults));
    for (final room in provider.rooms) {
      expect(room.builtinKind, isNull);
      expect(room.nameFor(AppLocale.en), room.name);
      expect(room.descriptionFor(AppLocale.en), room.description);
    }
    await provider.joinRoom('reading_room');
    final prefs = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(prefs.getString(FocusRoomProvider.storageKey)!) as Map;
    expect(saved.containsKey(_copyKey), isFalse);
    expect(saved['rooms'], defaults.map((room) => room.toJson()).toList());
  });

  test(
    'authored same-name local room retains literal copy and values',
    () async {
      final provider = FocusRoomProvider();
      addTearDown(provider.dispose);
      final authored = await provider.createRoom(
        name: defaults.first.name,
        description: defaults.first.description,
        weeklyTargetMinutes: 77,
      );
      expect(authored.builtinKind, isNull);
      expect(authored.nameFor(AppLocale.en), authored.name);
      expect(authored.weeklyTargetSeconds, 77 * 60);
      final reloaded = FocusRoomProvider();
      addTearDown(reloaded.dispose);
      await reloaded.loadFromStorage();
      final stored = reloaded.roomById(authored.id)!;
      expect(stored.builtinKind, isNull);
      expect(stored.toJson(), authored.toJson());
    },
  );

  final invalidMetadata = <String, Object?>{
    'unknown version': {
      'version': 2,
      'rooms': {'deep_work_room': 'deep_work'},
    },
    'string version': {
      'version': '1',
      'rooms': {'deep_work_room': 'deep_work'},
    },
    'double version': {
      'version': 1.0,
      'rooms': {'deep_work_room': 'deep_work'},
    },
    'non map': 'deep_work',
    'non map rooms': {
      'version': 1,
      'rooms': ['deep_work'],
    },
    'unknown code': _metadata({'deep_work_room': 'other'}),
    'non string code': _metadata({'deep_work_room': 1}),
    'wrong code and id': _metadata({'deep_work_room': 'reading'}),
    'missing room marker': _metadata({'missing_room': 'deep_work'}),
  };
  for (final entry in invalidMetadata.entries) {
    test(
      '${entry.key} metadata keeps stored room literal and membership intact',
      () async {
        final provider = await _load(
          _envelope(defaults, metadata: entry.value),
        );
        final room = provider.roomById(FocusRoomProvider.defaultRoomId)!;
        expect(room.builtinKind, isNull);
        expect(room.nameFor(AppLocale.en), room.name);
        expect(room.descriptionFor(AppLocale.en), room.description);
        expect(provider.activeRoomId, room.id);
        expect(provider.joinedRoomIds, {room.id});
      },
    );
  }

  test(
    'mixed valid and invalid metadata restores only the explicit valid entry',
    () async {
      final provider = await _load(
        _envelope(
          defaults,
          metadata: _metadata({
            'deep_work_room': 'deep_work',
            'reading_room': 'exam_sprint',
          }),
        ),
      );
      expect(
        provider.roomById('deep_work_room')!.builtinKind,
        FocusRoomBuiltinKind.deepWork,
      );
      expect(provider.roomById('reading_room')!.builtinKind, isNull);
      expect(provider.roomById('exam_sprint_room')!.builtinKind, isNull);
    },
  );

  for (final changeName in [true, false]) {
    test(
      'changed raw ${changeName ? 'name' : 'description'} clears stale persisted marker',
      () async {
        final modified = _roomWithRaw(
          defaults.first,
          name: changeName ? '用户更改标题' : null,
          description: changeName ? null : '用户更改说明',
        );
        final provider = await _load(
          _envelope(
            [modified, ...defaults.skip(1)],
            metadata: _metadata({
              for (final kind in FocusRoomBuiltinKind.values)
                kind.roomId: kind.storageCode,
            }),
          ),
        );
        final room = provider.roomById(modified.id)!;
        expect(room.builtinKind, isNull);
        expect(room.nameFor(AppLocale.en), modified.name);
        expect(room.descriptionFor(AppLocale.en), modified.description);
        await provider.joinRoom('reading_room');
        final prefs = await SharedPreferences.getInstance();
        final saved =
            jsonDecode(prefs.getString(FocusRoomProvider.storageKey)!) as Map;
        expect((saved[_copyKey] as Map)['rooms'], isNot(contains(modified.id)));
        final reloaded = FocusRoomProvider();
        addTearDown(reloaded.dispose);
        await reloaded.loadFromStorage();
        expect(reloaded.roomById(modified.id)!.builtinKind, isNull);
        expect(reloaded.roomById(modified.id)!.toJson(), modified.toJson());
      },
    );
  }

  for (final canonical in [true, false]) {
    test(
      'actual invite DTO and same-id remote ${canonical ? 'canonical' : 'authored'} overwrite discard local provenance',
      () async {
        final provider = FocusRoomProvider();
        addTearDown(provider.dispose);
        final original = provider.roomById(FocusRoomProvider.defaultRoomId)!;
        final payload = {
          'code': 'FIXTURE',
          'room': {
            ...original.toJson(),
            if (!canonical) 'name': '远端自定义名称',
            _copyKey: _metadata({original.id: 'deep_work'}),
            'builtinKind': 'deep_work',
          },
          'ranking': {'room_id': original.id, 'entries': []},
        };
        final requests = <String>[];
        final client = ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'fixture-token',
          httpClient: MockClient((request) async {
            requests.add('${request.method} ${request.url.path}');
            return http.Response(
              jsonEncode(payload),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        provider.apiClientGetter = () => client;
        final remote = FocusRoomInviteAcceptResult.fromJson(payload).room;
        expect(remote.builtinKind, isNull);
        await provider.acceptInviteCode('FIXTURE', displayName: '测试账号');
        expect(requests, ['POST /api/focus-room-invites/FIXTURE/accept']);
        final room = provider.roomById(original.id)!;
        expect(room.builtinKind, isNull);
        expect(
          room.nameFor(AppLocale.en),
          canonical ? original.name : '远端自定义名称',
        );
        expect(room.descriptionFor(AppLocale.en), original.description);
        expect(room.members, same(original.members));
        expect(room.createdAt, original.createdAt);
        final prefs = await SharedPreferences.getInstance();
        final saved =
            jsonDecode(prefs.getString(FocusRoomProvider.storageKey)!) as Map;
        expect((saved[_copyKey] as Map)['rooms'], isNot(contains(original.id)));
        final reloaded = FocusRoomProvider();
        addTearDown(reloaded.dispose);
        await reloaded.loadFromStorage();
        expect(reloaded.roomById(original.id)!.builtinKind, isNull);
        expect(reloaded.roomById(original.id)!.toJson(), room.toJson());
      },
    );
  }

  test(
    'real invite requests send identical raw payloads in both locales',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final room = defaults.first;
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'fixture-token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/focus-rooms/${room.id}/invites');
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({'room': room.toJson()}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        I18n.setLocale(locale);
        expect(bodies.length, locale == AppLocale.zh ? 0 : 1);
        final result = await FocusRoomApi(client).createInvite(room: room);
        expect(result.room.builtinKind, isNull);
        expect(result.room.nameFor(AppLocale.en), room.name);
      }
      expect(bodies, hasLength(2));
      expect(bodies.first, bodies.last);
      expect(bodies.first['room_name'], room.name);
      expect(bodies.first['roomName'], room.name);
      expect(bodies.first['description'], room.description);
      expect(bodies.first['weekly_target_seconds'], room.weeklyTargetSeconds);
      expect(bodies.first['accent_color'], room.accentColor);
      expect(bodies.first.containsKey(_copyKey), isFalse);
    },
  );
}
