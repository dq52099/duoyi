// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _HeldWriteStore extends InMemorySharedPreferencesStore {
  _HeldWriteStore() : super.withData({});
  String? heldKey;
  Completer<void> started = Completer<void>();
  Completer<void> release = Completer<void>();
  bool reject = true;
  final heldValues = <Object>[];
  final events = <String>[];

  void resetCompleters({bool nextReject = true}) {
    started = Completer<void>();
    release = Completer<void>();
    reject = nextReject;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    events.add('set:$key');
    if (key == heldKey) {
      heldValues.add(value);
      if (!started.isCompleted) {
        started.complete();
        await release.future;
        if (reject) return false;
      }
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await AccountPreferenceWrites.drain();
  });

  group('Widget theme publication commit boundary', () {
    for (final selection in [
      'appBrand',
      'widgetBackground',
      'widgetSkin',
      'followCardSkin',
    ]) {
      test(
        'widget capture preserves committed appearance during failed $selection write',
        () async {
          final store = _HeldWriteStore();
          SharedPreferencesStorePlatform.instance = store;
          final provider = ThemeProvider();
          await provider.unlockBrand('liquidGlass');
          await provider.unlockCardSkin('paper_card');
          final beforePayload = HomeWidgetThemePayload.fromThemeProvider(
            provider,
          );
          final beforeValues = beforePayload.payloadValues;
          var events = 0;
          provider.addListener(() => events++);

          store.heldKey = selection == 'appBrand'
              ? 'flutter.active_brand'
              : 'flutter.theme_shop_state';
          store.reject = true;

          final operation = switch (selection) {
            'appBrand' => provider.setBrand('liquidGlass'),
            'widgetBackground' => provider.setWidgetBackgroundBrand(
              'liquidGlass',
            ),
            'widgetSkin' => provider.setWidgetCardSkin('paper_card'),
            _ => provider.setCardSkin('paper_card'),
          };

          final rejected = expectLater(operation, throwsStateError);
          try {
            await store.started.future.timeout(const Duration(seconds: 5));
            expect(events, 0);
            expect(
              HomeWidgetThemePayload.fromThemeProvider(provider).payloadValues,
              beforeValues,
              reason: 'Native payload must not leak uncommitted $selection',
            );
          } finally {
            if (!store.release.isCompleted) store.release.complete();
            await rejected;
            await AccountPreferenceWrites.drain();
            expect(
              HomeWidgetThemePayload.fromThemeProvider(provider).payloadValues,
              beforeValues,
              reason: 'Rejection must leave committed appearance intact',
            );
            expect(events, 0);
            provider.dispose();
          }
        },
      );
    }

    test(
      'successful write publishes committed appearance only after persistence succeeds',
      () async {
        final store = _HeldWriteStore();
        SharedPreferencesStorePlatform.instance = store;
        final provider = ThemeProvider();
        await provider.unlockBrand('liquidGlass');
        final beforeValues = HomeWidgetThemePayload.fromThemeProvider(
          provider,
        ).payloadValues;
        var events = 0;
        provider.addListener(() => events++);

        store.heldKey = 'flutter.active_brand';
        store.reject = false;

        final operation = provider.setBrand('liquidGlass');
        try {
          await store.started.future.timeout(const Duration(seconds: 5));
          expect(events, 0);
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).payloadValues,
            beforeValues,
            reason:
                'Payload must remain on committed theme while write is held',
          );
        } finally {
          if (!store.release.isCompleted) store.release.complete();
        }

        final ok = await operation;
        expect(ok, isTrue);
        await AccountPreferenceWrites.drain();

        expect(
          events,
          1,
          reason: 'Listener should fire exactly once upon commit',
        );
        final committed = HomeWidgetThemePayload.fromThemeProvider(provider);
        expect(committed.brandId, 'liquidGlass');
        expect(
          committed.primary,
          AppBrands.liquidGlass.theme.colorScheme.primary,
        );
        expect(committed.borderWidthDp, 1);
        expect(committed.cornerRadiusDp, 16);
        expect(committed.payloadValues['widget_theme_brand_id'], 'liquidGlass');
        provider.dispose();
      },
    );

    test(
      'queue two selections with held first write maintains ordered presentation',
      () async {
        final store = _HeldWriteStore();
        SharedPreferencesStorePlatform.instance = store;
        final provider = ThemeProvider();
        await provider.unlockCardSkin('paper_card');
        await provider.unlockCardSkin('mint_card');

        var events = 0;
        provider.addListener(() => events++);

        store.heldKey = 'flutter.theme_shop_state';
        store.reject = false;

        final first = provider.setWidgetCardSkin('paper_card');
        await store.started.future.timeout(const Duration(seconds: 5));
        final second = provider.setWidgetCardSkin('mint_card');

        try {
          expect(events, 0);
          expect(
            provider.activeWidgetCardSkin.id,
            'plain_card',
            reason: 'First selection must not escape before commit',
          );
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).cardSkinId,
            'plain_card',
          );
        } finally {
          if (!store.release.isCompleted) store.release.complete();
        }

        final results = await Future.wait([first, second]);
        expect(results, [true, true]);
        await AccountPreferenceWrites.drain();

        expect(events, 2, reason: 'Each commit notifies once in order');
        expect(
          store.heldValues.map(
            (v) => jsonDecode(v as String)['activeWidgetCardSkinId'],
          ),
          ['paper_card', 'mint_card'],
        );
        final finalPayload = HomeWidgetThemePayload.fromThemeProvider(provider);
        expect(finalPayload.cardSkinId, 'mint_card');
        expect(finalPayload.cornerRadiusDp, 15);
        provider.dispose();
      },
    );

    test(
      'queued second selection succeeds and publishes when held first write rejects',
      () async {
        final store = _HeldWriteStore();
        SharedPreferencesStorePlatform.instance = store;
        final provider = ThemeProvider();
        await provider.unlockCardSkin('paper_card');
        await provider.unlockCardSkin('mint_card');

        var events = 0;
        provider.addListener(() => events++);

        store.heldKey = 'flutter.theme_shop_state';
        store.reject = true;

        final first = provider.setWidgetCardSkin('paper_card');
        await store.started.future.timeout(const Duration(seconds: 5));
        final second = provider.setWidgetCardSkin('mint_card');

        final rejectedFirst = expectLater(first, throwsStateError);
        try {
          expect(events, 0);
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).cardSkinId,
            'plain_card',
          );
        } finally {
          if (!store.release.isCompleted) store.release.complete();
        }

        await rejectedFirst;
        final secondResult = await second;
        expect(secondResult, isTrue);
        await AccountPreferenceWrites.drain();

        expect(
          events,
          1,
          reason: 'Only the successful second selection notifies',
        );
        final finalPayload = HomeWidgetThemePayload.fromThemeProvider(provider);
        expect(finalPayload.cardSkinId, 'mint_card');
        expect(finalPayload.cornerRadiusDp, 15);
        provider.dispose();
      },
    );

    test(
      'implicit follow-brand and follow-skin commit boundaries hold uncommitted appearance',
      () async {
        final store = _HeldWriteStore();
        SharedPreferencesStorePlatform.instance = store;
        final provider = ThemeProvider();
        await provider.unlockBrand('liquidGlass');
        await provider.unlockCardSkin('paper_card');

        expect(
          provider.activeWidgetBackgroundId,
          ThemeProvider.widgetFollowThemeId,
        );
        expect(
          provider.activeWidgetCardSkinId,
          ThemeProvider.widgetFollowCardSkinId,
        );

        // Subtest A: Implicit follow-brand
        store.heldKey = 'flutter.active_brand';
        store.reject = false;
        final brandOp = provider.setBrand('liquidGlass');
        try {
          await store.started.future.timeout(const Duration(seconds: 5));
          expect(
            provider.activeWidgetBackgroundBrand.id,
            'defaultBrand',
            reason: 'Implicit follow-brand must not leak before commit',
          );
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).brandId,
            'defaultBrand',
          );
        } finally {
          if (!store.release.isCompleted) store.release.complete();
        }
        expect(await brandOp, isTrue);
        expect(
          HomeWidgetThemePayload.fromThemeProvider(provider).brandId,
          'liquidGlass',
        );

        // Subtest B: Implicit follow-skin
        store.resetCompleters(nextReject: false);
        store.heldKey = 'flutter.theme_shop_state';
        final skinOp = provider.setCardSkin('paper_card');
        try {
          await store.started.future.timeout(const Duration(seconds: 5));
          expect(
            provider.activeWidgetCardSkin.id,
            'plain_card',
            reason: 'Implicit follow-skin must not leak before commit',
          );
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).cardSkinId,
            'plain_card',
          );
        } finally {
          if (!store.release.isCompleted) store.release.complete();
        }
        expect(await skinOp, isTrue);
        expect(
          HomeWidgetThemePayload.fromThemeProvider(provider).cardSkinId,
          'paper_card',
        );
        provider.dispose();
      },
    );

    test(
      'cleanup or reset while held cannot resurrect old account presentation',
      () async {
        final store = _HeldWriteStore();
        SharedPreferencesStorePlatform.instance = store;
        final provider = ThemeProvider();
        await provider.unlockBrand('liquidGlass');
        await provider.setBrand('liquidGlass');
        await AccountPreferenceWrites.drain();

        expect(
          HomeWidgetThemePayload.fromThemeProvider(provider).brandId,
          'liquidGlass',
        );

        await provider.unlockBrand('re0');
        await AccountPreferenceWrites.drain();

        store.heldKey = 'flutter.active_brand';
        store.reject = false;

        final first = provider.setBrand('re0');
        await store.started.future.timeout(const Duration(seconds: 5));

        try {
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).brandId,
            'liquidGlass',
          );
          // Account reset / cleanup fires while the write is suspended
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          provider.resetLocalState();

          expect(
            provider.brand.id,
            'defaultBrand',
            reason: 'Reset must immediately revert in-memory brand',
          );
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).brandId,
            'defaultBrand',
            reason: 'Native payload must reflect reset defaults immediately',
          );
        } finally {
          if (!store.release.isCompleted) store.release.complete();
        }

        final result = await first;
        expect(result, isFalse, reason: 'Old generation write must cancel');
        await AccountPreferenceWrites.drain();

        expect(
          provider.brand.id,
          'defaultBrand',
          reason:
              'Neither candidate nor previous account presentation may resurrect',
        );
        expect(
          HomeWidgetThemePayload.fromThemeProvider(provider).brandId,
          'defaultBrand',
        );
        provider.dispose();
      },
    );

    test(
      'server hydration holds committed appearance during held successful write and updates atomically upon commit',
      () async {
        final store = _HeldWriteStore();
        SharedPreferencesStorePlatform.instance = store;
        final provider = ThemeProvider();
        await provider.unlockBrand('liquidGlass');
        final beforePayload = HomeWidgetThemePayload.fromThemeProvider(
          provider,
        );
        final beforeValues = beforePayload.payloadValues;
        expect(beforePayload.brandId, 'defaultBrand');
        var events = 0;
        provider.addListener(() => events++);

        store.heldKey = 'flutter.active_brand';
        store.reject = false;

        final operation = provider.applyShopStateFromServer({
          'activeBrand': 'liquidGlass',
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          'updatedAt': '2099-01-01T00:00:00.000Z',
        });
        try {
          await store.started.future.timeout(const Duration(seconds: 5));
          expect(events, 0);
          expect(provider.consumeServerConfirmedChange(), isFalse);
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).payloadValues,
            beforeValues,
            reason: 'Committed appearance remains while server write is held',
          );
        } finally {
          if (!store.release.isCompleted) store.release.complete();
          await operation;
          await AccountPreferenceWrites.drain();
          store.heldKey = null;

          expect(events, 1, reason: 'Listener should fire once upon commit');
          expect(provider.consumeServerConfirmedChange(), isTrue);
          final committed = HomeWidgetThemePayload.fromThemeProvider(provider);
          expect(committed.brandId, 'liquidGlass');
          expect(
            committed.primary,
            AppBrands.liquidGlass.theme.colorScheme.primary,
          );
          expect(committed.borderWidthDp, 1);
          expect(committed.cornerRadiusDp, 16);
          expect(
            committed.payloadValues['widget_theme_brand_id'],
            'liquidGlass',
          );
          expect(provider.shopStateUpdatedAt, '2099-01-01T00:00:00.000Z');

          final reloaded = ThemeProvider();
          await reloaded.loadFromStorage();
          expect(reloaded.brand.id, 'liquidGlass');
          expect(reloaded.shopStateUpdatedAt, '2099-01-01T00:00:00.000Z');
          final reloadedPayload = HomeWidgetThemePayload.fromThemeProvider(
            reloaded,
          );
          expect(reloadedPayload.brandId, 'liquidGlass');
          expect(
            reloadedPayload.payloadValues['widget_theme_brand_id'],
            'liquidGlass',
          );
          reloaded.dispose();
          provider.dispose();
        }
      },
    );

    test(
      'server hydration holds committed appearance during held failed write and preserves storage on rejection',
      () async {
        final store = _HeldWriteStore();
        SharedPreferencesStorePlatform.instance = store;
        final provider = ThemeProvider();
        await provider.unlockBrand('liquidGlass');
        final beforePayload = HomeWidgetThemePayload.fromThemeProvider(
          provider,
        );
        final beforeValues = beforePayload.payloadValues;
        var events = 0;
        provider.addListener(() => events++);

        store.heldKey = 'flutter.active_brand';
        store.reject = true;

        final operation = provider.applyShopStateFromServer({
          'activeBrand': 'liquidGlass',
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          'updatedAt': '2099-01-01T00:00:00.000Z',
        });
        final rejected = expectLater(operation, throwsStateError);
        try {
          await store.started.future.timeout(const Duration(seconds: 5));
          expect(events, 0);
          expect(provider.consumeServerConfirmedChange(), isFalse);
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).payloadValues,
            beforeValues,
            reason: 'Server candidate must not leak uncommitted brand',
          );
        } finally {
          if (!store.release.isCompleted) store.release.complete();
          await rejected;
          await AccountPreferenceWrites.drain();
          store.heldKey = null;

          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).brandId,
            'defaultBrand',
          );
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).payloadValues,
            beforeValues,
          );
          expect(events, 0);
          expect(provider.consumeServerConfirmedChange(), isFalse);

          final reloaded = ThemeProvider();
          await reloaded.loadFromStorage();
          expect(reloaded.brand.id, 'defaultBrand');
          expect(
            HomeWidgetThemePayload.fromThemeProvider(reloaded).payloadValues,
            beforeValues,
          );
          reloaded.dispose();
          provider.dispose();
        }
      },
    );

    test(
      'server candidate with explicit widget background and skin holds and commits appearance',
      () async {
        final store = _HeldWriteStore();
        SharedPreferencesStorePlatform.instance = store;
        final provider = ThemeProvider();
        final beforePayload = HomeWidgetThemePayload.fromThemeProvider(
          provider,
        );
        final beforeValues = beforePayload.payloadValues;
        expect(beforePayload.brandId, 'defaultBrand');
        expect(beforePayload.cardSkinId, 'plain_card');

        var events = 0;
        provider.addListener(() => events++);

        store.heldKey = 'flutter.active_brand';
        store.reject = false;

        final operation = provider.applyShopStateFromServer({
          'activeBrand': 'liquidGlass',
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          'activeWidgetBackgroundId': 'liquidGlass',
          'activeWidgetCardSkinId': 'paper_card',
          'unlockedCardSkinIds': ['plain_card', 'paper_card'],
          'updatedAt': '2099-06-15T12:00:00.000Z',
        });
        try {
          await store.started.future.timeout(const Duration(seconds: 5));
          expect(events, 0);
          expect(provider.consumeServerConfirmedChange(), isFalse);
          expect(provider.activeWidgetBackgroundBrand.id, 'defaultBrand');
          expect(provider.activeWidgetCardSkin.id, 'plain_card');
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).payloadValues,
            beforeValues,
            reason:
                'Widget background and skin candidates remain held before commit',
          );
        } finally {
          if (!store.release.isCompleted) store.release.complete();
          await operation;
          await AccountPreferenceWrites.drain();
          store.heldKey = null;

          expect(events, 1);
          expect(provider.consumeServerConfirmedChange(), isTrue);
          expect(provider.activeWidgetBackgroundBrand.id, 'liquidGlass');
          expect(provider.activeWidgetCardSkin.id, 'paper_card');
          final committed = HomeWidgetThemePayload.fromThemeProvider(provider);
          expect(committed.brandId, 'liquidGlass');
          expect(committed.cardSkinId, 'paper_card');
          expect(
            committed.payloadValues['widget_theme_brand_id'],
            'liquidGlass',
          );
          expect(
            committed.payloadValues['widget_theme_card_skin_id'],
            'paper_card',
          );
          expect(provider.shopStateUpdatedAt, '2099-06-15T12:00:00.000Z');

          final reloaded = ThemeProvider();
          await reloaded.loadFromStorage();
          expect(reloaded.activeWidgetBackgroundBrand.id, 'liquidGlass');
          expect(reloaded.activeWidgetCardSkin.id, 'paper_card');
          expect(reloaded.shopStateUpdatedAt, '2099-06-15T12:00:00.000Z');
          final reloadedPayload = HomeWidgetThemePayload.fromThemeProvider(
            reloaded,
          );
          expect(reloadedPayload.brandId, 'liquidGlass');
          expect(reloadedPayload.cardSkinId, 'paper_card');
          expect(
            reloadedPayload.payloadValues['widget_theme_card_skin_id'],
            'paper_card',
          );
          reloaded.dispose();
          provider.dispose();
        }
      },
    );

    test(
      'account reset while server hydration write is held cannot resurrect old or candidate appearance',
      () async {
        final store = _HeldWriteStore();
        SharedPreferencesStorePlatform.instance = store;
        final provider = ThemeProvider();
        await provider.unlockBrand('liquidGlass');
        await provider.setBrand('liquidGlass');
        await AccountPreferenceWrites.drain();

        expect(
          HomeWidgetThemePayload.fromThemeProvider(provider).brandId,
          'liquidGlass',
        );

        var events = 0;
        provider.addListener(() => events++);

        store.heldKey = 'flutter.active_brand';
        store.reject = false;

        final operation = provider.applyShopStateFromServer({
          'activeBrand': 're0',
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass', 're0'],
          'updatedAt': '2099-09-09T00:00:00.000Z',
        });
        await store.started.future.timeout(const Duration(seconds: 5));

        try {
          expect(events, 0);
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).brandId,
            'liquidGlass',
            reason: 'Committed appearance held before reset',
          );

          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          provider.resetLocalState();

          expect(
            provider.brand.id,
            'defaultBrand',
            reason: 'Reset must immediately revert in-memory brand',
          );
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).brandId,
            'defaultBrand',
            reason: 'Payload must reflect reset defaults immediately',
          );
        } finally {
          if (!store.release.isCompleted) store.release.complete();
          await operation;
          await AccountPreferenceWrites.drain();
          store.heldKey = null;

          expect(
            provider.brand.id,
            'defaultBrand',
            reason:
                'Neither server candidate nor previous account presentation may resurrect',
          );
          expect(
            HomeWidgetThemePayload.fromThemeProvider(provider).brandId,
            'defaultBrand',
          );
          expect(provider.consumeServerConfirmedChange(), isFalse);
          provider.dispose();
        }
      },
    );
  });
}
