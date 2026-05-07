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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导出为日历 (.ics)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '生成一份 iCalendar 文件，可粘贴到系统日历 / Google Calendar / Outlook 订阅。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _includeAnniversaries,
            title: const Text('包含纪念日 & 生日 (YEARLY 循环)'),
            onChanged: (v) => setState(() => _includeAnniversaries = v),
          ),
          SwitchListTile(
            value: _includeCalendar,
            title: const Text('包含其他日程(待办/习惯/课程/日记/目标)'),
            onChanged: (v) => setState(() => _includeCalendar = v),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.event_note_outlined),
            label: const Text('生成 .ics'),
          ),
          if (_ics != null) ...[
            const SizedBox(height: 16),
            Container(
              height: 220,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _ics!,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _ics!));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制 .ics 内容')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('复制到剪贴板'),
            ),
          ],
        ],
      ),
    );
  }
}
