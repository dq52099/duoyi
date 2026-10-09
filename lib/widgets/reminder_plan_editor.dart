import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/reminder_editor_ui_copy.dart';
import '../models/goal.dart';
import '../services/account_local_data_cleaner.dart';
import 'app_time_picker.dart';
import 'surface_components.dart';

class ReminderPlanEditor extends StatelessWidget {
  final ReminderPlan plan;
  final ValueChanged<ReminderPlan> onChanged;
  final String? _customTitle;
  final String? subtitle;
  final bool showHeader;
  final bool allowAlarm;
  final bool allowRelativeToDue;
  final bool allowWeekly;
  final bool allowSnooze;
  final bool hasAnchorDate;
  final int? maxRules;
  final ReminderKind defaultKind;
  final bool showTypeSelector;
  final bool showKindSelector;

  const ReminderPlanEditor({
    super.key,
    required this.plan,
    required this.onChanged,
    String? title,
    this.subtitle,
    this.showHeader = true,
    this.allowAlarm = true,
    this.allowRelativeToDue = true,
    this.allowWeekly = true,
    this.allowSnooze = true,
    this.hasAnchorDate = true,
    this.maxRules,
    this.defaultKind = ReminderKind.push,
    this.showTypeSelector = true,
    this.showKindSelector = true,
  }) : _customTitle = title;

  String get title => _customTitle ?? ReminderEditorUiCopy.defaultPlanTitle;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) {
        final rules = plan.rules;
        final cs = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader) ...[
              _ReminderSwitchTile(
                value: plan.enabled,
                title: title,
                subtitle: subtitle ?? reminderPlanSummary(plan),
                onChanged: _toggleEnabled,
              ),
            ] else
              _ReminderSwitchTile(
                value: plan.enabled,
                title: ReminderEditorUiCopy.enableReminders,
                subtitle: reminderPlanSummary(plan),
                onChanged: _toggleEnabled,
              ),
            if (plan.enabled) ...[
              if (rules.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: DesignTokens.spaceSm,
                  ),
                  child: Text(
                    ReminderEditorUiCopy.noReminders,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.58),
                      fontSize: DesignTokens.fontSizeSm,
                    ),
                  ),
                )
              else
                ...rules.map(
                  (rule) => Padding(
                    padding: const EdgeInsets.only(
                      bottom: DesignTokens.spaceXs,
                    ),
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
                    label: Text(ReminderEditorUiCopy.addReminder),
                  ),
                ),
            ],
          ],
        );
      },
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
    final defaultTime = nextHalfHourTimeOfDay();
    final type = hasAnchorDate && allowRelativeToDue
        ? ReminderRuleType.absolute
        : ReminderRuleType.dailyTime;
    return ReminderRule(
      type: type,
      kind: defaultKind,
      hour: defaultTime.hour,
      minute: defaultTime.minute,
      fullScreen: allowAlarm && defaultKind == ReminderKind.alarm,
      weekdays: type == ReminderRuleType.weeklyTime
          ? [DateTime.now().weekday]
          : const <int>[],
    );
  }

  Future<void> _editRule(BuildContext context, ReminderRule? rule) async {
    if (!context.mounted) return;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    bool isOriginValid() {
      return context.mounted &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          );
    }

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
        showTypeSelector: showTypeSelector,
        showKindSelector: showKindSelector,
        accountGeneration: accountGeneration,
        originValidator: isOriginValid,
      ),
    );
    if (!context.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
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
  if (!plan.enabled) return ReminderEditorUiCopy.planSummaryDisabled;
  final enabledRules = plan.rules.where((r) => r.enabled).toList();
  if (enabledRules.isEmpty) return ReminderEditorUiCopy.planSummaryNoRules;
  if (enabledRules.length == 1) return _ruleSummary(enabledRules.single);
  return ReminderEditorUiCopy.planSummaryCount(enabledRules.length);
}

