import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/alarm_service.dart';
import '../providers/notification_service.dart';
import '../services/permission_health_service.dart';
import '../providers/preferences_provider.dart';
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
                              fontWeight: FontWeight.w500,
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
                    DropdownMenuItem(value: 5, child: Text('我的')),
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
                subtitle: '今日 / 我的 页右下角的 + 按钮',
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
        return '我的';
      default:
        return '今日';
    }
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
    await widget.notificationService.sendTest();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('测试通知已发送'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _refresh();
  }

  Future<void> _sendScheduledTest() async {
    await widget.notificationService.sendScheduledTest();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已安排 1 分钟后的测试提醒'),
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
          onSendScheduledTest: _sendScheduledTest,
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
  final opened = await openAppSettings();
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
                        fontWeight: FontWeight.w500,
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
                    fontWeight: FontWeight.w500,
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
