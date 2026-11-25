// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../test_support/recording_reminder_scheduler.dart';

const _oldTombstones = <String, Object>{
  'todos': <String, String>{'keep-todo': '2026-10-01T12:00:00.000Z'},
  'notes': <String, String>{'keep-note': '2026-10-02T12:00:00.000Z'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Store store;
  late CountdownProvider countdowns;
  late AnniversaryProvider anniversaries;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    countdowns = CountdownProvider();
    anniversaries = AnniversaryProvider();
  });

  tearDown(() async {
    store.releaseAll();
    await AccountPreferenceWrites.drain();
    countdowns.dispose();
    anniversaries.dispose();
  });

  final providers = <_ProviderCase>[
    _ProviderCase('CountdownProvider', () => _countdownHarness(countdowns)),
    _ProviderCase(
      'AnniversaryProvider',
      () => _anniversaryHarness(anniversaries),
    ),
  ];

  for (final providerCase in providers) {
    for (final throws in [false, true]) {
      test(
        '${providerCase.name} rejects platform false/throw without publishing and retries ($throws)',
        () async {
          final data = providerCase.create();
          await data.add(data.newItem('same', 'Confirmed', false));
          final prefs = await SharedPreferences.getInstance();
          final originalStorage = List<String>.of(
            prefs.getStringList(data.storageKey)!,
          );
          final originalMemory = data.snapshot();
          final scheduler = RecordingReminderScheduler()
            ..countdownSyncError = const ReminderScheduleSyncException([
              'injected reminder warning',
            ])
            ..anniversarySyncError = const ReminderScheduleSyncException([
              'injected reminder warning',
            ]);
          data.setScheduler(scheduler);

          var persisted = 0;
          var notifications = 0;
          data.onLocalMutationPersisted = () => persisted++;
          data.addListener(() => notifications++);
          store.rejectNext(data.platformListKey, throws: throws);

          await expectLater(
            data.update(data.newItem('same', 'Unconfirmed', true)),
            throwsA(isA<StateError>()),
          );

          expect(data.snapshot(), equals(originalMemory));
          expect(prefs.getStringList(data.storageKey), equals(originalStorage));
          expect(persisted, 0);
          expect(notifications, 0);

          final warning = await data.update(
            data.newItem('same', 'Confirmed with reminder', true),
          );
          expect(warning, isNotEmpty);
          expect(warning, isNot(contains('injected reminder warning')));
          expect(data.entry('same')!['title'], 'Confirmed with reminder');
          expect(
            _storedEntry(prefs, data, 'same')!['title'],
            'Confirmed with reminder',
          );
          expect(persisted, 1);
          expect(notifications, 1);
        },
      );
    }

    test(
      '${providerCase.name} cold mutation hydrates storage and serializes consecutive adds',
      () async {
        final data = providerCase.create();
        final prefs = await SharedPreferences.getInstance();
        final stored = data.newItem('from-disk', 'Stored item', false);
        await prefs.setStringList(data.storageKey, [
          jsonEncode(data.toJson(stored)),
        ]);
        final writesBefore = store.writeCount(data.platformListKey);
        var persisted = 0;
        data.onLocalMutationPersisted = () => persisted++;

        store.holdNext(data.platformListKey);
        final first = data.add(data.newItem('first', 'First add', false));
        await store.heldWriteStarted.timeout(const Duration(seconds: 2));
        expect(data.ids, {'from-disk'});
        expect(persisted, 0);

        final second = data.add(data.newItem('second', 'Second add', false));
        await Future<void>.delayed(Duration.zero);
        expect(store.writeCount(data.platformListKey), writesBefore + 1);

        store.releaseAll();
        await Future.wait([first, second]);

        expect(data.ids, {'from-disk', 'first', 'second'});
        expect(_storedIds(prefs, data), {'from-disk', 'first', 'second'});
        expect(store.writeCount(data.platformListKey), writesBefore + 2);
        expect(persisted, 2);
      },
    );

    test(
      '${providerCase.name} all mutation APIs honor false and throwing canWrite guards',
      () async {
        final data = providerCase.create();
        await data.add(data.newItem('existing', 'Existing', false));
        final prefs = await SharedPreferences.getInstance();
        final originalStorage = List<String>.of(
          prefs.getStringList(data.storageKey)!,
        );
        final originalMemory = data.snapshot();
        final listWritesBefore = store.writeCount(data.platformListKey);
        final tombstoneWritesBefore = store.writeCount(_platformTombstoneKey);
        var persisted = 0;
        var notifications = 0;
        data.onLocalMutationPersisted = () => persisted++;
        data.addListener(() => notifications++);

        final operations = <Future<void> Function(bool Function())>[
          (canWrite) async {
            await data.add(
              data.newItem('guard-add', 'Guarded add', false),
              canWrite: canWrite,
            );
          },
          (canWrite) async {
            await data.update(
              data.newItem('existing', 'Guarded update', false),
              canWrite: canWrite,
            );
          },
          (canWrite) async {
            await data.importItems([
              data.newItem('guard-import', 'Guarded import', false),
            ], canWrite: canWrite);
          },
          (canWrite) async {
            await data.togglePin('existing', canWrite: canWrite);
          },
          (canWrite) async {
            await data.setPinned('existing', true, canWrite: canWrite);
          },
          (canWrite) async {
            await data.delete('existing', canWrite: canWrite);
          },
        ];

        for (final operation in operations) {
          for (final guardThrows in [false, true]) {
            bool guard() {
              if (guardThrows) throw StateError('origin expired');
              return false;
            }

            await expectLater(
              operation(guard),
              throwsA(isA<AccountPreferenceWriteCanceled>()),
            );
            expect(data.snapshot(), equals(originalMemory));
            expect(
              prefs.getStringList(data.storageKey),
              equals(originalStorage),
            );
            expect(store.writeCount(data.platformListKey), listWritesBefore);
            expect(
              store.writeCount(_platformTombstoneKey),
              tombstoneWritesBefore,
            );
            expect(persisted, 0);
            expect(notifications, 0);
          }
        }

        await data.add(data.newItem('guard-add', 'Guarded add', false));
        await data.update(data.newItem('existing', 'Updated existing', false));
        expect(
          await data.importItems([
            data.newItem('guard-import', 'Guarded import', false),
          ]),
          1,
        );
        await data.togglePin('existing');
        await data.setPinned('guard-add', true);
        final afterPinWrite = data.snapshot();
        final pinWriteCount = store.writeCount(data.platformListKey);
        final pinPersistedCount = persisted;
        final pinNotificationCount = notifications;
        await data.setPinned('guard-add', true);
        expect(data.snapshot(), equals(afterPinWrite));
        expect(store.writeCount(data.platformListKey), pinWriteCount);
        expect(persisted, pinPersistedCount);
        expect(notifications, pinNotificationCount);
        await data.delete('existing');

        expect(data.ids, {'guard-add', 'guard-import'});
        expect(data.entry('guard-add')!['isPinned'], isTrue);
        expect(_storedIds(prefs, data), {'guard-add', 'guard-import'});
        expect(_tombstoneIds(prefs, data.collection), {'existing'});
        expect(persisted, 6);
        expect(notifications, 6);
      },
    );

    test(
      '${providerCase.name} reset cancels held write without a late publication',
      () async {
        final data = providerCase.create();
        await data.add(data.newItem('same', 'Confirmed', false));
        final prefs = await SharedPreferences.getInstance();
        final originalStorage = List<String>.of(
          prefs.getStringList(data.storageKey)!,
        );
        final generation = data.storageGeneration();
        var persisted = 0;
        var notifications = 0;
        data.onLocalMutationPersisted = () => persisted++;
        data.addListener(() => notifications++);
        store.holdNext(data.platformListKey);

        final saving = data.update(data.newItem('same', 'Held draft', false));
        final canceled = expectLater(
          saving,
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        try {
          await store.heldWriteStarted.timeout(const Duration(seconds: 2));
          expect(data.entry('same')!['title'], 'Confirmed');
          expect(persisted, 0);
          expect(notifications, 0);
          data.reset();
          expect(data.storageGeneration(), generation + 1);
          expect(data.snapshot(), isEmpty);
          expect(notifications, 1); // reset's own notification only.
        } finally {
          store.releaseAll();
        }
        await canceled;

        expect(data.snapshot(), isEmpty);
        expect(prefs.getStringList(data.storageKey), equals(originalStorage));
        expect(persisted, 0);
        expect(notifications, 1);
      },
    );

    test(
      '${providerCase.name} account cleanup drains a held write and removes its disk state',
      () async {
        final data = providerCase.create();
        await data.add(data.newItem('same', 'Confirmed', false));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          CloudSyncProvider.deletedItemsStorageKey,
          jsonEncode(_oldTombstones),
        );
        var persisted = 0;
        var notifications = 0;
        data.onLocalMutationPersisted = () => persisted++;
        data.addListener(() => notifications++);
        store.holdNext(data.platformListKey);

        final saving = data.update(data.newItem('same', 'Held draft', false));
        final canceled = expectLater(
          saving,
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        var cleanupFinished = false;
        Future<void>? cleanup;
        try {
          await store.heldWriteStarted.timeout(const Duration(seconds: 2));
          cleanup = AccountLocalDataCleaner.clearSharedPreferences().then((_) {
            cleanupFinished = true;
          });
          await Future<void>.delayed(Duration.zero);
          expect(cleanupFinished, isFalse);
          expect(persisted, 0);
          expect(notifications, 0);
        } finally {
          store.releaseAll();
        }
        await Future.wait([canceled, cleanup]);

        expect(prefs.getStringList(data.storageKey), isNull);
        expect(
          prefs.getString(CloudSyncProvider.deletedItemsStorageKey),
          isNull,
        );
        expect(persisted, 0);
        expect(notifications, 0);
      },
    );

    for (final target in ['list', 'tombstone']) {
      for (final throws in [false, true]) {
        test(
          '${providerCase.name} rejected delete $target write rolls back both keys and can retry ($throws)',
          () async {
            final data = providerCase.create();
            await data.add(data.newItem('delete-me', 'Delete me', false));
            await data.add(data.newItem('keep-me', 'Keep me', false));
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
              CloudSyncProvider.deletedItemsStorageKey,
              jsonEncode(_oldTombstones),
            );
            final originalList = List<String>.of(
              prefs.getStringList(data.storageKey)!,
            );
            final originalTombstones = prefs.getString(
              CloudSyncProvider.deletedItemsStorageKey,
            );
            var persisted = 0;
            var notifications = 0;
            data.onLocalMutationPersisted = () => persisted++;
            data.addListener(() => notifications++);
            store.rejectNext(
              target == 'list' ? data.platformListKey : _platformTombstoneKey,
              throws: throws,
            );

            await expectLater(
              data.delete('delete-me'),
              throwsA(isA<StateError>()),
            );

            expect(prefs.getStringList(data.storageKey), equals(originalList));
            expect(
              prefs.getString(CloudSyncProvider.deletedItemsStorageKey),
              originalTombstones,
            );
            expect(data.ids, {'delete-me', 'keep-me'});
            expect(persisted, 0);
            expect(notifications, 0);

            await data.delete('delete-me');

            expect(data.ids, {'keep-me'});
            expect(_storedIds(prefs, data), {'keep-me'});
            expect(_tombstoneIds(prefs, data.collection), {'delete-me'});
            expect(_tombstoneIds(prefs, 'todos'), {'keep-todo'});
            expect(_tombstoneIds(prefs, 'notes'), {'keep-note'});
            expect(persisted, 1);
            expect(notifications, 1);
          },
        );
      }
    }

    for (final throwsGuard in [false, true]) {
      for (final stage in ['update', 'delete-list', 'delete-tombstone']) {
        test(
          '${providerCase.name} held $stage cancels revoked authority ($throwsGuard)',
          () async {
            final data = providerCase.create();
            await data.add(data.newItem('same', 'Confirmed', false));
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
              CloudSyncProvider.deletedItemsStorageKey,
              jsonEncode(_oldTombstones),
            );
            final originalList = List<String>.of(
              prefs.getStringList(data.storageKey)!,
            );
            final originalTombstones = prefs.getString(
              CloudSyncProvider.deletedItemsStorageKey,
            );
            var current = true;
            bool canWrite() {
              if (!current && throwsGuard) {
                throw StateError('revoked authority');
              }
              return current;
            }

            var published = 0;
            data.onLocalMutationPersisted = () => published++;
            store.holdNext(
              stage == 'delete-tombstone'
                  ? _platformTombstoneKey
                  : data.platformListKey,
            );
            final operation = stage == 'update'
                ? data.update(
                    data.newItem('same', 'Unconfirmed', false),
                    canWrite: canWrite,
                  )
                : data.delete('same', canWrite: canWrite);
            final canceled = expectLater(
              operation,
              throwsA(isA<AccountPreferenceWriteCanceled>()),
            );
            try {
              await store.heldWriteStarted.timeout(const Duration(seconds: 2));
              current = false;
            } finally {
              store.releaseAll();
            }
            await canceled;
            expect(data.entry('same')!['title'], 'Confirmed');
            expect(prefs.getStringList(data.storageKey), originalList);
            expect(
              prefs.getString(CloudSyncProvider.deletedItemsStorageKey),
              originalTombstones,
            );
            expect(published, 0);
          },
        );
      }
    }
  }

  for (final anniversary in [false, true]) {
    for (final invalidate in ['reset', 'dispose']) {
      test(
        'date provider ($anniversary) held load rejects $invalidate',
        () async {
          final countdown = CountdownProvider();
          final memorial = AnniversaryProvider();
          final key = anniversary
              ? 'flutter.duoyi_anniversaries_v2'
              : 'flutter.duoyi_countdowns';
          final record = anniversary
              ? Anniversary(
                  id: 'stored',
                  title: 'Stored',
                  originDate: DateTime(2099),
                ).toJson()
              : CountdownItem(
                  id: 'stored',
                  title: 'Stored',
                  targetDate: DateTime(2099),
                ).toJson();
          await store.setValue('StringList', key, [jsonEncode(record)]);
          store.holdRead();
          var notifications = 0;
          final provider = anniversary ? memorial : countdown;
          provider.addListener(() => notifications++);
          final loading = anniversary
              ? memorial.loadFromStorage()
              : countdown.loadFromStorage();
          final canceled = expectLater(
            loading,
            throwsA(isA<AccountPreferenceWriteCanceled>()),
          );
          try {
            await store.readStarted.timeout(const Duration(seconds: 2));
            if (invalidate == 'reset') {
              anniversary
                  ? memorial.resetLocalState()
                  : countdown.resetLocalState();
            } else {
              provider.dispose();
            }
          } finally {
            store.releaseAll();
          }
          await canceled;
          expect(anniversary ? memorial.items : countdown.items, isEmpty);
          expect(notifications, invalidate == 'reset' ? 1 : 0);
          if (invalidate != 'dispose') provider.dispose();
          (anniversary ? countdown : memorial).dispose();
        },
      );
    }
    test(
      'date provider ($anniversary) read failure is reported and can retry',
      () async {
        final data = anniversary
            ? _anniversaryHarness(anniversaries)
            : _countdownHarness(countdowns);
        store.failNextRead = true;
        var notifications = 0;
        data.addListener(() => notifications++);
        final load = anniversary
            ? anniversaries.loadFromStorage
            : countdowns.loadFromStorage;
        await expectLater(load(), throwsA(isA<StateError>()));
        expect(data.items(), isEmpty);
        expect(notifications, 0);
        await load();
        expect(data.items(), isEmpty);
        expect(notifications, 1);
      },
    );
  }

  test(
    'AnniversaryProvider copies mutable inputs at add, update, and import commit',
    () async {
      final data = _anniversaryHarness(anniversaries);
      final prefs = await SharedPreferences.getInstance();

      final added = data.newItem('mutable-add', 'Added', false) as Anniversary;
      await data.add(added);
      final addedSnapshot = data.entry('mutable-add')!;
      _mutateCallerAnniversary(added);
      expect(data.entry('mutable-add'), equals(addedSnapshot));
      expect(_storedEntry(prefs, data, 'mutable-add'), equals(addedSnapshot));

      final updated =
          data.newItem('mutable-add', 'Updated', false) as Anniversary;
      await data.update(updated);
      final updatedSnapshot = data.entry('mutable-add')!;
      _mutateCallerAnniversary(updated);
      expect(data.entry('mutable-add'), equals(updatedSnapshot));
      expect(_storedEntry(prefs, data, 'mutable-add'), equals(updatedSnapshot));

      final imported =
          data.newItem('mutable-import', 'Imported', false) as Anniversary;
      expect(await data.importItems([imported]), 1);
      final importedSnapshot = data.entry('mutable-import')!;
      _mutateCallerAnniversary(imported);
      expect(data.entry('mutable-import'), equals(importedSnapshot));
      expect(
        _storedEntry(prefs, data, 'mutable-import'),
        equals(importedSnapshot),
      );
    },
  );
  test(
    'AnniversaryProvider copies caller inputs before queued and held writes',
    () async {
      final data = _anniversaryHarness(anniversaries);
      store.holdNext(data.platformListKey);
      final first =
          data.newItem('first', 'First snapshot', false) as Anniversary;
      final firstWrite = data.add(first);
      final queued =
          data.newItem('queued', 'Queued snapshot', false) as Anniversary;
      final queuedWrite = data.add(queued);
      try {
        await store.heldWriteStarted.timeout(const Duration(seconds: 2));
        _mutateCallerAnniversary(first);
        _mutateCallerAnniversary(queued);
      } finally {
        store.releaseAll();
      }
      await Future.wait([firstWrite, queuedWrite]);
      final prefs = await SharedPreferences.getInstance();
      expect(data.entry('first')!['title'], 'First snapshot');
      expect(data.entry('queued')!['title'], 'Queued snapshot');
      expect(_storedEntry(prefs, data, 'first')!['title'], 'First snapshot');
      expect(_storedEntry(prefs, data, 'queued')!['title'], 'Queued snapshot');
    },
  );
}

