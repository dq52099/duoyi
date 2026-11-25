import '../core/date_item_ui_copy.dart';
import '../services/date_item_action_origin.dart';
import 'date_item_feedback.dart';
import 'app_date_format.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/calendar_event_display_text.dart';
import '../core/calendar_event_sheet_ui_copy.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/iterable_extensions.dart';
import '../models/calendar_event.dart';
import '../models/habit.dart';
import '../models/todo.dart';
import '../providers/anniversary_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/course_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/share_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../screens/anniversary_screen.dart';
import '../screens/countdown_screen.dart';
import '../screens/course_schedule_screen.dart';
import '../screens/diary_screen.dart';
import '../screens/habit_detail_screen.dart';
import '../screens/pomodoro_screen.dart';
import '../screens/time_audit_screen.dart';
import '../screens/today_detail_router.dart';
import '../services/account_local_data_cleaner.dart';
import '../widgets/brand_background.dart';
import '../widgets/todo_completion_flow.dart';
import 'app_date_picker.dart';
import 'app_time_picker.dart';
import 'controller_dialog.dart' show createControllerDialogRoute;
import 'surface_components.dart';

bool _canEditWorkspace(BuildContext context, String? workspaceId) {
  if (workspaceId == null || workspaceId.isEmpty || workspaceId == 'private') {
    return true;
  }
  final share = Provider.of<ShareProvider?>(context, listen: false);
  return share?.canEdit(workspaceId) ?? false;
}

Future<void> showCalendarEventSheet(BuildContext context, CalendarEvent event) {
  final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
  return showAppModalSheet<void>(
    context: context,
    builder: (_) =>
        CalendarEventSheet(event: event, accountGeneration: accountGeneration),
  );
}

class _LocalEventEditorDraft {
  final String title;
  final String note;
  final DateTime startDate;
  final DateTime endDate;
  final bool allDay;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final Color color;
  final int? reminderMinutes;

  const _LocalEventEditorDraft({
    required this.title,
    required this.note,
    required this.startDate,
    required this.endDate,
    required this.allDay,
    required this.startTime,
    required this.endTime,
    required this.color,
    this.reminderMinutes,
  });
}

const List<int?> _localEventReminderOptions = <int?>[null, 0, 5, 15, 30, 60];

String _localEventReminderLabel(int? minutes) {
  final isEn = I18n.current == AppLocale.en;
  if (minutes == null) return isEn ? 'No reminder' : '不提醒';
  if (minutes == 0) return isEn ? 'At time' : '准时';
  if (minutes == 60) return isEn ? '1 hour before' : '提前 60 分钟';
  return isEn ? '$minutes min before' : '提前 $minutes 分钟';
}

class _LocalEventEditorDialog extends StatefulWidget {
  final CalendarEvent? event;
  final DateTime initialDate;
  final int accountGeneration;

  const _LocalEventEditorDialog({
    required this.event,
    required this.initialDate,
    required this.accountGeneration,
  });

  @override
  State<_LocalEventEditorDialog> createState() =>
      _LocalEventEditorDialogState();
}

