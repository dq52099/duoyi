import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/location_reminder.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';

void main() {
  group('LocationReminderEngine 距离', () {
    test('Haversine 距离同点为 0', () {
      final d = LocationReminderEngine.distanceMeters(
        39.9042,
        116.4074,
        39.9042,
        116.4074,
      );
      expect(d, lessThan(1));
    });

    test('距离对称且大于零', () {
      final d1 = LocationReminderEngine.distanceMeters(
        39.9042,
        116.4074,
        31.2304,
        121.4737,
      );
      final d2 = LocationReminderEngine.distanceMeters(
        31.2304,
        121.4737,
        39.9042,
        116.4074,
      );
      expect((d1 - d2).abs(), lessThan(1));
      // 北京到上海大约 1067 km
      expect(d1, greaterThan(1_000_000));
      expect(d1, lessThan(1_200_000));
    });
  });

  group('LocationReminderEngine.evaluate', () {
    final beijing = LocationFix(
      latitude: 39.9042,
      longitude: 116.4074,
      at: DateTime(2026, 5, 15, 10),
    );

    test('进入半径 → enter 触发', () {
      final reminder = LocationReminder(
        id: 'r1',
        title: '到公司提醒',
        latitude: 39.9042,
        longitude: 116.4074,
        radiusMeters: 200,
        trigger: LocationTrigger.enter,
      );
      final (hits, _) = LocationReminderEngine.evaluate(
        reminders: [reminder],
        fix: beijing,
        previousInRange: const {'r1': false},
      );
      expect(hits.length, 1);
      expect(hits.first.reminder.id, 'r1');
    });

    test('已在半径内 → 不再触发 enter', () {
      final reminder = LocationReminder(
        id: 'r1',
        title: '到公司提醒',
        latitude: 39.9042,
        longitude: 116.4074,
        radiusMeters: 200,
        trigger: LocationTrigger.enter,
      );
      final (hits, _) = LocationReminderEngine.evaluate(
        reminders: [reminder],
        fix: beijing,
        previousInRange: const {'r1': true},
      );
      expect(hits, isEmpty);
    });

    test('离开半径 → leave 触发', () {
      final reminder = LocationReminder(
        id: 'r2',
        title: '离开家提醒',
        latitude: 39.9042,
        longitude: 116.4074,
        radiusMeters: 100,
        trigger: LocationTrigger.leave,
      );
      // 上海，不在半径内
      final fix = LocationFix(
        latitude: 31.2304,
        longitude: 121.4737,
        at: DateTime(2026, 5, 15, 10),
      );
      final (hits, _) = LocationReminderEngine.evaluate(
        reminders: [reminder],
        fix: fix,
        previousInRange: const {'r2': true},
      );
      expect(hits.length, 1);
    });

    test('cooldown 期内不触发', () {
      final reminder = LocationReminder(
        id: 'r3',
        title: '到公司',
        latitude: 39.9042,
        longitude: 116.4074,
        radiusMeters: 200,
        trigger: LocationTrigger.enter,
        lastFiredAt: DateTime(2026, 5, 15, 9, 55),
      );
      final (hits, _) = LocationReminderEngine.evaluate(
        reminders: [reminder],
        fix: beijing,
        previousInRange: const {'r3': false},
      );
      expect(hits, isEmpty);
    });
  });

  group('LocationReminder JSON', () {
    test('roundtrip 保留字段和 updatedAt', () {
      final updatedAt = DateTime(2026, 5, 15, 12, 30);
      final r = LocationReminder(
        id: 'r1',
        title: '到公司',
        latitude: 39.9042,
        longitude: 116.4074,
        radiusMeters: 250,
        trigger: LocationTrigger.enter,
        oneShot: true,
        updatedAt: updatedAt,
      );
      final json = r.toJson();
      final decoded = LocationReminder.fromJson(json);
      expect(decoded.id, r.id);
      expect(decoded.title, r.title);
      expect(decoded.latitude, r.latitude);
      expect(decoded.longitude, r.longitude);
      expect(decoded.radiusMeters, r.radiusMeters);
      expect(decoded.trigger, r.trigger);
      expect(decoded.oneShot, r.oneShot);
      expect(decoded.updatedAt, updatedAt);
    });
  });

  group('LocationReminderProvider.loadFromStorage 清空语义', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    const storageKey = 'duoyi_location_reminders_v1';

    String encodeOne(String id) => jsonEncode([
      {
        'id': id,
        'title': '到家提醒',
        'latitude': 39.9042,
        'longitude': 116.4074,
        'radiusMeters': 200,
        'trigger': 'enter',
        'oneShot': false,
        'createdAt': '2026-05-15T10:00:00.000',
        'updatedAt': '2026-05-15T10:00:00.000',
      },
    ]);

    test('存储键被 wipe 后重载，内存旧提醒清空并通知 UI', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        storageKey: encodeOne('r1'),
      });
      final provider = LocationReminderProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      expect(provider.reminders.length, 1);

      // 模拟 BackupService.wipeAll：删除存储键后调用 loadFromStorage。
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);

      var notified = 0;
      provider.addListener(() => notified++);
      await provider.loadFromStorage();

      expect(provider.reminders, isEmpty);
      expect(provider.isLoaded, isTrue);
      expect(notified, greaterThan(0));
    });

    test('wipe 后重载再写入，不会把旧数据复活持久化', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        storageKey: encodeOne('old-1'),
      });
      final provider = LocationReminderProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
      await provider.loadFromStorage();
      expect(provider.reminders, isEmpty);

      await provider.add(
        LocationReminder(
          id: 'new-1',
          title: '到公司提醒',
          latitude: 31.2304,
          longitude: 121.4737,
        ),
      );

      final raw = prefs.getString(storageKey);
      expect(raw, isNotNull);
      final list = jsonDecode(raw!) as List;
      expect(list, hasLength(1));
      expect((list.single as Map)['id'], 'new-1');
    });
  });
}
