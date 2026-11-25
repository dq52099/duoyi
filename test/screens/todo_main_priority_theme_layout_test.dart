import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/completion_visibility_policy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/models/goal.dart' show ReminderConfig;
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

const taskPendingTitle = '固定待办：准备评审';
const taskOverdueTitle = '固定逾期：回顾日志';
const taskCompletedTitle = '固定完成：提交周报';

class _TodoRenderProbe extends RouteRenderProbe {
  _TodoRenderProbe(super.tester, super.boundary, super.name);

  @override
  Future<void> reveal(Finder finder) async {
    expect(finder, findsOneWidget);
    final element = tester.element(finder);
    final vertical = Scrollable.maybeOf(element, axis: Axis.vertical);
    if (vertical != null) {
      await vertical.position.ensureVisible(
        element.findRenderObject()!,
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
    }
    final horizontal = Scrollable.maybeOf(element, axis: Axis.horizontal);
    if (horizontal != null) {
      await horizontal.position.ensureVisible(
        element.findRenderObject()!,
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
    }
  }

  @override
  Future<void> text(
    Finder finder, {
    String? role,
    bool contrast = true,
    bool allowPreviewEllipsis = false,
    double? minimumGeometricScale,
    double? expectedBaseFontSize,
    TextScaler? expectedScaler,
  }) async {
    if (contrast && role != null && role.contains('completed badge')) {
      await super.text(
        finder,
        role: role,
        contrast: false,
        allowPreviewEllipsis: allowPreviewEllipsis,
        minimumGeometricScale: minimumGeometricScale,
      );

      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: finder, matching: find.byType(RichText)),
      );
      final style = paragraph.text.style!;
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rect = MatrixUtils.transformRect(
        paragraph.getTransformTo(render),
        Offset.zero & paragraph.size,
      );
      final label = (tester.widget(finder) as Text).data!;

      final pillBox = tester.renderObject<RenderBox>(
        find.ancestor(of: finder, matching: find.byType(DecoratedBox)).first,
      );
      final pillRect = MatrixUtils.transformRect(
        pillBox.getTransformTo(render),
        Offset.zero & pillBox.size,
      );

      final point = Offset(rect.right + 2, rect.center.dy);
      expect(point.dx > rect.right, isTrue, reason: 'point is past text right');
      expect(
        point.dx < pillRect.right,
        isTrue,
        reason: 'point is within pill right',
      );
      expect(
        point.dy > pillRect.top,
        isTrue,
        reason: 'point is within pill top',
      );
      expect(
        point.dy < pillRect.bottom,
        isTrue,
        reason: 'point is within pill bottom',
      );

      final captured = await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1);
        try {
          final raw = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final x = point.dx.floor(), y = point.dy.floor();
          expect(x, inInclusiveRange(0, image.width - 1), reason: label);
          expect(y, inInclusiveRange(0, image.height - 1), reason: label);
          final offset = (y * image.width + x) * 4;
          return Color.fromARGB(
            255,
            raw.getUint8(offset),
            raw.getUint8(offset + 1),
            raw.getUint8(offset + 2),
          );
        } finally {
          image.dispose();
        }
      });
      final background = captured!;
      final foreground = style.foreground?.color ?? style.color!;
      final a = Color.alphaBlend(foreground, background).computeLuminance();
      final b = background.computeLuminance();
      final ratio = (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
      final size = paragraph.textScaler.scale(style.fontSize!);
      final required = size >= 24 ? 3.0 : 4.5;
      rows.last.addAll({
        'foregroundARGB': foreground.toARGB32(),
        'backgroundARGB': background.toARGB32(),
        'sampleX': point.dx.floor(),
        'sampleY': point.dy.floor(),
        'ratio': ratio,
        'required': required,
        'renderedFontSize': size,
      });
      if (ratio < required) {
        errors.add('$role $label: contrast $ratio below $required');
      }
    } else {
      await super.text(
        finder,
        role: role,
        contrast: contrast,
        allowPreviewEllipsis: allowPreviewEllipsis,
        minimumGeometricScale: minimumGeometricScale,
      );
    }

    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)),
    );
    final style = paragraph.text.style!;
    final label = (tester.widget(finder) as Text).data!;
    if (expectedBaseFontSize != null) {
      if ((style.fontSize! - expectedBaseFontSize).abs() > 0.01) {
        errors.add(
          '$role $label: base font size ${style.fontSize} != $expectedBaseFontSize',
        );
      }
      expect(
        style.fontSize,
        closeTo(expectedBaseFontSize, 0.01),
        reason: '$role base font size',
      );
    }
    if (expectedBaseFontSize != null && expectedScaler != null) {
      final expectedScaled = expectedScaler.scale(expectedBaseFontSize);
      final renderedSize = paragraph.textScaler.scale(style.fontSize!);
      if ((renderedSize - expectedScaled).abs() > 0.05) {
        errors.add(
          '$role $label: scaled font size $renderedSize != $expectedScaled',
        );
      }
      expect(
        renderedSize,
        closeTo(expectedScaled, 0.05),
        reason: '$role scaled font size',
      );
      rows.last['expectedBaseFontSize'] = expectedBaseFontSize;
      rows.last['expectedScaledFontSize'] = expectedScaled;
      rows.last['actualScaledFontSize'] = renderedSize;
    }
  }
}

