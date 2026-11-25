// Actual collapsed editor surfaces, complete copy and retained draft in both priority themes.
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/screens/goal_edit_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

const _headers = <(String, String)>[
  ('空间归属', 'Workspace'),
  ('重复规则', 'Repeat rule'),
  ('调度模式', 'Scheduling'),
  ('跳过节假日', 'Skip holidays'),
  ('专注联动', 'Focus integration'),
  ('提醒', 'Reminders'),
  ('目标时长', 'Target duration'),
  ('每日次数', 'Daily count'),
  ('里程碑与进度', 'Milestones and progress'),
];

BoxDecoration? _sectionDecoration(Element element) {
  BoxDecoration? result;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    final decoration = widget is DecoratedBox
        ? widget.decoration
        : widget is Ink
        ? widget.decoration
        : null;
    if (decoration is BoxDecoration && decoration.borderRadius != null) {
      result = decoration;
      return false;
    }
    return true;
  });
  return result;
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'collapsed-goal-$brand-${locale.name}-${layout.name}';
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
                    id: 'synthetic-collapsed-sections',
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
          const draftTitle = 'Unsaved visual draft / 尚未保存';
          await tester.enterText(find.byType(TextField).first, draftTitle);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          expect(title.text, draftTitle);
          expect(writes, 0);
          final titleValue = title.value;
          final probe = RouteRenderProbe(tester, boundary, name);
          void checkNaturalText(Finder finder, String role, double fontSize) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: finder, matching: find.byType(RichText)),
            );
            final actualFontSize = paragraph.text.style!.fontSize!;
            final expectedSize = MediaQuery.textScalerOf(
              tester.element(finder),
            ).scale(fontSize);
            final actualSize = paragraph.textScaler.scale(actualFontSize);
            probe.rows.add({
              'role': '$role natural text scaling',
              'designFontSize': fontSize,
              'actualFontSize': actualFontSize,
              'expectedRenderedSize': expectedSize,
              'actualRenderedSize': actualSize,
            });
            if ((actualFontSize - fontSize).abs() > .01 ||
                (actualSize - expectedSize).abs() > .01) {
              probe.errors.add(
                '$role changes the intended font size or text scaler',
              );
            }
          }

          Future<void> inspect(String stage) async {
            final scrollable = find
                .descendant(of: route, matching: find.byType(Scrollable))
                .first;
            tester.state<ScrollableState>(scrollable).position.jumpTo(0);
            await tester.pumpAndSettle();
            for (final pair in _headers) {
              final label = I18n.current == AppLocale.en ? pair.$2 : pair.$1;
              final heading = find.text(label);
              await tester.scrollUntilVisible(
                heading,
                180,
                scrollable: scrollable,
              );
              expect(heading, findsOneWidget);
              await probe.text(
                heading,
                role: '$stage $label heading',
                minimumGeometricScale: .999,
              );
              checkNaturalText(
                heading,
                '$stage $label heading',
                DesignTokens.fontSizeMd,
              );
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: heading, matching: find.byType(RichText)),
              );
              if (I18n.current == AppLocale.en) {
                for (final match in RegExp(r'[A-Za-z]+').allMatches(label)) {
                  final word = match.group(0)!;
                  final painter = TextPainter(
                    text: TextSpan(text: word, style: paragraph.text.style),
                    textDirection: Directionality.of(tester.element(heading)),
                    textScaler: MediaQuery.textScalerOf(
                      tester.element(heading),
                    ),
                    locale: Localizations.localeOf(tester.element(heading)),
                    maxLines: 1,
                  )..layout();
                  if (painter.width > paragraph.size.width + .1) {
                    probe.errors.add(
                      '$stage $label splits fitting word $word: '
                      '${painter.width} > ${paragraph.size.width}',
                    );
                  }
                  painter.dispose();
                }
              }
              final tileFinder = find
                  .ancestor(of: heading, matching: find.byType(ExpansionTile))
                  .first;
              final tile = tester.widget<ExpansionTile>(tileFinder);
              expect(tile.initiallyExpanded, isFalse);
              final tileElement = tester.element(tileFinder);
              final surface = appSurfaceStyleOf(tileElement)!;
              final decoration = _sectionDecoration(tileElement);
              final radius = decoration?.borderRadius?.resolve(
                Directionality.of(tileElement),
              );
              final themed =
                  decoration != null &&
                  decoration.color == surface.cardFillColor &&
                  decoration.gradient == null &&
                  decoration.border == surface.cardBorder &&
                  radius == BorderRadius.circular(surface.cardRadius);
              probe.rows.add({
                'role': '$stage $label theme card surface',
                'actualFillARGB': decoration?.color?.toARGB32(),
                'expectedFillARGB': surface.cardFillColor?.toARGB32(),
                'actualBorder': decoration?.border.toString(),
                'expectedBorder': surface.cardBorder.toString(),
                'actualRadius': radius.toString(),
                'expectedRadius': surface.cardRadius,
                'matchesThemeSurface': themed,
              });
              if (!themed) {
                probe.errors.add(
                  '$stage $label card surface does not match $brand',
                );
              }
              final subtitle = tile.subtitle;
              expect(subtitle, isA<Text>());
              final subtitleFinder = find.byWidget(subtitle!);
              await probe.text(
                subtitleFinder,
                role: '$stage $label complete summary',
                minimumGeometricScale: .999,
              );
              checkNaturalText(
                subtitleFinder,
                '$stage $label summary',
                DesignTokens.fontSizeSm,
              );
              if (stage == 'initial' &&
                  pair.$2 == 'Scheduling' &&
                  ['common', 'large', 'landscape'].contains(layout.name)) {
                await Scrollable.ensureVisible(tileElement, alignment: .4);
                await tester.pumpAndSettle();
                await probe.capture('collapsed-scheduling');
              }
            }
          }

          await inspect('initial');
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          expect(tester.state(route), same(retainedState));
          expect(title.value, titleValue);
          expect(writes, 0);
          await inspect('switched');
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
