// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _entriesKey = 'flutter.duoyi_time_entries';
const _tombstonesKey = 'flutter.sync_deleted_items';
const _timeout = Duration(seconds: 3);
const _existingTombstones = <String, Map<String, String>>{
  'todos': {'previous-deletion': '2026-10-18T09:00:00.000'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final deleting in [false, true]) {
    test(
      '${deleting ? 'delete' : 'add'} keeps disk and memory consistent across acknowledgement and boundary orderings',
      () async {
        var acknowledgements = 0;
        var cancellations = 0;

        // Sweep external boundary timing around the final platform reply.
        // Registered await continuations can propagate synchronously from
        // commit through publication. Failure to observe a callback inside
        // the boundary is not evidence of a commit/publication race.
        for (var hops = 0; hops <= 24; hops++) {
          final acknowledged = await _exerciseBoundary(
            deleting: deleting,
            hops: hops,
          );
          if (acknowledged) {
            acknowledgements++;
          } else {
            cancellations++;
          }
        }

        expect(
          acknowledgements,
          greaterThan(0),
          reason: 'The sweep must include acknowledgement before the boundary.',
        );
        expect(
          cancellations,
          greaterThan(0),
          reason: 'The sweep must include a boundary before acknowledgement.',
        );
      },
    );
  }
}

Future<bool> _exerciseBoundary({
  required bool deleting,
  required int hops,
}) async {
  final retained = _entry('retained');
  final changed = _entry(deleting ? 'deleted-entry' : 'added-entry');
  final before = [retained, if (deleting) changed];
  final after = [retained, if (!deleting) changed];
  final beforeDisk = <String, Object>{
    _entriesKey: _encode(before),
    _tombstonesKey: jsonEncode(_existingTombstones),
  };
  SharedPreferences.setMockInitialValues({
    TimeAuditProvider.storageKey: _encode(before),
    'sync_deleted_items': jsonEncode(_existingTombstones),
  });
  final store = _BoundaryStore(beforeDisk);
  SharedPreferencesStorePlatform.instance = store;

  final provider = TimeAuditProvider();
  TimeAuditProvider? reloaded;
  Future<void>? boundary;
  final boundaryEntered = Completer<void>();
  final releaseBoundary = Completer<void>();
  var callbacks = 0;
  var notifications = 0;
  final reason = '${deleting ? 'delete' : 'add'}, microtask hops: $hops';

  try {
    await provider.loadFromStorage();
    final storageGeneration = provider.storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    provider.addListener(() => notifications++);
    provider.onLocalMutationPersisted = () {
      callbacks++;
    };
    store.armedKey = deleting ? _tombstonesKey : _entriesKey;
    store.beforeAcknowledgement = () {
      _afterMicrotasks(hops, () {
        boundary = AccountLocalDataCleaner.runPreferenceBoundary(() async {
          boundaryEntered.complete();
          await releaseBoundary.future;
        });
      });
    };

    // Attach the error observer before the platform acknowledgement resumes.
    final mutation = deleting
        ? provider.delete(changed.id)
        : provider.add(changed);
    final error = await mutation
        .then<Object?>(
          (_) => null,
          onError: (Object error, StackTrace _) => error,
        )
        .timeout(_timeout);
    await boundaryEntered.future.timeout(_timeout);

    expect(provider.storageGeneration, storageGeneration, reason: reason);
    expect(
      AccountLocalDataCleaner.accountDataGeneration,
      accountGeneration,
      reason: reason,
    );
    final disk = await store.readDisk();
    final acknowledged = error == null;
    if (acknowledged) {
      expect(disk[_entriesKey], _encode(after), reason: reason);
      _expectEntries(provider.entries, after, reason: reason);
      expect(callbacks, 1, reason: reason);
      expect(notifications, 1, reason: reason);
      final tombstones = jsonDecode(disk[_tombstonesKey]! as String) as Map;
      expect(tombstones['todos'], _existingTombstones['todos'], reason: reason);
      if (deleting) {
        expect(
          tombstones['time_entries'],
          contains(changed.id),
          reason: reason,
        );
      } else {
        expect(tombstones['time_entries'], isNull, reason: reason);
      }
    } else {
      expect(error, isA<AccountPreferenceWriteCanceled>(), reason: reason);
      expect(
        disk,
        beforeDisk,
        reason: '$reason: cancellation must restore disk',
      );
      _expectEntries(provider.entries, before, reason: reason);
      expect(callbacks, 0, reason: reason);
      expect(notifications, 0, reason: reason);
    }

    releaseBoundary.complete();
    await boundary!.timeout(_timeout);

    // A fresh provider must agree with disk after refreshing the legacy cache.
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    reloaded = TimeAuditProvider();
    await reloaded.loadFromStorage();
    _expectEntries(
      reloaded.entries,
      acknowledged ? after : before,
      reason: reason,
    );
    return acknowledged;
  } finally {
    if (!releaseBoundary.isCompleted) releaseBoundary.complete();
    final pendingBoundary = boundary;
    if (pendingBoundary != null) await pendingBoundary.timeout(_timeout);
    await AccountPreferenceWrites.drain().timeout(_timeout);
    provider.dispose();
    reloaded?.dispose();
  }
}

void _afterMicrotasks(int hops, void Function() callback) {
  scheduleMicrotask(() {
    if (hops == 0) {
      callback();
    } else {
      _afterMicrotasks(hops - 1, callback);
    }
  });
}

List<String> _encode(Iterable<TimeEntry> entries) =>
    entries.map((entry) => jsonEncode(entry.toJson())).toList();

void _expectEntries(
  Iterable<TimeEntry> actual,
  Iterable<TimeEntry> expected, {
  required String reason,
}) {
  expect(
    {for (final entry in actual) entry.id: jsonEncode(entry.toJson())},
    {for (final entry in expected) entry.id: jsonEncode(entry.toJson())},
    reason: reason,
  );
  expect(actual.length, expected.length, reason: reason);
}

TimeEntry _entry(String id) => TimeEntry(
  id: id,
  title: id,
  startAt: DateTime(2026, 10, 19, 9),
  endAt: DateTime(2026, 10, 19, 9, 30),
  category: TimeEntryCategory.study,
  createdAt: DateTime(2026, 10, 19, 8),
  updatedAt: DateTime(2026, 10, 19, 8),
);

class _BoundaryStore extends InMemorySharedPreferencesStore {
  _BoundaryStore(super.values) : super.withData();

  String? armedKey;
  void Function()? beforeAcknowledgement;

  Future<Map<String, Object>> readDisk() => super.getAll();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    // Model a platform reply delivered asynchronously. The boundary is an
    // external event; no hook runs inside the provider's commit/publication.
    if (key == armedKey) {
      final callback = beforeAcknowledgement;
      beforeAcknowledgement = null;
      callback?.call();
    }
    return await super.setValue(valueType, key, value);
  }
}
