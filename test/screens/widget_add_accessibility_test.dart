import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

void main() {
  setUp(() => AndroidWidgetManager.debugIsAndroidOverride = true);
  tearDown(() {
    AndroidWidgetManager.debugIsAndroidOverride = null;
    I18n.setLocale(AppLocale.zh);
  });
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final host in WidgetHostPlatform.values) {
      testWidgets('widget add accessible identity $brand ${host.name}', (
        tester,
      ) async {
        final channels = _Channels()..install(tester);
        final semantics = tester.ensureSemantics();
        final boundary = await mountPriorityFixture(
          tester,
          auth: AuthProvider(),
          brand: brand,
          locale: AppLocale.zh,
          size: const Size(390, 844),
          scale: 1.6,
          home: BrandRouteSurface(child: WidgetScreen(hostPlatform: host)),
        );
        final retained = tester.state(find.byType(WidgetScreen));
        final prefs = await SharedPreferences.getInstance();
        final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
        final report = _Report('identity-$brand-${host.name}');
        final probe = RouteRenderProbe(tester, boundary, report.name);
        for (var pass = 0; pass < 3; pass++) {
          _top(tester);
          await tester.pumpAndSettle();
          final locale = pass == 1 ? AppLocale.en : AppLocale.zh;
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          _top(tester);
          await tester.pumpAndSettle();
          final labels = <String>{};
          for (final kind in DuoyiWidgetKind.values) {
            final button = await _reveal(tester, kind);
            final visible = host == WidgetHostPlatform.android
                ? WidgetUiCopy.addWidgetButtonLabel(
                    modeLabel: WidgetDisplayMode.standard.label,
                    launcherRequestLabel:
                        WidgetDisplayMode.standard.launcherRequestLabel,
                  )
                : WidgetUiCopy.hostAddAction(host);
            final node = _inspect(
              tester,
              button,
              kind,
              visible,
              report,
              '${locale.name}-$pass',
              enabled: true,
            );
            labels.add(node.label);
            if (kind == DuoyiWidgetKind.todo) {
              await probe.capture('$pass-${locale.name}');
            }
          }
          if (labels.length != DuoyiWidgetKind.values.length) {
            report.errors.add(
              '${locale.name}: ${labels.length} distinct action names for ten kinds',
            );
          }
          expect(tester.state(find.byType(WidgetScreen)), same(retained));
          expect({
            for (final key in prefs.getKeys()) key: prefs.get(key),
          }, before);
        }
        expect(channels.pinRequests, 0);
        semantics.dispose();
        await report.finish(tester);
      });
    }

    testWidgets(
      'widget add semantic actions retain pending boundaries $brand',
      (tester) async {
        final channels = _Channels()..install(tester);
        final semantics = tester.ensureSemantics();
        await mountPriorityFixture(
          tester,
          auth: AuthProvider(),
          brand: brand,
          locale: AppLocale.zh,
          size: const Size(390, 844),
          scale: 1.6,
          home: const BrandRouteSurface(
            child: WidgetScreen(hostPlatform: WidgetHostPlatform.android),
          ),
        );
        final report = _Report('pending-$brand');
        await _reveal(tester, DuoyiWidgetKind.todo);
        channels.supportGate = Completer<Object?>();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        I18n.setLocale(AppLocale.en);
        await tester.pump();
        _inspect(
          tester,
          _button(DuoyiWidgetKind.todo),
          DuoyiWidgetKind.todo,
          WidgetUiCopy.checkingDesktopSupport,
          report,
          'checking-en',
          enabled: false,
        );
        channels.supportGate!.complete(true);
        channels.supportGate = null;
        await tester.pumpAndSettle();
        final ready = _inspect(
          tester,
          _button(DuoyiWidgetKind.todo),
          DuoyiWidgetKind.todo,
          WidgetUiCopy.addWidgetButtonLabel(
            modeLabel: WidgetDisplayMode.standard.label,
            launcherRequestLabel:
                WidgetDisplayMode.standard.launcherRequestLabel,
          ),
          report,
          'ready-en',
          enabled: true,
        );
        channels.pinGate = Completer<Object?>();
        channels.pinStarted = Completer<void>();
        ready.owner!.performAction(ready.id, ui.SemanticsAction.tap);
        await tester.runAsync(
          () => channels.pinStarted!.future.timeout(const Duration(seconds: 3)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        I18n.setLocale(AppLocale.zh);
        await tester.pump();
        final pending = _inspect(
          tester,
          _button(DuoyiWidgetKind.todo),
          DuoyiWidgetKind.todo,
          WidgetUiCopy.requestingAdd,
          report,
          'requesting-zh',
          enabled: false,
        );
        pending.owner!.performAction(pending.id, ui.SemanticsAction.tap);
        await tester.pump();
        expect(channels.pinRequests, 1);
        expect(channels.requestKinds, ['todo']);
        channels.pinGate!.complete('requested');
        channels.pinGate = null;
        await tester.pumpAndSettle();
        expect(channels.pinRequests, 1);
        _inspect(
          tester,
          _button(DuoyiWidgetKind.todo),
          DuoyiWidgetKind.todo,
          WidgetUiCopy.addWidgetButtonLabel(
            modeLabel: WidgetDisplayMode.standard.label,
            launcherRequestLabel:
                WidgetDisplayMode.standard.launcherRequestLabel,
          ),
          report,
          'ready-zh',
          enabled: true,
        );
        semantics.dispose();
        await report.finish(tester);
      },
    );
  }
}

