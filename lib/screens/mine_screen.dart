import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/todo_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/cloud_sync_provider.dart';
import '../providers/user_provider.dart';
import '../providers/notification_service.dart';
import '../providers/auth_provider.dart';
import '../services/ai_service.dart';
import '../services/app_update_service.dart';
import '../widgets/stats_overview_cards.dart';
import 'theme_picker_screen.dart';
import 'login_screen.dart';
import 'announcements_screen.dart';
import 'feedback_screen.dart';
import 'countdown_screen.dart';
import 'note_screen.dart';
import 'statistics_screen.dart';
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

class MineScreen extends StatelessWidget {
  const MineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final s = themeProvider.brand.strings;
    final todoProvider = context.watch<TodoProvider>();
    final habitProvider = context.watch<HabitProvider>();
    final pomodoroProvider = context.watch<PomodoroProvider>();
    final syncProvider = context.watch<CloudSyncProvider>();
    final userProvider = context.watch<UserProvider>();
    final notifService = context.watch<NotificationService>();
    final auth = context.watch<AuthProvider>();
    final ai = context.watch<AiService>();
    final updater = context.watch<AppUpdateService>();
    final cs = Theme.of(context).colorScheme;

    userProvider.recalc(
      completedTodos: todoProvider.completedTodos.length,
      totalFocusMinutes: pomodoroProvider.totalFocusMinutes,
      currentStreak: habitProvider.longestCurrentStreak,
      bestStreak: habitProvider.longestBestStreak,
    );
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
    final displayName = auth.state.isLoggedIn
        ? auth.state.username ?? p.username
        : '游客';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s.mineTitle),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        children: [
          // Profile header
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: cs.primary,
                  child: Text(
                    displayName.isNotEmpty ? displayName.substring(0, 1) : '我',
                    style: TextStyle(
                      fontSize: 20,
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting，$displayName',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.mineProductivityScore} ${p.productivityScore}',
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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
                            color: Colors.deepOrange.withValues(alpha: 0.15),
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
                if (auth.state.isLoggedIn)
                  IconButton(
                    onPressed: () async {
                      await context.read<AuthProvider>().logout();
                    },
                    icon: const Icon(Icons.logout),
                    tooltip: '退出登录',
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
            child: Row(
              children: [
                Expanded(
                  child: StatsOverviewCard(
                    title: '待办完成',
                    value: '${_todoRate(todoProvider)}%',
                    icon: Icons.task_alt,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatsOverviewCard(
                    title: '连续打卡',
                    value: '${p.currentStreak} 天',
                    icon: Icons.repeat,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: StatsOverviewCard(
                    title: '本周专注',
                    value: '${_weeklyFocus(pomodoroProvider)} 分钟',
                    icon: Icons.timer,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatsOverviewCard(
                    title: '综合评分',
                    value: '${p.productivityScore}',
                    icon: Icons.auto_awesome,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ),

          // AI weekly review
          if (ai.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _AiWeeklyReviewCard(
                todoProvider: todoProvider,
                pomodoroProvider: pomodoroProvider,
                habitProvider: habitProvider,
              ),
            ),

          const SizedBox(height: 8),
          _Section(title: '效率与工具'),
          _Tile(
            icon: Icons.flag_outlined,
            label: '目标管理',
            color: Colors.orange,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GoalScreen()),
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
          _Tile(
            icon: Icons.search,
            label: '全局搜索',
            color: Colors.blueGrey,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          _Tile(
            icon: Icons.pie_chart_outline,
            label: '时光足迹 (数据报表)',
            color: Colors.indigo,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StatisticsScreen()),
            ),
          ),
          _Tile(
            icon: Icons.event_available_outlined,
            label: '纪念日 · 生日 · 倒数',
            color: Colors.pink,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AnniversaryScreen()),
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
            icon: Icons.school_outlined,
            label: '课程表',
            color: Colors.blue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const CourseScheduleScreen()),
            ),
          ),
          _Tile(
            icon: Icons.wb_sunny_outlined,
            label: '黄历 · 万年历',
            color: Colors.deepOrange,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlmanacScreen()),
            ),
          ),
          _Tile(
            icon: Icons.timer_outlined,
            label: '简易倒数日 (兼容旧数据)',
            color: Colors.grey,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CountdownScreen()),
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
            label: '备份 · 恢复',
            color: Colors.brown,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackupScreen()),
            ),
          ),

          const SizedBox(height: 8),
          _Section(title: s.mineSectionShortcuts),
          _Tile(
            icon: Icons.campaign_outlined,
            label: '公告',
            color: Colors.cyan,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
            ),
          ),
          _Tile(
            icon: Icons.feedback_outlined,
            label: '反馈与许愿',
            color: Colors.indigo,
            onTap: () {
              if (!auth.state.isLoggedIn) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FeedbackScreen()),
              );
            },
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
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '新版 ${updater.latestVersion}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.red,
                            ),
                          ),
                        )
                      : null),
            onTap: () => _showUpdateDialog(context, updater),
          ),

          const SizedBox(height: 8),
          _Section(title: s.mineSectionSettings),
          _Tile(
            icon: Icons.palette,
            label: s.mineThemeLabel,
            color: cs.primary,
            trailing: Text(
              themeProvider.brand.name,
              style: TextStyle(color: cs.primary, fontSize: 13),
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ThemePickerScreen()),
            ),
          ),
          _Tile(
            icon: Icons.notifications_outlined,
            label: s.mineNotificationsLabel,
            color: Colors.orange,
            trailing: Text(
              '${notifService.pendingCount} 条',
              style: const TextStyle(fontSize: 13),
            ),
            onTap: () => _notifDialog(context, notifService),
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
          if (auth.state.isLoggedIn &&
              (auth.serverConfig['backup_enabled'] != false))
            _Tile(
              icon: Icons.cloud_sync_outlined,
              label: '立即同步',
              color: Colors.cyan,
              trailing: syncProvider.isSyncing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      syncProvider.hasEverSynced
                          ? _formatTime(syncProvider.config.lastSync)
                          : '未同步',
                      style: TextStyle(
                        fontSize: 12,
                        color: syncProvider.hasEverSynced
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ),
              onTap: syncProvider.isSyncing
                  ? null
                  : () async {
                      await syncProvider.syncNow();
                      if (!context.mounted) return;
                      final err = syncProvider.lastError;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(err == null ? '同步完成' : '同步失败: $err'),
                        ),
                      );
                    },
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
            icon: Icons.info_outline,
            label: s.mineAboutLabel,
            color: Colors.grey,
            onTap: () => _aboutDialog(context),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    if (t.millisecondsSinceEpoch == 0) return '未同步';
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
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

  void _showUpdateDialog(BuildContext context, AppUpdateService u) async {
    if (!u.checking) await u.checkNow();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('检查更新'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本: ${u.currentVersion}'),
            Text('远端版本: ${u.latestVersion ?? '—'}'),
            if (u.error != null) ...[
              const SizedBox(height: 8),
              Text(
                u.error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            if (u.hasUpdate) ...[
              const SizedBox(height: 12),
              const Text(
                '发现新版本',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if ((u.latestNotes ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    u.latestNotes!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              if (u.latestUrl != null) ...[
                const SizedBox(height: 8),
                Text(
                  '下载地址：${u.latestUrl}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          if (u.hasUpdate && u.latestUrl != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('请在浏览器中打开 ${u.latestUrl}')),
                );
              },
              child: const Text('前往下载'),
            ),
        ],
      ),
    );
  }

  void _notifDialog(BuildContext context, NotificationService ns) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('通知记录'),
        content: ns.history.isEmpty
            ? const Text('暂无通知记录')
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: ns.history.take(10).length,
                  itemBuilder: (_, i) {
                    final n = ns.history[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.notifications_active, size: 16),
                      title: Text(
                        n.title,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        n.body,
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () {
              ns.clearHistory();
              Navigator.pop(ctx);
            },
            child: const Text('清空历史'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _aboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('多仪'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('版本: v1.0.0'),
            SizedBox(height: 4),
            Text('Flutter 跨平台效率工具'),
            SizedBox(height: 4),
            Text('待办 · 习惯 · 日历 · 番茄专注'),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: cs.primary, size: 18),
                const SizedBox(width: 6),
                const Text(
                  'AI 每周回顾',
                  style: TextStyle(fontWeight: FontWeight.w600),
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
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _result!,
                  style: const TextStyle(fontSize: 13, height: 1.6),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '点击"生成"让 AI 根据本周完成数据写一段总结与建议',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.label,
    required this.color,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: trailing ?? const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}
