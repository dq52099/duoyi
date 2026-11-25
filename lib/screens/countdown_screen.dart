import 'dart:math' as math;
import '../core/date_item_ui_copy.dart';
import '../core/reminder_editor_ui_copy.dart';
import '../core/design_tokens.dart' show AppSurfaceStyle;
import '../services/date_item_action_origin.dart';
import '../widgets/date_item_feedback.dart';
import '../widgets/app_date_format.dart';
import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;
import 'package:flutter/material.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import 'package:provider/provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/notification_service.dart';
import '../models/countdown.dart';
import '../models/goal.dart' show ReminderKind;
import '../models/goal.dart' show normalizeUserSelectableReminderKind;
import '../services/alarm_service.dart';
import '../services/local_notifications.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

Future<void> showCountdownEditor(
  BuildContext context, {
  required CountdownItem item,
  bool showDelete = true,
}) {
  return showAppModalSheet<void>(
    context: context,
    builder: (_) => _CountdownEditSheet(item: item, showDelete: showDelete),
  );
}

ButtonStyle _countdownDangerTextButtonStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return TextButton.styleFrom(
    foregroundColor: cs.error,
    textStyle: appSecondaryControlTextStyle(context),
    minimumSize: const Size(44, 44),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
  );
}

String _formatCountdownReminderAdvance(int days) {
  if (ReminderEditorUiCopy.isEn && days > 0) {
    return ReminderEditorUiCopy.advanceDurationSummary(
      ReminderEditorUiCopy.durationLabel(days * 1440),
    );
  }
  return '${I18n.tr('countdown.reminder.before_prefix')}$days${I18n.tr('countdown.reminder.before_suffix')}';
}

class CountdownScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final String? initialCountdownId;

  const CountdownScreen({super.key, this.initialCountdownId});

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> {
  bool _openedInitialCountdown = false;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_localeChanged);
  }

  void _localeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_localeChanged);
    super.dispose();
  }

  void _showEditor(BuildContext context, {required CountdownItem item}) {
    showCountdownEditor(context, item: item);
  }

  void _showNewEditor(BuildContext context) {
    final now = DateTime.now();
    showCountdownEditor(
      context,
      showDelete: false,
      item: CountdownItem(
        id: 'countdown-${now.microsecondsSinceEpoch}',
        title: '',
        targetDate: DateTime(
          now.year,
          now.month,
          now.day,
        ).add(const Duration(days: 1)),
      ),
    );
  }

  void _openInitialCountdownIfNeeded(List<CountdownItem> items) {
    if (_openedInitialCountdown) return;
    final id = widget.initialCountdownId;
    if (id == null || id.isEmpty) return;
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _openedInitialCountdown = true;
    final origin = DateItemActionOrigin.countdown(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!origin.isCurrent()) return;
      _showEditor(context, item: items[index]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CountdownProvider>();
    final actionOrigin = DateItemActionOrigin.countdown(context);
    void add() {
      if (actionOrigin.isCurrent()) _showNewEditor(context);
    }

    final routeTitleStyle = appSecondaryRouteTitleTextStyle(context);
    final items = [...provider.items]
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        return a.daysRemaining.compareTo(b.daysRemaining);
      });
    _openInitialCountdownIfNeeded(items);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final upcoming = items.where((item) => item.daysRemaining >= 0).toList()
      ..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    final nearest = upcoming.isNotEmpty ? upcoming.first : null;
    final soonCount = upcoming.where((item) => item.daysRemaining <= 7).length;

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('countdown.title')),
        titleTextStyle: routeTitleStyle,
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('countdown_add_button'),
        heroTag: 'countdown_add_fab',
        tooltip: I18n.tr('countdown.title'),
        onPressed: add,
        icon: const Icon(Icons.add),
        label: Text(I18n.tr('action.add')),
        backgroundColor: cs.primary,
      ),
      body: AppSecondaryControlTheme(
        child: items.isEmpty
            ? EmptyState(
                icon: Icons.event,
                message: I18n.tr('countdown.empty'),
                actionLabel: I18n.tr('action.add'),
                onAction: add,
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  88 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  AppSurfaceCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.event, color: cs.primary, size: 26),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                I18n.tr('countdown.title'),
                                style: routeTitleStyle,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                nearest == null
                                    ? I18n.tr('countdown.nearest.empty')
                                    : '${I18n.tr('countdown.nearest.prefix')}${nearest.title} · '
                                          '${I18n.tr('countdown.nearest.days_prefix')}${nearest.daysRemaining} '
                                          '${I18n.tr('unit.day')}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.68,
                                      ),
                                    ),
                              ),
                              const SizedBox(height: 10),
                              _CountdownSummaryStats(
                                total: _SummaryStat(
                                  key: const ValueKey(
                                    'countdown_summary_total',
                                  ),
                                  label: I18n.tr('countdown.summary.total'),
                                  value: '${items.length}',
                                  color: cs.primary,
                                ),
                                soon: _SummaryStat(
                                  key: const ValueKey(
                                    'countdown_summary_within_7_days',
                                  ),
                                  label: I18n.tr(
                                    'countdown.summary.within_7_days',
                                  ),
                                  value: '$soonCount',
                                  color: cs.tertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppSectionHeader(
                    title: I18n.tr('countdown.list.title'),
                    subtitle: I18n.tr('countdown.list.subtitle'),
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                  ),
                  ...items.map((item) {
                    final origin = DateItemActionOrigin.countdown(context);
                    return _CountdownCard(
                      key: ValueKey((origin.identity, item.id)),
                      item: item,
                      origin: origin,
                      onTap: () {
                        if (origin.isCurrent()) {
                          _showEditor(context, item: item);
                        }
                      },
                    );
                  }),
                ],
              ),
      ),
    );

    if (!isLiquidGlass) {
      return scaffold;
    }

    final hasBrandSurface =
        DesktopEmbeddedHostScope.isHosted(context) ||
        context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
    if (hasBrandSurface) {
      return scaffold;
    }
    return Material(
      color: routeBackground,
      child: BrandBackground(child: scaffold),
    );
  }
}

