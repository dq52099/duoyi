import 'package:duoyi/core/almanac_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/almanac_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

class _AlmanacProbe extends RouteRenderProbe {
  _AlmanacProbe(super.tester, super.boundary, super.name);

  @override
  Future<void> reveal(Finder finder) async {
    expect(finder, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await tester.pumpAndSettle();
  }
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'almanac-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final boundary = await mountPriorityFixture(
            tester,
            auth: AuthProvider(),
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const ValueKey('open_almanac_theme'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BrandRouteSurface(
                        child: AlmanacScreen(
                          initialDate: DateTime(2026, 6, 28),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open synthetic almanac'),
                ),
              ),
            ),
          );
          await tester.tap(find.byKey(const ValueKey('open_almanac_theme')));
          await tester.pumpAndSettle();
          final state = tester.state(find.byType(AlmanacScreen));
          final probe = _AlmanacProbe(tester, boundary, name);
          void recordFrameworkErrors(String stage) {
            Object? error;
            while ((error = tester.takeException()) != null) {
              probe.errors.add('$stage: $error');
            }
          }

          recordFrameworkErrors('initial summary');
          Future<void> measureTextIn(Finder parent, String role) async {
            final texts = find
                .descendant(of: parent, matching: find.byType(Text))
                .evaluate()
                .map((element) => element.widget as Text)
                .toList();
            expect(texts, isNotEmpty);
            for (var i = 0; i < texts.length; i++) {
              final text = texts[i];
              if (text.data == null || text.data!.trim().isEmpty) continue;
              await probe.text(
                find.descendant(
                  of: parent,
                  matching: find.byWidgetPredicate(
                    (widget) => identical(widget, text),
                  ),
                ),
                role: '$role $i',
                minimumGeometricScale: .999,
              );
            }
          }

          final summary = find.byKey(
            const ValueKey('selected_date_almanac_summary_card'),
          );
          Future<void> mainChrome(String stage) async {
            await probe.text(
              find.text(AlmanacUiCopy.pageTitle),
              role: '$stage main title',
              minimumGeometricScale: .999,
            );
            final highlights = find.byWidgetPredicate(
              (widget) =>
                  widget.runtimeType.toString() == '_MonthHighlightsCard',
            );
            await measureTextIn(highlights, '$stage month highlights');
            recordFrameworkErrors('$stage main chrome');
            await probe.capture('$stage-highlights');
          }

          await mainChrome('initial');
          await measureTextIn(summary, 'initial selected summary');
          await probe.capture('initial-summary');
          await tester.tap(find.byTooltip(AlmanacUiCopy.nextDayTooltip));
          await tester.pumpAndSettle();
          recordFrameworkErrors('next day');
          await measureTextIn(summary, 'next-day selected summary');
          await probe.capture('next-day-summary');
          await probe.reveal(summary);
          await tester.tap(summary);
          await tester.pumpAndSettle();
          recordFrameworkErrors('opened detail');
          expect(find.byType(PageView), findsOneWidget);
          final pager = tester.element(find.byType(PageView));
          final controller = tester
              .widget<PageView>(find.byType(PageView))
              .controller!;
          final expectedPage = DateTime.utc(
            2026,
            6,
            29,
          ).difference(DateTime.utc(1900, 1, 1)).inDays;
          expect(controller.page, expectedPage.toDouble());
          Future<void> detail(String stage) async {
            for (final region in [
              ('_AlmanacDetailNavBar', 'title'),
              ('_DateHeroPanel', 'hero'),
              ('_VerticalYijiPanel', 'activities'),
              ('_ClassicalInfoTable', 'information'),
              ('_ClassicalHourRow', 'hours'),
            ]) {
              final panel = find.byWidgetPredicate(
                (widget) => widget.runtimeType.toString() == region.$1,
              );
              expect(panel, findsOneWidget);
              await measureTextIn(panel, '$stage detail ${region.$2}');
              recordFrameworkErrors('$stage detail ${region.$2}');
              await probe.capture('$stage-detail-${region.$2}');
            }
          }

          await detail('initial');
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          recordFrameworkErrors('live locale');
          expect(tester.element(find.byType(PageView)), same(pager));
          expect(
            tester.state(find.byType(AlmanacScreen, skipOffstage: false)),
            same(state),
          );
          expect(
            tester.widget<PageView>(find.byType(PageView)).controller,
            same(controller),
          );
          expect(controller.page, expectedPage.toDouble());
          probe.rows.add({
            'role': 'mounted locale retention',
            'sameMainState': true,
            'samePagerElement': true,
            'sameController': true,
            'selectedPage': controller.page,
            'expectedPage': expectedPage,
          });
          await detail('live');
          await tester.tap(find.byTooltip(AlmanacUiCopy.backTooltip));
          await tester.pumpAndSettle();
          recordFrameworkErrors('returned summary');
          expect(tester.state(find.byType(AlmanacScreen)), same(state));
          await mainChrome('live');
          await measureTextIn(summary, 'live selected summary');
          await probe.capture('live-summary');
          await probe.finish();
        });
      }
    }
  }
}
