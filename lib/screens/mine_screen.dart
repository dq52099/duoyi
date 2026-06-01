import 'dart:io' show Directory, File;
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../core/app_version.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/todo_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_provider.dart';
import '../providers/notification_service.dart';
import '../providers/auth_provider.dart';
import '../providers/achievement_provider.dart';
import '../services/ai_service.dart';
import '../services/app_update_installer.dart';
import '../services/app_update_service.dart';
import '../widgets/brand_background.dart';
import '../widgets/stats_overview_cards.dart';
import '../widgets/surface_components.dart';
import 'theme_picker_screen.dart';
import 'login_screen.dart';
import 'announcements_screen.dart';
import 'feedback_screen.dart';
import 'note_screen.dart';
import 'statistics_screen.dart';
import 'time_audit_screen.dart';
import 'pomodoro_screen.dart';
import 'countdown_screen.dart';
import 'anniversary_screen.dart' as anniversary;
import 'diary_screen.dart';
import 'goal_screen.dart';
import 'course_schedule_screen.dart';
import 'almanac_screen.dart';
import 'admin_screen.dart';
import 'achievements_screen.dart';
import 'backup_screen.dart';
import 'lock_settings_screen.dart';
import 'export_screen.dart';
import 'search_screen.dart';
import 'ai_history_screen.dart';
import 'preferences_screen.dart';
import 'integrations_screen.dart';
import 'share_screen.dart';
import 'sync_conflict_log_screen.dart';
import 'profile_screen.dart';
import 'more_apps_screen.dart';
import 'notification_history_screen.dart';

class MineScreen extends StatelessWidget {
  final List<int>? visibleBottomNavTabs;
  final bool useShellBackground;

