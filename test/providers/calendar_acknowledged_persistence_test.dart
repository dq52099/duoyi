// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _CalendarStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _CalendarStore();
    SharedPreferencesStorePlatform.instance = store;
  });

  test(
    'rejected calendar write cannot publish an event or signal success',
    () async {
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      var changes = 0;
      provider.onLocalEventsChanged = () => changes++;
      store.rejectNext = true;
      await expectLater(
        provider.addLocalEvent(_event('A', 'A event')),
        throwsA(anything),
      );
      expect(provider.localEvents, isEmpty);
      expect(provider.sourceRevision, 0);
      expect(changes, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('duoyi_local_calendar_events_v1') ?? [],
        isEmpty,
      );
    },
  );

  test(
    'calendar event is published only after acknowledged persistence',
    () async {
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      store.holdNext = true;
      final pending = provider.addLocalEvent(_event('A', 'A event'));
      await store.started.future;
      try {
        expect(provider.localEvents, isEmpty);
        expect(provider.sourceRevision, 0);
      } finally {
        store.release.complete();
        await pending;
      }
      expect(provider.localEvents.single.id, 'A');
      expect(provider.sourceRevision, 1);
    },
  );

  test(
    'held calendar update cannot overwrite a replacement account event',
    () async {
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      await provider.addLocalEvent(_event('A', 'A event'));
      final cancellationStarted = Completer<void>();
      final cancellationRelease = Completer<void>();
      provider.localEventReminderCanceller = (_) async {
        cancellationStarted.complete();
        await cancellationRelease.future;
      };
      final pending = provider.updateLocalEvent(_event('A', 'A changed'));
      final completed = pending.then<void>((_) {}, onError: (Object _) {});
      await cancellationStarted.future;
      provider.resetLocalState();
      final addReplacement = provider.addLocalEvent(_event('B', 'B event'));
      cancellationRelease.complete();
      await completed;
      await addReplacement;
      expect(provider.localEvents.single.id, 'B');
      expect(provider.localEvents.single.title, 'B event');
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('duoyi_local_calendar_events_v1')!;
      expect(saved.length, 1);
      expect((jsonDecode(saved.single) as Map)['id'], 'B');
    },
  );

  test(
    'held calendar create invalidates its lease and restores disk',
    () async {
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      var current = true;
      store.holdNext = true;
      final pending = provider.addLocalEvent(
        _event('A', 'old event'),
        canWrite: () => current,
      );
      final result = pending.then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await store.started.future;
      current = false;
      store.release.complete();
      expect(await result, isA<AccountPreferenceWriteCanceled>());
      expect(provider.localEvents, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('duoyi_local_calendar_events_v1') ?? [],
        isEmpty,
      );
      await provider.addLocalEvent(_event('B', 'new event'));
      expect(provider.localEvents.single.id, 'B');
    },
  );

  test('account cleanup drains held calendar create and rollback', () async {
    final provider = CalendarProvider();
    addTearDown(provider.dispose);
    store.holdNext = true;
    final pending = provider.addLocalEvent(_event('A', 'old event'));
    final result = pending.then<Object?>(
      (_) => null,
      onError: (Object error) => error,
    );
    await store.started.future;
    var cleared = false;
    final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then(
      (_) => cleared = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(cleared, isFalse);
    store.release.complete();
    expect(await result, isA<AccountPreferenceWriteCanceled>());
    await cleanup;
    expect(provider.localEvents, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.containsKey('duoyi_local_calendar_events_v1'), isFalse);
  });

  test(
    'a reserved preference boundary cannot publish an unwritten event',
    () async {
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      final entered = Completer<void>();
      final released = Completer<void>();
      final boundary = AccountPreferenceWrites.boundary(() async {
        entered.complete();
        await released.future;
      });
      await entered.future;
      try {
        await expectLater(
          provider.addLocalEvent(_event('ghost', 'unwritten')),
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        expect(provider.localEvents, isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('duoyi_local_calendar_events_v1'), isFalse);
      } finally {
        released.complete();
        await boundary;
      }
    },
  );
}

CalendarEvent _event(String id, String title) => CalendarEvent(
  id: id,
  sourceId: id,
  title: title,
  date: DateTime(2026, 10, 12),
  type: CalendarEventType.event,
  color: const Color(0xFF5B6EE1),
);

class _CalendarStore extends InMemorySharedPreferencesStore {
  _CalendarStore() : super.withData({});
  bool rejectNext = false;
  bool holdNext = false;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.duoyi_local_calendar_events_v1') {
      if (rejectNext) {
        rejectNext = false;
        return false;
      }
      if (holdNext) {
        holdNext = false;
        started.complete();
        await release.future;
      }
    }
    return super.setValue(type, key, value);
  }
}
