import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/services/reminder_schedule_display_copy.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/services/reminder_sinks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  test(
    'replace and applyBatch retain display metadata for a cold localized snapshot',
    () async {
      const registry = SharedPreferencesReminderScheduleRegistry();
      final todoCopy = ReminderScheduleDisplayCopy.rules(
        ReminderScheduleSubject.todo,
        defaultTitle: false,
        repeating: true,
        ruleCount: 3,
      );
      final todoDisplay = ReminderScheduleDisplayInfo(
        title: '  用户的待办标题 🔔  ',
        subtitle: '  待办 · 重复提醒 · 通知、弹出框 · 3 条规则  ',
        kinds: const <ReminderKind>{ReminderKind.push, ReminderKind.popup},
        acceptedIdSets: const <Set<int>>[
          <int>{101, 102},
          <int>{103},
        ],
        displayCopy: todoCopy,
      );

      await registry.replaceObject('todo', 'todo-with-display-copy', <int>{
        0,
        301,
        300,
      }, display: todoDisplay);

      final datedCopy = ReminderScheduleDisplayCopy.dated(
        ReminderScheduleSubject.countdown,
        defaultTitle: false,
        primaryKind: ReminderKind.alarm,
        at: DateTime(2026, 12, 24, 18, 5),
      );
      final datedDisplay = ReminderScheduleDisplayInfo(
        title: '  圣诞倒计时  ',
        subtitle: '  倒计时 · 闹钟 · 2026-12-24 18:05  ',
        kinds: const <ReminderKind>{ReminderKind.alarm},
        acceptedIdSets: const <Set<int>>[
          <int>{401, 402},
        ],
        displayCopy: datedCopy,
      );
      await registry.applyBatch(
        <String, Map<String, ReminderScheduleRegistryMutation>>{
          'countdown': <String, ReminderScheduleRegistryMutation>{
            'countdown-with-display-copy':
                ReminderScheduleRegistryMutation.replace(<int>{
                  501,
                  0,
                }, display: datedDisplay),
          },
        },
      );

      final preferences = await SharedPreferences.getInstance();
      final idsBeforeSnapshot = preferences.getString(
        'reminder_scheduler_registry_v1',
      );
      final displaysBeforeSnapshot = preferences.getString(
        'reminder_scheduler_display_registry_v1',
      );
      final idsJson = jsonDecode(idsBeforeSnapshot!) as Map<String, dynamic>;
      final displaysJson =
          jsonDecode(displaysBeforeSnapshot!) as Map<String, dynamic>;
      expect(idsJson['todo']['todo-with-display-copy'], <int>[300, 301]);
      expect(idsJson['countdown']['countdown-with-display-copy'], <int>[501]);
      expect(
        displaysJson['todo']['todo-with-display-copy']['title'],
        todoDisplay.title,
      );
      expect(
        displaysJson['todo']['todo-with-display-copy']['subtitle'],
        todoDisplay.subtitle,
      );
      expect(
        displaysJson['todo']['todo-with-display-copy']['display_copy'],
        todoCopy.toJson(),
      );
      expect(
        displaysJson['countdown']['countdown-with-display-copy']['display_copy'],
        datedCopy.toJson(),
      );

      // A new scheduler starts without a warmed display cache and must rebuild
      // the retained snapshot from the two persisted registry records.
      I18n.setLocale(AppLocale.en);
      final scheduler = _scheduler(registry);
      final snapshot = await scheduler.registeredRemindersSnapshot();
      final todoEntry = snapshot.singleWhere(
        (entry) => entry.objectKey == 'todo:todo-with-display-copy',
      );
      final countdownEntry = snapshot.singleWhere(
        (entry) => entry.objectKey == 'countdown:countdown-with-display-copy',
      );

      expect(todoEntry.ids, <int>[300, 301]);
      expect(todoEntry.kinds, <ReminderKind>{
        ReminderKind.push,
        ReminderKind.popup,
      });
      expect(todoEntry.acceptedIdSets, <Set<int>>[
        <int>{101, 102},
        <int>{103},
      ]);
      expect(todoEntry.displayCopy?.toJson(), todoCopy.toJson());
      expect(countdownEntry.ids, <int>[501]);
      expect(countdownEntry.kinds, <ReminderKind>{ReminderKind.alarm});
      expect(countdownEntry.acceptedIdSets, <Set<int>>[
        <int>{401, 402},
      ]);
      expect(countdownEntry.displayCopy?.toJson(), datedCopy.toJson());

      final todoZh = todoEntry.displayFor(AppLocale.zh);
      final todoEn = todoEntry.displayFor(AppLocale.en);
      expect(todoEntry.subtitle, todoEn.subtitle);
      expect(todoEntry.subtitle, contains('Todo · Repeating reminder'));
      expect(todoZh.title, todoDisplay.title);
      expect(todoEn.title, todoDisplay.title);
      expect(todoZh.subtitle, isNot(todoEn.subtitle));
      final countdownZh = countdownEntry.displayFor(AppLocale.zh);
      final countdownEn = countdownEntry.displayFor(AppLocale.en);
      expect(countdownEntry.subtitle, countdownEn.subtitle);
      expect(countdownEntry.subtitle, 'Countdown · Alarm · 12-24 18:05');
      expect(countdownZh.title, datedDisplay.title);
      expect(countdownEn.title, datedDisplay.title);
      expect(countdownZh.subtitle, isNot(countdownEn.subtitle));

      I18n.setLocale(AppLocale.zh);
      expect(todoEntry.title, todoZh.title);
      expect(todoEntry.subtitle, todoZh.subtitle);
      I18n.setLocale(AppLocale.en);
      expect(todoEntry.title, todoEn.title);
      expect(todoEntry.subtitle, todoEn.subtitle);
      I18n.setLocale(AppLocale.zh);
      expect(todoEntry.title, todoZh.title);
      expect(todoEntry.subtitle, todoZh.subtitle);

      // Reading either locale and retaining the same snapshot is read-only.
      expect(
        preferences.getString('reminder_scheduler_registry_v1'),
        idsBeforeSnapshot,
      );
      expect(
        preferences.getString('reminder_scheduler_display_registry_v1'),
        displaysBeforeSnapshot,
      );
      final restoredTodo = (await registry.displayByObject(
        'todo',
      ))['todo-with-display-copy']!;
      expect(restoredTodo.title, todoDisplay.title);
      expect(restoredTodo.subtitle, todoDisplay.subtitle);
      expect(restoredTodo.displayCopy?.toJson(), todoCopy.toJson());
      expect(restoredTodo.kinds, todoDisplay.kinds);
      expect(restoredTodo.acceptedIdSets, todoDisplay.acceptedIdSets);
    },
  );

  test(
    'cold preference decode keeps legacy and malformed records literal beside a valid neighbor',
    () async {
      final todoRules = <String, Object?>{
        'schemaVersion': 1,
        'shape': 'rules',
        'subject': 'todo',
        'titleMode': 'literal',
        'repeating': false,
        'ruleCount': 2,
      };
      final habitDescriptor = <String, Object?>{
        'schemaVersion': 1,
        'shape': 'habit',
        'subject': 'habit',
        'titleMode': 'literal',
        'primaryKind': 'popup',
        'weekdays': <int>[1, 3],
        'hour': 8,
        'minute': 30,
      };
      final datedDescriptor = <String, Object?>{
        'schemaVersion': 1,
        'shape': 'dated',
        'subject': 'countdown',
        'titleMode': 'literal',
        'primaryKind': 'alarm',
        'year': 2026,
        'month': 12,
        'day': 24,
        'hour': 18,
        'minute': 5,
      };
      final badDescriptors =
          <
            ({
              String objectType,
              String objectId,
              Map<String, Object?> descriptor,
            })
          >[
            (
              objectType: 'todo',
              objectId: 'bad-version',
              descriptor: <String, Object?>{
                ...todoRules,
                'schemaVersion': 2,
                'titleMode': 'default',
              },
            ),
            (
              objectType: 'todo',
              objectId: 'missing-rule-count',
              descriptor: <String, Object?>{
                'schemaVersion': 1,
                'shape': 'rules',
                'subject': 'todo',
                'titleMode': 'literal',
                'repeating': false,
              },
            ),
            (
              objectType: 'todo',
              objectId: 'extra-descriptor-key',
              descriptor: <String, Object?>{
                ...todoRules,
                'unexpected': 'future-field',
              },
            ),
            (
              objectType: 'todo',
              objectId: 'wrong-repeating-type',
              descriptor: <String, Object?>{...todoRules, 'repeating': 'false'},
            ),
            (
              objectType: 'todo',
              objectId: 'invalid-rule-count',
              descriptor: <String, Object?>{...todoRules, 'ruleCount': 0},
            ),
            (
              objectType: 'habit',
              objectId: 'invalid-hour',
              descriptor: <String, Object?>{...habitDescriptor, 'hour': 24},
            ),
            (
              objectType: 'countdown',
              objectId: 'impossible-date',
              descriptor: <String, Object?>{
                ...datedDescriptor,
                'month': 2,
                'day': 30,
              },
            ),
            (
              objectType: 'habit',
              objectId: 'invalid-weekday',
              descriptor: <String, Object?>{
                ...habitDescriptor,
                'weekdays': <int>[1, 8],
              },
            ),
            (
              objectType: 'todo',
              objectId: 'shape-subject-mismatch',
              descriptor: <String, Object?>{
                'schemaVersion': 1,
                'shape': 'habit',
                'subject': 'todo',
                'titleMode': 'literal',
                'primaryKind': 'popup',
                'weekdays': <int>[1, 3],
                'hour': 8,
                'minute': 30,
              },
            ),
            (
              objectType: 'todo',
              objectId: 'outer-subject-mismatch',
              descriptor: <String, Object?>{...todoRules, 'subject': 'goal'},
            ),
            (
              objectType: 'anniversary',
              objectId: 'off-primary-kind',
              descriptor: <String, Object?>{
                ...datedDescriptor,
                'subject': 'anniversary',
                'primaryKind': 'off',
              },
            ),
          ];

      final idRegistry = <String, Map<String, List<int>>>{};
      final displayRegistry = <String, Map<String, Map<String, Object?>>>{};
      final expectedRecords = <_SeededDisplay>[];
      var nextId = 9100;

      void addRecord({
        required String objectType,
        required String objectId,
        Map<String, Object?>? descriptor,
        Map<String, Object?>? expectedDisplayCopy,
        String? title,
        String? subtitle,
      }) {
        final registrationId = nextId++;
        final recordTitle = title ?? '  保留标题：$objectId / Keep 原文 🔔  ';
        final recordSubtitle =
            subtitle ?? '  保留说明：$objectId · Mixed EN · 不推断  ';
        const kinds = <ReminderKind>{ReminderKind.push, ReminderKind.popup};
        final acceptedIdSets = <Set<int>>[
          <int>{registrationId + 10, registrationId + 11},
          <int>{registrationId + 12},
        ];
        idRegistry.putIfAbsent(
          objectType,
          () => <String, List<int>>{},
        )[objectId] = <int>[
          registrationId,
        ];
        displayRegistry.putIfAbsent(
          objectType,
          () => <String, Map<String, Object?>>{},
        )[objectId] = <String, Object?>{
          'title': recordTitle,
          'subtitle': recordSubtitle,
          'kinds': kinds.map((kind) => kind.name).toList(),
          'accepted_id_sets': acceptedIdSets
              .map((ids) => ids.toList())
              .toList(),
          'display_copy': ?descriptor,
        };
        expectedRecords.add(
          _SeededDisplay(
            objectType: objectType,
            objectId: objectId,
            ids: <int>[registrationId],
            title: recordTitle,
            subtitle: recordSubtitle,
            kinds: kinds,
            acceptedIdSets: acceptedIdSets,
            descriptor: expectedDisplayCopy,
          ),
        );
      }

      final validNeighborCopy = ReminderScheduleDisplayCopy.rules(
        ReminderScheduleSubject.todo,
        defaultTitle: false,
        repeating: false,
        ruleCount: 1,
      );
      addRecord(
        objectType: 'todo',
        objectId: 'valid-neighbor',
        descriptor: validNeighborCopy.toJson(),
        expectedDisplayCopy: validNeighborCopy.toJson(),
        title: '  Neighbor title / 原文  ',
        subtitle: '  邻居记录的旧版中文说明  ',
      );
      addRecord(
        objectType: 'todo',
        objectId: 'legacy-template-like',
        title: '  待办提醒  ',
        subtitle: '  待办 · 已登记到系统提醒队列  ',
      );
      addRecord(
        objectType: 'todo',
        objectId: 'legacy-mixed-literal',
        title: ' \t待办提醒 / Keep this 原文 🔔  ',
        subtitle: '  待办 · 已登记到系统提醒队列 | Mixed EN  ',
      );
      for (final fixture in badDescriptors) {
        addRecord(
          objectType: fixture.objectType,
          objectId: fixture.objectId,
          descriptor: fixture.descriptor,
        );
      }

      final seededIds = jsonEncode(idRegistry);
      final seededDisplays = jsonEncode(displayRegistry);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reminder_scheduler_registry_v1': seededIds,
        'reminder_scheduler_display_registry_v1': seededDisplays,
      });
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('reminder_scheduler_registry_v1'),
        seededIds,
      );
      expect(
        preferences.getString('reminder_scheduler_display_registry_v1'),
        seededDisplays,
      );

      const registry = SharedPreferencesReminderScheduleRegistry();
      I18n.setLocale(AppLocale.en);
      final decodedByType =
          <String, Map<String, ReminderScheduleDisplayInfo>>{};
      for (final objectType in displayRegistry.keys) {
        final storedIds = await registry.idsByObject(objectType);
        expect(
          storedIds,
          <String, Set<int>>{
            for (final entry in idRegistry[objectType]!.entries)
              entry.key: entry.value.toSet(),
          },
          reason: 'IDs must survive optional metadata failure for $objectType',
        );
        decodedByType[objectType] = await registry.displayByObject(objectType);
      }

      for (final expected in expectedRecords) {
        final stored = decodedByType[expected.objectType]![expected.objectId];
        expect(stored, isNotNull, reason: expected.objectId);
        expect(stored!.title, expected.title, reason: expected.objectId);
        expect(stored.subtitle, expected.subtitle, reason: expected.objectId);
        expect(stored.kinds, expected.kinds, reason: expected.objectId);
        expect(
          stored.acceptedIdSets,
          expected.acceptedIdSets,
          reason: expected.objectId,
        );
        expect(
          stored.displayCopy?.toJson(),
          expected.descriptor,
          reason: expected.objectId,
        );
      }

      // Exercise the whole registry decoder and retained snapshot, not only
      // ReminderScheduleDisplayCopy.tryFromJson in isolation.
      final scheduler = _scheduler(registry);
      final snapshot = await scheduler.registeredRemindersSnapshot();
      final entriesByKey = <String, ReminderScheduleSnapshotEntry>{
        for (final entry in snapshot) entry.objectKey: entry,
      };
      expect(entriesByKey.keys.toSet(), {
        for (final record in expectedRecords)
          '${record.objectType}:${record.objectId}',
      });

      final neighbor = entriesByKey['todo:valid-neighbor']!;
      final neighborZh = neighbor.displayFor(AppLocale.zh);
      final neighborEn = neighbor.displayFor(AppLocale.en);
      expect(neighbor.title, neighborEn.title);
      expect(neighbor.subtitle, neighborEn.subtitle);
      expect(
        neighbor.subtitle,
        'Todo · One-time reminder · Notification, Popup · 1 rule',
      );
      expect(neighbor.displayCopy?.toJson(), validNeighborCopy.toJson());
      expect(neighborZh.title, '  Neighbor title / 原文  ');
      expect(neighborEn.title, '  Neighbor title / 原文  ');
      expect(neighborZh.subtitle, isNot('  邻居记录的旧版中文说明  '));
      expect(neighborEn.subtitle, isNot('  邻居记录的旧版中文说明  '));
      expect(neighborZh.subtitle, isNot(neighborEn.subtitle));

      for (final expected in expectedRecords) {
        final entry =
            entriesByKey['${expected.objectType}:${expected.objectId}']!;
        expect(entry.ids, expected.ids, reason: expected.objectId);
        expect(entry.kinds, expected.kinds, reason: expected.objectId);
        expect(
          entry.acceptedIdSets,
          expected.acceptedIdSets,
          reason: expected.objectId,
        );
        expect(
          entry.displayCopy?.toJson(),
          expected.descriptor,
          reason: expected.objectId,
        );

        final zh = entry.displayFor(AppLocale.zh);
        final en = entry.displayFor(AppLocale.en);
        if (expected.descriptor == null) {
          expect(zh.title, expected.title, reason: expected.objectId);
          expect(zh.subtitle, expected.subtitle, reason: expected.objectId);
          expect(en.title, expected.title, reason: expected.objectId);
          expect(en.subtitle, expected.subtitle, reason: expected.objectId);
        }

        for (final locale in const [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          if (expected.descriptor == null) {
            expect(entry.title, expected.title, reason: expected.objectId);
            expect(
              entry.subtitle,
              expected.subtitle,
              reason: expected.objectId,
            );
          } else {
            final localized = locale == AppLocale.zh ? zh : en;
            expect(entry.title, localized.title, reason: expected.objectId);
            expect(
              entry.subtitle,
              localized.subtitle,
              reason: expected.objectId,
            );
          }
        }
      }

      expect(
        preferences.getString('reminder_scheduler_registry_v1'),
        seededIds,
      );
      expect(
        preferences.getString('reminder_scheduler_display_registry_v1'),
        seededDisplays,
      );
    },
  );

  test(
    'reconciliation batch overlay and flush retain the whole display record',
    () async {
      const registry = SharedPreferencesReminderScheduleRegistry();
      const oldDisplay = ReminderScheduleDisplayInfo(
        title: '旧标题',
        subtitle: '旧说明',
        displayCopy: ReminderScheduleDisplayCopy.registered(
          ReminderScheduleSubject.habit,
        ),
      );
      await registry.replaceObject('habit', 'batched-habit', <int>{
        601,
      }, display: oldDisplay);

      final scheduler = _scheduler(registry);
      final replacementCopy = ReminderScheduleDisplayCopy.habit(
        defaultTitle: false,
        primaryKind: ReminderKind.popup,
        weekdays: const <int>[1, 3, 5],
        hour: 7,
        minute: 45,
      );
      final replacementDisplay = ReminderScheduleDisplayInfo(
        title: '  拉伸习惯  ',
        subtitle: '  习惯 · 周一、周三、周五 · 07:45  ',
        kinds: const <ReminderKind>{ReminderKind.popup, ReminderKind.push},
        acceptedIdSets: const <Set<int>>[
          <int>{701, 702},
        ],
        displayCopy: replacementCopy,
      );

      await scheduler.runReconciliationBatch((batch) async {
        batch.stageReplace('habit', 'batched-habit', <int>{
          602,
          0,
        }, display: replacementDisplay);
        final ids = batch.overlayIds(
          'habit',
          await registry.idsByObject('habit'),
        );
        final displays = batch.overlayDisplays(
          'habit',
          await registry.displayByObject('habit'),
        );
        expect(ids['batched-habit'], <int>{602});
        expect(displays['batched-habit']?.title, replacementDisplay.title);
        expect(
          displays['batched-habit']?.displayCopy?.toJson(),
          replacementCopy.toJson(),
        );

        // Staged values are visible to the overlay but remain uncommitted here.
        expect((await registry.idsByObject('habit'))['batched-habit'], <int>{
          601,
        });
        expect(
          (await registry.displayByObject('habit'))['batched-habit']?.title,
          oldDisplay.title,
        );
        return true;
      });

      expect((await registry.idsByObject('habit'))['batched-habit'], <int>{
        602,
      });
      final flushedDisplay = (await registry.displayByObject(
        'habit',
      ))['batched-habit']!;
      expect(flushedDisplay.title, replacementDisplay.title);
      expect(flushedDisplay.subtitle, replacementDisplay.subtitle);
      expect(flushedDisplay.displayCopy?.toJson(), replacementCopy.toJson());
      expect(flushedDisplay.kinds, replacementDisplay.kinds);
      expect(flushedDisplay.acceptedIdSets, replacementDisplay.acceptedIdSets);

      final batchSnapshot = await scheduler.registeredRemindersSnapshot();
      final entry = batchSnapshot.single;
      expect(entry.objectKey, 'habit:batched-habit');
      expect(entry.displayCopy?.toJson(), replacementCopy.toJson());
      expect(entry.displayFor(AppLocale.en).title, replacementDisplay.title);
    },
  );
}

