import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/providers/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'clearHistory clears the count shown by notification history entry',
    () async {
      final item = NotificationItem(
        id: 'n1',
        title: '测试通知',
        body: '通知内容',
        scheduledTime: DateTime(2026, 5, 17, 9),
        type: NotificationType.general,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'duoyi_notif_history': <String>[jsonEncode(item.toJson())],
      });

      final service = NotificationService();
      await service.loadHistoryForTest();

      expect(service.historyCount, 1);

      await service.clearHistory();

      expect(service.history, isEmpty);
      expect(service.historyCount, 0);
    },
  );
}
