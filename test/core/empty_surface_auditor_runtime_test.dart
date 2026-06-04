import 'package:duoyi/core/empty_surface_auditor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('runtimeAudit detects visible placeholder copy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(children: [Text('正常内容'), Text('TODO: 这里还是占位功能')]),
        ),
      ),
    );

    final context = tester.element(find.byType(Scaffold));
    final report = await EmptySurfaceAuditor.runtimeAudit(context);

    expect(report.knownEntries, isEmpty);
    expect(report.runtimeFindings, hasLength(1));
    expect(report.runtimeFindings.single, contains('TODO: 这里还是占位功能'));
    expect(report.totalIssues, 1);
  });
}
