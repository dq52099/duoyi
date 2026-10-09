import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';

/// 挂在 BrandRouteSurface 下的 const 子页：模拟
/// `const BrandRouteSurface(child: XxxScreen())` 推入路由后，
/// 父级不会下发新实例的形态。
class _ConstLocaleProbe extends StatelessWidget {
  const _ConstLocaleProbe();

  @override
  Widget build(BuildContext context) {
    return Text(I18n.tr('nav.mine'));
  }
}

const _probeRootKey = ValueKey<String>('locale_stateful_probe');
const _probeCopyKey = ValueKey<String>('locale_probe_copy');
const _probeCounterKey = ValueKey<String>('locale_probe_counter');
const _probeDraftKey = ValueKey<String>('locale_probe_draft');
const _probeIncrementKey = ValueKey<String>('locale_probe_increment');
const _openProbeKey = ValueKey<String>('open_locale_probe');

class _ProbeLifecycle {
  static int initCount = 0;
  static int disposeCount = 0;
  static int localeCallbackCount = 0;

  static void reset() {
    initCount = 0;
    disposeCount = 0;
    localeCallbackCount = 0;
  }
}

abstract class _LocaleProbeState<W extends StatefulWidget> extends State<W> {
  late final TextEditingController controller;
  int counter = 0;

  @override
  void initState() {
    super.initState();
    _ProbeLifecycle.initCount++;
    controller = TextEditingController();
    I18n.localeListenable.addListener(_handleLocaleChanged);
  }

  void _handleLocaleChanged() {
    _ProbeLifecycle.localeCallbackCount++;
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    controller.dispose();
    _ProbeLifecycle.disposeCount++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text(I18n.tr('nav.mine'), key: _probeCopyKey),
          Text('count=$counter', key: _probeCounterKey),
          TextField(key: _probeDraftKey, controller: controller),
          TextButton(
            key: _probeIncrementKey,
            onPressed: () => setState(() => counter++),
            child: const Text('increment'),
          ),
        ],
      ),
    );
  }
}

class _MarkedStatefulLocaleProbe extends StatefulWidget
    implements LocaleStatePreservingRoute {
  const _MarkedStatefulLocaleProbe({super.key});

  @override
  State<_MarkedStatefulLocaleProbe> createState() =>
      _MarkedStatefulLocaleProbeState();
}

class _MarkedStatefulLocaleProbeState
    extends _LocaleProbeState<_MarkedStatefulLocaleProbe> {}

class _UnmarkedStatefulLocaleProbe extends StatefulWidget {
  const _UnmarkedStatefulLocaleProbe({super.key});

  @override
  State<_UnmarkedStatefulLocaleProbe> createState() =>
      _UnmarkedStatefulLocaleProbeState();
}

class _UnmarkedStatefulLocaleProbeState
    extends _LocaleProbeState<_UnmarkedStatefulLocaleProbe> {}

class _MarkedStatelessLocaleFacade extends StatelessWidget
    implements LocaleStatePreservingRoute {
  const _MarkedStatelessLocaleFacade();

  @override
  Widget build(BuildContext context) {
    return const _MarkedStatefulLocaleProbe(key: _probeRootKey);
  }
}

Widget? _pendingProbeChild;
bool? _pendingRemountOnLocaleChange;

