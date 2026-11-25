import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_brand.dart';
import '../../core/app_version.dart';
import '../../core/global_search.dart';
import '../../core/i18n.dart';
import '../../models/note.dart';
import '../../providers/auth_provider.dart';
import '../../providers/habit_provider.dart';
import '../../providers/note_provider.dart';
import '../../providers/pomodoro_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/todo_provider.dart';
import '../../providers/user_provider.dart';
import '../../screens/anniversary_screen.dart';
import '../../screens/backup_screen.dart';
import '../../screens/countdown_screen.dart';
import '../../screens/course_schedule_screen.dart';
import '../../screens/diary_screen.dart';
import '../../screens/export_screen.dart';
import '../../screens/goal_screen.dart';
import '../../screens/integrations_screen.dart';
import '../../screens/lock_settings_screen.dart';
import '../../screens/login_screen.dart';
import '../../screens/mine_screen.dart';
import '../../screens/more_apps_screen.dart';
import '../../screens/note_screen.dart';
import '../../screens/notification_history_screen.dart';
import '../../screens/preferences_screen.dart';
import '../../screens/profile_screen.dart';
import '../../screens/statistics_screen.dart';
import '../../screens/sync_conflict_log_screen.dart';
import '../../screens/theme_picker_screen.dart';
import '../../screens/time_audit_screen.dart';
import '../../widgets/brand_background.dart';
import '../../widgets/surface_components.dart';
import '../../widgets/sync_status_card.dart';
import '../desktop_embedded_scope.dart';
import '../desktop_web_nav.dart';
import '../desktop_web_tokens.dart';

class DesktopEmbeddedPage extends StatefulWidget {
  final DesktopWebDestination destination;
  final DesktopWebNavController? controller;
  final void Function(DesktopWebDestination destination)? onNavigate;

  const DesktopEmbeddedPage({
    super.key,
    required this.destination,
    this.controller,
    this.onNavigate,
  });

  @override
  State<DesktopEmbeddedPage> createState() => _DesktopEmbeddedPageState();
}

class _DesktopEmbeddedPageState extends State<DesktopEmbeddedPage> {
  String? _lastTopBarSignature;

  DesktopWebNavController? _resolveNav(BuildContext context) {
    return widget.controller ?? DesktopWebScope.maybeOf(context);
  }

  void _syncTopBar(BuildContext context, AppLocale locale) {
    final nav = _resolveNav(context);
    if (nav == null) return;
    final signature = '${widget.destination.name}|${locale.storageValue}';
    if (_lastTopBarSignature == signature) return;
    _lastTopBarSignature = signature;
    final isEn = locale == AppLocale.en;
    final label = widget.destination.localizedLabel(locale);
    final section = widget.destination.sectionLabel(locale);
    nav.setTopBarSpec(
      widget.destination,
      DesktopTopBarSpec(
        title: label,
        breadcrumb: section,
        subtitle: _subtitleFor(widget.destination, isEn),
      ),
    );
  }