Finder _button(DuoyiWidgetKind kind) => find.descendant(
  of: find.byKey(ValueKey('widget_gallery_${kind.name}')),
  matching: find.byType(FilledButton),
);

void _top(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .jumpTo(0);

Future<Finder> _reveal(WidgetTester tester, DuoyiWidgetKind kind) async {
  final button = _button(kind);
  if (button.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      button,
      200,
      maxScrolls: 200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  return button;
}

SemanticsNode _inspect(
  WidgetTester tester,
  Finder button,
  DuoyiWidgetKind kind,
  String visible,
  _Report report,
  String stage, {
  required bool enabled,
}) {
  expect(
    find.descendant(of: button, matching: find.text(visible)),
    findsOneWidget,
  );
  final node = tester.getSemantics(button);
  final data = node.getSemanticsData();
  expect(data.flagsCollection.isButton, isTrue);
  expect(
    data.flagsCollection.isEnabled,
    enabled ? ui.Tristate.isTrue : ui.Tristate.isFalse,
  );
  expect(data.hasAction(ui.SemanticsAction.tap), enabled);
  expect(node.label, contains(visible));
  final title = WidgetUiCopy.catalogTitle(kind);
  if (!node.label.contains(title)) {
    report.errors.add('$stage ${kind.name}: accessible action lacks $title');
  }
  report.rows.add({
    'stage': stage,
    'kind': kind.name,
    'visible': visible,
    'accessibleName': node.label,
    'objectTitle': title,
    'enabled': enabled,
    'tap': data.hasAction(ui.SemanticsAction.tap),
  });
  return node;
}

class _Report {
  _Report(this.name);
  final String name;
  final rows = <Map<String, Object?>>[];
  final errors = <String>[];
  Future<void> finish(WidgetTester tester) async {
    final folder = Platform.environment['DUOYI_WIDGET_ACCESSIBILITY_REPORTS'];
    if (folder != null) {
      final path = File('$folder/$name.json');
      path.parent.createSync(recursive: true);
      path.writeAsStringSync(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'name': name, 'rows': rows, 'errors': errors}),
      );
    }
    expect(tester.takeException(), isNull);
    expect(errors, isEmpty);
  }
}

class _Channels {
  Completer<Object?>? supportGate;
  Completer<Object?>? pinGate;
  Completer<void>? pinStarted;
  int pinRequests = 0;
  final requestKinds = <String>[];
  void install(WidgetTester tester) {
    const channel = MethodChannel('duoyi/widgets');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'canRequestPinWidget':
          return supportGate == null ? true : await supportGate!.future;
        case 'canOpenWidgetSettings':
          return true;
        case 'requestPinWidget':
          pinRequests++;
          requestKinds.add(
            (call.arguments as Map<Object?, Object?>)['kind'].toString(),
          );
          pinStarted?.complete();
          return pinGate == null ? 'requested' : await pinGate!.future;
        default:
          return 0;
      }
    });
    addTearDown(() {
      if (supportGate != null && !supportGate!.isCompleted) {
        supportGate!.complete(true);
      }
      if (pinGate != null && !pinGate!.isCompleted) {
        pinGate!.complete('requested');
      }
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
  }
}
