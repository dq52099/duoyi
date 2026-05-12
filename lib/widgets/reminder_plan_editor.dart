import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/goal.dart';
import 'surface_components.dart';

class ReminderPlanEditor extends StatelessWidget {
  final ReminderPlan plan;
  final ValueChanged<ReminderPlan> onChanged;
  final String title;
  final String? subtitle;
  final bool showHeader;
  final bool allowAlarm;
  final bool allowRelativeToDue;
  final bool allowWeekly;
  final bool allowSnooze;
  final bool hasAnchorDate;
  final int? maxRules;
  final ReminderKind defaultKind;

  const ReminderPlanEditor({
    super.key,
    required this.plan,
    required this.onChanged,
    this.title = '提醒',
    this.subtitle,
    this.showHeader = true,
    this.allowAlarm = true,
    this.allowRelativeToDue = true,
    this.allowWeekly = true,
    this.allowSnooze = true,
    this.hasAnchorDate = true,
    this.maxRules,
    this.defaultKind = ReminderKind.push,
  });

  @override
  Widget build(BuildContext context) {
    final rules = plan.rules;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: plan.enabled,
            title: Text(title),
            subtitle: Text(subtitle ?? reminderPlanSummary(plan)),
            onChanged: _toggleEnabled,
          ),
        ] else
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: plan.enabled,
            title: const Text('开启提醒'),
            subtitle: Text(reminderPlanSummary(plan)),
            onChanged: _toggleEnabled,
          ),
        if (plan.enabled) ...[
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spaceSm,
              ),
              child: Text(
                '未添加提醒',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.58),
                  fontSize: DesignTokens.fontSizeSm,
                ),
              ),
            )
          else
            ...rules.map(
              (rule) => Padding(
                padding: const EdgeInsets.only(bottom: DesignTokens.spaceXs),
                child: _ReminderRuleTile(
                  rule: rule,
                  onTap: () => _editRule(context, rule),
                  onDelete: () => _deleteRule(rule.id),
                ),
              ),
            ),
          if (maxRules == null || rules.length < maxRules!)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _editRule(context, null),
                icon: const Icon(Icons.add_alarm, size: 18),
                label: const Text('添加提醒'),
              ),
            ),
        ],
      ],
    );
  }

  void _toggleEnabled(bool enabled) {
    if (!enabled) {
      onChanged(plan.copyWith(enabled: false));
      return;
    }
    final rules = plan.rules.isEmpty ? [_defaultRule()] : plan.rules;
    onChanged(ReminderPlan(enabled: true, rules: rules));
  }

  ReminderRule _defaultRule() {
    final seed = DateTime.now().add(const Duration(hours: 1));
    final minute = (seed.minute ~/ 5 * 5).clamp(0, 55).toInt();
    final type = hasAnchorDate && allowRelativeToDue
        ? ReminderRuleType.absolute
        : ReminderRuleType.dailyTime;
    return ReminderRule(
      type: type,
      kind: defaultKind,
      hour: seed.hour,
      minute: minute,
      weekdays: type == ReminderRuleType.weeklyTime
          ? [DateTime.now().weekday]
          : const <int>[],
    );
  }

  Future<void> _editRule(BuildContext context, ReminderRule? rule) async {
    final edited = await showAppModalSheet<ReminderRule>(
      context: context,
      builder: (_) => _ReminderRuleSheet(
        initial: rule,
        allowAlarm: allowAlarm,
        allowRelativeToDue: allowRelativeToDue,
        allowWeekly: allowWeekly,
        allowSnooze: allowSnooze,
        hasAnchorDate: hasAnchorDate,
        defaultKind: defaultKind,
      ),
    );
    if (edited == null) return;
    final nextRules = [...plan.rules];
    final index = nextRules.indexWhere((r) => r.id == edited.id);
    if (index >= 0) {
      nextRules[index] = edited;
    } else {
      nextRules.add(edited);
    }
    onChanged(ReminderPlan(enabled: true, rules: nextRules));
  }

  void _deleteRule(String ruleId) {
    final nextRules = plan.rules.where((r) => r.id != ruleId).toList();
    onChanged(ReminderPlan(enabled: nextRules.isNotEmpty, rules: nextRules));
  }
}