  const MineScreen({
    super.key,
    this.visibleBottomNavTabs,
    this.useShellBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final s = themeProvider.brand.strings;
    final todoCompletionRate = context.select<TodoProvider, int>(_todoRate);
    final todoProvider = context.read<TodoProvider>();
    final habitProvider = context.read<HabitProvider>();
    final weeklyFocus = context.select<PomodoroProvider, int>(_weeklyFocus);
    final pomodoroProvider = context.read<PomodoroProvider>();
    final userProvider = context.watch<UserProvider>();
    final notificationHistoryCount = context.select<NotificationService, int>(
      (service) => service.historyCount,
    );
    final hasUnreadNotificationHistory = context
        .select<NotificationService, bool>(
          (service) => service.hasUnreadHistory,
        );
    final auth = context.watch<AuthProvider>();
    final aiEnabled = context.select<AiService, bool>((ai) => ai.enabled);
    final aiReviewHistoryCount = context.select<AiService, int>(
      (ai) => ai.reviewHistory.length,
    );
    final updater = context.read<AppUpdateService>();
    final updateChecking = context.select<AppUpdateService, bool>(
      (service) => service.checking,
    );
    final updateHasUpdate = context.select<AppUpdateService, bool>(
      (service) => service.hasUpdate,
    );
    final updateLatestVersion = context.select<AppUpdateService, String?>(
      (service) => service.latestVersion,
    );
    final coinBalance = context.select<AchievementProvider, int>(
      (provider) => provider.coinBalance,
    );
    final cs = Theme.of(context).colorScheme;
    final avatarFrame = themeProvider.activeAvatarFrame;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final scaffoldBackground = useShellBackground
        ? Colors.transparent
        : routeBackground;
    final appBarBackground = useShellBackground
        ? Colors.transparent
        : routeBackground.withValues(alpha: 0.96);

    final p = userProvider.profile;
    final localDisplayName = _firstNonEmpty([p.displayName, p.username, '用户']);
    final displayName = auth.state.isLoggedIn
        ? _firstNonEmpty([
            auth.state.displayName,
            p.displayName,
            auth.state.username,
            localDisplayName,
          ])
        : localDisplayName;
    final avatarValue = auth.state.isLoggedIn
        ? _firstNonEmpty([auth.state.avatar, p.avatarUrl, p.avatarInitials])
        : _firstNonEmpty([p.avatarUrl, p.avatarInitials]);
    return Scaffold(
      backgroundColor: scaffoldBackground,
      appBar: AppBar(
        title: Text(s.mineTitle),
        backgroundColor: appBarBackground,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '全局搜索',
            icon: const Icon(Icons.search),
            onPressed: () => _openBrandedRoute(context, const SearchScreen()),
          ),
        ],
      ),
      body: ListView(
        children: [
          AppSurfaceCard(
            margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            padding: const EdgeInsets.all(14),
            borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 360;
                final avatarSize = compact ? 50.0 : 56.0;
                final avatar = SizedBox(
                  width: avatarSize + 6,
                  height: avatarSize + 6,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Tooltip(
                          message: '查看头像',
                          child: Semantics(
                            button: true,
                            label: '查看头像',
                            child: InkWell(
                              key: const ValueKey('mine_avatar_preview_button'),
                              customBorder: const CircleBorder(),
                              onTap: () => _showAvatarPreview(context),
                              child: Container(
                                width: avatarSize,
                                height: avatarSize,
                                padding:
                                    avatarFrame.id ==
                                        ThemeProvider.defaultAvatarFrameId
                                    ? EdgeInsets.zero
                                    : const EdgeInsets.all(3),
                                decoration:
                                    avatarFrame.id ==
                                        ThemeProvider.defaultAvatarFrameId
                                    ? null
                                    : BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          colors: avatarFrame.colors,
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: avatarFrame.colors.first
                                                .withValues(alpha: 0.12),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                child: Hero(
                                  tag: 'mine-avatar-preview',
                                  child: _ProfileAvatar(
                                    avatar: avatarValue,
                                    displayName: displayName,
                                    radius: compact ? 26 : 30,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -12,
                        bottom: -12,
                        child: SizedBox.square(
                          key: const ValueKey('mine_avatar_edit_button'),
                          dimension: 44,
                          child: Tooltip(
                            message: '修改头像',
                            child: Semantics(
                              button: true,
                              label: '修改头像',
                              child: Material(
                                color: Colors.transparent,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => _pickAndSaveAvatar(context),
                                  child: Center(
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: Color.alphaBlend(
                                          cs.primary.withValues(alpha: 0.90),
                                          cs.surface,
                                        ),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: cs.surface.withValues(
                                            alpha: 0.92,
                                          ),
                                          width: 0.45,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.edit_outlined,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                final username = auth.state.isLoggedIn
                    ? _firstNonEmpty([auth.state.username, p.username])
                    : p.username;
                final coins = auth.state.isLoggedIn
                    ? auth.state.coinBalance
                    : coinBalance;
                final accountAction = SizedBox(
                  width: auth.state.isLoggedIn ? 38 : 54,
                  height: 30,
                  child: auth.state.isLoggedIn
                      ? Tooltip(
                          message: '退出登录',
                          child: IconButton.filledTonal(
                            key: const ValueKey('mine_top_logout_button'),
                            onPressed: () => _confirmLogout(context),
                            icon: const Icon(Icons.logout, size: 16),
                            style: IconButton.styleFrom(
                              backgroundColor: cs.errorContainer.withValues(
                                alpha: 0.58,
                              ),
                              foregroundColor: cs.onErrorContainer,
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        )
                      : FilledButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          ),
                          style: appSecondaryFilledButtonStyle(context),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('登录', maxLines: 1),
                          ),
                        ),
                );
                final nameText = displayName.trim().isEmpty
                    ? '用户'
                    : displayName.trim();
                final usernameText = username.trim();
                final metadata = <Widget>[
                  if (usernameText.isNotEmpty)
                    _MineUserLineChip(
                      label: '@$usernameText',
                      icon: Icons.badge_outlined,
                      color: cs.primary,
                    ),
                  _MineUserLineChip(
                    label: '时光币 $coins',
                    icon: Icons.savings_outlined,
                    color: cs.secondary,
                  ),
                  if (auth.state.isLoggedIn && auth.state.isAdmin)
                    _MineUserLineChip(label: '管理员', color: cs.primary),
                ];
                return Row(
                  key: const ValueKey('mine_user_info_row'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(
                      key: const ValueKey('mine_avatar_row'),
                      child: avatar,
                    ),
                    SizedBox(width: compact ? 10 : 12),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: '查看个人资料',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusCard,
                          ),
                          onTap: () => _openProfileEditor(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 2,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nameText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontSize: 15,
                                        color: cs.onSurface,
                                        height: 1.18,
                                      ),
                                ),
                                const SizedBox(height: 5),
                                Wrap(
                                  spacing: compact ? 8 : 10,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: metadata,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    accountAction,
                  ],
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth < 520 ? 2 : 4;
                final aspectRatio = constraints.maxWidth < 520 ? 2.55 : 3.65;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: aspectRatio,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    StatsOverviewCard(
                      title: '待办完成',
                      value: '$todoCompletionRate',
                      unit: '%',
                      icon: Icons.check_circle_outline,
                      color: cs.primary,
                    ),
                    StatsOverviewCard(
                      title: '连续打卡',
                      value: '${p.currentStreak}',
                      unit: '天',
                      icon: Icons.repeat,
                      color: cs.tertiary,
                    ),
                    StatsOverviewCard(
                      title: '本周专注',
                      value: '$weeklyFocus',
                      unit: '分钟',
                      icon: Icons.timer,
                      color: DesignTokens.defaultError,
                    ),
                    StatsOverviewCard(
                      title: '效率评分',
                      value: '${p.productivityScore}',
                      icon: Icons.auto_awesome,
                      color: DesignTokens.defaultWarning,
                    ),
                  ],
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: aiEnabled
                ? _AiWeeklyReviewCard(
                    todoProvider: todoProvider,
                    pomodoroProvider: pomodoroProvider,
                    habitProvider: habitProvider,
                  )
                : AppInfoBanner(
                    icon: Icons.auto_awesome,
                    title: 'AI 助手',
                    message: '管理员后台配置 AI 后，这里会显示周回顾、任务拆解和建议生成入口。',
                    color: Colors.purple,
                    onTap: auth.state.isAdmin
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const BrandRouteSurface(child: AdminScreen()),
                            ),
                          )
                        : null,
                  ),
          ),

          const SizedBox(height: 12),
          _TileGroup(
            title: '行动计划',
            children: [
              _Tile(
                icon: Icons.flag_circle_outlined,
                label: '目标管理',
                color: Colors.orange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: GoalScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.timer,
                label: '番茄专注',
                color: Colors.red,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BrandRouteSurface(
                      child: PomodoroScreen(useShellBackground: true),
                    ),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.apps_outlined,
                label: '更多应用',
                subtitle: '查看隐藏功能',
                color: Colors.blueGrey,
                onTap: () => _openMoreApplications(context),
              ),
            ],
          ),
          _TileGroup(
            title: '记录回顾',
            children: [
              _Tile(
                icon: Icons.access_time,
                label: '时间足迹',
                color: Colors.teal,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: TimeAuditScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.pie_chart_outline,
                label: '统计报表',
                color: Colors.indigo,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: StatisticsScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.book_outlined,
                label: '日记',
                color: Colors.teal,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: DiaryScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.edit_note,
                label: '随手记',
                color: Colors.amber.shade700,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: NoteScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.emoji_events_outlined,
                label: '成就墙',
                color: Colors.amber,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: AchievementsScreen()),
                  ),
                ),
              ),
              if (aiEnabled)
                _Tile(
                  icon: Icons.history,
                  label: 'AI 周回顾历史',
                  color: Colors.purple,
                  trailing: aiReviewHistoryCount == 0
                      ? null
                      : Text(
                          '$aiReviewHistoryCount',
                          style: const TextStyle(fontSize: 11),
                        ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const BrandRouteSurface(child: AiHistoryScreen()),
                    ),
                  ),
                ),
            ],
          ),
          _TileGroup(
            title: '日程日期',
            children: [
              _Tile(
                icon: Icons.school_outlined,
                label: '课程表',
                color: Colors.blue,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: CourseScheduleScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.calendar_month_outlined,
                label: '万年历',
                color: Colors.green,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BrandRouteSurface(
                      child: AlmanacScreen(
                        initialMode: AlmanacEntryMode.calendar,
                      ),
                    ),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.hourglass_bottom_outlined,
                label: '倒数日',
                color: Colors.deepOrange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: CountdownScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.event_available_outlined,
                label: '纪念日',
                color: Colors.pink,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BrandRouteSurface(
                      child: anniversary.MemorialAnniversaryScreen(),
                    ),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.cake_outlined,
                label: '生日',
                color: Colors.purple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BrandRouteSurface(
                      child: anniversary.BirthdayScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          _TileGroup(
            title: '个性安全',
            children: [
              _Tile(
                icon: Icons.palette,
                label: s.mineThemeLabel,
                color: cs.primary,
                trailing: Text(
                  themeProvider.brand.name,
                  style: TextStyle(color: cs.primary, fontSize: 11),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: ThemePickerScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.tune,
                label: '个性设置',
                color: Colors.indigo,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: PreferencesScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.lock_outline,
                label: '应用锁',
                color: Colors.red.shade400,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: LockSettingsScreen()),
                  ),
                ),
              ),
            ],
          ),
          _TileGroup(
            title: '数据协作',
            children: [
              _Tile(
                icon: Icons.groups_2_outlined,
                label: '共享空间',
                color: Colors.cyan,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: ShareScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.extension_outlined,
                label: '扩展功能',
                color: Colors.deepPurple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: IntegrationsScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.sync_problem_outlined,
                label: '同步冲突记录',
                color: Colors.orange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: SyncConflictLogScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.event_note_outlined,
                label: '导出为日历 (.ics)',
                color: Colors.lightBlue,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: ExportScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.backup_outlined,
                label: '备份',
                color: Colors.brown,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BrandRouteSurface(
                      child: BackupScreen(initialMode: BackupEntryMode.backup),
                    ),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.restore_outlined,
                label: '恢复数据',
                color: Colors.blueGrey,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BrandRouteSurface(
                      child: BackupScreen(initialMode: BackupEntryMode.restore),
                    ),
                  ),
                ),
              ),
            ],
          ),
          _TileGroup(
            title: '通知支持',
            children: [
              _Tile(
                icon: Icons.history_toggle_off_outlined,
                label: '通知记录',
                subtitle: notificationHistoryCount == 0
                    ? '暂无通知记录'
                    : '$notificationHistoryCount 条',
                color: Colors.blueGrey,
                trailing: notificationHistoryCount == 0
                    ? null
                    : hasUnreadNotificationHistory
                    ? const _UnreadDot()
                    : null,
                onTap: () => _openNotificationHistory(context),
              ),
              _Tile(
                icon: Icons.notifications_outlined,
                label: '通知设置',
                subtitle: '提醒时间、权限、铃声和记录保留',
                color: Colors.orange,
                onTap: () => _openNotificationSettings(context),
              ),
              if (auth.state.isLoggedIn && auth.state.isAdmin)
                _Tile(
                  icon: Icons.admin_panel_settings_outlined,
                  label: '管理员后台',
                  color: Colors.deepOrange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const BrandRouteSurface(child: AdminScreen()),
                    ),
                  ),
                ),
              _Tile(
                icon: Icons.campaign_outlined,
                label: '公告',
                color: Colors.cyan,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BrandRouteSurface(child: AnnouncementsScreen()),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.forum_outlined,
                label: '许愿与反馈',
                subtitle: '提交建议并分页查看处理记录',
                color: Colors.indigo,
                onTap: () => _openFeedback(context, 'feature'),
              ),
              _Tile(
                icon: Icons.system_update,
                label: '检查更新',
                color: Colors.teal,
                trailing: updateChecking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : (updateHasUpdate
                          ? _UpdateAvailableBadge(version: updateLatestVersion)
                          : null),
                onTap: () => _showUpdateDialog(context, updater),
              ),
              _Tile(
                icon: Icons.info_outline,
                label: s.mineAboutLabel,
                color: Colors.grey,
                onTap: () => _aboutDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  int _todoRate(TodoProvider t) {
    if (t.todos.isEmpty) return 0;
    return (t.completedTodos.length / t.todos.length * 100).round();
  }

  int _weeklyFocus(PomodoroProvider p) {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    return p.sessions
            .where(
              (s) => s.type.name == 'focus' && s.startTime.isAfter(weekAgo),
            )
            .fold(0, (sum, s) => sum + s.durationSeconds) ~/
        60;
  }

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  void _openProfileEditor(BuildContext context, {bool avatarOnly = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrandRouteSurface(
          child: ProfileScreen(openAvatarSheetOnStart: avatarOnly),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        icon: const Icon(Icons.logout),
        title: const Text('退出登录？'),
        content: const Text('退出后可重新登录继续同步账号资料。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: appSecondaryFilledButtonStyle(ctx),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<AuthProvider>().logout();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已退出登录')));
  }

  Future<void> _pickAndSaveAvatar(BuildContext context) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Image',
            extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
          ),
        ],
      );
      if (file == null || !context.mounted) return;
      final auth = context.read<AuthProvider>();
      final userProvider = context.read<UserProvider>();
      if (auth.state.isLoggedIn) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          throw Exception('头像文件为空');
        }
        if (bytes.length > 3 * 1024 * 1024) {
          throw Exception(I18n.tr('profile.avatar.too_large'));
        }
        await auth.uploadAvatarBytes(filename: file.name, bytes: bytes);
        final state = auth.state;
        await userProvider.updateProfile(
          username: _firstNonEmpty([
            state.username,
            userProvider.profile.username,
            '用户',
          ]),
          displayName: state.displayName ?? '',
          email: state.email ?? '',
          emailVerified: state.emailVerified,
          avatarUrl: state.avatar ?? '',
          bio: state.bio ?? '',
        );
      } else {
        final storedPath = await _copyLocalAvatarFile(file);
        final profile = userProvider.profile;
        await userProvider.updateProfile(
          username: profile.username,
          avatarInitials: profile.avatarInitials,
          displayName: profile.displayName,
          email: profile.email,
          emailVerified: profile.emailVerified,
          avatarUrl: storedPath,
          bio: profile.bio,
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('头像已保存')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('头像保存失败：${_avatarErrorMessage(e)}')),
      );
    }
  }

  void _showAvatarPreview(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();
    final profile = userProvider.profile;
    final displayName = auth.state.isLoggedIn
        ? _firstNonEmpty([
            auth.state.displayName,
            auth.state.username,
            profile.displayName,
            profile.username,
            '我',
          ])
        : _firstNonEmpty([profile.displayName, profile.username, '我']);
    final avatar = auth.state.isLoggedIn
        ? _firstNonEmpty([
            auth.state.avatar,
            profile.avatarUrl,
            profile.avatarInitials,
          ])
        : _firstNonEmpty([profile.avatarUrl, profile.avatarInitials]);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AvatarPreviewScreen(
          avatar: avatar,
          displayName: displayName,
          onEdit: () => _pickAndSaveAvatar(context),
        ),
      ),
    );
  }

  void _showUpdateDialog(BuildContext context, AppUpdateService u) async {
    if (!u.checking) await u.checkNow();
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: !u.mustUpdate,
      builder: (ctx) => Consumer<AppUpdateService>(
        builder: (context, updater, _) {
          final notes = updater.latestNotesForDisplay;
          return PopScope(
            canPop: !updater.mustUpdate && !updater.busy,
            child: AppDialog(
              title: Text(updater.mustUpdate ? '必须更新' : '检查更新'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前版本: ${updater.currentVersion}'),
                  Text('远端版本: ${updater.latestVersion ?? '—'}'),
                  if (updater.minimumSupportedVersion != null) ...[
                    const SizedBox(height: 4),
                    Text('最低支持版本: ${updater.minimumSupportedVersion}'),
                  ],
                  if (updater.mustUpdate) ...[
                    const SizedBox(height: 12),
                    AppInfoBanner(
                      icon: Icons.system_update_alt_outlined,
                      title: '此版本需要强制更新',
                      message: '当前版本低于管理员设置的最低支持版本，或管理员已要求所有用户更新后继续使用。',
                      color: Theme.of(context).colorScheme.error,
                      margin: EdgeInsets.zero,
                    ),
                  ],
                  if (updater.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      updater.error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  if (updater.hasUpdate) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '发现新版本',
                      style: TextStyle(fontWeight: FontWeight.normal),
                    ),
                  ] else if (updater.error == null && !updater.checking) ...[
                    const SizedBox(height: 12),
                    const Text('已是最新版本'),
                  ],
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '更新内容',
                      style: TextStyle(fontWeight: FontWeight.normal),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          child: SelectableText(
                            notes,
                            style: const TextStyle(fontSize: 12, height: 1.45),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (updater.hasUpdate && updater.latestAssetName != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '安装包：${updater.latestAssetName}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                  if ((updater.mustUpdate || updater.hasUpdate) &&
                      updater.latestUrl == null) ...[
                    const SizedBox(height: 12),
                    AppInfoBanner(
                      icon: Icons.link_off_outlined,
                      title: '未配置安装包地址',
                      message: updater.forceUpdateBlockedReason == null
                          ? '更新策略已生效，但当前没有可下载的安装包地址。请管理员在发布通道补充安装包。'
                          : '更新策略已生效，但安装包不可用：${updater.forceUpdateBlockedReason}。请管理员在发布通道补充安装包。',
                      color: Theme.of(context).colorScheme.error,
                      margin: EdgeInsets.zero,
                    ),
                  ],
                  if (updater.hasUpdate && updater.downloading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: updater.downloadProgress),
                    const SizedBox(height: 6),
                    Text(
                      updater.downloadProgress == null
                          ? '正在下载更新包'
                          : '正在下载 ${(updater.downloadProgress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ] else if (updater.hasUpdate && updater.installing) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    const Text('正在打开安装器', style: TextStyle(fontSize: 12)),
                  ],
                ],
              ),
              actions: [
                if (!updater.mustUpdate)
                  TextButton(
                    onPressed: updater.busy ? null : () => Navigator.pop(ctx),
                    child: const Text('关闭'),
                  ),
                if (updater.hasUpdate &&
                    updater.latestUrl != null &&
                    AppUpdateInstaller.supportsInstall)
                  FilledButton.icon(
                    onPressed: updater.busy
                        ? null
                        : () async {
                            await updater.downloadAndInstallLatest();
                            if (!context.mounted) return;
                            if (updater.error != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(updater.error!)),
                              );
                            }
                          },
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text(
                      updater.downloadedFilePath == null ? '下载并安装' : '重新安装',
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openNotificationSettings(BuildContext context) async {
    _openBrandedRoute(context, const NotificationSettingsScreen());
  }

  void _openMoreApplications(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrandRouteSurface(
          child: MoreApplicationsScreen(
            visibleBottomNavTabs: visibleBottomNavTabs,
          ),
        ),
      ),
    );
  }

  void _openNotificationHistory(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BrandRouteSurface(
          child: NotificationHistoryScreen(markReadOnOpen: true),
        ),
      ),
    );
  }

  void _openFeedback(BuildContext context, String category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BrandRouteSurface(child: FeedbackScreen(initialCategory: category)),
      ),
    );
  }

  void _openBrandedRoute(BuildContext context, Widget child) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BrandRouteSurface(child: child)),
    );
  }

  void _aboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('多仪'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('版本: ${AppVersion.display}'),
            SizedBox(height: 4),
            Text('Flutter 跨平台效率工具'),
            SizedBox(height: 4),
            Text('待办'),
            Text('习惯'),
            Text('日历'),
            Text('番茄专注'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final double radius;

  const _ProfileAvatar({
    required this.avatar,
    required this.displayName,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final value = avatar?.trim() ?? '';
    final networkUrl = _networkAvatarUrl(value);
    final localPath = _localAvatarPath(value);
    final fallback = (networkUrl != null || localPath != null)
        ? displayName
        : (value.isNotEmpty ? value : displayName);
    final letter = fallback.isNotEmpty ? fallback.characters.first : '我';

    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primary,
      child: networkUrl != null
          ? ClipOval(
              child: Image.network(
                networkUrl,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _ProfileAvatarLetter(
                  letter: letter,
                  radius: radius,
                  color: cs.onPrimary,
                ),
              ),
            )
          : localPath != null
          ? ClipOval(
              child: Image.file(
                File(localPath),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _ProfileAvatarLetter(
                  letter: letter,
                  radius: radius,
                  color: cs.onPrimary,
                ),
              ),
            )
          : Text(
              letter,
              style: TextStyle(
                fontSize: radius * 0.62,
                color: cs.onPrimary,
                fontWeight: FontWeight.normal,
              ),
            ),
    );
  }
}

class _MineUserLineChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;

  const _MineUserLineChip({
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 20),
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Color.alphaBlend(
                  color.withValues(alpha: 0.48),
                  cs.onSurface,
                ),
                fontWeight: FontWeight.normal,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPreviewScreen extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final VoidCallback? onEdit;

  const _AvatarPreviewScreen({
    required this.avatar,
    required this.displayName,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: appSecondaryRouteTitleTextStyle(
          context,
        ).copyWith(color: Colors.white),
        title: const Text('头像'),
        actions: [
          if (onEdit != null)
            IconButton(
              tooltip: '修改头像',
              onPressed: () {
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) => onEdit!());
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: Center(
        child: Hero(
          tag: 'mine-avatar-preview',
          child: _ProfileAvatarFullImage(
            avatar: avatar,
            displayName: displayName,
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatarFullImage extends StatelessWidget {
  final String? avatar;
  final String displayName;

  const _ProfileAvatarFullImage({
    required this.avatar,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final value = avatar?.trim() ?? '';
    final networkUrl = _networkAvatarUrl(value);
    final localPath = _localAvatarPath(value);
    final image = networkUrl != null
        ? Image.network(
            networkUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _fallbackAvatar(context),
          )
        : localPath != null
        ? Image.file(
            File(localPath),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _fallbackAvatar(context),
          )
        : null;

    return SizedBox.expand(
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Center(child: image ?? _fallbackAvatar(context)),
      ),
    );
  }

  Widget _fallbackAvatar(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final radius = (size.shortestSide * 0.28).clamp(84.0, 150.0);
    final value = avatar?.trim() ?? '';
    final networkUrl = _networkAvatarUrl(value);
    final localPath = _localAvatarPath(value);
    final fallback = (networkUrl != null || localPath != null)
        ? displayName
        : (value.isNotEmpty ? value : displayName);
    final letter = fallback.isNotEmpty ? fallback.characters.first : '我';
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: _ProfileAvatarLetter(
        letter: letter,
        radius: radius,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

class _ProfileAvatarLetter extends StatelessWidget {
  final String letter;
  final double radius;
  final Color color;

  const _ProfileAvatarLetter({
    required this.letter,
    required this.radius,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      letter,
      style: TextStyle(
        fontSize: radius * 0.62,
        color: color,
        fontWeight: FontWeight.normal,
      ),
    );
  }
}

String? _localAvatarPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (_networkAvatarUrl(trimmed) != null) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.scheme == 'file') {
    return uri.toFilePath();
  }
  if (trimmed.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
    return trimmed;
  }
  return null;
}

String? _networkAvatarUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return trimmed;
  }
  final pathSegments = Uri.tryParse(trimmed)?.pathSegments ?? const <String>[];
  if (pathSegments.isNotEmpty &&
      (pathSegments.first == 'api' || pathSegments.first == 'uploads')) {
    final base = Uri.base;
    if (base.scheme == 'http' || base.scheme == 'https') {
      return base.resolve(trimmed).toString();
    }
    return trimmed;
  }
  return null;
}

Future<String> _copyLocalAvatarFile(XFile file) async {
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw Exception('头像文件为空');
  }
  if (bytes.length > 3 * 1024 * 1024) {
    throw Exception('头像不能超过 3MB');
  }
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory('${root.path}/profile_avatars');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final filename =
      'avatar_${DateTime.now().microsecondsSinceEpoch}${_avatarExtensionFor(file.name)}';
  final target = File('${dir.path}/$filename');
  await target.writeAsBytes(bytes, flush: true);
  return target.path;
}

String _avatarExtensionFor(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpeg')) return '.jpg';
  for (final extension in ['.jpg', '.png', '.webp', '.gif']) {
    if (lower.endsWith(extension)) return extension;
  }
  return '.png';
}

String _avatarErrorMessage(Object error) {
  final message = error.toString();
  return message.startsWith('Exception: ')
      ? message.substring('Exception: '.length)
      : message;
}

class _AiWeeklyReviewCard extends StatefulWidget {
  final TodoProvider todoProvider;
  final PomodoroProvider pomodoroProvider;
  final HabitProvider habitProvider;
  const _AiWeeklyReviewCard({
    required this.todoProvider,
    required this.pomodoroProvider,
    required this.habitProvider,
  });

  @override
  State<_AiWeeklyReviewCard> createState() => _AiWeeklyReviewCardState();
}

class _AiWeeklyReviewCardState extends State<_AiWeeklyReviewCard> {
  bool _busy = false;
  String? _result;
  String? _summary;
  String? _error;
  bool _generatedToday = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cached = context.read<AiService>().weeklyReviewForDay(DateTime.now());
    if (cached != null && _result == null) {
      _result = cached.content;
      _summary = cached.summary;
      _generatedToday = true;
    }
  }

  Future<void> _run() async {
    final cached = context.read<AiService>().weeklyReviewForDay(DateTime.now());
    if (cached != null) {
      setState(() {
        _result = cached.content;
        _summary = cached.summary;
        _generatedToday = true;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ai = context.read<AiService>();
      final now = DateTime.now();
      final range = _reviewRange(now);
      final completed = widget.todoProvider.completedTodos
          .where((t) => _inRange(t.completedAt ?? t.updatedAt, range))
          .length;
      final total = widget.todoProvider.todos
          .where((t) => _inRange(t.date, range))
          .length;
      final focus =
          widget.pomodoroProvider.sessions
              .where(
                (s) => s.type.name == 'focus' && _inRange(s.startTime, range),
              )
              .fold(0, (sum, s) => sum + s.durationSeconds) ~/
          60;
      final streak = widget.habitProvider.longestCurrentStreak;
      final label = _reviewRangeLabel(now);
      _result = await ai.weeklyReview(
        completedTodos: completed,
        totalTodos: total,
        weeklyFocusMinutes: focus,
        habitStreak: streak,
        periodLabel: label,
      );
      _summary =
          '$label数据：完成 $completed / $total 项待办，专注 $focus 分钟，习惯连续打卡 $streak 天。';
      _generatedToday = true;
    } on AiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ({DateTime start, DateTime end}) _reviewRange(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final start = now.weekday == DateTime.monday
        ? thisMonday.subtract(const Duration(days: 7))
        : thisMonday;
    return (start: start, end: start.add(const Duration(days: 7)));
  }

  String _reviewRangeLabel(DateTime now) =>
      now.weekday == DateTime.monday ? '上周' : '本周';

  bool _inRange(DateTime at, ({DateTime start, DateTime end}) range) {
    return !at.isBefore(range.start) && at.isBefore(range.end);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_awesome, color: cs.primary, size: 18),
              ),
              const SizedBox(width: 8),
              const Text(
                'AI 每周回顾',
                style: TextStyle(fontWeight: FontWeight.normal),
              ),
              const Spacer(),
              TextButton(
                onPressed: _busy || _generatedToday ? null : _run,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_generatedToday ? '今日已生成' : '生成'),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            )
          else if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_summary != null) ...[
                    Text(
                      _summary!,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    _result!,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '点击"生成"让 AI 根据${_reviewRangeLabel(DateTime.now())}完成数据写一段总结与建议，当天会保留结果',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }
}

class _TileGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _TileGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                height: 1.15,
                fontWeight: FontWeight.normal,
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
          AppSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 44,
                      color: cs.outlineVariant.withValues(alpha: 0.14),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateAvailableBadge extends StatelessWidget {
  final String? version;

  const _UpdateAvailableBadge({this.version});

  @override
  Widget build(BuildContext context) {
    final text = version == null || version!.trim().isEmpty
        ? '有更新'
        : '新版 $version';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 28,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appSecondaryMenuItemTextStyle(
                        context,
                      ).copyWith(height: 1.2, color: cs.onSurface),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          height: 1.15,
                          color: cs.onSurface.withValues(alpha: 0.58),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.34),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
