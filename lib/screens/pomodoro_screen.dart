import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/pomodoro.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/pomodoro_timer_ring.dart';
import '../widgets/pomodoro_session_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _typeColor(PomodoroType t) {
    switch (t) {
      case PomodoroType.focus:
        return const Color(0xFFE53935);
      case PomodoroType.shortBreak:
        return const Color(0xFF4CAF50);
      case PomodoroType.longBreak:
        return const Color(0xFF2196F3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PomodoroProvider>().state;
    final provider = context.read<PomodoroProvider>();
    final s = context.watch<ThemeProvider>().brand.strings;
    final color = _typeColor(state.type);

    String typeLabel(PomodoroType t) {
      switch (t) {
        case PomodoroType.focus:
          return s.focusStateFocus;
        case PomodoroType.shortBreak:
          return s.focusStateShortBreak;
        case PomodoroType.longBreak:
          return s.focusStateLongBreak;
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s.focusTitle),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: s.focusTabTimer),
            Tab(text: s.focusTabHistory),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            children: [
              AppSurfaceCard(
                padding: const EdgeInsets.all(18),
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.14),
                    Theme.of(context).colorScheme.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.timer_outlined,
                            color: color,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                typeLabel(state.type),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${state.completedSessions} ${s.focusCompletedSuffix}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.68),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            state.isRunning ? '进行中' : '已暂停',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: PomodoroTimerRing(
                        progress: state.progress,
                        timeText: _formatTime(state.remainingSeconds),
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        '${s.focusTabTimer} · ${state.completedSessions} ${s.focusCompletedSuffix}',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.64),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (state.taskName != null && state.taskName!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Center(
                          child: GestureDetector(
                            onTap: () => _editTaskName(
                              context,
                              provider,
                              state.taskName!,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width - 96,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.assignment_outlined,
                                      size: 14,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.64),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        state.taskName!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.72),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppSurfaceCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSectionHeader(
                      title: '专注设置',
                      subtitle: '时长预设、白噪音和控制',
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [25, 45, 60]
                          .map(
                            (min) => ChoiceChip(
                              label: Text('$min 分钟'),
                              selected:
                                  state.totalSeconds == min * 60 &&
                                  state.type == PomodoroType.focus,
                              onSelected: (_) => provider.setConfig(
                                provider.config..focusDuration = min * 60,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    AppActionTile(
                      icon: _soundIcon(state.whiteNoiseSound),
                      label: '白噪音',
                      subtitle: _soundLabel(state.whiteNoiseSound, s),
                      color: state.whiteNoiseSound != 'none'
                          ? color
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      onTap: () => _showSoundPicker(
                        context,
                        provider,
                        state.whiteNoiseSound,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filled(
                          onPressed: provider.resetTimer,
                          icon: const Icon(Icons.refresh),
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: 68,
                          height: 68,
                          child: FloatingActionButton(
                            onPressed: provider.toggleTimer,
                            backgroundColor: color,
                            child: Icon(
                              state.isRunning ? Icons.pause : Icons.play_arrow,
                              size: 34,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        IconButton.filled(
                          onPressed: provider.skipSession,
                          icon: const Icon(Icons.skip_next),
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // History tab
          _HistoryTab(),
        ],
      ),
    );
  }

  void _editTaskName(
    BuildContext context,
    PomodoroProvider provider,
    String current,
  ) {
    final s = context.read<ThemeProvider>().brand.strings;
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(s.focusTaskLinkLabel),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '输入名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              provider.setTaskName(null);
              Navigator.pop(ctx);
            },
            child: const Text('清除'),
          ),
          FilledButton(
            onPressed: () {
              provider.setTaskName(ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _soundLabel(String sound, var s) {
    switch (sound) {
      case 'rain':
        return '雨声';
      case 'forest':
        return '森林';
      case 'cafe':
        return '咖啡馆';
      case 'waves':
        return '海浪';
      default:
        return '无白噪音';
    }
  }

  IconData _soundIcon(String sound) {
    switch (sound) {
      case 'rain':
        return Icons.water_drop;
      case 'forest':
        return Icons.park;
      case 'cafe':
        return Icons.local_cafe;
      case 'waves':
        return Icons.waves;
      default:
        return Icons.music_off;
    }
  }

  void _showSoundPicker(
    BuildContext context,
    PomodoroProvider provider,
    String currentSound,
  ) {
    final sounds = [
      {'id': 'none', 'label': '无白噪音', 'icon': Icons.music_off},
      {'id': 'rain', 'label': '绵绵细雨', 'icon': Icons.water_drop},
      {'id': 'forest', 'label': '宁静森林', 'icon': Icons.park},
      {'id': 'cafe', 'label': '午后咖啡馆', 'icon': Icons.local_cafe},
      {'id': 'waves', 'label': '海浪拍岸', 'icon': Icons.waves},
    ];

    showAppModalSheet(
      context: context,
      builder: (ctx) => AppPickerSheet<String>(
        title: '选择白噪音',
        subtitle: '专注时可切换环境音',
        selectedValue: currentSound,
        options: sounds
            .map(
              (s) => AppPickerOption<String>(
                value: s['id'] as String,
                title: s['label'] as String,
                icon: s['icon'] as IconData,
              ),
            )
            .toList(),
        onSelected: provider.setWhiteNoiseSound,
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PomodoroProvider>();
    final s = context.watch<ThemeProvider>().brand.strings;
    final sessions =
        provider.sessions.where((s) => s.type == PomodoroType.focus).toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));

    if (sessions.isEmpty) {
      return EmptyState(icon: Icons.history, message: s.focusEmpty);
    }

    // Weekly chart data - last 7 days
    final now = DateTime.now();
    final chartData = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final start = DateTime(d.year, d.month, d.day);
      final end = start.add(const Duration(days: 1));
      return provider.sessions
              .where(
                (s) =>
                    s.type == PomodoroType.focus &&
                    s.startTime.isAfter(start) &&
                    s.startTime.isBefore(end),
              )
              .fold(0, (sum, s) => sum + s.durationSeconds) ~/
          60;
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        AppSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionHeader(
                title: '最近 7 天',
                subtitle: '按专注分钟统计',
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: '今日',
                      value: '${provider.sessionCountToday} 次',
                      icon: Icons.today_outlined,
                      color: const Color(0xFFE53935),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MiniStat(
                      label: '本周',
                      value: '${chartData.reduce((a, b) => a + b)} 分钟',
                      icon: Icons.view_week_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MiniStat(
                      label: '总计',
                      value: '${provider.totalFocusMinutes} 分钟',
                      icon: Icons.schedule,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: (chartData.reduce((a, b) => a > b ? a : b) + 10)
                          .toDouble(),
                      barGroups: List.generate(
                        7,
                        (i) => BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: chartData[i].toDouble(),
                              color: const Color(0xFFE53935),
                              width: 22,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (v, _) => Text(
                              '${v.toInt()}m',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) {
                              final labels = [
                                '一',
                                '二',
                                '三',
                                '四',
                                '五',
                                '六',
                                '日',
                              ];
                              final idx =
                                  (now.weekday - (6 - v.toInt()) + 7) % 7;
                              return Text(
                                labels[idx],
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppSectionHeader(
          title: '会话记录',
          subtitle: '${sessions.length} 次专注',
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        ),
        // Group sessions by date
        ..._groupedSessions(sessions).entries.map(
          (e) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  e.key,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ),
              ...e.value.map((s) => PomodoroSessionCard(session: s)),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, List<PomodoroSession>> _groupedSessions(
    List<PomodoroSession> sessions,
  ) {
    final map = <String, List<PomodoroSession>>{};
    for (final s in sessions) {
      final key =
          '${s.startTime.year}-${s.startTime.month}月${s.startTime.day}日';
      map.putIfAbsent(key, () => []).add(s);
    }
    return map;
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: cs.onSurface,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.62),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
