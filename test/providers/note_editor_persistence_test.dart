// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _notesKey = 'duoyi_notes';
const _platformNotesKey = 'flutter.duoyi_notes';
const _platformDeletedItemsKey = 'flutter.sync_deleted_items';
const _oldDeletedItems = <String, Object>{
  'todos': <String, String>{'keep-todo': '2026-10-01T12:00:00.000Z'},
  'notes': <String, String>{'old-deleted-note': '2026-10-02T12:00:00.000Z'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late NoteProvider notes;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    notes = NoteProvider();
  });

  tearDown(() async {
    store.releaseAll();
    await AccountPreferenceWrites.drain();
    notes.dispose();
  });

  test(
    'save guard false and throw pre-reject without a platform write',
    () async {
      final prefs = await SharedPreferences.getInstance();
      var persisted = 0;
      notes.onLocalMutationPersisted = () => persisted++;

      for (final throws in [false, true]) {
        bool guard() {
          if (throws) throw StateError('origin no longer current');
          return false;
        }

        await expectLater(
          notes.addOrUpdateNotePersisted(_note('blocked'), canWrite: guard),
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );

        expect(store.noteWrites, 0);
        expect(store.tombstoneWrites, 0);
        expect(prefs.getStringList(_notesKey), isNull);
        expect(notes.notes, isEmpty);
        expect(persisted, 0);
      }
    },
  );

  test(
    'delete guard false and throw pre-reject without a platform write',
    () async {
      await notes.addOrUpdateNotePersisted(_note('keep'));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        CloudSyncProvider.deletedItemsStorageKey,
        jsonEncode(_oldDeletedItems),
      );
      final noteWritesBefore = store.noteWrites;
      final tombstoneWritesBefore = store.tombstoneWrites;
      final oldTombstones = prefs.getString(
        CloudSyncProvider.deletedItemsStorageKey,
      );
      var persisted = 0;
      notes.onLocalMutationPersisted = () => persisted++;

      for (final throws in [false, true]) {
        bool guard() {
          if (throws) throw StateError('origin no longer current');
          return false;
        }

        await expectLater(
          notes.deleteNotePersisted('keep', canWrite: guard),
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );

        expect(store.noteWrites, noteWritesBefore);
        expect(store.tombstoneWrites, tombstoneWritesBefore);
        expect(_storedIds(prefs), {'keep'});
        expect(
          prefs.getString(CloudSyncProvider.deletedItemsStorageKey),
          oldTombstones,
        );
        expect(_noteIds(notes.notes), {'keep'});
        expect(persisted, 0);
      }
    },
  );

  test('held save guard expiry rolls back and permits retry', () async {
    await notes.addOrUpdateNotePersisted(_note('same', 'original content'));
    final prefs = await SharedPreferences.getInstance();
    final originalStorage = List<String>.of(prefs.getStringList(_notesKey)!);
    var allowed = true;
    var persisted = 0;
    notes.onLocalMutationPersisted = () => persisted++;
    store.holdNextNotesWrite();

    final saving = notes.addOrUpdateNotePersisted(
      _note('same', 'unacknowledged edit'),
      canWrite: () => allowed,
    );
    final rejected = expectLater(
      saving,
      throwsA(isA<AccountPreferenceWriteCanceled>()),
    );
    try {
      await store.noteStarted.future.timeout(const Duration(seconds: 2));
      expect(notes.notes.single.content, 'original content');
      allowed = false;
    } finally {
      store.releaseNotesWrite();
    }
    await rejected;

    expect(notes.notes.single.content, 'original content');
    expect(prefs.getStringList(_notesKey), originalStorage);
    expect(persisted, 0);

    allowed = true;
    await notes.addOrUpdateNotePersisted(
      _note('same', 'retry content'),
      canWrite: () => allowed,
    );
    expect(notes.notes.single.content, 'retry content');
    expect(_storedNotes(prefs).single.content, 'retry content');
    expect(persisted, 1);
  });

  test('delete commits note removal and tombstone together', () async {
    await notes.addOrUpdateNotePersisted(_note('delete-me'));
    await notes.addOrUpdateNotePersisted(_note('keep-me'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      CloudSyncProvider.deletedItemsStorageKey,
      jsonEncode(_oldDeletedItems),
    );
    final noteWritesBefore = store.noteWrites;
    final tombstoneWritesBefore = store.tombstoneWrites;
    var persisted = 0;
    notes.onLocalMutationPersisted = () => persisted++;

    await notes.deleteNotePersisted('delete-me');

    expect(_noteIds(notes.notes), {'keep-me'});
    expect(_storedIds(prefs), {'keep-me'});
    expect(store.noteWrites, noteWritesBefore + 1);
    expect(store.tombstoneWrites, tombstoneWritesBefore + 1);
    expect(_tombstoneIds(prefs, 'notes'), {'old-deleted-note', 'delete-me'});
    expect(_tombstoneIds(prefs, 'todos'), {'keep-todo'});
    expect(persisted, 1);
  });

  for (final target in ['notes', 'tombstone']) {
    for (final throws in [false, true]) {
      test(
        'rejected delete $target write rolls back both keys and can retry ($throws)',
        () async {
          await notes.addOrUpdateNotePersisted(_note('delete-me'));
          await notes.addOrUpdateNotePersisted(_note('keep-me'));
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            CloudSyncProvider.deletedItemsStorageKey,
            jsonEncode(_oldDeletedItems),
          );
          final originalNotes = List<String>.of(
            prefs.getStringList(_notesKey)!,
          );
          final originalTombstones = prefs.getString(
            CloudSyncProvider.deletedItemsStorageKey,
          );
          var persisted = 0;
          notes.onLocalMutationPersisted = () => persisted++;
          store.rejectNextKey = target == 'notes'
              ? _platformNotesKey
              : _platformDeletedItemsKey;
          store.throwOnRejection = throws;

          await expectLater(
            notes.deleteNotePersisted('delete-me'),
            throwsA(isA<StateError>()),
          );

          expect(prefs.getStringList(_notesKey), originalNotes);
          expect(
            prefs.getString(CloudSyncProvider.deletedItemsStorageKey),
            originalTombstones,
          );
          expect(_noteIds(notes.notes), {'delete-me', 'keep-me'});
          expect(persisted, 0);

          await notes.deleteNotePersisted('delete-me');

          expect(_noteIds(notes.notes), {'keep-me'});
          expect(_storedIds(prefs), {'keep-me'});
          expect(_tombstoneIds(prefs, 'notes'), {
            'old-deleted-note',
            'delete-me',
          });
          expect(_tombstoneIds(prefs, 'todos'), {'keep-todo'});
          expect(persisted, 1);
        },
      );
    }
  }

  test('held tombstone guard expiry rolls back both delete keys', () async {
    await notes.addOrUpdateNotePersisted(_note('delete-me'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      CloudSyncProvider.deletedItemsStorageKey,
      jsonEncode(_oldDeletedItems),
    );
    final originalNotes = List<String>.of(prefs.getStringList(_notesKey)!);
    final originalTombstones = prefs.getString(
      CloudSyncProvider.deletedItemsStorageKey,
    );
    var allowed = true;
    var persisted = 0;
    notes.onLocalMutationPersisted = () => persisted++;
    store.holdNextTombstoneWrite();

    final deleting = notes.deleteNotePersisted(
      'delete-me',
      canWrite: () => allowed,
    );
    final rejected = expectLater(
      deleting,
      throwsA(isA<AccountPreferenceWriteCanceled>()),
    );
    try {
      await store.tombstoneStarted.future.timeout(const Duration(seconds: 2));
      expect(_noteIds(notes.notes), {'delete-me'});
      allowed = false;
    } finally {
      store.releaseTombstoneWrite();
    }
    await rejected;

    expect(prefs.getStringList(_notesKey), originalNotes);
    expect(
      prefs.getString(CloudSyncProvider.deletedItemsStorageKey),
      originalTombstones,
    );
    expect(_noteIds(notes.notes), {'delete-me'});
    expect(persisted, 0);

    allowed = true;
    await notes.deleteNotePersisted('delete-me', canWrite: () => allowed);
    expect(notes.notes, isEmpty);
    expect(_storedIds(prefs), isEmpty);
    expect(_tombstoneIds(prefs, 'notes'), {'old-deleted-note', 'delete-me'});
    expect(persisted, 1);
  });

  test(
    'post-commit callback invalidation does not reject save or delete',
    () async {
      var allowed = true;
      var persisted = 0;
      notes.onLocalMutationPersisted = () {
        persisted++;
        allowed = false;
      };

      await notes.addOrUpdateNotePersisted(
        _note('confirmed'),
        canWrite: () => allowed,
      );
      expect(allowed, isFalse);
      expect(_noteIds(notes.notes), {'confirmed'});
      expect(persisted, 1);

      allowed = true;
      await notes.deleteNotePersisted('confirmed', canWrite: () => allowed);

      final prefs = await SharedPreferences.getInstance();
      expect(allowed, isFalse);
      expect(notes.notes, isEmpty);
      expect(_storedIds(prefs), isEmpty);
      expect(_tombstoneIds(prefs, 'notes'), {'confirmed'});
      expect(persisted, 2);
    },
  );

  test(
    'reset and account cleanup cancel old queued writes before new account save',
    () async {
      await notes.addOrUpdateNotePersisted(_note('old-account-note'));
      final prefs = await SharedPreferences.getInstance();
      final generation = notes.storageGeneration;
      var persisted = 0;
      notes.onLocalMutationPersisted = () => persisted++;
      store.holdNextNotesWrite();

      final oldSave = notes.addOrUpdateNotePersisted(_note('old-queued-save'));
      final oldSaveRejected = expectLater(
        oldSave,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      try {
        await store.noteStarted.future.timeout(const Duration(seconds: 2));
        final oldDelete = notes.deleteNotePersisted('old-account-note');
        final oldDeleteRejected = expectLater(
          oldDelete,
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        final cleanup = AccountLocalDataCleaner.clearSharedPreferences();
        notes.resetLocalState();
        expect(notes.storageGeneration, generation + 1);
        expect(notes.notes, isEmpty);
        store.releaseNotesWrite();
        await Future.wait([oldSaveRejected, oldDeleteRejected, cleanup]);
      } finally {
        store.releaseNotesWrite();
      }

      expect(prefs.getStringList(_notesKey), isNull);
      expect(prefs.getString(CloudSyncProvider.deletedItemsStorageKey), isNull);
      expect(notes.notes, isEmpty);
      expect(persisted, 0);

      await notes.addOrUpdateNotePersisted(_note('new-account-note'));
      expect(_storedIds(prefs), {'new-account-note'});
      expect(notes.notes.single.id, 'new-account-note');
      expect(prefs.getString(CloudSyncProvider.deletedItemsStorageKey), isNull);
      expect(persisted, 1);
    },
  );
}

NoteItem _note(String id, [String? content]) => NoteItem(
  id: id,
  content: content ?? 'literal / 保留原文 $id',
  createdAt: DateTime(2026, 10, 12),
  updatedAt: DateTime(2026, 10, 12),
);

List<NoteItem> _storedNotes(SharedPreferences prefs) =>
    (prefs.getStringList(_notesKey) ?? [])
        .map((raw) => NoteItem.fromJson(jsonDecode(raw)))
        .toList();

Set<String> _storedIds(SharedPreferences prefs) =>
    _storedNotes(prefs).map((note) => note.id).toSet();

Set<String> _noteIds(Iterable<NoteItem> source) =>
    source.map((note) => note.id).toSet();

Set<String> _tombstoneIds(SharedPreferences prefs, String collection) {
  final raw = prefs.getString(CloudSyncProvider.deletedItemsStorageKey);
  if (raw == null) return <String>{};
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final bucket = decoded[collection];
  if (bucket is! Map) return <String>{};
  return bucket.keys.map((key) => key.toString()).toSet();
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData(<String, Object>{});

  int noteWrites = 0;
  int tombstoneWrites = 0;
  String? rejectNextKey;
  bool throwOnRejection = false;
  bool _holdNextNote = false;
  bool _holdNextTombstone = false;
  Completer<void> noteStarted = Completer<void>();
  Completer<void> noteRelease = Completer<void>();
  Completer<void> tombstoneStarted = Completer<void>();
  Completer<void> tombstoneRelease = Completer<void>();

  void holdNextNotesWrite() {
    _holdNextNote = true;
    noteStarted = Completer<void>();
    noteRelease = Completer<void>();
  }

  void holdNextTombstoneWrite() {
    _holdNextTombstone = true;
    tombstoneStarted = Completer<void>();
    tombstoneRelease = Completer<void>();
  }

  void releaseNotesWrite() {
    if (!noteRelease.isCompleted) noteRelease.complete();
  }

  void releaseTombstoneWrite() {
    if (!tombstoneRelease.isCompleted) tombstoneRelease.complete();
  }

  void releaseAll() {
    releaseNotesWrite();
    releaseTombstoneWrite();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final isNotes = key == _platformNotesKey;
    final isTombstone = key == _platformDeletedItemsKey;
    if (isNotes) noteWrites++;
    if (isTombstone) tombstoneWrites++;
    final saved = await super.setValue(type, key, value);

    if (isNotes && _holdNextNote) {
      _holdNextNote = false;
      noteStarted.complete();
      await noteRelease.future;
    } else if (isTombstone && _holdNextTombstone) {
      _holdNextTombstone = false;
      tombstoneStarted.complete();
      await tombstoneRelease.future;
    }

    if (rejectNextKey == key) {
      rejectNextKey = null;
      final shouldThrow = throwOnRejection;
      throwOnRejection = false;
      if (shouldThrow) throw StateError('injected preference write failure');
      return false;
    }
    return saved;
  }
}
