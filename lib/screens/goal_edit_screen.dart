import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/goal_validation.dart';
import '../models/goal.dart';
import '../models/recurrence.dart';
import '../providers/goal_provider.dart';
import '../widgets/recurrence_picker.dart';

const List<int> _presetColors = <int>[
  0xFFFFA726,
  0xFF66BB6A,
  0xFF42A5F5,
  0xFFAB47BC,
  0xFFEF5350,
  0xFF26A69A,
];

const List<String> _weekdayNames = <String>['一', '二', '三', '四', '五', '六', '日'];

const List<int> _focusMinutePresets = <int>[15, 25, 45, 60];

const List<(String, String)> _whiteNoiseOptions = <(String, String)>[
  ('none', '无'),
  ('rain', '雨声'),
  ('forest', '森林'),
  ('cafe', '咖啡馆'),
  ('waves', '海浪'),
];

class GoalEditScreen extends StatefulWidget {
  final GoalItem? goal;
  const GoalEditScreen({super.key, this.goal});

  @override
  State<GoalEditScreen> createState() => _GoalEditScreenState();
}

class _GoalEditScreenState extends State<GoalEditScreen> {
  // ---- Basic ----
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  DateTime? _startDate;
  DateTime? _targetDate;
  GoalStatus _status = GoalStatus.active;
  int _colorValue = 0xFFFFA726;

  // ---- Recurrence ----
  RecurrenceRule _recurrence = const RecurrenceRule();

  // ---- Scheduling ----
  GoalScheduling _scheduling = const GoalScheduling.fixed();
  late final TextEditingController _minGapCtrl;
  late final TextEditingController _maxPerWeekCtrl;
  late final TextEditingController _maxPerMonthCtrl;

  // ---- Skip holidays ----
  bool _skipHolidays = false;

  // ---- Focus ----
  FocusLink _focus = const FocusLink.disabled();
  late final TextEditingController _focusMinutesCtrl;

  // ---- Reminder ----
  ReminderConfig _reminder = const ReminderConfig.disabled();

  // ---- Time target ----
  late final TextEditingController _timeTargetCtrl;

  // ---- Daily count ----
  late final TextEditingController _dailyCountCtrl;

  // ---- Milestones & auto progress ----
  bool _autoProgress = true;
  double _manualProgress = 0;
  List<GoalMilestone> _milestones = <GoalMilestone>[];
  late final TextEditingController _milestoneCtrl;

  /// 若为编辑模式则为原始 id；为新建模式时首次保存后赋值，
  /// 这样后续模块保存可直接走 `GoalProvider.update`。
  String? _editingId;

  /// 保留 createdAt，避免新建后再次 update 时时间被刷新。
  DateTime? _createdAt;

  bool get _isExisting => _editingId != null;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _editingId = g?.id;
    _createdAt = g?.createdAt;

    _titleCtrl = TextEditingController(text: g?.title ?? '');
    _descCtrl = TextEditingController(text: g?.description ?? '');
    _startDate = g?.startDate;
    _targetDate = g?.targetDate;
    _status = g?.status ?? GoalStatus.active;
    _colorValue = g?.colorValue ?? 0xFFFFA726;
    _recurrence = g?.recurrence ?? const RecurrenceRule();
    _scheduling = g?.scheduling ?? const GoalScheduling.fixed();
    _skipHolidays = g?.skipHolidays ?? false;
    _focus = g?.focusLink ?? const FocusLink.disabled();
    _reminder = g?.reminder ?? const ReminderConfig.disabled();
    _autoProgress = g?.autoProgress ?? true;
    _manualProgress = g?.progress ?? 0;
    _milestones = <GoalMilestone>[...?g?.milestones];

