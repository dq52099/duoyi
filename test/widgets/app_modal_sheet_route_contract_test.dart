import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<String> events = [];
  Route<dynamic>? pushedRoute;
  Route<dynamic>? previousRoute;

  void clear() {
    events.clear();
    pushedRoute = null;
    previousRoute = null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    events.add('observer.didPush');
    pushedRoute = route;
    this.previousRoute = previousRoute;
  }
}

Future<BuildContext> _pumpTestHost(
  WidgetTester tester, {
  required ThemeData theme,
  required Locale locale,
  NavigatorObserver? observer,
  Widget? home,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme,
      navigatorObservers: observer != null ? [observer] : const [],
      home: home ?? const Scaffold(body: Center(child: Text('Route host'))),
    ),
  );
  await tester.pumpAndSettle();
  if (observer is _RecordingNavigatorObserver) {
    observer.clear();
  }
  return tester.element(find.byType(Scaffold));
}

void main() {
  group('showAppModalSheet / createAppModalSheetRoute contract with framework showModalBottomSheet', () {
    testWidgets(
      'ModalBottomSheetRoute contract matches framework defaults for defaultBrand (light) in zh locale',
      (tester) async {
        final observer = _RecordingNavigatorObserver();
        final hostContext = await _pumpTestHost(
          tester,
          theme: AppBrands.defaultBrand.theme,
          locale: const Locale('zh'),
          observer: observer,
        );

        final localizations = MaterialLocalizations.of(hostContext);
        final theme = Theme.of(hostContext);
        final isDark = theme.brightness == Brightness.dark;

        final expectedModalBarrierColor = Colors.black.withValues(
          alpha: isDark ? 0.48 : 0.32,
        );
        expect(
          theme.bottomSheetTheme.modalBarrierColor,
          equals(expectedModalBarrierColor),
        );

        final expectedBarrierLabel = localizations.scrimLabel;
        final expectedBarrierOnTapHint = localizations.scrimOnTapHint(
          localizations.bottomSheetLabel,
        );

        final standaloneRoute = createAppModalSheetRoute<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 80, child: Text('Standalone')),
        );
        expect(standaloneRoute.modalBarrierColor, equals(expectedModalBarrierColor));
        expect(standaloneRoute.barrierColor, equals(expectedModalBarrierColor));
        expect(standaloneRoute.barrierLabel, equals(expectedBarrierLabel));
        expect(standaloneRoute.barrierOnTapHint, equals(expectedBarrierOnTapHint));
        expect(standaloneRoute.capturedThemes, isNotNull);
        expect(standaloneRoute.isDismissible, isTrue);
        expect(standaloneRoute.enableDrag, isTrue);

        final sheetFuture = showAppModalSheet<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 80, child: Text('Active Sheet')),
        );

        await tester.pumpAndSettle();

        final pushedRoute = observer.pushedRoute as ModalBottomSheetRoute<void>?;
        expect(pushedRoute, isNotNull);
        expect(pushedRoute!.modalBarrierColor, equals(expectedModalBarrierColor));
        expect(pushedRoute.barrierColor, equals(expectedModalBarrierColor));
        expect(pushedRoute.barrierLabel, equals(expectedBarrierLabel));
        expect(pushedRoute.barrierOnTapHint, equals(expectedBarrierOnTapHint));
        expect(pushedRoute.capturedThemes, isNotNull);
        expect(pushedRoute.isDismissible, isTrue);
        expect(pushedRoute.enableDrag, isTrue);

        final barrier = tester.widget<AnimatedModalBarrier>(
          find.byType(AnimatedModalBarrier).last,
        );
        expect(barrier.semanticsLabel, equals(expectedBarrierLabel));
        expect(barrier.semanticsOnTapHint, equals(expectedBarrierOnTapHint));
        expect(barrier.color.value, equals(expectedModalBarrierColor));

        Navigator.of(tester.element(find.text('Active Sheet'))).pop();
        await tester.pumpAndSettle();
        await sheetFuture;
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ModalBottomSheetRoute contract matches framework defaults for defaultBrand (light) in en locale',
      (tester) async {
        final observer = _RecordingNavigatorObserver();
        final hostContext = await _pumpTestHost(
          tester,
          theme: AppBrands.defaultBrand.theme,
          locale: const Locale('en'),
          observer: observer,
        );

        final localizations = MaterialLocalizations.of(hostContext);
        final theme = Theme.of(hostContext);
        final isDark = theme.brightness == Brightness.dark;

        final expectedModalBarrierColor = Colors.black.withValues(
          alpha: isDark ? 0.48 : 0.32,
        );
        expect(
          theme.bottomSheetTheme.modalBarrierColor,
          equals(expectedModalBarrierColor),
        );

        final expectedBarrierLabel = localizations.scrimLabel;
        final expectedBarrierOnTapHint = localizations.scrimOnTapHint(
          localizations.bottomSheetLabel,
        );

        final standaloneRoute = createAppModalSheetRoute<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 80, child: Text('Standalone')),
        );
        expect(standaloneRoute.modalBarrierColor, equals(expectedModalBarrierColor));
        expect(standaloneRoute.barrierColor, equals(expectedModalBarrierColor));
        expect(standaloneRoute.barrierLabel, equals(expectedBarrierLabel));
        expect(standaloneRoute.barrierOnTapHint, equals(expectedBarrierOnTapHint));
        expect(standaloneRoute.capturedThemes, isNotNull);
        expect(standaloneRoute.isDismissible, isTrue);
        expect(standaloneRoute.enableDrag, isTrue);

        final sheetFuture = showAppModalSheet<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 80, child: Text('Active Sheet')),
        );

        await tester.pumpAndSettle();

        final pushedRoute = observer.pushedRoute as ModalBottomSheetRoute<void>?;
        expect(pushedRoute, isNotNull);
        expect(pushedRoute!.modalBarrierColor, equals(expectedModalBarrierColor));
        expect(pushedRoute.barrierColor, equals(expectedModalBarrierColor));
        expect(pushedRoute.barrierLabel, equals(expectedBarrierLabel));
        expect(pushedRoute.barrierOnTapHint, equals(expectedBarrierOnTapHint));
        expect(pushedRoute.capturedThemes, isNotNull);
        expect(pushedRoute.isDismissible, isTrue);
        expect(pushedRoute.enableDrag, isTrue);

        final barrier = tester.widget<AnimatedModalBarrier>(
          find.byType(AnimatedModalBarrier).last,
        );
        expect(barrier.semanticsLabel, equals(expectedBarrierLabel));
        expect(barrier.semanticsOnTapHint, equals(expectedBarrierOnTapHint));
        expect(barrier.color.value, equals(expectedModalBarrierColor));

        Navigator.of(tester.element(find.text('Active Sheet'))).pop();
        await tester.pumpAndSettle();
        await sheetFuture;
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ModalBottomSheetRoute contract matches framework defaults for liquidGlass (light) in zh locale',
      (tester) async {
        final observer = _RecordingNavigatorObserver();
        final hostContext = await _pumpTestHost(
          tester,
          theme: AppBrands.liquidGlass.theme,
          locale: const Locale('zh'),
          observer: observer,
        );

        final localizations = MaterialLocalizations.of(hostContext);
        final theme = Theme.of(hostContext);
        final isDark = theme.brightness == Brightness.dark;

        final expectedModalBarrierColor = Colors.black.withValues(
          alpha: isDark ? 0.48 : 0.32,
        );
        expect(
          theme.bottomSheetTheme.modalBarrierColor,
          equals(expectedModalBarrierColor),
        );

        final expectedBarrierLabel = localizations.scrimLabel;
        final expectedBarrierOnTapHint = localizations.scrimOnTapHint(
          localizations.bottomSheetLabel,
        );

        final standaloneRoute = createAppModalSheetRoute<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 80, child: Text('Standalone')),
        );
        expect(standaloneRoute.modalBarrierColor, equals(expectedModalBarrierColor));
        expect(standaloneRoute.barrierColor, equals(expectedModalBarrierColor));
        expect(standaloneRoute.barrierLabel, equals(expectedBarrierLabel));
        expect(standaloneRoute.barrierOnTapHint, equals(expectedBarrierOnTapHint));
        expect(standaloneRoute.capturedThemes, isNotNull);
        expect(standaloneRoute.isDismissible, isTrue);
        expect(standaloneRoute.enableDrag, isTrue);

        final sheetFuture = showAppModalSheet<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 80, child: Text('Active Sheet')),
        );

        await tester.pumpAndSettle();

        final pushedRoute = observer.pushedRoute as ModalBottomSheetRoute<void>?;
        expect(pushedRoute, isNotNull);
        expect(pushedRoute!.modalBarrierColor, equals(expectedModalBarrierColor));
        expect(pushedRoute.barrierColor, equals(expectedModalBarrierColor));
        expect(pushedRoute.barrierLabel, equals(expectedBarrierLabel));
        expect(pushedRoute.barrierOnTapHint, equals(expectedBarrierOnTapHint));
        expect(pushedRoute.capturedThemes, isNotNull);
        expect(pushedRoute.isDismissible, isTrue);
        expect(pushedRoute.enableDrag, isTrue);

        final barrier = tester.widget<AnimatedModalBarrier>(
          find.byType(AnimatedModalBarrier).last,
        );
        expect(barrier.semanticsLabel, equals(expectedBarrierLabel));
        expect(barrier.semanticsOnTapHint, equals(expectedBarrierOnTapHint));
        expect(barrier.color.value, equals(expectedModalBarrierColor));

        Navigator.of(tester.element(find.text('Active Sheet'))).pop();
        await tester.pumpAndSettle();
        await sheetFuture;
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ModalBottomSheetRoute contract matches framework defaults for liquidGlass (light) in en locale',
      (tester) async {
        final observer = _RecordingNavigatorObserver();
        final hostContext = await _pumpTestHost(
          tester,
          theme: AppBrands.liquidGlass.theme,
          locale: const Locale('en'),
          observer: observer,
        );

        final localizations = MaterialLocalizations.of(hostContext);
        final theme = Theme.of(hostContext);
        final isDark = theme.brightness == Brightness.dark;

        final expectedModalBarrierColor = Colors.black.withValues(
          alpha: isDark ? 0.48 : 0.32,
        );
        expect(
          theme.bottomSheetTheme.modalBarrierColor,
          equals(expectedModalBarrierColor),
        );

        final expectedBarrierLabel = localizations.scrimLabel;
        final expectedBarrierOnTapHint = localizations.scrimOnTapHint(
          localizations.bottomSheetLabel,
        );

        final standaloneRoute = createAppModalSheetRoute<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 80, child: Text('Standalone')),
        );
        expect(standaloneRoute.modalBarrierColor, equals(expectedModalBarrierColor));
        expect(standaloneRoute.barrierColor, equals(expectedModalBarrierColor));
        expect(standaloneRoute.barrierLabel, equals(expectedBarrierLabel));
        expect(standaloneRoute.barrierOnTapHint, equals(expectedBarrierOnTapHint));
        expect(standaloneRoute.capturedThemes, isNotNull);
        expect(standaloneRoute.isDismissible, isTrue);
        expect(standaloneRoute.enableDrag, isTrue);

        final sheetFuture = showAppModalSheet<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 80, child: Text('Active Sheet')),
        );

        await tester.pumpAndSettle();

        final pushedRoute = observer.pushedRoute as ModalBottomSheetRoute<void>?;
        expect(pushedRoute, isNotNull);
        expect(pushedRoute!.modalBarrierColor, equals(expectedModalBarrierColor));
        expect(pushedRoute.barrierColor, equals(expectedModalBarrierColor));
        expect(pushedRoute.barrierLabel, equals(expectedBarrierLabel));
        expect(pushedRoute.barrierOnTapHint, equals(expectedBarrierOnTapHint));
        expect(pushedRoute.capturedThemes, isNotNull);
        expect(pushedRoute.isDismissible, isTrue);
        expect(pushedRoute.enableDrag, isTrue);

        final barrier = tester.widget<AnimatedModalBarrier>(
          find.byType(AnimatedModalBarrier).last,
        );
        expect(barrier.semanticsLabel, equals(expectedBarrierLabel));
        expect(barrier.semanticsOnTapHint, equals(expectedBarrierOnTapHint));
        expect(barrier.color.value, equals(expectedModalBarrierColor));

        Navigator.of(tester.element(find.text('Active Sheet'))).pop();
        await tester.pumpAndSettle();
        await sheetFuture;
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ModalBottomSheetRoute contract matches framework defaults for starRail (dark) in zh locale',
      (tester) async {
        final observer = _RecordingNavigatorObserver();
        final hostContext = await _pumpTestHost(
          tester,
          theme: AppBrands.starRail.theme,
          locale: const Locale('zh'),
          observer: observer,
        );

        final localizations = MaterialLocalizations.of(hostContext);
        final theme = Theme.of(hostContext);
        final isDark = theme.brightness == Brightness.dark;

        final expectedModalBarrierColor = Colors.black.withValues(
          alpha: isDark ? 0.48 : 0.32,
        );
        expect(
          theme.bottomSheetTheme.modalBarrierColor,
          equals(expectedModalBarrierColor),
        );

        final expectedBarrierLabel = localizations.scrimLabel;
        final expectedBarrierOnTapHint = localizations.scrimOnTapHint(
          localizations.bottomSheetLabel,
        );

        final standaloneRoute = createAppModalSheetRoute<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 80, child: Text('Standalone')),
        );
        expect(standaloneRoute.modalBarrierColor, equals(expectedModalBarrierColor));
        expect(standaloneRoute.barrierColor, equals(expectedModalBarrierColor));
        expect(standaloneRoute.barrierLabel, equals(expectedBarrierLabel));
        expect(standaloneRoute.barrierOnTapHint, equals(expectedBarrierOnTapHint));
        expect(standaloneRoute.capturedThemes, isNotNull);
        expect(standaloneRoute.isDismissible, isTrue);
        expect(standaloneRoute.enableDrag, isTrue);

        final sheetFuture = showAppModalSheet<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 80, child: Text('Active Sheet')),
        );

        await tester.pumpAndSettle();

        final pushedRoute = observer.pushedRoute as ModalBottomSheetRoute<void>?;
        expect(pushedRoute, isNotNull);
        expect(pushedRoute!.modalBarrierColor, equals(expectedModalBarrierColor));
        expect(pushedRoute.barrierColor, equals(expectedModalBarrierColor));
        expect(pushedRoute.barrierLabel, equals(expectedBarrierLabel));
        expect(pushedRoute.barrierOnTapHint, equals(expectedBarrierOnTapHint));
        expect(pushedRoute.capturedThemes, isNotNull);
        expect(pushedRoute.isDismissible, isTrue);
        expect(pushedRoute.enableDrag, isTrue);

        final barrier = tester.widget<AnimatedModalBarrier>(
          find.byType(AnimatedModalBarrier).last,
        );
        expect(barrier.semanticsLabel, equals(expectedBarrierLabel));
        expect(barrier.semanticsOnTapHint, equals(expectedBarrierOnTapHint));
        expect(barrier.color.value, equals(expectedModalBarrierColor));

        Navigator.of(tester.element(find.text('Active Sheet'))).pop();
        await tester.pumpAndSettle();
        await sheetFuture;
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ModalBottomSheetRoute contract matches framework defaults for starRail (dark) in en locale',
      (tester) async {
        final observer = _RecordingNavigatorObserver();
        final hostContext = await _pumpTestHost(
          tester,
          theme: AppBrands.starRail.theme,
          locale: const Locale('en'),
          observer: observer,
        );

        final localizations = MaterialLocalizations.of(hostContext);
        final theme = Theme.of(hostContext);
        final isDark = theme.brightness == Brightness.dark;

        final expectedModalBarrierColor = Colors.black.withValues(
          alpha: isDark ? 0.48 : 0.32,
        );
        expect(
          theme.bottomSheetTheme.modalBarrierColor,
          equals(expectedModalBarrierColor),
        );

        final expectedBarrierLabel = localizations.scrimLabel;
        final expectedBarrierOnTapHint = localizations.scrimOnTapHint(
          localizations.bottomSheetLabel,
        );

        final standaloneRoute = createAppModalSheetRoute<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 80, child: Text('Standalone')),
        );
        expect(standaloneRoute.modalBarrierColor, equals(expectedModalBarrierColor));
        expect(standaloneRoute.barrierColor, equals(expectedModalBarrierColor));
        expect(standaloneRoute.barrierLabel, equals(expectedBarrierLabel));
        expect(standaloneRoute.barrierOnTapHint, equals(expectedBarrierOnTapHint));
        expect(standaloneRoute.capturedThemes, isNotNull);
        expect(standaloneRoute.isDismissible, isTrue);
        expect(standaloneRoute.enableDrag, isTrue);

        final sheetFuture = showAppModalSheet<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 80, child: Text('Active Sheet')),
        );

        await tester.pumpAndSettle();

        final pushedRoute = observer.pushedRoute as ModalBottomSheetRoute<void>?;
        expect(pushedRoute, isNotNull);
        expect(pushedRoute!.modalBarrierColor, equals(expectedModalBarrierColor));
        expect(pushedRoute.barrierColor, equals(expectedModalBarrierColor));
        expect(pushedRoute.barrierLabel, equals(expectedBarrierLabel));
        expect(pushedRoute.barrierOnTapHint, equals(expectedBarrierOnTapHint));
        expect(pushedRoute.capturedThemes, isNotNull);
        expect(pushedRoute.isDismissible, isTrue);
        expect(pushedRoute.enableDrag, isTrue);

        final barrier = tester.widget<AnimatedModalBarrier>(
          find.byType(AnimatedModalBarrier).last,
        );
        expect(barrier.semanticsLabel, equals(expectedBarrierLabel));
        expect(barrier.semanticsOnTapHint, equals(expectedBarrierOnTapHint));
        expect(barrier.color.value, equals(expectedModalBarrierColor));

        Navigator.of(tester.element(find.text('Active Sheet'))).pop();
        await tester.pumpAndSettle();
        await sheetFuture;
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'createAppModalSheetRoute provides pre-push route identity before explicit Navigator.push and returns null on barrier dismiss',
      (tester) async {
        final observer = _RecordingNavigatorObserver();

        final hostContext = await _pumpTestHost(
          tester,
          theme: AppBrands.defaultBrand.theme,
          locale: const Locale('zh'),
          observer: observer,
        );

        final nearestRoute = createAppModalSheetRoute<void>(
          context: hostContext,
          useRootNavigator: false,
          builder: (_) => const SizedBox(),
        );
        expect(nearestRoute.capturedThemes, isNotNull);

        final rootRoute = createAppModalSheetRoute<void>(
          context: hostContext,
          useRootNavigator: true,
          builder: (_) => const SizedBox(),
        );
        expect(rootRoute.capturedThemes, isNotNull);

        final route = createAppModalSheetRoute<String>(
          context: hostContext,
          builder: (_) => const SizedBox(
            height: 120,
            child: Center(child: Text('Dismissible Body')),
          ),
        );

        expect(route, isNotNull);
        expect(route.isDismissible, isTrue);
        expect(route.enableDrag, isTrue);
        expect(route.isScrollControlled, isTrue);
        expect(route.capturedThemes, isNotNull);
        expect(observer.pushedRoute, isNull);
        expect(observer.events, isEmpty);

        final pushFuture = Navigator.of(hostContext).push(route);

        await tester.pumpAndSettle();

        expect(observer.events, equals(['observer.didPush']));
        expect(identical(route, observer.pushedRoute), isTrue);
        expect(find.text('Dismissible Body'), findsOneWidget);
        expect(
          tester.widget<ModalBarrier>(find.byType(ModalBarrier).last).dismissible,
          isTrue,
        );
        expect(
          tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
          isTrue,
        );

        // Dismiss sheet by tapping scrim barrier at top-left
        await tester.tapAt(const Offset(12, 12));
        await tester.pumpAndSettle();

        expect(find.text('Dismissible Body'), findsNothing);
        final result = await pushFuture;
        expect(result, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'createAppModalSheetRoute provides pre-push route identity before explicit Navigator.push and awaits explicit popped value',
      (tester) async {
        final observer = _RecordingNavigatorObserver();

        final hostContext = await _pumpTestHost(
          tester,
          theme: AppBrands.defaultBrand.theme,
          locale: const Locale('en'),
          observer: observer,
        );

        final nonDismissibleRoute = createAppModalSheetRoute<void>(
          context: hostContext,
          isDismissible: false,
          enableDrag: false,
          builder: (_) => const SizedBox(),
        );
        expect(nonDismissibleRoute.isDismissible, isFalse);
        expect(nonDismissibleRoute.enableDrag, isFalse);

        final unshiftedRoute = createAppModalSheetRoute<void>(
          context: hostContext,
          shiftForKeyboard: false,
          builder: (_) => const Text('Unshifted'),
        );
        expect(unshiftedRoute.builder(hostContext), isA<MediaQuery>());

        final shiftedRoute = createAppModalSheetRoute<void>(
          context: hostContext,
          shiftForKeyboard: true,
          builder: (_) => const Text('Shifted'),
        );
        expect(shiftedRoute.builder(hostContext), isA<Text>());

        final route = createAppModalSheetRoute<String>(
          context: hostContext,
          builder: (sheetContext) => SizedBox(
            height: 120,
            child: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(sheetContext).pop('submitted_payload'),
                child: const Text('Submit'),
              ),
            ),
          ),
        );

        expect(route, isNotNull);
        expect(route.capturedThemes, isNotNull);
        expect(observer.pushedRoute, isNull);
        expect(observer.events, isEmpty);

        final pushFuture = Navigator.of(hostContext).push(route);

        await tester.pumpAndSettle();

        expect(observer.events, equals(['observer.didPush']));
        expect(identical(route, observer.pushedRoute), isTrue);
        expect(find.text('Submit'), findsOneWidget);

        await tester.tap(find.text('Submit'));
        await tester.pumpAndSettle();

        expect(find.text('Submit'), findsNothing);
        final result = await pushFuture;
        expect(result, equals('submitted_payload'));
        expect(tester.takeException(), isNull);
      },
    );
  });
}
