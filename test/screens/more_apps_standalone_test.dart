import 'package:duoyi/screens/more_apps_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'MoreApplicationsScreen standalone route renders without provider black screen',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MoreApplicationsScreen(visibleBottomNavTabs: [0, 1, 2, 6]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MoreApplicationsScreen), findsOneWidget);
      expect(find.text('更多应用'), findsOneWidget);
      expect(find.text('隐藏入口'), findsOneWidget);
      expect(find.text('日历'), findsOneWidget);
      expect(find.text('小组件'), findsOneWidget);
      expect(find.text('倒数日'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('MoreApplicationsScreen hidden app grid fits 200-320px widths', (
    tester,
  ) async {
    await _pumpMoreApps(tester, width: 200);

    var grid = tester.widget<GridView>(find.byType(GridView));
    var delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 1);
    expect(find.text('日历'), findsOneWidget);
    expect(find.text('小组件'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pumpMoreApps(tester, width: 320);

    grid = tester.widget<GridView>(find.byType(GridView));
    delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(find.text('日历'), findsOneWidget);
    expect(find.text('小组件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpMoreApps(WidgetTester tester, {required double width}) async {
  await tester.binding.setSurfaceSize(Size(width, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    const MaterialApp(
      home: MoreApplicationsScreen(visibleBottomNavTabs: [0, 1, 2, 6]),
    ),
  );
  await tester.pumpAndSettle();
}
