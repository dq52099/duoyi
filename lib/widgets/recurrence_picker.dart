import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/reminder_editor_ui_copy.dart';
import '../models/recurrence.dart';
import '../services/account_local_data_cleaner.dart';
import 'app_date_picker.dart';
import 'surface_components.dart';

/// 重复规则编辑弹出层。
class RecurrencePicker extends StatefulWidget {
  final RecurrenceRule initial;
  final bool supportMaxOccurrences;
  final int? accountGeneration;

  /// Optional predicate defining whether the originating caller scope remains valid.
  ///
  /// When embedding [RecurrencePicker] directly into a view hierarchy rather than
  /// opening it via [RecurrencePicker.show], callers may supply this predicate to
  /// coordinate embedded lifetime and account validity with [AccountLocalDataCleaner].
  /// If omitted, the state falls back to checking its own mounting and
  /// [AccountLocalDataCleaner.isCurrentAccountDataGeneration].
  final bool Function()? originValidator;

  const RecurrencePicker({
    super.key,
    required this.initial,
    this.supportMaxOccurrences = true,
    this.accountGeneration,
    this.originValidator,
  });

  static Future<RecurrenceRule?> show(
    BuildContext context, {
    required RecurrenceRule initial,
    bool supportMaxOccurrences = true,
  }) async {
    if (!context.mounted) return null;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    bool isOriginValid() {
      return context.mounted &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          );
    }

    final result = await showAppModalSheet<RecurrenceRule>(
      context: context,
      builder: (_) => RecurrencePicker(
        initial: initial,
        supportMaxOccurrences: supportMaxOccurrences,
        accountGeneration: accountGeneration,
        originValidator: isOriginValid,
      ),
    );
    if (!context.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return null;
    }
    return result;
  }

  @override
  State<RecurrencePicker> createState() => _RecurrencePickerState();
}

class _RecurrencePickerState extends State<RecurrencePicker> {
  late int _accountGeneration;
  late RecurrenceFrequency _freq;
  late int _interval;
  late List<int> _weekdays;
  late final TextEditingController _intervalCtrl;
  late final TextEditingController _byMonthDayCtrl;
  late final TextEditingController _maxOccurrencesCtrl;
  int? _byMonthDay;
  DateTime? _endDate;
  int? _maxOccurrences;

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

  @override
  void initState() {
    super.initState();
    _accountGeneration =
        widget.accountGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountGenerationChanged,
    );
    _freq = widget.initial.frequency;
    _interval = widget.initial.interval;
    _weekdays = [...?widget.initial.byWeekdays];
    _intervalCtrl = TextEditingController(text: '$_interval');
    _byMonthDay = widget.initial.byMonthDay;
    _byMonthDayCtrl = TextEditingController(
      text: _byMonthDay?.toString() ?? '',
    );
    _maxOccurrences = widget.initial.maxOccurrences;
    _maxOccurrencesCtrl = TextEditingController(
      text: _maxOccurrences?.toString() ?? '',
    );
    _endDate = widget.initial.endDate;
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

  void _safeDismissOwnedRoute([RecurrenceRule? result]) {
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
    _intervalCtrl.dispose();
    _byMonthDayCtrl.dispose();
    _maxOccurrencesCtrl.dispose();
    super.dispose();
  }

  void _cancel() {
    if (!mounted) return;
    _safeDismissOwnedRoute();
  }

  void _clear() {
    if (!mounted) return;
    if (!_isOriginValid) {
      _safeDismissOwnedRoute();
      return;
    }
    _safeDismissOwnedRoute(const RecurrenceRule());
  }

