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
import '../services/backup_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String? _exported;
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final text = await BackupService.exportAll();
      if (!mounted) return;
      setState(() {
        _exported = text;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }

  Future<void> _copy() async {
    if (_exported == null) return;
    await Clipboard.setData(ClipboardData(text: _exported!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制备份 JSON 到剪贴板')),
    );
  }

  Future<void> _import({bool merge = false}) async {
    final ctrl = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(merge ? '合并导入' : '覆盖导入'),
        content: TextField(
          controller: ctrl,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: '把之前导出的备份 JSON 粘贴进来',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('确认导入')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $e')),
      );
    }
  }

  Future<void> _wipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部数据?'),
        content: const Text('将删除本机所有待办/习惯/笔记/日记等，登录账号不会删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    await BackupService.wipeAll();
    if (!mounted) return;
    await _reloadAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空本地数据')),
    );
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
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('导出',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: cs.primary)),
          const SizedBox(height: 6),
          Text('把本机所有数据打包成一段 JSON 文本，可以复制、发给自己、粘到其它设备。',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.download_outlined),
            label: const Text('生成备份'),
          ),
          if (_exported != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              height: 160,
              child: SingleChildScrollView(
                child: SelectableText(
                  _exported!,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy),
              label: const Text('复制到剪贴板'),
            ),
          ],
          const Divider(height: 32),
          Text('导入',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: cs.primary)),
          const SizedBox(height: 6),
          Text(
            '"覆盖" 用导入的数据替换本机；"合并" 保留本机已有并追加导入。',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _import(merge: true),
                  icon: const Icon(Icons.merge),
                  label: const Text('合并'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _import(merge: false),
                  icon: const Icon(Icons.upload),
                  label: const Text('覆盖'),
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          Text('危险操作',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _wipe,
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            label: const Text('清空本机数据',
                style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.red.shade300),
            ),
          ),
        ],
      ),
    );
  }
}
