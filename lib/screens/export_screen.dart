import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/anniversary_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/todo_provider.dart';
import '../services/ics_exporter.dart';
import '../widgets/surface_components.dart';

/// iCalendar 导出：生成 .ics 文本供复制或订阅。
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _includeAnniversaries = true;
  bool _includeCalendar = true;
  String? _ics;

  void _generate() {
    final ann = context.read<AnniversaryProvider>();
    final cal = context.read<CalendarProvider>();

    // 先刷新一次日历索引
    cal.rebuild(
      context.read<TodoProvider>().todos,
      context.read<HabitProvider>().habits,
      context.read<PomodoroProvider>().sessions,
      Theme.of(context).colorScheme,
      anniversaries: ann.items,
      courses: context.read<CourseProvider>().courses,
      courseSettings: context.read<CourseProvider>().settings,
      diaries: context.read<DiaryProvider>().entries,
      countdowns: context.read<CountdownProvider>().items,
      goals: context.read<GoalProvider>().goals,
    );

    final sb = StringBuffer();
    if (_includeAnniversaries) {
      sb.writeln(IcsExporter.fromAnniversaries(ann.items));
    }
    if (_includeCalendar) {
      sb.writeln(IcsExporter.fromEvents(cal.events));
    }
    setState(() => _ics = sb.toString());
  }

  Future<void> _copy() async {
    if (_ics == null) return;
    await Clipboard.setData(ClipboardData(text: _ics!));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制 .ics 内容')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('导出为日历 (.ics)')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          AppSurfaceCard(
            padding: const EdgeInsets.all(16),
            gradient: LinearGradient(
              colors: [cs.primary.withValues(alpha: 0.12), cs.surface],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.event_note_outlined,
                    color: cs.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '日历导出',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w400,
                              color: cs.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '生成一份 iCalendar 文件，可粘贴到系统日历、Google Calendar 或 Outlook。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.66),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSettingsSection(
            title: '导出范围',
            subtitle: '选择要包含的内容',
            children: [
              AppSwitchTile(
                icon: Icons.cake_outlined,
                color: Colors.pink,
                title: '包含纪念日与生日',
                subtitle: 'YEARLY 循环事件',
                value: _includeAnniversaries,
                onChanged: (v) => setState(() => _includeAnniversaries = v),
              ),
              AppSwitchTile(
                icon: Icons.calendar_month_outlined,
                color: Colors.blue,
                title: '包含日程总表',
                subtitle: '待办、习惯、课程、日记和目标',
                value: _includeCalendar,
                onChanged: (v) => setState(() => _includeCalendar = v),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('生成 .ics'),
                ),
              ),
            ],
          ),
          if (_ics != null) ...[
            const SizedBox(height: 12),
            AppSurfaceCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '导出内容',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: cs.onSurface,
                              ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _copy,
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text('复制'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 220,
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _ics!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