  void _save() {
    if (!mounted) return;
    if (!_isOriginValid) {
      _safeDismissOwnedRoute();
      return;
    }
    final rule = RecurrenceRule(
      frequency: _freq,
      interval: _interval < 1 ? 1 : _interval,
      byWeekdays: _freq == RecurrenceFrequency.weekly && _weekdays.isNotEmpty
          ? [..._weekdays]
          : null,
      byMonthDay: _freq == RecurrenceFrequency.monthly ? _byMonthDay : null,
      endDate: _endDate,
      maxOccurrences:
          _freq == RecurrenceFrequency.none || !widget.supportMaxOccurrences
          ? null
          : _maxOccurrences,
    );
    _safeDismissOwnedRoute(rule);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) {
        final cs = Theme.of(context).colorScheme;
        final controlText = appSecondaryControlTextStyle(context);
        final labelText = appSecondaryControlLabelStyle(context);
        final weekdayNames = ReminderEditorUiCopy.weekdayNamesShort;
        return AppModalSheet(
          title: ReminderEditorUiCopy.recurrenceTitle,
          subtitle: widget.supportMaxOccurrences
              ? ReminderEditorUiCopy.recurrenceSubtitleWithMax
              : ReminderEditorUiCopy.recurrenceSubtitleWithoutMax,
          leadingActions: [
            TextButton(
              onPressed: _clear,
              child: Text(ReminderEditorUiCopy.clear),
            ),
          ],
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
          child: AppSecondaryControlTheme(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in RecurrenceFrequency.values)
                      ChoiceChip(
                        label: Text(
                          ReminderEditorUiCopy.recurrenceFrequencyLabel(
                            f.index,
                          ),
                        ),
                        selected: _freq == f,
                        labelStyle: controlText,
                        onSelected: (_) {
                          if (!mounted) return;
                          if (!_isOriginValid) {
                            _safeDismissOwnedRoute();
                            return;
                          }
                          setState(() => _freq = f);
                        },
                      ),
                  ],
                ),
                if (_freq != RecurrenceFrequency.none) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        ReminderEditorUiCopy.intervalPrefix,
                        style: controlText,
                      ),
                      SizedBox(
                        width: 72,
                        child: TextField(
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          controller: _intervalCtrl,
                          style: controlText,
                          decoration: const InputDecoration(isDense: true),
                          onChanged: (v) {
                            if (!mounted) return;
                            if (!_isOriginValid) {
                              _safeDismissOwnedRoute();
                              return;
                            }
                            final n = int.tryParse(v);
                            if (n != null && n > 0) {
                              setState(() => _interval = n);
                            }
                          },
                        ),
                      ),
                      Text(
                        ' ${ReminderEditorUiCopy.intervalUnitLabel(_freq.index, _interval)}',
                        style: controlText,
                      ),
                    ],
                  ),
                ],
                if (_freq == RecurrenceFrequency.weekly) ...[
                  const SizedBox(height: 12),
                  Text(
                    ReminderEditorUiCopy.weeklyDaysLabel,
                    style: labelText.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: List.generate(7, (i) {
                      final selected = _weekdays.contains(i);
                      return FilterChip(
                        label: Text(weekdayNames[i]),
                        selected: selected,
                        showCheckmark: false,
                        labelStyle: controlText,
                        onSelected: (_) {
                          if (!mounted) return;
                          if (!_isOriginValid) {
                            _safeDismissOwnedRoute();
                            return;
                          }
                          setState(() {
                            if (selected) {
                              _weekdays.remove(i);
                            } else {
                              _weekdays.add(i);
                            }
                          });
                        },
                      );
                    }),
                  ),
                ],
                if (_freq == RecurrenceFrequency.monthly) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        ReminderEditorUiCopy.monthlyDayPrefix,
                        style: controlText,
                      ),
                      SizedBox(
                        width: 72,
                        child: TextField(
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          controller: _byMonthDayCtrl,
                          style: controlText,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: ReminderEditorUiCopy.monthlyDayHint,
                          ),
                          onChanged: (v) {
                            if (!mounted) return;
                            if (!_isOriginValid) {
                              _safeDismissOwnedRoute();
                              return;
                            }
                            setState(() {
                              final n = int.tryParse(v);
                              if (n != null && n >= 1 && n <= 31) {
                                _byMonthDay = n;
                              }
                              if (v.isEmpty) _byMonthDay = null;
                            });
                          },
                        ),
                      ),
                      if (ReminderEditorUiCopy.monthlyDaySuffix.isNotEmpty)
                        Text(
                          ReminderEditorUiCopy.monthlyDaySuffix,
                          style: controlText,
                        ),
                    ],
                  ),
                ],
                if (_freq != RecurrenceFrequency.none) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.event_busy, size: 18),
                    title: Text(ReminderEditorUiCopy.endDateTileTitle),
                    subtitle: Text(
                      _endDate == null
                          ? ReminderEditorUiCopy.endDateNever
                          : I18nDateFormat.date(_endDate!),
                    ),
                    trailing: _endDate == null
                        ? const Icon(Icons.chevron_right)
                        : IconButton(
                            tooltip: ReminderEditorUiCopy.clearEndDateTooltip,
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              if (!mounted) return;
                              if (!_isOriginValid) {
                                _safeDismissOwnedRoute();
                                return;
                              }
                              setState(() => _endDate = null);
                            },
                          ),
                    onTap: () async {
                      if (!mounted) return;
                      if (!_isOriginValid) {
                        _safeDismissOwnedRoute();
                        return;
                      }
                      final picked = await AppDatePicker.pickSolar(
                        context,
                        initialDate:
                            _endDate ??
                            DateTime.now().add(const Duration(days: 90)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2099, 12, 31),
                        titleKey: ReminderEditorUiCopy.datePickerTitleKey,
                      );
                      if (!mounted) return;
                      if (!_isOriginValid || _pendingDismissal) {
                        _safeDismissOwnedRoute();
                        return;
                      }
                      if (picked != null) setState(() => _endDate = picked);
                    },
                  ),
                  if (widget.supportMaxOccurrences) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.repeat_one, size: 18),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _maxOccurrencesCtrl,
                            keyboardType: TextInputType.number,
                            style: controlText,
                            decoration: InputDecoration(
                              labelText:
                                  ReminderEditorUiCopy.maxOccurrencesLabel,
                              helperText:
                                  ReminderEditorUiCopy.maxOccurrencesHelper,
                            ),
                            onChanged: (v) {
                              if (!mounted) return;
                              if (!_isOriginValid) {
                                _safeDismissOwnedRoute();
                                return;
                              }
                              final text = v.trim();
                              final n = int.tryParse(text);
                              setState(() {
                                _maxOccurrences =
                                    text.isEmpty || n == null || n < 1
                                    ? null
                                    : n;
                              });
                            },
                          ),
                        ),
                        if (_maxOccurrences != null)
                          IconButton(
                            tooltip:
                                ReminderEditorUiCopy.clearMaxOccurrencesTooltip,
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              if (!mounted) return;
                              if (!_isOriginValid) {
                                _safeDismissOwnedRoute();
                                return;
                              }
                              setState(() {
                                _maxOccurrences = null;
                                _maxOccurrencesCtrl.clear();
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
