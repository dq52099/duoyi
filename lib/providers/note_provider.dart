import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../core/account_preference_writes.dart';
import '../services/account_local_data_cleaner.dart';
import 'cloud_sync_provider.dart';

class NoteProvider extends ChangeNotifier {
  static const _key = 'duoyi_notes';
  List<NoteItem> _notes = [];
  int _storageGeneration = 0;
  bool _storageLoaded = false;
  bool _disposed = false;
  Future<void> _storageTail = Future<void>.value();
  VoidCallback? onLocalMutationPersisted;

  int get storageGeneration => _storageGeneration;

  List<NoteItem> get notes => _sorted(_notes);

  List<NoteItem> get activeNotes =>
      _sorted(_notes.where((note) => !note.archived));

  List<NoteItem> get archivedNotes =>
      _sorted(_notes.where((note) => note.archived));

  Future<void> loadFromStorage() => _enqueueStorage((token, isCurrent) async {
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(token, isCurrent);
    _notes = _decodeStoredNotes(prefs);
    _storageLoaded = true;
    notifyListeners();
  });

  void resetLocalState() {
    _storageGeneration++;
    _storageLoaded = false;
    _notes = [];
    if (!_disposed) notifyListeners();
  }

  /// Acknowledges persistence before publishing the imported note.
  /// The origin is captured before queueing, including during cold hydration.
  Future<void> addOrUpdateNotePersisted(
    NoteItem note, {
    bool Function()? canWrite,
  }) => _enqueueStorage((token, isCurrent) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(token, isCurrent);
    _hydrateBeforeWrite(prefs);
    final previous = _notes.where((item) => item.id == note.id).firstOrNull;
    final snapshot = List<NoteItem>.of(_notes);
    _replaceNote(snapshot, note);
    await _persistSnapshot(
      prefs,
      snapshot,
      token,
      isCurrent,
      onCommitted: () {
        // A queued legacy draft owns any newer version of this ID.
        final current = _notes.where((item) => item.id == note.id).firstOrNull;
        if (identical(current, previous)) _replaceNote(_notes, note);
      },
    );
    _publishCommittedMutation(token, generation, accountGeneration);
  }, canWrite: canWrite);

  /// Sets an explicit pin value using the latest queued note state.
  Future<void> setPinnedPersisted(
    String id,
    bool pinned, {
    bool Function()? canWrite,
  }) => _setManagementPersisted(id, pinned: pinned, canWrite: canWrite);

  /// Archives or restores a note in one acknowledged snapshot. Archiving clears pinning.
  Future<void> setArchivedPersisted(
    String id,
    bool archived, {
    bool Function()? canWrite,
  }) => _setManagementPersisted(id, archived: archived, canWrite: canWrite);

  Future<void> _setManagementPersisted(
    String id, {
    bool? pinned,
    bool? archived,
    bool Function()? canWrite,
  }) => _enqueueStorage((token, isCurrent) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(token, isCurrent);
    _hydrateBeforeWrite(prefs);
    final previous = _notes.where((note) => note.id == id).firstOrNull;
    if (previous == null) return;
    final nextPinned = pinned ?? (archived == true ? false : previous.pinned);
    final nextArchived = archived ?? previous.archived;
    if (previous.pinned == nextPinned && previous.archived == nextArchived) {
      return;
    }
    final now = DateTime.now();
    final updated = previous.copyWith(
      pinned: nextPinned,
      archived: nextArchived,
      updatedAt: previous.updatedAt.isAfter(now) ? previous.updatedAt : now,
    );
    final snapshot = List<NoteItem>.of(_notes);
    _replaceNote(snapshot, updated);
    await _persistSnapshot(
      prefs,
      snapshot,
      token,
      isCurrent,
      onCommitted: () {
        // Merge only this action's fields into a newer draft. Its queued save
        // keeps the latest content and unrelated management state.
        final current = _notes.where((note) => note.id == id).firstOrNull;
        if (current != null) {
          _replaceNote(
            _notes,
            current.copyWith(
              pinned: pinned ?? (archived == true ? false : current.pinned),
              archived: archived ?? current.archived,
              updatedAt: current.updatedAt.isAfter(updated.updatedAt)
                  ? current.updatedAt
                  : updated.updatedAt,
            ),
          );
        }
      },
    );
    _publishCommittedMutation(token, generation, accountGeneration);
  }, canWrite: canWrite);

  /// The note and its sync deletion record commit or roll back together.
  Future<void> deleteNotePersisted(
    String id, {
    bool Function()? canWrite,
  }) => _enqueueStorage((token, isCurrent) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(token, isCurrent);
    _hydrateBeforeWrite(prefs);
    final previous = _notes.where((note) => note.id == id).firstOrNull;
    if (previous == null) return;
    final snapshot = List<NoteItem>.of(_notes)
      ..removeWhere((note) => note.id == id);
    var committed = false;
    try {
      await CloudSyncProvider.withDeletedItemsLock<void>((lease) async {
        await _persistSnapshot(
          prefs,
          snapshot,
          token,
          isCurrent,
          deletedId: id,
          lease: lease,
          onCommitted: () {
            committed = true;
            // A confirmed deletion also wins over an optimistic legacy draft
            // changed while its write was held. Its queued save reads this
            // committed state, keeping note data and tombstones consistent.
            _notes.removeWhere((note) => note.id == id);
          },
        );
      });
    } on AccountPreferenceWriteCanceled {
      // A lease revoked after commit cannot turn an acknowledged delete into
      // a rejected operation. UI feedback has its own origin check.
      if (!committed) rethrow;
    }
    _publishCommittedMutation(token, generation, accountGeneration);
  }, canWrite: canWrite);

  Future<T> _enqueueStorage<T>(
    Future<T> Function(AccountPreferenceWriteToken, bool Function())
    operation, {
    bool Function()? canWrite,
  }) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final preceding = _storageTail;
    final result = AccountPreferenceWrites.runResult<T>((token) async {
      bool isCurrent() {
        try {
          return !_disposed &&
              generation == _storageGeneration &&
              AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                accountGeneration,
              ) &&
              (canWrite?.call() ?? true);
        } catch (_) {
          return false;
        }
      }

      await preceding;
      _ensureCurrent(token, isCurrent);
      return operation(token, isCurrent);
    }, canceledResult: () => throw const AccountPreferenceWriteCanceled());
    // Failure releases the queue but is still returned to the initiating UI.
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _ensureCurrent(
    AccountPreferenceWriteToken token,
    bool Function() isCurrent,
  ) {
    token.ensureCurrent();
    if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
  }

  List<NoteItem> _decodeStoredNotes(SharedPreferences prefs) =>
      (prefs.getStringList(_key) ?? [])
          .map((raw) => NoteItem.fromJson(jsonDecode(raw)))
          .toList();

  void _hydrateBeforeWrite(SharedPreferences prefs) {
    if (_storageLoaded) return;
    final loaded = _decodeStoredNotes(prefs);
    for (final draft in _notes) {
      _replaceNote(loaded, draft);
    }
    _notes = loaded;
    _storageLoaded = true;
  }

  static void _replaceNote(List<NoteItem> notes, NoteItem note) {
    final index = notes.indexWhere((item) => item.id == note.id);
    if (index < 0) {
      notes.add(note);
    } else {
      notes[index] = note;
    }
  }

  Future<void> _save() => _enqueueStorage((token, isCurrent) async {
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(token, isCurrent);
    _hydrateBeforeWrite(prefs);
    await _persistSnapshot(prefs, List.of(_notes), token, isCurrent);
    _ensureCurrent(token, isCurrent);
    _notifyLocalMutationPersisted();
    notifyListeners();
  });

  Future<void> _persistSnapshot(
    SharedPreferences prefs,
    List<NoteItem> snapshot,
    AccountPreferenceWriteToken token,
    bool Function() isCurrent, {
    String? deletedId,
    DeletedItemsWriteLease? lease,
    VoidCallback? onCommitted,
  }) async {
    final data = snapshot.length >= _isolateEncodeMinItems
        ? await compute(_encodeNoteStoragePayload, snapshot)
        : _encodeNoteStoragePayload(snapshot);
    _ensureCurrent(token, isCurrent);
    final transaction = AccountPreferenceTransaction(
      prefs,
      () => token.isCurrent && isCurrent(),
    );
    try {
      await transaction.setStringList(_key, data);
      if (deletedId != null) {
        await CloudSyncProvider.recordDeletedItem(
          'notes',
          deletedId,
          transaction: transaction,
          lease: lease,
        );
      }
      transaction.commit();
      onCommitted?.call();
    } catch (_) {
      // Account cleanup drains this tracked operation before removing keys.
      await transaction.rollback(canceledBeforeCleanup: true);
      rethrow;
    }
  }

  void _publishCommittedMutation(
    AccountPreferenceWriteToken token,
    int generation,
    int accountGeneration,
  ) {
    bool ownsStorage() =>
        !_disposed &&
        token.isCurrent &&
        _storageGeneration == generation &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
    if (!ownsStorage()) {
      return;
    }
    _notifyLocalMutationPersisted();
    if (ownsStorage()) {
      notifyListeners();
    }
  }

  void _saveLegacyDraft() {
    unawaited(
      _save().catchError((Object error, StackTrace stack) {
        if (error is! AccountPreferenceWriteCanceled) {
          debugPrint('[NoteProvider] draft persistence failed: $error\n$stack');
        }
      }),
    );
  }

  void _notifyLocalMutationPersisted() {
    try {
      onLocalMutationPersisted?.call();
    } catch (e, st) {
      debugPrint('[NoteProvider] local mutation callback failed: $e\n$st');
    }
  }

  void addOrUpdateNote(NoteItem note) {
    final idx = _notes.indexWhere((e) => e.id == note.id);
    if (idx != -1) {
      _notes[idx] = note;
    } else {
      _notes.add(note);
    }
    _saveLegacyDraft();
  }

  void togglePinned(String id) {
    final idx = _notes.indexWhere((note) => note.id == id);
    if (idx < 0) return;
    final note = _notes[idx];
    _notes[idx] = note.copyWith(
      pinned: !note.pinned,
      updatedAt: DateTime.now(),
    );
    _saveLegacyDraft();
  }

  void setArchived(String id, bool archived) {
    final idx = _notes.indexWhere((note) => note.id == id);
    if (idx < 0) return;
    final note = _notes[idx];
    _notes[idx] = note.copyWith(
      archived: archived,
      pinned: archived ? false : note.pinned,
      updatedAt: DateTime.now(),
    );
    _saveLegacyDraft();
  }

  Future<NoteImportSummary> importNotes(Iterable<NoteItem> notes) async {
    var inserted = 0;
    var skippedDuplicates = 0;
    final existing = _notes
        .map((note) => note.content.trim().toLowerCase())
        .where((content) => content.isNotEmpty)
        .toSet();
    for (final note in notes) {
      final key = note.content.trim().toLowerCase();
      if (key.isEmpty || existing.contains(key)) {
        skippedDuplicates++;
        continue;
      }
      _notes.add(note);
      existing.add(key);
      inserted++;
    }
    if (inserted > 0) await _save();
    return NoteImportSummary(
      inserted: inserted,
      skippedDuplicates: skippedDuplicates,
    );
  }

  Future<void> deleteNote(String id) async {
    await CloudSyncProvider.recordDeletedItem('notes', id);
    _notes.removeWhere((e) => e.id == id);
    await _save();
  }

  @override
  void dispose() {
    _disposed = true;
    _storageGeneration++;
    super.dispose();
  }

  List<NoteItem> _sorted(Iterable<NoteItem> source) {
    final result = source.toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return List.unmodifiable(result);
  }
}

class NoteImportSummary {
  final int inserted;
  final int skippedDuplicates;

  const NoteImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
  });
}

/// 单文件本地持久化的 JSON 编码条数阈值：超过后挪到后台 isolate 编码。
const int _isolateEncodeMinItems = 500;

List<String> _encodeNoteStoragePayload(List<NoteItem> notes) =>
    notes.map((e) => jsonEncode(e.toJson())).toList();
