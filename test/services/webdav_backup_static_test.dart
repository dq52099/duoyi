import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Backup service covers local calendar events and rollback clearing', () {
    final service = File('lib/services/backup_service.dart').readAsStringSync();

    expect(service, contains("'duoyi_local_calendar_events_v1'"));
    expect(service, contains('bool clearMissing = false'));
    expect(service, contains('if (clearMissing && !merge)'));
    expect(service, contains('if (!data.containsKey(key))'));
    expect(service, contains('await p.remove(key)'));
  });

  test('WebDAV backup service supports upload and restore primitives', () {
    final service = File(
      'lib/services/webdav_backup_service.dart',
    ).readAsStringSync();

    expect(service, contains('class WebDavBackupConfig'));
    expect(service, contains('webdav_backup_base_url'));
    expect(service, contains('webdav_backup_username'));
    expect(service, contains('webdav_backup_password'));
    expect(service, contains('webdav_backup_remote_path'));
    expect(service, contains('webdav_backup_filename'));
    expect(service, contains('BackupService.exportAll()'));
    expect(service, contains("http.Request('MKCOL'"));
    expect(service, contains('_client.put'));
    expect(service, contains('_client.get'));
    expect(service, contains('downloadLatestBackup'));
    expect(service, contains('authorization'));
  });

  test('Backup screen exposes WebDAV cloud backup actions', () {
    final screen = File('lib/screens/backup_screen.dart').readAsStringSync();

    expect(
      screen,
      contains("import '../services/webdav_backup_service.dart';"),
    );
    expect(screen, contains('WebDavBackupConfig _webDavConfig'));
    expect(screen, contains('Future<void> _configureWebDavBackup()'));
    expect(screen, contains('Future<void> _uploadWebDavBackup()'));
    expect(screen, contains('Future<void> _restoreFromWebDav'));
    expect(screen, contains('WebDAV 云盘备份'));
    expect(screen, contains('上传备份'));
    expect(screen, contains('云端合并'));
    expect(screen, contains('云端覆盖'));
    expect(screen, contains('BackupService.importAll(raw, merge: merge)'));
    expect(screen, contains('await _reloadAll()'));
  });

  test('Backup screen can restore and migrate from local files', () {
    final screen = File('lib/screens/backup_screen.dart').readAsStringSync();

    expect(screen, contains("package:file_selector/file_selector.dart"));
    expect(screen, contains('Future<String?> _pickImportTextFile()'));
    expect(screen, contains('XTypeGroup('));
    expect(screen, contains("extensions: ['json', 'csv', 'txt']"));
    expect(screen, contains('file?.readAsString()'));
    expect(screen, contains('Future<void> _importBackupFile'));
    expect(screen, contains('BackupService.importAll(raw, merge: merge)'));
    expect(screen, contains('文件合并'));
    expect(screen, contains('文件覆盖'));
    expect(screen, contains('从文件导入其他 App 数据'));
  });

  test('Parity docs mark cloud-drive backup as implemented with WebDAV', () {
    final competitive = File('docs/competitive-analysis.md').readAsStringSync();
    final audit = File('docs/zhijian-time-parity-audit.md').readAsStringSync();

    expect(competitive, contains('WebDAV 云盘备份'));
    expect(competitive, contains('OpenList、坚果云、NAS'));
    expect(audit, contains('WebDAV 云盘备份'));
    expect(audit, contains('test/services/webdav_backup_static_test.dart'));
  });
}
