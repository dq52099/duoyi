import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/services/foreground_reminder_popup_sink.dart';
import 'package:duoyi/services/reminder_sinks.dart';

class _FakeNotificationFallback
    implements ReminderNotificationSink, ReminderScheduleIssueSink {
  final List<Map<String, Object?>> once = [];
  final List<Map<String, Object?>> daily = [];
  final List<int> cancelled = [];
  final List<Map<String, Object?>> issues = [];
  bool failOnce = false;
  bool failDaily = false;

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (failOnce) {
      throw StateError('forced scheduleOnce fallback failure');
    }
    once.add({
      'id': id,
      'title': title,
      'body': body,
      'when': when,
      'payload': payload,
    });
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    if (failDaily) {
      throw StateError('forced scheduleDaily fallback failure');
    }
    daily.add({
      'id': id,
      'title': title,
      'body': body,
      'hour': hour,
      'minute': minute,
      'weekdays': weekdays,
      'payload': payload,
    });
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> cancelAnniversary(String annId) async {}

  @override
  Future<void> cancelHabitReminder(String habitId) async {}

  @override
  Future<void> cancelTodoReminder(String todoId) async {}

  @override
  Future<void> scheduleAnniversary({
    required String annId,
    required String title,
    required DateTime whenDate,
    int daysBefore = 1,
    int hour = 9,
    int minute = 0,
  }) async {}

  @override
  Future<void> scheduleHabitReminder({
    required String habitId,
    required String habitName,
    required int hour,
    required int minute,
    List<int>? weekdays,
  }) async {}

  @override
  void recordReminderScheduleIssue({
    required String title,
    required String message,
    DateTime? scheduledTime,
    String? relatedId,
    bool blocking = true,
  }) {
    issues.add({
      'title': title,
      'message': message,
      'relatedId': relatedId,
      'blocking': blocking,
    });
  }
}

