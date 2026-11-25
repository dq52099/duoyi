import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:duoyi/widgets/app_access_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final modal in ['page', 'dialog', 'sheet']) {
    testWidgets('lock covers $modal and retains its draft, focus and route', (
      tester,
    ) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app);
      fixture.open(modal);
      await tester.pumpAndSettle();
      final originalRoute = fixture.routes.currentRoute;
      final originalCount = fixture.routes.registeredRouteCount;
      await tester.tap(find.byKey(const ValueKey('draft')));
      await tester.enterText(find.byKey(const ValueKey('draft')), 'kept draft');
      fixture.controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 6,
      );
      final focus = FocusManager.instance.primaryFocus!;

      fixture.setAccess(locked: true);
      expect(
        (originalRoute! as ModalRoute).popDisposition,
        RoutePopDisposition.doNotPop,
      );
      await tester.pumpAndSettle();
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.byKey(const ValueKey('draft')).hitTestable(), findsNothing);
      expect(focus.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await fixture.navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(fixture.routes.currentRoute, same(originalRoute));
      expect(fixture.routes.registeredRouteCount, originalCount);

      fixture.setAccess();
      await tester.pumpAndSettle();
      expect(fixture.routes.currentRoute, same(originalRoute));
      expect(find.byKey(const ValueKey('draft')).hitTestable(), findsOneWidget);
      expect(fixture.controller.text, 'kept draft');
      expect(
        fixture.controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 6),
      );
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'update takes priority, and unlocking preserves page pop guards',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app);
      fixture.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const PopScope(
            canPop: false,
            child: Scaffold(body: Text('Unsaved')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final route = fixture.routes.currentRoute! as ModalRoute;
      fixture.setAccess(locked: true, update: true);
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Unlock'), findsNothing);
      expect(route.popDisposition, RoutePopDisposition.doNotPop);
      fixture.setAccess(locked: true);
      await tester.pumpAndSettle();
      expect(find.text('Unlock'), findsOneWidget);
      fixture.setAccess();
      await tester.pumpAndSettle();
      expect(route.popDisposition, RoutePopDisposition.doNotPop);
      await fixture.navigator.currentState!.maybePop();
      expect(fixture.routes.currentRoute, same(route));
      fixture.routes.dispose();
      expect(fixture.routes.registeredRouteCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account changes prevent restoring an old editor focus', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app);
    fixture.open('page');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('draft')));
    final focus = FocusManager.instance.primaryFocus!;
    fixture.setAccess(locked: true);
    await tester.pumpAndSettle();
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    fixture.setAccess();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Fixture {
  final navigator = GlobalKey<NavigatorState>();
  final routes = AppAccessRouteGate();
  final controller = TextEditingController();
  final access = ValueNotifier((locked: false, update: false));

  void setAccess({bool locked = false, bool update = false}) {
    routes.setBlocked(locked || update);
    access.value = (locked: locked, update: update);
  }

  Widget get editor =>
      TextField(key: const ValueKey('draft'), controller: controller);

  void open(String modal) {
    final context = navigator.currentContext!;
    switch (modal) {
      case 'page':
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => Scaffold(body: editor)),
        );
      case 'dialog':
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(content: editor),
        );
      case 'sheet':
        showModalBottomSheet<void>(
          context: context,
          builder: (_) =>
              Padding(padding: const EdgeInsets.all(24), child: editor),
        );
    }
  }

  Widget get app => MaterialApp(
    navigatorKey: navigator,
    navigatorObservers: [routes],
    home: const Scaffold(body: Text('Home')),
    builder: (context, child) => ValueListenableBuilder(
      valueListenable: access,
      builder: (context, value, _) => AppAccessLayer(
        locked: value.locked,
        mustUpdate: value.update,
        routes: routes,
        lockOverlay: const Center(child: Text('Unlock')),
        updateOverlay: value.update
            ? const Positioned.fill(
                child: Material(child: Center(child: Text('Update required'))),
              )
            : const SizedBox.shrink(),
        child: child!,
      ),
    ),
  );

  void dispose() {
    routes.dispose();
    controller.dispose();
    access.dispose();
  }
}
