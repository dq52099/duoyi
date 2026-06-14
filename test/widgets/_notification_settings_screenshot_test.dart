import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/notification_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture notification settings alignment screenshots', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final screenshotKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => NotificationService()),
            ChangeNotifierProvider(create: (_) => PreferencesProvider()),
          ],
          child: const MaterialApp(home: NotificationSettingsScreen()),
        ),
      ),
    );
    await tester.pump();

    await _jumpUntilBuilt(
      tester,
      find.byKey(const ValueKey('daily_reminder_slot_0_header')),
    );
    await _capture(
      screenshotKey,
      'evidence/screenshots/notification-settings-after-align-daily-320.png',
    );

    final reportHeader = find.byKey(
      const ValueKey('report_reminder_daily_header'),
    );
    await _jumpUntilBuilt(tester, reportHeader);
    await tester.tap(reportHeader);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await _capture(
      screenshotKey,
      'evidence/screenshots/notification-settings-after-align-report-320.png',
    );
  });
}

Future<void> _jumpUntilBuilt(WidgetTester tester, Finder finder) async {
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position;
  for (
    var offset = position.minScrollExtent;
    offset <= position.maxScrollExtent;
    offset += 260
  ) {
    position.jumpTo(offset);
    await tester.pump(const Duration(milliseconds: 50));
    if (tester.any(finder)) return;
  }
  position.jumpTo(position.maxScrollExtent);
  await tester.pump(const Duration(milliseconds: 50));
  expect(finder, findsOneWidget);
}

Future<void> _capture(GlobalKey key, String path) async {
  await Directory('evidence/screenshots').create(recursive: true);
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(data!.buffer.asUint8List());
}
