import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/anniversary_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/note_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/user_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/achievement_provider.dart';
import '../providers/share_provider.dart';
import '../services/backup_service.dart';
import '../services/ics_exporter.dart';
import '../widgets/surface_components.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String? _exported;
  String? _exportedTitle;
  bool _busy = false;

  Future<void> _exportAll() async {
    setState(() => _busy = true);
    try {
      final text = await BackupService.exportAll();
      if (!mounted) return;
      setState(() {
        _exported = text;
        _exportedTitle = '全量备份 (JSON)';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  void _showExport(String title, String text) {
    setState(() {
      _exportedTitle = title;
      _exported = text;
    });
  }

  Future<void> _copy() async {
    if (_exported == null) return;
    await Clipboard.setData(ClipboardData(text: _exported!));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  Future<void> _import({bool merge = false}) async {
    final ctrl = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(merge ? '合并导入' : '覆盖导入'),
        content: TextField(
          controller: ctrl,
          maxLines: 10,
          decoration: const InputDecoration(hintText: '把之前导出的备份 JSON 粘贴进来'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final count = await BackupService.importAll(raw, merge: merge);
      if (!mounted) return;
      await _reloadAll();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功${merge ? '合并' : '导入'} $count 项数据')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  Future<void> _wipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('清空全部数据?'),
        content: const Text('将删除本机所有待办/习惯/笔记/日记等，登录账号不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await BackupService.wipeAll();
    if (!mounted) return;
    await _reloadAll();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清空本地数据')));
  }

  Future<void> _reloadAll() async {
    await Future.wait([
      context.read<TodoProvider>().loadFromStorage(),
      context.read<HabitProvider>().loadFromStorage(),
      context.read<PomodoroProvider>().loadFromStorage(),
      context.read<NoteProvider>().loadFromStorage(),
      context.read<CountdownProvider>().loadFromStorage(),
      context.read<AnniversaryProvider>().loadFromStorage(),
      context.read<DiaryProvider>().loadFromStorage(),
      context.read<GoalProvider>().loadFromStorage(),
      context.read<CourseProvider>().loadFromStorage(),
      context.read<UserProvider>().loadFromStorage(),
      context.read<TimeAuditProvider>().loadFromStorage(),
      context.read<AchievementProvider>().loadFromStorage(),
      context.read<ShareProvider>().load(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('备份 · 恢复 · 导出')),
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
                    Icons.backup_outlined,
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
                        '备份与恢复',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w400,
                              color: cs.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '把本机所有数据打包成一段 JSON 文本，可以复制、发给自己，或者粘到另一台设备。',
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
          const SizedBox(height: 10),
          AppSettingsSection(
            title: '全量备份 / 恢复',
            subtitle: 'JSON 文本可跨设备搬运',
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _exportAll,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('生成 JSON'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _import(merge: true),
                      icon: const Icon(Icons.merge, size: 18),
                      label: const Text('合并'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _import(merge: false),
                      icon: const Icon(Icons.upload, size: 18),
                      label: const Text('覆盖'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppSettingsSection(
            title: '单模块导出',
            subtitle: 'CSV / Markdown 格式',
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip('待办 · CSV', () {
                    final todos = context.read<TodoProvider>().todos;
                    _showExport('待办 CSV', ModuleExporter.todosCsv(todos));
                  }),
                  _chip('待办 · Markdown', () {
                    final todos = context.read<TodoProvider>().todos;
                    _showExport(
                      '待办 Markdown',
                      ModuleExporter.todosMarkdown(todos),
                    );
                  }),
                  _chip('习惯 · CSV', () {
                    final hs = context.read<HabitProvider>().habits;
                    _showExport('习惯 CSV', ModuleExporter.habitsCsv(hs));
                  }),
                  _chip('笔记 · Markdown', () {
                    final ns = context.read<NoteProvider>().notes;
                    _showExport(
                      '笔记 Markdown',
                      ModuleExporter.notesMarkdown(ns),
                    );
                  }),
                  _chip('日记 · Markdown', () {
                    final ds = context.read<DiaryProvider>().entries;
                    _showExport(
                      '日记 Markdown',
                      ModuleExporter.diaryMarkdown(ds),
                    );
                  }),
                  _chip('纪念日 · Markdown', () {
                    final list = context.read<AnniversaryProvider>().items;
                    _showExport(
                      '纪念日 Markdown',
                      ModuleExporter.anniversariesMarkdown(list),
                    );
                  }),
                  _chip('目标 · Markdown', () {
                    final list = context.read<GoalProvider>().goals;
                    _showExport(
                      '目标 Markdown',
                      ModuleExporter.goalsMarkdown(list),
                    );
                  }),
                ],
              ),
            ],
          ),
          if (_exported != null) ...[
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
                          _exportedTitle ?? '导出内容',
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    height: 200,
                    width: double.infinity,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _exported!,
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
          const SizedBox(height: 12),
          AppSettingsSection(
            title: '危险操作',
            subtitle: '清空本机数据会删除本地内容',
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _wipe,
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text(
                  '清空本机数据',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade300),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) {
    return ActionChip(
      avatar: const Icon(Icons.download, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }
}
