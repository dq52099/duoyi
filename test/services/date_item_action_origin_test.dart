import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:duoyi/services/date_item_action_origin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  tearDown(() async {
    await AccountPreferenceWrites.drain();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('an operation owns its dialog and can write after confirmation', (
    tester,
  ) async {
    final harness = _Harness();
    await tester.pumpWidget(
      harness.app(
        observeRoutes: true,
        home: (_) => const Scaffold(body: Text('Source page')),
      ),
    );
    addTearDown(() => _disposeHarness(tester, harness));

    final operation = harness.createOperation();
    final dialogResult = operation.showDialog<bool>(
      (context) => AlertDialog(
        title: const Text('Owned dialog'),
        actions: [
          TextButton(
            key: const ValueKey('confirm_owned_dialog'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(operation.isCurrent(), isTrue);
    await tester.tap(find.byKey(const ValueKey('confirm_owned_dialog')));
    await tester.pumpAndSettle();
    expect(await dialogResult, isTrue);
    expect(operation.isCurrent(), isTrue);

    await harness.provider.addItem(
      CountdownItem(
        id: 'after-confirm',
        title: 'Write after confirm',
        targetDate: DateTime.now().add(const Duration(days: 4)),
      ),
      canWrite: operation.isCurrent,
    );
    expect(harness.provider.items.single.title, 'Write after confirm');
  });

  testWidgets(
    'a covering route cancels permanently and only removes the owned dialog',
    (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(
        harness.app(
          observeRoutes: true,
          home: (_) => const Scaffold(body: Text('Source page')),
        ),
      );
      addTearDown(() => _disposeHarness(tester, harness));

      final operation = harness.createOperation();
      final dialogResult = operation.showDialog<void>(
        (_) => const AlertDialog(title: Text('Owned dialog')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Owned dialog'), findsOneWidget);

      harness.navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Unrelated route'))),
        ),
      );
      await tester.pumpAndSettle();

      expect(operation.isCurrent(), isFalse);
      expect(find.text('Unrelated route'), findsOneWidget);
      expect(find.text('Owned dialog'), findsNothing);
      await dialogResult;

      harness.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Source page'), findsOneWidget);
      expect(operation.isCurrent(), isFalse);
    },
  );

  testWidgets(
    'provider reset removes its owned dialog and invalidates the operation',
    (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(
        harness.app(
          observeRoutes: true,
          home: (_) => const Scaffold(body: Text('Source page')),
        ),
      );
      addTearDown(() => _disposeHarness(tester, harness));

      final operation = harness.createOperation();
      final dialogResult = operation.showDialog<void>(
        (_) => const AlertDialog(title: Text('Owned dialog')),
      );
      await tester.pumpAndSettle();
      harness.provider.resetLocalState();
      await tester.pumpAndSettle();

      expect(operation.isCurrent(), isFalse);
      expect(find.text('Owned dialog'), findsNothing);
      expect(find.text('Source page'), findsOneWidget);
      await dialogResult;
    },
  );

  testWidgets(
    'provider replacement invalidates an operation on the same route',
    (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(
        harness.app(home: (_) => const Scaffold(body: Text('Source page'))),
      );
      addTearDown(() => _disposeHarness(tester, harness));

      final operation = harness.createOperation();
      expect(operation.isCurrent(), isTrue);
      final replacement = CountdownProvider();
      harness.replaceProvider(replacement);
      await tester.pump();

      expect(harness.sourceContext!.mounted, isTrue);
      expect(find.text('Source page'), findsOneWidget);
      expect(operation.isCurrent(), isFalse);
    },
  );

  testWidgets('a lock invalidates the operation even after unlocking again', (
    tester,
  ) async {
    final harness = _Harness();
    final lock = _TestLock();
    await tester.pumpWidget(
      harness.app(
        lock: lock,
        home: (_) => const Scaffold(body: Text('Source page')),
      ),
    );
    addTearDown(() async {
      await _disposeHarness(tester, harness);
      lock.dispose();
    });

    final operation = harness.createOperation();
    lock.setLocked(true);
    expect(operation.isCurrent(), isFalse);
    lock.setLocked(false);
    expect(operation.isCurrent(), isFalse);
  });

  testWidgets(
    'reverse dismissal permits a new operation; a later forward cover cancels it',
    (tester) async {
      final harness = _Harness();
      DateItemOperation? operation;
      await tester.pumpWidget(
        harness.app(
          home: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open_external_dialog'),
              onPressed: () => Navigator.of(context).push<void>(
                DialogRoute<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Transient dialog'),
                    actions: [
                      TextButton(
                        key: const ValueKey('pop_and_create_operation'),
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          operation = harness.createOperation();
                        },
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Text('Open dialog'),
            ),
          ),
        ),
      );
      addTearDown(() => _disposeHarness(tester, harness));

      await tester.tap(find.byKey(const ValueKey('open_external_dialog')));
      await tester.pumpAndSettle();
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('pop_and_create_operation')),
          )
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 20));

      expect(operation, isNotNull);
      expect(operation!.isCurrent(), isTrue);
      await tester.pumpAndSettle();
      expect(operation!.isCurrent(), isTrue);

      harness.navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Forward cover')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(operation!.isCurrent(), isFalse);
      await tester.pumpAndSettle();
      harness.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(operation!.isCurrent(), isFalse);
    },
  );
}

Future<void> _disposeHarness(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  harness.dispose();
}

class _Harness {
  final _initialProvider = CountdownProvider();
  late final ValueNotifier<CountdownProvider> _activeProvider =
      ValueNotifier<CountdownProvider>(_initialProvider);
  final navigator = GlobalKey<NavigatorState>();
  final routeGate = AppAccessRouteGate();
  final operations = <DateItemOperation>[];
  final providers = <CountdownProvider>[];
  BuildContext? sourceContext;

  CountdownProvider get provider => _activeProvider.value;

  Widget app({
    required WidgetBuilder home,
    bool observeRoutes = false,
    AppLockProvider? lock,
  }) {
    final app = MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: observeRoutes
          ? <NavigatorObserver>[routeGate]
          : const <NavigatorObserver>[],
      home: Builder(
        builder: (context) {
          sourceContext = context;
          return home(context);
        },
      ),
    );
    return ValueListenableBuilder<CountdownProvider>(
      valueListenable: _activeProvider,
      child: app,
      builder: (context, provider, child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<CountdownProvider>.value(value: provider),
          if (lock != null)
            ChangeNotifierProvider<AppLockProvider>.value(value: lock),
        ],
        child: child!,
      ),
    );
  }

  DateItemOperation createOperation() {
    final context = sourceContext;
    if (context == null) throw StateError('Source route has not built yet');
    final operation = DateItemOperation(
      DateItemActionOrigin.countdown(context),
    );
    operations.add(operation);
    return operation;
  }

  void replaceProvider(CountdownProvider provider) {
    providers.add(provider);
    _activeProvider.value = provider;
  }

  void dispose() {
    for (final operation in operations) {
      operation.dispose();
    }
    routeGate.dispose();
    _activeProvider.dispose();
    _initialProvider.dispose();
    for (final provider in providers) {
      provider.dispose();
    }
  }
}

class _TestLock extends AppLockProvider {
  bool _locked = false;

  @override
  bool get isLocked => _locked;

  void setLocked(bool locked) {
    _locked = locked;
    notifyListeners();
  }
}
