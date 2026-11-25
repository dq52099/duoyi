import 'dart:io';

import 'package:test/test.dart';

void main() {
  const scopedScreens = [
    'lib/screens/admin_screen.dart',
    'lib/screens/preferences_screen.dart',
    'lib/screens/more_apps_screen.dart',
    'lib/screens/integrations_screen.dart',
    'lib/screens/calendar_screen.dart',
    'lib/screens/ai_schedule_screen.dart',
    'lib/screens/feedback_screen.dart',
    'lib/screens/notification_history_screen.dart',
    'lib/screens/search_screen.dart',
    'lib/screens/share_screen.dart',
    'lib/screens/profile_screen.dart',
    'lib/screens/widget_screen.dart',
    'lib/screens/anniversary_screen.dart',
    'lib/screens/countdown_screen.dart',
    'lib/screens/goal_edit_screen.dart',
  ];

  test('二级页面避免粗字重、大标题和厚边框回退', () {
    for (final path in scopedScreens) {
      final source = File(path).readAsStringSync();
      var renderedTypography = source;
      if (path == 'lib/screens/widget_screen.dart') {
        // Only this pure measurement helper may use system-requested bold.
        // It must match Text's accessibility rendering when choosing capacity.
        final start = source.indexOf('TextStyle _widgetMeasurementStyle(');
        final end = source.indexOf('\nAxis _widgetSegmentDirection(', start);
        expect(start, greaterThanOrEqualTo(0));
        expect(end, greaterThan(start));
        final measurementHelper = source.substring(start, end);
        expect(measurementHelper, contains('MediaQuery.boldTextOf(context)'));
        expect(
          measurementHelper,
          contains('MediaQuery.maybeLineHeightScaleFactorOverrideOf(context)'),
        );
        expect(measurementHelper, isNot(contains('Text(')));
        expect(measurementHelper, isNot(contains('Widget(')));
        renderedTypography = source.replaceRange(start, end, '');
      }
      expect(
        renderedTypography,
        isNot(matches(RegExp(r'FontWeight\.(bold|w700|w800|w900)'))),
        reason: '$path should use regular secondary-page typography',
      );
      expect(
        source,
        isNot(matches(RegExp(r'fontSize:\s*(?:19|[2-9]\d)'))),
        reason: '$path should not introduce large secondary-page titles',
      );
    }

    for (final path in [
      ...scopedScreens,
      'lib/widgets/surface_components.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final call in [
        ..._calls(source, 'Border.all('),
        ..._calls(source, 'BorderSide('),
      ]) {
        final width = RegExp(
          r'width:\s*([0-9]+(?:\.[0-9]+)?)',
        ).firstMatch(call);
        final widthName = RegExp(
          r'width:\s*([A-Za-z_]\w*)\s*[,)]',
        ).firstMatch(call)?.group(1);
        final constantWidth = widthName == null
            ? null
            : RegExp(
                'const double ${RegExp.escape(widthName)}'
                r'\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*;',
              ).firstMatch(source);
        final resolvedWidth = double.tryParse(
          width?.group(1) ?? constantWidth?.group(1) ?? '',
        );
        final sharedInputWidth = RegExp(
          r'OutlineInputBorder inputBorder\(Color color, \{double width = ([0-9]+(?:\.[0-9]+)?)\}\)',
        ).firstMatch(source);
        final usesSharedInputWidth =
            call.contains('width: width') &&
            sharedInputWidth != null &&
            double.parse(sharedInputWidth.group(1)!) <= 0.5;
        final usesWidgetThemeWidth =
            path == 'lib/screens/widget_screen.dart' &&
            call.contains('width: widgetTheme.borderWidthDp.toDouble()') &&
            source.contains('border: widgetTheme.borderWidthDp == 0') &&
            source.contains(
              'HomeWidgetThemePayload.fromThemeProvider(provider)',
            );
        expect(
          resolvedWidth != null || usesSharedInputWidth || usesWidgetThemeWidth,
          isTrue,
          reason: '$path uses default 1px border:\n$call',
        );
        if (resolvedWidth != null) {
          expect(
            resolvedWidth,
            lessThanOrEqualTo(0.6),
            reason: '$path uses a thick border:\n$call',
          );
        }
      }
    }
  });

  test('全局二级控件选中态和卡片边框保持轻量可读', () {
    final source = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();

    final surfaceCard = source.substring(
      source.indexOf('final surfaceColor'),
      source.indexOf('final content = Ink('),
    );
    expect(surfaceCard, contains('final cardBorderColor'));
    expect(surfaceCard, contains('DesignTokens.defaultBorder'));
    expect(surfaceCard, contains('width: 0.55'));
    expect(
      surfaceCard,
      matches(
        RegExp(
          r'boxShadow:\s*boxShadow\s*\?\?\s*\(\s*elevation\s*<=\s*0\s*'
          r'\?\s*\(surfaceStyle\?\.cardShadow\s*\?\?\s*const\s*\[\]\)'
          r'\s*:\s*\[\s*BoxShadow\(',
          dotAll: true,
        ),
      ),
      reason: 'Zero elevation uses only the theme shadow, otherwise no shadow',
    );
    expect(
      surfaceCard,
      isNot(contains('Colors.black.withValues(alpha: 0.05)')),
    );
    expect(surfaceCard, contains('final surfaceColor = color ?? cs.surface'));

    final controls = source.substring(
      source.indexOf('class AppSecondaryControlTheme'),
      source.indexOf('class AppSecondaryMenuText'),
    );
    expect(
      controls,
      contains(
        'OutlineInputBorder inputBorder(Color color, {double width = 0.35})',
      ),
    );
    expect(controls, contains('alpha: isDark ? 0.12 : 0.16'));
    expect(controls, contains('Color.alphaBlend('));
    expect(controls, contains('alpha: isDark ? 0.14 : 0.09'));
    expect(
      controls,
      contains('cs.primary.withValues(alpha: isDark ? 0.34 : 0.30)'),
    );
    expect(controls, contains('BorderSide(color: color, width: 0.4)'));
    expect(controls, contains('side: BorderSide(color: subtleBorder'));

    final selectedForeground = source.substring(
      source.indexOf('final selectedControlForeground'),
      source.indexOf('final selectedControlIcon'),
    );
    expect(selectedForeground, contains('selectedControlRenderedBackground'));
    expect(selectedForeground, contains('cs.onSurface'));
    expect(selectedForeground, isNot(contains('Colors.white')));
    expect(
      controls,
      isNot(
        contains('alpha: theme.brightness == Brightness.dark ? 0.22 : 0.12'),
      ),
    );

    final calendar = File(
      'lib/screens/calendar_screen.dart',
    ).readAsStringSync();
    final yearOverview = calendar.substring(
      calendar.indexOf('class _CalendarYearOverview'),
      calendar.indexOf('class _MonthDot'),
    );
    expect(yearOverview, contains('final selectedFill = Color.alphaBlend('));
    expect(yearOverview, contains('final selectedText = cs.onSurface'));
    expect(yearOverview, isNot(contains('cs.primaryContainer')));
    expect(yearOverview, isNot(contains('cs.onPrimaryContainer')));

    final goalEdit = File(
      'lib/screens/goal_edit_screen.dart',
    ).readAsStringSync();
    expect(goalEdit, contains('width: 0.45'));
    expect(goalEdit, isNot(matches(RegExp(r'width:\s*2(?:\.0)?\b'))));
    expect(goalEdit, isNot(contains('width: isSelected ? 1.6 : 1')));
  });

  test('管理后台分页条在窄屏保持全宽分组布局', () {
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();
    final pagination = admin.substring(
      admin.indexOf('class _AdminPaginationBar'),
      admin.indexOf('class _AdminPaginationLabeledControl'),
    );

    expect(
      pagination,
      contains("key: const ValueKey('admin_compact_pagination_full_width')"),
    );
    expect(
      pagination,
      contains('crossAxisAlignment: CrossAxisAlignment.stretch'),
    );
    expect(pagination, contains('WrapAlignment.spaceBetween'));
    expect(
      pagination,
      matches(RegExp(r'return SizedBox\(\s*width:\s*double\.infinity,')),
    );
    final compactControls = pagination.substring(
      pagination.indexOf("ValueKey('admin_compact_pagination_controls')"),
      pagination.indexOf('if (isCompact)'),
    );
    expect(compactControls, contains('?pageJump'));
    expect(compactControls, contains('?pageSizePicker'));
    expect(
      compactControls,
      contains('message: AdminUiCopy.paginationNavigationFor(locale)'),
    );
    expect(
      pagination,
      isNot(contains('BoxConstraints(maxWidth: 960)')),
      reason:
          'Desktop pagination must not collapse into a centered 960px strip.',
    );
    expect(
      pagination,
      isNot(contains("ValueKey('admin_compact_pagination_horizontal')")),
      reason: 'Compact pagination should not be a narrow horizontal strip.',
    );

    final primaryTabBar = admin.substring(
      admin.indexOf('bottom: TabBar('),
      admin.indexOf('body: TabBarView('),
    );
    expect(primaryTabBar, contains('labelColor: cs.onSurface'));
    expect(
      primaryTabBar,
      isNot(contains('labelColor: cs.primary')),
      reason:
          'Admin selected tabs should stay readable and not use a loud primary foreground.',
    );
  });

  test('管理后台筛选控件不因低高度退回固定窄宽', () {
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();

    expect(
      admin,
      isNot(contains('constraints.maxWidth < 700 || constraints.maxHeight')),
      reason:
          'Admin filter compactness should be width-driven, not low-height.',
    );
    expect(
      admin,
      isNot(contains('width: compactAdminFilters ? 280 : double.infinity')),
    );
    expect(admin, isNot(contains('constraints.maxHeight < 520')));
    expect(admin, isNot(contains('SizedBox(width: 260, child: sortField)')));
  });

  test('管理后台弹窗内容不使用固定大宽度挤压窄屏', () {
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();

    expect(
      admin,
      isNot(matches(RegExp(r'SizedBox\(\s*width:\s*(?:400|420|430)'))),
      reason:
          'Admin dialogs should let AppDialog clamp content to the viewport.',
    );
    expect(admin, contains('BoxConstraints(maxWidth: 430)'));
    expect(admin, contains('BoxConstraints(maxWidth: 420)'));
    expect(admin, contains('BoxConstraints(maxWidth: 400)'));
  });

  test('反馈记录分页和标题保持紧凑且不挤压文本区域', () {
    final feedback = File(
      'lib/screens/feedback_screen.dart',
    ).readAsStringSync();
    final sectionStart = feedback.indexOf("title: '反馈记录'");
    final sectionEnd = feedback.indexOf('Text(', sectionStart + 1);
    expect(sectionStart, greaterThanOrEqualTo(0));
    expect(sectionEnd, greaterThan(sectionStart));
    final sectionHeader = feedback.substring(sectionStart, sectionEnd);

    expect(
      sectionHeader,
      isNot(contains('Theme.of(context).textTheme.titleMedium')),
      reason:
          'Feedback records title should use the shared compact section style.',
    );

    final pagination = feedback.substring(
      feedback.indexOf('class _FeedbackPagination'),
      feedback.indexOf('String normalizeFeedbackCategory'),
    );
    expect(pagination, contains('LayoutBuilder('));
    expect(pagination, contains('constraints.maxWidth < 360'));
    expect(pagination, contains('Column('));
    expect(pagination, contains('Row(children: controls)'));
    expect(
      pagination,
      matches(RegExp(r'appSecondaryControlLabelStyle\(\s*context\s*,?\s*\)')),
    );
    expect(
      pagination,
      isNot(contains('padding: const EdgeInsets.symmetric(horizontal: 12)')),
      reason:
          'Narrow feedback pagination should not reserve a fixed wide center label.',
    );
  });

  test('局部选中态不绕过可读前景色规则', () {
    final reminderPlan = File(
      'lib/widgets/reminder_plan_editor.dart',
    ).readAsStringSync();
    final selectedHelpers = reminderPlan.substring(
      reminderPlan.indexOf('ButtonStyle _selectedSegmentStyle'),
      reminderPlan.indexOf('IconData _ruleIcon'),
    );
    expect(selectedHelpers, contains('_readableForeground('));
    expect(selectedHelpers, contains('final selectedForeground'));
    expect(
      selectedHelpers,
      isNot(contains('return Theme.of(context).colorScheme.primary;')),
    );
    expect(selectedHelpers, isNot(contains('return cs.primary;')));

    final course = File(
      'lib/screens/course_schedule_screen.dart',
    ).readAsStringSync();
    final weekPicker = course.substring(
      course.indexOf('void _pickWeek'),
      course.indexOf('String _courseWeekLabel'),
    );
    expect(
      weekPicker,
      contains('foregroundColor: selected ? cs.onSurface : null'),
    );
    expect(
      weekPicker,
      isNot(contains('foregroundColor: selected ? cs.primary')),
    );

    final eventSheet = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();
    final colorChoice = eventSheet.substring(
      eventSheet.indexOf('class _ColorChoice'),
      eventSheet.indexOf('const _localEventColors'),
    );
    expect(colorChoice, contains('color.computeLuminance()'));
    expect(
      colorChoice,
      isNot(contains('const Icon(Icons.check, color: Colors.white')),
    );
  });

  test('任务语义图标与新建任务入口保持一致', () {
    final quick = File('lib/widgets/quick_capture_fab.dart').readAsStringSync();
    final quickTodo = quick.substring(
      quick.indexOf("label: I18n.tr('quick.menu.todo')") - 120,
      quick.indexOf("label: I18n.tr('quick.menu.todo')") + 120,
    );
    expect(quickTodo, contains('icon: Icons.check_circle_outline'));

    final today = File('lib/screens/today_screen.dart').readAsStringSync();
    final todayTodo = today.substring(
      today.indexOf('title: s.navTodo'),
      today.indexOf('title: s.navHabit'),
    );
    expect(todayTodo, contains('icon: Icons.check_circle_outline'));

    final todo = File('lib/screens/todo_screen.dart').readAsStringSync();
    final summary = todo.substring(
      todo.indexOf("icon: Icons.check_circle_outline"),
      todo.indexOf('label: TodoBoardUiCopy.todaySummaryChipKey'),
    );
    expect(summary, contains('icon: Icons.check_circle_outline'));

    final completionMenu = todo.substring(
      todo.indexOf('_TodoFilterMenu<TodoCompletionFilter>('),
      todo.indexOf('selected: filter.completion != TodoCompletionFilter.all'),
    );
    expect(completionMenu, contains('icon: Icons.check_circle_outline'));
  });

  test('管理后台备份记录列表独立滚动且分页固定在记录区底部', () {
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();
    final backupTab = admin.substring(
      admin.indexOf('class _BackupSettingsTab'),
      admin.indexOf(
        '// ====================================================================\n// 用户',
      ),
    );

    expect(backupTab, contains("ValueKey('admin_backup_record_tabs')"));
    expect(backupTab, contains("ValueKey('admin_backup_server_records')"));
    expect(backupTab, contains("ValueKey('admin_backup_user_records')"));
    expect(backupTab, contains("ValueKey('admin_backup_server_pagination')"));
    expect(backupTab, contains("ValueKey('admin_backup_user_pagination')"));
    expect(backupTab, contains('ListView.builder('));
    expect(
      backupTab,
      contains('height: 640'),
      reason: 'Backup records need a stable viewport instead of a narrow tail.',
    );

    final buildMethod = backupTab.substring(
      backupTab.indexOf('Widget build(BuildContext context)'),
    );
    expect(
      buildMethod,
      isNot(contains("title: '服务器备份记录'")),
      reason:
          'Backup records should be rendered by dedicated panels, not appended to the outer settings ListView.',
    );
    expect(
      buildMethod,
      contains('_buildBackupRecordTabs('),
      reason:
          'The outer settings ListView should only host the record viewport.',
    );
  });

  test('更多应用与日历弹层不会回退到黑屏或原生大面板', () {
    final moreApps = File(
      'lib/screens/more_apps_screen.dart',
    ).readAsStringSync();
    expect(moreApps, contains('final routeBackground'));
    expect(moreApps, contains('backgroundColor: routeBackground'));
    expect(
      moreApps,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(moreApps, contains('body: ColoredBox('));
    expect(moreApps, contains('SafeArea('));
    expect(
      moreApps.substring(moreApps.indexOf('class MoreApplicationButton')),
      isNot(contains('return Scaffold(')),
    );
    expect(
      moreApps.substring(moreApps.indexOf('class MoreApplicationButton')),
      contains('BrandRouteSurface('),
      reason:
          'Standalone hidden app fallback needs a route backing surface for transparent pages.',
    );
    expect(moreApps, isNot(contains('backgroundColor: Colors.transparent')));

    final brandBackground = File(
      'lib/widgets/brand_background.dart',
    ).readAsStringSync();
    final routeSurface = brandBackground.substring(
      brandBackground.indexOf('class BrandRouteSurface'),
      brandBackground.indexOf('class BrandScaffold'),
    );
    expect(routeSurface, contains('final routeBackground'));
    expect(routeSurface, contains('color: routeBackground'));
    // 子树经 locale 键控的 KeyedSubtree 挂载：语言热切换时强制重挂 const 子页，
    // 文案即时跟随（详见 BrandRouteSurface 内注释）。
    expect(routeSurface, contains('AppSecondaryControlTheme('));
    expect(routeSurface, contains('I18n.localeListenable'));
    expect(routeSurface, contains('ValueKey<AppLocale>(locale)'));
    expect(
      routeSurface,
      contains(
        'child: BrandBackground(\n            child: AppSecondaryControlTheme(',
      ),
      reason: '跳转页统一套二级控件字号，避免从我的/更多应用进入后字号偏大。',
    );
    final brandScaffold = brandBackground.substring(
      brandBackground.indexOf('class BrandScaffold'),
    );
    expect(brandScaffold, contains('final routeBackground'));
    expect(brandScaffold, contains('ColoredBox('));
    expect(
      brandScaffold,
      contains('color: paintBackground ? routeBackground : Colors.transparent'),
    );
    expect(brandScaffold, contains('final bool paintBackground'));
    expect(brandScaffold, contains('this.paintBackground = true'));
    expect(
      brandScaffold,
      contains('paintBackground ? BrandBackground(child: scaffold) : scaffold'),
      reason: '主导航 shell 已经绘制品牌背景，tab 内 BrandScaffold 需要可关闭内层背景以避免重复解码和重绘。',
    );

    final surfaceComponents = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();
    final modalSheet = surfaceComponents.substring(
      surfaceComponents.indexOf(
        'ModalBottomSheetRoute<T> createAppModalSheetRoute<T>',
      ),
      surfaceComponents.indexOf('class AppDialog'),
    );
    expect(modalSheet, contains('requestFocus: false'));
    expect(modalSheet, contains('showDragHandle: false'));
    expect(modalSheet, contains('bool isScrollControlled = true'));
    expect(modalSheet, contains('backgroundColor: Colors.transparent'));
    expect(modalSheet, isNot(contains('requestFocus: false ||')));
    expect(
      surfaceComponents,
      contains('TextStyle appSecondaryRouteTitleTextStyle'),
    );
    expect(surfaceComponents, contains('fontSize: DesignTokens.fontSizeMd'));
    expect(surfaceComponents, contains('fontWeight: FontWeight.normal'));

    final calendar = File(
      'lib/screens/calendar_screen.dart',
    ).readAsStringSync();
    final quickMenu = calendar.substring(
      calendar.indexOf('void _showQuickAddMenu'),
      calendar.indexOf('Future<void> _showQuickAddTimeEntry'),
    );
    expect(quickMenu, contains('showAppModalSheet<void>('));
    expect(calendar, contains('class _QuickAddMenuSheetState'));
    expect(calendar, contains('return AppModalSheet('));
    expect(quickMenu, isNot(contains('showModalBottomSheet')));
    expect(quickMenu, contains('BrandRouteSurface('));
    expect(
      quickMenu,
      contains('child: AiScheduleScreen(initialDate: origin.selectedDay)'),
    );

    final todo = File('lib/screens/todo_screen.dart').readAsStringSync();
    final kanbanSettings = todo.substring(
      todo.indexOf('Future<void> _showKanbanSettings'),
      todo.indexOf('Future<void> _deleteSelected'),
    );
    expect(
      kanbanSettings,
      contains('showAppModalSheet<TodoKanbanBoardConfig>('),
    );
    expect(kanbanSettings, isNot(contains('showModalBottomSheet')));
    final kanbanSheet = todo.substring(
      todo.indexOf('class _KanbanSettingsSheet'),
      todo.indexOf('Color _quadrantColor'),
    );
    expect(kanbanSheet, contains('AppModalSheet('));
    expect(kanbanSheet, contains('appSecondaryFilledButtonStyle(context)'));
    expect(kanbanSheet, isNot(contains('return SafeArea(')));
    expect(kanbanSheet, isNot(contains('textTheme.titleMedium')));

    final note = File('lib/screens/note_screen.dart').readAsStringSync();
    final attachmentPicker = note.substring(
      note.indexOf('Future<void> _addAttachment'),
      note.indexOf('if (source == _AttachmentSource.file)'),
    );
    expect(
      attachmentPicker,
      contains('createAppModalSheetRoute<_AttachmentSource>('),
    );
    expect(attachmentPicker, contains('_pushOwned<_AttachmentSource>('));
    expect(attachmentPicker, contains('AppModalSheet('));
    expect(attachmentPicker, contains('AppSettingsTile('));
    expect(attachmentPicker, isNot(contains('showModalBottomSheet')));
    expect(attachmentPicker, isNot(contains('ListTile(')));

    final projectDetail = calendar.substring(
      calendar.indexOf('class _ProjectDetailSheetState'),
      calendar.indexOf('class _ProjectStat'),
    );
    expect(projectDetail, contains('scrollable: false'));
    expect(projectDetail, contains("'calendar_project_detail_scroll_region'"));
    expect(projectDetail, contains('ListView.separated('));
    expect(projectDetail, contains('itemCount: widget.todos.length'));
    expect(projectDetail, isNot(contains('.take(8)')));

    final habit = File('lib/screens/habit_screen.dart').readAsStringSync();
    expect(habit, contains('final routeBackground'));
    expect(habit, contains('backgroundColor: routeBackground'));
    expect(
      habit,
      contains('labelStyle: appSecondaryControlLabelStyle(context)'),
    );
    expect(
      habit,
      contains('unselectedLabelStyle: appSecondaryControlLabelStyle(context)'),
    );
    expect(habit, isNot(contains('backgroundColor: Colors.transparent')));

    final preferences = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();
    expect(preferences, contains('final routeBackground'));
    expect(preferences, contains('backgroundColor: routeBackground'));
    expect(
      RegExp(
        r'titleTextStyle:\s*appSecondaryRouteTitleTextStyle\(context\)',
      ).allMatches(preferences).length,
      greaterThanOrEqualTo(3),
      reason: '个性设置入口、显示与行为、底部导航设置都要使用二级页标题样式',
    );
    expect(preferences, isNot(contains('backgroundColor: Colors.transparent')));

    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    expect(mine, contains('final bool useShellBackground'));
    expect(mine, contains('final routeBackground'));
    expect(mine, contains('final scaffoldBackground = useShellBackground'));
    expect(mine, contains('backgroundColor: scaffoldBackground'));
    expect(mine, contains('final toolbarBackground = useShellBackground'));
    expect(mine, contains('appBar: AppBar('));
    expect(mine, contains('backgroundColor: toolbarBackground'));
    expect(mine, contains('title: Text(s.mineTitle)'));
    expect(mine, isNot(contains('final mineToolbar = Padding(')));
    expect(mine, contains('void _openBrandedRoute'));
    expect(mine, contains('BrandRouteSurface(child: child)'));
    for (final rawRoute in [
      'builder: (_) => const SearchScreen()',
      'builder: (_) => const GoalScreen()',
      'builder: (_) => const PomodoroScreen()',
      'builder: (_) => const CourseScheduleScreen()',
      'builder: (_) => const AchievementsScreen()',
      'builder: (_) => const NotificationSettingsScreen()',
      'builder: (_) => FeedbackScreen(initialCategory: category)',
    ]) {
      expect(
        mine,
        isNot(contains(rawRoute)),
        reason:
            'Mine secondary routes need BrandRouteSurface to avoid black backing.',
      );
    }
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('useShellBackground: true'));

    for (final path in [
      'lib/screens/ai_schedule_screen.dart',
      'lib/screens/feedback_screen.dart',
      'lib/screens/notification_history_screen.dart',
      'lib/screens/search_screen.dart',
      'lib/screens/share_screen.dart',
      'lib/screens/integrations_screen.dart',
      'lib/screens/profile_screen.dart',
      'lib/screens/diary_screen.dart',
      'lib/screens/widget_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('final routeBackground'), reason: path);
      expect(
        source,
        contains('backgroundColor: routeBackground'),
        reason: path,
      );
      expect(
        source,
        contains('surfaceTintColor: Colors.transparent'),
        reason: path,
      );
      if (path == 'lib/screens/profile_screen.dart') {
        expect(
          source,
          contains('final routeBackground = Colors.transparent;'),
          reason: path,
        );
      } else if (path == 'lib/screens/integrations_screen.dart') {
        // Independently require the root's ordinary and owned Brand backing.
        final bodyStart = source.indexOf('class _IntegrationsScreenBody');
        final bodyEnd = source.indexOf(
          'ButtonStyle _integrationOutlinedButtonStyle',
          bodyStart,
        );
        expect(bodyStart, greaterThanOrEqualTo(0));
        expect(bodyEnd, greaterThan(bodyStart));
        final body = source.substring(bodyStart, bodyEnd);
        expect(
          body,
          matches(RegExp(
            r'final routeBackground = Theme\.of\(context\)\.brightness == Brightness\.dark'
            r'\s*\? cs\.surface\s*:\s*cs\.surfaceContainerLowest;',
          )),
        );
        expect(
          body,
          matches(RegExp(
            r'backgroundColor:\s*isLiquidGlass\s*\?\s*Colors\.transparent\s*:\s*routeBackground',
          )),
        );
        expect(
          body,
          matches(RegExp(r'if \(!isLiquidGlass\)\s*\{\s*return scaffold;')),
        );
        expect(
          body,
          contains('findAncestorWidgetOfExactType<BrandBackground>()'),
        );
        expect(
          body,
          contains('findAncestorWidgetOfExactType<BrandRouteSurface>()'),
        );
        expect(
          body,
          matches(RegExp(r'if \(hasBrandSurface\)\s*\{\s*return scaffold;')),
        );
        expect(
          body,
          matches(RegExp(
            r'return Material\(\s*color: routeBackground,\s*child: BrandBackground\(child: scaffold\)',
          )),
        );
        expect(
          body,
          isNot(matches(RegExp(r'backgroundColor:\s*Colors\.transparent'))),
        );
        expect(
          routeSurface,
          matches(RegExp(
            r'return Material\(\s*color: routeBackground,\s*child: BrandBackground\(',
          )),
          reason: 'An ancestor BrandRouteSurface must own its backing.',
        );
        final painterStart = brandBackground.indexOf(
          'class _LiquidGlassBackdropPainter',
        );
        final painterEnd = brandBackground.indexOf(
          'class BrandRouteSurface',
          painterStart,
        );
        expect(painterStart, greaterThanOrEqualTo(0));
        expect(painterEnd, greaterThan(painterStart));
        final painter = brandBackground.substring(painterStart, painterEnd);
        expect(painter, contains('final rect = Offset.zero & size;'));
        expect(
          painter,
          matches(RegExp(
            r'final basePaint = Paint\(\)\s*\.\.shader = const LinearGradient\('
            r'[\s\S]*?colors:\s*\[\s*Color\(0xFFE2ECF8\),\s*'
            r'Color\(0xFFE9EEF6\),\s*Color\(0xFFDFEAF7\),\s*'
            r'Color\(0xFFE7EFF8\),\s*\]',
          )),
          reason: 'The Brand backdrop retains an opaque viewport base.',
        );
        expect(painter, contains('canvas.drawRect(rect, basePaint);'));

        // Only this measured OAuth DialogRoute host gets the modal exception.
        final oauthStart = source.indexOf('class _OAuthCalendarCard');
        final oauthEnd = source.indexOf('class _OAuthCalendarTile', oauthStart);
        expect(oauthStart, greaterThanOrEqualTo(0));
        expect(oauthEnd, greaterThan(oauthStart));
        final oauth = source.substring(oauthStart, oauthEnd);
        final modalStart = oauth.indexOf(
          'final ok = await showControllerDialog<bool>(',
        );
        final modalEnd = oauth.indexOf(
          'final displayName = nameCtrl.text.trim();',
          modalStart,
        );
        expect(modalStart, greaterThanOrEqualTo(0));
        expect(modalEnd, greaterThan(modalStart));
        final modal = oauth.substring(modalStart, modalEnd);
        final transparentScaffold = RegExp(
          r'backgroundColor:\s*Colors\.transparent',
        );
        expect(transparentScaffold.allMatches(source), hasLength(1));
        expect(transparentScaffold.allMatches(oauth), hasLength(1));
        expect(transparentScaffold.allMatches(modal), hasLength(1));
        expect(
          modal,
          matches(RegExp(
            r'builder:\s*\(dialogCtx\)\s*=>\s*ScaffoldMessenger\('
            r'\s*child:\s*Scaffold\(\s*backgroundColor:\s*Colors\.transparent,'
            r'\s*resizeToAvoidBottomInset:\s*false,',
          )),
        );
        expect(modal, contains('child: AppDialog('));
        expect(modal, contains('valueListenable: I18n.localeListenable'));
        final controllerDialog = File(
          'lib/widgets/controller_dialog.dart',
        ).readAsStringSync();
        final createStart = controllerDialog.indexOf(
          'DialogRoute<T> createControllerDialogRoute<T>',
        );
        final showStart = controllerDialog.indexOf(
          'Future<T?> showControllerDialog<T>',
          createStart,
        );
        final showEnd = controllerDialog.indexOf(
          'class _ControlledDialogThemeScope',
          showStart,
        );
        expect(createStart, greaterThanOrEqualTo(0));
        expect(showStart, greaterThan(createStart));
        expect(showEnd, greaterThan(showStart));
        final createRoute = controllerDialog.substring(createStart, showStart);
        final showRoute = controllerDialog.substring(showStart, showEnd);
        expect(createRoute, contains('final route = DialogRoute<T>('));
        expect(createRoute, contains('barrierColor:'));
        expect(createRoute, contains('themes: InheritedTheme.capture('));
        expect(showRoute, contains('final route = createControllerDialogRoute<T>('));
        expect(showRoute, contains('builder: builder,'));
        expect(showRoute, contains('final result = navigator.push<T>(route);'));
        expect(showRoute, contains('route.completed.then((_) => disposeControllers())'));
      } else {
        expect(
          source,
          isNot(contains('backgroundColor: Colors.transparent')),
          reason: path,
        );
      }
    }

    final notificationHistory = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final reminderKindSelector = notificationHistory.substring(
      notificationHistory.indexOf('class _ReminderKindSelector'),
      notificationHistory.indexOf('String _kindLabel'),
    );
    expect(reminderKindSelector, contains('return cs.onSurface;'));
    expect(
      reminderKindSelector,
      contains('cs.primary.withValues(alpha: 0.12)'),
    );
    expect(reminderKindSelector, isNot(contains('return cs.onPrimary;')));
    expect(reminderKindSelector, isNot(contains('alpha: 0.82')));

    final weekStrip = File(
      'lib/widgets/calendar_week_strip.dart',
    ).readAsStringSync();
    final monthGrid = File(
      'lib/widgets/calendar_month_grid.dart',
    ).readAsStringSync();
    for (final source in [weekStrip, monthGrid]) {
      expect(source, contains('final selectedBackground = Color.alphaBlend('));
      expect(source, contains('final selectedForeground = cs.onSurface'));
      expect(source, contains('cs.primary.withValues('));
      expect(source, contains('Border.all('));
      expect(source, contains('button: true'));
      expect(source, contains('selected: isSelected'));
      expect(source, isNot(contains('? cs.onPrimary')));
      expect(
        source,
        isNot(
          contains(
            'color: isSelected\n                                        ? cs.onPrimary',
          ),
        ),
      );
    }
    expect(weekStrip, contains('d.year == selectedDay.year'));
    expect(weekStrip, contains('d.year == today.year'));
    expect(monthGrid, contains('final selectedDotColor = cs.onSurface'));
    expect(monthGrid, isNot(contains('? Colors.white')));
    expect(monthGrid, isNot(contains('? Colors.white70')));
    expect(monthGrid, isNot(contains('? Colors.white60')));
    expect(monthGrid, isNot(contains('? Colors.white54')));

    expect(
      calendar,
      contains('labelStyle: appSecondaryMenuItemTextStyle(context)'),
    );
    expect(calendar, contains('Color.alphaBlend('));
    expect(calendar, isNot(contains('labelColor: cs.onPrimaryContainer')));
    expect(calendar, isNot(contains('foregroundColor: cs.onPrimaryContainer')));

    final almanac = File('lib/screens/almanac_screen.dart').readAsStringSync();
    expect(almanac, contains("import '../widgets/surface_components.dart';"));
    expect(almanac, contains('final routeBackground'));
    expect(almanac, contains('backgroundColor: routeBackground'));
    expect(
      almanac,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(
      almanac,
      contains('backgroundColor: routeBackground.withValues(alpha: 0.96)'),
    );
    expect(almanac, contains('surfaceTintColor: Colors.transparent'));
    expect(almanac, contains('body: ColoredBox('));
    expect(almanac, contains('color: routeBackground.withValues(alpha: 0.92)'));
    expect(
      almanac,
      contains('22 + MediaQuery.paddingOf(context).bottom'),
      reason: '万年历主页面底部滚动 padding 需要避开 Android 手势区。',
    );
    expect(almanac, isNot(contains('backgroundColor: Colors.transparent')));
    expect(almanac, isNot(contains('return BrandScaffold(')));

    final appDatePicker = File(
      'lib/widgets/app_date_picker.dart',
    ).readAsStringSync();
    final solarDayCell = appDatePicker.substring(
      appDatePicker.indexOf('class _SolarDayCell'),
      appDatePicker.indexOf('class _LunarPicker'),
    );
    expect(solarDayCell, contains('final selectedFill = Color.alphaBlend('));
    expect(solarDayCell, contains('? selectedFill'));
    expect(solarDayCell, contains('? cs.onSurface'));
    expect(solarDayCell, contains('color: cs.primary.withValues(alpha: 0.26)'));
    expect(solarDayCell, isNot(contains('? cs.onPrimary')));
    expect(almanac, contains('final selectedFill = Color.alphaBlend('));
    expect(almanac, contains('final selectedText = cs.onSurface'));
    expect(almanac, isNot(contains('? cs.onPrimary')));
    expect(almanac, isNot(contains('cs.onPrimary.withValues')));
  });

  test('从我的和更多应用跳转后的默认字号不超过主页面常规尺度', () {
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    final surfaceComponents = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();
    final brandBackground = File(
      'lib/widgets/brand_background.dart',
    ).readAsStringSync();
    final moreApps = File(
      'lib/screens/more_apps_screen.dart',
    ).readAsStringSync();

    final nameTextIndex = mine.indexOf('nameText,');
    expect(nameTextIndex, greaterThanOrEqualTo(0));
    final nameTextStart = mine.lastIndexOf('Text(', nameTextIndex);
    expect(nameTextStart, greaterThanOrEqualTo(0));
    final metadataIndex = mine.indexOf('_MineHeaderMetadata(', nameTextIndex);
    expect(metadataIndex, greaterThan(nameTextIndex));
    final mineProfileHeader = mine.substring(nameTextStart, metadataIndex);
    final mainRegularSize = _requiredFontSize(mineProfileHeader);
    expect(mainRegularSize, equals(15));

    final controlText = surfaceComponents.substring(
      surfaceComponents.indexOf('TextStyle appSecondaryControlTextStyle'),
      surfaceComponents.indexOf('TextStyle appSecondaryControlLabelStyle'),
    );
    final menuText = surfaceComponents.substring(
      surfaceComponents.indexOf('TextStyle appSecondaryMenuItemTextStyle'),
      surfaceComponents.indexOf('TextStyle appSecondaryRouteTitleTextStyle'),
    );
    final routeTitle = surfaceComponents.substring(
      surfaceComponents.indexOf('TextStyle appSecondaryRouteTitleTextStyle'),
      surfaceComponents.indexOf('Color _appSecondaryActionBackground'),
    );

    expect(_requiredFontSize(controlText), lessThan(mainRegularSize));
    expect(_requiredFontSize(menuText), lessThan(mainRegularSize));
    expect(routeTitle, contains('fontSize: DesignTokens.fontSizeMd'));
    expect(controlText, contains('fontWeight: FontWeight.normal'));
    expect(menuText, contains('fontWeight: FontWeight.normal'));
    expect(routeTitle, contains('fontWeight: FontWeight.normal'));

    final secondaryTheme = surfaceComponents.substring(
      surfaceComponents.indexOf('class AppSecondaryControlTheme'),
      surfaceComponents.indexOf('class AppSecondaryMenuText'),
    );
    for (final textRole in [
      'titleMedium',
      'titleSmall',
      'bodyLarge',
      'bodyMedium',
    ]) {
      expect(
        secondaryTheme,
        contains('$textRole: controlText.copyWith'),
        reason: '$textRole should inherit compact secondary route text.',
      );
    }
    for (final textRole in ['bodySmall', 'labelLarge', 'labelMedium']) {
      expect(
        secondaryTheme,
        contains('$textRole: labelText.copyWith'),
        reason: '$textRole should inherit smaller secondary label text.',
      );
    }

    final routeSurface = brandBackground.substring(
      brandBackground.indexOf('class BrandRouteSurface'),
      brandBackground.indexOf('/// A scaffold'),
    );
    expect(
      routeSurface,
      contains(
        'child: BrandBackground(\n            child: AppSecondaryControlTheme(',
      ),
      reason:
          'Pushed routes must inherit the compact secondary text scale before painting their page content.',
    );

    final moreApplicationButton = moreApps.substring(
      moreApps.indexOf('class MoreApplicationButton'),
    );
    expect(moreApplicationButton, contains('BrandRouteSurface('));
    expect(
      moreApplicationButton,
      isNot(contains('builder: (_) => app.builder(')),
      reason:
          'More-app fallbacks should not bypass the compact route surface when pushed.',
    );
  });

  test('下拉菜单先收起键盘再按安全区域重算弹出位置', () {
    final source = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();
    final keyboardGuard = source.substring(
      source.indexOf('Future<void> _hideKeyboardBeforePicker'),
      source.indexOf('Future<T?> _showAnchoredDropdownMenu<T>'),
    );
    expect(
      keyboardGuard,
      contains('FocusScope.of(context, createDependency: false).unfocus()'),
    );
    expect(
      keyboardGuard,
      contains('FocusManager.instance.primaryFocus?.unfocus()'),
    );
    expect(keyboardGuard, contains("'TextInput.hide'"));
    expect(
      keyboardGuard,
      contains('await _waitForDropdownInsetsToSettle(context)'),
    );
    expect(
      keyboardGuard,
      contains('Future<void> _waitForDropdownInsetsToSettle'),
    );
    expect(keyboardGuard, contains('for (var i = 0; i < 18; i += 1)'));
    expect(keyboardGuard, contains('closedStableFrames >= 3'));
    expect(keyboardGuard, contains('unchangedFrames >= 4'));
    expect(keyboardGuard, contains('await WidgetsBinding.instance.endOfFrame'));
    expect(
      keyboardGuard,
      contains('MediaQuery.maybeOf(context)?.viewInsets.bottom'),
    );
    expect(keyboardGuard, contains('final hadKeyboard'));
    expect(
      keyboardGuard,
      contains('Future<void> _waitForDropdownAnchorLayoutToSettle'),
    );
    expect(keyboardGuard, contains('View.maybeOf(context)'));
    expect(
      keyboardGuard,
      contains('view.viewInsets.bottom / view.devicePixelRatio'),
    );
    expect(keyboardGuard, contains('if (!_dropdownAnchorIsVisible(context))'));
    expect(keyboardGuard, contains('if (hadKeyboard)'));
    expect(
      keyboardGuard,
      contains('ScrollPositionAlignmentPolicy.keepVisibleAtStart'),
    );
    expect(
      source,
      contains('bool _dropdownAnchorIsVisible(BuildContext context)'),
    );

    final menu = source.substring(
      source.indexOf('Future<T?> _showAnchoredDropdownMenu<T>'),
      source.indexOf('class AppCompactDropdown<T>'),
    );
    expect(menu, contains('_DropdownMenuPosition positionForCurrentLayout()'));
    expect(source, contains('class _DropdownMenuPosition'));
    expect(menu, contains('_effectiveDropdownBottomInset(context)'));
    expect(
      menu,
      contains(
        'final safeBottom = (activeOverlay.size.height - bottomInset - 8)',
      ),
    );
    expect(
      menu,
      contains('final openAbove = belowSpace < 160 && aboveSpace > belowSpace'),
    );
    expect(
      menu,
      contains(
        'final menuTop = unclampedTop.clamp(safeTop, maxTop).toDouble()',
      ),
    );
    expect(
      menu,
      contains(
        'final menuBottom = (activeOverlay.size.height - menuTop - availableHeight)',
      ),
    );
    expect(
      menu,
      contains(
        'positionBuilder: (_, constraints) => positionForCurrentLayout()',
      ),
    );
    expect(menu, contains('requestFocus: false'));
    expect(menu, contains('maxHeight: initialPosition.height'));
    expect(menu, contains('height: availableHeight'));
    expect(menu, isNot(contains('DropdownButton(')));
    expect(menu, isNot(contains('DropdownButtonFormField(')));

    final compactDropdown = source.substring(
      source.indexOf('class AppCompactDropdown<T>'),
      source.indexOf('class AppDropdownField<T>'),
    );
    expect(
      compactDropdown,
      contains('await _hideKeyboardBeforePicker(anchorContext)'),
    );
    expect(compactDropdown, contains('onTapDown: enabled'));
    expect(
      compactDropdown,
      contains('_beginDropdownKeyboardDismiss(anchorContext)'),
    );
    expect(compactDropdown, contains('context: anchorContext'));

    final dropdownField = source.substring(
      source.indexOf('class AppDropdownField<T>'),
    );
    expect(
      dropdownField,
      contains('await _hideKeyboardBeforePicker(anchorContext)'),
    );
    expect(dropdownField, contains('onTapDown: canOpen'));
    expect(
      dropdownField,
      contains('_beginDropdownKeyboardDismiss(anchorContext)'),
    );
    expect(dropdownField, contains('context: anchorContext'));
  });

  test('个人资料、通知二级页和管理员子页保持紧凑标题与单层内容区', () {
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    final notification = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final diary = File('lib/screens/diary_screen.dart').readAsStringSync();
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();
    final course = File(
      'lib/screens/course_schedule_screen.dart',
    ).readAsStringSync();

    expect(
      profile,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(
      notification,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(
      course,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(
      diary,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(diary, contains('AppSecondaryControlTheme('));
    expect(diary, contains('final routeBackground'));
    expect(diary, contains('backgroundColor: routeBackground'));
    expect(diary, contains('surfaceTintColor: Colors.transparent'));
    expect(diary, contains('width: 0.45'));
    expect(profile, isNot(contains('fontSize: 12')));
    expect(
      profile,
      contains('textStyle: appSecondaryControlTextStyle(context)'),
    );
    expect(
      admin,
      contains('labelStyle: appSecondaryMenuItemTextStyle(context)'),
    );
    expect(
      admin,
      contains('unselectedLabelStyle: appSecondaryMenuItemTextStyle(context)'),
    );
    expect(admin, contains('height: 38'));
    expect(admin, isNot(contains('height: 44')));
    expect(admin, contains('AdminUiCopy.tabTitle(text, locale)'));
    expect(admin, contains('Icon(icon, size: 16)'));

    for (final className in [
      'class _AnnouncementsTabState',
      'class _FeedbackTabState',
      'class _InvitesTabState',
    ]) {
      final start = admin.indexOf(className);
      expect(start, greaterThanOrEqualTo(0), reason: className);
      final nextClass = admin.indexOf('\nclass ', start + className.length);
      final section = admin.substring(
        start,
        nextClass == -1 ? admin.length : nextClass,
      );
      if (className == 'class _FeedbackTabState') {
        expect(section, contains('return RefreshIndicator('));
        expect(section, contains('child: CustomScrollView('));
        expect(section, contains('SliverToBoxAdapter('));
        expect(section, contains("ValueKey('admin_feedback_scroll')"));
      } else {
        expect(section, contains('return Column('), reason: className);
      }
      expect(section, isNot(contains('return Scaffold(')), reason: className);
    }
  });

  test('日历详情区域和扩展功能按钮保持紧凑不挤压', () {
    final calendar = File(
      'lib/screens/calendar_screen.dart',
    ).readAsStringSync();
    expect(
      calendar,
      contains("key: const ValueKey('calendar_month_detail_agenda')"),
    );
    expect(
      calendar,
      contains("key: const ValueKey('calendar_fixed_month_grid')"),
    );
    expect(
      calendar,
      contains("key: const ValueKey('calendar_month_global_scrollbar')"),
    );
    expect(calendar, contains("'calendar_month_global_scroll_view'"));
    expect(calendar, contains('double _monthGridHeightFor'));
    expect(
      calendar,
      matches(
        RegExp(
          r'rows >= 6\s*\?\s*288\.0\s*:\s*\(rows == 5 \?\s*260\.0\s*:\s*236\.0\)',
          multiLine: true,
        ),
      ),
    );
    expect(
      calendar,
      matches(
        RegExp(
          r'rows >= 6\s*\?\s*318\.0\s*:\s*\(rows == 5 \?\s*292\.0\s*:\s*268\.0\)',
          multiLine: true,
        ),
      ),
    );
    expect(calendar, contains('const monthGridChromeHeight = 36.0'));
    expect(calendar, contains('final minGridHeight'));
    expect(calendar, contains('final preferredGridHeight'));
    expect(calendar, contains('height: monthGridHeight'));
    expect(calendar, contains('scrollable: false'));
    expect(calendar, contains('horizontalPadding: 8'));
    expect(calendar, contains('maxLines: 2'));
    expect(calendar, contains('dimension: 48'));
    final eventSheet = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();
    expect(eventSheet, contains('maxWidth: 860'));
    expect(eventSheet, contains('scrollable: false'));
    expect(eventSheet, contains('SingleChildScrollView('));
    expect(
      eventSheet,
      contains("ValueKey('calendar_event_detail_scroll_region')"),
    );
    expect(eventSheet, isNot(contains('detailMaxHeight')));
    expect(calendar, contains('maxWidth: 860'));
    expect(calendar, contains('MediaQuery.sizeOf(context).height * 0.68'));

    final integrations = File(
      'lib/screens/integrations_screen.dart',
    ).readAsStringSync();
    expect(integrations, contains('_integrationHintTextStyle'));
    expect(integrations, isNot(contains('Colors.black54')));
    expect(integrations, isNot(contains('Colors.black45')));
    expect(integrations, isNot(contains('right: 88')));
    expect(integrations, contains('class _IntegrationActionStrip'));
    expect(
      integrations,
      contains("key: const ValueKey('integration_action_strip')"),
    );
    expect(integrations, contains('SingleChildScrollView('));
    expect(integrations, contains('scrollDirection: Axis.horizontal'));
    expect(integrations, contains('mainAxisAlignment: MainAxisAlignment.end'));
    expect(
      integrations,
      matches(RegExp(r'AppSecondaryMenuText\(\s*account\.enabled')),
    );
    expect(
      integrations,
      matches(RegExp(r'AppSecondaryMenuText\(\s*sub\.enabled')),
    );

    final moreApps = File(
      'lib/screens/more_apps_screen.dart',
    ).readAsStringSync();
    expect(
      moreApps,
      contains("key: const ValueKey('more_application_button_tap_region')"),
    );
    expect(moreApps, isNot(contains('return OutlinedButton.icon(')));
    expect(moreApps, contains('SizedBox.square('));
    expect(moreApps, contains('Expanded('));

    final habit = File('lib/screens/habit_screen.dart').readAsStringSync();
    expect(habit, isNot(contains("label: const Text('还原')")));
  });

  test('小组件页自身有背景且预览不会在宽屏左侧缩成窄列', () {
    final widgetScreen = File(
      'lib/screens/widget_screen.dart',
    ).readAsStringSync();
    expect(widgetScreen, contains('final routeBackground'));
    expect(widgetScreen, contains('backgroundColor: routeBackground'));
    expect(
      widgetScreen,
      contains('backgroundColor: routeBackground.withValues(alpha: 0.96)'),
    );
    expect(widgetScreen, contains('surfaceTintColor: Colors.transparent'));
    expect(widgetScreen, contains('AppSecondaryControlTheme('));
    expect(widgetScreen, contains('appSecondaryFilledButtonStyle(context)'));
    expect(widgetScreen, isNot(contains('fontSize: 20')));
    // An opaque owned BrandBackground may contain a transparent Scaffold.
    // widget_style_loading_layout_test.dart checks standalone and pushed
    // route margins against the real painter and rejects a black/alpha hole.
    expect(widgetScreen, contains("'2x2', 1.0, 320"));
    expect(widgetScreen, contains("'3x2', 1.5, 480"));
    expect(widgetScreen, contains("'4x3', 4 / 3, 640"));
    expect(widgetScreen, contains('alignment: Alignment.center'));
  });

  test('习惯今日打卡优先展示且懒构建，避免一屏只露出一个卡片', () {
    final habit = File('lib/screens/habit_screen.dart').readAsStringSync();

    expect(habit, contains("key: const ValueKey('habit_today_scroll_view')"));
    expect(
      habit,
      contains("key: const ValueKey('habit_today_checkin_sliver')"),
    );
    expect(habit, contains('SliverList.builder('));
    expect(habit, contains('itemCount: activeHabits.length'));
    expect(habit, contains('_HabitTodaySummaryCard('));
    expect(habit, contains('minimumSize: const Size('));
    expect(habit, contains("key: const ValueKey('habit-undo-inline-button')"));
    expect(habit, contains('IconButton.styleFrom('));
    expect(habit, isNot(contains("label: const Text('还原')")));
    expect(habit, isNot(contains('Icons.verified_rounded')));
    expect(habit, contains('class _HabitSwipeActionWrapper'));
    expect(habit, contains('if (_swipeOffset > 0)'));
    expect(habit, contains('onEnd: () => _runAction('));
    expect(habit, contains('onDelete: () => _runAction('));
    expect(
      habit,
      matches(
        RegExp(
          r"_handleHabitMenuAction\(\s*context,\s*widget\.habit,\s*'end',\s*origin,?\s*\)",
        ),
      ),
    );
    expect(
      habit,
      matches(
        RegExp(
          r"_handleHabitMenuAction\(\s*context,\s*widget\.habit,\s*'delete',\s*origin,?\s*\)",
        ),
      ),
    );
    expect(habit, contains('await origin.habitProvider.deleteHabit(habit.id)'));
    expect(habit, contains('await origin.habitProvider.endHabit(habit.id)'));
    expect(
      habit,
      contains('await confirmHabitEnd(context, habit, origin: origin)'),
    );
    expect(
      habit,
      contains('await confirmHabitDelete(context, habit, origin: origin)'),
    );
    final habitDetail = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();
    final confirmations = habitDetail.substring(
      habitDetail.indexOf('Future<bool> confirmHabitDelete('),
      habitDetail.indexOf('Future<bool> _confirmHabitDelete('),
    );
    expect(
      RegExp(r'return AppDialog\(').allMatches(confirmations),
      hasLength(2),
    );
    expect(confirmations, contains('valueListenable: I18n.localeListenable'));
    expect(confirmations, isNot(contains('AlertDialog(')));
    expect(habit, isNot(contains('builder: (ctx) => AlertDialog(')));
    expect(habit, isNot(contains('...activeHabits.map')));
    final heatmapStart = habit.indexOf('class _HabitHeatmapTab');
    final heatmapEnd = habit.indexOf(
      'class _HabitInsightSection',
      heatmapStart,
    );
    expect(heatmapStart, greaterThanOrEqualTo(0));
    expect(heatmapEnd, greaterThan(heatmapStart));
    final heatmapTab = habit.substring(heatmapStart, heatmapEnd);
    expect(heatmapTab, contains('return CustomScrollView('));
    expect(heatmapTab, contains('SliverList.builder('));
    expect(heatmapTab, contains('itemCount: habitGroups.length'));
    expect(
      heatmapTab,
      isNot(contains('return ListView(')),
      reason: '热力图分组不能一次性 eager 构建所有分组和任务。',
    );
    expect(
      habit.indexOf('const SliverToBoxAdapter(child: HabitWeeklyCard())'),
      lessThan(
        habit.indexOf("key: const ValueKey('habit_today_checkin_sliver')"),
      ),
    );
  });
}

double _requiredFontSize(String source) {
  final match = RegExp(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(source);
  expect(match, isNotNull, reason: 'Expected a literal fontSize in:\n$source');
  return double.parse(match!.group(1)!);
}

Iterable<String> _calls(String source, String token) sync* {
  var searchFrom = 0;
  while (true) {
    final start = source.indexOf(token, searchFrom);
    if (start == -1) return;
    var depth = 0;
    var end = start;
    for (; end < source.length; end++) {
      final char = source[end];
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          end++;
          break;
        }
      }
    }
    yield source.substring(start, end);
    searchFrom = end;
  }
}