ReminderScheduler _scheduler(ReminderScheduleRegistry registry) =>
    ReminderScheduler(
      _UnexpectedNotificationSink(),
      alarm: _UnexpectedAlarmSink(),
      registry: registry,
    );

class _SeededDisplay {
  const _SeededDisplay({
    required this.objectType,
    required this.objectId,
    required this.ids,
    required this.title,
    required this.subtitle,
    required this.kinds,
    required this.acceptedIdSets,
    required this.descriptor,
  });

  final String objectType;
  final String objectId;
  final List<int> ids;
  final String title;
  final String subtitle;
  final Set<ReminderKind> kinds;
  final List<Set<int>> acceptedIdSets;
  final Map<String, Object?>? descriptor;
}

Never _unexpectedSchedulerCall() => throw StateError(
  'A display snapshot must not schedule or cancel reminders.',
);

class _UnexpectedNotificationSink implements ReminderNotificationSink {
  @override
  Future<void> cancel(int id) async => _unexpectedSchedulerCall();

  @override
  Future<void> cancelAnniversary(String annId) async =>
      _unexpectedSchedulerCall();

  @override
  Future<void> cancelHabitReminder(String habitId) async =>
      _unexpectedSchedulerCall();

  @override
  Future<void> cancelTodoReminder(String todoId) async =>
      _unexpectedSchedulerCall();

  @override
  Future<void> scheduleAnniversary({
    required String annId,
    required String title,
    required DateTime whenDate,
    int daysBefore = 1,
    int hour = 9,
    int minute = 0,
  }) async => _unexpectedSchedulerCall();

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async => _unexpectedSchedulerCall();

  @override
  Future<void> scheduleHabitReminder({
    required String habitId,
    required String habitName,
    required int hour,
    required int minute,
    List<int>? weekdays,
  }) async => _unexpectedSchedulerCall();

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async => _unexpectedSchedulerCall();
}

class _UnexpectedAlarmSink implements ReminderAlarmSink {
  @override
  Future<void> cancel(int id) async => _unexpectedSchedulerCall();

  @override
  Future<void> scheduleDailyFullScreen({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  }) async => _unexpectedSchedulerCall();

  @override
  Future<void> scheduleFullScreen({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  }) async => _unexpectedSchedulerCall();
}
