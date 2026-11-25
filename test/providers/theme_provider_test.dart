import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/domain_event_bus.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await AccountPreferenceWrites.drain();
  });

  for (final item in [
    (type: 'brand', id: 're0', active: 'activeBrand', cost: 140),
    (
      type: 'focus_backdrop',
      id: 'forest_focus',
      active: 'activeFocusBackdropId',
      cost: 100,
    ),
    (
      type: 'avatar_frame',
      id: 'forest_frame',
      active: 'activeAvatarFrameId',
      cost: 100,
    ),
    (type: 'card_skin', id: 'paper_card', active: 'activeCardSkinId', cost: 90),
  ]) {
    test(
      'guest ${item.type} redeem commits once and survives reload',
      () async {
        final theme = ThemeProvider();
        final rewards = AchievementProvider();
        addTearDown(theme.dispose);
        addTearDown(rewards.dispose);
        await _seedGuestRewards(rewards);
        expect(
          await _redeemGuest(
            theme,
            rewards,
            itemType: item.type,
            itemId: item.id,
          ),
          isTrue,
        );
        expect(
          await _redeemGuest(
            theme,
            rewards,
            itemType: item.type,
            itemId: item.id,
          ),
          isTrue,
        );
        expect(rewards.coinBalance, 1000 - item.cost);
        expect(
          rewards.rewardLedger.where((entry) => entry.coins < 0),
          hasLength(1),
        );
        expect(theme.shopStateSnapshot[item.active], item.id);
        final reloadedTheme = ThemeProvider();
        final reloadedRewards = AchievementProvider();
        addTearDown(reloadedTheme.dispose);
        addTearDown(reloadedRewards.dispose);
        await reloadedTheme.loadFromStorage();
        await reloadedRewards.loadFromStorage();
        expect(reloadedTheme.shopStateSnapshot[item.active], item.id);
        expect(reloadedRewards.coinBalance, 1000 - item.cost);
      },
    );
  }

  for (final rejectedKey in [
    'duoyi_virtual_rewards',
    'active_brand',
    'theme_unlocked_brands',
    'theme_switch_count',
    'theme_shop_state',
  ]) {
    test(
      'guest redeem rolls back rejected $rejectedKey and ledger history',
      () async {
        final store = _ThemeStore();
        SharedPreferencesStorePlatform.instance = store;
        final theme = ThemeProvider();
        final rewards = AchievementProvider();
        addTearDown(theme.dispose);
        addTearDown(rewards.dispose);
        await _seedGuestRewards(rewards, ledgerSize: 50);
        final beforeLedger = rewards.rewardLedger
            .map((entry) => entry.id)
            .toList();
        final beforeTheme = theme.shopStateSnapshot;
        final prefs = await SharedPreferences.getInstance();
        final beforeRewards = prefs.getString('duoyi_virtual_rewards');
        store.rejectKeyOnce = 'flutter.$rejectedKey';
        await expectLater(_redeemGuest(theme, rewards), throwsStateError);
        expect(rewards.coinBalance, 1000);
        expect(rewards.lifetimeCoins, 1000);
        expect(rewards.rewardLedger.map((entry) => entry.id), beforeLedger);
        expect(prefs.getString('duoyi_virtual_rewards'), beforeRewards);
        expect(theme.shopStateSnapshot, beforeTheme);
        expect(theme.isBrandUnlocked('re0'), isFalse);
        expect(prefs.getString('active_brand'), isNull);
        expect(prefs.getInt('theme_switch_count'), isNull);
        expect(prefs.getStringList('theme_unlocked_brands'), isNull);
      },
    );
  }

  test('two queued guest redeems charge once', () async {
    final store = _ThemeStore();
    SharedPreferencesStorePlatform.instance = store;
    final theme = ThemeProvider();
    final rewards = AchievementProvider();
    addTearDown(theme.dispose);
    addTearDown(rewards.dispose);
    await _seedGuestRewards(rewards);
    store.holdKey = 'flutter.theme_shop_state';
    final first = _redeemGuest(theme, rewards);
    await store.started.future.timeout(const Duration(seconds: 5));
    final second = _redeemGuest(theme, rewards);
    expect(
      theme.isBrandUnlocked('re0'),
      isFalse,
      reason: 'Pending state is not published',
    );
    store.release.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(rewards.coinBalance, 860);
    expect(theme.themeSwitchCount, 1);
    expect(
      rewards.rewardLedger.where((entry) => entry.coins < 0),
      hasLength(1),
    );
  });

  for (final hydration in ['load', 'snapshot', 'failed purchase']) {
    test(
      'guest purchase preserves real award after queued $hydration',
      () async {
        final store = _ThemeStore();
        SharedPreferencesStorePlatform.instance = store;
        final theme = ThemeProvider();
        final rewards = AchievementProvider();
        addTearDown(theme.dispose);
        addTearDown(rewards.dispose);
        await rewards.loadFromStorage();
        await _seedGuestRewards(rewards);
        store.holdKey = 'flutter.theme_shop_state';
        final operation = _redeemGuest(theme, rewards);
        final failure = hydration == 'failed purchase';
        final assertion = failure
            ? expectLater(operation, throwsStateError)
            : null;
        await store.started.future.timeout(const Duration(seconds: 5));
        if (failure) store.rejectKeyOnce = store.holdKey;
        final pendingHydration = hydration == 'snapshot'
            ? rewards.applyRewardsSnapshot({
                'balance': 860,
                'lifetime': 1000,
                'updatedAt': DateTime.now()
                    .add(const Duration(minutes: 1))
                    .toUtc()
                    .toIso8601String(),
              })
            : rewards.loadFromStorage();
        DomainEventBus.instance.publish(
          DomainEvent(
            type: DomainEventType.todoCompleted,
            objectId: 'guest-award-$hydration',
          ),
        );
        store.release.complete();
        if (failure) {
          await assertion;
        } else {
          expect(await operation, isTrue);
        }
        await pendingHydration;
        await AccountPreferenceWrites.drain();
        expect(rewards.coinBalance, (failure ? 1000 : 860) + 5);
        expect(rewards.lifetimeCoins, 1005);
        expect(
          rewards.rewardLedger.any(
            (entry) => entry.id == 'event:todo:guest-award-$hydration',
          ),
          isTrue,
        );
        final prefs = await SharedPreferences.getInstance();
        final stored =
            jsonDecode(prefs.getString('duoyi_virtual_rewards')!) as Map;
        expect(stored['balance'], rewards.coinBalance);
        expect(stored['lifetime'], 1005);
        expect(
          stored['grantIds'],
          contains('event:todo:guest-award-$hydration'),
        );
      },
    );
  }

  for (final resetAccount in [false, true]) {
    test('guest purchase cancels with account reset=$resetAccount', () async {
      final store = _ThemeStore();
      SharedPreferencesStorePlatform.instance = store;
      final theme = ThemeProvider();
      final rewards = AchievementProvider();
      addTearDown(theme.dispose);
      addTearDown(rewards.dispose);
      await _seedGuestRewards(rewards);
      store.holdKey = 'flutter.theme_shop_state';
      final operation = _redeemGuest(theme, rewards);
      await store.started.future.timeout(const Duration(seconds: 5));
      Future<void>? boundary;
      Future<void>? expectedFailure;
      if (resetAccount) {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        theme.resetLocalState();
        rewards.resetLocalState();
      } else {
        boundary = AccountLocalDataCleaner.runPreferenceBoundary<void>(
          () async {
            throw StateError('Synthetic aborted transition');
          },
        );
        expectedFailure = expectLater(boundary, throwsStateError);
      }
      store.release.complete();
      expect(await operation, isFalse);
      if (expectedFailure != null) await expectedFailure;
      expect(rewards.coinBalance, resetAccount ? 0 : 1000);
      expect(rewards.rewardLedger.where((entry) => entry.coins < 0), isEmpty);
      expect(theme.isBrandUnlocked('re0'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        (jsonDecode(prefs.getString('duoyi_virtual_rewards')!)
            as Map)['balance'],
        1000,
      );
      expect(prefs.getString('active_brand'), isNull);
    });
  }

  test('guest authorization is checked at the final shared commit', () async {
    final theme = ThemeProvider();
    final rewards = AchievementProvider();
    addTearDown(theme.dispose);
    addTearDown(rewards.dispose);
    await _seedGuestRewards(rewards);
    var commitAuthorizationChecks = 0;
    final applied = await theme.redeemGuestItem(
      rewards: rewards,
      itemType: 'brand',
      itemId: 're0',
      title: 'Synthetic theme',
      reason: 'Synthetic',
      isAuthorized: () {
        // The staged selection is applied after the last platform write.
        // Reject only the commit-time check, after write-time checks passed.
        if (theme.brand.id == 're0') {
          commitAuthorizationChecks++;
          return false;
        }
        return true;
      },
    );
    expect(commitAuthorizationChecks, greaterThan(0));
    expect(applied, isFalse);
    expect(theme.isBrandUnlocked('re0'), isFalse);
    expect(rewards.coinBalance, 1000);
    expect(rewards.rewardLedger.where((entry) => entry.coins < 0), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('active_brand'), isNull);
    expect(
      (jsonDecode(prefs.getString('duoyi_virtual_rewards')!) as Map)['balance'],
      1000,
    );
  });

  test(
    'guest purchase rejects unaffordable and unknown items without changes',
    () async {
      final theme = ThemeProvider();
      final rewards = AchievementProvider();
      addTearDown(theme.dispose);
      addTearDown(rewards.dispose);
      expect(await _redeemGuest(theme, rewards), isFalse);
      await expectLater(
        _redeemGuest(theme, rewards, itemId: 'unknown'),
        throwsArgumentError,
      );
      expect(rewards.coinBalance, 0);
      expect(rewards.rewardLedger, isEmpty);
      expect(theme.isBrandUnlocked('re0'), isFalse);
    },
  );

  test(
    'old brand write cannot increment the next account switch count',
    () async {
      final store = _ThemeStore();
      SharedPreferencesStorePlatform.instance = store;
      final provider = ThemeProvider();
      await provider.unlockBrand('re0');
      store.holdKey = 'flutter.active_brand';
      final prefs = await SharedPreferences.getInstance();
      final operation = provider.setBrand('re0');
      await store.started.future.timeout(const Duration(seconds: 5));
      // The first platform write is in flight; hold its completion explicitly.
      expect(prefs.getString('active_brand'), 're0');
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      provider.resetLocalState();
      store.release.complete();

      expect(await operation, isFalse);
      expect(provider.themeSwitchCount, 0);
      expect(prefs.getInt('theme_switch_count'), isNull);
      provider.dispose();
    },
  );

  test(
    'old server theme write cannot confirm the next account state',
    () async {
      final store = _ThemeStore()..holdKey = 'flutter.active_brand';
      SharedPreferencesStorePlatform.instance = store;
      final provider = ThemeProvider();
      final prefs = await SharedPreferences.getInstance();
      final operation = provider.applyShopStateFromServer({
        'activeBrand': 're0',
        'unlockedBrandIds': ['defaultBrand', 're0'],
        'updatedAt': '2026-06-01T00:00:00Z',
      });
      await store.started.future.timeout(const Duration(seconds: 5));
      expect(prefs.getString('active_brand'), 're0');
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      provider.resetLocalState();
      store.release.complete();

      await operation;
      expect(provider.consumeServerConfirmedChange(), isFalse);
      expect(prefs.getStringList('theme_unlocked_brands'), isNull);
      expect(prefs.getString('theme_shop_state'), isNull);
      provider.dispose();
    },
  );

  test('failed brand save restores all keys without a switch event', () async {
    final store = _ThemeStore();
    SharedPreferencesStorePlatform.instance = store;
    final provider = ThemeProvider();
    await provider.unlockBrand('re0');
    final before = provider.shopStateSnapshot;
    store.rejectKeyOnce = 'flutter.theme_shop_state';
    final events = <DomainEvent>[];
    final subscription = DomainEventBus.instance.events.listen(events.add);

    await expectLater(provider.setBrand('re0'), throwsStateError);

    final prefs = await SharedPreferences.getInstance();
    expect(provider.shopStateSnapshot, before);
    expect(provider.brand.id, 'defaultBrand');
    expect(provider.themeSwitchCount, 0);
    expect(prefs.getString('active_brand'), isNull);
    expect(prefs.getInt('theme_switch_count'), isNull);
    expect(jsonDecode(prefs.getString('theme_shop_state')!), before);
    expect(events, isEmpty);
    // An earlier rejection must not poison the serial queue.
    expect(await provider.setBrand('re0'), isTrue);
    expect(events.single.type, DomainEventType.themeSwitched);
    await subscription.cancel();
    provider.dispose();
  });

  test('widget appearance rejection restores selection and cache', () async {
    final store = _ThemeStore();
    SharedPreferencesStorePlatform.instance = store;
    final provider = ThemeProvider();
    await provider.unlockCardSkin('paper_card');
    final before = provider.shopStateSnapshot;
    store.rejectKeyOnce = 'flutter.theme_shop_state';

    await expectLater(
      provider.setWidgetCardSkin('paper_card'),
      throwsStateError,
    );

    expect(provider.shopStateSnapshot, before);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('theme_shop_state')!), before);
    provider.dispose();
  });

  test('rapid widget selections persist in submission order', () async {
    final store = _ThemeStore();
    SharedPreferencesStorePlatform.instance = store;
    final provider = ThemeProvider();
    await provider.unlockCardSkin('paper_card');
    await provider.unlockCardSkin('mint_card');
    store.holdKey = 'flutter.theme_shop_state';
    final first = provider.setWidgetCardSkin('paper_card');
    await store.started.future.timeout(const Duration(seconds: 5));
    final second = provider.setWidgetCardSkin('mint_card');
    expect(store.heldValues, hasLength(1));
    store.release.complete();
    expect(await Future.wait([first, second]), [true, true]);

    expect(
      store.heldValues.map(
        (value) => jsonDecode(value as String)['activeWidgetCardSkinId'],
      ),
      ['paper_card', 'mint_card'],
    );
    expect(provider.activeWidgetCardSkin.id, 'mint_card');
    provider.dispose();
  });

  test(
    'cleanup drains issued theme writes and skips old queued edits',
    () async {
      final store = _ThemeStore();
      SharedPreferencesStorePlatform.instance = store;
      final provider = ThemeProvider();
      await provider.unlockBrand('re0');
      store.holdKey = 'flutter.active_brand';
      final events = <DomainEvent>[];
      final subscription = DomainEventBus.instance.events.listen(events.add);
      final first = provider.setBrand('re0');
      await store.started.future.timeout(const Duration(seconds: 5));
      final queued = provider.setWidgetBackgroundBrand('re0');
      provider.resetLocalState();
      var cleaned = false;
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then((
        _,
      ) {
        cleaned = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isFalse);
      store.release.complete();
      expect(await first, isFalse);
      expect(await queued, isFalse);
      await cleanup;

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('active_brand'), isFalse);
      expect(prefs.containsKey('theme_shop_state'), isFalse);
      expect(provider.brand.id, 'defaultBrand');
      expect(
        provider.activeWidgetBackgroundId,
        ThemeProvider.widgetFollowThemeId,
      );
      expect(events, isEmpty);
      expect(
        store.events.indexOf('set:flutter.active_brand'),
        lessThan(store.events.indexOf('remove:flutter.active_brand')),
      );
      await subscription.cancel();
      provider.dispose();
    },
  );

  test(
    'aborted account transition rolls back theme before returning',
    () async {
      final store = _ThemeStore();
      SharedPreferencesStorePlatform.instance = store;
      final provider = ThemeProvider();
      await provider.unlockBrand('re0');
      final before = provider.shopStateSnapshot;
      store.holdKey = 'flutter.theme_shop_state';
      final events = <DomainEvent>[];
      final subscription = DomainEventBus.instance.events.listen(events.add);
      final write = provider.setBrand('re0');
      await store.started.future.timeout(const Duration(seconds: 5));
      final boundary = AccountLocalDataCleaner.runPreferenceBoundary<void>(
        () async {
          throw StateError('Preflight failed');
        },
      );
      final expectedFailure = expectLater(boundary, throwsStateError);
      store.release.complete();
      expect(await write, isFalse);
      await expectedFailure;

      expect(provider.shopStateSnapshot, before);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('active_brand'), isNull);
      expect(prefs.getInt('theme_switch_count'), isNull);
      expect(jsonDecode(prefs.getString('theme_shop_state')!), before);
      expect(events, isEmpty);
      await subscription.cancel();
      provider.dispose();
    },
  );

  test(
    'theme writes submitted inside cleanup return canceled results',
    () async {
      final provider = ThemeProvider();
      await provider.unlockBrand('re0');
      await AccountLocalDataCleaner.runPreferenceBoundary<void>(() async {
        expect(await provider.setBrand('re0'), isFalse);
        await provider.unlockCardSkin('paper_card');
      });
      expect(provider.brand.id, 'defaultBrand');
      expect(provider.isCardSkinUnlocked('paper_card'), isFalse);
      provider.dispose();
    },
  );

  test('partial server save restores unlocks and confirmation flag', () async {
    final store = _ThemeStore()
      ..rejectKeyOnce = 'flutter.theme_unlocked_brands';
    SharedPreferencesStorePlatform.instance = store;
    final provider = ThemeProvider();
    await expectLater(
      provider.applyShopStateFromServer({
        'activeBrand': 're0',
        'unlockedBrandIds': ['defaultBrand', 're0'],
        'updatedAt': '2026-06-01T00:00:00Z',
      }),
      throwsStateError,
    );
    expect(provider.brand.id, 'defaultBrand');
    expect(provider.isBrandUnlocked('re0'), isFalse);
    expect(provider.consumeServerConfirmedChange(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('active_brand'), isNull);
    expect(prefs.getStringList('theme_unlocked_brands'), isNull);
    expect(prefs.getString('theme_shop_state'), isNull);
    provider.dispose();
  });

  test('server theme shop state updates provider and local cache', () async {
    final provider = ThemeProvider();

    await provider.applyShopStateFromServer({
      'activeBrand': 're0',
      'switchCount': 1,
      'unlockedBrandIds': ['defaultBrand', 're0'],
      'activeFocusBackdropId': 'forest_focus',
      'unlockedFocusBackdropIds': ['classic_focus', 'forest_focus'],
      'updatedAt': '2026-06-01T00:00:00Z',
    });
    final prefs = await SharedPreferences.getInstance();
    final persisted =
        json.decode(prefs.getString('theme_shop_state')!)
            as Map<String, dynamic>;

    expect(provider.brand.id, 're0');
    expect(provider.activeFocusBackdrop.id, 'forest_focus');
    expect(provider.shopStateUpdatedAt, '2026-06-01T00:00:00Z');
    expect(persisted['activeBrand'], 're0');
    expect(persisted['activeFocusBackdropId'], 'forest_focus');
    expect(persisted['updatedAt'], '2026-06-01T00:00:00Z');
  });

  test(
    'server confirmed theme state can override local future timestamp',
    () async {
      final provider = ThemeProvider();

      await provider.applyShopStateFromServer({
        'activeBrand': 're0',
        'unlockedBrandIds': ['defaultBrand', 're0'],
        'updatedAt': '2026-06-01T00:00:10Z',
      });
      await provider.applyShopStateFromServer({
        'activeBrand': 'genshin',
        'unlockedBrandIds': ['defaultBrand', 're0', 'genshin'],
        'updatedAt': '2026-06-01T00:00:09Z',
      }, trusted: true);

      expect(provider.brand.id, 'genshin');
      expect(provider.shopStateUpdatedAt, '2026-06-01T00:00:09Z');
    },
  );

  test(
    'theme shop state accepts snake case fields from old payloads',
    () async {
      final provider = ThemeProvider();

      await provider.applyShopStateFromServer({
        'active_brand': 'starRail',
        'unlocked_brand_ids': ['defaultBrand', 'starRail'],
        'active_focus_backdrop_id': 'ocean_focus',
        'unlocked_focus_backdrop_ids': ['classic_focus', 'ocean_focus'],
        'active_avatar_frame_id': 'golden_frame',
        'unlocked_avatar_frame_ids': ['simple_frame', 'golden_frame'],
        'active_card_skin_id': 'mint_card',
        'unlocked_card_skin_ids': ['plain_card', 'mint_card'],
        'active_widget_background_id': 'starRail',
        'active_widget_card_skin_id': 'mint_card',
        'switch_count': 3,
        'updated_at': '2026-06-01T00:00:03Z',
      });

      expect(provider.brand.id, 'starRail');
      expect(provider.activeFocusBackdrop.id, 'ocean_focus');
      expect(provider.activeAvatarFrame.id, 'golden_frame');
      expect(provider.activeCardSkin.id, 'mint_card');
      expect(provider.activeWidgetBackgroundId, 'starRail');
      expect(provider.activeWidgetCardSkin.id, 'mint_card');
      expect(provider.themeSwitchCount, 3);
    },
  );

  test(
    'widget theme overrides persist and stay limited to unlocked items',
    () async {
      final provider = ThemeProvider();

      await provider.unlockBrand('re0');
      await provider.unlockCardSkin('paper_card');
      expect(await provider.setWidgetBackgroundBrand('re0'), isTrue);
      expect(await provider.setWidgetCardSkin('paper_card'), isTrue);
      expect(await provider.setWidgetBackgroundBrand('genshin'), isFalse);
      expect(await provider.setWidgetCardSkin('mint_card'), isFalse);

      final prefs = await SharedPreferences.getInstance();
      final persisted =
          json.decode(prefs.getString('theme_shop_state')!)
              as Map<String, dynamic>;

      expect(provider.activeWidgetBackgroundBrand.id, 're0');
      expect(provider.activeWidgetCardSkin.id, 'paper_card');
      expect(persisted['activeWidgetBackgroundId'], 're0');
      expect(persisted['activeWidgetCardSkinId'], 'paper_card');
    },
  );

  test(
    'local theme shop changes include updatedAt for sync ordering',
    () async {
      final provider = ThemeProvider();

      await provider.loadFromStorage();
      await provider.unlockBrand('re0');
      await provider.setBrand('re0');
      final prefs = await SharedPreferences.getInstance();
      final persisted =
          json.decode(prefs.getString('theme_shop_state')!)
              as Map<String, dynamic>;

      expect(provider.brand.id, 're0');
      expect(provider.shopStateUpdatedAt, isNotEmpty);
      expect(persisted['activeBrand'], 're0');
      expect(persisted['updatedAt'], isNotEmpty);
    },
  );

  test('older server theme shop state cannot roll back active theme', () async {
    final provider = ThemeProvider();

    await provider.applyShopStateFromServer({
      'activeBrand': 're0',
      'unlockedBrandIds': ['defaultBrand', 're0'],
      'updatedAt': '2026-06-01T00:00:02Z',
    });
    await provider.applyShopStateFromServer({
      'activeBrand': 'defaultBrand',
      'unlockedBrandIds': ['defaultBrand'],
      'updatedAt': '2026-06-01T00:00:01Z',
    });
    final prefs = await SharedPreferences.getInstance();
    final persisted =
        json.decode(prefs.getString('theme_shop_state')!)
            as Map<String, dynamic>;

    expect(provider.brand.id, 're0');
    expect(provider.shopStateUpdatedAt, '2026-06-01T00:00:02Z');
    expect(persisted['activeBrand'], 're0');
  });

  test(
    'older stored theme shop state cannot roll back in-memory theme',
    () async {
      final provider = ThemeProvider();

      await provider.applyShopStateFromServer({
        'activeBrand': 're0',
        'unlockedBrandIds': ['defaultBrand', 're0'],
        'updatedAt': '2026-06-01T00:00:02Z',
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'theme_shop_state',
        json.encode({
          'activeBrand': 'defaultBrand',
          'unlockedBrandIds': ['defaultBrand'],
          'updatedAt': '2026-06-01T00:00:01Z',
        }),
      );
      await provider.loadFromStorage();

      expect(provider.brand.id, 're0');
      expect(provider.shopStateUpdatedAt, '2026-06-01T00:00:02Z');
    },
  );

  test('older server reward snapshot cannot roll back coin balance', () async {
    final provider = AchievementProvider();

    await provider.applyRewardsSnapshot({
      'balance': 60,
      'lifetime': 200,
      'updatedAt': '2026-06-01T00:00:02Z',
    });
    await provider.applyRewardsSnapshot({
      'balance': 120,
      'lifetime': 200,
      'updatedAt': '2026-06-01T00:00:01Z',
    });
    final prefs = await SharedPreferences.getInstance();
    final persisted =
        json.decode(prefs.getString('duoyi_virtual_rewards')!)
            as Map<String, dynamic>;

    expect(provider.coinBalance, 60);
    expect(provider.lifetimeCoins, 200);
    expect(persisted['balance'], 60);
  });

  test(
    'loadFromStorage resets theme state when account keys are removed',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'active_brand': 're0',
        'theme_switch_count': 4,
        'theme_unlocked_brands': <String>['defaultBrand', 're0'],
        'theme_shop_state': json.encode({
          'activeBrand': 're0',
          'switchCount': 4,
          'unlockedBrandIds': ['defaultBrand', 're0'],
          'activeFocusBackdropId': 'forest_focus',
          'unlockedFocusBackdropIds': ['classic_focus', 'forest_focus'],
          'updatedAt': '2026-06-01T00:00:00.000Z',
        }),
      });
      final provider = ThemeProvider();

      await provider.loadFromStorage();
      expect(provider.brand.id, 're0');
      expect(provider.themeSwitchCount, 4);
      expect(provider.activeFocusBackdrop.id, 'forest_focus');

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('theme_shop_state');
      await prefs.remove('active_brand');
      await prefs.remove('theme_switch_count');
      await prefs.remove('theme_unlocked_brands');
      await provider.loadFromStorage();

      expect(provider.brand.id, 'defaultBrand');
      expect(provider.themeSwitchCount, 0);
      expect(provider.unlockedBrandIds, {'defaultBrand'});
      expect(
        provider.activeFocusBackdrop.id,
        ThemeProvider.defaultFocusBackdropId,
      );
      expect(
        provider.activeWidgetBackgroundId,
        ThemeProvider.widgetFollowThemeId,
      );
    },
  );
}

