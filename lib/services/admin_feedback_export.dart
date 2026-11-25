import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'admin_api.dart';

/// A file allocated exclusively for one Feedback export.
class AdminFeedbackExportFile {
  const AdminFeedbackExportFile({required this.path, required this.directory});

  final String path;
  final String directory;
}

/// Operation-local effects keep each asynchronous boundary independently owned.
abstract class AdminFeedbackExportEffects {
  Future<String> temporaryDirectory();
  Future<AdminFeedbackExportFile> allocate(String temporaryDirectory);
  Future<void> write(AdminFeedbackExportFile file, String csv);
  Future<void> copyPath(String path);
  Future<void> share(AdminFeedbackExportFile file, String text, String subject);
  Future<void> cleanup(AdminFeedbackExportFile file);
}

class PlatformAdminFeedbackExportEffects implements AdminFeedbackExportEffects {
  const PlatformAdminFeedbackExportEffects();

  @override
  Future<String> temporaryDirectory() async =>
      (await getTemporaryDirectory()).path;

  @override
  Future<AdminFeedbackExportFile> allocate(String temporaryDirectory) async {
    final directory = await Directory(
      temporaryDirectory,
    ).createTemp('duoyi_feedback_');
    return AdminFeedbackExportFile(
      directory: directory.path,
      path:
          '${directory.path}/duoyi_feedback_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
  }

  @override
  Future<void> write(AdminFeedbackExportFile file, String csv) async {
    await File(file.path).writeAsString(csv, flush: true);
  }

  @override
  Future<void> copyPath(String path) =>
      Clipboard.setData(ClipboardData(text: path));

  @override
  Future<void> share(
    AdminFeedbackExportFile file,
    String text,
    String subject,
  ) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text, subject: subject),
    );
  }

  @override
  Future<void> cleanup(AdminFeedbackExportFile file) async {
    final ownedFile = File(file.path);
    if (await ownedFile.exists()) await ownedFile.delete();
    final ownedDirectory = Directory(file.directory);
    // Never recursively delete another export or a shared temporary directory.
    if (await ownedDirectory.exists()) await ownedDirectory.delete();
  }
}

/// Stops later effects after expiry; already-started clipboard/share calls
/// cannot be retracted. A shared file remains available to the system reader.
Future<String> exportAdminFeedbackCsv({
  required String csv,
  required bool Function() isCurrent,
  required AdminFeedbackExportEffects effects,
  required String Function() shareText,
  required String Function() shareSubject,
}) async {
  AdminFeedbackExportFile? owned;
  var handedOff = false;
  void requireCurrent() {
    if (!isCurrent()) throw const AdminActionExpired();
  }

  try {
    requireCurrent();
    final directory = await effects.temporaryDirectory();
    requireCurrent();
    // Retain ownership before checking an allocation which completed late.
    owned = await effects.allocate(directory);
    requireCurrent();
    await effects.write(owned, csv);
    requireCurrent();
    await effects.copyPath(owned.path);
    requireCurrent();
    final text = shareText();
    final subject = shareSubject();
    requireCurrent();
    handedOff = true;
    await effects.share(owned, text, subject);
    requireCurrent();
    return owned.path;
  } catch (_) {
    requireCurrent();
    rethrow;
  } finally {
    // Await write/copy settlement first. Never delete a file handed to SharePlus.
    if (owned != null && !handedOff) {
      try {
        await effects.cleanup(owned);
      } catch (error) {
        debugPrint('[AdminFeedbackExport] owned file cleanup failed: $error');
      }
    }
  }
}
