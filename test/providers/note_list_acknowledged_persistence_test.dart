// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _notesKey = 'duoyi_notes';
const _platformNotesKey = 'flutter.duoyi_notes';

typedef _Setter =
    Future<void> Function(
      NoteProvider provider,
      String id,
      bool value, {
      bool Function()? canWrite,
    });

class _Mutation {
  const _Mutation({required this.name, required this.set, required this.read});

  final String name;
  final _Setter set;
  final bool Function(NoteItem note) read;
}

class _HeldInterleaveCase {
  const _HeldInterleaveCase({
    required this.name,
    required this.set,
    required this.targetValue,
    required this.oldPinned,
    required this.oldArchived,
    required this.draftPinned,
    required this.draftArchived,
    required this.expectedPinned,
    required this.expectedArchived,
  });

  final String name;
  final _Setter set;
  final bool targetValue;
  final bool oldPinned;
  final bool oldArchived;
  final bool draftPinned;
  final bool draftArchived;
  final bool expectedPinned;
  final bool expectedArchived;
}

Future<void> _setPinned(
  NoteProvider provider,
  String id,
  bool value, {
  bool Function()? canWrite,
}) => provider.setPinnedPersisted(id, value, canWrite: canWrite);

Future<void> _setArchived(
  NoteProvider provider,
  String id,
  bool value, {
  bool Function()? canWrite,
}) => provider.setArchivedPersisted(id, value, canWrite: canWrite);

const _mutations = <_Mutation>[
  _Mutation(name: 'pinned', set: _setPinned, read: _readPinned),
  _Mutation(name: 'archived', set: _setArchived, read: _readArchived),
];

