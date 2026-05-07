import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../providers/goal_provider.dart';
import '../widgets/empty_state.dart';

class GoalScreen extends StatelessWidget {
  const GoalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GoalProvider>();
    final goals = provider.goals;

    return Scaffold(
      appBar: AppBar(title: const Text('目标管理')),
      body: goals.isEmpty
          ? EmptyState(
              icon: Icons.flag_outlined,
              message: '设立一个目标，让时间为你累积',
              actionLabel: '新建目标',
              onAction: () => _openEdit(context),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: goals.length,
              itemBuilder: (_, i) => _GoalCard(goal: goals[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(context),
        icon: const Icon(Icons.add),
        label: const Text('新目标'),
      ),
    );
  }

  void _openEdit(BuildContext context, {GoalItem? goal}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GoalEditScreen(goal: goal)),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final GoalItem goal;
  const _GoalCard({required this.goal});

  Color _statusColor() => switch (goal.status) {
        GoalStatus.active => const Color(0xFF66BB6A),
        GoalStatus.paused => Colors.grey,
        GoalStatus.achieved => const Color(0xFFFFA726),
        GoalStatus.abandoned => Colors.red.shade300,
      };

  String _statusText() => switch (goal.status) {
        GoalStatus.active => '进行中',
        GoalStatus.paused => '已暂停',
        GoalStatus.achieved => '已达成',
        GoalStatus.abandoned => '已放弃',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(goal.colorValue);
    final progress = goal.computedProgress;
    final days = goal.daysRemaining;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GoalEditScreen(goal: goal)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.flag, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (goal.description.isNotEmpty)
                          Text(
                            goal.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor().withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _statusText(),
                      style: TextStyle(
                        fontSize: 11,
                        color: _statusColor(),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: color.withValues(alpha: 0.1),
                        color: color,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 12, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '里程碑 ${goal.milestones.where((m) => m.isCompleted).length}/${goal.milestones.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (goal.targetDate != null) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.schedule,
                        size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      days >= 0 ? '还剩 $days 天' : '已超期 ${-days} 天',
                      style: TextStyle(
                        fontSize: 11,
                        color: days >= 0
                            ? Colors.grey.shade600
                            : Colors.red,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GoalEditScreen extends StatefulWidget {
  final GoalItem? goal;
  const GoalEditScreen({super.key, this.goal});

  @override
  State<GoalEditScreen> createState() => _GoalEditScreenState();
}

class _GoalEditScreenState extends State<GoalEditScreen> {
  late TextEditingController _title;
  late TextEditingController _desc;
  late TextEditingController _milestone;
  DateTime? _startDate;
  DateTime? _targetDate;
  GoalStatus _status = GoalStatus.active;
  int _colorValue = 0xFFFFA726;
  List<GoalMilestone> _milestones = [];
  bool _autoProgress = true;
  double _manualProgress = 0;

  static const _presetColors = [
    0xFFFFA726,
    0xFF66BB6A,
    0xFF42A5F5,
    0xFFAB47BC,
    0xFFEF5350,
    0xFF26A69A,
  ];

  bool get _isNew => widget.goal == null;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _title = TextEditingController(text: g?.title ?? '');
    _desc = TextEditingController(text: g?.description ?? '');
    _milestone = TextEditingController();
    _startDate = g?.startDate;
    _targetDate = g?.targetDate;
    _status = g?.status ?? GoalStatus.active;
    _colorValue = g?.colorValue ?? 0xFFFFA726;
    _milestones = [...?g?.milestones];
    _autoProgress = g?.autoProgress ?? true;
    _manualProgress = g?.progress ?? 0;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _milestone.dispose();
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) return;
    final p = context.read<GoalProvider>();
    final item = GoalItem(
      id: widget.goal?.id,
      title: _title.text.trim(),
      description: _desc.text.trim(),
      colorValue: _colorValue,
      startDate: _startDate,
      targetDate: _targetDate,
      status: _status,
      autoProgress: _autoProgress,
      progress: _autoProgress ? 0 : _manualProgress,
      milestones: _milestones,
      createdAt: widget.goal?.createdAt,
    );
    if (_isNew) {
      p.add(item);
    } else {
      p.update(item);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新建目标' : '编辑目标'),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                context.read<GoalProvider>().delete(widget.goal!.id);
                Navigator.pop(context);
              },
            ),
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '目标',
              hintText: '如：今年读 24 本书',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '描述 (可选)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _datePickRow(
                  label: '开始日期',
                  date: _startDate,
                  onPick: (d) => setState(() => _startDate = d),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _datePickRow(
                  label: '目标日期',
                  date: _targetDate,
                  onPick: (d) => setState(() => _targetDate = d),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('颜色',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            children: _presetColors.map((v) {
              return GestureDetector(
                onTap: () => setState(() => _colorValue = v),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(v),
                    shape: BoxShape.circle,
                    border: v == _colorValue
                        ? Border.all(color: Colors.black, width: 2)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text('状态',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: GoalStatus.values.map((s) {
              final label = switch (s) {
                GoalStatus.active => '进行中',
                GoalStatus.paused => '暂停',
                GoalStatus.achieved => '已达成',
                GoalStatus.abandoned => '放弃',
              };
              return ChoiceChip(
                label: Text(label),
                selected: _status == s,
                onSelected: (_) => setState(() => _status = s),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _autoProgress,
            title: const Text('按里程碑自动计算进度'),
            subtitle: Text(
              _autoProgress
                  ? '完成度 = 已完成里程碑 / 总里程碑'
                  : '手动设置当前进度',
            ),
            onChanged: (v) => setState(() => _autoProgress = v),
          ),
          if (!_autoProgress)
            Row(
              children: [
                const SizedBox(width: 16),
                const Text('进度:'),
                Expanded(
                  child: Slider(
                    value: _manualProgress,
                    onChanged: (v) =>
                        setState(() => _manualProgress = v),
                    label: '${(_manualProgress * 100).toInt()}%',
                    divisions: 100,
                  ),
                ),
                Text('${(_manualProgress * 100).toInt()}%'),
                const SizedBox(width: 16),
              ],
            ),
          const SizedBox(height: 16),
          const Text('里程碑',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 6),
          ..._milestones.asMap().entries.map(
                (e) => Dismissible(
                  key: ValueKey(e.value.id),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => setState(
                      () => _milestones.removeAt(e.key)),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: CheckboxListTile(
                    value: e.value.isCompleted,
                    onChanged: (v) => setState(() {
                      e.value.isCompleted = v ?? false;
                      e.value.completedAt =
                          e.value.isCompleted ? DateTime.now() : null;
                    }),
                    title: Text(
                      e.value.title,
                      style: TextStyle(
                        decoration: e.value.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: e.value.isCompleted ? Colors.grey : null,
                      ),
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _milestone,
                  decoration: const InputDecoration(
                    hintText: '添加里程碑',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      setState(() {
                        _milestones.add(GoalMilestone(title: v.trim()));
                        _milestone.clear();
                      });
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  if (_milestone.text.trim().isNotEmpty) {
                    setState(() {
                      _milestones.add(
                          GoalMilestone(title: _milestone.text.trim()));
                      _milestone.clear();
                    });
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _datePickRow({
    required String label,
    required DateTime? date,
    required void Function(DateTime?) onPick,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2099, 12, 31),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey)),
                  Text(
                    date == null
                        ? '未设置'
                        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            if (date != null)
              IconButton(
                iconSize: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.close),
                onPressed: () => onPick(null),
              ),
          ],
        ),
      ),
    );
  }
}
