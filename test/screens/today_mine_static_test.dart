import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('今日和我的视觉结构', () {
    test('四个指标卡使用紧凑统一样式', () {
      final today = File('lib/screens/today_screen.dart').readAsStringSync();
      final todo = File('lib/screens/todo_screen.dart').readAsStringSync();
      final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
      final surface = File(
        'lib/widgets/surface_components.dart',
      ).readAsStringSync();

      expect(today, contains('constraints.maxWidth < 520 ? 2.55 : 3.65'));
      expect(mine, contains('constraints.maxWidth < 520 ? 2.55 : 3.65'));
      expect(surface, contains('class AppMetricCard'));
      expect(surface, contains('activeCardSkin'));
      expect(surface, contains('defaultCardSkinId'));
      expect(surface, contains('Radius.circular(DesignTokens.radiusMd)'));
      expect(surface, contains('iconBoxSize = 28'));
      expect(surface, contains('fontSize: 12'));
      expect(surface, contains('fontSize: 11'));
      expect(surface, contains('Text.rich'));

      expect(today, contains("unit: I18n.tr('today.unit.item')"));
      expect(today, contains('icon: Icons.check_circle_outline'));
      expect(todo, contains('icon: Icons.check_circle_outline'));
      expect(mine, contains("unit: '%'"));
      expect(mine, contains("unit: '天'"));
      expect(mine, contains("unit: '分钟'"));
      expect(mine, contains("title: '效率评分'"));
      expect(mine, isNot(contains("title: '综合评分'")));
    });

    test('今日列表标题不把数量塞进大标题', () {
      final today = File('lib/screens/today_screen.dart').readAsStringSync();

      expect(today, contains("I18n.tr('today.todos')"));
      expect(
        today,
        contains("\$todayTodosCount \${I18n.tr('today.unit.item')}"),
      );
      expect(today, contains("I18n.tr('today.completed')"));
      expect(today, contains("I18n.tr('today.courses')"));
      expect(today, contains("\${I18n.tr('today.unit.course_section')}"));
      expect(today, contains('titleStyle: theme.textTheme.bodyMedium'));
      expect(today, contains('fontSize: 14'));
      expect(today, isNot(contains("'今日待办 · \$todayTodosCount 项")));
      expect(today, isNot(contains("'今日课程 · \${todayCourses.length} 节'")));
    });

    test('今日页展示本周效率评分摘要', () {
      final today = File('lib/screens/today_screen.dart').readAsStringSync();

      expect(today, contains("import '../core/report_engine.dart';"));
      expect(today, contains("import '../core/todo_templates.dart';"));
      expect(
        today,
        contains("import '../providers/time_audit_provider.dart';"),
      );
      expect(today, contains("import 'statistics_screen.dart';"));
      expect(today, contains('context.watch<TimeAuditProvider>()'));
      expect(today, contains('ReportEngine.buildReport'));
      expect(today, contains('ReportEngine.compare'));
      expect(today, contains('SmartScheduleAdvisor.suggestToday'));
      expect(today, contains('CompletionVisibilityPolicy.shouldShowInToday'));
      expect(today, contains('limit: 5'));
      expect(today, contains('final actionNow = DateTime.now();'));
      expect(today, contains('scheduleTodoForToday('));
      expect(today, contains('waitForReminderSync: false'));
      expect(today, contains('_TodayProductivityCard'));
      expect(today, contains('_TodayProductivityPill'));
      expect(today, contains("I18n.tr('today.add_to_today')"));
      expect(today, contains("I18n.tr('today.suggestions')"));
      expect(today, contains("I18n.tr('today.productivity.weekly')"));
      expect(today, contains("I18n.tr('today.productivity.subtitle')"));
      expect(today, contains("I18n.tr('today.productivity.score')"));
      expect(today, isNot(contains("const Text('加入今日')")));
    });

    test('今日页任务条目左滑只保留删除，图标和标题同行', () {
      final today = File('lib/screens/today_screen.dart').readAsStringSync();

      expect(
        today,
        contains('class _TodayTodoSwipeTile extends StatefulWidget'),
      );
      expect(today, contains('Matrix4.translationValues(-_swipeOffset'));
      expect(today, contains('bool get _swipeActive => _swipeOffset > 0'));
      expect(today, contains('if (_swipeActive)'));
      expect(today, contains('RepaintBoundary(child: tile)'));
      expect(
        today,
        isNot(contains("ValueKey('today_todo_swipe_detail_button')")),
      );
      expect(today, contains("ValueKey('today_todo_swipe_delete_button')"));
      expect(today, contains("title: const Text('删除任务？')"));
      expect(today, contains("await context.read<TodoProvider>().deleteTodo"));
      expect(today, contains('return _TodayTodoSwipeTile('));
      expect(today, contains('onToggleTodo(todo)'));
      expect(today, contains('onOpenTodo(t.id)'));
      expect(today, contains('CompletionVisibilityPolicy.visualState(todo)'));
      expect(today, contains('List<TodoItem> _visibleTodayOverviewTodos('));
      expect(today, contains('if (due == null) return true;'));
      expect(today, contains('return !due.isBefore(now);'));
      expect(today, contains('_visibleTodayOverviewTodos(todoP.todos, now)'));
      expect(today, contains('class _TodayTodoStatusPill'));
      expect(today, contains('TodoVisualState.completed'));
      expect(today, contains('TodoVisualState.overdue'));
      expect(today, contains("Text(label, style: TextStyle(fontSize: 10"));
      expect(today, contains('effectiveTileBackground'));
      expect(today, contains('effectiveTileBorderColor'));
      expect(today, contains('class _TodayTodoLeading'));
      expect(today, contains('static const double width = 44'));
      expect(today, contains('static const double touchTargetSize = 44'));
      expect(today, contains('class _TodayTodoTitleLine'));
      expect(today, contains('class _TodayTodoStatusToggle'));
      expect(today, contains('minLeadingWidth: widget.leading == null'));
      expect(today, contains('TodoVisualState.normal => templateVisual.color'));
      expect(today, contains('today_todo_template_icon'));
      expect(today, contains('today_reminder_template_icon'));
      expect(today, contains("iconKeyPrefix = 'today_todo_template_icon'"));
      expect(today, contains('class _TodoTemplateAvatar'));
      expect(today, contains('today_suggestion_template_icon'));
      expect(today, contains("import '../providers/share_provider.dart';"));
      expect(today, contains('context.select<ShareProvider?, bool>'));
      expect(today, contains("共享空间只读，不能\$action"));
      expect(today, isNot(contains('void _openDetails()')));
      expect(today, isNot(contains('onTap: _openDetails')));
      expect(today, isNot(contains('Dismissible(')));
    });

    test('我的功能入口有外边框并按任务场景重新分类', () {
      final mine = File('lib/screens/mine_screen.dart').readAsStringSync();

      expect(mine, contains('class _TileGroup'));
      expect(mine, contains('class _Tile'));
      expect(mine, contains('AppSurfaceCard('));
      expect(mine, contains('Divider('));
      expect(mine, contains('indent: 44'));
      expect(
        mine,
        contains(
          'borderRadius: BorderRadius.circular(DesignTokens.radiusControl)',
        ),
      );
      expect(mine, contains('final compact = constraints.maxWidth < 360'));
      expect(mine, contains('final avatarSize = compact ? 50.0 : 56.0'));
      expect(mine, contains('final headerHeight = compact'));
      expect(mine, contains("key: const ValueKey('mine_header_stable_box')"));
      expect(mine, contains('height: headerHeight'));
      expect(mine, contains('height: _mineHeaderMetadataHeight'));
      expect(mine, contains('ClipRect('));
      expect(mine, contains('final metadata = <Widget>['));
      expect(mine, contains('return SizedBox('));
      expect(mine, contains('child: Row('));
      expect(mine, contains('crossAxisAlignment: CrossAxisAlignment.center'));
      expect(mine, contains("key: const ValueKey('mine_avatar_row')"));
      expect(mine, contains('child: avatar'));
      expect(mine, contains('SizedBox(width: compact ? 10 : 12)'));
      expect(mine, contains("label: '查看个人资料'"));
      expect(mine, contains('onTap: () => _openProfileEditor(context)'));
      expect(mine, contains("key: const ValueKey('mine_user_info_row')"));
      expect(
        mine,
        contains(
          'borderRadius: BorderRadius.circular(DesignTokens.radiusCard)',
        ),
      );
      expect(mine, contains('Expanded('));
      expect(mine, contains('Wrap('));
      expect(mine, contains('runSpacing: 4'));
      expect(mine, contains('class _MineUserLineChip extends StatelessWidget'));
      expect(mine, isNot(contains('maxWidth: compact ? 116 : 150')));
      expect(
        mine,
        isNot(
          contains(
            'borderRadius: BorderRadius.circular(22),\n            onTap: () => _openProfileEditor(context)',
          ),
        ),
      );
      expect(mine, contains("message: '查看头像'"));
      expect(mine, contains("message: '修改头像'"));
      expect(
        mine,
        contains("key: const ValueKey('mine_avatar_preview_button')"),
      );
      expect(mine, contains("key: const ValueKey('mine_avatar_edit_button')"));
      expect(mine, contains('dimension: 44'));
      expect(mine, contains('width: 20'));
      expect(mine, contains('height: 20'));
      expect(mine, contains('size: 10'));
      expect(mine, contains('onTap: () => _pickAndSaveAvatar(context)'));
      expect(mine, contains("label: '@\$usernameText'"));
      expect(mine, contains(r"label: '时光币 $coins'"));
      expect(mine, contains('activeAvatarFrame'));
      expect(mine, contains('defaultAvatarFrameId'));
      expect(mine, contains('onTap: () => _showAvatarPreview(context)'));
      expect(mine, contains('child: Hero('));
      expect(
        mine,
        contains('class _AvatarPreviewScreen extends StatelessWidget'),
      );
      expect(mine, contains('MaterialPageRoute<void>('));
      expect(mine, contains("tag: 'mine-avatar-preview'"));
      expect(mine, contains('backgroundColor: Colors.black'));
      expect(
        mine,
        contains('titleTextStyle: appSecondaryRouteTitleTextStyle('),
      );
      expect(mine, contains(').copyWith(color: Colors.white)'));
      final avatarPreviewStart = mine.indexOf(
        'class _AvatarPreviewScreen extends StatelessWidget',
      );
      final avatarPreview = mine.substring(avatarPreviewStart);
      expect(avatarPreview, isNot(contains('AppDialog(')));
      expect(avatarPreview, isNot(contains('showDialog(')));
      final fullImageStart = mine.indexOf('class _ProfileAvatarFullImage');
      final fullImageEnd = mine.indexOf(
        'class _ProfileAvatarLetter',
        fullImageStart,
      );
      expect(fullImageStart, greaterThan(avatarPreviewStart));
      expect(fullImageEnd, greaterThan(fullImageStart));
      final fullImage = mine.substring(fullImageStart, fullImageEnd);
      expect(fullImage, contains('InteractiveViewer'));
      expect(fullImage, contains('fit: BoxFit.contain'));
      expect(fullImage, isNot(contains('ClipOval')));
      expect(fullImage, isNot(contains('BoxFit.cover')));
      expect(mine, contains('fontSize: radius * 0.62'));
      expect(mine, isNot(contains('fontSize: 20')));
      expect(
        mine,
        contains('ProfileScreen(openAvatarSheetOnStart: avatarOnly)'),
      );
      expect(mine, contains('onTap: () => _openProfileEditor(context)'));
      expect(mine, isNot(contains("title: '账号资料'")));
      expect(
        mine,
        isNot(contains('class _ProfileInfoRow extends StatelessWidget')),
      );
      expect(mine, contains("message: '退出登录'"));
      expect(mine, contains("key: const ValueKey('mine_top_logout_button')"));
      expect(mine, contains('onPressed: () => _confirmLogout(context)'));
      expect(
        mine,
        contains('Future<void> _confirmLogout(BuildContext context)'),
      );
      expect(mine, contains('await context.read<AuthProvider>().logout();'));
      expect(mine, isNot(contains('greetingAfternoon')));
      expect(mine, contains('openFile('));
      expect(mine, isNot(contains('photo_library_outlined')));

      final groups = [
        "title: '行动计划'",
        "title: '记录回顾'",
        "title: '日程日期'",
        "title: '个性安全'",
        "title: '数据协作'",
        "title: '通知支持'",
      ];
      for (final group in groups) {
        expect(mine, contains(group));
      }
      for (var i = 0; i < groups.length - 1; i++) {
        expect(mine.indexOf(groups[i]), lessThan(mine.indexOf(groups[i + 1])));
      }
      expect(mine, contains("title: 'AI 助手'"));
      expect(mine, isNot(contains("title: '智能分类'")));
      expect(mine, isNot(contains("title: '智能工具'")));

      for (final label in [
        "label: '目标管理'",
        "label: '番茄专注'",
        "label: '课程表'",
        "label: '纪念日'",
        "label: '生日'",
        "label: '倒数日'",
        "label: '万年历'",
        "label: '时间足迹'",
        "label: '统计报表'",
        "label: '日记'",
        "label: '随手记'",
        "label: '成就墙'",
        "label: '个性设置'",
        "label: '共享空间'",
        "label: '扩展功能'",
        "label: '导出为日历 (.ics)'",
        "label: '同步冲突记录'",
        "label: '备份'",
        "label: '恢复数据'",
        "label: '公告'",
        "label: '许愿与反馈'",
        "label: '更多应用'",
        "label: '检查更新'",
      ]) {
        expect(mine, contains(label));
      }
      expect(mine, contains("subtitle: '查看隐藏功能'"));
      expect(mine, isNot(contains("label: '黄历'")));
      expect(
        mine,
        contains('class _UpdateAvailableBadge extends StatelessWidget'),
      );
      expect(mine, contains('_UpdateAvailableBadge('));
      expect(mine, contains('version: updateLatestVersion'));
      expect(mine, contains('width: 8'));
      expect(mine, contains("'有更新'"));
      expect(mine, contains("'新版 \$version'"));
      expect(mine, contains("title: '未配置安装包地址'"));
      expect(mine, contains('updater.latestUrl == null'));
      expect(mine, contains("tooltip: '全局搜索'"));
      expect(mine, isNot(contains("label: '全局搜索'")));
      expect(
        File('lib/screens/more_apps_screen.dart').readAsStringSync(),
        contains("class MoreApplicationsScreen extends StatelessWidget"),
      );
      expect(mine, contains('onTap: () => _openMoreApplications(context)'));
      expect(mine, contains('class _UnreadDot extends StatelessWidget'));
      expect(mine, contains('hasUnreadNotificationHistory'));
      expect(
        File('lib/screens/more_apps_screen.dart').readAsStringSync(),
        contains('hiddenBottomNavApps'),
      );
      expect(mine, contains("label: '更多应用'"));
      expect(mine, contains('final coins = auth.state.isLoggedIn'));
      expect(mine, contains('coinBalance'));
      expect(mine, contains('auth.state.coinBalance'));
      expect(mine, contains("label: '通知设置'"));
      expect(
        mine,
        contains(
          'Future<void> _openNotificationSettings(BuildContext context)',
        ),
      );
      final settingsStart = mine.indexOf(
        'Future<void> _openNotificationSettings(BuildContext context)',
      );
      final settingsEnd = mine.indexOf(
        'void _openMoreApplications',
        settingsStart,
      );
      expect(settingsStart, greaterThanOrEqualTo(0));
      expect(settingsEnd, greaterThan(settingsStart));
      expect(
        mine.substring(settingsStart, settingsEnd),
        isNot(contains('markAllHistoryRead')),
      );
      expect(
        mine.substring(settingsStart, settingsEnd),
        isNot(contains('hasUnreadHistory')),
      );
      expect(
        mine.substring(settingsStart, settingsEnd),
        isNot(contains('_UnreadDot')),
      );
      expect(
        mine,
        contains(
          '_openBrandedRoute(context, const NotificationSettingsScreen())',
        ),
      );
      expect(mine, contains("subtitle: '提醒时间、权限、铃声、已注册提醒和记录保留'"));
      expect(mine, contains("key: const ValueKey('mine_ai_review_toggle')"));
      expect(mine, contains("key: const ValueKey('mine_ai_review_content')"));
      expect(mine, contains("tooltip: _reviewExpanded ? '收起回顾' : '展开回顾'"));
      expect(mine, contains("label: const Text('展开完整回顾')"));
      expect(mine, isNot(contains("title: '智能工具'")));
      expect(mine, isNot(contains("label: '底部导航栏'")));
      expect(
        mine,
        isNot(contains('builder: (_) => const BottomNavSettingsScreen()')),
      );
      expect(
        mine,
        isNot(contains('initialSection: PreferencesInitialSection.bottomNav')),
      );
      expect(mine, isNot(contains("label: '偏好设置'")));
      expect(mine, isNot(contains("label: '功能建议'")));
      expect(mine, isNot(contains("label: '问题反馈'")));
      expect(mine, isNot(contains("label: '许愿池'")));

      final tileLabels = RegExp(
        r"label: '([^']+)'",
      ).allMatches(mine).map((match) => match.group(1)!).toList();
      for (final label in tileLabels) {
        expect(
          label,
          isNot(matches(RegExp(r'[·/／、&]'))),
          reason: '功能入口不能组合: $label',
        );
      }

      expect(mine, isNot(contains("label: '纪念日 · 生日 · 倒数'")));
      expect(mine, isNot(contains("label: '黄历 · 万年历'")));
      expect(mine, isNot(contains("label: '备份 · 恢复'")));
      expect(mine, isNot(contains("label: '反馈与许愿'")));
      expect(mine, isNot(contains('待办 · 习惯 · 日历 · 番茄专注')));
      expect(mine, contains("Text('待办')"));
      expect(mine, contains("Text('习惯')"));
      expect(mine, contains("Text('日历')"));
      expect(mine, contains("Text('番茄专注')"));
    });

    test('全局搜索入口在我的顶部右上角，今日页不再放顶部搜索', () {
      final main = File('lib/main.dart').readAsStringSync();
      final mine = File('lib/screens/mine_screen.dart').readAsStringSync();

      expect(mine, contains("tooltip: '全局搜索'"));
      expect(
        mine,
        contains('_openBrandedRoute(context, const SearchScreen())'),
      );
      expect(
        main,
        isNot(
          contains("MaterialPageRoute(builder: (_) => const SearchScreen())"),
        ),
      );
    });

    test('更多应用只展示隐藏的主导航功能且不包含番茄专注或倒数日', () {
      final main = File('lib/main.dart').readAsStringSync();
      final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
      final moreApps = File(
        'lib/screens/more_apps_screen.dart',
      ).readAsStringSync();
      final start = moreApps.indexOf('List<MoreAppItem> hiddenBottomNavApps');
      final end = moreApps.indexOf('@override', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = moreApps.substring(start, end);

      expect(
        method,
        contains(
          'final visible = (visibleBottomNavTabs ?? prefs.visibleBottomNavTabs)',
        ),
      );
      expect(method, contains("label: '今日'"));
      expect(method, contains("label: '待办'"));
      expect(method, contains("label: '习惯'"));
      expect(method, contains("label: '日历'"));
      expect(method, contains("label: '小组件'"));
      expect(method, contains('builder: (_) => const WidgetScreen()'));
      expect(method, isNot(contains('opensStandalone')));
      expect(method, contains('builder: (_) => const TodayScreen()'));
      expect(method, isNot(contains("label: '番茄专注'")));
      expect(method, isNot(contains("label: '倒数日'")));
      expect(method, isNot(contains('PomodoroScreen')));
      expect(method, isNot(contains('CountdownScreen')));
      expect(method, contains('!visible.contains(app.tab)'));
      expect(moreApps, isNot(contains('_BottomTabStandaloneScreen')));
      expect(main, contains('visibleBottomNavTabs: safeVisibleTabs'));
      expect(main, contains('final Set<int> _builtTabs = <int>{0}'));
      expect(main, contains('List.generate('));
      expect(main, contains('_builtTabs.contains(tab)'));
      expect(main, contains('_LazyTabPlaceholder'));
      expect(main, contains('_buildTab(tab, safeVisibleTabs)'));
      expect(
        main,
        isNot(contains('_builtTabs.contains(tab) && tab == safeIndex')),
        reason: '已访问底部页签必须继续挂载，避免日历/习惯/专注来回切换整页重建造成卡顿。',
      );
      expect(
        main,
        isNot(
          contains(
            'onOpenHiddenBottomNavTab: (tab) => navigateTo(tab, allowHidden: true)',
          ),
        ),
      );
      expect(mine, isNot(contains('onOpenHiddenBottomNavTab')));
      expect(
        moreApps,
        isNot(contains('final ValueChanged<int>? onOpenHiddenTab')),
      );
      expect(moreApps, isNot(contains('shellOpen(app.tab);')));
      expect(main, contains('_HiddenTabReturnBar'));
      expect(main, contains("const Text('返回我的')"));
      expect(main, contains('_allowHiddenCurrentIndex = false'));
      expect(main, contains('state.navigateTo(idx, allowHidden: true);'));

      expect(mine, contains("import 'more_apps_screen.dart';"));
      final screenStart = moreApps.indexOf('class MoreApplicationsScreen');
      final buttonStart = moreApps.indexOf('class MoreApplicationButton');
      expect(screenStart, greaterThanOrEqualTo(0));
      expect(buttonStart, greaterThan(screenStart));
      final screen = moreApps.substring(screenStart, buttonStart);
      expect(screen, contains('return Scaffold('));
      expect(screen, contains('backgroundColor: routeBackground'));
      expect(
        screen,
        contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
      );
      expect(screen, contains('body: ColoredBox('));
      expect(screen, contains('SafeArea('));
      expect(screen, isNot(contains('body: BrandRouteSurface(')));
      expect(screen, isNot(contains('child: BrandScaffold(')));
      expect(screen, contains('final routeBackground'));
      expect(screen, contains('routeBackground.withValues(alpha: 0.92)'));
      expect(screen, contains("title: const Text('更多应用')"));
      expect(screen, contains('? 2.55'));
      expect(screen, contains(': 3.3'));

      final buttonEnd = moreApps.length;
      expect(buttonEnd, greaterThan(buttonStart));
      final button = moreApps.substring(buttonStart, buttonEnd);
      expect(
        button,
        isNot(
          contains('backgroundColor: Theme.of(context).colorScheme.surface'),
        ),
      );
      expect(button, isNot(contains('onOpenHiddenBottomNavTab')));
      expect(button, isNot(contains('app.opensStandalone')));
      expect(button, isNot(contains('openHiddenTab(app.tab)')));
      expect(button, isNot(contains('Navigator.of(context).pop()')));
      expect(
        button,
        isNot(contains('WidgetsBinding.instance.addPostFrameCallback')),
      );
      expect(button, isNot(contains('popUntil')));
      expect(button, contains('Navigator.of(context).push('));
      expect(button, contains('BrandRouteSurface('));
      expect(button, contains('builder: (routeContext)'));
      expect(
        button,
        contains('BrandRouteSurface(child: app.builder(routeContext))'),
      );
      expect(button, contains('appSecondaryMenuItemTextStyle('));
      expect(button, contains('context,'));
      expect(button, contains('maxLines: 1'));
      expect(
        button,
        isNot(contains('return Scaffold(')),
        reason:
            'Hidden app fallback routes should not wrap full-screen pages in a nested Scaffold.',
      );
    });
  });
}
