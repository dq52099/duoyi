import 'dart:async';

import 'package:duoyi/services/widget_calendar_route_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('replaces visible owned date routes and showSection pops one', (
    tester,
  ) async {
    final controller = WidgetCalendarRouteController();
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _RouteStackObserver();

    await tester.pumpWidget(
      _singleNavigatorApp(navigatorKey: navigatorKey, observer: observer),
    );
    await tester.pumpAndSettle();

    final navigator = navigatorKey.currentState!;
    final section = observer.routes.single;
    final firstDate = _pageRoute('/date/2026-10-11');
    controller.open(navigator, firstDate);
    await tester.pumpAndSettle();

    expect(observer.names, ['/', '/date/2026-10-11']);
    expect(firstDate.isCurrent, isTrue);

    final secondDate = _pageRoute('/date/2026-10-12');
    controller.open(navigator, secondDate);
    await tester.pumpAndSettle();

    expect(observer.names, ['/', '/date/2026-10-12']);
    expect(firstDate.isActive, isFalse);
    expect(secondDate.isCurrent, isTrue);

    final thirdDate = _pageRoute('/date/2026-10-13');
    controller.open(navigator, thirdDate);
    await tester.pumpAndSettle();

    expect(observer.names, ['/', '/date/2026-10-13']);
    expect(
      observer.routes,
      hasLength(2),
      reason: 'replacement must not grow the stack',
    );
    expect(secondDate.isActive, isFalse);
    expect(thirdDate.isCurrent, isTrue);

    expect(controller.showSection(navigator), isTrue);
    await tester.pumpAndSettle();
    expect(observer.routes, [section]);
    expect(thirdDate.isActive, isFalse);
    expect(controller.showSection(navigator), isFalse);
  });

  testWidgets(
    'preserves an unrelated dialog and tracks an older date route below it',
    (tester) async {
      final controller = WidgetCalendarRouteController();
      final navigatorKey = GlobalKey<NavigatorState>();
      final observer = _RouteStackObserver();

      await tester.pumpWidget(
        _singleNavigatorApp(navigatorKey: navigatorKey, observer: observer),
      );
      await tester.pumpAndSettle();

      final navigator = navigatorKey.currentState!;
      final section = observer.routes.single;
      final olderDate = _pageRoute('/date/2026-10-11');
      controller.open(navigator, olderDate);
      await tester.pumpAndSettle();

      final dialog = DialogRoute<void>(
        context: navigator.context,
        settings: const RouteSettings(name: '/draft-dialog'),
        builder: (_) => const AlertDialog(title: Text('Unrelated draft')),
      );
      unawaited(navigator.push<void>(dialog));
      await tester.pumpAndSettle();
      expect(dialog.isCurrent, isTrue);

      final newerDate = _pageRoute('/date/2026-10-12');
      controller.open(navigator, newerDate);
      await tester.pumpAndSettle();
      expect(observer.names, [
        '/',
        '/date/2026-10-11',
        '/draft-dialog',
        '/date/2026-10-12',
      ]);
      expect(dialog.isActive, isTrue);
      expect(newerDate.isCurrent, isTrue);

      navigator.pop<void>();
      await tester.pumpAndSettle();
      expect(newerDate.isActive, isFalse);
      expect(dialog.isCurrent, isTrue);
      expect(olderDate.isActive, isTrue);
      expect(controller.showSection(navigator), isFalse);
      expect(observer.routes, [section, olderDate, dialog]);

      navigator.pop<void>();
      await tester.pumpAndSettle();
      expect(dialog.isActive, isFalse);
      expect(olderDate.isCurrent, isTrue);

      expect(controller.showSection(navigator), isTrue);
      await tester.pumpAndSettle();
      expect(observer.routes, [section]);
      expect(olderDate.isActive, isFalse);
    },
  );

  testWidgets('owned routes are isolated by NavigatorState', (tester) async {
    final controller = WidgetCalendarRouteController();
    final firstNavigatorKey = GlobalKey<NavigatorState>();
    final secondNavigatorKey = GlobalKey<NavigatorState>();
    final firstObserver = _RouteStackObserver();
    final secondObserver = _RouteStackObserver();

    await tester.pumpWidget(
      _twoNavigatorApp(
        firstKey: firstNavigatorKey,
        secondKey: secondNavigatorKey,
        firstObserver: firstObserver,
        secondObserver: secondObserver,
      ),
    );
    await tester.pumpAndSettle();

    final firstNavigator = firstNavigatorKey.currentState!;
    final secondNavigator = secondNavigatorKey.currentState!;
    final firstDate = _pageRoute('/first/date');
    final secondDate = _pageRoute('/second/date');
    controller.open(firstNavigator, firstDate);
    controller.open(secondNavigator, secondDate);
    await tester.pumpAndSettle();

    expect(firstDate.isCurrent, isTrue);
    expect(secondDate.isCurrent, isTrue);
    expect(controller.showSection(firstNavigator), isTrue);
    await tester.pumpAndSettle();

    expect(firstDate.isActive, isFalse);
    expect(secondDate.isCurrent, isTrue);
    expect(firstObserver.names, ['/first/home']);
    expect(secondObserver.names, ['/second/home', '/second/date']);

    expect(controller.showSection(secondNavigator), isTrue);
    await tester.pumpAndSettle();
    expect(secondDate.isActive, isFalse);
    expect(secondObserver.names, ['/second/home']);
  });

  testWidgets('disposed Navigator ignores open and showSection', (
    tester,
  ) async {
    final controller = WidgetCalendarRouteController();
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _RouteStackObserver();

    await tester.pumpWidget(
      _singleNavigatorApp(navigatorKey: navigatorKey, observer: observer),
    );
    await tester.pumpAndSettle();

    final disposedNavigator = navigatorKey.currentState!;
    final ownedDate = _pageRoute('/date/2026-10-11');
    controller.open(disposedNavigator, ownedDate);
    await tester.pumpAndSettle();
    expect(ownedDate.isCurrent, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposedNavigator.mounted, isFalse);

    final rejectedDate = _pageRoute('/date/2026-10-12');
    controller.open(disposedNavigator, rejectedDate);

    expect(rejectedDate.isActive, isFalse);
    expect(controller.showSection(disposedNavigator), isFalse);
    expect(tester.takeException(), isNull);
  });
}

