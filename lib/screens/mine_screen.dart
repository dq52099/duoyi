import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_version.dart';
import '../providers/todo_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_provider.dart';
import '../providers/notification_service.dart';
import '../providers/auth_provider.dart';
import '../services/ai_service.dart';
import '../services/api_client.dart';
import '../services/app_update_service.dart';
import '../widgets/empty_state.dart';
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
import 'anniversary_screen.dart';
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

class MineScreen extends StatelessWidget {
  const MineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final s = themeProvider.brand.strings;
    final todoProvider = context.watch<TodoProvider>();
    final habitProvider = context.watch<HabitProvider>();
    final pomodoroProvider = context.watch<PomodoroProvider>();
    final userProvider = context.watch<UserProvider>();
    final notifService = context.watch<NotificationService>();
    final auth = context.watch<AuthProvider>();
    final ai = context.watch<AiService>();
    final updater = context.watch<AppUpdateService>();
    final cs = Theme.of(context).colorScheme;
    final avatarFrame = themeProvider.activeAvatarFrame;

    final p = userProvider.profile;
    final hour = DateTime.now().hour;
    final greeting = hour < 6
        ? s.greetingEvening
        : hour < 12
        ? s.greetingMorning
        : hour < 14
        ? s.greetingNoon
        : hour < 18
        ? s.greetingAfternoon
        : s.greetingEvening;
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
    final profileLine = auth.state.isLoggedIn
        ? _firstNonEmpty([
            auth.state.bio,
            p.bio,
            auth.state.email,
            p.email,
            auth.state.username,
          ])
        : _firstNonEmpty([
            p.bio,
            p.email,
            '本地资料 · ${s.mineProductivityScore} ${p.productivityScore}',
          ]);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s.mineTitle),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        children: [
          // Profile header
          AppSurfaceCard(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(16),
            color: cs.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(22),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  padding: avatarFrame.id == ThemeProvider.defaultAvatarFrameId
                      ? EdgeInsets.zero
                      : const EdgeInsets.all(3),
                  decoration:
                      avatarFrame.id == ThemeProvider.defaultAvatarFrameId
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
                              color: avatarFrame.colors.first.withValues(
                                alpha: 0.22,
                              ),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                  child: _ProfileAvatar(
                    avatar: avatarValue,
                    displayName: displayName,
                    radius: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showProfileDialog(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting，$displayName',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profileLine.isEmpty
                                ? '${s.mineProductivityScore} ${p.productivityScore}'
                                : profileLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: auth.state.isLoggedIn
                                  ? cs.onSurface.withValues(alpha: 0.65)
                                  : cs.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          if (auth.state.isLoggedIn && auth.state.isAdmin) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '管理员',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (auth.state.isLoggedIn)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _showProfileDialog(context),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '编辑资料',
                      ),
                      IconButton(
                        onPressed: () async {
                          await context.read<AuthProvider>().logout();
                        },
                        icon: const Icon(Icons.logout),
                        tooltip: '退出登录',
                      ),
                    ],
                  )
                else
                  FilledButton.tonal(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: const Text('登录'),
                  ),
              ],
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
                      value: '${_todoRate(todoProvider)}',
                      unit: '%',
                      icon: Icons.task_alt,
                      color: Colors.blue,
                    ),
                    StatsOverviewCard(
                      title: '连续打卡',
                      value: '${p.currentStreak}',
                      unit: '天',
                      icon: Icons.repeat,
                      color: Colors.green,
                    ),
                    StatsOverviewCard(
                      title: '本周专注',
                      value: '${_weeklyFocus(pomodoroProvider)}',
                      unit: '分钟',
                      icon: Icons.timer,
                      color: Colors.red,
                    ),
                    StatsOverviewCard(
                      title: '效率评分',
                      value: '${p.productivityScore}',
                      icon: Icons.auto_awesome,
                      color: Colors.orange,
                    ),
                  ],
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: ai.enabled
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
                              builder: (_) => const AdminScreen(),
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
                  MaterialPageRoute(builder: (_) => const GoalScreen()),
                ),
              ),
              _Tile(
                icon: Icons.timer,
                label: '番茄专注',
                color: Colors.red,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PomodoroScreen()),
                ),
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
                  MaterialPageRoute(builder: (_) => const TimeAuditScreen()),
                ),
              ),
              _Tile(
                icon: Icons.pie_chart_outline,
                label: '统计报表',
                color: Colors.indigo,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StatisticsScreen()),
                ),
              ),
              _Tile(
                icon: Icons.book_outlined,
                label: '日记',
                color: Colors.teal,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DiaryScreen()),
                ),
              ),
              _Tile(
                icon: Icons.edit_note,
                label: '随手记',
                color: Colors.amber.shade700,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NoteScreen()),
                ),
              ),
              _Tile(
                icon: Icons.emoji_events_outlined,
                label: '成就墙',
                color: Colors.amber,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AchievementsScreen()),
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
                    builder: (_) => const CourseScheduleScreen(),
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
                    builder: (_) => const AlmanacScreen(
                      initialMode: AlmanacEntryMode.calendar,
                    ),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.wb_sunny_outlined,
                label: '黄历',
                color: Colors.deepOrange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AlmanacScreen(
                      initialMode: AlmanacEntryMode.almanac,
                    ),
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
                    builder: (_) => const AnniversaryScreen(initialTab: 2),
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
                    builder: (_) => const AnniversaryScreen(initialTab: 1),
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
                    builder: (_) => const AnniversaryScreen(initialTab: 3),
                  ),
                ),
              ),
            ],
          ),
          _TileGroup(
            title: '智能工具',
            children: [
              _Tile(
                icon: Icons.search,
                label: '全局搜索',
                color: Colors.blueGrey,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                ),
              ),
              if (ai.enabled)
                _Tile(
                  icon: Icons.history,
                  label: 'AI 周回顾历史',
                  color: Colors.purple,
                  trailing: ai.reviewHistory.isEmpty
                      ? null
                      : Text(
                          '${ai.reviewHistory.length}',
                          style: const TextStyle(fontSize: 11),
                        ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AiHistoryScreen()),
                  ),
                ),
            ],
          ),
          _TileGroup(
            title: '个性安全',
            children: [
              _Tile(
                icon: Icons.account_circle_outlined,
                label: '个人资料',
                color: Colors.blue,
                trailing: Text(
                  auth.state.isLoggedIn ? '账号' : '本地',
                  style: TextStyle(color: cs.primary, fontSize: 11),
                ),
                onTap: () => _showProfileDialog(context),
              ),
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
                  MaterialPageRoute(builder: (_) => const ThemePickerScreen()),
                ),
              ),
              _Tile(
                icon: Icons.tune,
                label: '偏好设置',
                color: Colors.indigo,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PreferencesScreen()),
                ),
              ),
              _Tile(
                icon: Icons.space_dashboard_outlined,
                label: '底部导航栏',
                color: Colors.blueGrey,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PreferencesScreen(
                      initialSection: PreferencesInitialSection.bottomNav,
                    ),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.lock_outline,
                label: '应用锁',
                color: Colors.red.shade400,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LockSettingsScreen()),
                ),
              ),
              if (auth.state.isLoggedIn)
                _Tile(
                  icon: Icons.password_outlined,
                  label: '修改登录密码',
                  color: Colors.deepOrange,
                  onTap: () => _showChangePasswordDialog(context),
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
                  MaterialPageRoute(builder: (_) => const ShareScreen()),
                ),
              ),
              _Tile(
                icon: Icons.extension_outlined,
                label: '扩展集成',
                color: Colors.deepPurple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const IntegrationsScreen()),
                ),
              ),
              _Tile(
                icon: Icons.sync_problem_outlined,
                label: '同步冲突记录',
                color: Colors.orange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SyncConflictLogScreen(),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.event_note_outlined,
                label: '导出为日历 (.ics)',
                color: Colors.lightBlue,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExportScreen()),
                ),
              ),
              _Tile(
                icon: Icons.backup_outlined,
                label: '备份',
                color: Colors.brown,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BackupScreen(initialMode: BackupEntryMode.backup),
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
                    builder: (_) => const BackupScreen(
                      initialMode: BackupEntryMode.restore,
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
                color: Colors.blueGrey,
                trailing: notifService.historyCount == 0
                    ? null
                    : Text(
                        '${notifService.historyCount} 条',
                        style: const TextStyle(fontSize: 11),
                      ),
                onTap: () => _openNotificationHistory(context),
              ),
              _Tile(
                icon: Icons.notifications_outlined,
                label: s.mineNotificationsLabel,
                subtitle: '管理提醒时间、通知权限和铃声',
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
                    MaterialPageRoute(builder: (_) => const AdminScreen()),
                  ),
                ),
              _Tile(
                icon: Icons.campaign_outlined,
                label: '公告',
                color: Colors.cyan,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AnnouncementsScreen(),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.lightbulb_outline,
                label: '功能建议',
                color: Colors.indigo,
                onTap: () => _openFeedback(context, auth, 'feature'),
              ),
              _Tile(
                icon: Icons.report_problem_outlined,
                label: '问题反馈',
                color: Colors.red.shade400,
                onTap: () => _openFeedback(context, auth, 'bug'),
              ),
              _Tile(
                icon: Icons.auto_awesome_outlined,
                label: '许愿池',
                color: Colors.purple,
                onTap: () => _openFeedback(context, auth, 'wish'),
              ),
              _Tile(
                icon: Icons.system_update,
                label: '检查更新',
                color: Colors.teal,
                trailing: updater.checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : (updater.hasUpdate
                          ? _UpdateAvailableBadge(
                              version: updater.latestVersion,
                            )
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

  void _showProfileDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const _ChangePasswordDialog());
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
                      style: TextStyle(fontWeight: FontWeight.w400),
                    ),
                  ] else if (updater.error == null && !updater.checking) ...[
                    const SizedBox(height: 12),
                    const Text('已是最新版本'),
                  ],
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '更新内容',
                      style: TextStyle(fontWeight: FontWeight.w400),
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
                if (updater.hasUpdate && updater.latestUrl != null)
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

  void _openNotificationSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PreferencesScreen(
          initialSection: PreferencesInitialSection.notifications,
        ),
      ),
    );
  }

  void _openNotificationHistory(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _NotificationHistoryScreen()),
    );
  }

  void _openFeedback(BuildContext context, AuthProvider auth, String category) {
    if (!auth.state.isLoggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeedbackScreen(initialCategory: category),
      ),
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
    final uri = Uri.tryParse(value);
    final isUrl =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final localPath = _localAvatarPath(value);
    final fallback = value.isNotEmpty ? value : displayName;
    final letter = fallback.isNotEmpty ? fallback.characters.first : '我';

    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primary,
      child: isUrl
          ? ClipOval(
              child: Image.network(
                value,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _ProfileAvatarLetter(
                  letter: letter,
                  fontSize: 20,
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
                  fontSize: 20,
                  color: cs.onPrimary,
                ),
              ),
            )
          : Text(
              letter,
              style: TextStyle(
                fontSize: 20,
                color: cs.onPrimary,
                fontWeight: FontWeight.w400,
              ),
            ),
    );
  }
}