class _ReminderSwitchTile extends StatelessWidget {
  final bool value;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  const _ReminderSwitchTile({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: DesignTokens.borderRadiusSm,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceXs),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: DesignTokens.fontWeightRegular,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.62),
                        fontSize: DesignTokens.fontSizeSm,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
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
            border: Border.all(
              color: cs.outline.withValues(alpha: 0.18),
              width: 0.45,
            ),
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
                fontWeight: DesignTokens.fontWeightRegular,
              ),
            ),
            subtitle: Text(
              _ruleSummary(rule),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: ReminderEditorUiCopy.delete,
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
  final bool showTypeSelector;
  final bool showKindSelector;
  final int? accountGeneration;
  final bool Function()? originValidator;

  const _ReminderRuleSheet({
    required this.initial,
    required this.allowAlarm,
    required this.allowRelativeToDue,
    required this.allowWeekly,
    required this.allowSnooze,
    required this.hasAnchorDate,
    required this.defaultKind,
    required this.showTypeSelector,
    required this.showKindSelector,
    this.accountGeneration,
    this.originValidator,
  });

  @override
  State<_ReminderRuleSheet> createState() => _ReminderRuleSheetState();
}

class _ReminderRuleSheetState extends State<_ReminderRuleSheet> {
  late int _accountGeneration;
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

  ModalRoute<dynamic>? _ownedRoute;
  NavigatorState? _ownedNavigator;
  bool _pendingDismissal = false;

