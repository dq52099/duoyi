import 'dart:convert';

import 'package:duoyi/providers/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('通知红点状态', () {
    test('未读历史、全部已读、全部未读和清空会同步红点状态', () async {
      final service = NotificationService();

      expect(service.unreadCount, 0);
      expect(service.hasUnreadHistory, isFalse);

      service.addHistoryForTest(
        NotificationItem(
          id: 'unread-1',
          title: '待处理提醒',
          body: '需要在我的页和通知设置显示红点',
          scheduledTime: DateTime(2026, 5, 24, 9),
          type: NotificationType.todo,
          isRead: false,
        ),
      );

      expect(service.unreadCount, 1);
      expect(service.hasUnreadHistory, isTrue);

      await service.markAllHistoryRead();
      expect(service.unreadCount, 0);
      expect(service.hasUnreadHistory, isFalse);

      await service.markAllHistoryUnread();
      expect(service.unreadCount, 1);
      expect(service.hasUnreadHistory, isTrue);

      await service.clearHistory();
      expect(service.historyCount, 0);
      expect(service.unreadCount, 0);
      expect(service.hasUnreadHistory, isFalse);
    });

    test('持久化历史保留显式未读状态并写入最近已读时间', () async {
      final newest = DateTime(2026, 5, 24, 10);
      final older = DateTime(2026, 5, 23, 18);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'duoyi_notif_history': <String>[
          jsonEncode(
            NotificationItem(
              id: 'new-unread',
              title: '新通知',
              body: '应该触发红点',
              scheduledTime: newest,
              type: NotificationType.general,
              isRead: false,
            ).toJson(),
          ),
          jsonEncode(
            NotificationItem(
              id: 'old-read',
              title: '旧通知',
              body: '已经读过',
              scheduledTime: older,
              type: NotificationType.habit,
              isRead: true,
            ).toJson(),
          ),
        ],
      });
      final service = NotificationService();

      await service.loadHistoryForTest();

      expect(service.historyCount, 2);
      expect(service.unreadCount, 1);
      expect(service.hasUnreadHistory, isTrue);

      await service.markAllHistoryRead();

      expect(service.unreadCount, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('duoyi_notif_history_seen_at'),
        newest.toIso8601String(),
      );
    });

    test('旧版无 read 字段记录按 seen 时间迁移，避免升级后误亮红点', () async {
      final seenAt = DateTime(2026, 5, 24, 10);
      final beforeSeen = DateTime(2026, 5, 24, 9, 30);
      final afterSeen = DateTime(2026, 5, 24, 10, 30);
      Map<String, Object?> legacyJson(String id, DateTime scheduledTime) {
        return <String, Object?>{
          'id': id,
          'title': id,
          'body': 'legacy',
          'scheduledTime': scheduledTime.toIso8601String(),
          'type': NotificationType.general.index,
        };
      }

      SharedPreferences.setMockInitialValues(<String, Object>{
        'duoyi_notif_history_seen_at': seenAt.toIso8601String(),
        'duoyi_notif_history': <String>[
          jsonEncode(legacyJson('after-seen', afterSeen)),
          jsonEncode(legacyJson('before-seen', beforeSeen)),
        ],
      });
      final service = NotificationService();

      await service.loadHistoryForTest();

      expect(service.historyCount, 2);
      expect(service.history.first.id, 'after-seen');
      expect(service.history.first.isRead, isFalse);
      expect(service.history.last.id, 'before-seen');
      expect(service.history.last.isRead, isTrue);
      expect(service.unreadCount, 1);
      expect(service.hasUnreadHistory, isTrue);
    });

    test('调度排查记录保持已读，只有真实新通知点亮红点', () {
      final service = NotificationService();

      service.addHistoryForTest(
        NotificationItem(
          id: 'scheduled-1',
          title: '已注册提醒',
          body: '用于排查系统队列，不应点亮红点',
          scheduledTime: DateTime(2026, 5, 24, 12),
          type: NotificationType.todo,
          isRead: true,
        ),
      );

      expect(service.historyCount, 1);
      expect(service.unreadCount, 0);
      expect(service.hasUnreadHistory, isFalse);

      service.addHistoryForTest(
        NotificationItem(
          id: 'delivered-1',
          title: '新通知',
          body: '真实到达的新通知才显示红点',
          scheduledTime: DateTime(2026, 5, 24, 12, 30),
          type: NotificationType.general,
          isRead: false,
        ),
      );

      expect(service.historyCount, 2);
      expect(service.unreadCount, 1);
      expect(service.hasUnreadHistory, isTrue);
    });
  });
}