class _CountdownEditSheet extends StatefulWidget {
  final CountdownItem item;
  final bool showDelete;

  const _CountdownEditSheet({required this.item, required this.showDelete});

  @override
  State<_CountdownEditSheet> createState() => _CountdownEditSheetState();
}

class _CountdownEditSheetState extends State<_CountdownEditSheet>
    with DateItemMutationState<_CountdownEditSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _categoryCtrl;
  late DateTime _targetDate;
  late bool _remind;
  late int _remindDaysBefore;
  late TimeOfDay _remindTime;
  late ReminderKind _reminderKind;
  bool get _saving => dateItemBusy;
  DateItemActionOrigin? _origin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _origin ??= DateItemActionOrigin.countdown(context);
  }

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _titleCtrl = TextEditingController(text: item.title);
    _categoryCtrl = TextEditingController(
      text: item.categoryIsDefault ? '' : item.category,
    );
    _targetDate = item.targetDate;
    _remind = item.remind;
    _remindDaysBefore = item.remindDaysBefore;
    _remindTime = TimeOfDay(hour: item.remindHour, minute: item.remindMinute);
    _reminderKind = normalizeUserSelectableReminderKind(item.reminderKind);
    if (_reminderKind == ReminderKind.off) {
      _remind = false;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  DateTime _remindAtFor(CountdownItem item) {
    return DateTime(
      item.targetDate.year,
      item.targetDate.month,
      item.targetDate.day,
      item.remindHour,
      item.remindMinute,
    ).subtract(Duration(days: item.remindDaysBefore));
  }

  Future<_ReminderPreflightResult> _checkReminderBeforeSave(
    CountdownItem item,
    DateTime remindAt,
  ) async {
    final issueTitle = I18n.tr('countdown.reminder.register_failed');
    try {
      switch (item.reminderKind) {
        case ReminderKind.push:
          final notif = context.read<NotificationService?>();
          final ready =
              await notif
                  ?.ensureReadyForReminder(
                    scheduledTime: remindAt,
                    issueTitle: issueTitle,
                    relatedId: item.id,
                  )
                  .timeout(
                    const Duration(seconds: 5),
                    onTimeout: () => false,
                  ) ??
              true;
          if (ready) return const _ReminderPreflightResult.ok();
          final issue = notif?.lastScheduleIssue;
          return _ReminderPreflightResult.disabled(
            () => issue?.copy == null
                ? I18n.tr('countdown.reminder.not_registered')
                : '${I18n.tr('countdown.reminder.not_registered_prefix')}${issue!.renderMessage()}',
          );
        case ReminderKind.popup:
          final notif = context.read<NotificationService?>();
          final ready =
              await notif
                  ?.ensureReadyForReminder(
                    scheduledTime: remindAt,
                    issueTitle: I18n.tr(
                      'countdown.reminder.popup_fallback_failed',
                    ),
                    relatedId: item.id,
                  )
                  .timeout(
                    const Duration(seconds: 5),
                    onTimeout: () => false,
                  ) ??
              await LocalNotifications.instance.ensurePermission().timeout(
                const Duration(seconds: 5),
                onTimeout: () => false,
              );
          if (!ready) {
            final issue = notif?.lastScheduleIssue;
            return _ReminderPreflightResult.disabled(
              () => issue?.copy == null
                  ? I18n.tr('countdown.reminder.popup_permission_denied')
                  : '${I18n.tr('countdown.reminder.popup_not_registered_prefix')}${issue!.renderMessage()}',
            );
          }
          return _ReminderPreflightResult.warning(
            () => I18n.tr('countdown.reminder.popup_warning'),
          );
        case ReminderKind.alarm:
          final notificationGranted = await LocalNotifications.instance
              .ensurePermission()
              .timeout(const Duration(seconds: 5), onTimeout: () => false);
          if (!notificationGranted) {
            return _ReminderPreflightResult.disabled(
              () => I18n.tr('countdown.reminder.alarm_permission_denied'),
            );
          }
          final warnings = <String>[];
          final channelIds = await AlarmService.instance
              .notificationChannelIds();
          if (channelIds != null &&
              channelIds.isNotEmpty &&
              !channelIds.contains(AlarmService.channelId)) {
            warnings.add('countdown.reminder.alarm_channel_missing');
          }
          final exactGranted = await AlarmService.instance
              .hasExactAlarmPermission();
          if (!exactGranted) {
            warnings.add('countdown.reminder.exact_alarm_missing');
          }
          final fullScreenGranted = await AlarmService.instance
              .hasFullScreenIntentPermission();
          if (!fullScreenGranted) {
            warnings.add('countdown.reminder.fullscreen_missing');
          }
          if (warnings.isEmpty) return const _ReminderPreflightResult.ok();
          return _ReminderPreflightResult.warning(
            () =>
                '${I18n.tr('countdown.reminder.saved_with_warnings_prefix')}${warnings.map(I18n.tr).join('; ')}',
          );
        case ReminderKind.email:
          return _ReminderPreflightResult.warning(
            () => I18n.tr('countdown.reminder.email_warning'),
          );
        case ReminderKind.off:
          return const _ReminderPreflightResult.ok();
      }
    } catch (_) {
      return _ReminderPreflightResult.disabled(
        () => I18n.tr('countdown.reminder.not_registered'),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final origin = _origin!;
    if (!origin.isCurrent()) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: DateItemFeedbackText(
            () => I18n.tr('countdown.validation.title_required'),
          ),
        ),
      );
      return;
    }
    final category = _categoryCtrl.text.trim();
    var next = CountdownItem(
      id: widget.item.id,
      title: title,
      targetDate: _targetDate,
      isPinned: widget.item.isPinned,
      category: category,
      remind: _remind,
      remindDaysBefore: _remindDaysBefore,
      remindHour: _remindTime.hour,
      remindMinute: _remindTime.minute,
      reminderKind: _remind ? _reminderKind : ReminderKind.off,
    );
    String Function()? reminderWarning;
    DateItemReminderIssue? syncIssue;
    await runDateItemMutation(
      origin: origin,
      failure: () => DateItemUiCopy.saveFailed,
      retry: _save,
      write: (operation) async {
        if (next.remind && !_remindAtFor(next).isAfter(DateTime.now())) {
          reminderWarning = () => I18n.tr('countdown.reminder.time_past');
          next = next.copyWith(remind: false, reminderKind: ReminderKind.off);
        }
        if (next.remind) {
          final preflight =
              await _checkReminderBeforeSave(next, _remindAtFor(next)).timeout(
                const Duration(seconds: 5),
                onTimeout: () => _ReminderPreflightResult.disabled(
                  () => I18n.tr('countdown.reminder.not_registered'),
                ),
              );
          if (!operation.isCurrent()) return;
          if (preflight.message.isNotEmpty) {
            reminderWarning = () => preflight.message;
          }
          if (preflight.disableReminder) {
            next = next.copyWith(remind: false, reminderKind: ReminderKind.off);
          }
        }
        if (!operation.isCurrent()) return;
        await origin.countdown.updateItem(next, canWrite: operation.isCurrent);
        syncIssue = origin.countdown.lastReminderIssue;
      },
      onCommitted: () {
        final messenger = ScaffoldMessenger.maybeOf(context);
        Navigator.pop(context);
        messenger?.showSnackBar(
          SnackBar(
            content: DateItemFeedbackText(
              () => syncIssue != null
                  ? DateItemUiCopy.savedReminderWarning
                  : reminderWarning?.call() ?? I18n.tr('countdown.saved'),
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      },
    );
  }

  Future<void> _delete() => runDateItemMutation(
    origin: _origin!,
    failure: () => DateItemUiCopy.deleteFailed,
    confirm: (operation) =>
        confirmDateItemDeletion(operation, widget.item.title),
    write: (operation) => _origin!.countdown.deleteItem(
      widget.item.id,
      canWrite: operation.isCurrent,
    ),
    onCommitted: () => Navigator.pop(context),
  );

  Widget _buildSegmentContent({
    required ReminderKind kind,
    required String label,
    required IconData defaultIcon,
    required bool isVertical,
    required double availableWidth,
  }) {
    final isSelected = _reminderKind == kind;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 44,
        minWidth: isVertical ? availableWidth : 0.0,
        maxWidth: isVertical ? availableWidth : double.infinity,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisSize: isVertical ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? Icons.check : defaultIcon,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  softWrap: true,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targetText = AppDateFormat.date(context, _targetDate);
    final timeText = I18nDateFormat.timeOfDay(
      hour: _remindTime.hour,
      minute: _remindTime.minute,
    );
    return AppModalSheet(
      leadingActions: widget.showDelete
          ? [
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                style: _countdownDangerTextButtonStyle(context),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(I18n.tr('action.delete')),
              ),
            ]
          : const [],
      actions: [
        TextButton(
          onPressed: () {
            if (_origin?.isCurrent() == true) Navigator.pop(context);
          },
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          key: const ValueKey('countdown_editor_save_button'),
          onPressed: _saving ? null : _save,
          child: dateItemWriting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(I18n.tr('action.save')),
        ),
      ],
      child: dateItemStatus(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader(
              title: widget.item.title.trim().isEmpty
                  ? I18n.tr('countdown.title')
                  : I18n.tr('countdown.editor.edit_title'),
              subtitle: I18n.tr('countdown.editor.subtitle'),
              padding: EdgeInsets.zero,
              wrapText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              enabled: !_saving,
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: I18n.tr('countdown.field.title'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              enabled: !_saving,
              controller: _categoryCtrl,
              decoration: InputDecoration(
                labelText: I18n.tr('countdown.field.category'),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                hintText: I18n.tr('countdown.category.default'),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _categoryCtrl,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          key: const ValueKey('countdown_category_reset'),
                          tooltip: DateItemUiCopy.resetCategory,
                          onPressed: _saving ? null : _categoryCtrl.clear,
                          icon: const Icon(Icons.clear, size: 18),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(I18n.tr('countdown.field.target_date')),
              subtitle: Text(targetText),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await AppDatePicker.pickSolar(
                  context,
                  initialDate: _targetDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  titleKey: 'countdown.field.target_date',
                );
                if (!mounted) return;
                if (picked != null) {
                  setState(() => _targetDate = picked);
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _remind,
              title: Text(I18n.tr('countdown.field.due_reminder')),
              subtitle: Text(
                _remind
                    ? '${_formatCountdownReminderAdvance(_remindDaysBefore)} · $timeText'
                    : I18n.tr('countdown.reminder.closed'),
              ),
              onChanged: (v) => setState(() => _remind = v),
            ),
            if (_remind) ...[
              KeyedSubtree(
                key: const ValueKey('countdown_reminder_kind_scroll'),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final textScaler = MediaQuery.textScalerOf(context);
                    final style = appSecondaryControlTextStyle(context);
                    final labels = [
                      I18n.tr('reminder.kind.push'),
                      I18n.tr('reminder.kind.popup'),
                      I18n.tr('reminder.kind.alarm'),
                      I18n.tr('reminder.kind.off'),
                    ];
                    var widest = 0.0;
                    for (final label in labels) {
                      final painter = TextPainter(
                        text: TextSpan(text: label, style: style),
                        textDirection: Directionality.of(context),
                        textScaler: textScaler,
                      )..layout();
                      if (painter.width > widest) widest = painter.width;
                      painter.dispose();
                    }
                    final segmentMinWidth = widest + 64.0;
                    final requiredWidth = segmentMinWidth * labels.length;
                    final availableWidth = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : MediaQuery.sizeOf(context).width - 32.0;
                    final isVertical = availableWidth < requiredWidth;

                    final selector = AppSecondaryControlTheme(
                      child: SegmentedButton<ReminderKind>(
                        direction: isVertical ? Axis.vertical : Axis.horizontal,
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.standard,
                          tapTargetSize: MaterialTapTargetSize.padded,
                          padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
                            EdgeInsets.zero,
                          ),
                        ),
                        segments: [
                          ButtonSegment<ReminderKind>(
                            value: ReminderKind.push,
                            tooltip: labels[0],
                            label: _buildSegmentContent(
                              kind: ReminderKind.push,
                              label: labels[0],
                              defaultIcon: Icons.notifications_outlined,
                              isVertical: isVertical,
                              availableWidth: availableWidth,
                            ),
                          ),
                          ButtonSegment<ReminderKind>(
                            value: ReminderKind.popup,
                            tooltip: labels[1],
                            label: _buildSegmentContent(
                              kind: ReminderKind.popup,
                              label: labels[1],
                              defaultIcon: Icons.open_in_new_outlined,
                              isVertical: isVertical,
                              availableWidth: availableWidth,
                            ),
                          ),
                          ButtonSegment<ReminderKind>(
                            value: ReminderKind.alarm,
                            tooltip: labels[2],
                            label: _buildSegmentContent(
                              kind: ReminderKind.alarm,
                              label: labels[2],
                              defaultIcon: Icons.alarm_outlined,
                              isVertical: isVertical,
                              availableWidth: availableWidth,
                            ),
                          ),
                          ButtonSegment<ReminderKind>(
                            value: ReminderKind.off,
                            tooltip: labels[3],
                            label: _buildSegmentContent(
                              kind: ReminderKind.off,
                              label: labels[3],
                              defaultIcon: Icons.notifications_off_outlined,
                              isVertical: isVertical,
                              availableWidth: availableWidth,
                            ),
                          ),
                        ],
                        selected: {_reminderKind},
                        onSelectionChanged: (selected) => setState(() {
                          _reminderKind = selected.first;
                          if (_reminderKind == ReminderKind.off) {
                            _remind = false;
                          }
                        }),
                      ),
                    );

                    if (!isVertical) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: selector,
                      );
                    }
                    return selector;
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 4),
                  Text(I18n.tr('countdown.field.remind_days')),
                  Expanded(
                    child: Slider(
                      value: _remindDaysBefore.toDouble(),
                      min: 0,
                      max: 30,
                      divisions: 30,
                      label: '$_remindDaysBefore',
                      onChanged: (v) =>
                          setState(() => _remindDaysBefore = v.toInt()),
                    ),
                  ),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(I18n.tr('countdown.field.remind_time')),
                subtitle: Text(timeText),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await AppTimePicker.show(
                    context,
                    initialTime: _remindTime,
                    title: I18n.tr('countdown.field.remind_time'),
                    minuteStep: 5,
                  );
                  if (!mounted) return;
                  if (picked != null) {
                    setState(() => _remindTime = picked);
                  }
                },
              ),
            ],
          ],
        ),
        showProgress: false,
      ),
    );
  }
}