String reminderPlanSummary(ReminderPlan plan) {
  if (!plan.enabled) return '已关闭';
  final enabledRules = plan.rules.where((r) => r.enabled).toList();
  if (enabledRules.isEmpty) return '无启用规则';
  if (enabledRules.length == 1) return _ruleSummary(enabledRules.single);
  return '${enabledRules.length} 条提醒';
}

class _ReminderRuleTile extends StatelessWidget {
  final ReminderRule rule;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ReminderRuleTile({
    required this.rule,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = rule.kind == ReminderKind.alarm
        ? DesignTokens.priorityMedium
        : cs.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: DesignTokens.borderRadiusSm,
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: DesignTokens.borderRadiusSm,
            border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.only(left: 12, right: 4),
            leading: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: DesignTokens.borderRadiusSm,
              ),
              child: Icon(_ruleIcon(rule), color: color, size: 19),
            ),
            title: Text(
              _ruleTitle(rule),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: DesignTokens.fontWeightSemiBold,
              ),
            ),
            subtitle: Text(
              _ruleSummary(rule),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDelete,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReminderRuleSheet extends StatefulWidget {
  final ReminderRule? initial;
  final bool allowAlarm;
  final bool allowRelativeToDue;
  final bool allowWeekly;
  final bool allowSnooze;
  final bool hasAnchorDate;
  final ReminderKind defaultKind;

  const _ReminderRuleSheet({
    required this.initial,
    required this.allowAlarm,
    required this.allowRelativeToDue,
    required this.allowWeekly,
    required this.allowSnooze,
    required this.hasAnchorDate,
    required this.defaultKind,
  });

  @override
  State<_ReminderRuleSheet> createState() => _ReminderRuleSheetState();
}

class _ReminderRuleSheetState extends State<_ReminderRuleSheet> {
  late bool _enabled;
  late ReminderRuleType _type;
  late ReminderKind _kind;
  late TimeOfDay _time;
  late int _offsetMinutes;
  late List<int> _weekdays;
  late bool _vibrate;
  late bool _fullScreen;
  late int _snoozeMinutes;
  late int _repeatCount;

  List<ReminderRuleType> get _availableTypes {
    final types = <ReminderRuleType>[
      if (widget.allowRelativeToDue) ReminderRuleType.absolute,
      if (widget.allowRelativeToDue) ReminderRuleType.relativeToDue,
      ReminderRuleType.dailyTime,
      if (widget.allowWeekly) ReminderRuleType.weeklyTime,
    ];
    return types;
  }

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    final defaultTime = nextHalfHourTimeOfDay();
    _enabled = r?.enabled ?? true;
    _type =
        r?.type ??
        (widget.hasAnchorDate
            ? ReminderRuleType.absolute
            : ReminderRuleType.dailyTime);
    if (!_availableTypes.contains(_type)) {
      _type = _availableTypes.first;
    }
    _kind = widget.allowAlarm
        ? r?.kind ?? widget.defaultKind
        : widget.defaultKind;
    _time = TimeOfDay(
      hour: r?.hour ?? defaultTime.hour,
      minute: r?.minute ?? defaultTime.minute,
    );
    _offsetMinutes = r?.offsetMinutes ?? -30;
    _weekdays = r?.weekdays.isNotEmpty == true
        ? [...r!.weekdays]
        : [DateTime.now().weekday];
    _vibrate = r?.vibrate ?? true;
    _fullScreen = r?.fullScreen ?? true;
    _snoozeMinutes = r?.snoozeMinutes ?? 0;
    _repeatCount = r?.repeatCount ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return AppModalSheet(
      title: widget.initial == null ? '添加提醒' : '编辑提醒',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            title: const Text('启用'),
            onChanged: (v) => setState(() => _enabled = v),
          ),
          AppDropdownField<ReminderRuleType>(
            initialValue: _type,
            labelText: '提醒类型',
            prefixIcon: const Icon(Icons.tune, size: 20),
            items: [
              for (final type in _availableTypes)
                DropdownMenuItem(value: type, child: Text(_typeLabel(type))),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _type = v);
            },
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('提醒时间'),
            subtitle: Text(_formatTimeOfDay(_time)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickTime,
          ),
          if (_type == ReminderRuleType.relativeToDue) ...[
            const SizedBox(height: DesignTokens.spaceSm),
            Text('提前时间', style: _labelStyle(context)),
            const SizedBox(height: DesignTokens.spaceXs),
            Wrap(
              spacing: DesignTokens.spaceXs,
              runSpacing: DesignTokens.spaceXs,
              children:
                  const [
                    (-10, '10 分钟'),
                    (-30, '30 分钟'),
                    (-60, '1 小时'),
                    (-1440, '1 天'),
                    (-2880, '2 天'),
                    (-4320, '3 天'),
                  ].map((preset) {
                    return ChoiceChip(
                      label: Text(preset.$2),
                      selected: _offsetMinutes == preset.$1,
                      onSelected: (_) =>
                          setState(() => _offsetMinutes = preset.$1),
                    );
                  }).toList(),
            ),
          ],
          if (_type == ReminderRuleType.weeklyTime) ...[
            const SizedBox(height: DesignTokens.spaceSm),
            Text('每周', style: _labelStyle(context)),
            const SizedBox(height: DesignTokens.spaceXs),
            Wrap(
              spacing: DesignTokens.spaceXs,
              runSpacing: DesignTokens.spaceXs,
              children: List.generate(7, (i) {
                final day = i + 1;
                final selected = _weekdays.contains(day);
                return FilterChip(
                  label: Text(_weekdayNames[i]),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) {
                    final next = {..._weekdays};
                    if (selected) {
                      next.remove(day);
                    } else {
                      next.add(day);
                    }
                    if (next.isEmpty) next.add(day);
                    setState(() => _weekdays = next.toList()..sort());
                  },
                );
              }),
            ),
          ],
          const SizedBox(height: DesignTokens.spaceMd),
          if (widget.allowAlarm) ...[
            Text('提醒方式', style: _labelStyle(context)),
            const SizedBox(height: DesignTokens.spaceXs),
            SegmentedButton<ReminderKind>(
              segments: const [
                ButtonSegment(
                  value: ReminderKind.push,
                  label: Text('推送'),
                  icon: Icon(Icons.notifications_outlined),
                ),
                ButtonSegment(
                  value: ReminderKind.alarm,
                  label: Text('闹钟'),
                  icon: Icon(Icons.alarm_outlined),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _vibrate,
            title: const Text('震动'),
            onChanged: (v) => setState(() => _vibrate = v),
          ),
          if (_kind == ReminderKind.alarm)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _fullScreen,
              title: const Text('全屏提醒'),
              subtitle: const Text('仅闹钟方式生效'),
              onChanged: (v) => setState(() => _fullScreen = v),
            ),
          if (widget.allowSnooze) ...[
            const SizedBox(height: DesignTokens.spaceXs),
            Text('稍后提醒', style: _labelStyle(context)),
            const SizedBox(height: DesignTokens.spaceXs),
            Wrap(
              spacing: DesignTokens.spaceXs,
              runSpacing: DesignTokens.spaceXs,
              children:
                  const [
                    (0, '关闭'),
                    (5, '5 分钟'),
                    (10, '10 分钟'),
                    (15, '15 分钟'),
                    (30, '30 分钟'),
                  ].map((preset) {
                    return ChoiceChip(
                      label: Text(preset.$2),
                      selected: _snoozeMinutes == preset.$1,
                      onSelected: (_) =>
                          setState(() => _snoozeMinutes = preset.$1),
                    );
                  }).toList(),
            ),
            const SizedBox(height: DesignTokens.spaceSm),
            Text('重复次数', style: _labelStyle(context)),
            const SizedBox(height: DesignTokens.spaceXs),
            Wrap(
              spacing: DesignTokens.spaceXs,
              children: [0, 1, 2, 3].map((count) {
                return ChoiceChip(
                  label: Text(count == 0 ? '不重复' : '$count 次'),
                  selected: _repeatCount == count,
                  onSelected: (_) => setState(() => _repeatCount = count),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    final type = _type;
    final rule = ReminderRule(
      id: widget.initial?.id,
      enabled: _enabled,
      type: type,
      kind: widget.allowAlarm ? _kind : widget.defaultKind,
      hour: _time.hour,
      minute: _time.minute,
      offsetMinutes: type == ReminderRuleType.relativeToDue
          ? _offsetMinutes
          : null,
      weekdays: type == ReminderRuleType.weeklyTime ? _weekdays : const <int>[],
      vibrate: _vibrate,
      fullScreen: _kind == ReminderKind.alarm && _fullScreen,
      snoozeMinutes: _snoozeMinutes,
      repeatCount: _repeatCount,
    );
    Navigator.pop(context, rule);
  }
}

TextStyle _labelStyle(BuildContext context) {
  return TextStyle(
    fontSize: DesignTokens.fontSizeSm,
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.68),
    fontWeight: DesignTokens.fontWeightMedium,
  );
}

IconData _ruleIcon(ReminderRule rule) {
  if (rule.kind == ReminderKind.alarm) return Icons.alarm_outlined;
  return switch (rule.type) {
    ReminderRuleType.absolute => Icons.event_available_outlined,
    ReminderRuleType.relativeToDue => Icons.timelapse_outlined,
    ReminderRuleType.dailyTime => Icons.today_outlined,
    ReminderRuleType.weeklyTime => Icons.calendar_view_week_outlined,
  };
}

String _ruleTitle(ReminderRule rule) {
  final mode = rule.kind == ReminderKind.alarm ? '闹钟' : '推送';
  return '${_typeLabel(rule.type)} · $mode';
}

String _ruleSummary(ReminderRule rule) {
  final pieces = <String>[_formatHm(rule.hour, rule.minute)];
  if (rule.type == ReminderRuleType.relativeToDue) {
    pieces.add('提前 ${_durationLabel((rule.offsetMinutes ?? 0).abs())}');
  }
  if (rule.type == ReminderRuleType.weeklyTime && rule.weekdays.isNotEmpty) {
    pieces.add(rule.weekdays.map(_weekdayLabel).join('/'));
  }
  if (rule.snoozeMinutes > 0) {
    pieces.add('稍后 ${rule.snoozeMinutes} 分钟');
  }
  if (rule.repeatCount > 0) {
    pieces.add('重复 ${rule.repeatCount} 次');
  }
  if (!rule.enabled) pieces.add('已停用');
  return pieces.join(' · ');
}

String _typeLabel(ReminderRuleType type) => switch (type) {
  ReminderRuleType.absolute => '到期提醒',
  ReminderRuleType.relativeToDue => '提前提醒',
  ReminderRuleType.dailyTime => '每日提醒',
  ReminderRuleType.weeklyTime => '每周提醒',
};

String _formatHm(int? hour, int? minute) {
  if (hour == null || minute == null) return '未设置时间';
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String _formatTimeOfDay(TimeOfDay time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

TimeOfDay nextHalfHourTimeOfDay([DateTime? from]) {
  final now = from ?? DateTime.now();
  if (now.minute < 30) {
    return TimeOfDay(hour: now.hour, minute: 30);
  }
  return TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
}

String _durationLabel(int minutes) {
  if (minutes >= 1440 && minutes % 1440 == 0) {
    return '${minutes ~/ 1440} 天';
  }
  if (minutes >= 60 && minutes % 60 == 0) return '${minutes ~/ 60} 小时';
  return '$minutes 分钟';
}

String _weekdayLabel(int day) {
  if (day < 1 || day > 7) return '周?';
  return '周${_weekdayNames[day - 1]}';
}

const _weekdayNames = <String>['一', '二', '三', '四', '五', '六', '日'];
