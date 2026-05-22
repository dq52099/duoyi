import 'dart:convert';

import 'package:duoyi/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('exports local calendar events in full backups', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('duoyi_local_calendar_events_v1', <String>[
      '{"id":"event-1","title":"Imported event"}',
    ]);

    final raw = await BackupService.exportAll();
    final backup = json.decode(raw) as Map<String, dynamic>;
    final data = backup['data'] as Map<String, dynamic>;

    expect(data, contains('duoyi_local_calendar_events_v1'));
    expect(data['duoyi_local_calendar_events_v1'], <String, Object>{
      'type': 'stringList',
      'value': <String>['{"id":"event-1","title":"Imported event"}'],
    });
  });

  test('clearMissing rollback removes keys absent from the snapshot', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('todos', <String>['before']);
    final snapshot = await BackupService.exportAll();

    await prefs.setStringList('duoyi_notes', <String>['imported note']);
    await prefs.setStringList('duoyi_local_calendar_events_v1', <String>[
      'imported event',
    ]);

    await BackupService.importAll(snapshot, merge: false, clearMissing: true);

    expect(prefs.getStringList('todos'), <String>['before']);
    expect(prefs.getStringList('duoyi_notes'), isNull);
    expect(prefs.getStringList('duoyi_local_calendar_events_v1'), isNull);
  });

  test('normal overwrite keeps keys absent from the backup', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('todos', <String>['before']);
    final snapshot = await BackupService.exportAll();

    await prefs.setStringList('duoyi_notes', <String>['keep me']);

    await BackupService.importAll(snapshot, merge: false);

    expect(prefs.getStringList('todos'), <String>['before']);
    expect(prefs.getStringList('duoyi_notes'), <String>['keep me']);
  });
}
