import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('今日和我的视觉结构', () {
    test('四个指标卡使用紧凑统一样式', () {
      final today = File('lib/screens/today_screen.dart').readAsStringSync();
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
      expect(surface, contains('fontSize: 12.5'));
      expect(surface, contains('fontSize: 10'));
      expect(surface, contains('Text.rich'));

      expect(today, contains("unit: I18n.tr('today.unit.item')"));
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
      expect(
        today,
        contains("import '../providers/time_audit_provider.dart';"),
      );
      expect(today, contains("import 'statistics_screen.dart';"));
      expect(today, contains('context.watch<TimeAuditProvider>()'));
      expect(today, contains('ReportEngine.buildReport'));
      expect(today, contains('ReportEngine.compare'));
      expect(today, contains('SmartScheduleAdvisor.suggestToday'));
      expect(today, contains('limit: 5'));
      expect(today, contains('scheduleTodoForToday(t.id, now: now)'));
      expect(today, contains('_TodayProductivityCard'));
      expect(today, contains('_TodayProductivityPill'));
      expect(today, contains("I18n.tr('today.add_to_today')"));
      expect(today, contains("I18n.tr('today.suggestions')"));
      expect(today, contains("I18n.tr('today.productivity.weekly')"));
      expect(today, contains("I18n.tr('today.productivity.subtitle')"));
      expect(today, contains("I18n.tr('today.productivity.score')"));
      expect(today, isNot(contains("const Text('加入今日')")));
    });

    test('我的功能入口有外边框并按任务场景重新分类', () {
      final mine = File('lib/screens/mine_screen.dart').readAsStringSync();

      expect(mine, contains('class _TileGroup'));
      expect(mine, contains('class _Tile'));
      expect(mine, contains('border: Border.all'));
      expect(mine, contains('alpha: isDark ? 0.76 : 1'));
      expect(mine, contains('activeAvatarFrame'));
      expect(mine, contains('defaultAvatarFrameId'));

      final groups = [
        "title: '行动计划'",
        "title: '记录回顾'",
        "title: '日程日期'",
        "title: '智能工具'",
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

      for (final label in [
        "label: '目标管理'",
        "label: '番茄专注'",
        "label: '课程表'",
        "label: '纪念日'",
        "label: '生日'",
        "label: '倒数日'",
        "label: '万年历'",
        "label: '黄历'",
        "label: '时间足迹'",
        "label: '统计报表'",
        "label: '日记'",
        "label: '随手记'",
        "label: '成就墙'",
        "label: '个性设置'",
        "label: '底部导航栏'",
        "label: '共享空间'",
        "label: '扩展集成'",
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
      expect(
        mine,
        contains('class _UpdateAvailableBadge extends StatelessWidget'),
      );
      expect(mine, contains('_UpdateAvailableBadge('));
      expect(mine, contains('version: updater.latestVersion'));
      expect(mine, contains('width: 8'));
      expect(mine, contains("'有更新'"));
      expect(mine, contains("'新版 \$version'"));
      expect(mine, contains("tooltip: '全局搜索'"));
      expect(mine, isNot(contains("label: '全局搜索'")));
      expect(
        mine,
        contains("class _MoreApplicationsSheet extends StatelessWidget"),
      );
      expect(mine, contains('class _UnreadDot extends StatelessWidget'));
      expect(mine, contains('notifService.hasUnreadHistory'));
      expect(mine, contains('_hiddenBottomNavApps'));
      expect(mine, contains("label: '更多应用'"));
      expect(mine, contains("label: '通知设置'"));
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
        contains('MaterialPageRoute(builder: (_) => const SearchScreen())'),
      );
      expect(
        main,
        isNot(
          contains("MaterialPageRoute(builder: (_) => const SearchScreen())"),
        ),
      );
    });

    test('更多应用只展示隐藏的主导航功能且不包含番茄专注', () {
      final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
      final start = mine.indexOf('List<_MoreAppItem> _hiddenBottomNavApps');
      final end = mine.indexOf('void _openNotificationHistory', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = mine.substring(start, end);

      expect(method, contains('final visible = prefs.bottomNavVisible'));
      expect(method, contains("label: '今日'"));
      expect(method, contains("label: '待办'"));
      expect(method, contains("label: '习惯'"));
      expect(method, contains("label: '日历'"));
      expect(method, isNot(contains("label: '番茄专注'")));
      expect(method, isNot(contains('PomodoroScreen')));
      expect(method, contains('!visible.contains(app.tab)'));
    });
  });
}
