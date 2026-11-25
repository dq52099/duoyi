import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/recommended_goals.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Recommendation forwards the original write authority before storage',
    () async {
      final store = _Store();
      SharedPreferencesStorePlatform.instance = store;
      final provider = GoalProvider();
      addTearDown(provider.dispose);
      await expectLater(
        provider.applyRecommended(
          RecommendedGoalsLibrary.all().first,
          canWrite: () => false,
        ),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      expect(store.writes, 0);
      expect(provider.goals, isEmpty);
    },
  );

  test(
    'Recommendation rolls back if its authority expires during the write',
    () async {
      final store = _Store()..hold = true;
      SharedPreferencesStorePlatform.instance = store;
      final provider = GoalProvider();
      addTearDown(provider.dispose);
      var current = true;
      final pending = provider.applyRecommended(
        RecommendedGoalsLibrary.all().first,
        canWrite: () => current,
      );
      final rejected = expectLater(
        pending,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await store.started.future.timeout(const Duration(seconds: 5));
      expect(provider.goals, isEmpty);
      current = false;
      store.release.complete();
      await rejected;
      expect(provider.goals, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getStringList('duoyi_goals'), isNull);
    },
  );

  for (final throwsError in [false, true]) {
    test(
      'Rejected recommendation (${throwsError ? 'throw' : 'false'}) retries without a phantom goal',
      () async {
        final store = _Store()
          ..fail = true
          ..throwsError = throwsError;
        SharedPreferencesStorePlatform.instance = store;
        final provider = GoalProvider();
        addTearDown(provider.dispose);
        await expectLater(
          provider.applyRecommended(RecommendedGoalsLibrary.all().first),
          throwsStateError,
        );
        expect(provider.goals, isEmpty);
        final saved = await provider.applyRecommended(
          RecommendedGoalsLibrary.all().first,
        );
        expect(provider.goals.single.id, saved.id);
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        expect(prefs.getStringList('duoyi_goals'), hasLength(1));
        expect(
          jsonDecode(prefs.getStringList('duoyi_goals')!.single)['id'],
          saved.id,
        );
      },
    );
  }

  test('Revocation after commit preserves acknowledged success', () async {
    final provider = GoalProvider();
    addTearDown(provider.dispose);
    var current = true;
    provider.onLocalMutationPersisted = () => current = false;
    final saved = await provider.applyRecommended(
      RecommendedGoalsLibrary.all().first,
      canWrite: () => current,
    );
    expect(current, isFalse);
    expect(provider.goals.single.id, saved.id);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('duoyi_goals'), hasLength(1));
  });
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  bool hold = false;
  bool fail = false;
  bool throwsError = false;
  int writes = 0;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.duoyi_goals') {
      writes++;
      if (hold && !started.isCompleted) {
        started.complete();
        await release.future;
      }
      await super.setValue(type, key, value);
      if (fail) {
        fail = false;
        if (throwsError) throw StateError('Synthetic persistence failure');
        return false;
      }
      return true;
    }
    return super.setValue(type, key, value);
  }
}
