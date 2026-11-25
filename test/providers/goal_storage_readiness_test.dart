import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(AccountPreferenceWrites.drain);

  test(
    'boundary load settles before cleanup and rehydrates its surviving owner',
    () async {
      final provider = GoalProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      final prefs = await SharedPreferences.getInstance();
      await AccountPreferenceWrites.boundary(() async {
        await prefs.setStringList('duoyi_goals', [
          jsonEncode(GoalItem(id: 'remote', title: 'Remote goal').toJson()),
        ]);
        await provider.loadFromStorage().timeout(const Duration(seconds: 1));
        expect(provider.isStorageHydrated, isFalse);
        expect(provider.goals, isEmpty);
      });
      await _settle();
      expect(provider.isStorageHydrated, isTrue);
      expect(provider.goals.single.id, 'remote');
    },
  );

  for (final invalidation in ['account', 'reset', 'dispose']) {
    test('deferred load cannot survive $invalidation invalidation', () async {
      final provider = GoalProvider();
      if (invalidation != 'dispose') addTearDown(provider.dispose);
      await provider.loadFromStorage();
      final revision = provider.storageReadRevision;
      await AccountPreferenceWrites.boundary(() async {
        await provider.loadFromStorage();
        switch (invalidation) {
          case 'account':
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          case 'reset':
            provider.resetLocalState();
          case 'dispose':
            provider.dispose();
        }
      });
      await _settle();
      expect(provider.isStorageHydrated, isFalse);
      expect(provider.storageReadRevision, revision + 1);
    });
  }

  test('multiple boundary loads coalesce to the newest read', () async {
    final provider = GoalProvider();
    addTearDown(provider.dispose);
    await provider.loadFromStorage();
    await AccountPreferenceWrites.boundary(() async {
      await provider.loadFromStorage();
      await provider.loadFromStorage();
      await provider.loadFromStorage();
    });
    await _settle();
    expect(provider.isStorageHydrated, isTrue);
    expect(provider.storageReadRevision, 5);
  });

  test(
    'a boundary entered during an awaited read defers publication',
    () async {
      final store = _HeldStore();
      SharedPreferencesStorePlatform.instance = store;
      final provider = GoalProvider();
      addTearDown(provider.dispose);
      final loading = provider.loadFromStorage();
      await store.started.future;
      await AccountPreferenceWrites.boundary(() async {
        store.release.complete();
        await loading.timeout(const Duration(seconds: 1));
        expect(provider.isStorageHydrated, isFalse);
      });
      await _settle();
      expect(provider.isStorageHydrated, isTrue);
      expect(provider.storageReadRevision, 2);
    },
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _HeldStore extends InMemorySharedPreferencesStore {
  _HeldStore() : super.withData({});
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<Map<String, Object>> getAll() async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.getAll();
  }
}
