import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/user_profile.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ProfileStore store;
  late UserProvider user;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _ProfileStore();
    SharedPreferencesStorePlatform.instance = store;
    user = UserProvider();
  });
  tearDown(() async {
    user.dispose();
    await AccountPreferenceWrites.drain();
  });

  Future<SharedPreferences> seed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'user_profile',
      jsonEncode(
        UserProfile(
          username: 'prior',
          displayName: 'literal / 原文',
          avatarUrl: 'prior.png',
          totalFocusMinutes: 77,
          bio: 'prior biography',
        ).toJson(),
      ),
    );
    await user.loadFromStorage();
    store.profileWrites = 0;
    return prefs;
  }

  test(
    'profile publication and mutation notice wait for storage acknowledgement',
    () async {
      final prefs = await seed();
      var persisted = 0;
      user.onLocalMutationPersisted = () => persisted++;
      store.hold = true;
      final saving = user.updateProfile(
        username: 'next',
        avatarUrl: 'next.png',
      );
      await store.started.future;
      expect(user.profile.username, 'prior');
      expect(user.profile.avatarUrl, 'prior.png');
      expect(persisted, 0);
      store.release.complete();
      await saving;
      expect(user.profile.username, 'next');
      expect(user.profile.avatarUrl, 'next.png');
      expect(_stored(prefs).avatarUrl, 'next.png');
      expect(persisted, 1);
    },
  );

  for (final throws in [false, true]) {
    test(
      'rejected profile persistence $throws keeps prior state and allows retry',
      () async {
        final prefs = await seed();
        var persisted = 0;
        user.onLocalMutationPersisted = () => persisted++;
        store.reject = true;
        store.throws = throws;
        await expectLater(
          user.updateProfile(username: 'next', avatarUrl: 'next.png'),
          throwsStateError,
        );
        expect(user.profile.username, 'prior');
        expect(user.profile.avatarUrl, 'prior.png');
        expect(_stored(prefs).username, 'prior');
        expect(persisted, 0);
        await user.updateProfile(username: 'next', avatarUrl: 'next.png');
        expect(user.profile.username, 'next');
        expect(_stored(prefs).avatarUrl, 'next.png');
        expect(persisted, 1);
      },
    );
  }

  test('cold partial profile save hydrates untouched stored fields', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'user_profile',
      jsonEncode(
        UserProfile(
          username: 'stored',
          avatarUrl: 'stored.png',
          bio: 'stored biography',
          totalFocusMinutes: 120,
        ).toJson(),
      ),
    );
    await user.updateProfile(username: 'next');
    expect(user.profile.avatarUrl, 'stored.png');
    expect(user.profile.bio, 'stored biography');
    expect(_stored(prefs).totalFocusMinutes, 120);
  });

  test(
    'queued profile changes merge against the last acknowledged state',
    () async {
      final prefs = await seed();
      store.hold = true;
      final first = user.updateProfile(
        username: 'one',
        displayName: 'first name',
      );
      await store.started.future;
      final second = user.updateProfile(
        username: 'two',
        bio: 'second biography',
      );
      expect(store.profileWrites, 1);
      store.release.complete();
      await Future.wait([first, second]);
      expect(user.profile.username, 'two');
      expect(user.profile.displayName, 'first name');
      expect(user.profile.bio, 'second biography');
      expect(_stored(prefs).displayName, 'first name');
    },
  );

  test('held profile save preserves newer stats and sync timestamp', () async {
    final prefs = await seed();
    store.hold = true;
    final saving = user.updateProfile(username: 'next');
    await store.started.future;
    final sync = DateTime.utc(2026, 10, 12, 12);
    user.recalc(
      completedTodos: 9,
      totalFocusMinutes: 90,
      currentStreak: 2,
      bestStreak: 4,
    );
    user.updateLastSyncTime(sync);
    user.recalc(
      completedTodos: 10,
      totalFocusMinutes: 100,
      currentStreak: 3,
      bestStreak: 5,
    );
    final newerSync = sync.add(const Duration(minutes: 1));
    user.updateLastSyncTime(newerSync);
    expect(user.profile.username, 'prior');
    expect(user.profile.totalTodosCompleted, 10);
    store.release.complete();
    await saving;
    await AccountPreferenceWrites.drain();
    expect(user.profile.username, 'next');
    expect(user.profile.totalFocusMinutes, 100);
    expect(user.profile.lastSyncTime, newerSync);
    expect(_stored(prefs).totalTodosCompleted, 10);
    expect(_stored(prefs).lastSyncTime, newerSync);
  });

  test(
    'cleanup drains issued profile save and cancels its queued follower',
    () async {
      final prefs = await seed();
      store.hold = true;
      var persisted = 0;
      user.onLocalMutationPersisted = () => persisted++;
      final first = user.updateProfile(username: 'departing');
      final firstRejected = expectLater(
        first,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await store.started.future;
      final follower = user.updateProfile(username: 'queued-old');
      final followerRejected = expectLater(
        follower,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      var cleaned = false;
      final cleanup = AccountLocalDataCleaner.runPreferenceBoundary(() async {
        user.resetLocalState();
        await user.clearAccountProfileCache();
        await AccountLocalDataCleaner.clearSharedPreferences();
        cleaned = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isFalse);
      store.release.complete();
      await Future.wait([firstRejected, followerRejected, cleanup]);
      expect(prefs.getString('user_profile'), isNull);
      expect(user.profile.avatarUrl, isEmpty);
      expect(persisted, 0);
      await user.updateProfile(username: 'new-account');
      expect(_stored(prefs).username, 'new-account');
    },
  );

  test(
    'reset rejects a queued profile before issuing a platform write',
    () async {
      final saving = user.updateProfile(username: 'stale');
      final rejected = expectLater(
        saving,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      user.resetLocalState();
      await rejected;
      expect(store.profileWrites, 0);
      expect(user.profile.username, '用户');
    },
  );

  test(
    'derived updates during cleanup do not throw or write account keys',
    () async {
      final prefs = await seed();
      await AccountPreferenceWrites.boundary(() async {
        expect(() => user.recalc(completedTodos: 5), returnsNormally);
        expect(
          () => user.updateLastSyncTime(DateTime.utc(2026)),
          returnsNormally,
        );
        await user.clearAccountProfileCache();
        await prefs.remove('user_profile');
      });
      await AccountPreferenceWrites.drain();
      expect(prefs.getString('user_profile'), isNull);
      expect(store.profileWrites, 0);
    },
  );

  for (final profileAcknowledges in [false, true]) {
    test(
      'reload accepts newer stored derived fields after acknowledgement via profile=$profileAcknowledges',
      () async {
        final prefs = await seed();
        store.reject = profileAcknowledges;
        user.recalc(completedTodos: 5);
        await AccountPreferenceWrites.drain();
        store.reject = profileAcknowledges;
        user.updateLastSyncTime(DateTime.utc(2026, 10, 10));
        await AccountPreferenceWrites.drain();
        if (profileAcknowledges) {
          await user.updateProfile(username: 'acknowledged');
        }
        await prefs.setString(
          'user_profile',
          jsonEncode(
            UserProfile(
              username: 'imported',
              totalTodosCompleted: 99,
              lastSyncTime: DateTime.utc(2026, 10, 12),
            ).toJson(),
          ),
        );
        await user.loadFromStorage();
        expect(user.profile.totalTodosCompleted, 99);
        expect(user.profile.lastSyncTime, DateTime.utc(2026, 10, 12));
      },
    );
  }

  test('unchanged stats retry a rejected derived save', () async {
    final prefs = await seed();
    store.reject = true;
    user.recalc(completedTodos: 12);
    await AccountPreferenceWrites.drain();
    expect(_stored(prefs).totalTodosCompleted, 0);
    user.recalc(completedTodos: 12);
    await AccountPreferenceWrites.drain();
    expect(_stored(prefs).totalTodosCompleted, 12);
  });
}

UserProfile _stored(SharedPreferences prefs) =>
    UserProfile.fromJson(jsonDecode(prefs.getString('user_profile')!));

class _ProfileStore extends InMemorySharedPreferencesStore {
  _ProfileStore() : super.withData({});
  bool hold = false;
  bool reject = false;
  bool throws = false;
  int profileWrites = 0;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != 'flutter.user_profile') return super.setValue(type, key, value);
    profileWrites++;
    if (hold && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    await super.setValue(type, key, value);
    if (reject) {
      reject = false;
      if (throws) throw StateError('synthetic profile failure');
      return false;
    }
    return true;
  }
}