  bool get _isOriginValid {
    if (!mounted) return false;
    final customValidator = widget.originValidator;
    if (customValidator != null && !customValidator()) {
      return false;
    }
    return AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      _accountGeneration,
    );
  }

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
    _accountGeneration =
        widget.accountGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountGenerationChanged,
    );
    final r = widget.initial;
    _enabled = r?.enabled ?? true;
    _type =
        r?.type ??
        (widget.hasAnchorDate
            ? ReminderRuleType.absolute
            : ReminderRuleType.dailyTime);
    if (!_availableTypes.contains(_type)) {
      _type = _availableTypes.first;
    }
    _kind = widget.showKindSelector && widget.allowAlarm
        ? normalizeUserSelectableReminderKind(r?.kind ?? widget.defaultKind)
        : widget.defaultKind;
    final defaultTime = nextHalfHourTimeOfDay();
    _time = TimeOfDay(
      hour: r?.hour ?? defaultTime.hour,
      minute: r?.minute ?? defaultTime.minute,
    );
    _offsetMinutes = r?.offsetMinutes ?? -30;
    _weekdays = r?.weekdays.isNotEmpty == true
        ? [...r!.weekdays]
        : [DateTime.now().weekday];
    _vibrate = r?.vibrate ?? true;
    _fullScreen = r?.fullScreen ?? _kind == ReminderKind.alarm;
    _snoozeMinutes = r?.snoozeMinutes ?? 0;
    _repeatCount = r?.repeatCount ?? 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextRoute = ModalRoute.of(context);
    if (_ownedRoute != nextRoute) {
      _ownedRoute?.secondaryAnimation?.removeStatusListener(
        _onSecondaryAnimationStatusChanged,
      );
      _ownedRoute = nextRoute;
      _ownedRoute?.secondaryAnimation?.addStatusListener(
        _onSecondaryAnimationStatusChanged,
      );
    }
    _ownedNavigator ??= Navigator.maybeOf(context);
  }

  void _onSecondaryAnimationStatusChanged(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.dismissed && _pendingDismissal) {
      _safeDismissOwnedRoute();
    }
  }

  void _onAccountGenerationChanged() {
    if (!mounted) return;
    if (_isOriginValid) return;
    _handleStaleAccount();
  }

  void _handleStaleAccount() {
    if (!mounted) return;
    _pendingDismissal = true;
    _safeDismissOwnedRoute();
  }

  void _safeDismissOwnedRoute([ReminderRule? result]) {
    if (!mounted) return;
    final route = _ownedRoute;
    final navigator = _ownedNavigator;
    if (route == null || navigator == null || !route.isActive) return;

    if (route.isCurrent) {
      _pendingDismissal = false;
      navigator.pop(result);
    } else {
      _pendingDismissal = true;
    }
  }

  @override
  void dispose() {
    _ownedRoute?.secondaryAnimation?.removeStatusListener(
      _onSecondaryAnimationStatusChanged,
    );
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountGenerationChanged,
    );
    super.dispose();
  }

  void _cancel() {
    if (!mounted) return;
    _safeDismissOwnedRoute();
  }

  void _save() {
    if (!mounted) return;
    if (!_isOriginValid) {
      _safeDismissOwnedRoute();
      return;
    }
    final type = _type;
    final kind = widget.showKindSelector && widget.allowAlarm
        ? _kind
        : widget.defaultKind;
    final rule = ReminderRule(
      id: widget.initial?.id,
      enabled: _enabled,
      type: type,
      kind: kind,
      hour: _time.hour,
      minute: _time.minute,
      offsetMinutes: type == ReminderRuleType.relativeToDue
          ? _offsetMinutes
          : null,
      weekdays: type == ReminderRuleType.weeklyTime ? _weekdays : const <int>[],
      vibrate: _vibrate,
      fullScreen: widget.allowAlarm && kind == ReminderKind.alarm
          ? _fullScreen
          : false,
      snoozeMinutes: _snoozeMinutes,
      repeatCount: _repeatCount,
    );
    _safeDismissOwnedRoute(rule);
  }

  Future<void> _pickTime() async {
    if (!mounted) return;
    if (!_isOriginValid) {
      _safeDismissOwnedRoute();
      return;
    }
    final picked = await AppTimePicker.show(
      context,
      initialTime: _time,
      titleKey: ReminderEditorUiCopy.timePickerTitleKey,
      subtitleKey: ReminderEditorUiCopy.timePickerSubtitleKey,
      minuteStep: 5,
    );
    if (!mounted) return;
    if (!_isOriginValid || _pendingDismissal) {
      _safeDismissOwnedRoute();
      return;
    }
    if (picked != null) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) {
        return AppModalSheet(
          title: widget.initial == null
              ? ReminderEditorUiCopy.addReminder
              : ReminderEditorUiCopy.editReminder,
          actions: [
            TextButton(
              onPressed: _cancel,
              child: Text(ReminderEditorUiCopy.cancel),
            ),
            FilledButton(
              onPressed: _save,
              child: Text(ReminderEditorUiCopy.save),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                title: Text(ReminderEditorUiCopy.enabled),
                onChanged: (v) {
                  if (!mounted) return;
                  if (!_isOriginValid) {
                    _safeDismissOwnedRoute();
                    return;
                  }
                  setState(() {
                    _enabled = v;
                    if (v && _kind == ReminderKind.off) {
                      _kind = widget.defaultKind == ReminderKind.off
                          ? ReminderKind.push
                          : widget.defaultKind;
                    }
                  });
                },
              ),
              if (widget.showTypeSelector) ...[
                AppDropdownField<ReminderRuleType>(
                  initialValue: _type,
                  labelText: ReminderEditorUiCopy.reminderType,
                  isInteractionAllowed: () {
                    if (!mounted) return false;
                    if (!_isOriginValid) {
                      _safeDismissOwnedRoute();
                      return false;
                    }
                    return true;
                  },
                  prefixIcon: const Icon(Icons.tune, size: 20),
                  items: [
                    for (final type in _availableTypes)
                      DropdownMenuItem(
                        value: type,
                        child: ValueListenableBuilder<AppLocale>(
                          valueListenable: I18n.localeListenable,
                          builder: (context, _, _) => Text(_typeLabel(type)),
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (!mounted) return;
                    if (!_isOriginValid) {
                      _safeDismissOwnedRoute();
                      return;
                    }
                    if (v != null) setState(() => _type = v);
                  },
                ),
                const SizedBox(height: DesignTokens.spaceMd),
              ],
              _ReminderTimeField(time: _time, onTap: _pickTime),
              if (_type == ReminderRuleType.relativeToDue) ...[
                const SizedBox(height: DesignTokens.spaceSm),
                Text(
                  ReminderEditorUiCopy.advanceTime,
                  style: _labelStyle(context),
                ),
                const SizedBox(height: DesignTokens.spaceXs),
                Wrap(
                  spacing: DesignTokens.spaceXs,
                  runSpacing: DesignTokens.spaceXs,
                  key: const ValueKey('reminder_relative_offset_presets'),
                  children: ReminderRule.relativeOffsetPresetMinutes.map((
                    minutes,
                  ) {
                    final offset = minutes.abs();
                    final selected = _offsetMinutes == minutes;
                    return ChoiceChip(
                      label: Text(_durationLabel(offset)),
                      selected: selected,
                      selectedColor: _selectedControlColor(context),
                      checkmarkColor: _selectedControlTextColor(context),
                      labelStyle: _selectedChipLabelStyle(context, selected),
                      onSelected: (_) {
                        if (!mounted) return;
                        if (!_isOriginValid) {
                          _safeDismissOwnedRoute();
                          return;
                        }
                        setState(() => _offsetMinutes = minutes);
                      },
                    );
                  }).toList(),
                ),
              ],
              if (_type == ReminderRuleType.weeklyTime) ...[
                const SizedBox(height: DesignTokens.spaceSm),
                Text(ReminderEditorUiCopy.weekly, style: _labelStyle(context)),
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
                      selectedColor: _selectedControlColor(context),
                      checkmarkColor: _selectedControlTextColor(context),
                      labelStyle: _selectedChipLabelStyle(context, selected),
                      showCheckmark: false,
                      onSelected: (_) {
                        if (!mounted) return;
                        if (!_isOriginValid) {
                          _safeDismissOwnedRoute();
                          return;
                        }
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
              if (widget.allowAlarm && widget.showKindSelector) ...[
                Text(
                  ReminderEditorUiCopy.reminderMethod,
                  style: _labelStyle(context),
                ),
                const SizedBox(height: DesignTokens.spaceXs),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<ReminderKind>(
                    style: _selectedSegmentStyle(context),
                    segments: [
                      ButtonSegment(
                        value: ReminderKind.push,
                        label: Text(
                          ReminderEditorUiCopy.ruleKindLabelByName('push'),
                        ),
                        icon: const Icon(Icons.notifications_outlined),
                      ),
                      ButtonSegment(
                        value: ReminderKind.popup,
                        label: Text(
                          ReminderEditorUiCopy.ruleKindLabelByName('popup'),
                        ),
                        icon: const Icon(Icons.open_in_new_outlined),
                      ),
                      ButtonSegment(
                        value: ReminderKind.alarm,
                        label: Text(
                          ReminderEditorUiCopy.ruleKindLabelByName('alarm'),
                        ),
                        icon: const Icon(Icons.alarm_outlined),
                      ),
                      ButtonSegment(
                        value: ReminderKind.off,
                        label: Text(
                          ReminderEditorUiCopy.ruleKindLabelByName('off'),
                        ),
                        icon: const Icon(Icons.notifications_off_outlined),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) {
                      if (!mounted) return;
                      if (!_isOriginValid) {
                        _safeDismissOwnedRoute();
                        return;
                      }
                      setState(() {
                        _kind = s.first;
                        _enabled = _kind != ReminderKind.off;
                      });
                    },
                  ),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _vibrate,
                title: Text(ReminderEditorUiCopy.vibrate),
                onChanged: (v) {
                  if (!mounted) return;
                  if (!_isOriginValid) {
                    _safeDismissOwnedRoute();
                    return;
                  }
                  setState(() => _vibrate = v);
                },
              ),
              if (_kind == ReminderKind.alarm)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _fullScreen,
                  title: Text(ReminderEditorUiCopy.fullScreenReminder),
                  subtitle: Text(
                    ReminderEditorUiCopy.fullScreenReminderSubtitle,
                  ),
                  onChanged: (v) {
                    if (!mounted) return;
                    if (!_isOriginValid) {
                      _safeDismissOwnedRoute();
                      return;
                    }
                    setState(() => _fullScreen = v);
                  },
                ),
              if (widget.allowSnooze) ...[
                const SizedBox(height: DesignTokens.spaceXs),
                Text(ReminderEditorUiCopy.snooze, style: _labelStyle(context)),
                const SizedBox(height: DesignTokens.spaceXs),
                Wrap(
                  spacing: DesignTokens.spaceXs,
                  runSpacing: DesignTokens.spaceXs,
                  key: const ValueKey('reminder_snooze_presets'),
                  children: [0, 5, 10, 15, 30].map((preset) {
                    final selected = _snoozeMinutes == preset;
                    return ChoiceChip(
                      label: Text(
                        ReminderEditorUiCopy.snoozePresetLabel(preset),
                      ),
                      selected: selected,
                      selectedColor: _selectedControlColor(context),
                      checkmarkColor: _selectedControlTextColor(context),
                      labelStyle: _selectedChipLabelStyle(context, selected),
                      onSelected: (_) {
                        if (!mounted) return;
                        if (!_isOriginValid) {
                          _safeDismissOwnedRoute();
                          return;
                        }
                        setState(() => _snoozeMinutes = preset);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: DesignTokens.spaceSm),
                Text(
                  ReminderEditorUiCopy.repeatCount,
                  style: _labelStyle(context),
                ),
                const SizedBox(height: DesignTokens.spaceXs),
                Wrap(
                  spacing: DesignTokens.spaceXs,
                  key: const ValueKey('reminder_repeat_count_presets'),
                  children: [0, 1, 2, 3].map((count) {
                    final selected = _repeatCount == count;
                    return ChoiceChip(
                      label: Text(
                        ReminderEditorUiCopy.repeatCountPresetLabel(count),
                      ),
                      selected: selected,
                      selectedColor: _selectedControlColor(context),
                      checkmarkColor: _selectedControlTextColor(context),
                      labelStyle: _selectedChipLabelStyle(context, selected),
                      onSelected: (_) {
                        if (!mounted) return;
                        if (!_isOriginValid) {
                          _safeDismissOwnedRoute();
                          return;
                        }
                        setState(() => _repeatCount = count);
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReminderTimeField extends StatelessWidget {
  final TimeOfDay time;
  final VoidCallback onTap;

  const _ReminderTimeField({required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final borderColor = cs.outlineVariant.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.16 : 0.22,
    );

    return Semantics(
      key: const ValueKey('reminder_time_compact_field'),
      button: true,
      label: ReminderEditorUiCopy.reminderTimeCompactSemantics(
        _formatTimeOfDay(time),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
              border: Border.all(color: borderColor, width: 0.45),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: DesignTokens.spaceSm),
                  Expanded(
                    child: Text(
                      ReminderEditorUiCopy.reminderTime,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceXs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _formatTimeOfDay(time),
                        maxLines: 1,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _labelStyle(BuildContext context) {
  return TextStyle(
    fontSize: DesignTokens.fontSizeSm,
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.68),
    fontWeight: DesignTokens.fontWeightRegular,
  );
}

ButtonStyle _selectedSegmentStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final selectedBackground = _selectedControlColor(context);
  final selectedForeground = _selectedControlTextColor(context);
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return selectedBackground;
      return null;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return selectedForeground;
      if (states.contains(WidgetState.disabled)) {
        return cs.onSurface.withValues(alpha: 0.38);
      }
      return cs.onSurface;
    }),
    iconColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return selectedForeground;
      if (states.contains(WidgetState.disabled)) {
        return cs.onSurface.withValues(alpha: 0.38);
      }
      return cs.onSurfaceVariant;
    }),
  );
}

Color _selectedControlColor(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  return Color.alphaBlend(
    cs.primary.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.14 : 0.09,
    ),
    cs.surface,
  );
}

Color _selectedControlTextColor(BuildContext context) {
  final theme = Theme.of(context);
  return _readableForeground(
    _selectedControlColor(context),
    theme.colorScheme.onSurface,
  );
}

TextStyle _selectedChipLabelStyle(BuildContext context, bool selected) {
  final cs = Theme.of(context).colorScheme;
  return TextStyle(
    color: selected ? _selectedControlTextColor(context) : cs.onSurface,
  );
}

Color _readableForeground(Color background, Color preferred) {
  final preferredContrast = _contrastRatio(background, preferred);
  final blackContrast = _contrastRatio(background, Colors.black);
  final whiteContrast = _contrastRatio(background, Colors.white);
  if (preferredContrast >= 4.5 ||
      (preferredContrast >= blackContrast &&
          preferredContrast >= whiteContrast)) {
    return preferred;
  }
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

double _contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance() + 0.05;
  final l2 = b.computeLuminance() + 0.05;
  return l1 > l2 ? l1 / l2 : l2 / l1;
}

IconData _ruleIcon(ReminderRule rule) {
  final kind = normalizeUserSelectableReminderKind(rule.kind);
  if (kind == ReminderKind.off) return Icons.notifications_off_outlined;
  if (kind == ReminderKind.alarm) return Icons.alarm_outlined;
  if (kind == ReminderKind.popup) return Icons.open_in_new_outlined;
  return switch (rule.type) {
    ReminderRuleType.absolute => Icons.event_available_outlined,
    ReminderRuleType.relativeToDue => Icons.timelapse_outlined,
    ReminderRuleType.dailyTime => Icons.today_outlined,
    ReminderRuleType.weeklyTime => Icons.calendar_view_week_outlined,
  };
}

String _ruleTitle(ReminderRule rule) {
  final mode = ReminderEditorUiCopy.ruleKindLabelByName(
    normalizeUserSelectableReminderKind(rule.kind).name,
  );
  return ReminderEditorUiCopy.ruleTitle(_typeLabel(rule.type), mode);
}

String _ruleSummary(ReminderRule rule) {
  final pieces = <String>[_formatHm(rule.hour, rule.minute)];
  if (rule.type == ReminderRuleType.relativeToDue) {
    pieces.add(
      ReminderEditorUiCopy.advanceDurationSummary(
        _durationLabel((rule.offsetMinutes ?? 0).abs()),
      ),
    );
  }
  if (rule.type == ReminderRuleType.weeklyTime && rule.weekdays.isNotEmpty) {
    pieces.add(rule.weekdays.map(_weekdayLabel).join('/'));
  }
  if (rule.snoozeMinutes > 0) {
    pieces.add(ReminderEditorUiCopy.snoozeSummary(rule.snoozeMinutes));
  }
  if (rule.repeatCount > 0) {
    pieces.add(ReminderEditorUiCopy.repeatCountSummary(rule.repeatCount));
  }
  if (!rule.enabled) pieces.add(ReminderEditorUiCopy.disabledSummary);
  return pieces.join(' · ');
}

String _typeLabel(ReminderRuleType type) =>
    ReminderEditorUiCopy.ruleTypeLabelByName(type.name);

String _formatHm(int? hour, int? minute) {
  if (hour == null || minute == null) return ReminderEditorUiCopy.timeNotSet;
  return I18nDateFormat.timeOfDay(hour: hour, minute: minute);
}

String _formatTimeOfDay(TimeOfDay time) {
  return I18nDateFormat.timeOfDay(hour: time.hour, minute: time.minute);
}

TimeOfDay nextHalfHourTimeOfDay([DateTime? from]) {
  final now = from ?? DateTime.now();
  if (now.minute < 30) {
    return TimeOfDay(hour: now.hour, minute: 30);
  }
  return TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
}

String _durationLabel(int minutes) =>
    ReminderEditorUiCopy.durationLabel(minutes);

String _weekdayLabel(int day) => ReminderEditorUiCopy.weekdayLabel(day);

List<String> get _weekdayNames => ReminderEditorUiCopy.weekdayNamesShort;
