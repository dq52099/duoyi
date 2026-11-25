// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'rejected add is not published and retries as one persisted entry',
    () async {
      final store = _installStore();
      final provider = TimeAuditProvider();
      await provider.loadFromStorage();
      var notifications = 0;
      var callbacks = 0;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => callbacks++;

      final entry = _entry('retry-entry', 'first save rejected');
      store.rejectNextTimeEntryWrite = true;
      await expectLater(provider.add(entry), throwsA(isA<StateError>()));

      expect(provider.entries, isEmpty);
      expect(notifications, 0);
      expect(callbacks, 0);
      expect(store.timeEntrySetAttempts, 1);
      expect(await _storedEntries(store), isEmpty);

      final retried = entry.copyWith(title: 'retry saved');
      await provider.add(retried);

      expect(_entryFingerprints(provider), [jsonEncode(retried.toJson())]);
      expect(notifications, 1);
      expect(callbacks, 1);
      expect(store.timeEntrySetAttempts, 2);
      expect(await _storedEntries(store), [jsonEncode(retried.toJson())]);

      // Reload the plugin cache from the platform store before hydrating a new
      // provider, so this checks persisted preferences rather than the first
      // provider's in-memory list.
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final reloaded = TimeAuditProvider();
      await reloaded.loadFromStorage();
      expect(_entryFingerprints(reloaded), [jsonEncode(retried.toJson())]);

      provider.dispose();
      reloaded.dispose();
    },
  );

  test(
    'rejected update throws without persisted callback or notification',
    () async {
      final original = _entry('update-entry', 'stored value');
      final store = _installStore(entries: [original]);
      final provider = TimeAuditProvider();
      await provider.loadFromStorage();
      var notifications = 0;
      var callbacks = 0;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => callbacks++;

      final rejected = original.copyWith(title: 'in-memory rejected value');
      store.rejectNextTimeEntryWrite = true;
      await expectLater(provider.update(rejected), throwsA(isA<StateError>()));

      expect(_entryFingerprints(provider), [jsonEncode(original.toJson())]);
      expect(notifications, 0);
      expect(callbacks, 0);
      // The rejected platform call is followed by restoration of the old value.
      expect(store.timeEntrySetAttempts, 2);
      expect(await _storedEntries(store), [jsonEncode(original.toJson())]);
      provider.dispose();
    },
  );

  test('reset and dispose advance the storage generation', () {
    final provider = TimeAuditProvider();
    final beforeReset = provider.storageGeneration;
    expect(provider.isDisposed, isFalse);

    provider.resetLocalState();
    final afterReset = provider.storageGeneration;
    expect(afterReset, greaterThan(beforeReset));
    expect(provider.isDisposed, isFalse);

    provider.dispose();
    expect(provider.isDisposed, isTrue);
    expect(provider.storageGeneration, greaterThan(afterReset));
  });
}

_RejectingPreferencesStore _installStore({List<TimeEntry> entries = const []}) {
  final values = <String, Object>{
    if (entries.isNotEmpty)
      TimeAuditProvider.storageKey: entries.map(jsonEncode).toList(),
  };
  SharedPreferences.setMockInitialValues(values);
  final store = _RejectingPreferencesStore({
    for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
  });
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

TimeEntry _entry(String id, String title) => TimeEntry(
  id: id,
  title: title,
  startAt: DateTime(2026, 10, 9, 9),
  endAt: DateTime(2026, 10, 9, 9, 30),
  category: TimeEntryCategory.study,
  createdAt: DateTime(2026, 10, 9, 8),
  updatedAt: DateTime(2026, 10, 9, 8),
);

Future<List<String>> _storedEntries(_RejectingPreferencesStore store) async {
  final values = await store.getAll();
  final raw = values['flutter.${TimeAuditProvider.storageKey}'];
  return raw is List ? raw.cast<String>() : <String>[];
}

List<String> _entryFingerprints(TimeAuditProvider provider) => provider.entries
    .map((entry) => jsonEncode(entry.toJson()))
    .toList(growable: false);

class _RejectingPreferencesStore extends InMemorySharedPreferencesStore {
  _RejectingPreferencesStore(super.data) : super.withData();

  bool rejectNextTimeEntryWrite = false;
  int timeEntrySetAttempts = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.${TimeAuditProvider.storageKey}') {
      timeEntrySetAttempts++;
      if (rejectNextTimeEntryWrite) {
        rejectNextTimeEntryWrite = false;
        return false;
      }
    }
    return super.setValue(valueType, key, value);
  }
}
