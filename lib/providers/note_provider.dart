import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import 'cloud_sync_provider.dart';

class NoteProvider extends ChangeNotifier {
  static const _key = 'duoyi_notes';
  List<NoteItem> _notes = [];
  int _storageGeneration = 0;

  List<NoteItem> get notes => _sorted(_notes);

  List<NoteItem> get activeNotes =>
      _sorted(_notes.where((note) => !note.archived));

  List<NoteItem> get archivedNotes =>
      _sorted(_notes.where((note) => note.archived));

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    final data = prefs.getStringList(_key) ?? [];
    _notes = data.map((e) => NoteItem.fromJson(jsonDecode(e))).toList();
    notifyListeners();
  }

  void resetLocalState() {
    _storageGeneration++;
    _notes = [];
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _notes.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_key, data);
    notifyListeners();
  }

  void addOrUpdateNote(NoteItem note) {
    final idx = _notes.indexWhere((e) => e.id == note.id);
    if (idx != -1) {
      _notes[idx] = note;
    } else {
      _notes.add(note);
    }
    _save();
  }

  void togglePinned(String id) {
    final idx = _notes.indexWhere((note) => note.id == id);
    if (idx < 0) return;
    final note = _notes[idx];
    _notes[idx] = note.copyWith(
      pinned: !note.pinned,
      updatedAt: DateTime.now(),
    );
    _save();
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
    _save();
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
