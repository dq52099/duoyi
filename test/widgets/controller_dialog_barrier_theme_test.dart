import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/widgets/controller_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = [
    (
      name: 'default iOS brand',
      theme: AppBrands.defaultBrand.theme,
      local: null,
      expected: Colors.black.withValues(alpha: 0.36),
    ),
    (
      name: 'liquid glass brand',
      theme: AppBrands.byId('liquidGlass').theme,
      local: null,
      expected: Colors.black.withValues(alpha: 0.36),
    ),
    (
      name: 'dark brand',
      theme: AppBrands.byId('starRail').theme,
      local: null,
      expected: Colors.black.withValues(alpha: 0.56),
    ),
    (
      name: 'local DialogTheme override',
      theme: AppBrands.defaultBrand.theme,
      local: const Color(0x55123456),
      expected: const Color(0x55123456),
    ),
    (
      name: 'framework fallback without a themed barrier',
      theme: ThemeData(dialogTheme: const DialogThemeData()),
      local: null,
      expected: Colors.black54,
    ),
  ];

  for (final scenario in cases) {
    testWidgets('controlled dialog preserves ${scenario.name} barrier', (
      tester,
    ) async {
      String? result;
      Widget dialog(BuildContext context) => AlertDialog(
        title: const Text('Dialog'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('closed'),
            child: const Text('Close'),
          ),
        ],
      );

      final launchers = Builder(
        builder: (context) => Column(
          children: [
            TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: dialog,
                );
              },
              child: const Text('Reference'),
            ),
            TextButton(
              onPressed: () async {
                result = await showControllerDialog<String>(
                  context: context,
                  controllers: const [],
                  builder: dialog,
                );
              },
              child: const Text('Controlled'),
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: scenario.theme,
          home: Scaffold(
            body: scenario.local == null
                ? launchers
                : DialogTheme(
                    data: DialogThemeData(barrierColor: scenario.local),
                    child: launchers,
                  ),
          ),
        ),
      );

      for (final launcher in ['Reference', 'Controlled']) {
        result = null;
        await tester.tap(find.text(launcher));
        await tester.pumpAndSettle();
        final route = ModalRoute.of(tester.element(find.byType(AlertDialog)))!;
        expect(route.barrierColor, scenario.expected, reason: launcher);
        expect(route.barrierDismissible, isTrue);
        final barrier = tester.widget<AnimatedModalBarrier>(
          find.byType(AnimatedModalBarrier),
        );
        expect(barrier.color.value, scenario.expected, reason: launcher);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(result, 'closed');
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
