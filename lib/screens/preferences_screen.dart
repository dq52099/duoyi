import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/alarm_service.dart';
import '../providers/notification_service.dart';
import '../services/notification_permission_exception.dart';
import '../services/notification_settings.dart';
import '../services/permission_health_service.dart';
import '../providers/preferences_provider.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/notification_health_card.dart';
import '../widgets/surface_components.dart';

/// 偏好设置页。纯本地的用户习惯，与服务器/管理员配置无关。
class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PreferencesProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('偏好设置')),
      body: ListView(
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
                        '本地偏好',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w400,
                              color: cs.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '调整日期、默认入口、交互反馈和本机通知行为',
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
            title: '日期与日历',
            subtitle: '影响今日卡片、日历和日期展示',
            children: [
              AppSettingsTile(
                icon: Icons.calendar_view_week_outlined,
                color: cs.primary,
                title: '一周从哪一天开始',
                subtitle: p.firstDayOfWeek == 1 ? '当前为周一' : '当前为周日',
                trailing: _compactDropdown<int>(
                  value: p.firstDayOfWeek,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('周一')),
                    DropdownMenuItem(value: 7, child: Text('周日')),
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
                title: '日期格式',
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
                title: '应用时区',
                subtitle: p.followSystemTimeZone
                    ? '跟随手机：${p.appTimeZone}'
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
                title: '显示农历',
                subtitle: '影响日历月视图与今日卡',
                onChanged: (v) =>
                    context.read<PreferencesProvider>().setShowLunar(v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppSettingsSection(
            title: '默认行为',
            subtitle: '启动入口、快捷捕获和专注时长',
            children: [
              AppSettingsTile(
                icon: Icons.open_in_new,
                color: Colors.blue,
                title: '启动默认 Tab',
                subtitle: _tabLabel(p.defaultTab),
                trailing: _compactDropdown<int>(
                  value: p.defaultTab,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('今日')),
                    DropdownMenuItem(value: 1, child: Text('待办')),
                    DropdownMenuItem(value: 2, child: Text('习惯')),
                    DropdownMenuItem(value: 3, child: Text('日历')),
                    DropdownMenuItem(value: 4, child: Text('专注')),
                    DropdownMenuItem(value: 5, child: Text('小组件')),
                    DropdownMenuItem(value: 6, child: Text('我的')),
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
                title: '显示快速捕获按钮',
                subtitle: '今日页右下角的快捷创建按钮',
                onChanged: (v) =>
                    context.read<PreferencesProvider>().setQuickCaptureFab(v),
              ),
              AppSwitchTile(
                icon: Icons.done_all,
                color: Colors.green,
                value: p.showCompletedTodos,
                title: '待办页显示已完成',
                subtitle: '关闭后只看未完成和进行中的事项',
                onChanged: (v) => context
                    .read<PreferencesProvider>()
                    .setShowCompletedTodos(v),
              ),
              _SliderSetting(
                icon: Icons.timer_outlined,
                color: Colors.red,
                title: '默认番茄钟长度',
                subtitle: '${p.defaultPomodoroMinutes} 分钟',
                value: p.defaultPomodoroMinutes.toDouble(),
                min: 5,
                max: 90,
                divisions: 17,
                label: '${p.defaultPomodoroMinutes} 分',
                onChanged: (v) => context
                    .read<PreferencesProvider>()
                    .setDefaultPomodoroMinutes(v.toInt()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppSettingsSection(
            title: '底部导航栏',
            subtitle: '配置显示菜单和顺序，至少保留两个入口',
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
            title: '交互',
            subtitle: '触感反馈与完成动作',
            children: [
              AppSwitchTile(
                icon: Icons.vibration,
                color: Colors.purple,
                value: p.haptic,
                title: '震动反馈',
                subtitle: '完成/切换/解锁等操作',
                onChanged: (v) =>
                    context.read<PreferencesProvider>().setHaptic(v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppSettingsSection(
            title: '待办自动归档',
            subtitle: '减少已完成项目对列表的干扰',
            children: [
              _SliderSetting(
                icon: Icons.inventory_2_outlined,
                color: Colors.brown,
                title: '完成 N 天后隐藏',
                subtitle: p.autoArchiveCompletedDays == 0
                    ? '从不归档'
                    : '${p.autoArchiveCompletedDays} 天后自动隐藏',
                value: p.autoArchiveCompletedDays.toDouble(),
                min: 0,
                max: 30,
                divisions: 30,
                label: p.autoArchiveCompletedDays == 0
                    ? '关'
                    : '${p.autoArchiveCompletedDays} 天',
                onChanged: (v) => context
                    .read<PreferencesProvider>()
                    .setAutoArchiveCompletedDays(v.toInt()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppSettingsSection(
            title: '每日提醒',
            subtitle: '最多三组提醒：时间、任务范围、重复周期、节假日暂停',
            children: [
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
          const SizedBox(height: 12),
          Consumer<NotificationService>(
            builder: (context, notif, child) =>
                _NotificationHealthSection(notificationService: notif),
          ),
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
        return '今日';
      case 1:
        return '待办';
      case 2:
        return '习惯';
      case 3:
        return '日历';
      case 4:
        return '专注';
      case 5:
        return '小组件';
      case 6:
        return '我的';
      default:
        return '今日';
    }
  }

  String _repeatDaysLabel(List<int> days) {
    if (days.length == 7) return '每天';
    if (days.length == 5 && days.every((d) => d >= 1 && d <= 5)) {
      return '工作日';
    }
    return days.map(_weekdayLabel).join('/');
  }

  String _weekdayLabel(int day) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (day < 1 || day > 7) return '周?';
    return names[day - 1];
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
      _future = _load();
    });
  }

  Future<void> _requestNotificationPermission() async {
    final granted = await widget.notificationService.requestPermission();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('系统通知权限未授予'),
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
        content: Text(granted ? '精准闹钟权限已授权' : '精准闹钟权限未授予'),
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
        content: Text(granted ? '弹出屏幕权限已允许' : '弹出屏幕权限未允许'),
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
        const SnackBar(
          content: Text('系统通知权限未授权，无法发送响铃测试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refresh();
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('响铃测试发送失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refresh();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('响铃弹屏测试已发送'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _refresh();
  }

  Future<void> _clearPending() async {
    await widget.notificationService.cancelAll();
    await AlarmService.instance.cancelAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已取消全部待调度提醒'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _refresh();
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
          pendingCount: snapshot?.pendingCount,
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

  String get _title => '提醒${['一', '二', '三'][index]}';
  String get _time =>
      '${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}';

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
              : '已关闭 · $_time',
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
            title: '提醒时间',
            subtitle: '到点发送带声音和震动的提醒',
            trailing: TextButton(
              onPressed: () async {
                final picked = await AppTimePicker.show(
                  context,
                  initialTime: TimeOfDay(hour: slot.hour, minute: slot.minute),
                  title: '$_title时间',
                  subtitle: '设置提醒触发时间',
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
            title: '任务：今日任务',
            subtitle: '提醒中包含今日未完成任务数量',
            onChanged: (v) =>
                _save(context, slot.copyWith(includeTodayTasks: v)),
          ),
          AppSwitchTile(
            icon: Icons.next_plan_outlined,
            color: Colors.teal,
            value: slot.includeTomorrowPlan,
            title: '任务：明日计划',
            subtitle: '提醒中包含明日已安排任务数量',
            onChanged: (v) =>
                _save(context, slot.copyWith(includeTomorrowPlan: v)),
          ),
          AppSwitchTile(
            icon: Icons.warning_amber_outlined,
            color: Colors.red,
            value: slot.includeOverdue,
            title: '任务：逾期任务',
            subtitle: '提醒中包含已过期未完成任务',
            onChanged: (v) => _save(context, slot.copyWith(includeOverdue: v)),
          ),
          AppSwitchTile(
            icon: Icons.beach_access_outlined,
            color: Colors.green,
            value: slot.pauseHolidays,
            title: '法定节假日暂停提醒',
            subtitle: '遇到内置节假日时顺延到下一个提醒日',
            onChanged: (v) => _save(context, slot.copyWith(pauseHolidays: v)),
          ),
        ],
      ),
    );
  }

  String _taskScopeText(DailyReminderSlot slot) {
    final parts = <String>[];
    if (slot.includeTodayTasks) parts.add('今日');
    if (slot.includeOverdue) parts.add('逾期');
    if (slot.includeTomorrowPlan) parts.add('明日');
    return parts.isEmpty ? '无任务范围' : parts.join('/');
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
    return AppSettingsTile(
      icon: _icon,
      color: Theme.of(context).colorScheme.primary,
      title: label,
      subtitle: visible ? '已显示' : '已隐藏',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '上移',
            onPressed: canMoveUp
                ? () => context.read<PreferencesProvider>().moveBottomNavTab(
                    tab,
                    -1,
                  )
                : null,
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          IconButton(
            tooltip: '下移',
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
            onChanged: (v) =>
                context.read<PreferencesProvider>().setBottomNavVisible(tab, v),
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
      await NotificationSettings.openNotificationChannelSettings(
        AlarmService.channelId,
      ) ||
      await NotificationSettings.openAppNotificationSettings() ||
      await openAppSettings();
  if (!context.mounted) return;
  if (!opened) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('无法打开系统设置'),
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
