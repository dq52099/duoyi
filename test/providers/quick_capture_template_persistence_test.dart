// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/quick_capture_template.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/quick_capture_template_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _templatesKey = 'duoyi_quick_capture_templates_v1';
const _deletedItemsKey = 'sync_deleted_items';
Completer<void>? _activeExternalLockRelease;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _TemplateStore store;
  late QuickCaptureTemplateProvider provider;
  var providerDisposed = false;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _TemplateStore();
    SharedPreferencesStorePlatform.instance = store;
    _activeStore = store;
    provider = QuickCaptureTemplateProvider();
    providerDisposed = false;
  });

  tearDown(() async {
    store.releaseAll();
    final externalRelease = _activeExternalLockRelease;
    if (externalRelease != null && !externalRelease.isCompleted) {
      externalRelease.complete();
    }
    await AccountPreferenceWrites.drain();
    _activeExternalLockRelease = null;
    if (!providerDisposed) provider.dispose();
  });

  test(
    'cold save hydrates stored templates and publishes only after acknowledgement',
    () async {
      final prefs = await _seed([_template('existing')]);
      var notifications = 0;
      var persisted = 0;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => persisted++;
      store.holdNextTemplateSet = true;

      final saving = provider.saveTemplate(_template('new'));
      await store.templateSetEntered.future.timeout(const Duration(seconds: 1));
      expect(provider.customTemplates, isEmpty);
      expect(notifications, 0);
      expect(persisted, 0);

      store.releaseTemplateSet.complete();
      await saving;

      expect(_ids(provider.customTemplates), {'existing', 'new'});
      expect(_storedIds(prefs), {'existing', 'new'});
      expect(notifications, 1);
      expect(persisted, 1);
    },
  );

  for (final throws in [false, true]) {
    test(
      'rejected save throws=$throws restores cold storage and permits retry',
      () async {
        final prefs = await _seed([_template('existing')]);
        var notifications = 0;
        var persisted = 0;
        provider.addListener(() => notifications++);
        provider.onLocalMutationPersisted = () => persisted++;
        store.rejectNextTemplateSet = true;
        store.throwOnTemplateRejection = throws;

        await expectLater(
          provider.saveTemplate(_template('retry')),
          throwsA(isA<StateError>()),
        );
        expect(provider.customTemplates, isEmpty);
        expect(_storedIds(prefs), {'existing'});
        expect(notifications, 0);
        expect(persisted, 0);

        await provider.saveTemplate(_template('retry'));
        expect(_ids(provider.customTemplates), {'existing', 'retry'});
        expect(_storedIds(prefs), {'existing', 'retry'});
        expect(notifications, 1);
        expect(persisted, 1);
      },
    );
  }

  test(
    'queued edits and load run serially against acknowledged storage',
    () async {
      final prefs = await _seed([_template('existing')]);
      var notifications = 0;
      var persisted = 0;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => persisted++;
      store.holdNextTemplateSet = true;

      final first = provider.saveTemplate(_template('first'));
      await store.templateSetEntered.future.timeout(const Duration(seconds: 1));
      final second = provider.saveTemplate(_template('second'));
      final load = provider.loadFromStorage();
      expect(store.templateSetAttempts, 1);

      store.releaseTemplateSet.complete();
      await Future.wait([first, second, load]);

      expect(store.templateSetAttempts, 2);
      expect(_ids(provider.customTemplates), {'existing', 'first', 'second'});
      expect(_storedIds(prefs), {'existing', 'first', 'second'});
      expect(notifications, 3);
      expect(persisted, 2);
    },
  );

  for (final rejectedWrite in ['tombstone', 'template snapshot']) {
    for (final throws in [false, true]) {
      test(
        'delete rolls back rejected $rejectedWrite write throws=$throws and can retry',
        () async {
          final prefs = await _seed(
            [_template('remove'), _template('keep')],
            tombstones: <String, Object>{
              'todos': <String, String>{'prior': '2026-10-14T00:00:00.000Z'},
            },
          );
          await provider.loadFromStorage();
          final templatesBefore = prefs.getString(_templatesKey);
          final tombstonesBefore = prefs.getString(_deletedItemsKey);
          var notifications = 0;
          var persisted = 0;
          provider.addListener(() => notifications++);
          provider.onLocalMutationPersisted = () => persisted++;
          if (rejectedWrite == 'tombstone') {
            store.rejectNextTombstoneSet = true;
            store.throwOnTombstoneRejection = throws;
          } else {
            store.rejectNextTemplateSet = true;
            store.throwOnTemplateRejection = throws;
          }

          await expectLater(
            provider.deleteTemplate('remove'),
            throwsA(isA<StateError>()),
          );
          expect(_ids(provider.customTemplates), {'remove', 'keep'});
          expect(prefs.getString(_templatesKey), templatesBefore);
          expect(prefs.getString(_deletedItemsKey), tombstonesBefore);
          expect(notifications, 0);
          expect(persisted, 0);

          await provider.deleteTemplate('remove');
          expect(_ids(provider.customTemplates), {'keep'});
          expect(_storedIds(prefs), {'keep'});
          expect(_tombstones(prefs)['todos'], contains('prior'));
          expect(
            _tombstones(prefs)['quick_capture_templates'],
            contains('remove'),
          );
          expect(notifications, 1);
          expect(persisted, 1);
        },
      );
    }
  }

  test(
    'failed delete rollback stays inside tombstone lock and preserves another collection',
    () async {
      final prefs = await _seed([_template('remove')]);
      await provider.loadFromStorage();
      final templatesBefore = prefs.getString(_templatesKey);
      store.holdNextTombstoneSet = true;
      store.rejectNextTemplateSet = true;

      final deleting = expectLater(
        provider.deleteTemplate('remove'),
        throwsA(isA<StateError>()),
      );
      await store.tombstoneSetEntered.future.timeout(
        const Duration(seconds: 1),
      );
      final otherCollection = CloudSyncProvider.recordDeletedItem(
        'todos',
        'distinct-todo',
      );
      await Future<void>.delayed(Duration.zero);
      store.releaseTombstoneSet.complete();
      await Future.wait([deleting, otherCollection]);

      final deleted = _tombstones(prefs);
      expect(deleted['todos'], contains('distinct-todo'));
      expect(deleted['quick_capture_templates'], isNull);
      expect(prefs.getString(_templatesKey), templatesBefore);
      expect(_ids(provider.customTemplates), {'remove'});
    },
  );

  for (final invalidation in ['reset', 'dispose']) {
    test(
      '$invalidation during held save cancels its queued follower',
      () async {
        final prefs = await _seed([_template('existing')]);
        await provider.loadFromStorage();
        var notifications = 0;
        var persisted = 0;
        provider.addListener(() => notifications++);
        provider.onLocalMutationPersisted = () => persisted++;
        store.holdNextTemplateSet = true;

        final first = provider.saveTemplate(_template('departing'));
        final firstRejected = expectLater(
          first,
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        await store.templateSetEntered.future.timeout(
          const Duration(seconds: 1),
        );
        final follower = provider.saveTemplate(_template('queued-old'));
        final followerRejected = expectLater(
          follower,
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );

        if (invalidation == 'reset') {
          provider.resetLocalState();
        } else {
          provider.dispose();
          providerDisposed = true;
        }
        store.releaseTemplateSet.complete();
        await Future.wait([firstRejected, followerRejected]);

        expect(prefs.getString(_templatesKey), isNotNull);
        expect(_storedIds(prefs), {'existing'});
        expect(
          _ids(provider.customTemplates),
          invalidation == 'reset' ? isEmpty : {'existing'},
        );
        expect(notifications, invalidation == 'reset' ? 1 : 0);
        expect(persisted, 0);
        expect(store.templateSetAttempts, 2); // Failed write plus rollback.
      },
    );
  }

  test(
    'account cleanup drains held save and cancels its queued follower',
    () async {
      final prefs = await _seed([_template('existing')]);
      await provider.loadFromStorage();
      var notifications = 0;
      var persisted = 0;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => persisted++;
      store.holdNextTemplateSet = true;

      final first = provider.saveTemplate(_template('departing'));
      final firstRejected = expectLater(
        first,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await store.templateSetEntered.future.timeout(const Duration(seconds: 1));
      final follower = provider.saveTemplate(_template('queued-old'));
      final followerRejected = expectLater(
        follower,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );

      var cleaned = false;
      final cleanup = AccountLocalDataCleaner.runPreferenceBoundary(() async {
        provider.resetLocalState();
        await AccountLocalDataCleaner.clearSharedPreferences();
        cleaned = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isFalse);
      store.releaseTemplateSet.complete();
      await Future.wait([firstRejected, followerRejected, cleanup]);

      expect(prefs.getString(_templatesKey), isNull);
      expect(provider.customTemplates, isEmpty);
      expect(notifications, 1);
      expect(persisted, 0);
    },
  );

  test(
    'account invalidation cancels delete while waiting for tombstone lock',
    () async {
      final prefs = await _seed([_template('remove')]);
      await provider.loadFromStorage();
      final templatesBefore = prefs.getString(_templatesKey);
      final deletedBefore = prefs.getString(_deletedItemsKey);
      final lockEntered = Completer<void>();
      final releaseLock = Completer<void>();
      _activeExternalLockRelease = releaseLock;
      final lockHolder = CloudSyncProvider.withDeletedItemsLock((_) async {
        lockEntered.complete();
        await releaseLock.future;
      });
      final holderRejected = expectLater(
        lockHolder,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await lockEntered.future.timeout(const Duration(seconds: 1));

      final deleting = provider.deleteTemplate('remove');
      final deleteRejected = expectLater(
        deleting,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await Future<void>.delayed(Duration.zero);
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      releaseLock.complete();
      await Future.wait([holderRejected, deleteRejected]);
      _activeExternalLockRelease = null;

      expect(prefs.getString(_templatesKey), templatesBefore);
      expect(prefs.getString(_deletedItemsKey), deletedBefore);
      expect(_ids(provider.customTemplates), {'remove'});
      expect(store.writes, isEmpty);
    },
  );
}

Future<SharedPreferences> _seed(
  List<QuickCaptureTemplate> templates, {
  Map<String, Object>? tombstones,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _templatesKey,
    jsonEncode(templates.map((template) => template.toJson()).toList()),
  );
  if (tombstones != null) {
    await prefs.setString(_deletedItemsKey, jsonEncode(tombstones));
  }
  // Ignore fixture setup writes in per-operation counts and traces.
  _activeStore!.resetTracking();
  return prefs;
}

_TemplateStore? _activeStore;

QuickCaptureTemplate _template(String id) => QuickCaptureTemplate(
  id: id,
  name: 'Template $id',
  kind: QuickCaptureTemplateKind.todo,
  titlePrefix: 'Prefix $id',
  createdAt: DateTime.utc(2026, 10, 12),
  updatedAt: DateTime.utc(2026, 10, 12),
);

Set<String> _ids(Iterable<QuickCaptureTemplate> templates) =>
    templates.map((template) => template.id).toSet();

Set<String> _storedIds(SharedPreferences prefs) =>
    _storedTemplates(prefs).map((template) => template.id).toSet();

List<QuickCaptureTemplate> _storedTemplates(SharedPreferences prefs) {
  final raw = prefs.getString(_templatesKey);
  if (raw == null) return const [];
  return (jsonDecode(raw) as List)
      .map(
        (item) => QuickCaptureTemplate.fromJson(
          Map<String, dynamic>.from(item as Map),
        ),
      )
      .toList();
}

Map<String, dynamic> _tombstones(SharedPreferences prefs) =>
    jsonDecode(prefs.getString(_deletedItemsKey) ?? '{}')
        as Map<String, dynamic>;

class _TemplateStore extends InMemorySharedPreferencesStore {
  _TemplateStore() : super.withData({});

  bool holdNextTemplateSet = false;
  bool rejectNextTemplateSet = false;
  bool throwOnTemplateRejection = false;
  bool holdNextTombstoneSet = false;
  bool rejectNextTombstoneSet = false;
  bool throwOnTombstoneRejection = false;
  int templateSetAttempts = 0;
  int tombstoneSetAttempts = 0;
  final writes = <String>[];
  final templateSetEntered = Completer<void>();
  final releaseTemplateSet = Completer<void>();
  final tombstoneSetEntered = Completer<void>();
  final releaseTombstoneSet = Completer<void>();

  void releaseAll() {
    if (!releaseTemplateSet.isCompleted) releaseTemplateSet.complete();
    if (!releaseTombstoneSet.isCompleted) releaseTombstoneSet.complete();
  }

  void resetTracking() {
    templateSetAttempts = 0;
    tombstoneSetAttempts = 0;
    writes.clear();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes.add(key);
    if (key == 'flutter.$_templatesKey') {
      templateSetAttempts++;
      final reject = rejectNextTemplateSet;
      final throwError = throwOnTemplateRejection;
      rejectNextTemplateSet = false;
      throwOnTemplateRejection = false;
      if (holdNextTemplateSet && !templateSetEntered.isCompleted) {
        holdNextTemplateSet = false;
        templateSetEntered.complete();
        await releaseTemplateSet.future;
      }
      await super.setValue(type, key, value);
      if (reject) {
        if (throwError) throw StateError('synthetic template write failure');
        return false;
      }
      return true;
    }
    if (key == 'flutter.$_deletedItemsKey') {
      tombstoneSetAttempts++;
      final reject = rejectNextTombstoneSet;
      final throwError = throwOnTombstoneRejection;
      rejectNextTombstoneSet = false;
      throwOnTombstoneRejection = false;
      if (holdNextTombstoneSet && !tombstoneSetEntered.isCompleted) {
        holdNextTombstoneSet = false;
        tombstoneSetEntered.complete();
        await releaseTombstoneSet.future;
      }
      await super.setValue(type, key, value);
      if (reject) {
        if (throwError) throw StateError('synthetic tombstone write failure');
        return false;
      }
      return true;
    }
    return super.setValue(type, key, value);
  }
}
