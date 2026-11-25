// Real pushed announcements route with synthetic HTTP read responses only.
import 'dart:convert';

import 'package:duoyi/core/announcement_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/announcements_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

const _levels = ['info', 'warning', 'critical'];
final _rows = [
  for (var i = 0; i < _levels.length; i++)
    {
      'id': i + 1,
      'level': _levels[i],
      'title': 'Synthetic announcement ${i + 1} 标题',
      'body':
          'Original published message ${i + 1} 原文保留。Please check the updated schedule before continuing.',
      'created_at': '2026-10-21T0${i + 1}:30:00Z',
    },
];

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'announcements-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          var requests = 0;
          final transport = MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/api/announcements');
            requests++;
            final fail = requests == 2;
            return http.Response(
              jsonEncode(
                fail
                    ? {'detail': 'PRIVATE synthetic server error'}
                    : requests >= 3
                    ? []
                    : _rows,
              ),
              fail ? 503 : 200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          });
          addTearDown(transport.close);
          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://synthetic.example.test',
              httpClient: transport,
            ),
          );
          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    key: const ValueKey('open_announcements_theme'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const BrandRouteSurface(
                          child: AnnouncementsScreen(),
                        ),
                      ),
                    ),
                    child: const Text('Open synthetic announcements'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(
            find.byKey(const ValueKey('open_announcements_theme')),
          );
          await tester.pumpAndSettle();
          expect(requests, 1);
          final state = tester.state(find.byType(AnnouncementsScreen));
          final probe = RouteRenderProbe(tester, boundary, name);
          Finder scrollable() => find
              .descendant(
                of: find.byType(RefreshIndicator),
                matching: find.byType(Scrollable),
              )
              .first;
          Future<void> text(
            String label,
            String role, {
            bool contrast = true,
          }) async {
            final finder = find.descendant(
              of: find.byType(RefreshIndicator),
              matching: find.text(label),
            );
            if (finder.evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                finder,
                180,
                scrollable: scrollable(),
                maxScrolls: 30,
              );
            }
            await probe.text(finder, role: role, contrast: contrast);
          }

          Future<void> content(String stage) async {
            tester.state<ScrollableState>(scrollable()).position.jumpTo(0);
            await tester.pumpAndSettle();
            await text(I18n.tr('announcement.center'), '$stage hero title');
            await text(
              I18n.tr('announcement.subtitle'),
              '$stage hero explanation',
            );
            await probe.capture('$stage-hero');
            for (var i = 0; i < _levels.length; i++) {
              await text(
                I18n.tr('announcement.level.${_levels[i]}'),
                '$stage ${_levels[i]} level',
              );
              await text(_rows[i]['title'] as String, '$stage item title');
              final titleFinder = find.text(_rows[i]['title'] as String);
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(
                  of: titleFinder,
                  matching: find.byType(RichText),
                ),
              );
              final copy = paragraph.text.toPlainText();
              for (final match in RegExp(r'[A-Za-z]+').allMatches(copy)) {
                final word = match.group(0)!;
                final painter = TextPainter(
                  text: TextSpan(text: word, style: paragraph.text.style),
                  textDirection: TextDirection.ltr,
                  textScaler: paragraph.textScaler,
                )..layout();
                final width = painter.width;
                painter.dispose();
                final lines = paragraph
                    .getBoxesForSelection(
                      TextSelection(
                        baseOffset: match.start,
                        extentOffset: match.end,
                      ),
                    )
                    .map((box) => box.top)
                    .toSet()
                    .length;
                probe.rows.add({
                  'role': '$stage title word',
                  'word': word,
                  'lines': lines,
                  'naturalWidth': width,
                });
                if (width <= layout.size.width * .8 && lines > 1) {
                  probe.errors.add('$stage title splits fitting word $word');
                }
              }
              await text(_rows[i]['body'] as String, '$stage item body');
              await text(
                _rows[i]['created_at'] as String,
                '$stage item timestamp',
              );
              await probe.capture('$stage-${_levels[i]}');
            }
          }

          await content('initial');
          final scrollState = tester.state<ScrollableState>(scrollable());
          final offset = scrollState.position.pixels;
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(AnnouncementsScreen)), same(state));
          expect(
            tester.state<ScrollableState>(scrollable()),
            same(scrollState),
          );
          expect(
            scrollState.position.pixels,
            closeTo(
              offset.clamp(0.0, scrollState.position.maxScrollExtent),
              .01,
            ),
          );
          expect(requests, 1);
          await content('live');
          await tester
              .widget<RefreshIndicator>(find.byType(RefreshIndicator))
              .onRefresh();
          await tester.pumpAndSettle();
          expect(requests, 2);
          scrollState.position.jumpTo(0);
          await tester.pumpAndSettle();
          await text(AnnouncementUiCopy.refreshFailed, 'cached refresh error');
          expect(find.textContaining('PRIVATE'), findsNothing);
          await text(AnnouncementUiCopy.retry, 'retry action', contrast: false);
          await probe.capture('refresh-error');
          await tester.tap(find.byKey(const ValueKey('announcements_retry')));
          await tester.pumpAndSettle();
          expect(requests, 3);
          expect(find.text(_rows.first['title'] as String), findsNothing);
          await text(I18n.tr('announcement.empty'), 'empty state');
          await probe.capture('empty');
          Navigator.of(tester.element(find.byType(AnnouncementsScreen))).pop();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('open_announcements_theme')),
            findsOneWidget,
          );
          expect(requests, 3);
          await probe.finish();
        });
      }
    }
  }
}