    _minGapCtrl = TextEditingController(
      text: _scheduling.randomMinGapDays?.toString() ?? '',
    );
    _maxPerWeekCtrl = TextEditingController(
      text: _scheduling.randomMaxPerWeek?.toString() ?? '',
    );
    _maxPerMonthCtrl = TextEditingController(
      text: _scheduling.randomMaxPerMonth?.toString() ?? '',
    );
    _focusMinutesCtrl = TextEditingController(
      text: _focus.focusSeconds != null
          ? (_focus.focusSeconds! ~/ 60).toString()
          : '',
    );
    _timeTargetCtrl = TextEditingController(
      text: g?.timeTargetSeconds != null
          ? (g!.timeTargetSeconds! ~/ 60).toString()
          : '',
    );
    _dailyCountCtrl = TextEditingController(
      text: g?.dailyTargetCount?.toString() ?? '',
    );
    _milestoneCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _minGapCtrl.dispose();
    _maxPerWeekCtrl.dispose();
    _maxPerMonthCtrl.dispose();
    _focusMinutesCtrl.dispose();
    _timeTargetCtrl.dispose();
    _dailyCountCtrl.dispose();
    _milestoneCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  GoalItem _composeItem() {
    return GoalItem(
      id: _editingId,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      icon: widget.goal?.icon ?? 'flag',
      colorValue: _colorValue,
      startDate: _startDate,
      targetDate: _targetDate,
      status: _status,
      autoProgress: _autoProgress,
      progress: _autoProgress
          ? (widget.goal?.progress ?? 0)
          : _manualProgress,
      milestones: _milestones,
      category: widget.goal?.category ?? GoalCategory.custom,
      recurrence: _recurrence,
      scheduling: _scheduling,
      skipHolidays: _skipHolidays,
      focusLink: _focus,
      reminder: _reminder,
      timeTargetSeconds:
          _parsePositiveInt(_timeTargetCtrl.text).let((min) => min * 60),
      dailyTargetCount: _parsePositiveInt(_dailyCountCtrl.text),
      sortOrder: widget.goal?.sortOrder ?? 0,
      createdAt: _createdAt,
    );
  }

  Future<bool> _persist({required bool pop}) async {
    if (_titleCtrl.text.trim().isEmpty) {
      _showError('请填写目标标题');
      return false;
    }
    final item = _composeItem();
    final issues = validateGoal(item);
    if (issues.isNotEmpty) {
      _showError(issues.first.message);
      return false;
    }
    final provider = context.read<GoalProvider>();
    if (!_isExisting) {
      await provider.add(item);
      if (!mounted) return true;
      setState(() {
        _editingId = item.id;
        _createdAt = item.createdAt;
      });
    } else {
      await provider.update(item);
    }
    if (!mounted) return true;
    if (pop) {
      Navigator.pop(context);
    } else {
      _showSaved();
    }
    return true;
  }

