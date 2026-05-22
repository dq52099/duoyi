import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/time_audit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('TimeAuditScreen supports manual add, edit and delete', (
    tester,
  ) async {
    final provider = TimeAuditProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<TimeAuditProvider>.value(
        value: provider,
        child: const MaterialApp(home: TimeAuditScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('补记'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '补记阅读');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(provider.entries, hasLength(1));
    expect(provider.entries.single.title, '补记阅读');
    expect(find.text('补记阅读'), findsOneWidget);

    await tester.tap(find.text('补记阅读'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '修改阅读');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(provider.entries, hasLength(1));
    expect(provider.entries.single.title, '修改阅读');
    expect(find.text('修改阅读'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(provider.entries, isEmpty);
    expect(find.text('今日暂无时间记录'), findsOneWidget);
  });

  testWidgets(
    'TimeAuditScreen exposes timeline category calendar and trend views',
    (tester) async {
      final provider = TimeAuditProvider();
      final now = DateTime.now();
      await provider.add(
        TimeEntry(
          title: '深度工作',
          startAt: DateTime(now.year, now.month, now.day, 9),
          endAt: DateTime(now.year, now.month, now.day, 10),
          category: TimeEntryCategory.work,
          source: TimeEntrySource.manual,
        ),
      );
      await provider.add(
        TimeEntry(
          title: '阅读',
          startAt: DateTime(now.year, now.month, now.day, 11),
          endAt: DateTime(now.year, now.month, now.day, 11, 30),
          category: TimeEntryCategory.study,
          source: TimeEntrySource.todo,
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<TimeAuditProvider>.value(
          value: provider,
          child: const MaterialApp(home: TimeAuditScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('今日时间线'), findsOneWidget);
      expect(find.text('深度工作'), findsOneWidget);
      expect(find.byTooltip('复制报告'), findsOneWidget);

      await tester.tap(find.text('分类'));
      await tester.pumpAndSettle();
      expect(find.text('分类视图'), findsOneWidget);
      expect(find.text('来源分布'), findsOneWidget);
      expect(find.text('工作'), findsWidgets);
      expect(find.text('学习'), findsWidgets);

      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();
      expect(find.text('日历视图'), findsOneWidget);
      expect(find.text('${now.month}月${now.day}日'), findsOneWidget);

      await tester.tap(find.text('趋势'));
      await tester.pumpAndSettle();
      expect(find.text('趋势视图'), findsOneWidget);
      expect(find.text('${now.month}/${now.day}'), findsOneWidget);
    },
  );

  testWidgets('TimeAuditScreen range switch reveals week and month entries', (
    tester,
  ) async {
    final provider = TimeAuditProvider();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekOtherDay = now.weekday == DateTime.monday
        ? today.add(const Duration(days: 1))
        : today.subtract(const Duration(days: 1));
    final monthOtherDay = today.day == 1
        ? today.add(const Duration(days: 1))
        : today.subtract(const Duration(days: 1));
    await provider.add(
      TimeEntry(
        title: '今日专注',
        startAt: today.add(const Duration(hours: 9)),
        endAt: today.add(const Duration(hours: 10)),
        category: TimeEntryCategory.focus,
        source: TimeEntrySource.pomodoro,
      ),
    );
    await provider.add(
      TimeEntry(
        title: '周内复盘',
        startAt: weekOtherDay.add(const Duration(hours: 20)),
        endAt: weekOtherDay.add(const Duration(hours: 21)),
        category: TimeEntryCategory.other,
        source: TimeEntrySource.manual,
      ),
    );
    await provider.add(
      TimeEntry(
        title: '月内整理',
        startAt: monthOtherDay.add(const Duration(hours: 18)),
        endAt: monthOtherDay.add(const Duration(hours: 19)),
        category: TimeEntryCategory.life,
        source: TimeEntrySource.manual,
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<TimeAuditProvider>.value(
        value: provider,
        child: const MaterialApp(home: TimeAuditScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日时间线'), findsOneWidget);
    expect(find.text('今日专注'), findsOneWidget);
    expect(find.text('周内复盘'), findsNothing);
    expect(find.text('月内整理'), findsNothing);

    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();

    expect(find.text('本周时间线'), findsOneWidget);
    expect(find.text('今日专注'), findsOneWidget);
    expect(find.text('周内复盘'), findsOneWidget);

    await tester.tap(find.text('本月'));
    await tester.pumpAndSettle();

    expect(find.text('本月时间线'), findsOneWidget);
    expect(find.text('今日专注'), findsOneWidget);
    expect(find.text('月内整理'), findsOneWidget);
  });

  testWidgets('TimeAuditScreen localizes primary UI in English', (
    tester,
  ) async {
    I18n.setLocale(AppLocale.en);
    final provider = TimeAuditProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<TimeAuditProvider>.value(
        value: provider,
        child: const MaterialApp(home: TimeAuditScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Time Tracking'), findsOneWidget);
    expect(find.byTooltip('Copy report'), findsOneWidget);
    expect(find.text('Add entry'), findsOneWidget);
    expect(find.text('Today has no time entries'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Trend'), findsOneWidget);

    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();

    expect(find.text('Add time entry'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Category'), findsWidgets);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
    expect(find.text('Minutes'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
  });
}
