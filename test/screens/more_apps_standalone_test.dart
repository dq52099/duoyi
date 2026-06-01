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
}
