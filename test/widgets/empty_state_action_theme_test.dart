import 'dart:ui' as ui;

import 'package:duoyi/core/feedback_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/feedback_screen.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/empty_state.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

class _ActionProbe extends RouteRenderProbe {
  _ActionProbe(super.tester, super.boundary, super.name);

  @override
  Future<void> reveal(Finder finder) async {
    expect(finder, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await tester.pumpAndSettle();
  }
}

Future<void> _action(
  WidgetTester tester,
  _ActionProbe probe,
  String label,
) async {
  final text = find.descendant(
    of: find.byType(EmptyState),
    matching: find.text(label),
  );
  await probe.text(text, role: 'empty action', minimumGeometricScale: .999);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  for (final match in RegExp(r'[A-Za-z]+').allMatches(label)) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: match.start, extentOffset: match.end),
    );
    final lines = boxes.map((box) => box.top).toSet().length;
    probe.rows.add({'role': 'action word', 'word': match[0], 'lines': lines});
    if (lines > 1) probe.errors.add('action splits word ${match[0]}');
  }
  final button = find.ancestor(of: text, matching: find.byType(FilledButton));
  final rect = tester.getRect(button);
  final node = tester.getSemantics(button);
  final data = node.getSemanticsData();
  probe.rows.add({
    'role': 'action target',
    'label': data.label,
    'width': node.rect.width,
    'height': node.rect.height,
    'tappable': data.hasAction(ui.SemanticsAction.tap),
  });
  expect(data.label, contains(label));
  expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
  expect(node.rect.width, greaterThanOrEqualTo(44));
  expect(node.rect.height, greaterThanOrEqualTo(44));
  final textRect = tester.getRect(text);
  expect(textRect.left, greaterThanOrEqualTo(rect.left - .1));
  expect(textRect.right, lessThanOrEqualTo(rect.right + .1));
  expect(textRect.top, greaterThanOrEqualTo(rect.top - .1));
  expect(textRect.bottom, lessThanOrEqualTo(rect.bottom + .1));
}

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final initial in AppLocale.values) {
      for (final layout in priorityLayouts) {
        for (final routed in [false, true]) {
          final name =
              'empty-action-$brand-${initial.name}-${layout.name}-${routed ? "feedback" : "component"}';
          testWidgets(name, (tester) async {
            final handle = tester.ensureSemantics();
            try {
              var calls = 0;
              final requests = <String>[];
              final transport = MockClient((request) async {
                requests.add('${request.method} ${request.url.path}');
                return http.Response('{}', 500);
              });
              addTearDown(transport.close);
              final auth = AuthProvider(
                client: ApiClient(
                  baseUrl: 'https://synthetic.example.test',
                  httpClient: transport,
                ),
              );
              const feedback = FeedbackScreen();
              final boundary = await mountPriorityFixture(
                tester,
                auth: auth,
                brand: brand,
                locale: initial,
                size: layout.size,
                scale: layout.scale,
                home: routed
                    ? Builder(
                        builder: (context) => Scaffold(
                          body: TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const BrandRouteSurface(child: feedback),
                              ),
                            ),
                            child: const Text('Open synthetic feedback'),
                          ),
                        ),
                      )
                    : BrandRouteSurface(
                        child: Scaffold(
                          backgroundColor: brand == 'liquidGlass'
                              ? Colors.transparent
                              : null,
                          body: AppSecondaryControlTheme(
                            child: ValueListenableBuilder<AppLocale>(
                              valueListenable: I18n.localeListenable,
                              builder: (context, locale, _) => EmptyState(
                                icon: Icons.login_outlined,
                                message: FeedbackUiCopy.loginRecordsRequired(
                                  locale,
                                ),
                                actionLabel: FeedbackUiCopy.loginSubmitPrefix(
                                  'feature',
                                  locale,
                                ),
                                onAction: () => calls++,
                                minCardHeight: EmptyState.defaultMinCardHeight,
                              ),
                            ),
                          ),
                        ),
                      ),
              );
              if (routed) {
                await tester.tap(find.text('Open synthetic feedback'));
                await tester.pumpAndSettle();
              }
              final probe = _ActionProbe(tester, boundary, name);
              final retained = routed
                  ? tester.state(find.byType(FeedbackScreen))
                  : null;
              for (final locale in [
                initial,
                initial == AppLocale.en ? AppLocale.zh : AppLocale.en,
              ]) {
                I18n.setLocale(locale);
                await tester.pumpAndSettle();
                if (routed) {
                  expect(
                    tester.state(find.byType(FeedbackScreen)),
                    same(retained),
                  );
                }
                final label = FeedbackUiCopy.loginSubmitPrefix(
                  'feature',
                  locale,
                );
                await _action(tester, probe, label);
                await probe.capture(locale.name);
                if (!routed) {
                  final before = calls;
                  await tester.tap(find.text(label));
                  await tester.pumpAndSettle();
                  expect(calls, before + 1);
                }
              }
              if (routed) {
                await tester.tap(
                  find.text(FeedbackUiCopy.loginSubmitPrefix('feature')),
                );
                await tester.pumpAndSettle();
                expect(find.byType(LoginScreen), findsOneWidget);
                Navigator.of(tester.element(find.byType(LoginScreen))).pop();
                await tester.pumpAndSettle();
                expect(
                  tester.state(find.byType(FeedbackScreen)),
                  same(retained),
                );
              }
              expect(requests, isEmpty);
              await probe.finish();
            } finally {
              handle.dispose();
            }
          });
        }
      }
    }
  }
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      testWidgets('empty-action-$brand-${locale.name}-200px', (tester) async {
        final handle = tester.ensureSemantics();
        try {
          var calls = 0;
          final transport = MockClient((_) async => http.Response('{}', 500));
          addTearDown(transport.close);
          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://synthetic.example.test',
              httpClient: transport,
            ),
          );
          final label = FeedbackUiCopy.loginSubmitPrefix('feature', locale);
          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: const Size(200, 200),
            scale: 2,
            home: BrandRouteSurface(
              child: Scaffold(
                backgroundColor: brand == 'liquidGlass'
                    ? Colors.transparent
                    : null,
                body: AppSecondaryControlTheme(
                  child: EmptyState(
                    icon: Icons.login_outlined,
                    message: FeedbackUiCopy.loginRecordsRequired(locale),
                    actionLabel: label,
                    onAction: () => calls++,
                    minCardHeight: EmptyState.defaultMinCardHeight,
                  ),
                ),
              ),
            ),
          );
          final probe = _ActionProbe(
            tester,
            boundary,
            'empty-action-$brand-${locale.name}-200px',
          );
          await _action(tester, probe, label);
          await probe.capture('action');
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(calls, 1);
          await probe.finish();
        } finally {
          handle.dispose();
        }
      });
    }
  }
}
