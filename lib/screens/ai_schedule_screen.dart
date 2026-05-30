import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n_date_format.dart';
import '../models/calendar_event.dart';
import '../models/goal.dart' show ReminderKind;
import '../providers/calendar_provider.dart';
import '../providers/notification_service.dart';
import '../providers/todo_provider.dart';
import '../services/local_notifications.dart';
import '../services/notification_permission_exception.dart';
import '../services/ai_service.dart';
import '../services/reminder_scheduler.dart';
import '../widgets/surface_components.dart';

class AiScheduleScreen extends StatefulWidget {
  final String initialText;
  final DateTime? initialDate;

  const AiScheduleScreen({super.key, this.initialText = '', this.initialDate});

  @override
  State<AiScheduleScreen> createState() => _AiScheduleScreenState();
}

class _AiScheduleScreenState extends State<AiScheduleScreen> {
  late final TextEditingController _inputCtrl;
  AiScheduleDraft? _draft;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _inputCtrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _recognize() async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _error = '请输入要创建的日程或待办内容');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _draft = null;
    });
    try {
      final draft = await context.read<AiService>().createScheduleDraft(
        input,
        now: widget.initialDate,
      );
      if (!mounted) return;
      setState(() => _draft = draft);
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '创建草稿失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    if (_saving) return;
    final draft = _draft;
    if (draft == null) return;
    final calendarProvider = context.read<CalendarProvider>();
    final todoProvider = context.read<TodoProvider>();
    final notificationService = context.read<NotificationService>();
    setState(() => _saving = true);
    String? reminderStatus;
    var created = false;
    try {
      if (draft.isCalendar) {
        final event = _toCalendarEvent(draft);
        if (draft.reminderEnabled) {
          final ready = await notificationService.ensureReadyForReminder(
            scheduledTime: draft.startAt,
            issueTitle: 'AI 日程提醒注册失败',
            relatedId: event.id,
          );
          if (!mounted) return;
          if (!ready) {
            final issue = notificationService.lastScheduleIssue;
            setState(() {
              _saving = false;
              _error = issue == null
                  ? '提醒未注册，请检查通知权限和日程时间。'
                  : '${issue.title}：${issue.message}';
            });
            return;
          }
        }
        await calendarProvider.addLocalEvent(event);
        if (draft.reminderEnabled) {
          try {
            await notificationService.scheduleCalendarReminder(
              calendarEventId: event.id,
              title: '日程提醒',
              body: draft.title,
              when: draft.startAt,
              payload: 'duoyi://calendar',
            );
            reminderStatus = '提醒已注册到系统通知';
          } on NotificationPermissionDeniedException catch (e) {
            reminderStatus = e.message;
          } catch (e) {
            reminderStatus = '提醒注册失败：$e';
          }
        }
      } else {
        final todo = draft.toTodo();
        if (draft.reminderEnabled) {
          final preflight = preflightTodoReminderPlan(todo);
          final blockingIssue = preflight.blockingIssue;
          if (blockingIssue != null) {
            if (!mounted) return;
            setState(() {
              _saving = false;
              _error = '${blockingIssue.title}：${blockingIssue.message}';
            });
            return;
          }
          final usesPush = preflight.kinds.contains(ReminderKind.push);
          final usesPopup = preflight.kinds.contains(ReminderKind.popup);
          final usesAlarm = preflight.kinds.contains(ReminderKind.alarm);
          if (usesPush || usesPopup) {
            final ready = await notificationService.ensureReadyForReminder(
              scheduledTime: preflight.firstScheduledTime ?? draft.startAt,
              issueTitle: 'AI 待办提醒注册失败',
              relatedId: todo.id,
            );
            if (!mounted) return;
            if (!ready) {
              final issue = notificationService.lastScheduleIssue;
              setState(() {
                _saving = false;
                _error = issue == null
                    ? '提醒未注册，请检查通知权限和待办时间。'
                    : '${issue.title}：${issue.message}';
              });
              return;
            }
          }
          final usesAlarmOnly = usesAlarm && !usesPush && !usesPopup;
          if (usesAlarmOnly &&
              !await LocalNotifications.instance.ensurePermission()) {
            if (!mounted) return;
            setState(() {
              _saving = false;
              _error = 'AI 待办提醒注册失败：系统通知权限未开启，闹钟提醒未注册。请开启通知权限后重新保存提醒。';
            });
            return;
          }
        }
        await todoProvider.addTodo(todo);
        if (draft.reminderEnabled) {
          final issue = notificationService.lastScheduleIssue;
          reminderStatus = issue == null
              ? '待办提醒已提交系统注册'
              : '${issue.title}：${issue.message}';
        }
      }
      if (!mounted) return;
      created = true;
      setState(() => _saving = false);
      await showDialog<void>(
        context: context,
        builder: (_) => AppDialog(
          icon: Icon(
            draft.isCalendar
                ? Icons.event_available_outlined
                : Icons.check_circle_outline,
          ),
          title: Text('${draft.isCalendar ? '日程' : '待办'}已创建'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${draft.isCalendar ? '日程' : '待办'}：${draft.title}',
                style: const TextStyle(height: 1.45),
              ),
              const SizedBox(height: 6),
              Text(
                draft.isCalendar
                    ? '开始时间：${I18nDateFormat.fullDateTime(draft.startAt)}'
                    : '计划时间：${I18nDateFormat.fullDateTime(draft.startAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (reminderStatus != null) ...[
                const SizedBox(height: 8),
                Text(
                  reminderStatus,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '保存失败：$e');
    } finally {
      if (mounted && !created) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final aiEnabled = context.watch<AiService>().enabled;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('AI 创建日程'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (!aiEnabled) ...[
              AppInfoBanner(
                icon: Icons.offline_bolt_outlined,
                color: cs.tertiary,
                title: 'AI 未启用',
                message: '将使用本地时间解析生成草稿，仍可确认创建日程或待办。',
              ),
              const SizedBox(height: 12),
            ],
            AppSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSectionHeader(
                    title: '输入安排',
                    subtitle: '例如：明天下午 3 点和产品开会，提前提醒我',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inputCtrl,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: '输入自然语言安排、待办或提醒',
                      prefixIcon: Icon(Icons.auto_awesome_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _recognize,
                          icon: _loading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.manage_search_outlined),
                          label: Text(_loading ? '识别中' : '识别并生成确认信息'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              AppInfoBanner(
                icon: Icons.error_outline,
                color: cs.error,
                title: 'AI 创建失败',
                message: _error!,
              ),
            ],
            if (_draft != null) ...[
              const SizedBox(height: 12),
              if (_draft!.warning != null) ...[
                AppInfoBanner(
                  icon: Icons.warning_amber_outlined,
                  color: cs.tertiary,
                  title: _draft!.source == AiScheduleSource.localParser
                      ? 'AI 识别未完成'
                      : 'AI 识别结果不完整',
                  message: '${_draft!.warning!} 请核对下方本地草稿后再确认创建。',
                ),
                const SizedBox(height: 12),
              ],
              AppInfoBanner(
                icon: Icons.fact_check_outlined,
                color: cs.primary,
                title: '已生成确认草稿',
                message: _draft!.source == AiScheduleSource.ai
                    ? 'AI 已生成结构化结果，请核对类型、标题、时间和提醒设置。'
                    : '当前不是完整 AI 识别结果，请确认本地兜底草稿无误后再写入。',
              ),
              const SizedBox(height: 12),
              _AiScheduleDraftCard(draft: _draft!),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _create,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_saving ? '保存中' : '确认创建'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

CalendarEvent _toCalendarEvent(AiScheduleDraft draft) {
  final id = 'ai_${DateTime.now().microsecondsSinceEpoch}';
  return CalendarEvent(
    id: id,
    sourceId: id,
    title: draft.title,
    date: draft.startAt,
    endDate: draft.endAt,
    type: CalendarEventType.event,
    color: const Color(0xFF5B6EE1),
    subtitle: draft.allDay ? 'AI 创建 · 全天' : 'AI 创建',
    note: draft.notes,
  );
}

class _AiScheduleDraftCard extends StatelessWidget {
  final AiScheduleDraft draft;

  const _AiScheduleDraftCard({required this.draft});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final endAt = draft.endAt;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: '确认创建内容',
            subtitle: _sourceLabel(draft.source),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          _DraftRow(
            icon: draft.isCalendar
                ? Icons.event_available_outlined
                : Icons.check_circle_outline,
            label: '类型',
            value: draft.isCalendar ? '日程' : '待办',
          ),
          _DraftRow(
            icon: Icons.title_outlined,
            label: '标题',
            value: draft.title,
          ),
          _DraftRow(
            icon: Icons.schedule,
            label: '开始',
            value: I18nDateFormat.fullDateTime(draft.startAt),
          ),
          if (endAt != null && draft.isCalendar)
            _DraftRow(
              icon: Icons.timelapse_outlined,
              label: '结束',
              value: I18nDateFormat.fullDateTime(endAt),
            ),
          _DraftRow(
            icon: Icons.notifications_active_outlined,
            label: '提醒',
            value: draft.reminderEnabled ? '已开启系统推送提醒' : '未设置提醒',
          ),
          if (draft.notes.isNotEmpty)
            _DraftRow(
              icon: Icons.notes_outlined,
              label: '备注',
              value: draft.notes,
            ),
          if (draft.subtasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '子任务',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 4),
            for (final item in draft.subtasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
          ],
          if (draft.warning != null) ...[
            const SizedBox(height: 10),
            Text(
              draft.warning!,
              style: TextStyle(fontSize: 12, color: cs.tertiary, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }

  String _sourceLabel(AiScheduleSource source) => switch (source) {
    AiScheduleSource.ai => 'AI 已识别输入内容，请确认无误后创建',
    AiScheduleSource.aiWithLocalFallback => 'AI 返回不完整，已用本地解析补全',
    AiScheduleSource.localParser => '当前使用本地解析结果，请确认时间和类型',
  };
}

class _DraftRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DraftRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.62),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(height: 1.35))),
        ],
      ),
    );
  }
}
