import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(640, 250), const Size(320, 270)]) {
    for (final kind in ['dialog', 'sheet']) {
      testWidgets('$kind uses the actual available height at $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const Scaffold(body: Text('Home')),
          ),
        );
        final context = navigator.currentContext!;
        Widget content(BuildContext popup) {
          final action = TextButton(
            onPressed: () => Navigator.of(popup).pop(),
            child: const Text('Close'),
          );
          return kind == 'dialog'
              ? AppDialog(
                  title: const Text('Settings'),
                  content: const Text('Short window'),
                  actions: [action],
                )
              : AppModalSheet(
                  title: 'Settings',
                  actions: [action],
                  child: const Text('Short window'),
                );
        }

        if (kind == 'dialog') {
          showDialog<void>(context: context, builder: content);
        } else {
          showAppModalSheet<void>(context: context, builder: content);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Close'));
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Home'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
