import 'dart:async';

import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('route events are synchronous and retain access pop guards', (
    tester,
  ) async {
    final gate = AppAccessRouteGate();
    final navigatorKey = GlobalKey<NavigatorState>();
    addTearDown(gate.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [gate],
        home: const Scaffold(body: Text('Root')),
      ),
    );
    final navigator = navigatorKey.currentState!;
    final root = gate.currentRoute! as ModalRoute<dynamic>;
    final initialRevision = gate.routeRevision.value;
    final observed = <Route<dynamic>?>[];
    void observe() => observed.add(gate.currentRoute);
    gate.routeRevision.addListener(observe);

    final transient = _page('Transient');
    unawaited(navigator.push(transient));
    expect(gate.routeRevision.value, initialRevision + 1);
    expect(observed.last, same(transient));
    navigator.pop();
    expect(gate.routeRevision.value, initialRevision + 2);
    expect(observed.last, same(root));
    expect(gate.registeredRouteCount, 1);
    await tester.pumpAndSettle();

    final first = _page('First');
    unawaited(navigator.push(first));
    await tester.pumpAndSettle();
    final replacement = _page('Replacement');
    navigator.replace(oldRoute: first, newRoute: replacement);
    expect(gate.routeRevision.value, initialRevision + 4);
    expect(observed.last, same(replacement));
    await tester.pumpAndSettle();

    final top = _page('Top');
    unawaited(navigator.push(top));
    await tester.pumpAndSettle();
    navigator.removeRoute(replacement);
    expect(gate.routeRevision.value, initialRevision + 6);
    expect(observed.last, same(top));
    expect(gate.registeredRouteCount, 2);
    await tester.pumpAndSettle();

    gate.setBlocked(true);
    expect(root.popDisposition, RoutePopDisposition.doNotPop);
    expect(top.popDisposition, RoutePopDisposition.doNotPop);
    expect(await navigator.maybePop(), isTrue);
    expect(gate.currentRoute, same(top));
    expect(gate.routeRevision.value, initialRevision + 6);
    gate.setBlocked(false);
    expect(top.popDisposition, RoutePopDisposition.pop);
    await navigator.maybePop();
    expect(gate.routeRevision.value, initialRevision + 7);
    expect(gate.currentRoute, same(root));
    await tester.pumpAndSettle();

    gate.routeRevision.removeListener(observe);
    final observedCount = observed.length;
    unawaited(navigator.push(_page('Unobserved')));
    navigator.pop();
    expect(observed, hasLength(observedCount));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.dispose();
    gate.dispose();
    expect(gate.registeredRouteCount, 0);
    expect(gate.currentRoute, isNull);
    expect(tester.takeException(), isNull);
  });
}

MaterialPageRoute<void> _page(String text) =>
    MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(text)));