  String _subtitleFor(DesktopWebDestination dest, bool isEn) {
    return switch (dest) {
      DesktopWebDestination.goals =>
        isEn ? 'Long-term milestones & progress' : '长期目标拆解与进度追踪',
      DesktopWebDestination.notes =>
        isEn ? 'Quick notes & organized library' : '灵感记录与结构化随手记',
      DesktopWebDestination.diary =>
        isEn ? 'Daily reflections & mood trends' : '每日复盘与情绪热力记录',
      DesktopWebDestination.stats =>
        isEn ? 'Focus, tasks, and habit analytics' : '任务、习惯与专注多维报表',
      DesktopWebDestination.timeAudit =>
        isEn ? 'Timeline & category audit' : '时间足迹与分类投入分析',
      DesktopWebDestination.schedule =>
        isEn ? 'Weekly course & timetable view' : '每周课表与课程安排',
      DesktopWebDestination.anniversary =>
        isEn ? 'Birthdays & milestone events' : '生日提醒与重要纪念日',
      DesktopWebDestination.countdown =>
        isEn ? 'Target dates & live countdowns' : '目标日期与倒计时追踪',
      DesktopWebDestination.themes =>
        isEn ? 'Themes, glass surfaces & skins' : '品牌主题、毛玻璃与卡片皮肤',
      DesktopWebDestination.settings =>
        isEn ? 'Workspace account, preferences & sync' : '账号概览、偏好设置与同步数据',
      DesktopWebDestination.moreApps =>
        isEn ? 'Additional modules & hidden tools' : '更多效率入口与扩展工具',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        _syncTopBar(context, locale);
        final t = DesktopWebTokens.of(context);
        if (widget.destination == DesktopWebDestination.settings) {
          return DesktopEmbeddedHostScope(
            child: DesktopAccountOverviewView(
              controller: widget.controller,
              onNavigate: widget.onNavigate,
            ),
          );
        }

        final nav = _resolveNav(context);
        final embedded = nav == null
            ? _buildEmbeddedChild(context, null)
            : ListenableBuilder(
                listenable: nav,
                builder: (ctx, _) => _buildEmbeddedChild(ctx, nav),
              );
        final baseTheme = Theme.of(context);
        final embeddedTheme = baseTheme.copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          appBarTheme: baseTheme.appBarTheme.copyWith(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
            toolbarHeight: 46,
            shape: Border(
              bottom: BorderSide(
                color: t.hairlineBorder,
                width: DesktopWebTokens.hairlineWidth,
              ),
            ),
            titleTextStyle: t.cardTitleStyle.copyWith(fontSize: 15),
            foregroundColor: t.textPrimary,
          ),
        );

        return DesktopEmbeddedHostScope(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesktopWebTokens.embeddedMaxWidth,
                ),
                child: DecoratedBox(
                  decoration: t.panelDecoration(
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusXl,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusXl,
                    ),
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      removeBottom: true,
                      child: Theme(
                        data: embeddedTheme,
                        child: AppSecondaryControlTheme(
                          child: LayoutBuilder(
                            builder: (_, constraints) {
                              final height = constraints.hasBoundedHeight
                                  ? constraints.maxHeight
                                  : 760.0;
                              return SizedBox(
                                width: constraints.hasBoundedWidth
                                    ? constraints.maxWidth
                                    : DesktopWebTokens.embeddedMaxWidth,
                                height: height,
                                child: embedded,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmbeddedChild(
    BuildContext context,
    DesktopWebNavController? nav,
  ) {
    final prefs = context.read<PreferencesProvider?>();
    final selectedGoalId = nav?.selectedIdFor(SearchKind.goal);
    final selectedNoteId = nav?.selectedIdFor(SearchKind.note);
    final selectedDiaryId = nav?.selectedIdFor(SearchKind.diary);
    final selectedTimeEntryId = nav?.selectedIdFor(SearchKind.timeEntry);
    final selectedCourseId = nav?.selectedIdFor(SearchKind.course);
    final selectedAnniversaryId = nav?.selectedIdFor(SearchKind.anniversary);
    final selectedCountdownId = nav?.selectedIdFor(SearchKind.countdown);
    return switch (widget.destination) {
      DesktopWebDestination.goals => GoalScreen(
        key: ValueKey('desktop_goal_${selectedGoalId ?? 'all'}'),
        initialGoalId: selectedGoalId,
      ),
      DesktopWebDestination.notes => _buildNotesWithDeepLink(
        context,
        nav: nav,
        selectedNoteId: selectedNoteId,
      ),
      DesktopWebDestination.diary => DiaryScreen(
        key: ValueKey('desktop_diary_${selectedDiaryId ?? 'all'}'),
        initialEntryId: selectedDiaryId,
      ),
      DesktopWebDestination.stats => const StatisticsScreen(),
      DesktopWebDestination.timeAudit => TimeAuditScreen(
        key: ValueKey('desktop_time_audit_${selectedTimeEntryId ?? 'all'}'),
        initialEntryId: selectedTimeEntryId,
        openInitialEntrySheet: false,
      ),
      DesktopWebDestination.schedule => CourseScheduleScreen(
        key: ValueKey('desktop_schedule_${selectedCourseId ?? 'all'}'),
        initialCourseId: selectedCourseId,
        openInitialCourseSheet: false,
      ),
      DesktopWebDestination.anniversary => AnniversaryScreen(
        key: ValueKey(
          'desktop_anniversary_${selectedAnniversaryId ?? 'all'}',
        ),
        initialAnniversaryId: selectedAnniversaryId,
      ),
      DesktopWebDestination.countdown => CountdownScreen(
        key: ValueKey('desktop_countdown_${selectedCountdownId ?? 'all'}'),
        initialCountdownId: selectedCountdownId,
      ),
      DesktopWebDestination.themes => const ThemePickerScreen(),
      DesktopWebDestination.moreApps => MoreApplicationsScreen(
        visibleBottomNavTabs: prefs?.visibleBottomNavTabs,
      ),
      DesktopWebDestination.settings => DesktopAccountOverviewView(
        controller: widget.controller,
        onNavigate: widget.onNavigate,
      ),
      _ => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.destination.icon,
                size: 36,
                color: DesktopWebTokens.of(context).textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                widget.destination.localizedLabel(I18n.current),
                style: DesktopWebTokens.of(context).cardTitleStyle,
              ),
            ],
          ),
        ),
      ),
    };
  }

  Widget _buildNotesWithDeepLink(
    BuildContext context, {
    required DesktopWebNavController? nav,
    required String? selectedNoteId,
  }) {
    if (selectedNoteId == null || selectedNoteId.isEmpty) {
      return const NoteScreen();
    }
    final notes = context.watch<NoteProvider?>()?.notes ?? const <NoteItem>[];
    final matched = notes
        .where((note) => note.id == selectedNoteId)
        .firstOrNull;
    if (matched == null) {
      return const NoteScreen();
    }
    final t = DesktopWebTokens.of(context);
    final isEn = I18n.current == AppLocale.en;
    final headline = matched.title.trim().isNotEmpty
        ? matched.title.trim()
        : matched.preview;
    return Column(
      children: [
        Container(
          key: ValueKey('desktop_note_deeplink_${matched.id}'),
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: t.accentSoft,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
            border: Border.all(
              color: t.accent.withValues(alpha: 0.32),
              width: DesktopWebTokens.hairlineWidth,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 18, color: t.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline.isEmpty
                      ? (isEn ? 'Matched note' : '已定位到笔记')
                      : headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyStyle.copyWith(color: t.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          BrandRouteSurface(child: NoteEditScreen(note: matched)),
                    ),
                  );
                },
                child: Text(isEn ? 'Open note' : '打开笔记'),
              ),
              IconButton(
                tooltip: isEn ? 'Dismiss' : '关闭定位',
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () => nav?.clearSelectedEntity(),
              ),
            ],
          ),
        ),
        const Expanded(child: NoteScreen()),
      ],
    );
  }
}

