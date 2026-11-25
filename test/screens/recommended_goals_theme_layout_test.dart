import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/recommended_goals.dart';
import 'package:duoyi/core/recommended_goals_ui_copy.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/screens/recommended_goals_picker.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

const _categories = [
  GoalCategory.recommend,
  GoalCategory.health,
  GoalCategory.study,
  GoalCategory.sport,
  GoalCategory.emotion,
];

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'recommended-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final goals = GoalProvider();
          addTearDown(goals.dispose);
          var writes = 0;
          goals.onLocalMutationPersisted = () => writes++;
          final boundary = await mountPriorityFixture(
            tester,
            auth: AuthProvider(),
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: ChangeNotifierProvider<GoalProvider>.value(
              value: goals,
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      key: const ValueKey('open_recommended_theme'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BrandRouteSurface(
                            child: RecommendedGoalsPicker(),
                          ),
                        ),
                      ),
                      child: const Text('Open synthetic recommendations'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(
            find.byKey(const ValueKey('open_recommended_theme')),
          );
          await tester.pumpAndSettle();
          final picker = find.byType(RecommendedGoalsPicker);
          final retainedState = tester.state(picker);
          final probe = RouteRenderProbe(tester, boundary, name);

          void collectFramework(String stage) {
            Object? error;
            while ((error = tester.takeException()) != null) {
              probe.errors.add('$stage: $error');
            }
          }

          Future<void> select(GoalCategory category) async {
            final chip = find.byKey(
              ValueKey('recommended-category-${category.name}'),
            );
            await Scrollable.ensureVisible(tester.element(chip), alignment: .5);
            await tester.pumpAndSettle();
            await tester.tap(chip);
            await tester.pumpAndSettle();
            expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
          }

          Future<void> measure(String stage) async {
            await probe.text(
              find.text(RecommendedGoalsUiCopy.title),
              role: '$stage route title',
              minimumGeometricScale: .999,
            );
            for (final category in _categories) {
              await select(category);
              final chip = find.byKey(
                ValueKey('recommended-category-${category.name}'),
              );
              await probe.text(
                find.descendant(
                  of: chip,
                  matching: find.text(
                    RecommendedGoalsUiCopy.category(category),
                  ),
                ),
                role: '$stage selected category ${category.name}',
                minimumGeometricScale: .999,
              );
              final list = find.byKey(
                PageStorageKey('recommended-goal-list-${category.name}'),
              );
              final scroll = find.descendant(
                of: list,
                matching: find.byType(Scrollable),
              );
              tester.state<ScrollableState>(scroll).position.jumpTo(0);
              await tester.pumpAndSettle();
              final templates = RecommendedGoalsLibrary.byCategory(category);
              for (final goal in templates) {
                final card = find.byKey(
                  ValueKey('recommended-goal-${goal.id}'),
                );
                await tester.scrollUntilVisible(
                  card,
                  120,
                  scrollable: scroll,
                  maxScrolls: 100,
                );
                final texts = tester
                    .widgetList<Text>(
                      find.descendant(of: card, matching: find.byType(Text)),
                    )
                    .toList();
                expect(
                  texts.map((t) => t.data),
                  containsAll([goal.localizedTitle, goal.localizedDescription]),
                );
                if (identical(goal, templates.first)) {
                  await probe.reveal(
                    find.descendant(
                      of: card,
                      matching: find.text(goal.localizedTitle),
                    ),
                  );
                  await probe.capture('$stage-${category.name}-title');
                }
                for (var i = 0; i < texts.length; i++) {
                  final text = texts[i];
                  final finder = find.descendant(
                    of: card,
                    matching: find.byWidgetPredicate(
                      (widget) => identical(widget, text),
                    ),
                  );
                  await probe.text(
                    finder,
                    role: '$stage ${goal.id} text $i',
                    minimumGeometricScale: .999,
                  );
                  // Words that fit the full padded card must not split merely
                  // because side controls squeeze them into a narrow column.
                  final paragraph = tester.renderObject<RenderParagraph>(
                    find.descendant(
                      of: finder,
                      matching: find.byType(RichText),
                    ),
                  );
                  final available = tester.getSize(card).width - 32;
                  final broken = <String>[];
                  for (final match in RegExp(
                    r"[A-Za-z]+(?:’[A-Za-z]+)?",
                  ).allMatches(text.data!)) {
                    final word = match.group(0)!;
                    final painter = TextPainter(
                      text: TextSpan(text: word, style: paragraph.text.style),
                      textDirection: paragraph.textDirection,
                      textScaler: paragraph.textScaler,
                    )..layout();
                    final fitsCard = painter.width <= available + .1;
                    painter.dispose();
                    final boxes = paragraph.getBoxesForSelection(
                      TextSelection(
                        baseOffset: match.start,
                        extentOffset: match.end,
                      ),
                    );
                    final lineTops = boxes
                        .map((box) => (box.top * 100).round())
                        .toSet();
                    if (fitsCard && lineTops.length > 1) broken.add(word);
                  }
                  probe.rows.add({
                    'role': '$stage ${goal.id} text $i word layout',
                    'text': text.data,
                    'availableCardTextWidth': available,
                    'brokenFittingWords': broken,
                  });
                  if (broken.isNotEmpty) {
                    probe.errors.add(
                      '$stage ${goal.id} text $i: '
                      'fitting words split: ${broken.join(', ')}',
                    );
                  }
                }
                final add = tester.widget<IconButton>(
                  find.byKey(ValueKey('recommended-add-${goal.id}')),
                );
                expect(add.onPressed, isNotNull);
                expect(add.tooltip, RecommendedGoalsUiCopy.add);
                if (identical(goal, templates.first)) {
                  await probe.capture('$stage-${category.name}-first');
                }
                collectFramework('$stage ${goal.id}');
              }
            }
          }

          await measure('initial');
          await select(GoalCategory.study);
          final list = find.byKey(
            const PageStorageKey('recommended-goal-list-study'),
          );
          final scroll = find.descendant(
            of: list,
            matching: find.byType(Scrollable),
          );
          final scrollState = tester.state<ScrollableState>(scroll);
          final position = scrollState.position;
          position.jumpTo(32);
          await tester.pumpAndSettle();
          final beforeOffset = position.pixels;
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          expect(tester.state(picker), same(retainedState));
          expect(tester.state<ScrollableState>(scroll), same(scrollState));
          final afterOffset = scrollState.position.pixels;
          expect(afterOffset, closeTo(beforeOffset, .1));
          expect(
            tester
                .widget<ChoiceChip>(
                  find.byKey(const ValueKey('recommended-category-study')),
                )
                .selected,
            isTrue,
          );
          probe.rows.add({
            'role': 'mounted locale retention',
            'samePickerState': true,
            'sameScrollableState': true,
            'selectedCategory': 'study',
            'beforeScrollOffset': beforeOffset,
            'afterScrollOffset': afterOffset,
          });
          await measure('live');
          expect(goals.goals, isEmpty);
          expect(writes, 0);
          collectFramework('final');
          await probe.finish();
        });
      }
    }
  }
}
