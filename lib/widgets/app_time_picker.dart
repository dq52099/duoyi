import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import 'surface_components.dart';

class AppTimePicker {
  AppTimePicker._();

  static Future<TimeOfDay?> show(
    BuildContext context, {
    required TimeOfDay initialTime,
    String? title,
    String? subtitle,
    String? titleKey,
    String? subtitleKey,
    int minuteStep = 5,
  }) {
    return showAppModalSheet<TimeOfDay>(
      context: context,
      builder: (_) => _AppTimePickerSheet(
        initialTime: initialTime,
        title: title,
        subtitle: subtitle,
        titleKey: titleKey,
        subtitleKey: subtitleKey,
        minuteStep: minuteStep,
      ),
    );
  }

  static String format(TimeOfDay time) {
    return I18nDateFormat.timeOfDay(hour: time.hour, minute: time.minute);
  }

  static TimeOfDay nextHalfHour([DateTime? from]) {
    final now = from ?? DateTime.now();
    if (now.minute < 30) return TimeOfDay(hour: now.hour, minute: 30);
    return TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
  }
}

class _AppTimePickerSheet extends StatefulWidget {
  final TimeOfDay initialTime;
  final String? title;
  final String? subtitle;
  final String? titleKey;
  final String? subtitleKey;
  final int minuteStep;

  const _AppTimePickerSheet({
    required this.initialTime,
    this.title,
    this.subtitle,
    this.titleKey,
    this.subtitleKey,
    required this.minuteStep,
  });

  @override
  State<_AppTimePickerSheet> createState() => _AppTimePickerSheetState();
}

class _AppTimePickerSheetState extends State<_AppTimePickerSheet> {
  late int _hour;
  late int _minute;
  late List<int> _minutes;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    final step = _normalizedStep(widget.minuteStep);
    _minutes = [for (var m = 0; m < 60; m += step) m];
    final rounded = _roundedTime(widget.initialTime);
    _hour = rounded.hour;
    _minute = rounded.minute;
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(
      initialItem: _minutes.indexOf(_minute).clamp(0, _minutes.length - 1),
    );
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  int _normalizedStep(int step) {
    if (step <= 0 || 60 % step != 0) return 5;
    return step;
  }

  TimeOfDay _roundedTime(TimeOfDay time) {
    final step = _normalizedStep(widget.minuteStep);
    final rounded = ((time.minute + step - 1) ~/ step * step)
        .clamp(0, 60)
        .toInt();
    if (rounded == 60) {
      return TimeOfDay(hour: (time.hour + 1) % 24, minute: 0);
    }
    return TimeOfDay(hour: time.hour, minute: rounded);
  }

  TimeOfDay get _value => TimeOfDay(hour: _hour, minute: _minute);

  void _setValue(TimeOfDay value) {
    final rounded = _roundedTime(value);
    setState(() {
      _hour = rounded.hour;
      _minute = rounded.minute;
    });
    _hourController.animateToItem(
      _hour,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    _minuteController.animateToItem(
      _minutes.indexOf(_minute).clamp(0, _minutes.length - 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _shiftMinutes(int delta) {
    final total = (_hour * 60 + _minute + delta) % (24 * 60);
    final normalized = total < 0 ? total + 24 * 60 : total;
    _setValue(TimeOfDay(hour: normalized ~/ 60, minute: normalized % 60));
  }

  String _resolveTitle() {
    if (widget.titleKey != null) return I18n.tr(widget.titleKey!);
    if (widget.title != null) return widget.title!;
    return I18n.tr('picker.time.title');
  }

  String? _resolveSubtitle() {
    if (widget.subtitleKey != null) return I18n.tr(widget.subtitleKey!);
    return widget.subtitle;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppModalSheet(
      title: _resolveTitle(),
      subtitle: _resolveSubtitle(),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _value),
          child: Text(I18n.tr('action.confirm')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            label: AppTimePicker.format(_value),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.42),
                borderRadius: DesignTokens.borderRadiusLg,
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.12),
                  width: 0.45,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                AppTimePicker.format(_value),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.normal,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: cs.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shiftMinutes(-30),
                  icon: const Icon(Icons.keyboard_arrow_left_rounded),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(I18n.tr('picker.time.earlier_30m')),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shiftMinutes(30),
                  icon: const Icon(Icons.keyboard_arrow_right_rounded),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(I18n.tr('picker.time.later_30m')),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PresetChip(
                label: I18n.tr('picker.time.preset_morning'),
                onTap: () => _setValue(const TimeOfDay(hour: 9, minute: 0)),
              ),
              _PresetChip(
                label: I18n.tr('picker.time.preset_noon'),
                onTap: () => _setValue(const TimeOfDay(hour: 12, minute: 0)),
              ),
              _PresetChip(
                label: I18n.tr('picker.time.preset_evening'),
                onTap: () => _setValue(const TimeOfDay(hour: 20, minute: 0)),
              ),
              _PresetChip(
                label: I18n.tr('picker.time.preset_now'),
                onTap: () => _setValue(TimeOfDay.now()),
              ),
              _PresetChip(
                label: I18n.tr('picker.time.preset_next_slot'),
                onTap: () => _setValue(AppTimePicker.nextHalfHour()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            height: 190,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.32),
              borderRadius: DesignTokens.borderRadiusLg,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _Wheel(
                    controller: _hourController,
                    count: 24,
                    labelBuilder: (i) => i.toString().padLeft(2, '0'),
                    onSelectedItemChanged: (i) => setState(() => _hour = i),
                  ),
                ),
                Text(
                  ':',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                Expanded(
                  child: _Wheel(
                    controller: _minuteController,
                    count: _minutes.length,
                    labelBuilder: (i) => _minutes[i].toString().padLeft(2, '0'),
                    onSelectedItemChanged: (i) =>
                        setState(() => _minute = _minutes[i]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.schedule, size: 16),
      onPressed: onTap,
    );
  }
}

class _Wheel extends StatelessWidget {
  final FixedExtentScrollController controller;
  final int count;
  final String Function(int index) labelBuilder;
  final ValueChanged<int> onSelectedItemChanged;

  const _Wheel({
    required this.controller,
    required this.count,
    required this.labelBuilder,
    required this.onSelectedItemChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 44,
      physics: const FixedExtentScrollPhysics(),
      perspective: 0.003,
      overAndUnderCenterOpacity: 0.42,
      onSelectedItemChanged: onSelectedItemChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, index) {
          final text = labelBuilder(index);
          return Semantics(
            label: text,
            child: Center(
              child: Text(
                text,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: cs.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
