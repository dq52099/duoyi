import 'dart:io';

import 'package:duoyi/services/web_lifecycle_recovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(WebLifecycleRecovery.resetForTesting);

  testWidgets('visual recovery schedules repaint and cleans up follow-up timer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Duoyi'))),
      ),
    );
    await tester.pumpAndSettle();

    WebLifecycleRecovery.install();
    WebLifecycleRecovery.requestVisualRecovery();
    expect(WebLifecycleRecovery.debugRepaintRequestCount, 1);
    expect(WebLifecycleRecovery.debugHasPendingSettleTimer, isTrue);

    await tester.pump(const Duration(milliseconds: 120));
    expect(WebLifecycleRecovery.debugHasPendingSettleTimer, isFalse);

    WebLifecycleRecovery.requestVisualRecovery();
    expect(WebLifecycleRecovery.debugHasPendingSettleTimer, isTrue);
    WebLifecycleRecovery.uninstall();
    expect(WebLifecycleRecovery.debugHasPendingSettleTimer, isFalse);
  });

  test('lib/main.dart wires WebLifecycleRecovery across init/resume/dispose', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    expect(mainSource, contains("import 'services/web_lifecycle_recovery.dart';"));
    expect(mainSource, contains('WebLifecycleRecovery.install();'));
    expect(mainSource, contains('WebLifecycleRecovery.uninstall();'));
    expect(mainSource, contains('WebLifecycleRecovery.onAppResumed();'));
  });
}
