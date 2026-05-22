import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/notification_history_policy.dart';
import '../core/report_reminder_config.dart';
import '../services/alarm_service.dart';
import '../providers/notification_service.dart';
import '../services/notification_permission_exception.dart';
import '../services/notification_settings.dart';
import '../services/permission_health_service.dart';
import '../services/reminder_ringtone_settings.dart';
import '../providers/preferences_provider.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/notification_health_card.dart';
import '../widgets/surface_components.dart';

enum PreferencesInitialSection { notifications }

/// 偏好设置页。纯本地的用户习惯，与服务器/管理员配置无关。
class PreferencesScreen extends StatefulWidget {
  final PreferencesInitialSection? initialSection;

  const PreferencesScreen({super.key, this.initialSection});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _notificationSectionKey = GlobalKey();

  static const _dateFormats = [
    ['yyyy-MM-dd', '2026-05-07'],
    ['MM/dd/yyyy', '05/07/2026'],
    ['dd/MM/yyyy', '07/05/2026'],
    ['yyyy年M月d日', '2026年5月7日'],
  ];
  static const _timeZones = [
    ['system', '跟随手机'],
    ['Asia/Shanghai', '中国标准时间'],
    ['America/Mexico_City', '墨西哥城时间'],
    ['America/Tijuana', '蒂华纳时间'],
    ['Asia/Tokyo', '日本时间'],
    ['Asia/Hong_Kong', '香港时间'],
    ['Asia/Singapore', '新加坡时间'],
    ['America/New_York', '纽约时间'],
    ['America/Los_Angeles', '洛杉矶时间'],
    ['Europe/London', '伦敦时间'],
    ['Europe/Paris', '巴黎时间'],
    ['Australia/Sydney', '悉尼时间'],
  ];
  static const _notificationHistoryLimitOptions =
      NotificationHistoryPolicy.options;

