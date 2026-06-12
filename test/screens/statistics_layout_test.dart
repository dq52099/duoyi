import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('统计页 KPI 网格适配 320/390/430 和桌面宽度', (tester) async {
    addTearDown(tester.view.reset);

    for (final scenario in const [
      (width: 320.0, expectedColumns: 1),
      (width: 390.0, expectedColumns: 2),
      (width: 430.0, expectedColumns: 2),
      (width: 900.0, expectedColumns: 3),
    ]) {
      tester.view.physicalSize = Size(scenario.width, 760);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(_wrapStatistics());
      await tester.pump();

      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('statistics_kpi_grid')),
      );
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(
        delegate.crossAxisCount,
        scenario.expectedColumns,
        reason: 'width=${scenario.width}',
      );
      expect(tester.takeException(), isNull, reason: 'width=${scenario.width}');
    }
  });
}

Widget _wrapStatistics() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => DiaryProvider()),
      ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
      ChangeNotifierProvider(create: (_) => AiService()),
    ],
    child: const MaterialApp(home: StatisticsScreen()),
  );
}