Widget _singleNavigatorApp({
  required GlobalKey<NavigatorState> navigatorKey,
  required _RouteStackObserver observer,
}) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: [observer],
    home: const Scaffold(body: Text('Calendar section')),
  );
}

Widget _twoNavigatorApp({
  required GlobalKey<NavigatorState> firstKey,
  required GlobalKey<NavigatorState> secondKey,
  required _RouteStackObserver firstObserver,
  required _RouteStackObserver secondObserver,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Navigator(
              key: firstKey,
              observers: [firstObserver],
              onGenerateRoute: (_) => _pageRoute('/first/home'),
            ),
          ),
          Expanded(
            child: Navigator(
              key: secondKey,
              observers: [secondObserver],
              onGenerateRoute: (_) => _pageRoute('/second/home'),
            ),
          ),
        ],
      ),
    ),
  );
}

PageRoute<void> _pageRoute(String name) {
  return PageRouteBuilder<void>(
    settings: RouteSettings(name: name),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => Scaffold(body: Text(name)),
  );
}

class _RouteStackObserver extends NavigatorObserver {
  final List<Route<dynamic>> routes = [];

  List<String?> get names =>
      routes.map((route) => route.settings.name).toList();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == null) {
      if (newRoute != null) routes.add(newRoute);
      return;
    }
    final index = routes.indexOf(oldRoute);
    if (newRoute == null) {
      routes.remove(oldRoute);
    } else if (index < 0) {
      routes.add(newRoute);
    } else {
      routes[index] = newRoute;
    }
  }
}
