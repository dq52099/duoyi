import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/focus_sound_service.dart';

class CustomFocusSound {
  final String id;
  final String label;
  final String path;
  final DateTime importedAt;

  const CustomFocusSound({
    required this.id,
    required this.label,
    required this.path,
    required this.importedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'path': path,
    'importedAt': importedAt.toIso8601String(),
  };

  factory CustomFocusSound.fromJson(Map<String, dynamic> json) {
    return CustomFocusSound(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '自定义音频',
      path: json['path']?.toString() ?? '',
      importedAt:
          DateTime.tryParse(json['importedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class CustomFocusSoundProvider extends ChangeNotifier {
  static const storageKey = 'duoyi_custom_focus_sounds';
  static const idPrefix = 'custom:';

  final List<CustomFocusSound> _sounds = [];
  int _storageGeneration = 0;

  List<CustomFocusSound> get sounds =>
      List<CustomFocusSound>.unmodifiable(_sounds);

  bool isCustomSound(String id) => id.startsWith(idPrefix);

  String labelFor(String id) {
    for (final sound in _sounds) {
      if (sound.id == id) return sound.label;
    }
    return '自定义音频';
  }

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    final raw = prefs.getStringList(storageKey) ?? const <String>[];
    _sounds
      ..clear()
      ..addAll(
        raw
            .map((item) {
              try {
                return CustomFocusSound.fromJson(
                  jsonDecode(item) as Map<String, dynamic>,
                );
              } catch (_) {
                return null;
              }
            })
            .whereType<CustomFocusSound>()
            .where((sound) => sound.id.isNotEmpty && sound.path.isNotEmpty),
      );
    _registerWithPlaybackService();
    notifyListeners();
  }

  void resetLocalState() {
    _storageGeneration++;
    _sounds.clear();
    _registerWithPlaybackService();
    notifyListeners();
  }

  Future<CustomFocusSound?> importAudio() async {
    if (kIsWeb) return null;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Audio',
          extensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
          mimeTypes: ['audio/mpeg', 'audio/mp4', 'audio/wav', 'audio/aac'],
        ),
      ],
    );
    if (file == null) return null;
    final sourcePath = file.path;
    if (sourcePath.isEmpty) return null;

    final source = File(sourcePath);
    if (!await source.exists()) return null;
    final dir = await _customSoundDirectory();
    final extension = _extensionFor(sourcePath);
    final id = '$idPrefix${DateTime.now().microsecondsSinceEpoch}';
    final target = File('${dir.path}/${id.replaceAll(':', '_')}.$extension');
    await source.copy(target.path);

    final label = _labelFor(file.name);
    final sound = CustomFocusSound(
      id: id,
      label: label,
      path: target.path,
      importedAt: DateTime.now(),
    );
    _sounds.insert(0, sound);
    await _save();
    _registerWithPlaybackService();
    notifyListeners();
    return sound;
  }

  Future<void> remove(String id) async {
    final idx = _sounds.indexWhere((sound) => sound.id == id);
    if (idx < 0) return;
    final removed = _sounds.removeAt(idx);
    final file = File(removed.path);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // Keep metadata removal even if the OS refuses file deletion.
      }
    }
    await _save();
    _registerWithPlaybackService();
    notifyListeners();
  }

  Future<Directory> _customSoundDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/custom_focus_sounds');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      storageKey,
      _sounds.map((sound) => jsonEncode(sound.toJson())).toList(),
    );
  }

  void _registerWithPlaybackService() {
    FocusSoundService.instance.registerCustomTracks({
      for (final sound in _sounds)
        if (File(sound.path).existsSync()) sound.id: sound.path,
    });
  }

  String _extensionFor(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'mp3';
    final ext = name.substring(dot + 1).toLowerCase();
    return ext.isEmpty ? 'mp3' : ext;
  }

  String _labelFor(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final clean = base.trim();
    return clean.isEmpty ? '自定义音频' : clean;
  }
}