class _LocalEventEditorDialogState extends State<_LocalEventEditorDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _noteCtrl;
  late DateTime _startDate;
  late DateTime _endDate;
  late bool _allDay;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late Color _color;
  late int? _reminderMinutes;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _titleCtrl = TextEditingController(text: event?.title ?? '');
    _noteCtrl = TextEditingController(text: event?.note ?? '');
    _startDate = _dateOnly(widget.initialDate);
    _endDate = _localEventInclusiveEndDate(event) ?? _startDate;
    _allDay = event?.time == null;
    _startTime = event?.time ?? const TimeOfDay(hour: 9, minute: 0);
    _endTime = event?.endDate == null
        ? const TimeOfDay(hour: 10, minute: 0)
        : TimeOfDay.fromDateTime(event!.endDate!);
    _color = event?.color ?? const Color(0xFF5B6EE1);
    _reminderMinutes = event?.reminderMinutes;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _onSave() {
    if (!mounted) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route != null && (!route.isCurrent || !route.isActive)) {
      return;
    }
    Navigator.pop(
      context,
      _LocalEventEditorDraft(
        title: title,
        note: _noteCtrl.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        allDay: _allDay,
        startTime: _startTime,
        endTime: _endTime,
        color: _color,
        reminderMinutes: _reminderMinutes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final allDay = _allDay;
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => AppDialog(
        title: Text(
          CalendarEventSheetUiCopy.editorTitle(isEditing: event != null),
        ),
        content: AppSecondaryControlTheme(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: CalendarEventSheetUiCopy.eventTitleLabel,
                    prefixIcon: const Icon(Icons.event_note_outlined),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.today_outlined),
                  title: Text(CalendarEventSheetUiCopy.allDay),
                  subtitle: Text(CalendarEventSheetUiCopy.allDaySubtitle),
                  value: _allDay,
                  onChanged: (value) => setState(() => _allDay = value),
                ),
                _DatePickTile(
                  icon: Icons.event_available_outlined,
                  title: CalendarEventSheetUiCopy.startDate,
                  value: _startDate,
                  onTap: () async {
                    final picked = await AppDatePicker.pickSolar(
                      context,
                      initialDate: _startDate,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                      title: CalendarEventSheetUiCopy.startDate,
                      titleKey: 'calendar.picker.start_date',
                    );
                    if (picked == null ||
                        !mounted ||
                        !context.mounted ||
                        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                          widget.accountGeneration,
                        )) {
                      return;
                    }
                    setState(() {
                      _startDate = _dateOnly(picked);
                      if (_endDate.isBefore(_startDate)) {
                        _endDate = _startDate;
                      }
                    });
                  },
                ),
                _DatePickTile(
                  icon: Icons.event_busy_outlined,
                  title: CalendarEventSheetUiCopy.endDate,
                  value: _endDate,
                  onTap: () async {
                    final picked = await AppDatePicker.pickSolar(
                      context,
                      initialDate: _endDate,
                      firstDate: _startDate,
                      lastDate: DateTime(2100),
                      title: CalendarEventSheetUiCopy.endDate,
                      titleKey: 'calendar.picker.end_date',
                    );
                    if (picked == null ||
                        !mounted ||
                        !context.mounted ||
                        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                          widget.accountGeneration,
                        )) {
                      return;
                    }
                    setState(() => _endDate = _dateOnly(picked));
                  },
                ),
                if (!allDay) ...[
                  _TimePickTile(
                    icon: Icons.schedule_outlined,
                    title: CalendarEventSheetUiCopy.startTime,
                    value: _startTime,
                    onTap: () async {
                      final picked = await AppTimePicker.show(
                        context,
                        initialTime: _startTime,
                        title: CalendarEventSheetUiCopy.startTime,
                        titleKey: 'calendar.picker.start_time',
                        minuteStep: 5,
                      );
                      if (picked == null ||
                          !mounted ||
                          !context.mounted ||
                          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                            widget.accountGeneration,
                          )) {
                        return;
                      }
                      setState(() => _startTime = picked);
                    },
                  ),
                  _TimePickTile(
                    icon: Icons.timelapse_outlined,
                    title: CalendarEventSheetUiCopy.endTime,
                    value: _endTime,
                    onTap: () async {
                      final picked = await AppTimePicker.show(
                        context,
                        initialTime: _endTime,
                        title: CalendarEventSheetUiCopy.endTime,
                        titleKey: 'calendar.picker.end_time',
                        minuteStep: 5,
                      );
                      if (picked == null ||
                          !mounted ||
                          !context.mounted ||
                          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                            widget.accountGeneration,
                          )) {
                        return;
                      }
                      setState(() => _endTime = picked);
                    },
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in _localEventColors)
                        _ColorChoice(
                          color: option,
                          selected: _color == option,
                          onTap: () => setState(() => _color = option),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteCtrl,
                  decoration: InputDecoration(
                    labelText: CalendarEventSheetUiCopy.noteLabel,
                    prefixIcon: const Icon(Icons.notes_outlined),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        I18n.current == AppLocale.en ? 'Reminder' : '提醒时间',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final option in _localEventReminderOptions)
                            ChoiceChip(
                              label: Text(_localEventReminderLabel(option)),
                              selected: _reminderMinutes == option,
                              onSelected: (selected) {
                                if (!selected) return;
                                setState(() => _reminderMinutes = option);
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (!mounted) return;
              final route = ModalRoute.of(context);
              if (route != null && (!route.isCurrent || !route.isActive)) {
                return;
              }
              Navigator.pop(context, null);
            },
            child: Text(CalendarEventSheetUiCopy.cancel),
          ),
          FilledButton(
            onPressed: _onSave,
            child: Text(CalendarEventSheetUiCopy.save),
          ),
        ],
      ),
    );
  }
}

