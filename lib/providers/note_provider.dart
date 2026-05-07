import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';

class NoteProvider extends ChangeNotifier {
  static const _key = 'duoyi_notes';
  List<NoteItem> _notes = [];

  List<NoteItem> get notes => List.unmodifiable(
    _notes..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
  );

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_key) ?? [];
    _notes = data.map((e) => NoteItem.fromJson(jsonDecode(e))).toList();
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

  void deleteNote(String id) {
    _notes.removeWhere((e) => e.id == id);
    _save();
  }
}
