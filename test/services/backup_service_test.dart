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

  test('backup export and import keep countdown records', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('duoyi_countdowns', <String>[
      '{"id":"legacy-countdown","title":"Legacy"}',
    ]);
    await prefs.setStringList('duoyi_anniversaries_v2', <String>[
      '{"id":"normal-anniversary","title":"Normal","originDate":"2026-09-01T00:00:00.000","type":0}',
      '{"id":"birthday-anniversary","title":"Birthday","originDate":"2026-09-02T00:00:00.000","type":1}',
    ]);

    final raw = await BackupService.exportAll();
    final backup = json.decode(raw) as Map<String, dynamic>;
    final data = backup['data'] as Map<String, dynamic>;
    expect(data['duoyi_countdowns'], <String, Object>{
      'type': 'stringList',
      'value': <String>['{"id":"legacy-countdown","title":"Legacy"}'],
    });
    expect(data['duoyi_anniversaries_v2']['value'], <String>[
      '{"id":"normal-anniversary","title":"Normal","originDate":"2026-09-01T00:00:00.000","type":0}',
      '{"id":"birthday-anniversary","title":"Birthday","originDate":"2026-09-02T00:00:00.000","type":1}',
    ]);

    const incoming = '''
{
  "app": "duoyi",
  "schema": 1,
  "data": {
    "duoyi_countdowns": {
      "type": "stringList",
      "value": ["{\\"id\\":\\"imported-countdown\\",\\"title\\":\\"Blocked\\"}"]
    },
    "duoyi_anniversaries_v2": {
      "type": "stringList",
      "value": [
        "{\\"id\\":\\"imported-legacy\\",\\"title\\":\\"Legacy anniversary countdown\\",\\"originDate\\":\\"2026-09-03T00:00:00.000\\",\\"type\\":0}"
      ]
    }
  }
}
''';

    await prefs.remove('duoyi_countdowns');
    await prefs.remove('duoyi_anniversaries_v2');
    final count = await BackupService.importAll(incoming);
    expect(count, 2);
    expect(prefs.getStringList('duoyi_countdowns'), [
      '{"id":"imported-countdown","title":"Blocked"}',
    ]);
    expect(prefs.getStringList('duoyi_anniversaries_v2'), [
      '{"id":"imported-legacy","title":"Legacy anniversary countdown","originDate":"2026-09-03T00:00:00.000","type":0}',
    ]);
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

  test(
    'merge import replaces same-id records instead of duplicating them',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('todos', <String>[
        '{"id":"todo-1","title":"old","updatedAt":"2026-05-26T08:00:00Z"}',
        '{"id":"todo-2","title":"stay","updatedAt":"2026-05-26T09:00:00Z"}',
      ]);

      const incoming = '''
{
  "app": "duoyi",
  "schema": 1,
  "data": {
    "todos": {
      "type": "stringList",
      "value": [
        "{\\"id\\":\\"todo-1\\",\\"title\\":\\"new\\",\\"updatedAt\\":\\"2026-05-27T08:00:00Z\\"}",
        "{\\"id\\":\\"todo-3\\",\\"title\\":\\"add\\",\\"updatedAt\\":\\"2026-05-27T09:00:00Z\\"}"
      ]
    }
  }
}
''';

      await BackupService.importAll(incoming, merge: true);

      expect(prefs.getStringList('todos'), <String>[
        '{"id":"todo-1","title":"new","updatedAt":"2026-05-27T08:00:00Z"}',
        '{"id":"todo-2","title":"stay","updatedAt":"2026-05-26T09:00:00Z"}',
        '{"id":"todo-3","title":"add","updatedAt":"2026-05-27T09:00:00Z"}',
      ]);
    },
  );
}
