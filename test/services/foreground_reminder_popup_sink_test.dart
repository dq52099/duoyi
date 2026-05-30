import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/services/foreground_reminder_popup_sink.dart';

void main() {
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
      when: DateTime.now().add(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
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
      when: now.add(const Duration(milliseconds: 20)),
    );
    await sink.scheduleOnce(
      id: 7,
      title: '提醒',
      body: '新提醒',
      when: now.add(const Duration(milliseconds: 30)),
    );

    await tester.pump(const Duration(milliseconds: 40));
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
      when: DateTime.now().add(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(find.text('已显示'), findsOneWidget);

    await sink.scheduleOnce(
      id: 9,
      title: '提醒',
      body: '替换后',
      when: DateTime.now().add(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    expect(find.text('已显示'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
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
      when: now.add(const Duration(milliseconds: 10)),
      payload: 'duoyi://todo/a',
    );
    await sink.scheduleOnce(
      id: 102,
      title: '提醒',
      body: '重复内容',
      when: now.add(const Duration(milliseconds: 12)),
      payload: 'duoyi://todo/a',
    );

    await tester.pump(const Duration(milliseconds: 20));
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
