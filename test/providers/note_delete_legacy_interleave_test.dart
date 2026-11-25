// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NoteProvider notes;
  late _Store store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    notes = NoteProvider();
  });
  tearDown(() async {
    store.release();
    await AccountPreferenceWrites.drain();
    notes.dispose();
  });

  test('acknowledged delete wins over a held same-ID legacy draft', () async {
    await notes.addOrUpdateNotePersisted(_note('same', 'original'));
    final prefs = await SharedPreferences.getInstance();
    store.hold = true;
    final deleting = notes.deleteNotePersisted('same');
    try {
      await store.started.future.timeout(const Duration(seconds: 2));
      notes.addOrUpdateNote(_note('same', 'new optimistic draft'));
      notes.addOrUpdateNote(_note('distinct', 'keep distinct draft'));
    } finally {
      store.release();
    }
    await deleting;
    await AccountPreferenceWrites.drain();

    expect(notes.notes.map((note) => note.id), ['distinct']);
    expect(_storedNotes(prefs).map((note) => note.id), ['distinct']);
    final deleted =
        jsonDecode(prefs.getString(CloudSyncProvider.deletedItemsStorageKey)!)
            as Map<String, dynamic>;
    expect((deleted['notes'] as Map).keys, ['same']);
  });

  test(
    'canceled delete preserves a newer legacy draft and no tombstone',
    () async {
      await notes.addOrUpdateNotePersisted(_note('same', 'original'));
      final prefs = await SharedPreferences.getInstance();
      var allowed = true;
      store.hold = true;
      final deleting = notes.deleteNotePersisted(
        'same',
        canWrite: () => allowed,
      );
      final canceled = expectLater(
        deleting,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      try {
        await store.started.future.timeout(const Duration(seconds: 2));
        notes.addOrUpdateNote(_note('same', 'new optimistic draft'));
        allowed = false;
      } finally {
        store.release();
      }
      await canceled;
      await AccountPreferenceWrites.drain();

      expect(notes.notes.single.content, 'new optimistic draft');
      expect(_storedNotes(prefs).single.content, 'new optimistic draft');
      expect(prefs.getString(CloudSyncProvider.deletedItemsStorageKey), isNull);
    },
  );
}

NoteItem _note(String id, String text) => NoteItem(
  id: id,
  content: text,
  createdAt: DateTime(2026, 10, 15),
  updatedAt: DateTime(2026, 10, 15),
);

List<NoteItem> _storedNotes(SharedPreferences prefs) =>
    (prefs.getStringList('duoyi_notes') ?? [])
        .map((raw) => NoteItem.fromJson(jsonDecode(raw)))
        .toList();

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  bool hold = false;
  final started = Completer<void>();
  final gate = Completer<void>();

  void release() {
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.duoyi_notes' && hold) {
      hold = false;
      started.complete();
      await gate.future;
    }
    return super.setValue(type, key, value);
  }
}
