import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/location_reminder.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/services/location_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocationReminderController', () {
    test('ingest fix triggers reminders via ManualLocationProbe', () async {
      final provider = LocationReminderProvider();
      await provider.loadFromStorage();
      await provider.add(
        LocationReminder(
          id: 'r1',
          title: '到办公室',
          latitude: 39.9042,
          longitude: 116.4074,
          radiusMeters: 500,
          trigger: LocationTrigger.enter,
        ),
      );

      final probe = ManualLocationProbe();
      final hits = <LocationReminderHit>[];
      final controller = LocationReminderController(
        probe: probe,
        provider: provider,
        onHit: hits.add,
      );

      await controller.start();
      expect(probe.isTracking, isTrue);

      probe.setCurrentLocation(39.9042, 116.4074);
      await Future<void>.delayed(Duration.zero);

      expect(hits.length, 1);
      expect(hits.first.reminder.id, 'r1');

      await controller.stop();
      expect(probe.isTracking, isFalse);
    });

    test('远距离 fix 不触发', () async {
      final provider = LocationReminderProvider();
      await provider.loadFromStorage();
      await provider.add(
        LocationReminder(
          id: 'r1',
          title: '到办公室',
          latitude: 39.9042,
          longitude: 116.4074,
          radiusMeters: 100,
          trigger: LocationTrigger.enter,
        ),
      );

      final probe = ManualLocationProbe();
      final hits = <LocationReminderHit>[];
      final controller = LocationReminderController(
        probe: probe,
        provider: provider,
        onHit: hits.add,
      );

      await controller.start();
      probe.setCurrentLocation(31.2304, 121.4737); // 上海
      await Future<void>.delayed(Duration.zero);

      expect(hits, isEmpty);
    });

    test('未 start 时 setCurrentLocation 无效', () async {
      final probe = ManualLocationProbe();
      expect(probe.isTracking, isFalse);
      probe.setCurrentLocation(39.9042, 116.4074);
      // 不报错就行
    });
  });
}