/// A const MaterialApp keeps its own locale fixed during raw I18n notifications.
class _ProbeRouteLauncher extends StatelessWidget {
  const _ProbeRouteLauncher();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: _openProbeKey,
          onPressed: () {
            final child = _pendingProbeChild!;
            final remountOnLocaleChange = _pendingRemountOnLocaleChange;
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => remountOnLocaleChange == null
                    ? BrandRouteSurface(child: child)
                    : BrandRouteSurface(
                        remountOnLocaleChange: remountOnLocaleChange,
                        child: child,
                      ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

Future<void> _pumpProbeRoute(
  WidgetTester tester,
  Widget child, {
  bool? remountOnLocaleChange,
}) async {
  _pendingProbeChild = child;
  _pendingRemountOnLocaleChange = remountOnLocaleChange;
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MaterialApp(home: _ProbeRouteLauncher()),
    ),
  );
  await tester.tap(find.byKey(_openProbeKey));
  await tester.pumpAndSettle();
  _pendingProbeChild = null;
  _pendingRemountOnLocaleChange = null;
}

Future<void> _expectProbeStateSurvivesLocaleChanges(
  WidgetTester tester,
  Widget child, {
  bool? remountOnLocaleChange,
}) async {
  await _pumpProbeRoute(
    tester,
    child,
    remountOnLocaleChange: remountOnLocaleChange,
  );

  final stateBefore = tester.state(find.byKey(_probeRootKey));
  final controllerBefore = tester
      .widget<TextField>(find.byKey(_probeDraftKey))
      .controller!;
  expect(_ProbeLifecycle.initCount, 1);
  expect(_ProbeLifecycle.disposeCount, 0);

  await tester.enterText(find.byKey(_probeDraftKey), 'draft survives');
  await tester.tap(find.byKey(_probeIncrementKey));
  await tester.pumpAndSettle();
  expect(find.text('count=1'), findsOneWidget);

  for (final locale in [AppLocale.en, AppLocale.zh]) {
    I18n.setLocale(locale);
    await tester.pumpAndSettle();

    expect(find.text(locale == AppLocale.en ? 'Me' : '我的'), findsOneWidget);
    expect(tester.state(find.byKey(_probeRootKey)), same(stateBefore));
    expect(
      tester.widget<TextField>(find.byKey(_probeDraftKey)).controller,
      same(controllerBefore),
    );
    expect(controllerBefore.text, 'draft survives');
    expect(find.text('count=1'), findsOneWidget);
    expect(_ProbeLifecycle.initCount, 1);
    expect(_ProbeLifecycle.disposeCount, 0);
  }

  expect(_ProbeLifecycle.localeCallbackCount, 2);
  tester.state<NavigatorState>(find.byType(Navigator)).pop();
  await tester.pumpAndSettle();
  expect(_ProbeLifecycle.disposeCount, 1);

  final callbacksAfterPop = _ProbeLifecycle.localeCallbackCount;
  I18n.setLocale(AppLocale.en);
  await tester.pumpAndSettle();
  expect(_ProbeLifecycle.localeCallbackCount, callbacksAfterPop);
  expect(_ProbeLifecycle.initCount, 1);
  expect(_ProbeLifecycle.disposeCount, 1);
}

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
    _ProbeLifecycle.reset();
  });

  testWidgets('BrandRouteSurface const 子树在语言热切换后仍跟随新语言', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const MaterialApp(
          home: BrandRouteSurface(child: _ConstLocaleProbe()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的'), findsOneWidget);

    // 只通知静态 locale listenable，不重建外层 const MaterialApp。
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();

    expect(find.text('Me'), findsOneWidget);
    expect(find.text('我的'), findsNothing);
  });

  testWidgets(
    'marked const StatefulWidget keeps State, controller, draft and counter',
    (tester) async {
      await _expectProbeStateSurvivesLocaleChanges(
        tester,
        const _MarkedStatefulLocaleProbe(key: _probeRootKey),
      );
    },
  );

  testWidgets('marked stateless facade preserves its stateful body', (
    tester,
  ) async {
    await _expectProbeStateSurvivesLocaleChanges(
      tester,
      const _MarkedStatelessLocaleFacade(),
    );
  });

  testWidgets(
    'remountOnLocaleChange false preserves an unmarked self-refreshing child',
    (tester) async {
      await _expectProbeStateSurvivesLocaleChanges(
        tester,
        const _UnmarkedStatefulLocaleProbe(key: _probeRootKey),
        remountOnLocaleChange: false,
      );
    },
  );

  testWidgets('marker takes precedence when remountOnLocaleChange is true', (
    tester,
  ) async {
    await _expectProbeStateSurvivesLocaleChanges(
      tester,
      const _MarkedStatefulLocaleProbe(key: _probeRootKey),
      remountOnLocaleChange: true,
    );
  });
}