Future<void> _seedGuestRewards(
  AchievementProvider rewards, {
  int ledgerSize = 0,
}) => rewards.applyRewardsSnapshot({
  'balance': 1000,
  'lifetime': 1000,
  'ledger': [
    for (var i = 0; i < ledgerSize; i++)
      {
        'id': 'prior-$i',
        'title': 'Prior reward',
        'coins': 1,
        'reason': 'Synthetic',
        'awardedAt': '2020-01-01T00:00:00Z',
      },
  ],
  'updatedAt': '2020-01-01T00:00:00Z',
});

Future<bool> _redeemGuest(
  ThemeProvider theme,
  AchievementProvider rewards, {
  String itemType = 'brand',
  String itemId = 're0',
}) => theme.redeemGuestItem(
  rewards: rewards,
  itemType: itemType,
  itemId: itemId,
  title: 'Synthetic theme',
  reason: 'Synthetic purchase',
  isAuthorized: () => true,
);

class _ThemeStore extends InMemorySharedPreferencesStore {
  _ThemeStore() : super.withData({});

  String? rejectKeyOnce;
  String? holdKey;
  final started = Completer<void>();
  final release = Completer<void>();
  final heldValues = <Object>[];
  final events = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == holdKey) {
      heldValues.add(value);
      if (!started.isCompleted) {
        started.complete();
        await release.future;
      }
    }
    if (key == rejectKeyOnce) {
      rejectKeyOnce = null;
      return false;
    }
    final saved = await super.setValue(valueType, key, value);
    events.add('set:$key');
    return saved;
  }

  @override
  Future<bool> remove(String key) async {
    final removed = await super.remove(key);
    events.add('remove:$key');
    return removed;
  }
}
