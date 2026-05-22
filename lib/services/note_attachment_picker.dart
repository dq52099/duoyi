import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';

import '../models/note.dart';

class NoteAttachmentPicker {
  NoteAttachmentPicker._();

  static const MethodChannel _channel = MethodChannel(
    'duoyi/note_attachment_picker',
  );

  static Future<NoteAttachment?> pickFile() async {
    if (!_isAndroid) return _pickPortableFile();
    return _pickAndroidFile();
  }

  static Future<NoteAttachment?> _pickAndroidFile() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'pickFile',
      );
      if (result == null) return null;
      final uri = result['uri']?.toString() ?? '';
      if (uri.isEmpty) return null;
      final name = result['name']?.toString();
      return NoteAttachment(
        name: name == null || name.trim().isEmpty ? '附件' : name.trim(),
        uri: uri,
        mimeType: result['mimeType']?.toString() ?? '',
      );
    } catch (e, st) {
      debugPrint('[NoteAttachmentPicker] pickFile failed: $e\n$st');
      return null;
    }
  }

  static Future<NoteAttachment?> _pickPortableFile() async {
    if (kIsWeb) return null;
    try {
      final file = await openFile();
      if (file == null) return null;
      final uri = file.path.trim();
      if (uri.isEmpty) return null;
      final name = file.name.trim().isEmpty ? '附件' : file.name.trim();
      return NoteAttachment(
        name: name,
        uri: uri,
        mimeType: file.mimeType ?? '',
      );
    } catch (e, st) {
      debugPrint('[NoteAttachmentPicker] portable pickFile failed: $e\n$st');
      return null;
    }
  }

  static bool get _isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }
}
