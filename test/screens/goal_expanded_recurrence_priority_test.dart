// Actual expanded repeat guidance in both priority themes and retained locales.
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/screens/goal_edit_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'expanded-repeat-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final goals = GoalProvider();
          final sounds = CustomFocusSoundProvider();
          addTearDown(goals.dispose);
          addTearDown(sounds.dispose);
          var writes = 0;
          goals.onLocalMutationPersisted = () => writes++;
          final boundary = await mountPriorityFixture(
            tester,
            auth: AuthProvider(),
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<GoalProvider>.value(value: goals),
                ChangeNotifierProvider<CustomFocusSoundProvider>.value(
                  value: sounds,
                ),
              ],
              child: BrandRouteSurface(
                child: GoalEditScreen(
                  goal: GoalItem(
                    id: 'synthetic-expanded-repeat',
                    title: 'Literal goal / 自定义目标',
                    createdAt: DateTime(2026, 1, 1),
                  ),
                ),
              ),
            ),
          );
          final route = find.byType(GoalEditScreen);
          final retainedState = tester.state(route);
          final title = tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!;
          final titleValue = title.value;
          final heading = find.text(
            locale == AppLocale.en ? 'Repeat rule' : '重复规则',
          );
          final scrollable = find
              .descendant(of: route, matching: find.byType(Scrollable))
              .first;
          await tester.scrollUntilVisible(heading, 180, scrollable: scrollable);
          await tester.pumpAndSettle();
          await Scrollable.ensureVisible(
            tester.element(heading),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          expect(heading.hitTestable(), findsOneWidget);
          await tester.tap(heading);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Expanding the actual repeat section must fit $name',
          );
          final probe = RouteRenderProbe(tester, boundary, name);
          Future<void> measure(String stage) async {
            final label = find.text(
              I18n.current == AppLocale.en
                  ? 'Next scheduled date: '
                  : '下一次派发日：',
            );
            final callout = find
                .ancestor(of: label, matching: find.byType(Container))
                .first;
            final paragraphs = find.descendant(
              of: callout,
              matching: find.byType(Text),
            );
            expect(paragraphs, findsNWidgets(2));
            for (var i = 0; i < 2; i++) {
              await probe.text(
                paragraphs.at(i),
                role: '$stage next scheduled date paragraph $i',
                minimumGeometricScale: .999,
              );
            }
            await Scrollable.ensureVisible(
              tester.element(callout),
              alignment: .5,
            );
            await tester.pumpAndSettle();
            if (stage == 'initial' &&
                ['common', 'large', 'landscape'].contains(layout.name)) {
              await probe.capture('expanded-repeat');
            }
          }

          await measure('initial');
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Locale switching must fit $name',
          );
          expect(tester.state(route), same(retainedState));
          expect(title.value, titleValue);
          expect(writes, 0);
          await measure('switched');
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(tester.state(route), same(retainedState));
          expect(title.value, titleValue);
          expect(writes, 0);
          expect(goals.goals, isEmpty);
          await probe.finish();
        });
      }
    }
  }
}