class _ReminderPreflightResult {
  final bool disableReminder;
  final String Function()? _resolve;
  String get message => _resolve?.call() ?? '';

  const _ReminderPreflightResult._({
    required this.disableReminder,
    String Function()? resolve,
  }) : _resolve = resolve;
  const _ReminderPreflightResult.ok() : this._(disableReminder: false);
  const _ReminderPreflightResult.warning(String Function() resolve)
    : this._(disableReminder: false, resolve: resolve);
  const _ReminderPreflightResult.disabled(String Function() resolve)
    : this._(disableReminder: true, resolve: resolve);
}

class _CountdownSummaryStats extends StatelessWidget {
  final _SummaryStat total;
  final _SummaryStat soon;

  const _CountdownSummaryStats({required this.total, required this.soon});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 220.0;
        final statWidth = width >= 176 ? ((width - 14) / 2) : width;
        return Wrap(
          spacing: 14,
          runSpacing: 10,
          children: [
            SizedBox(width: statWidth, child: total),
            SizedBox(width: statWidth, child: soon),
          ],
        );
      },
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryStat({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
          child: Icon(Icons.numbers, size: 15, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: appSecondaryRouteTitleTextStyle(context).copyWith(
            fontWeight: FontWeight.normal,
            color: cs.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.62),
            fontWeight: FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _CountdownCard extends StatefulWidget {
  final CountdownItem item;
  final VoidCallback onTap;
  final DateItemActionOrigin origin;

  const _CountdownCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.origin,
  });

  @override
  State<_CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<_CountdownCard>
    with DateItemMutationState<_CountdownCard> {
  static const double _swipeActionWidth = 82;
  static const double _swipeOpenThreshold = 32;

  double _swipeOffset = 0;
  bool _dragging = false;

  bool get _swipeOpen => _swipeOffset > 0;

  @override
  void didUpdateWidget(covariant _CountdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.id != oldWidget.item.id) {
      _swipeOffset = 0;
      _dragging = false;
    }
  }

  void _closeSwipe() {
    if (!_swipeOpen || !mounted) return;
    setState(() => _swipeOffset = 0);
  }

  Future<void> _confirmDelete(BuildContext context) => runDateItemMutation(
    origin: widget.origin,
    failure: () => DateItemUiCopy.deleteFailed,
    confirm: (operation) =>
        confirmDateItemDeletion(operation, widget.item.title),
    write: (operation) => widget.origin.countdown.deleteItem(
      widget.item.id,
      canWrite: operation.isCurrent,
    ),
    onCommitted: _closeSwipe,
  );

  Future<void> _setPinned() {
    final id = widget.item.id;
    final pinned = !widget.item.isPinned;
    final origin = widget.origin;
    return runDateItemMutation(
      origin: origin,
      failure: () => DateItemUiCopy.pinFailed,
      write: (operation) =>
          origin.countdown.setPinned(id, pinned, canWrite: operation.isCurrent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final cs = Theme.of(context).colorScheme;
    final isPast = item.daysRemaining < 0;
    final absDays = item.daysRemaining.abs();
    final color = isPast
        ? cs.onSurfaceVariant
        : (item.daysRemaining <= 3 ? cs.error : cs.primary);
    final status = item.isPinned
        ? I18n.tr('countdown.status.pinned')
        : isPast
        ? I18n.tr('countdown.status.expired')
        : item.daysRemaining <= 3
        ? I18n.tr('countdown.status.soon')
        : I18n.tr('countdown.status.running');
    final titleStyle = appSecondaryRouteTitleTextStyle(context);
    final metaStyle = appSecondaryControlLabelStyle(
      context,
    ).copyWith(color: cs.onSurface.withValues(alpha: 0.62));

    final content = InkWell(
      onTap: _swipeOpen
          ? _closeSwipe
          : () {
              if (mounted && widget.origin.isCurrent()) widget.onTap();
            },
      onLongPress: _setPinned,
      borderRadius: BorderRadius.circular(14),
      child: AppSurfaceCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.12), width: 0.45),
        child: Stack(
          children: [
            Positioned.fill(
              right: null,
              child: Container(
                width: 5,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isPast ? 0.42 : 0.72),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(14),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final daysLabel = isPast
                      ? I18n.tr('countdown.days.elapsed')
                      : I18n.tr('countdown.days.remaining');
                  final textScaler = MediaQuery.textScalerOf(context);
                  final textDirection = Directionality.of(context);
                  final defaultStyle = DefaultTextStyle.of(context).style;

                  final resolvedDaysLabelStyle = defaultStyle.merge(
                    metaStyle.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.54),
                    ),
                  );
                  final resolvedNumberStyle = defaultStyle.merge(
                    TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.normal,
                      color: color,
                      height: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  );
                  final resolvedUnitStyle = defaultStyle.merge(
                    TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.normal,
                    ),
                  );

                  double daysLabelWidth = 0.0;
                  final daysLabelPainter = TextPainter(
                    text: TextSpan(text: daysLabel, style: resolvedDaysLabelStyle),
                    textDirection: textDirection,
                    textScaler: textScaler,
                  );
                  try {
                    daysLabelPainter.layout();
                    daysLabelWidth = daysLabelPainter.width;
                  } finally {
                    daysLabelPainter.dispose();
                  }

                  double numberWidth = 0.0;
                  final numberPainter = TextPainter(
                    text: TextSpan(text: '$absDays', style: resolvedNumberStyle),
                    textDirection: textDirection,
                    textScaler: textScaler,
                  );
                  try {
                    numberPainter.layout();
                    numberWidth = numberPainter.width;
                  } finally {
                    numberPainter.dispose();
                  }

                  double unitWidth = 0.0;
                  final unitPainter = TextPainter(
                    text: TextSpan(text: I18n.tr('unit.day'), style: resolvedUnitStyle),
                    textDirection: textDirection,
                    textScaler: textScaler,
                  );
                  try {
                    unitPainter.layout();
                    unitWidth = unitPainter.width;
                  } finally {
                    unitPainter.dispose();
                  }

                  const double numberUnitSpacing = 3.0;
                  final numberRowWidth = numberWidth + numberUnitSpacing + unitWidth;

                  final measuredRightWidth = math.max(
                    54.0,
                    math.max(daysLabelWidth, numberRowWidth),
                  );
                  final availableLeftWidth =
                      constraints.maxWidth - measuredRightWidth - 12;
                  final isNarrowOrSqueezed =
                      availableLeftWidth < 215 ||
                      constraints.maxWidth < 310 ||
                      textScaler.scale(1.0) >= 1.4;

                  final titleRow = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.isPinned)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 6),
                          child: Icon(
                            Icons.push_pin,
                            size: 14,
                            color: color,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          item.title,
                          style: titleStyle,
                        ),
                      ),
                    ],
                  );

                  final pills = Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _StatusPill(label: status, color: color),
                      _StatusPill(
                        label: DateItemUiCopy.countdownCategory(item),
                        color: cs.tertiary,
                      ),
                      if (item.remind)
                        _StatusPill(
                          label:
                              '${_formatCountdownReminderAdvance(item.remindDaysBefore)} '
                              '${I18nDateFormat.timeOfDay(hour: item.remindHour, minute: item.remindMinute)}',
                          color: cs.primary,
                          icon: Icons.notifications_active_outlined,
                        ),
                    ],
                  );

                  final targetDate = Text(
                    '${I18n.tr('countdown.target.prefix')}'
                    '${AppDateFormat.date(context, item.targetDate)}',
                    style: metaStyle,
                  );

                  if (isNarrowOrSqueezed) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleRow,
                        const SizedBox(height: 6),
                        pills,
                        const SizedBox(height: 6),
                        targetDate,
                        const SizedBox(height: 8),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Text(
                              daysLabel,
                              style: metaStyle.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.54),
                              ),
                            ),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.end,
                              spacing: 3,
                              children: [
                                Text(
                                  '$absDays',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.normal,
                                    color: color,
                                    height: 1.0,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                Text(
                                  I18n.tr('unit.day'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: color,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            titleRow,
                            const SizedBox(height: 6),
                            pills,
                            const SizedBox(height: 6),
                            targetDate,
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: 54,
                          maxWidth: math.max(108.0, measuredRightWidth),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              daysLabel,
                              style: metaStyle.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.54),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.end,
                              alignment: WrapAlignment.end,
                              spacing: 3,
                              children: [
                                Text(
                                  '$absDays',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.normal,
                                    color: color,
                                    height: 1.0,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                Text(
                                  I18n.tr('unit.day'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: color,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    return dateItemStatus(
      GestureDetector(
        key: ValueKey('countdown_card_${item.id}'),
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) {
          final next = (_swipeOffset - details.delta.dx).clamp(
            0.0,
            _swipeActionWidth,
          );
          if (next == _swipeOffset) return;
          setState(() => _swipeOffset = next);
        },
        onHorizontalDragEnd: (_) {
          final shouldOpen = _swipeOffset >= _swipeOpenThreshold;
          setState(() {
            _dragging = false;
            _swipeOffset = shouldOpen ? _swipeActionWidth : 0;
          });
        },
        onHorizontalDragCancel: () => setState(() {
          _dragging = false;
          _swipeOffset = _swipeOffset >= _swipeOpenThreshold
              ? _swipeActionWidth
              : 0;
        }),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (_swipeOffset > 0)
              Positioned.fill(
                child: _CountdownInlineSwipeActions(
                  margin: const EdgeInsets.only(bottom: 12),
                  onDelete: () => _confirmDelete(context),
                ),
              ),
            AnimatedContainer(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(-_swipeOffset, 0, 0),
              child: content,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownInlineSwipeActions extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  final VoidCallback onDelete;

  const _CountdownInlineSwipeActions({
    required this.margin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: _CountdownCardState._swipeActionWidth,
        height: double.infinity,
        child: _CountdownInlineSwipeButton(
          key: const ValueKey('countdown_swipe_delete_button'),
          icon: Icons.delete_outline,
          label: I18n.tr('action.delete'),
          background: cs.errorContainer.withValues(alpha: 0.86),
          foreground: cs.onErrorContainer,
          onTap: onDelete,
        ),
      ),
    );
  }
}

class _CountdownInlineSwipeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _CountdownInlineSwipeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: foreground,
      fontWeight: FontWeight.normal,
      height: 1.1,
    );
    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _StatusPill({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final maxWidth = (MediaQuery.sizeOf(context).width - 120)
        .clamp(96.0, 180.0)
        .toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.10), width: 0.45),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
