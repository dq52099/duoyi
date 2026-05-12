import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/time_audit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
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
}
