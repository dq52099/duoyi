import 'dart:convert';
import 'dart:math' as math;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/screens/goal_edit_screen.dart';
import 'package:duoyi/screens/goal_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'goal-list-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final items = [
            for (var i = 0; i < GoalStatus.values.length; i++)
              GoalItem(
                id: 'synthetic-goal-$i',
                title: 'Plan $i 原文',
                description: 'Draft $i 原文',
                status: GoalStatus.values[i],
                colorValue: [0xFFFFA726, 0xFF26A69A, 0xFF7E57C2, 0xFF42A5F5][i],
                autoProgress: false,
                progress: [.35, .60, 1.0, .10][i],
                targetDate: i == 0
                    ? null
                    : today.add(Duration(days: i == 1 ? -42 : 365)),
                workspaceId: i == 3 ? 'synthetic-shared' : 'private',
                milestones: [
                  GoalMilestone(
                    id: 'done-$i',
                    title: 'First',
                    isCompleted: true,
                  ),
                  GoalMilestone(id: 'next-$i', title: 'Next'),
                ],
              ),
          ];
          final provider = GoalProvider();
          final auth = AuthProvider();
          var writes = 0;
          provider.onLocalMutationPersisted = () => writes++;
          addTearDown(provider.dispose);
          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<GoalProvider>.value(value: provider),
                ChangeNotifierProvider(
                  create: (_) => CustomFocusSoundProvider(),
                ),
              ],
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      key: const ValueKey('open_goal_list_theme'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const BrandRouteSurface(child: GoalScreen()),
                        ),
                      ),
                      child: const Text('Open synthetic goals'),
                    ),
                  ),
                ),
              ),
            ),
          );
          SharedPreferences.setMockInitialValues({
            'active_brand': brand,
            'duoyi_goals': items.map((g) => jsonEncode(g.toJson())).toList(),
          });
          await tester.runAsync(
            () =>
                provider.loadFromStorage().timeout(const Duration(seconds: 10)),
          );
          await tester.pumpAndSettle();
          expect(provider.goals, hasLength(4));
          final before = jsonEncode(
            provider.goals.map((g) => g.toJson()).toList(),
          );
          await tester.tap(find.byKey(const ValueKey('open_goal_list_theme')));
          await tester.pumpAndSettle();
          final element = tester.element(find.byType(GoalScreen));
          final probe = RouteRenderProbe(tester, boundary, name);
          final routeContext = tester.element(find.byType(GoalScreen));
          final routeTheme = Theme.of(routeContext);
          final surface = appSurfaceStyleOf(routeContext);
          final fill = surface?.cardFillColor ?? routeTheme.colorScheme.surface;
          var shadowedBackdrop = routeTheme.scaffoldBackgroundColor;
          for (final shadow in surface?.cardShadow ?? const <BoxShadow>[]) {
            shadowedBackdrop = Color.alphaBlend(shadow.color, shadowedBackdrop);
          }
          probe.rows.add({
            'role': 'theme surface facts',
            'scaffoldARGB': routeTheme.scaffoldBackgroundColor.toARGB32(),
            'fillARGB': fill.toARGB32(),
            'shadowARGB': [
              for (final shadow in surface?.cardShadow ?? const <BoxShadow>[])
                shadow.color.toARGB32(),
            ],
            'fullShadowCoverageCompositeARGB': Color.alphaBlend(
              fill,
              shadowedBackdrop,
            ).toARGB32(),
          });
          Future<void> records(String stage) async {
            final scroll = find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first;
            tester.state<ScrollableState>(scroll).position.jumpTo(0);
            await tester.pumpAndSettle();
            final sorted = provider.goals;
            for (var i = 0; i < sorted.length; i++) {
              final item = sorted[i];
              final title = find.text(item.title);
              await tester.scrollUntilVisible(
                title,
                120,
                scrollable: scroll,
                maxScrolls: 40,
              );
              final card = find
                  .ancestor(of: title, matching: find.byType(AppSurfaceCard))
                  .first;
              final status = I18n.tr('goal.status.${item.status.name}');
              final days = item.daysRemaining;
              final deadline = item.targetDate == null
                  ? (I18n.current == AppLocale.en ? 'No deadline' : '无期限')
                  : days >= 0
                  ? '${I18n.tr('goal.days_remaining.prefix')}$days${I18n.tr('goal.days_remaining.suffix')}'
                  : '${I18n.tr('goal.overdue.prefix')}${-days}${I18n.tr('goal.overdue.suffix')}';
              for (final (value, role) in [
                (item.description, 'description'),
                (status, 'status ${item.status.name}'),
                (
                  '${(item.computedProgress * 100).toStringAsFixed(0)}%',
                  'progress',
                ),
                ('${I18n.tr('goal.milestone.prefix')}1/2', 'milestones'),
                (deadline, 'deadline'),
                if (i == 3)
                  (
                    I18n.current == AppLocale.en ? 'Shared' : '共享',
                    'shared owner',
                  ),
              ]) {
                await probe.text(
                  find.descendant(of: card, matching: find.text(value)),
                  role: '$stage $role',
                  allowPreviewEllipsis: role == 'description',
                  minimumGeometricScale: .999,
                );
              }
              await probe.capture('$stage-card-$i');
            }
            final position = tester.state<ScrollableState>(scroll).position;
            position.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();
            final last = sorted.last;
            final lastCard = find
                .ancestor(
                  of: find.text(last.title),
                  matching: find.byType(AppSurfaceCard),
                )
                .first;
            final viewport = tester.getRect(find.byType(ListView));
            final fab = tester.getRect(find.byType(FloatingActionButton));
            for (final value in [
              '${I18n.tr('goal.milestone.prefix')}1/2',
              '${I18n.tr('goal.days_remaining.prefix')}${last.daysRemaining}${I18n.tr('goal.days_remaining.suffix')}',
            ]) {
              final rect = tester.getRect(
                find.descendant(of: lastCard, matching: find.text(value)),
              );
              final clear =
                  !rect.overlaps(fab) &&
                  rect.top >= viewport.top &&
                  rect.bottom <= viewport.bottom;
              probe.rows.add({
                'role': '$stage trailing metadata',
                'text': value,
                'fullyVisibleWithoutFabOverlap': clear,
              });
              if (!clear) {
                probe.errors.add('$stage trailing metadata obscured: $value');
              }
            }
            await probe.capture('$stage-scroll-end');
          }

          await records('initial');
          final scroll = find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first;
          final retainedPosition = tester
              .state<ScrollableState>(scroll)
              .position;
          // Use an interior offset: translated cards can change the final
          // scroll extent, which legitimately clamps an end-of-list offset.
          retainedPosition.jumpTo(
            math.min(80.0, retainedPosition.maxScrollExtent * .2),
          );
          await tester.pumpAndSettle();
          final offset = retainedPosition.pixels;
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          final retainedElement = tester.element(find.byType(GoalScreen));
          final retainedOffset = tester
              .state<ScrollableState>(scroll)
              .position
              .pixels;
          final sameElement = identical(retainedElement, element);
          probe.rows.add({
            'role': 'mounted locale retention',
            'sameElement': sameElement,
            'beforeScrollOffset': offset,
            'afterScrollOffset': retainedOffset,
          });
          if (!sameElement || (retainedOffset - offset).abs() > .1) {
            probe.errors.add(
              'mounted locale remounts goal list or resets scroll',
            );
          }
          await records('live');
          final listException = tester.takeException();
          if (listException != null) {
            probe.errors.add('goal list framework: $listException');
          }
          tester.state<ScrollableState>(scroll).position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.tap(find.text(items.first.title));
          await tester.pumpAndSettle();
          expect(find.byType(GoalEditScreen), findsOneWidget);
          expect(
            find.widgetWithText(TextField, items.first.title),
            findsOneWidget,
          );
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(
            tester.element(find.byType(GoalScreen)),
            same(retainedElement),
          );
          expect(
            jsonEncode(provider.goals.map((g) => g.toJson()).toList()),
            before,
          );
          expect(writes, 0);
          final editorException = tester.takeException();
          if (editorException != null) {
            probe.errors.add(
              'goal editor roundtrip framework: $editorException',
            );
          }
          await probe.finish();
        });
      }
    }
  }
}
