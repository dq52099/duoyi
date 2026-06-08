import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quick_capture_template.dart';
import 'cloud_sync_provider.dart';

class QuickCaptureTemplateProvider extends ChangeNotifier {
  static const _storageKey = 'duoyi_quick_capture_templates_v1';

  final List<QuickCaptureTemplate> _customTemplates = [];
  int _storageGeneration = 0;

  List<QuickCaptureTemplate> get customTemplates =>
      List.unmodifiable(_customTemplates);

  List<QuickCaptureTemplate> get templates => List.unmodifiable([
    ...QuickCaptureTemplate.builtIns(),
    ..._customTemplates,
  ]);

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    final raw = prefs.getString(_storageKey);
    _customTemplates
      ..clear()
      ..addAll(_decode(raw));
    notifyListeners();
  }

  void resetLocalState() {
    _storageGeneration++;
    _customTemplates.clear();
    notifyListeners();
  }

  Future<void> saveTemplate(QuickCaptureTemplate template) async {
    final custom = template.copyWith(builtIn: false);
    final index = _customTemplates.indexWhere((item) => item.id == custom.id);
    if (index == -1) {
      _customTemplates.add(custom);
    } else {
      _customTemplates[index] = custom;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> deleteTemplate(String id) async {
    await CloudSyncProvider.recordDeletedItem('quick_capture_templates', id);
    _customTemplates.removeWhere((item) => item.id == id && !item.builtIn);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      json.encode(_customTemplates.map((item) => item.toJson()).toList()),
    );
  }

  List<QuickCaptureTemplate> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) {
            return QuickCaptureTemplate.fromJson(
              Map<String, dynamic>.from(item),
            );
          })
          .where((item) => !item.builtIn)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