Future<void> showLocalCalendarEventEditor(
  BuildContext context, {
  DateTime? initialDate,
  CalendarEvent? event,
  String? workspaceId,
}) async {
  final effectiveWorkspaceId = workspaceId ?? event?.workspaceId;
  if (!_canEditWorkspace(context, effectiveWorkspaceId)) {
    return;
  }
  final provider = context.read<CalendarProvider>();
  final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
  final defaultDate = initialDate ?? event?.date ?? DateTime.now();

  final route = createControllerDialogRoute<_LocalEventEditorDraft>(
    context: context,
    builder: (dialogContext) => _LocalEventEditorDialog(
      event: event,
      initialDate: defaultDate,
      accountGeneration: accountGeneration,
    ),
  );
  final draft = await Navigator.of(context, rootNavigator: true).push<_LocalEventEditorDraft>(
    route,
  );

  if (draft == null ||
      !context.mounted ||
      !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        accountGeneration,
      ) ||
      !_canEditWorkspace(context, effectiveWorkspaceId)) {
    return;
  }
  final title = draft.title;
  if (title.isEmpty) return;

  final normalized = _normalizeLocalEventTime(
    startDate: draft.startDate,
    endDate: draft.endDate,
    allDay: draft.allDay,
    startTime: draft.startTime,
    endTime: draft.endTime,
  );
  final next = CalendarEvent(
    id: event?.id ?? '',
    title: title,
    date: normalized.start,
    endDate: normalized.end,
    type: CalendarEventType.event,
    color: draft.color,
    sourceId: event?.sourceId,
    subtitle: draft.note.isEmpty ? null : draft.note,
    workspaceId: effectiveWorkspaceId,
    time: draft.allDay ? null : draft.startTime,
    note: draft.note.isEmpty ? null : draft.note,
    updatedAt: DateTime.now(),
    reminderMinutes: draft.reminderMinutes,
  );

  if (!context.mounted ||
      !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        accountGeneration,
      ) ||
      !_canEditWorkspace(context, effectiveWorkspaceId)) {
    return;
  }

  try {
    if (event == null) {
      await provider.addLocalEvent(next);
    } else {
      await provider.updateLocalEvent(next);
    }
  } catch (e) {
    if (context.mounted &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${CalendarEventSheetUiCopy.saveFailed}: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

class CalendarEventSheet extends StatefulWidget {
  final CalendarEvent event;
  final int? accountGeneration;

  const CalendarEventSheet({
    super.key,
    required this.event,
    this.accountGeneration,
  });

  @override
  State<CalendarEventSheet> createState() => _CalendarEventSheetState();
}

class _CalendarEventSheetState extends State<CalendarEventSheet>
    with DateItemMutationState<CalendarEventSheet> {
  DateItemActionOrigin? _dateOrigin;
  bool _datePicking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dateOrigin ??= switch (widget.event.type) {
      CalendarEventType.countdown => DateItemActionOrigin.countdown(context),
      CalendarEventType.anniversary => DateItemActionOrigin.anniversary(
        context,
      ),
      _ => null,
    };
  }

  late final int _originAccountGeneration;

  @override
  void initState() {
    super.initState();
    _originAccountGeneration =
        widget.accountGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountDataGenerationChanged,
    );
  }

  @override
  void dispose() {
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountDataGenerationChanged,
    );
    super.dispose();
  }

  void _onAccountDataGenerationChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _canEditEvent(BuildContext context) =>
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        _originAccountGeneration,
      ) &&
      _canEditWorkspace(context, widget.event.workspaceId);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) {
        final cs = Theme.of(context).colorScheme;
        final displayTitle = CalendarEventDisplayText.resolveTitle(
          widget.event,
        );
        final displaySubtitle = CalendarEventDisplayText.resolveSubtitle(
          widget.event,
        );
        return AppModalSheet(
          title: displayTitle,
          maxWidth: 860,
          scrollable: false,
          child: Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: icon + type tag + time + conflict warning
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: widget.event.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _icon(widget.event.type),
                        color: widget.event.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppStatusBadge(
                            label: widget.event.type.label,
                            color: widget.event.color,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _timeText(widget.event),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.event.hasConflict)
                      Tooltip(
                        message: CalendarEventSheetUiCopy.conflictWarning(
                          widget.event.conflictCount,
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: cs.error,
                          size: 20,
                        ),
                      ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('calendar_event_detail_scroll_region'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (displaySubtitle != null &&
                            displaySubtitle.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            displaySubtitle,
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.68),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Type-specific action buttons
                dateItemStatus(
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _buildActions(context),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build action buttons based on event type.
  List<Widget> _buildActions(BuildContext context) {
    final canEdit = _canEditEvent(context) && !dateItemBusy && !_datePicking;
    switch (widget.event.type) {
      case CalendarEventType.event:
        return [
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: CalendarEventSheetUiCopy.actionEdit,
            onPressed: canEdit ? () => _editLocalEvent(context) : null,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: CalendarEventSheetUiCopy.actionDelete,
            onPressed: canEdit ? () => _delete(context) : null,
            tonal: true,
          ),
        ];
      case CalendarEventType.todo:
        return [
          if (!widget.event.isCompleted)
            _actionButton(
              context,
              icon: Icons.done,
              label: CalendarEventSheetUiCopy.actionComplete,
              onPressed: canEdit ? () => _completeTodo(context) : null,
            ),
          _actionButton(
            context,
            icon: Icons.event_repeat,
            label: CalendarEventSheetUiCopy.actionReschedule,
            onPressed: canEdit ? () => _reschedule(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.schedule_outlined,
            label: CalendarEventSheetUiCopy.actionAdjustTime,
            onPressed: canEdit ? () => _adjustTodoTime(context) : null,
          ),
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: CalendarEventSheetUiCopy.actionEdit,
            onPressed: canEdit ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: CalendarEventSheetUiCopy.actionOpenDetail,
            onPressed: widget.event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: CalendarEventSheetUiCopy.actionDelete,
            onPressed: canEdit ? () => _delete(context) : null,
            tonal: true,
          ),
        ];
      case CalendarEventType.habit:
        final habit = widget.event.sourceId == null
            ? null
            : context
                  .read<HabitProvider>()
                  .habits
                  .where((h) => h.id == widget.event.sourceId)
                  .firstOrNull;
        final isNegative = habit?.kind == HabitKind.negative;
        return [
          if (!widget.event.isCompleted)
            _actionButton(
              context,
              icon: isNegative ? Icons.add_circle_outline : Icons.check,
              label: isNegative
                  ? CalendarEventSheetUiCopy.actionLogOnce
                  : CalendarEventSheetUiCopy.actionCheckIn,
              onPressed: canEdit ? () => _checkInHabit(context) : null,
            ),
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: CalendarEventSheetUiCopy.actionEdit,
            onPressed: canEdit ? () => _editSourceEvent(context) : null,
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: CalendarEventSheetUiCopy.actionOpenDetail,
            onPressed: widget.event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: CalendarEventSheetUiCopy.actionDelete,
            onPressed: canEdit ? () => _delete(context) : null,
            tonal: true,
          ),
        ];
      case CalendarEventType.pomodoro:
        return [
          _actionButton(
            context,
            icon: Icons.play_arrow,
            label: CalendarEventSheetUiCopy.actionStartFocus,
            onPressed: () => _startFocus(context),
          ),
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: CalendarEventSheetUiCopy.actionEdit,
            onPressed: canEdit ? () => _editSourceEvent(context) : null,
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: CalendarEventSheetUiCopy.actionOpenDetail,
            onPressed: widget.event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: CalendarEventSheetUiCopy.actionDelete,
            onPressed: canEdit ? () => _delete(context) : null,
            tonal: true,
          ),
        ];
      case CalendarEventType.goal:
        return [
          _actionButton(
            context,
            icon: Icons.event_repeat,
            label: CalendarEventSheetUiCopy.actionReschedule,
            onPressed: canEdit ? () => _reschedule(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: CalendarEventSheetUiCopy.actionOpenDetail,
            onPressed: widget.event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: CalendarEventSheetUiCopy.actionDelete,
            onPressed: canEdit ? () => _delete(context) : null,
            tonal: true,
          ),
        ];
      case CalendarEventType.course:
        return [
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: CalendarEventSheetUiCopy.actionEdit,
            onPressed: canEdit ? () => _editSourceEvent(context) : null,
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: CalendarEventSheetUiCopy.actionOpenDetail,
            onPressed: widget.event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: CalendarEventSheetUiCopy.actionDelete,
            onPressed: canEdit ? () => _delete(context) : null,
            tonal: true,
          ),
        ];
      case CalendarEventType.anniversary:
        return [
          _actionButton(
            context,
            icon: Icons.event_repeat,
            label: CalendarEventSheetUiCopy.actionReschedule,
            onPressed: canEdit ? () => _reschedule(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: CalendarEventSheetUiCopy.actionEdit,
            onPressed: canEdit ? () => _editSourceEvent(context) : null,
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: CalendarEventSheetUiCopy.actionOpenDetail,
            onPressed: widget.event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: CalendarEventSheetUiCopy.actionDelete,
            onPressed: canEdit ? () => _delete(context) : null,
            tonal: true,
          ),
        ];
      case CalendarEventType.countdown:
        return [
          _actionButton(
            context,
            icon: Icons.event_repeat,
            label: CalendarEventSheetUiCopy.actionReschedule,
            onPressed: canEdit ? () => _reschedule(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: CalendarEventSheetUiCopy.actionEdit,
            onPressed: canEdit ? () => _editSourceEvent(context) : null,
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: CalendarEventSheetUiCopy.actionOpenDetail,
            onPressed: widget.event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: CalendarEventSheetUiCopy.actionDelete,
            onPressed: canEdit ? () => _delete(context) : null,
            tonal: true,
          ),
        ];
      case CalendarEventType.diary:
        return [
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: CalendarEventSheetUiCopy.actionEdit,
            onPressed: canEdit ? () => _editSourceEvent(context) : null,
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: CalendarEventSheetUiCopy.actionOpenDetail,
            onPressed: widget.event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: CalendarEventSheetUiCopy.actionDelete,
            onPressed: canEdit ? () => _delete(context) : null,
            tonal: true,
          ),
        ];
      case CalendarEventType.timeEntry:
        if (widget.event.sourceId == null) return const <Widget>[];
        return [
          _actionButton(
            context,
            icon: Icons.event_repeat,
            label: CalendarEventSheetUiCopy.actionReschedule,
            onPressed: canEdit ? () => _reschedule(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.schedule_outlined,
            label: CalendarEventSheetUiCopy.actionAdjustStart,
            onPressed: canEdit ? () => _adjustTimeEntryStart(context) : null,
          ),
          _actionButton(
            context,
            icon: Icons.timer_outlined,
            label: CalendarEventSheetUiCopy.actionAdjustDuration,
            onPressed: canEdit ? () => _adjustTimeEntryDuration(context) : null,
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: CalendarEventSheetUiCopy.actionOpenDetail,
            onPressed: widget.event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: CalendarEventSheetUiCopy.actionDelete,
            onPressed: canEdit ? () => _delete(context) : null,
            tonal: true,
          ),
        ];
    }
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    VoidCallback? onPressed,
    bool tonal = false,
  }) {
    final compactStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      textStyle: WidgetStatePropertyAll(appSecondaryControlTextStyle(context)),
    );
    if (tonal) {
      return FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: compactStyle,
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: compactStyle,
    );
  }

  // ---- CalendarActionRouter: dispatches actions back to source providers ----

  Future<void> _completeTodo(BuildContext context) async {
    final sourceId = widget.event.sourceId;
    if (sourceId == null) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }
    final todo = context
        .read<TodoProvider>()
        .todos
        .where((t) => t.id == sourceId)
        .firstOrNull;
    if (todo == null) return;
    try {
      await completeTodoWithOptionalTimeRecord(context, todo);
      if (mounted &&
          context.mounted &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          )) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted &&
          context.mounted &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          )) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${CalendarEventSheetUiCopy.actionCompleteFailed}: $e',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _checkInHabit(BuildContext context) async {
    final sourceId = widget.event.sourceId;
    if (sourceId == null) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }
    try {
      await context.read<HabitProvider>().incrementHabitForDate(
        sourceId,
        widget.event.date,
      );
      if (mounted &&
          context.mounted &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          )) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted &&
          context.mounted &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          )) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${CalendarEventSheetUiCopy.actionCheckInFailed}: $e',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _startFocus(BuildContext context) async {
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      _originAccountGeneration,
    )) {
      return;
    }
    final navigator = Navigator.of(context);
    final hostContext = navigator.context;
    navigator.pop();
    if (!hostContext.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        )) {
      return;
    }
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => const BrandRouteSurface(
          child: PomodoroScreen(useShellBackground: true),
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context) async {
    if (!mounted ||
        (_dateOrigin != null &&
            (!_dateOrigin!.isCurrent() || dateItemBusy || _datePicking))) {
      return;
    }

    final sourceId = widget.event.sourceId;
    if (sourceId == null) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      _originAccountGeneration,
    )) {
      return;
    }
    final navigator = Navigator.of(context);
    final navigationContext = navigator.context;
    navigator.pop();
    if (!navigationContext.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        )) {
      return;
    }
    switch (widget.event.type) {
      case CalendarEventType.todo:
        await TodayDetailRouter.open(
          navigationContext,
          TodaySectionKind.todos,
          id: sourceId,
        );
      case CalendarEventType.habit:
        await TodayDetailRouter.open(
          navigationContext,
          TodaySectionKind.habits,
          id: sourceId,
        );
      case CalendarEventType.goal:
        await TodayDetailRouter.open(
          navigationContext,
          TodaySectionKind.goals,
          id: sourceId,
        );
      case CalendarEventType.anniversary:
        await TodayDetailRouter.open(
          navigationContext,
          TodaySectionKind.anniversaries,
          id: sourceId,
        );
      case CalendarEventType.course:
        await TodayDetailRouter.open(
          navigationContext,
          TodaySectionKind.courses,
          id: sourceId,
        );
      case CalendarEventType.diary:
        await TodayDetailRouter.open(
          navigationContext,
          TodaySectionKind.diary,
          id: sourceId,
        );
      case CalendarEventType.countdown:
        if (!navigationContext.mounted ||
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              _originAccountGeneration,
            )) {
          return;
        }
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => BrandRouteSurface(
              child: CountdownScreen(initialCountdownId: sourceId),
            ),
          ),
        );
      case CalendarEventType.timeEntry:
      case CalendarEventType.pomodoro:
        if (!navigationContext.mounted ||
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              _originAccountGeneration,
            )) {
          return;
        }
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => const BrandRouteSurface(child: TimeAuditScreen()),
          ),
        );
      case CalendarEventType.event:
        break;
    }
  }

  Future<void> _rescheduleDateItem(BuildContext context) async {
    final origin = _dateOrigin!;
    final sourceId = widget.event.sourceId;
    if (sourceId == null ||
        dateItemBusy ||
        _datePicking ||
        !origin.isCurrent() ||
        !_canEditEvent(context)) {
      return;
    }
    DateTime? picked;
    setState(() => _datePicking = true);
    try {
      picked = await AppDatePicker.pickSolar(
        context,
        initialDate: widget.event.date,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        title: CalendarEventSheetUiCopy.rescheduleDateTitle,
        titleKey: 'calendar.picker.reschedule_date',
      );
    } finally {
      if (mounted) setState(() => _datePicking = false);
    }
    if (!context.mounted ||
        picked == null ||
        !origin.isCurrent() ||
        !_canEditEvent(context)) {
      return;
    }
    final targetDate = picked;
    DateItemReminderIssue? reminderIssue;
    await runDateItemMutation(
      origin: origin,
      failure: () => DateItemUiCopy.saveFailed,
      write: (operation) async {
        bool canWrite() => operation.isCurrent() && _canEditEvent(context);
        if (origin.anniversary) {
          final item = origin.anniversaries.items
              .where((a) => a.id == sourceId)
              .firstOrNull;
          if (item == null) throw StateError('Date item no longer exists');
          item.originDate = targetDate;
          await origin.anniversaries.update(item, canWrite: canWrite);
          reminderIssue = origin.anniversaries.lastReminderIssue;
        } else {
          final item = origin.countdown.items
              .where((a) => a.id == sourceId)
              .firstOrNull;
          if (item == null) throw StateError('Date item no longer exists');
          await origin.countdown.updateItem(
            item.copyWith(targetDate: targetDate),
            canWrite: canWrite,
          );
          reminderIssue = origin.countdown.lastReminderIssue;
        }
      },
      onCommitted: () {
        final messenger = ScaffoldMessenger.maybeOf(context);
        Navigator.pop(context);
        if (reminderIssue != null) {
          messenger?.showSnackBar(
            SnackBar(
              content: DateItemFeedbackText(
                () => DateItemUiCopy.savedReminderWarning,
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }

  Future<void> _reschedule(BuildContext context) async {
    if (_dateOrigin != null) {
      await _rescheduleDateItem(context);
      return;
    }
    final sourceId = widget.event.sourceId;
    if (sourceId == null && widget.event.type != CalendarEventType.event) {
      return;
    }
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: widget.event.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      title: CalendarEventSheetUiCopy.rescheduleDateTitle,
      titleKey: 'calendar.picker.reschedule_date',
    );
    if (picked == null ||
        !context.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }

    switch (widget.event.type) {
      case CalendarEventType.todo:
        final provider = context.read<TodoProvider>();
        final todo = provider.todos.where((t) => t.id == sourceId).firstOrNull;
        if (todo != null) {
          final saved = await _saveTodoFromCalendarSheet(
            context,
            provider,
            todo,
            todo.copyWith(
              date: picked,
              dueDate: todo.dueDate == null
                  ? null
                  : _sameTime(picked, todo.dueDate!),
            ),
          );
          if (!saved) return;
        }
      case CalendarEventType.goal:
        final provider = context.read<GoalProvider>();
        final goal = provider.goals.where((g) => g.id == sourceId).firstOrNull;
        if (goal != null) {
          goal.targetDate = picked;
          await provider.update(goal);
        }
      case CalendarEventType.anniversary:
      case CalendarEventType.countdown:
        return;
      case CalendarEventType.timeEntry:
        final provider = context.read<TimeAuditProvider>();
        final entry = provider.entries
            .where((e) => e.id == sourceId)
            .firstOrNull;
        if (entry != null) {
          final duration = entry.endAt.difference(entry.startAt);
          final start = _sameTime(picked, entry.startAt);
          await provider.update(
            entry.copyWith(startAt: start, endAt: start.add(duration)),
          );
        }
      case CalendarEventType.event:
        final provider = context.read<CalendarProvider>();
        final original = provider.localEvents
            .where((local) => local.id == widget.event.id)
            .firstOrNull;
        if (original != null) {
          final duration = (original.endDate ?? original.date).difference(
            original.date,
          );
          final start = _sameTime(picked, original.date);
          await provider.updateLocalEvent(
            original.copyWith(date: start, endDate: start.add(duration)),
          );
        }
      default:
        break;
    }
    if (context.mounted &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        )) {
      Navigator.pop(context);
    }
  }

  Future<void> _adjustTimeEntryDuration(BuildContext context) async {
    final sourceId = widget.event.sourceId;
    if (sourceId == null) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }
    final provider = context.read<TimeAuditProvider>();
    final entry = provider.entries.where((e) => e.id == sourceId).firstOrNull;
    if (entry == null) return;

    final minutes = await showAppModalSheet<int>(
      context: context,
      builder: (_) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (_, _, _) => AppPickerSheet<int>(
          title: CalendarEventSheetUiCopy.adjustDurationTitle,
          subtitle: CalendarEventSheetUiCopy.adjustDurationSubtitle,
          selectedValue: (entry.durationSeconds / 60).round(),
          options: [
            AppPickerOption(
              value: 15,
              title: CalendarEventSheetUiCopy.durationOption(15),
            ),
            AppPickerOption(
              value: 30,
              title: CalendarEventSheetUiCopy.durationOption(30),
            ),
            AppPickerOption(
              value: 45,
              title: CalendarEventSheetUiCopy.durationOption(45),
            ),
            AppPickerOption(
              value: 60,
              title: CalendarEventSheetUiCopy.durationOption(60),
            ),
            AppPickerOption(
              value: 90,
              title: CalendarEventSheetUiCopy.durationOption(90),
            ),
            AppPickerOption(
              value: 120,
              title: CalendarEventSheetUiCopy.durationOption(120),
            ),
          ],
        ),
      ),
    );
    if (minutes == null ||
        !context.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }
    await provider.update(
      entry.copyWith(endAt: entry.startAt.add(Duration(minutes: minutes))),
    );
    if (context.mounted &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        )) {
      Navigator.pop(context);
    }
  }

  Future<void> _adjustTimeEntryStart(BuildContext context) async {
    final sourceId = widget.event.sourceId;
    if (sourceId == null) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }
    final provider = context.read<TimeAuditProvider>();
    final entry = provider.entries.where((e) => e.id == sourceId).firstOrNull;
    if (entry == null) return;

    final picked = await AppTimePicker.show(
      context,
      initialTime: TimeOfDay.fromDateTime(entry.startAt),
      title: CalendarEventSheetUiCopy.adjustStartTimeTitle,
      subtitle: CalendarEventSheetUiCopy.adjustStartTimeSubtitle,
      titleKey: 'calendar.picker.adjust_start_time',
      subtitleKey: 'calendar.picker.adjust_start_time_subtitle',
    );
    if (picked == null ||
        !context.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }

    final startAt = DateTime(
      entry.startAt.year,
      entry.startAt.month,
      entry.startAt.day,
      picked.hour,
      picked.minute,
    );
    final duration = entry.endAt.difference(entry.startAt);
    await provider.update(
      entry.copyWith(startAt: startAt, endAt: startAt.add(duration)),
    );
    if (context.mounted &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        )) {
      Navigator.pop(context);
    }
  }

  Future<void> _adjustTodoTime(BuildContext context) async {
    final sourceId = widget.event.sourceId;
    if (sourceId == null) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }
    final provider = context.read<TodoProvider>();
    final todo = provider.todos.where((t) => t.id == sourceId).firstOrNull;
    if (todo == null) return;

    final base = todo.dueDate ?? todo.date;
    final picked = await AppTimePicker.show(
      context,
      initialTime: TimeOfDay.fromDateTime(base),
      title: CalendarEventSheetUiCopy.adjustDueTimeTitle,
      subtitle: CalendarEventSheetUiCopy.adjustDueTimeSubtitle,
      titleKey: 'calendar.picker.adjust_due_time',
      subtitleKey: 'calendar.picker.adjust_due_time_subtitle',
    );
    if (picked == null ||
        !context.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }

    final dueDate = DateTime(
      todo.date.year,
      todo.date.month,
      todo.date.day,
      picked.hour,
      picked.minute,
    );
    final saved = await _saveTodoFromCalendarSheet(
      context,
      provider,
      todo,
      todo.copyWith(dueDate: dueDate),
    );
    if (!saved) return;
    if (context.mounted &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        )) {
      Navigator.pop(context);
    }
  }

  Future<bool> _saveTodoFromCalendarSheet(
    BuildContext context,
    TodoProvider provider,
    TodoItem current,
    TodoItem next,
  ) async {
    final waitForReminderSync = _todoNeedsReminderSync(current);
    try {
      final saveResult = await provider.updateTodoWithResult(
        current.id,
        next,
        waitForReminderSync: waitForReminderSync,
      );
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          )) {
        return false;
      }
      if (!saveResult.saved) {
        _showTodoSaveIssue(context, CalendarEventSheetUiCopy.todoSavingBusy);
        return false;
      }
      final reminderIssue = waitForReminderSync
          ? saveResult.reminderSync?.issue
          : null;
      if (reminderIssue != null) {
        _showTodoSaveIssue(
          context,
          CalendarEventSheetUiCopy.todoReminderSyncIssue(reminderIssue),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          )) {
        _showTodoSaveIssue(context, CalendarEventSheetUiCopy.todoSaveFailed(e));
      }
      return false;
    }
  }

  bool _todoNeedsReminderSync(TodoItem todo) {
    return todo.hasReminder ||
        todo.reminder.enabled ||
        todo.reminderPlan.enabled;
  }

  void _showTodoSaveIssue(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _editLocalEvent(BuildContext context) async {
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }
    final navigator = Navigator.of(context);
    final navigationContext = navigator.context;
    navigator.pop();
    if (!navigationContext.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        )) {
      return;
    }
    await showLocalCalendarEventEditor(navigationContext, event: widget.event);
  }

  Future<void> _editSourceEvent(BuildContext context) async {
    if (!mounted ||
        (_dateOrigin != null &&
            (!_dateOrigin!.isCurrent() || dateItemBusy || _datePicking))) {
      return;
    }

    final sourceId = widget.event.sourceId;
    if (sourceId == null) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }
    final navigator = Navigator.of(context);
    final navigationContext = navigator.context;
    switch (widget.event.type) {
      case CalendarEventType.anniversary:
        final item = context
            .read<AnniversaryProvider>()
            .items
            .where((a) => a.id == sourceId)
            .firstOrNull;
        if (item == null) return;
        navigator.pop();
        if (!navigationContext.mounted ||
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              _originAccountGeneration,
            )) {
          return;
        }
        await showAnniversaryEditor(navigationContext, item: item);
      case CalendarEventType.countdown:
        final item = context
            .read<CountdownProvider>()
            .items
            .where((c) => c.id == sourceId)
            .firstOrNull;
        if (item == null) return;
        navigator.pop();
        if (!navigationContext.mounted ||
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              _originAccountGeneration,
            )) {
          return;
        }
        await showCountdownEditor(navigationContext, item: item);
      case CalendarEventType.course:
        final item = context
            .read<CourseProvider>()
            .courses
            .where((c) => c.id == sourceId)
            .firstOrNull;
        if (item == null) return;
        navigator.pop();
        if (!navigationContext.mounted ||
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              _originAccountGeneration,
            )) {
          return;
        }
        await showCourseEditor(navigationContext, course: item);
      case CalendarEventType.diary:
        final item = context
            .read<DiaryProvider>()
            .entries
            .where((d) => d.id == sourceId)
            .firstOrNull;
        if (item == null) return;
        navigator.pop();
        if (!navigationContext.mounted ||
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              _originAccountGeneration,
            )) {
          return;
        }
        await showDiaryEditor(navigationContext, entry: item);
      case CalendarEventType.habit:
        final item = context
            .read<HabitProvider>()
            .habits
            .where((h) => h.id == sourceId)
            .firstOrNull;
        if (item == null) return;
        navigator.pop();
        if (!navigationContext.mounted ||
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              _originAccountGeneration,
            )) {
          return;
        }
        await showHabitEditor(navigationContext, item);
      case CalendarEventType.pomodoro:
        final item = context
            .read<PomodoroProvider>()
            .sessions
            .where((s) => s.id == sourceId)
            .firstOrNull;
        if (item == null) return;
        navigator.pop();
        if (!navigationContext.mounted ||
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              _originAccountGeneration,
            )) {
          return;
        }
        await showPomodoroSessionEditor(navigationContext, item);
      default:
        break;
    }
  }

  Future<void> _delete(BuildContext context) async {
    final origin = _dateOrigin;
    if (origin != null) {
      final id = widget.event.sourceId;
      if (!mounted ||
          !origin.isCurrent() ||
          id == null ||
          !_canEditEvent(context) ||
          _datePicking) {
        return;
      }
      await runDateItemMutation(
        origin: origin,
        failure: () => DateItemUiCopy.deleteFailed,
        write: (operation) {
          bool canWrite() => operation.isCurrent() && _canEditEvent(context);
          return origin.anniversary
              ? origin.anniversaries.delete(id, canWrite: canWrite)
              : origin.countdown.deleteItem(id, canWrite: canWrite);
        },
        onCommitted: () => Navigator.pop(context),
      );
      return;
    }
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        !_canEditEvent(context)) {
      return;
    }
    try {
      if (widget.event.type == CalendarEventType.event) {
        await context.read<CalendarProvider>().deleteLocalEvent(
          widget.event.id,
        );
        if (context.mounted &&
            AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              _originAccountGeneration,
            )) {
          Navigator.pop(context);
        }
        return;
      }
      final sourceId = widget.event.sourceId;
      if (sourceId == null) return;
      switch (widget.event.type) {
        case CalendarEventType.todo:
          await context.read<TodoProvider>().deleteTodo(sourceId);
        case CalendarEventType.habit:
          await context.read<HabitProvider>().deleteHabit(sourceId);
        case CalendarEventType.goal:
          await context.read<GoalProvider>().delete(sourceId);
        case CalendarEventType.anniversary:
          await context.read<AnniversaryProvider>().delete(sourceId);
        case CalendarEventType.countdown:
          await context.read<CountdownProvider>().deleteItem(sourceId);
        case CalendarEventType.course:
          await context.read<CourseProvider>().delete(sourceId);
        case CalendarEventType.diary:
          await context.read<DiaryProvider>().delete(sourceId);
        case CalendarEventType.timeEntry:
          await context.read<TimeAuditProvider>().delete(sourceId);
        case CalendarEventType.pomodoro:
          await context.read<PomodoroProvider>().deleteSession(sourceId);
        default:
          break;
      }
      if (context.mounted &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          )) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          )) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${CalendarEventSheetUiCopy.deleteFailed}: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  DateTime _sameTime(DateTime date, DateTime time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _timeText(CalendarEvent event) {
    final start = event.time;
    if (start == null) return _allDayText(event);
    final startText = I18nDateFormat.timeOfDay(
      hour: start.hour,
      minute: start.minute,
    );
    final dateText = I18nDateFormat.monthDay(event.date);
    if (event.endDate == null) {
      return '$dateText $startText';
    }
    final end = TimeOfDay.fromDateTime(event.endDate!);
    final endText = I18nDateFormat.timeOfDay(
      hour: end.hour,
      minute: end.minute,
    );
    final endDateText = I18nDateFormat.monthDay(event.endDate!);
    if (_dateOnly(event.date) == _dateOnly(event.endDate!)) {
      return '$dateText $startText-$endText';
    }
    return '$dateText $startText - $endDateText $endText';
  }

  IconData _icon(CalendarEventType t) {
    return switch (t) {
      CalendarEventType.event => Icons.event_note_outlined,
      CalendarEventType.todo => Icons.check_circle_outline,
      CalendarEventType.habit => Icons.repeat,
      CalendarEventType.pomodoro => Icons.timer,
      CalendarEventType.anniversary => Icons.celebration_outlined,
      CalendarEventType.course => Icons.class_outlined,
      CalendarEventType.diary => Icons.book_outlined,
      CalendarEventType.countdown => Icons.hourglass_bottom,
      CalendarEventType.goal => Icons.flag_circle_outlined,
      CalendarEventType.timeEntry => Icons.timelapse_outlined,
    };
  }

  String _allDayText(CalendarEvent event) {
    final visibleEnd = _localEventInclusiveEndDate(event);
    if (visibleEnd == null || _dateOnly(event.date) == visibleEnd) {
      return CalendarEventSheetUiCopy.allDaySingle(event.date);
    }
    return CalendarEventSheetUiCopy.allDayRange(event.date, visibleEnd);
  }
}