const _platformTombstoneKey = 'flutter.sync_deleted_items';

class _ProviderCase {
  const _ProviderCase(this.name, this.create);

  final String name;
  final _Harness Function() create;
}

class _Harness {
  const _Harness({
    required this.storageKey,
    required this.platformListKey,
    required this.collection,
    required this.items,
    required this.toJson,
    required this.makeItem,
    required this.add,
    required this.update,
    required this.importItems,
    required this.delete,
    required this.togglePin,
    required this.setPinned,
    required this.reset,
    required this.storageGeneration,
    required this.setScheduler,
    required this.setOnLocalMutationPersisted,
    required this.addListener,
  });

  final String storageKey;
  final String platformListKey;
  final String collection;
  final List<Object> Function() items;
  final Map<String, dynamic> Function(Object item) toJson;
  final Object Function(String id, String title, bool remind) makeItem;
  final Future<String?> Function(Object item, {bool Function()? canWrite}) add;
  final Future<String?> Function(Object item, {bool Function()? canWrite})
  update;
  final Future<int> Function(
    Iterable<Object> items, {
    bool Function()? canWrite,
  })
  importItems;
  final Future<void> Function(String id, {bool Function()? canWrite}) delete;
  final Future<void> Function(String id, {bool Function()? canWrite}) togglePin;
  final Future<void> Function(
    String id,
    bool pinned, {
    bool Function()? canWrite,
  })
  setPinned;
  final void Function() reset;
  final int Function() storageGeneration;
  final void Function(RecordingReminderScheduler scheduler) setScheduler;
  final void Function(void Function()? callback) setOnLocalMutationPersisted;
  final void Function(void Function() listener) addListener;