Future<void> _ensureVisibleInHeader(
  WidgetTester tester,
  Finder target, {
  double alignment = 0.5,
}) async {
  expect(target, findsOneWidget);
  final element = tester.element(target);
  final horizontal = Scrollable.maybeOf(element, axis: Axis.horizontal);
  final verticalTarget =
      horizontal?.context.findRenderObject() ?? element.findRenderObject()!;
  final vertical = Scrollable.maybeOf(element, axis: Axis.vertical);
  if (vertical != null) {
    await vertical.position.ensureVisible(
      verticalTarget,
      alignment: alignment,
    );
    await tester.pumpAndSettle();
  }
  if (horizontal != null) {
    await horizontal.position.ensureVisible(
      element.findRenderObject()!,
      alignment: alignment,
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _revealListRow(
  WidgetTester tester,
  Finder list,
  Finder row,
) async {
  final scrollable = find.descendant(
    of: list,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);
  final scrollableState = tester.state<ScrollableState>(scrollable);
  scrollableState.position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(row, 80, scrollable: scrollable);
  await tester.pumpAndSettle();
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
}

void main() {
  late AppLocale originalLocale;

  setUp(() {
    originalLocale = I18n.current;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    I18n.setLocale(originalLocale);
  });

  final targetLayouts = priorityLayouts.where(
    (layout) => const {
      'common',
      'large',
      'landscape',
      'nonlinear',
    }.contains(layout.name),
  );

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in [AppLocale.zh, AppLocale.en]) {
      for (final layout in targetLayouts) {
        final name = '$brand-${locale.name}-${layout.name}';
        testWidgets('todo main priority theme layout $name', (tester) async {
          final now = DateTime.now();
          final taskPending = TodoItem(
            id: 'fixture-todo-pending',
            title: taskPendingTitle,
            dueDate: now.add(const Duration(minutes: 45)),
            timeTargetSeconds: 25 * 60,
            reminder: const ReminderConfig(enabled: true, hour: 21, minute: 5),
            priority: TodoPriority.high,
            quadrant: EisenhowerQuadrant.urgentImportant,
            workspaceId: 'fixture-shared-space',
          );
          final taskOverdue = TodoItem(
            id: 'fixture-todo-overdue',
            title: taskOverdueTitle,
            dueDate: now.subtract(const Duration(hours: 2)),
            priority: TodoPriority.urgent,
            quadrant: EisenhowerQuadrant.urgentImportant,
          );
          final taskCompleted = TodoItem(
            id: 'fixture-todo-completed',
            title: taskCompletedTitle,
            isCompleted: true,
            completedAt: now,
            priority: TodoPriority.medium,
            quadrant: EisenhowerQuadrant.notUrgentImportant,
          );

          final todos = TodoProvider();
          await todos.addTodo(taskPending);
          await todos.addTodo(taskOverdue);
          await todos.addTodo(taskCompleted);

          final initialRevision = todos.revision;
          final initialJson = todos.todos
              .map((todo) => jsonEncode(todo.toJson()))
              .toList();

          final habits = HabitProvider();
          final goals = GoalProvider();
          final share = ShareProvider();
          final ai = AiService();
          final preferences = PreferencesProvider();
          await preferences.setShowCompletedTodos(true);

          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            todos.dispose();
            habits.dispose();
            goals.dispose();
            share.dispose();
            ai.dispose();
            preferences.dispose();
          });

          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient((_) async => fail('No fixture HTTP')),
            ),
          );

          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<TodoProvider>.value(value: todos),
                ChangeNotifierProvider<HabitProvider>.value(value: habits),
                ChangeNotifierProvider<GoalProvider>.value(value: goals),
                ChangeNotifierProvider<ShareProvider>.value(value: share),
                ChangeNotifierProvider<AiService>.value(value: ai),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences,
                ),
              ],
              child: const BrandRouteSurface(
                remountOnLocaleChange: false,
                child: TodoScreen(),
              ),
            ),
          );

          final probe = _TodoRenderProbe(tester, boundary, name);
          final initialError = tester.takeException();
          if (initialError != null) probe.errors.add('$initialError');

          final scaler = layout.scale < 0
              ? const RouteProbeNonlinearScaler()
              : TextScaler.linear(layout.scale);

          final screenState = tester.state(find.byType(TodoScreen));

          final initialAppBarTitle = AppBrands.byId(brand).strings.todoTitle;
          await probe.text(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text(initialAppBarTitle),
            ),
            role: 'app bar title ${locale.name}',
            minimumGeometricScale: 0.999,
            expectedBaseFontSize: 16.0,
            expectedScaler: scaler,
          );

          final todoCount = todos.todos
              .where(
                (todo) =>
                    CompletionVisibilityPolicy.shouldShowInToday(todo, now),
              )
              .length;
          final remaining = todoCount;

          await probe.text(
            find.text(TodoBoardUiCopy.todayRemainingTasks(remaining)),
            role: 'today remaining tasks summary',
            minimumGeometricScale: 0.999,
          );
          await probe.text(
            find.text(TodoBoardUiCopy.todaySummaryBreakdown(0, todoCount, 0)),
            role: 'today summary breakdown',
            minimumGeometricScale: 0.999,
          );

          for (final (label, role) in [
            (TodoBoardUiCopy.viewMatrix, 'view matrix'),
            (TodoBoardUiCopy.viewList, 'view list'),
            (TodoBoardUiCopy.viewKanban, 'view kanban'),
          ]) {
            await probe.text(
              find.descendant(
                of: find.byKey(const ValueKey('todo_view_switcher')),
                matching: find.text(label),
              ),
              role: role,
              minimumGeometricScale: 0.999,
            );
          }

          await probe.capture('matrix');

          final listSegment = find.descendant(
            of: find.byKey(const ValueKey('todo_view_switcher')),
            matching: find.text(TodoBoardUiCopy.viewList),
          );
          await probe.reveal(listSegment);
          await tester.tap(listSegment);
          await tester.pumpAndSettle();

          final switchError = tester.takeException();
          if (switchError != null) probe.errors.add('$switchError');

          final list = find.byKey(const ValueKey('todo_list_scroll'));
          expect(list, findsOneWidget);

          final ungroupedLabel = TodoBoardUiCopy.ungroupedListLabel;
          final ungroupedHeaderTitle = find.text(ungroupedLabel);
          expect(ungroupedHeaderTitle, findsOneWidget);
          await probe.text(
            ungroupedHeaderTitle,
            role: 'ungrouped list header ${locale.name}',
            minimumGeometricScale: 0.999,
            expectedBaseFontSize: 13.0,
            expectedScaler: scaler,
          );

          final pendingTile = find.byKey(
            ValueKey('list-todo-${taskPending.id}'),
          );
          await _revealListRow(tester, list, pendingTile);
          expect(
            find.descendant(
              of: pendingTile,
              matching: find.text(taskPendingTitle),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: pendingTile,
              matching: find.text(TodoBoardUiCopy.badgeDueSoon),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: pendingTile,
              matching: find.text(TodoBoardUiCopy.badgeTargetMinutes(25)),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: pendingTile,
              matching: find.text(TodoBoardUiCopy.badgeShared),
            ),
            findsOneWidget,
          );

          final overdueTile = find.byKey(
            ValueKey('list-todo-${taskOverdue.id}'),
          );
          await _revealListRow(tester, list, overdueTile);
          expect(
            find.descendant(
              of: overdueTile,
              matching: find.text(taskOverdueTitle),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: overdueTile,
              matching: find.text(TodoBoardUiCopy.badgeOverdue),
            ),
            findsOneWidget,
          );

          final completedTile = find.byKey(
            ValueKey('list-todo-${taskCompleted.id}'),
          );
          await _revealListRow(tester, list, completedTile);
          expect(
            find.descendant(
              of: completedTile,
              matching: find.text(taskCompletedTitle),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: completedTile,
              matching: find.text(TodoBoardUiCopy.cardCompletedBadge),
            ),
            findsOneWidget,
          );

          await probe.capture('list');

          final filterCompletedChipText = find.descendant(
            of: find.byType(FilterChip),
            matching: find.text(TodoBoardUiCopy.filterCompleted),
          );
          expect(filterCompletedChipText, findsOneWidget);
          final filterCompletedChip = find.ancestor(
            of: filterCompletedChipText,
            matching: find.byType(FilterChip),
          );
          expect(filterCompletedChip, findsOneWidget);
          await _ensureVisibleInHeader(
            tester,
            filterCompletedChip,
            alignment: 0.5,
          );
          await tester.tap(filterCompletedChip);
          await tester.pumpAndSettle();

          // Filtering keeps the lazy list mounted; reveal the remaining row
          // before querying its text, including the enlarged landscape case.
          await _revealListRow(tester, list, completedTile);

          final filterError = tester.takeException();
          if (filterError != null) probe.errors.add('$filterError');

          expect(find.text(taskCompletedTitle), findsOneWidget);
          expect(
            find.byKey(ValueKey('list-todo-${taskPending.id}')),
            findsNothing,
          );
          expect(
            find.byKey(ValueKey('list-todo-${taskOverdue.id}')),
            findsNothing,
          );
          expect(
            find.text(TodoBoardUiCopy.customViewTitle(1, 3)),
            findsOneWidget,
          );
          expect(find.text(TodoBoardUiCopy.clear), findsOneWidget);

          await probe.capture('filtered-initial');

          final otherLocale = locale == AppLocale.zh
              ? AppLocale.en
              : AppLocale.zh;
          I18n.setLocale(otherLocale);
          await tester.pumpAndSettle();

          final localeError = tester.takeException();
          if (localeError != null) probe.errors.add('$localeError');

          expect(tester.state(find.byType(TodoScreen)), same(screenState));
          expect(todos.revision, initialRevision);
          expect(
            todos.todos.map((todo) => jsonEncode(todo.toJson())).toList(),
            initialJson,
          );

          final otherCustomTitle = find.text(
            TodoBoardUiCopy.customViewTitle(1, 3),
          );
          final otherClear = find.text(TodoBoardUiCopy.clear);
          final otherCompletedBadge = find.descendant(
            of: completedTile,
            matching: find.text(TodoBoardUiCopy.cardCompletedBadge),
          );

          expect(otherCustomTitle, findsOneWidget);
          expect(otherClear, findsOneWidget);
          expect(otherCompletedBadge, findsOneWidget);
          expect(find.text(taskCompletedTitle), findsOneWidget);
          expect(
            find.byKey(ValueKey('list-todo-${taskPending.id}')),
            findsNothing,
          );
          expect(
            find.byKey(ValueKey('list-todo-${taskOverdue.id}')),
            findsNothing,
          );

          await probe.text(
            otherCustomTitle,
            role: 'filtered custom view title ${otherLocale.name}',
            minimumGeometricScale: 0.999,
            expectedBaseFontSize: 13.0,
            expectedScaler: scaler,
          );
          await probe.text(
            otherClear,
            role: 'filter clear action ${otherLocale.name}',
            minimumGeometricScale: 0.999,
          );
          await probe.text(
            otherCompletedBadge,
            role: 'completed badge ${otherLocale.name}',
            minimumGeometricScale: 0.999,
          );

          final otherAppBarTitle = AppBrands.byId(brand).strings.todoTitle;
          await probe.text(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text(otherAppBarTitle),
            ),
            role: 'app bar title ${otherLocale.name}',
            minimumGeometricScale: 0.999,
            expectedBaseFontSize: 16.0,
            expectedScaler: scaler,
          );

          await probe.capture('filtered-${otherLocale.name}');

          I18n.setLocale(locale);
          await tester.pumpAndSettle();

          final restoreLocaleError = tester.takeException();
          if (restoreLocaleError != null) {
            probe.errors.add('$restoreLocaleError');
          }

          expect(tester.state(find.byType(TodoScreen)), same(screenState));
          expect(todos.revision, initialRevision);
          expect(
            todos.todos.map((todo) => jsonEncode(todo.toJson())).toList(),
            initialJson,
          );

          final restoredCustomTitle = find.text(
            TodoBoardUiCopy.customViewTitle(1, 3),
          );
          final restoredClear = find.text(TodoBoardUiCopy.clear);
          final restoredCompletedBadge = find.descendant(
            of: completedTile,
            matching: find.text(TodoBoardUiCopy.cardCompletedBadge),
          );

          expect(restoredCustomTitle, findsOneWidget);
          expect(restoredClear, findsOneWidget);
          expect(restoredCompletedBadge, findsOneWidget);
          expect(find.text(taskCompletedTitle), findsOneWidget);
          expect(
            find.byKey(ValueKey('list-todo-${taskPending.id}')),
            findsNothing,
          );
          expect(
            find.byKey(ValueKey('list-todo-${taskOverdue.id}')),
            findsNothing,
          );

          await probe.text(
            restoredCustomTitle,
            role: 'filtered custom view title ${locale.name}',
            minimumGeometricScale: 0.999,
            expectedBaseFontSize: 13.0,
            expectedScaler: scaler,
          );
          await probe.text(
            restoredClear,
            role: 'filter clear action ${locale.name}',
            minimumGeometricScale: 0.999,
          );
          await probe.text(
            restoredCompletedBadge,
            role: 'completed badge ${locale.name}',
            minimumGeometricScale: 0.999,
          );

          final restoredAppBarTitle = AppBrands.byId(brand).strings.todoTitle;
          await probe.text(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text(restoredAppBarTitle),
            ),
            role: 'app bar title restored ${locale.name}',
            minimumGeometricScale: 0.999,
            expectedBaseFontSize: 16.0,
            expectedScaler: scaler,
          );

          await _ensureVisibleInHeader(tester, restoredClear);
          await tester.tap(restoredClear);
          await tester.pumpAndSettle();

          final clearError = tester.takeException();
          if (clearError != null) probe.errors.add('$clearError');

          expect(find.text(TodoBoardUiCopy.clear), findsNothing);
          expect(tester.state(find.byType(TodoScreen)), same(screenState));
          expect(todos.revision, initialRevision);
          expect(
            todos.todos.map((todo) => jsonEncode(todo.toJson())).toList(),
            initialJson,
          );

          await probe.capture('cleared');

          final finalError = tester.takeException();
          if (finalError != null) probe.errors.add('$finalError');

          for (final row in probe.rows) {
            for (final entry in row.entries.toList()) {
              final value = entry.value;
              if (value is double && !value.isFinite) {
                probe.errors.add('${row['role']} has no drawable area');
                row[entry.key] = null;
              }
            }
          }

          await probe.finish();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
