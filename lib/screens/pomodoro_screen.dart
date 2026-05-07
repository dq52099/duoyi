import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/pomodoro.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/pomodoro_timer_ring.dart';
import '../widgets/pomodoro_session_card.dart';
import '../widgets/empty_state.dart';

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
          // Timer tab
          Column(
            children: [
              const Spacer(flex: 1),
              Text(
                typeLabel(state.type),
                style: TextStyle(
                  fontSize: 18,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              PomodoroTimerRing(
                progress: state.progress,
                timeText: _formatTime(state.remainingSeconds),
                color: color,
              ),
              const SizedBox(height: 8),
              Text(
                '${s.focusTabTimer} · ${state.completedSessions} ${s.focusCompletedSuffix}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              if (state.taskName != null && state.taskName!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.assignment,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () =>
                            _editTaskName(context, provider, state.taskName!),
                        child: Text(
                          state.taskName!,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              // Duration presets
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [25, 45, 60]
                    .map(
                      (min) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text('$min 分钟'),
                          selected:
                              state.totalSeconds == min * 60 &&
                              state.type == PomodoroType.focus,
                          onSelected: (_) => provider.setConfig(
                            provider.config..focusDuration = min * 60,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              // White noise selector
              ActionChip(
                label: Text(
                  _soundLabel(state.whiteNoiseSound, s),
                  style: TextStyle(
                    color: state.whiteNoiseSound != 'none'
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade600,
                  ),
                ),
                avatar: Icon(
                  _soundIcon(state.whiteNoiseSound),
                  size: 16,
                  color: state.whiteNoiseSound != 'none'
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade600,
                ),
                backgroundColor: state.whiteNoiseSound != 'none'
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: state.whiteNoiseSound != 'none'
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.3)
                        : Colors.grey.shade300,
                  ),
                ),
                onPressed: () =>
                    _showSoundPicker(context, provider, state.whiteNoiseSound),
              ),
              const SizedBox(height: 32),
              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    onPressed: provider.resetTimer,
                    icon: const Icon(Icons.refresh),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
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
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 1),
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
      builder: (ctx) => AlertDialog(
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

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  '选择白噪音',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              ...sounds.map((s) {
                final isSelected = s['id'] == currentSound;
                return ListTile(
                  leading: Icon(
                    s['icon'] as IconData,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  title: Text(
                    s['label'] as String,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    provider.setWhiteNoiseSound(s['id'] as String);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        ),
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
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _MiniStat(
                    label: '今日',
                    value: '${provider.sessionCountToday} 次',
                  ),
                  const SizedBox(width: 16),
                  _MiniStat(
                    label: '本周',
                    value: '${chartData.reduce((a, b) => a + b)} 分钟',
                  ),
                  const SizedBox(width: 16),
                  _MiniStat(
                    label: '总计',
                    value: '${provider.totalFocusMinutes} 分钟',
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
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
                        final labels = ['一', '二', '三', '四', '五', '六', '日'];
                        final idx = (now.weekday - (6 - v.toInt()) + 7) % 7;
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
        const Divider(),
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
                    color: Colors.grey.shade600,
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
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      ],
    );
  }
}