class _LocalEventTimeRange {
  final DateTime start;
  final DateTime end;

  const _LocalEventTimeRange({required this.start, required this.end});
}

class _DatePickTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final DateTime value;
  final VoidCallback onTap;

  const _DatePickTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(AppDateFormat.date(context, value)),
      onTap: onTap,
    );
  }
}

class _TimePickTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final TimeOfDay value;
  final VoidCallback onTap;

  const _TimePickTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(AppTimePicker.format(value)),
      onTap: onTap,
    );
  }
}

class _ColorChoice extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 0.6,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.28),
                    blurRadius: 0,
                    spreadRadius: 1.5,
                  ),
                ]
              : null,
        ),
        child: selected
            ? Icon(
                Icons.check,
                color: color.computeLuminance() > 0.55
                    ? Colors.black
                    : Colors.white,
                size: 18,
              )
            : null,
      ),
    );
  }
}

const _localEventColors = <Color>[
  Color(0xFF5B6EE1),
  Color(0xFF26A69A),
  DesignTokens.defaultWarning,
  DesignTokens.defaultError,
  Color(0xFF7E57C2),
  DesignTokens.defaultTextMuted,
];

_LocalEventTimeRange _normalizeLocalEventTime({
  required DateTime startDate,
  required DateTime endDate,
  required bool allDay,
  required TimeOfDay startTime,
  required TimeOfDay endTime,
}) {
  if (allDay) {
    // Preserve local midnight across DST transitions while satisfying
    // inclusive-end calendar semantics (legacy: endDate.add(const Duration(days: 1))).
    return _LocalEventTimeRange(
      start: startDate,
      end: DateTime(endDate.year, endDate.month, endDate.day + 1),
    );
  }
  final start = DateTime(
    startDate.year,
    startDate.month,
    startDate.day,
    startTime.hour,
    startTime.minute,
  );
  var end = DateTime(
    endDate.year,
    endDate.month,
    endDate.day,
    endTime.hour,
    endTime.minute,
  );
  if (!end.isAfter(start)) {
    end = start.add(const Duration(minutes: 30));
  }
  return _LocalEventTimeRange(start: start, end: end);
}

DateTime? _localEventInclusiveEndDate(CalendarEvent? event) {
  final endDate = event?.endDate;
  if (event == null || endDate == null) return null;
  if (event.time != null) return _dateOnly(endDate);
  final end = _dateOnly(endDate);
  if (end.isAfter(_dateOnly(event.date))) {
    return DateTime(end.year, end.month, end.day - 1);
  }
  return end;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