  Object newItem(String id, String title, bool remind) =>
      makeItem(id, title, remind);

  set onLocalMutationPersisted(void Function()? callback) =>
      setOnLocalMutationPersisted(callback);

  List<Map<String, dynamic>> snapshot() => items()
      .map((item) => Map<String, dynamic>.from(toJson(item)))
      .toList(growable: false);

  Set<String> get ids =>
      items().map((item) => toJson(item)['id'] as String).toSet();

  Map<String, dynamic>? entry(String id) {
    for (final item in items()) {
      final json = toJson(item);
      if (json['id'] == id) return Map<String, dynamic>.from(json);
    }
    return null;
  }
}

_Harness _countdownHarness(CountdownProvider provider) => _Harness(
  storageKey: 'duoyi_countdowns',
  platformListKey: 'flutter.duoyi_countdowns',
  collection: 'countdowns',
  items: () => List<Object>.of(provider.items),
  toJson: (item) => (item as CountdownItem).toJson(),
  makeItem: (id, title, remind) => CountdownItem(
    id: id,
    title: title,
    targetDate: DateTime(2099, 7, 1),
    remind: remind,
  ),
  add: (item, {canWrite}) =>
      provider.addItem(item as CountdownItem, canWrite: canWrite),
  update: (item, {canWrite}) =>
      provider.updateItem(item as CountdownItem, canWrite: canWrite),
  importItems: (items, {canWrite}) async => (await provider.importCountdowns(
    items.cast<CountdownItem>(),
    canWrite: canWrite,
  )).inserted,
  delete: (id, {canWrite}) => provider.deleteItem(id, canWrite: canWrite),
  togglePin: (id, {canWrite}) => provider.togglePin(id, canWrite: canWrite),
  setPinned: (id, pinned, {canWrite}) =>
      provider.setPinned(id, pinned, canWrite: canWrite),
  reset: provider.resetLocalState,
  storageGeneration: () => provider.storageGeneration,
  setScheduler: (scheduler) => provider.scheduler = scheduler,
  setOnLocalMutationPersisted: (callback) =>
      provider.onLocalMutationPersisted = callback,
  addListener: provider.addListener,
);

