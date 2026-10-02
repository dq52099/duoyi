import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/services/foreground_reminder_popup_sink.dart';
import 'package:duoyi/services/reminder_sinks.dart';

class _FakeNotificationFallback
    implements ReminderNotificationSink, ReminderScheduleIssueSink {
  final List<Map<String, Object?>> once = [];
  final List<Map<String, Object?>> daily = [];
  final List<int> cancelled = [];
  final List<String> operations = [];
  Object? onceError;
  Object? dailyError;
  Object? cancelError;
  bool failCancelAfterSchedule = false;
  int scheduleCount = 0;
  Completer<void>? dailyGate;
  int? failDailyCall;
  int dailyCalls = 0;
  final List<Map<String, Object?>> issues = [];

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    operations.add('once:$id');
    if (onceError case final error?) throw error;
    scheduleCount += 1;
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
    dailyCalls += 1;
    operations.add('daily-start:$dailyCalls');
    await dailyGate?.future;
    final error = dailyError;
    if ((failDailyCall == null || failDailyCall == dailyCalls) &&
        error != null) {
      throw error;
    }
    operations.add('daily-done:$dailyCalls');
    scheduleCount += 1;
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
    operations.add('cancel:$id');
    if (cancelError case final error?) {
      if (!failCancelAfterSchedule || scheduleCount > 0) throw error;
    }
    cancelled.add(id);
  }

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
      'scheduledTime': scheduledTime,
      'relatedId': relatedId,
      'blocking': blocking,
    });
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
}

void main() {
  testWidgets('one-shot popup reports fallback registration failures', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final fallback = _FakeNotificationFallback()
      ..onceError = StateError('one-shot fallback failed');
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

    await expectLater(
      sink.scheduleOnce(
        id: 88,
        title: '提醒',
        body: '兜底注册失败',
        when: DateTime.now().add(const Duration(minutes: 1)),
        payload: 'duoyi://todo/88',
      ),
      throwsStateError,
    );
    expect(fallback.issues.single['relatedId'], '88');

    await sink.cancel(88);
  });

  testWidgets('repeating popup reports fallback registration failures', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final fallback = _FakeNotificationFallback()
      ..dailyError = StateError('repeating fallback failed');
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

    await expectLater(
      sink.scheduleRepeating(
        id: 89,
        title: '提醒',
        body: '兜底注册失败',
        hour: 19,
        minute: 5,
        payload: 'duoyi://todo/89',
      ),
      throwsStateError,
    );
    expect(fallback.issues.single['relatedId'], '89');
    await sink.cancel(89);
  });

  testWidgets('cancel failure still closes the popup dialog', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final fallback = _FakeNotificationFallback()
      ..cancelError = StateError('cancel failed')
      ..failCancelAfterSchedule = true;
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
      id: 87,
      title: '提醒',
      body: '需要关闭',
      when: DateTime.now().add(const Duration(seconds: 1)),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('需要关闭'), findsOneWidget);

    await expectLater(sink.cancel(87), throwsStateError);
    await tester.pumpAndSettle();
    expect(find.text('需要关闭'), findsNothing);
  });

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

  testWidgets('foreground repeating delivery serializes fallback refresh', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final now = DateTime(2030, 6, 1, 10);
    final fallback = _FakeNotificationFallback();
    final sink = ForegroundReminderPopupSink(
      contextGetter: () => navigatorKey.currentContext,
      notificationFallback: fallback,
      nowGetter: () => now,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    await sink.scheduleRepeating(
      id: 68,
      title: '每日提醒',
      body: '顺序刷新',
      hour: 10,
      minute: 1,
      payload: 'duoyi://todo/68',
    );
    expect(fallback.operations, ['cancel:68', 'daily-start:1', 'daily-done:1']);

    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 10 && fallback.dailyCalls < 2; attempt++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(find.text('顺序刷新'), findsOneWidget);
    expect(fallback.operations.sublist(3), [
      'cancel:68',
      'daily-start:2',
      'daily-done:2',
    ]);
    await sink.cancel(68);
  });

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

  testWidgets('repeating popup reports second fallback registration failure', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final now = DateTime(2030, 6, 1, 10);
    final fallback = _FakeNotificationFallback()
      ..dailyError = StateError('second repeating fallback failed')
      ..failDailyCall = 2;
    final sink = ForegroundReminderPopupSink(
      contextGetter: () => navigatorKey.currentContext,
      notificationFallback: fallback,
      nowGetter: () => now,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    await sink.scheduleRepeating(
      id: 69,
      title: '每日提醒',
      body: '兜底失败',
      hour: 10,
      minute: 1,
      payload: 'duoyi://todo/69',
    );

    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 10 && fallback.dailyCalls < 2; attempt++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(fallback.dailyCalls, 2);
    expect(fallback.issues, hasLength(1));
    expect(fallback.issues.single['relatedId'], '69');
    await sink.cancel(69);
  });

  testWidgets('delayed fallback registration cannot resurrect after cancel', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final fallback = _FakeNotificationFallback()..dailyGate = Completer<void>();
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

    final schedule = sink.scheduleRepeating(
      id: 70,
      title: '旧提醒',
      body: '应取消',
      hour: 19,
      minute: 5,
    );
    await tester.pump();
    final cancel = sink.cancel(70);
    fallback.dailyGate!.complete();
    await Future.wait([schedule, cancel]);
    await tester.pumpAndSettle();

    expect(find.text('旧提醒'), findsNothing);
    expect(fallback.operations, contains('daily-done:1'));
    expect(fallback.operations.last, 'cancel:70');
    expect(fallback.cancelled, contains(70));
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
