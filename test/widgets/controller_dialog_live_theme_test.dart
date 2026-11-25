import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/controller_dialog.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TrackedController extends TextEditingController {
  int disposals = 0;

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class _ThemeNotifications extends ThemeProvider {
  void notifyWithoutChangingBrand() => notifyListeners();
}

const _localPrimary = Color(0xff123456);
const _draft = TextEditingValue(
  text: 'Uncommitted dialog draft',
  selection: TextSelection(baseOffset: 2, extentOffset: 10),
);

Widget _app(ThemeData theme, _TrackedController controller) => MaterialApp(
  theme: theme,
  home: Theme(
    data: theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(primary: _localPrimary),
    ),
    child: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showControllerDialog<void>(
              context: context,
              controllers: [controller],
              builder: (context) => AppDialog(
                title: const Text('Draft dialog'),
                content: TextField(controller: controller),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close dialog'),
                  ),
                ],
              ),
            ),
            child: const Text('Open dialog'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _closeAndCheckDisposal(
  WidgetTester tester,
  _TrackedController controller,
) async {
  await tester.tap(find.text('Close dialog'));
  await tester.pump(const Duration(milliseconds: 16));
  expect(
    controller.disposals,
    0,
    reason: 'Inputs still need their controllers during the exit animation.',
  );
  await tester.pumpAndSettle();
  expect(find.byType(AppDialog), findsNothing);
  expect(controller.disposals, 1);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'provider-less controlled dialog keeps its captured local theme',
    (tester) async {
      final controller = _TrackedController();
      try {
        await tester.pumpWidget(_app(AppBrands.defaultBrand.theme, controller));
        await tester.tap(find.text('Open dialog'));
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(AppDialog))).colorScheme.primary,
          _localPrimary,
        );
        controller.value = _draft;
        await tester.pump();
        expect(controller.value, _draft);
        await _closeAndCheckDisposal(tester, controller);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        if (controller.disposals == 0) controller.dispose();
      }
    },
  );

  testWidgets(
    'controlled dialog follows brand while retaining route and draft',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'active_brand': 'defaultBrand',
        'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        'theme_shop_state': jsonEncode({
          'activeBrand': 'defaultBrand',
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
        }),
      });
      late final _ThemeNotifications theme;
      await tester.runAsync(() async {
        theme = _ThemeNotifications();
        await theme.loadFromStorage();
      });
      final controller = _TrackedController();
      try {
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>.value(
            value: theme,
            child: Consumer<ThemeProvider>(
              builder: (_, current, _) => _app(current.brand.theme, controller),
            ),
          ),
        );
        await tester.tap(find.text('Open dialog'));
        await tester.pumpAndSettle();
        final dialog = find.byType(AppDialog);
        final element = tester.element(dialog);
        final route = ModalRoute.of(element);
        controller.value = _draft;
        await tester.pump();

        theme.notifyWithoutChangingBrand();
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(dialog)).colorScheme.primary,
          _localPrimary,
        );

        for (final brand in ['liquidGlass', 'defaultBrand']) {
          await tester.runAsync(() async {
            expect(await theme.setBrand(brand), isTrue);
          });
          await tester.pumpAndSettle();
          expect(tester.element(dialog), same(element));
          expect(ModalRoute.of(tester.element(dialog)), same(route));
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller,
            same(controller),
          );
          expect(controller.value, _draft);
          expect(controller.disposals, 0);
          expect(
            Theme.of(tester.element(dialog)).colorScheme.primary,
            brand == 'defaultBrand'
                ? _localPrimary
                : AppBrands.liquidGlass.theme.colorScheme.primary,
          );
          expect(tester.takeException(), isNull);
        }
        await _closeAndCheckDisposal(tester, controller);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        if (controller.disposals == 0) controller.dispose();
        theme.dispose();
      }
    },
  );
}