_Harness _anniversaryHarness(AnniversaryProvider provider) => _Harness(
  storageKey: 'duoyi_anniversaries_v2',
  platformListKey: 'flutter.duoyi_anniversaries_v2',
  collection: 'anniversaries',
  items: () => List<Object>.of(provider.items),
  toJson: (item) => (item as Anniversary).toJson(),
  makeItem: (id, title, remind) => Anniversary(
    id: id,
    title: title,
    originDate: DateTime(2099, 7, 1),
    type: AnniversaryType.memorial,
    remind: remind,
  ),
  add: (item, {canWrite}) =>
      provider.add(item as Anniversary, canWrite: canWrite),
  update: (item, {canWrite}) =>
      provider.update(item as Anniversary, canWrite: canWrite),
  importItems: (items, {canWrite}) async => (await provider.importAnniversaries(
    items.cast<Anniversary>(),
    canWrite: canWrite,
  )).inserted,
  delete: (id, {canWrite}) => provider.delete(id, canWrite: canWrite),
  togglePin: (id, {canWrite}) => provider.togglePin(id, canWrite: canWrite),
  setPinned: (id, pinned, {canWrite}) =>
      provider.setPinned(id, pinned, canWrite: canWrite),
  reset: provider.resetLocalState,
  storageGeneration: () => provider.storageGeneration,
  setScheduler: (scheduler) => provider.scheduler = scheduler,
  setOnLocalMutationPersisted: (callback) =>
      provider.onLocalMutationPersisted = callback,
  addListener: provider.addListener,
);

