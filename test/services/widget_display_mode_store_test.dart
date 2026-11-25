// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:duoyi/services/widget_display_mode_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('legacy mode loads without creating a pending delivery', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(WidgetDisplayModeSelection.legacyKey, 'detailed');
    final selection = await WidgetDisplayModeStore.read();
    expect(selection.mode, 'detailed');
    expect(selection.pending, isFalse);
    expect(prefs.containsKey(WidgetDisplayModeSelection.storageKey), isFalse);
  });

  test(
    'canonical mode and pending intent take priority over legacy mirror',
    () async {
      final prefs = await SharedPreferences.getInstance();
      const saved = WidgetDisplayModeSelection(
        mode: 'compact',
        intentId: 'persisted-intent',
        pending: true,
      );
      await prefs.setString(
        WidgetDisplayModeSelection.storageKey,
        saved.encode(),
      );
      await prefs.setString(WidgetDisplayModeSelection.legacyKey, 'detailed');
      final selection = await WidgetDisplayModeStore.read();
      expect(selection.mode, 'compact');
      expect(selection.intentId, saved.intentId);
      expect(selection.pending, isTrue);
    },
  );

  test(
    'malformed canonical data cannot silently fall back to legacy',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(WidgetDisplayModeSelection.legacyKey, 'detailed');
      await prefs.setString(WidgetDisplayModeSelection.storageKey, '{"v":1}');
      await expectLater(WidgetDisplayModeStore.read(), throwsFormatException);
    },
  );

  test(
    'acknowledgement keeps mode and only clears the matching intent',
    () async {
      final first = (await WidgetDisplayModeStore.save(
        'detailed',
        isCurrent: () => true,
      ))!;
      final second = (await WidgetDisplayModeStore.save(
        'compact',
        isCurrent: () => true,
      ))!;
      expect(first.intentId, isNot(second.intentId));
      expect(
        await WidgetDisplayModeStore.acknowledge(first, isCurrent: () => true),
        isFalse,
      );
      expect((await WidgetDisplayModeStore.read()).pending, isTrue);
      expect(
        await WidgetDisplayModeStore.acknowledge(second, isCurrent: () => true),
        isTrue,
      );
      final saved = await WidgetDisplayModeStore.read();
      expect(saved.mode, 'compact');
      expect(saved.intentId, second.intentId);
      expect(saved.pending, isFalse);
    },
  );

  test('failed acknowledgement preserves the durable pending intent', () async {
    final store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    final selection = (await WidgetDisplayModeStore.save(
      'detailed',
      isCurrent: () => true,
    ))!;
    store.rejectNextCanonical = true;
    await expectLater(
      WidgetDisplayModeStore.acknowledge(selection, isCurrent: () => true),
      throwsStateError,
    );
    final saved = await WidgetDisplayModeStore.read();
    expect(saved.pending, isTrue);
    expect(saved.intentId, selection.intentId);
  });

  for (final canceled in [false, true]) {
    test(
      'read waits for mirror failure or cancellation: canceled=$canceled',
      () async {
        final store = _Store();
        SharedPreferencesStorePlatform.instance = store;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(WidgetDisplayModeSelection.legacyKey, 'standard');
        store.holdMirror();
        var current = true;
        final saving = WidgetDisplayModeStore.save(
          'detailed',
          isCurrent: () => current,
        );
        // Attach an error handler before releasing the platform failure.
        final outcome = saving.then<Object?>(
          (value) => value,
          onError: (Object e) => e,
        );
        await store.mirrorEntered!.future;
        var readFinished = false;
        final reading = WidgetDisplayModeStore.read().then((value) {
          readFinished = true;
          return value;
        });
        await Future<void>.delayed(Duration.zero);
        expect(readFinished, isFalse);
        if (canceled) current = false;
        store.mirrorRelease!.complete(canceled);
        expect(await outcome, canceled ? isNull : isStateError);
        final saved = await reading;
        expect(saved.mode, 'standard');
        expect(saved.pending, isFalse);
        expect(
          prefs.containsKey(WidgetDisplayModeSelection.storageKey),
          isFalse,
        );
      },
    );
  }

  test(
    'full operations keep their order while native work is suspended',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final order = <String>[];
      final first = WidgetDisplayModeStore.runOperation(() async {
        order.add('first-local');
        entered.complete();
        await release.future;
        order.add('first-native');
      });
      await entered.future;
      final second = WidgetDisplayModeStore.runOperation(() async {
        order.add('second-local');
      });
      await Future<void>.delayed(Duration.zero);
      expect(order, ['first-local']);
      release.complete();
      await Future.wait([first, second]);
      expect(order, ['first-local', 'first-native', 'second-local']);
    },
  );
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  bool rejectNextCanonical = false;
  Completer<void>? mirrorEntered;
  Completer<bool>? mirrorRelease;

  void holdMirror() {
    mirrorEntered = Completer<void>();
    mirrorRelease = Completer<bool>();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.${WidgetDisplayModeSelection.storageKey}' &&
        rejectNextCanonical) {
      rejectNextCanonical = false;
      return false;
    }
    if (key == 'flutter.${WidgetDisplayModeSelection.legacyKey}' &&
        mirrorEntered != null &&
        !mirrorEntered!.isCompleted) {
      mirrorEntered!.complete();
      if (!await mirrorRelease!.future) return false;
    }
    return super.setValue(type, key, value);
  }
}
