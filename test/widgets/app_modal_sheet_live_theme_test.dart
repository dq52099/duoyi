import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localPrimary = Color(0xff123456);
const _draft = TextEditingValue(
  text: 'Retained sheet draft',
  selection: TextSelection(baseOffset: 2, extentOffset: 8),
);

class _Notifications extends ThemeProvider {
  void unrelatedChange() => notifyListeners();
}

// A captured inherited theme that Material does not replace with its own defaults.
class _MarkerTheme extends InheritedTheme {
  const _MarkerTheme({required super.child});

  static int? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MarkerTheme>() == null
      ? null
      : 31;

  @override
  Widget wrap(BuildContext context, Widget child) => _MarkerTheme(child: child);

  @override
  bool updateShouldNotify(_MarkerTheme oldWidget) => false;
}

class _DraftSheet extends StatefulWidget {
  final TextEditingController controller;
  final ScrollController scroll;
  const _DraftSheet(this.controller, this.scroll);

  @override
  State<_DraftSheet> createState() => _DraftSheetState();
}

class _DraftSheetState extends State<_DraftSheet> {
  @override
  Widget build(BuildContext context) => AppModalSheet(
    title: 'Draft sheet',
    scrollController: widget.scroll,
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop('closed'),
        child: const Text('Close sheet'),
      ),
    ],
    child: Column(
      children: [
        TextField(controller: widget.controller),
        const SizedBox(height: 1200),
        const Text('End of retained content'),
      ],
    ),
  );
}

Widget _app(
  ThemeData theme,
  TextEditingController controller,
  ScrollController scroll,
  ValueChanged<String?> result,
) => MaterialApp(
  theme: theme,
  home: Theme(
    data: theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(primary: _localPrimary),
    ),
    child: AppSecondaryControlTheme(
      child: _MarkerTheme(
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result(
                await showAppModalSheet<String>(
                  context: context,
                  builder: (_) => _DraftSheet(controller, scroll),
                ),
              ),
              child: const Text('Open sheet'),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 50),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

Future<void> _closeSheet(WidgetTester tester) async {
  final scrollable = find
      .descendant(
        of: find.byType(AppModalSheet),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    find.text('Close sheet'),
    150,
    scrollable: scrollable,
  );
  await tester.ensureVisible(find.text('Close sheet'));
  await _settle(tester);
  expect(find.text('Close sheet').hitTestable(), findsOneWidget);
  await tester.tap(find.text('Close sheet'));
  await _settle(tester);
}

void main() {
  testWidgets('provider-less sheet retains captured local themes and result', (
    tester,
  ) async {
    final controller = TextEditingController();
    final scroll = ScrollController();
    String? result;
    try {
      await tester.pumpWidget(
        _app(
          AppBrands.defaultBrand.theme,
          controller,
          scroll,
          (v) => result = v,
        ),
      );
      await tester.tap(find.text('Open sheet'));
      await _settle(tester);
      final field = tester.element(find.byType(TextField));
      expect(Theme.of(field).colorScheme.primary, _localPrimary);
      expect(_MarkerTheme.of(field), 31);
      controller.value = _draft;
      await tester.pump();
      await _closeSheet(tester);
      expect(result, 'closed');
      expect(find.byType(_DraftSheet), findsNothing);
      expect(controller.value, _draft);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      controller.dispose();
      scroll.dispose();
    }
  });

  testWidgets('open sheet follows brand and retains local theme on roundtrip', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'active_brand': 'defaultBrand',
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      'theme_shop_state': jsonEncode({
        'activeBrand': 'defaultBrand',
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
    });
    late final _Notifications theme;
    await tester.runAsync(() async {
      theme = _Notifications();
      await theme.loadFromStorage().timeout(const Duration(seconds: 5));
    });
    final controller = TextEditingController();
    final scroll = ScrollController();
    String? result;
    try {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: Consumer<ThemeProvider>(
            builder: (_, active, _) =>
                _app(active.brand.theme, controller, scroll, (v) => result = v),
          ),
        ),
      );
      await tester.tap(find.text('Open sheet'));
      await _settle(tester);
      final sheet = find.byType(_DraftSheet);
      final state = tester.state(sheet);
      final route = ModalRoute.of(tester.element(sheet));
      controller.value = _draft;
      await tester.pump();
      scroll.jumpTo(36);
      await tester.pump();
      expect(scroll.offset, 36);
      final opening = Theme.of(tester.element(find.byType(TextField)));
      expect(opening.colorScheme.primary, _localPrimary);
      expect(appSurfaceStyleOf(tester.element(sheet)), AppSurfaceStyle.ios);
      theme.unrelatedChange();
      await _settle(tester);
      expect(
        Theme.of(tester.element(find.byType(TextField))).colorScheme.primary,
        _localPrimary,
      );
      await tester.runAsync(() async {
        expect(await theme.setBrand('liquidGlass'), isTrue);
      });
      await _settle(tester);
      final switched = tester.element(find.byType(TextField));
      expect(
        Theme.of(switched).colorScheme.primary,
        AppBrands.byId('liquidGlass').theme.colorScheme.primary,
      );
      expect(appSurfaceStyleOf(switched), AppSurfaceStyle.liquidGlass);
      expect(_MarkerTheme.of(switched), 31);
      expect(
        Theme.of(switched).inputDecorationTheme.prefixIconConstraints,
        opening.inputDecorationTheme.prefixIconConstraints,
      );
      expect(tester.state(sheet), same(state));
      expect(ModalRoute.of(tester.element(sheet)), same(route));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        same(controller),
      );
      expect(controller.value, _draft);
      expect(scroll.offset, 36);
      await tester.runAsync(() async {
        expect(await theme.setBrand('defaultBrand'), isTrue);
      });
      await _settle(tester);
      final restored = tester.element(find.byType(TextField));
      expect(Theme.of(restored).colorScheme.primary, _localPrimary);
      expect(appSurfaceStyleOf(restored), AppSurfaceStyle.ios);
      expect(_MarkerTheme.of(restored), 31);
      expect(tester.state(sheet), same(state));
      expect(controller.value, _draft);
      expect(scroll.offset, 36);
      await _closeSheet(tester);
      expect(result, 'closed');
      expect(find.byType(_DraftSheet), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      controller.dispose();
      scroll.dispose();
      theme.dispose();
    }
  });
}
