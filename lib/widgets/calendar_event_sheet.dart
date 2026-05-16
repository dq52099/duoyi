import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/calendar_event.dart';
import '../providers/anniversary_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/course_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../screens/countdown_screen.dart';
import '../screens/pomodoro_screen.dart';
import '../screens/time_audit_screen.dart';
import '../screens/today_detail_router.dart';
import '../widgets/brand_background.dart';
import 'app_date_picker.dart';
import 'surface_components.dart';

Future<void> showCalendarEventSheet(BuildContext context, CalendarEvent event) {
  return showAppModalSheet<void>(
    context: context,
    builder: (_) => CalendarEventSheet(event: event),
  );
}

class CalendarEventSheet extends StatelessWidget {
  final CalendarEvent event;

  const CalendarEventSheet({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppModalSheet(
      title: event.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: icon + type tag + time + conflict warning
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: event.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icon(event.type), color: event.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStatusBadge(
                      label: event.type.label,
                      color: event.color,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _timeText(event),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (event.hasConflict)
                Tooltip(
                  message: '同一时间段还有 ${event.conflictCount} 个事项',
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: cs.error,
                    size: 20,
                  ),
                ),
            ],
          ),
          if (event.subtitle != null && event.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              event.subtitle!,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.68),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Type-specific action buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buildActions(context),
          ),
        ],
      ),
    );
  }

  /// Build action buttons based on event type.
  List<Widget> _buildActions(BuildContext context) {
    switch (event.type) {
      case CalendarEventType.todo:
        return [
          if (!event.isCompleted)
            _actionButton(
              context,
              icon: Icons.done,
              label: '完成',
              onPressed: () => _completeTodo(context),
            ),
          _actionButton(
            context,
            icon: Icons.event_repeat,
            label: '改期',
            onPressed: () => _reschedule(context),
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: '编辑',
            onPressed: () => _openDetail(context),
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: '删除',
            onPressed: () => _delete(context),
            tonal: true,
          ),
        ];
      case CalendarEventType.habit:
        return [
          if (!event.isCompleted)
            _actionButton(
              context,
              icon: Icons.check,
              label: '打卡',
              onPressed: () => _checkInHabit(context),
            ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
        ];
      case CalendarEventType.pomodoro:
        return [
          _actionButton(
            context,
            icon: Icons.play_arrow,
            label: '开始专注',
            onPressed: () => _startFocus(context),
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
        ];
      case CalendarEventType.goal:
        return [
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
          ),
        ];
      case CalendarEventType.course:
        return [
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
          ),
        ];
      case CalendarEventType.anniversary:
        return [
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
          ),
        ];
      case CalendarEventType.countdown:
        return [
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
          ),
        ];
      case CalendarEventType.diary:
        return [
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
          ),
        ];
      case CalendarEventType.timeEntry:
        return [
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
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
    if (tonal) {
      return FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  // ---- CalendarActionRouter: dispatches actions back to source providers ----

  Future<void> _completeTodo(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    await context.read<TodoProvider>().toggleTodo(sourceId);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _checkInHabit(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    await context.read<HabitProvider>().incrementHabit(sourceId);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _startFocus(BuildContext context) async {
    Navigator.pop(context);
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BrandRouteSurface(child: PomodoroScreen()),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    Navigator.pop(context);
    if (!context.mounted) return;
    switch (event.type) {
      case CalendarEventType.todo:
        await TodayDetailRouter.open(
          context,
          TodaySectionKind.todos,
          id: sourceId,
        );
      case CalendarEventType.habit:
        await TodayDetailRouter.open(
          context,
          TodaySectionKind.habits,
          id: sourceId,
        );
      case CalendarEventType.goal:
        await TodayDetailRouter.open(
          context,
          TodaySectionKind.goals,
          id: sourceId,
        );
      case CalendarEventType.anniversary:
        await TodayDetailRouter.open(
          context,
          TodaySectionKind.anniversaries,
          id: sourceId,
        );
      case CalendarEventType.course:
        await TodayDetailRouter.open(
          context,
          TodaySectionKind.courses,
          id: sourceId,
        );
      case CalendarEventType.diary:
        await TodayDetailRouter.open(
          context,
          TodaySectionKind.diary,
          id: sourceId,
        );
      case CalendarEventType.countdown:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CountdownScreen()),
        );
      case CalendarEventType.timeEntry:
      case CalendarEventType.pomodoro:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TimeAuditScreen()),
        );
    }
  }

  Future<void> _reschedule(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: event.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      title: '调整日期',
    );
    if (picked == null || !context.mounted) return;

    switch (event.type) {
      case CalendarEventType.todo:
        final provider = context.read<TodoProvider>();
        final todo = provider.todos.where((t) => t.id == sourceId).firstOrNull;
        if (todo != null) {
          await provider.updateTodo(
            todo.id,
            todo.copyWith(
              date: picked,
              dueDate: todo.dueDate == null
                  ? null
                  : _sameTime(picked, todo.dueDate!),
            ),
          );
        }
      case CalendarEventType.goal:
        final provider = context.read<GoalProvider>();
        final goal = provider.goals.where((g) => g.id == sourceId).firstOrNull;
        if (goal != null) {
          goal.targetDate = picked;
          await provider.update(goal);
        }
      case CalendarEventType.anniversary:
        final provider = context.read<AnniversaryProvider>();
        final item = provider.items.where((a) => a.id == sourceId).firstOrNull;
        if (item != null) {
          item.originDate = picked;
          await provider.update(item);
        }
      case CalendarEventType.countdown:
        final provider = context.read<CountdownProvider>();
        final item = provider.items.where((c) => c.id == sourceId).firstOrNull;
        if (item != null) {
          provider.updateItem(item.copyWith(targetDate: picked));
        }
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
      default:
        break;
    }
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _delete(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    switch (event.type) {
      case CalendarEventType.todo:
        await context.read<TodoProvider>().deleteTodo(sourceId);
      case CalendarEventType.habit:
        await context.read<HabitProvider>().deleteHabit(sourceId);
      case CalendarEventType.goal:
        await context.read<GoalProvider>().delete(sourceId);
      case CalendarEventType.anniversary:
        await context.read<AnniversaryProvider>().delete(sourceId);
      case CalendarEventType.countdown:
        context.read<CountdownProvider>().deleteItem(sourceId);
      case CalendarEventType.course:
        await context.read<CourseProvider>().delete(sourceId);
      case CalendarEventType.timeEntry:
        await context.read<TimeAuditProvider>().delete(sourceId);
      default:
        break;
    }
    if (context.mounted) Navigator.pop(context);
  }

  DateTime _sameTime(DateTime date, DateTime time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _timeText(CalendarEvent event) {
    final start = event.time;
    if (start == null) return '${event.date.month}/${event.date.day}';
    final h = start.hour.toString().padLeft(2, '0');
    final m = start.minute.toString().padLeft(2, '0');
    if (event.endDate == null) {
      return '${event.date.month}/${event.date.day} $h:$m';
    }
    final end = TimeOfDay.fromDateTime(event.endDate!);
    final eh = end.hour.toString().padLeft(2, '0');
    final em = end.minute.toString().padLeft(2, '0');
    return '${event.date.month}/${event.date.day} $h:$m-$eh:$em';
  }

  IconData _icon(CalendarEventType t) {
    return switch (t) {
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
}
