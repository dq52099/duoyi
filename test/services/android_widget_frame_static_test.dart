import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _nativeRoot = 'android/app/src/main/kotlin/com/duoyi/duoyi/';

String _source(String name) => File('$_nativeRoot$name.kt').readAsStringSync();

void main() {
  test(
    'primary widget fitting uses scaled metrics before frame acceptance',
    () {
      final source = _source('DuoyiWidgetSnapshot');
      expect(source, contains('finishRender(context, built.views, frame)'));
      expect(
        source.indexOf('finishRender(context, built.views, frame)'),
        lessThan(source.indexOf('val reason = frame.core.rejectionReason(')),
      );
      expect(source, contains('fitPrimaryWidget(context, views, frame)'));
      expect(source, contains('TypedValue.COMPLEX_UNIT_SP, sp, metrics'));
      expect(source, contains('font.bottom - font.top'));
      expect(source, contains('(dp * metrics.density).roundToInt()'));
      expect(source, contains('visibility(plan.rows[slot])'));
      final todoMarker = 'if (views.layoutId == R.layout.duoyi_todo_widget ||\n'
          '            views.layoutId == R.layout.duoyi_todo_widget_reflow) {';
      final todoStart = source.indexOf(todoMarker);
      expect(todoStart, greaterThanOrEqualTo(0));
      final habitStart = source.indexOf(
        '} else if (views.layoutId == R.layout.duoyi_habit_widget) {',
        todoStart,
      );
      expect(habitStart, greaterThan(todoStart));
      final goalStart = source.indexOf(
        '} else if (views.layoutId == R.layout.duoyi_goal_widget) {',
        habitStart,
      );
      expect(goalStart, greaterThan(habitStart));
      final todo = source.substring(todoStart, habitStart);
      final habit = source.substring(habitStart, goalStart);

      final todoRequired = todo.indexOf('val requiredRow1Fits = requiredHeaderFits &&');
      expect(todoRequired, greaterThanOrEqualTo(0));
      final todoFailure = todo.indexOf('if (!requiredRow1Fits) {', todoRequired);
      expect(todoFailure, greaterThan(todoRequired));
      final todoInputs = todo.substring(0, todoRequired);
      expect(todoInputs, contains('val plan = if (requiredHeaderFits) {'));
      expect(todoInputs, contains('textMetrics.measureWrapped(itemTitle, 12f, usableTextWidth)'));
      expect(todoInputs, contains('val rowFitsWidth = rowMeasurements.map { it.second }'));
      expect(todoInputs, contains('maxOf(38, maxOf(naturalFrame, textHeight)) to (measurement?.fits == true)'));
      final todoRequiredGate = todo.substring(todoRequired, todoFailure);
      expect(
        todoRequiredGate,
        contains('val requiredRow1Fits = requiredHeaderFits &&\n'
            '                rowFitsWidth.getOrElse(0) { false } &&\n'
            '                (plan?.rows?.getOrElse(0) { false } == true)'),
      );
      final todoRestoreMarker = '} else {\n'
          '                val nonNullPlan = plan!!\n'
          '                views.setViewVisibility(R.id.widget_todo_recovery, View.GONE)\n'
          '                views.setContentDescription(R.id.widget_todo_root, null)';
      final todoRestore = todo.indexOf(todoRestoreMarker, todoFailure);
      expect(todoRestore, greaterThan(todoFailure));
      final failedTodo = todo.substring(todoFailure, todoRestore);
      final restoredTodo = todo.substring(todoRestore);
      for (final binding in [
        'val showRow1 = nonNullPlan.rows[0]',
        'val showRow2 = nonNullPlan.rows[1] && rowFitsWidth[1]',
        'val showRow3 = nonNullPlan.rows[2] && (!hasSecondaryRows[0] || showRow2) && rowFitsWidth[2]',
        'val visibleRows = booleanArrayOf(showRow1, showRow2, showRow3)',
        'val allAdmittedRowsShown = (0..2).all { slot -> !nonNullPlan.rows[slot] || visibleRows[slot] }',
        'val showSummary = nonNullPlan.showSummary && allAdmittedRowsShown && frame.fresh',
        'val showNavigation = nonNullPlan.showNavigation && allAdmittedRowsShown',
        'R.id.widget_todo_today_summary, visibility(showSummary)',
        'R.id.widget_todo_bottom_nav, visibility(showNavigation)',
      ]) {
        expect(restoredTodo, contains(binding));
      }

      final habitRequired = habit.indexOf('val requiredContextFits =');
      expect(habitRequired, greaterThanOrEqualTo(0));
      final habitFailure = habit.indexOf('if (!requiredHabitFits) {', habitRequired);
      expect(habitFailure, greaterThan(habitRequired));
      final habitInputs = habit.substring(0, habitRequired);
      for (final binding in [
        'val hint = DuoyiWidgetCopy.habitQuickCheckLabel(rawHint, isZh)',
        'val hasHint = hint.isNotBlank()',
        'val hintFits = hintMeasurement?.fits == true',
        'textMetrics.measureWrapped(summaryText, 12f, contentWidth)',
        'val summaryFits = summaryMeasurement?.fits == true',
      ]) {
        expect(habitInputs, contains(binding));
      }
      final habitRequiredGate = habit.substring(habitRequired, habitFailure);
      for (final gate in [
        'val requiredContextFits = if (hasHint) hintFits else summaryFits',
        'val requiredContextHeight = if (hasHint) hintHeight + 6 else habitSummaryHeight',
        'val strictlyRequiredFitsInHeight = available >= padding * 2 + requiredHeaderHeight + 10 + requiredContextHeight + 2',
        'val strictlyRequiredFits = requiredHeaderWidthFits && requiredContextFits && strictlyRequiredFitsInHeight',
        'if (!strictlyRequiredFits) {',
        'requiredHabitFits = false',
        'requiredHabitFits = true',
      ]) {
        expect(habitRequiredGate, contains(gate));
      }
      final habitRestoreMarker = '} else {\n'
          '                views.setViewVisibility(R.id.widget_habit_recovery, View.GONE)\n'
          '                views.setContentDescription(R.id.widget_habit_root, null)';
      final habitRestore = habit.indexOf(habitRestoreMarker, habitFailure);
      expect(habitRestore, greaterThan(habitFailure));
      final failedHabit = habit.substring(habitFailure, habitRestore);
      final restoredHabit = habit.substring(habitRestore);
      expect(failedHabit, isNot(contains('DuoyiWidgetLayoutPolicy.habit(')));
      for (final binding in [
        'DuoyiWidgetLayoutPolicy.habit(',
        'frame.core.effectiveMode, width, height',
        'requiredHeaderFits = requiredHabitFits',
        'val wantsStreak = !noHabitsToday && frame.core.effectiveMode != "compact"',
        'val showHint = plan.showHint',
        'val showSummary = plan.showSummary && summaryFits',
        'val showStreak = plan.showStreak && showSummary && streakFits',
        'val showSubtitle = plan.showSubtitle && showSummary && (!wantsStreak || showStreak) && subtitleFits',
        'val showNavigation = plan.showNavigation && showSummary && (!wantsStreak || showStreak) && showSubtitle',
        'R.id.widget_habit_summary, visibility(showSummary)',
        'R.id.widget_habit_hint, visibility(showHint)',
        'R.id.widget_habit_body, visibility(showSummary || showStreak || showHint)',
        'R.id.widget_habit_bottom_nav, visibility(showNavigation)',
      ]) {
        expect(restoredHabit, contains(binding));
      }
      for (final id in [
        'header', 'title', 'unit', 'count', 'quick_add', 'row_1', 'row_2',
        'row_3', 'done_1', 'done_2', 'done_3', 'today_summary', 'spacer', 'bottom_nav',
      ]) {
        expect(failedTodo, contains('R.id.widget_todo_$id, View.GONE'));
      }
      for (final id in [
        'header', 'title', 'percent', 'subtitle', 'body', 'summary', 'streak',
        'hint', 'spacer', 'bottom_nav',
      ]) {
        expect(failedHabit, contains('R.id.widget_habit_$id, View.GONE'));
      }
      for (final entry in <String, String>{
        'todo': failedTodo,
        'habit': failedHabit,
      }.entries) {
        final kind = entry.key;
        final failed = entry.value;
        expect(failed, contains('R.id.widget_refresh, View.GONE'));
        expect(failed, contains('DuoyiWidgetCopy.${kind}RecoveryText(isZh)'));
        expect(failed, contains('textMetrics.measureWrapped(recoveryText, 12f, contentWidth)'));
        expect(
          failed,
          contains('val recoveryFits = contentWidth > 0 && recoveryMeasurement.fits &&\n'
              '                    available >= padding * 2 + recoveryMeasurement.height'),
        );
        expect(failed, contains('DuoyiWidgetCopy.${kind}NoFitContentDescription('));
        expect(failed, contains('frame.fresh, isZh, frame.core.publicationState, recoveryVisible = recoveryFits'));
        expect(failed, contains('if (recoveryFits) {'));
        expect(failed, contains('R.id.widget_${kind}_recovery, View.VISIBLE'));
        expect(failed, contains('R.id.widget_${kind}_recovery, recoveryText'));
        expect(failed, contains('R.id.widget_${kind}_recovery, recoveryDesc'));
        expect(failed, contains('R.id.widget_${kind}_recovery, View.GONE'));
        expect(failed, contains('R.id.widget_${kind}_root, recoveryDesc'));
      }

      final policy = _source('DuoyiWidgetLayoutPolicy');
      final rowLimitStart = policy.indexOf('private fun rowLimit(mode: String): Int = when (mode) {');
      expect(rowLimitStart, greaterThanOrEqualTo(0));
      final rowLimitEnd = policy.indexOf('fun heightOrDefault(', rowLimitStart);
      expect(rowLimitEnd, greaterThan(rowLimitStart));
      expect(policy.substring(rowLimitStart, rowLimitEnd), contains('"compact" -> 1'));
      final todoPolicyStart = policy.indexOf('fun todo(');
      expect(todoPolicyStart, greaterThanOrEqualTo(0));
      final habitPolicyStart = policy.indexOf('fun habit(', todoPolicyStart);
      expect(habitPolicyStart, greaterThan(todoPolicyStart));
      final todoPolicy = policy.substring(todoPolicyStart, habitPolicyStart);
      for (final gate in [
        'val present = slot == 0 || secondaryRows.getOrElse(slot - 1) { false }',
        '!present || slot >= rowLimit(mode)',
        'val wantsSummary = mode == "detailed"',
        'val summary = wantsSummary && allRows && used + summaryCost <= available',
        'mode != "compact" && requiredHeaderFits && allRows && (!wantsSummary || summary)',
      ]) {
        expect(todoPolicy, contains(gate));
      }
      final habitPolicyEndMarker =
          'return Habit(padding, subtitle, summary, streak, hint, navigation, used)\n    }';
      final habitPolicyEnd = policy.indexOf(habitPolicyEndMarker, habitPolicyStart);
      expect(habitPolicyEnd, greaterThan(habitPolicyStart));
      final habitPolicy = policy.substring(
        habitPolicyStart,
        habitPolicyEnd + habitPolicyEndMarker.length,
      );
      for (final gate in [
        'val hint = hasHint && used + hintCost <= available',
        'val summary = used + effectiveSummaryHeight <= available',
        'val wantsStreak = hasStreak && mode != "compact"',
        'mode != "compact" && requiredHeaderFits && (!hasHint || hint) && summary',
      ]) {
        expect(habitPolicy, contains(gate));
      }
      expect(source, contains('hint.isNotBlank()'));
      expect(
        habitInputs,
        contains('val hintMeasurement = if (hasHint && contentWidth > 0) {\n'
            '                textMetrics.measureWrappedAction(\n'
            '                    hint, 11f, contentWidth,\n'
            '                    minWidthDp = 0, minHeightDp = 36,\n'
            '                    horizontalPaddingDp = 0, verticalPaddingDp = 0,\n'
            '                )\n'
            '            } else null'),
      );
      expect(restoredHabit, contains('hasHint, !noHabitsToday,'));
      expect(restoredHabit, contains('hintHeight = hintHeight,'));
      expect(
        restoredHabit,
        contains('views.setViewVisibility(R.id.widget_habit_hint, visibility(showHint))'),
      );
    },
  );

  test('narrow todo header keeps the add action accessible', () {
    final source = _source('DuoyiWidgetSnapshot');
    final todoMarker = 'if (views.layoutId == R.layout.duoyi_todo_widget ||\n'
        '            views.layoutId == R.layout.duoyi_todo_widget_reflow) {';
    final todoStart = source.indexOf(todoMarker);
    expect(todoStart, greaterThanOrEqualTo(0));
    final habitStart = source.indexOf(
      '} else if (views.layoutId == R.layout.duoyi_habit_widget) {',
      todoStart,
    );
    expect(habitStart, greaterThan(todoStart));
    final todo = source.substring(todoStart, habitStart);
    final headerStart = todo.indexOf('if (isReflow) {');
    expect(headerStart, greaterThanOrEqualTo(0));
    final normalMarker = '} else {\n'
        '                val quickAddMeasurement = textMetrics.measureSingleLine(';
    final normalStart = todo.indexOf(normalMarker, headerStart);
    expect(normalStart, greaterThan(headerStart));
    final headerEnd = todo.indexOf(
      'val doneFrameWidth = maxOf(38, textMetrics.width("○", 14f))',
      normalStart,
    );
    expect(headerEnd, greaterThan(normalStart));
    final common = todo.substring(0, headerStart);
    final reflow = todo.substring(headerStart, normalStart);
    final normal = todo.substring(normalStart, headerEnd);
    for (final binding in [
      'val quickAdd = DuoyiWidgetCopy.todoQuickAdd(isZh)',
      'views.setContentDescription(R.id.widget_todo_quick_add, quickAdd)',
      'views.setTextViewText(R.id.widget_todo_quick_add, quickAdd)',
      'val isReflow = views.layoutId == R.layout.duoyi_todo_widget_reflow',
      'val baseHeader = if (width in 1..151) 34 else 36',
      'val countMeasurement = textMetrics.measureSingleLine(visibleCount, 14f, contentWidth)',
      'val refreshMeasurement = textMetrics.measureSingleLine("↻", 14f, contentWidth, minWidthDp = 36, minHeightDp = 36)',
      'val available = DuoyiWidgetLayoutPolicy.heightOrDefault(height, frame.core.effectiveMode)',
    ]) {
      expect(common, contains(binding));
    }
    final reflowFailure = reflow.indexOf('if (!strictlyRequiredFits) {');
    expect(reflowFailure, greaterThanOrEqualTo(0));
    final normalFailure = normal.indexOf('if (!strictlyRequiredFits) {');
    expect(normalFailure, greaterThanOrEqualTo(0));
    final reflowGate = reflow.substring(0, reflowFailure);
    final normalGate = normal.substring(0, normalFailure);
    expect(
      reflowGate,
      contains('val quickAddMeasurement = textMetrics.measureWrappedAction(\n'
          '                    quickAdd, 11f, contentWidth,\n'
          '                    minWidthDp = 44, minHeightDp = 34,\n'
          '                    horizontalPaddingDp = 16, verticalPaddingDp = 0,\n'
          '                )'),
    );
    for (final gate in [
      'val row2Fits = contentWidth > 0 && quickAddMeasurement.fits',
      'val row2Height = if (row2Fits) quickAddMeasurement.height else 0',
      'val requiredRow1Width = countMeasurement.width + 4 + refreshMeasurement.width',
      'val requiredRow1Height = maxOf(baseHeader, countMeasurement.height, refreshMeasurement.height)',
      'val requiredRow1Fits = contentWidth > 0 && requiredRow1Width <= contentWidth &&\n'
          '                    countMeasurement.fits && refreshMeasurement.fits',
      'val strictlyRequiredHeaderHeight = requiredRow1Height + 4 + row2Height',
      'val strictlyRequiredFitsInHeight = available >= padding * 2 + strictlyRequiredHeaderHeight + 2',
      'val strictlyRequiredFits = requiredRow1Fits && row2Fits && strictlyRequiredFitsInHeight',
    ]) {
      expect(reflowGate, contains(gate));
    }
    expect(
      normalGate,
      contains('val quickAddMeasurement = textMetrics.measureSingleLine(\n'
          '                    quickAdd, 11f, contentWidth,\n'
          '                    minWidthDp = 44, minHeightDp = 34,\n'
          '                    horizontalPaddingDp = 16,\n'
          '                )'),
    );
    for (final gate in [
      'val minimalRequiredWidth = countMeasurement.width + 6 + quickAddMeasurement.width + 4 + refreshMeasurement.width',
      'val requiredRowHeight = maxOf(baseHeader, countMeasurement.height, quickAddMeasurement.height, refreshMeasurement.height)',
      'val strictlyRequiredFitsInHeight = available >= padding * 2 + requiredRowHeight + 2',
      'val strictlyRequiredRowFits = contentWidth > 0 && minimalRequiredWidth <= contentWidth &&\n'
          '                    countMeasurement.fits && quickAddMeasurement.fits && refreshMeasurement.fits',
      'val strictlyRequiredFits = strictlyRequiredRowFits && strictlyRequiredFitsInHeight',
    ]) {
      expect(normalGate, contains(gate));
    }
    final successMarker = '} else {\n'
        '                    showCount = true\n'
        '                    showQuickAdd = true';
    final reflowSuccess = reflow.indexOf(successMarker, reflowFailure);
    expect(reflowSuccess, greaterThan(reflowFailure));
    final normalSuccess = normal.indexOf(successMarker, normalFailure);
    expect(normalSuccess, greaterThan(normalFailure));
    final failedReflow = reflow.substring(reflowFailure, reflowSuccess);
    final failedNormal = normal.substring(normalFailure, normalSuccess);
    final admittedReflow = reflow.substring(reflowSuccess);
    final admittedNormal = normal.substring(normalSuccess);
    for (final failed in [failedReflow, failedNormal]) {
      for (final binding in [
        'showTitle = false', 'showUnit = false', 'showCount = false',
        'showQuickAdd = false', 'headerHeight = 0', 'requiredHeaderFits = false',
      ]) {
        expect(failed, contains(binding));
      }
    }
    for (final admitted in [admittedReflow, admittedNormal]) {
      for (final binding in [
        'showCount = true', 'showQuickAdd = true',
        'val titleFitsWidth = width !in 1..179 && availableTitleWidth > 0 &&\n'
            '                        textMetrics.fitsSingleLine(titleText, 14f, availableTitleWidth)',
        'val titleMeasurement = if (titleFitsWidth) textMetrics.measureSingleLine(titleText, 14f, availableTitleWidth) else null',
        'val titleFits = titleFitsWidth && titleMeasurement != null && titleMeasurement.fits && titleFitsHeight',
        'showTitle = titleFits', 'requiredHeaderFits = true',
      ]) {
        expect(admitted, contains(binding));
      }
    }
    expect(
      admittedReflow,
      contains('val availableTitleWidth = contentWidth - (6 + countMeasurement.width + effectiveUnitWidth + 4 + refreshMeasurement.width)'),
    );
    expect(admittedReflow, contains('val headerHeightWithTitle = row1HeightWithTitle + 4 + row2Height'));
    expect(admittedReflow, contains('val titleFitsHeight = available >= padding * 2 + headerHeightWithTitle + 2'));
    expect(
      admittedNormal,
      contains('val availableTitleWidth = contentWidth - (6 + countMeasurement.width + effectiveUnitWidth + 6 + quickAddMeasurement.width + 4 + refreshMeasurement.width)'),
    );
    expect(admittedNormal, contains('val titleFitsHeight = available >= padding * 2 + rowHeightWithTitle + 2'));

    final requiredStart = todo.indexOf('val requiredRow1Fits = requiredHeaderFits &&');
    expect(requiredStart, greaterThan(headerEnd));
    final failureStart = todo.indexOf('if (!requiredRow1Fits) {', requiredStart);
    expect(failureStart, greaterThan(requiredStart));
    expect(
      todo.substring(requiredStart, failureStart),
      contains('val requiredRow1Fits = requiredHeaderFits &&\n'
          '                rowFitsWidth.getOrElse(0) { false } &&\n'
          '                (plan?.rows?.getOrElse(0) { false } == true)'),
    );
    final restoreMarker = '} else {\n'
        '                val nonNullPlan = plan!!\n'
        '                views.setViewVisibility(R.id.widget_todo_recovery, View.GONE)\n'
        '                views.setContentDescription(R.id.widget_todo_root, null)';
    final restoreStart = todo.indexOf(restoreMarker, failureStart);
    expect(restoreStart, greaterThan(failureStart));
    final failedContent = todo.substring(failureStart, restoreStart);
    final restoredContent = todo.substring(restoreStart);
    for (final id in [
      'header', 'title', 'unit', 'count', 'quick_add', 'row_1', 'row_2', 'row_3',
      'done_1', 'done_2', 'done_3', 'today_summary', 'spacer', 'bottom_nav',
    ]) {
      expect(failedContent, contains('R.id.widget_todo_$id, View.GONE'));
    }
    expect(failedContent, contains('R.id.widget_refresh, View.GONE'));
    expect(failedContent, contains('DuoyiWidgetCopy.todoRecoveryText(isZh)'));
    expect(failedContent, contains('textMetrics.measureWrapped(recoveryText, 12f, contentWidth)'));
    expect(
      failedContent,
      contains('val recoveryFits = contentWidth > 0 && recoveryMeasurement.fits &&\n'
          '                    available >= padding * 2 + recoveryMeasurement.height'),
    );
    expect(failedContent, contains('DuoyiWidgetCopy.todoNoFitContentDescription('));
    expect(failedContent, contains('frame.fresh, isZh, frame.core.publicationState, recoveryVisible = recoveryFits'));
    expect(failedContent, contains('if (recoveryFits) {'));
    expect(failedContent, contains('R.id.widget_todo_recovery, View.VISIBLE'));
    expect(failedContent, contains('R.id.widget_todo_recovery, View.GONE'));
    expect(failedContent, contains('R.id.widget_todo_recovery, recoveryText'));
    expect(failedContent, contains('R.id.widget_todo_recovery, recoveryDesc'));
    expect(failedContent, contains('R.id.widget_todo_root, recoveryDesc'));
    for (final binding in [
      'R.id.widget_todo_recovery, View.GONE', 'R.id.widget_todo_root, null',
      'views.setViewVisibility(R.id.widget_todo_header, View.VISIBLE)',
      'views.setViewVisibility(R.id.widget_todo_title, visibility(showTitle))',
      'views.setViewVisibility(R.id.widget_todo_count, visibility(showCount))',
      'views.setViewVisibility(R.id.widget_todo_quick_add, visibility(showQuickAdd))',
      'views.setViewVisibility(R.id.widget_refresh, View.VISIBLE)',
    ]) {
      expect(restoredContent, contains(binding));
    }

    final routeStart = source.indexOf('fun needsTodoReflow(context: Context, frame: DuoyiWidgetRenderFrame): Boolean {');
    expect(routeStart, greaterThanOrEqualTo(0));
    final routeEnd = source.indexOf(
      '/** Fit real content before optional navigation; all intents remain provider-owned. */',
      routeStart,
    );
    expect(routeEnd, greaterThan(routeStart));
    expect(routeEnd, lessThan(todoStart));
    final route = source.substring(routeStart, routeEnd);
    for (final binding in [
      'val quickAdd = DuoyiWidgetCopy.todoQuickAdd(isZh)',
      'val quickAddWidth = maxOf(44, textMetrics.width(quickAdd, 11f) + 16)',
      'val refreshWidth = maxOf(36, refreshGlyphWidth)',
      'val minimalHeaderWidth = countWidth + 6 + quickAddWidth + 4 + refreshWidth',
      'return contentWidth > 0 && minimalHeaderWidth > contentWidth',
    ]) {
      expect(route, contains(binding));
    }
    expect(
      source,
      contains('setContentDescription(R.id.widget_todo_quick_add, quickAdd)'),
    );
    final layout = File(
      'android/app/src/main/res/layout/duoyi_todo_widget.xml',
    ).readAsStringSync();
    final add = RegExp(
      r'<TextView\s+android:id="@\+id/widget_todo_quick_add"[^>]+>',
    ).firstMatch(layout)!.group(0)!;
    expect(add, contains('android:minWidth="44dp"'));
    expect(add, contains('android:layout_height="wrap_content"'));
    expect(add, contains('android:minHeight="34dp"'));
    expect(layout, contains('@+id/widget_todo_content'));
    expect(
      File(
        'android/app/src/main/res/layout/duoyi_habit_widget.xml',
      ).readAsStringSync(),
      contains('@+id/widget_habit_content'),
    );
  });

  test('five text-list layouts fit raw source slots before optional details', () {
    final source = _source('DuoyiWidgetSnapshot');
    expect(source, contains('views.layoutId in textLists'));

    final goalStart = source.indexOf('} else if (views.layoutId == R.layout.duoyi_goal_widget) {');
    final genericStart = source.indexOf('val spec = textLists[views.layoutId] ?: return', goalStart);
    expect(goalStart, greaterThanOrEqualTo(0));
    expect(genericStart, greaterThan(goalStart));
    final goal = source.substring(goalStart, genericStart);
    final generic = source.substring(genericStart);
    expect(generic, contains('DuoyiWidgetLayoutPolicy.textList('));
    expect(
      generic,
      contains(
        r'!prefs.getString("${spec.keyPrefix}_highlight_$slot", "").isNullOrBlank()',
      ),
    );
    expect(generic, contains('padding(spec.contentId, plan.padding)'));
    expect(generic, contains('spec.rowIds.forEachIndexed { slot, viewId ->'));
    expect(
      generic,
      contains(
        'setViewVisibility(spec.subtitleId, visibility(plan.showSubtitle))',
      ),
    );
    expect(
      generic,
      contains(
        'setViewVisibility(spec.navigationId, visibility(plan.showNavigation))',
      ),
    );

    expect(goal, isNot(contains('DuoyiWidgetLayoutPolicy.textList(')));
    final goalPlanStart = goal.indexOf('val plan = DuoyiWidgetLayoutPolicy.goal(');
    final goalFailure = goal.indexOf('if (!plan.requiredContentFits) {', goalPlanStart);
    expect(goalPlanStart, greaterThanOrEqualTo(0));
    expect(goalFailure, greaterThan(goalPlanStart));
    final goalPlan = goal.substring(goalPlanStart, goalFailure);
    for (final binding in [
      'mode = frame.core.effectiveMode', 'headerHeight = headerHeight',
      'rowHeights = rowHeights', 'rowFitsWidth = rowFitsWidth', 'secondaryRows = hasSecondaryRows',
      'subtitleHeight = subtitleMeasurement?.height ?: smallLine',
      'subtitleFitsWidth = subtitleMeasurement?.fits == true',
      'navigationHeight = navigationHeight', 'navigationFitsWidth = navigationFitsWidth',
      'requiredHeaderFits = refreshFits && available >= padding * 2 + headerHeight + 10 + 2',
    ]) {
      expect(goalPlan, contains(binding));
    }
    for (var slot = 1; slot <= 3; slot++) {
      expect(goal, contains('DuoyiWidgetCopy.goalHighlight$slot(prefs.getString("goal_highlight_$slot", null), isZh)'));
    }
    expect(goal, contains(r'!prefs.getString("goal_highlight_$slot", "").isNullOrBlank()'));
    expect(goal, contains('index > 0 && !hasSecondaryRows[index - 1]'));
    expect(goal, contains('val sp = if (index == 2) 11f else 12f'));
    expect(goal, contains('textMetrics.measureWrapped(text, sp, contentWidth)'));
    expect(goal, contains('val rowHeights = slotMeasurements.map { it?.height ?: 0 }'));
    expect(goal, contains('val rowFitsWidth = slotMeasurements.map { it?.fits == true }'));
    final restoreMarker = '} else {\n'
        '                views.setViewVisibility(R.id.widget_goal_recovery, View.GONE)\n'
        '                views.setContentDescription(R.id.widget_goal_root, null)';
    final goalRestore = goal.indexOf(restoreMarker, goalFailure);
    expect(goalRestore, greaterThan(goalFailure));
    final failedGoal = goal.substring(goalFailure, goalRestore);
    final restoredGoal = goal.substring(goalRestore);
    for (final id in ['header', 'title', 'subtitle', 'body', '1', '2', '3', 'bottom_nav']) {
      expect(failedGoal, contains('R.id.widget_goal_$id, View.GONE'));
    }
    expect(failedGoal, contains('R.id.widget_refresh, View.GONE'));
    expect(failedGoal, contains('DuoyiWidgetCopy.goalRecoveryText(isZh)'));
    expect(failedGoal, contains('textMetrics.measureWrapped(recoveryText, 12f, contentWidth)'));
    expect(failedGoal, contains('contentWidth > 0 && recoveryMeasurement.fits &&'));
    expect(failedGoal, contains('available >= padding * 2 + recoveryMeasurement.height'));
    expect(failedGoal, contains('if (recoveryFits) {'));
    expect(failedGoal, contains('R.id.widget_goal_recovery, View.VISIBLE'));
    expect(failedGoal, contains('R.id.widget_goal_recovery, View.GONE'));
    expect(failedGoal, contains('DuoyiWidgetCopy.goalNoFitContentDescription('));
    expect(failedGoal, contains('frame.fresh, isZh, frame.core.publicationState, recoveryVisible = recoveryFits'));
    expect(failedGoal, contains('R.id.widget_goal_root, recoveryDesc'));
    expect(failedGoal, contains('Uri.parse("duoyi://goal")'));
    expect(failedGoal, contains('DuoyiWidgetTheme.read(prefs).text'));
    expect(restoredGoal, contains('R.id.widget_goal_root, null'));
    expect(restoredGoal, contains('R.id.widget_goal_recovery, View.GONE'));
    expect(restoredGoal, contains('R.id.widget_goal_body, View.VISIBLE'));
    for (var slot = 0; slot < 3; slot++) {
      expect(restoredGoal, contains('R.id.widget_goal_${slot + 1}, visibility(plan.rows[$slot])'));
    }
    expect(restoredGoal, contains('R.id.widget_goal_subtitle, visibility(plan.showSubtitle)'));
    expect(restoredGoal, contains('R.id.widget_goal_bottom_nav, visibility(plan.showNavigation)'));
    final policy = _source('DuoyiWidgetLayoutPolicy');
    final policyStart = policy.indexOf('fun goal(');
    final policyEnd = policy.indexOf('data class Todo(', policyStart);
    expect(policyStart, greaterThanOrEqualTo(0));
    expect(policyEnd, greaterThan(policyStart));
    final goalPolicy = policy.substring(policyStart, policyEnd);
    for (final gate in [
      'slot == 0 || secondaryRows.getOrElse(slot - 1) { false }',
      '!present || slot >= rowLimit(mode)',
      'rowFitsWidth.getOrElse(slot) { false }',
      'precedingRowsFit && fitsWidth && used + rowCost <= available',
      '(slot > 0 && !secondaryRows.getOrElse(slot - 1) { false }) || rows[slot]',
      'val requiredContentFits = rows[0] && allRows', 'if (!requiredContentFits)',
      'subtitleFitsWidth && used + subtitleCost <= available',
      'mode != "compact" && showSubtitle &&',
      'return Goal(padding, rows, showSubtitle, showNavigation, used, true)',
    ]) {
      expect(goalPolicy, contains(gate));
    }
    expect(RegExp(RegExp.escape('return Goal(padding, listOf(false, false, false), false, false, padding * 2, false)')).allMatches(goalPolicy), hasLength(2));
    for (final kind in ['schedule', 'course', 'goal', 'note', 'diary']) {
      final smallThird = ['schedule', 'course', 'goal'].contains(kind);
      final descriptor = RegExp(
        'R\\.layout\\.duoyi_${kind}_widget to TextListViews\\(([\\s\\S]*?)\\n        \\)',
      ).firstMatch(source)!.group(1)!;
      expect(descriptor, contains('"$kind", R.id.widget_${kind}_content'));
      expect(descriptor, contains('R.id.widget_${kind}_subtitle'));
      expect(
        descriptor,
        contains('R.id.widget_${kind}_bottom_nav, $smallThird,'),
      );
      for (var slot = 1; slot <= 3; slot++) {
        expect(descriptor, contains('R.id.widget_${kind}_$slot'));
      }
      final xml = File(
        'android/app/src/main/res/layout/duoyi_${kind}_widget.xml',
      ).readAsStringSync();
      expect(xml, contains('@+id/widget_${kind}_content'));
      final thirdRow = RegExp(
        '<TextView\\s+android:id="@\\+id/widget_${kind}_3"[^>]+>',
      ).firstMatch(xml)!.group(0)!;
      expect(
        thirdRow,
        contains('android:textSize="${smallThird ? 11 : 12}sp"'),
      );
      expect(thirdRow, contains('android:layout_marginTop="6dp"'));
    }
  });

  test('all eleven actual renderers submit through captured frames', () {
    const providers = [
      'DuoyiWidgetProvider',
      'DuoyiTodoWidgetProvider',
      'DuoyiHabitWidgetProvider',
      'DuoyiFocusHabitWidgetProvider',
      'DuoyiCalendarWidgetProvider',
      'DuoyiAnniversaryWidgetProvider',
      'DuoyiGoalWidgetProvider',
      'DuoyiScheduleWidgetProvider',
      'DuoyiCourseWidgetProvider',
      'DuoyiNoteWidgetProvider',
      'DuoyiDiaryWidgetProvider',
    ];
    for (final name in providers) {
      final source = _source(name);
      expect(
        source,
        contains('DuoyiWidgetSnapshot.renderWidget('),
        reason: name,
      );
      expect(source, contains('val prefs = frame.prefs'), reason: name);
      expect(source, contains('DuoyiWidgetBuiltViews(views'), reason: name);
      expect(source, isNot(contains('updateAppWidget(')), reason: name);
      expect(source, isNot(contains('forDisplay(')), reason: name);
      expect(source, isNot(contains('getAppWidgetOptions(')), reason: name);
      expect(source, isNot(contains('actionUri(prefs,')), reason: name);
    }
  });

  test('snapshot initializes styles before reading the native publication', () {
    final source = _source('DuoyiWidgetSnapshot');
    expect(
      source,
      contains('saveForWidgetIfMissing(backing, id, initialStyle)'),
    );
    const capture = 'capture = { store.read(nonBlocking = true) }';
    expect(source, contains(capture));
    expect(source.indexOf('saveForWidgetIfMissing('), lessThan(source.indexOf(capture)));
    expect(
      source,
      contains('Looper.myLooper() != android.os.Looper.getMainLooper()'),
    );
    expect(source, contains('read.envelope?.document?.toFlatValues()'));
    expect(
      source,
      contains('DuoyiWidgetFrameCore.deviceDisplayValues(backing.all, id)'),
    );
    expect(source, isNot(contains('display[key]?.let { raw[key] = it }')));
    expect(source, contains('DuoyiWidgetFrameAttempts.run('));
    expect(source, contains('store.acceptSnapshot(read.envelope)'));
    expect(source, contains('frame.core.rejectionReason(values(latest'));
    expect(source, contains('manager.updateAppWidget(id, built.views)'));
    expect(
      source,
      contains('canBuild = { read -> read.status != "busy" }'),
    );
    expect(source, contains('commit = { read, (_, built) ->'));
    expect(source, isNot(contains('SharedPreferences by backing')));
    expect(source, isNot(contains('.putString(')));
    expect(source, isNot(contains('requestUpdateForAllWidgets(')));
  });

  test('raw values and dimensions are checked before any accepted effect', () {
    final source = _source('DuoyiWidgetFrameCore');
    expect(source, contains('rawValues != currentValues'));
    expect(source, contains('options != currentOptions'));
    expect(source, contains('clock.zone != currentClock.zone'));
    expect(source, contains('clock.day != currentClock.day'));
    expect(
      source,
      contains('clock.offsetMinutes != currentClock.offsetMinutes'),
    );
    expect(source, contains('systemLocaleTag != currentSystemLocaleTag'));
    expect(source, contains('return "timer_expired"'));
    expect(source, contains('repeat(2)'));
    expect(
      source.indexOf('commit(frame, views)'),
      lessThan(source.indexOf('acceptedEffect(frame, views)')),
    );
  });

  test('frozen preferences cover all reads and deny generic editing', () {
    final source = _source('DuoyiFrozenWidgetPreferences');
    for (final method in [
      'getAll',
      'contains',
      'getString',
      'getStringSet',
      'getInt',
      'getLong',
      'getFloat',
      'getBoolean',
      'edit',
    ]) {
      expect(source, contains('override fun $method('));
    }
    expect(source, contains('DuoyiWidgetFrameCore.immutableValues(values)'));
    expect(source, contains('throw UnsupportedOperationException('));
    expect(source, isNot(contains('backing')));
    final projection = _source('DuoyiWidgetRenderFrame');
    expect(projection, contains('!core.sessionTrusted'));
    expect(projection, contains('it.startsWith("focus_timer_")'));
    expect(projection, isNot(contains('endsWith("_id")')));
  });

  test(
    'focus uses frozen clock values and defers its existing alarm effect',
    () {
      final source = _source('DuoyiFocusHabitWidgetProvider');
      expect(source, contains('val now = frame.wallMillis'));
      expect(source, contains('val base = frame.elapsedMillis'));
      expect(source, contains('-(now - startedAt).coerceAtLeast(0L)'));
      expect(
        source,
        contains('currentTimerRemainingSeconds(prefs, timerRunning, now)'),
      );
      expect(
        source,
        contains('DuoyiWidgetBuiltViews(views, timerAlarmEffect)'),
      );
      expect(
        source,
        contains('val timerAlarmEffect: (() -> Unit)? = if (sessionTrusted)'),
      );
      expect(source, contains('} else null'));
      expect(source, contains('getBroadcast(context, 14101'));
      expect(source, isNot(contains('SystemClock.elapsedRealtime()')));
      expect(source, isNot(contains('Date()')));
    },
  );

  test('all mutation entry points require the captured fresh session', () {
    expect(_source('DuoyiWidgetSnapshot'), contains('require(frame.fresh)'));
    expect(
      _source('DuoyiWidgetProvider'),
      contains('if (frame.fresh) DuoyiWidgetSnapshot.actionUri(frame,'),
    );
    expect(
      _source('DuoyiTodoWidgetProvider'),
      contains('if (!frame.fresh || todoId.isBlank())'),
    );
    expect(
      _source('DuoyiHabitWidgetProvider'),
      contains('if (frame.fresh && habitQuickCheckId.isNotBlank())'),
    );
    expect(
      _source('DuoyiFocusHabitWidgetProvider'),
      contains('if (frame.fresh && !storedRunning)'),
    );
  });
}