class DesktopAccountOverviewView extends StatelessWidget {
  final DesktopWebNavController? controller;
  final void Function(DesktopWebDestination destination)? onNavigate;

  const DesktopAccountOverviewView({
    super.key,
    this.controller,
    this.onNavigate,
  });

  void _openEmbeddedRoute(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrandRouteSurface(child: screen),
      ),
    );
  }

  void _navigateToDestination(
    BuildContext context,
    DesktopWebDestination destination,
  ) {
    if (onNavigate != null) {
      onNavigate!(destination);
      return;
    }
    final nav = controller ?? DesktopWebScope.maybeOf(context);
    if (nav != null) {
      nav.navigateTo(destination);
      return;
    }
    if (destination == DesktopWebDestination.themes) {
      _openEmbeddedRoute(context, const ThemePickerScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final t = DesktopWebTokens.of(context);
        final isEn = locale == AppLocale.en;
        final nav = controller ?? DesktopWebScope.maybeOf(context);
        final auth = context.watch<AuthProvider?>();
        final user = context.watch<UserProvider?>();
        final themeProvider = context.watch<ThemeProvider?>();
        final localeProvider = context.watch<LocaleProvider?>();
        final todoProvider = context.watch<TodoProvider?>();
        final habitProvider = context.watch<HabitProvider?>();
        final pomodoroProvider = context.watch<PomodoroProvider?>();
        final prefs = context.watch<PreferencesProvider?>();

        final isLoggedIn = auth?.state.isLoggedIn ?? false;
        String? cleanName(String? raw) {
          final trimmed = raw?.trim();
          if (trimmed == null || trimmed.isEmpty) return null;
          if (!isLoggedIn && trimmed == '用户') return null;
          return trimmed;
        }

        final displayName = _firstNonEmpty([
          cleanName(auth?.state.displayName),
          cleanName(auth?.state.username),
          cleanName(user?.profile.displayName),
          cleanName(user?.profile.username),
          isEn ? 'Local Workspace' : '本地工作区',
        ]);
        final subtitle = isLoggedIn
            ? _firstNonEmpty([
                auth?.state.email,
                isEn ? 'Signed in · Cloud sync ready' : '已登录 · 云端同步已就绪',
              ])
            : (isEn
                  ? 'Guest mode · Data saved locally in browser'
                  : '访客模式 · 数据安全保存在本地浏览器中');
        final initial = displayName.isNotEmpty
            ? displayName.substring(0, 1).toUpperCase()
            : 'L';

        final completedTodos = todoProvider?.todos
                .where((item) => item.isCompleted)
                .length ??
            0;
        final habitCount = habitProvider?.habits.length ?? 0;
        final focusMinutes = pomodoroProvider?.mineWeeklyFocusMinutes ?? 0;
        final currentBrand = themeProvider?.brand ?? AppBrands.defaultBrand;

        final actionCards = <_SettingsQuickCardData>[
          _SettingsQuickCardData(
            key: const ValueKey('desktop_settings_card_preferences'),
            icon: Icons.tune_rounded,
            color: t.info,
            title: isEn ? 'Preferences' : '个性化偏好',
            subtitle: isEn
                ? 'Week start, date format, reminders & defaults'
                : '周首日、日期格式、默认页面与提醒规则',
            actionLabel: isEn ? 'Open' : '配置',
            onTap: () => _openEmbeddedRoute(context, const PreferencesScreen()),
          ),
          _SettingsQuickCardData(
            key: const ValueKey('desktop_settings_card_themes'),
            icon: Icons.palette_outlined,
            color: t.accent,
            title: isEn ? 'Themes & Skins' : '外观主题与皮肤',
            subtitle: isEn
                ? 'Current: ${currentBrand.localizedName}'
                : '当前主题：${currentBrand.localizedName}',
            actionLabel: isEn ? 'Browse' : '切换主题',
            onTap: () => _navigateToDestination(
              context,
              DesktopWebDestination.themes,
            ),
          ),
          _SettingsQuickCardData(
            key: const ValueKey('desktop_settings_card_backup'),
            icon: Icons.backup_outlined,
            color: t.success,
            title: isEn ? 'Backup & Restore' : '数据备份与恢复',
            subtitle: isEn
                ? 'JSON/CSV snapshots, WebDAV & import tools'
                : '本地全量导出、CSV/Markdown 与恢复',
            actionLabel: isEn ? 'Manage' : '打开备份',
            onTap: () => _openEmbeddedRoute(
              context,
              const BackupScreen(initialMode: BackupEntryMode.backup),
            ),
          ),
          _SettingsQuickCardData(
            key: const ValueKey('desktop_settings_card_export'),
            icon: Icons.event_note_outlined,
            color: t.warning,
            title: isEn ? 'iCalendar & Integrations' : '日历导出与扩展集成',
            subtitle: isEn
                ? 'Export .ics calendars & subscribe external feeds'
                : '生成 .ics 日历订阅与外部日历集成',
            actionLabel: isEn ? 'Export' : '导出 .ics',
            onTap: () => _openEmbeddedRoute(context, const ExportScreen()),
          ),
          _SettingsQuickCardData(
            key: const ValueKey('desktop_settings_card_integrations'),
            icon: Icons.extension_outlined,
            color: const Color(0xFF7E57C2),
            title: isEn ? 'Integrations & Subscriptions' : '扩展功能与订阅',
            subtitle: isEn
                ? 'Calendar subscriptions, geofence & language'
                : '外部日历订阅、位置提醒与语言入口',
            actionLabel: isEn ? 'Configure' : '进入扩展',
            onTap: () =>
                _openEmbeddedRoute(context, const IntegrationsScreen()),
          ),
          _SettingsQuickCardData(
            key: const ValueKey('desktop_settings_card_mine_full'),
            icon: Icons.dashboard_customize_outlined,
            color: t.textSecondary,
            title: isEn ? 'Classic Profile & All Modules' : '完整个人中心与全部工具',
            subtitle: isEn
                ? 'Security lock, notification log & full settings'
                : '应用锁、通知记录、更多应用与完整面板',
            actionLabel: isEn ? 'Open All' : '打开面板',
            onTap: () => _openEmbeddedRoute(
              context,
              MineScreen(
                useShellBackground: true,
                visibleBottomNavTabs: prefs?.visibleBottomNavTabs,
              ),
            ),
          ),
        ];

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesktopWebTokens.embeddedMaxWidth,
            ),
            child: SingleChildScrollView(
              key: const ValueKey('desktop_account_overview_view'),
              padding: const EdgeInsets.fromLTRB(
                DesktopWebTokens.space2xl,
                DesktopWebTokens.spaceXl,
                DesktopWebTokens.space2xl,
                DesktopWebTokens.space3xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Account Hero Card
                  DesktopPanelCard(
                    padding: const EdgeInsets.all(22),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 720;
                        final identity = Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: t.accentSoft,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: t.accentBorder,
                                  width: DesktopWebTokens.hairlineWidth,
                                ),
                              ),
                              child: Text(
                                initial,
                                style: t.heroTitleStyle.copyWith(
                                  fontSize: 22,
                                  color: t.accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: t.heroTitleStyle.copyWith(
                                            fontSize: 19,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isLoggedIn
                                              ? t.success.withValues(alpha: 0.12)
                                              : t.mutedSurface,
                                          borderRadius: BorderRadius.circular(
                                            DesktopWebTokens.radiusPill,
                                          ),
                                          border: Border.all(
                                            color: isLoggedIn
                                                ? t.success.withValues(
                                                    alpha: 0.28,
                                                  )
                                                : t.hairlineBorder,
                                            width: DesktopWebTokens
                                                .hairlineWidth,
                                          ),
                                        ),
                                        child: Text(
                                          isLoggedIn
                                              ? (isEn ? 'Signed in' : '已登录')
                                              : (isEn ? 'Local' : '本地'),
                                          style: t.captionStyle.copyWith(
                                            color: isLoggedIn
                                                ? t.success
                                                : t.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.bodyMutedStyle,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );

                        final statsRow = Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _AccountStatPill(
                              label: isEn ? 'Todos Done' : '已完成待办',
                              value: '$completedTodos',
                            ),
                            _AccountStatPill(
                              label: isEn ? 'Habits' : '活跃习惯',
                              value: '$habitCount',
                            ),
                            _AccountStatPill(
                              label: isEn ? 'Weekly Focus' : '本周专注',
                              value: '$focusMinutes ${isEn ? 'min' : '分钟'}',
                            ),
                            FilledButton(
                              onPressed: () => _openEmbeddedRoute(
                                context,
                                isLoggedIn
                                    ? const ProfileScreen()
                                    : const LoginScreen(),
                              ),
                              child: Text(
                                isLoggedIn
                                    ? (isEn ? 'Edit Profile' : '编辑资料')
                                    : (isEn ? 'Sign In' : '登录账号'),
                              ),
                            ),
                          ],
                        );

                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              identity,
                              const SizedBox(height: 16),
                              statsRow,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: identity),
                            const SizedBox(width: 16),
                            statsRow,
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: DesktopWebTokens.spaceLg),

                  // Quick Workspace Controls (Appearance & Language) + Read-only Cloud Sync
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoCol = constraints.maxWidth >= 780;
                      final appearanceCard = DesktopPanelCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEn ? 'Workspace Appearance & Language' : '桌面外观与语言',
                              style: t.cardTitleStyle,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isEn
                                  ? 'Switch surface feel, brightness, or interface language immediately.'
                                  : '即时切换浅色/深色、毛玻璃质感与中英文界面语言。',
                              style: t.captionStyle,
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SegmentedButton<AppLocale>(
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(
                                      value: AppLocale.zh,
                                      label: Text('简体中文'),
                                    ),
                                    ButtonSegment(
                                      value: AppLocale.en,
                                      label: Text('English'),
                                    ),
                                  ],
                                  selected: {locale},
                                  onSelectionChanged: (sel) {
                                    final next = sel.first;
                                    if (localeProvider != null) {
                                      localeProvider.setLocale(next);
                                    } else {
                                      I18n.setLocale(next);
                                    }
                                  },
                                ),
                                if (nav != null) ...[
                                  OutlinedButton.icon(
                                    onPressed: () => nav.toggleDarkMode(
                                      Theme.of(context).brightness,
                                    ),
                                    icon: Icon(
                                      t.isDark
                                          ? Icons.light_mode_outlined
                                          : Icons.dark_mode_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      t.isDark
                                          ? (isEn ? 'Light Mode' : '切换浅色')
                                          : (isEn ? 'Dark Mode' : '切换深色'),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      final next = !t.isLiquidGlass;
                                      nav.setFrostedOverride(next);
                                      if (themeProvider != null) {
                                        if (next &&
                                            themeProvider.isBrandUnlocked(
                                              AppBrands.liquidGlass.id,
                                            ) &&
                                            themeProvider.brand.id !=
                                                AppBrands.liquidGlass.id) {
                                          themeProvider.setBrand(
                                            AppBrands.liquidGlass.id,
                                          );
                                        } else if (!next &&
                                            themeProvider.brand.id ==
                                                AppBrands.liquidGlass.id) {
                                          themeProvider.setBrand(
                                            AppBrands.defaultBrand.id,
                                          );
                                        }
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.blur_on_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      t.isLiquidGlass
                                          ? (isEn ? 'Default Surface' : '默认质感')
                                          : (isEn ? 'Frosted Glass' : '毛玻璃质感'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );

                      final syncCard = DesktopPanelCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    isEn ? 'Cloud Sync & Conflicts' : '云同步状态与日志',
                                    style: t.cardTitleStyle,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _openEmbeddedRoute(
                                    context,
                                    const SyncConflictLogScreen(),
                                  ),
                                  icon: const Icon(
                                    Icons.history_outlined,
                                    size: 16,
                                  ),
                                  label: Text(isEn ? 'Conflict Log' : '冲突记录'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const SyncStatusCard(),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _openEmbeddedRoute(
                                    context,
                                    const LockSettingsScreen(),
                                  ),
                                  icon: const Icon(
                                    Icons.lock_outline,
                                    size: 15,
                                  ),
                                  label: Text(
                                    I18n.trForLocale('app_lock.title', locale),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _openEmbeddedRoute(
                                    context,
                                    const NotificationHistoryScreen(
                                      markReadOnOpen: true,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.notifications_none_outlined,
                                    size: 15,
                                  ),
                                  label: Text(
                                    isEn ? 'Notifications' : '通知历史',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );

                      if (!twoCol) {
                        return Column(
                          children: [
                            appearanceCard,
                            const SizedBox(height: DesktopWebTokens.spaceLg),
                            syncCard,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: appearanceCard),
                          const SizedBox(width: DesktopWebTokens.spaceLg),
                          Expanded(child: syncCard),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: DesktopWebTokens.spaceXl),
                  Text(
                    isEn
                        ? 'Settings, Data & Extensions'
                        : '设置、数据与扩展入口',
                    style: t.sectionHeaderStyle,
                  ),
                  const SizedBox(height: DesktopWebTokens.spaceMd),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth >= 820 ? 2 : 1;
                      final rowCount =
                          (actionCards.length + cols - 1) ~/ cols;
                      return Column(
                        children: [
                          for (var row = 0; row < rowCount; row++)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: row == rowCount - 1
                                    ? 0
                                    : DesktopWebTokens.spaceMd,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var col = 0; col < cols; col++) ...[
                                    if (col > 0)
                                      const SizedBox(
                                        width: DesktopWebTokens.spaceMd,
                                      ),
                                    Expanded(
                                      child: (row * cols + col) <
                                              actionCards.length
                                          ? _SettingsQuickCard(
                                              data: actionCards[row * cols +
                                                  col],
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: DesktopWebTokens.spaceXl),
                  Center(
                    child: Text(
                      '${isEn ? 'Duoyi Web' : '多仪桌面工作区'} · ${AppVersion.display}',
                      style: t.captionStyle.copyWith(color: t.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AccountStatPill extends StatelessWidget {
  final String label;
  final String value;

  const _AccountStatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = DesktopWebTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.mutedSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
        border: Border.all(
          color: t.hairlineBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: t.cardTitleStyle.copyWith(
              fontSize: 15,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: t.captionStyle.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SettingsQuickCardData {
  final Key? key;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  const _SettingsQuickCardData({
    this.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });
}

class _SettingsQuickCard extends StatelessWidget {
  final _SettingsQuickCardData data;

  const _SettingsQuickCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final t = DesktopWebTokens.of(context);
    return DesktopPanelCard(
      key: data.key,
      padding: const EdgeInsets.all(16),
      onTap: data.onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: t.isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
            ),
            child: Icon(data.icon, size: 20, color: data.color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.cardTitleStyle.copyWith(fontSize: 14.5),
                ),
                const SizedBox(height: 3),
                Text(
                  data.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.captionStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: data.onTap,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              side: BorderSide(
                color: t.hairlineBorder,
                width: DesktopWebTokens.hairlineWidth,
              ),
            ),
            child: Text(data.actionLabel),
          ),
        ],
      ),
    );
  }
}

String _firstNonEmpty(List<String?> values) {
  for (final v in values) {
    final trimmed = v?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return '';
}