  void _showSaved() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('已保存'),
          duration: Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor: DesignTokens.resultError,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isExisting ? '编辑目标' : '新建目标'),
        actions: [
          if (_isExisting)
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await context.read<GoalProvider>().delete(_editingId!);
                if (!mounted) return;
                Navigator.pop(context);
              },
            ),
          IconButton(
            tooltip: '保存并返回',
            icon: const Icon(Icons.check),
            onPressed: () => _persist(pop: true),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spaceLg,
          DesignTokens.spaceMd,
          DesignTokens.spaceLg,
          DesignTokens.space3xl,
        ),
        children: [
          _BasicSection(
            titleCtrl: _titleCtrl,
            descCtrl: _descCtrl,
            startDate: _startDate,
            targetDate: _targetDate,
            status: _status,
            colorValue: _colorValue,
            onPickStart: (d) => setState(() => _startDate = d),
            onPickTarget: (d) => setState(() => _targetDate = d),
            onStatus: (s) => setState(() => _status = s),
            onColor: (v) => setState(() => _colorValue = v),
            onSave: () => _persist(pop: false),
          ),
          _RecurrenceSection(
            rule: _recurrence,
            nextDispatchLabel: _nextDispatchLabel(),
            onPick: () async {
              final r = await RecurrencePicker.show(
                context,
                initial: _recurrence,
              );
              if (r != null) setState(() => _recurrence = r);
            },
            onSave: () => _persist(pop: false),
          ),
          _SchedulingSection(
            scheduling: _scheduling,
            recurrence: _recurrence,
            minGapCtrl: _minGapCtrl,
            maxPerWeekCtrl: _maxPerWeekCtrl,
            maxPerMonthCtrl: _maxPerMonthCtrl,
            onModeChange: (mode) => setState(() {
              _scheduling = _scheduling.copyWith(mode: mode);
            }),
            onWeekdaysChange: (days) => setState(() {
              _scheduling = GoalScheduling(
                mode: _scheduling.mode,
                fixedWeekdays: days.isEmpty ? null : List<int>.unmodifiable(days),
                fixedMonthDays: _scheduling.fixedMonthDays,
                randomMinGapDays: _scheduling.randomMinGapDays,
                randomMaxPerWeek: _scheduling.randomMaxPerWeek,
                randomMaxPerMonth: _scheduling.randomMaxPerMonth,
              );
            }),
            onMonthDaysChange: (days) => setState(() {
              _scheduling = GoalScheduling(
                mode: _scheduling.mode,
                fixedWeekdays: _scheduling.fixedWeekdays,
                fixedMonthDays: days.isEmpty ? null : List<int>.unmodifiable(days),
                randomMinGapDays: _scheduling.randomMinGapDays,
                randomMaxPerWeek: _scheduling.randomMaxPerWeek,
                randomMaxPerMonth: _scheduling.randomMaxPerMonth,
              );
            }),
            onRandomChange: () => setState(() {
              _scheduling = GoalScheduling(
                mode: SchedulingMode.random,
                fixedWeekdays: _scheduling.fixedWeekdays,
                fixedMonthDays: _scheduling.fixedMonthDays,
                randomMinGapDays: _parsePositiveInt(_minGapCtrl.text),
                randomMaxPerWeek: _parsePositiveInt(_maxPerWeekCtrl.text),
                randomMaxPerMonth: _parsePositiveInt(_maxPerMonthCtrl.text),
              );
            }),
            onSave: () {
              // 随机模式下,输入框的改动尚未提交到 _scheduling,先同步一次。
              if (_scheduling.mode == SchedulingMode.random) {
                _scheduling = GoalScheduling(
                  mode: SchedulingMode.random,
                  fixedWeekdays: _scheduling.fixedWeekdays,
                  fixedMonthDays: _scheduling.fixedMonthDays,
                  randomMinGapDays: _parsePositiveInt(_minGapCtrl.text),
                  randomMaxPerWeek: _parsePositiveInt(_maxPerWeekCtrl.text),
                  randomMaxPerMonth: _parsePositiveInt(_maxPerMonthCtrl.text),
                );
              }
              return _persist(pop: false);
            },
          ),
          _SkipHolidaysSection(
            enabled: _skipHolidays,
            onChange: (v) => setState(() => _skipHolidays = v),
            onSave: () => _persist(pop: false),
          ),
          _FocusSection(
            focus: _focus,
            minutesCtrl: _focusMinutesCtrl,
            onToggle: (v) => setState(() {
              _focus = _focus.copyWith(enabled: v);
            }),
            onPickPreset: (min) => setState(() {
              _focusMinutesCtrl.text = min.toString();
              _focus = _focus.copyWith(focusSeconds: min * 60);
            }),
            onMinutesChange: (v) {
              final min = _parsePositiveInt(v);
              setState(() {
                _focus = FocusLink(
                  enabled: _focus.enabled,
                  presetId: _focus.presetId,
                  focusSeconds: min == null ? null : min * 60,
                  whiteNoise: _focus.whiteNoise,
                );
              });
            },
            onPickNoise: (id) => setState(() {
              _focus = _focus.copyWith(whiteNoise: id);
            }),
            onSave: () => _persist(pop: false),
          ),
          _ReminderSection(
            reminder: _reminder,
            hasTargetDate: _targetDate != null,
            onToggle: (v) => setState(() {
              _reminder = _reminder.copyWith(enabled: v);
            }),
            onPickTime: _pickReminderTime,
            onKind: (k) => setState(() {
              _reminder = _reminder.copyWith(kind: k);
            }),
            onDaysBeforeChange: (v) => setState(() {
              _reminder = _reminder.copyWith(daysBefore: v);
            }),
            onVibrate: (v) => setState(() {
              _reminder = _reminder.copyWith(vibrate: v);
            }),
            onFullScreen: (v) => setState(() {
              _reminder = _reminder.copyWith(fullScreen: v);
            }),
            onSave: () => _persist(pop: false),
          ),
          _TimeTargetSection(
            controller: _timeTargetCtrl,
            onClear: () {
              setState(() {
                _timeTargetCtrl.clear();
              });
            },
            onSave: () => _persist(pop: false),
          ),
          _DailyCountSection(
            controller: _dailyCountCtrl,
            onInc: () {
              final v = _parsePositiveInt(_dailyCountCtrl.text) ?? 0;
              setState(() {
                _dailyCountCtrl.text = (v + 1).toString();
              });
            },
            onDec: () {
              final v = _parsePositiveInt(_dailyCountCtrl.text) ?? 0;
              final next = v - 1;
              setState(() {
                _dailyCountCtrl.text = next <= 0 ? '' : next.toString();
              });
            },
            onChanged: (_) => setState(() {}),
            onSave: () => _persist(pop: false),
          ),
          _MilestonesSection(
            milestones: _milestones,
            controller: _milestoneCtrl,
            autoProgress: _autoProgress,
            manualProgress: _manualProgress,
            onToggle: (m, v) => setState(() {
              m.isCompleted = v;
              m.completedAt = v ? DateTime.now() : null;
            }),
            onRemove: (i) => setState(() {
              _milestones.removeAt(i);
            }),
            onAdd: (title) => setState(() {
              _milestones.add(GoalMilestone(title: title));
              _milestoneCtrl.clear();
            }),
            onAutoChange: (v) => setState(() => _autoProgress = v),
            onManualChange: (v) => setState(() => _manualProgress = v),
          ),
        ],
      ),
    );
  }

  String _nextDispatchLabel() {
    if (_recurrence.frequency == RecurrenceFrequency.none) return '不重复';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final anchor = (_startDate != null && _startDate!.isAfter(today))
        ? _startDate!
        : today;
    // TODO(task-22): 切到 RecurrenceEngine.nextOccurrence(rule, scheduling,
    //  skipHolidays, anchor)。当前阶段 RecurrenceEngine 尚未实现,先退化为
    //  基于 RecurrenceRule.nextAfter(anchor) 的临时计算。
    final next = _recurrence.nextAfter(anchor);
    if (next == null) return '无（已到终止日）';
    return _formatDate(next);
  }

  Future<void> _pickReminderTime() async {
    final initial = TimeOfDay(
      hour: _reminder.hour ?? TimeOfDay.now().hour,
      minute: _reminder.minute ?? 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    setState(() {
      _reminder = _reminder.copyWith(
        hour: picked.hour,
        minute: picked.minute,
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Section: 基础信息
// ---------------------------------------------------------------------------

class _BasicSection extends StatelessWidget {
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final DateTime? startDate;
  final DateTime? targetDate;
  final GoalStatus status;
  final int colorValue;
  final ValueChanged<DateTime?> onPickStart;
  final ValueChanged<DateTime?> onPickTarget;
  final ValueChanged<GoalStatus> onStatus;
  final ValueChanged<int> onColor;
  final VoidCallback onSave;

  const _BasicSection({
    required this.titleCtrl,
    required this.descCtrl,
    required this.startDate,
    required this.targetDate,
    required this.status,
    required this.colorValue,
    required this.onPickStart,
    required this.onPickTarget,
    required this.onStatus,
    required this.onColor,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '基础信息',
      icon: Icons.flag_outlined,
      initiallyExpanded: true,
      onSave: onSave,
      children: [
        TextField(
          controller: titleCtrl,
          decoration: const InputDecoration(
            labelText: '目标',
            hintText: '如：今年读 24 本书',
          ),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        TextField(
          controller: descCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '描述 (可选)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceLg),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: '开始日期',
                date: startDate,
                onPick: onPickStart,
              ),
            ),
            const SizedBox(width: DesignTokens.spaceSm),
            Expanded(
              child: _DateField(
                label: '目标日期',
                date: targetDate,
                onPick: onPickTarget,
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spaceLg),
        Text(
          '颜色',
          style: _subtleLabel(context),
        ),
        const SizedBox(height: DesignTokens.spaceXs),
        Wrap(
          spacing: DesignTokens.spaceSm,
          children: _presetColors.map((v) {
            final selected = v == colorValue;
            return GestureDetector(
              onTap: () => onColor(v),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(v),
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 2,
                        )
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: DesignTokens.spaceLg),
        Text('状态', style: _subtleLabel(context)),
        const SizedBox(height: DesignTokens.spaceXs),
        Wrap(
          spacing: DesignTokens.spaceXs,
          children: GoalStatus.values.map((s) {
            final label = switch (s) {
              GoalStatus.active => '进行中',
              GoalStatus.paused => '暂停',
              GoalStatus.achieved => '已达成',
              GoalStatus.abandoned => '放弃',
            };
            return ChoiceChip(
              label: Text(label),
              selected: status == s,
              onSelected: (_) => onStatus(s),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 重复规则
// ---------------------------------------------------------------------------

class _RecurrenceSection extends StatelessWidget {
  final RecurrenceRule rule;
  final String nextDispatchLabel;
  final VoidCallback onPick;
  final VoidCallback onSave;

  const _RecurrenceSection({
    required this.rule,
    required this.nextDispatchLabel,
    required this.onPick,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '重复规则',
      icon: Icons.repeat,
      subtitle: rule.label,
      onSave: onSave,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.tune),
          title: const Text('编辑重复规则'),
          subtitle: Text(rule.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: onPick,
        ),
        const SizedBox(height: DesignTokens.spaceXs),
        Container(
          padding: const EdgeInsets.all(DesignTokens.spaceMd),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.06),
            borderRadius: DesignTokens.borderRadiusSm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.event_available,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              Text(
                '下一次派发日：',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeSm,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: DesignTokens.spaceXs),
              Expanded(
                child: Text(
                  nextDispatchLabel,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeBase,
                    fontWeight: DesignTokens.fontWeightSemiBold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 调度模式
// ---------------------------------------------------------------------------

class _SchedulingSection extends StatelessWidget {
  final GoalScheduling scheduling;
  final RecurrenceRule recurrence;
  final TextEditingController minGapCtrl;
  final TextEditingController maxPerWeekCtrl;
  final TextEditingController maxPerMonthCtrl;
  final ValueChanged<SchedulingMode> onModeChange;
  final ValueChanged<List<int>> onWeekdaysChange;
  final ValueChanged<List<int>> onMonthDaysChange;
  final VoidCallback onRandomChange;
  final VoidCallback onSave;

  const _SchedulingSection({
    required this.scheduling,
    required this.recurrence,
    required this.minGapCtrl,
    required this.maxPerWeekCtrl,
    required this.maxPerMonthCtrl,
    required this.onModeChange,
    required this.onWeekdaysChange,
    required this.onMonthDaysChange,
    required this.onRandomChange,
    required this.onSave,
  });

  String _subtitle() {
    if (scheduling.mode == SchedulingMode.random) return '随机派发';
    if (recurrence.frequency == RecurrenceFrequency.weekly &&
        (scheduling.fixedWeekdays?.isNotEmpty ?? false)) {
      final days = ([...scheduling.fixedWeekdays!]..sort())
          .where((d) => d >= 0 && d < 7)
          .map((d) => '周${_weekdayNames[d]}')
          .join('/');
      return '固定 · $days';
    }
    if (recurrence.frequency == RecurrenceFrequency.monthly &&
        (scheduling.fixedMonthDays?.isNotEmpty ?? false)) {
      final days = ([...scheduling.fixedMonthDays!]..sort()).join('/');
      return '固定 · 每月 $days 号';
    }
    return '固定派发';
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '调度模式',
      icon: Icons.tune,
      subtitle: _subtitle(),
      onSave: onSave,
      children: [
        SegmentedButton<SchedulingMode>(
          segments: const [
            ButtonSegment(
              value: SchedulingMode.fixed,
              label: Text('固定'),
              icon: Icon(Icons.calendar_view_week),
            ),
            ButtonSegment(
              value: SchedulingMode.random,
              label: Text('随机'),
              icon: Icon(Icons.shuffle),
            ),
          ],
          selected: {scheduling.mode},
          onSelectionChanged: (s) => onModeChange(s.first),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        if (scheduling.mode == SchedulingMode.fixed)
          _FixedScheduling(
            scheduling: scheduling,
            recurrence: recurrence,
            onWeekdaysChange: onWeekdaysChange,
            onMonthDaysChange: onMonthDaysChange,
          )
        else
          _RandomScheduling(
            minGapCtrl: minGapCtrl,
            maxPerWeekCtrl: maxPerWeekCtrl,
            maxPerMonthCtrl: maxPerMonthCtrl,
            onChanged: onRandomChange,
          ),
      ],
    );
  }
}

class _FixedScheduling extends StatelessWidget {
  final GoalScheduling scheduling;
  final RecurrenceRule recurrence;
  final ValueChanged<List<int>> onWeekdaysChange;
  final ValueChanged<List<int>> onMonthDaysChange;

  const _FixedScheduling({
    required this.scheduling,
    required this.recurrence,
    required this.onWeekdaysChange,
    required this.onMonthDaysChange,
  });

  @override
  Widget build(BuildContext context) {
    if (recurrence.frequency == RecurrenceFrequency.weekly) {
      final selected = <int>{...?scheduling.fixedWeekdays};
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('每周派发日', style: _subtleLabel(context)),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceXs,
            children: List.generate(7, (i) {
              final isSel = selected.contains(i);
              return FilterChip(
                label: Text('周${_weekdayNames[i]}'),
                selected: isSel,
                showCheckmark: false,
                onSelected: (_) {
                  final next = {...selected};
                  if (isSel) {
                    next.remove(i);
                  } else {
                    next.add(i);
                  }
                  onWeekdaysChange(next.toList()..sort());
                },
              );
            }),
          ),
        ],
      );
    }
    if (recurrence.frequency == RecurrenceFrequency.monthly) {
      final selected = <int>{...?scheduling.fixedMonthDays};
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('每月派发日（1~31）', style: _subtleLabel(context)),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceXs,
            runSpacing: DesignTokens.spaceXs,
            children: List.generate(31, (i) {
              final day = i + 1;
              final isSel = selected.contains(day);
              return FilterChip(
                label: Text('$day'),
                selected: isSel,
                showCheckmark: false,
                onSelected: (_) {
                  final next = {...selected};
                  if (isSel) {
                    next.remove(day);
                  } else {
                    next.add(day);
                  }
                  onMonthDaysChange(next.toList()..sort());
                },
              );
            }),
          ),
        ],
      );
    }
    return Text(
      '当前重复规则下无需额外配置固定派发日。',
      style: TextStyle(
        fontSize: DesignTokens.fontSizeSm,
        color: Theme.of(context)
            .colorScheme
            .onSurface
            .withValues(alpha: 0.6),
      ),
    );
  }
}

class _RandomScheduling extends StatelessWidget {
  final TextEditingController minGapCtrl;
  final TextEditingController maxPerWeekCtrl;
  final TextEditingController maxPerMonthCtrl;
  final VoidCallback onChanged;

  const _RandomScheduling({
    required this.minGapCtrl,
    required this.maxPerWeekCtrl,
    required this.maxPerMonthCtrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RandomRow(
          label: '最小间隔天数',
          hint: '≥ 1',
          controller: minGapCtrl,
          onChanged: onChanged,
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        _RandomRow(
          label: '每周最多派发次数',
          hint: '留空 = 不限',
          controller: maxPerWeekCtrl,
          onChanged: onChanged,
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        _RandomRow(
          label: '每月最多派发次数',
          hint: '留空 = 不限',
          controller: maxPerMonthCtrl,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RandomRow extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _RandomRow({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(label, style: _subtleLabel(context)),
        ),
        Expanded(
          flex: 2,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 跳过节假日
// ---------------------------------------------------------------------------

class _SkipHolidaysSection extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChange;
  final VoidCallback onSave;

  const _SkipHolidaysSection({
    required this.enabled,
    required this.onChange,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '跳过节假日',
      icon: Icons.beach_access,
      subtitle: enabled ? '已开启' : '已关闭',
      onSave: onSave,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          title: const Text('遇法定节假日顺延'),
          subtitle: const Text('派发日遇节假日时自动跳到下一个工作日'),
          onChanged: onChange,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 专注联动
// ---------------------------------------------------------------------------

class _FocusSection extends StatelessWidget {
  final FocusLink focus;
  final TextEditingController minutesCtrl;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onPickPreset;
  final ValueChanged<String> onMinutesChange;
  final ValueChanged<String> onPickNoise;
  final VoidCallback onSave;

  const _FocusSection({
    required this.focus,
    required this.minutesCtrl,
    required this.onToggle,
    required this.onPickPreset,
    required this.onMinutesChange,
    required this.onPickNoise,
    required this.onSave,
  });

  String _subtitle() {
    if (!focus.enabled) return '已关闭';
    final sec = focus.focusSeconds;
    final min = (sec == null || sec <= 0) ? null : sec ~/ 60;
    final noise = _whiteNoiseOptions.firstWhere(
      (e) => e.$1 == focus.whiteNoise,
      orElse: () => ('none', '无'),
    );
    if (min == null) return '已开启 · ${noise.$2}';
    return '$min 分钟 · ${noise.$2}';
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '专注联动',
      icon: Icons.timer_outlined,
      subtitle: _subtitle(),
      onSave: onSave,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: focus.enabled,
          title: const Text('开启专注联动'),
          subtitle: const Text('派发时自动跳转番茄钟,并播放白噪音'),
          onChanged: onToggle,
        ),
        if (focus.enabled) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          Text('专注时长', style: _subtleLabel(context)),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceXs,
            children: _focusMinutePresets.map((m) {
              final selected = focus.focusSeconds == m * 60;
              return ChoiceChip(
                label: Text('$m 分钟'),
                selected: selected,
                onSelected: (_) => onPickPreset(m),
              );
            }).toList(),
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('自定义分钟', style: _subtleLabel(context)),
              ),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: minutesCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '留空 = 未设定',
                  ),
                  onChanged: onMinutesChange,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          Text('白噪音', style: _subtleLabel(context)),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceXs,
            children: _whiteNoiseOptions.map((opt) {
              final selected = focus.whiteNoise == opt.$1;
              return ChoiceChip(
                label: Text(opt.$2),
                selected: selected,
                onSelected: (_) => onPickNoise(opt.$1),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 提醒
// ---------------------------------------------------------------------------

class _ReminderSection extends StatelessWidget {
  final ReminderConfig reminder;
  final bool hasTargetDate;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickTime;
  final ValueChanged<ReminderKind> onKind;
  final ValueChanged<int> onDaysBeforeChange;
  final ValueChanged<bool> onVibrate;
  final ValueChanged<bool> onFullScreen;
  final VoidCallback onSave;

  const _ReminderSection({
    required this.reminder,
    required this.hasTargetDate,
    required this.onToggle,
    required this.onPickTime,
    required this.onKind,
    required this.onDaysBeforeChange,
    required this.onVibrate,
    required this.onFullScreen,
    required this.onSave,
  });

  String _subtitle() {
    if (!reminder.enabled) return '已关闭';
    final hhmm = _formatHm(reminder.hour, reminder.minute) ?? '未设置时间';
    final kind = reminder.kind == ReminderKind.alarm ? '闹钟' : '推送';
    return '$kind · $hhmm';
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel = _formatHm(reminder.hour, reminder.minute) ?? '选择时间';
    return _SectionCard(
      title: '提醒',
      icon: Icons.notifications_active_outlined,
      subtitle: _subtitle(),
      onSave: onSave,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: reminder.enabled,
          title: const Text('开启提醒'),
          subtitle: const Text('派发日按时触发提醒'),
          onChanged: onToggle,
        ),
        if (reminder.enabled) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('提醒时间'),
            subtitle: Text(timeLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: onPickTime,
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          Text('提醒类型', style: _subtleLabel(context)),
          const SizedBox(height: DesignTokens.spaceXs),
          SegmentedButton<ReminderKind>(
            segments: const [
              ButtonSegment(
                value: ReminderKind.push,
                label: Text('推送'),
                icon: Icon(Icons.notifications),
              ),
              ButtonSegment(
                value: ReminderKind.alarm,
                label: Text('闹钟'),
                icon: Icon(Icons.alarm),
              ),
            ],
            selected: {reminder.kind},
            onSelectionChanged: (s) => onKind(s.first),
          ),
          if (hasTargetDate) ...[
            const SizedBox(height: DesignTokens.spaceMd),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child:
                      Text('目标日前 N 天提醒', style: _subtleLabel(context)),
                ),
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: reminder.daysBefore > 0
                            ? () => onDaysBeforeChange(reminder.daysBefore - 1)
                            : null,
                      ),
                      Expanded(
                        child: Text(
                          '${reminder.daysBefore} 天',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () =>
                            onDaysBeforeChange(reminder.daysBefore + 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: reminder.vibrate,
            title: const Text('震动'),
            onChanged: onVibrate,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: reminder.fullScreen,
            title: const Text('全屏提醒'),
            subtitle: const Text('仅对闹钟类型生效'),
            onChanged: reminder.kind == ReminderKind.alarm ? onFullScreen : null,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 目标时长
// ---------------------------------------------------------------------------

class _TimeTargetSection extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onClear;
  final VoidCallback onSave;

  const _TimeTargetSection({
    required this.controller,
    required this.onClear,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final min = int.tryParse(controller.text.trim());
    final subtitle =
        (min == null || min <= 0) ? '未设置' : '$min 分钟 / 每次';
    return _SectionCard(
      title: '目标时长',
      icon: Icons.hourglass_bottom,
      subtitle: subtitle,
      onSave: onSave,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Text('每次时长（分钟）', style: _subtleLabel(context)),
            ),
            Expanded(
              flex: 2,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '0 或留空 = 清除',
                ),
              ),
            ),
            IconButton(
              tooltip: '清除',
              icon: const Icon(Icons.clear),
              onPressed: onClear,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 每日次数
// ---------------------------------------------------------------------------

class _DailyCountSection extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final ValueChanged<String> onChanged;
  final VoidCallback onSave;

  const _DailyCountSection({
    required this.controller,
    required this.onInc,
    required this.onDec,
    required this.onChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(controller.text.trim());
    final subtitle = (n == null || n <= 0) ? '未设置' : '每日 $n 次';
    return _SectionCard(
      title: '每日次数',
      icon: Icons.format_list_numbered,
      subtitle: subtitle,
      onSave: onSave,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Text('每日目标次数', style: _subtleLabel(context)),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: onDec,
            ),
            SizedBox(
              width: 72,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '0',
                ),
                onChanged: onChanged,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onInc,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 里程碑 + 自动进度
// ---------------------------------------------------------------------------

class _MilestonesSection extends StatelessWidget {
  final List<GoalMilestone> milestones;
  final TextEditingController controller;
  final bool autoProgress;
  final double manualProgress;
  final void Function(GoalMilestone, bool) onToggle;
  final ValueChanged<int> onRemove;
  final ValueChanged<String> onAdd;
  final ValueChanged<bool> onAutoChange;
  final ValueChanged<double> onManualChange;

  const _MilestonesSection({
    required this.milestones,
    required this.controller,
    required this.autoProgress,
    required this.manualProgress,
    required this.onToggle,
    required this.onRemove,
    required this.onAdd,
    required this.onAutoChange,
    required this.onManualChange,
  });

  @override
  Widget build(BuildContext context) {
    final completed = milestones.where((m) => m.isCompleted).length;
    return _SectionCard(
      title: '里程碑与进度',
      icon: Icons.flag_circle_outlined,
      subtitle: '$completed/${milestones.length} · '
          '${autoProgress ? '自动' : '手动 ${(manualProgress * 100).toInt()}%'}',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: autoProgress,
          title: const Text('按里程碑自动计算进度'),
          subtitle: Text(
            autoProgress ? '完成度 = 已完成里程碑 / 总里程碑' : '手动设置当前进度',
          ),
          onChanged: onAutoChange,
        ),
        if (!autoProgress)
          Row(
            children: [
              const Text('进度:'),
              Expanded(
                child: Slider(
                  value: manualProgress,
                  onChanged: onManualChange,
                  label: '${(manualProgress * 100).toInt()}%',
                  divisions: 100,
                ),
              ),
              Text('${(manualProgress * 100).toInt()}%'),
            ],
          ),
        const SizedBox(height: DesignTokens.spaceSm),
        ...milestones.asMap().entries.map(
              (e) => Dismissible(
                key: ValueKey(e.value.id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => onRemove(e.key),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding:
                      const EdgeInsets.only(right: DesignTokens.spaceLg),
                  color: DesignTokens.resultError,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: CheckboxListTile(
                  value: e.value.isCompleted,
                  onChanged: (v) => onToggle(e.value, v ?? false),
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
                controller: controller,
                decoration: const InputDecoration(
                  hintText: '添加里程碑',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) onAdd(v.trim());
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                final v = controller.text.trim();
                if (v.isNotEmpty) onAdd(v);
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final bool initiallyExpanded;
  final VoidCallback? onSave;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: DesignTokens.spaceMd),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: DesignTokens.borderRadiusLg,
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
        boxShadow: DesignTokens.shadowXs,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceLg,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            DesignTokens.spaceLg,
            0,
            DesignTokens.spaceLg,
            DesignTokens.spaceLg,
          ),
          leading: Icon(icon, color: cs.primary),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: DesignTokens.fontSizeMd,
              fontWeight: DesignTokens.fontWeightSemiBold,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeSm,
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
          children: [
            ...children,
            if (onSave != null) ...[
              const SizedBox(height: DesignTokens.spaceMd),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('保存本模块'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final ValueChanged<DateTime?> onPick;

  const _DateField({
    required this.label,
    required this.date,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
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
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceMd,
          vertical: DesignTokens.spaceSm,
        ),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: DesignTokens.borderRadiusSm,
          border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 14,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: DesignTokens.spaceXs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeXs,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  Text(
                    date == null ? '未设置' : _formatDate(date!),
                    style: const TextStyle(
                      fontSize: DesignTokens.fontSizeBase,
                    ),
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

TextStyle _subtleLabel(BuildContext context) => TextStyle(
      fontSize: DesignTokens.fontSizeSm,
      color: Theme.of(context)
          .colorScheme
          .onSurface
          .withValues(alpha: 0.65),
    );

String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String? _formatHm(int? hour, int? minute) {
  if (hour == null || minute == null) return null;
  final hh = hour.toString().padLeft(2, '0');
  final mm = minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// 解析正整数输入；空串或非正整数返回 null。
int? _parsePositiveInt(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final n = int.tryParse(s);
  if (n == null || n <= 0) return null;
  return n;
}

extension _NullableIntMap on int? {
  /// `1.let((x) => x * 60)` → 60；`null.let(...)` → null。
  T? let<T>(T Function(int) fn) {
    final v = this;
    if (v == null) return null;
    return fn(v);
  }
}
