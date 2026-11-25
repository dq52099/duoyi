import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late NoteProvider notes;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    notes = NoteProvider();
  });
  tearDown(() async {
    notes.dispose();
    await AccountPreferenceWrites.drain();
  });

  test(
    'cold shared import hydrates existing notes before acknowledged save',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('duoyi_notes', [
        jsonEncode(_note('old').toJson()),
      ]);
      var persisted = 0;
      notes.onLocalMutationPersisted = () => persisted++;
      store.hold = true;
      final saving = notes.addOrUpdateNotePersisted(_note('shared'));
      await store.started.future;
      expect(notes.notes.map((note) => note.id), ['old']);
      expect(persisted, 0);
      store.release.complete();
      await saving;
      expect(notes.notes.map((note) => note.id).toSet(), {'old', 'shared'});
      expect(_storedIds(prefs), {'old', 'shared'});
      expect(persisted, 1);
    },
  );

  for (final throws in [false, true]) {
    test(
      'rejected platform save $throws restores storage and permits same-ID retry',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('duoyi_notes', [
          jsonEncode(_note('old').toJson()),
        ]);
        var persisted = 0;
        notes.onLocalMutationPersisted = () => persisted++;
        store.reject = true;
        store.throws = throws;
        await expectLater(
          notes.addOrUpdateNotePersisted(_note('shared')),
          throwsStateError,
        );
        expect(notes.notes.map((note) => note.id), ['old']);
        expect(_storedIds(prefs), {'old'});
        expect(persisted, 0);
        await notes.addOrUpdateNotePersisted(_note('shared'));
        await notes.addOrUpdateNotePersisted(_note('shared'));
        expect(_storedIds(prefs), {'old', 'shared'});
        expect(notes.notes.where((note) => note.id == 'shared'), hasLength(1));
      },
    );
  }

  test(
    'queued acknowledged imports serialize and retain every accepted note',
    () async {
      final prefs = await SharedPreferences.getInstance();
      store.hold = true;
      final first = notes.addOrUpdateNotePersisted(_note('one'));
      await store.started.future;
      final second = notes.addOrUpdateNotePersisted(_note('two'));
      expect(store.noteWrites, 1);
      store.release.complete();
      await Future.wait([first, second]);
      expect(store.noteWrites, 2);
      expect(_storedIds(prefs), {'one', 'two'});
      expect(notes.notes.map((note) => note.id).toSet(), {'one', 'two'});
    },
  );

  test(
    'newer legacy same-ID draft survives a held acknowledged update',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await notes.addOrUpdateNotePersisted(_note('same', 'original'));
      store.hold = true;
      final saving = notes.addOrUpdateNotePersisted(_note('same', 'imported'));
      await store.started.future;
      notes.addOrUpdateNote(_note('same', 'newer editor draft'));
      notes.addOrUpdateNote(_note('distinct', 'another note'));
      store.release.complete();
      await saving;
      await AccountPreferenceWrites.drain();
      expect(
        notes.notes.firstWhere((note) => note.id == 'same').content,
        'newer editor draft',
      );
      final saved = prefs
          .getStringList('duoyi_notes')!
          .map((raw) => NoteItem.fromJson(jsonDecode(raw)));
      expect(
        saved.firstWhere((note) => note.id == 'same').content,
        'newer editor draft',
      );
      expect(_storedIds(prefs), {'same', 'distinct'});
    },
  );

  test(
    'account cleanup waits for issued write and cancels its queued follower',
    () async {
      final prefs = await SharedPreferences.getInstance();
      store.hold = true;
      var persisted = 0;
      notes.onLocalMutationPersisted = () => persisted++;
      final first = notes.addOrUpdateNotePersisted(_note('departing'));
      final firstRejected = expectLater(
        first,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await store.started.future;
      final follower = notes.addOrUpdateNotePersisted(_note('queued-old'));
      final followerRejected = expectLater(
        follower,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      var cleaned = false;
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then(
        (_) => cleaned = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isFalse);
      notes.resetLocalState();
      store.release.complete();
      await Future.wait([firstRejected, followerRejected, cleanup]);
      expect(prefs.getStringList('duoyi_notes'), isNull);
      expect(notes.notes, isEmpty);
      expect(persisted, 0);
      await notes.addOrUpdateNotePersisted(_note('new-account'));
      expect(_storedIds(prefs), {'new-account'});
    },
  );

  test(
    'reset cancels queued cold import before issuing its storage write',
    () async {
      final saving = notes.addOrUpdateNotePersisted(_note('stale'));
      final rejected = expectLater(
        saving,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      notes.resetLocalState();
      await rejected;
      expect(store.noteWrites, 0);
      expect(notes.notes, isEmpty);
    },
  );
}

NoteItem _note(String id, [String? content]) => NoteItem(
  id: id,
  content: content ?? 'literal / 保留原文 $id',
  createdAt: DateTime(2026, 10, 12),
  updatedAt: DateTime(2026, 10, 12),
);

Set<String> _storedIds(SharedPreferences prefs) =>
    (prefs.getStringList('duoyi_notes') ?? [])
        .map((raw) => (jsonDecode(raw) as Map<String, dynamic>)['id'] as String)
        .toSet();

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  bool hold = false;
  bool reject = false;
  bool throws = false;
  int noteWrites = 0;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != 'flutter.duoyi_notes') return super.setValue(type, key, value);
    noteWrites++;
    if (hold && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    // Simulate a platform that changed storage before reporting failure.
    await super.setValue(type, key, value);
    if (reject) {
      reject = false;
      if (throws) throw StateError('injected note failure');
      return false;
    }
    return true;
  }
}
