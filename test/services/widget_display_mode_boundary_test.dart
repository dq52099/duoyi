// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/widget_display_mode_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final heldWrite in ['canonical', 'mirror', 'acknowledgement']) {
    test('account cleanup drains a held $heldWrite write', () async {
      final store = _GatedStore();
      SharedPreferencesStorePlatform.instance = store;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('todos', 'departing account data');

      late Future<Object?> operationOutcome;
      if (heldWrite == 'acknowledgement') {
        final selection = (await WidgetDisplayModeStore.save(
          'detailed',
          isCurrent: () => true,
        ))!;
        store.hold(WidgetDisplayModeSelection.storageKey);
        final operation = WidgetDisplayModeStore.acknowledge(
          selection,
          isCurrent: () => true,
        );
        operationOutcome = operation.then<Object?>(
          (value) => value,
          onError: (Object error) => error,
        );
      } else {
        store.hold(
          heldWrite == 'canonical'
              ? WidgetDisplayModeSelection.storageKey
              : WidgetDisplayModeSelection.legacyKey,
        );
        final operation = WidgetDisplayModeStore.save(
          'detailed',
          isCurrent: () => true,
        );
        operationOutcome = operation.then<Object?>(
          (value) => value,
          onError: (Object error) => error,
        );
      }

      await store.writeEntered!.future;
      var cleanupFinished = false;
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then((
        _,
      ) {
        cleanupFinished = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(cleanupFinished, isFalse);

      store.writeRelease!.complete(true);
      expect(
        await operationOutcome,
        heldWrite == 'acknowledgement' ? isFalse : isNull,
      );
      await cleanup;

      expect(prefs.containsKey('todos'), isFalse);
      expect(prefs.containsKey(WidgetDisplayModeSelection.storageKey), isFalse);
      expect(prefs.containsKey(WidgetDisplayModeSelection.legacyKey), isFalse);
    });
  }

  test(
    'queued request keeps its entry generation and a failed operation does not poison the tail',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(WidgetDisplayModeSelection.legacyKey, 'standard');
      final entered = Completer<void>();
      final release = Completer<void>();
      final failing = WidgetDisplayModeStore.runOperation(() async {
        entered.complete();
        await release.future;
        throw StateError('synthetic operation failure');
      });
      final failingOutcome = failing.then<Object?>(
        (value) => value,
        onError: (Object error) => error,
      );
      await entered.future;

      final preferenceGeneration = AccountPreferenceWrites.generation;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      bool isCurrent() =>
          preferenceGeneration == AccountPreferenceWrites.generation &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          );
      var staleOperationRan = false;
      final queued = WidgetDisplayModeStore.runOperation(() async {
        if (!isCurrent()) return;
        staleOperationRan = true;
        await WidgetDisplayModeStore.save('detailed', isCurrent: isCurrent);
      });
      var tailRecovered = false;
      final following = WidgetDisplayModeStore.runOperation(() async {
        tailRecovered = true;
      });

      await AccountLocalDataCleaner.clearSharedPreferences();
      release.complete();

      expect(await failingOutcome, isA<StateError>());
      await Future.wait([queued, following]);
      expect(staleOperationRan, isFalse);
      expect(tailRecovered, isTrue);
      expect(prefs.containsKey(WidgetDisplayModeSelection.storageKey), isFalse);
      expect(prefs.containsKey(WidgetDisplayModeSelection.legacyKey), isFalse);
    },
  );

  test('same-mode stale acknowledgement preserves the newer intent', () async {
    final first = (await WidgetDisplayModeStore.save(
      'detailed',
      isCurrent: () => true,
    ))!;
    final newer = (await WidgetDisplayModeStore.save(
      'detailed',
      isCurrent: () => true,
    ))!;
    expect(newer.intentId, isNot(first.intentId));

    expect(
      await WidgetDisplayModeStore.acknowledge(first, isCurrent: () => true),
      isFalse,
    );
    final saved = await WidgetDisplayModeStore.read();
    expect(saved.mode, 'detailed');
    expect(saved.intentId, newer.intentId);
    expect(saved.pending, isTrue);
  });
}

class _GatedStore extends InMemorySharedPreferencesStore {
  _GatedStore() : super.withData({});

  String? _heldKey;
  Completer<void>? writeEntered;
  Completer<bool>? writeRelease;

  void hold(String key) {
    _heldKey = 'flutter.$key';
    writeEntered = Completer<void>();
    writeRelease = Completer<bool>();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == _heldKey) {
      _heldKey = null;
      writeEntered!.complete();
      if (!await writeRelease!.future) return false;
    }
    return super.setValue(type, key, value);
  }
}