  @override
  void initState() {
    super.initState();
    if (widget.initialSection == PreferencesInitialSection.notifications) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToInitialSection();
      });
    }
  }

  @override
  void didUpdateWidget(covariant PreferencesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection &&
        widget.initialSection == PreferencesInitialSection.notifications) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToInitialSection();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToInitialSection() {
    final target = _notificationSectionKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PreferencesProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(I18n.tr('preferences.title'))),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          AppSurfaceCard(
            padding: const EdgeInsets.all(16),
            gradient: LinearGradient(
              colors: [cs.primary.withValues(alpha: 0.12), cs.surface],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.tune, color: cs.primary, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        I18n.tr('preferences.local.title'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w400,
                              color: cs.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        I18n.tr('preferences.local.subtitle'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.66),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSettingsSection(
            title: I18n.tr('preferences.section.date'),
            subtitle: I18n.tr('preferences.section.date.subtitle'),
            children: [
              AppSettingsTile(
                icon: Icons.calendar_view_week_outlined,
                color: cs.primary,
                title: I18n.tr('preferences.first_day.title'),
                subtitle: p.firstDayOfWeek == 1
                    ? I18n.tr('preferences.first_day.current_monday')
                    : I18n.tr('preferences.first_day.current_sunday'),
                trailing: _compactDropdown<int>(
                  value: p.firstDayOfWeek,
                  items: [
                    DropdownMenuItem(
                      value: 1,
                      child: Text(I18n.tr('weekday.mon')),
                    ),
                    DropdownMenuItem(
                      value: 7,
                      child: Text(I18n.tr('weekday.sun')),
                    ),
                  ],
                  onChanged: (v) => v == null
                      ? null
                      : context.read<PreferencesProvider>().setFirstDayOfWeek(
                          v,
                        ),
                ),
              ),
              AppSettingsTile(
                icon: Icons.date_range_outlined,
                color: Colors.teal,
                title: I18n.tr('preferences.date_format.title'),
                subtitle: _dateFormats.firstWhere(
                  (f) => f[0] == p.dateFormat,
                  orElse: () => _dateFormats.first,
                )[1],
                trailing: _compactDropdown<String>(
                  width: 138,
                  value: p.dateFormat,
                  items: [
                    for (final f in _dateFormats)
                      DropdownMenuItem(
                        value: f[0],
                        child: Text(f[1], style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                  onChanged: (v) => v == null
                      ? null
                      : context.read<PreferencesProvider>().setDateFormat(v),
                ),
              ),
              AppSettingsTile(
                icon: Icons.public_outlined,
                color: Colors.deepOrange,
                title: I18n.tr('preferences.timezone.title'),
                subtitle: p.followSystemTimeZone
                    ? '${I18n.tr('preferences.timezone.follow_system')}：${p.appTimeZone}'
                    : p.appTimeZone,
                trailing: _compactDropdown<String>(
                  width: 156,
                  value: p.appTimeZoneSelection,
                  items: [
                    for (final z in _timeZones)
                      DropdownMenuItem(
                        value: z[0],
                        child: Text(z[1], style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                  onChanged: (v) => v == null
                      ? null
                      : context.read<PreferencesProvider>().setAppTimeZone(v),
                ),
              ),
              AppSwitchTile(
                icon: Icons.brightness_2_outlined,
                color: Colors.indigo,
                value: p.showLunar,
                title: I18n.tr('preferences.lunar.title'),
                subtitle: I18n.tr('preferences.lunar.subtitle'),
                onChanged: (v) =>
                    context.read<PreferencesProvider>().setShowLunar(v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppSettingsSection(
            title: I18n.tr('preferences.section.defaults'),
            subtitle: I18n.tr('preferences.section.defaults.subtitle'),
            children: [
              AppSettingsTile(
                icon: Icons.open_in_new,
                color: Colors.blue,
                title: I18n.tr('preferences.default_tab.title'),
                subtitle: _tabLabel(p.defaultTab),
                trailing: _compactDropdown<int>(
                  value: p.defaultTab,
                  items: [
                    DropdownMenuItem(value: 0, child: Text(_tabLabel(0))),
                    DropdownMenuItem(value: 1, child: Text(_tabLabel(1))),
                    DropdownMenuItem(value: 2, child: Text(_tabLabel(2))),
                    DropdownMenuItem(value: 3, child: Text(_tabLabel(3))),
                    DropdownMenuItem(value: 4, child: Text(_tabLabel(4))),
                    DropdownMenuItem(value: 5, child: Text(_tabLabel(5))),
                    DropdownMenuItem(value: 6, child: Text(_tabLabel(6))),
                  ],
                  onChanged: (v) => v == null
                      ? null
                      : context.read<PreferencesProvider>().setDefaultTab(v),
                ),
              ),
              AppSwitchTile(
                icon: Icons.add_circle_outline,
                color: cs.primary,
                value: p.quickCaptureFab,
                title: I18n.tr('preferences.quick_capture.title'),
                subtitle: I18n.tr('preferences.quick_capture.subtitle'),
                onChanged: (v) =>
                    context.read<PreferencesProvider>().setQuickCaptureFab(v),
              ),
              AppSwitchTile(
                icon: Icons.notifications_active_outlined,
                color: Colors.deepOrange,
                value: p.notificationQuickAdd,
                title: I18n.tr('preferences.notification_quick_add.title'),
                subtitle: I18n.tr(
                  'preferences.notification_quick_add.subtitle',
                ),
                onChanged: (v) => context
                    .read<PreferencesProvider>()
                    .setNotificationQuickAdd(v),
              ),
              AppSwitchTile(
                icon: Icons.done_all,
                color: Colors.green,
                value: p.showCompletedTodos,
                title: I18n.tr('preferences.show_completed.title'),
                subtitle: I18n.tr('preferences.show_completed.subtitle'),
                onChanged: (v) => context
                    .read<PreferencesProvider>()
                    .setShowCompletedTodos(v),
              ),
              _SliderSetting(
                icon: Icons.timer_outlined,
                color: Colors.red,
                title: I18n.tr('preferences.pomodoro_length.title'),
                subtitle:
                    '${p.defaultPomodoroMinutes} ${I18n.tr('unit.minute')}',
                value: p.defaultPomodoroMinutes.toDouble(),
                min: 5,
                max: 90,
                divisions: 17,
                label: '${p.defaultPomodoroMinutes} ${I18n.tr('unit.min')}',
                onChanged: (v) => context
                    .read<PreferencesProvider>()
                    .setDefaultPomodoroMinutes(v.toInt()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppSettingsSection(
            title: I18n.tr('preferences.section.bottom_nav'),
            subtitle: I18n.tr('preferences.section.bottom_nav.subtitle'),
            children: [
              for (final tab in p.bottomNavOrder)
                _NavConfigTile(
                  tab: tab,
                  label: _tabLabel(tab),
                  visible: p.bottomNavVisible.contains(tab),
                  canMoveUp: p.bottomNavOrder.indexOf(tab) > 0,
                  canMoveDown:
                      p.bottomNavOrder.indexOf(tab) <
                      p.bottomNavOrder.length - 1,
                ),
            ],
          ),
          const SizedBox(height: 12),
          AppSettingsSection(
            title: I18n.tr('preferences.section.interaction'),
            subtitle: I18n.tr('preferences.section.interaction.subtitle'),
            children: [
              AppSwitchTile(
                icon: Icons.vibration,
                color: Colors.purple,
                value: p.haptic,
                title: I18n.tr('preferences.haptic.title'),
                subtitle: I18n.tr('preferences.haptic.subtitle'),
                onChanged: (v) =>
                    context.read<PreferencesProvider>().setHaptic(v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppSettingsSection(
            title: I18n.tr('preferences.section.auto_archive'),
            subtitle: I18n.tr('preferences.section.auto_archive.subtitle'),
            children: [
              _SliderSetting(
                icon: Icons.inventory_2_outlined,
                color: Colors.brown,
                title: I18n.tr('preferences.auto_archive.title'),
                subtitle: p.autoArchiveCompletedDays == 0
                    ? I18n.tr('preferences.auto_archive.never')
                    : '${p.autoArchiveCompletedDays} ${I18n.tr('preferences.auto_archive.after_days')}',
                value: p.autoArchiveCompletedDays.toDouble(),
                min: 0,
                max: 30,
                divisions: 30,
                label: p.autoArchiveCompletedDays == 0
                    ? I18n.tr('action.off')
                    : '${p.autoArchiveCompletedDays} ${I18n.tr('unit.day')}',
                onChanged: (v) => context
                    .read<PreferencesProvider>()
                    .setAutoArchiveCompletedDays(v.toInt()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: _notificationSectionKey,
            child: AppSettingsSection(
              title: '提醒偏好 / 通知设置',
              subtitle: '管理每日提醒、通知权限、通知记录保留和提醒铃声',
              children: [
                AppSettingsTile(
                  icon: Icons.history_outlined,
                  color: Colors.blueGrey,
                  title: '通知记录保留',
                  subtitle:
                      '最多保留 ${p.notificationHistoryLimit} 条历史，调低后会自动裁剪旧记录',
                  trailing: AppCompactDropdown<int>(
                    value: p.notificationHistoryLimit,
                    width: 116,
                    items: [
                      for (final value in _notificationHistoryLimitOptions)
                        DropdownMenuItem(value: value, child: Text('$value 条')),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      final prefs = context.read<PreferencesProvider>();
                      final notif = context.read<NotificationService>();
                      await prefs.setNotificationHistoryLimit(value);
                      await notif.setHistoryLimit(
                        prefs.notificationHistoryLimit,
                      );
                    },
                  ),
                ),
                for (var i = 0; i < p.dailyReminderSlots.length; i++)
                  _DailyReminderSlotTile(
                    index: i,
                    slot: p.dailyReminderSlots[i],
                    repeatLabel: _repeatDaysLabel(
                      p.dailyReminderSlots[i].repeatDays,
                    ),
                    weekdayLabel: _weekdayLabel,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _ReportReminderSection(),
          const SizedBox(height: 12),
          Consumer<NotificationService>(
            builder: (context, notif, child) =>
                _NotificationHealthSection(notificationService: notif),
          ),
          const SizedBox(height: 12),
          const _ReminderRingtoneSection(),
        ],
      ),
    );
  }

  Widget _compactDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    double width = 92,
  }) {
    return AppCompactDropdown<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      width: width,
    );
  }

  String _tabLabel(int index) {
    switch (index) {
      case 0:
        return I18n.tr('nav.today');
      case 1:
        return I18n.tr('nav.todo');
      case 2:
        return I18n.tr('nav.habit');
      case 3:
        return I18n.tr('nav.calendar');
      case 4:
        return I18n.tr('nav.focus');
      case 5:
        return I18n.tr('nav.widget');
      case 6:
        return I18n.tr('nav.mine');
      default:
        return I18n.tr('nav.today');
    }
  }

  String _repeatDaysLabel(List<int> days) {
    if (days.length == 7) return I18n.tr('repeat.every_day');
    if (days.length == 5 && days.every((d) => d >= 1 && d <= 5)) {
      return I18n.tr('repeat.weekdays');
    }
    return days.map(_weekdayLabel).join('/');
  }

  String _weekdayLabel(int day) {
    const keys = [
      'weekday.mon',
      'weekday.tue',
      'weekday.wed',
      'weekday.thu',
      'weekday.fri',
      'weekday.sat',
      'weekday.sun',
    ];
    if (day < 1 || day > 7) return I18n.tr('weekday.unknown');
    return I18n.tr(keys[day - 1]);
  }
}

class _ReportReminderSection extends StatelessWidget {
  const _ReportReminderSection();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    return AppSettingsSection(
      title: '报告推送',
      subtitle: '按你的节奏提醒查看每日复盘、周报、月报和年报，点击通知直达统计报表',
      children: [
        _ReportReminderTile(
          title: '每日效率复盘',
          icon: Icons.today_outlined,
          color: Colors.blue,
          config: prefs.dailyReportReminderConfig,
          cadence: _ReportReminderCadence.daily,
        ),
        _ReportReminderTile(
          title: '每周效率周报',
          icon: Icons.summarize_outlined,
          color: Colors.indigo,
          config: prefs.weeklyReportReminderConfig,
          cadence: _ReportReminderCadence.weekly,
        ),
        _ReportReminderTile(
          title: '每月成长月报',
          icon: Icons.calendar_month_outlined,
          color: Colors.teal,
          config: prefs.monthlyReportReminderConfig,
          cadence: _ReportReminderCadence.monthly,
        ),
        _ReportReminderTile(
          title: '每年成长年报',
          icon: Icons.event_available_outlined,
          color: Colors.deepOrange,
          config: prefs.yearlyReportReminderConfig,
          cadence: _ReportReminderCadence.yearly,
        ),
      ],
    );
  }
}

enum _ReportReminderCadence { daily, weekly, monthly, yearly }

class _ReportReminderTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final ReportReminderConfig config;
  final _ReportReminderCadence cadence;

  const _ReportReminderTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.config,
    required this.cadence,
  });

  String get _time =>
      I18nDateFormat.timeOfDay(hour: config.hour, minute: config.minute);

  String get _subtitle {
    final cadenceText = switch (cadence) {
      _ReportReminderCadence.daily => '每天',
      _ReportReminderCadence.weekly => '每${_weekdayLabel(config.weekday)}',
      _ReportReminderCadence.monthly => '每月 ${config.monthDay} 日',
      _ReportReminderCadence.yearly =>
        '每年 ${config.month} 月 ${config.monthDay} 日',
    };
    final state = config.enabled ? '动态摘要' : '已关闭';
    return '$state · $cadenceText $_time';
  }

  Future<void> _save(BuildContext context, ReportReminderConfig next) {
    final prefs = context.read<PreferencesProvider>();
    return switch (cadence) {
      _ReportReminderCadence.daily => prefs.setDailyReportReminderConfig(next),
      _ReportReminderCadence.weekly => prefs.setWeeklyReportReminderConfig(
        next,
      ),
      _ReportReminderCadence.monthly => prefs.setMonthlyReportReminderConfig(
        next,
      ),
      _ReportReminderCadence.yearly => prefs.setYearlyReportReminderConfig(
        next,
      ),
    };
  }

  String get _timeSubtitle {
    return switch (cadence) {
      _ReportReminderCadence.daily => '到点推送今天报告动态摘要',
      _ReportReminderCadence.weekly => '到点推送上一周报告动态摘要',
      _ReportReminderCadence.monthly => '到点推送上月报告动态摘要',
      _ReportReminderCadence.yearly => '到点推送上一年报告动态摘要',
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(_subtitle),
        trailing: Switch(
          value: config.enabled,
          onChanged: (v) => _save(context, config.copyWith(enabled: v)),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          AppSettingsTile(
            icon: Icons.schedule,
            color: color,
            title: '推送时间',
            subtitle: _timeSubtitle,
            trailing: TextButton(
              onPressed: () async {
                final picked = await AppTimePicker.show(
                  context,
                  initialTime: TimeOfDay(
                    hour: config.hour,
                    minute: config.minute,
                  ),
                  title: '$title推送时间',
                  subtitle: '修改后会立即重排下一次报告通知',
                );
                if (picked == null || !context.mounted) return;
                await _save(
                  context,
                  config.copyWith(hour: picked.hour, minute: picked.minute),
                );
              },
              child: Text(_time),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _cadenceChips(context),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _cadenceChips(BuildContext context) {
    return switch (cadence) {
      _ReportReminderCadence.daily => const <Widget>[],
      _ReportReminderCadence.weekly => [
        for (var day = 1; day <= 7; day++)
          FilterChip(
            label: Text(_weekdayLabel(day)),
            selected: config.weekday == day,
            showCheckmark: false,
            onSelected: (_) => _save(context, config.copyWith(weekday: day)),
          ),
      ],
      _ReportReminderCadence.monthly => _monthDayChips(context),
      _ReportReminderCadence.yearly => [
        for (var month = 1; month <= 12; month++)
          FilterChip(
            label: Text('$month 月'),
            selected: config.month == month,
            showCheckmark: false,
            onSelected: (_) => _save(context, config.copyWith(month: month)),
          ),
        for (final day in const [1, 5, 10, 15, 20, 25, 28, 31])
          FilterChip(
            label: Text('$day 日'),
            selected: config.monthDay == day,
            showCheckmark: false,
            onSelected: (_) => _save(context, config.copyWith(monthDay: day)),
          ),
      ],
    };
  }

  List<Widget> _monthDayChips(BuildContext context) {
    return [
      for (final day in const [1, 5, 10, 15, 20, 25, 28, 31])
        FilterChip(
          label: Text('$day 日'),
          selected: config.monthDay == day,
          showCheckmark: false,
          onSelected: (_) => _save(context, config.copyWith(monthDay: day)),
        ),
    ];
  }

  static String _weekdayLabel(int day) {
    const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (day < 1 || day > 7) return '周一';
    return labels[day - 1];
  }
}

class _NotificationHealthSection extends StatefulWidget {
  final NotificationService notificationService;

  const _NotificationHealthSection({required this.notificationService});

  @override
  State<_NotificationHealthSection> createState() =>
      _NotificationHealthSectionState();
}

class _NotificationHealthSectionState extends State<_NotificationHealthSection>
    with WidgetsBindingObserver {
  Future<_NotificationHealthSnapshot>? _future;
  int? _pendingCountOverride;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _NotificationHealthSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notificationService != widget.notificationService) {
      _future = _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<_NotificationHealthSnapshot> _load() async {
    await widget.notificationService.refreshPermission();
    final report = await PermissionHealthService.instance.check();
    final pushPending = await widget.notificationService.pendingIds();
    final alarmPending = await AlarmService.instance.pendingIds();
    DateTime? lastTestAt;
    for (final item in widget.notificationService.history) {
      if (item.type == NotificationType.general &&
          (item.title == '测试通知' || item.title == '定时测试通知')) {
        lastTestAt = item.scheduledTime;
        break;
      }
    }
    return _NotificationHealthSnapshot(
      report: report,
      pendingCount: pushPending.length + alarmPending.length,
      lastTestAt: lastTestAt,
    );
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _pendingCountOverride = null;
      _future = _load();
    });
  }

  Future<void> _requestNotificationPermission() async {
    final granted = await widget.notificationService.requestPermission();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.tr('preferences.notify.permission_denied')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    await _refresh();
  }

  Future<void> _requestExactAlarmPermission() async {
    final granted = await AlarmService.instance.requestExactAlarmPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? I18n.tr('preferences.notify.exact_alarm_granted')
              : I18n.tr('preferences.notify.exact_alarm_denied'),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _refresh();
  }

  Future<void> _requestFullScreenIntentPermission() async {
    final granted = await AlarmService.instance
        .requestFullScreenIntentPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? I18n.tr('preferences.notify.full_screen_granted')
              : I18n.tr('preferences.notify.full_screen_denied'),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _refresh();
  }

  Future<void> _sendTest() async {
    try {
      await widget.notificationService.sendTest();
    } on NotificationPermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.tr('preferences.notify.test_permission_denied')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refresh();
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${I18n.tr('preferences.notify.test_failed')}$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refresh();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(I18n.tr('preferences.notify.test_sent')),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _refresh();
  }

  Future<void> _clearPending() async {
    await widget.notificationService.cancelAll();
    await AlarmService.instance.cancelAll();
    if (!mounted) return;
    setState(() {
      _pendingCountOverride = 0;
      _future = _load();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(I18n.tr('preferences.notify.pending_cleared')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_NotificationHealthSnapshot>(
      future: _future,
      builder: (context, snap) {
        final snapshot = snap.data;
        return NotificationHealthCard(
          loading:
              snap.connectionState == ConnectionState.waiting &&
              snapshot == null,
          errorText: snap.hasError ? '${snap.error}' : null,
          report: snapshot?.report,
          pendingCount: snap.connectionState == ConnectionState.waiting
              ? (_pendingCountOverride ?? snapshot?.pendingCount)
              : snapshot?.pendingCount,
          lastTestAt: snapshot?.lastTestAt,
          onRefresh: _refresh,
          onOpenSystemSettings: () => _openAppSettings(context),
          onSendTest: _sendTest,
          onClearPending: _clearPending,
          onRequestNotificationPermission: _requestNotificationPermission,
          onRequestExactAlarmPermission: _requestExactAlarmPermission,
          onRequestFullScreenIntentPermission:
              _requestFullScreenIntentPermission,
        );
      },
    );
  }
}

class _ReminderRingtoneSection extends StatefulWidget {
  const _ReminderRingtoneSection();

  @override
  State<_ReminderRingtoneSection> createState() =>
      _ReminderRingtoneSectionState();
}

class _ReminderRingtoneSectionState extends State<_ReminderRingtoneSection> {
  int _volume = ReminderRingtoneSettings.defaultVolumePercent;
  String _sound = ReminderRingtoneSettings.defaultSound;
  final ReminderRingtonePlatformPolicy _policy =
      ReminderRingtoneSettings.platformPolicy;

  @override
  void initState() {
    super.initState();
    if (!_policy.supportsBuiltInSoundPicker) return;
    ReminderRingtoneSettings.loadVolumePercent().then((value) {
      if (mounted) setState(() => _volume = value);
    });
    ReminderRingtoneSettings.loadSound().then((value) {
      if (mounted) setState(() => _sound = value);
    });
  }

  Future<void> _setVolume(int value) async {
    setState(() => _volume = value);
    await ReminderRingtoneSettings.setVolumePercent(value);
  }

  Future<void> _setSound(String value) async {
    setState(() => _sound = value);
    await ReminderRingtoneSettings.setSound(value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_policy.supportsBuiltInSoundPicker) {
      return AppSettingsSection(
        title: I18n.tr('preferences.ringtone.section'),
        subtitle: I18n.tr(_policy.sectionSubtitleKey),
        children: [
          AppSettingsTile(
            icon: Icons.notifications_active_outlined,
            color: Colors.orange,
            title: I18n.tr(_policy.tileTitleKey),
            subtitle: I18n.tr(_policy.tileSubtitleKey),
            trailing: const SizedBox.shrink(),
          ),
        ],
      );
    }

    return AppSettingsSection(
      title: I18n.tr('preferences.ringtone.section'),
      subtitle: I18n.tr(_policy.sectionSubtitleKey),
      children: [
        AppSettingsTile(
          icon: Icons.notifications_active_outlined,
          color: Colors.orange,
          title: I18n.tr('preferences.ringtone.sound'),
          subtitle: ReminderRingtoneSettings.sounds
              .firstWhere((s) => s.id == _sound)
              .label,
          trailing: AppCompactDropdown<String>(
            value: _sound,
            width: 112,
            items: [
              for (final sound in ReminderRingtoneSettings.sounds)
                DropdownMenuItem(value: sound.id, child: Text(sound.label)),
            ],
            onChanged: (value) => value == null ? null : _setSound(value),
          ),
        ),
        if (_policy.supportsVolumePresets)
          AppSettingsTile(
            icon: Icons.volume_up_outlined,
            color: Colors.deepOrange,
            title: I18n.tr('preferences.ringtone.volume'),
            subtitle: '${I18n.tr('preferences.ringtone.current')} $_volume%',
            trailing: Wrap(
              spacing: 6,
              children: [
                for (final value in ReminderRingtoneSettings.presets)
                  ChoiceChip(
                    label: Text('$value%'),
                    selected: _volume == value,
                    onSelected: (_) => _setVolume(value),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DailyReminderSlotTile extends StatelessWidget {
  final int index;
  final DailyReminderSlot slot;
  final String repeatLabel;
  final String Function(int day) weekdayLabel;

  const _DailyReminderSlotTile({
    required this.index,
    required this.slot,
    required this.repeatLabel,
    required this.weekdayLabel,
  });

  String get _title => I18n.tr(
    [
      'preferences.daily_reminder.one',
      'preferences.daily_reminder.two',
      'preferences.daily_reminder.three',
    ][index],
  );
  String get _time =>
      I18nDateFormat.timeOfDay(hour: slot.hour, minute: slot.minute);

  Future<void> _save(BuildContext context, DailyReminderSlot next) {
    return context.read<PreferencesProvider>().setDailyReminderSlot(
      index,
      next,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: ExpansionTile(
        initiallyExpanded: index == 0,
        leading: Icon(Icons.notifications_active_outlined, color: cs.primary),
        title: Text(_title),
        subtitle: Text(
          slot.enabled
              ? '$_time · $repeatLabel · ${_taskScopeText(slot)}'
              : '${I18n.tr('preferences.daily_reminder.disabled')} · $_time',
        ),
        trailing: Switch(
          value: slot.enabled,
          onChanged: (v) => _save(context, slot.copyWith(enabled: v)),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          AppSettingsTile(
            icon: Icons.schedule,
            color: Colors.deepOrange,
            title: I18n.tr('preferences.daily_reminder.time'),
            subtitle: I18n.tr('preferences.daily_reminder.time.subtitle'),
            trailing: TextButton(
              onPressed: () async {
                final picked = await AppTimePicker.show(
                  context,
                  initialTime: TimeOfDay(hour: slot.hour, minute: slot.minute),
                  title:
                      '$_title${I18n.tr('preferences.daily_reminder.time_suffix')}',
                  subtitle: I18n.tr(
                    'preferences.daily_reminder.time_picker.subtitle',
                  ),
                );
                if (picked == null || !context.mounted) return;
                await _save(
                  context,
                  slot.copyWith(hour: picked.hour, minute: picked.minute),
                );
              },
              child: Text(_time),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(7, (i) {
                final day = i + 1;
                final selected = slot.repeatDays.contains(day);
                return FilterChip(
                  label: Text(weekdayLabel(day)),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) {
                    final next = [...slot.repeatDays];
                    if (selected) {
                      next.remove(day);
                    } else {
                      next.add(day);
                    }
                    _save(context, slot.copyWith(repeatDays: next));
                  },
                );
              }),
            ),
          ),
          AppSwitchTile(
            icon: Icons.today_outlined,
            color: Colors.blue,
            value: slot.includeTodayTasks,
            title: I18n.tr('preferences.daily_reminder.today_tasks'),
            subtitle: I18n.tr(
              'preferences.daily_reminder.today_tasks.subtitle',
            ),
            onChanged: (v) =>
                _save(context, slot.copyWith(includeTodayTasks: v)),
          ),
          AppSwitchTile(
            icon: Icons.next_plan_outlined,
            color: Colors.teal,
            value: slot.includeTomorrowPlan,
            title: I18n.tr('preferences.daily_reminder.tomorrow_plan'),
            subtitle: I18n.tr(
              'preferences.daily_reminder.tomorrow_plan.subtitle',
            ),
            onChanged: (v) =>
                _save(context, slot.copyWith(includeTomorrowPlan: v)),
          ),
          AppSwitchTile(
            icon: Icons.warning_amber_outlined,
            color: Colors.red,
            value: slot.includeOverdue,
            title: I18n.tr('preferences.daily_reminder.overdue_tasks'),
            subtitle: I18n.tr(
              'preferences.daily_reminder.overdue_tasks.subtitle',
            ),
            onChanged: (v) => _save(context, slot.copyWith(includeOverdue: v)),
          ),
          AppSwitchTile(
            icon: Icons.beach_access_outlined,
            color: Colors.green,
            value: slot.pauseHolidays,
            title: I18n.tr('preferences.daily_reminder.pause_holidays'),
            subtitle: I18n.tr(
              'preferences.daily_reminder.pause_holidays.subtitle',
            ),
            onChanged: (v) => _save(context, slot.copyWith(pauseHolidays: v)),
          ),
        ],
      ),
    );
  }

  String _taskScopeText(DailyReminderSlot slot) {
    final parts = <String>[];
    if (slot.includeTodayTasks) {
      parts.add(I18n.tr('preferences.daily_reminder.scope.today'));
    }
    if (slot.includeOverdue) {
      parts.add(I18n.tr('preferences.daily_reminder.scope.overdue'));
    }
    if (slot.includeTomorrowPlan) {
      parts.add(I18n.tr('preferences.daily_reminder.scope.tomorrow'));
    }
    return parts.isEmpty
        ? I18n.tr('preferences.daily_reminder.scope.none')
        : parts.join('/');
  }
}

class _NavConfigTile extends StatelessWidget {
  final int tab;
  final String label;
  final bool visible;
  final bool canMoveUp;
  final bool canMoveDown;

  const _NavConfigTile({
    required this.tab,
    required this.label,
    required this.visible,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  IconData get _icon => switch (tab) {
    0 => Icons.today_outlined,
    1 => Icons.checklist,
    2 => Icons.repeat,
    3 => Icons.calendar_month_outlined,
    4 => Icons.timer_outlined,
    5 => Icons.widgets_outlined,
    _ => Icons.person_outline,
  };

  @override
  Widget build(BuildContext context) {
    final lockedVisible = tab == 5 || tab == 6;
    return AppSettingsTile(
      icon: _icon,
      color: Theme.of(context).colorScheme.primary,
      title: label,
      subtitle: lockedVisible
          ? I18n.tr('preferences.nav.fixed')
          : visible
          ? I18n.tr('preferences.nav.visible')
          : I18n.tr('preferences.nav.hidden'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: I18n.tr('action.move_up'),
            onPressed: canMoveUp
                ? () => context.read<PreferencesProvider>().moveBottomNavTab(
                    tab,
                    -1,
                  )
                : null,
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          IconButton(
            tooltip: I18n.tr('action.move_down'),
            onPressed: canMoveDown
                ? () => context.read<PreferencesProvider>().moveBottomNavTab(
                    tab,
                    1,
                  )
                : null,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          Switch(
            value: visible,
            onChanged: lockedVisible
                ? null
                : (v) => context
                      .read<PreferencesProvider>()
                      .setBottomNavVisible(tab, v),
          ),
        ],
      ),
    );
  }
}

class _NotificationHealthSnapshot {
  final NotificationHealthReport report;
  final int pendingCount;
  final DateTime? lastTestAt;

  const _NotificationHealthSnapshot({
    required this.report,
    required this.pendingCount,
    required this.lastTestAt,
  });
}

Future<void> _openAppSettings(BuildContext context) async {
  final opened =
      await NotificationSettings.openAppNotificationSettings() ||
      await NotificationSettings.openNotificationChannelSettings(
        AlarmService.channelId,
      ) ||
      await openAppSettings();
  if (!context.mounted) return;
  if (!opened) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(I18n.tr('preferences.notify.open_settings_failed')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  const _SliderSetting({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