void main() {
  testWidgets(
    'one-shot popup registers notification fallback and cancels it for foreground dialog',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final fallback = _FakeNotificationFallback();
      final sink = ForegroundReminderPopupSink(
        contextGetter: () => navigatorKey.currentContext,
        notificationFallback: fallback,
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );

      await sink.scheduleOnce(
        id: 5,
        title: '提醒',
        body: '前台显示',
        when: DateTime.now().add(const Duration(milliseconds: 800)),
        payload: 'duoyi://todo/5',
      );

      expect(fallback.once, hasLength(1));
      final cancelCountAfterSchedule = fallback.cancelled.length;
      expect(
        fallback.once.single['payload'],
        contains('fallback=popup_notification'),
      );

      await tester.pump(const Duration(milliseconds: 180));
      expect(fallback.cancelled, hasLength(cancelCountAfterSchedule));
      expect(find.text('前台显示'), findsNothing);

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('前台显示'), findsOneWidget);
      expect(fallback.cancelled.length, greaterThan(cancelCountAfterSchedule));
    },
  );

  testWidgets(
    'in-app-only one-shot popup does not register notification fallback',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final fallback = _FakeNotificationFallback();
      final sink = ForegroundReminderPopupSink(
        contextGetter: () => navigatorKey.currentContext,
        notificationFallback: fallback,
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );

      await sink.scheduleInAppOnlyOnce(
        id: 6,
        title: '弹出测试',
        body: '只在应用内显示',
        when: DateTime.now().add(const Duration(milliseconds: 800)),
        payload: 'duoyi://tab/mine',
      );

      expect(fallback.once, isEmpty);
      expect(fallback.cancelled, contains(6));

      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      expect(find.text('只在应用内显示'), findsOneWidget);
      expect(fallback.once, isEmpty);
    },
  );

  testWidgets(
    'one-shot popup keeps fallback when app backgrounds right before due time',
    (tester) async {
      var foreground = true;
      final navigatorKey = GlobalKey<NavigatorState>();
      final fallback = _FakeNotificationFallback();
      final sink = ForegroundReminderPopupSink(
        contextGetter: () => navigatorKey.currentContext,
        notificationFallback: fallback,
        isForegroundGetter: () => foreground,
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );

      await sink.scheduleOnce(
        id: 15,
        title: '提醒',
        body: '锁屏兜底',
        when: DateTime.now().add(const Duration(milliseconds: 800)),
        payload: 'duoyi://todo/15',
      );
      final cancelCountAfterSchedule = fallback.cancelled.length;

      await tester.pump(const Duration(milliseconds: 700));
      foreground = false;
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pumpAndSettle();

      expect(fallback.once, hasLength(1));
      expect(fallback.cancelled, hasLength(cancelCountAfterSchedule));
      expect(find.text('锁屏兜底'), findsNothing);
    },
  );

  testWidgets(
    'one-shot popup keeps notification fallback when app is not foreground',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final fallback = _FakeNotificationFallback();
      final sink = ForegroundReminderPopupSink(
        contextGetter: () => navigatorKey.currentContext,
        notificationFallback: fallback,
        isForegroundGetter: () => false,
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );

      await sink.scheduleOnce(
        id: 6,
        title: '提醒',
        body: '后台兜底',
        when: DateTime.now().add(const Duration(milliseconds: 20)),
        payload: 'duoyi://todo/6',
      );
      final cancelCountAfterSchedule = fallback.cancelled.length;

      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();

      expect(fallback.once, hasLength(1));
      expect(fallback.cancelled, hasLength(cancelCountAfterSchedule));
      expect(find.text('后台兜底'), findsNothing);
    },
  );

  testWidgets('repeating popup registers daily notification fallback', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final fallback = _FakeNotificationFallback();
    final sink = ForegroundReminderPopupSink(
      contextGetter: () => navigatorKey.currentContext,
      notificationFallback: fallback,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    await sink.scheduleRepeating(
      id: 8,
      title: '提醒',
      body: '每天提醒',
      hour: 19,
      minute: 5,
      weekdays: const [DateTime.monday, DateTime.friday],
      payload: 'duoyi://habit/8',
    );

    expect(fallback.daily, hasLength(1));
    expect(fallback.daily.single['id'], 8);
    expect(fallback.daily.single['weekdays'], const [
      DateTime.monday,
      DateTime.friday,
    ]);
    expect(
      fallback.daily.single['payload'],
      contains('fallback=popup_notification'),
    );
    await sink.cancel(8);
  });

  testWidgets(
    'repeating popup records fallback rebuild failure after foreground delivery',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final fallback = _FakeNotificationFallback();
      final sink = ForegroundReminderPopupSink(
        contextGetter: () => navigatorKey.currentContext,
        notificationFallback: fallback,
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );

      final now = DateTime.now();
      var trigger = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      ).add(const Duration(minutes: 1));
      if (!trigger.isAfter(now)) {
        trigger = trigger.add(const Duration(minutes: 1));
      }
      await sink.scheduleRepeating(
        id: 928,
        title: '提醒',
        body: '下一次兜底失败',
        hour: trigger.hour,
        minute: trigger.minute,
        payload: 'duoyi://habit/h-28?confirm=1',
      );
      expect(fallback.daily, hasLength(1));

      fallback.failDaily = true;
      await tester.pump(
        trigger.difference(now) + const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();
      await tester.pump();

      expect(find.text('下一次兜底失败'), findsOneWidget);
      expect(fallback.issues, hasLength(1));
      expect(fallback.issues.single['title'], '弹出提醒兜底重建失败');
      expect(fallback.issues.single['relatedId'], 'h-28');
      expect(fallback.issues.single['blocking'], isFalse);
      expect(tester.takeException(), isNull);

      await sink.cancel(928);
    },
  );

  testWidgets('one-shot popup propagates notification fallback failures', (
    tester,
  ) async {
    final fallback = _FakeNotificationFallback()..failOnce = true;
    final sink = ForegroundReminderPopupSink(
      contextGetter: () => null,
      notificationFallback: fallback,
    );

    await expectLater(
      sink.scheduleOnce(
        id: 18,
        title: '提醒',
        body: '兜底失败',
        when: DateTime.now().add(const Duration(minutes: 5)),
        payload: 'duoyi://todo/18',
      ),
      throwsA(isA<ReminderPopupFallbackUnavailableException>()),
    );
    expect(fallback.once, isEmpty);
  });

  testWidgets('repeating popup propagates notification fallback failures', (
    tester,
  ) async {
    final fallback = _FakeNotificationFallback()..failDaily = true;
    final sink = ForegroundReminderPopupSink(
      contextGetter: () => null,
      notificationFallback: fallback,
    );

    await expectLater(
      sink.scheduleRepeating(
        id: 19,
        title: '提醒',
        body: '重复兜底失败',
        hour: 9,
        minute: 30,
        payload: 'duoyi://habit/19',
      ),
      throwsA(isA<ReminderPopupFallbackUnavailableException>()),
    );
    expect(fallback.daily, isEmpty);
  });

  testWidgets('cancel closes a visible foreground reminder dialog', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final sink = ForegroundReminderPopupSink(
      contextGetter: () => navigatorKey.currentContext,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    await sink.scheduleOnce(
      id: 42,
      title: '提醒',
      body: '只显示一条',
      when: DateTime.now().add(const Duration(seconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(find.text('只显示一条'), findsOneWidget);

    await sink.cancel(42);
    await tester.pumpAndSettle();
    expect(find.text('只显示一条'), findsNothing);
  });

  testWidgets('rescheduling same id keeps only the latest foreground dialog', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final sink = ForegroundReminderPopupSink(
      contextGetter: () => navigatorKey.currentContext,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    final now = DateTime.now();
    await sink.scheduleOnce(
      id: 7,
      title: '提醒',
      body: '旧提醒',
      when: now.add(const Duration(seconds: 1)),
    );
    await sink.scheduleOnce(
      id: 7,
      title: '提醒',
      body: '新提醒',
      when: now.add(const Duration(seconds: 2)),
    );

    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('新提醒'), findsOneWidget);
    expect(find.text('旧提醒'), findsNothing);
  });

  testWidgets('rescheduling visible same id replaces the existing dialog', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final sink = ForegroundReminderPopupSink(
      contextGetter: () => navigatorKey.currentContext,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    await sink.scheduleOnce(
      id: 9,
      title: '提醒',
      body: '已显示',
      when: DateTime.now().add(const Duration(seconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(find.text('已显示'), findsOneWidget);

    await sink.scheduleOnce(
      id: 9,
      title: '提醒',
      body: '替换后',
      when: DateTime.now().add(const Duration(seconds: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.text('已显示'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('替换后'), findsOneWidget);
  });

  testWidgets('same popup content only opens one visible dialog briefly', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final sink = ForegroundReminderPopupSink(
      contextGetter: () => navigatorKey.currentContext,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    final now = DateTime.now();
    await sink.scheduleOnce(
      id: 101,
      title: '提醒',
      body: '重复内容',
      when: now.add(const Duration(seconds: 1)),
      payload: 'duoyi://todo/a',
    );
    await sink.scheduleOnce(
      id: 102,
      title: '提醒',
      body: '重复内容',
      when: now.add(const Duration(milliseconds: 1050)),
      payload: 'duoyi://todo/a',
    );

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('重复内容'), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('重复内容'), findsNothing);
  });
}