bool _readPinned(NoteItem note) => note.pinned;
bool _readArchived(NoteItem note) => note.archived;

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

  for (final mutation in _mutations) {
    test(
      '${mutation.name} setter persists the requested value without toggling',
      () async {
        final id = '${mutation.name}-repeat';
        final original = _richNote(
          id,
          pinned: mutation.name == 'pinned',
          archived: mutation.name == 'archived',
        );
        await notes.addOrUpdateNotePersisted(original);
        final prefs = await SharedPreferences.getInstance();
        final writesBeforeSet = store.noteWrites;
        var persisted = 0;
        notes.onLocalMutationPersisted = () => persisted++;

        await mutation.set(notes, id, false);
        await mutation.set(notes, id, false);

        final current = notes.notes.single;
        final saved = _storedNote(prefs, id)!;
        expect(mutation.read(current), isFalse);
        expect(mutation.read(saved), isFalse);
        // Restoring an archived note retains its current pin state.
        expect(current.pinned, isFalse);
        expect(current.archived, isFalse);
        expect(current.updatedAt.isAfter(original.updatedAt), isTrue);
        expect(saved.updatedAt, current.updatedAt);
        expect(notes.activeNotes.map((note) => note.id), [id]);
        expect(notes.archivedNotes, isEmpty);
        _expectUnchangedFields(current, original);
        _expectUnchangedFields(saved, original);
        expect(store.noteWrites, writesBeforeSet + 1);
        expect(persisted, 1);
      },
    );

    test(
      '${mutation.name} setter does not publish memory or callback before commit',
      () async {
        final id = '${mutation.name}-held';
        final original = _richNote(id);
        await notes.addOrUpdateNotePersisted(original);
        final prefs = await SharedPreferences.getInstance();
        var persisted = 0;
        var notifications = 0;
        notes.onLocalMutationPersisted = () => persisted++;
        notes.addListener(() => notifications++);
        store.holdNextNotesWrite();

        final saving = mutation.set(notes, id, true);
        try {
          await store.noteStarted.future.timeout(const Duration(seconds: 2));
          expect(notes.notes.single.toJson(), equals(original.toJson()));
          // SharedPreferences updates its process cache before the platform
          // write completes; the provider's published model remains guarded.
          expect(persisted, 0);
          expect(notifications, 0);
        } finally {
          store.releaseNotesWrite();
        }
        await saving;

        final current = notes.notes.single;
        expect(mutation.read(current), isTrue);
        if (mutation.name == 'archived') {
          expect(current.pinned, isFalse);
          expect(notes.activeNotes, isEmpty);
          expect(notes.archivedNotes.map((note) => note.id), [id]);
        } else {
          expect(notes.activeNotes.map((note) => note.id), [id]);
          expect(notes.archivedNotes, isEmpty);
        }
        expect(mutation.read(_storedNote(prefs, id)!), isTrue);
        expect(persisted, 1);
        expect(notifications, 1);
      },
    );

    for (final throws in [false, true]) {
      test(
        'rejected ${mutation.name} write ($throws) rolls back and permits retry',
        () async {
          final id = '${mutation.name}-rejected-$throws';
          final original = _richNote(
            id,
            pinned: mutation.name == 'pinned',
            archived: mutation.name == 'archived',
          );
          await notes.addOrUpdateNotePersisted(original);
          final prefs = await SharedPreferences.getInstance();
          var persisted = 0;
          var notifications = 0;
          notes.onLocalMutationPersisted = () => persisted++;
          notes.addListener(() => notifications++);
          store.rejectNextNoteWrite(throws: throws);

          await expectLater(
            mutation.set(notes, id, false),
            throwsA(isA<StateError>()),
          );

          expect(notes.notes.single.toJson(), equals(original.toJson()));
          expect(_storedNote(prefs, id)!.toJson(), equals(original.toJson()));
          expect(persisted, 0);
          expect(notifications, 0);

          await mutation.set(notes, id, false);

          final current = notes.notes.single;
          expect(mutation.read(current), isFalse);
          expect(current.pinned, isFalse);
          expect(current.archived, isFalse);
          expect(notes.activeNotes.map((note) => note.id), [id]);
          expect(notes.archivedNotes, isEmpty);
          expect(mutation.read(_storedNote(prefs, id)!), isFalse);
          _expectUnchangedFields(current, original);
          expect(persisted, 1);
          expect(notifications, 1);
        },
      );
    }

    for (final throws in [false, true]) {
      test(
        '${mutation.name} guard false/throw pre-rejects without a write ($throws)',
        () async {
          final id = '${mutation.name}-guard-$throws';
          final original = _richNote(id);
          await notes.addOrUpdateNotePersisted(original);
          final prefs = await SharedPreferences.getInstance();
          final writesBefore = store.noteWrites;
          var persisted = 0;
          notes.onLocalMutationPersisted = () => persisted++;

          bool guard() {
            if (throws) throw StateError('origin is no longer current');
            return false;
          }

          await expectLater(
            mutation.set(notes, id, true, canWrite: guard),
            throwsA(isA<AccountPreferenceWriteCanceled>()),
          );

          expect(store.noteWrites, writesBefore);
          expect(notes.notes.single.toJson(), equals(original.toJson()));
          expect(_storedNote(prefs, id)!.toJson(), equals(original.toJson()));
          expect(persisted, 0);

          await mutation.set(notes, id, true);

          expect(mutation.read(notes.notes.single), isTrue);
          expect(mutation.read(_storedNote(prefs, id)!), isTrue);
          expect(persisted, 1);
        },
      );
    }

    test(
      'held ${mutation.name} guard expiry rolls back and allows the same retry',
      () async {
        final id = '${mutation.name}-guard-expiry';
        final original = _richNote(id);
        await notes.addOrUpdateNotePersisted(original);
        final prefs = await SharedPreferences.getInstance();
        var allowed = true;
        var persisted = 0;
        notes.onLocalMutationPersisted = () => persisted++;
        store.holdNextNotesWrite();

        final saving = mutation.set(notes, id, true, canWrite: () => allowed);
        final rejected = expectLater(
          saving,
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        try {
          await store.noteStarted.future.timeout(const Duration(seconds: 2));
          expect(notes.notes.single.toJson(), equals(original.toJson()));
          allowed = false;
        } finally {
          store.releaseNotesWrite();
        }
        await rejected;

        expect(notes.notes.single.toJson(), equals(original.toJson()));
        expect(_storedNote(prefs, id)!.toJson(), equals(original.toJson()));
        expect(persisted, 0);

        allowed = true;
        await mutation.set(notes, id, true, canWrite: () => allowed);
        expect(mutation.read(notes.notes.single), isTrue);
        expect(mutation.read(_storedNote(prefs, id)!), isTrue);
        expect(persisted, 1);
      },
    );

    test(
      'reset cancels a held ${mutation.name} write and permits a fresh retry',
      () async {
        final id = '${mutation.name}-reset';
        final original = _richNote(id);
        await notes.addOrUpdateNotePersisted(original);
        final prefs = await SharedPreferences.getInstance();
        var persisted = 0;
        notes.onLocalMutationPersisted = () => persisted++;
        store.holdNextNotesWrite();

        final saving = mutation.set(notes, id, true);
        final rejected = expectLater(
          saving,
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        try {
          await store.noteStarted.future.timeout(const Duration(seconds: 2));
          notes.resetLocalState();
        } finally {
          store.releaseNotesWrite();
        }
        await rejected;

        expect(notes.notes, isEmpty);
        expect(_storedNote(prefs, id)!.toJson(), equals(original.toJson()));
        expect(persisted, 0);

        await notes.loadFromStorage();
        await mutation.set(notes, id, true);
        expect(mutation.read(notes.notes.single), isTrue);
        expect(mutation.read(_storedNote(prefs, id)!), isTrue);
        expect(persisted, 1);
      },
    );

    test(
      'account invalidation cancels a held ${mutation.name} write',
      () async {
        final id = '${mutation.name}-account';
        final original = _richNote(id);
        await notes.addOrUpdateNotePersisted(original);
        final prefs = await SharedPreferences.getInstance();
        var persisted = 0;
        notes.onLocalMutationPersisted = () => persisted++;
        store.holdNextNotesWrite();

        final saving = mutation.set(notes, id, true);
        final rejected = expectLater(
          saving,
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        try {
          await store.noteStarted.future.timeout(const Duration(seconds: 2));
          final cleanup = AccountLocalDataCleaner.clearSharedPreferences();
          store.releaseNotesWrite();
          await Future.wait([rejected, cleanup]);
        } finally {
          store.releaseNotesWrite();
        }

        expect(prefs.getStringList(_notesKey), isNull);
        expect(notes.notes.single.toJson(), equals(original.toJson()));
        expect(persisted, 0);

        notes.resetLocalState();
        await notes.addOrUpdateNotePersisted(_richNote('new-account-note'));
        expect(_storedNotes(prefs).map((note) => note.id), [
          'new-account-note',
        ]);
        expect(notes.notes.single.id, 'new-account-note');
        expect(persisted, 1);
      },
    );

    test(
      '${mutation.name} setter for a missing ID does not write or publish',
      () async {
        var persisted = 0;
        var notifications = 0;
        notes.onLocalMutationPersisted = () => persisted++;
        notes.addListener(() => notifications++);

        await mutation.set(notes, 'missing-${mutation.name}', true);

        expect(store.noteWrites, 0);
        expect(notes.notes, isEmpty);
        expect(persisted, 0);
        expect(notifications, 0);
      },
    );
  }

  test(
    'archiving a pinned note clears the pin and restoring keeps it clear',
    () async {
      final id = 'archive-clears-pin';
      final original = _richNote(id, pinned: true);
      await notes.addOrUpdateNotePersisted(original);
      final prefs = await SharedPreferences.getInstance();
      var persisted = 0;
      notes.onLocalMutationPersisted = () => persisted++;

      await notes.setArchivedPersisted(id, true);

      expect(notes.notes.single.pinned, isFalse);
      expect(notes.notes.single.archived, isTrue);
      expect(_storedNote(prefs, id)!.pinned, isFalse);
      expect(_storedNote(prefs, id)!.archived, isTrue);
      expect(notes.activeNotes, isEmpty);
      expect(notes.archivedNotes.map((note) => note.id), [id]);

      await notes.setArchivedPersisted(id, false);

      expect(notes.notes.single.pinned, isFalse);
      expect(notes.notes.single.archived, isFalse);
      expect(_storedNote(prefs, id)!.pinned, isFalse);
      expect(_storedNote(prefs, id)!.archived, isFalse);
      expect(notes.activeNotes.map((note) => note.id), [id]);
      expect(notes.archivedNotes, isEmpty);
      expect(persisted, 2);
    },
  );

  test(
    'cold hydration archives an already archived pinned note and clears its pin',
    () async {
      final id = 'cold-archived-pinned';
      final original = _richNote(id, pinned: true, archived: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_notesKey, [jsonEncode(original.toJson())]);
      final writesBeforeSet = store.noteWrites;
      var persisted = 0;
      notes.onLocalMutationPersisted = () => persisted++;

      await notes.setArchivedPersisted(id, true);

      expect(notes.archivedNotes.single.pinned, isFalse);
      expect(notes.archivedNotes.single.archived, isTrue);
      expect(_storedNote(prefs, id)!.pinned, isFalse);
      expect(_storedNote(prefs, id)!.archived, isTrue);
      expect(store.noteWrites, writesBeforeSet + 1);
      expect(persisted, 1);
    },
  );

  final heldInterleaveCases = <_HeldInterleaveCase>[
    _HeldInterleaveCase(
      name: 'pin false preserves a newer archive value',
      set: _setPinned,
      targetValue: false,
      oldPinned: true,
      oldArchived: false,
      draftPinned: true,
      draftArchived: true,
      expectedPinned: false,
      expectedArchived: true,
    ),
    _HeldInterleaveCase(
      name: 'pin true preserves a newer restore value',
      set: _setPinned,
      targetValue: true,
      oldPinned: false,
      oldArchived: true,
      draftPinned: false,
      draftArchived: false,
      expectedPinned: true,
      expectedArchived: false,
    ),
    _HeldInterleaveCase(
      name: 'archive true clears a newer pin and applies archive',
      set: _setArchived,
      targetValue: true,
      oldPinned: false,
      oldArchived: false,
      draftPinned: true,
      draftArchived: false,
      expectedPinned: false,
      expectedArchived: true,
    ),
    _HeldInterleaveCase(
      name: 'archive false preserves a newer pin value',
      set: _setArchived,
      targetValue: false,
      oldPinned: false,
      oldArchived: true,
      draftPinned: true,
      draftArchived: true,
      expectedPinned: true,
      expectedArchived: false,
    ),
  ];

  for (final scenario in heldInterleaveCases) {
    test(
      'held ${scenario.name} merges only action fields and keeps the latest draft',
      () async {
        final suffix = scenario.name.replaceAll(' ', '-');
        final id = 'interleave-$suffix';
        final original = _richNote(
          id,
          pinned: scenario.oldPinned,
          archived: scenario.oldArchived,
        );
        await notes.addOrUpdateNotePersisted(original);
        final prefs = await SharedPreferences.getInstance();
        final futureUpdatedAt = DateTime.utc(2099, 8, 7, 6, 5);
        final expectedAttachments = const [
          NoteAttachment(
            name: 'new-draft.pdf',
            uri: 'local://new-draft.pdf',
            mimeType: 'application/pdf',
          ),
        ];
        var persisted = 0;
        notes.onLocalMutationPersisted = () => persisted++;
        store.holdNextNotesWrite();

        final action = scenario.set(notes, id, scenario.targetValue);
        await store.noteStarted.future.timeout(const Duration(seconds: 2));
        final draft = _richNote(
          id,
          content: 'newer draft content: ${scenario.name}',
          pinned: scenario.draftPinned,
          archived: scenario.draftArchived,
          attachments: expectedAttachments,
          updatedAt: futureUpdatedAt,
        );
        notes.addOrUpdateNote(draft);
        expect(notes.notes.single.toJson(), equals(draft.toJson()));

        store.releaseNotesWrite();
        await action;
        await AccountPreferenceWrites.drain();

        final current = notes.notes.single;
        final saved = _storedNote(prefs, id)!;
        expect(current.content, draft.content);
        expect(
          current.blocks.map((block) => block.toJson()).toList(),
          draft.blocks.map((block) => block.toJson()).toList(),
        );
        expect(
          current.attachments.map((item) => item.toJson()).toList(),
          expectedAttachments.map((item) => item.toJson()).toList(),
        );
        expect(current.createdAt, draft.createdAt);
        expect(current.pinned, scenario.expectedPinned);
        expect(current.archived, scenario.expectedArchived);
        expect(current.updatedAt, futureUpdatedAt);
        expect(saved.toJson(), equals(current.toJson()));
        expect(persisted, 2); // Acknowledged action and queued legacy save.
      },
    );
  }

  for (final actionOnCommit in ['reset', 'dispose']) {
    test(
      'post-commit $actionOnCommit callback does not publish a second notification',
      () async {
        final id = 'post-commit-$actionOnCommit';
        await notes.addOrUpdateNotePersisted(_richNote(id));
        final prefs = await SharedPreferences.getInstance();
        var persisted = 0;
        var notifications = 0;
        notes.addListener(() => notifications++);
        notes.onLocalMutationPersisted = () {
          persisted++;
          if (actionOnCommit == 'reset') {
            notes.resetLocalState();
          } else {
            notes.dispose();
          }
        };

        await notes.setPinnedPersisted(id, true);

        expect(persisted, 1);
        expect(_storedNote(prefs, id)!.pinned, isTrue);
        if (actionOnCommit == 'reset') {
          expect(notes.notes, isEmpty);
          // resetLocalState is the only notification; committed publication
          // observes the changed generation and does not notify again.
          expect(notifications, 1);
        } else {
          expect(notifications, 0);
          // The provider was disposed from its callback; give tearDown a fresh
          // instance so it can dispose the provider it owns exactly once.
          notes = NoteProvider();
        }
      },
    );
  }

  test(
    'queued flag changes use the latest same-ID note and preserve a newer draft',
    () async {
      final id = 'queued-note';
      final original = _richNote(id);
      await notes.addOrUpdateNotePersisted(original);
      final prefs = await SharedPreferences.getInstance();
      var persisted = 0;
      notes.onLocalMutationPersisted = () => persisted++;
      store.holdNextNotesWrite();

      final pinning = notes.setPinnedPersisted(id, true);
      await store.noteStarted.future.timeout(const Duration(seconds: 2));
      final latestDraft = _richNote(
        id,
        content: 'newer queued editor draft',
        pinned: true,
        blocks: const [
          NoteBlock(
            id: 'draft-block',
            type: NoteBlockType.checklist,
            text: 'keep this block',
            checked: true,
          ),
        ],
        attachments: const [
          NoteAttachment(name: 'draft.png', uri: 'local://draft.png'),
        ],
      );
      notes.addOrUpdateNote(latestDraft);
      final archiving = notes.setArchivedPersisted(id, true);
      expect(notes.notes.single.toJson(), equals(latestDraft.toJson()));
      expect(persisted, 0);

      store.releaseNotesWrite();
      await Future.wait([pinning, archiving]);
      await AccountPreferenceWrites.drain();

      final current = notes.notes.single;
      final saved = _storedNote(prefs, id)!;
      expect(current.content, 'newer queued editor draft');
      expect(current.pinned, isFalse);
      expect(current.archived, isTrue);
      expect(current.format, latestDraft.format);
      expect(
        current.blocks.map((block) => block.toJson()).toList(),
        latestDraft.blocks.map((block) => block.toJson()).toList(),
      );
      expect(
        current.attachments.map((item) => item.toJson()).toList(),
        latestDraft.attachments.map((item) => item.toJson()).toList(),
      );
      expect(current.createdAt, latestDraft.createdAt);
      expect(notes.activeNotes, isEmpty);
      expect(notes.archivedNotes.map((note) => note.id), [id]);
      expect(saved.toJson(), equals(current.toJson()));
      expect(persisted, 3); // Pin commit, legacy draft save, archive commit.
    },
  );
}

NoteItem _richNote(
  String id, {
  String? content,
  bool pinned = false,
  bool archived = false,
  List<NoteBlock>? blocks,
  List<NoteAttachment>? attachments,
  DateTime? updatedAt,
}) {
  final actualContent = content ?? 'original content for $id';
  return NoteItem(
    id: id,
    content: actualContent,
    format: 'rich-text',
    blocks:
        blocks ??
        [NoteBlock(id: 'body', type: NoteBlockType.code, text: actualContent)],
    attachments:
        attachments ??
        const [
          NoteAttachment(
            name: 'receipt.jpg',
            uri: 'local://receipt.jpg',
            mimeType: 'image/jpeg',
          ),
        ],
    pinned: pinned,
    archived: archived,
    createdAt: DateTime.utc(2001, 2, 3, 4, 5),
    updatedAt: updatedAt ?? DateTime.utc(2002, 3, 4, 5, 6),
  );
}

void _expectUnchangedFields(NoteItem actual, NoteItem original) {
  expect(actual.content, original.content);
  expect(actual.format, original.format);
  expect(
    actual.blocks.map((block) => block.toJson()).toList(),
    equals(original.blocks.map((block) => block.toJson()).toList()),
  );
  expect(
    actual.attachments.map((attachment) => attachment.toJson()).toList(),
    equals(
      original.attachments.map((attachment) => attachment.toJson()).toList(),
    ),
  );
  expect(actual.createdAt, original.createdAt);
}

List<NoteItem> _storedNotes(SharedPreferences prefs) =>
    (prefs.getStringList(_notesKey) ?? [])
        .map(
          (raw) => NoteItem.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        )
        .toList();

NoteItem? _storedNote(SharedPreferences prefs, String id) {
  for (final note in _storedNotes(prefs)) {
    if (note.id == id) return note;
  }
  return null;
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData(<String, Object>{});

  int noteWrites = 0;
  bool _holdNextNote = false;
  bool _rejectNextNote = false;
  bool _throwOnRejection = false;
  Completer<void>? _noteStarted;
  Completer<void>? _noteRelease;

  Completer<void> get noteStarted => _noteStarted!;

  void holdNextNotesWrite() {
    _holdNextNote = true;
    _noteStarted = Completer<void>();
    _noteRelease = Completer<void>();
  }

  void releaseNotesWrite() {
    final release = _noteRelease;
    if (release != null && !release.isCompleted) release.complete();
  }

  void releaseAll() => releaseNotesWrite();

  void rejectNextNoteWrite({required bool throws}) {
    _rejectNextNote = true;
    _throwOnRejection = throws;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != _platformNotesKey) return super.setValue(type, key, value);
    noteWrites++;
    if (_holdNextNote) {
      _holdNextNote = false;
      _noteStarted!.complete();
      await _noteRelease!.future;
    }

    // Apply first so the transaction test also checks restoration after a
    // platform that changes storage before returning false or throwing.
    final saved = await super.setValue(type, key, value);
    if (_rejectNextNote) {
      _rejectNextNote = false;
      if (_throwOnRejection) throw StateError('injected note write failure');
      return false;
    }
    return saved;
  }
}