List<String> _storedRaw(SharedPreferences prefs, _Harness data) =>
    prefs.getStringList(data.storageKey) ?? const <String>[];

Set<String> _storedIds(SharedPreferences prefs, _Harness data) =>
    _storedRaw(prefs, data)
        .map((raw) => (jsonDecode(raw) as Map<String, dynamic>)['id'] as String)
        .toSet();

Map<String, dynamic>? _storedEntry(
  SharedPreferences prefs,
  _Harness data,
  String id,
) {
  for (final raw in _storedRaw(prefs, data)) {
    final entry = jsonDecode(raw) as Map<String, dynamic>;
    if (entry['id'] == id) return entry;
  }
  return null;
}

Set<String> _tombstoneIds(SharedPreferences prefs, String collection) {
  final raw = prefs.getString(CloudSyncProvider.deletedItemsStorageKey);
  if (raw == null) return <String>{};
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final bucket = decoded[collection];
  if (bucket is! Map) return <String>{};
  return bucket.keys.map((key) => key.toString()).toSet();
}

void _mutateCallerAnniversary(Anniversary item) {
  item.title = 'mutated after commit';
  item.description = 'caller-owned description';
  item.originDate = DateTime(2100, 8, 9);
  item.colorValue = 0xFF000000;
  item.isPinned = !item.isPinned;
  item.remind = !item.remind;
  item.remindDaysBefore = 17;
  item.remindHour = 18;
  item.remindMinute = 42;
  item.ignoreYear = !item.ignoreYear;
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData(<String, Object>{});

  final Map<String, int> _writes = <String, int>{};
  bool failNextRead = false;
  Completer<void>? _readStarted;
  Completer<void>? _readRelease;
  Future<void> get readStarted => _readStarted!.future;
  void holdRead() {
    _readStarted = Completer<void>();
    _readRelease = Completer<void>();
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    if (_readRelease != null && !_readRelease!.isCompleted) {
      _readStarted!.complete();
      await _readRelease!.future;
    }
    if (failNextRead) {
      failNextRead = false;
      throw StateError('injected read failure');
    }
    return super.getAllWithParameters(parameters);
  }

  String? _rejectKey;
  bool _throwOnRejection = false;
  String? _heldKey;
  Completer<void>? _heldWriteStarted;
  Completer<void>? _heldWriteRelease;

  Future<void> get heldWriteStarted => _heldWriteStarted!.future;

  int writeCount(String key) => _writes[key] ?? 0;

  void rejectNext(String key, {required bool throws}) {
    _rejectKey = key;
    _throwOnRejection = throws;
  }

  void holdNext(String key) {
    _heldKey = key;
    _heldWriteStarted = Completer<void>();
    _heldWriteRelease = Completer<void>();
  }

  void releaseAll() {
    if (_readRelease != null && !_readRelease!.isCompleted) {
      _readRelease!.complete();
    }
    final release = _heldWriteRelease;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    _writes.update(key, (count) => count + 1, ifAbsent: () => 1);
    if (_heldKey == key) {
      _heldKey = null;
      _heldWriteStarted!.complete();
      await _heldWriteRelease!.future;
    }

    // Model a platform that changes storage before returning false or throwing.
    final saved = await super.setValue(type, key, value);
    if (_rejectKey == key) {
      final shouldThrow = _throwOnRejection;
      _rejectKey = null;
      _throwOnRejection = false;
      if (shouldThrow) throw StateError('injected platform write failure');
      return false;
    }
    return saved;
  }
}