class _ProfileAvatarLetter extends StatelessWidget {
  final String letter;
  final double fontSize;
  final Color color;

  const _ProfileAvatarLetter({
    required this.letter,
    required this.fontSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      letter,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

String? _localAvatarPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.scheme == 'file') {
    return uri.toFilePath();
  }
  if (trimmed.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
    return trimmed;
  }
  return null;
}

class _NotificationHistoryScreen extends StatefulWidget {
  const _NotificationHistoryScreen();

  @override
  State<_NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState
    extends State<_NotificationHistoryScreen> {
  static const _pageSize = 50;

  final _searchCtrl = TextEditingController();
  NotificationType? _typeFilter;
  int _page = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<NotificationItem> _filteredHistory(List<NotificationItem> history) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return history
        .where((item) {
          if (_typeFilter != null && item.type != _typeFilter) return false;
          if (query.isEmpty) return true;
          return item.title.toLowerCase().contains(query) ||
              item.body.toLowerCase().contains(query) ||
              (item.relatedId ?? '').toLowerCase().contains(query) ||
              _notificationTypeLabel(item.type).toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  void _resetPaging() {
    _page = 0;
  }

  void _changePage(int page) {
    setState(() => _page = page < 0 ? 0 : page);
  }

  Future<void> _confirmClearHistory(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('清空通知记录？'),
        icon: const Icon(Icons.delete_outline),
        content: Text('将清空当前保留的 $count 条通知记录，已调度的提醒不会被取消。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await context.read<NotificationService>().clearHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('通知记录已清空'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.watch<NotificationService>();
    final history = ns.history;
    final filteredHistory = _filteredHistory(history);
    final cs = Theme.of(context).colorScheme;
    final totalPages = filteredHistory.isEmpty
        ? 1
        : ((filteredHistory.length - 1) ~/ _pageSize) + 1;
    final currentPage = _page >= totalPages ? totalPages - 1 : _page;
    if (currentPage != _page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _page = currentPage);
      });
    }
    final pageStart = currentPage * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, filteredHistory.length);
    final visibleHistory = filteredHistory.sublist(pageStart, pageEnd);

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知记录'),
        actions: [
          TextButton.icon(
            onPressed: history.isEmpty
                ? null
                : () => _confirmClearHistory(history.length),
            icon: const Icon(Icons.delete_outline),
            label: const Text('清空'),
          ),
        ],
      ),
      body: history.isEmpty
          ? const Center(child: Text('暂无通知记录'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: AppSurfaceCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: '搜索标题、内容或关联 ID',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchCtrl.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: '清空搜索',
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(_resetPaging);
                                    },
                                  ),
                            isDense: true,
                          ),
                          textInputAction: TextInputAction.search,
                          onChanged: (_) => setState(_resetPaging),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _historyTypeChip('全部', null),
                              for (final type in NotificationType.values)
                                _historyTypeChip(
                                  _notificationTypeLabel(type),
                                  type,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          filteredHistory.isEmpty
                              ? '共 ${history.length} 条，当前筛选无结果'
                              : filteredHistory.length == history.length
                              ? '共 ${history.length} 条 · 支持搜索、筛选和分页浏览 · 第 ${currentPage + 1} / $totalPages 页 · 每页 $_pageSize 条'
                              : '已筛出 ${filteredHistory.length} / ${history.length} 条 · 支持搜索、筛选和分页浏览 · 第 ${currentPage + 1} / $totalPages 页',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.58),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: filteredHistory.isEmpty
                      ? const EmptyState(
                          icon: Icons.manage_search_outlined,
                          message: '没有匹配的通知记录',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                          itemCount: visibleHistory.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = visibleHistory[index];
                            return AppSurfaceCard(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: _notificationColor(
                                        item.type,
                                      ).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _notificationIcon(item.type),
                                      size: 20,
                                      color: _notificationColor(item.type),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              item.title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w400,
                                                    color: cs.onSurface,
                                                  ),
                                            ),
                                            AppStatusBadge(
                                              label: _notificationTypeLabel(
                                                item.type,
                                              ),
                                              color: _notificationColor(
                                                item.type,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        if (item.body.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            item.body,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: cs.onSurface
                                                      .withValues(alpha: 0.66),
                                                ),
                                          ),
                                        ],
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatNotificationTime(
                                            item.scheduledTime,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: cs.onSurface.withValues(
                                                  alpha: 0.48,
                                                ),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                if (filteredHistory.length > _pageSize)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        Text(
                          '${pageStart + 1}-$pageEnd / ${filteredHistory.length}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const Spacer(),
                        IconButton.outlined(
                          tooltip: '上一页',
                          onPressed: currentPage == 0
                              ? null
                              : () => _changePage(currentPage - 1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          tooltip: '下一页',
                          onPressed: currentPage >= totalPages - 1
                              ? null
                              : () => _changePage(currentPage + 1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _historyTypeChip(String label, NotificationType? type) {
    final selected = _typeFilter == type;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() {
          _typeFilter = type;
          _resetPaging();
        }),
      ),
    );
  }

  Color _notificationColor(NotificationType type) {
    return switch (type) {
      NotificationType.todo => Colors.blue,
      NotificationType.habit => Colors.green,
      NotificationType.pomodoro => Colors.red,
      NotificationType.anniversary => Colors.pink,
      NotificationType.location => Colors.teal,
      NotificationType.general => Colors.orange,
    };
  }

  IconData _notificationIcon(NotificationType type) {
    return switch (type) {
      NotificationType.todo => Icons.checklist,
      NotificationType.habit => Icons.repeat,
      NotificationType.pomodoro => Icons.timer,
      NotificationType.anniversary => Icons.event_available_outlined,
      NotificationType.location => Icons.location_on_outlined,
      NotificationType.general => Icons.notifications_active_outlined,
    };
  }

  String _notificationTypeLabel(NotificationType type) {
    return switch (type) {
      NotificationType.todo => '待办',
      NotificationType.habit => '习惯',
      NotificationType.pomodoro => '番茄钟',
      NotificationType.anniversary => '纪念日',
      NotificationType.location => '位置',
      NotificationType.general => '系统',
    };
  }

  String _formatNotificationTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newPassword = _newCtrl.text;
    if (newPassword.length < 6) {
      setState(() => _error = '新密码至少 6 位');
      return;
    }
    if (newPassword != _confirmCtrl.text) {
      setState(() => _error = '两次输入的新密码不一致');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: newPassword,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('登录密码已更新')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改登录密码'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _currentCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '当前密码'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认新密码'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
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
  String? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ai = context.read<AiService>();
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final completed = widget.todoProvider.completedTodos.length;
      final total = widget.todoProvider.todos.length;
      final focus =
          widget.pomodoroProvider.sessions
              .where(
                (s) => s.type.name == 'focus' && s.startTime.isAfter(weekAgo),
              )
              .fold(0, (sum, s) => sum + s.durationSeconds) ~/
          60;
      final streak = widget.habitProvider.longestCurrentStreak;
      _result = await ai.weeklyReview(
        completedTodos: completed,
        totalTodos: total,
        weeklyFocusMinutes: focus,
        habitStreak: streak,
      );
    } on AiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(18),
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
                style: TextStyle(fontWeight: FontWeight.w400),
              ),
              const Spacer(),
              TextButton(
                onPressed: _busy ? null : _run,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('生成'),
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
              child: Text(
                _result!,
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '点击"生成"让 AI 根据本周完成数据写一段总结与建议',
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
    final isDark = theme.brightness == Brightness.dark;
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
                fontWeight: FontWeight.w400,
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? cs.surface.withValues(alpha: 0.54)
                  : cs.surface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: cs.outlineVariant.withValues(
                  alpha: isDark ? 0.62 : 0.82,
                ),
              ),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
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
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: isDark
                ? cs.surfaceContainerHighest.withValues(alpha: 0.34)
                : cs.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.76 : 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.022),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
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
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13.5,
                          height: 1.2,
                          fontWeight: FontWeight.w400,
                          color: cs.onSurface,
                        ),
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
      ),
    );
  }
}
